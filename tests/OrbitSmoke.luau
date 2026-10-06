-- Smoke test for orbiting planets, run outside Studio. Loads the client's
-- StarController against a place built by Rojo, with stand-ins for the
-- services Lune doesn't have, builds one star with two planets the way the
-- server does, then steps the controller's render loop across two seconds of
-- server time and checks that the planets moved along their orbits.
--
-- Usage, from the repository root:
--   rojo build -o build.rbxl
--   lune run tests/OrbitSmoke build.rbxl

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local process = require("@lune/process")
local game = roblox.deserializePlace(fs.readFile(process.args[1] or "build.rbxl"))
local workspace = game:GetService("Workspace")

-- A stub that absorbs any use: indexing, calling, connecting.
local stub
stub = setmetatable({}, {
	__index = function()
		return stub
	end,
	__call = function()
		return stub
	end,
})
local clockNow = 1759650000
local captured = {}
local function event(name)
	return {
		Connect = function(_, fn)
			captured[name] = fn
			return stub
		end,
		Once = function()
			return stub
		end,
		Wait = function() end,
	}
end
local runService = {
	RenderStepped = event("render"),
	Heartbeat = event("heartbeat"),
	PreSimulation = event("pre"),
	BindToRenderStep = function() end,
	IsClient = function()
		return true
	end,
	IsServer = function()
		return false
	end,
}
local playerGui = roblox.Instance.new("Folder")
local localPlayer = setmetatable({ UserId = 1, Name = "Tester", DisplayName = "Tester" }, {
	__index = function(_, k)
		if k == "WaitForChild" or k == "FindFirstChild" then
			return function()
				return playerGui
			end
		end
		if k == "GetAttribute" then
			return function()
				return nil
			end
		end
		return stub
	end,
})
local players = setmetatable({ LocalPlayer = localPlayer }, {
	__index = function()
		return stub
	end,
})
local ws = setmetatable({}, {
	__index = function(_, k)
		if k == "GetServerTimeNow" then
			return function()
				return clockNow
			end
		end
		if k == "CurrentCamera" then
			return stub
		end
		local v = workspace[k]
		if type(v) == "function" then
			return function(_, ...)
				return v(workspace, ...)
			end
		end
		return v
	end,
})
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if name == "RunService" then
					return runService
				end
				if name == "Players" then
					return players
				end
				if name == "Workspace" then
					return ws
				end
				if
					name == "ReplicatedStorage"
					or name == "ServerScriptService"
					or name == "ServerStorage"
				then
					return game:GetService(name)
				end
				return stub
			end
		end
		return game[k]
	end,
})
local cache = {}
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local env = setmetatable({
		script = module,
		game = gameProxy,
		workspace = ws,
		require = requireModule,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		TweenInfo = stub,
		Random = stub,
		PhysicalProperties = roblox.PhysicalProperties,
		Rect = roblox.Rect,
		STUB_CONNECT = function()
			return stub
		end,
		task = {
			spawn = function(f, ...)
				f(...)
			end,
			delay = function() end,
			defer = function(f, ...)
				f(...)
			end,
			wait = function() end,
		},
	}, { __index = getfenv() })
	local source = string.gsub(module.Source, ":WaitForChild%(", ":FindFirstChild(")
	source =
		string.gsub(source, "[%w_%.]+:GetAttributeChangedSignal%b():Connect%(", "STUB_CONNECT(")
	source = string.gsub(source, "[%w_]+%.AncestryChanged:Connect%(", "STUB_CONNECT(")
	source = string.gsub(source, "regions%.DescendantAdded:Connect%(", "STUB_CONNECT(")
	local chunk = luau.load(source, { debugName = module:GetFullName(), environment = env })
	local result = chunk()
	cache[module] = result
	return result
end

local shared = game:GetService("ReplicatedStorage").Shared
local server = game:GetService("ServerScriptService").Server
local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
-- A region with one star and two planets, as the server builds it.
local regions = roblox.Instance.new("Folder")
regions.Name = "Regions"
regions.Parent = workspace
local StarBuilder = requireModule(server.World.StarBuilder)
local star = StarBuilder.build(
	"s1",
	{
		typeId = "BrownDwarf",
		level = 2,
		pos = { x = 0, y = 0, z = 0 },
	},
	roblox.CFrame.new(100, 0, 0),
	1,
	{
		[1] = { typeId = "Basalt", level = 1 },
		[3] = { typeId = "ObsidianLava", level = 2 },
	}
)
star.Parent = regions
local StarController = requireModule(client.Controllers.StarController)
-- init builds the panel, which needs a real GUI layout; orbits don't use it.
pcall(StarController.init)
StarController.start()

local function planetParts()
	local list = {}
	for _, child in star:GetChildren() do
		if string.sub(child.Name, 1, 10) == "GaG_Planet" then
			table.insert(list, child)
		end
	end
	return list
end

local failures = 0
local function check(ok, label)
	print(`  {if ok then "ok  " else "FAIL"}  {label}`)
	if not ok then
		failures += 1
	end
end

print("OrbitSmoke")
local render = captured.render
check(render ~= nil, "the orbit loop is connected to RenderStepped")
check(#planetParts() == 2, "both bought planets are drawn")
if render and #planetParts() == 2 then
	render(1 / 60)
	local before = {}
	for i, part in planetParts() do
		before[i] = part.CFrame.Position
	end
	clockNow += 2
	render(1 / 60)
	for i, part in planetParts() do
		local moved = (part.CFrame.Position - before[i]).Magnitude
		check(moved > 1, `{part.Name} moved {math.floor(moved)} studs in 2 s of server time`)
		local fromStar = (part.CFrame.Position - star.PrimaryPart.CFrame.Position).Magnitude
		check(fromStar > 30, `{part.Name} stays out on its orbit ({math.floor(fromStar)} studs)`)
	end
end
-- Every planet type in the catalog builds, with only known look features.
local Planets = requireModule(shared.Config.Planets)
local PlanetLook = requireModule(client.Fx.PlanetLook)
local built, unknown = 0, {}
for _, id in Planets.ORDER do
	local def = Planets.BY_ID[id]
	for _, feature in def.features do
		if not PlanetLook.knows(feature) then
			table.insert(unknown, `{id}.{feature}`)
		end
	end
	local ok, body = pcall(PlanetLook.build, def, def.radius, false)
	if ok and body then
		built += 1
		body:Destroy()
	else
		print(`  {id}: {body}`)
	end
end
check(built == #Planets.ORDER, `all {#Planets.ORDER} planet types build ({built} did)`)
check(
	#unknown == 0,
	`every look feature is drawn{if #unknown > 0
		then ` (unknown: {table.concat(unknown, ", ")})`
		else ""}`
)
print(`{failures} failed`)
if failures > 0 then
	process.exit(1)
end

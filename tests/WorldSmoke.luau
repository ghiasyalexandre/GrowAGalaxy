-- Smoke test for the server's world builders, run outside Studio.
--
-- Loads the place built by Rojo with Lune's Roblox library, runs WorldSystem.init
-- and builds one region and station, then checks part budgets and the markers
-- other systems rely on. This catches runtime errors in builder code; it does
-- not render anything or replace a playtest.
--
-- Usage, from the repository root:
--   rojo build -o build.rbxl
--   lune run tests/WorldSmoke build.rbxl

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ISS_PART_BUDGET = 400
local REGION_PART_BUDGET = 60

local placePath = process.args[1] or "build.rbxl"
local game = roblox.deserializePlace(fs.readFile(placePath))

-- Lune's CollectionService has no tag methods, so builders get a small stand-in.
local tagged: { [string]: { any } } = {}
local collectionService = {
	AddTag = function(_, instance, tag: string)
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], instance)
	end,
}
local gameProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name: string)
				if name == "CollectionService" then
					return collectionService
				end
				return game:GetService(name)
			end
		end
		return game[key]
	end,
})

local warnings = {}
local cache = {}
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local env = setmetatable({
		script = module,
		game = gameProxy,
		require = requireModule,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		warn = function(...)
			table.insert(warnings, table.concat({ ... }, " "))
		end,
	}, { __index = getfenv() })
	local chunk = luau.load(module.Source, { debugName = module:GetFullName(), environment = env })
	local result = chunk()
	cache[module] = result
	return result
end

local failures = 0
local function check(ok: boolean, label: string)
	print(`  {if ok then "ok  " else "FAIL"}  {label}`)
	if not ok then
		failures += 1
	end
end

local function countParts(root): number
	local n = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local shared = game:GetService("ReplicatedStorage").Shared
local server = game:GetService("ServerScriptService").Server

print("WorldSmoke")
local WorldSystem = requireModule(server.Systems.WorldSystem)
WorldSystem.init()

local world = game:GetService("Workspace").World
local issParts = countParts(world.ISS)
check(
	issParts > 0 and issParts <= ISS_PART_BUDGET,
	`ISS has {issParts} parts (budget {ISS_PART_BUDGET})`
)
for _, name in WorldSystem.MARKERS do
	check(WorldSystem.getMarker(name) ~= nil, `ISS marker {name} exists`)
end
local arrival = WorldSystem.getMarker("ArrivalSpawn")
check(arrival ~= nil and arrival:IsA("SpawnLocation"), "ArrivalSpawn is a SpawnLocation")
check(
	#(tagged.WarpPrompt or {}) == 3,
	"ISS has 3 warp prompts (navigation, airlock out, airlock in)"
)
check(countParts(world.Earth) > 0, "Earth backdrop built")
check(#warnings == 0, `no warnings ({table.concat(warnings, "; ")})`)

local RegionMath = requireModule(shared.Logic.RegionMath)
local RegionBuilder = requireModule(server.World.RegionBuilder)
local StationBuilder = requireModule(server.World.StationBuilder)

for slot = 1, requireModule(shared.Config).World.MAX_PLAYERS do
	local position, yaw = RegionMath.slotOrigin(slot)
	local origin = roblox.CFrame.new(position.x, position.y, position.z)
		* roblox.CFrame.Angles(0, yaw, 0)
	local size = RegionMath.regionSize(1)
	local region = roblox.Instance.new("Model")
	RegionBuilder.buildBounds(region, origin, roblox.Vector3.new(size.x, size.y, size.z), "#4FC3F7")
	local station = StationBuilder.build(region, origin, "Tester", "#4FC3F7")
	local parts = countParts(region)
	local spawn = station.spawn
	local facesRegion = spawn.LookVector:Dot(origin.LookVector) < -0.99
	if slot == 1 then
		check(
			parts <= REGION_PART_BUDGET,
			`region and station have {parts} parts (budget {REGION_PART_BUDGET})`
		)
		check(
			#region:GetDescendants() > 0 and region:FindFirstChild("Station") ~= nil,
			"station built in region"
		)
	end
	check(facesRegion, `slot {slot}: station spawn faces into the region`)
end
check(#(tagged.WarpPrompt or {}) == 3 + 8, "every station has a warp prompt")

print(`\n{failures} failed`)
if failures > 0 then
	process.exit(1)
end

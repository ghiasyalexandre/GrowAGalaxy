--!strict
-- World events announced by the server (WorldEvent):
--
--   "swarm" (centre, endsAt, count)  a golden asteroid swarm: a banner, then a
--                                    gold marker over its centre, seen through
--                                    anything, with the distance and time left
--   "swarmEnd"                       the marker goes
--
-- Display only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local A = Config.Asteroids
local GOLD = Color3.fromHex(A.SWARM_COLOR)

local WorldEventController = {}

local marker: Part? = nil
local markerText: TextLabel? = nil
local endsAt = 0
local sinceUpdate = 0

local function clear()
	if marker then
		marker:Destroy()
	end
	marker, markerText = nil, nil
end

local function showSwarm(centre: unknown, closesAt: unknown, count: unknown)
	if typeof(centre) ~= "Vector3" or type(closesAt) ~= "number" then
		return
	end
	clear()
	endsAt = closesAt
	local anchor = Instance.new("Part")
	anchor.Name = "GaG_SwarmMarker"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(centre)
	anchor.Parent = Workspace.CurrentCamera
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(220, 56)
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	marker, markerText = anchor, label
	ClientState.celebrate:Fire(
		"GOLDEN SWARM",
		`{if type(count) == "number" then count else A.SWARM_COUNT} golden asteroids appeared`,
		`Worth {A.SWARM_REWARD}x Stardust · follow the gold marker · {math.floor(
			A.SWARM_DURATION / 60 * 10 + 0.5
		) / 10} min`,
		GOLD,
		true
	)
end

local function update()
	local anchor, label = marker, markerText
	if anchor == nil or label == nil then
		return
	end
	local left = math.ceil(endsAt - Workspace:GetServerTimeNow())
	if left <= 0 then
		clear()
		return
	end
	local camera = Workspace.CurrentCamera
	local distance = (camera.CFrame.Position - anchor.Position).Magnitude
	label.Text =
		`GOLDEN SWARM\n{Format.abbreviate(math.floor(distance))} studs · {left // 60}:{string.format(
			"%02d",
			left % 60
		)}`
end

function WorldEventController.init() end

function WorldEventController.start()
	Net.WorldEvent.OnClientEvent:Connect(function(kind: unknown, ...: unknown)
		if kind == "swarm" then
			showSwarm(...)
			update()
		elseif kind == "swarmEnd" then
			clear()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		sinceUpdate += dt
		if sinceUpdate >= 0.25 then
			sinceUpdate = 0
			update()
		end
	end)
end

return WorldEventController

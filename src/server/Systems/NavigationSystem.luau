--!strict
-- Handles navigation prompts: the ISS navigation console, the station console
-- and the airlocks. Prompts are ProximityPrompts tagged "WarpPrompt" with a
-- WarpTarget attribute. Triggered events arrive on the server, so the client
-- never names a destination; the server picks it from the prompt.
--
-- Stage 1 stand-in for travel. In Stage 2 ships replace the ISS <-> station
-- warp; the airlock warps stay.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Parent.World.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local StationSystem = require(script.Parent.StationSystem)
local WorldSystem = require(script.Parent.WorldSystem)

-- WarpTarget values that point at ISS markers, and the marker they use.
local MARKER_TARGETS: { [string]: string } = {
	Arrival = "ArrivalSpawn",
	DockingArea = "DockingSpawn",
	Interior = "AirlockInside",
}

-- Extra reach allowed beyond a prompt's own activation distance (lag, avatar size).
local REACH_TOLERANCE = 8

local NavigationSystem = {}

local lastWarp: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function destination(player: Player, target: string): CFrame?
	if target == "OwnStation" then
		return StationSystem.getSpawn(player)
	end
	local markerName = MARKER_TARGETS[target]
	local marker = markerName and WorldSystem.getMarker(markerName)
	if marker == nil then
		return nil
	end
	if marker:IsA("SpawnLocation") then
		-- Spawn pads lie on the floor; stand the player on top.
		return marker.CFrame + Vector3.new(0, marker.Size.Y / 2 + 3, 0)
	end
	return marker.CFrame
end

local function onTriggered(prompt: ProximityPrompt, player: Player)
	local target = prompt:GetAttribute("WarpTarget")
	local anchor = prompt.Parent
	local root = rootOf(player)
	if type(target) ~= "string" or root == nil or anchor == nil or not anchor:IsA("BasePart") then
		return
	end
	if
		(root.Position - anchor.Position).Magnitude
		> prompt.MaxActivationDistance + REACH_TOLERANCE
	then
		return
	end
	local now = os.clock()
	if now - (lastWarp[player] or -math.huge) < Config.World.WARP_COOLDOWN then
		return
	end

	local goal = destination(player, target)
	if goal == nil then
		return
	end
	lastWarp[player] = now

	local character = player.Character
	pcall(function()
		player:RequestStreamAroundAsync(goal.Position)
	end)
	-- The player may have respawned or left while the area streamed in.
	if character and player.Character == character and rootOf(player) then
		character:PivotTo(goal)
	end
end

local function hook(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Triggered:Connect(function(player)
			onTriggered(instance, player)
		end)
	end
end

function NavigationSystem.start()
	for _, prompt in CollectionService:GetTagged(Build.WARP_TAG) do
		hook(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Build.WARP_TAG):Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		lastWarp[player] = nil
	end)
end

return NavigationSystem

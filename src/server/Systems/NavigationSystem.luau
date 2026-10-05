--!strict
-- Handles the airlocks: ProximityPrompts tagged "WarpPrompt" with a
-- WarpTarget attribute that move a player between the ISS interior and the
-- docking platform. Triggered events arrive on the server, so the client
-- never names a destination; the server picks it from the prompt.
--
-- The Stage 1 warps between the ISS and stations are gone: players fly there
-- now. Navigation consoles show a route instead (RoutePrompt, client side).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Parent.World.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local FlightGuard = require(script.Parent.FlightGuard)
local Teleport = require(script.Parent.Parent.Util.Teleport)
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

-- Destinations other systems add (e.g. the Dodgeball arena), by WarpTarget.
local extraTargets: { [string]: (Player) -> CFrame? } = {}

-- Lets another system own a WarpTarget: `where` picks the player's goal.
function NavigationSystem.addTarget(name: string, where: (Player) -> CFrame?)
	extraTargets[name] = where
end

local function destination(target: string, player: Player): CFrame?
	local extra = extraTargets[target]
	if extra then
		return extra(player)
	end
	local markerName = MARKER_TARGETS[target]
	local marker = markerName and WorldSystem.getMarker(markerName)
	if marker == nil then
		return nil
	end
	if marker:IsA("SpawnLocation") then
		-- Spawn pads lie on the floor; place the player just above.
		return marker.CFrame + Vector3.new(0, marker.Size.Y / 2 + 3, 0)
	end
	return marker.CFrame
end

local function onTriggered(prompt: ProximityPrompt, player: Player)
	local target = prompt:GetAttribute("WarpTarget")
	local anchor = prompt.Parent
	local root = Teleport.rootOf(player)
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

	local goal = destination(target, player)
	if goal == nil then
		return
	end
	lastWarp[player] = now
	if Teleport.character(player, goal) then
		FlightGuard.reset(player)
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

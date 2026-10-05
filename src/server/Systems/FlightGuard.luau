--!strict
-- Server-side movement check. Ships and spacesuits are moved by their own
-- client (network ownership), so twice a second the server compares each
-- player's position with the last one and asks: could they have covered that
-- distance at their top speed? A player who fails FLIGHT_GUARD_STRIKES checks
-- in a row, or leaves the flight area, is moved back to their last good
-- position. Rewards in later stages are validated separately on top of this.
--
-- Each player has one tracked subject: their ship's hull while piloting
-- (ShipSystem calls track), otherwise their character's root part. Systems
-- that move a player on purpose call reset() afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FlightMath = require(ReplicatedStorage.Shared.Logic.FlightMath)

local M = Config.Movement

-- Studs past the flight area edge before the guard steps in. The client stops
-- thrusting outwards at the edge, so only drifting or cheating gets this far.
local BOUNDS_MARGIN = 150

type Subject = { part: BasePart, maxSpeed: number }

type Track = {
	part: BasePart,
	maxSpeed: number,
	lastPosition: Vector3,
	lastGood: CFrame, -- pivot of the part's model at the last good sample
	lastTime: number,
	strikes: number,
}

local FlightGuard = {}

local explicit: { [Player]: Subject } = {}
local tracks: { [Player]: Track } = {}

local function modelOf(part: BasePart): Model?
	return part:FindFirstAncestorOfClass("Model")
end

local function currentSubject(player: Player): Subject?
	local chosen = explicit[player]
	if chosen and chosen.part:IsDescendantOf(Workspace) then
		return chosen
	end
	explicit[player] = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		-- Zero G Dodgeball: faster suits, launches off blocks, knockbacks.
		local D = Config.Dodgeball
		local top = if player:GetAttribute("Dodgeball") == true
			then math.max(M.SUIT_MAX_SPEED * D.SPEED_MULTIPLIER, D.LAUNCH_SPEED, D.KNOCKBACK)
			else M.SUIT_MAX_SPEED
		return { part = root, maxSpeed = top }
	end
	return nil
end

local function pivotOf(part: BasePart): CFrame
	local model = modelOf(part)
	return if model then model:GetPivot() else part.CFrame
end

local function baseline(subject: Subject): Track
	return {
		part = subject.part,
		maxSpeed = subject.maxSpeed,
		lastPosition = subject.part.Position,
		lastGood = pivotOf(subject.part),
		lastTime = os.clock(),
		strikes = 0,
	}
end

local function pullBack(player: Player, track: Track, reason: string)
	local model = modelOf(track.part)
	if model then
		model:PivotTo(track.lastGood)
	else
		track.part.CFrame = track.lastGood
	end
	track.part.AssemblyLinearVelocity = Vector3.zero
	warn(`[FlightGuard] Moved {player.Name} back to their last good position ({reason})`)
	track.lastPosition = track.lastGood.Position
	track.lastTime = os.clock()
	track.strikes = 0
end

local function check(player: Player)
	local subject = currentSubject(player)
	if subject == nil then
		tracks[player] = nil
		return
	end
	local track = tracks[player]
	if track == nil or track.part ~= subject.part then
		tracks[player] = baseline(subject)
		return
	end
	track.maxSpeed = subject.maxSpeed

	local now = os.clock()
	local position = track.part.Position
	local moved = (position - track.lastPosition).Magnitude
	local elapsed = now - track.lastTime
	track.lastPosition = position
	track.lastTime = now

	if
		not FlightMath.inBounds(
			position,
			M.FLIGHT_BOUNDS_RADIUS,
			M.FLIGHT_BOUNDS_HEIGHT,
			BOUNDS_MARGIN
		)
	then
		pullBack(player, track, "left the flight area")
		return
	end
	if
		FlightMath.plausibleTravel(
			moved,
			elapsed,
			track.maxSpeed,
			M.FLIGHT_GUARD_TOLERANCE,
			M.FLIGHT_GUARD_SLACK
		)
	then
		track.strikes = 0
		track.lastGood = pivotOf(track.part)
		return
	end
	track.strikes += 1
	if track.strikes >= M.FLIGHT_GUARD_STRIKES then
		pullBack(player, track, `{math.floor(moved)} studs in {string.format("%.2f", elapsed)}s`)
	end
end

-- Checks `part` (a ship hull) at `maxSpeed` instead of the character.
function FlightGuard.track(player: Player, part: BasePart, maxSpeed: number)
	explicit[player] = { part = part, maxSpeed = maxSpeed }
	FlightGuard.reset(player)
end

-- Goes back to checking the character.
function FlightGuard.untrack(player: Player)
	explicit[player] = nil
	FlightGuard.reset(player)
end

-- Accepts the player's current position as good, after a server move.
function FlightGuard.reset(player: Player)
	local subject = currentSubject(player)
	if subject then
		tracks[player] = baseline(subject)
	else
		tracks[player] = nil
	end
end

function FlightGuard.start()
	Players.PlayerRemoving:Connect(function(player)
		explicit[player] = nil
		tracks[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(M.FLIGHT_GUARD_INTERVAL)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return FlightGuard

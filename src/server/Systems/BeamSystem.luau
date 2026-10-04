--!strict
-- Ship mining lasers. The pilot's client says when the beam starts and stops
-- and where it points; this system decides whether it may fire, tracks heat
-- and overheating, and publishes the result on the ship model so every
-- client draws the same beam. While it fires, MiningSystem extracts
-- whatever asteroid it hits.
--
-- BeamInput (client -> server):
--   "start", aim   start firing (only while piloting)
--   "aim", aim     the aim while firing; also starts the beam, in case a
--                  "start" was dropped by the rate limit
--   "stop"         stop firing (never rate-limited)
-- Overheating lets go of the trigger: the client must send "start" again
-- once the beam has cooled, so a lost "stop" can't keep it firing.
-- `aim` is a unit Vector3 in ship space (-Z is the nose). It is clamped to
-- Config.Beam.AIM_CONE_DEGREES around the nose.
--
-- Ship model attributes:
--   BeamOn      boolean  the beam is firing
--   BeamAim     Vector3  its direction in ship space
--   Heat        number   0 to 1, share of the ship's heat capacity
--   Overheated  boolean  locked until heat falls to OVERHEAT_RESUME_SHARE
--
-- Heat belongs to the player, not the ship, so leaving and reboarding or
-- relaunching doesn't cool the beam any faster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BeamMath = require(ReplicatedStorage.Shared.Logic.BeamMath)
local Config = require(ReplicatedStorage.Shared.Config)
local MiningSystem = require(script.Parent.MiningSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ShipSystem = require(script.Parent.ShipSystem)

local B = Config.Beam
local CONE = math.rad(B.AIM_CONE_DEGREES)

type State = {
	firing: boolean, -- the client is holding the trigger
	aim: Vector3,
	heat: number,
	overheated: boolean,
	capacity: number,
	cooling: number,
	model: Model?, -- the ship whose attributes show this state
}

local BeamSystem = {}

local states: { [Player]: State } = {}
-- Starts and up to 10 aim updates a second, with room for jitter. Stops
-- aren't limited.
local inputLimit = RateLimiter.new(20, 15)
local elapsed = 0

local function stateFor(player: Player): State
	local state = states[player]
	if state == nil then
		state = {
			firing = false,
			aim = BeamMath.FORWARD,
			heat = 0,
			overheated = false,
			capacity = 1,
			cooling = 1,
			model = nil,
		}
		states[player] = state
	end
	return state
end

local function publish(model: Model, state: State)
	local on = state.firing and not state.overheated
	model:SetAttribute("BeamOn", on)
	if on then
		model:SetAttribute("BeamAim", state.aim)
	end
	model:SetAttribute("Overheated", state.overheated)
	model:SetAttribute("Heat", math.floor(state.heat / state.capacity * 100 + 0.5) / 100)
end

local function clear(model: Model?)
	if model and model.Parent then
		model:SetAttribute("BeamOn", false)
		MiningSystem.stop(model)
	end
end

local function onInput(player: Player, action: unknown, aim: unknown)
	-- Stopping only ever reduces activity, so it skips the rate limit.
	if action == "stop" then
		local state = states[player]
		if state and state.firing then
			state.firing = false
			if state.model then
				publish(state.model, state)
			end
		end
		return
	end
	if (action ~= "start" and action ~= "aim") or not inputLimit.allow(player) then
		return
	end
	local model, info = ShipSystem.getPiloted(player)
	local direction = BeamMath.sanitizeAim(aim, CONE)
	if model == nil or info == nil or direction == nil then
		return
	end
	local state = stateFor(player)
	state.aim = direction
	state.capacity = info.heatCapacity
	state.cooling = info.coolingRate
	if not state.overheated then
		state.firing = true
	end
	if state.model ~= model then
		clear(state.model)
		state.model = model
	end
	publish(model, state)
end

local function tick(dt: number)
	for player, state in states do
		local model, info = ShipSystem.getPiloted(player)
		if model ~= state.model then
			clear(state.model)
			state.model = model
		end
		if info then
			state.capacity = info.heatCapacity
			state.cooling = info.coolingRate
		end
		-- Only a piloted ship fires; leaving the seat lets go of the trigger.
		if model == nil then
			state.firing = false
		end
		local wasOverheated = state.overheated
		state.heat, state.overheated = BeamMath.heatStep(
			state.heat,
			state.overheated,
			state.firing,
			dt,
			state.capacity,
			B.HEAT_PER_SECOND,
			state.cooling,
			B.OVERHEAT_RESUME_SHARE
		)
		if state.overheated and not wasOverheated then
			state.firing = false
			MiningSystem.noteOverheat(player)
			Notify.send(player, "Laser overheated. It fires again once it cools down.")
		end
		if model and info then
			publish(model, state)
			if state.firing and not state.overheated then
				MiningSystem.step(player, model, info, state.aim, dt)
			else
				MiningSystem.stop(model)
			end
		elseif state.heat <= 0 then
			states[player] = nil
		end
	end
end

function BeamSystem.start()
	Net.BeamInput.OnServerEvent:Connect(onInput)
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= B.SERVER_TICK then
			tick(elapsed)
			elapsed = 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return BeamSystem

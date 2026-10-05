--!strict
-- Ship mining lasers, fired one shot per click. The pilot's client sends a
-- shot with its aim; this system decides whether it may fire (piloting, not
-- overheated, not faster than FIRE_INTERVAL), adds heat, hands the shot to
-- MiningSystem and CombatSystem (PvP), and publishes it on the ship model so every client draws the
-- bolt. Lasers cool between shots.
--
-- BeamInput (client -> server):
--   "shot", aim   fire one shot. `aim` is a unit Vector3 in ship space (-Z is
--                 the nose), clamped to Config.Beam.AIM_CONE_DEGREES.
--
-- Ship model attributes:
--   Shot        number   counts this ship's shots; each change is a bolt
--   BeamAim     Vector3  the last shot's direction in ship space
--   Heat        number   0 to 1, share of the ship's heat capacity
--   Overheated  boolean  locked until heat falls to OVERHEAT_RESUME_SHARE
--
-- Heat belongs to the player, not the ship, so leaving and reboarding or
-- relaunching doesn't cool the laser any faster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BeamMath = require(ReplicatedStorage.Shared.Logic.BeamMath)
local CombatSystem = require(script.Parent.CombatSystem)
local Config = require(ReplicatedStorage.Shared.Config)
local RaidSystem = require(script.Parent.RaidSystem)
local MiningSystem = require(script.Parent.MiningSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ShipSystem = require(script.Parent.ShipSystem)

local B = Config.Beam
local CONE = math.rad(B.AIM_CONE_DEGREES)
-- Network jitter can bunch two clicks together; allow a little slack.
local MIN_INTERVAL = B.FIRE_INTERVAL * 0.8

type State = {
	heat: number,
	overheated: boolean,
	capacity: number,
	cooling: number,
	lastShot: number,
	shots: number,
	model: Model?, -- the ship whose attributes show this state
}

local BeamSystem = {}

local states: { [Player]: State } = {}
local inputLimit = RateLimiter.new(8, 1 / B.FIRE_INTERVAL + 1)
local elapsed = 0

local function stateFor(player: Player): State
	local state = states[player]
	if state == nil then
		state = {
			heat = 0,
			overheated = false,
			capacity = 1,
			cooling = 1,
			lastShot = 0,
			shots = 0,
			model = nil,
		}
		states[player] = state
	end
	return state
end

local function publishHeat(model: Model, state: State)
	model:SetAttribute("Overheated", state.overheated)
	model:SetAttribute("Heat", math.floor(state.heat / state.capacity * 100 + 0.5) / 100)
end

local function onInput(player: Player, action: unknown, aim: unknown)
	if action ~= "shot" or not inputLimit.allow(player) then
		return
	end
	local model, info = ShipSystem.getPiloted(player)
	local direction = BeamMath.sanitizeAim(aim, CONE)
	if model == nil or info == nil or direction == nil then
		return
	end
	local state = stateFor(player)
	local now = os.clock()
	if state.overheated or now - state.lastShot < MIN_INTERVAL then
		return
	end
	state.lastShot = now
	state.capacity = info.heatCapacity
	state.cooling = info.coolingRate
	state.model = model
	state.heat, state.overheated = BeamMath.shotHeat(state.heat, state.capacity, B.HEAT_PER_SHOT)
	state.shots += 1

	model:SetAttribute("BeamAim", direction)
	model:SetAttribute("Shot", state.shots)
	publishHeat(model, state)
	MiningSystem.shot(player, model, info, direction)
	CombatSystem.shot(player, model, info, direction)
	RaidSystem.shot(player, model, info, direction)
	if state.overheated then
		MiningSystem.noteOverheat(player)
		Notify.send(player, "Laser overheated. It fires again once it cools down.")
	end
end

local function tick(dt: number)
	for player, state in states do
		local model, info = ShipSystem.getPiloted(player)
		if info then
			state.capacity = info.heatCapacity
			state.cooling = info.coolingRate
		end
		state.heat, state.overheated = BeamMath.heatStep(
			state.heat,
			state.overheated,
			false,
			dt,
			state.capacity,
			0,
			state.cooling,
			B.OVERHEAT_RESUME_SHARE
		)
		if model then
			state.model = model
			publishHeat(model, state)
			MiningSystem.refresh(player, model)
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

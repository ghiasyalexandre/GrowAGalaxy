--!strict
-- The daily prize wheel on the server (Config.Wheel, Logic/WheelMath).
--
-- WheelRequest (RemoteFunction, client -> server):
--   "spin" -> (ok, message, prizeIndex?)
--
-- One free spin every 24 hours from the last one; there are no paid spins
-- and nothing speeds the timer up. The server draws the prize with its own
-- Random, then DataSystem.spinWheel records the spin and adds the Stardust
-- in one step before answering, so the prize is granted even if the client
-- never plays the animation. Prizes are fixed amounts: no pass, boost or
-- trail multiplies them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local WheelMath = require(ReplicatedStorage.Shared.Logic.WheelMath)

local W = Config.Wheel
local CURRENCY = Config.Economy.CURRENCY_NAME

local WheelSystem = {}

local requestLimit = RateLimiter.new(2, 1)
local rng = Random.new()

local function spin(player: Player): (boolean, string, number?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "Your save isn't ready yet.", nil
	end
	local now = os.time()
	if not WheelMath.ready(profile.wheel.nextSpin, now) then
		return false,
			`Your next free spin is in {EggMath.durationText(
				WheelMath.wait(profile.wheel.nextSpin, now)
			)}.`,
			nil
	end
	local index = WheelMath.pick(rng:NextInteger(1, WheelMath.total()))
	if not DataSystem.spinWheel(player, index, now) then
		return false, "The wheel couldn't spin. Try again.", nil
	end
	DataSystem.addStat(player, "wheelSpins", 1)
	local prize = W.PRIZES[index]
	return true, `You won {Format.commas(prize.stardust)} {CURRENCY}!`, index
end

local function onRequest(player: Player, action: unknown): (boolean, string, number?)
	if not requestLimit.allow(player) then
		return false, "Slow down a little.", nil
	end
	if action == "spin" then
		return spin(player)
	end
	return false, "The wheel only spins.", nil
end

function WheelSystem.start()
	Net.WheelRequest.OnServerInvoke = onRequest
end

return WheelSystem

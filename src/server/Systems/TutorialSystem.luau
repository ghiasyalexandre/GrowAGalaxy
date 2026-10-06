--!strict
-- The tutorial's player-confirmed steps (Config.Tutorial `ack` steps) and
-- skipping. Every other step completes from gameplay stats
-- (ProgressionSystem moves the tutorial on as stats change).
--
-- TutorialRequest (RemoteFunction, client -> server), returns (ok, message):
--   "ack", stepIndex   counts the current step's stat, only if that step is
--                      the player's current one and an `ack` step; the
--                      `final` step also pays FINISH_REWARD (once: after it
--                      the tutorial is done)
--   "skip"             ends the tutorial without the reward

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Reward = require(script.Parent.Parent.Util.Reward)

local T = Config.Tutorial

local TutorialSystem = {}

local limit = RateLimiter.new(3, 1)

local function ack(player: Player, index: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or profile.tutorial.done then
		return false, "The tutorial is already finished."
	end
	local current = Progression.tutorialStep(profile.stats)
	local step = T.STEPS[current]
	if step == nil or index ~= current or not step.ack then
		return false, "That isn't the step you're on."
	end
	if step.final then
		DataSystem.addStardust(player, T.FINISH_REWARD)
		Reward.send(
			player,
			"achievement",
			T.FINISH_REWARD,
			nil,
			`Tutorial complete|+{T.FINISH_REWARD} Stardust`
		)
	end
	DataSystem.addStat(player, step.stat, 1)
	return true, "Great job!"
end

local function onRequest(player: Player, action: unknown, a: unknown): (boolean, string)
	if not limit.allow(player) then
		return false, "Slow down a little."
	end
	if action == "ack" then
		return ack(player, a)
	elseif action == "skip" then
		DataSystem.setTutorialStep(player, 0)
		return true, "Tutorial skipped. You can read the guide any time in Settings."
	end
	return false, "Unknown tutorial action."
end

function TutorialSystem.start()
	Net.TutorialRequest.OnServerInvoke = onRequest
end

return TutorialSystem

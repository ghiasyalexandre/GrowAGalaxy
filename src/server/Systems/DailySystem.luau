--!strict
-- Daily prizes (Config.Daily). DailyRequest "claim" claims today's prize for
-- the calling player if they haven't yet today. The day is the server's UTC
-- day, never the client's clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyMath = require(ReplicatedStorage.Shared.Logic.DailyMath)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DailySystem = {}

local limit = RateLimiter.new(3, 1)

local function claim(player: Player): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "Your save is still loading."
	end
	local day, amount = DataSystem.claimDaily(player, DailyMath.today(os.time()))
	if day == nil then
		return false, "Today's prize is already claimed. Come back tomorrow!"
	end
	DataSystem.addStat(player, "dailyClaims", 1)
	return true, `Day {day} prize: {DailyMath.describe(amount or 0)}!`
end

function DailySystem.start()
	Net.DailyRequest.OnServerInvoke = function(player: Player, action: unknown)
		if action ~= "claim" or not limit.allow(player) or player.Parent ~= Players then
			return false, "Try again in a moment."
		end
		return claim(player)
	end
end

return DailySystem

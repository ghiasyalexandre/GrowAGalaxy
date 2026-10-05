--!strict
-- Redeemable codes (Config.Codes) from the Settings panel's code box,
-- through CodeRequest(code) -> (ok, message). The text is trimmed and
-- upper-cased, so "  iluvghiasy " works; each code works once per player
-- (DataSystem.redeemCode records it in the profile). Rate limited, so codes
-- can't be guessed by brute force.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local CodeSystem = {}

local limit = RateLimiter.new(5, 0.2) -- 5 tries, then one every 5 seconds

local function redeem(player: Player, text: unknown): (boolean, string)
	if not limit.allow(player) then
		return false, "Too many tries. Wait a few seconds."
	end
	if type(text) ~= "string" or #text > Config.Codes.MAX_LENGTH * 2 then
		return false, "That code doesn't exist."
	end
	local code = string.upper(string.match(text, "^%s*(.-)%s*$") or "")
	if code == "" then
		return false, "Type a code first."
	end
	local def, problem = DataSystem.redeemCode(player, code)
	if def == nil then
		return false, problem or "That code doesn't exist."
	end
	return true, `Code redeemed: {def.message}`
end

function CodeSystem.start()
	Net.CodeRequest.OnServerInvoke = redeem
end

return CodeSystem

--!strict
-- Redeemable codes (Config.Codes) from the Settings panel's code box,
-- through CodeRequest(code) -> (ok, message). The text is trimmed and
-- upper-cased, so "  iluvghiasy " works; each code works once per player
-- (DataSystem.redeemCode records it in the profile). Rate limited, so codes
-- can't be guessed by brute force. A `reset` code is different: typed
-- twice within RESET_CONFIRM_SECONDS it erases the player's own save
-- (DataSystem.resetProfile) and has them rejoin to a fresh start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local CodeSystem = {}

local limit = RateLimiter.new(5, 0.2) -- 5 tries, then one every 5 seconds
-- A reset code typed once: when, so typing it again in time confirms.
local resetAsked: { [Player]: number } = {}

-- The reset code: the first time only warns; again within
-- RESET_CONFIRM_SECONDS it erases the save and has the player rejoin.
local function reset(player: Player, def: { message: string }): (boolean, string)
	local asked = resetAsked[player]
	local now = os.clock()
	if asked == nil or now - asked > Config.Codes.RESET_CONFIRM_SECONDS then
		resetAsked[player] = now
		return false,
			`WARNING: this erases ALL your progress (Stardust, stars, planets, ships, everything). Type the code again within {Config.Codes.RESET_CONFIRM_SECONDS} seconds to confirm.`
	end
	resetAsked[player] = nil
	if not DataSystem.resetProfile(player) then
		return false, "Your save isn't loaded yet."
	end
	task.delay(1.5, function()
		if player.Parent then
			player:Kick(def.message)
		end
	end)
	return true, def.message
end

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
	local resetDef = Config.Codes.BY_CODE[code]
	if resetDef and resetDef.reset then
		return reset(player, resetDef)
	end
	local def, problem = DataSystem.redeemCode(player, code)
	if def == nil then
		return false, problem or "That code doesn't exist."
	end
	return true, `Code redeemed: {def.message}`
end

function CodeSystem.start()
	Net.CodeRequest.OnServerInvoke = redeem
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		resetAsked[player] = nil
	end)
end

return CodeSystem

--!strict
-- Awards Roblox badges (Config.Badges) on the server. A badge is earned when
-- its stat reaches its goal (DataSystem.statChanged), and checked again when
-- a profile loads, so players who earned it before it existed still get it.
-- Roblox is asked first whether the player has it (UserHasBadgeAsync), so a
-- badge is only ever awarded once; failures are retried a few times, then
-- left for the next stat change or join.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Notify = require(script.Parent.Parent.Util.Notify)

local TRIES = 3

local BadgeSystem = {}

-- Badges already confirmed for each player this session.
local confirmed: { [Player]: { [string]: boolean } } = {}

local function retry<T>(work: () -> T): (boolean, T?)
	for attempt = 1, TRIES do
		local ok, value = pcall(work)
		if ok then
			return true, value
		end
		if attempt < TRIES then
			task.wait(attempt * 2)
		end
	end
	return false, nil
end

local function award(player: Player, key: string)
	local def = Config.Badges.BY_KEY[key]
	local done = confirmed[player]
	if def == nil or def.id <= 0 or done == nil or done[key] then
		return
	end
	done[key] = true -- one attempt at a time
	local ok, has = retry(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, def.id)
	end)
	if not ok then
		done[key] = nil
		return
	end
	if has then
		return
	end
	local awarded, result = retry(function()
		return BadgeService:AwardBadge(player.UserId, def.id)
	end)
	if awarded and result then
		Notify.send(player, `Badge earned: {def.displayName}!`)
	else
		done[key] = nil
		warn(`[BadgeSystem] Could not award {key} to {player.Name}`)
	end
end

local function check(player: Player, stat: string?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	for key, def in Config.Badges.BY_KEY do
		if (stat == nil or stat == def.stat) and (profile.stats[def.stat] or 0) >= def.goal then
			task.spawn(award, player, key)
		end
	end
end

function BadgeSystem.start()
	DataSystem.profileLoaded:Connect(function(player)
		confirmed[player] = {}
		check(player, nil)
	end)
	DataSystem.statChanged:Connect(function(player, stat)
		check(player, stat)
	end)
	Players.PlayerRemoving:Connect(function(player)
		confirmed[player] = nil
	end)
end

return BadgeSystem

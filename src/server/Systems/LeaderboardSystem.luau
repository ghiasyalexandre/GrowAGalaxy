--!strict
-- Keeps the Stardust leaderboard's OrderedDataStore (Config.Leaderboard) up
-- to date with each player's current balance: written when their profile
-- loads, every WRITE_INTERVAL seconds if it changed, and when they leave.
--
-- Writes run one player at a time in their own threads and are spread over
-- the interval, so a full server stays far below Roblox's write budget. A
-- failed write is retried on the next round. The leaderboard store is
-- separate from the save data: nothing here can touch a profile. In Studio
-- without API access the store can't be opened, and this does nothing.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)

local L = Config.Leaderboard

local LeaderboardSystem = {}

local store: OrderedDataStore? = nil
local written: { [Player]: number } = {} -- last value saved for each player
local latest: { [Player]: number } = {} -- last balance seen, for writing on leave

local function write(userId: number, value: number): boolean
	local target = store
	if target == nil then
		return false
	end
	local ok, problem = pcall(function()
		target:SetAsync(tostring(userId), value)
	end)
	if not ok then
		warn(`[LeaderboardSystem] Couldn't save {userId}'s Stardust: {problem}`)
	end
	return ok
end

-- Saves the player's balance if it changed since the last save.
local function update(player: Player)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	local value = math.max(math.floor(profile.stardust), 0)
	latest[player] = value
	if written[player] ~= value and write(player.UserId, value) then
		written[player] = value
	end
end

function LeaderboardSystem.start()
	local ok, opened = pcall(function()
		return DataStoreService:GetOrderedDataStore(L.STORE, L.SCOPE)
	end)
	if not ok then
		warn(`[LeaderboardSystem] Leaderboard off: {opened}`)
		return
	end
	store = opened

	DataSystem.profileLoaded:Connect(function(player)
		task.spawn(update, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local value = latest[player]
		if value and written[player] ~= value then
			task.spawn(write, player.UserId, value)
		end
		written[player] = nil
		latest[player] = nil
	end)
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			local gap = L.WRITE_INTERVAL / math.max(#players, 1)
			for _, player in players do
				if player.Parent == Players then
					task.spawn(update, player)
				end
				task.wait(gap)
			end
			if #players == 0 then
				task.wait(L.WRITE_INTERVAL)
			end
		end
	end)
end

return LeaderboardSystem

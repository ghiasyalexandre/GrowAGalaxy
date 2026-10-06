--!strict
-- Stardust on the leaderboards:
--
--   In game     every player's "leaderstats" folder has a Stardust value,
--               so Roblox's player list (top right) shows each balance live.
--   Global      each player's current balance is written to the
--               OrderedDataStore (Config.Leaderboard) a Roblox leaderboard
--               reads: when their profile loads, every WRITE_INTERVAL
--               seconds if it changed, and when they leave.
--
-- The top balances are read back every READ_INTERVAL seconds for the ISS
-- Star Lounge board (top()); names are looked up once per user and cached.
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
export type Entry = { name: string, stardust: number }
local top: { Entry } = {}
local names: { [number]: string } = {}
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

-- The player list's Stardust column.
local function stat(player: Player): IntValue
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "leaderstats"
		made.Parent = player
		folder = made
	end
	local value = (folder :: Instance):FindFirstChild(L.UNITS)
	if value == nil or not value:IsA("IntValue") then
		local made = Instance.new("IntValue")
		made.Name = L.UNITS
		made.Parent = folder
		value = made
	end
	return value :: IntValue
end

local function showLive()
	for _, player in Players:GetPlayers() do
		local profile = DataSystem.getProfile(player)
		if profile then
			local value = math.floor(profile.stardust)
			local holder = stat(player)
			if holder.Value ~= value then
				holder.Value = value
			end
		end
	end
end

local function nameOf(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	names[userId] = result
	return result
end

-- Reads the top balances (yields).
local function readTop()
	local target = store
	if target == nil then
		return
	end
	local ok, pages = pcall(function()
		return target:GetSortedAsync(false, L.BOARD_SIZE)
	end)
	if not ok then
		warn(`[LeaderboardSystem] Couldn't read the top balances: {pages}`)
		return
	end
	local entries: { Entry } = {}
	for _, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			table.insert(entries, { name = nameOf(userId), stardust = item.value })
		end
	end
	top = entries
end

-- The latest top balances read from the global leaderboard (empty until
-- the first read, and where the data store isn't available).
function LeaderboardSystem.top(): { Entry }
	return table.clone(top)
end

function LeaderboardSystem.start()
	-- The player list works even where the data store doesn't (Studio).
	task.spawn(function()
		while true do
			showLive()
			task.wait(1)
		end
	end)
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
			readTop()
			task.wait(L.READ_INTERVAL)
		end
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

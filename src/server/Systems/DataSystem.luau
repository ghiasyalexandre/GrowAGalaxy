--!strict
-- Owns every player's Profile: loading, saving, and all Stardust changes.
-- Other systems go through this module; nothing else writes leaderstats.
--
-- Starter-grade persistence (retry + autosave + BindToClose). Before launch,
-- move to session locking (e.g. ProfileStore) so two servers can't race.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

local PROFILE_VERSION = 1
local MAX_ATTEMPTS = 3

local DataSystem = {}

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local store: DataStore? = nil

local function defaultProfile(): Profile
	return {
		version = PROFILE_VERSION,
		stardust = Config.STARTING_STARDUST,
		owned = {},
	}
end

local function sanitize(raw: any): Profile
	local profile = defaultProfile()
	if typeof(raw) ~= "table" then
		return profile
	end
	local stardust = raw.stardust
	if typeof(stardust) == "number" and stardust == stardust and stardust >= 0 then
		profile.stardust = math.floor(stardust)
	end
	if typeof(raw.owned) == "table" then
		for _, id in raw.owned do
			if typeof(id) == "string" and Config.DROPPERS_BY_ID[id] then
				table.insert(profile.owned, id)
			end
		end
	end
	return profile
end

local function withRetry(label: string, fn: () -> any): (boolean, any)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataSystem] {label} attempt {attempt} failed: {result}`)
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function updateLeaderstats(player: Player, profile: Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(Config.CURRENCY_NAME)
	if value and value:IsA("IntValue") then
		value.Value = profile.stardust
	end
end

local function load(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local stardust = Instance.new("IntValue")
	stardust.Name = Config.CURRENCY_NAME
	stardust.Parent = leaderstats
	leaderstats.Parent = player

	local profile = defaultProfile()
	local ds = store
	if ds then
		local ok, raw = withRetry("load", function()
			return ds:GetAsync(keyFor(player))
		end)
		if ok then
			profile = sanitize(raw)
			canSave[player] = true
		else
			-- Never overwrite real data with defaults after a failed load.
			warn(`[DataSystem] {player.Name} is playing on a temporary profile; it will not save`)
		end
	end

	if player.Parent ~= Players then
		canSave[player] = nil
		return
	end
	profiles[player] = profile
	updateLeaderstats(player, profile)
end

local function save(player: Player)
	local profile = profiles[player]
	local ds = store
	if not profile or not ds or not canSave[player] then
		return
	end
	local snapshot = table.clone(profile)
	snapshot.owned = table.clone(profile.owned)
	withRetry("save", function()
		return ds:SetAsync(keyFor(player), snapshot, { player.UserId })
	end)
end

-- Yields until the player's profile is loaded. Returns nil if they leave first.
function DataSystem.waitForProfile(player: Player): Profile?
	while player.Parent == Players and not profiles[player] do
		task.wait()
	end
	return profiles[player]
end

function DataSystem.getStardust(player: Player): number
	local profile = profiles[player]
	return if profile then profile.stardust else 0
end

function DataSystem.addStardust(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.stardust += math.floor(amount)
	updateLeaderstats(player, profile)
end

function DataSystem.trySpend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.stardust < amount then
		return false
	end
	profile.stardust -= amount
	updateLeaderstats(player, profile)
	return true
end

function DataSystem.owns(player: Player, id: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.owned, id) ~= nil
end

function DataSystem.markOwned(player: Player, id: string)
	local profile = profiles[player]
	if profile and not table.find(profile.owned, id) then
		table.insert(profile.owned, id)
	end
end

function DataSystem.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[DataSystem] DataStores unavailable, progress won't save: {result}`)
	end
end

function DataSystem.start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		canSave[player] = nil
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)

	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for player in profiles do
			task.spawn(save, player)
		end
	end
end

return DataSystem

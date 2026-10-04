--!strict
-- Owns every player's saved profile.
--
-- ProfileStore handles session locking (one server at a time per profile),
-- autosaving, saving on leave and on shutdown. If a profile cannot be loaded
-- the player is kicked: the game never runs on a stand-in profile that could
-- overwrite real data. Other systems read profiles with getProfile() and change
-- them only through the functions below, which also update the owner's HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local ProfileSchema = require(ReplicatedStorage.Shared.Logic.ProfileSchema)
local ProfileStore = require(ServerScriptService.Vendor.ProfileStore) :: any
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

-- A fresh store: the dropper prototype's saves ("GrowAGalaxy2_Profiles_v1")
-- use a different format and are deliberately left untouched.
local STORE_NAME = "PlayerProfiles_v1"

local DataSystem = {}

-- Fires once per join, after the profile is loaded and cleaned up.
DataSystem.profileLoaded = Signal.new() :: Signal.Signal<Player, Profile>

local store: any = nil
local sessions: { [Player]: any } = {}

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function load(player: Player)
	local session = store:StartSessionAsync(keyFor(player), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if session == nil then
		if player.Parent == Players then
			player:Kick(
				"We couldn't load your save, so we stopped before anything could be overwritten. Please rejoin."
			)
		end
		return
	end

	local ok, problem = ProfileSchema.normalize(session.Data)
	if not ok then
		warn(`[DataSystem] Not using {player.Name}'s profile: {problem}`)
		session:EndSession() -- normalize changed nothing, so this saves the data as it was
		player:Kick(
			"This server runs an older version of the game. Please rejoin to get a newer server."
		)
		return
	end

	session:AddUserId(player.UserId)
	session.OnSessionEnd:Connect(function()
		sessions[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		session:EndSession()
		return
	end
	sessions[player] = session
	DataSystem.profileLoaded:Fire(player, session.Data)
end

local function push(player: Player, field: string, value: any)
	Net.ProfileChanged:FireClient(player, field, value)
end

local function wholePositive(amount: number): number?
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then
		return nil
	end
	local whole = math.floor(amount)
	return if whole > 0 then whole else nil
end

function DataSystem.getProfile(player: Player): Profile?
	local session = sessions[player]
	return if session then session.Data else nil
end

-- Yields until the player's profile is ready. Returns nil if they leave, the
-- load fails, or `timeout` seconds pass.
function DataSystem.waitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while sessions[player] == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataSystem.getProfile(player)
end

function DataSystem.addCredits(player: Player, amount: number): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil then
		return false
	end
	profile.credits += whole
	push(player, "credits", profile.credits)
	return true
end

-- Deducts Credits only if the player can afford all of it.
function DataSystem.spendCredits(player: Player, amount: number): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil or profile.credits < whole then
		return false
	end
	profile.credits -= whole
	push(player, "credits", profile.credits)
	return true
end

function DataSystem.init()
	store = ProfileStore.New(STORE_NAME, ProfileSchema.default())
end

function DataSystem.start()
	Players.PlayerAdded:Connect(load)
	-- Deferred so the other systems' start() run first and are listening for
	-- profileLoaded before the first profile can finish loading.
	for _, player in Players:GetPlayers() do
		task.defer(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			session:EndSession()
		end
	end)
end

return DataSystem

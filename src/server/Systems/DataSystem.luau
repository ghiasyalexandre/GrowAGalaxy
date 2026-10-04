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

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ProfileSchema = require(ReplicatedStorage.Shared.Logic.ProfileSchema)
local ProfileStore = require(ServerScriptService.Vendor.ProfileStore) :: any
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

-- A fresh store: the dropper prototype's saves ("GrowAGalaxy2_Profiles_v1")
-- use a different format and are deliberately left untouched.
local STORE_NAME = "PlayerProfiles_v1"

local DataSystem = {}

-- Fires once per join, after the profile is loaded and cleaned up.
DataSystem.profileLoaded = Signal.new() :: Signal.Signal<Player, Profile>
-- Fires after addStat changes a stat (achievements and the tutorial listen).
DataSystem.statChanged = Signal.new() :: Signal.Signal<Player, string>

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

function DataSystem.addStardust(player: Player, amount: number): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil then
		return false
	end
	profile.stardust += whole
	push(player, "stardust", profile.stardust)
	return true
end

-- Deducts Stardust only if the player can afford all of it.
function DataSystem.spendStardust(player: Player, amount: number): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil or profile.stardust < whole then
		return false
	end
	profile.stardust -= whole
	push(player, "stardust", profile.stardust)
	return true
end

local function pushIncome(player: Player, profile: Profile)
	push(player, "incomeRate", StarMath.totalIncome(profile.galaxy.stars))
end

-- Adds a star to the player's galaxy and returns its new id. The caller has
-- already validated and paid for it.
function DataSystem.addStar(player: Player, star: Types.StarRecord): string?
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil
	end
	local galaxy = profile.galaxy
	local id = `s{galaxy.nextId}`
	galaxy.nextId += 1
	galaxy.stars[id] = star
	pushIncome(player, profile)
	return id
end

-- Changes a star's level or position (already validated by the caller).
function DataSystem.updateStar(player: Player, id: string, level: number?, pos: Types.Vec3?)
	local profile = DataSystem.getProfile(player)
	local star = profile and profile.galaxy.stars[id]
	if profile == nil or star == nil then
		return
	end
	if level then
		star.level = level
	end
	if pos then
		star.pos = pos
	end
	pushIncome(player, profile)
end

-- Adds `dt` seconds of star income to "uncollected", up to the cap.
function DataSystem.accrueIncome(player: Player, dt: number)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	local rate = StarMath.totalIncome(profile.galaxy.stars)
	if rate <= 0 then
		return
	end
	local cap = rate * Config.Economy.UNCOLLECTED_CAP_SECONDS
	local before = profile.uncollected
	profile.uncollected = StarMath.accrue(before, rate, dt, cap)
	if math.floor(profile.uncollected) ~= math.floor(before) then
		push(player, "uncollected", math.floor(profile.uncollected))
	end
end

-- Moves the whole Stardust part of "uncollected" into the balance. Returns
-- how much was collected (0 if less than one).
function DataSystem.collectIncome(player: Player): number
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return 0
	end
	local whole = math.floor(profile.uncollected)
	if whole < 1 then
		return 0
	end
	profile.uncollected -= whole
	push(player, "uncollected", math.floor(profile.uncollected))
	DataSystem.addStardust(player, whole)
	return whole
end

-- Adds to a lifetime stat (profile.stats), e.g. asteroids mined. Stats feed
-- achievements. Not shown on the HUD, so nothing is pushed.
function DataSystem.addStat(player: Player, stat: string, amount: number)
	local profile = DataSystem.getProfile(player)
	if profile and type(amount) == "number" and amount == amount and amount > 0 then
		profile.stats[stat] = (profile.stats[stat] or 0) + amount
		DataSystem.statChanged:Fire(player, stat)
	end
end

-- Gives the player a ship, fitted with all the equipment they own.
function DataSystem.grantShip(player: Player, shipId: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or profile.ownedShips[shipId] then
		return
	end
	profile.ownedShips[shipId] = true
	local equipment: { [string]: string } = {}
	local starter = profile.loadouts[profile.activeShip]
	if starter then
		equipment = table.clone(starter.equipment)
	end
	profile.loadouts[shipId] = { equipment = equipment }
	push(player, "ownedShips", table.clone(profile.ownedShips))
end

-- Makes an owned ship the one the hangars launch.
function DataSystem.setActiveShip(player: Player, shipId: string): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or not profile.ownedShips[shipId] then
		return false
	end
	profile.activeShip = shipId
	push(player, "activeShip", shipId)
	return true
end

-- Gives the player an equipment item and fits it to every ship they own.
function DataSystem.grantEquipment(player: Player, itemId: string, slot: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	profile.ownedEquipment[itemId] = true
	for shipId in profile.ownedShips do
		local loadout = profile.loadouts[shipId]
		if loadout == nil then
			loadout = { equipment = {} }
			profile.loadouts[shipId] = loadout
		end
		loadout.equipment[slot] = itemId
	end
	push(player, "ownedEquipment", table.clone(profile.ownedEquipment))
end

function DataSystem.setExpansion(player: Player, level: number)
	local profile = DataSystem.getProfile(player)
	if profile then
		profile.galaxy.expansion = level
		push(player, "expansion", level)
	end
end

-- Marks an achievement claimed. False if it already was (so its reward is
-- only ever granted once).
function DataSystem.claimAchievement(player: Player, id: string): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false
	end
	local record = profile.achievements[id]
	if record and record.claimed then
		return false
	end
	profile.achievements[id] = { progress = (record and record.progress) or 0, claimed = true }
	return true
end

function DataSystem.grantCosmetic(player: Player, cosmeticId: string)
	local profile = DataSystem.getProfile(player)
	if profile then
		profile.ownedCosmetics[cosmeticId] = true
	end
end

-- Player settings a client may change (all booleans).
local BOOLEAN_SETTINGS = { stabilization = true, reducedEffects = true }

-- Saves a setting from the client. Unknown names and non-boolean values are
-- ignored.
function DataSystem.setSetting(player: Player, name: unknown, value: unknown)
	local profile = DataSystem.getProfile(player)
	if
		profile == nil
		or type(name) ~= "string"
		or not BOOLEAN_SETTINGS[name]
		or type(value) ~= "boolean"
	then
		return
	end
	(profile.settings :: any)[name] = value
	push(player, "settings", table.clone(profile.settings))
end

-- Records the tutorial step to show (0 = finished) and tells the client.
function DataSystem.setTutorialStep(player: Player, step: number)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	profile.tutorial.step = math.max(step, 1)
	profile.tutorial.done = step == 0
	push(player, "tutorialStep", step)
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

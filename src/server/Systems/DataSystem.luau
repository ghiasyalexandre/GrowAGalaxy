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
local DailyMath = require(ReplicatedStorage.Shared.Logic.DailyMath)
local ReceiptFlow = require(ReplicatedStorage.Shared.Logic.ReceiptFlow)
local RewardMath = require(ReplicatedStorage.Shared.Logic.RewardMath)
local HangarMath = require(ReplicatedStorage.Shared.Logic.HangarMath)
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
	push(player, "incomeRate", ProfileSchema.incomeRate(profile))
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

export type StarChanges = {
	typeId: string?,
	level: number?,
	pos: Types.Vec3?,
	slot: string?, -- with planet: put this planet in this orbit slot
	planet: string?,
}

-- Changes a star (already validated and paid for by the caller).
function DataSystem.updateStar(player: Player, id: string, changes: StarChanges)
	local profile = DataSystem.getProfile(player)
	local star = profile and profile.galaxy.stars[id]
	if profile == nil or star == nil then
		return
	end
	if changes.typeId then
		star.typeId = changes.typeId
	end
	if changes.level then
		star.level = changes.level
	end
	if changes.pos then
		star.pos = changes.pos
	end
	if changes.slot and changes.planet then
		star.planets[changes.slot] = changes.planet
	end
	pushIncome(player, profile)
end

-- Advances `dt` seconds of play for an online player:
--   * star income made in that time goes to "uncollected" (up to the cap),
--     multiplied by the star pass and by the star boost for the part of
--     `dt` the boost still covers (RewardMath.starIncome);
--   * with the Automatic Collection pass it moves straight to the wallet;
--   * boost timers count down (they only run while the player is online).
-- `passes` are the server-verified passes (MonetizationSystem).
function DataSystem.accrueIncome(player: Player, dt: number, passes: { [string]: boolean })
	local profile = DataSystem.getProfile(player)
	if profile == nil or dt <= 0 then
		return
	end
	local boosts = profile.boosts
	local rate = ProfileSchema.incomeRate(profile)
	if rate > 0 then
		local made = RewardMath.starIncome(rate, dt, boosts.star, passes)
		-- The cap grows with the permanent pass, not with a temporary boost.
		local cap = rate
			* RewardMath.permanent("star", passes)
			* Config.Economy.UNCOLLECTED_CAP_SECONDS
			* HangarMath.storageMultiplier(profile.hangar)
		local before = profile.uncollected
		profile.uncollected = StarMath.accrue(before, made, 1, cap)
		if RewardMath.autoCollect(passes) and profile.uncollected >= 1 then
			DataSystem.collectIncome(player)
			-- Counts as having collected once, for the tutorial.
			if (profile.stats.collections or 0) < 1 then
				DataSystem.addStat(player, "collections", 1)
			end
		elseif math.floor(profile.uncollected) ~= math.floor(before) then
			push(player, "uncollected", math.floor(profile.uncollected))
		end
	end
	local mining, star = boosts.mining, boosts.star
	if mining > 0 or star > 0 then
		boosts.mining = RewardMath.tick(mining, dt)
		boosts.star = RewardMath.tick(star, dt)
		-- The HUD counts down by itself; resync every 10 s and when one ends.
		local ended = (mining > 0 and boosts.mining == 0) or (star > 0 and boosts.star == 0)
		if ended or mining // 10 ~= boosts.mining // 10 or star // 10 ~= boosts.star // 10 then
			push(player, "boosts", table.clone(boosts))
		end
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

-- Records a hangar upgrade as built. The caller has already validated and
-- paid for it.
function DataSystem.grantHangar(player: Player, upgradeId: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	profile.hangar[upgradeId] = true
	pushIncome(player, profile)
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

-- Fulfils a developer product: its fixed reward and its PurchaseId are
-- written together (ReceiptFlow.applyTo). Returns "granted", "duplicate"
-- (already done for this PurchaseId) or "invalid".
function DataSystem.applyPurchase(player: Player, purchaseId: string, grants: any): string
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		error("profile not loaded")
	end
	local result = ReceiptFlow.applyTo(profile, purchaseId, grants)
	if result == "granted" then
		push(player, "stardust", profile.stardust)
		push(player, "boosts", table.clone(profile.boosts))
	end
	return result
end

-- Yields until the saved copy of the profile contains `purchaseId` (true),
-- or the session ends or `timeout` seconds pass (false). Asks ProfileStore
-- to save now rather than waiting for the next autosave.
function DataSystem.waitForSave(player: Player, purchaseId: string, timeout: number): boolean
	local session = sessions[player]
	local deadline = os.clock() + timeout
	local function saved(): boolean
		local data = session and session.LastSavedData
		return data ~= nil
			and type(data.receipts) == "table"
			and table.find(data.receipts, purchaseId) ~= nil
	end
	while session and session:IsActive() and os.clock() < deadline do
		if saved() then
			return true
		end
		session:Save()
		local waitUntil = math.min(os.clock() + 10, deadline)
		while os.clock() < waitUntil and session:IsActive() and not saved() do
			task.wait(0.25)
		end
	end
	return saved()
end

-- Remembers what Roblox last said about the player's passes (a fallback
-- while a later check fails).
function DataSystem.setVerifiedPasses(player: Player, passes: { [string]: boolean })
	local profile = DataSystem.getProfile(player)
	if profile then
		profile.verifiedPasses = table.clone(passes)
	end
end

-- Tells the client which passes are active (Store and HUD).
function DataSystem.showPasses(player: Player, passes: { [string]: boolean })
	push(player, "passes", table.clone(passes))
end

-- Claims today's daily prize (Config.Daily) if it hasn't been claimed.
-- Returns the calendar day claimed and its prize, or nil. Prizes are fixed:
-- no multiplier applies.
function DataSystem.claimDaily(player: Player, today: number): (number?, any)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil, nil
	end
	local day, record = DailyMath.claim(profile.daily, today)
	if day == nil then
		return nil, nil
	end
	profile.daily = record
	local prize = Config.Daily.PRIZES[day]
	if prize.stardust then
		DataSystem.addStardust(player, prize.stardust)
	elseif prize.boost then
		local source = prize.boost.source
		profile.boosts[source] = RewardMath.extend(profile.boosts[source], prize.boost.seconds)
		push(player, "boosts", table.clone(profile.boosts))
	end
	push(player, "daily", table.clone(profile.daily))
	return day, prize
end

-- Grants a raid reward (Config.Raids): fixed Stardust, plus boost time
-- added to any running boost. No multiplier applies.
function DataSystem.grantRaidReward(player: Player, reward: any)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	DataSystem.addStardust(player, reward.stardust)
	if reward.boost then
		local source = reward.boost.source
		profile.boosts[source] = RewardMath.extend(profile.boosts[source], reward.boost.seconds)
		push(player, "boosts", table.clone(profile.boosts))
	end
end

-- Player settings a client may change (all booleans).
local BOOLEAN_SETTINGS = { stabilization = true, reducedEffects = true, pvp = true }

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

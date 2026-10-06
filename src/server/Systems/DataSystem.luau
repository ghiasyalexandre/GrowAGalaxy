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
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local HatchMath = require(ReplicatedStorage.Shared.Logic.HatchMath)
local Entitlements = require(script.Parent.Parent.Util.Entitlements)
local ReceiptFlow = require(ReplicatedStorage.Shared.Logic.ReceiptFlow)
local RewardMath = require(ReplicatedStorage.Shared.Logic.RewardMath)
local HangarMath = require(ReplicatedStorage.Shared.Logic.HangarMath)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local OfflineMath = require(ReplicatedStorage.Shared.Logic.OfflineMath)
local PlanetInventory = require(ReplicatedStorage.Shared.Logic.PlanetInventory)
local ProfileSchema = require(ReplicatedStorage.Shared.Logic.ProfileSchema)
local ProfileStore = require(ServerScriptService.Vendor.ProfileStore) :: any
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local WheelMath = require(ReplicatedStorage.Shared.Logic.WheelMath)
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
-- os.clock() when each online player's income was last added up (settleIncome).
local settledAt: { [Player]: number } = {}

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

-- Offline earnings (Logic/OfflineMath): what the player's stars made while
-- they were away, at their rate now with the passes Roblox last confirmed
-- and their trail (boosts don't run offline), up to OFFLINE_CAP_SECONDS,
-- straight into the wallet. Then they count as online from now.
local payOffline: (player: Player, profile: Profile) -> ()

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
	settledAt[player] = os.clock()
	payOffline(player, session.Data)
	DataSystem.profileLoaded:Fire(player, session.Data)
end

local function push(player: Player, field: string, value: any)
	Net.ProfileChanged:FireClient(player, field, value)
end

payOffline = function(player: Player, profile: Profile)
	local now = os.time()
	local rate = ProfileSchema.incomeRate(profile)
		* RewardMath.permanent("star", profile.verifiedPasses)
		* ProfileSchema.trailMultiplier(profile)
	local amount, seconds = OfflineMath.earned(rate, profile.lastOnline, now)
	profile.lastOnline = now
	if amount <= 0 then
		return
	end
	profile.stardust += amount
	DataSystem.addStat(player, "offlineStardust", amount)
	local hours = math.floor(seconds / 3600)
	local away = if hours >= 1 then `{hours} h` else `{math.floor(seconds / 60)} min`
	-- After the client has loaded, so the message isn't missed.
	task.delay(6, function()
		if player.Parent then
			push(player, "stardust", profile.stardust)
			Notify.send(
				player,
				`Welcome back! Your stars made {amount} Stardust while you were away ({away}{if seconds
						>= Config.Economy.OFFLINE_CAP_SECONDS
					then ", the 3-day maximum"
					else ""}).`
			)
		end
	end)
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
}

-- Changes a star (already validated and paid for by the caller). Income up
-- to now is settled at the old rate first.
function DataSystem.updateStar(player: Player, id: string, changes: StarChanges)
	local profile = DataSystem.getProfile(player)
	local star = profile and profile.galaxy.stars[id]
	if profile == nil or star == nil then
		return
	end
	DataSystem.settleIncome(player)
	if changes.typeId then
		star.typeId = changes.typeId
	end
	if changes.level then
		star.level = changes.level
	end
	if changes.pos then
		star.pos = changes.pos
	end
	pushIncome(player, profile)
end

local function pushPlanets(player: Player, profile: Profile)
	push(player, "planets", ProfileSchema.planetsView(profile))
	pushIncome(player, profile)
end

-- Adds a new planet to the player's inventory (from a hatch or a grant) and
-- returns its id. The caller has already validated and paid for it.
function DataSystem.addPlanet(player: Player, typeId: string, level: number?): string?
	local profile = DataSystem.getProfile(player)
	if profile == nil or Config.Planets.BY_ID[typeId] == nil then
		return nil
	end
	local id, nextId = PlanetInventory.newId(profile.nextPlanetId)
	profile.nextPlanetId = nextId
	profile.planets[id] = {
		typeId = typeId,
		level = math.clamp(level or 1, 1, Config.Planets.MAX_LEVEL),
	}
	pushPlanets(player, profile)
	return id
end

-- Puts an owned planet into an orbit of one of the player's stars, moving it
-- there in one step if it orbits elsewhere. Income up to now is settled
-- first. Returns (ok, problem) as PlanetInventory.equip; the caller rebuilds
-- the stars involved.
function DataSystem.equipPlanet(
	player: Player,
	planetId: string,
	starId: string,
	slot: number
): (boolean, PlanetInventory.Problem?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "UnknownPlanet"
	end
	local ok, problem =
		PlanetInventory.check(profile.planets, profile.galaxy.stars, planetId, starId, slot)
	if not ok then
		return false, problem :: PlanetInventory.Problem?
	end
	DataSystem.settleIncome(player)
	PlanetInventory.equip(profile.planets, profile.galaxy.stars, planetId, starId, slot)
	pushPlanets(player, profile)
	return true, nil
end

-- Takes a planet out of orbit into the inventory (income settled first).
function DataSystem.unequipPlanet(player: Player, planetId: string): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or profile.planets[planetId] == nil then
		return false
	end
	DataSystem.settleIncome(player)
	PlanetInventory.unequip(profile.planets, planetId)
	pushPlanets(player, profile)
	return true
end

export type EggProblem = "NoProfile" | "Full" | "Poor"

-- Buys one planet egg in a single step: checks room (Config.Eggs
-- MAX_UNHATCHED) and the balance, takes `price`, counts the purchase (later
-- mystery eggs cost more) and saves the egg with its planet already chosen.
-- Nothing yields in between, so the Stardust and the egg are saved together
-- or not at all. Returns the new egg id, or nil and why.
function DataSystem.buyEgg(
	player: Player,
	outcome: string,
	guaranteed: boolean,
	price: number
): (string?, EggProblem?)
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(price)
	if profile == nil or whole == nil then
		return nil, "NoProfile"
	end
	if EggMath.held(profile.eggs, profile.hatches) >= Config.Eggs.MAX_UNHATCHED then
		return nil, "Full"
	end
	if profile.stardust < whole then
		return nil, "Poor"
	end
	profile.stardust -= whole
	profile.eggsBought += 1
	local id = `e{profile.nextEggId}`
	profile.nextEggId += 1
	profile.eggs[id] = { outcome = outcome, guaranteed = guaranteed, boughtAt = os.time() }
	push(player, "stardust", profile.stardust)
	push(player, "eggsBought", profile.eggsBought)
	push(player, "eggs", ProfileSchema.eggsView(profile))
	return id, nil
end

-- Puts a waiting egg into an incubator chamber ("1".."HATCH_SLOTS") in one
-- step: the egg leaves the inventory and the hatch record (same planet,
-- start and end times from its rarity) is saved together. Returns the
-- hatch, or nil if the egg isn't the player's or the chamber isn't free.
function DataSystem.startHatch(player: Player, eggId: string, chamber: number): Types.HatchRecord?
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil
	end
	local hatch = HatchMath.begin(profile.eggs, profile.hatches, eggId, chamber, os.time())
	if hatch then
		push(player, "eggs", ProfileSchema.eggsView(profile))
		push(player, "hatches", ProfileSchema.hatchesView(profile))
	end
	return hatch
end

-- Finishes a hatch whose time is up, in one step: the hatch record goes and
-- the planet joins the inventory, so it is granted exactly once and the
-- chamber is free again. Returns the new planet's id and type, or nil if
-- the chamber has nothing ready (`now` is unix seconds).
function DataSystem.completeHatch(player: Player, chamber: string, now: number): (string?, string?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil, nil
	end
	local typeId = HatchMath.finish(profile.hatches, chamber, now)
	if typeId == nil then
		return nil, nil
	end
	local id, nextId = PlanetInventory.newId(profile.nextPlanetId)
	profile.nextPlanetId = nextId
	profile.planets[id] = { typeId = typeId, level = 1 }
	profile.stats.planetsHatched = (profile.stats.planetsHatched or 0) + 1
	push(player, "hatches", ProfileSchema.hatchesView(profile))
	pushPlanets(player, profile)
	DataSystem.statChanged:Fire(player, "planetsHatched")
	return id, typeId
end

-- The daily wheel (Config.Wheel): if a free spin is ready at `now` (unix
-- seconds), records the spin (next one a COOLDOWN later), remembers the
-- prize and adds its Stardust, all in one step and before the client's
-- animation starts. The prize is fixed: no multiplier applies. Returns
-- whether it spun.
function DataSystem.spinWheel(player: Player, prizeIndex: number, now: number): boolean
	local profile = DataSystem.getProfile(player)
	local prize = Config.Wheel.PRIZES[prizeIndex]
	if profile == nil or prize == nil then
		return false
	end
	local nextSpin = WheelMath.spin(profile.wheel.nextSpin, now)
	if nextSpin == nil then
		return false
	end
	profile.wheel.nextSpin = nextSpin
	profile.wheel.lastPrize = prizeIndex
	profile.stardust += prize.stardust
	push(player, "stardust", profile.stardust)
	push(player, "wheel", table.clone(profile.wheel))
	return true
end

-- Sets an owned planet's level (already validated and paid for by the
-- caller), settling income first.
function DataSystem.setPlanetLevel(player: Player, planetId: string, level: number)
	local profile = DataSystem.getProfile(player)
	local planet = profile and profile.planets[planetId]
	if profile == nil or planet == nil then
		return
	end
	DataSystem.settleIncome(player)
	planet.level = math.clamp(level, 1, Config.Planets.MAX_LEVEL)
	pushPlanets(player, profile)
end

-- Advances `dt` seconds of play for an online player:
--   * star income made in that time goes to "uncollected" (up to the cap),
--     multiplied by the star pass and by the star boost for the part of
--     `dt` the boost still covers (RewardMath.starIncome);
--   * with the Automatic Collection pass it moves straight to the wallet;
--   * boost timers count down (they only run while the player is online).
-- `passes` are the server-verified passes (MonetizationSystem).
local function accrue(player: Player, profile: Profile, dt: number, passes: { [string]: boolean })
	-- Seen online now: offline earnings count from the last of these.
	profile.lastOnline = os.time()
	local boosts = profile.boosts
	local rate = ProfileSchema.incomeRate(profile)
	if rate > 0 then
		local made = RewardMath.starIncome(
			rate,
			dt,
			boosts.star,
			passes,
			ProfileSchema.trailMultiplier(profile)
		)
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

-- Adds up an online player's income since the last settlement at the
-- current rate. StarSystem calls it every INCOME_TICK; anything that changes
-- the rate (star, planet or arrangement changes) calls it first, so the old
-- rate is paid exactly up to the change and the new one from then on.
function DataSystem.settleIncome(player: Player)
	local profile = DataSystem.getProfile(player)
	local last = settledAt[player]
	if profile == nil or last == nil then
		return
	end
	local now = os.clock()
	settledAt[player] = now
	local dt = now - last
	if dt > 0 then
		accrue(player, profile, dt, Entitlements.passes(player))
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
	profile.equipmentLevels[itemId] = profile.equipmentLevels[itemId] or 1
	for shipId in profile.ownedShips do
		local loadout = profile.loadouts[shipId]
		if loadout == nil then
			loadout = { equipment = {} }
			profile.loadouts[shipId] = loadout
		end
		loadout.equipment[slot] = itemId
	end
	push(player, "ownedEquipment", table.clone(profile.ownedEquipment))
	push(player, "equipmentLevels", table.clone(profile.equipmentLevels))
end

-- Raises an owned equipment item one level (the caller has paid).
function DataSystem.levelEquipment(player: Player, itemId: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or not profile.ownedEquipment[itemId] then
		return
	end
	local level = profile.equipmentLevels[itemId] or 1
	profile.equipmentLevels[itemId] = math.min(level + 1, Config.Equipment.MAX_LEVEL)
	push(player, "equipmentLevels", table.clone(profile.equipmentLevels))
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
local BOOLEAN_SETTINGS = {
	stabilization = true,
	reducedEffects = true,
	pvp = true,
	showBounds = true,
	showControls = true,
}
-- Player settings that are volumes, 0 to 1.
local VOLUME_SETTINGS = { sfxVolume = true, musicVolume = true }

-- Saves a setting from the client. Unknown names and values of the wrong
-- type are ignored; volumes are clamped to 0..1.
function DataSystem.setSetting(player: Player, name: unknown, value: unknown)
	local profile = DataSystem.getProfile(player)
	if profile == nil or type(name) ~= "string" then
		return
	end
	if BOOLEAN_SETTINGS[name] and type(value) == "boolean" then
		(profile.settings :: any)[name] = value
	elseif VOLUME_SETTINGS[name] and type(value) == "number" and value == value then
		(profile.settings :: any)[name] = math.clamp(value, 0, 1)
	else
		return
	end
	push(player, "settings", table.clone(profile.settings))
end

-- Sets an owned ship's colours (Config.Paint): swatch colours, or nil for
-- the standard laser / engines. False if the ship isn't owned or a colour
-- isn't offered.
function DataSystem.setShipLook(
	player: Player,
	shipId: string,
	laserColor: string?,
	boostColor: string?
): boolean
	local profile = DataSystem.getProfile(player)
	local loadout = profile and profile.loadouts[shipId]
	if profile == nil or loadout == nil or not profile.ownedShips[shipId] then
		return false
	end
	for _, color in { laserColor, boostColor } do
		if color ~= nil and not ProfileSchema.validColor(color) then
			return false
		end
	end
	loadout.laserColor = laserColor
	loadout.boostColor = boostColor
	push(player, "looks", ProfileSchema.looks(profile))
	return true
end

-- Redeems a code (Config.Codes, already upper-cased and trimmed) for the
-- player: grants its fixed reward and records it. Returns the code's
-- definition, or nil and why not.
function DataSystem.redeemCode(player: Player, code: string): (any, string?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil, "Your save isn't loaded yet."
	end
	local def = Config.Codes.BY_CODE[code]
	if def == nil then
		return nil, "That code doesn't exist."
	end
	if profile.redeemedCodes[code] then
		return nil, "You've already redeemed that code."
	end
	profile.redeemedCodes[code] = true
	if def.stardust then
		DataSystem.addStardust(player, def.stardust)
	end
	local boost = def.boost
	if boost then
		profile.boosts[boost.source] =
			RewardMath.extend(profile.boosts[boost.source], boost.seconds)
		push(player, "boosts", table.clone(profile.boosts))
	end
	return def, nil
end

-- Gives the player a trail (the caller has paid).
function DataSystem.grantTrail(player: Player, trailId: string)
	local profile = DataSystem.getProfile(player)
	if profile then
		profile.ownedTrails[trailId] = true
		push(player, "ownedTrails", table.clone(profile.ownedTrails))
	end
end

-- Equips an owned trail, or none with nil. False if it isn't owned.
function DataSystem.equipTrail(player: Player, trailId: string?): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or (trailId ~= nil and not profile.ownedTrails[trailId]) then
		return false
	end
	profile.trail = trailId
	push(player, "trail", trailId or false)
	return true
end

-- Puts an owned ship on show in the Showcase Dock, or takes it off. Returns
-- false (and changes nothing) when it isn't owned or every slot is taken.
function DataSystem.setShowcase(player: Player, shipId: string, on: boolean): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or not profile.ownedShips[shipId] then
		return false
	end
	local index = table.find(profile.showcase, shipId)
	if on and index == nil then
		if #profile.showcase >= Config.Paint.SHOWCASE_SLOTS then
			return false
		end
		table.insert(profile.showcase, shipId)
	elseif not on and index then
		table.remove(profile.showcase, index)
	end
	push(player, "showcase", table.clone(profile.showcase))
	return true
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
			DataSystem.settleIncome(player)
			session:EndSession()
		end
		settledAt[player] = nil
	end)
end

return DataSystem

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
local EconomyAnalytics = require(script.Parent.Parent.Util.EconomyAnalytics)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Util.Format)
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
-- Each online player's recent production, for their reward rate R
-- (EconomyMath.track), and the economy view last sent to them.
local windows: { [Player]: EconomyMath.Window } = {}
local sentEconomy: { [Player]: Types.EconomyView } = {}

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

-- Offline earnings (Logic/OfflineMath): OFFLINE_RATE of what the player's
-- stars and planets made while they were away, at their production B (with
-- trail and Refinery) and the star pass Roblox last confirmed (boosts don't
-- run offline), up to OFFLINE_CAP_SECONDS (raised by the Silo), straight
-- into the wallet. Then they count as online from now.
local payOffline: (player: Player, profile: Profile) -> ()

-- Today's reward rate R: snapshotted from the last session's production on
-- the first visit of each reward (UTC) day. A brand-new account's first
-- day uses 1.
local function refreshReward(profile: Profile, now: number): boolean
	local day = DailyMath.today(now)
	local economy = profile.economy
	if economy.rewardDay == day then
		return false
	end
	economy.rewardDay = day
	economy.reward = EconomyMath.snapshot(economy.recent)
	return true
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
	settledAt[player] = os.clock()
	windows[player] = {}
	refreshReward(session.Data, os.time())
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
	local capMultiplier = HangarMath.storageMultiplier(profile.hangar)
	local cap = Config.Economy.OFFLINE_CAP_SECONDS * capMultiplier
	local amount, seconds = OfflineMath.earned(rate, profile.lastOnline, now, capMultiplier)
	profile.lastOnline = now
	if amount <= 0 then
		return
	end
	profile.stardust += amount
	EconomyAnalytics.source(player, amount, profile.stardust, "star_offline")
	DataSystem.addStat(player, "offlineStardust", amount)
	local hours = math.floor(seconds / 3600)
	local away = if hours >= 1 then `{hours} h` else `{math.floor(seconds / 60)} min`
	-- After the client has loaded, so the message isn't missed.
	task.delay(6, function()
		if player.Parent then
			push(player, "stardust", profile.stardust)
			Notify.send(
				player,
				`Welcome back! Your stars made {Format.abbreviate(amount)} Stardust while you were away ({away}{if seconds
						>= cap
					then `, the {math.floor(cap / 3600)} h maximum`
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

-- Adds Stardust to the wallet; `sku` names where it came from (analytics,
-- Util/EconomyAnalytics).
function DataSystem.addStardust(player: Player, amount: number, sku: string?): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil then
		return false
	end
	profile.stardust += whole
	EconomyAnalytics.source(player, whole, profile.stardust, sku or "other")
	push(player, "stardust", profile.stardust)
	return true
end

-- Deducts Stardust only if the player can afford all of it; `sku` names
-- what it bought (analytics).
function DataSystem.spendStardust(player: Player, amount: number, sku: string?): boolean
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(amount)
	if profile == nil or whole == nil or profile.stardust < whole then
		return false
	end
	profile.stardust -= whole
	EconomyAnalytics.sink(player, whole, profile.stardust, sku or "other")
	push(player, "stardust", profile.stardust)
	return true
end

-- Tells the owner their economy view (H, R, egg price, next BuildIndex)
-- when it changed.
local function pushEconomy(player: Player, profile: Profile)
	local view = ProfileSchema.economyView(profile)
	local last = sentEconomy[player]
	if
		last == nil
		or last.eggPrice ~= view.eggPrice
		or last.reward ~= view.reward
		or last.nextBuild ~= view.nextBuild
		or math.floor(last.high) ~= math.floor(view.high)
	then
		sentEconomy[player] = view
		push(player, "economy", view)
	end
end

-- Production changed: raise H if it's a new best and tell the owner.
local function pushIncome(player: Player, profile: Profile)
	local rate = ProfileSchema.incomeRate(profile)
	profile.economy.high = math.max(profile.economy.high, rate)
	push(player, "incomeRate", rate)
	pushEconomy(player, profile)
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
	-- Its BuildIndex, never reused.
	star.build = galaxy.nextBuild
	galaxy.nextBuild += 1
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
		tier = 1,
		paid = 0,
		spent = 0,
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

export type EggProblem = "NoProfile" | "Full" | "Storage" | "Poor" | "Empty" | "Top"

-- Whether one more planet has room: owned planets plus every egg kept or
-- incubating (each reserves a place) stay under MAX_PLANETS.
function DataSystem.storageFree(profile: Profile): boolean
	return PlanetInventory.count(profile.planets) + EggMath.held(profile.eggs, profile.hatches)
		< Config.Planets.MAX_PLANETS
end

-- Pays `price` and puts a freshly rolled egg (its planet and tier chosen by
-- EggSystem) on the Egg Lab's pedestal, replacing any egg there, in one
-- step: the Stardust and the new egg are saved together or not at all.
function DataSystem.rollEgg(
	player: Player,
	outcome: string,
	tier: number,
	price: number
): (boolean, EggProblem?)
	local profile = DataSystem.getProfile(player)
	local whole = wholePositive(price)
	if profile == nil or whole == nil or Config.Planets.BY_ID[outcome] == nil then
		return false, "NoProfile"
	end
	if not DataSystem.storageFree(profile) then
		return false, "Storage"
	end
	if profile.stardust < whole then
		return false, "Poor"
	end
	profile.stardust -= whole
	EconomyAnalytics.sink(
		player,
		whole,
		profile.stardust,
		if profile.eggLab.current then "egg_reroll" else "egg_roll"
	)
	profile.eggLab.current = { outcome = outcome, tier = tier, paid = whole }
	profile.eggLab.rolls += 1
	push(player, "stardust", profile.stardust)
	push(player, "eggLab", ProfileSchema.eggLabView(profile))
	return true, nil
end

-- Moves the pedestal egg into the player's eggs (ready to incubate) in one
-- step, counting it as kept (later eggs cost more). Returns its id, or nil
-- and why ("Empty": nothing rolled; "Full": too many unhatched eggs).
function DataSystem.keepEgg(player: Player): (string?, EggProblem?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil, "NoProfile"
	end
	local current = profile.eggLab.current
	if current == nil then
		return nil, "Empty"
	end
	if EggMath.held(profile.eggs, profile.hatches) >= Config.Eggs.MAX_UNHATCHED then
		return nil, "Full"
	end
	if not DataSystem.storageFree(profile) then
		return nil, "Storage"
	end
	local id = `e{profile.nextEggId}`
	profile.nextEggId += 1
	profile.eggs[id] = {
		outcome = current.outcome,
		tier = current.tier,
		guaranteed = false,
		boughtAt = os.time(),
		paid = current.paid,
	}
	profile.eggLab.current = nil
	profile.eggsBought += 1
	pushEconomy(player, profile)
	push(player, "eggsBought", profile.eggsBought)
	push(player, "eggs", ProfileSchema.eggsView(profile))
	push(player, "eggLab", ProfileSchema.eggLabView(profile))
	return id, nil
end

-- Gives the free tutorial egg once (Config.Eggs.TUTORIAL_EGG_SECONDS into
-- a first session): the cheapest Common type, tier 1, nothing paid (so it
-- sells for nothing). Returns its id, or nil if it was already given.
function DataSystem.grantTutorialEgg(player: Player): string?
	local profile = DataSystem.getProfile(player)
	if profile == nil or profile.tutorialEgg then
		return nil
	end
	local P = Config.Planets
	local cheapest: string? = nil
	for _, typeId in P.BY_RARITY.Common do
		if cheapest == nil or P.BY_ID[typeId].income < P.BY_ID[cheapest].income then
			cheapest = typeId
		end
	end
	if cheapest == nil then
		return nil
	end
	profile.tutorialEgg = true
	local id = `e{profile.nextEggId}`
	profile.nextEggId += 1
	profile.eggs[id] = {
		outcome = cheapest,
		tier = 1,
		guaranteed = false,
		boughtAt = os.time(),
		paid = 0,
	}
	push(player, "eggs", ProfileSchema.eggsView(profile))
	return id
end

-- Pays `cost` and raises the Egg Lab one level, in one step. "Top": it's
-- already at the last level.
function DataSystem.upgradeEggLab(player: Player, cost: number): (boolean, EggProblem?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "NoProfile"
	end
	if profile.eggLab.level >= #Config.Eggs.LAB_LEVELS then
		return false, "Top"
	end
	if profile.stardust < cost then
		return false, "Poor"
	end
	profile.stardust -= cost
	EconomyAnalytics.sink(player, cost, profile.stardust, "lab_level")
	profile.eggLab.level += 1
	EconomyAnalytics.progression(player, "labLevel", profile.eggLab.level)
	push(player, "stardust", profile.stardust)
	push(player, "eggLab", ProfileSchema.eggLabView(profile))
	return true, nil
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

export type HatchResult = {
	typeId: string,
	tier: number,
	chamber: string,
	at: number,
	planetId: string?, -- kept: the new planet's id
	sold: number?, -- sold on hatching: the Stardust it paid
	reason: string?, -- why it was sold: "auto" or "full"
	new: boolean, -- a type the player had never owned before
}

-- Finishes every hatch whose time is up at `now` (unix seconds), in the
-- order they ended, in one step (Logic/HatchMath). With the autoIncubate
-- setting a freed chamber takes the oldest waiting egg from the moment it
-- freed, so incubation carries on offline. Each hatched planet is granted
-- exactly once: it joins the inventory (its place was reserved when the
-- egg was kept, so a hatch is never sold for lack of room), or is sold at
-- once (paying its sale value) when the player chose to auto-sell its
-- rarity (and, with keepNewTypes, it isn't a type they've never had).
function DataSystem.advanceHatches(player: Player, now: number): { HatchResult }
	local profile = DataSystem.getProfile(player)
	if profile == nil or next(profile.hatches) == nil then
		return {}
	end
	local settings = profile.settings
	local hatched = HatchMath.advance(profile.eggs, profile.hatches, now, settings.autoIncubate)
	if #hatched == 0 then
		return {}
	end
	local results: { HatchResult } = {}
	local earned = 0
	for _, item in hatched do
		local def = Config.Planets.BY_ID[item.typeId]
		local isNew = not profile.discovered[item.typeId]
		profile.discovered[item.typeId] = true
		local result: HatchResult = {
			typeId = item.typeId,
			tier = item.tier,
			chamber = item.chamber,
			at = item.at,
			new = isNew,
		}
		local auto = settings.autoSell[def.rarity] == true and not (settings.keepNewTypes and isNew)
		-- What it cost; an egg from before economy v2 keeps the old value.
		local record: Types.PlanetRecord = {
			typeId = item.typeId,
			level = 1,
			tier = item.tier,
			paid = item.paid or 0,
			spent = 0,
			legacy = if item.paid == nil then Config.Planets.LEGACY_SELL_VALUE[def.rarity] else nil,
		}
		if auto then
			local value = PlanetInventory.sellValue(record)
			earned += value
			result.sold = value
			result.reason = "auto"
		else
			local id, nextId = PlanetInventory.newId(profile.nextPlanetId)
			profile.nextPlanetId = nextId
			profile.planets[id] = record
			result.planetId = id
		end
		profile.stats.planetsHatched = (profile.stats.planetsHatched or 0) + 1
		table.insert(results, result)
	end
	profile.stardust += earned
	if earned > 0 then
		EconomyAnalytics.source(player, earned, profile.stardust, "planet_sale")
		push(player, "stardust", profile.stardust)
	end
	push(player, "eggs", ProfileSchema.eggsView(profile))
	push(player, "hatches", ProfileSchema.hatchesView(profile))
	push(player, "discovered", table.clone(profile.discovered))
	pushPlanets(player, profile)
	DataSystem.statChanged:Fire(player, "planetsHatched")
	return results
end

-- Puts the oldest waiting eggs into every free chamber now. Returns how
-- many started.
function DataSystem.fillChambers(player: Player): number
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return 0
	end
	local started = HatchMath.fill(profile.eggs, profile.hatches, os.time())
	if started > 0 then
		push(player, "eggs", ProfileSchema.eggsView(profile))
		push(player, "hatches", ProfileSchema.hatchesView(profile))
	end
	return started
end

-- Sells planets from the inventory in one step: every id that may be sold
-- (PlanetInventory.canSell: owned, not in orbit, not locked) is removed and
-- pays its sale value; the rest are left alone. Returns how many sold and
-- the Stardust paid.
function DataSystem.sellPlanets(player: Player, ids: { string }): (number, number)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return 0, 0
	end
	local sold, total = 0, 0
	for _, id in ids do
		if PlanetInventory.canSell(profile.planets, id) then
			total += PlanetInventory.sellValue(profile.planets[id])
			profile.planets[id] = nil
			sold += 1
		end
	end
	if sold > 0 then
		profile.stardust += total
		EconomyAnalytics.source(player, total, profile.stardust, "planet_sale")
		push(player, "stardust", profile.stardust)
		push(player, "planets", ProfileSchema.planetsView(profile))
		DataSystem.addStat(player, "planetsSold", sold)
	end
	return sold, total
end

-- Locks (protects from any selling) or unlocks an owned planet.
function DataSystem.setPlanetLocked(player: Player, planetId: string, locked: boolean): boolean
	local profile = DataSystem.getProfile(player)
	local planet = if profile then profile.planets[planetId] else nil
	if profile == nil or planet == nil then
		return false
	end
	planet.locked = if locked then true else nil
	push(player, "planets", ProfileSchema.planetsView(profile))
	return true
end

-- Rearranges planets into the best-earning layout (PlanetInventory.best),
-- settling income first. Returns the ids of the stars whose planets changed.
function DataSystem.equipBest(player: Player): { string }
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return {}
	end
	local layout = PlanetInventory.best(profile.planets, profile.galaxy.stars)
	local changed: { [string]: boolean } = {}
	local moves = 0
	for id, planet in profile.planets do
		local target = layout[id]
		if
			planet.star ~= (if target then target.star else nil)
			or planet.slot ~= (if target then target.slot else nil)
		then
			moves += 1
		end
	end
	if moves == 0 then
		return {}
	end
	DataSystem.settleIncome(player)
	for id, planet in profile.planets do
		local target = layout[id]
		if
			planet.star ~= (if target then target.star else nil)
			or planet.slot ~= (if target then target.slot else nil)
		then
			if planet.star then
				changed[planet.star] = true
			end
			if target then
				changed[target.star] = true
			end
			planet.star = if target then target.star else nil
			planet.slot = if target then target.slot else nil
		end
	end
	pushPlanets(player, profile)
	local list: { string } = {}
	for starId in changed do
		table.insert(list, starId)
	end
	return list
end

-- Switches a built, toggleable hangar upgrade (Config.Hangar `toggle`)
-- off or on. False for anything else.
function DataSystem.setHangarOff(player: Player, id: unknown, off: unknown): boolean
	local profile = DataSystem.getProfile(player)
	local def = if type(id) == "string" then Config.Hangar.BY_ID[id] else nil
	if
		profile == nil
		or def == nil
		or not def.toggle
		or not profile.hangar[def.id]
		or type(off) ~= "boolean"
	then
		return false
	end
	if off then
		profile.hangarOff[def.id] = true
	else
		profile.hangarOff[def.id] = nil
	end
	push(player, "hangarOff", table.clone(profile.hangarOff))
	return true
end

-- Sets the hangar highlight colour (a Config.Hangar.HIGHLIGHT_COLORS id, or
-- "" for the region's own). False for anything else.
function DataSystem.setHangarColor(player: Player, id: unknown): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or type(id) ~= "string" then
		return false
	end
	if id == "" then
		profile.hangarColor = nil
	else
		local known = false
		for _, choice in Config.Hangar.HIGHLIGHT_COLORS do
			known = known or choice.id == id
		end
		if not known then
			return false
		end
		profile.hangarColor = id
	end
	push(player, "hangarColor", profile.hangarColor)
	return true
end

-- Turns automatic selling of newly hatched planets of `rarity` on or off
-- (only Config.Planets.AUTO_SELL_RARITIES).
function DataSystem.setAutoSell(player: Player, rarity: unknown, on: unknown): boolean
	local profile = DataSystem.getProfile(player)
	if
		profile == nil
		or type(rarity) ~= "string"
		or type(on) ~= "boolean"
		or table.find(Config.Planets.AUTO_SELL_RARITIES, rarity) == nil
	then
		return false
	end
	if on then
		profile.settings.autoSell[rarity] = true
	else
		profile.settings.autoSell[rarity] = nil
	end
	push(player, "settings", table.clone(profile.settings))
	return true
end

-- The daily wheel (Config.Wheel): if the free spin is ready at `now` (unix
-- seconds), records the spin (next one a COOLDOWN later), remembers the
-- prize and adds its Stardust (its minutes of reward rate R), all in one
-- step and before the client's animation starts. Returns the Stardust won,
-- or nil if it didn't spin.
function DataSystem.spinWheel(player: Player, prizeIndex: number, now: number): number?
	local profile = DataSystem.getProfile(player)
	local prize = Config.Wheel.PRIZES[prizeIndex]
	if profile == nil or prize == nil then
		return nil
	end
	local nextSpin = WheelMath.spin(profile.wheel.nextSpin, now)
	if nextSpin == nil then
		return nil
	end
	profile.wheel.nextSpin = nextSpin
	profile.wheel.lastPrize = prizeIndex
	local amount = EconomyMath.reward(prize.minutes, DataSystem.rewardRate(player))
	profile.stardust += amount
	EconomyAnalytics.source(player, amount, profile.stardust, "wheel_prize")
	push(player, "stardust", profile.stardust)
	push(player, "wheel", table.clone(profile.wheel))
	return amount
end

-- The player's reward rate R for today (refreshed if a new reward day has
-- begun), at least 1.
function DataSystem.rewardRate(player: Player): number
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return 1
	end
	if refreshReward(profile, os.time()) then
		pushEconomy(player, profile)
	end
	return profile.economy.reward
end

-- Stardust worth `minutes` of the player's reward rate (at least
-- `minimum`), added with analytics `sku`. Returns the amount.
function DataSystem.grantMinutes(
	player: Player,
	minutes: number,
	minimum: number?,
	sku: string
): number
	local amount = EconomyMath.reward(minutes, DataSystem.rewardRate(player), minimum)
	DataSystem.addStardust(player, amount, sku)
	return amount
end

-- Sets an owned planet's level (already validated and paid for by the
-- caller, `paid` Stardust, recorded for its sale value), settling income
-- first.
function DataSystem.setPlanetLevel(player: Player, planetId: string, level: number, paid: number?)
	local profile = DataSystem.getProfile(player)
	local planet = profile and profile.planets[planetId]
	if profile == nil or planet == nil then
		return
	end
	DataSystem.settleIncome(player)
	planet.level = math.clamp(level, 1, Config.Planets.MAX_LEVEL)
	planet.spent = (planet.spent or 0) + math.max(paid or 0, 0)
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
	-- R's window: production B (no passes or boosts) while online.
	local window = windows[player]
	if window then
		profile.economy.recent = EconomyMath.track(window, rate, dt, os.clock())
	end
	profile.economy.high = math.max(profile.economy.high, rate)
	if refreshReward(profile, os.time()) then
		pushEconomy(player, profile)
	end
	if rate > 0 then
		-- B already includes the trail and the Refinery.
		local made = RewardMath.starIncome(rate, dt, boosts.star, passes, nil)
		-- The tank holds UNCOLLECTED_CAP_SECONDS of permanent income (with
		-- the star pass, not a temporary boost); the Silo raises it.
		local cap = EconomyMath.tankCap(
			rate * RewardMath.permanent("star", passes),
			HangarMath.storageMultiplier(profile.hangar)
		)
		-- The collector's tank shows uncollected / cap (MachineController).
		if player:GetAttribute("UncollectedCap") ~= cap then
			player:SetAttribute("UncollectedCap", cap)
		end
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
	DataSystem.addStardust(player, whole, "star_online")
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

local function pushShipLevels(player: Player, profile: Profile)
	push(player, "shipLevels", ProfileSchema.shipLevels(profile))
end

-- Gives the player a ship. It comes with no equipment: every ship has its
-- own upgrades (Config.Equipment).
function DataSystem.grantShip(player: Player, shipId: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or profile.ownedShips[shipId] then
		return
	end
	profile.ownedShips[shipId] = true
	profile.loadouts[shipId] = { equipment = {}, levels = {} }
	push(player, "ownedShips", table.clone(profile.ownedShips))
	pushShipLevels(player, profile)
end

-- Records a hangar upgrade as built. The caller has already validated and
-- paid for it.
function DataSystem.grantHangar(player: Player, upgradeId: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	profile.hangar[upgradeId] = true
	push(player, "hangar", table.clone(profile.hangar))
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

-- Buys an equipment item (level 1) for one owned ship and fits it in its
-- slot. The caller has paid.
function DataSystem.grantEquipment(player: Player, shipId: string, itemId: string, slot: string)
	local profile = DataSystem.getProfile(player)
	local loadout = if profile then profile.loadouts[shipId] else nil
	if profile == nil or loadout == nil then
		return
	end
	loadout.levels[itemId] = loadout.levels[itemId] or 1
	loadout.equipment[slot] = itemId
	pushShipLevels(player, profile)
end

-- Raises an item bought for a ship one level (the caller has paid).
function DataSystem.levelEquipment(player: Player, shipId: string, itemId: string)
	local profile = DataSystem.getProfile(player)
	local loadout = if profile then profile.loadouts[shipId] else nil
	local level = if loadout then loadout.levels[itemId] else nil
	if profile == nil or loadout == nil or level == nil then
		return
	end
	loadout.levels[itemId] = math.min(level + 1, Config.Equipment.MAX_LEVEL)
	pushShipLevels(player, profile)
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
-- Returns the calendar day claimed and the Stardust it paid (its minutes
-- of reward rate R), or nil.
function DataSystem.claimDaily(player: Player, today: number): (number?, number?)
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
	local amount = DataSystem.grantMinutes(player, prize.minutes, nil, "calendar_day")
	push(player, "daily", table.clone(profile.daily))
	return day, amount
end

-- Grants a raid reward (Config.Raids): its minutes of reward rate R (at
-- least its minimum), for the first win of each reward day only. Returns
-- the Stardust paid (0 for a later win that day).
function DataSystem.grantRaidReward(player: Player, reward: any): number
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return 0
	end
	local today = DailyMath.today(os.time())
	if profile.economy.raidDay == today then
		return 0
	end
	profile.economy.raidDay = today
	return DataSystem.grantMinutes(player, reward.minutes, reward.minimum, "raid_first_clear")
end

-- Player settings a client may change (all booleans).
local BOOLEAN_SETTINGS = {
	stabilization = true,
	reducedEffects = true,
	pvp = true,
	showBounds = true,
	showControls = true,
	floating = true,
	autoIncubate = true,
	keepNewTypes = true,
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
	local P = Config.Planets
	if def.allPlanets then
		local free = P.MAX_PLANETS - PlanetInventory.count(profile.planets)
		if free < #P.ORDER then
			return nil,
				`You need {#P.ORDER} free planet spaces (you have {math.max(free, 0)}). Sell some planets first.`
		end
	end
	profile.redeemedCodes[code] = true
	if def.allPlanets then
		for _, typeId in P.ORDER do
			local id, nextId = PlanetInventory.newId(profile.nextPlanetId)
			profile.nextPlanetId = nextId
			profile.planets[id] = { typeId = typeId, level = 1, tier = 1, paid = 0, spent = 0 }
			profile.discovered[typeId] = true
		end
		push(player, "discovered", table.clone(profile.discovered))
		pushPlanets(player, profile)
	end
	if def.allShips then
		for _, shipId in Config.Ships.ORDER do
			DataSystem.grantShip(player, shipId)
		end
	end
	if def.cloak then
		push(player, "cloakUnlocked", true)
	end
	if def.minutes then
		DataSystem.grantMinutes(player, def.minutes, nil, "code")
	end
	return def, nil
end

-- Completes a Constellation Project (Config.Economy): pays its price from
-- the wallet and raises constellationRank by one, in one step. Returns the
-- new rank, or nil and why not.
function DataSystem.completeConstellation(player: Player, expected: unknown): (number?, string?)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return nil, "Your save isn't ready yet."
	end
	if not EconomyMath.constellationReady(profile) then
		return nil,
			`Constellation Projects open once you have {Config.Economy.CONSTELLATION_STARS} max-level {Config.Stars.BY_ID[Config.Stars.ORDER[#Config.Stars.ORDER]].displayName} stars and the best Egg Lab.`
	end
	local price = EconomyMath.constellationPrice(profile.constellationRank)
	if expected ~= nil and expected ~= price then
		return nil, "The price changed. Check it and try again."
	end
	if profile.stardust < price then
		return nil, `You need {price} Stardust for this project.`
	end
	profile.stardust -= price
	profile.constellationRank += 1
	EconomyAnalytics.sink(player, price, profile.stardust, "constellation_project")
	EconomyAnalytics.progression(player, "constellationRank", profile.constellationRank)
	push(player, "stardust", profile.stardust)
	push(player, "constellationRank", profile.constellationRank)
	return profile.constellationRank, nil
end

-- Erases the player's progress: the save becomes a brand-new profile (all
-- codes usable again), keeping only the purchase receipts so a Robux
-- purchase can never be granted twice. The caller then has them rejoin,
-- which saves it and rebuilds their world. False without a loaded save.
function DataSystem.resetProfile(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local data = session.Data
	local receipts = data.receipts
	local fresh = ProfileSchema.default()
	for key in data do
		data[key] = nil
	end
	for key, value in fresh do
		(data :: any)[key] = value
	end
	data.receipts = receipts
	data.lastOnline = os.time()
	return true
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
	-- The trail is part of production B: settle at the old rate first.
	DataSystem.settleIncome(player)
	profile.trail = trailId
	push(player, "trail", trailId or false)
	pushIncome(player, profile)
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
		windows[player] = nil
		sentEconomy[player] = nil
	end)
end

return DataSystem

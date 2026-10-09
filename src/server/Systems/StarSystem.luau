--!strict
-- The star tycoon on the server: builds each player's saved stars in their
-- region, handles buying, moving and upgrading stars (StarRequest), adds star
-- income to "uncollected" once per INCOME_TICK, and pays it out at the
-- station's Collect console.
--
-- StarRequest (RemoteFunction, client -> server), returns (ok, message):
--   "place", typeId: string, pos: Vector3       buy a star at pos (region space)
--   "move", starId: string, pos: Vector3        move a star and its planets
--   "upgrade", starId: string                   next level: more production
--   "evolve", starId: string                    at max level: become the next star
--                                               type, back to level 1, keeping
--                                               its planets; may open more orbits
--                                               (never grants planets)
--   "equipPlanet", planetId, starId, slot?      put an owned planet in that orbit
--                                               (first free one if no slot),
--                                               moving it there if it orbits
--                                               elsewhere
--   "unequipPlanet", planetId                   back to the planet inventory
--   "levelPlanet", planetId                     next level (in orbit or not)
--   "sellPlanets", { planetId }                 sell inventory planets (never
--                                               in orbit or locked) for Stardust
--   "lockPlanet", planetId, locked: boolean     protect a planet from selling
--   "equipBest"                                 fill every orbit with the
--                                               best-earning planets
-- Every request is validated here: ownership, Config.Stars, the region's
-- bounds and star spacing (Logic/PlacementRules), capacity, orbits and
-- cost. The client's ghost preview and panels run the same rules but are
-- never trusted. Income is settled before anything changes it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Build = require(script.Parent.Parent.World.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Notify = require(script.Parent.Parent.Util.Notify)
local PlacementRules = require(ReplicatedStorage.Shared.Logic.PlacementRules)
local PlanetInventory = require(ReplicatedStorage.Shared.Logic.PlanetInventory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local RegionSystem = require(script.Parent.RegionSystem)
local Reward = require(script.Parent.Parent.Util.Reward)
local StarBuilder = require(script.Parent.Parent.World.StarBuilder)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local Types = require(ReplicatedStorage.Shared.Types)

local S = Config.Stars
local P = Config.Planets
local CURRENCY = Config.Economy.CURRENCY_NAME
-- The top of the star ladder; owning one counts for the "blackHoles" stat.
local BLACK_HOLE = "BlackHole"

local REJECTIONS: { [string]: string } = {
	Invalid = "That isn't a valid spot.",
	OutOfBounds = "Stars must sit inside your galaxy, away from its side walls.",
	TooHigh = "Too high or too low: keep the star inside your galaxy's height.",
	TooClose = "Too close to another star: its planets need room.",
	AtCapacity = "Your galaxy can't hold more stars yet.",
}

-- The message for a placement rejection, with how far off a clash is.
local function rejectionText(rejection: string?, short: number?): string
	local text = REJECTIONS[rejection or "Invalid"] or REJECTIONS.Invalid
	if rejection == "TooClose" and short then
		text ..= ` Move it {short} studs further away.`
	end
	return text
end

local StarSystem = {}

local models: { [Player]: { [string]: Model } } = {}
local requestLimit = RateLimiter.new(6, 2)
local elapsed = 0

local function starsFolder(region: RegionSystem.Region): Instance
	local existing = region.model:FindFirstChild("Stars")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Stars"
	folder.Parent = region.model
	return folder
end

-- The planets in orbit around one of the player's stars.
local function equipped(player: Player, starId: string): { [number]: Types.PlanetRecord }
	local profile = DataSystem.getProfile(player)
	return if profile then PlanetInventory.equippedOn(profile.planets, starId) else {}
end

local function spawnStar(
	player: Player,
	region: RegionSystem.Region,
	id: string,
	star: Types.StarRecord
)
	local cframe = CFrame.new(RegionSystem.toWorld(region, star.pos))
	local model = StarBuilder.build(id, star, cframe, player.UserId, equipped(player, id))
	model.Parent = starsFolder(region)
	models[player] = models[player] or {}
	models[player][id] = model
end

local function positions(stars: { [string]: Types.StarRecord }, except: string?): { Types.Vec3 }
	local list: { Types.Vec3 } = {}
	for id, star in stars do
		if id ~= except then
			table.insert(list, star.pos)
		end
	end
	return list
end

local function count(stars: { [string]: any }): number
	local n = 0
	for _ in stars do
		n += 1
	end
	return n
end

local function toVec3(value: unknown): Types.Vec3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	local pos = { x = v.X, y = v.Y, z = v.Z }
	return if PlacementRules.isValidVec3(pos) then pos else nil
end

local function place(player: Player, typeId: unknown, rawPos: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local region = RegionSystem.getRegion(player)
	local def = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	local pos = toVec3(rawPos)
	if profile == nil or region == nil or def == nil or not def.enabled or pos == nil then
		return false, REJECTIONS.Invalid
	end
	local galaxy = profile.galaxy
	if not StarMath.typeUnlocked(def.id, galaxy.stars) then
		return false, "You need a star of the previous tier first."
	end
	local owned = count(galaxy.stars)
	if not PlacementRules.hasCapacity(owned, galaxy.expansion) then
		return false, REJECTIONS.AtCapacity
	end
	local ok, rejection, short =
		PlacementRules.checkStar(pos, galaxy.expansion, positions(galaxy.stars))
	if not ok then
		return false, rejectionText(rejection, short)
	end
	local cost = StarMath.placeCost(def.id, StarMath.nextBuild(galaxy)) :: number
	if not DataSystem.spendStardust(player, cost, "star_buy") then
		return false, `You need {Format.commas(cost)} {CURRENCY} for this star.`
	end
	-- DataSystem.addStar gives it the next BuildIndex (the one priced above).
	local star: Types.StarRecord = { typeId = def.id, level = 1, pos = pos, build = 0 }
	local id = DataSystem.addStar(player, star)
	if id == nil then
		DataSystem.addStardust(player, cost)
		return false, REJECTIONS.Invalid
	end
	spawnStar(player, region, id, star)
	-- Clients play the star-birth effect for stars born moments ago.
	local mine = models[player]
	local model = if mine then mine[id] else nil
	if model then
		model:SetAttribute("BornAt", Workspace:GetServerTimeNow())
	end
	DataSystem.addStat(player, "starsPlaced", 1)
	if def.id == BLACK_HOLE then
		DataSystem.addStat(player, "blackHoles", 1)
	end
	return true,
		`{def.displayName} placed! It makes {Format.rate(StarMath.income(star))} {CURRENCY}/s.`
end

local function move(player: Player, starId: unknown, rawPos: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local region = RegionSystem.getRegion(player)
	local star = if profile and type(starId) == "string" then profile.galaxy.stars[starId] else nil
	local pos = toVec3(rawPos)
	local model = if type(starId) == "string" and models[player]
		then models[player][starId]
		else nil
	if profile == nil or region == nil or star == nil or pos == nil or model == nil then
		return false, REJECTIONS.Invalid
	end
	local id = starId :: string
	local galaxy = profile.galaxy
	local ok, rejection, short =
		PlacementRules.checkStar(pos, galaxy.expansion, positions(galaxy.stars, id))
	if not ok then
		return false, rejectionText(rejection, short)
	end
	DataSystem.updateStar(player, id, { pos = pos })
	model:PivotTo(CFrame.new(RegionSystem.toWorld(region, pos)))
	return true, "Star moved, planets and all."
end

-- The caller's own star record and model, or nil.
local function ownStar(player: Player, starId: unknown): (Types.StarRecord?, Model?)
	local profile = DataSystem.getProfile(player)
	if profile == nil or type(starId) ~= "string" then
		return nil, nil
	end
	local star = profile.galaxy.stars[starId]
	local owned = models[player]
	local model = if owned then owned[starId] else nil
	if star == nil or model == nil then
		return nil, nil
	end
	return star, model
end

-- Rebuilds a star's looks and attributes after it or its planets changed.
local function refresh(player: Player, starId: string?)
	local profile = DataSystem.getProfile(player)
	local owned = models[player]
	if profile == nil or owned == nil or starId == nil then
		return
	end
	local star, model = profile.galaxy.stars[starId], owned[starId]
	if star and model then
		StarBuilder.apply(model, star, equipped(player, starId))
	end
end

local function upgrade(player: Player, starId: unknown): (boolean, string)
	local star, model = ownStar(player, starId)
	if star == nil or model == nil then
		return false, REJECTIONS.Invalid
	end
	local cost = StarMath.upgradeCost(star.typeId, star.level, star.build)
	if cost == nil then
		return false,
			if StarMath.evolveTarget(star.typeId)
				then "Max level! This star is ready to evolve."
				else "This star is at its highest level."
	end
	if not DataSystem.spendStardust(player, cost, "star_level") then
		return false, `You need {Format.commas(cost)} {CURRENCY} for this upgrade.`
	end
	local level = star.level + 1
	DataSystem.updateStar(player, starId :: string, { level = level })
	DataSystem.addStat(player, "starUpgrades", 1)
	refresh(player, starId :: string)
	local income = Format.rate(StarMath.income(star, equipped(player, starId :: string)))
	return true,
		if level >= StarMath.maxLevel(star.typeId) and StarMath.evolveTarget(star.typeId)
			then `Level {level}: max level! Now {income} {CURRENCY}/s. It can evolve.`
			else `Level {level}! Now {income} {CURRENCY}/s.`
end

local function evolve(player: Player, starId: unknown): (boolean, string)
	local star, model = ownStar(player, starId)
	if star == nil or model == nil then
		return false, REJECTIONS.Invalid
	end
	local target = StarMath.evolveTarget(star.typeId)
	if target == nil then
		return false, "Nothing is beyond a black hole."
	end
	local def = S.BY_ID[target]
	local top = StarMath.maxLevel(star.typeId)
	if star.level < top then
		return false, `Level this star up to {top} before it can evolve.`
	end
	local cost = StarMath.evolveCost(star.typeId, star.build) :: number
	if not DataSystem.spendStardust(player, cost, "star_evolve") then
		return false,
			`You need {Format.commas(cost)} {CURRENCY} to evolve into a {def.displayName}.`
	end
	-- A new type starts again at level 1, keeping its planets in their slots
	-- (orbits never decrease up the ladder). It grants no planets.
	local before = StarMath.slots(star.typeId)
	DataSystem.updateStar(player, starId :: string, { typeId = target, level = 1 })
	DataSystem.addStat(player, "starEvolutions", 1)
	if target == BLACK_HOLE then
		DataSystem.addStat(player, "blackHoles", 1)
	end
	refresh(player, starId :: string)
	local after = StarMath.slots(target)
	return true,
		`Your star became a {def.displayName}! {if after > before
			then `{after} orbits ({after - before} new)`
			else `{after} orbits`}, levels up to {StarMath.maxLevel(target)}.`
end

local function equipPlanet(
	player: Player,
	planetId: unknown,
	starId: unknown,
	rawSlot: unknown
): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local star = ownStar(player, starId)
	local planet = if profile and type(planetId) == "string" then profile.planets[planetId] else nil
	if profile == nil or star == nil or planet == nil then
		return false, REJECTIONS.Invalid
	end
	local pid, sid = planetId :: string, starId :: string
	local slot: number? = nil
	if rawSlot == nil then
		slot = PlanetInventory.freeSlot(profile.planets, sid, star)
		if slot == nil then
			return false, "Every orbit of this star is taken. Evolve it or unequip a planet."
		end
	elseif type(rawSlot) == "number" and rawSlot == rawSlot then
		slot = rawSlot
	else
		return false, REJECTIONS.Invalid
	end
	local from = planet.star
	local ok, problem = DataSystem.equipPlanet(player, pid, sid, slot :: number)
	if not ok then
		return false,
			PlanetInventory.MESSAGES[(problem or "UnknownPlanet") :: PlanetInventory.Problem]
	end
	DataSystem.addStat(player, "planetsEquipped", 1)
	refresh(player, from)
	if from ~= sid then
		refresh(player, sid)
	end
	local def = P.BY_ID[planet.typeId]
	local host = profile and profile.galaxy.stars[sid]
	local own = if host then StarMath.starIncome(host.typeId, host.level) else 0
	return true,
		`{def.displayName} now orbits your star: +{Format.rate(
			StarMath.planetIncome(def.id, planet.level, planet.tier, own)
		)} {CURRENCY}/s.`
end

local function unequipPlanet(player: Player, planetId: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local planet = if profile and type(planetId) == "string" then profile.planets[planetId] else nil
	if planet == nil then
		return false, REJECTIONS.Invalid
	end
	local from = planet.star
	if from == nil then
		return false, "That planet is already in your inventory."
	end
	DataSystem.unequipPlanet(player, planetId :: string)
	refresh(player, from)
	return true, `{P.BY_ID[planet.typeId].displayName} is back in your planet inventory.`
end

local function levelPlanet(player: Player, planetId: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local planet = if profile and type(planetId) == "string" then profile.planets[planetId] else nil
	local def = if planet then P.BY_ID[planet.typeId] else nil
	if planet == nil or def == nil then
		return false, REJECTIONS.Invalid
	end
	local cost =
		StarMath.planetLevelCost(def.id, planet.level, EconomyMath.profileEggPrice(profile :: any))
	if cost == nil then
		return false, "That planet is at its top level."
	end
	if not DataSystem.spendStardust(player, cost, "planet_level") then
		return false, `You need {Format.commas(cost)} {CURRENCY} to level this planet.`
	end
	local level = planet.level + 1
	DataSystem.setPlanetLevel(player, planetId :: string, level, cost)
	DataSystem.addStat(player, "planetLevels", 1)
	refresh(player, planet.star)
	local host = if planet.star then (profile :: any).galaxy.stars[planet.star] else nil
	local share = math.floor(StarMath.planetFactor(def.id, level, planet.tier) * 1000 + 0.5) / 10
	return true,
		if host
			then `{def.displayName} reached level {level}! It makes {Format.rate(
				StarMath.planetIncome(
					def.id,
					level,
					planet.tier,
					StarMath.starIncome(host.typeId, host.level)
				)
			)} {CURRENCY}/s.`
			else `{def.displayName} reached level {level}! In orbit it adds {share}% of its star's output.`
end

-- Star and planet income per second (before passes, boosts, trail and
-- Refinery).
local function baseIncome(profile: Types.Profile): number
	return StarMath.totalIncome(profile.galaxy.stars, profile.planets)
end

local function sellPlanets(player: Player, rawIds: unknown): (boolean, string)
	if type(rawIds) ~= "table" then
		return false, REJECTIONS.Invalid
	end
	local ids: { string } = {}
	for index, id in rawIds :: { any } do
		if
			type(index) ~= "number"
			or type(id) ~= "string"
			or index > Config.Planets.MAX_PLANETS
		then
			return false, REJECTIONS.Invalid
		end
		table.insert(ids, id)
	end
	local sold, total = DataSystem.sellPlanets(player, ids)
	if sold == 0 then
		return false, "Nothing sold: planets in orbit or locked can't be sold."
	end
	return true,
		`Sold {sold} {if sold == 1 then "planet" else "planets"} for {Format.commas(total)} {CURRENCY}.{if sold
				< #ids
			then " Planets in orbit or locked were kept."
			else ""}`
end

local function lockPlanet(player: Player, planetId: unknown, locked: unknown): (boolean, string)
	if type(planetId) ~= "string" or type(locked) ~= "boolean" then
		return false, REJECTIONS.Invalid
	end
	if not DataSystem.setPlanetLocked(player, planetId, locked) then
		return false, REJECTIONS.Invalid
	end
	return true, if locked then "Locked: this planet can't be sold." else "Unlocked."
end

local function equipBest(player: Player): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, REJECTIONS.Invalid
	end
	local before = baseIncome(profile)
	local changed = DataSystem.equipBest(player)
	if #changed == 0 then
		return true, "Your best planets are already in orbit."
	end
	for _, starId in changed do
		refresh(player, starId)
	end
	local after = baseIncome(profile)
	return true,
		`Planets rearranged: {Format.rate(before)} -> {Format.rate(after)} {CURRENCY}/s before boosts.`
end

local function onRequest(
	player: Player,
	action: unknown,
	a: unknown,
	b: unknown,
	c: unknown
): (boolean, string)
	if not requestLimit.allow(player) then
		return false, "Slow down a little."
	end
	if action == "place" then
		return place(player, a, b)
	elseif action == "move" then
		return move(player, a, b)
	elseif action == "upgrade" then
		return upgrade(player, a)
	elseif action == "evolve" then
		return evolve(player, a)
	elseif action == "equipPlanet" then
		return equipPlanet(player, a, b, c)
	elseif action == "unequipPlanet" then
		return unequipPlanet(player, a)
	elseif action == "levelPlanet" then
		return levelPlanet(player, a)
	elseif action == "sellPlanets" then
		return sellPlanets(player, a)
	elseif action == "lockPlanet" then
		return lockPlanet(player, a, b)
	elseif action == "equipBest" then
		return equipBest(player)
	end
	return false, REJECTIONS.Invalid
end

-- The Collect console: only the station's owner may collect there.
local function onPrompt(prompt: ProximityPrompt, player: Player)
	if not CollectionService:HasTag(prompt, Build.TYCOON_TAG) then
		return
	end
	if prompt:GetAttribute("TycoonAction") ~= "Collect" then
		return
	end
	local region = RegionSystem.getRegion(player)
	if region == nil or not prompt:IsDescendantOf(region.model) then
		Notify.send(player, "You can only collect at your own station.")
		return
	end
	local amount = DataSystem.collectIncome(player)
	if amount > 0 then
		DataSystem.addStat(player, "collections", 1)
		local console = prompt.Parent
		Reward.send(
			player,
			"collect",
			amount,
			if console and console:IsA("BasePart") then console.Position else nil,
			"Collected from your stars"
		)
	else
		local profile = DataSystem.getProfile(player)
		local hasStars = profile ~= nil and next(profile.galaxy.stars) ~= nil
		Notify.send(
			player,
			if hasStars
				then "Nothing to collect yet. Your stars are working on it."
				else "Buy a star at the Star Shop to start earning here."
		)
	end
end

function StarSystem.start()
	Net.StarRequest.OnServerInvoke = onRequest
	ProximityPromptService.PromptTriggered:Connect(onPrompt)

	RegionSystem.regionAdded:Connect(function(region)
		local profile = DataSystem.getProfile(region.owner)
		if profile == nil then
			return
		end
		for id, star in profile.galaxy.stars do
			if S.BY_ID[star.typeId] then
				spawnStar(region.owner, region, id, star)
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < S.INCOME_TICK then
			return
		end
		for _, player in Players:GetPlayers() do
			DataSystem.settleIncome(player)
		end
		elapsed = 0
	end)

	Players.PlayerRemoving:Connect(function(player)
		models[player] = nil
	end)
end

return StarSystem

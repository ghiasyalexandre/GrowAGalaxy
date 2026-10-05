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
--                                               planets, with one more orbit
--   "buyPlanet", starId: string, planetId       buy a planet into the first free slot
--   "upgradePlanet", starId: string, slot: string  planet in that slot -> next tier
-- Every request is validated here: ownership, Config.Stars, the region's
-- bounds and star spacing (Logic/PlacementRules), capacity and cost. The
-- client's ghost preview runs the same rules but is never trusted.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Build = require(script.Parent.Parent.World.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local PlacementRules = require(ReplicatedStorage.Shared.Logic.PlacementRules)
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
local BLACK_HOLE = S.ORDER[#S.ORDER]

local REJECTIONS: { [string]: string } = {
	Invalid = "That isn't a valid spot.",
	OutOfBounds = "Stars must sit inside your galaxy, away from its edges.",
	TooClose = "Too close to another star: its planets need room.",
	AtCapacity = "Your galaxy can't hold more stars yet.",
}

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

local function spawnStar(
	player: Player,
	region: RegionSystem.Region,
	id: string,
	star: Types.StarRecord
)
	local cframe = CFrame.new(RegionSystem.toWorld(region, star.pos))
	local model = StarBuilder.build(id, star, cframe, player.UserId)
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
	local ok, rejection = PlacementRules.checkStar(pos, galaxy.expansion, positions(galaxy.stars))
	if not ok then
		return false, REJECTIONS[rejection or "Invalid"]
	end
	local cost = StarMath.placeCost(def.id, owned) :: number
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} for this star.`
	end
	local star: Types.StarRecord = { typeId = def.id, level = 1, pos = pos, planets = {} }
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
	return true, `{def.displayName} placed! It makes {StarMath.income(star)} {CURRENCY}/s.`
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
	local ok, rejection =
		PlacementRules.checkStar(pos, galaxy.expansion, positions(galaxy.stars, id))
	if not ok then
		return false, REJECTIONS[rejection or "Invalid"]
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

local function upgrade(player: Player, starId: unknown): (boolean, string)
	local star, model = ownStar(player, starId)
	if star == nil or model == nil then
		return false, REJECTIONS.Invalid
	end
	local cost = StarMath.upgradeCost(star.typeId, star.level)
	if cost == nil then
		return false,
			if StarMath.evolveTarget(star.typeId)
				then "Max level! This star is ready to evolve."
				else "This star is at its highest level."
	end
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} for this upgrade.`
	end
	local level = star.level + 1
	DataSystem.updateStar(player, starId :: string, { level = level })
	DataSystem.addStat(player, "starUpgrades", 1)
	StarBuilder.apply(model, star)
	return true,
		if level >= StarMath.maxLevel(star.typeId) and StarMath.evolveTarget(star.typeId)
			then `Level {level}: max level! Now {StarMath.income(star)} {CURRENCY}/s. It can evolve.`
			else `Level {level}! Now {StarMath.income(star)} {CURRENCY}/s.`
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
	if not DataSystem.spendStardust(player, def.cost) then
		return false, `You need {def.cost} {CURRENCY} to evolve into a {def.displayName}.`
	end
	-- A new type starts again at level 1, keeping its planets.
	DataSystem.updateStar(player, starId :: string, { typeId = target, level = 1 })
	DataSystem.addStat(player, "starEvolutions", 1)
	if target == BLACK_HOLE then
		DataSystem.addStat(player, "blackHoles", 1)
	end
	StarBuilder.apply(model, star)
	return true,
		`Your star became a {def.displayName}! {StarMath.slots(target)} orbits, levels up to {StarMath.maxLevel(
			target
		)}.`
end

local function buyPlanet(player: Player, starId: unknown, planetId: unknown): (boolean, string)
	local star, model = ownStar(player, starId)
	local def = if type(planetId) == "string" then P.BY_ID[planetId] else nil
	if star == nil or model == nil or def == nil then
		return false, REJECTIONS.Invalid
	end
	if not StarMath.planetAllowed(star.typeId, def.id) then
		return false, "This star isn't big enough for that planet. Evolve it first."
	end
	local slot = StarMath.freeSlot(star)
	if slot == nil then
		return false, "No free orbit. Evolve the star to open another."
	end
	if not DataSystem.spendStardust(player, def.cost) then
		return false, `You need {def.cost} {CURRENCY} for a {def.displayName}.`
	end
	DataSystem.updateStar(player, starId :: string, { slot = slot, planet = def.id })
	DataSystem.addStat(player, "planetsBought", 1)
	StarBuilder.apply(model, star)
	return true, `A {def.displayName} joins your star's orbit! +{def.income} {CURRENCY}/s.`
end

local function upgradePlanet(player: Player, starId: unknown, slot: unknown): (boolean, string)
	local star, model = ownStar(player, starId)
	local current = if star and type(slot) == "string" then star.planets[slot] else nil
	if star == nil or model == nil or current == nil then
		return false, REJECTIONS.Invalid
	end
	local target, cost = StarMath.planetUpgrade(current)
	if target == nil or cost == nil then
		return false, "That planet is already the finest there is."
	end
	if not StarMath.planetAllowed(star.typeId, target) then
		return false, "Evolve the star to hold a better planet."
	end
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} for this upgrade.`
	end
	DataSystem.updateStar(player, starId :: string, { slot = slot :: string, planet = target })
	DataSystem.addStat(player, "planetUpgrades", 1)
	StarBuilder.apply(model, star)
	return true,
		`Your planet became a {P.BY_ID[target].displayName}! Now {StarMath.income(star)} {CURRENCY}/s.`
end

local function onRequest(player: Player, action: unknown, a: unknown, b: unknown): (boolean, string)
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
	elseif action == "buyPlanet" then
		return buyPlanet(player, a, b)
	elseif action == "upgradePlanet" then
		return upgradePlanet(player, a, b)
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
			DataSystem.accrueIncome(player, elapsed)
		end
		elapsed = 0
	end)

	Players.PlayerRemoving:Connect(function(player)
		models[player] = nil
	end)
end

return StarSystem

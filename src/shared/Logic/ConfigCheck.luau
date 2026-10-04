--!strict
-- Consistency checks for the Config tables. Returns a list of problems (empty
-- when everything is consistent). The server logs these at startup and the
-- Lune tests fail on any of them, so a bad tuning edit is caught before play.
--
-- Takes the config as a parameter so tests can feed it deliberately broken
-- copies.

local ConfigCheck = {}

function ConfigCheck.run(config: any): { string }
	local problems: { string } = {}
	local function fail(message: string)
		table.insert(problems, message)
	end

	local materials = config.Materials.BY_ID
	local galaxy = config.Galaxy

	local function checkMaterials(where: string, list: { [string]: number }?)
		if list == nil then
			return
		end
		for id, n in list do
			if materials[id] == nil then
				fail(`{where}: unknown material "{id}"`)
			end
			if type(n) ~= "number" or n <= 0 then
				fail(`{where}: amount of {id} must be a positive number`)
			end
		end
	end

	local function checkCost(where: string, cost: any)
		if cost == nil then
			return
		end
		if type(cost.stardust) ~= "number" or cost.stardust < 0 then
			fail(`{where}: stardust must be zero or more`)
		end
		checkMaterials(where, cost.materials)
	end

	local function checkOrder(name: string, order: { string }, byId: { [string]: any })
		local listed: { [string]: boolean } = {}
		for _, id in order do
			listed[id] = true
			local def = byId[id]
			if def == nil then
				fail(`{name}.ORDER lists "{id}" but it has no definition`)
			elseif def.id ~= id then
				fail(`{name}: entry "{id}" has id "{def.id}"`)
			end
		end
		for id in byId do
			if not listed[id] then
				fail(`{name}: "{id}" is missing from ORDER`)
			end
		end
	end

	checkOrder("Materials", config.Materials.ORDER, materials)
	checkOrder("Zones", config.Zones.ORDER, config.Zones.BY_ID)
	checkOrder("Ships", config.Ships.ORDER, config.Ships.BY_ID)
	checkOrder("Equipment", config.Equipment.ORDER, config.Equipment.BY_ID)
	checkOrder("Recipes", config.Recipes.ORDER, config.Recipes.BY_ID)
	checkOrder("Celestials", config.Celestials.ORDER, config.Celestials.BY_ID)
	checkOrder("Achievements", config.Achievements.ORDER, config.Achievements.BY_ID)

	-- Zones: a zone's unlock may only cost materials that earlier zones produce.
	local minable: { [string]: boolean } = {}
	local minableEnabled: { [string]: boolean } = {}
	local starterZone = config.Zones.BY_ID[config.Zones.STARTER_ZONE]
	if starterZone == nil then
		fail(`Zones.STARTER_ZONE "{config.Zones.STARTER_ZONE}" does not exist`)
	elseif starterZone.unlock ~= nil or not starterZone.enabled then
		fail("The starter zone must be enabled and free")
	end
	for _, zoneId in config.Zones.ORDER do
		local zone = config.Zones.BY_ID[zoneId]
		if zone == nil then
			continue
		end
		checkCost(`Zone {zoneId} unlock`, zone.unlock)
		if zone.unlock then
			for material in zone.unlock.materials do
				if not minable[material] then
					fail(`Zone {zoneId} unlock needs {material}, which no earlier zone produces`)
				end
			end
		end
		if #zone.materials == 0 then
			fail(`Zone {zoneId} produces no materials`)
		end
		for _, entry in zone.materials do
			if materials[entry.material] == nil then
				fail(`Zone {zoneId}: unknown material "{entry.material}"`)
			end
			if entry.weight <= 0 then
				fail(`Zone {zoneId}: weight of {entry.material} must be positive`)
			end
			minable[entry.material] = true
			if zone.enabled then
				minableEnabled[entry.material] = true
			end
		end
	end

	-- Ships: exactly one free starter; every other ship is earnable with minable materials.
	local starterId = config.Ships.STARTER_SHIP
	local starterShip = config.Ships.BY_ID[starterId]
	if starterShip == nil then
		fail(`Ships.STARTER_SHIP "{starterId}" does not exist`)
	elseif not starterShip.enabled or starterShip.earn ~= nil then
		fail("The starter ship must be enabled and free")
	end
	local statNames: { [string]: boolean } = {}
	if starterShip then
		for stat in starterShip.stats do
			statNames[stat] = true
		end
	end
	for shipId, ship in config.Ships.BY_ID do
		for stat in statNames do
			local value = ship.stats[stat]
			if type(value) ~= "number" or value <= 0 then
				fail(`Ship {shipId}: stat {stat} must be a positive number`)
			end
		end
		if shipId ~= starterId then
			if ship.earn == nil then
				fail(`Ship {shipId} has no gameplay way to earn it`)
			else
				checkCost(`Ship {shipId}`, ship.earn)
				for material in ship.earn.materials do
					if not minable[material] then
						fail(`Ship {shipId} costs {material}, which no zone produces`)
					end
				end
			end
		end
		if ship.productKey and config.Products.BY_KEY[ship.productKey] == nil then
			fail(`Ship {shipId}: unknown product "{ship.productKey}"`)
		end
	end

	-- Movement: the suit must be slower than every ship, and docking must be
	-- possible below every ship's top speed.
	local movement = config.Movement
	for shipId, ship in config.Ships.BY_ID do
		if movement.SUIT_MAX_SPEED >= ship.stats.maxSpeed then
			fail(`Movement: the spacesuit is not slower than ship {shipId}`)
		end
		if movement.DOCK_MAX_SPEED >= ship.stats.maxSpeed then
			fail(`Movement: DOCK_MAX_SPEED is not below ship {shipId}'s top speed`)
		end
	end
	for _, name in { "SHIP_REVERSE_FACTOR", "SHIP_STRAFE_FACTOR", "SHIP_IDLE_BRAKE_FACTOR" } do
		local value = movement[name]
		if type(value) ~= "number" or value <= 0 or value > 1 then
			fail(`Movement: {name} must be between 0 and 1`)
		end
	end

	for _, name in { "SHIP_MAX_BANK_DEGREES", "SUIT_LEAN_DEGREES", "SUIT_ROLL_DEGREES" } do
		local value = movement[name]
		if type(value) ~= "number" or value < 0 or value >= 90 then
			fail(`Movement: {name} must be from 0 up to 90`)
		end
	end
	if movement.CAMERA_FOV + movement.CAMERA_FOV_BOOST > 120 then
		fail("Movement: CAMERA_FOV plus CAMERA_FOV_BOOST is over Roblox's limit of 120")
	end

	-- Mining beam: every ship fires for a while before it overheats.
	local beam = config.Beam
	if type(beam.HEAT_PER_SECOND) ~= "number" or beam.HEAT_PER_SECOND <= 0 then
		fail("Beam: HEAT_PER_SECOND must be a positive number")
	else
		for shipId, ship in config.Ships.BY_ID do
			if ship.stats.heatCapacity / beam.HEAT_PER_SECOND < 2 then
				fail(`Beam: ship {shipId} overheats in under 2 seconds`)
			end
		end
	end
	if beam.OVERHEAT_RESUME_SHARE <= 0 or beam.OVERHEAT_RESUME_SHARE >= 1 then
		fail("Beam: OVERHEAT_RESUME_SHARE must be between 0 and 1")
	end
	if beam.AIM_CONE_DEGREES <= 0 or beam.AIM_CONE_DEGREES >= 90 then
		fail("Beam: AIM_CONE_DEGREES must be between 0 and 90")
	end

	-- Asteroids: sizes make sense, the population caps agree, and the spawn
	-- volume sits inside the flight area with room outside the ISS.
	local asteroids = config.Asteroids
	checkOrder("Asteroids sizes", asteroids.SIZE_ORDER, asteroids.SIZES)
	local largestRock = 0
	for sizeId, size in asteroids.SIZES do
		local where = `Asteroid size {sizeId}`
		for _, field in { "weight", "radius", "weakPointRadius", "durability", "reward" } do
			if type(size[field]) ~= "number" or size[field] <= 0 then
				fail(`{where}: {field} must be a positive number`)
			end
		end
		if size.weakPointRadius >= size.radius then
			fail(`{where}: the weak point must be smaller than the rock`)
		end
		largestRock = math.max(largestRock, size.radius)
	end
	if asteroids.TARGET_COUNT <= 0 or asteroids.TARGET_COUNT > asteroids.MAX_COUNT then
		fail("Asteroids: TARGET_COUNT must be positive and at most MAX_COUNT")
	end
	if asteroids.CLUSTER_MIN < 1 or asteroids.CLUSTER_MAX < asteroids.CLUSTER_MIN then
		fail("Asteroids: need 1 <= CLUSTER_MIN <= CLUSTER_MAX")
	end
	if asteroids.ISS_CLEARANCE + 2 * largestRock >= asteroids.MAX_DISTANCE then
		fail("Asteroids: no room between ISS_CLEARANCE and MAX_DISTANCE")
	end
	if asteroids.MAX_DISTANCE >= movement.FLIGHT_BOUNDS_RADIUS then
		fail("Asteroids: MAX_DISTANCE reaches past the flight area")
	end
	if asteroids.HEIGHT >= movement.FLIGHT_BOUNDS_HEIGHT then
		fail("Asteroids: HEIGHT reaches past the flight area")
	end
	-- The station sits STATION_DISTANCE in front of its region, with its
	-- berth and docking approach reaching about 100 studs further.
	if asteroids.REGION_CLEARANCE < config.World.STATION_DISTANCE + 100 then
		fail("Asteroids: REGION_CLEARANCE does not keep asteroids off personal stations")
	end
	if asteroids.ROCK_EFFICIENCY <= 0 or asteroids.ROCK_EFFICIENCY > 1 then
		fail("Asteroids: ROCK_EFFICIENCY must be above 0 and at most 1")
	end
	for _, name in { "SCAN_RANGE", "SCAN_MARKERS", "SCAN_INTERVAL" } do
		if type(asteroids[name]) ~= "number" or asteroids[name] <= 0 then
			fail(`Asteroids: {name} must be a positive number`)
		end
	end
	if asteroids.BREAK_SOUND ~= "" and not string.match(asteroids.BREAK_SOUND, "^rbxasset") then
		fail("Asteroids: BREAK_SOUND must be an rbxasset:// or rbxassetid:// URI, or empty")
	end
	if asteroids.PRECISION_BONUS < 0 then
		fail("Asteroids: PRECISION_BONUS must be zero or more")
	end
	for shipId, ship in config.Ships.BY_ID do
		if ship.stats.beamRange <= 2 * largestRock then
			fail(`Asteroids: ship {shipId}'s beam range is too short for the largest asteroid`)
		end
	end

	-- Stars: every level's planets fit inside SYSTEM_RADIUS and clear of the
	-- star, costs are positive, production never drops.
	local stars = config.Stars
	checkOrder("Stars", stars.ORDER, stars.BY_ID)
	if stars.BY_ID[stars.DEFAULT_TYPE] == nil or not stars.BY_ID[stars.DEFAULT_TYPE].enabled then
		fail("Stars: DEFAULT_TYPE must exist and be enabled")
	end
	if stars.PRICE_GROWTH < 1 then
		fail("Stars: PRICE_GROWTH must be at least 1")
	end
	local largestStar = 0
	for typeId, def in stars.BY_ID do
		if def.cost <= 0 then
			fail(`Star {typeId}: cost must be positive`)
		end
		local previous = -1
		local used: { [number]: boolean } = {}
		for index, levelDef in def.levels do
			local where = `Star {typeId} level {index}`
			if (index == 1) ~= (levelDef.upgradeCost == nil) then
				fail(`{where}: only level 1 may (and must) have no upgradeCost`)
			end
			if levelDef.upgradeCost and levelDef.upgradeCost <= 0 then
				fail(`{where}: upgradeCost must be positive`)
			end
			if levelDef.income < previous then
				fail(`{where}: income goes down`)
			end
			previous = levelDef.income
			if levelDef.starRadius <= 0 or levelDef.starRadius > galaxy.STAR_MAX_RADIUS then
				fail(`{where}: starRadius must be within 0..{galaxy.STAR_MAX_RADIUS}`)
			end
			largestStar = math.max(largestStar, levelDef.starRadius)
			if levelDef.planet then
				if stars.PLANETS[levelDef.planet] == nil then
					fail(`{where}: unknown planet {levelDef.planet}`)
				elseif used[levelDef.planet] then
					fail(`{where}: planet {levelDef.planet} is added twice`)
				end
				used[levelDef.planet] = true
			end
		end
	end
	for index, planet in stars.PLANETS do
		local where = `Stars planet {index}`
		if planet.orbit + planet.radius > galaxy.SYSTEM_RADIUS then
			fail(`{where}: orbit reaches past Galaxy.SYSTEM_RADIUS`)
		end
		if planet.orbit - planet.radius <= largestStar then
			fail(`{where}: orbit touches the star`)
		end
		if planet.period <= 0 then
			fail(`{where}: period must be positive`)
		end
		local nextPlanet = stars.PLANETS[index + 1]
		if nextPlanet and nextPlanet.orbit - nextPlanet.radius <= planet.orbit + planet.radius then
			fail(`{where}: orbit overlaps the next planet's`)
		end
	end

	-- The flight area must hold every region at its largest and stay clear of
	-- the Earth backdrop.
	local world = config.World
	local largest = config.Galaxy.EXPANSIONS[#config.Galaxy.EXPANSIONS].size
	local farthest = math.sqrt((world.REGION_RING_RADIUS + largest.z) ^ 2 + (largest.x / 2) ^ 2)
	if movement.FLIGHT_BOUNDS_RADIUS <= farthest then
		fail(
			`Movement: FLIGHT_BOUNDS_RADIUS does not reach the far corners of the largest region ({math.ceil(
				farthest
			)} studs)`
		)
	end
	if movement.FLIGHT_BOUNDS_HEIGHT <= math.abs(world.REGION_RING_HEIGHT) + largest.y / 2 then
		fail("Movement: FLIGHT_BOUNDS_HEIGHT does not cover the tallest region")
	end
	local earthTop = world.EARTH_CENTER.y + world.EARTH_DIAMETER / 2
	if -movement.FLIGHT_BOUNDS_HEIGHT <= earthTop then
		fail("Movement: the flight area reaches into the Earth backdrop")
	end

	-- Equipment
	local slots: { [string]: boolean } = {}
	for _, slot in config.Equipment.SLOTS do
		slots[slot] = true
	end
	for itemId, item in config.Equipment.BY_ID do
		if not slots[item.slot] then
			fail(`Equipment {itemId}: unknown slot "{item.slot}"`)
		end
		for stat, multiplier in item.modifiers do
			if not statNames[stat] then
				fail(`Equipment {itemId}: modifies unknown ship stat "{stat}"`)
			end
			if multiplier <= 0 then
				fail(`Equipment {itemId}: multiplier for {stat} must be positive`)
			end
		end
		checkCost(`Equipment {itemId}`, item.cost)
	end

	-- Recipes: inputs and outputs exist; enabled recipes only need materials from enabled zones.
	local celestials = config.Celestials.BY_ID
	local components = config.Recipes.COMPONENTS
	local function isItem(id: string): boolean
		return components[id] ~= nil or celestials[id] ~= nil
	end
	for recipeId, recipe in config.Recipes.BY_ID do
		checkMaterials(`Recipe {recipeId}`, recipe.materials)
		for itemId, n in recipe.items do
			if not isItem(itemId) then
				fail(`Recipe {recipeId}: unknown input item "{itemId}"`)
			end
			if n <= 0 then
				fail(`Recipe {recipeId}: amount of {itemId} must be positive`)
			end
		end
		if not isItem(recipe.output) then
			fail(`Recipe {recipeId}: unknown output "{recipe.output}"`)
		end
		if recipe.outputCount < 1 then
			fail(`Recipe {recipeId}: outputCount must be at least 1`)
		end
		if recipe.enabled then
			for material in recipe.materials do
				if not minableEnabled[material] then
					fail(
						`Recipe {recipeId} is enabled but {material} is not minable in any enabled zone`
					)
				end
			end
			local output = celestials[recipe.output]
			if output and not output.enabled then
				fail(`Recipe {recipeId} is enabled but makes disabled celestial {recipe.output}`)
			end
		end
	end

	-- Galaxy geometry: fixed orbits must keep every body apart and inside SYSTEM_RADIUS.
	local moonOrbits: { number } = galaxy.MOON_ORBIT_RADII
	local planetOrbits: { number } = galaxy.PLANET_ORBIT_RADII
	local planetExtent = moonOrbits[#moonOrbits] + galaxy.MOON_MAX_RADIUS
	if moonOrbits[1] - galaxy.MOON_MAX_RADIUS <= galaxy.PLANET_MAX_RADIUS then
		fail("Galaxy: the innermost moon orbit would touch its planet")
	end
	for i = 2, #moonOrbits do
		if moonOrbits[i] - moonOrbits[i - 1] <= 2 * galaxy.MOON_MAX_RADIUS then
			fail(`Galaxy: moon orbits {i - 1} and {i} are too close`)
		end
	end
	if planetOrbits[1] - planetExtent <= galaxy.STAR_MAX_RADIUS then
		fail("Galaxy: the innermost planet orbit would touch its star")
	end
	for i = 2, #planetOrbits do
		if planetOrbits[i] - planetOrbits[i - 1] <= 2 * planetExtent then
			fail(`Galaxy: planet orbits {i - 1} and {i} are too close for planets with moons`)
		end
	end
	if planetOrbits[#planetOrbits] + planetExtent > galaxy.SYSTEM_RADIUS then
		fail("Galaxy: the outermost orbit reaches beyond SYSTEM_RADIUS")
	end
	if galaxy.MIN_STAR_SPACING < 2 * galaxy.SYSTEM_RADIUS then
		fail("Galaxy: MIN_STAR_SPACING must be at least 2 x SYSTEM_RADIUS")
	end
	if galaxy.WALL_MARGIN < galaxy.SYSTEM_RADIUS then
		fail("Galaxy: WALL_MARGIN must be at least SYSTEM_RADIUS")
	end

	local previousSize = nil
	local previousSystems = 0
	for level, expansion in galaxy.EXPANSIONS do
		local size = expansion.size
		if level == 1 and expansion.cost ~= nil then
			fail("Galaxy: the starting expansion must be free")
		elseif level > 1 then
			if expansion.cost == nil then
				fail(`Galaxy: expansion {level} needs a cost`)
			end
			checkCost(`Galaxy expansion {level}`, expansion.cost)
		end
		if
			previousSize
			and (size.x < previousSize.x or size.y < previousSize.y or size.z < previousSize.z)
		then
			fail(`Galaxy: expansion {level} is smaller than the one before`)
		end
		if expansion.maxSystems < previousSystems then
			fail(`Galaxy: expansion {level} allows fewer systems than the one before`)
		end
		-- Enough room for maxSystems stars on a MIN_STAR_SPACING lattice?
		local fit = 1
		for _, axis in { size.x, size.y } do
			local inner = axis - 2 * galaxy.WALL_MARGIN
			if inner < 0 then
				fit = 0
			else
				fit *= math.floor(inner / galaxy.MIN_STAR_SPACING) + 1
			end
		end
		local innerDepth = size.z - 2 * galaxy.WALL_MARGIN
		fit *= if innerDepth < 0 then 0 else math.floor(innerDepth / galaxy.MIN_STAR_SPACING) + 1
		if fit < expansion.maxSystems then
			fail(`Galaxy: expansion {level} cannot physically fit {expansion.maxSystems} systems`)
		end
		previousSize = size
		previousSystems = expansion.maxSystems
	end

	-- Celestials: sizes inside the geometry caps, slots inside the orbit tables.
	local maxRadius = {
		star = galaxy.STAR_MAX_RADIUS,
		planet = galaxy.PLANET_MAX_RADIUS,
		moon = galaxy.MOON_MAX_RADIUS,
	}
	local maxLevels = { star = 0, planet = 0, moon = 0 }
	for typeId, def in celestials do
		if #def.levels == 0 then
			fail(`Celestial {typeId} has no levels`)
		end
		if #def.appearances == 0 then
			fail(`Celestial {typeId} has no appearances`)
		end
		if def.enabled then
			maxLevels[def.kind] = math.max(maxLevels[def.kind], #def.levels)
		end
		local previousIncome = -1
		for index, levelDef in def.levels do
			local where = `Celestial {typeId} level {index}`
			if index == 1 and levelDef.upgradeCost ~= nil then
				fail(`{where}: the first level must not have an upgrade cost`)
			elseif index > 1 and levelDef.upgradeCost == nil then
				fail(`{where}: needs an upgrade cost`)
			end
			checkCost(where, levelDef.upgradeCost)
			if levelDef.radius <= 0 or levelDef.radius > maxRadius[def.kind] then
				fail(`{where}: radius {levelDef.radius} is outside 0..{maxRadius[def.kind]}`)
			end
			if levelDef.planetSlots > #planetOrbits then
				fail(`{where}: more planet slots than planet orbits`)
			end
			if levelDef.moonSlots > #moonOrbits then
				fail(`{where}: more moon slots than moon orbits`)
			end
			local value = if def.kind == "moon" then levelDef.moonBonus else levelDef.income
			if value < previousIncome then
				fail(`{where}: income or bonus goes down`)
			end
			previousIncome = value
		end
	end

	-- What a level allows, taking the best enabled type of that kind.
	local function bestAt(kind: string, level: number, field: string): number
		local best = 0
		for _, def in celestials do
			if def.kind == kind and def.enabled then
				local levelDef = def.levels[math.min(level, #def.levels)]
				best = math.max(best, levelDef[field])
			end
		end
		return best
	end

	-- Solar-system tiers: tier N must be reachable under tier N-1's caps.
	local tiers = config.SolarSystems.TIERS
	for index, tier in tiers do
		local where = `Solar system tier {index}`
		if index == 1 then
			if tier.requirements ~= nil then
				fail(`{where}: the first tier must have no requirements`)
			end
			continue
		end
		local previous = tiers[index - 1]
		local caps = previous.levelCaps
		if
			caps.star > maxLevels.star
			or caps.planet > maxLevels.planet
			or caps.moon > maxLevels.moon
		then
			-- Caps above the highest level are harmless but usually a typo.
			fail(`Solar system tier {index - 1}: level caps exceed the highest celestial levels`)
		end
		local req = tier.requirements
		if req == nil then
			fail(`{where}: needs requirements`)
			continue
		end
		checkCost(where, req.cost)
		if req.starLevel > caps.star then
			fail(
				`{where}: needs star level {req.starLevel} but tier {index - 1} caps stars at {caps.star}`
			)
		end
		if req.planetMinLevel > caps.planet then
			fail(
				`{where}: needs planets at level {req.planetMinLevel} but tier {index - 1} caps planets at {caps.planet}`
			)
		end
		local slotsAllowed = math.min(
			bestAt("star", caps.star, "planetSlots") + previous.bonusPlanetSlots,
			#planetOrbits
		)
		if req.planets > slotsAllowed then
			fail(
				`{where}: needs {req.planets} planets but tier {index - 1} allows only {slotsAllowed}`
			)
		end
		local moonSlots = req.planets * bestAt("planet", caps.planet, "moonSlots")
		if req.moons > moonSlots then
			fail(`{where}: needs {req.moons} moons but its planets can hold only {moonSlots}`)
		end
		if tier.incomeMultiplier < previous.incomeMultiplier then
			fail(`{where}: income multiplier goes down`)
		end
		if
			tier.levelCaps.star < caps.star
			or tier.levelCaps.planet < caps.planet
			or tier.levelCaps.moon < caps.moon
		then
			fail(`{where}: level caps go down`)
		end
	end

	-- Achievements, cosmetics and products.
	local cosmetics = config.Cosmetics.BY_ID
	for achievementId, achievement in config.Achievements.BY_ID do
		if achievement.goal <= 0 then
			fail(`Achievement {achievementId}: goal must be positive`)
		end
		local reward = achievement.reward
		if reward.cosmetic and cosmetics[reward.cosmetic] == nil then
			fail(`Achievement {achievementId}: unknown cosmetic "{reward.cosmetic}"`)
		end
		if reward.ship and config.Ships.BY_ID[reward.ship] == nil then
			fail(`Achievement {achievementId}: unknown ship "{reward.ship}"`)
		end
	end
	for cosmeticId, cosmetic in cosmetics do
		if cosmetic.productKey and config.Products.BY_KEY[cosmetic.productKey] == nil then
			fail(`Cosmetic {cosmeticId}: unknown product "{cosmetic.productKey}"`)
		end
	end
	for key, product in config.Products.BY_KEY do
		if product.key ~= key then
			fail(`Product {key} has key "{product.key}"`)
		end
		if config.Products.PURCHASES_ENABLED and product.id <= 0 then
			fail(`Product {key} has no id but purchases are enabled`)
		end
		if product.grants.ship and config.Ships.BY_ID[product.grants.ship] == nil then
			fail(`Product {key}: unknown ship "{product.grants.ship}"`)
		end
		if product.grants.cosmetic and cosmetics[product.grants.cosmetic] == nil then
			fail(`Product {key}: unknown cosmetic "{product.grants.cosmetic}"`)
		end
	end

	return problems
end

return ConfigCheck

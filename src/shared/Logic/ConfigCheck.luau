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
		if type(cost.credits) ~= "number" or cost.credits < 0 then
			fail(`{where}: credits must be zero or more`)
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

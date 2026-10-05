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
		if type(ship.model) ~= "string" or ship.model == "" then
			fail(`Ship {shipId}: model must name an asset`)
		end
		if type(ship.modelSize) ~= "number" or ship.modelSize <= 0 then
			fail(`Ship {shipId}: modelSize must be positive`)
		end
		if type(ship.modelYaw) ~= "number" then
			fail(`Ship {shipId}: modelYaw must be a number`)
		end
	end

	-- The ladder (checkOrder covers ORDER itself): the starter first, and each
	-- ship costs more than the one before it.
	local lastCost = 0
	for index, shipId in config.Ships.ORDER do
		local ship = config.Ships.BY_ID[shipId]
		if ship == nil then
			continue
		end
		if index == 1 and shipId ~= starterId then
			fail("Ships.ORDER must start with the starter ship")
		end
		local cost = if ship.earn then ship.earn.stardust else 0
		if index > 1 and cost <= lastCost then
			fail(`Ship {shipId} must cost more than the ship before it`)
		end
		lastCost = cost
	end
	for old, new in config.Ships.RENAMED do
		if config.Ships.BY_ID[new] == nil then
			fail(`Ships.RENAMED: {old} maps to unknown ship {new}`)
		end
	end
	if config.Ships.PREVIEW_SPIN < 0 then
		fail("Ships.PREVIEW_SPIN must not be negative")
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
		local s = ship.stats
		if s.boostMultiplier <= 1 or s.boostDuration <= 0 or s.boostRecharge <= 0 then
			fail(
				`Ship {shipId}: boost needs a multiplier above 1 and positive duration and recharge`
			)
		end
	end
	-- Hangar upgrades: known requirements, positive costs and multipliers,
	-- real ship stats, pads on the deck and apart from each other.
	local hangar = config.Hangar
	checkOrder("Hangar", hangar.ORDER, hangar.BY_ID)
	for id, def in hangar.BY_ID do
		if type(def.cost) ~= "number" or def.cost <= 0 then
			fail(`Hangar {id}: cost must be positive`)
		end
		for _, need in def.requires do
			if hangar.BY_ID[need] == nil or need == id then
				fail(`Hangar {id}: bad requirement {need}`)
			end
		end
		for stat, multiplier in def.stats or {} do
			if statNames[stat] == nil or multiplier <= 0 then
				fail(`Hangar {id}: bad stat modifier {stat}`)
			end
		end
		if (def.income and def.income <= 0) or (def.storage and def.storage <= 0) then
			fail(`Hangar {id}: multipliers must be positive`)
		end
		if math.abs(def.pad.x) > 26 or math.abs(def.pad.z) > 30 then
			fail(`Hangar {id}: pad is off the deck`)
		end
		for otherId, other in hangar.BY_ID do
			local gap =
				math.max(math.abs(def.pad.x - other.pad.x), math.abs(def.pad.z - other.pad.z))
			if otherId ~= id and gap < 12 then
				fail(`Hangar {id}: pad too close to {otherId}`)
			end
		end
	end

	-- Daily prizes: each day gives exactly one positive prize.
	for day, prize in config.Daily.PRIZES do
		local stardust = prize.stardust and prize.stardust > 0
		local boost = prize.boost
			and prize.boost.seconds > 0
			and (prize.boost.source == "mining" or prize.boost.source == "star")
		if (stardust and 1 or 0) + (boost and 1 or 0) ~= 1 then
			fail(`Daily day {day}: needs exactly one positive prize`)
		end
	end

	-- Raids: harder difficulties pay more and have tougher bosses.
	local raids = config.Raids
	local lastStardust, lastHealth = 0, 0
	for _, id in raids.ORDER do
		local def = raids.BY_ID[id]
		if def == nil or def.id ~= id then
			fail(`Raid {id}: missing or misnamed`)
			continue
		end
		if def.reward.stardust <= lastStardust or def.bossHealth <= lastHealth then
			fail(`Raid {id}: must pay more and be tougher than the difficulty before it`)
		end
		lastStardust, lastHealth = def.reward.stardust, def.bossHealth
		-- Every move present needs a positive interval and damage (and count).
		for name, move in def.moves :: { [string]: any } do
			local count = move.count or move.bolts or 1
			if
				type(move.interval) ~= "number"
				or move.interval <= 0
				or type(move.damage) ~= "number"
				or move.damage <= 0
				or count < 1
			then
				fail(`Raid {id}: move {name} needs a positive interval, damage and count`)
			end
		end
		local boost = def.reward.boost
		if
			boost and (boost.seconds <= 0 or (boost.source ~= "mining" and boost.source ~= "star"))
		then
			fail(`Raid {id}: bad boost reward`)
		end
	end
	if
		raids.MAX_RAIDERS < 1
		or raids.QUEUE_COUNTDOWN < raids.FULL_COUNTDOWN
		or raids.TIME_LIMIT <= 0
	then
		fail("Raids: bad queue or time settings")
	end
	if
		raids.WEAK_POINT_MOVE_SHARE <= 0
		or raids.WEAK_POINT_MOVE_SHARE >= 1
		or raids.WEAK_POINT_MIN_ANGLE <= 0
		or raids.WEAK_POINT_MIN_ANGLE > 120
		or raids.ENRAGE_SHARE <= 0
		or raids.ENRAGE_SHARE >= 1
		or raids.ENRAGE_SPEEDUP < 1
	then
		fail("Raids: bad weak point or enrage settings")
	end
	if raids.DRONE_SPEED <= 0 or raids.SHOCKWAVE_SPEED <= 0 or raids.BOMBARD_DELAY <= 0 then
		fail("Raids: drones, shockwaves and bombardment need positive speeds and delays")
	end

	-- Codes: upper case (players' input is upper-cased), each with a reward.
	for code, def in config.Codes.BY_CODE do
		if code ~= string.upper(code) or #code > config.Codes.MAX_LENGTH then
			fail(`Code {code}: must be upper case and at most MAX_LENGTH letters`)
		end
		if (def.stardust or 0) <= 0 and def.boost == nil then
			fail(`Code {code}: needs a reward`)
		end
	end

	-- Leaderboard store.
	local board = config.Leaderboard
	if board.STORE == "" or board.SCOPE == "" or board.WRITE_INTERVAL < 6 then
		fail("Leaderboard: needs a store name, a scope, and at least 6 s between writes")
	end

	-- Badges: a real id, a stat and a positive goal.
	for key, badge in config.Badges.BY_KEY do
		if badge.id <= 0 or badge.goal <= 0 or badge.stat == "" then
			fail(`Badge {key}: needs a Creator Hub id, a stat and a positive goal`)
		end
	end

	-- Trails: known colours, multipliers above 1.
	for _, id in config.Trails.ORDER do
		local def = config.Trails.BY_ID[id]
		if
			def == nil
			or def.id ~= id
			or def.multiplier <= 1
			or def.cost <= 0
			or #def.colors < 1
		then
			fail(`Trail {id}: needs a multiplier above 1, a price and colours`)
		end
	end
	-- Rockets.
	local rockets = config.Rockets
	for _, name in
		{ "COOLDOWN", "SPEED", "LIFETIME", "HIT_RADIUS", "BLAST_RADIUS", "POWER", "MAX_AIM_ANGLE" }
	do
		local value = rockets[name]
		if type(value) ~= "number" or value <= 0 then
			fail(`Rockets: {name} must be a positive number`)
		end
	end
	-- Ship colours.
	for _, hex in config.Paint.SWATCHES do
		if type(hex) ~= "string" or string.match(hex, "^#%x%x%x%x%x%x$") == nil then
			fail(`Paint: {hex} is not a #RRGGBB colour`)
		end
	end

	-- Zero G Dodgeball.
	local dodge = config.Dodgeball
	for _, name in
		{
			"BLOCK_COUNT",
			"SPAWN_COUNT",
			"SPEED_MULTIPLIER",
			"LAUNCH_SPEED",
			"LAUNCH_REACH",
			"LAUNCH_TIME",
			"THROW_COOLDOWN",
			"BALL_SPEED",
			"BALL_RADIUS",
			"BALL_LIFETIME",
			"OUT_TIME",
			"KNOCKBACK",
			"MEMBERSHIP_TICK",
		}
	do
		local value = dodge[name]
		if type(value) ~= "number" or value <= 0 then
			fail(`Dodgeball: {name} must be a positive number`)
		end
	end
	if dodge.BLOCK_SIZE[1] <= 0 or dodge.BLOCK_SIZE[2] < dodge.BLOCK_SIZE[1] then
		fail("Dodgeball: BLOCK_SIZE must be a rising pair of positive sizes")
	end
	local bottom = dodge.CENTER.y - dodge.SIZE.y / 2
	local top = dodge.CENTER.y + dodge.SIZE.y / 2
	local clearOfField = top < -config.Asteroids.HEIGHT or bottom > config.Asteroids.HEIGHT
	if
		math.max(math.abs(bottom), math.abs(top)) > config.Movement.FLIGHT_BOUNDS_HEIGHT
		or not clearOfField
	then
		fail("Dodgeball: the arena must be inside the flight area and clear of the asteroid field")
	end

	-- Combat (opt-in PvP).
	local combat = config.Combat
	for _, name in
		{
			"DAMAGE_PER_POWER",
			"REGEN_DELAY",
			"REGEN_SHARE",
			"COMBAT_LOCK",
			"TOGGLE_COOLDOWN",
			"RELAUNCH_DELAY",
			"SERVER_TICK",
			"EXPLOSION_SIZE",
			"EXPLOSION_TIME",
			"DEBRIS_LIFETIME",
			"SHAKE_RADIUS",
			"TAG_DISTANCE",
			"HIT_MARKER_TIME",
		}
	do
		local value = combat[name]
		if type(value) ~= "number" or value <= 0 then
			fail(`Combat: {name} must be a positive number`)
		end
	end
	if combat.DEBRIS_SPEED[1] > combat.DEBRIS_SPEED[2] then
		fail("Combat: DEBRIS_SPEED must be { min, max }")
	end
	if combat.EMBER_SHARE < 0 or combat.EMBER_SHARE > 1 or combat.DEBRIS_DRAG >= 1 then
		fail("Combat: EMBER_SHARE must be 0..1 and DEBRIS_DRAG below 1")
	end
	if movement.ALT_TAP_TIME <= 0 or movement.SHOULDER_SMOOTHING <= 0 then
		fail("Movement: ALT_TAP_TIME and SHOULDER_SMOOTHING must be positive")
	end
	if movement.BOOST_RESTART_SHARE <= 0 or movement.BOOST_RESTART_SHARE > 1 then
		fail("Movement: BOOST_RESTART_SHARE must be between 0 and 1")
	end
	for _, name in { "SHIP_REVERSE_FACTOR", "SHIP_STRAFE_FACTOR", "SHIP_IDLE_BRAKE_FACTOR" } do
		local value = movement[name]
		if type(value) ~= "number" or value <= 0 or value > 1 then
			fail(`Movement: {name} must be between 0 and 1`)
		end
	end

	for _, name in
		{
			"SHIP_MAX_BANK_DEGREES",
			"SUIT_IDLE_LEAN_DEGREES",
			"SUIT_LEAN_DEGREES",
			"SUIT_ROLL_DEGREES",
		}
	do
		local value = movement[name]
		if type(value) ~= "number" or value < 0 or value >= 90 then
			fail(`Movement: {name} must be from 0 up to 90`)
		end
	end
	if movement.SUIT_IDLE_LEAN_DEGREES > movement.SUIT_LEAN_DEGREES then
		fail("Movement: SUIT_IDLE_LEAN_DEGREES must not exceed SUIT_LEAN_DEGREES")
	end
	if
		movement.SUIT_SOUND_VOLUME < 0
		or movement.SUIT_SOUND_VOLUME > 1
		or movement.SUIT_SOUND_PITCH[1] <= 0
		or movement.SUIT_SOUND_PITCH[2] < movement.SUIT_SOUND_PITCH[1]
	then
		fail("Movement: SUIT_SOUND_VOLUME must be 0 to 1 and SUIT_SOUND_PITCH a rising pair")
	end
	if movement.SUIT_FLOOR_GAP < 0 or movement.SUIT_FLOOR_PUSH <= 0 then
		fail("Movement: SUIT_FLOOR_GAP must be 0 or more and SUIT_FLOOR_PUSH positive")
	end
	if movement.CAMERA_FOV + movement.CAMERA_FOV_BOOST + movement.CAMERA_BOOST_FOV > 120 then
		fail("Movement: CAMERA_FOV plus both FOV boosts is over Roblox's limit of 120")
	end

	-- Mining beam: every ship fires for a while before it overheats.
	local beam = config.Beam
	if type(beam.HEAT_PER_SHOT) ~= "number" or beam.HEAT_PER_SHOT <= 0 then
		fail("Beam: HEAT_PER_SHOT must be a positive number")
	else
		for shipId, ship in config.Ships.BY_ID do
			if ship.stats.heatCapacity / beam.HEAT_PER_SHOT < 4 then
				fail(`Beam: ship {shipId} overheats in under 4 shots`)
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
	if
		asteroids.CLUSTER_SKEW <= 0
		or asteroids.CLUSTER_SPREAD_MIN <= 0
		or asteroids.CLUSTER_SPREAD_MAX < asteroids.CLUSTER_SPREAD_MIN
		or asteroids.STREAM_CHANCE < 0
		or asteroids.STREAM_CHANCE > 1
		or asteroids.SIZE_JITTER < 0
		or asteroids.SIZE_JITTER >= 0.5
	then
		fail("Asteroids: bad group spread, stream chance or size jitter")
	end
	if
		asteroids.SWARM_INTERVAL <= asteroids.SWARM_DURATION
		or asteroids.SWARM_COUNT < 1
		or asteroids.SWARM_REWARD < 1
		or asteroids.SWARM_DURABILITY < 1
		or asteroids.SWARM_SPREAD <= 0
	then
		fail(
			"Asteroids: the golden swarm needs a positive count, spread and reward, and to end before the next"
		)
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

	-- Stars and planets: a clean tier ladder each, planets fit their orbit
	-- slots inside SYSTEM_RADIUS and clear of the largest star, prices and
	-- production rise with tier, levels only improve.
	local stars = config.Stars
	local planets = config.Planets
	checkOrder("Stars", stars.ORDER, stars.BY_ID)
	checkOrder("Planets", planets.ORDER, planets.BY_ID)
	local defaultStar = stars.BY_ID[stars.DEFAULT_TYPE]
	if defaultStar == nil or not defaultStar.enabled or defaultStar.tier ~= 1 then
		fail("Stars: DEFAULT_TYPE must exist, be enabled and be tier 1")
	elseif config.Economy.STARTING_STARDUST < defaultStar.cost then
		fail("Economy: STARTING_STARDUST doesn't cover the first star")
	end
	if stars.PRICE_GROWTH < 1 then
		fail("Stars: PRICE_GROWTH must be at least 1")
	end
	local function checkLadder(name: string, order: { string }, byId: { [string]: any })
		local previous: any = nil
		for index, id in order do
			local def = byId[id]
			if def == nil then
				continue
			end
			if def.tier ~= index then
				fail(`{name} {id}: tier must be {index} (its place in ORDER)`)
			end
			if def.cost <= 0 or def.income <= 0 then
				fail(`{name} {id}: cost and income must be positive`)
			end
			if previous and (def.cost <= previous.cost or def.income <= previous.income) then
				fail(`{name} {id}: must cost and earn more than {previous.id}`)
			end
			previous = def
		end
	end
	checkLadder("Star", stars.ORDER, stars.BY_ID)
	checkLadder("Planet", planets.ORDER, planets.BY_ID)
	-- Levels: max levels stay even; production and upgrade prices only rise.
	if stars.MAX_LEVEL_BASE < 2 or stars.MAX_LEVEL_BASE % 2 ~= 0 then
		fail("Stars: MAX_LEVEL_BASE must be an even number of at least 2")
	end
	if stars.MAX_LEVEL_STEP < 2 or stars.MAX_LEVEL_STEP % 2 ~= 0 then
		fail("Stars: MAX_LEVEL_STEP must be an even number of at least 2")
	end
	if
		stars.LEVEL_INCOME_LINEAR <= 0
		or stars.LEVEL_INCOME_CURVE < 0
		or stars.UPGRADE_SHARE <= 0
		or stars.UPGRADE_GROWTH < 1
	then
		fail(
			"Stars: LEVEL_INCOME_LINEAR and UPGRADE_SHARE must be positive, LEVEL_INCOME_CURVE not negative, UPGRADE_GROWTH at least 1"
		)
	end
	if stars.MAX_RADIUS_SCALE < 1 then
		fail("Stars: MAX_RADIUS_SCALE must be at least 1")
	end
	-- Orbits: one per tier above ORBITS_BASE, so the top tier needs them all.
	if #stars.SLOTS < stars.ORBITS_BASE + #stars.ORDER - 1 then
		fail("Stars: not enough SLOTS for the top tier's orbits")
	end
	local maxScale = stars.MAX_RADIUS_SCALE
	local largestStar = 0
	for id, def in stars.BY_ID do
		local radius = def.radius * maxScale
		if radius > galaxy.STAR_MAX_RADIUS then
			fail(`Star {id}: at its top level it is bigger than Galaxy.STAR_MAX_RADIUS`)
		end
		largestStar = math.max(largestStar, radius)
	end
	local largestPlanet = 0
	for id, def in planets.BY_ID do
		if def.radius <= 0 or def.radius > galaxy.PLANET_MAX_RADIUS then
			fail(`Planet {id}: radius must be within 0..{galaxy.PLANET_MAX_RADIUS}`)
		end
		-- At its top level a planet is LEVEL_SIZE_STEP x (MAX_LEVEL - 1) bigger.
		local grown = def.radius
			* (1 + config.Planets.LEVEL_SIZE_STEP * (config.Planets.MAX_LEVEL - 1))
		largestPlanet = math.max(largestPlanet, grown)
	end
	for index, slot in stars.SLOTS do
		local where = `Stars slot {index}`
		if slot.orbit + largestPlanet > galaxy.SYSTEM_RADIUS then
			fail(`{where}: orbit reaches past Galaxy.SYSTEM_RADIUS`)
		end
		if slot.orbit - largestPlanet <= largestStar then
			fail(`{where}: a big planet would touch the biggest star`)
		end
		if slot.periodDays <= 0 then
			fail(`{where}: period must be positive`)
		end
		local nextSlot = stars.SLOTS[index + 1]
		if nextSlot and nextSlot.orbit - slot.orbit <= 2 * largestPlanet then
			fail(`{where}: too close to the next orbit`)
		end
	end
	if planets.UPGRADE_CREDIT < 0 or planets.UPGRADE_CREDIT >= 1 then
		fail("Planets: UPGRADE_CREDIT must be from 0 up to 1")
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
	if galaxy.MIN_STAR_SPACING < galaxy.SYSTEM_RADIUS + galaxy.STAR_MAX_RADIUS then
		fail("Galaxy: MIN_STAR_SPACING must keep every planet out of a neighbouring star")
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
		if config.Products.PURCHASES_ENABLED and product.enabled and product.id <= 0 then
			fail(`Product {key} has no id but purchases are enabled`)
		end
		-- Exactly one grant, of a kind that fits the product type.
		local count = 0
		for _ in product.grants do
			count += 1
		end
		if count ~= 1 then
			fail(`Product {key} must grant exactly one thing`)
		end
		local repeatable = product.grants.stardust ~= nil or product.grants.boost ~= nil
		if repeatable ~= (product.kind == "DeveloperProduct") then
			fail(`Product {key}: packs and boosts are developer products, everything else passes`)
		end
		local boost = product.grants.boost
		if
			boost and (boost.seconds <= 0 or (boost.source ~= "mining" and boost.source ~= "star"))
		then
			fail(`Product {key}: bad boost`)
		end
		local multiplier = product.grants.multiplier
		if
			multiplier
			and (
				multiplier.value <= 1
				or (multiplier.source ~= "mining" and multiplier.source ~= "star")
			)
		then
			fail(`Product {key}: bad multiplier`)
		end
		if product.grants.stardust and product.grants.stardust <= 0 then
			fail(`Product {key}: a pack must add Stardust`)
		end
		if product.grants.ship then
			local ship = config.Ships.BY_ID[product.grants.ship]
			-- A Robux ship must also be earnable with Stardust.
			if ship and (ship.earn == nil or ship.productKey ~= key) then
				fail(`Product {key}: its ship must be earnable and point back to it`)
			end
		end
		if not table.find(config.Products.ORDER, key) then
			fail(`Product {key} is missing from Products.ORDER`)
		end
		if product.grants.ship and config.Ships.BY_ID[product.grants.ship] == nil then
			fail(`Product {key}: unknown ship "{product.grants.ship}"`)
		end
		if product.grants.cosmetic and cosmetics[product.grants.cosmetic] == nil then
			fail(`Product {key}: unknown cosmetic "{product.grants.cosmetic}"`)
		end
	end

	-- Sprites: every rect inside the sheet, every slice inside its sprite,
	-- and the image id (when set) in rbxassetid form.
	local sprites = config.Sprites
	if sprites.IMAGE ~= nil and not string.match(sprites.IMAGE, "^rbxassetid://%d+$") then
		fail(`Sprites: IMAGE must look like "rbxassetid://123", not "{sprites.IMAGE}"`)
	end
	for name, def in sprites.SPRITES do
		if
			def.x < 0
			or def.y < 0
			or def.x + def.w > sprites.SHEET_WIDTH
			or def.y + def.h > sprites.SHEET_HEIGHT
		then
			fail(`Sprite {name} is outside the sheet`)
		end
		local cut = def.slice
		if
			cut
			and not (
				0 <= cut.x0
				and cut.x0 < cut.x1
				and cut.x1 <= def.w
				and 0 <= cut.y0
				and cut.y0 < cut.y1
				and cut.y1 <= def.h
			)
		then
			fail(`Sprite {name}: slice centre is outside the sprite`)
		end
	end

	return problems
end

return ConfigCheck

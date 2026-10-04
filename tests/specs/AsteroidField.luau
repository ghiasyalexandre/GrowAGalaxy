return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local AsteroidField = Loader.require("src/shared/Logic/AsteroidField")
	local RegionMath = Loader.require("src/shared/Logic/RegionMath")

	local A = Config.Asteroids

	-- Deterministic stand-in for Random:NextNumber().
	local function lcg(seed: number): () -> number
		local state = seed
		return function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	-- A spot halfway between the ISS clearance and the region ring, between
	-- slots 1 and 2 (22.5 degrees).
	local angle = math.rad(180 / Config.World.MAX_PLAYERS)
	local between = (A.ISS_CLEARANCE + Config.World.REGION_RING_RADIUS - A.REGION_CLEARANCE) / 2
	local open = { x = math.sin(angle) * between, y = 0, z = math.cos(angle) * between }

	T.describe("AsteroidField", function()
		T.test("an open spot between the ISS and the regions is valid", function()
			T.truthy(AsteroidField.isValid(open, 10, {}, {}))
		end)

		T.test("too close to the ISS is rejected", function()
			T.falsy(AsteroidField.inVolume({ x = 0, y = 0, z = A.ISS_CLEARANCE - 5 }, 10))
			T.falsy(AsteroidField.inVolume({ x = 0, y = A.ISS_CLEARANCE - 5, z = 0 }, 10))
		end)

		T.test("outside the spawn height or distance is rejected", function()
			T.falsy(AsteroidField.inVolume({ x = open.x, y = A.HEIGHT, z = open.z }, 10))
			T.falsy(AsteroidField.inVolume({ x = 0, y = 0, z = A.MAX_DISTANCE }, 10))
		end)

		T.test("inside any region slot, at any expansion, is rejected", function()
			local size = Config.Galaxy.EXPANSIONS[#Config.Galaxy.EXPANSIONS].size
			for slot = 1, Config.World.MAX_PLAYERS do
				local centre = RegionMath.toWorld(slot, { x = 0, y = 0, z = size.z / 2 })
				local corner =
					RegionMath.toWorld(slot, { x = size.x / 2 - 1, y = 0, z = size.z - 1 })
				T.falsy(AsteroidField.clearOfRegions(centre, 10), `slot {slot} centre`)
				T.falsy(AsteroidField.clearOfRegions(corner, 10), `slot {slot} far corner`)
			end
		end)

		T.test("a personal station in front of its region is kept clear", function()
			for slot = 1, Config.World.MAX_PLAYERS do
				local station =
					RegionMath.toWorld(slot, { x = 0, y = 0, z = -Config.World.STATION_DISTANCE })
				T.falsy(AsteroidField.clearOfRegions(station, 10), `slot {slot} station`)
			end
		end)

		T.test("asteroids keep MIN_GAP between surfaces", function()
			local other = { position = open, radius = 10 }
			local touching = { x = open.x + 20 + A.MIN_GAP - 1, y = open.y, z = open.z }
			local apart = { x = open.x + 20 + A.MIN_GAP + 1, y = open.y, z = open.z }
			T.falsy(AsteroidField.isValid(touching, 10, { other }, {}))
			T.truthy(AsteroidField.isValid(apart, 10, { other }, {}))
		end)

		T.test("ships and players block spawning within their clearance", function()
			local ship = { position = open, radius = A.SHIP_CLEARANCE }
			T.falsy(AsteroidField.isValid(open, 10, {}, { ship }))
		end)

		T.test("sizes are picked by weight and every size can come up", function()
			local rng = lcg(7)
			local seen = {}
			for _ = 1, 500 do
				local id = AsteroidField.pickSize(rng)
				T.truthy(A.SIZES[id], `known size {id}`)
				seen[id] = (seen[id] or 0) + 1
			end
			for _, id in A.SIZE_ORDER do
				T.truthy(seen[id], `size {id} was picked`)
			end
			T.truthy(seen.Small > seen.Large, "Small is more common than Large")
		end)

		T.test(
			"the volume has room for MAX_COUNT asteroids with the configured attempts",
			function()
				-- Greedy fill, the way AsteroidSystem places them (largest extent,
				-- worst case), with a fixed seed so the test is repeatable.
				local rng = lcg(42)
				local extent = A.SIZES.Large.radius * 1.4
				local placed = {}
				local attempts = 0
				while #placed < A.MAX_COUNT and attempts < A.MAX_COUNT * A.PLACEMENT_ATTEMPTS do
					attempts += 1
					local p = AsteroidField.randomPoint(rng)
					if AsteroidField.isValid(p, extent, placed, {}) then
						table.insert(placed, { position = p, radius = extent })
					end
				end
				T.equal(#placed, A.MAX_COUNT)
			end
		)

		T.test("cluster members stay within the spread of their centre", function()
			local rng = lcg(3)
			for _ = 1, 100 do
				local p = AsteroidField.near(open, A.CLUSTER_SPREAD, rng)
				local d = math.sqrt((p.x - open.x) ^ 2 + (p.y - open.y) ^ 2 + (p.z - open.z) ^ 2)
				T.truthy(d <= A.CLUSTER_SPREAD + 1e-6)
			end
		end)
	end)
end

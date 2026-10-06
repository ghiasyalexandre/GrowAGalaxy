return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local PlacementRules = Loader.require("src/shared/Logic/PlacementRules")

	local G = Config.Galaxy
	local size = G.EXPANSIONS[1].size
	local centre = { x = 0, y = 0, z = size.z / 2 }

	T.describe("PlacementRules", function()
		T.test("accepts a star in the middle of an empty region", function()
			local ok, reason = PlacementRules.checkStar(centre, 1, {})
			T.truthy(ok)
			T.equal(reason, nil)
		end)

		T.test("rejects stars whose footprint would leave the region, saying which way", function()
			local box = PlacementRules.buildBox(1)
			local cases = {
				{ pos = { x = box.max.x + 1, y = 0, z = centre.z }, reason = "OutOfBounds" },
				{ pos = { x = 0, y = 0, z = box.min.z - 1 }, reason = "OutOfBounds" },
				{ pos = { x = 0, y = 0, z = box.max.z + 1 }, reason = "OutOfBounds" },
				{ pos = { x = 0, y = box.max.y + 1, z = centre.z }, reason = "TooHigh" },
				{ pos = { x = 0, y = box.min.y - 1, z = centre.z }, reason = "TooHigh" },
			}
			for i, case in cases do
				local ok, reason = PlacementRules.checkStar(case.pos, 1, {})
				T.falsy(ok, `case {i}`)
				T.equal(reason, case.reason, `case {i}`)
			end
			-- The edges of the box themselves are fine.
			T.truthy((PlacementRules.checkStar(box.max, 1, {})))
			T.truthy((PlacementRules.checkStar(box.min, 1, {})))
		end)

		T.test("the build box leaves real room to move up and down", function()
			local box = PlacementRules.buildBox(1)
			T.truthy(box.max.y - box.min.y >= 400, "at least 400 studs of height")
			T.equal(box.max.y, size.y / 2 - G.WALL_MARGIN_Y)
		end)

		T.test("footprints may not overlap, but may stack vertically", function()
			local other = { x = 0, y = 0, z = centre.z + 2 * G.SYSTEM_RADIUS - 10 }
			local ok, reason, short = PlacementRules.checkStar(centre, 3, { other })
			T.falsy(ok)
			T.equal(reason, "TooClose")
			T.equal(short, 10)
			local beside = { x = 0, y = 0, z = centre.z + 2 * G.SYSTEM_RADIUS }
			T.truthy((PlacementRules.checkStar(centre, 3, { beside })))
			local above = { x = 0, y = 2 * G.SYSTEM_HALF_HEIGHT, z = centre.z }
			T.truthy((PlacementRules.checkStar(centre, 3, { above })), "stacked above")
		end)

		T.test("clamp pulls any aim into the build box", function()
			local clamped = PlacementRules.clamp({ x = 1e6, y = -1e6, z = -50 }, 1)
			local box = PlacementRules.buildBox(1)
			T.equal(clamped.x, box.max.x)
			T.equal(clamped.y, box.min.y)
			T.equal(clamped.z, box.min.z)
			T.truthy((PlacementRules.checkStar(clamped, 1, {})))
		end)

		T.test("the nearest valid spot is found when the aim is blocked", function()
			local spot = PlacementRules.nearestValid(centre, 2, { centre })
			T.truthy(spot ~= nil)
			T.truthy((PlacementRules.checkStar(spot, 2, { centre })))
			-- An aim outside the region starts at the closest valid point inside.
			local fromOutside = PlacementRules.nearestValid({ x = 0, y = 0, z = -500 }, 1, {})
			T.truthy(fromOutside ~= nil and fromOutside.z == PlacementRules.buildBox(1).min.z)
		end)

		T.test("rejects malformed positions", function()
			local nan = 0 / 0
			for i, pos in
				{ nil, 5, {}, { x = nan, y = 0, z = 500 }, { x = math.huge, y = 0, z = 500 } }
			do
				local ok, reason = PlacementRules.checkStar(pos, 1, {})
				T.falsy(ok, `case {i}`)
				T.equal(reason, "Invalid", `case {i}`)
			end
		end)

		T.test("capacity follows the expansion level", function()
			local first = G.EXPANSIONS[1].maxSystems
			T.truthy(PlacementRules.hasCapacity(0, 1))
			T.falsy(PlacementRules.hasCapacity(first, 1))
			T.truthy(PlacementRules.hasCapacity(first, 2))
			T.falsy(PlacementRules.hasCapacity(G.EXPANSIONS[2].maxSystems, 2))
		end)

		T.test("snap rounds to the grid", function()
			local snapped = PlacementRules.snap({ x = 14, y = -16, z = 25 }, 10)
			T.equal(snapped.x, 10)
			T.equal(snapped.y, -20)
			T.equal(snapped.z, 30)
		end)
	end)
end

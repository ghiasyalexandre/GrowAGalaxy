return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local PlacementRules = Loader.require("src/shared/Logic/PlacementRules")

	local margin = Config.Galaxy.WALL_MARGIN
	local size = Config.Galaxy.EXPANSIONS[1].size
	local centre = { x = 0, y = 0, z = size.z / 2 }

	T.describe("PlacementRules", function()
		T.test("accepts a star in the middle of an empty region", function()
			local ok, reason = PlacementRules.checkStar(centre, 1, {})
			T.truthy(ok)
			T.equal(reason, nil)
		end)

		T.test("rejects stars too close to a wall", function()
			local tests = {
				{ x = size.x / 2 - margin + 1, y = 0, z = size.z / 2 },
				{ x = 0, y = -(size.y / 2 - margin + 1), z = size.z / 2 },
				{ x = 0, y = 0, z = margin - 1 },
				{ x = 0, y = 0, z = size.z - margin + 1 },
			}
			for i, pos in tests do
				local ok, reason = PlacementRules.checkStar(pos, 1, {})
				T.falsy(ok, `case {i}`)
				T.equal(reason, "OutOfBounds", `case {i}`)
			end
		end)

		T.test("rejects a star closer than the minimum spacing", function()
			local other = { x = 0, y = 0, z = size.z / 2 + Config.Galaxy.MIN_STAR_SPACING - 1 }
			local ok, reason = PlacementRules.checkStar(centre, 3, { other })
			T.falsy(ok)
			T.equal(reason, "TooClose")
		end)

		T.test("accepts a star exactly at the minimum spacing", function()
			local spacing = Config.Galaxy.MIN_STAR_SPACING
			local a = { x = -spacing / 2, y = 0, z = 700 }
			local b = { x = spacing / 2, y = 0, z = 700 }
			local ok = PlacementRules.checkStar(a, 2, { b })
			T.truthy(ok)
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
			local first = Config.Galaxy.EXPANSIONS[1].maxSystems
			T.truthy(PlacementRules.hasCapacity(0, 1))
			T.falsy(PlacementRules.hasCapacity(first, 1))
			T.truthy(PlacementRules.hasCapacity(first, 2))
			T.falsy(PlacementRules.hasCapacity(Config.Galaxy.EXPANSIONS[2].maxSystems, 2))
		end)

		T.test("snap rounds to the grid", function()
			local snapped = PlacementRules.snap({ x = 14, y = -16, z = 25 }, 10)
			T.equal(snapped.x, 10)
			T.equal(snapped.y, -20)
			T.equal(snapped.z, 30)
		end)
	end)
end

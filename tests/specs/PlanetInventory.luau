return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local PlanetInventory = Loader.require("src/shared/Logic/PlanetInventory")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local P = Config.Planets

	local function setup()
		local stars = {
			s1 = { typeId = "BrownDwarf", level = 1, pos = { x = 0, y = 0, z = 0 } }, -- 3 orbits
			s2 = { typeId = "BlackHole", level = 1, pos = { x = 0, y = 0, z = 0 } }, -- 9 orbits
		}
		local planets = {
			p1 = { typeId = "Basalt", level = 2, star = "s1", slot = 1 },
			p2 = { typeId = "Aurora", level = 1 },
			p3 = { typeId = "Singularity", level = 5 },
		}
		return stars, planets
	end

	T.describe("PlanetInventory", function()
		T.test("equips an inventory planet into an open, empty orbit", function()
			local stars, planets = setup()
			T.truthy((PlanetInventory.equip(planets, stars, "p2", "s1", 2)))
			T.equal(planets.p2.star, "s1")
			T.equal(planets.p2.slot, 2)
			T.equal(PlanetInventory.occupant(planets, "s1", 2), "p2")
		end)

		T.test("refuses locked, taken, unknown and fractional slots", function()
			local stars, planets = setup()
			local _, locked = PlanetInventory.check(planets, stars, "p2", "s1", 4)
			T.equal(locked, "SlotLocked")
			local _, taken = PlanetInventory.check(planets, stars, "p2", "s1", 1)
			T.equal(taken, "SlotTaken")
			local _, noStar = PlanetInventory.check(planets, stars, "p2", "nope", 1)
			T.equal(noStar, "UnknownStar")
			local _, noPlanet = PlanetInventory.check(planets, stars, "p9", "s1", 2)
			T.equal(noPlanet, "UnknownPlanet")
			local _, fraction = PlanetInventory.check(planets, stars, "p2", "s1", 1.5)
			T.equal(fraction, "SlotLocked")
			T.equal(planets.p2.star, nil)
		end)

		T.test("moving keeps the level and leaves the old slot empty in one step", function()
			local stars, planets = setup()
			T.truthy((PlanetInventory.equip(planets, stars, "p1", "s2", 9)))
			T.equal(planets.p1.star, "s2")
			T.equal(planets.p1.slot, 9)
			T.equal(planets.p1.level, 2)
			T.equal(PlanetInventory.occupant(planets, "s1", 1), nil)
			-- Re-equipping into its own slot is allowed (no-op).
			T.truthy((PlanetInventory.equip(planets, stars, "p1", "s2", 9)))
		end)

		T.test("unequip returns to inventory; the planet stops producing", function()
			local stars, planets = setup()
			local before = StarMath.totalIncome(stars, planets)
			T.truthy(PlanetInventory.unequip(planets, "p1"))
			T.equal(planets.p1.star, nil)
			T.equal(planets.p1.slot, nil)
			T.near(
				before - StarMath.totalIncome(stars, planets),
				StarMath.planetIncome("Basalt", 2, 1, StarMath.starIncome("BrownDwarf", 1))
			)
			T.falsy(PlanetInventory.unequip(planets, "p9"))
		end)

		T.test("income counts each equipped planet exactly once", function()
			local stars, planets = setup()
			PlanetInventory.equip(planets, stars, "p2", "s2", 1)
			PlanetInventory.equip(planets, stars, "p3", "s2", 2)
			local brown, hole =
				StarMath.starIncome("BrownDwarf", 1), StarMath.starIncome("BlackHole", 1)
			local expected = brown
				+ hole
				+ StarMath.planetIncome("Basalt", 2, 1, brown)
				+ StarMath.planetIncome("Aurora", 1, 1, hole)
				+ StarMath.planetIncome("Singularity", 5, 1, hole)
			T.near(StarMath.totalIncome(stars, planets), expected)
			local on = PlanetInventory.equippedOn(planets, "s2")
			T.near(
				StarMath.income(stars.s2, on),
				hole
					+ StarMath.planetIncome("Aurora", 1, 1, hole)
					+ StarMath.planetIncome("Singularity", 5, 1, hole)
			)
		end)

		T.test("free slots fill in order and stop at the star's orbits", function()
			local stars, planets = setup()
			T.equal(PlanetInventory.freeSlot(planets, "s1", stars.s1), 2)
			PlanetInventory.equip(planets, stars, "p2", "s1", 2)
			PlanetInventory.equip(planets, stars, "p3", "s1", 3)
			T.equal(PlanetInventory.freeSlot(planets, "s1", stars.s1), nil)
		end)

		T.test("removing a star sends its planets back to inventory", function()
			local stars, planets = setup()
			PlanetInventory.equip(planets, stars, "p2", "s1", 2)
			T.equal(PlanetInventory.releaseStar(planets, "s1"), 2)
			stars.s1 = nil
			T.equal(planets.p1.star, nil)
			T.equal(planets.p2.star, nil)
			T.near(StarMath.totalIncome(stars, planets), StarMath.starIncome("BlackHole", 1))
		end)

		T.test(
			"sale value: a share of the roll price plus a quarter of the levelling spent",
			function()
				T.equal(
					PlanetInventory.sellValue({
						typeId = "Basalt",
						level = 1,
						tier = 1,
						paid = 1000,
					}),
					math.floor(1000 * P.SELL_FRACTION.Common)
				)
				T.equal(
					PlanetInventory.sellValue({
						typeId = "Aurora",
						level = 3,
						tier = 7,
						paid = 5000,
						spent = 4000,
					}),
					math.floor(5000 * P.SELL_FRACTION.Rare + 4000 * P.SELL_LEVEL_REFUND),
					"tier adds nothing"
				)
				T.equal(
					PlanetInventory.sellValue({
						typeId = "Basalt",
						level = 1,
						tier = 1,
						legacy = 40,
					}),
					40,
					"a planet from before economy v2 keeps its fixed value"
				)
				T.equal(
					PlanetInventory.sellValue({ typeId = "Basalt", level = 1, tier = 1 }),
					0,
					"free"
				)
				T.equal(PlanetInventory.sellValue({ typeId = "Nope", level = 1, tier = 1 }), 0)
				-- Resale never returns what a planet cost.
				for _, rarity in P.RARITY_ORDER do
					T.truthy(P.SELL_FRACTION[rarity] < 1 and P.SELL_LEVEL_REFUND < 1, rarity)
				end
			end
		)

		T.test("only unlocked inventory planets can be sold", function()
			local _, planets = setup()
			planets.p2.locked = true
			T.equal(select(2, PlanetInventory.canSell(planets, "p1")), "InOrbit")
			T.equal(select(2, PlanetInventory.canSell(planets, "p2")), "Locked")
			T.truthy((PlanetInventory.canSell(planets, "p3")))
			T.equal(select(2, PlanetInventory.canSell(planets, "p9")), "UnknownPlanet")
		end)

		T.test("equip best fills every orbit with the top earners", function()
			local stars = {
				s1 = { typeId = "BrownDwarf", level = 1, pos = { x = 0, y = 0, z = 0 } }, -- 3 orbits
			}
			local planets = {
				a = { typeId = "Basalt", level = 1, star = "s1", slot = 1 }, -- 2/s, the weakest
				b = { typeId = "Moss", level = 1, star = "s1", slot = 2 }, -- 5/s
				c = { typeId = "Singularity", level = 1 }, -- 1250/s
				d = { typeId = "Aurora", level = 1 }, -- 40/s
				e = { typeId = "Desert", level = 1 }, -- 4/s
			}
			local layout = PlanetInventory.best(planets, stars)
			T.equal(layout.a, nil, "the weakest leaves orbit")
			T.equal(layout.e, nil)
			T.equal(layout.b.slot, 2, "a kept planet doesn't move")
			T.truthy(layout.c and layout.d, "the best two are in")
			local used = {}
			for _, place in layout do
				T.equal(place.star, "s1")
				T.falsy(used[place.slot], "no two share a slot")
				used[place.slot] = true
			end
		end)

		T.test("equip best puts the best planets on the strongest star", function()
			local stars, planets = setup()
			local layout = PlanetInventory.best(planets, stars)
			for id in planets do
				T.equal(layout[id].star, "s2", `{id} goes to the Black Hole`)
			end
		end)

		T.test("equip best leaves an already best layout alone", function()
			local stars, planets = setup()
			planets.p1.star, planets.p1.slot = "s2", 3
			planets.p2.star, planets.p2.slot = "s2", 1
			planets.p3.star, planets.p3.slot = "s2", 2
			local layout = PlanetInventory.best(planets, stars)
			for id, planet in planets do
				T.equal(layout[id].star, planet.star, id)
				T.equal(layout[id].slot, planet.slot, id)
			end
		end)

		T.test("planet storage holds 200", function()
			T.equal(P.MAX_PLANETS, 200)
		end)

		T.test("new ids count up", function()
			local id, nextId = PlanetInventory.newId(7)
			T.equal(id, "p7")
			T.equal(nextId, 8)
		end)
	end)

	T.describe("Planet catalog", function()
		T.test("42 types in six rarities with the exact odds", function()
			T.equal(#P.ORDER, 42)
			local counts =
				{ Common = 6, Uncommon = 6, Rare = 9, Epic = 9, Legendary = 6, Interstellar = 6 }
			-- Percent per type: each rarity's share (45.6, 25.6, 12.8, 10, 4, 2)
			-- split evenly among its types.
			local each = {
				Common = 45.6 / 6,
				Uncommon = 25.6 / 6,
				Rare = 12.8 / 9,
				Epic = 10 / 9,
				Legendary = 4 / 6,
				Interstellar = 2 / 6,
			}
			local total = 0
			for rarity, n in counts do
				T.equal(#P.BY_RARITY[rarity], n, rarity)
				for _, id in P.BY_RARITY[rarity] do
					local weight = P.BY_ID[id].weight
					T.near(weight / P.WEIGHT_TOTAL * 100, each[rarity], 1e-9)
					total += weight
				end
			end
			T.equal(total, P.WEIGHT_TOTAL)
		end)

		T.test("hatch times follow round(10 x 180^(i/5)), rounded up to 10 s", function()
			local expected = { 10, 30, 80, 230, 640, 1800 }
			for index, rarity in P.RARITY_ORDER do
				T.equal(P.RARITIES[rarity].hatchSeconds, expected[index], rarity)
			end
		end)

		T.test("buying mystery eggs to sell them never pays", function()
			local expected = 0
			for _, id in P.ORDER do
				local def = P.BY_ID[id]
				expected += def.weight / P.WEIGHT_TOTAL * P.SELL_FRACTION[def.rarity]
			end
			T.near(expected, 0.04, 1e-6, "4% of the roll price at lab 1")
		end)

		T.test("incomes are evenly spaced within each rarity, rarer always higher", function()
			local ranges = {
				Common = { 0.5, 0.8 },
				Uncommon = { 1.2, 1.6 },
				Rare = { 2.4, 3.4 },
				Epic = { 5, 7 },
				Legendary = { 10, 13 },
				Interstellar = { 16, 20 },
			}
			for rarity, range in ranges do
				local ids = P.BY_RARITY[rarity]
				for index, id in ids do
					local want = range[1] + (range[2] - range[1]) * (index - 1) / (#ids - 1)
					T.near(P.BY_ID[id].income, want, 0.001, id)
				end
			end
			for oldId in P.LEGACY do
				T.truthy(P.BY_ID[P.LEGACY[oldId]], oldId)
			end
		end)
	end)
end

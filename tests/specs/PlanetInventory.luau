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
				StarMath.planetIncome("Basalt", 2)
			)
			T.falsy(PlanetInventory.unequip(planets, "p9"))
		end)

		T.test("income counts each equipped planet exactly once", function()
			local stars, planets = setup()
			PlanetInventory.equip(planets, stars, "p2", "s2", 1)
			PlanetInventory.equip(planets, stars, "p3", "s2", 2)
			local expected = StarMath.starIncome("BrownDwarf", 1)
				+ StarMath.starIncome("BlackHole", 1)
				+ StarMath.planetIncome("Basalt", 2)
				+ StarMath.planetIncome("Aurora", 1)
				+ StarMath.planetIncome("Singularity", 5)
			T.near(StarMath.totalIncome(stars, planets), expected)
			local on = PlanetInventory.equippedOn(planets, "s2")
			T.near(
				StarMath.income(stars.s2, on),
				StarMath.starIncome("BlackHole", 1)
					+ StarMath.planetIncome("Aurora", 1)
					+ StarMath.planetIncome("Singularity", 5)
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

		T.test("new ids count up", function()
			local id, nextId = PlanetInventory.newId(7)
			T.equal(id, "p7")
			T.equal(nextId, 8)
		end)
	end)

	T.describe("Planet catalog", function()
		T.test("28 types in six rarities with the exact odds", function()
			T.equal(#P.ORDER, 28)
			local counts =
				{ Common = 4, Uncommon = 4, Rare = 6, Epic = 6, Legendary = 4, Interstellar = 4 }
			-- Percent per type, from the design: 12.5, 7, 14/6, 5/6, 0.5, 0.25.
			local each = {
				Common = 12.5,
				Uncommon = 7,
				Rare = 14 / 6,
				Epic = 5 / 6,
				Legendary = 0.5,
				Interstellar = 0.25,
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

		T.test("hatch times follow round(10 x 180^(i/5))", function()
			local expected = { 10, 28, 80, 226, 637, 1800 }
			for index, rarity in P.RARITY_ORDER do
				T.equal(P.RARITIES[rarity].hatchSeconds, expected[index], rarity)
			end
		end)

		T.test("every old planet maps to a type that earns at least as much", function()
			-- Version 14 incomes (Config.Planets before the egg overhaul).
			local old = {
				Barren = 2,
				Molten = 5,
				Desert = 14,
				Ocean = 35,
				Terran = 85,
				IceGiant = 200,
				GasGiant = 480,
				Crystal = 1100,
			}
			for oldId, income in old do
				local target = P.LEGACY[oldId]
				T.truthy(target and P.BY_ID[target], oldId)
				T.truthy(P.BY_ID[target].income >= income, `{oldId} -> {target}`)
			end
		end)
	end)
end

return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local CombatMath = Loader.require("src/shared/Logic/CombatMath")

	local C = Config.Combat

	T.describe("CombatMath", function()
		T.test("only two opted-in players hurt each other, outside safe zones", function()
			T.truthy(CombatMath.canDamage(true, true, false, true, false))
			T.equal(
				CombatMath.canDamage(true, false, false, true, false),
				false,
				"victim opted out"
			)
			T.equal(
				CombatMath.canDamage(false, true, false, true, false),
				false,
				"attacker opted out"
			)
			T.equal(CombatMath.canDamage(true, true, true, true, false), false, "own ship")
			T.equal(CombatMath.canDamage(true, true, false, false, false), false, "parked ship")
			T.equal(CombatMath.canDamage(true, true, false, true, true), false, "docking area")
		end)

		T.test("damage scales with beam power", function()
			T.near(CombatMath.damage(10), 10 * C.DAMAGE_PER_POWER)
			T.equal(CombatMath.damage(-5), 0)
		end)

		T.test("the hull repairs only after the delay, up to full", function()
			T.equal(CombatMath.repair(50, 100, C.REGEN_DELAY - 1, 1), 50)
			T.near(CombatMath.repair(50, 100, C.REGEN_DELAY + 1, 1), 50 + 100 * C.REGEN_SHARE)
			T.equal(CombatMath.repair(99.9, 100, 100, 10), 100)
		end)

		T.test("PvP can't be switched off mid-fight or toggled rapidly", function()
			T.truthy(CombatMath.canToggle(true, 100, 0, 99))
			T.equal(CombatMath.canToggle(false, 100, 0, 100 - C.COMBAT_LOCK / 2), false)
			T.truthy(CombatMath.canToggle(false, 100, 0, 100 - C.COMBAT_LOCK - 1))
			T.equal(CombatMath.canToggle(true, 100, 100 - C.TOGGLE_COOLDOWN / 2, 0), false)
		end)

		T.test("every ship has hull points that rise along the ladder", function()
			local last = 0
			for _, shipId in Config.Ships.ORDER do
				local hull = Config.Ships.BY_ID[shipId].stats.hull
				T.truthy(hull > last, shipId)
				last = hull
			end
		end)

		T.test("hull climbs on a curve: each ship adds more than the last", function()
			local lastHull, lastGain = 0, 0
			for index, shipId in Config.Ships.ORDER do
				local hull = Config.Ships.BY_ID[shipId].stats.hull
				if index > 1 then
					T.truthy(hull - lastHull > lastGain, shipId)
					lastGain = hull - lastHull
				end
				lastHull = hull
			end
		end)
	end)
end

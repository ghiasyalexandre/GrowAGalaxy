return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local EggMath = Loader.require("src/shared/Logic/EggMath")
	local Format = Loader.require("src/shared/Util/Format")

	local P, E = Config.Planets, Config.Eggs

	T.describe("EggMath", function()
		T.test(
			"every roll lands on a type, each type on exactly its weight, at every lab level",
			function()
				for level = 1, #E.LAB_LEVELS do
					local at = 0
					for _, id in P.ORDER do
						local weight = EggMath.typeWeight(id, level)
						T.truthy(weight > 0, `{id} can be rolled at level {level}`)
						T.equal(EggMath.pickType(level, at + 1), id, `{id} first roll`)
						T.equal(EggMath.pickType(level, at + weight), id, `{id} last roll`)
						at += weight
					end
					T.equal(at, EggMath.typeTotal(level))
				end
			end
		)

		T.test("every tier roll lands on exactly its weight", function()
			for level = 1, #E.LAB_LEVELS do
				local at = 0
				for tier = 1, #P.TIERS do
					local weight = EggMath.tierWeight(tier, level)
					T.equal(EggMath.pickTier(level, at + 1), tier)
					T.equal(EggMath.pickTier(level, at + weight), tier)
					at += weight
				end
				T.equal(at, EggMath.tierTotal(level))
			end
		end)

		T.test("level 1 shows the plain designed odds", function()
			T.equal(EggMath.percentText(EggMath.typePercent("Basalt", 1)), "7.6%")
			T.equal(EggMath.percentText(EggMath.typePercent("Singularity", 1)), "0.333%")
			T.equal(EggMath.percentText(EggMath.rarityPercent("Common", 1)), "45.6%")
			T.equal(EggMath.percentText(EggMath.rarityPercent("Epic", 1)), "10%")
			T.equal(EggMath.percentText(EggMath.rarityPercent("Interstellar", 1)), "2%")
			T.equal(EggMath.percentText(EggMath.tierPercent(1, 1)), "20%")
			T.equal(EggMath.percentText(EggMath.tierPercent(2, 1)), "50%")
			T.equal(EggMath.percentText(EggMath.tierPercent(7, 1)), "0.2%")
		end)

		T.test("chances add up to 100% at every level", function()
			for level = 1, #E.LAB_LEVELS do
				local types, rarities, tiers = 0, 0, 0
				for _, id in P.ORDER do
					types += EggMath.typePercent(id, level)
				end
				for _, rarity in P.RARITY_ORDER do
					rarities += EggMath.rarityPercent(rarity, level)
				end
				for tier = 1, #P.TIERS do
					tiers += EggMath.tierPercent(tier, level)
				end
				T.truthy(math.abs(types - 100) < 1e-6 and math.abs(rarities - 100) < 1e-6)
				T.truthy(math.abs(tiers - 100) < 1e-6)
			end
		end)

		T.test(
			"lab upgrades only ever improve the top rarity, the top tier and egg value",
			function()
				for level = 2, #E.LAB_LEVELS do
					T.truthy(
						EggMath.rarityPercent("Interstellar", level)
							>= EggMath.rarityPercent("Interstellar", level - 1)
					)
					T.truthy(
						EggMath.tierPercent(#P.TIERS, level)
							>= EggMath.tierPercent(#P.TIERS, level - 1)
					)
					T.truthy(EggMath.expectedIncome(level) > EggMath.expectedIncome(level - 1))
				end
				T.equal(EggMath.upgradeCost(1), E.LAB_LEVELS[2].cost)
				T.equal(EggMath.upgradeCost(#E.LAB_LEVELS), nil)
			end
		)

		T.test("the top tier multiplies income x2.2 and rarity sets the base range", function()
			T.equal(P.TIERS[#P.TIERS].multiplier, 2.2)
			local commonLow, commonHigh = EggMath.rarityRange("Common")
			local rareLow = EggMath.rarityRange("Rare")
			T.truthy(commonLow > 0 and commonHigh < rareLow)
		end)

		T.test(
			"the egg price: a minute of best production, at least 250, never raised by eggs kept",
			function()
				T.equal(EggMath.price(0, 0), 250, "the floor")
				T.equal(EggMath.price(4, 0), 250, "60 x 4 = 240 is under the floor")
				T.equal(EggMath.price(100, 0), 6000, "60 seconds of H")
				T.equal(EggMath.price(100, 100), 6000, "keeping eggs never raises the price")
				T.equal(EggMath.price(100, 1000), 6000)
			end
		)

		T.test(
			"expected resale stays a small share of the roll price at every lab level",
			function()
				T.near(EggMath.expectedSaleShare(1), 0.04, 1e-9, "4% of the roll price at lab 1")
				local last = 0
				for level = 1, #E.LAB_LEVELS do
					local share = EggMath.expectedSaleShare(level)
					T.truthy(share > last and share < 0.06, `lab {level}: {share}`)
					last = share
				end
			end
		)

		T.test("lab levels need a best star tier that never falls", function()
			T.equal(EggMath.upgradeTier(1), 4)
			T.equal(EggMath.upgradeTier(7), 16)
			T.equal(EggMath.upgradeTier(#E.LAB_LEVELS), nil)
		end)

		T.test("random eggs only when the policy is known to allow them", function()
			T.truthy(EggMath.canBuyRandom("allowed"))
			T.falsy(EggMath.canBuyRandom("restricted"))
			T.falsy(EggMath.canBuyRandom("unknown"))
		end)

		T.test("held counts waiting and incubating eggs", function()
			T.equal(EggMath.held({ e1 = 1, e2 = 1 }, { ["1"] = 1 }), 3)
			T.equal(EggMath.held({}, {}), 0)
		end)

		T.test("exact prices get thousands separators", function()
			T.equal(Format.commas(500), "500")
			T.equal(Format.commas(1000), "1,000")
			T.equal(Format.commas(1234567), "1,234,567")
			T.equal(Format.commas(-25000), "-25,000")
		end)

		T.test("durations read naturally", function()
			T.equal(EggMath.durationText(10), "10 s")
			T.equal(EggMath.durationText(226), "3 min 46 s")
			T.equal(EggMath.durationText(1800), "30 min")
			T.equal(EggMath.durationText(3600 + 120), "1 h 2 min")
		end)
	end)
end

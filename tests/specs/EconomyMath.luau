return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local EconomyMath = Loader.require("src/shared/Logic/EconomyMath")
	local ProfileSchema = Loader.require("src/shared/Logic/ProfileSchema")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local S = Config.Stars

	local function star(typeId: string, level: number, build: number?): any
		return { typeId = typeId, level = level, pos = { x = 0, y = 0, z = 0 }, build = build or 0 }
	end

	T.describe("EconomyMath", function()
		T.test("the star ladder: costs and 3x incomes from REBALANCE.md", function()
			local costs = {
				100,
				450,
				1800,
				7000,
				28000,
				110000,
				450000,
				2e6,
				1e7,
				5e7,
				2.5e8,
				1.3e9,
				7e9,
				3e10,
				1.2e11,
				4.8e11,
				1.9e12,
			}
			for index, id in S.ORDER do
				local def = S.BY_ID[id]
				T.equal(def.cost, costs[index], id)
				T.equal(def.income, 3 ^ (index - 1), id)
			end
			-- A level-8 Void Flame makes about 124.4M/s by itself, times the boost.
			T.near(StarMath.starIncome("VoidFlame", 8), 124405023.69 * S.INCOME_BOOST, 0.01)
		end)

		T.test("production B: stars, planets on their host, then trail and Refinery", function()
			local profile = ProfileSchema.default() :: any
			profile.galaxy.stars = { s1 = star("RedDwarf", 1) }
			profile.planets =
				{ p1 = { typeId = "Basalt", level = 1, tier = 1, star = "s1", slot = 1 } }
			local base = (3 + 3 * 0.005) * S.INCOME_BOOST
			T.near(EconomyMath.production(profile), base)
			profile.ownedTrails = { CometDust = true }
			profile.trail = "CometDust"
			profile.hangar = { StardustSilo = true, Refinery = true }
			T.near(EconomyMath.production(profile), base * 1.1 * 1.1)
		end)

		T.test("H never falls below what the save makes now", function()
			local profile = ProfileSchema.default() :: any
			profile.galaxy.stars = { s1 = star("YellowDwarf", 1) }
			profile.economy.high = 5
			T.near(EconomyMath.high(profile), 9 * S.INCOME_BOOST)
			profile.economy.high = 50
			T.near(EconomyMath.high(profile), 50)
		end)

		T.test("rewards are minutes of R, R at least 1, never under a minimum", function()
			T.equal(EconomyMath.reward(2, 1), 120)
			T.equal(EconomyMath.reward(2, 0.2), 120)
			T.equal(EconomyMath.reward(3, 1000), 180000)
			T.equal(EconomyMath.reward(1, 1, 600), 600)
		end)

		T.test(
			"mining factor a: 0.65 for the starter, 0.85 fully equipped on the flagship",
			function()
				T.near(EconomyMath.miningFactor(1, 0), 0.65)
				T.near(EconomyMath.miningFactor(11, 16), 0.85)
				T.near(EconomyMath.miningFactor(12, 40), 0.85, 1e-9, "capped")
				-- 1 + a: active play is 1.65 to 1.85 x passive.
				local payout = EconomyMath.miningPayout(1000, 0.65, 10, 0, 1)
				T.equal(payout, 6500)
				T.equal(
					EconomyMath.miningPayout(1000, 0.65, 10, 1, 1),
					8125,
					"+25% all on the weak point"
				)
				T.equal(EconomyMath.miningPayout(1000, 0.65, 10, 0, 2), 13000, "pass x2")
			end
		)

		T.test("R follows the average production over the last ten online minutes", function()
			local window = {}
			EconomyMath.track(window, 100, 60, 0)
			T.near(EconomyMath.track(window, 300, 60, 60), 200)
			-- Eleven minutes later the first minutes have dropped out.
			for minute = 2, 12 do
				EconomyMath.track(window, 500, 60, minute * 60)
			end
			T.near(EconomyMath.track(window, 500, 0, 12 * 60), 500)
			T.equal(EconomyMath.snapshot(0), 1, "a new account's first day uses 1")
		end)

		T.test("the collector tank holds 2 hours, 3 with the Silo", function()
			T.equal(EconomyMath.tankCap(10, 1), 72000)
			T.equal(EconomyMath.tankCap(10, 1.5), 108000)
		end)

		T.test("constellation projects: 20% more each rank, capped", function()
			T.truthy(math.abs(EconomyMath.constellationPrice(0) - 88675900886233) <= 1)
			T.truthy(EconomyMath.constellationPrice(1) > EconomyMath.constellationPrice(0))
			T.equal(EconomyMath.constellationPrice(18), EconomyMath.constellationPrice(40))
			T.truthy(EconomyMath.constellationPrice(40) <= 2e15)
			local profile = ProfileSchema.default() :: any
			T.falsy(EconomyMath.constellationReady(profile))
			for index = 1, 20 do
				profile.galaxy.stars[`s{index}`] = star("VoidFlame", 8, index - 1)
			end
			T.falsy(EconomyMath.constellationReady(profile), "needs the best lab too")
			profile.eggLab.level = #Config.Eggs.LAB_LEVELS
			T.truthy(EconomyMath.constellationReady(profile))
		end)

		T.test("old levels keep their share of the way to max", function()
			T.equal(EconomyMath.remapLevel(1, 4, 4), 1)
			T.equal(EconomyMath.remapLevel(4, 4, 4), 4)
			T.equal(EconomyMath.remapLevel(36, 36, 8), 8)
			T.equal(EconomyMath.remapLevel(18, 36, 8), 4)
		end)

		T.test(
			"v21: BuildIndex in id order, remapped levels, legacy planets, no tutorial egg",
			function()
				local data = ProfileSchema.default() :: any
				data.schemaVersion = 20
				data.tutorialEgg = nil
				data.economy = nil
				data.galaxy = {
					expansion = 1,
					nextId = 12,
					stars = {
						s10 = {
							typeId = "CosmicPhoenix",
							level = 36,
							pos = { x = 0, y = 0, z = 0 },
						},
						s2 = { typeId = "RedDwarf", level = 6, pos = { x = 0, y = 0, z = 0 } },
						s1 = { typeId = "BrownDwarf", level = 2, pos = { x = 0, y = 0, z = 0 } },
					},
				}
				data.planets = { p1 = { typeId = "Basalt", level = 3, tier = 2 } }
				data.stardust = 12345
				T.truthy(ProfileSchema.normalize(data))
				local stars = data.galaxy.stars
				T.equal(stars.s1.build, 0)
				T.equal(stars.s2.build, 1)
				T.equal(stars.s10.build, 2, "numeric id order, not string order")
				T.equal(data.galaxy.nextBuild, 3)
				T.equal(stars.s10.level, StarMath.maxLevel("CosmicPhoenix"))
				T.equal(stars.s2.level, 4)
				T.equal(stars.s1.level, 2)
				T.equal(data.planets.p1.legacy, Config.Planets.LEGACY_SELL_VALUE.Common)
				T.equal(data.tutorialEgg, true)
				T.equal(data.stardust, 12345, "the wallet is kept")
				T.near(data.economy.high, EconomyMath.production(data))
				T.equal(data.constellationRank, 0)
				-- Running it again changes nothing.
				T.truthy(ProfileSchema.normalize(data))
				T.equal(stars.s10.build, 2)
				T.equal(data.galaxy.nextBuild, 3)
				T.equal(stars.s10.level, StarMath.maxLevel("CosmicPhoenix"))
			end
		)

		T.test(
			"a new profile starts with BuildIndex 0, R 1 and the tutorial egg to come",
			function()
				local data = ProfileSchema.default()
				T.equal(data.galaxy.nextBuild, 0)
				T.equal(data.economy.reward, 1)
				T.equal(data.tutorialEgg, false)
			end
		)
	end)
end

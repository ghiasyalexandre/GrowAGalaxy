return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local RewardMath = Loader.require("src/shared/Logic/RewardMath")
	local ReceiptFlow = Loader.require("src/shared/Logic/ReceiptFlow")

	local P = Config.Products

	local function entitlements(passes, mining, star)
		return { passes = passes or {}, boosts = { mining = mining or 0, star = star or 0 } }
	end

	T.describe("RewardMath", function()
		T.test("mining: 1x, pass 2x, boost 2x, both 4x", function()
			T.equal(RewardMath.multiplier("mining", entitlements()), 1)
			T.equal(RewardMath.multiplier("mining", entitlements({ MiningMultiplier = true })), 2)
			T.equal(RewardMath.multiplier("mining", entitlements({}, 60)), 2)
			T.equal(
				RewardMath.multiplier("mining", entitlements({ MiningMultiplier = true }, 60)),
				4
			)
			T.equal(RewardMath.miningReward(30, entitlements({ MiningMultiplier = true }, 60)), 120)
		end)

		T.test("each pass only affects its own source", function()
			local star = entitlements({ StarMultiplier = true }, 0, 60)
			T.equal(
				RewardMath.multiplier("mining", star),
				1,
				"star pass and boost don't touch mining"
			)
			local mining = entitlements({ MiningMultiplier = true }, 60, 0)
			T.equal(
				RewardMath.multiplier("star", mining),
				1,
				"mining pass and boost don't touch stars"
			)
			T.equal(
				RewardMath.multiplier("mining", entitlements({ EnhancedBeam = true })),
				1,
				"beam is not a reward"
			)
			T.equal(RewardMath.beamPower({ EnhancedBeam = true }), 1.25)
			T.equal(RewardMath.beamPower({ MiningMultiplier = true }), 1)
			T.truthy(RewardMath.autoCollect({ AutoCollect = true }))
			T.equal(RewardMath.autoCollect({ StarMultiplier = true }), false)
		end)

		T.test("a boost expiring mid-interval only boosts the covered part", function()
			-- 10 s at 5/s with 4 s of boost: 4 s at 2x + 6 s at 1x = 70.
			T.near(RewardMath.starIncome(5, 10, 4, {}), 70)
			T.near(RewardMath.starIncome(5, 10, 0, {}), 50)
			T.near(RewardMath.starIncome(5, 10, 100, {}), 100)
			-- Pass and boost together: 4x for the boosted part.
			T.near(RewardMath.starIncome(5, 10, 10, { StarMultiplier = true }), 200)
			T.equal(RewardMath.starIncome(0, 10, 10, {}), 0)
		end)

		T.test("buying a boost twice adds time, not strength", function()
			local left = RewardMath.extend(0, 900)
			left = RewardMath.extend(left, 900)
			T.equal(left, 1800)
			T.equal(RewardMath.temporary("mining", { mining = left, star = 0 }), P.BOOST_MULTIPLIER)
			T.equal(RewardMath.tick(1800, 600), 1200)
			T.equal(RewardMath.tick(5, 10), 0)
		end)

		T.test("disabled products grant nothing", function()
			T.equal(RewardMath.permanent("mining", { NoSuchPass = true }), 1)
		end)

		T.test("timers read naturally", function()
			T.equal(RewardMath.clock(905), "15:05")
			T.equal(RewardMath.clock(3723), "1:02:03")
		end)
	end)

	T.describe("ReceiptFlow", function()
		local function profile()
			return { stardust = 100, boosts = { mining = 0, star = 0 }, receipts = {} }
		end

		T.test("a pack adds its exact amount once per PurchaseId", function()
			local data = profile()
			local grants = P.BY_KEY.StardustSmall.grants
			T.equal(ReceiptFlow.applyTo(data, "p1", grants), "granted")
			T.equal(data.stardust, 100 + grants.stardust, "not multiplied")
			T.equal(ReceiptFlow.applyTo(data, "p1", grants), "duplicate")
			T.equal(data.stardust, 100 + grants.stardust, "repeat grants nothing")
		end)

		T.test("boost receipts add time", function()
			local data = profile()
			ReceiptFlow.applyTo(data, "a", P.BY_KEY.MiningBoost.grants)
			ReceiptFlow.applyTo(data, "b", P.BY_KEY.MiningBoost.grants)
			T.equal(data.boosts.mining, 1800)
			T.equal(data.boosts.star, 0)
		end)

		T.test("old receipt ids are trimmed to the limit", function()
			local data = profile()
			for i = 1, P.MAX_RECEIPTS + 5 do
				ReceiptFlow.applyTo(data, `r{i}`, P.BY_KEY.StardustSmall.grants)
			end
			T.equal(#data.receipts, P.MAX_RECEIPTS)
			T.equal(data.receipts[1], "r6")
		end)

		-- Fake dependencies for process(): a profile in memory, a "saved" copy.
		local function fakes(overrides)
			local state = { data = profile(), saved = nil, logs = {}, saveWorks = true }
			local deps = {
				productFor = function(id)
					return if id == 7 then P.BY_KEY.StardustSmall else nil
				end,
				playerFor = function(userId)
					return if userId == 1 then "player" else nil
				end,
				profileFor = function()
					return true
				end,
				apply = function(_, purchaseId, def)
					return ReceiptFlow.applyTo(state.data, purchaseId, def.grants)
				end,
				waitSaved = function(_, purchaseId)
					if state.saveWorks then
						state.saved = T.deepCopy(state.data)
					end
					return state.saved ~= nil
						and table.find(state.saved.receipts, purchaseId) ~= nil
				end,
				wait = function() end,
				log = function(message)
					table.insert(state.logs, message)
				end,
			}
			for key, value in overrides or {} do
				deps[key] = value
			end
			return state, deps
		end

		T.test("repeated receipts grant once and are acknowledged", function()
			local state, deps = fakes()
			local receipt = { PurchaseId = "x1", ProductId = 7, PlayerId = 1 }
			T.equal(ReceiptFlow.process(receipt, deps, {}), "granted")
			T.equal(ReceiptFlow.process(receipt, deps, {}), "granted")
			T.equal(state.data.stardust, 100 + P.BY_KEY.StardustSmall.grants.stardust)
		end)

		T.test("a failed save is never acknowledged", function()
			local state, deps = fakes()
			state.saveWorks = false
			local receipt = { PurchaseId = "x2", ProductId = 7, PlayerId = 1 }
			T.equal(ReceiptFlow.process(receipt, deps, {}), "retry")
		end)

		T.test("unknown products, absent players and missing profiles retry", function()
			local state, deps = fakes()
			T.equal(
				ReceiptFlow.process({ PurchaseId = "u", ProductId = 99, PlayerId = 1 }, deps, {}),
				"retry"
			)
			T.truthy(#state.logs > 0, "unknown product is logged, not discarded")
			T.equal(
				ReceiptFlow.process({ PurchaseId = "v", ProductId = 7, PlayerId = 2 }, deps, {}),
				"retry"
			)
			local _, noProfile = fakes({
				profileFor = function()
					return false
				end,
			})
			T.equal(
				ReceiptFlow.process(
					{ PurchaseId = "w", ProductId = 7, PlayerId = 1 },
					noProfile,
					{}
				),
				"retry"
			)
		end)

		T.test("an error while granting retries instead of acknowledging", function()
			local _, deps = fakes({
				apply = function()
					error("boom")
				end,
			})
			T.equal(
				ReceiptFlow.process({ PurchaseId = "e", ProductId = 7, PlayerId = 1 }, deps, {}),
				"retry"
			)
		end)

		T.test("the same receipt in flight twice waits and grants once", function()
			local state, deps = fakes()
			local inFlight = { x3 = true }
			deps.wait = function()
				inFlight.x3 = nil -- the other call finishes
			end
			local receipt = { PurchaseId = "x3", ProductId = 7, PlayerId = 1 }
			T.equal(ReceiptFlow.process(receipt, deps, inFlight), "granted")
			T.equal(ReceiptFlow.process(receipt, deps, inFlight), "granted")
			T.equal(state.data.stardust, 100 + P.BY_KEY.StardustSmall.grants.stardust)
		end)

		T.test("an equipped trail multiplies mining and star income", function()
			local e = RewardMath.none()
			e.trail = 2.5
			T.near(RewardMath.multiplier("mining", e), 2.5)
			T.equal(RewardMath.miningReward(10, e), 25)
			T.near(RewardMath.starIncome(10, 1, 0, {}, 2.5), 25)
			T.near(RewardMath.starIncome(10, 1, 0, {}), 10)
		end)

		T.test("trail multipliers rise in steps of 0.5", function()
			local last, lastCost = 1, 0
			for _, id in Config.Trails.ORDER do
				local def = Config.Trails.BY_ID[id]
				T.near(def.multiplier - last, 0.5, 1e-9, id)
				T.truthy(def.cost > lastCost, id)
				last, lastCost = def.multiplier, def.cost
			end
		end)
	end)
end

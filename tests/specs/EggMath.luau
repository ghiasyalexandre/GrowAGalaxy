return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local EggMath = Loader.require("src/shared/Logic/EggMath")
	local Format = Loader.require("src/shared/Util/Format")

	local P, E = Config.Planets, Config.Eggs

	T.describe("EggMath", function()
		T.test("every roll lands on a type, each type on exactly its weight", function()
			local hits = {}
			-- Walk the boundaries rather than all 1.2M rolls.
			local at = 0
			for _, id in P.ORDER do
				local weight = P.BY_ID[id].weight
				T.equal(EggMath.pick(at + 1), id, `{id} first roll`)
				T.equal(EggMath.pick(at + weight), id, `{id} last roll`)
				hits[id] = weight
				at += weight
			end
			T.equal(at, P.WEIGHT_TOTAL)
			T.equal(EggMath.pick(1), P.ORDER[1])
			T.equal(EggMath.pick(P.WEIGHT_TOTAL), P.ORDER[#P.ORDER])
		end)

		T.test("chances add up to 100% and show the designed numbers", function()
			local total = 0
			for _, id in P.ORDER do
				total += EggMath.percent(id)
			end
			T.near(total, 100, 1e-9)
			T.equal(EggMath.percentText(EggMath.percent("Basalt")), "12.5%")
			T.equal(EggMath.percentText(EggMath.percent("Coral")), "7%")
			T.equal(EggMath.percentText(EggMath.percent("Aurora")), "2.333%")
			T.equal(EggMath.percentText(EggMath.percent("Eclipse")), "0.833%")
			T.equal(EggMath.percentText(EggMath.percent("PhoenixCore")), "0.5%")
			T.equal(EggMath.percentText(EggMath.percent("Singularity")), "0.25%")
		end)

		T.test("every mystery egg costs a flat 1,000 Stardust", function()
			T.equal(E.PRICE_BASE, 1000)
			for bought = 0, 200, 25 do
				T.equal(EggMath.price(bought), 1000, `egg {bought}`)
			end
			T.equal(EggMath.guaranteedPrice, nil, "planets can't be bought directly")
		end)

		T.test("a batch costs each egg's own price in turn", function()
			local prices, total = EggMath.batch(3, 5)
			T.equal(#prices, 5)
			local sum = 0
			for index, price in prices do
				T.equal(price, EggMath.price(3 + index - 1))
				sum += price
			end
			T.equal(total, sum)
			T.truthy(EggMath.isBatchSize(1) and EggMath.isBatchSize(10))
			T.falsy(EggMath.isBatchSize(7))
			T.falsy(EggMath.isBatchSize("10"))
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

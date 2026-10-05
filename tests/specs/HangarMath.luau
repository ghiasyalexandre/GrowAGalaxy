return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local HangarMath = Loader.require("src/shared/Logic/HangarMath")

	T.describe("HangarMath", function()
		T.test("upgrades appear once their requirements are built", function()
			T.truthy(HangarMath.available("StardustSilo", {}))
			T.equal(HangarMath.available("Refinery", {}), false)
			T.truthy(HangarMath.available("Refinery", { StardustSilo = true }))
			T.equal(HangarMath.available("StardustSilo", { StardustSilo = true }), false, "built")
		end)

		T.test("buying needs the requirements and the Stardust", function()
			local cost = Config.Hangar.BY_ID.StardustSilo.cost
			T.equal(HangarMath.canBuy("StardustSilo", {}, cost), cost)
			T.equal(HangarMath.canBuy("StardustSilo", {}, cost - 1), nil)
			T.equal(HangarMath.canBuy("Refinery", {}, 1e9), nil)
			T.equal(HangarMath.canBuy("NoSuchThing", {}, 1e9), nil)
		end)

		T.test("effects multiply and stack", function()
			T.equal(HangarMath.statMultiplier({}, "hull"), 1)
			T.near(HangarMath.statMultiplier({ ArmorWorkshop = true }, "hull"), 1.3)
			T.near(HangarMath.incomeMultiplier({ Refinery = true }), 1.15)
			T.near(HangarMath.storageMultiplier({ StardustSilo = true }), 1.5)
			T.equal(HangarMath.incomeMultiplier({ OldUpgrade = true }), 1, "unknown ids ignored")
		end)
	end)
end

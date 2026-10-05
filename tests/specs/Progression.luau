return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local Progression = Loader.require("src/shared/Logic/Progression")

	T.describe("Progression", function()
		T.test("tutorial shows the first step not done, in any order, then 0", function()
			local steps = Config.Tutorial.STEPS
			T.equal(Progression.tutorialStep({}), 1)
			T.equal(Progression.tutorialStep({ [steps[1].stat] = 1, [steps[3].stat] = 1 }), 2)
			local all = {}
			for _, step in steps do
				all[step.stat] = 1
			end
			T.equal(Progression.tutorialStep(all), 0)
		end)

		T.test("achievements are earned at their goal, once", function()
			local earned = Progression.earnedAchievements({ starsPlaced = 1 }, {})
			T.truthy(table.find(earned, "FirstLight"))
			T.falsy(table.find(earned, "StarCluster"), "needs 3 stars")
			local again = Progression.earnedAchievements(
				{ starsPlaced = 1 },
				{ FirstLight = { progress = 1, claimed = true } }
			)
			T.falsy(table.find(again, "FirstLight"))
		end)

		T.test("every enabled achievement and tutorial step uses a stat the game counts", function()
			local counted = {
				asteroidsMined = true,
				coolExtractions = true,
				starsPlaced = true,
				shipsLaunched = true,
				collections = true,
				starUpgrades = true,
				planetsBought = true,
				planetUpgrades = true,
				starEvolutions = true,
				blackHoles = true,
			}
			for id, def in Config.Achievements.BY_ID do
				if def.enabled then
					T.truthy(counted[def.stat], `achievement {id} stat {def.stat}`)
				end
			end
			for index, step in Config.Tutorial.STEPS do
				T.truthy(counted[step.stat], `tutorial step {index} stat {step.stat}`)
			end
		end)

		T.test("shop prices: earnable ships, enabled equipment, next expansion", function()
			T.equal(Progression.shipCost(Config.Ships.STARTER_SHIP), nil, "starter is free")
			T.truthy(Progression.shipCost("RedFighter"))
			T.equal(Progression.equipmentCost("CargoMk2"), nil, "disabled")
			T.equal(Progression.expansionCost(1), Config.Galaxy.EXPANSIONS[2].cost.stardust)
			T.equal(Progression.expansionCost(#Config.Galaxy.EXPANSIONS), nil)
		end)

		T.test("ships unlock in ladder order", function()
			local order = Config.Ships.ORDER
			T.equal(order[1], "MicroRecon")
			T.equal(order[11], "MeteorSlicer")
			local owned = { [order[1]] = true }
			T.truthy(Progression.shipUnlocked(order[2], owned))
			T.equal(Progression.shipUnlocked(order[3], owned), false, "skips a step")
			owned[order[2]] = true
			T.truthy(Progression.shipUnlocked(order[3], owned))
			T.equal(Progression.shipUnlocked("NoSuchShip", owned), false)
			T.equal(Progression.previousShip(order[3]), order[2])
			T.equal(Progression.previousShip(order[1]), nil)
		end)

		T.test("equipment has 5 levels: each costs more and gives more", function()
			local E = Config.Equipment
			T.equal(E.MAX_LEVEL, 5)
			for _, itemId in E.ORDER do
				if Progression.equipmentCost(itemId) == nil then
					continue
				end
				local lastCost, lastBonus = 0, 0
				for level = 1, E.MAX_LEVEL do
					local cost = Progression.equipmentCost(itemId, level) :: number
					T.truthy(cost > lastCost and cost == math.floor(cost), `{itemId} L{level} cost`)
					for _, multiplier in E.BY_ID[itemId].modifiers do
						local bonus = Progression.equipmentMultiplier(multiplier, level)
						T.truthy(bonus > lastBonus or level == 1, `{itemId} L{level} bonus`)
						lastBonus = bonus
						break
					end
					lastCost = cost
				end
				T.equal(Progression.equipmentCost(itemId, E.MAX_LEVEL + 1), nil)
			end
		end)
	end)
end

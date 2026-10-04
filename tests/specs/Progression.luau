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
			T.truthy(Progression.shipCost("Prospector"))
			T.equal(Progression.equipmentCost("CargoMk2"), nil, "disabled")
			T.equal(Progression.expansionCost(1), Config.Galaxy.EXPANSIONS[2].cost.stardust)
			T.equal(Progression.expansionCost(#Config.Galaxy.EXPANSIONS), nil)
		end)
	end)
end

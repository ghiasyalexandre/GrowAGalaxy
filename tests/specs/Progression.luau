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

		T.test("the tutorial starts with a welcome, ends with a reward, skips no basics", function()
			local steps = Config.Tutorial.STEPS
			T.equal(steps[1].id, "welcome")
			T.truthy(steps[#steps].final, "the last step pays the reward")
			T.truthy(Config.Tutorial.FINISH_REWARD > 0)
			local ids = {}
			for _, step in steps do
				ids[step.id] = true
				-- Every step has kid-sized text: a title and a few sentences.
				T.truthy(#step.title > 0 and #step.title <= 24, `{step.id} title`)
				for _, text in { step.text, step.gamepad or "", step.touch or "" } do
					T.truthy(#text <= Config.Tutorial.MAX_TEXT, `{step.id} text is short`)
				end
			end
			for _, needed in
				{
					"move",
					"launch",
					"fly",
					"mine",
					"star",
					"collect",
					"egg",
					"incubate",
					"equip",
					"levelup",
				}
			do
				T.truthy(ids[needed], `teaches {needed}`)
			end
			-- A star comes before mining, and the free egg before rolling one.
			local at = {}
			for index, step in steps do
				at[step.id] = index
			end
			T.truthy(at.star < at.mine and at.star < at.launch, "place a star before mining")
			T.truthy(at.collect < at.mine, "collect before mining")
			T.truthy(at.incubate < at.egg, "hatch the free egg before rolling one")
			-- Already-done steps are skipped: someone who mined first starts at the welcome.
			T.equal(Progression.tutorialStep({ asteroidsMined = 3 }), 1)
			T.equal(Progression.tutorialStep({ tutorialWelcome = 1, tutorialMoved = 1 }), 3)
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
				planetsEquipped = true, -- StarSystem equipPlanet
				planetLevels = true, -- StarSystem levelPlanet
				planetsHatched = true, -- HatchSystem
				eggsBought = true, -- EggSystem
				eggsIncubated = true, -- HatchSystem
				tutorialWelcome = true, -- TutorialSystem (ack steps)
				tutorialMoved = true,
				tutorialFlew = true,
				tutorialFinished = true,
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
			T.equal(order[12], "QuasarBoard")
			T.truthy(Config.Ships.BY_ID.QuasarBoard.rider)
			local owned = { [order[1]] = true }
			T.truthy(Progression.shipUnlocked(order[2], owned))
			T.equal(Progression.shipUnlocked(order[3], owned), false, "skips a step")
			owned[order[2]] = true
			T.truthy(Progression.shipUnlocked(order[3], owned))
			T.equal(Progression.shipUnlocked("NoSuchShip", owned), false)
			T.equal(Progression.previousShip(order[3]), order[2])
			T.equal(Progression.previousShip(order[1]), nil)
		end)

		T.test("equipment has 4 levels: doubling prices, +15% steps to +60%", function()
			local E = Config.Equipment
			T.equal(E.MAX_LEVEL, 4)
			T.equal(Progression.equipmentCost("BeamMk2", 1), 500)
			T.equal(Progression.equipmentCost("BeamMk2", 4), 4000)
			T.equal(Progression.equipmentCost("ThrustersMk2", 4), 12000)
			-- Per ship: a share of the ship's price, never under the item's cost.
			T.equal(
				Progression.equipmentCost("BeamMk2", 1, "MicroRecon"),
				500,
				"starter: the floor"
			)
			T.equal(Progression.equipmentCost("BeamMk2", 1, "RedFighter"), 500, "10% of 5,000")
			T.equal(Progression.equipmentCost("BeamMk2", 1, "Warship"), 50000, "10% of 500,000")
			T.equal(Progression.equipmentCost("ThrustersMk2", 2, "Warship"), 300000, "30%, then x2")
			T.near(Progression.equipmentMultiplier(1.15, 4), 1.6)
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

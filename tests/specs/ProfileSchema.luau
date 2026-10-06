return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local ProfileSchema = Loader.require("src/shared/Logic/ProfileSchema")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local starter = Config.Ships.STARTER_SHIP

	T.describe("ProfileSchema", function()
		T.test("default profile owns and flies the starter ship", function()
			local profile = ProfileSchema.default()
			T.equal(profile.schemaVersion, ProfileSchema.VERSION)
			T.equal(profile.stardust, Config.Economy.STARTING_STARDUST)
			T.truthy(profile.ownedShips[starter])
			T.equal(profile.activeShip, starter)
			T.truthy(profile.unlockedZones[Config.Zones.STARTER_ZONE])
			T.equal(profile.galaxy.expansion, 1)
		end)

		T.test("a default profile survives normalize unchanged", function()
			local profile = ProfileSchema.default()
			local ok = ProfileSchema.normalize(profile)
			T.truthy(ok)
			T.equal(profile.activeShip, starter)
			T.equal(profile.galaxy.nextId, 1)
		end)

		T.test("an empty table becomes a full default profile", function()
			local data = {}
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.schemaVersion, ProfileSchema.VERSION)
			T.equal(data.stardust, Config.Economy.STARTING_STARDUST)
			T.truthy(data.ownedShips[starter])
			T.equal(type(data.galaxy.stars), "table")
			T.equal(data.settings.stabilization, true)
		end)

		T.test("refuses data from a newer game version and leaves it untouched", function()
			local data = { schemaVersion = ProfileSchema.VERSION + 1, stardust = 77 }
			local ok, reason = ProfileSchema.normalize(data)
			T.falsy(ok)
			T.truthy(reason)
			T.equal(data.stardust, 77)
			T.equal(data.ownedShips, nil)
		end)

		T.test("repairs bad numbers", function()
			local data = {
				stardust = -5,
				uncollected = 0 / 0,
				materials = { Iron = 12.7, Silicate = -3, Ice = "lots", [5] = 3 },
			}
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.stardust, Config.Economy.STARTING_STARDUST, "falls back to the default")
			T.equal(data.uncollected, 0)
			T.equal(data.materials.Iron, 12)
			T.equal(data.materials.Silicate, nil)
			T.equal(data.materials.Ice, nil)
			T.equal(data.materials[5], nil)
		end)

		T.test("keeps unknown ids so a config mistake cannot wipe a save", function()
			local data = { ownedShips = { RetiredShip = true }, materials = { OldOre = 4 } }
			T.truthy(ProfileSchema.normalize(data))
			T.truthy(data.ownedShips.RetiredShip)
			T.truthy(data.ownedShips[starter], "starter is always owned")
			T.equal(data.materials.OldOre, 4)
		end)

		T.test("falls back to the starter ship when the active ship is not owned", function()
			local data = { activeShip = "RedFighter", ownedShips = {} }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.activeShip, starter)
		end)

		T.test("drops loadout equipment the player does not own", function()
			local data = {
				ownedEquipment = { BeamMk2 = true },
				loadouts = { [starter] = { equipment = { Beam = "BeamMk2", Cargo = "CargoMk2" } } },
			}
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.loadouts[starter].equipment.Beam, "BeamMk2")
			T.equal(data.loadouts[starter].equipment.Cargo, nil)
		end)

		T.test("v7: hangar upgrades start empty and keep only true flags", function()
			local fresh = { schemaVersion = 6 }
			T.truthy(ProfileSchema.normalize(fresh))
			T.equal(next(fresh.hangar), nil)
			local data = { hangar = { StardustSilo = true, Junk = "yes" } }
			T.truthy(ProfileSchema.normalize(data))
			T.truthy(data.hangar.StardustSilo)
			T.equal(data.hangar.Junk, nil)
		end)

		T.test("v6: old ship ids become their ladder replacements", function()
			local data = {
				schemaVersion = 5,
				activeShip = "Prospector",
				ownedShips = { StarterShuttle = true, Prospector = true },
				ownedEquipment = { BeamMk2 = true },
				loadouts = { Prospector = { equipment = { Beam = "BeamMk2" } } },
			}
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.activeShip, "RedFighter")
			T.truthy(data.ownedShips.MicroRecon)
			T.truthy(data.ownedShips.RedFighter)
			T.equal(data.ownedShips.Prospector, nil)
			T.equal(data.ownedShips.StarterShuttle, nil)
			T.equal(data.loadouts.RedFighter.equipment.Beam, "BeamMk2")
			T.equal(data.loadouts.Prospector, nil)
		end)

		T.test("v5: a level above the type's max level is lowered to it", function()
			local data = {
				schemaVersion = 4,
				galaxy = {
					stars = {
						a = { typeId = "BrownDwarf", level = 5, pos = { x = 0, y = 0, z = 0 } },
						b = { typeId = "RedDwarf", level = 3, pos = { x = 0, y = 0, z = 0 } },
					},
				},
			}
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.galaxy.stars.a.level, 4, "Brown Dwarf max level is 4")
			T.equal(data.galaxy.stars.b.level, 3, "levels within the max are kept")
		end)

		T.test("keeps valid stars and drops corrupt ones", function()
			local data = {
				galaxy = {
					expansion = 99,
					nextId = 2,
					stars = {
						s1 = {
							typeId = "YellowDwarf",
							level = 2,
							pos = { x = 0, y = 10, z = 500 },
						},
						s4 = { typeId = "RetiredStar", level = 1, pos = { x = 1, y = 2, z = 3 } },
						s9 = {
							typeId = "YellowDwarf",
							level = 1,
							pos = { x = "far", y = 0, z = 0 },
						},
						s7 = { typeId = "YellowDwarf", level = 0, pos = { x = 0, y = 0, z = 0 } },
					},
				},
			}
			T.truthy(ProfileSchema.normalize(data))
			local galaxy = data.galaxy
			T.equal(galaxy.expansion, #Config.Galaxy.EXPANSIONS, "expansion clamped")
			T.truthy(galaxy.stars.s1)
			T.equal((galaxy.stars.s1 :: any).planets, nil, "stars no longer hold planets")
			T.truthy(galaxy.stars.s4, "unknown type kept")
			T.equal(galaxy.stars.s9, nil, "bad position")
			T.equal(galaxy.stars.s7, nil, "bad level")
			T.equal(galaxy.nextId, 10, "nextId moves past every existing id")
		end)

		T.test("version 2 systems become stars at their positions", function()
			local data = {
				schemaVersion = 2,
				stardust = 5,
				galaxy = {
					expansion = 1,
					nextId = 3,
					systems = { s1 = { starId = "b2", tier = 1, pos = { x = 0, y = 0, z = 400 } } },
					bodies = {
						b2 = { kind = "star", typeId = "StarterStar", systemId = "s1", level = 2 },
					},
				},
			}
			T.truthy(ProfileSchema.normalize(data))
			local star = data.galaxy.stars.s1
			T.truthy(star)
			T.equal(star.typeId, Config.Stars.DEFAULT_TYPE)
			T.equal(star.level, 2)
			T.equal(star.pos.z, 400)
			T.equal(data.galaxy.systems, nil)
		end)

		T.test("migrates version 1 Credits to Stardust without losing the balance", function()
			local data = { schemaVersion = 1, credits = 1234, uncollected = 5.5 }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.schemaVersion, ProfileSchema.VERSION)
			T.equal(data.stardust, 1234)
			T.equal(data.credits, nil, "old field removed")
			T.near(data.uncollected, 5.5)
		end)

		T.test("version 1 Credits win over a template-filled Stardust default", function()
			local data = { schemaVersion = 1, credits = 900, stardust = 0 }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.stardust, 900)
		end)

		T.test("a version 2 profile keeps its Stardust and ignores stray credits", function()
			local data = { schemaVersion = 2, stardust = 50, credits = 999 }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.stardust, 50)
		end)

		T.test("keeps only the most recent purchase receipts", function()
			local receipts = {}
			local max = Config.Products.MAX_RECEIPTS
			for i = 1, max + 10 do
				table.insert(receipts, `r{i}`)
			end
			local data = { receipts = receipts }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(#data.receipts, max)
			T.equal(data.receipts[1], "r11")
			T.equal(data.receipts[max], `r{max + 10}`)
		end)

		T.test("view exposes only client-safe fields", function()
			local profile = ProfileSchema.default()
			profile.stardust = 42
			local view = ProfileSchema.view(profile)
			T.equal(view.stardust, 42)
			T.equal(view.expansion, 1)
			T.equal((view :: any).receipts, nil)
		end)

		T.test(
			"v11: ship colours, trails, showcase and settings are filled in and checked",
			function()
				local data = ProfileSchema.default()
				data.schemaVersion = 10
				data.showcase = nil :: any
				data.ownedTrails = nil :: any
				data.settings.showBounds = nil :: any
				data.settings.showControls = nil :: any
				data.ownedShips.RedFighter = true
				data.loadouts.RedFighter = {
					equipment = {},
					paint = "#9AA3B0",
					finish = "Metallic",
					laserColor = Config.Paint.SWATCHES[2],
				} :: any
				data.loadouts[Config.Ships.STARTER_SHIP] =
					{ equipment = {}, laserColor = "#123456", boostColor = 7 } :: any
				data.trail = "CometDust"
				T.truthy(ProfileSchema.normalize(data))
				T.equal(data.schemaVersion, ProfileSchema.VERSION)
				T.equal(#data.showcase, 0)
				T.equal(data.settings.showBounds, true)
				T.equal(data.settings.showControls, true)
				T.equal(data.trail, nil, "a trail that isn't owned can't be equipped")
				T.equal(data.loadouts.RedFighter.laserColor, Config.Paint.SWATCHES[2])
				T.equal((data.loadouts.RedFighter :: any).paint, nil, "old paint jobs are dropped")
				T.equal((data.loadouts.RedFighter :: any).finish, nil)
				T.equal(
					data.loadouts[Config.Ships.STARTER_SHIP].laserColor,
					nil,
					"colours outside the swatches are dropped"
				)
				T.equal(data.loadouts[Config.Ships.STARTER_SHIP].boostColor, nil)

				data.ownedTrails = { CometDust = true }
				data.trail = "CometDust"
				T.truthy(ProfileSchema.normalize(data))
				T.equal(data.trail, "CometDust")
				T.equal(
					ProfileSchema.trailMultiplier(data),
					Config.Trails.BY_ID.CometDust.multiplier
				)

				data.showcase =
					{ "RedFighter", "RedFighter", "Warship", Config.Ships.STARTER_SHIP, 5 } :: any
				T.truthy(ProfileSchema.normalize(data))
				T.equal(#data.showcase, 2, "unowned, repeated and bad ids are dropped")
				T.equal(data.showcase[1], "RedFighter")
			end
		)

		T.test("v15: old orbit planets become owned planets, same level, nothing lost", function()
			local data = ProfileSchema.default() :: any
			data.schemaVersion = 14
			data.stats = { planetsBought = 7, planetUpgrades = 2, planetLevels = 3 }
			data.planets = nil
			data.nextPlanetId = nil
			data.galaxy.nextId = 3
			data.galaxy.stars = {
				-- Brown dwarf: 3 orbits now (4 before), so slot 4 goes to inventory.
				s1 = {
					typeId = "BrownDwarf",
					level = 2,
					pos = { x = 0, y = 0, z = 0 },
					planets = { ["1"] = "Barren", ["3"] = "Molten", ["4"] = "Barren" },
					planetLevels = { ["1"] = 3, ["4"] = 2 },
				},
				-- Black hole: 9 orbits now (11 before); 10 and 11 go to inventory.
				s2 = {
					typeId = "BlackHole",
					level = 1,
					pos = { x = 0, y = 200, z = 0 },
					planets = {
						["2"] = "Crystal",
						["9"] = "GasGiant",
						["10"] = "Ocean",
						["11"] = "Retired",
					},
					planetLevels = { ["2"] = 5, ["10"] = 99 },
				},
			}
			local incomeBefore = 0
			local oldIncome = {
				Barren = 2,
				Molten = 5,
				Ocean = 35,
				GasGiant = 480,
				Crystal = 1100,
			}
			for _, star in data.galaxy.stars do
				for slot, id in star.planets do
					local base = oldIncome[id] or 0
					local level = math.clamp(star.planetLevels[slot] or 1, 1, 5)
					incomeBefore += math.floor(base * (1 + 0.5 * (level - 1)) + 0.5)
				end
			end

			T.truthy(ProfileSchema.normalize(data))
			local count, inOrbit, levels = 0, 0, {}
			for id, planet in data.planets do
				count += 1
				T.truthy(Config.Planets.BY_ID[planet.typeId], `{id} has a catalog type`)
				if planet.star then
					inOrbit += 1
					T.truthy(planet.slot <= StarMath.slots(data.galaxy.stars[planet.star].typeId))
				end
				levels[`{planet.star or "inv"}:{planet.slot or 0}:{planet.typeId}`] = planet.level
			end
			T.equal(count, 7, "every old planet became an owned planet")
			T.equal(inOrbit, 4, "slots past the new capacity went to inventory")
			T.equal(levels["s1:1:Basalt"], 3, "levels are kept")
			T.equal(levels["s1:3:Rust"], 1)
			T.equal(levels["inv:0:Basalt"], 2, "overflow keeps its level too")
			T.equal(levels["s2:2:DiamondCrystal"], 5)
			T.equal(levels["s2:9:NebulaShell"], 1)
			T.equal(levels["inv:0:Bioluminescent"], Config.Planets.MAX_LEVEL)
			T.equal(
				levels[`inv:0:{Config.Planets.LEGACY_FALLBACK}`] ~= nil,
				true,
				"unknown ids still become a planet"
			)
			T.equal(data.nextPlanetId, 8)
			for _, star in data.galaxy.stars do
				T.equal(star.planets, nil)
				T.equal(star.planetLevels, nil)
			end
			-- Every equipped planet earns at least what it did in that slot.
			local equippedNow = 0
			for _, planet in data.planets do
				if planet.star then
					equippedNow += StarMath.planetIncome(planet.typeId, planet.level)
				end
			end
			local equippedBefore = math.floor(2 * 2 + 0.5) + 5 + math.floor(1100 * 3 + 0.5) + 480
			T.truthy(equippedNow >= equippedBefore, `{equippedNow} >= {equippedBefore}`)
			T.truthy(incomeBefore > 0)
			-- Old progress still counts towards the new achievements.
			T.equal(data.stats.planetsEquipped, 7)
			T.equal(data.stats.planetsHatched, 7)
			T.equal(data.stats.planetLevels, 5)

			-- Running it again changes nothing.
			local again = table.clone(data.planets)
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.stats.planetLevels, 5, "stats carried over once")
			for id, planet in again do
				T.equal(data.planets[id].typeId, planet.typeId)
				T.equal(data.planets[id].star, planet.star)
			end
		end)

		T.test("v15: planets equipped on missing stars or shared slots go to inventory", function()
			local data = ProfileSchema.default() :: any
			data.galaxy.stars.s1 =
				{ typeId = "BrownDwarf", level = 1, pos = { x = 0, y = 0, z = 0 } }
			data.planets = {
				p1 = { typeId = "Basalt", level = 9, star = "s1", slot = 1 },
				p2 = { typeId = "Moss", level = 1, star = "s1", slot = 1 },
				p3 = { typeId = "Geode", level = 2, star = "gone", slot = 2 },
				p4 = { typeId = "Coral", level = 1, star = "s1", slot = 7 },
				p5 = "junk",
				p6 = { typeId = "FutureType", level = 1 },
			}
			data.nextPlanetId = 2
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.planets.p1.star, "s1")
			T.equal(data.planets.p1.level, Config.Planets.MAX_LEVEL)
			T.equal(data.planets.p2.star, nil, "slot already taken")
			T.equal(data.planets.p3.star, nil, "star is gone")
			T.equal(data.planets.p3.level, 2)
			T.equal(data.planets.p4.star, nil, "slot past capacity")
			T.equal(data.planets.p5, nil)
			T.truthy(data.planets.p6, "a type this server doesn't know is kept")
			T.equal(data.nextPlanetId, 7, "next id passes every existing id")
		end)

		T.test("v15: eggs, hatches and the wheel are cleaned up, never rerolled", function()
			local data = ProfileSchema.default() :: any
			data.eggs = {
				e1 = { outcome = "Aurora", guaranteed = false, boughtAt = 100 },
				e2 = { outcome = 5 },
			}
			data.hatches = {
				["1"] = { eggId = "e3", outcome = "Singularity", startedAt = 10, endsAt = 1810 },
				["6"] = { eggId = "e4", outcome = "Basalt", startedAt = 10, endsAt = 20 },
				["2"] = { eggId = "e5", outcome = "Basalt", startedAt = "x", endsAt = 20 },
			}
			data.nextEggId = 1
			data.wheel = { nextSpin = 123, lastPrize = 99 }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.eggs.e1.outcome, "Aurora")
			T.equal(data.eggs.e2, nil)
			T.equal(data.hatches["1"].outcome, "Singularity")
			T.equal(data.hatches["1"].endsAt, 1810)
			T.equal(data.hatches["6"], nil, "only HATCH_SLOTS chambers")
			T.equal(data.hatches["2"], nil)
			T.equal(data.nextEggId, 4)
			T.equal(data.wheel.nextSpin, 123)
			T.equal(data.wheel.lastPrize, #Config.Wheel.PRIZES)
			-- The client sees a mystery egg's rarity only once hatching, never its planet.
			local view = ProfileSchema.view(data)
			T.equal(view.eggs.e1.outcome, nil)
			T.equal(view.hatches["1"].rarity, "Interstellar")
			T.equal((view.hatches["1"] :: any).outcome, nil)
		end)

		T.test("v16: new settings default safely; locks and the Planet Index", function()
			local data = ProfileSchema.default() :: any
			data.schemaVersion = 15
			data.settings.floating = nil
			data.settings.autoSell = { Common = true, Legendary = true, Rare = "yes" }
			data.planets = {
				p1 = { typeId = "Aurora", level = 1, locked = true },
				p2 = { typeId = "Basalt", level = 1, locked = "x" },
			}
			data.discovered = { Geode = true, Junk = 5 }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.schemaVersion, 16)
			T.equal(data.settings.floating, true, "floating stays the default")
			T.equal(data.settings.autoIncubate, true)
			T.equal(data.settings.keepNewTypes, true)
			T.equal(data.settings.autoSell.Common, true)
			T.equal(data.settings.autoSell.Legendary, nil, "Legendary can't be auto-sold")
			T.equal(data.settings.autoSell.Rare, nil)
			T.equal(data.planets.p1.locked, true)
			T.equal(data.planets.p2.locked, nil)
			T.truthy(data.discovered.Geode and data.discovered.Aurora and data.discovered.Basalt)
			T.equal(data.discovered.Junk, nil)
		end)

		T.test("v13: redeemed codes are kept as flags; the ILUVGHIASY code exists", function()
			local data = ProfileSchema.default()
			data.schemaVersion = 12
			data.redeemedCodes = nil :: any
			T.truthy(ProfileSchema.normalize(data))
			T.equal(next(data.redeemedCodes), nil, "none redeemed yet")
			data.redeemedCodes = { ILUVGHIASY = true, BAD = 5 } :: any
			T.truthy(ProfileSchema.normalize(data))
			T.equal(data.redeemedCodes.ILUVGHIASY, true)
			T.equal(data.redeemedCodes.BAD, nil)
			local code = Config.Codes.BY_CODE.ILUVGHIASY
			T.equal(code and code.stardust, 5000000, "the code gives 5,000,000 Stardust")
			T.truthy(Config.Codes.BY_CODE.PLANETZPLZ.allPlanets, "PlanetzPlz: one of every planet")
			T.truthy(Config.Codes.BY_CODE.STARZSHIPZ.allShips, "StarzShipz: every ship")
		end)
	end)
end

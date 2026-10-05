return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local ProfileSchema = Loader.require("src/shared/Logic/ProfileSchema")

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
							planets = { ["1"] = "Barren", ["99"] = "Ocean", [2] = "Desert" },
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
			T.equal(galaxy.stars.s1.planets["1"], "Barren")
			T.equal(galaxy.stars.s1.planets["99"], nil, "slot out of range")
			T.equal(galaxy.stars.s1.planets["2"], nil, "number key dropped")
			T.truthy(galaxy.stars.s4, "unknown type kept")
			T.equal(type(galaxy.stars.s4.planets), "table", "planets filled in")
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

		T.test("v12: planet levels are kept for planets that exist, within 2..MAX_LEVEL", function()
			local data = ProfileSchema.default()
			data.schemaVersion = 11
			data.galaxy.stars.s1 = {
				typeId = Config.Stars.DEFAULT_TYPE,
				level = 1,
				pos = { x = 0, y = 0, z = 0 },
				planets = { ["1"] = "Barren", ["2"] = "Barren" },
				planetLevels = { ["1"] = 3, ["2"] = 99, ["3"] = 4, ["4"] = "x" },
			} :: any
			T.truthy(ProfileSchema.normalize(data))
			local levels = data.galaxy.stars.s1.planetLevels :: { [string]: number }
			T.equal(levels["1"], 3)
			T.equal(levels["2"], Config.Planets.MAX_LEVEL)
			T.equal(levels["3"], nil, "no planet in slot 3")
			T.equal(levels["4"], nil)
		end)
	end)
end

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
			T.equal(data.stardust, 0)
			T.truthy(data.ownedShips[starter])
			T.equal(type(data.galaxy.systems), "table")
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
			T.equal(data.stardust, 0)
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
			local data = { activeShip = "Prospector", ownedShips = {} }
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

		T.test("keeps valid galaxy records and drops corrupt ones", function()
			local data = {
				galaxy = {
					expansion = 99,
					nextId = 2,
					systems = {
						s1 = { starId = "b2", tier = 1, pos = { x = 0, y = 10, z = 500 } },
						s9 = { starId = "b3", tier = 1, pos = { x = "far", y = 0, z = 0 } },
					},
					bodies = {
						b2 = { kind = "star", typeId = "StarterStar", systemId = "s1", level = 2 },
						b5 = {
							kind = "planet",
							typeId = "RockyPlanet",
							systemId = "s1",
							parentId = "b2",
							level = 1,
							orbit = { slot = 1, tilt = 0.2, node = 1, phase = 3 },
						},
						b6 = {
							kind = "planet",
							typeId = "RockyPlanet",
							systemId = "s1",
							parentId = "b2",
							level = 1,
						},
						b7 = { kind = "comet", typeId = "X", systemId = "s1", level = 1 },
					},
				},
			}
			T.truthy(ProfileSchema.normalize(data))
			local galaxy = data.galaxy
			T.equal(galaxy.expansion, #Config.Galaxy.EXPANSIONS, "expansion clamped")
			T.truthy(galaxy.systems.s1)
			T.equal(galaxy.systems.s9, nil, "system with a bad position")
			T.truthy(galaxy.bodies.b2)
			T.truthy(galaxy.bodies.b5)
			T.equal(galaxy.bodies.b6, nil, "planet without an orbit")
			T.equal(galaxy.bodies.b7, nil, "unknown kind")
			T.equal(galaxy.nextId, 10, "nextId moves past every existing id")
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
			for i = 1, 60 do
				table.insert(receipts, `r{i}`)
			end
			local data = { receipts = receipts }
			T.truthy(ProfileSchema.normalize(data))
			T.equal(#data.receipts, 50)
			T.equal(data.receipts[1], "r11")
			T.equal(data.receipts[50], "r60")
		end)

		T.test("view exposes only client-safe fields", function()
			local profile = ProfileSchema.default()
			profile.stardust = 42
			local view = ProfileSchema.view(profile)
			T.equal(view.stardust, 42)
			T.equal(view.expansion, 1)
			T.equal((view :: any).receipts, nil)
		end)
	end)
end

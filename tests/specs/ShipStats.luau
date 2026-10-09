return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local ProfileSchema = Loader.require("src/shared/Logic/ProfileSchema")
	local ShipStats = Loader.require("src/shared/Logic/ShipStats")

	local starter = Config.Ships.STARTER_SHIP
	local base = Config.Ships.BY_ID[starter].stats

	T.describe("ShipStats", function()
		T.test("no loadout gives the chassis stats", function()
			local stats = ShipStats.effective(starter, nil)
			T.equal(stats.cargoCapacity, base.cargoCapacity)
			T.equal(stats.maxSpeed, base.maxSpeed)
		end)

		T.test("equipment bought for the ship, in the right slot, multiplies stats", function()
			local loadout = {
				equipment = { Cargo = "CargoMk2", Thrusters = "ThrustersMk2" },
				levels = { CargoMk2 = 1, ThrustersMk2 = 4 },
			}
			local stats = ShipStats.effective(starter, loadout :: any)
			T.near(stats.cargoCapacity, base.cargoCapacity * 1.4)
			T.near(stats.maxSpeed, base.maxSpeed * 1.6, 1e-9, "level 4: +60%")
			T.near(stats.beamPower, base.beamPower, 1e-9, "unrelated stat unchanged")
		end)

		T.test("unowned, unknown or mis-slotted equipment is ignored", function()
			local loadout = {
				equipment = { Cargo = "CargoMk2", Beam = "CargoMk2", Cooling = "Nope" },
				levels = {},
			}
			local unowned = ShipStats.effective(starter, loadout :: any)
			T.equal(unowned.cargoCapacity, base.cargoCapacity)
			local misSlotted = ShipStats.effective(
				starter,
				{ equipment = { Beam = "CargoMk2" }, levels = { CargoMk2 = 1 } } :: any
			)
			T.equal(misSlotted.cargoCapacity, base.cargoCapacity)
		end)

		T.test("effective stats never change the config table", function()
			ShipStats.effective(
				starter,
				{ equipment = { Cargo = "CargoMk2" }, levels = { CargoMk2 = 1 } } :: any
			)
			T.equal(Config.Ships.BY_ID[starter].stats.cargoCapacity, base.cargoCapacity)
		end)

		T.test("unknown ships return nil and profiles fall back to the starter", function()
			T.equal(ShipStats.effective("Nope", nil), nil)
			local profile = ProfileSchema.default()
			profile.activeShip = "Nope"
			T.equal(ShipStats.forProfile(profile).maxSpeed, base.maxSpeed)
		end)

		T.test("canCarry blocks switching to a ship with too small a hold", function()
			local stats = ShipStats.effective(starter, nil)
			T.truthy(ShipStats.canCarry(stats, { Iron = 30, Silicate = 30 }))
			T.falsy(ShipStats.canCarry(stats, { Iron = 40, Silicate = 30 }))
			T.equal(ShipStats.cargoUsed({ Iron = 4, Ice = 6 }), 10)
		end)
	end)
end

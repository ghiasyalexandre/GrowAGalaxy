-- The real config must pass every consistency check, and the checker must
-- catch the mistakes it exists for.

return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local ConfigCheck = Loader.require("src/shared/Logic/ConfigCheck")

	local function hasProblem(problems: { string }, fragment: string): boolean
		for _, problem in problems do
			if string.find(problem, fragment, 1, true) then
				return true
			end
		end
		return false
	end

	T.describe("ConfigCheck", function()
		T.test("the shipped config has no problems", function()
			local problems = ConfigCheck.run(Config)
			for _, problem in problems do
				print(`        - {problem}`)
			end
			T.equal(#problems, 0, "problem count")
		end)

		T.test("catches a tier that needs a level only it unlocks", function()
			local broken = T.deepCopy(Config)
			broken.SolarSystems.TIERS[2].requirements.starLevel = 3
			T.truthy(hasProblem(ConfigCheck.run(broken), "caps stars at 2"))
		end)

		T.test("catches a tier needing more planets than slots allow", function()
			local broken = T.deepCopy(Config)
			broken.SolarSystems.TIERS[2].requirements.planets = 4
			T.truthy(hasProblem(ConfigCheck.run(broken), "allows only"))
		end)

		T.test("catches a zone unlocked by its own material", function()
			local broken = T.deepCopy(Config)
			broken.Zones.BY_ID.FrozenBelt.unlock.materials = { Ice = 10 }
			T.truthy(hasProblem(ConfigCheck.run(broken), "which no earlier zone produces"))
		end)

		T.test("catches recipes with unknown materials", function()
			local broken = T.deepCopy(Config)
			broken.Recipes.BY_ID.StellarCore.materials = { Unobtainium = 5 }
			T.truthy(hasProblem(ConfigCheck.run(broken), "unknown material"))
		end)

		T.test("catches an enabled recipe that needs a material from a locked zone", function()
			local broken = T.deepCopy(Config)
			broken.Recipes.BY_ID.RockyPlanet.materials = { Ice = 5 }
			T.truthy(hasProblem(ConfigCheck.run(broken), "not minable in any enabled zone"))
		end)

		T.test("catches orbits that would let planets collide", function()
			local broken = T.deepCopy(Config)
			broken.Galaxy.PLANET_ORBIT_RADII = { 52, 70, 140, 184 }
			T.truthy(hasProblem(ConfigCheck.run(broken), "too close"))
		end)

		T.test("catches a planet too big for the geometry caps", function()
			local broken = T.deepCopy(Config)
			broken.Celestials.BY_ID.RockyPlanet.levels[4].radius = 12
			T.truthy(hasProblem(ConfigCheck.run(broken), "outside 0..7"))
		end)

		T.test("catches enabled purchases without product ids", function()
			local broken = T.deepCopy(Config)
			broken.Products.PURCHASES_ENABLED = true
			T.truthy(hasProblem(ConfigCheck.run(broken), "has no id"))
		end)

		T.test("catches a spacesuit faster than a ship", function()
			local broken = T.deepCopy(Config)
			broken.Movement.SUIT_MAX_SPEED = 500
			T.truthy(hasProblem(ConfigCheck.run(broken), "spacesuit is not slower"))
		end)

		T.test("catches a flight area smaller than the regions", function()
			local broken = T.deepCopy(Config)
			broken.Movement.FLIGHT_BOUNDS_RADIUS = 3500
			T.truthy(hasProblem(ConfigCheck.run(broken), "FLIGHT_BOUNDS_RADIUS"))
		end)

		T.test("catches a flight area that reaches the Earth", function()
			local broken = T.deepCopy(Config)
			broken.Movement.FLIGHT_BOUNDS_HEIGHT = 2500
			T.truthy(hasProblem(ConfigCheck.run(broken), "Earth backdrop"))
		end)

		T.test("catches a paid ship with no earnable path", function()
			local broken = T.deepCopy(Config)
			broken.Ships.BY_ID.CrystalExplorer.earn = nil
			T.truthy(hasProblem(ConfigCheck.run(broken), "no gameplay way to earn"))
		end)
	end)
end

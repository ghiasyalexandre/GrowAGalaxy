return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local RaidMath = Loader.require("src/shared/Logic/RaidMath")

	local R = Config.Raids

	T.describe("RaidMath", function()
		T.test("harder raids give better rewards and tougher bosses", function()
			local lastStardust, lastHealth = 0, 0
			for _, id in R.ORDER do
				local def = R.BY_ID[id]
				T.truthy(def.reward.stardust > lastStardust, id)
				T.truthy(def.bossHealth > lastHealth, id)
				lastStardust, lastHealth = def.reward.stardust, def.bossHealth
			end
		end)

		T.test("boss health grows with the number of raiders", function()
			local one = RaidMath.bossHealth("Easy", 1)
			T.equal(one, R.BY_ID.Easy.bossHealth)
			T.equal(
				RaidMath.bossHealth("Easy", 3),
				math.floor(one * (1 + 2 * R.BY_ID.Easy.healthPerExtraRaider))
			)
			T.equal(RaidMath.bossHealth("Easy", 0), one)
		end)

		T.test("the weak point takes extra damage", function()
			T.equal(RaidMath.bossDamage(10, false), 10 * R.DAMAGE_PER_POWER)
			T.equal(
				RaidMath.bossDamage(10, true),
				10 * R.DAMAGE_PER_POWER * R.WEAK_POINT_MULTIPLIER
			)
		end)

		T.test("queues start after the countdown, or sooner when full", function()
			T.equal(RaidMath.startTime(100, nil), 100 + R.QUEUE_COUNTDOWN)
			T.equal(RaidMath.startTime(100, 102), 102 + R.FULL_COUNTDOWN)
			T.equal(RaidMath.startTime(100, 100 + R.QUEUE_COUNTDOWN), 100 + R.QUEUE_COUNTDOWN)
		end)

		T.test("rewards need real help or survival", function()
			T.truthy(RaidMath.earnsReward(0, 1000, true))
			T.truthy(RaidMath.earnsReward(1000 * R.MIN_DAMAGE_SHARE, 1000, false))
			T.equal(RaidMath.earnsReward(1, 1000, false), false)
		end)

		T.test("attacks hit what's in their path", function()
			local a, b = { x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }
			T.near(RaidMath.distanceToSegment({ x = 50, y = 10, z = 0 }, a, b), 10)
			T.near(RaidMath.distanceToSegment({ x = -30, y = 40, z = 0 }, a, b), 50)
			T.truthy(
				RaidMath.boltHits(
					{ x = 0, y = 0, z = 0 },
					{ x = R.BOLT_HIT_RADIUS - 1, y = 0, z = 0 }
				)
			)
			T.equal(RaidMath.boltHits({ x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }), false)
			T.near(RaidMath.boltTime(R.BOLT_SPEED * 2), 2)
		end)
	end)
end

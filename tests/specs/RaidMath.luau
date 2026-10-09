return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local RaidMath = Loader.require("src/shared/Logic/RaidMath")

	local R = Config.Raids

	T.describe("RaidMath", function()
		T.test("harder raids give better rewards and tougher bosses", function()
			local lastStardust, lastHealth = 0, 0
			for _, id in R.ORDER do
				local def = R.BY_ID[id]
				T.truthy(def.reward.minutes > lastStardust, id)
				T.truthy(def.bossHealth > lastHealth, id)
				lastStardust, lastHealth = def.reward.minutes, def.bossHealth
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

		T.test("the weak point moves every 5% of health lost", function()
			T.equal(RaidMath.weakStage(1000, 1000), 0)
			T.equal(RaidMath.weakStage(951, 1000), 0)
			T.equal(RaidMath.weakStage(950, 1000), 1)
			T.equal(RaidMath.weakStage(500, 1000), 10)
			T.equal(RaidMath.weakStage(0, 1000), 20)
		end)

		T.test("new weak point spots are far from the last", function()
			local seed = 7
			local function rng(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end
			local minDot = math.cos(math.rad(R.WEAK_POINT_MIN_ANGLE))
			local previous = nil
			for _ = 1, 50 do
				local d = RaidMath.nextWeakDirection(previous, rng)
				T.near(math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1, 1e-6)
				if previous then
					T.truthy(
						d.x * previous.x + d.y * previous.y + d.z * previous.z <= minDot + 1e-9
					)
				end
				previous = d
			end
		end)

		T.test("the boss enrages at low health and attacks faster", function()
			T.equal(RaidMath.enraged(1000, 1000), false)
			T.truthy(RaidMath.enraged(1000 * R.ENRAGE_SHARE - 1, 1000))
			T.equal(RaidMath.enraged(0, 1000), false)
			T.truthy(RaidMath.moveInterval(10, true) < RaidMath.moveInterval(10, false))
		end)

		T.test("shockwaves hit only in their plane, as the ring passes", function()
			local c, n = { x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }
			T.truthy(RaidMath.ringHits({ x = 100, y = 0, z = 0 }, c, n, 80, 120))
			T.equal(
				RaidMath.ringHits({ x = 100, y = R.SHOCKWAVE_THICKNESS + 1, z = 0 }, c, n, 80, 120),
				false
			)
			T.equal(RaidMath.ringHits({ x = 300, y = 0, z = 0 }, c, n, 80, 120), false)
			T.truthy(
				RaidMath.inBlast(
					{ x = 0, y = 0, z = 0 },
					{ x = R.BOMBARD_RADIUS - 1, y = 0, z = 0 }
				)
			)
			T.equal(
				RaidMath.inBlast(
					{ x = 0, y = 0, z = 0 },
					{ x = R.BOMBARD_RADIUS + 1, y = 0, z = 0 }
				),
				false
			)
		end)

		T.test("harder raids add moves", function()
			local last = 0
			for _, id in R.ORDER do
				local n = 0
				for _ in R.BY_ID[id].moves do
					n += 1
				end
				T.truthy(n >= last and n >= 3, id)
				last = n
			end
			T.truthy(R.BY_ID.Hard.moves.bombard ~= nil)
		end)
	end)
end

--!strict
-- Death Star raids. Outside the ISS, the Saturn V rocket is the raid beacon:
-- three glowing pads around it (Easy, Medium, Hard) each hold a queue.
-- Step on a pad (or use its prompt) to join; the countdown starts with the
-- first player and is cut short when the queue is full. When it ends, the
-- queued players are put in their ships at that difficulty's arena, high
-- above the ISS, facing the Death Star.
--
-- The boss: its health grows with the number of players. Lasers damage it
-- (its glowing superlaser dish takes WEAK_POINT_MULTIPLIER x). It fires
-- turbolaser volleys at raiders' ships (aimed where they are when fired, so
-- they can be dodged) and, on Medium and Hard, charges its superlaser: a
-- telegraphed beam that hits everything in a line. Raiders whose ships are
-- destroyed are out. Win before TIME_LIMIT to earn the difficulty's
-- reward (fixed amounts: no multiplier applies).

export type Difficulty = "Easy" | "Medium" | "Hard"

export type DifficultyDef = {
	id: Difficulty,
	displayName: string,
	color: string,
	order: number,
	pad: { angle: number }, -- degrees around the Saturn V
	arena: { x: number, y: number, z: number }, -- world position of the boss
	bossHealth: number, -- for one raider
	healthPerExtraRaider: number, -- share of bossHealth added per extra raider
	volleyInterval: number, -- seconds between turbolaser volleys
	boltsPerVolley: number,
	boltDamage: number, -- hull points
	superlaser: boolean,
	superlaserInterval: number,
	superlaserDamage: number,
	reward: { stardust: number, boost: { source: "mining" | "star", seconds: number }? },
}

local ORDER: { Difficulty } = { "Easy", "Medium", "Hard" }

local BY_ID: { [string]: DifficultyDef } = {
	Easy = {
		id = "Easy",
		displayName = "Easy",
		color = "#5CFF8A",
		order = 1,
		pad = { angle = -50 },
		arena = { x = -1200, y = 1100, z = 0 },
		bossHealth = 1500,
		healthPerExtraRaider = 0.6,
		volleyInterval = 4,
		boltsPerVolley = 2,
		boltDamage = 12,
		superlaser = false,
		superlaserInterval = 0,
		superlaserDamage = 0,
		reward = { stardust = 3000 },
	},
	Medium = {
		id = "Medium",
		displayName = "Medium",
		color = "#FFB347",
		order = 2,
		pad = { angle = 0 },
		arena = { x = 0, y = 1100, z = 1200 },
		bossHealth = 4000,
		healthPerExtraRaider = 0.7,
		volleyInterval = 3,
		boltsPerVolley = 3,
		boltDamage = 18,
		superlaser = true,
		superlaserInterval = 30,
		superlaserDamage = 70,
		reward = { stardust = 9000, boost = { source = "mining", seconds = 10 * 60 } },
	},
	Hard = {
		id = "Hard",
		displayName = "Hard",
		color = "#FF4A4A",
		order = 3,
		pad = { angle = 50 },
		arena = { x = 1200, y = 1100, z = 0 },
		bossHealth = 10000,
		healthPerExtraRaider = 0.8,
		volleyInterval = 2.2,
		boltsPerVolley = 4,
		boltDamage = 26,
		superlaser = true,
		superlaserInterval = 20,
		superlaserDamage = 120,
		reward = { stardust = 25000, boost = { source = "star", seconds = 20 * 60 } },
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	MAX_RAIDERS = 6,
	QUEUE_COUNTDOWN = 20, -- seconds from the first player joining
	FULL_COUNTDOWN = 5, -- seconds once the queue is full
	TIME_LIMIT = 300, -- seconds to beat the boss
	END_DELAY = 6, -- seconds after a win or loss before raiders go home
	OUT_DELAY = 3, -- seconds after losing your ship before you go home
	-- Boss
	BOSS_SIZE = 260, -- studs across
	BOSS_SPIN = 0.04, -- radians per second (drawn by clients)
	DAMAGE_PER_POWER = 1, -- boss damage per shot = shooter's beamPower x this
	WEAK_POINT_MULTIPLIER = 3,
	START_DISTANCE = 520, -- studs from the boss's centre where raiders start
	BOLT_SPEED = 260, -- studs per second (turbolasers)
	BOLT_HIT_RADIUS = 14, -- studs: a ship this close to the aim point is hit
	SUPERLASER_CHARGE = 3, -- seconds of warning glow before it fires
	SUPERLASER_WIDTH = 40, -- studs: ships this close to the beam's line are hit
	-- A raider must deal this share of the boss's health to share the reward
	-- (or still be flying when it falls).
	MIN_DAMAGE_SHARE = 0.03,
	-- The raid beacon area outside the ISS.
	PAD_RADIUS = 6,
	PAD_DISTANCE = 70, -- studs from the Saturn V's base to each pad
	BEACON_HEIGHT = 170, -- studs: the Saturn V is scaled to this height
}

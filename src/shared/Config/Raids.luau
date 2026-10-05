--!strict
-- Death Star raids. Outside the ISS, the Saturn V rocket is the raid beacon:
-- three glowing pads around it (Easy, Medium, Hard) each hold a queue.
-- Step on a pad (or use its prompt) to join; the countdown starts with the
-- first player and is cut short when the queue is full. When it ends, the
-- queued players are put in their ships at that difficulty's arena, high
-- above the ISS, facing the Death Star.
--
-- The boss: its health grows with the number of players. Lasers damage it;
-- its glowing weak point takes WEAK_POINT_MULTIPLIER x and jumps to a new
-- spot on the hull every time the boss loses WEAK_POINT_MOVE_SHARE of its
-- health. Below ENRAGE_SHARE health it is enraged: every move comes
-- ENRAGE_SPEEDUP x as often. Its moves (each per difficulty, nil = never):
--
--   volley      turbolaser bolts aimed where raiders are when fired (dodge
--               by moving)
--   drones      homing drones that chase a raider and explode on contact;
--               one laser hit destroys one
--   shockwave   a glowing ring expanding from the boss in a tilted plane,
--               after a short charge showing that plane; fly out of the
--               plane (above or below the ring) to dodge it
--   superlaser  a telegraphed beam that hits everything along a line
--   bombard     (Hard) warning zones appear on and around raiders, then
--               detonate
--
-- Raiders whose ships are destroyed are out. Win before TIME_LIMIT to earn
-- the difficulty's reward (fixed amounts: no multiplier applies).
-- Logic/ConfigCheck validates this table.

export type Difficulty = "Easy" | "Medium" | "Hard"

export type Moves = {
	volley: { interval: number, bolts: number, damage: number },
	drones: { interval: number, count: number, damage: number }?,
	shockwave: { interval: number, damage: number }?,
	superlaser: { interval: number, damage: number }?,
	bombard: { interval: number, count: number, damage: number }?,
}

export type DifficultyDef = {
	id: Difficulty,
	displayName: string,
	color: string,
	order: number,
	pad: { angle: number }, -- degrees around the Saturn V
	arena: { x: number, y: number, z: number }, -- world position of the boss
	bossHealth: number, -- for one raider
	healthPerExtraRaider: number, -- share of bossHealth added per extra raider
	moves: Moves, -- intervals in seconds, damage in hull points
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
		bossHealth = 4000,
		healthPerExtraRaider = 0.6,
		moves = {
			volley = { interval = 4, bolts = 2, damage = 12 },
			drones = { interval = 18, count = 2, damage = 15 },
			shockwave = { interval = 22, damage = 20 },
		},
		reward = { stardust = 4000 },
	},
	Medium = {
		id = "Medium",
		displayName = "Medium",
		color = "#FFB347",
		order = 2,
		pad = { angle = 0 },
		arena = { x = 0, y = 1100, z = 1200 },
		bossHealth = 12000,
		healthPerExtraRaider = 0.7,
		moves = {
			volley = { interval = 3, bolts = 3, damage = 18 },
			drones = { interval = 15, count = 3, damage = 22 },
			shockwave = { interval = 18, damage = 30 },
			superlaser = { interval = 30, damage = 70 },
		},
		reward = { stardust = 14000, boost = { source = "mining", seconds = 10 * 60 } },
	},
	Hard = {
		id = "Hard",
		displayName = "Hard",
		color = "#FF4A4A",
		order = 3,
		pad = { angle = 50 },
		arena = { x = 1200, y = 1100, z = 0 },
		bossHealth = 35000,
		healthPerExtraRaider = 0.8,
		moves = {
			volley = { interval = 2.2, bolts = 4, damage = 26 },
			drones = { interval = 12, count = 4, damage = 30 },
			shockwave = { interval = 14, damage = 45 },
			superlaser = { interval = 20, damage = 120 },
			bombard = { interval = 16, count = 6, damage = 60 },
		},
		reward = { stardust = 45000, boost = { source = "star", seconds = 20 * 60 } },
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
	-- Boss damage per shot = shooter's beamPower x this (the same share of
	-- beam power a shot puts into an asteroid, Config.Beam.SHOT_POWER).
	DAMAGE_PER_POWER = 0.5,
	WEAK_POINT_MULTIPLIER = 3,
	WEAK_POINT_MOVE_SHARE = 0.05, -- the weak point jumps after each 5% of health lost
	WEAK_POINT_MIN_ANGLE = 50, -- degrees: each new spot is at least this far round from the last
	ENRAGE_SHARE = 0.25, -- below this share of health the boss is enraged
	ENRAGE_SPEEDUP = 1.35, -- enraged, every move comes this many times as often
	-- Big moves (shockwave, superlaser, bombard) never overlap: after one
	-- starts, the others wait this long.
	BIG_MOVE_GAP = 5,
	START_DISTANCE = 520, -- studs from the boss's centre where raiders start
	-- Volley
	BOLT_SPEED = 260, -- studs per second (turbolasers)
	BOLT_HIT_RADIUS = 14, -- studs: a ship this close to the aim point is hit
	-- Drones
	DRONE_SPEED = 75, -- studs per second; every ship can outrun one
	DRONE_TURN = 2.5, -- radians per second they can turn
	DRONE_LIFETIME = 14, -- seconds before one burns out
	DRONE_HIT_RADIUS = 12, -- studs: explodes on a ship this close
	DRONE_SIZE = 7, -- studs across
	-- Shockwave
	SHOCKWAVE_CHARGE = 1.5, -- seconds the plane is shown before the ring goes out
	SHOCKWAVE_SPEED = 230, -- studs per second the ring grows
	SHOCKWAVE_RANGE = 950, -- studs: the ring fades at this radius
	SHOCKWAVE_THICKNESS = 16, -- studs either side of the plane that the ring hits
	SHOCKWAVE_BAND = 24, -- studs of ring width
	-- Superlaser
	SUPERLASER_CHARGE = 3, -- seconds of warning glow before it fires
	SUPERLASER_WIDTH = 40, -- studs: ships this close to the beam's line are hit
	-- Bombard
	BOMBARD_DELAY = 2.6, -- seconds between the warning and the blast
	BOMBARD_RADIUS = 45, -- studs: blast radius
	BOMBARD_SPREAD = 150, -- studs: extra blasts land this far around raiders
	-- A raider must deal this share of the boss's health to share the reward
	-- (or still be flying when it falls).
	MIN_DAMAGE_SHARE = 0.03,
	-- The raid beacon area outside the ISS.
	PAD_RADIUS = 6,
	PAD_DISTANCE = 70, -- studs from the Saturn V's base to each pad
	BEACON_HEIGHT = 170, -- studs: the Saturn V is scaled to this height
}

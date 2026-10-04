--!strict
-- Ship mining laser. Each click fires one shot: a short bolt that adds heat
-- and, on an asteroid, extraction progress (Config.Asteroids). Range, heat
-- capacity and cooling come from each ship's stats (Config.Ships); these are
-- the rules every laser shares.

local Beam = {
	-- Fastest the laser can fire: at most one shot per FIRE_INTERVAL seconds.
	FIRE_INTERVAL = 0.22,
	-- Heat added by each shot. A ship with heatCapacity 100 overheats after
	-- 12 shots fired faster than it cools.
	HEAT_PER_SHOT = 9,
	-- Extraction per shot, in seconds of the ship's beamPower: a shot from a
	-- beamPower 10 ship on a weak point adds 5 progress.
	SHOT_POWER = 0.5,
	-- An overheated laser stays locked until its heat falls to this share of
	-- the ship's capacity.
	OVERHEAT_RESUME_SHARE = 0.3,
	-- How far a shot can point away from the ship's nose.
	AIM_CONE_DEGREES = 35,
	-- How often the server cools lasers and updates heat.
	SERVER_TICK = 0.1,

	-- Looks
	COLOR = "#FF6A3D",
	CORE_COLOR = "#FFF4D6",
	WIDTH = 1.6, -- studs
	BOLT_TIME = 0.2, -- seconds a shot's bolt stays visible
	BOLT_TRAVEL_TIME = 0.05, -- seconds for the bolt to reach what it hits
	MUZZLE_FLASH_SIZE = 3.5, -- studs, flash at the ship's nose
	IMPACT_FLASH_SIZE = 9, -- studs, flash and shockwave where a bolt hits
	SPARK_BURST = 30, -- sparks where a bolt hits
	DEBRIS_BURST = 10, -- rock chips knocked off an asteroid

	-- Feel (your own ship only). Each shot kicks the camera up by
	-- RECOIL_DEGREES, recovering at RECOIL_RECOVERY per second, narrows the
	-- view by RECOIL_FOV degrees and pushes the ship back by RECOIL_PUSH
	-- studs per second. Shake is in studs and dies away at SHAKE_DECAY.
	RECOIL_DEGREES = 1.8,
	RECOIL_RECOVERY = 12,
	RECOIL_FOV = 3,
	RECOIL_PUSH = 5,
	SHOT_SHAKE = 0.2,
	HIT_SHAKE = 0.5,
	SHAKE_DECAY = 10,
}

return Beam

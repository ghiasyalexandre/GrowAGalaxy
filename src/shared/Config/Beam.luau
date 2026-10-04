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
	WIDTH = 0.9, -- studs
	BOLT_TIME = 0.12, -- seconds a shot's bolt stays visible
}

return Beam

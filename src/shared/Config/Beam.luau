--!strict
-- Ship mining laser. Range, heat capacity and cooling come from each ship's
-- stats (Config.Ships); these are the rules every beam shares. What the beam
-- does to asteroids is in Config.Asteroids.

local Beam = {
	-- Heat added per second while the beam fires. A ship with heatCapacity
	-- 100 fires for 5 seconds before it overheats.
	HEAT_PER_SECOND = 20,
	-- An overheated beam stays locked until its heat falls to this share of
	-- the ship's capacity.
	OVERHEAT_RESUME_SHARE = 0.3,
	-- How far the beam can point away from the ship's nose.
	AIM_CONE_DEGREES = 35,
	-- How often a pilot's client sends a changed aim while firing, and how
	-- often the server updates heat.
	AIM_SEND_INTERVAL = 0.1,
	SERVER_TICK = 0.1,

	-- Looks
	COLOR = "#FF6A3D",
	CORE_COLOR = "#FFF4D6",
	WIDTH = 0.7, -- studs
}

return Beam

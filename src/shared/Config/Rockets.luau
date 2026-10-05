--!strict
-- The ship's rocket (Q / gamepad B / touch button while flying): a heavy
-- missile on a long cooldown that flies straight where you aim and bursts in
-- a big explosion the colour of your laser. The blast adds extraction to
-- asteroids it catches (breaking them pays as usual), hurts the Death Star
-- and its drones in a raid, and damages PvP ships under the usual PvP rules.

return {
	COOLDOWN = 12, -- seconds between rockets
	SPEED = 240, -- studs per second
	LIFETIME = 3, -- seconds before it bursts on its own
	HIT_RADIUS = 3, -- studs: what it collides with
	BLAST_RADIUS = 45, -- studs
	-- Blast strength = the ship's beam power x POWER: extraction progress on
	-- asteroids, damage on the Death Star (x Raids.DAMAGE_PER_POWER) and on
	-- PvP ships (x Combat.DAMAGE_PER_POWER).
	POWER = 12,
	-- The aim may be at most this many degrees off the ship's nose.
	MAX_AIM_ANGLE = 60,
}

--!strict
-- Opt-in PvP between ships. A laser shot damages another player's piloted
-- ship only when both players have PvP switched on (a saved setting, off by
-- default) and neither ship is inside a docking area. A ship's hull points
-- come from its stats (Config.Ships `hull`); at 0 it explodes, its pilot
-- floats free, and its owner can relaunch after RELAUNCH_DELAY.

return {
	PVP_DEFAULT = false,
	-- Hull damage per shot = the shooter's beamPower x DAMAGE_PER_POWER.
	-- A Micro Recon (beamPower 10) takes 17 shots to destroy another.
	DAMAGE_PER_POWER = 0.6,
	-- Hull repairs itself REGEN_DELAY seconds after the last hit, at
	-- REGEN_SHARE of full hull per second.
	REGEN_DELAY = 6,
	REGEN_SHARE = 0.08,
	-- PvP can't be switched off within COMBAT_LOCK seconds of dealing or
	-- taking damage, or toggled more often than TOGGLE_COOLDOWN.
	COMBAT_LOCK = 15,
	TOGGLE_COOLDOWN = 3,
	-- Seconds after losing a ship before its owner can launch again.
	RELAUNCH_DELAY = 5,
	SERVER_TICK = 0.5, -- seconds between hull repairs and PvP flag syncs

	-- Looks (every client draws the explosion).
	EXPLOSION_SIZE = 34, -- studs, the fireball at its largest
	EXPLOSION_TIME = 0.7, -- seconds the fireball and shockwave last
	DEBRIS_COUNT = 28, -- chunks flung out (halved with reduced effects)
	DEBRIS_SPEED = { 25, 75 }, -- studs per second, min and max
	DEBRIS_LIFETIME = 2.8, -- seconds before a chunk has faded
	DEBRIS_DRAG = 0.6, -- share of speed lost per second
	EMBER_SHARE = 0.3, -- share of chunks that glow and trail fire
	SHAKE_RADIUS = 300, -- studs: closer than this, your camera shakes
	SHAKE_MAX = 2.2, -- studs of shake right next to the blast
	TAG_DISTANCE = 600, -- studs: PvP tags and hull bars over ships
	HIT_MARKER_TIME = 0.25, -- seconds the hit marker shows
	-- Ships with every Roblox client, like the asteroid break; played lower
	-- for a heavier boom. Empty string = silent.
	EXPLOSION_SOUND = "rbxasset://sounds/impact_explosion_03.mp3",
	EXPLOSION_SOUND_SPEED = 0.7,
	EXPLOSION_SOUND_VOLUME = 1,
}

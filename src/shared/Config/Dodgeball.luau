--!strict
-- Zero G Dodgeball: a drop-in minigame arena, reached through the portal in
-- the ISS playground module. No queue: anyone inside the arena is playing.
--
-- The arena is a glass box far below the ISS, full of floating glowing
-- blocks for cover. Ships aren't allowed in (a ship that flies in is stowed).
-- Inside, the suit floats SPEED_MULTIPLIER x faster, and pressing Launch
-- next to any block face pushes you off it at LAUNCH_SPEED.
--
-- Every player holds an endless sun-ball: throw it (it flies straight, zero-g)
-- and a new one is ready after THROW_COOLDOWN. A ball that hits another
-- player knocks them out: they're flung back and reappear at a random spawn
-- point after OUT_TIME. The thrower scores a hit (stat "dodgeballHits").
-- Logic/ConfigCheck validates this table.

return {
	CENTER = { x = 0, y = -1000, z = 0 }, -- world position of the arena's middle
	SIZE = { x = 260, y = 160, z = 260 }, -- studs, inside the glass walls
	BLOCK_COUNT = 34, -- floating cover blocks
	BLOCK_SIZE = { 8, 22 } :: { number }, -- studs, smallest and largest side
	BLOCK_COLORS = { "#5FE3FF", "#B06BFF", "#FF6EC8", "#FFD36B", "#7CFF8A" } :: { string },
	SPAWN_COUNT = 8,
	SEED = 2026, -- the blocks are laid out the same way every server

	-- Movement inside
	SPEED_MULTIPLIER = 2, -- suit top speed and acceleration
	LAUNCH_SPEED = 95, -- studs per second off a block face
	LAUNCH_REACH = 6, -- studs: how close to a face you must be to launch
	LAUNCH_COOLDOWN = 0.5,
	LAUNCH_TIME = 0.35, -- seconds the launch overrides your own thrust

	-- The ball
	THROW_COOLDOWN = 1.6, -- seconds until your next ball is ready
	BALL_SPEED = 150, -- studs per second
	BALL_RADIUS = 2.2, -- studs; also its hit radius
	BALL_LIFETIME = 2.5, -- seconds before an unlucky ball fizzles
	OUT_TIME = 2, -- seconds a hit player is out before they reappear
	KNOCKBACK = 70, -- studs per second the hit flings you

	-- How often the server checks who is inside.
	MEMBERSHIP_TICK = 0.25,
}

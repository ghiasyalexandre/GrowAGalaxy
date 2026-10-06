--!strict
-- The Stardust leaderboard: every player's current Stardust balance, written
-- by the server (LeaderboardSystem) to an OrderedDataStore that a Roblox
-- leaderboard reads. Keys are user ids, values whole Stardust.
--
-- Leaderboard setup (Creator Hub): ordered data store STORE, scope SCOPE,
-- units UNITS.

return {
	STORE = "StardustLeaderboard",
	SCOPE = "global",
	UNITS = "Stardust",
	-- Seconds between writes for each player (only when the balance changed);
	-- a player's balance is also written when they leave.
	WRITE_INTERVAL = 60,
	-- The ISS Star Lounge board: the top BOARD_SIZE balances, read every
	-- READ_INTERVAL seconds.
	BOARD_SIZE = 10,
	READ_INTERVAL = 120,
}

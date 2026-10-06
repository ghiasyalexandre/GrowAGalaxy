--!strict
-- Planet eggs, sold for Stardust at the ISS Planet Egg station and hatched
-- at the player's hangar incubator (Config.Planets for the planets and odds).
--
--   Mystery egg   one random planet from the whole catalog, with the odds in
--                 Config.Planets (shown in full before buying). The planet is
--                 chosen on the server the moment the egg is bought and saved
--                 with it; it never changes. Price: PRICE_BASE x
--                 PRICE_GROWTH^(eggs bought so far), rounded; with
--                 PRICE_GROWTH 1 every egg costs PRICE_BASE.
--
-- Planets can't be bought directly: eggs are the only way to get them.
--
-- Eggs wait in the player's inventory until they put one in one of
-- HATCH_SLOTS incubation chambers; it hatches after its rarity's hatch time
-- (Config.Planets.RARITIES), even while they're offline.
--
-- Price review (Oct 2026): a flat 1,000 Stardust per egg. A new player's
-- first egg takes a few minutes of mining; later eggs stay cheap next to
-- star upgrades, so eggs are the steady way to fill orbits.

return {
	PRICE_BASE = 1000,
	PRICE_GROWTH = 1, -- 1: the price never rises
	-- Mystery eggs bought in one go.
	MULTI_BUY = { 1, 5, 10 } :: { number },
	HATCH_SLOTS = 5,
	MAX_UNHATCHED = 50, -- eggs a player may hold unhatched at once
	-- Seconds between rechecks of a player's paid-random-item policy when
	-- Roblox couldn't answer.
	POLICY_RETRY = 30,
	-- Hatches of this rarity or rarer are announced to the whole server and
	-- shown on the ISS Egg Lab's hatch board (last HATCH_FEED_SIZE).
	ANNOUNCE_RARITY = "Epic",
	-- Hatches of this rarity or rarer are also announced in the chat.
	CHAT_RARITY = "Legendary",
	HATCH_FEED_SIZE = 6,
}

--!strict
-- Planet eggs, sold for Stardust at the ISS Planet Egg station and hatched
-- at the player's hangar incubator (Config.Planets for the planets and odds).
--
--   Mystery egg   one random planet from the whole catalog, with the odds in
--                 Config.Planets (shown in full before buying). The planet is
--                 chosen on the server the moment the egg is bought and saved
--                 with it; it never changes. Price: PRICE_BASE x
--                 PRICE_GROWTH^(eggs bought so far), rounded.
--   Chosen planet a guaranteed, non-random egg for one specific planet type,
--                 for GUARANTEED_MULTIPLIER[rarity] x the current mystery
--                 egg price. Always available, and the only way for players
--                 whose region restricts paid random items (PolicyService).
--
-- Eggs wait in the player's inventory until they put one in one of
-- HATCH_SLOTS incubation chambers; it hatches after its rarity's hatch time
-- (Config.Planets.RARITIES), even while they're offline.
--
-- Price review (Oct 2026 economy): a new player has 100 Stardust, their first
-- star makes 1/s and a small asteroid pays ~12, so a 500 Stardust first egg
-- takes a few minutes of mining. Each egg bought raises the next by 15%: the
-- 10th costs ~1.8k, the 25th ~13k, the 50th ~470k, keeping later eggs a real
-- goal next to star upgrades.

return {
	PRICE_BASE = 500,
	PRICE_GROWTH = 1.15,
	GUARANTEED_MULTIPLIER = {
		Common = 3,
		Uncommon = 6,
		Rare = 16,
		Epic = 50,
		Legendary = 150,
		Interstellar = 400,
	} :: { [string]: number },
	-- Mystery eggs bought in one go (each at its own rising price).
	MULTI_BUY = { 1, 5, 10 } :: { number },
	HATCH_SLOTS = 5,
	MAX_UNHATCHED = 50, -- eggs a player may hold unhatched at once
	-- Seconds between rechecks of a player's paid-random-item policy when
	-- Roblox couldn't answer.
	POLICY_RETRY = 30,
	-- Hatches of this rarity or rarer are announced to the whole server and
	-- shown on the ISS Egg Lab's hatch board (last HATCH_FEED_SIZE).
	ANNOUNCE_RARITY = "Epic",
	HATCH_FEED_SIZE = 6,
}

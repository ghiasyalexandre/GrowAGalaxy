--!strict
-- Planet eggs, rolled at each player's own Egg Lab (in their station's
-- Incubator Bay) and hatched in the incubator chambers beside it
-- (Config.Planets for the planets, rarities and tiers).
--
--   Roll    pays the egg price and rolls a mystery egg onto the lab's
--           pedestal: its rarity and tier show, its planet stays hidden
--           until it hatches. Rolling again (a reroll) pays again and
--           replaces it; the egg on the pedestal is lost.
--   Keep    moves the egg on the pedestal into the player's eggs (free),
--           ready to incubate.
--
-- Price (economy v2): E = max(PRICE_BASE, PRICE_INCOME_SECONDS x H) x
-- min(PRICE_GROWTH_CAP, PRICE_GROWTH^(eggs kept)), rounded up, where H is
-- the player's best production rate so far (a high-water mark that never
-- falls, Logic/EconomyMath). PRICE_GROWTH is 1, so buying more eggs never
-- raises the price: a roll costs a minute of the best unboosted production
-- (at least PRICE_BASE), keeping pace with the galaxy.
--
-- Odds: a planet type's chance is its Config.Planets weight times the lab
-- level's rarityLuck ^ (its rarity's index, 0 = Common), out of the sum of
-- all of them; a tier's chance is TIER_WEIGHTS[tier] times tierLuck ^
-- (tier - 1), out of their sum (Logic/EggMath, shown in full in the panel).
-- So luck 1 is the plain odds and more luck shifts chance up the ladder.
--
-- Lab levels: the player pays Stardust to upgrade their lab, one level at
-- a time (LAB_LEVELS[n].cost buys level n), once their best star reaches
-- the level's minTier. Nothing is sold for Robux.
--
-- Eggs wait in the player's inventory until they put one in one of
-- HATCH_SLOTS incubation chambers; it hatches after its rarity's hatch time
-- (Config.Planets.RARITIES), even while they're offline.

export type LabLevel = {
	cost: number, -- Stardust to reach this level (0 for level 1)
	rarityLuck: number, -- at least 1, never falling level to level
	tierLuck: number, -- at least 1, never falling level to level
	minTier: number, -- the player's best star tier needed to buy this level
}

return {
	PRICE_BASE = 250, -- the price floor
	PRICE_INCOME_SECONDS = 60, -- seconds of best production (H) a roll costs
	PRICE_GROWTH = 1, -- per egg kept: 1 = keeping eggs never raises the price
	PRICE_GROWTH_CAP = 2, -- the kept-egg growth stops at this factor
	-- Tiers 1 to 7, before the lab's luck (Config.Planets.TIERS).
	-- 20%, 50%, 20%, 7%, 2%, 0.8%, 0.2%.
	TIER_WEIGHTS = { 200000, 500000, 200000, 70000, 20000, 8000, 2000 } :: { number },
	LAB_LEVELS = {
		{ cost = 0, rarityLuck = 1, tierLuck = 1, minTier = 1 },
		{ cost = 5000, rarityLuck = 1.04, tierLuck = 1.03, minTier = 4 },
		{ cost = 50000, rarityLuck = 1.08, tierLuck = 1.06, minTier = 6 },
		{ cost = 750000, rarityLuck = 1.12, tierLuck = 1.09, minTier = 8 },
		{ cost = 20000000, rarityLuck = 1.16, tierLuck = 1.12, minTier = 10 },
		{ cost = 500000000, rarityLuck = 1.2, tierLuck = 1.15, minTier = 12 },
		{ cost = 12000000000, rarityLuck = 1.24, tierLuck = 1.18, minTier = 14 },
		{ cost = 250000000000, rarityLuck = 1.28, tierLuck = 1.21, minTier = 16 },
	} :: { LabLevel },
	-- Seconds the client's roll animation takes (the server has already
	-- rolled; the result shows when it ends). Reduced motion skips most of it.
	ROLL_SECONDS = 1.2,
	HATCH_SLOTS = 5,
	-- A free tutorial egg (the cheapest Common, tier 1, salvage 0) is given
	-- this many seconds into a player's first session.
	TUTORIAL_EGG_SECONDS = 120,
	MAX_UNHATCHED = 50, -- eggs a player may hold unhatched at once
	-- Seconds between rechecks of a player's paid-random-item policy when
	-- Roblox couldn't answer.
	POLICY_RETRY = 30,
	-- Hatches of this rarity or rarer, or of ANNOUNCE_TIER or higher, are
	-- announced to the whole server and shown on the ISS hatch board (last
	-- HATCH_FEED_SIZE).
	ANNOUNCE_RARITY = "Epic",
	ANNOUNCE_TIER = 5,
	-- Hatches of this rarity or rarer, or of CHAT_TIER, also go to the chat.
	CHAT_RARITY = "Legendary",
	CHAT_TIER = 7,
	HATCH_FEED_SIZE = 6,
}

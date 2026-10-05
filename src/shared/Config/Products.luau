--!strict
-- Optional Robux products: the catalog the Store shows and the server
-- fulfils (MonetizationSystem). Everything here is optional: the whole game
-- can be played and finished with Stardust alone.
--
-- Nothing can be bought until it is configured:
--   * PURCHASES_ENABLED is the master switch (false = the Store shows every
--     offer as "Not available yet" and the server ignores purchases);
--   * each product needs its real `id` from the Creator Hub (0 = not set up)
--     and `enabled = true`.
-- ConfigCheck refuses PURCHASES_ENABLED with an enabled product whose id is
-- 0. See docs/monetization-setup.md for creating the passes and products.
--
-- Prices are never stored here: the Store asks Roblox for the current price
-- (MarketplaceService:GetProductInfoAsync), so it always matches the prompt.
--
-- Kinds:
--   GamePass          permanent; ownership is checked with Roblox on join
--   DeveloperProduct  repeatable; fulfilled once per receipt (ProcessReceipt)
--
-- Grants (exactly one per product):
--   multiplier = { source, value }  permanent reward multiplier ("mining"/"star")
--   beamPower = n                   permanent extraction-speed multiplier
--   autoCollect = true              star income moves to the wallet as it accrues
--   ship = id                       a ship (identical to the Stardust version)
--   boost = { source, seconds }     adds time to a 2x boost (Config.Products.BOOST_MULTIPLIER)
--   stardust = n                    a fixed amount, never multiplied
--   cosmetic = id                   a cosmetic (none on sale yet)

export type BoostSource = "mining" | "star"

export type Grants = {
	multiplier: { source: BoostSource, value: number }?,
	beamPower: number?,
	autoCollect: boolean?,
	ship: string?,
	boost: { source: BoostSource, seconds: number }?,
	stardust: number?,
	cosmetic: string?,
}

export type Category = "pass" | "boost" | "pack" | "ship" | "cosmetic"

export type ProductDef = {
	key: string,
	kind: "GamePass" | "DeveloperProduct",
	id: number, -- Creator Hub id; 0 = not configured, can't be bought
	enabled: boolean, -- false = hidden from the Store and never fulfilled
	category: Category,
	displayName: string,
	benefit: string, -- the exact effect, shown in the Store
	stacking: string, -- how it combines with other purchases, shown in the Store
	grants: Grants,
}

local function pass(
	key: string,
	name: string,
	benefit: string,
	stacking: string,
	grants: Grants,
	category: Category?
): ProductDef
	return {
		key = key,
		kind = "GamePass",
		id = 0,
		enabled = true,
		category = category or "pass",
		displayName = name,
		benefit = benefit,
		stacking = stacking,
		grants = grants,
	}
end

local function product(
	key: string,
	name: string,
	benefit: string,
	stacking: string,
	grants: Grants,
	category: Category
): ProductDef
	return {
		key = key,
		kind = "DeveloperProduct",
		id = 0,
		enabled = true,
		category = category,
		displayName = name,
		benefit = benefit,
		stacking = stacking,
		grants = grants,
	}
end

local BOOST_SECONDS = 15 * 60

local BY_KEY: { [string]: ProductDef } = {
	-- Permanent passes
	MiningMultiplier = pass(
		"MiningMultiplier",
		"2x Mining Stardust",
		"Doubles the Stardust you get for breaking asteroids. Star income is not affected.",
		"Stacks with a Mining Boost: 4x while both are active.",
		{ multiplier = { source = "mining", value = 2 } }
	),
	StarMultiplier = pass(
		"StarMultiplier",
		"2x Star Production",
		"Doubles the Stardust your stars make from now on. Mining and Stardust already made are not affected.",
		"Stacks with a Star Production Boost: 4x while both are active.",
		{ multiplier = { source = "star", value = 2 } }
	),
	EnhancedBeam = pass(
		"EnhancedBeam",
		"Enhanced Mining Beam",
		"25% more extraction power on every ship, so asteroids break faster. Stardust per asteroid and PvP damage are unchanged.",
		"Stacks with equipment and the Mining Lab.",
		{ beamPower = 1.25 }
	),
	AutoCollect = pass(
		"AutoCollect",
		"Automatic Stardust Collection",
		"Your stars' income goes straight into your wallet while you play, so you never need the Collect console. No offline income, no extra Stardust.",
		"Works with every production multiplier; adds nothing itself.",
		{ autoCollect = true }
	),

	-- Ships (identical to the versions bought with Stardust in the Shipyard)
	GalactixRacerShip = pass(
		"GalactixRacerShip",
		"Galactix Racer",
		"Unlocks the Galactix Racer (ship 3) at once. Same stats as the Stardust version.",
		"Permanent. Already own it? Nothing to buy.",
		{ ship = "GalactixRacer" },
		"ship"
	),
	CamoStellarShip = pass(
		"CamoStellarShip",
		"Camo Stellar",
		"Unlocks the Camo Stellar (ship 5) at once. Same stats as the Stardust version.",
		"Permanent. Already own it? Nothing to buy.",
		{ ship = "CamoStellar" },
		"ship"
	),
	InterstellarRunnerShip = pass(
		"InterstellarRunnerShip",
		"Interstellar Runner",
		"Unlocks the Interstellar Runner (ship 7) at once. Same stats as the Stardust version.",
		"Permanent. Already own it? Nothing to buy.",
		{ ship = "InterstellarRunner" },
		"ship"
	),

	-- Temporary boosts
	MiningBoost = product(
		"MiningBoost",
		"Mining Boost",
		"2x Stardust from asteroids for 15 minutes of play time.",
		"Buying again adds 15 more minutes (the boost stays 2x). The timer pauses while you're offline.",
		{ boost = { source = "mining", seconds = BOOST_SECONDS } },
		"boost"
	),
	StarBoost = product(
		"StarBoost",
		"Star Production Boost",
		"2x Stardust from your stars for 15 minutes of play time.",
		"Buying again adds 15 more minutes (the boost stays 2x). The timer pauses while you're offline.",
		{ boost = { source = "star", seconds = BOOST_SECONDS } },
		"boost"
	),

	-- Stardust packs (fixed amounts, never multiplied; need balance review)
	StardustSmall = product(
		"StardustSmall",
		"Stardust Pouch",
		"Adds exactly 2,500 Stardust to your wallet.",
		"Fixed amount: multipliers and boosts don't apply.",
		{ stardust = 2500 },
		"pack"
	),
	StardustMedium = product(
		"StardustMedium",
		"Stardust Crate",
		"Adds exactly 12,000 Stardust to your wallet.",
		"Fixed amount: multipliers and boosts don't apply.",
		{ stardust = 12000 },
		"pack"
	),
	StardustLarge = product(
		"StardustLarge",
		"Stardust Vault",
		"Adds exactly 50,000 Stardust to your wallet.",
		"Fixed amount: multipliers and boosts don't apply.",
		{ stardust = 50000 },
		"pack"
	),

	-- Kept from stage 8; the cosmetic itself isn't in the game yet.
	AuroraTrailPack = {
		key = "AuroraTrailPack",
		kind = "GamePass",
		id = 0,
		enabled = false,
		category = "cosmetic",
		displayName = "Aurora Thruster Trail",
		benefit = "A cosmetic thruster trail. No gameplay effect.",
		stacking = "Permanent.",
		grants = { cosmetic = "AuroraTrail" },
	},
}

-- Store order within each category.
local ORDER: { string } = {
	"MiningMultiplier",
	"StarMultiplier",
	"EnhancedBeam",
	"AutoCollect",
	"MiningBoost",
	"StarBoost",
	"StardustSmall",
	"StardustMedium",
	"StardustLarge",
	"GalactixRacerShip",
	"CamoStellarShip",
	"InterstellarRunnerShip",
	"AuroraTrailPack",
}

return {
	PURCHASES_ENABLED = false,
	ORDER = ORDER,
	BY_KEY = BY_KEY,
	BOOST_MULTIPLIER = 2, -- strength of a temporary boost; more time never makes it stronger
	-- Receipt ids remembered per profile for duplicate protection (newest kept).
	MAX_RECEIPTS = 100,
	-- Pass ownership checks with Roblox: tries per check and seconds between
	-- tries; after that the last confirmed result is used and checked again
	-- every RECHECK_SECONDS.
	OWNERSHIP_TRIES = 3,
	OWNERSHIP_RETRY = 2,
	RECHECK_SECONDS = 60,
	-- How long a receipt waits for the profile to save before giving up (Roblox
	-- retries later).
	SAVE_TIMEOUT = 40,
}

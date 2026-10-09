--!strict
-- Stardust economy events for Roblox analytics (AnalyticsService), logged
-- by DataSystem after each accepted change to the wallet. Wallet basis:
-- star income counts when it reaches the wallet (collected, auto-collected
-- or paid offline), never again as it accrues, and moving it from the
-- collector into the wallet is the only time it is logged.
--
-- `sku` names what the Stardust came from or went to (docs/stage-48:
-- star_online, star_offline, asteroid, swarm_bonus, calendar_day,
-- wheel_prize, raid_first_clear, achievement, code, planet_sale,
-- legacy_paid_receipt; star_buy, star_level, star_evolve, galaxy_expand,
-- egg_roll, egg_reroll, planet_level, lab_level, ship_buy,
-- equipment_level, trail_buy, hangar_buy, constellation_project).
-- Failures are ignored: analytics never blocks play.

local AnalyticsService = game:GetService("AnalyticsService")

local EconomyAnalytics = {}

local CURRENCY = "Stardust"

local TRANSACTION: { [string]: Enum.AnalyticsEconomyTransactionType } = {
	star_online = Enum.AnalyticsEconomyTransactionType.Gameplay,
	star_offline = Enum.AnalyticsEconomyTransactionType.TimedReward,
	asteroid = Enum.AnalyticsEconomyTransactionType.Gameplay,
	swarm_bonus = Enum.AnalyticsEconomyTransactionType.Gameplay,
	calendar_day = Enum.AnalyticsEconomyTransactionType.TimedReward,
	wheel_prize = Enum.AnalyticsEconomyTransactionType.TimedReward,
	raid_first_clear = Enum.AnalyticsEconomyTransactionType.Gameplay,
	achievement = Enum.AnalyticsEconomyTransactionType.Gameplay,
	code = Enum.AnalyticsEconomyTransactionType.Gameplay,
	planet_sale = Enum.AnalyticsEconomyTransactionType.Shop,
	legacy_paid_receipt = Enum.AnalyticsEconomyTransactionType.IAP,
	onboarding = Enum.AnalyticsEconomyTransactionType.Onboarding,
}

local function log(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	amount: number,
	balance: number,
	sku: string
)
	if amount <= 0 then
		return
	end
	local kind = TRANSACTION[sku] or Enum.AnalyticsEconomyTransactionType.Shop
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, CURRENCY, amount, balance, kind.Name, sku)
	end)
end

-- Stardust that entered the wallet.
function EconomyAnalytics.source(player: Player, amount: number, balance: number, sku: string)
	log(player, Enum.AnalyticsEconomyFlowType.Source, amount, balance, sku)
end

-- Stardust that left the wallet.
function EconomyAnalytics.sink(player: Player, amount: number, balance: number, sku: string)
	log(player, Enum.AnalyticsEconomyFlowType.Sink, amount, balance, sku)
end

-- A step of the first-session funnel (docs/stage-48), once per player.
function EconomyAnalytics.funnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- A progression milestone (best star tier, galaxy size, lab level, ship
-- step, constellation rank).
function EconomyAnalytics.progression(player: Player, path: string, level: number)
	pcall(function()
		AnalyticsService:LogProgressionCompleteEvent(player, path, level)
	end)
end

return EconomyAnalytics

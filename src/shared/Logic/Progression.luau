--!strict
-- Progression rules shared by server, client and tests: the tutorial step,
-- which achievements a player has just earned, and shop prices.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local Progression = {}

-- Index of the first tutorial step whose stat is still 0, or 0 when every
-- step is done.
function Progression.tutorialStep(stats: { [string]: number }): number
	for index, step in Config.Tutorial.STEPS do
		if (stats[step.stat] or 0) < 1 then
			return index
		end
	end
	return 0
end

-- Ids (in Config order) of enabled achievements whose goal the stats reach
-- and that haven't been claimed yet.
function Progression.earnedAchievements(
	stats: { [string]: number },
	records: { [string]: Types.AchievementRecord }
): { string }
	local earned: { string } = {}
	for _, id in Config.Achievements.ORDER do
		local def = Config.Achievements.BY_ID[id]
		local record = records[id]
		if
			def.enabled
			and (stats[def.stat] or 0) >= def.goal
			and not (record and record.claimed)
		then
			table.insert(earned, id)
		end
	end
	return earned
end

-- Stardust price of the next galaxy expansion, or nil at the largest size.
function Progression.expansionCost(level: number): number?
	local nextLevel = Config.Galaxy.EXPANSIONS[level + 1]
	local cost = nextLevel and nextLevel.cost
	return if cost then cost.stardust else nil
end

-- Stardust price of a ship the player can earn, or nil if it isn't on sale
-- (unknown, disabled, or the free starter).
function Progression.shipCost(shipId: string): number?
	local def = Config.Ships.BY_ID[shipId]
	if def == nil or not def.enabled or def.earn == nil then
		return nil
	end
	return def.earn.stardust
end

-- True when the ship may be bought: it's the first on the ladder or the
-- player owns the ship before it in Config.Ships.ORDER, and (when the best
-- star tier is given) their best star has reached the ship's minTier.
function Progression.shipUnlocked(
	shipId: string,
	ownedShips: { [string]: boolean },
	bestTier: number?
): boolean
	local order = Config.Ships.ORDER
	local index = table.find(order, shipId)
	if index == nil then
		return false
	end
	if bestTier and bestTier < Config.Ships.BY_ID[shipId].minTier then
		return false
	end
	return index == 1 or ownedShips[order[index - 1]] == true
end

-- The ship before this one on the ladder, or nil for the first (or unknown).
function Progression.previousShip(shipId: string): string?
	local index = table.find(Config.Ships.ORDER, shipId)
	return if index and index > 1 then Config.Ships.ORDER[index - 1] else nil
end

-- Stardust price of level `level` (1 = buying it) of an equipment item on
-- sale for ship `shipId`, or nil (not for sale, or past MAX_LEVEL): the
-- item's share of the ship's price (at least the item's own cost), doubling
-- each level (Config.Equipment). A whole number.
function Progression.equipmentCost(itemId: string, level: number?, shipId: string?): number?
	local def = Config.Equipment.BY_ID[itemId]
	local wanted = level or 1
	if def == nil or not def.enabled or wanted < 1 or wanted > Config.Equipment.MAX_LEVEL then
		return nil
	end
	local shipPrice = if shipId then Progression.shipCost(shipId) or 0 else 0
	local base = math.max(def.cost.stardust, shipPrice * def.costShare)
	return math.ceil(base * Config.Equipment.COST_GROWTH ^ (wanted - 1) - 1e-9)
end

-- An equipment modifier at a level: its bonus (multiplier - 1) grows by
-- Config.Equipment.LEVEL_BONUS.
function Progression.equipmentMultiplier(multiplier: number, level: number): number
	local index = math.clamp(math.floor(level), 1, Config.Equipment.MAX_LEVEL)
	return 1 + (multiplier - 1) * Config.Equipment.LEVEL_BONUS[index]
end

return Progression

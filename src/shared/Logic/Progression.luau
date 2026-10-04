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

-- Stardust price of an equipment item on sale, or nil.
function Progression.equipmentCost(itemId: string): number?
	local def = Config.Equipment.BY_ID[itemId]
	if def == nil or not def.enabled then
		return nil
	end
	return def.cost.stardust
end

return Progression

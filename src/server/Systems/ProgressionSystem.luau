--!strict
-- Achievements and the tutorial, both driven by profile stats.
--
-- Whenever a stat changes (and once when a profile loads), every enabled
-- achievement whose goal is reached is claimed and its reward granted once
-- (Stardust, a cosmetic, a ship), with a toast. The tutorial step shown on
-- the HUD is the first Config.Tutorial step whose stat is still 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Notify = require(script.Parent.Parent.Util.Notify)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)

local CURRENCY = Config.Economy.CURRENCY_NAME

local ProgressionSystem = {}

local function check(player: Player)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	for _, id in Progression.earnedAchievements(profile.stats, profile.achievements) do
		if not DataSystem.claimAchievement(player, id) then
			continue
		end
		local def = Config.Achievements.BY_ID[id]
		local reward = def.reward
		local parts: { string } = {}
		if reward.stardust > 0 then
			DataSystem.addStardust(player, reward.stardust)
			table.insert(parts, `+{reward.stardust} {CURRENCY}`)
		end
		if reward.cosmetic and Config.Cosmetics.BY_ID[reward.cosmetic] then
			DataSystem.grantCosmetic(player, reward.cosmetic)
			table.insert(parts, Config.Cosmetics.BY_ID[reward.cosmetic].displayName)
		end
		if reward.ship and Config.Ships.BY_ID[reward.ship] then
			DataSystem.grantShip(player, reward.ship)
			table.insert(parts, Config.Ships.BY_ID[reward.ship].displayName)
		end
		Notify.send(player, `Achievement: {def.displayName}! {table.concat(parts, ", ")}`)
	end

	if not profile.tutorial.done then
		local step = Progression.tutorialStep(profile.stats)
		if step == 0 or step ~= profile.tutorial.step then
			DataSystem.setTutorialStep(player, step)
			if step == 0 then
				Notify.send(player, "Tutorial complete. Keep growing your galaxy!")
			end
		end
	end
end

function ProgressionSystem.start()
	DataSystem.statChanged:Connect(check)
	DataSystem.profileLoaded:Connect(check)
end

return ProgressionSystem

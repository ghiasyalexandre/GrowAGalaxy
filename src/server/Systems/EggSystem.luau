--!strict
-- Each player's Egg Lab on the server (the machine beside their station's
-- Stardust Collector, Config.Eggs): rolls mystery eggs, keeps them, upgrades
-- the lab's odds.
--
-- EggRequest (RemoteFunction, client -> server):
--   "status"                  -> (ok, message, policy) the player's
--                                random-egg eligibility (EggMath.Policy)
-- (The lab's physical ROLL and KEEP buttons do the same, see wireButtons.)
--   "roll", expectedPrice?    -> (ok, message) pays the egg price and rolls
--                                a new egg onto the pedestal (replacing the
--                                one there: a reroll)
--   "keep"                    -> (ok, message) the pedestal egg joins your
--                                eggs (and starts incubating in a free
--                                chamber with auto-incubate on)
--   "upgrade", expectedCost?  -> (ok, message) the lab's next level
--
-- The planet type and tier are rolled here with the server's own Random at
-- the lab's level (EggMath) and saved on the pedestal (DataSystem.rollEgg);
-- the client is told the rarity and tier but never the planet until it
-- hatches. If the client's expected price differs from the server's,
-- nothing happens.
--
-- The lab model shows the pedestal egg to everyone near the station through
-- attributes (Rarity, Tier, RolledAt in server time, LabLevel); clients
-- draw it (EggLabController).
--
-- Paid random items: Stardust could be bought with Robux, so egg rolls are
-- offered only to players whose PolicyService policy says paid random items
-- are allowed. Until Roblox has answered (or if it fails) the policy is
-- "unknown" and rolls stay off, rechecked every POLICY_RETRY seconds.
--
-- Economy v2: the roll price comes from the player's best production H
-- (EconomyMath.eggPrice); a lab level needs the best star tier its
-- minTier names; a roll needs a free planet place (eggs reserve one); and
-- every player gets one free tutorial egg TUTORIAL_EGG_SECONDS into their
-- first session.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local StationSystem = require(script.Parent.StationSystem)

local E = Config.Eggs
local P = Config.Planets
local CURRENCY = Config.Economy.CURRENCY_NAME

local EggSystem = {}

local policies: { [Player]: string } = {}
local checking: { [Player]: boolean } = {}
local requestLimit = RateLimiter.new(6, 2)
local rng = Random.new()

local POLICY_MESSAGES: { [string]: string } = {
	allowed = "",
	restricted = "Planet eggs aren't available in your region.",
	unknown = "We couldn't check whether planet eggs are allowed for you yet, so they're off for now. Try again in a moment.",
}

-- Asks Roblox once; on failure tries again after POLICY_RETRY seconds while
-- the player is here. Yields, so it always runs in its own thread.
local function checkPolicy(player: Player)
	if checking[player] then
		return
	end
	checking[player] = true
	while
		player.Parent == Players
		and policies[player] ~= "allowed"
		and policies[player] ~= "restricted"
	do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if
			ok
			and type(info) == "table"
			and type(info.ArePaidRandomItemsRestricted) == "boolean"
		then
			policies[player] = if info.ArePaidRandomItemsRestricted then "restricted" else "allowed"
		else
			policies[player] = "unknown"
			if not ok then
				warn(`[EggSystem] Policy check failed for {player.Name}: {info}`)
			end
			task.wait(E.POLICY_RETRY)
		end
	end
	checking[player] = nil
end

local function policyOf(player: Player): EggMath.Policy
	local policy = policies[player]
	return if policy == "allowed"
		then "allowed"
		elseif policy == "restricted" then "restricted"
		else "unknown"
end

local function expectedMatches(expected: unknown, price: number): boolean
	return expected == nil or (type(expected) == "number" and expected == price)
end

local PROBLEMS: { [string]: string } = {
	NoProfile = "Your save isn't ready yet. Try again in a moment.",
	Full = `You can hold {E.MAX_UNHATCHED} unhatched eggs at once. Hatch some first.`,
	Storage = `Your planet storage ({P.MAX_PLANETS}) is full, counting eggs waiting and incubating. Sell some planets first.`,
	Poor = `You don't have enough {CURRENCY}.`,
	Empty = "Roll an egg first.",
	Top = "Your Egg Lab is already at its best level.",
}

-- Shows the player's pedestal egg and lab level on their station's lab.
local function show(player: Player, rolled: boolean?)
	local profile = DataSystem.getProfile(player)
	local station = StationSystem.getStation(player)
	local lab = if station then station.model:FindFirstChild("EggLab", true) else nil
	if profile == nil or lab == nil then
		return
	end
	local current = profile.eggLab.current
	local def = if current then P.BY_ID[current.outcome] else nil
	lab:SetAttribute("Rarity", if def then def.rarity else nil)
	lab:SetAttribute("Tier", if current then current.tier else nil)
	lab:SetAttribute("LabLevel", profile.eggLab.level)
	if rolled then
		lab:SetAttribute("RolledAt", Workspace:GetServerTimeNow())
	end
end

-- An egg's name for messages: the tier (with its number) in the tier's
-- colour and the rarity in the rarity's colour (rich text: toasts show it).
local function eggName(rarity: string, tier: number): string
	local tierDef, rarityDef = P.TIERS[tier], P.RARITIES[rarity]
	return `<font color="{tierDef.color}">Tier {tier} {tierDef.name}</font> <font color="{rarityDef.color}">{rarityDef.displayName}</font>`
end

local function roll(player: Player, expected: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, PROBLEMS.NoProfile
	end
	local policy = policyOf(player)
	if not EggMath.canBuyRandom(policy) then
		if policy == "unknown" then
			task.spawn(checkPolicy, player)
		end
		return false, POLICY_MESSAGES[policy]
	end
	local price = EconomyMath.profileEggPrice(profile)
	if not expectedMatches(expected, price) then
		return false,
			`The price changed to {Format.commas(price)} {CURRENCY}. Check it and try again.`
	end
	local level = profile.eggLab.level
	local outcome = EggMath.pickType(level, rng:NextInteger(1, EggMath.typeTotal(level)))
	local tier = EggMath.pickTier(level, rng:NextInteger(1, EggMath.tierTotal(level)))
	local ok, problem = DataSystem.rollEgg(player, outcome, tier, price)
	if not ok then
		return false, PROBLEMS[problem or "NoProfile"]
	end
	show(player, true)
	DataSystem.addStat(player, "eggRolls", 1)
	return true, `A {eggName(P.BY_ID[outcome].rarity, tier)} egg! Keep it or roll again.`
end

local function keep(player: Player): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local current = if profile then profile.eggLab.current else nil
	local id, problem = DataSystem.keepEgg(player)
	if id == nil or profile == nil or current == nil then
		return false, PROBLEMS[problem or "NoProfile"]
	end
	DataSystem.addStat(player, "eggsBought", 1)
	local started = if profile.settings.autoIncubate then DataSystem.fillChambers(player) else 0
	if started > 0 then
		DataSystem.addStat(player, "eggsIncubated", started)
	end
	show(player)
	local name = eggName(P.BY_ID[current.outcome].rarity, current.tier)
	return true,
		if started > 0
			then `Your {name} egg is incubating!`
			else `Your {name} egg is waiting for a free incubator chamber.`
end

local function upgrade(player: Player, expected: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, PROBLEMS.NoProfile
	end
	local cost = EggMath.upgradeCost(profile.eggLab.level)
	if cost == nil then
		return false, PROBLEMS.Top
	end
	local needTier = EggMath.upgradeTier(profile.eggLab.level) or 1
	if StarMath.highestTier(profile.galaxy.stars) < needTier then
		local name = Config.Stars.BY_ID[Config.Stars.ORDER[needTier]].displayName
		return false, `The next Egg Lab level needs a {name} (star tier {needTier}) in your galaxy.`
	end
	if not expectedMatches(expected, cost) then
		return false,
			`The upgrade now costs {Format.commas(cost)} {CURRENCY}. Check it and try again.`
	end
	local ok, problem = DataSystem.upgradeEggLab(player, cost)
	if not ok then
		return false, PROBLEMS[problem or "NoProfile"]
	end
	show(player)
	return true, `Egg Lab level {profile.eggLab.level}: better odds on every roll!`
end

-- The lab's physical ROLL and KEEP buttons (ClickDetectors on the
-- station's lab, DeviceBuilder.eggLab): only the lab's owner can press
-- them; the result comes back as a message.
local function wireButtons(owner: Player)
	local station = StationSystem.getStation(owner)
	local lab = if station then station.model:FindFirstChild("EggLab", true) else nil
	if lab == nil or lab:GetAttribute("GaG_ButtonsWired") then
		return
	end
	lab:SetAttribute("GaG_ButtonsWired", true)
	for name, press in
		{
			RollButton = function(player: Player)
				return roll(player, nil)
			end,
			KeepButton = keep,
		} :: { [string]: (Player) -> (boolean, string) }
	do
		local key = lab:FindFirstChild(name, true)
		local click = if key then key:FindFirstChildOfClass("ClickDetector") else nil
		if click then
			click.MouseClick:Connect(function(player)
				if player ~= owner or not requestLimit.allow(player) then
					return
				end
				local _, message = press(player)
				if message ~= "" then
					Notify.send(player, message)
				end
			end)
		end
	end
end

local function onRequest(player: Player, action: unknown, a: unknown): (boolean, string, any)
	if not requestLimit.allow(player) then
		return false, "Slow down a little.", nil
	end
	if action == "status" then
		local policy = policyOf(player)
		if policy == "unknown" then
			task.spawn(checkPolicy, player)
		end
		return true, POLICY_MESSAGES[policy], policy
	elseif action == "roll" then
		local ok, message = roll(player, a)
		return ok, message, nil
	elseif action == "keep" then
		local ok, message = keep(player)
		return ok, message, nil
	elseif action == "upgrade" then
		local ok, message = upgrade(player, a)
		return ok, message, nil
	end
	return false, "That isn't something the Egg Lab does.", nil
end

-- The player's random-egg eligibility as last checked (for other systems).
function EggSystem.policy(player: Player): EggMath.Policy
	return policyOf(player)
end

function EggSystem.start()
	Net.EggRequest.OnServerInvoke = onRequest
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPolicy, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPolicy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		policies[player] = nil
	end)
	DataSystem.profileLoaded:Connect(function(player, profile)
		show(player)
		-- The free tutorial egg, TUTORIAL_EGG_SECONDS into a first session.
		if not profile.tutorialEgg then
			task.delay(E.TUTORIAL_EGG_SECONDS, function()
				if player.Parent ~= Players then
					return
				end
				if DataSystem.grantTutorialEgg(player) then
					local started = if profile.settings.autoIncubate
						then DataSystem.fillChambers(player)
						else 0
					if started > 0 then
						-- Counts for the tutorial's "Hatch your egg" step.
						DataSystem.addStat(player, "eggsIncubated", started)
					end
					Notify.send(
						player,
						if started > 0
							then "A free planet egg is incubating in your station! Watch it hatch."
							else "A free planet egg is waiting at your station's incubator."
					)
				end
			end)
		end
	end)
	StationSystem.stationAdded:Connect(function(player)
		show(player)
		wireButtons(player)
	end)
end

return EggSystem

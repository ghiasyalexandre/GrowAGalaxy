--!strict
-- The ISS Planet Egg Lab on the server: sells planet eggs for Stardust.
--
-- EggRequest (RemoteFunction, client -> server):
--   "status"                          -> (ok, message, policy) the player's
--                                        random-egg eligibility (EggMath.Policy)
--   "buyMystery", expectedPrice?      -> (ok, message) one random egg
--   "buyChosen", typeId, expectedPrice? -> (ok, message) one egg of that type
--
-- A mystery egg's planet is rolled here with the server's own Random the
-- moment it is bought and saved with the egg (DataSystem.buyEgg); it never
-- changes and the client isn't told what it is until it hatches. Chosen
-- eggs are never random. If the client's expected price differs from the
-- server's (another purchase raised it), nothing is bought.
--
-- Paid random items: Stardust can be bought with Robux, so mystery eggs are
-- sold only to players whose PolicyService policy says paid random items are
-- allowed. Until Roblox has answered (or if it fails) the policy is
-- "unknown" and random eggs stay off, rechecked every POLICY_RETRY seconds;
-- chosen eggs are always available. There are no paid luck boosts, rerolls,
-- hatch speed-ups or trading.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local E = Config.Eggs
local P = Config.Planets
local CURRENCY = Config.Economy.CURRENCY_NAME

local EggSystem = {}

local policies: { [Player]: string } = {}
local checking: { [Player]: boolean } = {}
local requestLimit = RateLimiter.new(4, 2)
local rng = Random.new()

local POLICY_MESSAGES: { [string]: string } = {
	allowed = "",
	restricted = "Mystery eggs aren't available in your region. You can still choose a planet.",
	unknown = "We couldn't check whether mystery eggs are allowed for you yet, so they're off for now. You can still choose a planet.",
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
	Full = `You can hold {E.MAX_UNHATCHED} eggs at once. Hatch some at your hangar first.`,
	Poor = `You don't have enough {CURRENCY}.`,
}

local function buyMystery(player: Player, expected: unknown): (boolean, string)
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
	local price = EggMath.price(profile.eggsBought)
	if not expectedMatches(expected, price) then
		return false, `The price changed to {price} {CURRENCY}. Check it and try again.`
	end
	local outcome = EggMath.pick(rng:NextInteger(1, P.WEIGHT_TOTAL))
	local id, problem = DataSystem.buyEgg(player, outcome, false, price)
	if id == nil then
		return false, PROBLEMS[problem or "NoProfile"]
	end
	DataSystem.addStat(player, "eggsBought", 1)
	return true, `Mystery egg bought for {price} {CURRENCY}! Hatch it in your hangar's incubator.`
end

local function buyChosen(player: Player, typeId: unknown, expected: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	local def = if type(typeId) == "string" then P.BY_ID[typeId] else nil
	if profile == nil or def == nil then
		return false, "That isn't a planet you can choose."
	end
	local price = EggMath.guaranteedPrice(profile.eggsBought, def.id) :: number
	if not expectedMatches(expected, price) then
		return false, `The price changed to {price} {CURRENCY}. Check it and try again.`
	end
	local id, problem = DataSystem.buyEgg(player, def.id, true, price)
	if id == nil then
		return false, PROBLEMS[problem or "NoProfile"]
	end
	DataSystem.addStat(player, "eggsBought", 1)
	return true,
		`{def.displayName} egg bought for {price} {CURRENCY}! Hatch it in your hangar's incubator.`
end

local function onRequest(
	player: Player,
	action: unknown,
	a: unknown,
	b: unknown
): (boolean, string, any)
	if not requestLimit.allow(player) then
		return false, "Slow down a little.", nil
	end
	if action == "status" then
		local policy = policyOf(player)
		if policy == "unknown" then
			task.spawn(checkPolicy, player)
		end
		return true, POLICY_MESSAGES[policy], policy
	elseif action == "buyMystery" then
		local ok, message = buyMystery(player, a)
		return ok, message, nil
	elseif action == "buyChosen" then
		local ok, message = buyChosen(player, a, b)
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
end

return EggSystem

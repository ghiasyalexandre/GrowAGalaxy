--!strict
-- Hatching planet eggs in the incubator chambers of each player's hangar
-- (StationBuilder's Incubator Bay, Config.Eggs.HATCH_SLOTS chambers).
--
-- HatchRequest (RemoteFunction, client -> server):
--   "start", eggId: string, chamber: number?  -> (ok, message)
--       puts one of your waiting eggs into that chamber (or the first free
--       one). DataSystem.startHatch moves the egg and records the hatch in one
--       step; the end time comes from the planet's rarity.
--   "fill"  -> (ok, message) the oldest waiting eggs into every free chamber.
--
-- With the autoIncubate setting a chamber that frees up takes the next
-- waiting egg by itself (also while offline). Hatched planets of a rarity
-- the player auto-sells are sold on the spot (DataSystem.advanceHatches).
-- Hatches of Config.Eggs.ANNOUNCE_RARITY or rarer, or ANNOUNCE_TIER or
-- higher, are announced to the whole server and listed in the hatch feed
-- (the ISS Star Lounge board); CHAT_RARITY or CHAT_TIER also go to the chat.
--
-- Hatches are saved as unix start and end times, so they keep going while
-- the player is offline. Every second (and when a profile loads) any hatch
-- whose time is up is completed by DataSystem.completeHatch, which removes
-- the hatch and adds the planet in one step: each egg is granted exactly
-- once and its chamber frees itself. On join, eggs that finished while the
-- player was away are summed up in one message.
--
-- Each chamber part shows its state to everyone near the station (owner and
-- visitors) through attributes: Rarity, Tier, StartedAt, EndsAt while
-- hatching (never the planet), and HatchedType / HatchedTier / HatchedAt after it
-- hatches. Only the owner's client enables the chambers' prompts, and a
-- request only ever touches the requester's own profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local StationSystem = require(script.Parent.StationSystem)

local E = Config.Eggs
local P = Config.Planets
-- Seconds after joining before the offline summary, after the welcome-back
-- income message.
local SUMMARY_DELAY = 9

local HatchSystem = {}

export type FeedEntry = { name: string, typeId: string, tier: number, at: number }

-- Fires after a rare hatch joins the feed.
HatchSystem.feedChanged = Signal.new() :: Signal.Signal<()>
local feed: { FeedEntry } = {}

local requestLimit = RateLimiter.new(4, 2)
local elapsed = 0

local function chamberPart(player: Player, index: number): BasePart?
	local station = StationSystem.getStation(player)
	local incubator = if station then station.model:FindFirstChild("Incubator") else nil
	local part = if incubator then incubator:FindFirstChild(`Chamber{index}`) else nil
	return if part and part:IsA("BasePart") then part else nil
end

-- Writes every chamber's state into its part's attributes.
local function show(player: Player)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	for index = 1, E.HATCH_SLOTS do
		local part = chamberPart(player, index)
		if part then
			local hatch = profile.hatches[tostring(index)]
			local def = if hatch then P.BY_ID[hatch.outcome] else nil
			part:SetAttribute(
				"Rarity",
				if hatch then (if def then def.rarity else "Common") else nil
			)
			part:SetAttribute("StartedAt", if hatch then hatch.startedAt else nil)
			part:SetAttribute("EndsAt", if hatch then hatch.endsAt else nil)
			part:SetAttribute("Tier", if hatch then hatch.tier else nil)
		end
	end
end

-- "Radiant Legendary Phoenix Core" (tier, rarity, type).
local function planetName(def: any, tier: number): string
	return `{P.TIERS[tier].name} {P.RARITIES[def.rarity].displayName} {def.displayName}`
end

-- A rare hatch (by rarity or by tier): everyone in the server hears about
-- it, and it joins the feed.
local function announce(player: Player, typeId: string, tier: number)
	local def = P.BY_ID[typeId]
	if def == nil then
		return
	end
	local rank = P.RARITIES[def.rarity].index
	if rank < P.RARITIES[E.ANNOUNCE_RARITY].index and tier < E.ANNOUNCE_TIER then
		return
	end
	table.insert(
		feed,
		1,
		{ name = player.DisplayName, typeId = typeId, tier = tier, at = os.time() }
	)
	while #feed > E.HATCH_FEED_SIZE do
		table.remove(feed)
	end
	HatchSystem.feedChanged:Fire()
	local name = planetName(def, tier)
	if rank >= P.RARITIES[E.CHAT_RARITY].index or tier >= E.CHAT_TIER then
		Net.ChatAnnounce:FireAllClients(
			`[Planet Egg] {player.DisplayName} hatched a {name}!`,
			P.RARITIES[def.rarity].color
		)
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Notify.send(other, `{player.DisplayName} hatched a {name}!`)
		end
	end
end

-- Completes every finished hatch (DataSystem.advanceHatches) and shows the
-- newest one per chamber popping out. Returns what hatched.
local function settle(player: Player, now: number): { DataSystem.HatchResult }
	local results = DataSystem.advanceHatches(player, now)
	if #results == 0 then
		return results
	end
	local latest: { [string]: DataSystem.HatchResult } = {}
	for _, result in results do
		latest[result.chamber] = result
		announce(player, result.typeId, result.tier)
	end
	for chamber, result in latest do
		local part = chamberPart(player, tonumber(chamber) or 0)
		if part then
			part:SetAttribute("HatchedType", result.typeId)
			part:SetAttribute("HatchedTier", result.tier)
			part:SetAttribute("HatchedAt", Workspace:GetServerTimeNow())
		end
	end
	show(player)
	return results
end

local function typesOf(results: { DataSystem.HatchResult }): { string }
	local types: { string } = {}
	for _, result in results do
		table.insert(types, result.typeId)
	end
	return types
end

-- What was sold on hatching, as " (3 sold for 120 Stardust)", or "".
local function soldText(results: { DataSystem.HatchResult }): string
	local count, total, full = 0, 0, false
	for _, result in results do
		if result.sold then
			count += 1
			total += result.sold
			full = full or result.reason == "full"
		end
	end
	if count == 0 then
		return ""
	end
	return ` ({count} auto-sold for {total} {Config.Economy.CURRENCY_NAME}{if full
		then "; your planet storage is full"
		else ""})`
end

-- "Aurora World (Rare), 2x Basalt World (Common)"
local function summary(types: { string }): string
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, typeId in types do
		if counts[typeId] == nil then
			table.insert(order, typeId)
		end
		counts[typeId] = (counts[typeId] or 0) + 1
	end
	local parts: { string } = {}
	for _, typeId in order do
		local def = P.BY_ID[typeId]
		local name = if def
			then `{def.displayName} ({P.RARITIES[def.rarity].displayName})`
			else typeId
		table.insert(parts, if counts[typeId] > 1 then `{counts[typeId]}x {name}` else name)
	end
	return table.concat(parts, ", ")
end

local function start(player: Player, eggId: unknown, rawChamber: unknown): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "Your save isn't ready yet."
	end
	if type(eggId) ~= "string" or profile.eggs[eggId] == nil then
		return false, "That egg isn't in your inventory."
	end
	local chamber: number? = nil
	if rawChamber == nil then
		for index = 1, E.HATCH_SLOTS do
			if profile.hatches[tostring(index)] == nil then
				chamber = index
				break
			end
		end
		if chamber == nil then
			return false, "Every chamber is busy. Wait for an egg to hatch."
		end
	elseif type(rawChamber) == "number" and rawChamber == math.floor(rawChamber) then
		chamber = rawChamber
	else
		return false, "That isn't a chamber."
	end
	local index = chamber :: number
	if index < 1 or index > E.HATCH_SLOTS then
		return false, "That isn't a chamber."
	end
	if profile.hatches[tostring(index)] then
		return false, `Chamber {index} is busy.`
	end
	local hatch = DataSystem.startHatch(player, eggId :: string, index)
	if hatch == nil then
		return false, "That egg can't go in there."
	end
	show(player)
	DataSystem.addStat(player, "eggsIncubated", 1)
	return true,
		`Your egg is in chamber {index}. It hatches in {EggMath.durationText(
			hatch.endsAt - hatch.startedAt
		)}, even while you're away.`
end

local function onRequest(player: Player, action: unknown, a: unknown, b: unknown): (boolean, string)
	if not requestLimit.allow(player) then
		return false, "Slow down a little."
	end
	if action == "start" then
		return start(player, a, b)
	elseif action == "fill" then
		local started = DataSystem.fillChambers(player)
		show(player)
		if started == 0 then
			return false, "No free chamber, or no eggs waiting."
		end
		DataSystem.addStat(player, "eggsIncubated", started)
		return true, `{started} {if started == 1 then "egg is" else "eggs are"} incubating.`
	end
	return false, "That isn't something the incubator does."
end

function HatchSystem.start()
	Net.HatchRequest.OnServerInvoke = onRequest
	DataSystem.profileLoaded:Connect(function(player)
		local hatched = settle(player, os.time())
		show(player)
		if #hatched > 0 then
			task.delay(SUMMARY_DELAY, function()
				if player.Parent == Players then
					Notify.send(
						player,
						`While you were away, {#hatched} {if #hatched == 1 then "egg" else "eggs"} hatched: {summary(
							typesOf(hatched)
						)}{soldText(hatched)}. See them in Planets (P).`
					)
				end
			end)
		end
	end)
	StationSystem.stationAdded:Connect(show)
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 then
			return
		end
		elapsed = 0
		local now = os.time()
		for _, player in Players:GetPlayers() do
			for _, result in settle(player, now) do
				local def = P.BY_ID[result.typeId]
				if def then
					local name = planetName(def, result.tier)
					Notify.send(
						player,
						if result.sold
							then `A {name} hatched and was sold for {result.sold} {Config.Economy.CURRENCY_NAME}{if result.reason
									== "full"
								then ": your planet storage is full"
								else ""}.`
							else `A {name} hatched{if result.new
								then ": a new type for your Planet Index!"
								else "!"} Equip it from Planets (P).`
					)
				end
			end
		end
	end)
end

-- The latest rare hatches in this server, newest first.
function HatchSystem.feed(): { FeedEntry }
	return table.clone(feed)
end

return HatchSystem

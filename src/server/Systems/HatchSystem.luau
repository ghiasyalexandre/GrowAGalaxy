--!strict
-- Hatching planet eggs in the incubator chambers of each player's hangar
-- (StationBuilder's Incubator Bay, Config.Eggs.HATCH_SLOTS chambers).
--
-- HatchRequest (RemoteFunction, client -> server):
--   "start", eggId: string, chamber: number?  -> (ok, message)
--       puts one of your waiting eggs into that chamber (or the first free
--       one). DataSystem.startHatch moves the egg and records the hatch in one
--       step; the end time comes from the planet's rarity.
--
-- Hatches are saved as unix start and end times, so they keep going while
-- the player is offline. Every second (and when a profile loads) any hatch
-- whose time is up is completed by DataSystem.completeHatch, which removes
-- the hatch and adds the planet in one step: each egg is granted exactly
-- once and its chamber frees itself. On join, eggs that finished while the
-- player was away are summed up in one message.
--
-- Each chamber part shows its state to everyone near the station (owner and
-- visitors) through attributes: Rarity, StartedAt, EndsAt while hatching
-- (never the planet), and HatchedType / HatchedAt for a moment after it
-- hatches. Only the owner's client enables the chambers' prompts, and a
-- request only ever touches the requester's own profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local EggMath = require(ReplicatedStorage.Shared.Logic.EggMath)
local HatchMath = require(ReplicatedStorage.Shared.Logic.HatchMath)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local StationSystem = require(script.Parent.StationSystem)

local E = Config.Eggs
local P = Config.Planets
-- Seconds after joining before the offline summary, after the welcome-back
-- income message.
local SUMMARY_DELAY = 9

local HatchSystem = {}

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
		end
	end
end

-- Completes every finished hatch. Returns the planet types granted.
local function settle(player: Player, now: number): { string }
	local profile = DataSystem.getProfile(player)
	local granted: { string } = {}
	if profile == nil or next(profile.hatches) == nil then
		return granted
	end
	for _, chamber in HatchMath.due(profile.hatches, now) do
		local planetId, typeId = DataSystem.completeHatch(player, chamber, now)
		if planetId and typeId then
			table.insert(granted, typeId)
			local part = chamberPart(player, tonumber(chamber) or 0)
			if part then
				part:SetAttribute("HatchedType", typeId)
				part:SetAttribute("HatchedAt", Workspace:GetServerTimeNow())
			end
		end
	end
	if #granted > 0 then
		show(player)
	end
	return granted
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
							hatched
						)}. Equip {if #hatched == 1 then "it" else "them"} from Planets (P).`
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
			local hatched = settle(player, now)
			for _, typeId in hatched do
				local def = P.BY_ID[typeId]
				if def then
					Notify.send(
						player,
						`A {def.displayName} hatched ({P.RARITIES[def.rarity].displayName})! Equip it from Planets (P).`
					)
				end
			end
		end
	end)
end

return HatchSystem

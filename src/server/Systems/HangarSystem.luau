--!strict
-- Hangar upgrades on each player's station deck (Config.Hangar). For every
-- upgrade the station's "Hangar" model holds either its finished building
-- (built) or a red ground circle (on offer: its requirements are built), or
-- nothing yet. Stepping on a circle, or its Build prompt, buys it through
-- DataSystem; only the station's owner can.
--
-- Buildings are tagged "HangarStructure" (one bought just now also has
-- BuiltAt, server time, so clients animate it rising and celebrate); pads
-- are tagged "HangarPad" (clients make them pulse).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local HangarBuilder = require(script.Parent.Parent.World.HangarBuilder)
local HangarMath = require(ReplicatedStorage.Shared.Logic.HangarMath)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local StationSystem = require(script.Parent.StationSystem)

local H = Config.Hangar
local STRUCTURE_TAG = "HangarStructure"
local PAD_TAG = "HangarPad"

local HangarSystem = {}

local limit = RateLimiter.new(4, 1)
local lastTouch: { [Player]: number } = {}

local refresh: (player: Player, justBuilt: string?) -> ()

local function buy(player: Player, upgradeId: string, fromTouch: boolean)
	local profile = DataSystem.getProfile(player)
	if profile == nil or not limit.allow(player) then
		return
	end
	local cost, reason = HangarMath.canBuy(upgradeId, profile.hangar, profile.stardust)
	if cost == nil then
		-- Standing on a pad you can't afford shouldn't spam messages.
		local now = os.clock()
		if not fromTouch or now - (lastTouch[player] or 0) >= H.TOUCH_COOLDOWN * 2 then
			lastTouch[player] = now
			Notify.send(player, reason or "You can't build that yet.")
		end
		return
	end
	if not DataSystem.spendStardust(player, cost) then
		return
	end
	DataSystem.grantHangar(player, upgradeId)
	DataSystem.addStat(player, "hangarUpgrades", 1)
	local def = H.BY_ID[upgradeId]
	Notify.send(
		player,
		if def.stats
			then `{def.displayName} built: {def.effect}. Ships get it from their next launch.`
			else `{def.displayName} built: {def.effect}.`
	)
	refresh(player, upgradeId)
end

local function ownerOf(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function hookPad(player: Player, pad: Model, upgradeId: string)
	local circle = pad:FindFirstChild("Circle") :: BasePart?
	if circle == nil then
		return
	end
	circle.Touched:Connect(function(hit)
		if ownerOf(hit) ~= player then
			return
		end
		local now = os.clock()
		if now - (lastTouch[player] or 0) < H.TOUCH_COOLDOWN then
			return
		end
		lastTouch[player] = now
		buy(player, upgradeId, true)
	end)
	local prompt = circle:FindFirstChild("BuildPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Triggered:Connect(function(who)
			if who == player then
				buy(player, upgradeId, false)
			else
				Notify.send(who, "Only this hangar's owner can build here.")
			end
		end)
	end
end

-- Brings the station's Hangar model in line with the player's upgrades.
refresh = function(player: Player, justBuilt: string?)
	local station = StationSystem.getStation(player)
	local profile = DataSystem.getProfile(player)
	if station == nil or profile == nil then
		return
	end
	local folder = station.model:FindFirstChild("Hangar")
	if folder == nil then
		local made = Instance.new("Model")
		made.Name = "Hangar"
		made.Parent = station.model
		folder = made
	end
	for _, upgradeId in H.ORDER do
		local def = H.BY_ID[upgradeId]
		local wanted = if profile.hangar[upgradeId]
			then "built"
			elseif HangarMath.available(upgradeId, profile.hangar) then "pad"
			else nil
		local existing = (folder :: Instance):FindFirstChild(upgradeId)
		local state = if existing then existing:GetAttribute("State") else nil
		if state == wanted then
			continue
		end
		if existing then
			existing:Destroy()
		end
		if wanted == nil then
			continue
		end
		local floor = station.floor * CFrame.new(def.pad.x, 0, def.pad.z)
		local model = if wanted == "built"
			then HangarBuilder.structure(def, floor)
			else HangarBuilder.pad(def, floor)
		model:SetAttribute("OwnerUserId", player.UserId)
		if wanted == "built" then
			if upgradeId == justBuilt then
				model:SetAttribute("BuiltAt", Workspace:GetServerTimeNow())
			end
			CollectionService:AddTag(model, STRUCTURE_TAG)
		end
		model.Parent = folder
		if wanted == "pad" then
			CollectionService:AddTag(model, PAD_TAG)
			hookPad(player, model, upgradeId)
		end
	end
end

function HangarSystem.start()
	StationSystem.stationAdded:Connect(function(player)
		refresh(player, nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

return HangarSystem

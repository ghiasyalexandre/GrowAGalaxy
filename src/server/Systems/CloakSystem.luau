--!strict
-- The cloak: invisibility unlocked by a code (Config.Codes, a code with
-- `cloak = true`; owning it is just having redeemed that code). Players who
-- have it switch it on and off in Settings (SettingChanged "cloak", bool).
--
-- While cloaked, twice a second the player's character and piloted ship
-- are made fully transparent for everyone, their name tags and overhead
-- labels hidden, and their trail removed (TrailSystem checks the player
-- attribute Cloaked). Laser shots and engine exhaust still show. Each
-- part's own transparency is kept in an attribute and put back on uncloak.
-- The owner's client draws its own character faintly (CloakController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Notify = require(script.Parent.Parent.Util.Notify)
local ShipSystem = require(script.Parent.ShipSystem)

local ORIGINAL = "GaG_CloakTransparency"
local HIDDEN_GUI = "GaG_CloakHidden"
local TICK = 0.5

local CloakSystem = {}

local elapsed = 0
local hidden: { [Player]: { [Instance]: boolean } } = {}

-- Whether the player has redeemed a cloak code.
function CloakSystem.unlocked(player: Player): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false
	end
	for code, def in Config.Codes.BY_CODE do
		if def.cloak and profile.redeemedCodes[code] then
			return true
		end
	end
	return false
end

local function hide(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			local thing = item :: any
			if item:GetAttribute(ORIGINAL) == nil then
				item:SetAttribute(ORIGINAL, thing.Transparency)
			end
			if thing.Transparency ~= 1 then
				thing.Transparency = 1
			end
		elseif item:IsA("BillboardGui") and item.Enabled then
			item:SetAttribute(HIDDEN_GUI, true)
			item.Enabled = false
		end
	end
	local humanoid = root:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function show(root: Instance)
	for _, item in root:GetDescendants() do
		local original = item:GetAttribute(ORIGINAL)
		if type(original) == "number" and (item:IsA("BasePart") or item:IsA("Decal")) then
			(item :: any).Transparency = original
			item:SetAttribute(ORIGINAL, nil)
		elseif item:IsA("BillboardGui") and item:GetAttribute(HIDDEN_GUI) then
			item.Enabled = true
			item:SetAttribute(HIDDEN_GUI, nil)
		end
	end
	local humanoid = root:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function reconcile(player: Player)
	local cloaked = player:GetAttribute("Cloaked") == true
	local targets: { Instance } = {}
	if player.Character then
		table.insert(targets, player.Character)
	end
	local ship = ShipSystem.getPiloted(player)
	if ship then
		table.insert(targets, ship)
	end
	local now: { [Instance]: boolean } = {}
	for _, target in targets do
		if cloaked then
			hide(target)
			now[target] = true
		else
			show(target)
		end
	end
	-- Anything hidden before that isn't ours to hide now (a ship left
	-- behind, an old character) shows again.
	local before: { [Instance]: boolean } = hidden[player] or {}
	for target in before do
		if not now[target] and target.Parent then
			show(target)
		end
	end
	if cloaked then
		hidden[player] = now
	else
		hidden[player] = nil
	end
end

local function set(player: Player, on: boolean)
	if on and not CloakSystem.unlocked(player) then
		Notify.send(player, "You need the cloak code first.")
		return
	end
	player:SetAttribute("Cloaked", if on then true else nil)
	reconcile(player)
	Notify.send(
		player,
		if on then "Cloak on: nobody can see you!" else "Cloak off: you're visible again."
	)
end

-- Switches the cloak (from SettingsSystem).
function CloakSystem.request(player: Player, on: unknown)
	if type(on) == "boolean" then
		set(player, on)
	end
end

function CloakSystem.start()
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Cloaked") == true or hidden[player] then
				reconcile(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local leftover: { [Instance]: boolean } = hidden[player] or {}
		for target in leftover do
			if target.Parent then
				show(target)
			end
		end
		hidden[player] = nil
	end)
end

return CloakSystem

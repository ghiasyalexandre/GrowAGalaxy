--!strict
-- Opt-in PvP (Config.Combat). BeamSystem hands every shot here after mining:
-- a shot that hits another player's piloted ship damages its hull when both
-- players have PvP on and neither ship is in a docking area (CombatMath).
-- At 0 hull ShipSystem.destroy blows the ship up.
--
-- PvP is a saved setting (profile.settings.pvp), switched through
-- SettingChanged "pvp" (SettingsSystem routes it here). Switching off is
-- refused for COMBAT_LOCK seconds after dealing or taking damage.
--
-- Player attribute:  PvP     boolean  the player's PvP setting, for every client
-- Ship attribute:    Health  number   0 to 1, share of the ship's hull left

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatMath = require(ReplicatedStorage.Shared.Logic.CombatMath)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local FlightMath = require(ReplicatedStorage.Shared.Logic.FlightMath)
local Notify = require(script.Parent.Parent.Util.Notify)
local ShipSystem = require(script.Parent.ShipSystem)
local Types = require(ReplicatedStorage.Shared.Types)

local C = Config.Combat
local DOCK_ZONE_TAG = "DockZone"
local SAFE_ZONE_TAG = "SafeZone" -- e.g. around the ISS: no PvP inside

type Hull = { points: number, max: number, lastHit: number }

local CombatSystem = {}

local hulls: { [Model]: Hull } = {}
local lastCombat: { [Player]: number } = {}
local lastToggle: { [Player]: number } = {}
local elapsed = 0

local function pvpOf(player: Player): boolean
	local profile = DataSystem.getProfile(player)
	return profile ~= nil and profile.settings.pvp == true
end

local function inSafeZone(position: Vector3): boolean
	for _, tag in { DOCK_ZONE_TAG, SAFE_ZONE_TAG } do
		for _, zone in CollectionService:GetTagged(tag) do
			if zone:IsA("BasePart") and FlightMath.insideBox(zone.CFrame, zone.Size, position) then
				return true
			end
		end
	end
	return false
end

local function publish(model: Model, hull: Hull)
	model:SetAttribute("Health", math.floor(hull.points / hull.max * 100 + 0.5) / 100)
end

-- Takes `amount` off the hull of `victim`'s ship model `target`. Returns
-- true if that destroyed it (ShipSystem.destroy has run).
local function hit(victim: Player, target: Model, amount: number): boolean
	local _, targetInfo = ShipSystem.getPiloted(victim)
	local now = os.clock()
	local state = hulls[target]
	if state == nil then
		local max = if targetInfo then targetInfo.hull else 100
		state = { points = max, max = max, lastHit = now }
		hulls[target] = state
		target.Destroying:Once(function()
			hulls[target] = nil
		end)
	end
	state.points -= amount
	state.lastHit = now
	publish(target, state)
	if state.points <= 0 then
		hulls[target] = nil
		ShipSystem.destroy(victim)
		return true
	end
	return false
end

-- Damage from the game itself (raid bosses): no PvP rules apply. Returns
-- true if the ship was destroyed.
function CombatSystem.damageShip(victim: Player, amount: number): boolean
	local target = ShipSystem.getPiloted(victim)
	if target == nil or amount <= 0 then
		return false
	end
	return hit(victim, target, amount)
end

-- Called by BeamSystem for each shot fired (after mining has had it).
function CombatSystem.shot(player: Player, model: Model, info: Types.ShipInfo, aim: Vector3)
	local hull = model.PrimaryPart
	local muzzle = hull and hull:FindFirstChild("BeamOrigin")
	if hull == nil or muzzle == nil or not muzzle:IsA("Attachment") or not pvpOf(player) then
		return
	end
	local exclude: { Instance } = { model }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local direction = hull.CFrame:VectorToWorldSpace(aim) * info.beamRange
	local result = Workspace:Raycast(muzzle.WorldPosition, direction, params)
	if result == nil then
		return
	end
	local victim, target, piloted = ShipSystem.shipOf(result.Instance)
	if victim == nil or target == nil or target.PrimaryPart == nil then
		return
	end
	local safe = inSafeZone(hull.Position) or inSafeZone(target.PrimaryPart.Position)
	if not CombatMath.canDamage(true, pvpOf(victim), victim == player, piloted, safe) then
		return
	end

	local _, targetInfo = ShipSystem.getPiloted(victim)
	local now = os.clock()
	lastCombat[player] = now
	lastCombat[victim] = now
	if hit(victim, target, CombatMath.damage(info.beamPower)) then
		local lost = if targetInfo then targetInfo.displayName else "ship"
		DataSystem.addStat(player, "shipsDestroyed", 1)
		Notify.send(player, `You destroyed {victim.DisplayName}'s {lost}!`)
		Notify.send(
			victim,
			`{player.DisplayName} destroyed your {lost}. Press Launch Ship again in {C.RELAUNCH_DELAY}s.`
		)
	end
end

-- A rocket blast (RocketSystem): damages every other PvP ship it reaches,
-- under the same rules as a laser hit.
function CombatSystem.blast(player: Player, center: Vector3, radius: number, amount: number)
	if not pvpOf(player) then
		return
	end
	for _, victim in Players:GetPlayers() do
		local target = if victim ~= player then ShipSystem.getPiloted(victim) else nil
		local hull = target and target.PrimaryPart
		if
			target == nil
			or hull == nil
			or (hull.Position - center).Magnitude > radius + hull.Size.Magnitude / 2
		then
			continue
		end
		local safe = inSafeZone(center) or inSafeZone(hull.Position)
		if not CombatMath.canDamage(true, pvpOf(victim), false, true, safe) then
			continue
		end
		local now = os.clock()
		lastCombat[player] = now
		lastCombat[victim] = now
		if hit(victim, target, amount) then
			DataSystem.addStat(player, "shipsDestroyed", 1)
			Notify.send(player, `Your rocket destroyed {victim.DisplayName}'s ship!`)
			Notify.send(
				victim,
				`{player.DisplayName}'s rocket destroyed your ship. Press Launch Ship again in {C.RELAUNCH_DELAY}s.`
			)
		end
	end
end

-- PvP switch requests (SettingChanged "pvp").
function CombatSystem.requestPvp(player: Player, wanted: unknown)
	if type(wanted) ~= "boolean" or DataSystem.getProfile(player) == nil then
		return
	end
	local now = os.clock()
	local ok, reason = CombatMath.canToggle(
		wanted,
		now,
		lastToggle[player] or -math.huge,
		lastCombat[player] or -math.huge
	)
	if not ok then
		-- Re-send the saved value so the client's button snaps back.
		DataSystem.setSetting(player, "pvp", pvpOf(player))
		Notify.send(player, reason or "PvP can't be switched right now.")
		return
	end
	lastToggle[player] = now
	DataSystem.setSetting(player, "pvp", wanted)
	player:SetAttribute("PvP", wanted)
	Notify.send(
		player,
		if wanted
			then "PvP on: other PvP pilots can shoot your ship, and you theirs. Docking areas are safe."
			else "PvP off: your ship can't be damaged by other players."
	)
end

local function tick(dt: number)
	local now = os.clock()
	for model, state in hulls do
		local before = state.points
		state.points = CombatMath.repair(state.points, state.max, now - state.lastHit, dt)
		if state.points ~= before then
			publish(model, state)
		end
	end
	-- Profiles load asynchronously: keep every player's flag in step.
	for _, player in Players:GetPlayers() do
		local on = pvpOf(player)
		if player:GetAttribute("PvP") ~= on then
			player:SetAttribute("PvP", on)
		end
	end
end

function CombatSystem.start()
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= C.SERVER_TICK then
			tick(elapsed)
			elapsed = 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCombat[player] = nil
		lastToggle[player] = nil
	end)
end

return CombatSystem

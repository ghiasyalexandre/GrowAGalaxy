--!strict
-- Keeps each player's equipped trail (Config.Trails, profile.trail) on them:
-- behind their character while floating, and behind their ship's hull. Twice
-- a second it reconciles what's attached with what's equipped, so respawns,
-- launches and equipping all just work. The Stardust multiplier itself is
-- applied where rewards are paid (RewardMath, DataSystem, MiningSystem).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local ShipSystem = require(script.Parent.ShipSystem)

local NAME = "GaG_Trail"
local TICK = 0.5

local TrailSystem = {}

local elapsed = 0

local function sequence(colors: { string }): ColorSequence
	local keys = {}
	for index, hex in colors do
		local t = if #colors > 1 then (index - 1) / (#colors - 1) else 0
		table.insert(keys, ColorSequenceKeypoint.new(t, Color3.fromHex(hex)))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
	end
	return ColorSequence.new(keys)
end

-- Makes `part` carry trail `trailId` (or none), `scale` times its width.
local function attach(part: BasePart, trailId: string?, scale: number)
	local existing = part:FindFirstChild(NAME)
	if existing and existing:GetAttribute("TrailId") == trailId then
		return
	end
	if existing then
		existing:Destroy()
	end
	local def = if trailId then Config.Trails.BY_ID[trailId] else nil
	if def == nil then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = NAME
	holder:SetAttribute("TrailId", trailId)
	local half = def.width * scale / 2
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, half, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -half, 0)
	bottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = sequence(def.colors)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Lifetime = def.lifetime
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Parent = holder
	-- The attachments go with the trail when it's swapped.
	holder.Destroying:Connect(function()
		top:Destroy()
		bottom:Destroy()
	end)
	holder.Parent = part
end

local function reconcile(player: Player)
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	local trailId = profile.trail
	local ship = ShipSystem.getPiloted(player)
	local hull = ship and ship.PrimaryPart
	if hull then
		attach(hull, trailId, 2)
	end
	-- Piloting, the pilot is hidden inside the ship: only the ship trails.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		attach(root, if hull then nil else trailId, 1)
	end
end

function TrailSystem.start()
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			reconcile(player)
		end
	end)
end

return TrailSystem

--!strict
-- How hangar upgrades look on this client (HangarSystem builds them):
--   * red pads (tagged "HangarPad") pulse, their glow breathing in and out;
--   * a building bought moments ago (tagged "HangarStructure" with BuiltAt)
--     rises out of the deck with a bounce, a golden burst and a shockwave
--     ring; for its owner, a HANGAR UPGRADE banner.
-- Purely visual and local.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PAD_TAG = "HangarPad"
local STRUCTURE_TAG = "HangarStructure"
local RISE_TIME = 1.1
local FRESH = 4 -- seconds: a building younger than this is animated
local GOLD = Color3.fromRGB(255, 211, 107)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local HangarController = {}

local function easeOutBack(t: number): number
	local c = 1.7
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function burst(at: Vector3, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = Workspace.CurrentCamera

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = SPARKLE
	sparkles.Rate = 0
	sparkles.Speed = NumberRange.new(10, 26)
	sparkles.SpreadAngle = Vector2.new(70, 70)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Lifetime = NumberRange.new(0.8, 1.6)
	sparkles.Size = NumberSequence.new(1.4, 0)
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD)
	sparkles.LightEmission = 1
	sparkles.Acceleration = Vector3.new(0, -12, 0)
	sparkles.Parent = anchor
	sparkles:Emit(if ClientState.reducedEffects then 30 else 70)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.ForceField
	ring.Color = GOLD
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = anchor
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.3, size * 3, size * 3),
		Transparency = 1,
	}):Play()
	task.delay(2, function()
		anchor:Destroy()
	end)
end

-- Raises a just-built structure out of the deck.
local function rise(model: Model)
	local _, size = model:GetBoundingBox()
	local depth = size.Y + 1
	local parts: { [BasePart]: CFrame } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			parts[item] = item.CFrame
			item.CFrame = item.CFrame - Vector3.new(0, depth, 0)
		end
	end
	local base = model:GetPivot().Position
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / RISE_TIME, 0, 1)
		local offset = depth * (1 - easeOutBack(t))
		for part, goal in parts do
			if part.Parent then
				part.CFrame = goal - Vector3.new(0, offset, 0)
			end
		end
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	burst(base, math.max(size.X, size.Z))
end

local function onStructure(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local builtAt = instance:GetAttribute("BuiltAt")
	if type(builtAt) ~= "number" or Workspace:GetServerTimeNow() - builtAt > FRESH then
		return
	end
	rise(instance)
	if instance:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
		local id = instance:GetAttribute("UpgradeId")
		local def = if type(id) == "string" then Config.Hangar.BY_ID[id] else nil
		if def then
			ClientState.celebrate:Fire("HANGAR UPGRADE", def.displayName, def.effect, GOLD, true)
		end
	end
end

function HangarController.start()
	for _, instance in CollectionService:GetTagged(STRUCTURE_TAG) do
		onStructure(instance)
	end
	CollectionService:GetInstanceAddedSignal(STRUCTURE_TAG):Connect(onStructure)

	-- Pads breathe: their ring glows brighter and dimmer.
	RunService.RenderStepped:Connect(function()
		local wave = 0.5 + 0.5 * math.sin(os.clock() * 3)
		for _, pad in CollectionService:GetTagged(PAD_TAG) do
			local circle = pad:FindFirstChild("Circle")
			if circle and circle:IsA("BasePart") then
				circle.Transparency = 0.05 + 0.4 * wave
			end
		end
	end)
end

return HangarController

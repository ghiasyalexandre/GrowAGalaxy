--!strict
-- Space atmosphere and the central hub players spawn on.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldSystem = {}

local function setupLighting()
	workspace.Gravity = Config.GRAVITY

	Lighting.ClockTime = 0
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 70, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 140)

	local sky = Instance.new("Sky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Threshold = 0.9
	bloom.Parent = Lighting
end

local function buildHub()
	local hub = Instance.new("Model")
	hub.Name = "Hub"

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(Config.HUB_SIZE, 1, Config.HUB_SIZE)
	floor.CFrame = CFrame.new(0, -0.5, 0)
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(40, 40, 60)
	floor.Parent = hub

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Parent = hub

	hub.Parent = workspace
end

function WorldSystem.init()
	setupLighting()
	buildHub()
end

return WorldSystem

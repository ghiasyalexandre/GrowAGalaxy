--!strict
-- Builds the shared world when the server starts: zero gravity, space
-- lighting, the ISS hub and the Earth backdrop. Also clears leftovers from
-- Studio's Baseplate template (the baseplate, its spawn and its atmosphere)
-- that would break the space scene.
--
-- To use a hand-built ISS instead of the greybox, put a Model named "ISS" in
-- ServerStorage/Assets. It must contain every part listed in MARKERS, plus
-- ProximityPrompts tagged "WarpPrompt" with a WarpTarget attribute for the
-- airlocks (NavigationSystem), one tagged "LaunchPrompt" with Hangar = "ISS"
-- (ShipSystem), and the DockZone part tagged "DockZone" with OwnerUserId = 0.

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local EarthBuilder = require(script.Parent.Parent.World.EarthBuilder)
local IssBuilder = require(script.Parent.Parent.World.IssBuilder)

local WorldSystem = {}

-- Named parts the rest of the game relies on.
WorldSystem.MARKERS = {
	"ArrivalSpawn", -- SpawnLocation where players appear
	"AirlockInside", -- standing point inside the docking module
	"DockingSpawn", -- standing point on the exterior docking platform
	"Berth1", -- ship berths on the docking platform, facing the way ships leave
	"Berth2",
	"Berth3",
	"DockZone", -- assisted docking volume around the berths
}

local iss: Model? = nil

local function setupLighting()
	for _, child in Lighting:GetChildren() do
		if
			child:IsA("Sky")
			or child:IsA("Atmosphere")
			or child:IsA("BloomEffect")
			or child:IsA("SunRaysEffect")
			or child:IsA("DepthOfFieldEffect")
		then
			child:Destroy()
		end
	end

	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(120, 122, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 112, 135)
	Lighting.GlobalShadows = false
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.FogEnd = 100000

	local sky = Instance.new("Sky")
	sky.Name = "SpaceSky"
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SpaceBloom"
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 0.9
	bloom.Parent = Lighting
end

local function clearTemplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		warn(
			"[WorldSystem] Removed the template Baseplate; delete it from the place to silence this"
		)
		baseplate:Destroy()
	end
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds:Destroy()
	end
	-- Only the ISS arrival spawn may be used.
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant.Enabled = false
			warn(`[WorldSystem] Disabled stray SpawnLocation {descendant:GetFullName()}`)
		end
	end
end

local function loadIss(): Model
	local assets = ServerStorage:FindFirstChild("Assets")
	local custom = assets and assets:FindFirstChild("ISS")
	if custom and custom:IsA("Model") then
		local model = custom:Clone()
		for _, name in WorldSystem.MARKERS do
			if model:FindFirstChild(name, true) == nil then
				warn(
					`[WorldSystem] Custom ISS is missing marker "{name}"; using the greybox instead`
				)
				model:Destroy()
				return IssBuilder.build()
			end
		end
		return model
	end
	return IssBuilder.build()
end

-- A named marker part inside the ISS (see MARKERS).
function WorldSystem.getMarker(name: string): BasePart?
	local model = iss
	local marker = model and model:FindFirstChild(name, true)
	if marker and marker:IsA("BasePart") then
		return marker
	end
	return nil
end

function WorldSystem.init()
	-- Also set in default.project.json; set here too so a place file with
	-- different settings still plays in zero-g.
	Workspace.Gravity = 0
	setupLighting()
	clearTemplate()

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	local hub = loadIss()
	hub.Name = "ISS"
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	hub.Parent = world
	iss = hub

	local earth = EarthBuilder.build()
	earth.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	earth.Parent = world
end

return WorldSystem

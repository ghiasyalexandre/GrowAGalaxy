--!strict
-- Imported mesh models (tools/hangar_meshes: one FBX, imported in Studio
-- and saved under ServerStorage/Assets/Hangar) and the small effects that
-- dress them, shared by HangarBuilder (hangar upgrades) and DeviceBuilder
-- (the deck machines):
--
--   MeshAsset.source(id)                the imported model named `id`, or nil
--   MeshAsset.place(source, floor, model)  builds it into `model` on `floor`
--   light / emit / spin / pulse / skyBeam, and the SMOKE, STEAM and SPARKS
--   emitter presets

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local H = Config.Hangar
-- Parts in the station's highlight colour (StationBuilder.recolor).
local ACCENT = "GaG_Accent"

export type Emitter = {
	rate: number,
	speed: NumberRange,
	lifetime: NumberRange,
	size: NumberSequence,
	color: Color3,
	transparency: NumberSequence?,
	spread: number?,
	glow: boolean?,
	gravity: number?,
}

local MeshAsset = {}

function MeshAsset.light(part: BasePart, color: string, range: number)
	local point = Instance.new("PointLight")
	point.Color = Color3.fromHex(color)
	point.Range = range
	point.Brightness = 1.5
	point.Shadows = false
	point.Parent = part
end

local SPIN_TAG = "GaG_Spin"
local PULSE_TAG = "GaG_Pulse"

function MeshAsset.spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, SPIN_TAG)
end

function MeshAsset.pulse(part: BasePart, from: number, to: number)
	part:SetAttribute("PulseFrom", from)
	part:SetAttribute("PulseTo", to)
	CollectionService:AddTag(part, PULSE_TAG)
end

-- Smoke, steam or sparks from a part.
function MeshAsset.emit(part: BasePart, props: Emitter)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = props.rate
	emitter.Speed = props.speed
	emitter.Lifetime = props.lifetime
	emitter.Size = props.size
	emitter.Color = ColorSequence.new(props.color)
	emitter.Transparency = props.transparency or NumberSequence.new(0.4, 1)
	emitter.EmissionDirection = Enum.NormalId.Top
	if props.spread then
		emitter.SpreadAngle = Vector2.new(props.spread, props.spread)
	end
	if props.glow then
		emitter.LightEmission = 1
	end
	if props.gravity then
		emitter.Acceleration = Vector3.new(0, -props.gravity, 0)
	end
	emitter.Parent = part
end

local SMOKE: Emitter = {
	rate = 3,
	speed = NumberRange.new(2, 4),
	lifetime = NumberRange.new(2, 3),
	size = NumberSequence.new(1, 3),
	color = Color3.fromRGB(200, 190, 170),
	transparency = NumberSequence.new(0.5, 1),
}
local STEAM: Emitter = {
	rate = 8,
	speed = NumberRange.new(3, 6),
	lifetime = NumberRange.new(2, 3.5),
	size = NumberSequence.new(2, 5),
	color = Color3.fromRGB(235, 248, 255),
}
local SPARKS: Emitter = {
	rate = 25,
	speed = NumberRange.new(4, 10),
	lifetime = NumberRange.new(0.2, 0.5),
	size = NumberSequence.new(0.25, 0),
	color = Color3.fromRGB(255, 220, 140),
	transparency = NumberSequence.new(0),
	spread = 60,
	glow = true,
	gravity = 20,
}

MeshAsset.SMOKE = SMOKE
MeshAsset.STEAM = STEAM
MeshAsset.SPARKS = SPARKS

-- A beam of light from `part` straight up into the sky (the Victory Spire).
function MeshAsset.skyBeam(part: BasePart)
	local sky = Instance.new("Attachment")
	sky.Position = Vector3.new(0, 400, 0)
	sky.Parent = part
	local base = Instance.new("Attachment")
	base.Parent = part
	local ray = Instance.new("Beam")
	ray.Attachment0 = base
	ray.Attachment1 = sky
	ray.Width0 = 3
	ray.Width1 = 0.5
	ray.FaceCamera = true
	ray.LightEmission = 1
	ray.Color = ColorSequence.new(Color3.fromHex("#FFD36B"))
	ray.Transparency = NumberSequence.new(0.3, 1)
	ray.Parent = part
end

-- The imported mesh model named `id`, if it has been saved into the place.
function MeshAsset.source(id: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	if assets == nil then
		return nil
	end
	-- Every folder named Hangar (a sync glitch can leave two).
	for _, folder in assets:GetChildren() do
		if folder.Name == "Hangar" then
			local found = folder:FindFirstChild(id, true)
			if found and found:IsA("Model") then
				return found
			end
		end
	end
	return nil
end

-- A marker's name without an importer suffix ("Smoke.001" -> "Smoke").
local function bare(name: string): string
	return (string.gsub(name, "%.%d+$", ""))
end

-- Builds a building or machine from its imported mesh model into `model`, standing on
-- `floor`. The Blender export names every part Role__RRGGBB__Material (the
-- look is applied from the name, never trusting the importer's colours) and
-- adds markers: Origin (the floor point), Front (8 studs out of the front)
-- and Up (8 studs above) let it be scaled and turned however it was
-- imported; Light_<RRGGBB>_<range>, Smoke, Steam, Sparks and Beam place
-- effects. Parts named Spin_<Group>_<Part> turn together
-- (Config.Hangar.SPIN_SPEEDS); roles starting "Accent" are tagged for the
-- station's highlight colour. Returns false if the model is unusable.
local function build(source: Model, floor: CFrame, model: Model): boolean
	local copy = source:Clone()
	local markers: { [string]: BasePart } = {}
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			local name = string.match(item.Name, "^Marker_(.+)$")
			if name then
				markers[bare(name)] = item
			end
		end
	end
	local origin: BasePart?, front: BasePart?, up: BasePart? =
		markers.Origin, markers.Front, markers.Up
	if not origin or not front or not up then
		warn(`[MeshAsset] mesh {source.Name} is missing its Origin/Front/Up markers`)
		copy:Destroy()
		return false
	end
	local span = (front.CFrame.Position - origin.CFrame.Position).Magnitude
	if span < 1e-3 then
		copy:Destroy()
		return false
	end
	-- The markers' frame as imported (x right, y up, z back); each part is
	-- moved from it onto the floor, scaled so Front is 8 studs out.
	local o = origin.CFrame.Position
	local back = (o - front.CFrame.Position).Unit
	local upward = (up.CFrame.Position - o).Unit
	local current = CFrame.fromMatrix(o, upward:Cross(back), upward, back)
	local scale = 8 / span
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			local relative = current:ToObjectSpace(item.CFrame)
			item.Size *= scale
			item.CFrame = floor * CFrame.new(relative.Position * scale) * relative.Rotation
		end
	end

	local groups: { [string]: Model } = {}
	for _, item in copy:GetDescendants() do
		if not item:IsA("BasePart") then
			continue
		end
		item.Anchored = true
		item.CanTouch = false
		item.CastShadow = false
		local markerName = string.match(item.Name, "^Marker_(.+)$")
		if markerName then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.Name = "Marker_" .. bare(markerName)
			item.Parent = model
			continue
		end
		local role, color, materialName = string.match(item.Name, "^(.-)__(%x%x%x%x%x%x)__(%a+)")
		if role == nil or color == nil or materialName == nil then
			item.Parent = model
			continue
		end
		local ok, material = pcall(function()
			return (Enum.Material :: any)[materialName]
		end)
		item.Name = role
		item.Color = Color3.fromHex(color)
		if ok and material then
			item.Material = material
		end
		local glowing = materialName == "Neon"
			or materialName == "Glass"
			or materialName == "ForceField"
		item.CanCollide = not glowing and string.sub(role, 1, 5) ~= "Spin_"
		if materialName == "Glass" then
			item.Transparency = 0.35
		elseif materialName == "ForceField" then
			item.Transparency = 0.2
		end
		if string.sub(role, 1, 6) == "Accent" then
			item:SetAttribute(ACCENT, true)
			item:SetAttribute("GlowDim", H.MESH_GLOW_DIM)
		end
		local row = tonumber(string.match(role, "^Chevron(%d+)$"))
		if role == "Beam" then
			item.Transparency = 0.85
			MeshAsset.pulse(item, 0.75, 0.92)
		elseif row then
			-- Chevron rows: the further out, the fainter.
			local fade = row / 8
			item.Transparency = 0.1 + fade * 0.5
			MeshAsset.pulse(item, 0.05 + fade * 0.4, 0.6 + fade * 0.3)
		end
		local groupName = string.match(role, "^Spin_([^_]+)_")
		if groupName then
			local group = groups[groupName]
			if not group then
				local made = Instance.new("Model")
				made.Name = groupName
				made.Parent = model
				groups[groupName] = made
				group = made
			end
			item.Parent = group
		else
			item.Parent = model
		end
	end
	copy:Destroy()

	for name, group in groups do
		-- Pivot on the middle of its parts, so it turns on the spot.
		local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in group:GetChildren() do
			if part:IsA("BasePart") then
				low = low:Min(part.CFrame.Position)
				high = high:Max(part.CFrame.Position)
			end
		end
		group.WorldPivot = CFrame.new((low + high) / 2)
		MeshAsset.spin(group, H.SPIN_SPEEDS[name] or H.SPIN_SPEED_DEFAULT)
	end
	for name, part in markers do
		local hex, range = string.match(name, "^Light_(%x%x%x%x%x%x)_(%d+)$")
		if hex and range then
			MeshAsset.light(part, "#" .. hex, tonumber(range) :: number)
		elseif name == "Smoke" then
			MeshAsset.emit(part, SMOKE)
		elseif name == "Steam" then
			MeshAsset.emit(part, STEAM)
		elseif name == "Sparks" then
			MeshAsset.emit(part, SPARKS)
		elseif name == "Beam" then
			MeshAsset.skyBeam(part)
		end
	end
	return true
end

-- Builds `source` into `model` (see build). A broken model never breaks the
-- station: it warns, clears what it half-built and returns false, and the
-- caller falls back to its part-built look.
function MeshAsset.place(source: Model, floor: CFrame, model: Model): boolean
	local ok, result = pcall(build, source, floor, model)
	if ok then
		return result
	end
	warn(`[MeshAsset] could not build {source.Name}: {result}`)
	model:ClearAllChildren()
	return false
end

return MeshAsset

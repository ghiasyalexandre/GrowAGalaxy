--!strict
-- Solar weather on every star near the camera, on this client only:
--
--   Flares       now and then a loop of glowing plasma arcs off the star's
--                surface (a curved beam between two points of the
--                surface), with a bright flash at its foot and a puff of
--                sparks thrown out into space. Hotter stars flare more often.
--   Black holes  instead fire twin jets from their poles.
--
-- Reduced effects makes flares rarer and drops the sparks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local S = Config.Stars
local RANGE = 2200 -- studs from the camera
local CHECK = 0.5 -- seconds between rolls
local INTERVAL = 9 -- average seconds between flares on a tier 1 star
local LIFE = 1.8 -- seconds a flare lasts
local WHITE = Color3.new(1, 1, 1)

type Flare = {
	started: number,
	beam: Beam?,
	parts: { BasePart },
	cleanup: { Instance },
	size: number,
}

local SolarFlareController = {}

local stars: { [Model]: boolean } = {}
local flares: { Flare } = {}
local elapsed = 0
local folder: Folder? = nil

local function fx(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GaG_SolarWeather"
	made.Parent = Workspace.CurrentCamera
	folder = made
	return made
end

local function glowBall(color: Color3, at: Vector3, size: number): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.one * size
	part.CFrame = CFrame.new(at)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = fx()
	return part
end

local function randomUnit(): Vector3
	local z = math.random() * 2 - 1
	local a = math.random() * 2 * math.pi
	local r = math.sqrt(1 - z * z)
	return Vector3.new(math.cos(a) * r, z, math.sin(a) * r)
end

local function starInfo(model: Model): (BasePart?, Color3, number, boolean)
	local core = model.PrimaryPart
	local typeId = model:GetAttribute("TypeId")
	local def = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	local color = if def then Color3.fromHex(def.light) else WHITE
	return core, color, if def then def.tier else 1, typeId == "BlackHole"
end

-- A plasma loop between two nearby points of the surface.
local function flare(core: BasePart, color: Color3)
	local radius = core.Size.X / 2
	local center = core.Position
	local out = randomUnit()
	local side = out:Cross(randomUnit())
	if side.Magnitude < 1e-3 then
		return
	end
	side = side.Unit * radius * (0.35 + math.random() * 0.3)
	local footA = center + (out * radius - side * 0.5).Unit * radius
	local footB = center + (out * radius + side * 0.5).Unit * radius

	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(center)
	anchor.Parent = fx()
	-- The beam bends along each attachment's X axis: point both outwards.
	local a0 = Instance.new("Attachment")
	a0.Parent = anchor
	a0.WorldCFrame = CFrame.fromMatrix(footA, out, side.Unit)
	local a1 = Instance.new("Attachment")
	a1.Parent = anchor
	a1.WorldCFrame = CFrame.fromMatrix(footB, out, side.Unit)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	local height = radius * (0.6 + math.random() * 0.6)
	beam.CurveSize0 = height
	beam.CurveSize1 = -height
	beam.Segments = 24
	beam.Width0 = radius * 0.22
	beam.Width1 = radius * 0.22
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(1, color),
	})
	beam.Transparency = NumberSequence.new(1)
	beam.Parent = anchor

	local flash = glowBall(color:Lerp(WHITE, 0.5), (footA + footB) / 2, radius * 0.3)
	local cleanup: { Instance } = { anchor, flash }
	if not ClientState.reducedEffects then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 0
		sparks.Speed = NumberRange.new(radius * 1.5, radius * 3.5)
		sparks.SpreadAngle = Vector2.new(25, 25)
		sparks.Lifetime = NumberRange.new(0.8, 1.6)
		sparks.Size = NumberSequence.new(radius * 0.08, 0)
		sparks.Color = ColorSequence.new(WHITE, color)
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Drag = 1.5
		local emitAt = Instance.new("Attachment")
		emitAt.Parent = anchor
		emitAt.WorldCFrame = CFrame.fromMatrix((footA + footB) / 2, side.Unit, out)
		sparks.Parent = emitAt
		sparks:Emit(24)
	end
	table.insert(flares, {
		started = os.clock(),
		beam = beam,
		parts = { flash },
		cleanup = cleanup,
		size = radius * 0.3,
	})
end

-- Twin jets out of a black hole's poles.
local function jets(core: BasePart, color: Color3)
	local radius = core.Size.X / 2
	local parts: { BasePart } = {}
	local cleanup: { Instance } = {}
	local axis = core.CFrame.UpVector
	for _, sign in { -1, 1 } do
		local length = radius * 8
		local jet = Instance.new("Part")
		jet.Shape = Enum.PartType.Cylinder
		jet.Material = Enum.Material.Neon
		jet.Color = color:Lerp(WHITE, 0.3)
		jet.Size = Vector3.new(length, radius * 0.35, radius * 0.35)
		local tip = core.Position + axis * sign * (radius + length / 2)
		jet.CFrame = CFrame.lookAt(tip, tip + axis) * CFrame.Angles(0, math.pi / 2, 0)
		jet.Anchored = true
		jet.CanCollide = false
		jet.CanQuery = false
		jet.CanTouch = false
		jet.CastShadow = false
		jet.Transparency = 1
		jet.Parent = fx()
		table.insert(parts, jet)
		table.insert(cleanup, jet)
	end
	table.insert(flares, {
		started = os.clock(),
		beam = nil,
		parts = parts,
		cleanup = cleanup,
		size = 0,
	})
end

local function step(dt: number)
	local now = os.clock()
	for i = #flares, 1, -1 do
		local f = flares[i]
		local t = (now - f.started) / LIFE
		if t >= 1 then
			for _, item in f.cleanup do
				item:Destroy()
			end
			table.remove(flares, i)
			continue
		end
		-- Swells in fast, fades out slowly.
		local alpha = if t < 0.2 then t / 0.2 else 1 - (t - 0.2) / 0.8
		local beam = f.beam
		if beam then
			beam.Transparency = NumberSequence.new(1 - alpha * 0.9)
			local flash = f.parts[1]
			flash.Size = Vector3.one * f.size * (1 + t * 2)
			flash.Transparency = 1 - alpha
		else
			for _, part in f.parts do
				part.Transparency = 1 - alpha * 0.6
			end
		end
	end

	elapsed += dt
	if elapsed < CHECK then
		return
	end
	elapsed = 0
	local camera = Workspace.CurrentCamera
	local eye = camera.CFrame.Position
	for model in stars do
		if model.Parent == nil then
			stars[model] = nil
			continue
		end
		local core, color, tier, blackHole = starInfo(model)
		if core == nil or (core.Position - eye).Magnitude > RANGE then
			continue
		end
		-- Hotter stars flare more often; reduced effects, a third as often.
		local interval = INTERVAL / (1 + (tier - 1) * 0.25)
		if ClientState.reducedEffects then
			interval *= 3
		end
		if math.random() < CHECK / interval then
			if blackHole then
				jets(core, color)
			else
				flare(core, color)
			end
		end
	end
end

local function consider(item: Instance)
	if item:IsA("Model") and item:GetAttribute("StarId") ~= nil then
		stars[item] = true
	end
end

function SolarFlareController.init() end

function SolarFlareController.start()
	task.spawn(function()
		local regions = Workspace:WaitForChild("Regions")
		for _, item in regions:GetDescendants() do
			consider(item)
		end
		regions.DescendantAdded:Connect(consider)
	end)
	RunService.Heartbeat:Connect(step)
end

return SolarFlareController

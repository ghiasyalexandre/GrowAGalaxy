--!strict
-- How each planet type looks (Config.Planets). build() makes the planet's
-- body, a ball in its colour and material, and dresses it with the shapes
-- its `features` name: surface patches and bands, clouds, cracks, crystal
-- spikes, rings, floating islands and shards, gears, a glowing core, an
-- eclipse halo, a caged singularity, pulsar beams or a rift. Rarer types
-- combine more of them and add a glow (Epic), a golden aura (Legendary) or
-- star sparks (Interstellar).
--
-- Every extra part is welded to the body, so moving the anchored body moves
-- the whole planet. Rings are curved beams on attachments (ring()), which
-- the star's orbit lines use too. Particles and sparkles are left out when
-- `reduced` (the Reduced effects setting); the shapes always stay, so every
-- type is recognisable either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))

type PlanetTypeDef = PlanetsConfig.PlanetTypeDef

-- Bezier handle length for a quarter circle of radius 1.
local QUARTER = 0.5523
local GOLDEN_ANGLE = 2.39996
local WHITE = Color3.new(1, 1, 1)
local RAINBOW =
	{ Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 255, 140), Color3.fromRGB(90, 160, 255) }

local PlanetLook = {}

-- A faint circle of `radius` around `part`, tilted `tilt` degrees, drawn
-- with four curved beams between attachments on the part. Returns what it
-- made (all parented to `part`).
function PlanetLook.ring(
	part: BasePart,
	radius: number,
	tilt: number,
	color: Color3,
	width: number,
	transparency: number?
): { Instance }
	local made: { Instance } = {}
	local plane = CFrame.Angles(math.rad(tilt), 0, 0)
	local points: { Attachment } = {}
	for index = 0, 3 do
		local angle = index * math.pi / 2
		local attachment = Instance.new("Attachment")
		attachment.Name = "GaG_Orbit"
		-- Each attachment's +X axis is the tangent the beam curves along.
		attachment.CFrame = plane
			* CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			* CFrame.Angles(0, -angle - math.pi / 2, 0)
		attachment.Parent = part
		table.insert(points, attachment)
		table.insert(made, attachment)
	end
	for index = 1, 4 do
		local beam = Instance.new("Beam")
		beam.Name = "GaG_OrbitRing"
		beam.Attachment0 = points[index]
		beam.Attachment1 = points[index % 4 + 1]
		beam.CurveSize0 = radius * QUARTER
		beam.CurveSize1 = radius * QUARTER
		beam.Segments = 16
		beam.Width0 = width
		beam.Width1 = width
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(transparency or 0.6)
		beam.Parent = part
		table.insert(made, beam)
	end
	return made
end

local function material(name: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

-- Evenly spread directions over a sphere (a Fibonacci lattice), the same on
-- every client.
local function direction(index: number, count: number): Vector3
	local y = 1 - (index - 0.5) / count * 2
	local across = math.sqrt(math.max(1 - y * y, 0))
	local theta = index * GOLDEN_ANGLE
	return Vector3.new(math.cos(theta) * across, y, math.sin(theta) * across)
end

-- A frame at `dir * distance` whose X axis points along `dir` (cylinders
-- lie flat on the surface; their axis is X).
local function flat(dir: Vector3, distance: number): CFrame
	return CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, math.pi / 2, 0) + dir * distance
end

-- A frame at `dir * distance` whose Y axis points along `dir` (blocks stand
-- up off the surface).
local function upright(dir: Vector3, distance: number): CFrame
	return CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(-math.pi / 2, 0, 0) + dir * distance
end

type PieceProps = {
	name: string,
	shape: Enum.PartType?,
	size: Vector3,
	cframe: CFrame, -- relative to the body
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
}

-- An extra part welded to the body.
local function piece(body: BasePart, props: PieceProps): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Shape = props.shape or Enum.PartType.Block
	part.Size = props.size
	part.CFrame = body.CFrame * props.cframe
	part.Color = props.color
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	part.Parent = body
	return part
end

-- A thin band all the way round the planet, square to `dir`.
local function greatCircle(
	body: BasePart,
	r: number,
	dir: Vector3,
	color: Color3,
	mat: Enum.Material,
	thickness: number,
	reach: number?
)
	local diameter = r * 2 * (reach or 1.01)
	piece(body, {
		name = "Band",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(thickness, diameter, diameter),
		cframe = flat(dir, 0),
		color = color,
		material = mat,
	})
end

local function patches(body: BasePart, r: number, color: Color3, mat: Enum.Material, count: number)
	for index = 1, count do
		local size = r * (0.55 + (index % 3) * 0.12)
		piece(body, {
			name = "Patch",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(r * 0.1, size, size),
			cframe = flat(direction(index, count), r * 0.95),
			color = color,
			material = mat,
		})
	end
end

local function particles(
	body: BasePart,
	r: number,
	colors: ColorSequence,
	rate: number,
	speed: number
)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(r * speed * 0.5, r * speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Size = NumberSequence.new(r * 0.16, 0)
	emitter.Color = colors
	emitter.LightEmission = 1
	emitter.Parent = body
end

local function glow(body: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = body
end

type Dresser = (body: BasePart, def: PlanetTypeDef, r: number, reduced: boolean) -> ()

local function colors(def: PlanetTypeDef): (Color3, Color3)
	return Color3.fromHex(def.color), Color3.fromHex(def.accent)
end

local FEATURES: { [string]: Dresser } = {
	patches = function(body, def, r)
		local _, accent = colors(def)
		patches(body, r, accent, body.Material, 5)
	end,
	glowpatches = function(body, def, r)
		local _, accent = colors(def)
		patches(body, r, accent, Enum.Material.Neon, 6)
		glow(body, accent, r * 3, 0.8)
	end,
	bands = function(body, def, r)
		local _, accent = colors(def)
		for index, y in { -0.5, 0.02, 0.48 } do
			local across = math.sqrt(1 - y * y) * 2 * r + r * 0.06
			piece(body, {
				name = "Band",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(r * (0.12 + index * 0.03), across, across),
				cframe = CFrame.new(0, y * r, 0) * CFrame.Angles(0, 0, math.pi / 2),
				color = accent,
				material = body.Material,
			})
		end
	end,
	atmosphere = function(body, def, r)
		local air = piece(body, {
			name = "Atmosphere",
			shape = Enum.PartType.Ball,
			size = Vector3.one * r * 2.36,
			cframe = CFrame.identity,
			color = Color3.fromHex(def.color):Lerp(WHITE, 0.45),
			material = Enum.Material.ForceField,
		})
		air.CastShadow = false
	end,
	clouds = function(body, def, r)
		local _, accent = colors(def)
		local cloud = accent:Lerp(WHITE, 0.5)
		piece(body, {
			name = "CloudLayer",
			shape = Enum.PartType.Ball,
			size = Vector3.one * r * 2.12,
			cframe = CFrame.identity,
			color = cloud,
			transparency = 0.6,
		})
		for index = 1, 4 do
			piece(body, {
				name = "Cloud",
				shape = Enum.PartType.Ball,
				size = Vector3.new(r * 0.7, r * 0.3, r * 0.5),
				cframe = upright(direction(index, 4), r * 1.0),
				color = cloud,
				transparency = 0.25,
			})
		end
	end,
	cracks = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 3 do
			greatCircle(body, r, direction(index, 3), accent, body.Material, r * 0.06)
		end
	end,
	glowcracks = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 3 do
			greatCircle(body, r, direction(index + 1, 4), accent, Enum.Material.Neon, r * 0.07)
		end
		glow(body, accent, r * 3, 1)
	end,
	embers = function(body, def, r, reduced)
		if not reduced then
			local _, accent = colors(def)
			particles(body, r, ColorSequence.new(accent:Lerp(WHITE, 0.4), accent), 6, 0.9)
		end
	end,
	aurora = function(body, def, r)
		local _, accent = colors(def)
		for _, y in { 0.8, -0.8 } do
			local across = math.sqrt(1 - y * y) * 2 * r + r * 0.35
			piece(body, {
				name = "Aurora",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(r * 0.28, across, across),
				cframe = CFrame.new(0, y * r, 0) * CFrame.Angles(0, 0, math.pi / 2),
				color = accent,
				material = Enum.Material.Neon,
				transparency = 0.35,
			})
		end
	end,
	spikes = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 7 do
			local length = r * (0.55 + (index % 3) * 0.12)
			piece(body, {
				name = "Spike",
				size = Vector3.new(r * 0.26, length, r * 0.26),
				cframe = upright(direction(index, 7), r * 0.85 + length / 2)
					* CFrame.Angles(0, math.rad(45), 0),
				color = accent,
				material = Enum.Material.Glass,
				transparency = 0.1,
			})
		end
	end,
	ring = function(body, def, r)
		local _, accent = colors(def)
		PlanetLook.ring(body, r * 1.6, 20, accent, r * 0.45, 0.35)
	end,
	ring2 = function(body, def, r)
		local color = Color3.fromHex(def.color):Lerp(WHITE, 0.5)
		PlanetLook.ring(body, r * 1.9, -35, color, r * 0.25, 0.45)
	end,
	shards = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 5 do
			piece(body, {
				name = "Shard",
				size = Vector3.new(r * 0.32, r * 0.18, r * 0.5),
				cframe = upright(direction(index, 5), r * 1.4)
					* CFrame.Angles(index, index * 0.7, 0),
				color = accent,
				material = body.Material,
			})
		end
	end,
	islands = function(body, def, r)
		local color, accent = colors(def)
		for index = 1, 5 do
			local dir = direction(index, 5)
			piece(body, {
				name = "Island",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(r * 0.16, r * 0.62, r * 0.62),
				cframe = flat(dir, r * 1.3),
				color = color:Lerp(WHITE, 0.15),
				material = Enum.Material.Grass,
			})
			piece(body, {
				name = "IslandRock",
				shape = Enum.PartType.Ball,
				size = Vector3.one * r * 0.36,
				cframe = flat(dir, r * 1.17),
				color = accent,
				material = Enum.Material.Slate,
			})
		end
	end,
	gears = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 2 do
			local dir = direction(index * 2, 4)
			local around = flat(dir, r * 0.98)
			piece(body, {
				name = "Gear",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(r * 0.16, r * 0.95, r * 0.95),
				cframe = around,
				color = accent,
				material = Enum.Material.Metal,
			})
			for tooth = 1, 6 do
				local angle = tooth / 6 * math.pi * 2
				piece(body, {
					name = "Tooth",
					size = Vector3.new(r * 0.16, r * 0.16, r * 0.16),
					cframe = around * CFrame.Angles(angle, 0, 0) * CFrame.new(0, r * 0.52, 0),
					color = accent,
					material = Enum.Material.Metal,
				})
			end
		end
	end,
	prism = function(body, _def, r, reduced)
		for index, color in RAINBOW do
			greatCircle(body, r, direction(index, 3), color, Enum.Material.Neon, r * 0.05, 1.03)
		end
		if not reduced then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = WHITE
			sparkles.Parent = body
		end
	end,
	core = function(body, def, r)
		local _, accent = colors(def)
		body.Transparency = 0.35
		piece(body, {
			name = "Core",
			shape = Enum.PartType.Ball,
			size = Vector3.one * r * 1.1,
			cframe = CFrame.identity,
			color = accent,
			material = Enum.Material.Neon,
		})
		glow(body, accent, r * 3.5, 1.5)
	end,
	eclipse = function(body, def, r)
		local _, accent = colors(def)
		piece(body, {
			name = "Halo",
			shape = Enum.PartType.Ball,
			size = Vector3.one * r * 2.6,
			cframe = CFrame.identity,
			color = accent,
			material = Enum.Material.ForceField,
		})
		PlanetLook.ring(body, r * 1.12, 0, accent, r * 0.35, 0.1)
		glow(body, accent, r * 3, 1.2)
	end,
	singularity = function(body, def, r)
		local _, accent = colors(def)
		body.Material = Enum.Material.Neon
		body.Color = Color3.new(0, 0, 0)
		PlanetLook.ring(body, r * 1.7, 15, accent, r * 0.8, 0.2)
		PlanetLook.ring(body, r * 1.3, 15, WHITE, r * 0.25, 0.3)
		for index = 1, 3 do
			greatCircle(body, r, direction(index, 3), accent, Enum.Material.Neon, r * 0.04, 1.18)
		end
		glow(body, accent, r * 4, 1.5)
	end,
	lattice = function(body, def, r)
		local _, accent = colors(def)
		for _, turn in
			{ CFrame.identity, CFrame.Angles(0, 0, math.pi / 2), CFrame.Angles(0, math.pi / 2, 0) }
		do
			piece(body, {
				name = "Beam",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(r * 3.2, r * 0.12, r * 0.12),
				cframe = turn,
				color = accent,
				material = Enum.Material.Neon,
			})
			for _, side in { -1, 1 } do
				piece(body, {
					name = "BeamTip",
					shape = Enum.PartType.Ball,
					size = Vector3.one * r * 0.26,
					cframe = turn * CFrame.new(side * r * 1.6, 0, 0),
					color = accent:Lerp(WHITE, 0.5),
					material = Enum.Material.Neon,
				})
			end
		end
	end,
	rift = function(body, def, r)
		local _, accent = colors(def)
		for index = 1, 5 do
			local y = (index - 3) * 0.32
			local dir = Vector3.new(0, y, -math.sqrt(math.max(1 - y * y, 0)))
			piece(body, {
				name = "Rift",
				size = Vector3.new(r * 0.12, r * 0.4, r * 0.12),
				cframe = upright(dir, r * 0.98)
					* CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 35 else -35)),
				color = accent,
				material = Enum.Material.Neon,
			})
		end
		piece(body, {
			name = "RiftGlow",
			shape = Enum.PartType.Ball,
			size = Vector3.one * r * 2.25,
			cframe = CFrame.identity,
			color = accent,
			material = Enum.Material.ForceField,
		})
		glow(body, accent, r * 3, 1.2)
	end,
}

-- Extra flair by rarity (none for Common to Rare).
local function rarityFlair(body: BasePart, def: PlanetTypeDef, r: number, reduced: boolean)
	local rarity = PlanetsConfig.RARITIES[def.rarity]
	local tint = Color3.fromHex(rarity.color)
	if rarity.index >= 3 and body:FindFirstChild("Glow") == nil then
		glow(body, tint, r * 2.5, 0.6)
	end
	if reduced then
		return
	end
	if def.rarity == "Legendary" then
		particles(body, r, ColorSequence.new(Color3.fromRGB(255, 230, 140), tint), 4, 0.5)
	elseif def.rarity == "Interstellar" then
		particles(body, r, ColorSequence.new(WHITE, tint), 7, 0.7)
	end
end

-- A planet of `def` with body radius `radius`, at the origin, ready to be
-- named, parented and moved (anchored; everything else is welded to it).
function PlanetLook.build(def: PlanetTypeDef, radius: number, reduced: boolean): Part
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * radius * 2
	body.CFrame = CFrame.identity
	body.Color = Color3.fromHex(def.color)
	body.Material = material(def.material)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	for _, feature in def.features do
		local dresser = FEATURES[feature]
		if dresser then
			dresser(body, def, radius, reduced)
		end
	end
	rarityFlair(body, def, radius, reduced)
	return body
end

-- Feature names build() knows (ConfigCheck can't see client code, so the
-- smoke test compares these with the catalog).
function PlanetLook.knows(feature: string): boolean
	return FEATURES[feature] ~= nil
end

return PlanetLook

--!strict
-- The interactive machines players walk up to, each built standing on the
-- floor point `floor` with its front (the side players use) facing the
-- floor's -Z. Each returns its control part: the part with the name label
-- and the one the caller puts the prompt on. Those names are the contract
-- (RewardController and the tutorial look for them):
--
--   collector(floor, parent)      Stardust Collector. A glass collector
--                                 sphere holding a glowing Stardust core
--                                 ("StardustOrb"), fed by three intake arms
--                                 from a round base, with a control panel at
--                                 the front ("CollectConsole").
--   galaxyControl(floor, parent)  Galaxy Control. A holo-table projecting a
--                                 spinning galaxy (a disc, a golden core and
--                                 orbiting stars) above its top, with a
--                                 front panel ("GalaxyConsole").
--   eggDispenser(floor, parent)   Planet Egg dispenser. A machine with an egg
--                                 turning in a glass dome, a row of rarity
--                                 lights, a chute and a front panel
--                                 ("EggConsole").
--
-- Spinning pieces are tagged "GaG_Spin" (SpinController turns them on each
-- client). Orbit rings are curved beams, so they cost no parts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local COLORS = Config.World.COLORS
local STARDUST = "#FFD36B"
local HOLO = "#B06BFF"
local EGG_PINK = "#FF6EC8"
local RARITY_LIGHTS = { "#B8C2CC", "#5CFF8A", "#3FA9F5", "#B06BFF", "#FFB020", "#FF4FD8" }

local DeviceBuilder = {}

local function spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, "GaG_Spin")
end

-- An upright cylinder `height` tall, standing on `at` (its bottom).
local function column(
	name: string,
	diameter: number,
	height: number,
	at: CFrame,
	color: string,
	material: Enum.Material,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = at * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material,
		parent = parent,
	})
end

local function ball(
	name: string,
	size: number,
	at: CFrame,
	color: string,
	material: Enum.Material,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Ball,
		size = Vector3.one * size,
		cframe = at,
		color = color,
		material = material,
		collide = false,
		parent = parent,
	})
end

local function light(part: BasePart, color: string, range: number, brightness: number)
	local made = Instance.new("PointLight")
	made.Color = Color3.fromHex(color)
	made.Range = range
	made.Brightness = brightness
	made.Shadows = false
	made.Parent = part
end

-- A glowing ring of curved beams around `part`, `radius` studs out, in the
-- part's XZ plane tilted `tilt` degrees.
local function beamRing(part: BasePart, radius: number, tilt: number, color: string, width: number)
	local points: { Attachment } = {}
	for corner = 0, 3 do
		local angle = corner * math.pi / 2
		local attachment = Instance.new("Attachment")
		attachment.CFrame = CFrame.Angles(math.rad(tilt), 0, 0)
			* CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			* CFrame.Angles(0, -angle - math.pi / 2, 0)
		attachment.Parent = part
		table.insert(points, attachment)
	end
	for corner = 1, 4 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = points[corner]
		beam.Attachment1 = points[corner % 4 + 1]
		beam.CurveSize0 = radius * 0.5523
		beam.CurveSize1 = radius * 0.5523
		beam.Segments = 16
		beam.Width0 = width
		beam.Width1 = width
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(Color3.fromHex(color))
		beam.Transparency = NumberSequence.new(0.3)
		beam.Parent = part
	end
end

-- A slanted control panel at the front, `y` above the floor and `z` in front
-- of the centre, carrying the label.
local function panel(
	name: string,
	title: string,
	at: CFrame,
	width: number,
	accent: string,
	parent: Instance
): Part
	local made = Build.part({
		name = name,
		size = Vector3.new(width, 1.6, 0.5),
		cframe = at * CFrame.Angles(math.rad(-25), 0, 0),
		color = COLORS.console,
		material = Enum.Material.Metal,
		parent = parent,
	})
	Build.label(made, title, { Enum.NormalId.Front }, accent)
	Build.part({
		name = "PanelTrim",
		size = Vector3.new(width + 0.2, 0.15, 0.6),
		cframe = made.CFrame * CFrame.new(0, 0.85, 0),
		color = accent,
		material = Enum.Material.Neon,
		collide = false,
		parent = made,
	})
	return made
end

function DeviceBuilder.collector(floor: CFrame, parent: Instance): Part
	local model = Build.model("StardustCollector", parent)
	column("Base", 5.4, 0.6, floor, COLORS.hullAlt, Enum.Material.DiamondPlate, model)
	column(
		"Stem",
		1.4,
		3.4,
		floor * CFrame.new(0, 0.6, 0),
		COLORS.console,
		Enum.Material.Metal,
		model
	)
	-- The collector: a glass sphere with the Stardust core inside.
	local sphere = ball(
		"CollectorGlass",
		3.6,
		floor * CFrame.new(0, 5.6, 0),
		COLORS.glass,
		Enum.Material.Glass,
		model
	)
	sphere.Transparency = 0.55
	local core =
		ball("StardustOrb", 1.8, floor * CFrame.new(0, 5.6, 0), STARDUST, Enum.Material.Neon, model)
	light(core, STARDUST, 14, 1.6)
	beamRing(core, 2.4, 20, STARDUST, 0.25)
	-- Three intake arms rising from the base's rim to the sphere.
	for index = 0, 2 do
		local angle = index * 2 * math.pi / 3 + math.pi / 6
		local rim = Vector3.new(math.cos(angle) * 2.4, 0.6, math.sin(angle) * 2.4)
		local top = Vector3.new(math.cos(angle) * 1.4, 5, math.sin(angle) * 1.4)
		local from = (floor * CFrame.new(rim)).Position
		local to = (floor * CFrame.new(top)).Position
		Build.part({
			name = "IntakeArm",
			size = Vector3.new(0.35, 0.35, (to - from).Magnitude),
			cframe = CFrame.lookAt((from + to) / 2, to),
			color = STARDUST,
			material = Enum.Material.Neon,
			collide = false,
			parent = model,
		})
	end
	column(
		"Cap",
		1.6,
		0.5,
		floor * CFrame.new(0, 7.3, 0),
		COLORS.console,
		Enum.Material.Metal,
		model
	)
	return panel(
		"CollectConsole",
		"Collect\nStardust from your stars",
		floor * CFrame.new(0, 1.6, -2.4),
		3.2,
		STARDUST,
		model
	)
end

function DeviceBuilder.galaxyControl(floor: CFrame, parent: Instance): Part
	local model = Build.model("GalaxyControl", parent)
	column("Base", 4.4, 0.5, floor, COLORS.hullAlt, Enum.Material.DiamondPlate, model)
	column(
		"Stem",
		1.2,
		2.6,
		floor * CFrame.new(0, 0.5, 0),
		COLORS.console,
		Enum.Material.Metal,
		model
	)
	column(
		"TableTop",
		5.2,
		0.4,
		floor * CFrame.new(0, 3.1, 0),
		COLORS.console,
		Enum.Material.Metal,
		model
	)
	local projector = column(
		"Projector",
		4.6,
		0.12,
		floor * CFrame.new(0, 3.5, 0),
		HOLO,
		Enum.Material.Neon,
		model
	)
	projector.Transparency = 0.4
	projector.CanCollide = false
	-- The hologram: a galaxy disc, a golden core and three stars, turning.
	local holo = Build.model("GalaxyHolo", model)
	local centre = floor * CFrame.new(0, 5.1, 0)
	local disc = Build.part({
		name = "GalaxyDisc",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.08, 3.8, 3.8),
		cframe = centre * CFrame.Angles(math.rad(12), 0, math.pi / 2),
		color = HOLO,
		material = Enum.Material.Neon,
		transparency = 0.6,
		collide = false,
		parent = holo,
	})
	disc.CanQuery = false
	local core = ball("GalaxyCore", 0.7, centre, STARDUST, Enum.Material.Neon, holo)
	holo.PrimaryPart = core
	light(core, HOLO, 12, 1.2)
	beamRing(core, 1.3, 12, "#5FE3FF", 0.06)
	beamRing(core, 1.8, 12, HOLO, 0.06)
	for index, color in { "#5FE3FF", "#FF6EC8", "#FFFFFF" } do
		local angle = index * 2.1
		local radius = 0.9 + index * 0.4
		ball(
			"HoloStar",
			0.32,
			centre * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
			color,
			Enum.Material.Neon,
			holo
		)
	end
	spin(holo, 0.6)
	return panel(
		"GalaxyConsole",
		"Galaxy Control\nYour solar systems",
		floor * CFrame.new(0, 2.4, -2.8),
		3,
		HOLO,
		model
	)
end

function DeviceBuilder.eggDispenser(floor: CFrame, parent: Instance): Part
	local model = Build.model("EggDispenser", parent)
	Build.part({
		name = "Plinth",
		size = Vector3.new(4, 0.8, 3.2),
		cframe = floor * CFrame.new(0, 0.4, 0),
		color = COLORS.hullAlt,
		material = Enum.Material.DiamondPlate,
		parent = model,
	})
	local body = Build.part({
		name = "EggConsole",
		size = Vector3.new(3.4, 3.4, 2.6),
		cframe = floor * CFrame.new(0, 2.5, 0),
		color = "#FFF4FB",
		material = Enum.Material.SmoothPlastic,
		parent = model,
	})
	Build.label(body, "Planet Eggs\nOdds inside", { Enum.NormalId.Front }, EGG_PINK)
	-- The chute an egg would drop from, and a glowing coin slot.
	Build.part({
		name = "Chute",
		size = Vector3.new(1.6, 0.9, 0.5),
		cframe = floor * CFrame.new(0, 1.3, -1.4),
		color = "#2A2440",
		material = Enum.Material.Metal,
		parent = model,
	})
	Build.part({
		name = "Slot",
		size = Vector3.new(0.9, 0.18, 0.2),
		cframe = floor * CFrame.new(1.1, 3.6, -1.35),
		color = STARDUST,
		material = Enum.Material.Neon,
		collide = false,
		parent = model,
	})
	-- Rarity lights along the top edge, Common to Interstellar.
	for index, color in RARITY_LIGHTS do
		local x = -1.375 + (index - 1) * 0.55
		ball(
			"RarityLight",
			0.38,
			floor * CFrame.new(x, 4.05, -1.25),
			color,
			Enum.Material.Neon,
			model
		)
	end
	-- The dome with an egg turning inside.
	local dome =
		ball("Dome", 3, floor * CFrame.new(0, 5.5, 0), COLORS.glass, Enum.Material.Glass, model)
	dome.Transparency = 0.6
	local egg = ball(
		"DisplayEgg",
		1.6,
		floor * CFrame.new(0, 5.5, 0),
		EGG_PINK,
		Enum.Material.SmoothPlastic,
		model
	)
	egg.Reflectance = 0.25
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.35, 1)
	mesh.Parent = egg
	light(egg, EGG_PINK, 12, 1)
	spin(egg, 1)
	return body
end

return DeviceBuilder

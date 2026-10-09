--!strict
-- The interactive machines players walk up to, each built standing on the
-- floor point `floor` with its front (the side players use) facing the
-- floor's -Z. Each returns its control part: the part with the name label
-- and the one the caller puts the prompt on. Those names are the contract
-- (RewardController and the tutorial look for them):
--
--   collector(floor, parent)      Stardust Collector, with a control panel
--                                 at the front ("CollectConsole") and a
--                                 glowing Stardust core ("StardustOrb").
--   galaxyControl(floor, parent)  Galaxy Control: a holo-table with a front
--                                 panel ("GalaxyConsole").
--   eggLab(floor, parent)         A player's Planet Egg Lab: the console
--                                 ("EggConsole") with physical ROLL and KEEP
--                                 buttons (ClickDetectors), rarity lights,
--                                 fluid tanks, and a glass dome where clients
--                                 draw the rolled egg (at "EggSpot").
--
-- The collector and Galaxy Control use their Blender mesh models
-- (tools/hangar_meshes, MeshAsset) once imported, with attribute Mesh = true:
-- the collector then gets a glass tank whose Stardust fill ("StardustFill")
-- and floating core rise, drain and pulse on each client
-- (Controllers/MachineController), and Galaxy Control's hologram is drawn
-- by each client (it shows the owner's own stars). Until the mesh is
-- imported they keep their part-built look.
--
-- Spinning pieces are tagged "GaG_Spin" (SpinController turns them on each
-- client). Orbit rings are curved beams, so they cost no parts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local MeshAsset = require(script.Parent.MeshAsset)

local COLORS = Config.World.COLORS
local STARDUST = "#FFD36B"
local HOLO = "#B06BFF"
local EGG_PINK = "#FF6EC8"
local RARITY_LIGHTS = { "#B8C2CC", "#5CFF8A", "#3FA9F5", "#B06BFF", "#FFB020", "#FF4FD8" }

local DeviceBuilder = {}

-- The collector mesh's glass tank, inside, in floor space (studs):
-- tools/hangar_meshes/models/StardustCollector.py.
DeviceBuilder.COLLECTOR_TANK = { radius = 1.45, bottom = 1.75, top = 5.65 }
-- Galaxy Control's hologram centre above the floor (mesh version).
DeviceBuilder.HOLO_HEIGHT = 5.15

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

-- The mesh collector: the imported model, plus the tank's contents (built
-- here so each client can raise, drain and pulse them).
local function meshCollector(source: Model, floor: CFrame, model: Model): boolean
	if not MeshAsset.place(source, floor, model) then
		return false
	end
	local tank = DeviceBuilder.COLLECTOR_TANK
	local fill = Build.part({
		name = "StardustFill",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, tank.radius * 2, tank.radius * 2),
		cframe = floor * CFrame.new(0, tank.bottom + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = STARDUST,
		material = Enum.Material.Neon,
		transparency = 0.25,
		collide = false,
		parent = model,
	})
	fill.CanQuery = false
	local core = ball(
		"StardustOrb",
		1.1,
		floor * CFrame.new(0, tank.bottom + 1.2, 0),
		STARDUST,
		Enum.Material.Neon,
		model
	)
	core.CanCollide = false
	light(core, STARDUST, 12, 1.2)
	model:SetAttribute("Mesh", true)
	model:SetAttribute("TankBottom", tank.bottom)
	model:SetAttribute("TankTop", tank.top)
	return true
end

function DeviceBuilder.collector(floor: CFrame, parent: Instance): Part
	local model = Build.model("StardustCollector", parent)
	local source = MeshAsset.source("StardustCollector")
	if source and meshCollector(source, floor, model) then
		return panel(
			"CollectConsole",
			"Collect\nStardust from your stars",
			floor * CFrame.new(0, 1.6, -2.4),
			3.2,
			STARDUST,
			model
		)
	end
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
	local source = MeshAsset.source("GalaxyControl")
	if source and MeshAsset.place(source, floor, model) then
		-- The hologram is drawn by each client (MachineController).
		model:SetAttribute("Mesh", true)
		model:SetAttribute("HoloHeight", DeviceBuilder.HOLO_HEIGHT)
		return panel(
			"GalaxyConsole",
			"Galaxy Control\nYour solar systems",
			floor * CFrame.new(0, 2.4, -2.8),
			3,
			HOLO,
			model
		)
	end
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

-- A big push button on the lab's control deck: a neon key on a dark collar,
-- its word on top, and a ClickDetector the server listens to (EggSystem).
local function pushButton(
	name: string,
	word: string,
	color: string,
	at: CFrame,
	parent: Instance
): Part
	Build.part({
		name = `{name}Collar`,
		size = Vector3.new(1.8, 0.3, 1.2),
		cframe = at,
		color = "#1A1E2A",
		material = Enum.Material.Metal,
		parent = parent,
	})
	local key = Build.part({
		name = name,
		size = Vector3.new(1.5, 0.35, 0.9),
		cframe = at * CFrame.new(0, 0.3, 0),
		color = color,
		material = Enum.Material.Neon,
		parent = parent,
	})
	-- The word lies on a thin plate on the key's top, its Front face turned
	-- up and its top edge towards the lab's back (+Z), so it reads upright
	-- from the front where the player stands. (A Top-face SurfaceGui lays
	-- its text along the part's own axes and showed it sideways.)
	local plate = Build.part({
		name = `{name}Label`,
		size = Vector3.new(1.5, 0.9, 0.02),
		cframe = at * CFrame.new(0, 0.49, 0) * CFrame.Angles(math.rad(90), 0, 0),
		transparency = 1,
		collide = false,
		parent = parent,
	})
	plate.CanQuery = false
	plate.CanTouch = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = word
	label.Parent = gui
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 14
	click.Parent = key
	light(key, color, 5, 0.6)
	return key
end

-- The Planet Egg Lab: a round base with a glowing ring, a white console
-- (labelled "Planet Egg Lab") with a sloped control deck carrying the
-- ROLL and KEEP buttons (ClickDetectors, EggSystem), a row of rarity
-- lights, two glass tanks of glowing egg fluid on its sides, and on top a
-- pedestal under a glass dome held by three arms, with a spinning emitter
-- above it. Each client draws the rolled egg at "EggSpot"
-- (EggLabController) from the model's attributes (EggSystem).
function DeviceBuilder.eggLab(floor: CFrame, parent: Instance): Part
	local model = Build.model("EggLab", parent)
	local source = MeshAsset.source("EggLab")
	if source and MeshAsset.place(source, floor, model) then
		-- The mesh (tools/hangar_meshes/models/EggLab.py) is everything you
		-- see, lettering included; only the working parts are built here:
		-- an invisible box for the prompt, the ROLL and KEEP keys on its
		-- control deck, and the spot where clients draw the egg.
		model:SetAttribute("Mesh", true)
		local box = Build.part({
			name = "EggConsole",
			size = Vector3.new(4.4, 3.6, 3.2),
			cframe = floor * CFrame.new(0, 2.4, 0.3),
			transparency = 1,
			collide = false,
			parent = model,
		})
		box.CanQuery = true
		local meshDeck = floor * CFrame.new(0, 2.6, -1.85) * CFrame.Angles(math.rad(-35), 0, 0)
		pushButton("RollButton", "ROLL", EGG_PINK, meshDeck * CFrame.new(-1.05, 0.2, 0), model)
		pushButton("KeepButton", "KEEP", "#5CFF8A", meshDeck * CFrame.new(1.05, 0.2, 0), model)
		local meshSpot = Build.part({
			name = "EggSpot",
			size = Vector3.one * 0.2,
			cframe = floor * CFrame.new(0, 6.4, 0.3),
			transparency = 1,
			collide = false,
			parent = model,
		})
		meshSpot.CanQuery = false
		return box
	end
	column("Base", 6.4, 0.6, floor, "#2A2F3E", Enum.Material.Metal, model)
	local ring = column("BaseRing", 6.9, 0.12, floor, EGG_PINK, Enum.Material.Neon, model)
	ring.CanCollide = false
	local body = Build.part({
		name = "EggConsole",
		size = Vector3.new(4.4, 3.6, 3.2),
		cframe = floor * CFrame.new(0, 2.4, 0.3),
		color = "#FFF4FB",
		material = Enum.Material.SmoothPlastic,
		parent = model,
	})
	Build.label(body, "Planet Egg Lab", { Enum.NormalId.Front }, EGG_PINK)
	for _, side in { -1, 1 } do
		Build.part({
			name = "BodyStrip",
			size = Vector3.new(0.15, 3.2, 3.3),
			cframe = floor * CFrame.new(side * 2.25, 2.4, 0.3),
			color = EGG_PINK,
			material = Enum.Material.Neon,
			collide = false,
			parent = model,
		})
	end
	-- The sloped control deck at the front, with the two buttons.
	local deck = floor * CFrame.new(0, 2.6, -1.85) * CFrame.Angles(math.rad(-35), 0, 0)
	Build.part({
		name = "ControlDeck",
		size = Vector3.new(4.4, 0.4, 1.8),
		cframe = deck,
		color = COLORS.console,
		material = Enum.Material.Metal,
		parent = model,
	})
	pushButton("RollButton", "ROLL", EGG_PINK, deck * CFrame.new(-1.05, 0.2, 0), model)
	pushButton("KeepButton", "KEEP", "#5CFF8A", deck * CFrame.new(1.05, 0.2, 0), model)
	-- Rarity lights along the top front edge, Common to Interstellar.
	for index, color in RARITY_LIGHTS do
		local x = -1.6 + (index - 1) * 0.64
		ball(
			"RarityLight",
			0.42,
			floor * CFrame.new(x, 4.3, -1.25),
			color,
			Enum.Material.Neon,
			model
		)
	end
	-- Glass tanks of glowing egg fluid on both sides, with lit caps.
	for _, side in { -1, 1 } do
		local tankAt = floor * CFrame.new(side * 3.0, 0.6, 0.8)
		local tank = column("Tank", 1.2, 4.4, tankAt, COLORS.glass, Enum.Material.Glass, model)
		tank.Transparency = 0.55
		local fluid = column(
			"TankFluid",
			0.7,
			3.6,
			tankAt * CFrame.new(0, 0.3, 0),
			if side < 0 then EGG_PINK else HOLO,
			Enum.Material.Neon,
			model
		)
		fluid.CanCollide = false
		local cap = column(
			"TankCap",
			1.4,
			0.4,
			tankAt * CFrame.new(0, 4.4, 0),
			"#2A2F3E",
			Enum.Material.Metal,
			model
		)
		light(cap, if side < 0 then EGG_PINK else HOLO, 8, 0.5)
	end
	-- The pedestal, dome, collar and the three arms holding the dome.
	local pedestal = column(
		"Pedestal",
		1.6,
		1,
		floor * CFrame.new(0, 4.2, 0.3),
		"#2A2440",
		Enum.Material.Metal,
		model
	)
	light(pedestal, EGG_PINK, 10, 0.8)
	local collar = column(
		"DomeCollar",
		4.8,
		0.25,
		floor * CFrame.new(0, 4.2, 0.3),
		EGG_PINK,
		Enum.Material.Neon,
		model
	)
	collar.CanCollide = false
	local dome =
		ball("Dome", 4.4, floor * CFrame.new(0, 6.4, 0.3), COLORS.glass, Enum.Material.Glass, model)
	dome.Transparency = 0.72
	dome.CanQuery = false
	for index = 0, 2 do
		local angle = index / 3 * 2 * math.pi + math.pi / 2
		local at = floor
			* CFrame.new(math.cos(angle) * 2.3, 6.4, 0.3 + math.sin(angle) * 2.3)
			* CFrame.Angles(0, -angle, 0)
		Build.part({
			name = "DomeArm",
			size = Vector3.new(0.3, 4.6, 0.5),
			cframe = at,
			color = "#C9CED9",
			material = Enum.Material.Metal,
			collide = false,
			parent = model,
		})
	end
	local emitter =
		ball("Emitter", 0.8, floor * CFrame.new(0, 9.1, 0.3), EGG_PINK, Enum.Material.Neon, model)
	beamRing(emitter, 1.1, 0, EGG_PINK, 0.12)
	spin(emitter, 1.5)
	local spot = Build.part({
		name = "EggSpot",
		size = Vector3.one * 0.2,
		cframe = floor * CFrame.new(0, 6.4, 0.3),
		transparency = 1,
		collide = false,
		parent = model,
	})
	spot.CanQuery = false
	return body
end

return DeviceBuilder

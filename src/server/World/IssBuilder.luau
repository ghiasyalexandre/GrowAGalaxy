--!strict
-- The International Space Station hub, built from parts at the world origin.
--
-- Exterior: a line of roomy cylindrical modules with window bands down both
-- sides, a long truss crossing above them, four solar-array assemblies, two
-- radiators, a glass observation cupola at the -X end and, past the airlock
-- at the +X end, the raid platform: a wide deck where RaidSystem stands the
-- Saturn V beacon (at the "RaidBeacon" marker) and its difficulty pads.
-- No ships dock at the ISS: ships launch from each player's own station.
--
-- Interior, one module per area: Observation Cupola, Arrival (spawn),
-- Star Lounge (galaxy hologram, couches), Planet Egg Lab (a giant egg on a
-- pedestal; its console opens the egg panel, EggSystem), Navigation (route to your
-- station), the Zero G Dodgeball portal (to the arena, DodgeballSystem; floating
-- hoops), Ship Showroom (ship models turning on pads) and the Raid Airlock.
-- Gravity is off, so players float; floors give them something to push on.
--
-- Boards (parts tagged "GaG_IssBoard", attribute Board, a SurfaceGui with
-- Title and Body labels): the Arrival directory (fixed text), the Star
-- Lounge's Stardust leaderboard and the Egg Lab's rare-hatch feed (filled
-- in by IssBoardSystem). The Star Lounge also has the Daily Wheel kiosk
-- (prompt attribute OpenPanel = "Wheel"), and the Egg Lab an "EggGallery"
-- marker that clients circle with one planet of each rarity.
--
-- Parts tagged "GaG_Spin" (with a SpinSpeed attribute, radians per second)
-- are turned by every client (SpinController). The parts named in
-- WorldSystem.MARKERS are the contract with the rest of the game.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShipModel = require(ReplicatedStorage.Shared.Util.ShipModel)
local Build = require(script.Parent.Build)
local DeviceBuilder = require(script.Parent.DeviceBuilder)

local COLORS = Config.World.COLORS

local TUBE_RADIUS = 16
local TUBE_SIDES = 12
local FLOOR_Y = -9
local FLOOR_WIDTH = 28
local TRUSS_Y = 30
local TRUSS_LENGTH = 340
local SPIN_TAG = "GaG_Spin"
-- The main hull's white panels glare in the sun: they're 20% darker.
local HULL_DIM = 0.2
local SAFE_ZONE_TAG = "SafeZone"
local PLATFORM_SIZE = 260 -- the raid platform, square
local BALL_COLORS = { "#FF5AA0", "#5FE3FF", "#FFD36B", "#8CFF6B", "#B06BFF", "#FF8A3D" }

type ModuleDef = {
	id: string,
	label: string,
	length: number,
	glass: boolean?,
	trim: string, -- floor strip and light tint
}

-- From the -X end to the +X end. The Navigation module is centred on the origin.
local MODULES: { ModuleDef } = {
	{ id = "Cupola", label = "Observation Cupola", length = 30, glass = true, trim = "#9FD8FF" },
	{ id = "Arrival", label = "Arrival", length = 44, trim = "#4FC3F7" },
	{ id = "Lounge", label = "Star Lounge", length = 40, trim = "#B06BFF" },
	{ id = "EggLab", label = "Planet Egg Lab", length = 36, trim = "#FF6EC8" },
	{ id = "Navigation", label = "Navigation", length = 32, trim = "#4FC3F7" },
	{ id = "Playground", label = "Zero G Dodgeball", length = 52, trim = "#FFB020" },
	{ id = "Showroom", label = "Ship Showroom", length = 48, trim = "#FFD36B" },
	{ id = "RaidAirlock", label = "Raid Airlock", length = 32, trim = "#FF4A4A" },
}

type Span = { from: number, to: number, center: number }

local function layout(): { [string]: Span }
	local offset = 0
	for _, def in MODULES do
		if def.id == "Navigation" then
			offset += def.length / 2
			break
		end
		offset += def.length
	end
	local spans: { [string]: Span } = {}
	local x = -offset
	for _, def in MODULES do
		spans[def.id] = { from = x, to = x + def.length, center = x + def.length / 2 }
		x += def.length
	end
	return spans
end

local function spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, SPIN_TAG)
end

local function neon(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: string,
	parent: Instance
): Part
	return Build.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
end

local function lamp(part: BasePart, color: string, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(color)
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- A hollow polygonal tube along X, open at both ends. Its two side panels
-- are windows; the cupola is glass underneath too.
local function dim(color: string): string
	return Color3.fromHex(color):Lerp(Color3.new(), HULL_DIM):ToHex()
end

local function tube(parent: Instance, span: Span, color: string, glassBottom: boolean)
	local width = 2 * (TUBE_RADIUS + 1) * math.tan(math.pi / TUBE_SIDES) + 0.2
	for i = 0, TUBE_SIDES - 1 do
		local angle = i / TUBE_SIDES * 2 * math.pi
		local window = math.abs(math.sin(angle)) > 0.95
		local glass = window or (glassBottom and math.cos(angle) < -0.4)
		Build.part({
			name = if glass then "Window" else "Hull",
			size = Vector3.new(span.to - span.from, 1, width),
			cframe = CFrame.new(span.center, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, TUBE_RADIUS + 0.5, 0),
			color = if glass then COLORS.glass else dim(color),
			material = if glass then Enum.Material.Glass else Enum.Material.SmoothPlastic,
			transparency = if glass then 0.5 else 0,
			parent = parent,
		})
	end
end

local function endCap(parent: Instance, x: number, glass: boolean)
	Build.part({
		name = "EndCap",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1, 2 * TUBE_RADIUS + 3, 2 * TUBE_RADIUS + 3),
		cframe = CFrame.new(x, 0, 0),
		color = if glass then COLORS.glass else dim(COLORS.hullAlt),
		material = if glass then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		transparency = if glass then 0.45 else 0,
		parent = parent,
	})
end

local function interior(parent: Instance, def: ModuleDef, span: Span)
	local length = span.to - span.from
	Build.part({
		name = "Floor",
		size = Vector3.new(length, 1, FLOOR_WIDTH),
		cframe = CFrame.new(span.center, FLOOR_Y - 0.5, 0),
		color = if def.glass then COLORS.glass else COLORS.deck,
		material = if def.glass then Enum.Material.Glass else Enum.Material.DiamondPlate,
		transparency = if def.glass then 0.35 else 0,
		parent = parent,
	})
	-- Glowing strips along both edges of the floor in the module's colour.
	for _, z in { -FLOOR_WIDTH / 2 + 1, FLOOR_WIDTH / 2 - 1 } do
		neon(
			"FloorStrip",
			Vector3.new(length - 2, 0.15, 0.5),
			CFrame.new(span.center, FLOOR_Y + 0.08, z),
			def.trim,
			parent
		)
	end
	-- Two ceiling light panels.
	for _, x in { span.center - length / 4, span.center + length / 4 } do
		local panel = neon(
			"Light",
			Vector3.new(6, 0.4, 3),
			CFrame.new(x, TUBE_RADIUS - 1.5, 0),
			"#F2F8FF",
			parent
		)
		lamp(panel, "#E8F2FF", 34, 0.6)
	end
	-- Hanging area sign, readable from both directions along the walkway.
	Build.sign({
		name = "AreaSign",
		text = def.label,
		size = Vector3.new(0.4, 3.4, 15),
		cframe = CFrame.new(span.from + 2.5, 8, 0),
		faces = { Enum.NormalId.Left, Enum.NormalId.Right },
		parent = parent,
		textColor = def.trim,
	})
end

-- Floor point against the -Z wall of a module, facing the walkway.
local function wallSpot(x: number): CFrame
	return CFrame.new(x, FLOOR_Y, -10) * CFrame.Angles(0, math.pi, 0)
end

-- A ring of glowing segments (a hoop) facing along X.
local function hoop(parent: Instance, center: Vector3, radius: number, color: string)
	local model = Build.model("Hoop", parent)
	local segments = 14
	local length = 2 * radius * math.tan(math.pi / segments) + 0.3
	for i = 0, segments - 1 do
		local angle = i / segments * 2 * math.pi
		neon(
			"Segment",
			Vector3.new(0.8, 0.8, length),
			CFrame.new(center) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, radius, 0),
			color,
			model
		)
	end
end

local BOARD_TAG = "GaG_IssBoard"

-- A wall board with a title and a body text, readable on `face`.
local function board(
	name: string,
	kind: string,
	size: Vector3,
	cframe: CFrame,
	face: Enum.NormalId,
	title: string,
	body: string,
	accent: string,
	parent: Instance
): Part
	local part = Build.part({
		name = name,
		size = size,
		cframe = cframe,
		color = "#141A2E",
		material = Enum.Material.SmoothPlastic,
		parent = parent,
	})
	part:SetAttribute("Board", kind)
	CollectionService:AddTag(part, BOARD_TAG)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	pad.PaddingRight = UDim.new(0, 24)
	pad.PaddingTop = UDim.new(0, 16)
	pad.Parent = gui
	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.new(1, 0, 0, 56)
	heading.Font = Enum.Font.GothamBlack
	heading.TextScaled = true
	heading.TextColor3 = Color3.fromHex(accent)
	heading.Text = title
	heading.Parent = gui
	local text = Instance.new("TextLabel")
	text.Name = "Body"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(0, 66)
	text.Size = UDim2.new(1, 0, 1, -86)
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 30
	text.TextWrapped = true
	text.RichText = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextColor3 = Color3.fromRGB(225, 232, 255)
	text.Text = body
	text.Parent = gui
	local edge = neon(
		`{name}Edge`,
		Vector3.new(size.X + 0.4, 0.3, 0.3),
		cframe * CFrame.new(0, -size.Y / 2, 0),
		accent,
		parent
	)
	edge.CanQuery = false
	return part
end

local function lounge(parent: Instance, span: Span)
	-- The galaxy hologram over a round table.
	Build.part({
		name = "HoloTable",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3, 9, 9),
		cframe = CFrame.new(span.center, FLOOR_Y + 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hullAlt,
		material = Enum.Material.Metal,
		parent = parent,
	})
	local holo = Build.model("Hologram", parent)
	local disc = neon(
		"GalaxyDisc",
		Vector3.new(0.2, 8, 8),
		CFrame.new(span.center, FLOOR_Y + 6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#B06BFF",
		holo
	)
	disc.Transparency = 0.55
	local core = neon(
		"GalaxyCore",
		Vector3.one * 1.6,
		CFrame.new(span.center, FLOOR_Y + 6, 0),
		"#FFE6A3",
		holo
	)
	core.Shape = Enum.PartType.Ball
	lamp(core, "#B06BFF", 20, 0.9)
	for i = 1, 6 do
		local angle = i / 6 * 2 * math.pi
		local star = neon(
			"HoloStar",
			Vector3.one * 0.5,
			CFrame.new(span.center + math.cos(angle) * 3, FLOOR_Y + 6.2, math.sin(angle) * 3),
			"#5FE3FF",
			holo
		)
		star.Shape = Enum.PartType.Ball
	end
	holo.PrimaryPart = core
	spin(holo, 0.5)
	-- The Stardust leaderboard on the wall (IssBoardSystem fills it in).
	board(
		"StardustBoard",
		"Stardust",
		Vector3.new(20, 9, 0.4),
		CFrame.new(span.center, 3, 13.6),
		Enum.NormalId.Front,
		"Top Stardust",
		"Loading...",
		"#FFD36B",
		parent
	)
	-- The Daily Wheel kiosk: opens the wheel panel (WheelController).
	local kiosk =
		Build.console("WheelKiosk", "Daily Wheel\nOne spin a day", wallSpot(span.center), parent)
	local wheelTop = neon(
		"KioskWheel",
		Vector3.new(0.4, 3, 3),
		kiosk.CFrame * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, math.pi / 2, 0),
		"#FFB020",
		parent
	)
	wheelTop.Shape = Enum.PartType.Cylinder
	spin(wheelTop, 0.8)
	local kioskPrompt =
		Build.prompt(kiosk, { action = "Spin the Daily Wheel", object = "Daily Wheel" })
	kioskPrompt:SetAttribute("OpenPanel", "Wheel")
	kioskPrompt.MaxActivationDistance = 12
	-- Couches along both walls.
	for _, z in { -10.5, 10.5 } do
		for _, x in { span.center - 11, span.center + 11 } do
			Build.part({
				name = "Couch",
				size = Vector3.new(10, 2, 4),
				cframe = CFrame.new(x, FLOOR_Y + 1, z),
				color = "#3B2A6B",
				material = Enum.Material.Fabric,
				parent = parent,
			})
			Build.part({
				name = "CouchBack",
				size = Vector3.new(10, 3, 1),
				cframe = CFrame.new(x, FLOOR_Y + 3, z + (if z < 0 then -1.5 else 1.5)),
				color = "#3B2A6B",
				material = Enum.Material.Fabric,
				parent = parent,
			})
		end
	end
end

-- The Planet Egg Lab: a giant pearly egg turning on a pedestal inside
-- rarity-coloured rings, small eggs on shelves, and the console that opens
-- the egg panel (TycoonAction "Eggs", EggShopController).
local RARITY_GLOWS = { "#B8C2CC", "#5CFF8A", "#3FA9F5", "#B06BFF", "#FFB020", "#FF4FD8" }

local function egg(
	name: string,
	size: number,
	cframe: CFrame,
	color: string,
	parent: Instance
): Part
	local part = Build.part({
		name = name,
		shape = Enum.PartType.Ball,
		size = Vector3.one * size,
		cframe = cframe,
		color = color,
		material = Enum.Material.Glass,
		collide = false,
		parent = parent,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.35, 1)
	mesh.Parent = part
	return part
end

local function eggLab(parent: Instance, span: Span)
	Build.part({
		name = "EggPedestal",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2, 10, 10),
		cframe = CFrame.new(span.center, FLOOR_Y + 1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hullAlt,
		material = Enum.Material.Metal,
		parent = parent,
	})
	local display = Build.model("EggDisplay", parent)
	local big = egg("GiantEgg", 6, CFrame.new(span.center, FLOOR_Y + 7, 0), "#FFF4FB", display)
	big.Material = Enum.Material.SmoothPlastic
	big.Reflectance = 0.3
	lamp(big, "#FF6EC8", 24, 0.9)
	-- Rarity-coloured rings around it: curved beams, so they cost no parts.
	for index, color in RARITY_GLOWS do
		local radius = 5 + index * 0.35
		local tilt = CFrame.Angles(math.rad(index * 30), math.rad(index * 17), 0)
		local points: { Attachment } = {}
		for corner = 0, 3 do
			local angle = corner * math.pi / 2
			local attachment = Instance.new("Attachment")
			attachment.CFrame = tilt
				* CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				* CFrame.Angles(0, -angle - math.pi / 2, 0)
			attachment.Parent = big
			table.insert(points, attachment)
		end
		for corner = 1, 4 do
			local beam = Instance.new("Beam")
			beam.Attachment0 = points[corner]
			beam.Attachment1 = points[corner % 4 + 1]
			beam.CurveSize0 = radius * 0.5523
			beam.CurveSize1 = radius * 0.5523
			beam.Segments = 16
			beam.Width0 = 0.3
			beam.Width1 = 0.3
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.Color = ColorSequence.new(Color3.fromHex(color))
			beam.Transparency = NumberSequence.new(0.2)
			beam.Parent = big
		end
	end
	display.PrimaryPart = big
	spin(display, 0.35)
	-- Clients circle the egg with one planet of each rarity (IssGalleryController).
	local gallery = Build.marker("EggGallery", CFrame.new(span.center, FLOOR_Y + 7, 0), parent)
	CollectionService:AddTag(gallery, "GaG_EggGallery")
	-- The latest rare hatches in this server (IssBoardSystem fills it in).
	board(
		"HatchFeedBoard",
		"HatchFeed",
		Vector3.new(18, 9, 0.4),
		CFrame.new(span.center - 4, 3, -13.6),
		Enum.NormalId.Back,
		"Rare hatches",
		"No rare planets hatched in this server yet. Will yours be the first?",
		"#FF6EC8",
		parent
	)
	-- Shelves of small eggs along both walls, one per rarity.
	for side, z in { -11, 11 } do
		Build.part({
			name = "EggShelf",
			size = Vector3.new(19, 1, 3),
			cframe = CFrame.new(span.center - 4, FLOOR_Y + 4, z),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = parent,
		})
		for index, color in RARITY_GLOWS do
			local x = span.center - 12 + (index - 1) * 3.2
			local small = egg("ShelfEgg", 1.6, CFrame.new(x, FLOOR_Y + 5.6, z), color, parent)
			small.Material = if side == 1 then Enum.Material.Neon else Enum.Material.Glass
		end
	end
	-- The egg dispenser the panel opens from (DeviceBuilder).
	local console = DeviceBuilder.eggDispenser(wallSpot(span.center + 9), parent)
	local prompt = Build.prompt(
		console,
		{ action = "Open Planet Egg Lab", object = "Planet Eggs", tycoon = "Eggs" }
	)
	prompt.MaxActivationDistance = 14
	Build.sign({
		name = "EggLabSign",
		text = "Planet Egg Lab\nEvery planet comes from an egg. Odds and hatch times at the console.",
		size = Vector3.new(22, 6, 0.4),
		cframe = CFrame.new(span.center, 2, 13.5),
		faces = { Enum.NormalId.Front },
		parent = parent,
		textColor = "#FF6EC8",
	})
end

local function playground(parent: Instance, span: Span)
	-- The Zero G Dodgeball portal: a big glowing ring across the module with
	-- a shimmering sun-coloured field inside; its prompt sends you to the
	-- arena (DodgeballSystem). Small hoops float around it for show.
	local center = Vector3.new(span.center, FLOOR_Y + 9, 0)
	hoop(parent, center, 8, "#FFB020")
	hoop(parent, center, 9.2, "#FF6A3D")
	local field = Build.part({
		name = "PortalField",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.4, 15.5, 15.5),
		cframe = CFrame.new(center),
		color = "#FFB020",
		material = Enum.Material.ForceField,
		transparency = 0.1,
		collide = false,
		parent = parent,
	})
	field.CastShadow = false
	lamp(field, "#FFAA3C", 30, 0.9)
	Build.prompt(field, { action = "Play Zero G Dodgeball", object = "Portal", warp = "Dodgeball" })
	for i, x in { span.center - 18, span.center + 18 } do
		hoop(parent, Vector3.new(x, 2 + i * 2, (i - 1.5) * 10), 3, BALL_COLORS[i])
	end
	Build.sign({
		name = "PlaygroundSign",
		text = "Zero G Dodgeball\nStep through the portal: throw suns, launch off blocks!",
		size = Vector3.new(20, 5, 0.4),
		cframe = CFrame.new(span.center, 2, -13.5),
		faces = { Enum.NormalId.Back },
		parent = parent,
		textColor = "#FFB020",
	})
end

local function showroom(parent: Instance, span: Span)
	for i, x in { span.center - 14, span.center + 14 } do
		local pad = Build.part({
			name = "DisplayPad",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.6, 14, 14),
			cframe = CFrame.new(x, FLOOR_Y + 0.3, 2) * CFrame.Angles(0, 0, math.pi / 2),
			color = "#FFD36B",
			material = Enum.Material.Neon,
			parent = parent,
		})
		lamp(pad, "#FFD36B", 18, 0.9)
		-- A ship model turning above each pad, if the models are imported.
		local shipId = if i == 1 then "RedFighter" else "UltravioletIntruder"
		local def = Config.Ships.BY_ID[shipId]
		local source = if def then ShipModel.find(def) else nil
		if source and def then
			local ok, model = pcall(function(): Model
				return (ShipModel.fit(source, def, Vector3.new(12, 6, 12)))
			end)
			if ok and model then
				model.Name = `Display_{shipId}`
				model:PivotTo(CFrame.new(x, FLOOR_Y + 5, 2) * model:GetPivot())
				for _, item in model:GetDescendants() do
					if item:IsA("BasePart") then
						item.Anchored = true
						item.CanCollide = false
						if not ShipModel.textured(item) then
							item.Color = Color3.fromHex(def.paint)
						end
					end
				end
				model.Parent = parent
				spin(model, 0.35)
			end
		end
	end
	Build.sign({
		name = "ShowroomSign",
		text = "Ship Showroom\nEvery ship is at the Shipyard (HUD button)",
		size = Vector3.new(18, 5, 0.4),
		cframe = CFrame.new(span.center, 2, -13.5),
		faces = { Enum.NormalId.Back },
		parent = parent,
		textColor = "#FFD36B",
	})
end

local function areaContents(parent: Instance, def: ModuleDef, span: Span)
	if def.id == "Arrival" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "ArrivalSpawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(10, 0.2, 10)
		spawn.CFrame = CFrame.lookAt(
			Vector3.new(span.center, FLOOR_Y + 0.1, 0),
			Vector3.new(span.to, FLOOR_Y + 0.1, 0)
		)
		spawn.Color = Color3.fromHex(COLORS.accent)
		spawn.Material = Enum.Material.Neon
		spawn.CastShadow = false
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = parent
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		board(
			"Directory",
			"Directory",
			Vector3.new(24, 9, 0.4),
			CFrame.new(span.center, 3, 13.6),
			Enum.NormalId.Front,
			"ISS Directory",
			table.concat({
				"<b>Observation Cupola</b>: the view",
				"<b>Star Lounge</b>: top Stardust, the Daily Wheel",
				"<b>Planet Egg Lab</b>: planet eggs, odds, rare hatches",
				"<b>Navigation</b>: route to your station",
				"<b>Zero G Dodgeball</b> · <b>Ship Showroom</b> · <b>Raid Airlock</b>",
				"Your station: hatch eggs in the hangar's Incubator Bay",
			}, "\n"),
			"#4FC3F7",
			parent
		)
		Build.sign({
			name = "Welcome",
			text = "Welcome to Grow a Galaxy!\nPress Launch Ship to fly. Raid the Death Star through the Raid Airlock.",
			size = Vector3.new(22, 6, 0.4),
			cframe = CFrame.new(span.center, 2, -13.5),
			faces = { Enum.NormalId.Back },
			parent = parent,
		})
	elseif def.id == "Lounge" then
		lounge(parent, span)
	elseif def.id == "EggLab" then
		eggLab(parent, span)
	elseif def.id == "Navigation" then
		local console = Build.console(
			"NavigationConsole",
			"Navigation\nRoute to your station",
			wallSpot(span.center),
			parent
		)
		Build.prompt(
			console,
			{ action = "Show route to my station", object = "Navigation", route = "Station" }
		)
	elseif def.id == "Playground" then
		playground(parent, span)
	elseif def.id == "Showroom" then
		showroom(parent, span)
	elseif def.id == "RaidAirlock" then
		local console = Build.console(
			"AirlockConsole",
			"Raid Airlock\nTo the Saturn V raid beacon",
			wallSpot(span.center),
			parent
		)
		Build.prompt(
			console,
			{ action = "Go outside", object = "Raid Airlock", warp = "DockingArea" }
		)
		Build.marker(
			"AirlockInside",
			CFrame.lookAt(
				Vector3.new(span.center, FLOOR_Y + 3, 4),
				Vector3.new(span.from, FLOOR_Y + 3, 4)
			),
			parent
		)
		local glow = neon(
			"RaidGlow",
			Vector3.new(0.4, 6, 10),
			CFrame.new(span.to - 1, 0, 0),
			"#FF4A4A",
			parent
		)
		lamp(glow, "#FF4A4A", 30, 0.8)
	end
end

local function truss(parent: Instance)
	Build.part({
		name = "Truss",
		size = Vector3.new(6, 5, TRUSS_LENGTH),
		cframe = CFrame.new(0, TRUSS_Y, 0),
		color = COLORS.truss,
		material = Enum.Material.DiamondPlate,
		parent = parent,
	})
	for _, x in { -3.6, 3.6 } do
		Build.part({
			name = "TrussRail",
			size = Vector3.new(1, 1, TRUSS_LENGTH),
			cframe = CFrame.new(x, TRUSS_Y + 2.5, 0),
			color = COLORS.hullAlt,
			parent = parent,
		})
	end
	Build.part({
		name = "TrussPylon",
		size = Vector3.new(4, TRUSS_Y - 2.5 - TUBE_RADIUS, 4),
		cframe = CFrame.new(0, (TRUSS_Y - 2.5 + TUBE_RADIUS) / 2, 0),
		color = COLORS.truss,
		parent = parent,
	})

	-- Four solar-array assemblies: a mast across the truss with two blankets on each side.
	for _, z in { -160, -110, 110, 160 } do
		Build.part({
			name = "ArrayJoint",
			size = Vector3.new(8, 7, 8),
			cframe = CFrame.new(0, TRUSS_Y, z),
			color = COLORS.hullAlt,
			parent = parent,
		})
		Build.part({
			name = "ArrayMast",
			size = Vector3.new(160, 0.8, 0.8),
			cframe = CFrame.new(0, TRUSS_Y, z),
			color = COLORS.solarFrame,
			parent = parent,
		})
		for _, side in { -1, 1 } do
			for _, offset in { -6.5, 6.5 } do
				Build.part({
					name = "SolarArray",
					size = Vector3.new(72, 0.3, 11),
					cframe = CFrame.new(side * 42, TRUSS_Y, z + offset)
						* CFrame.Angles(math.rad(25), 0, 0),
					color = COLORS.solar,
					material = Enum.Material.Glass,
					collide = false,
					parent = parent,
				})
			end
		end
	end

	-- Radiators hang below the truss, clear of the modules.
	for _, z in { -62, 62 } do
		Build.part({
			name = "Radiator",
			size = Vector3.new(0.4, 22, 16),
			cframe = CFrame.new(0, TRUSS_Y - 2.5 - 11, z),
			color = COLORS.radiator,
			collide = false,
			parent = parent,
		})
	end
end

-- The raid platform past the airlock: a wide deck with a glowing rim, the
-- RaidBeacon marker at its centre (RaidSystem stands the Saturn V there).
local function raidPlatform(parent: Instance, airlockSpan: Span)
	local x0 = airlockSpan.to
	Build.part({
		name = "Tunnel",
		size = Vector3.new(14, 16, 16),
		cframe = CFrame.new(x0 + 7, 0, 0),
		color = COLORS.hullAlt,
		parent = parent,
	})
	local cx = x0 + 14 + PLATFORM_SIZE / 2
	Build.part({
		name = "RaidPlatform",
		size = Vector3.new(PLATFORM_SIZE, 2, PLATFORM_SIZE),
		cframe = CFrame.new(cx, FLOOR_Y - 1, 0),
		color = "#1E2230",
		material = Enum.Material.DiamondPlate,
		parent = parent,
	})
	-- Glowing rim.
	for _, edge in
		{
			{
				size = Vector3.new(PLATFORM_SIZE, 0.6, 1),
				offset = Vector3.new(0, 0, -PLATFORM_SIZE / 2),
			},
			{
				size = Vector3.new(PLATFORM_SIZE, 0.6, 1),
				offset = Vector3.new(0, 0, PLATFORM_SIZE / 2),
			},
			{
				size = Vector3.new(1, 0.6, PLATFORM_SIZE),
				offset = Vector3.new(-PLATFORM_SIZE / 2, 0, 0),
			},
			{
				size = Vector3.new(1, 0.6, PLATFORM_SIZE),
				offset = Vector3.new(PLATFORM_SIZE / 2, 0, 0),
			},
		}
	do
		neon(
			"Rim",
			edge.size,
			CFrame.new(cx, FLOOR_Y + 0.3, 0) * CFrame.new(edge.offset),
			"#FF4A4A",
			parent
		)
	end
	-- Walkway lights from the airlock to the beacon.
	for x = x0 + 18, cx - 30, 8 do
		for _, z in { -6, 6 } do
			neon(
				"WalkLight",
				Vector3.new(1, 0.4, 1),
				CFrame.new(x, FLOOR_Y + 0.2, z),
				"#FF8A3D",
				parent
			)
		end
	end

	Build.marker("RaidBeacon", CFrame.new(cx, FLOOR_Y, 0), parent)
	Build.marker(
		"DockingSpawn",
		CFrame.lookAt(Vector3.new(x0 + 22, FLOOR_Y + 3, 0), Vector3.new(cx, FLOOR_Y + 3, 0)),
		parent
	)
	local console = Build.console(
		"AirlockReturn",
		"Airlock\nBack inside",
		CFrame.new(x0 + 20, FLOOR_Y, -12) * CFrame.Angles(0, math.pi, 0),
		parent
	)
	Build.prompt(console, { action = "Go inside", object = "Airlock", warp = "Interior" })
	Build.sign({
		name = "RaidSign",
		text = "DEATH STAR RAIDS\nStep on a glowing pad to join a raid queue",
		size = Vector3.new(30, 7, 0.4),
		cframe = CFrame.new(x0 + 40, FLOOR_Y + 9, -24),
		faces = { Enum.NormalId.Back },
		parent = parent,
		textColor = "#FF8A3D",
	})
end

local IssBuilder = {}

function IssBuilder.build(): Model
	local model = Build.model("ISS")
	local spans = layout()

	local hull = Build.model("Hull", model)
	local rooms = Build.model("Interior", model)
	for index, def in MODULES do
		local span = spans[def.id]
		local area = Build.model(def.id, rooms)
		tube(hull, span, if index % 2 == 0 then COLORS.hull else COLORS.hullAlt, def.glass == true)
		interior(area, def, span)
		areaContents(area, def, span)
	end
	endCap(hull, spans[MODULES[1].id].from - 0.5, true)
	endCap(hull, spans[MODULES[#MODULES].id].to + 0.5, false)

	truss(Build.model("Truss", model))
	raidPlatform(Build.model("RaidArea", model), spans.RaidAirlock)

	-- No PvP around the hub and its raid platform (CombatSystem).
	local first, last =
		spans[MODULES[1].id].from, spans[MODULES[#MODULES].id].to + 14 + PLATFORM_SIZE
	local safe = Build.part({
		name = "SafeZone",
		size = Vector3.new(last - first + 200, 500, 500),
		cframe = CFrame.new((first + last) / 2, 120, 0),
		transparency = 1,
		collide = false,
		parent = model,
	})
	safe.CanQuery = false
	CollectionService:AddTag(safe, SAFE_ZONE_TAG)

	model.WorldPivot = CFrame.new()
	return model
end

return IssBuilder

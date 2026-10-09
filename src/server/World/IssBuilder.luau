--!strict
-- The International Space Station hub, built from parts at the world origin.
--
-- Exterior: a line of roomy cylindrical modules with window bands down both
-- sides and gold berthing collars at the joints, a long truss crossing above
-- them (four segmented solar-array assemblies, finned radiators, the robot
-- arm, a comms dish), the spinning gravity wheel round the hull between the
-- Star Lounge and the Central Hub (scenery: it turns on each client about the
-- long axis), a glass observation cupola at the -X end and, past the airlock
-- at the +X end, the raid platform: a wide deck where RaidSystem stands the
-- Saturn V beacon (at the "RaidBeacon" marker) and its difficulty pads.
-- No ships dock at the ISS: ships launch from each player's own station.
--
-- Interior, one module per area, each entered through a lit arch with its
-- name and icon: Observation Cupola, Arrival (spawn), Star Lounge (spiral
-- galaxy hologram, curved sofas, boards, the big Daily Wheel, party lights),
-- Central Hub (a compass plaza round a globe beacon, signposts of arrows to
-- every area), the Zero G Dodgeball portal (to the arena,
-- DodgeballSystem; floating hoops), Ship Showroom (ships on spotlit
-- turntables with plaques) and the Raid Airlock (hazard-striped inner door,
-- suit lockers, rotating beacons, a pulsing floor strip and the round outer
-- hatch; its console cycles you out to the raid deck).
-- Gravity is off, so players float; floors give them something to push on.
--
-- Boards (parts tagged "GaG_IssBoard", attribute Board, a SurfaceGui with
-- Title and Body labels): the Arrival directory (fixed text), the Star
-- Lounge's Stardust leaderboard and rare-hatch feed (filled in by
-- IssBoardSystem). The Star Lounge's Daily Wheel turns on each client
-- (SpinAxis "Z"); its kiosk has the prompt (attribute OpenPanel = "Wheel"). Planet eggs are rolled at each player's
-- own Egg Lab, in their station (StationBuilder).
--
-- Parts tagged "GaG_Spin" (with a SpinSpeed attribute, radians per second)
-- are turned by every client (SpinController). The parts named in
-- WorldSystem.MARKERS are the contract with the rest of the game.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ShipModel = require(ReplicatedStorage.Shared.Util.ShipModel)
local Build = require(script.Parent.Build)

local COLORS = Config.World.COLORS

local TUBE_RADIUS = 20
local TUBE_SIDES = 12
local FLOOR_Y = -9
local FLOOR_WIDTH = 34
-- Boards and signs hang on the side walls, this far from the centre line.
local WALL_Z = TUBE_RADIUS - 2.4
-- Every module is this much longer than its listed length: roomier halls.
local LENGTH_SCALE = 1.25
local TRUSS_Y = 38
-- Each module's entrance arch: posts this far either side of the centre
-- line, lintel at this height.
local ARCH_HALF = 13
local ARCH_TOP = 9
-- The Daily Wheel's neon and lights glow this much less (bloom).
local WHEEL_BLOOM_DIM = 0.4
-- The spinning gravity wheel round the hull (centripetal "gravity" ring):
-- centred on the joint between the Star Lounge and the Central Hub, turning about
-- the station's long (X) axis.
local WHEEL_RADIUS = 76
local WHEEL_WIDTH = 14
local WHEEL_SEGMENTS = 24
local WHEEL_SPOKES = 4
local WHEEL_SPIN = 0.12 -- radians per second
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
	trim: string, -- floor strip, light tint and sign colour
	icon: string, -- emoji on its signs
}

-- From the -X end to the +X end. The Central Hub is centred on the origin.
local MODULES: { ModuleDef } = {
	{
		id = "Cupola",
		label = "Observation Cupola",
		length = 30,
		glass = true,
		trim = "#5FB8FF",
		icon = "🔭",
	},
	{ id = "Arrival", label = "Arrival", length = 44, trim = "#4FC3F7", icon = "🚀" },
	{ id = "Lounge", label = "Star Lounge", length = 40, trim = "#B06BFF", icon = "✨" },
	{ id = "Hub", label = "Central Hub", length = 32, trim = "#2EC4B6", icon = "🧭" },
	{ id = "Playground", label = "Zero G Dodgeball", length = 52, trim = "#FFB020", icon = "🏐" },
	{ id = "Showroom", label = "Ship Showroom", length = 48, trim = "#FFD36B", icon = "🛸" },
	{ id = "RaidAirlock", label = "Raid Airlock", length = 32, trim = "#FF4A4A", icon = "💀" },
}

type Span = { from: number, to: number, center: number }

local function layout(): { [string]: Span }
	local offset = 0
	for _, def in MODULES do
		if def.id == "Hub" then
			offset += def.length * LENGTH_SCALE / 2
			break
		end
		offset += def.length * LENGTH_SCALE
	end
	local spans: { [string]: Span } = {}
	local x = -offset
	for _, def in MODULES do
		local length = def.length * LENGTH_SCALE
		spans[def.id] = { from = x, to = x + length, center = x + length / 2 }
		x += length
	end
	return spans
end

local IssBuilder = {}

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

-- Signs share one arcade style: a rounded panel filled with a gradient of
-- the accent colour, a bright rim, a glossy top, a row of marquee bulbs
-- along the top and bottom edges, and chunky outlined lettering with an
-- emoji icon. Drawn in a SurfaceGui, so a sign costs one part.
local SIGN_FONT = Enum.Font.FredokaOne
local SIGN_PIXELS = 40 -- SurfaceGui pixels per stud

local function outlined(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = Color3.fromRGB(20, 14, 40)
	stroke.Thickness = thickness
	stroke.Parent = label
end

-- The sign's backdrop on `gui` (pixel size `pixels`): panel, rim, gloss
-- and bulbs. Returns the panel for the text.
local function signPanel(gui: SurfaceGui, pixels: Vector2, accent: string): Frame
	local color = Color3.fromHex(accent)
	local margin = math.min(pixels.X, pixels.Y) * 0.06
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(1, -2 * margin, 1, -2 * margin)
	panel.Position = UDim2.fromOffset(margin, margin)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.ZIndex = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.min(pixels.X, pixels.Y) * 0.22)
	corner.Parent = panel
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.25)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.fromRGB(20, 10, 50), 0.6)),
	})
	fill.Parent = panel
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = color:Lerp(Color3.new(1, 1, 1), 0.65)
	rim.Thickness = math.max(4, margin * 0.6)
	rim.Parent = panel
	-- Gloss over the top third.
	local gloss = Instance.new("Frame")
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.82
	gloss.Size = UDim2.new(0.94, 0, 0.32, 0)
	gloss.Position = UDim2.fromScale(0.03, 0.05)
	gloss.ZIndex = 1
	gloss.Parent = panel
	local glossCorner = Instance.new("UICorner")
	glossCorner.CornerRadius = UDim.new(1, 0)
	glossCorner.Parent = gloss
	-- Marquee bulbs along the top and bottom edges, warm and white in turn.
	local bulb = math.min(pixels.Y * 0.07, 18)
	local count = math.max(3, math.floor(pixels.X / (bulb * 3.2)))
	for _, y in { margin / 2, pixels.Y - margin / 2 } do
		for index = 1, count do
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(bulb, bulb)
			dot.Position = UDim2.fromOffset(pixels.X * (index - 0.5) / count, y)
			dot.BackgroundColor3 = if index % 2 == 0
				then Color3.fromRGB(255, 244, 214)
				else Color3.fromRGB(255, 196, 64)
			dot.ZIndex = 3
			dot.Parent = gui
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(1, 0)
			round.Parent = dot
		end
	end
	return panel
end

-- Draws a sign on one face of `part`: icon, title and an optional subtitle.
local function signFace(
	part: BasePart,
	face: Enum.NormalId,
	title: string,
	subtitle: string,
	accent: string
)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS
	gui.LightInfluence = 0
	gui.Parent = part
	local size = part.Size
	local across = if face == Enum.NormalId.Left or face == Enum.NormalId.Right
		then size.Z
		else size.X
	local panel = signPanel(gui, Vector2.new(across, size.Y) * SIGN_PIXELS, accent)
	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromScale(0.05, if subtitle == "" then 0.14 else 0.1)
	heading.Size = UDim2.fromScale(0.9, if subtitle == "" then 0.72 else 0.52)
	heading.Font = SIGN_FONT
	heading.TextScaled = true
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.Text = title
	heading.ZIndex = 2
	heading.Parent = panel
	outlined(heading, 4)
	if subtitle ~= "" then
		local line = Instance.new("TextLabel")
		line.Name = "Subtitle"
		line.BackgroundTransparency = 1
		line.Position = UDim2.fromScale(0.08, 0.64)
		line.Size = UDim2.fromScale(0.84, 0.26)
		line.Font = Enum.Font.GothamBold
		line.TextScaled = true
		line.TextColor3 = Color3.fromRGB(255, 250, 235)
		line.Text = subtitle
		line.ZIndex = 2
		line.Parent = panel
		outlined(line, 2)
	end
end

local BOARD_TAG = "GaG_IssBoard"

-- A wall board with a title and a body text, readable on `face`, in the
-- sign style. Title and Body sit straight under the "Board" SurfaceGui
-- (the contract with IssBoardSystem).
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
	gui.PixelsPerStud = SIGN_PIXELS
	gui.LightInfluence = 0
	gui.Parent = part
	local pixels = Vector2.new(size.X, size.Y) * SIGN_PIXELS
	local panel = signPanel(gui, pixels, accent)
	-- A dark window inside the panel for the text.
	local inset = Instance.new("Frame")
	inset.BackgroundColor3 = Color3.fromRGB(16, 14, 38)
	inset.BackgroundTransparency = 0.15
	inset.Position = UDim2.new(0, 22, 0, 84)
	inset.Size = UDim2.new(1, -44, 1, -106)
	inset.ZIndex = 1
	inset.Parent = panel
	local insetCorner = Instance.new("UICorner")
	insetCorner.CornerRadius = UDim.new(0, 18)
	insetCorner.Parent = inset
	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromOffset(40, 26)
	heading.Size = UDim2.new(1, -80, 0, 60)
	heading.Font = SIGN_FONT
	heading.TextScaled = true
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.Text = title
	heading.ZIndex = 4
	heading.Parent = gui
	outlined(heading, 4)
	local text = Instance.new("TextLabel")
	text.Name = "Body"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(52, 116)
	text.Size = UDim2.new(1, -104, 1, -150)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 28
	text.TextWrapped = true
	text.RichText = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextColor3 = Color3.fromRGB(235, 238, 255)
	text.Text = body
	text.ZIndex = 4
	text.Parent = gui
	return part
end

-- A wall sign (one part, not solid) in the sign style, readable on `face`.
local function wallSign(
	name: string,
	title: string,
	subtitle: string,
	size: Vector3,
	cframe: CFrame,
	face: Enum.NormalId,
	accent: string,
	parent: Instance
): Part
	local part = Build.part({
		name = name,
		size = size,
		cframe = cframe,
		color = "#0E1222",
		material = Enum.Material.SmoothPlastic,
		collide = false,
		parent = parent,
	})
	signFace(part, face, title, subtitle, accent)
	return part
end

-- A signpost arrow (one invisible part along X): a gradient arrow with an
-- icon and a place name, pointing the way to `direction` (+1 = +X) on both
-- faces. (Seen from the Front face, -Z, +X is on the viewer's left.)
local function arrowSign(
	name: string,
	text: string,
	direction: number,
	size: Vector3,
	cframe: CFrame,
	accent: string,
	parent: Instance
): Part
	local part = Build.part({
		name = name,
		size = size,
		cframe = cframe,
		color = "#0E1222",
		transparency = 1,
		collide = false,
		parent = parent,
	})
	part.CanQuery = false
	local color = Color3.fromHex(accent)
	local pixels = Vector2.new(size.X, size.Y) * SIGN_PIXELS
	local tip = pixels.Y / 2
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local right = (face == Enum.NormalId.Back) == (direction > 0)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Arrow"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = SIGN_PIXELS
		gui.LightInfluence = 0
		gui.Parent = part
		local shaft = Instance.new("Frame")
		shaft.Size = UDim2.new(1, -tip, 1, 0)
		shaft.Position = UDim2.fromOffset(if right then 0 else tip, 0)
		shaft.BackgroundColor3 = Color3.new(1, 1, 1)
		shaft.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, pixels.Y * 0.25)
		corner.Parent = shaft
		-- The head: a square turned 45 degrees, half of it past the shaft.
		local head = Instance.new("Frame")
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Size = UDim2.fromOffset(pixels.Y / math.sqrt(2), pixels.Y / math.sqrt(2))
		head.Position = UDim2.fromOffset(if right then pixels.X - tip else tip, pixels.Y / 2)
		head.Rotation = 45
		head.BackgroundColor3 = Color3.new(1, 1, 1)
		head.Parent = gui
		for _, piece in { shaft, head } do
			local fill = Instance.new("UIGradient")
			fill.Rotation = 90 - head.Rotation * (if piece == head then 1 else 0)
			fill.Color = ColorSequence.new(
				color:Lerp(Color3.new(1, 1, 1), 0.3),
				color:Lerp(Color3.fromRGB(20, 10, 50), 0.45)
			)
			fill.Parent = piece
			local rim = Instance.new("UIStroke")
			rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rim.Color = color:Lerp(Color3.new(1, 1, 1), 0.7)
			rim.Thickness = 4
			rim.Parent = piece
		end
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.06, 0.12)
		label.Size = UDim2.fromScale(0.88, 0.76)
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = text
		label.ZIndex = 2
		label.Parent = shaft
		outlined(label, 3)
	end
	return part
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
	-- The entrance arch: two metal posts and a lintel glowing in the
	-- module's colour, with the area's name on a sign under it, readable
	-- from both directions along the walkway.
	-- The Raid Airlock has its own hazard-striped door instead.
	if def.id == "RaidAirlock" then
		return
	end
	local archX = span.from + 1.5
	for _, z in { -ARCH_HALF, ARCH_HALF } do
		Build.part({
			name = "ArchPost",
			size = Vector3.new(1.4, ARCH_TOP - FLOOR_Y, 1.4),
			cframe = CFrame.new(archX, (ARCH_TOP + FLOOR_Y) / 2, z),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
	neon(
		"ArchLintel",
		Vector3.new(1.6, 0.8, ARCH_HALF * 2 + 1.4),
		CFrame.new(archX, ARCH_TOP, 0),
		def.trim,
		parent
	)
	local sign = Build.part({
		name = "AreaSign",
		size = Vector3.new(0.4, 3.4, 18),
		cframe = CFrame.new(archX, ARCH_TOP - 2.4, 0),
		color = "#0E1222",
		collide = false,
		parent = parent,
	})
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		signFace(sign, face, `{def.icon} {def.label}`, "", def.trim)
	end
end

-- Floor point against the -Z wall of a module, facing the walkway.
local function wallSpot(x: number): CFrame
	return CFrame.new(x, FLOOR_Y, -(TUBE_RADIUS - 7)) * CFrame.Angles(0, math.pi, 0)
end

-- A glowing floor chevron at `x` pointing along `direction` (+1 = +X).
local function chevron(parent: Instance, x: number, z: number, direction: number, color: string)
	for _, side in { -1, 1 } do
		neon(
			"Chevron",
			Vector3.new(0.5, 0.12, 3),
			CFrame.new(x, FLOOR_Y + 0.07, z + side * 1)
				* CFrame.Angles(0, -side * direction * math.rad(40), 0),
			color,
			parent
		)
	end
end

-- A potted space plant: a glowing pot rim and three curling stems, each
-- with a glowing bulb.
local function spacePlant(parent: Instance, at: Vector3, color: string)
	Build.part({
		name = "PlantPot",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(2.2, 2.6, 2.6),
		cframe = CFrame.new(at + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = "#E8ECF8",
		material = Enum.Material.SmoothPlastic,
		parent = parent,
	})
	for index = 1, 3 do
		local angle = index / 3 * 2 * math.pi
		local lean = CFrame.new(at + Vector3.new(0, 2.2, 0))
			* CFrame.Angles(0, angle, 0)
			* CFrame.Angles(math.rad(14 + index * 4), 0, 0)
		local height = 2.4 + index * 0.8
		Build.part({
			name = "PlantStem",
			size = Vector3.new(0.3, height, 0.3),
			cframe = lean * CFrame.new(0, height / 2, 0),
			color = "#3FCF8E",
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = parent,
		})
		local bulb = neon(
			"PlantBulb",
			Vector3.one * (0.8 + index * 0.15),
			lean * CFrame.new(0, height + 0.3, 0),
			color,
			parent
		)
		bulb.Shape = Enum.PartType.Ball
	end
end

-- A string of party bulbs hanging from the ceiling along X, sagging in the
-- middle.
local function stringLights(parent: Instance, from: number, to: number, z: number, top: number)
	local count = 12
	local lights = Build.model("StringLights", parent)
	for index = 0, count - 1 do
		local t = index / (count - 1)
		local sag = 3 * (1 - (2 * t - 1) ^ 2)
		local bulb = neon(
			"PartyBulb",
			Vector3.one * 0.7,
			CFrame.new(from + (to - from) * t, top - sag, z),
			BALL_COLORS[index % #BALL_COLORS + 1],
			lights
		)
		bulb.Shape = Enum.PartType.Ball
	end
	Build.dimEmissive(lights, 0.25)
end

-- The Central Hub: a compass plaza round a globe beacon (a spinning planet
-- with its moons in a glass sphere), and two signposts whose colourful
-- arrows point the way to every area, with floor chevrons leading on.
local function hub(parent: Instance, span: Span)
	local x = span.center
	-- The plaza: a dark medallion with a glowing rim and compass points.
	local rim = neon(
		"PlazaRim",
		Vector3.new(0.1, 25, 25),
		CFrame.new(x, FLOOR_Y + 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#2EC4B6",
		parent
	)
	rim.Shape = Enum.PartType.Cylinder
	local plaza = Build.part({
		name = "Plaza",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.12, 23.6, 23.6),
		cframe = CFrame.new(x, FLOOR_Y + 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = "#16223A",
		material = Enum.Material.SmoothPlastic,
		parent = parent,
	})
	plaza.CastShadow = false
	for index = 0, 3 do
		neon(
			"CompassPoint",
			Vector3.new(0.6, 0.12, 6),
			CFrame.new(x, FLOOR_Y + 0.1, 0)
				* CFrame.Angles(0, index * math.pi / 2, 0)
				* CFrame.new(0, 0, 7.5),
			if index % 2 == 0 then "#FFD36B" else "#2EC4B6",
			parent
		)
	end
	-- The globe beacon: plinth, column and cradle under a glass sphere.
	for _, piece in
		{
			{ name = "BeaconPlinth", height = 1.2, width = 7, y = 0.6, color = COLORS.hullAlt },
			{ name = "BeaconColumn", height = 7, width = 2.2, y = 4.7, color = "#DDE6F5" },
			{ name = "BeaconCradle", height = 0.8, width = 4.4, y = 8.6, color = COLORS.hullAlt },
		}
	do
		Build.part({
			name = piece.name,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(piece.height, piece.width, piece.width),
			cframe = CFrame.new(x, FLOOR_Y + piece.y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color = piece.color,
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
	for _, y in { 1.3, 9.05 } do
		local band = neon(
			"BeaconBand",
			Vector3.new(0.3, if y < 5 then 7.6 else 4.8, if y < 5 then 7.6 else 4.8),
			CFrame.new(x, FLOOR_Y + y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			"#2EC4B6",
			parent
		)
		band.Shape = Enum.PartType.Cylinder
	end
	local globeY = FLOOR_Y + 12.6
	local globe = Build.part({
		name = "BeaconGlobe",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 7.4,
		cframe = CFrame.new(x, globeY, 0),
		color = "#BFEFFF",
		material = Enum.Material.Glass,
		transparency = 0.7,
		collide = false,
		parent = parent,
	})
	globe.CastShadow = false
	local planet = Build.model("BeaconPlanet", parent)
	local world = Build.part({
		name = "Planet",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 3.2,
		cframe = CFrame.new(x, globeY, 0),
		color = "#3FA9F5",
		material = Enum.Material.SmoothPlastic,
		collide = false,
		parent = planet,
	})
	local band = neon(
		"PlanetRing",
		Vector3.new(0.12, 5.6, 5.6),
		CFrame.new(x, globeY, 0) * CFrame.Angles(0, 0, math.rad(90 - 18)),
		"#FFD36B",
		planet
	)
	band.Shape = Enum.PartType.Cylinder
	band.Transparency = 0.45
	for index, color in { "#FF6EC8", "#8CFF6B", "#FFFFFF" } do
		local angle = index / 3 * 2 * math.pi
		local moon = neon(
			"Moon",
			Vector3.one * 0.6,
			CFrame.new(x + math.cos(angle) * 3.2, globeY + (index - 2) * 0.5, math.sin(angle) * 3.2),
			color,
			planet
		)
		moon.Shape = Enum.PartType.Ball
	end
	planet.PrimaryPart = world
	spin(planet, 0.7)
	lamp(world, "#5FE3FF", 28, 0.8)
	-- Two signposts, one either side of the walkway. Each arrow points the
	-- way to an area, in that area's colour; a little skew makes them look
	-- hand-placed.
	local ways = {
		{ label = "Star Lounge", icon = "✨", color = "#B06BFF", direction = -1 },
		{ label = "Zero G Dodgeball", icon = "🏐", color = "#FFB020", direction = 1 },
		{ label = "Arrival", icon = "🚀", color = "#4FC3F7", direction = -1 },
		{ label = "Ship Showroom", icon = "🛸", color = "#FFD36B", direction = 1 },
		{ label = "Cupola", icon = "🔭", color = "#5FB8FF", direction = -1 },
		{ label = "Raid Airlock", icon = "💀", color = "#FF4A4A", direction = 1 },
	}
	for _, z in { -11, 11 } do
		local postTop = FLOOR_Y + 16
		Build.part({
			name = "SignpostPole",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(postTop - FLOOR_Y, 0.8, 0.8),
			cframe = CFrame.new(x, (postTop + FLOOR_Y) / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
			color = "#E8ECF8",
			material = Enum.Material.Metal,
			parent = parent,
		})
		local cap = neon(
			"SignpostCap",
			Vector3.one * 1.4,
			CFrame.new(x, postTop + 0.5, z),
			"#FFD36B",
			parent
		)
		cap.Shape = Enum.PartType.Ball
		for index, way in ways do
			local y = FLOOR_Y + 4 + (index - 1) * 2
			local skew = math.rad(((index * 7) % 5 - 2) * 3)
			arrowSign(
				"WayArrow",
				`{way.icon} {way.label}`,
				way.direction,
				Vector3.new(8, 1.6, 0.2),
				CFrame.new(x + way.direction * 4.3, y, z) * CFrame.Angles(0, 0, skew),
				way.color,
				parent
			)
		end
	end
	-- Chevrons on the floor lead on both ways, and space plants in the corners.
	for _, side in { -1, 1 } do
		for step = 1, 3 do
			chevron(
				parent,
				x + side * (13 + step * 2.5),
				0,
				side,
				if side < 0 then "#B06BFF" else "#FFB020"
			)
		end
		for _, z in { -13.5, 13.5 } do
			spacePlant(
				parent,
				Vector3.new(x + side * 15, FLOOR_Y, z),
				if z < 0 then "#FF6EC8" else "#5FE3FF"
			)
		end
	end
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

-- The Daily Wheel: a big prize wheel standing against the -Z wall, its
-- wedges in the prizes' colours (Config.Wheel) and a ring of bulbs, turning
-- slowly (SpinController, SpinAxis "Z") under a fixed pointer and a
-- marquee. The kiosk in front of it opens the wheel panel (WheelController).
local function prizeWheel(parent: Instance, x: number)
	local centre = CFrame.new(x, 1, -(WALL_Z - 1.2))
	local wheel = Build.model("PrizeWheel", parent)
	local back = Build.part({
		name = "WheelBack",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.4, 12.4, 12.4),
		cframe = centre * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.pi / 2, 0),
		color = "#C9A24A",
		material = Enum.Material.Metal,
		collide = false,
		parent = wheel,
	})
	back.CastShadow = false
	local prizes = Config.Wheel.PRIZES
	local count = #prizes
	for index, prize in prizes do
		local angle = (index - 1) / count * 2 * math.pi
		neon(
			"Wedge",
			Vector3.new(2 * 5.4 * math.tan(math.pi / count) * 0.92, 4.4, 0.3),
			centre * CFrame.Angles(0, 0, angle) * CFrame.new(0, 3.1, index * 0.01),
			prize.color,
			wheel
		)
	end
	for index = 1, 12 do
		local angle = index / 12 * 2 * math.pi
		local bulb = neon(
			"Bulb",
			Vector3.one * 0.6,
			centre * CFrame.Angles(0, 0, angle) * CFrame.new(0, 5.8, 0.2),
			if index % 2 == 0 then "#FFF4D6" else "#FFB020",
			wheel
		)
		bulb.Shape = Enum.PartType.Ball
	end
	local hubBall =
		neon("WheelHub", Vector3.one * 1.6, centre * CFrame.new(0, 0, 0.3), "#FFF4D6", wheel)
	hubBall.Shape = Enum.PartType.Ball
	lamp(hubBall, "#FFB020", 22, 0.9)
	wheel:SetAttribute("SpinAxis", "Z")
	spin(wheel, 0.5)
	-- Toned down so it doesn't bloom out the lounge.
	Build.dimEmissive(wheel, WHEEL_BLOOM_DIM)
	-- The fixed pointer at the top, the stand and the marquee.
	local pointer = neon(
		"Pointer",
		Vector3.new(1.2, 1.2, 0.5),
		centre * CFrame.new(0, 6.7, 0.4) * CFrame.Angles(0, 0, math.rad(45)),
		"#FF4A4A",
		parent
	)
	Build.dimEmissive(pointer, WHEEL_BLOOM_DIM)
	for _, side in { -1, 1 } do
		Build.part({
			name = "WheelLeg",
			size = Vector3.new(0.8, 9, 0.8),
			cframe = CFrame.new(x + side * 3.2, FLOOR_Y + 4.5, -(WALL_Z - 0.6))
				* CFrame.Angles(0, 0, side * math.rad(-12)),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
	wallSign(
		"WheelMarquee",
		"★ DAILY SPIN ★",
		"",
		Vector3.new(14, 2.6, 0.4),
		CFrame.new(x, 8.4, -(WALL_Z - 0.4)),
		Enum.NormalId.Back,
		"#FFB020",
		parent
	)
	local kiosk = Build.console("WheelKiosk", "Daily Wheel\nOne spin a day", wallSpot(x), parent)
	local kioskPrompt =
		Build.prompt(kiosk, { action = "Spin the Daily Wheel", object = "Daily Wheel" })
	kioskPrompt:SetAttribute("OpenPanel", "Wheel")
	kioskPrompt.MaxActivationDistance = 12
end

-- The Star Lounge: a spiral galaxy hologram over a glowing projector in
-- the middle of a round rug, curved sofas round it (open towards the boards
-- and the Daily Wheel), party lights under the ceiling and space plants.
local function lounge(parent: Instance, span: Span)
	local x = span.center
	-- The rug and its glowing edge.
	local edge = neon(
		"RugEdge",
		Vector3.new(0.08, 27, 27),
		CFrame.new(x, FLOOR_Y + 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#B06BFF",
		parent
	)
	edge.Shape = Enum.PartType.Cylinder
	local rug = Build.part({
		name = "Rug",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.12, 26, 26),
		cframe = CFrame.new(x, FLOOR_Y + 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = "#2A1F4F",
		material = Enum.Material.Fabric,
		parent = parent,
	})
	rug.CastShadow = false
	-- The projector: a stepped base, a glowing lens and a faint light column.
	for _, piece in { { 1.2, 8, 0.6 }, { 1, 5.6, 1.7 } } do
		Build.part({
			name = "Projector",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(piece[1], piece[2], piece[2]),
			cframe = CFrame.new(x, FLOOR_Y + piece[3], 0) * CFrame.Angles(0, 0, math.pi / 2),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
	local lens = neon(
		"ProjectorLens",
		Vector3.new(0.3, 4.2, 4.2),
		CFrame.new(x, FLOOR_Y + 2.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#5FE3FF",
		parent
	)
	lens.Shape = Enum.PartType.Cylinder
	local column = neon(
		"LightColumn",
		Vector3.new(6, 3.6, 3.6),
		CFrame.new(x, FLOOR_Y + 5.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#B06BFF",
		parent
	)
	column.Shape = Enum.PartType.Cylinder
	column.Transparency = 0.85
	column.CastShadow = false
	-- The galaxy: a bright core, a faint disc and two spiral arms of stars
	-- shading from violet to cyan, turning slowly.
	local galaxyY = FLOOR_Y + 9
	local holo = Build.model("Hologram", parent)
	local core = neon("GalaxyCore", Vector3.one * 1.8, CFrame.new(x, galaxyY, 0), "#FFE6A3", holo)
	core.Shape = Enum.PartType.Ball
	lamp(core, "#B06BFF", 26, 1)
	local disc = neon(
		"GalaxyDisc",
		Vector3.new(0.1, 13, 13),
		CFrame.new(x, galaxyY, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#7A4ACF",
		holo
	)
	disc.Shape = Enum.PartType.Cylinder
	disc.Transparency = 0.8
	local inner, outer = Color3.fromHex("#D58BFF"), Color3.fromHex("#5FE3FF")
	for arm = 0, 1 do
		for step = 1, 9 do
			local radius = 1 + step * 0.62
			local angle = arm * math.pi + step * 0.55
			local star = neon(
				"HoloStar",
				Vector3.one * (0.75 - step * 0.045),
				CFrame.new(
					x + math.cos(angle) * radius,
					galaxyY + math.sin(step * 1.7) * 0.25,
					math.sin(angle) * radius
				),
				inner:Lerp(outer, step / 9):ToHex(),
				holo
			)
			star.Shape = Enum.PartType.Ball
		end
	end
	holo.PrimaryPart = core
	spin(holo, 0.35)
	-- Two boards side by side on the +Z wall (IssBoardSystem fills them in):
	-- the Stardust leaderboard and the latest rare hatches in this server.
	board(
		"StardustBoard",
		"Stardust",
		Vector3.new(18, 10, 0.4),
		CFrame.new(x - 12, 3.5, WALL_Z),
		Enum.NormalId.Front,
		"🏆 Top Stardust",
		"Loading...",
		"#FFB020",
		parent
	)
	board(
		"HatchFeedBoard",
		"HatchFeed",
		Vector3.new(18, 10, 0.4),
		CFrame.new(x + 12, 3.5, WALL_Z),
		Enum.NormalId.Front,
		"🪐 Rare hatches",
		"No rare planets hatched in this server yet. Will yours be the first?",
		"#FF5AA0",
		parent
	)
	prizeWheel(parent, x)
	-- Curved sofas round the rug, facing the hologram, in four pairs; the
	-- gaps on each side lead to the boards and the wheel's kiosk.
	local radius = 12
	for _, side in { -1, 1 } do
		for index, degrees in { 34, 60, 120, 146 } do
			local angle = math.rad(degrees) * side
			local at =
				Vector3.new(x + math.cos(angle) * radius, FLOOR_Y + 0.9, math.sin(angle) * radius)
			local seat = CFrame.lookAt(at, Vector3.new(x, at.Y, 0))
			Build.part({
				name = "Sofa",
				size = Vector3.new(6.2, 1.8, 3),
				cframe = seat,
				color = "#4B2F8F",
				material = Enum.Material.Fabric,
				parent = parent,
			})
			Build.part({
				name = "SofaBack",
				size = Vector3.new(6.2, 3, 0.9),
				cframe = seat * CFrame.new(0, 1.3, 1.6) * CFrame.Angles(math.rad(-10), 0, 0),
				color = "#3A2373",
				material = Enum.Material.Fabric,
				parent = parent,
			})
			Build.part({
				name = "Cushion",
				size = Vector3.new(1.5, 1.4, 0.5),
				cframe = seat
					* CFrame.new(if index % 2 == 0 then 1.8 else -1.8, 1.4, 1)
					* CFrame.Angles(math.rad(-15), 0, math.rad(8)),
				color = BALL_COLORS[(index + (if side > 0 then 2 else 0)) % #BALL_COLORS + 1],
				material = Enum.Material.Fabric,
				collide = false,
				parent = parent,
			})
		end
	end
	-- Party lights under the ceiling and space plants in the corners.
	for _, z in { -7, 7 } do
		stringLights(parent, span.from + 4, span.to - 4, z, 15.5)
	end
	for _, dx in { -19, 19 } do
		for _, z in { -13.5, 13.5 } do
			spacePlant(
				parent,
				Vector3.new(x + dx, FLOOR_Y, z),
				if dx < 0 then "#8CFF6B" else "#FF8A3D"
			)
		end
	end
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
	wallSign(
		"PlaygroundSign",
		"☀ ZERO G DODGEBALL",
		"Jump through the portal!",
		Vector3.new(18, 5, 0.4),
		CFrame.new(span.center, 3, -(WALL_Z - 0.1)),
		Enum.NormalId.Back,
		"#FFB020",
		parent
	)
end

-- Ships on show: SHOWROOM_PODIUMS turntables, each under a ceiling
-- spotlight with a plaque giving its ship's name, top speed and price. The
-- podiums cycle through every ship on the ladder (Config.Ships.ORDER), each
-- SHOWROOM_OFFSET places after the one before (IssBuilder.dressShowroom,
-- stepped by ShowroomSystem).
local SHOWROOM_PODIUMS = 3
local SHOWROOM_OFFSET = 3
local SHOWROOM_Z = 9 -- turntable centres, close to the +Z wall
local SHOWROOM_GLOW = "#FFD36B"
local SHOWROOM_TOP_GLOW = "#FF6EC8" -- the plaque of the top ship on the ladder

-- Removes a podium's ship and plaque and puts `shipId` on it instead.
local function dressPodium(podium: Instance, shipId: string)
	for _, child in podium:GetChildren() do
		if child.Name == "Display" or child.Name == "Plaque" then
			child:Destroy()
		end
	end
	local x = podium:GetAttribute("X")
	local def = Config.Ships.BY_ID[shipId]
	if type(x) ~= "number" or def == nil then
		return
	end
	podium:SetAttribute("ShipId", shipId)
	local top = Config.Ships.ORDER[#Config.Ships.ORDER] == shipId
	local glow = if top then SHOWROOM_TOP_GLOW else SHOWROOM_GLOW
	-- The ship turning above the turntable, if the models are imported.
	local source = ShipModel.find(def)
	if source then
		local ok, model = pcall(function(): Model
			return (ShipModel.fit(source, def, Vector3.new(12, 6, 12)))
		end)
		if ok and model then
			model.Name = "Display"
			model:SetAttribute("ShipId", shipId)
			model:PivotTo(CFrame.new(x, FLOOR_Y + 5, SHOWROOM_Z) * model:GetPivot())
			for _, item in model:GetDescendants() do
				if item:IsA("BasePart") then
					item.Anchored = true
					item.CanCollide = false
					if not ShipModel.textured(item) then
						item.Color = Color3.fromHex(def.paint)
					end
				end
			end
			model.Parent = podium
			spin(model, 0.35)
		end
	end
	-- The plaque on its stand at the front edge of the turntable.
	Build.sign({
		name = "Plaque",
		text = `{if top then "★ " else ""}{def.displayName}\nTop speed {def.stats.maxSpeed} · {if def.earn
			then `{Format.abbreviate(def.earn.stardust)} Stardust`
			else "Starter ship"}`,
		size = Vector3.new(7, 2.4, 0.3),
		cframe = CFrame.new(x, FLOOR_Y + 3.8, SHOWROOM_Z - 8) * CFrame.Angles(math.rad(20), 0, 0),
		faces = { Enum.NormalId.Front },
		parent = podium,
		textColor = glow,
	})
end

local function showroom(parent: Instance, span: Span)
	local podiums = Instance.new("Folder")
	podiums.Name = "ShowroomPodiums"
	podiums.Parent = parent
	for i = 1, SHOWROOM_PODIUMS do
		local x = span.center + (i - (SHOWROOM_PODIUMS + 1) / 2) * 18
		local podium = Build.model(`Podium{i}`, podiums)
		podium:SetAttribute("X", x)
		Build.part({
			name = "Turntable",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1, 13, 13),
			cframe = CFrame.new(x, FLOOR_Y + 0.5, SHOWROOM_Z) * CFrame.Angles(0, 0, math.pi / 2),
			color = "#2A2F3E",
			material = Enum.Material.Metal,
			parent = podium,
		})
		local rim = neon(
			"TurntableRim",
			Vector3.new(0.3, 13.8, 13.8),
			CFrame.new(x, FLOOR_Y + 0.15, SHOWROOM_Z) * CFrame.Angles(0, 0, math.pi / 2),
			SHOWROOM_GLOW,
			podium
		)
		rim.Shape = Enum.PartType.Cylinder
		-- A spotlight in the ceiling, pointing down at the ship.
		local fixture = Build.part({
			name = "Spotlight",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1, 2.4, 2.4),
			cframe = CFrame.new(x, TUBE_RADIUS - 2.5, SHOWROOM_Z)
				* CFrame.Angles(0, 0, math.pi / 2),
			color = "#1A1E2A",
			material = Enum.Material.Metal,
			parent = podium,
		})
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Left -- the cylinder's -X end, pointing down
		spot.Angle = 45
		spot.Range = 34
		spot.Brightness = 4
		spot.Color = Color3.fromHex(SHOWROOM_GLOW)
		spot.Shadows = false
		spot.Parent = fixture
		Build.part({
			name = "PlaqueStand",
			size = Vector3.new(0.6, 3, 0.6),
			cframe = CFrame.new(x, FLOOR_Y + 1.5, SHOWROOM_Z - 8),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = podium,
		})
	end
	IssBuilder.dressShowroom(podiums, 0)
	wallSign(
		"ShowroomSign",
		"✦ SHIP SHOWROOM",
		"Buy ships at the Shipyard",
		Vector3.new(16, 4, 0.4),
		CFrame.new(span.center, 7, WALL_Z - 0.1),
		Enum.NormalId.Front,
		"#FFD36B",
		parent
	)
end

-- Puts the ships for cycle `step` on the showroom podiums (the
-- ShowroomPodiums folder): podium i shows the ship SHOWROOM_OFFSET x (i - 1)
-- places after step's on the ladder, wrapping round.
function IssBuilder.dressShowroom(podiums: Instance, step: number)
	local order = Config.Ships.ORDER
	for i = 1, SHOWROOM_PODIUMS do
		local podium = podiums:FindFirstChild(`Podium{i}`)
		if podium then
			local index = (step + SHOWROOM_OFFSET * (i - 1)) % #order + 1
			dressPodium(podium, order[index])
		end
	end
end

local HAZARD_YELLOW, HAZARD_BLACK = "#FFC21A", "#1A1A1A"

-- The airlock opener: a heavy control post with a status screen
-- ("PRESSURIZED", "PRESS TO OPEN"), and on its sloped top a big red
-- mushroom button in a yellow hazard collar under a flipped-up glass guard.
-- Used inside ("AirlockConsole", pressurized) and out on the raid deck
-- ("AirlockReturn", vacuum). Returns the post, which carries the prompt.
local function airlockOpener(
	name: string,
	status: string,
	statusColor: Color3,
	floor: CFrame,
	parent: Instance
): Part
	local post = Build.part({
		name = name,
		size = Vector3.new(3.4, 4, 2),
		cframe = floor * CFrame.new(0, 2, 0),
		color = "#2A2F3E",
		material = Enum.Material.Metal,
		parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = post
	local screen = Instance.new("Frame")
	screen.Position = UDim2.fromScale(0.08, 0.06)
	screen.Size = UDim2.fromScale(0.84, 0.62)
	screen.BackgroundColor3 = Color3.fromRGB(8, 14, 12)
	screen.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = screen
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(HAZARD_YELLOW)
	stroke.Thickness = 5
	stroke.Parent = screen
	for _, line in
		{
			{ text = "AIRLOCK", y = 0.06, h = 0.3, color = Color3.fromHex(HAZARD_YELLOW) },
			{ text = status, y = 0.4, h = 0.22, color = statusColor },
			{ text = "PRESS TO OPEN ▼", y = 0.7, h = 0.2, color = Color3.fromRGB(255, 90, 80) },
		}
	do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.06, line.y)
		label.Size = UDim2.fromScale(0.88, line.h)
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.TextColor3 = line.color
		label.Text = line.text
		label.Parent = screen
	end
	-- The sloped top with the button.
	local top = floor * CFrame.new(0, 4.25, -0.2) * CFrame.Angles(math.rad(-25), 0, 0)
	Build.part({
		name = "OpenerTop",
		size = Vector3.new(3.4, 0.5, 2.4),
		cframe = top,
		color = HAZARD_BLACK,
		material = Enum.Material.Metal,
		parent = parent,
	})
	Build.part({
		name = "ButtonCollar",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.3, 1.9, 1.9),
		cframe = top * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = HAZARD_YELLOW,
		material = Enum.Material.SmoothPlastic,
		collide = false,
		parent = parent,
	})
	local button = neon(
		"OpenButton",
		Vector3.new(0.5, 1.3, 1.3),
		top * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#FF2A2A",
		parent
	)
	button.Shape = Enum.PartType.Cylinder
	lamp(button, "#FF2A2A", 8, 0.6)
	-- The glass guard, flipped up behind the button.
	Build.part({
		name = "ButtonGuard",
		size = Vector3.new(2.2, 0.15, 2),
		cframe = top
			* CFrame.new(0, 0.3, 1.1)
			* CFrame.Angles(math.rad(-70), 0, 0)
			* CFrame.new(0, 0, -1),
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.5,
		collide = false,
		parent = parent,
	})
	return post
end

-- The Raid Airlock: an inner pressure door with hazard-striped posts, suit
-- lockers, rotating red beacons, a pulsing floor strip, and at the far end
-- the big round outer hatch in a hazard ring. The console cycles the
-- airlock (warp to the raid deck, NavigationSystem).
local function raidAirlock(parent: Instance, span: Span)
	-- Inner door: striped posts and a warning sign across the top.
	local doorX = span.from + 5
	for _, z in { -ARCH_HALF + 2, ARCH_HALF - 2 } do
		for step = 0, 4 do
			Build.part({
				name = "HazardPost",
				size = Vector3.new(1.6, 3.6, 1.6),
				cframe = CFrame.new(doorX, FLOOR_Y + 1.8 + step * 3.6, z),
				color = if step % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK,
				material = Enum.Material.SmoothPlastic,
				parent = parent,
			})
		end
	end
	Build.sign({
		name = "AirlockWarning",
		text = "⚠ RAID AIRLOCK ⚠\nSuit up · raid deck ahead",
		size = Vector3.new(0.4, 3.4, (ARCH_HALF - 2) * 2),
		cframe = CFrame.new(doorX, FLOOR_Y + 19.7, 0),
		faces = { Enum.NormalId.Left, Enum.NormalId.Right },
		parent = parent,
		textColor = "#FF4A4A",
	})
	-- Suit lockers along the +Z wall, each with a lit visor.
	for index = 0, 3 do
		local x = doorX + 6 + index * 4
		Build.part({
			name = "SuitLocker",
			size = Vector3.new(3.4, 7, 2),
			cframe = CFrame.new(x, FLOOR_Y + 3.5, WALL_Z - 3),
			color = "#D8DCE6",
			material = Enum.Material.Metal,
			parent = parent,
		})
		neon(
			"LockerVisor",
			Vector3.new(2, 1, 0.2),
			CFrame.new(x, FLOOR_Y + 5.4, WALL_Z - 4.05),
			if index % 2 == 0 then "#5FE3FF" else "#FFB020",
			parent
		)
	end
	-- Rotating red beacons in the ceiling.
	for _, offset in { -8, 8 } do
		local beacon = neon(
			"Beacon",
			Vector3.new(1.2, 1.2, 1.2),
			CFrame.new(span.center + offset, TUBE_RADIUS - 2.5, 0),
			"#FF2A2A",
			parent
		)
		local sweep = Instance.new("SpotLight")
		sweep.Face = Enum.NormalId.Front
		sweep.Angle = 35
		sweep.Range = 30
		sweep.Brightness = 3
		sweep.Color = Color3.fromHex("#FF3030")
		sweep.Shadows = false
		sweep.Parent = beacon
		spin(beacon, 3)
	end
	-- A red strip down the floor that breathes (SpinController, GaG_Pulse).
	local strip = neon(
		"PulseStrip",
		Vector3.new(span.to - doorX - 4, 0.12, 1),
		CFrame.new((span.to + doorX) / 2, FLOOR_Y + 0.07, 0),
		"#FF4A4A",
		parent
	)
	strip:SetAttribute("PulseFrom", 0.05)
	strip:SetAttribute("PulseTo", 0.8)
	CollectionService:AddTag(strip, "GaG_Pulse")
	-- The outer hatch: a round door in a hazard-striped ring, a red
	-- porthole, and hazard stripes on the floor in front of it.
	local hatchX = span.to - 1.2
	Build.part({
		name = "OuterHatch",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1, 15, 15),
		cframe = CFrame.new(hatchX, 0, 0),
		color = "#3A3F4E",
		material = Enum.Material.Metal,
		parent = parent,
	})
	for index = 0, 11 do
		Build.part({
			name = "HatchRing",
			size = Vector3.new(0.8, 1.4, 4.6),
			cframe = CFrame.new(hatchX - 0.2, 0, 0)
				* CFrame.Angles(index / 12 * 2 * math.pi, 0, 0)
				* CFrame.new(0, 8.2, 0),
			color = if index % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK,
			material = Enum.Material.SmoothPlastic,
			parent = parent,
		})
	end
	local porthole =
		neon("Porthole", Vector3.new(0.4, 3, 3), CFrame.new(hatchX - 0.6, 2, 0), "#FF4A4A", parent)
	porthole.Shape = Enum.PartType.Cylinder
	lamp(porthole, "#FF4A4A", 30, 0.8)
	for index = 0, 4 do
		Build.part({
			name = "FloorHazard",
			size = Vector3.new(1.2, 0.1, 16),
			cframe = CFrame.new(hatchX - 3 - index * 1.2, FLOOR_Y + 0.06, 0),
			color = if index % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK,
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = parent,
		})
	end
	-- The airlock opener and the pressure readout above it.
	local console = airlockOpener(
		"AirlockConsole",
		"● PRESSURIZED",
		Color3.fromRGB(90, 255, 140),
		wallSpot(span.center + 4),
		parent
	)
	Build.prompt(
		console,
		{ action = "Open the airlock", object = "Airlock Control", warp = "DockingArea" }
	)
	wallSign(
		"PressureSign",
		"⚠ CYCLE TO EXIT",
		"The raid deck is outside",
		Vector3.new(14, 4, 0.4),
		CFrame.new(span.center + 4, 3, -(WALL_Z - 0.1)),
		Enum.NormalId.Back,
		"#FF8A3D",
		parent
	)
	Build.marker(
		"AirlockInside",
		CFrame.lookAt(
			Vector3.new(span.center, FLOOR_Y + 3, 4),
			Vector3.new(span.from, FLOOR_Y + 3, 4)
		),
		parent
	)
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
			CFrame.new(span.center, 3, WALL_Z),
			Enum.NormalId.Front,
			"ISS Directory",
			table.concat({
				"◀ <b>Cupola</b> · the view",
				"◀ <b>Star Lounge</b> · leaderboards, Daily Spin",
				"▶ <b>Central Hub</b> · signs to everything",
				"▶ <b>Dodgeball</b> · <b>Showroom</b> · <b>Raid Airlock</b>",
			}, "\n"),
			"#4FC3F7",
			parent
		)
		wallSign(
			"Welcome",
			"🚀 WELCOME, PILOT!",
			"Launch your ship · grow your galaxy",
			Vector3.new(20, 5, 0.4),
			CFrame.new(span.center, 3, -(WALL_Z - 0.1)),
			Enum.NormalId.Back,
			"#4FC3F7",
			parent
		)
	elseif def.id == "Lounge" then
		lounge(parent, span)
	elseif def.id == "Hub" then
		hub(parent, span)
	elseif def.id == "Playground" then
		playground(parent, span)
	elseif def.id == "Showroom" then
		showroom(parent, span)
	elseif def.id == "RaidAirlock" then
		raidAirlock(parent, span)
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
				-- Three panels with gaps, like the real accordion blankets.
				for panel = 0, 2 do
					Build.part({
						name = "SolarArray",
						size = Vector3.new(23, 0.3, 11),
						cframe = CFrame.new(side * (18 + panel * 24.5), TRUSS_Y, z + offset)
							* CFrame.Angles(math.rad(25), 0, 0),
						color = COLORS.solar,
						material = Enum.Material.Glass,
						collide = false,
						parent = parent,
					})
				end
				Build.part({
					name = "BlanketBox",
					size = Vector3.new(4, 1.4, 11.5),
					cframe = CFrame.new(side * 5.5, TRUSS_Y, z + offset)
						* CFrame.Angles(math.rad(25), 0, 0),
					color = "#C9A24A",
					material = Enum.Material.Foil,
					collide = false,
					parent = parent,
				})
			end
		end
	end

	-- Radiators hang below the truss, clear of the modules.
	for _, z in { -62, 62 } do
		for panel = -1, 1 do
			Build.part({
				name = "Radiator",
				size = Vector3.new(0.4, 22, 9),
				cframe = CFrame.new(0, TRUSS_Y - 2.5 - 11, z + panel * 9.8),
				color = COLORS.radiator,
				collide = false,
				parent = parent,
			})
		end
	end

	-- The robot arm, folded on the truss, and a comms dish on a short mast.
	local shoulder = CFrame.new(0, TRUSS_Y + 4, -40)
	local elbow = shoulder * CFrame.new(0, 0, 26)
	Build.part({
		name = "ArmBoom",
		size = Vector3.new(2, 2, 26),
		cframe = shoulder * CFrame.new(0, 0, 13),
		color = "#E8E8E8",
		parent = parent,
	})
	Build.part({
		name = "ArmBoom",
		size = Vector3.new(2, 2, 24),
		cframe = elbow * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0, -12),
		color = "#E8E8E8",
		parent = parent,
	})
	for _, joint in { shoulder, elbow } do
		Build.part({
			name = "ArmJoint",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 3.2,
			cframe = joint,
			color = "#3A3F4E",
			material = Enum.Material.Metal,
			parent = parent,
		})
	end
	local dishAt = CFrame.new(0, TRUSS_Y + 13, 60) * CFrame.Angles(0, 0, math.rad(60))
	Build.part({
		name = "DishMast",
		size = Vector3.new(1, 10, 1),
		cframe = CFrame.new(0, TRUSS_Y + 7.5, 60),
		color = COLORS.truss,
		parent = parent,
	})
	Build.part({
		name = "Dish",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1, 12, 12),
		cframe = dishAt,
		color = "#F2F2F2",
		parent = parent,
	})
	local feed =
		neon("DishFeed", Vector3.one * 1.2, dishAt * CFrame.new(3, 0, 0), "#FF4A4A", parent)
	feed.Shape = Enum.PartType.Ball
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
	local console = airlockOpener(
		"AirlockReturn",
		"● VACUUM",
		Color3.fromRGB(110, 190, 255),
		CFrame.new(x0 + 20, FLOOR_Y, -12) * CFrame.Angles(0, math.pi, 0),
		parent
	)
	Build.prompt(
		console,
		{ action = "Open the airlock", object = "Airlock Control", warp = "Interior" }
	)
	wallSign(
		"RaidSign",
		"☠ DEATH STAR RAIDS",
		"Step on a glowing pad to join",
		Vector3.new(30, 7, 0.4),
		CFrame.new(x0 + 40, FLOOR_Y + 9, -24),
		Enum.NormalId.Back,
		"#FF4A4A",
		parent
	)
end

-- A collar round the hull where two modules meet (gold foil and metal),
-- like the real station's berthing rings.
local function collar(parent: Instance, x: number)
	local width = 2 * (TUBE_RADIUS + 2.2) * math.tan(math.pi / TUBE_SIDES) + 0.3
	for i = 0, TUBE_SIDES - 1 do
		local angle = (i + 0.5) / TUBE_SIDES * 2 * math.pi
		Build.part({
			name = "Collar",
			size = Vector3.new(3, 1.6, width),
			cframe = CFrame.new(x, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, TUBE_RADIUS + 1.6, 0),
			color = if i % 2 == 0 then "#C9A24A" else "#9AA3B5",
			material = if i % 2 == 0 then Enum.Material.Foil else Enum.Material.Metal,
			collide = false,
			parent = parent,
		})
	end
end

-- The gravity wheel: a ring of habitat pods on spokes, turning round the
-- hull on the station's long axis (SpinController, SpinAxis "X"). Scenery:
-- anchored, not collidable, turned on each client.
local function gravityWheel(parent: Instance, x: number)
	local wheel = Build.model("GravityWheel", parent)
	local around = CFrame.new(x, 0, 0)
	local tangent = 2 * WHEEL_RADIUS * math.tan(math.pi / WHEEL_SEGMENTS) + 0.4
	for i = 0, WHEEL_SEGMENTS - 1 do
		local pod = around
			* CFrame.Angles(i / WHEEL_SEGMENTS * 2 * math.pi, 0, 0)
			* CFrame.new(0, WHEEL_RADIUS, 0)
		Build.part({
			name = "Habitat",
			size = Vector3.new(WHEEL_WIDTH, 9, tangent),
			cframe = pod,
			color = if i % 2 == 0 then dim(COLORS.hull) else dim(COLORS.hullAlt),
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = wheel,
		})
		-- Lit windows down both faces: the rooms where "down" is outwards.
		for _, side in { -1, 1 } do
			neon(
				"HabWindow",
				Vector3.new(0.3, 2.2, tangent - 4),
				pod * CFrame.new(side * (WHEEL_WIDTH / 2 + 0.1), 0.8, 0),
				if i % 3 == 0 then "#FFE6A3" else "#9FD8FF",
				wheel
			)
		end
		if i % 2 == 0 then
			neon(
				"RimLight",
				Vector3.new(WHEEL_WIDTH - 2, 0.4, 1.2),
				pod * CFrame.new(0, 4.6, 0),
				"#4FC3F7",
				wheel
			)
		end
	end
	-- The hub: a bearing collar clear of the hull, turning with the wheel.
	local hubRadius = TUBE_RADIUS + 5
	local hubWidth = 2 * (hubRadius + 1) * math.tan(math.pi / 12) + 0.3
	for i = 0, 11 do
		Build.part({
			name = "Hub",
			size = Vector3.new(WHEEL_WIDTH - 4, 2, hubWidth),
			cframe = around
				* CFrame.Angles(i / 12 * 2 * math.pi, 0, 0)
				* CFrame.new(0, hubRadius, 0),
			color = "#3A3F4E",
			material = Enum.Material.Metal,
			collide = false,
			parent = wheel,
		})
	end
	-- Spokes: crawl tubes from the hub to the rim, each with a lift light.
	local spokeLength = WHEEL_RADIUS - 4.5 - hubRadius - 1
	for i = 0, WHEEL_SPOKES - 1 do
		local middle = around
			* CFrame.Angles((i + 0.5) / WHEEL_SPOKES * 2 * math.pi, 0, 0)
			* CFrame.new(0, hubRadius + 1 + spokeLength / 2, 0)
		Build.part({
			name = "Spoke",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(spokeLength, 4.5, 4.5),
			cframe = middle * CFrame.Angles(0, 0, math.pi / 2),
			color = COLORS.hullAlt,
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = wheel,
		})
		neon(
			"SpokeLight",
			Vector3.new(0.6, spokeLength - 4, 0.6),
			middle * CFrame.new(2.3, 0, 0),
			"#FFB020",
			wheel
		)
	end
	wheel:SetAttribute("SpinAxis", "X")
	spin(wheel, WHEEL_SPIN)
end

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
	for index = 2, #MODULES do
		collar(hull, spans[MODULES[index].id].from)
	end
	gravityWheel(model, spans.Lounge.to)

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

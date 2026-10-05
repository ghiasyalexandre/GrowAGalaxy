--!strict
-- Hangar upgrade geometry (Config.Hangar), built on a station deck by
-- HangarSystem. Two forms per upgrade, both standing on the floor point
-- `floor` (station space, so -Z faces the berth):
--   pad(def, floor)        a glowing red ground circle with a sign above it
--                          (name, what it does, cost) and a "Build" prompt.
--                          The circle part is named "Circle".
--   structure(def, floor)  the finished building, with a small name plate
--                          (none for one built at its `site`, off its pad).
-- Both return a Model; the caller parents it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Build = require(script.Parent.Build)
local HangarConfig = require(ReplicatedStorage.Shared.Config.Hangar)

local COLORS = Config.World.COLORS
local H = Config.Hangar

type HangarDef = HangarConfig.HangarDef

local HangarBuilder = {}

local function flat(
	name: string,
	radius: number,
	height: number,
	floor: CFrame,
	color: string,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, radius * 2, radius * 2),
		cframe = floor * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
end

-- An upright cylinder of `height` standing on `floor`.
local function column(
	name: string,
	diameter: number,
	height: number,
	floor: CFrame,
	color: string,
	material: Enum.Material?,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = floor * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material or Enum.Material.Metal,
		parent = parent,
	})
end

local function box(
	name: string,
	size: Vector3,
	where: CFrame,
	color: string,
	material: Enum.Material?,
	parent: Instance
): Part
	return Build.part({
		name = name,
		size = size,
		cframe = where,
		color = color,
		material = material or Enum.Material.Metal,
		parent = parent,
	})
end

local function glow(
	name: string,
	size: Vector3,
	where: CFrame,
	color: string,
	parent: Instance
): Part
	return Build.part({
		name = name,
		size = size,
		cframe = where,
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
end

local function light(part: BasePart, color: string, range: number)
	local point = Instance.new("PointLight")
	point.Color = Color3.fromHex(color)
	point.Range = range
	point.Brightness = 1.5
	point.Shadows = false
	point.Parent = part
end

local function textLine(
	parent: Instance,
	text: string,
	y: number,
	height: number,
	size: number,
	color: Color3,
	font: Enum.Font
)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.Font = font
	label.TextWrapped = true
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
end

function HangarBuilder.pad(def: HangarDef, floor: CFrame): Model
	local model = Instance.new("Model")
	model.Name = def.id
	local radius = H.PAD_RADIUS

	-- Outer glowing ring, dark inner disc, bright centre dot.
	local circle = flat("Circle", radius, 0.25, floor, H.PAD_COLOR, model)
	circle.Transparency = 0.1
	circle.CanTouch = true
	circle.CanCollide = false
	local inner = flat("Inner", radius - 0.7, 0.3, floor, "#4A0C0C", model)
	inner.Material = Enum.Material.SmoothPlastic
	flat("Dot", 0.9, 0.35, floor, "#FFB0A0", model)
	light(circle, H.PAD_COLOR, 12)

	-- The sign: name, what it does, price.
	local anchor = Build.marker("SignAnchor", floor * CFrame.new(0, 6, 0), model)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(240, 96)
	sign.LightInfluence = 0
	sign.MaxDistance = H.SIGN_DISTANCE
	sign.Adornee = anchor
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
	panel.BackgroundTransparency = 0.2
	panel.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(H.PAD_COLOR)
	stroke.Thickness = 2
	stroke.Parent = panel
	textLine(
		panel,
		def.displayName,
		6,
		24,
		20,
		Color3.fromRGB(255, 214, 110),
		Enum.Font.GothamBlack
	)
	textLine(panel, def.effect, 32, 32, 14, Color3.fromRGB(235, 240, 255), Enum.Font.GothamBold)
	textLine(
		panel,
		`{Format.abbreviate(def.cost)} {Config.Economy.CURRENCY_NAME}  ·  step on to build`,
		68,
		22,
		14,
		Color3.fromHex(H.PAD_COLOR):Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Font.GothamBold
	)
	sign.Parent = anchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuildPrompt"
	prompt.ActionText = `Build ({Format.abbreviate(def.cost)})`
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = circle

	model:SetAttribute("State", "pad")
	model:SetAttribute("UpgradeId", def.id)
	return model
end

local builders: { [string]: (Model, CFrame) -> () } = {}

-- Two tall silos with gold bands and domes, joined by a pipe.
builders.StardustSilo = function(model, floor)
	for _, x in { -2.6, 2.6 } do
		local base = floor * CFrame.new(x, 0, 0)
		column("Silo", 4.4, 11, base, COLORS.hull, nil, model)
		for _, y in { 3, 7 } do
			column(
				"Band",
				4.6,
				0.5,
				base * CFrame.new(0, y, 0),
				"#FFD36B",
				Enum.Material.Neon,
				model
			).CanCollide =
				false
		end
		Build.part({
			name = "Dome",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 4.4,
			cframe = base * CFrame.new(0, 11, 0),
			color = COLORS.hullAlt,
			parent = model,
		})
	end
	box("Pipe", Vector3.new(3, 0.8, 0.8), floor * CFrame.new(0, 8.5, 0), COLORS.truss, nil, model)
	local core =
		glow("Core", Vector3.new(1.2, 6, 1.2), floor * CFrame.new(0, 3, -2.6), "#FFD36B", model)
	light(core, "#FFD36B", 14)
end

-- Three horizontal fuel tanks on cradles with hazard bands.
builders.FuelDepot = function(model, floor)
	for i, z in { -3.4, 0, 3.4 } do
		local y = if i == 2 then 4.6 else 2
		Build.part({
			name = "Tank",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(9, 3, 3),
			cframe = floor * CFrame.new(0, y, z),
			color = "#D9DDE3",
			material = Enum.Material.Metal,
			parent = model,
		})
		for _, x in { -3, 3 } do
			Build.part({
				name = "Hazard",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.6, 3.15, 3.15),
				cframe = floor * CFrame.new(x, y, z),
				color = "#F2C230",
				material = Enum.Material.SmoothPlastic,
				collide = false,
				parent = model,
			})
		end
	end
	for _, x in { -3, 3 } do
		box(
			"Cradle",
			Vector3.new(1, 1, 10),
			floor * CFrame.new(x, 0.5, 0),
			COLORS.truss,
			nil,
			model
		)
	end
	local valve = glow(
		"Valve",
		Vector3.new(0.8, 0.8, 0.8),
		floor * CFrame.new(-4.8, 4.6, 0),
		"#7FD4FF",
		model
	)
	light(valve, "#7FD4FF", 10)
end

-- A refinery block with a chimney, glowing gold pipes and a window.
builders.Refinery = function(model, floor)
	box("Building", Vector3.new(9, 6, 8), floor * CFrame.new(0, 3, 0), COLORS.hullAlt, nil, model)
	box("Roof", Vector3.new(9.6, 0.6, 8.6), floor * CFrame.new(0, 6.3, 0), COLORS.truss, nil, model)
	column("Chimney", 1.8, 6, floor * CFrame.new(2.6, 6.6, 2), COLORS.hull, nil, model)
	glow(
		"ChimneyGlow",
		Vector3.new(1.9, 0.4, 1.9),
		floor * CFrame.new(2.6, 12.4, 2),
		"#FFB347",
		model
	)
	Build.part({
		name = "Window",
		size = Vector3.new(5, 2, 0.2),
		cframe = floor * CFrame.new(0, 3.6, -4.05),
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.3,
		parent = model,
	})
	for _, y in { 1.4, 2.4 } do
		glow("Pipe", Vector3.new(0.5, 0.5, 8.4), floor * CFrame.new(-4.8, y, 0), "#FFD36B", model)
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 4)
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Size = NumberSequence.new(1, 3)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
	smoke.EmissionDirection = Enum.NormalId.Top
	local top = model:FindFirstChild("ChimneyGlow") :: BasePart
	smoke.Parent = top
	light(top, "#FFB347", 12)
end

-- A cooling tower narrowing then flaring, with cyan vents and steam.
builders.CoolingTower = function(model, floor)
	local diameters = { 7, 6.2, 5.4, 5, 5.2, 5.8 }
	for i, d in diameters do
		column(
			"Shell",
			d,
			2,
			floor * CFrame.new(0, (i - 1) * 2, 0),
			"#C9CED6",
			Enum.Material.Concrete,
			model
		)
	end
	local rim =
		column("Vent", 6, 0.4, floor * CFrame.new(0, 12, 0), "#5FE3FF", Enum.Material.Neon, model)
	rim.CanCollide = false
	for _, angle in { 0, 120, 240 } do
		local dir = CFrame.Angles(0, math.rad(angle), 0)
		glow(
			"VentSlit",
			Vector3.new(1.4, 0.4, 0.2),
			floor * dir * CFrame.new(0, 1.5, -3.55),
			"#5FE3FF",
			model
		)
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Rate = 8
	steam.Speed = NumberRange.new(3, 6)
	steam.Lifetime = NumberRange.new(2, 3.5)
	steam.Size = NumberSequence.new(2, 5)
	steam.Transparency = NumberSequence.new(0.4, 1)
	steam.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255))
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Parent = rim
	light(rim, "#5FE3FF", 14)
end

-- A glass dome lab with a laser antenna.
builders.MiningLab = function(model, floor)
	column("Base", 9, 1, floor, COLORS.hullAlt, nil, model)
	Build.part({
		name = "Dome",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 8,
		cframe = floor * CFrame.new(0, 1, 0),
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.4,
		parent = model,
	})
	column("Crystal", 1.6, 3, floor * CFrame.new(0, 1, 0), "#B06BFF", Enum.Material.Neon, model).CanCollide =
		false
	column("Mast", 0.6, 6, floor * CFrame.new(2.8, 4, 2.8), COLORS.truss, nil, model)
	local tip =
		glow("LaserTip", Vector3.new(1, 1, 1), floor * CFrame.new(2.8, 10.4, 2.8), "#FF6A3D", model)
	light(tip, "#FF6A3D", 10)
	light(model:FindFirstChild("Crystal") :: BasePart, "#B06BFF", 14)
end

-- An open workshop frame with an armour rack and a welding arm throwing sparks.
builders.ArmorWorkshop = function(model, floor)
	for _, x in { -4.5, 4.5 } do
		for _, z in { -4, 4 } do
			box(
				"Post",
				Vector3.new(0.8, 7, 0.8),
				floor * CFrame.new(x, 3.5, z),
				COLORS.truss,
				nil,
				model
			)
		end
	end
	box("Roof", Vector3.new(10, 0.6, 9), floor * CFrame.new(0, 7.3, 0), COLORS.hullAlt, nil, model)
	glow("RoofStrip", Vector3.new(8, 0.2, 0.4), floor * CFrame.new(0, 6.9, 0), "#FFB347", model)
	for i = -1, 1 do
		box(
			"Plate",
			Vector3.new(2.2, 3.2, 0.3),
			floor * CFrame.new(i * 2.6, 2, 3.4),
			"#8A93A3",
			nil,
			model
		)
	end
	box(
		"ArmBase",
		Vector3.new(1.6, 1.4, 1.6),
		floor * CFrame.new(-2, 0.7, -1.5),
		"#F2C230",
		nil,
		model
	)
	box(
		"Arm",
		Vector3.new(0.7, 4, 0.7),
		floor * CFrame.new(-2, 3, -1.5) * CFrame.Angles(0, 0, math.rad(-25)),
		"#F2C230",
		nil,
		model
	)
	local torch = glow(
		"Torch",
		Vector3.new(0.6, 0.6, 0.6),
		floor * CFrame.new(-1.1, 4.9, -1.5),
		"#FFF4D6",
		model
	)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 25
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
	sparks.LightEmission = 1
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Parent = torch
	light(torch, "#FFC870", 10)
end

-- Vanity -------------------------------------------------------------------

local SPIN_TAG = "GaG_Spin"
local PULSE_TAG = "GaG_Pulse"

local function spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, SPIN_TAG)
end

local function pulse(part: BasePart, from: number, to: number)
	part:SetAttribute("PulseFrom", from)
	part:SetAttribute("PulseTo", to)
	CollectionService:AddTag(part, PULSE_TAG)
end

-- Floating chevrons leading in to the berth (which is towards +Z from here),
-- flanked by two rows of edge lights.
builders.NeonRunway = function(model, floor)
	for i = 0, 7 do
		local z = -i * 12
		local fade = i / 8
		for _, side in { -1, 1 } do
			local arm = glow(
				"Chevron",
				Vector3.new(6, 0.4, 1.2),
				floor * CFrame.new(side * 2.6, 0, z) * CFrame.Angles(0, side * math.rad(-35), 0),
				"#5FE3FF",
				model
			)
			arm.Transparency = 0.1 + fade * 0.5
			pulse(arm, 0.05 + fade * 0.4, 0.6 + fade * 0.3)
			local edge = glow(
				"EdgeLight",
				Vector3.one * 1.2,
				floor * CFrame.new(side * 14, 0, z),
				"#FFD36B",
				model
			)
			edge.Shape = Enum.PartType.Ball
		end
	end
	light(model:FindFirstChild("Chevron") :: BasePart, "#5FE3FF", 30)
end

-- A spinning galaxy hologram: a glowing core, two tilted spiral arms of stars
-- and a faint disc, over a projector ring on the deck below.
builders.HoloGalaxy = function(model, floor)
	local holo = Instance.new("Model")
	holo.Name = "Hologram"
	holo.Parent = model
	local core = Build.part({
		name = "Core",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 3,
		cframe = floor,
		color = "#FFE6A3",
		material = Enum.Material.Neon,
		collide = false,
		parent = holo,
	})
	light(core, "#B06BFF", 24)
	local disc = Build.part({
		name = "Disc",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 22, 22),
		cframe = floor * CFrame.Angles(0, 0, math.pi / 2),
		color = "#8C6BFF",
		material = Enum.Material.ForceField,
		transparency = 0.2,
		collide = false,
		parent = holo,
	})
	disc.CastShadow = false
	local colors = { "#5FE3FF", "#B06BFF", "#FF6EC8", "#FFE6A3" }
	for arm = 0, 1 do
		for step = 1, 14 do
			local angle = arm * math.pi + step * 0.42
			local radius = 1.6 + step * 0.65
			local star = Build.part({
				name = "Star",
				shape = Enum.PartType.Ball,
				size = Vector3.one * (0.9 - step * 0.035),
				cframe = floor * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
				color = colors[(step + arm) % #colors + 1],
				material = Enum.Material.Neon,
				collide = false,
				parent = holo,
			})
			star.CastShadow = false
		end
	end
	holo.PrimaryPart = core
	spin(holo, 0.35)
	-- The projector on the deck below, beaming up.
	local site = model:GetAttribute("SiteHeight")
	local down = if type(site) == "number" then site else 16
	local projector = glow(
		"Projector",
		Vector3.new(0.4, 6, 6),
		floor * CFrame.new(0, -down + 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#B06BFF",
		model
	)
	projector.Shape = Enum.PartType.Cylinder
	local beam = glow(
		"Beam",
		Vector3.new(down - 2, 3, 3),
		floor * CFrame.new(0, -down / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#B06BFF",
		model
	)
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.85
	pulse(beam, 0.75, 0.92)
end

-- A tall spire with rings turning around it and a beacon on top.
builders.VictorySpire = function(model, floor)
	box("Base", Vector3.new(12, 2, 12), floor * CFrame.new(0, 1, 0), COLORS.hullAlt, nil, model)
	for i, d in { 6, 5, 4, 3, 2.2 } do
		column("Spire", d, 9, floor * CFrame.new(0, 2 + (i - 1) * 9, 0), COLORS.hull, nil, model)
	end
	for i, y in { 12, 24, 36 } do
		local ring = Instance.new("Model")
		ring.Name = `Ring{i}`
		ring.Parent = model
		for s = 0, 7 do
			local angle = s / 8 * 2 * math.pi
			glow(
				"Segment",
				Vector3.new(2.6, 0.4, 0.6),
				floor
					* CFrame.new(0, y, 0)
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, 0, -(4 + i)),
				if i % 2 == 0 then "#FFD36B" else "#5FE3FF",
				ring
			)
		end
		ring.WorldPivot = floor * CFrame.new(0, y, 0)
		spin(ring, if i % 2 == 0 then -0.5 else 0.4)
	end
	local beacon = glow("Beacon", Vector3.one * 4, floor * CFrame.new(0, 49, 0), "#FFD36B", model)
	beacon.Shape = Enum.PartType.Ball
	pulse(beacon, 0, 0.5)
	light(beacon, "#FFD36B", 60)
	local sky = Instance.new("Attachment")
	sky.Position = Vector3.new(0, 400, 0)
	sky.Parent = beacon
	local base = Instance.new("Attachment")
	base.Parent = beacon
	local ray = Instance.new("Beam")
	ray.Attachment0 = base
	ray.Attachment1 = sky
	ray.Width0 = 3
	ray.Width1 = 0.5
	ray.FaceCamera = true
	ray.LightEmission = 1
	ray.Color = ColorSequence.new(Color3.fromHex("#FFD36B"))
	ray.Transparency = NumberSequence.new(0.3, 1)
	ray.Parent = beacon
end

-- An open platform off the deck's side with three lit cradles; HangarSystem
-- puts the player's chosen ships on them (parts named "Cradle1".."Cradle3",
-- their tops are where a ship's bottom sits).
builders.ShowcaseDock = function(model, floor)
	box(
		"Platform",
		Vector3.new(30, 1.4, 66),
		floor * CFrame.new(0, -0.7, 0),
		COLORS.deck,
		Enum.Material.DiamondPlate,
		model
	)
	box(
		"Bridge",
		Vector3.new(12, 1, 8),
		floor * CFrame.new(-21, -0.5, 0),
		COLORS.deck,
		Enum.Material.DiamondPlate,
		model
	)
	for _, side in { -1, 1 } do
		glow(
			"EdgeStrip",
			Vector3.new(0.5, 0.2, 64),
			floor * CFrame.new(side * 14.5, 0.1, 0),
			"#FFD36B",
			model
		)
	end
	for index, z in { -21, 0, 21 } do
		local cradle = column(
			`Cradle{index}`,
			12,
			1,
			floor * CFrame.new(0, 0, z),
			COLORS.hullAlt,
			Enum.Material.Metal,
			model
		)
		cradle.Name = `Cradle{index}`
		local rim = flat("CradleGlow", 6.4, 0.2, floor * CFrame.new(0, 1, z), "#5FE3FF", model)
		pulse(rim, 0.1, 0.6)
		light(rim, "#5FE3FF", 22)
	end
	local sign = Build.sign({
		name = "DockSign",
		text = "SHOWCASE",
		size = Vector3.new(16, 3, 0.4),
		cframe = floor * CFrame.new(-14.6, 6, 0) * CFrame.Angles(0, math.pi / 2, 0),
		faces = { Enum.NormalId.Front, Enum.NormalId.Back },
		parent = model,
		textColor = "#FFD36B",
	})
	sign.CanCollide = false
end

function HangarBuilder.structure(def: HangarDef, floor: CFrame): Model
	local model = Instance.new("Model")
	model.Name = def.id
	local site = def.site
	if site and site.y then
		model:SetAttribute("SiteHeight", site.y)
	end
	local build = builders[def.id]
	if build then
		build(model, floor)
	else
		box(
			"Building",
			Vector3.new(8, 5, 8),
			floor * CFrame.new(0, 2.5, 0),
			COLORS.hullAlt,
			nil,
			model
		)
	end
	model:SetAttribute("State", "built")
	model:SetAttribute("UpgradeId", def.id)
	if site then
		-- Built away from its pad: no name plate on the deck.
		return model
	end
	-- Name plate at the front edge, facing the deck's centre line.
	local plate = Build.sign({
		name = "Plate",
		text = `{def.displayName}\n{def.effect}`,
		size = Vector3.new(7, 1.6, 0.3),
		cframe = floor * CFrame.new(0, 0.8, -6.2),
		faces = { Enum.NormalId.Front },
		parent = model,
		textColor = "#FFD36B",
	})
	plate.CanCollide = false
	model:SetAttribute("State", "built")
	model:SetAttribute("UpgradeId", def.id)
	return model
end

return HangarBuilder

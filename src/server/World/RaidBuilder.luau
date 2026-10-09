--!strict
-- Raid geometry (Config.Raids), built by RaidSystem.
--
--   beacon(floor)      the Saturn V from ServerStorage/Assets/Stuff/SaturnV,
--                      cleaned (its scripts, click detectors, sounds and
--                      humanoids removed, every part anchored), scaled to
--                      BEACON_HEIGHT and stood upright on `floor`, wrapped in
--                      glow: spinning neon rings, a light beam to the sky,
--                      rising sparkles and lights. A greybox rocket stands in
--                      without the asset.
--   pad(def, floor)    a difficulty pad: a glowing circle ("Circle", with a
--                      "JoinPrompt") under a pulsing light column, and a sign
--                      whose "Queue" and "Status" labels RaidSystem updates.
--   boss(center)       the Death Star from ServerStorage/Assets/Bosses/
--                      DeathStar (a grey sphere without it), BOSS_SIZE across,
--                      with a glowing green "WeakPoint" disc (and an always-
--                      on-top target marker) facing -Z, where raiders start.
--   placeWeakPoint     moves the weak point to a direction on the hull.
--   drone(position)    a homing drone: a glowing red core trailing fire.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local RaidsConfig = require(ReplicatedStorage.Shared.Config.Raids)

local R = Config.Raids
local SPIN_TAG = "GaG_Spin"
local BEAM_COLORS =
	{ Color3.fromRGB(95, 227, 255), Color3.fromRGB(176, 120, 255), Color3.fromRGB(255, 110, 200) }

type DifficultyDef = RaidsConfig.DifficultyDef

local RaidBuilder = {}

local function asset(folder: string, name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local holder = assets and assets:FindFirstChild(folder)
	return holder and holder:FindFirstChild(name)
end

local function spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, SPIN_TAG)
end

local function neon(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: string,
	parent: Instance
): Part
	local part = Build.part({
		name = name,
		shape = shape,
		size = size,
		cframe = cframe,
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
	return part
end

local function lamp(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- Removes everything that could run code, make noise or be clicked, and
-- anchors the rest: the rocket is scenery.
local function clean(model: Instance)
	for _, item in model:GetDescendants() do
		if
			item:IsA("LuaSourceContainer")
			or item:IsA("ClickDetector")
			or item:IsA("Sound")
			or item:IsA("Humanoid")
			or item:IsA("ProximityPrompt")
		then
			item:Destroy()
		end
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanTouch = false
			item.CastShadow = false
		elseif item:IsA("JointInstance") or item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end
end

local function greyboxRocket(floor: CFrame, parent: Instance): Model
	local model = Build.model("SaturnV", parent)
	local h = R.BEACON_HEIGHT
	for i, stage in
		{
			{ d = 18, from = 0, to = 0.45 },
			{ d = 18, from = 0.45, to = 0.7 },
			{ d = 12, from = 0.7, to = 0.88 },
		}
	do
		local height = (stage.to - stage.from) * h
		Build.part({
			name = `Stage{i}`,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(height, stage.d, stage.d),
			cframe = floor
				* CFrame.new(0, stage.from * h + height / 2, 0)
				* CFrame.Angles(0, 0, math.pi / 2),
			color = if i % 2 == 1 then "#F2F2F2" else "#2B2B2B",
			parent = model,
		})
	end
	Build.part({
		name = "Tip",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 10,
		cframe = floor * CFrame.new(0, 0.9 * h, 0),
		color = "#F2F2F2",
		parent = model,
	})
	return model
end

function RaidBuilder.beacon(floor: CFrame, parent: Instance): Model
	local root = Build.model("RaidBeacon", parent)
	local source = asset("Stuff", "SaturnV")
	local rocket: Model? = nil
	if source and source:IsA("Model") then
		local ok, result = pcall(function()
			local copy = source:Clone()
			clean(copy)
			local _, size = copy:GetBoundingBox()
			copy:ScaleTo(copy:GetScale() * R.BEACON_HEIGHT / math.max(size.Y, 1))
			local box, scaled = copy:GetBoundingBox()
			-- Stand it with the bottom of its box on the floor, centred.
			local offset = box:ToObjectSpace(copy:GetPivot())
			copy:PivotTo(floor * CFrame.new(0, scaled.Y / 2, 0) * offset)
			copy.Name = "SaturnV"
			copy.Parent = root
			return copy
		end)
		if ok then
			rocket = result
		else
			warn(`[RaidBuilder] Could not place the Saturn V: {result}`)
		end
	end
	if rocket == nil then
		rocket = greyboxRocket(floor, root)
	end

	-- Glow: rings on the floor turning both ways, a beam into the sky,
	-- sparkles rising around the base.
	for i, ring in
		{
			{ r = 26, color = "#5FE3FF", speed = 0.3 },
			{ r = 34, color = "#B06BFF", speed = -0.2 },
			{ r = 42, color = "#FF6EC8", speed = 0.15 },
		}
	do
		local holder = Build.model(`GlowRing{i}`, root)
		local segments = 24
		local length = 2 * ring.r * math.tan(math.pi / segments) + 0.4
		for s = 0, segments - 1 do
			local angle = s / segments * 2 * math.pi
			if s % 2 == 0 then
				neon(
					"Segment",
					Enum.PartType.Block,
					Vector3.new(length, 0.3, 1),
					floor * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.2 + i * 0.05, -ring.r),
					ring.color,
					holder
				)
			end
		end
		holder.WorldPivot = floor
		spin(holder, ring.speed)
	end
	local base = neon(
		"BeaconBase",
		Enum.PartType.Cylinder,
		Vector3.new(0.4, 22, 22),
		floor * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#5FE3FF",
		root
	)
	base.Transparency = 0.4
	lamp(base, Color3.fromRGB(120, 200, 255), 60, 3)
	local top = Build.marker("BeamTop", floor * CFrame.new(0, R.BEACON_HEIGHT * 2.5, 0), root)
	local a0 = Instance.new("Attachment")
	a0.Parent = base
	local a1 = Instance.new("Attachment")
	a1.Parent = top
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 30
	beam.Width1 = 8
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(BEAM_COLORS[1], BEAM_COLORS[2])
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = base
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 25
	sparkles.Lifetime = NumberRange.new(3, 5)
	sparkles.Speed = NumberRange.new(10, 22)
	sparkles.SpreadAngle = Vector2.new(25, 25)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Size = NumberSequence.new(2, 0)
	sparkles.Color = ColorSequence.new(BEAM_COLORS[1], BEAM_COLORS[3])
	sparkles.LightEmission = 1
	sparkles.Parent = a0
	return root
end

function RaidBuilder.pad(def: DifficultyDef, floor: CFrame, parent: Instance): Model
	local model = Build.model(def.id, parent)
	local radius = R.PAD_RADIUS
	local circle = neon(
		"Circle",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, radius * 2, radius * 2),
		floor * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
		def.color,
		model
	)
	circle.CanTouch = true
	neon(
		"Inner",
		Enum.PartType.Cylinder,
		Vector3.new(0.35, radius * 1.6, radius * 1.6),
		floor * CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"#101018",
		model
	).Material =
		Enum.Material.SmoothPlastic
	local column = neon(
		"LightColumn",
		Enum.PartType.Cylinder,
		Vector3.new(28, radius * 1.8, radius * 1.8),
		floor * CFrame.new(0, 14, 0) * CFrame.Angles(0, 0, math.pi / 2),
		def.color,
		model
	)
	column.Transparency = 0.82
	column:SetAttribute("PulseFrom", 0.7)
	column:SetAttribute("PulseTo", 0.92)
	CollectionService:AddTag(column, "GaG_Pulse")
	lamp(circle, Color3.fromHex(def.color), 30, 2.5)

	local anchor = Build.marker("SignAnchor", floor * CFrame.new(0, 34, 0), model)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(260, 120)
	sign.LightInfluence = 0
	sign.MaxDistance = 400
	sign.Adornee = anchor
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(12, 12, 26)
	panel.BackgroundTransparency = 0.15
	panel.Parent = sign
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 12)
	round.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(def.color)
	stroke.Thickness = 3
	stroke.Parent = panel
	local function line(
		name: string,
		text: string,
		y: number,
		height: number,
		size: number,
		color: Color3
	)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.Text = text
		label.TextSize = size
		label.TextColor3 = color
		label.Font = Enum.Font.GothamBlack
		label.TextStrokeTransparency = 0.4
		label.TextWrapped = true
		label.Parent = panel
	end
	local reward = `{def.reward.minutes} min of production (first win each day)`
	line("Title", `{string.upper(def.displayName)} RAID`, 6, 28, 24, Color3.fromHex(def.color))
	line("Reward", `Reward: {reward}`, 36, 20, 13, Color3.fromRGB(255, 214, 110))
	line("Queue", `0 / {R.MAX_RAIDERS} in queue`, 60, 22, 16, Color3.new(1, 1, 1))
	line("Status", "Step on to join", 86, 22, 14, Color3.fromRGB(190, 200, 230))
	sign.Parent = anchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JoinPrompt"
	prompt.ActionText = "Join queue"
	prompt.ObjectText = `{def.displayName} raid`
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = circle
	model:SetAttribute("Difficulty", def.id)
	return model
end

function RaidBuilder.boss(center: CFrame, parent: Instance): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "DeathStar"
	local size = R.BOSS_SIZE
	local body: BasePart
	local source = asset("Bosses", "DeathStar")
	if source and source:IsA("BasePart") then
		local copy = source:Clone()
		for _, item in copy:GetDescendants() do
			if not item:IsA("SurfaceAppearance") then
				item:Destroy() -- welds and anything else attached
			end
		end
		copy.Size = Vector3.one * size
		body = copy
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * size
		ball.Color = Color3.fromRGB(150, 155, 165)
		ball.Material = Enum.Material.Metal
		body = ball
	end
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = true
	body.CanTouch = false
	body.CastShadow = false
	body.CFrame = center
	body.Parent = model
	model.PrimaryPart = body

	-- The weak point starts on the front, facing the raiders.
	local weak = Instance.new("Part")
	weak.Name = "WeakPoint"
	weak.Shape = Enum.PartType.Cylinder
	weak.Size = Vector3.new(2, size * 0.22, size * 0.22)
	weak.Material = Enum.Material.Neon
	weak.Color = Color3.fromRGB(90, 255, 120)
	weak.Anchored = true
	weak.CanCollide = false
	weak.CanTouch = false
	weak.CastShadow = false
	RaidBuilder.placeWeakPoint(weak, center.Position, Vector3.new(0, 0.42, -1).Unit)
	weak.Parent = model
	lamp(weak, Color3.fromRGB(90, 255, 120), 120, 4)
	-- A target marker raiders can see through the hull, so they can find it
	-- after it moves.
	local marker = Instance.new("BillboardGui")
	marker.Name = "Target"
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.fromOffset(64, 64)
	marker.MaxDistance = 2500
	marker.Parent = weak
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(40, 40)
	ring.BackgroundTransparency = 1
	ring.Parent = marker
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(110, 255, 140)
	edge.Thickness = 3
	edge.Parent = ring
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = Color3.fromRGB(110, 255, 140)
	dot.Parent = ring
	local dotRound = Instance.new("UICorner")
	dotRound.CornerRadius = UDim.new(1, 0)
	dotRound.Parent = dot
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 80, 80)
	glow.Range = 60
	glow.Brightness = 2
	glow.Parent = body
	model.Parent = parent
	return model, body, weak
end

-- Puts the weak point on the hull of a boss centred at `center`, facing out
-- along the unit vector `direction`.
function RaidBuilder.placeWeakPoint(weak: BasePart, center: Vector3, direction: Vector3)
	local surface = center + direction * R.BOSS_SIZE * 0.49
	-- A cylinder's axis is X: point it along `direction`.
	weak.CFrame = CFrame.lookAt(surface, surface + direction) * CFrame.Angles(0, math.pi / 2, 0)
end

-- A homing drone at `position`: a red neon core trailing fire. One part,
-- so the server can move it cheaply. Not collidable; lasers can hit it.
function RaidBuilder.drone(position: Vector3, parent: Instance): BasePart
	local size = R.DRONE_SIZE
	local core = Instance.new("Part")
	core.Name = "Drone"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * size
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 60, 60)
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CastShadow = false
	core.CFrame = CFrame.new(position)
	core:SetAttribute("Drone", true)
	lamp(core, Color3.fromRGB(255, 70, 70), 30, 3)
	local trail = Instance.new("Fire")
	trail.Color = Color3.fromRGB(255, 80, 60)
	trail.SecondaryColor = Color3.fromRGB(255, 200, 80)
	trail.Size = size * 0.6
	trail.Heat = 4
	trail.Parent = core
	core.Parent = parent
	return core
end

return RaidBuilder

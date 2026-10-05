--!strict
-- What PvP looks like on this client (Config.Combat). Purely visual; the
-- server (CombatSystem) decides every hit.
--
--   Explosion  ShipDestroyed: a white flash inside a swelling fireball, a
--              shockwave ring, smoke and fire, a boom, and chunks of the hull
--              (in its paint, some glowing embers trailing fire) flung out,
--              tumbling and fading. Nearby cameras shake.
--   Tags       Over other ships whose owner has PvP on: a red PvP tag and a
--              hull bar once damaged.
--   Hits       A hit marker when your shot damages a ship; a red flash at the
--              screen's edges and a shake when your own ship is hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local C = Config.Combat

local FIRE_HOT = Color3.fromRGB(255, 244, 214)
local FIRE = Color3.fromRGB(255, 140, 50)
local FIRE_DARK = Color3.fromRGB(200, 50, 20)
local SMOKE = Color3.fromRGB(60, 58, 64)
local HULL_GREY = Color3.fromRGB(58, 63, 74)
local PVP_RED = Color3.fromRGB(255, 70, 70)
local TAG_REFRESH = 0.2
-- Your shot counts as the cause of a hull drop seen this soon after it.
local HIT_WINDOW = 0.6

type Chunk = {
	part: BasePart,
	velocity: Vector3,
	axis: Vector3,
	spin: number, -- radians per second
}

type Blast = {
	started: number,
	size: number,
	fireball: Part,
	core: Part,
	ring: Part,
	light: PointLight,
	chunks: { Chunk },
	cleanup: { Instance },
}

local CombatController = {}

local blasts: { Blast } = {}
local folder: Folder? = nil
local hitMarker: Frame
local vignette: { Frame } = {}
local tags: { [Model]: BillboardGui } = {}

local function sequence(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

local function fxFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GaG_Explosions"
	made.Parent = Workspace.CurrentCamera
	folder = made
	return made
end

local function fxPart(shape: Enum.PartType, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Material = material
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.one
	part.Parent = fxFolder()
	return part
end

-- Smoke, fire and sparks bursting from the blast's centre.
local function burstEmitters(at: CFrame, scale: number, reduced: boolean): Part
	local anchor = fxPart(Enum.PartType.Ball, FIRE, Enum.Material.Neon)
	anchor.Transparency = 1
	anchor.CFrame = at
	local share = if reduced then 0.5 else 1

	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(6 * scale, 18 * scale)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Lifetime = NumberRange.new(1.6, 2.6)
	smoke.Size = sequence({ { 0, 3 * scale }, { 1, 9 * scale } })
	smoke.Transparency = sequence({ { 0, 0.35 }, { 1, 1 } })
	smoke.Color = ColorSequence.new(SMOKE)
	smoke.Drag = 2
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.LightInfluence = 1
	smoke.Parent = anchor
	smoke:Emit(math.floor(24 * share))

	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 0
	fire.Speed = NumberRange.new(12 * scale, 34 * scale)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Lifetime = NumberRange.new(0.4, 0.9)
	fire.Size = sequence({ { 0, 4 * scale }, { 1, 0.5 } })
	fire.Transparency = sequence({ { 0, 0 }, { 1, 1 } })
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, FIRE_HOT),
		ColorSequenceKeypoint.new(0.4, FIRE),
		ColorSequenceKeypoint.new(1, FIRE_DARK),
	})
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Drag = 3
	fire.Parent = anchor
	fire:Emit(math.floor(40 * share))

	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(40 * scale, 110 * scale)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Size = sequence({ { 0, 0.7 }, { 1, 0 } })
	sparks.Color = ColorSequence.new(FIRE_HOT, FIRE)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Drag = 2
	sparks.Parent = anchor
	sparks:Emit(math.floor(60 * share))

	if C.EXPLOSION_SOUND ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = C.EXPLOSION_SOUND
		sound.Volume = C.EXPLOSION_SOUND_VOLUME
		sound.PlaybackSpeed = C.EXPLOSION_SOUND_SPEED
		sound.RollOffMinDistance = 30
		sound.RollOffMaxDistance = 900
		sound.Parent = anchor
		sound:Play()
	end
	return anchor
end

-- Chunks of hull flung out from the blast, tumbling.
local function makeChunks(at: CFrame, size: Vector3, paint: Color3, reduced: boolean): { Chunk }
	local chunks: { Chunk } = {}
	local count = if reduced then math.ceil(C.DEBRIS_COUNT / 2) else C.DEBRIS_COUNT
	local scale = math.max(size.X, size.Z) / 16
	local palette = { paint, paint, paint:Lerp(Color3.new(), 0.45), HULL_GREY }
	for i = 1, count do
		local ember = math.random() < C.EMBER_SHARE
		local shape = if math.random() < 0.5 then "WedgePart" else "Part"
		local part = Instance.new(shape) :: BasePart
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local edge = (0.5 + math.random() * 1.8) * scale
		part.Size =
			Vector3.new(edge, edge * (0.3 + math.random() * 0.5), edge * (0.6 + math.random()))
		if ember then
			part.Material = Enum.Material.Neon
			part.Color = if i % 2 == 0 then FIRE else FIRE_DARK
			part.Size *= 0.6
			-- A fiery streak behind each ember.
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, part.Size.Y / 2, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -part.Size.Y / 2, 0)
			a1.Parent = part
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(FIRE_HOT, FIRE_DARK)
			trail.Transparency = sequence({ { 0, 0.1 }, { 1, 1 } })
			trail.WidthScale = sequence({ { 0, 1 }, { 1, 0 } })
			trail.Lifetime = 0.45
			trail.FaceCamera = true
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.Parent = part
		else
			part.Material = Enum.Material.Metal
			part.Color = palette[math.random(#palette)]
		end
		-- Start spread over the hull, fly outwards from the centre.
		local offset = Vector3.new(
			(math.random() - 0.5) * size.X,
			(math.random() - 0.5) * size.Y,
			(math.random() - 0.5) * size.Z
		) * 0.7
		local start = at * CFrame.new(offset)
		part.CFrame = start
			* CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, 0)
		part.Parent = fxFolder()
		local outward = start.Position - at.Position
		local direction = if outward.Magnitude > 0.1
			then outward.Unit
			else Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
		direction = (direction + Vector3.new(
			math.random() - 0.5,
			math.random() - 0.5,
			math.random() - 0.5
		) * 0.8).Unit
		local speed = C.DEBRIS_SPEED[1] + math.random() * (C.DEBRIS_SPEED[2] - C.DEBRIS_SPEED[1])
		table.insert(chunks, {
			part = part,
			velocity = direction * speed * (if ember then 1.25 else 1),
			axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
			spin = 2 + math.random() * 8,
		})
	end
	return chunks
end

local function explode(pivot: unknown, size: unknown, paint: unknown, _ownerUserId: unknown)
	if typeof(pivot) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return
	end
	local color = if type(paint) == "string" then Color3.fromHex(paint) else HULL_GREY
	local reduced = ClientState.reducedEffects
	local scale = math.clamp(math.max(size.X, size.Z) / 16, 0.6, 1.6)
	local at = CFrame.new(pivot.Position) * pivot.Rotation

	local fireball = fxPart(Enum.PartType.Ball, FIRE, Enum.Material.Neon)
	fireball.CFrame = at
	local core = fxPart(Enum.PartType.Ball, FIRE_HOT, Enum.Material.Neon)
	core.CFrame = at
	local ring = fxPart(Enum.PartType.Cylinder, FIRE, Enum.Material.ForceField)
	-- The ring lies in the ship's wing plane.
	ring.CFrame = at * CFrame.Angles(0, 0, math.rad(90))
	local light = Instance.new("PointLight")
	light.Color = FIRE
	light.Range = 60 * scale
	light.Brightness = 14
	light.Shadows = false
	light.Parent = core

	local emitters = burstEmitters(at, scale, reduced)
	table.insert(blasts, {
		started = os.clock(),
		size = C.EXPLOSION_SIZE * scale,
		fireball = fireball,
		core = core,
		ring = ring,
		light = light,
		chunks = makeChunks(at, size, color, reduced),
		cleanup = { fireball, core, ring, emitters },
	})

	-- Shake the camera, more the closer it is.
	local camera = Workspace.CurrentCamera
	local distance = (camera.CFrame.Position - at.Position).Magnitude
	if distance < C.SHAKE_RADIUS then
		ClientState.shake:Fire(C.SHAKE_MAX * (1 - distance / C.SHAKE_RADIUS))
	end
end

local function step(dt: number)
	local now = os.clock()
	for index = #blasts, 1, -1 do
		local blast = blasts[index]
		local age = now - blast.started
		local t = math.clamp(age / C.EXPLOSION_TIME, 0, 1)
		-- Fireball: swells fast, then fades; white core flashes first.
		local swell = 1 - (1 - t) ^ 3
		blast.fireball.Size = Vector3.one * blast.size * (0.25 + 0.75 * swell)
		blast.fireball.Transparency = 0.05 + 0.95 * t
		blast.fireball.Color = FIRE:Lerp(FIRE_DARK, t)
		local flash = math.clamp(age / (C.EXPLOSION_TIME * 0.4), 0, 1)
		blast.core.Size = Vector3.one * blast.size * (0.15 + 0.35 * flash)
		blast.core.Transparency = flash
		local ringSize = blast.size * (0.4 + 2.6 * swell)
		blast.ring.Size = Vector3.new(0.3, ringSize, ringSize)
		blast.ring.Transparency = 0.2 + 0.8 * t
		blast.light.Brightness = 14 * (1 - t)

		local fadeFrom = C.DEBRIS_LIFETIME * 0.6
		local keep = math.exp(-C.DEBRIS_DRAG * dt)
		for _, chunk in blast.chunks do
			chunk.velocity *= keep
			chunk.part.CFrame = (chunk.part.CFrame + chunk.velocity * dt)
				* CFrame.fromAxisAngle(chunk.axis, chunk.spin * dt)
			if age > fadeFrom then
				chunk.part.Transparency =
					math.clamp((age - fadeFrom) / (C.DEBRIS_LIFETIME - fadeFrom), 0, 1)
			end
		end

		if age >= C.DEBRIS_LIFETIME + 0.3 then
			for _, chunk in blast.chunks do
				chunk.part:Destroy()
			end
			for _, item in blast.cleanup do
				item:Destroy()
			end
			table.remove(blasts, index)
		end
	end
end

-- Hit feedback -------------------------------------------------------------

local function buildScreen()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Combat"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5

	-- Hit marker: four short slanted bars around the screen's centre.
	hitMarker = Instance.new("Frame")
	hitMarker.Name = "HitMarker"
	hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitMarker.Position = UDim2.fromScale(0.5, 0.5)
	hitMarker.Size = UDim2.fromOffset(34, 34)
	hitMarker.BackgroundTransparency = 1
	hitMarker.Visible = false
	hitMarker.Parent = gui
	for i = 0, 3 do
		local angle = math.rad(45 + 90 * i)
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, math.cos(angle) * 11, 0.5, math.sin(angle) * 11)
		bar.Size = UDim2.fromOffset(10, 3)
		bar.Rotation = math.deg(angle)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Parent = hitMarker
		local stroke = Instance.new("UIStroke")
		stroke.Color = PVP_RED
		stroke.Thickness = 1
		stroke.Parent = bar
	end

	-- Damage flash: red glows fading in from each screen edge.
	local edges = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.18), rot = 90 },
		{ pos = UDim2.fromScale(0, 0.82), size = UDim2.fromScale(1, 0.18), rot = -90 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.14, 1), rot = 0 },
		{ pos = UDim2.fromScale(0.86, 0), size = UDim2.fromScale(0.14, 1), rot = 180 },
	}
	for _, edge in edges do
		local frame = Instance.new("Frame")
		frame.Position = edge.pos
		frame.Size = edge.size
		frame.BackgroundColor3 = PVP_RED
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rot
		gradient.Transparency = sequence({ { 0, 0 }, { 1, 1 } })
		gradient.Parent = frame
		table.insert(vignette, frame)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function showHitMarker()
	hitMarker.Visible = true
	hitMarker.Size = UDim2.fromOffset(44, 44)
	TweenService
		:Create(hitMarker, TweenInfo.new(C.HIT_MARKER_TIME), { Size = UDim2.fromOffset(30, 30) })
		:Play()
	local shownAt = os.clock()
	hitMarker:SetAttribute("ShownAt", shownAt)
	task.delay(C.HIT_MARKER_TIME, function()
		if hitMarker:GetAttribute("ShownAt") == shownAt then
			hitMarker.Visible = false
		end
	end)
end

local function flashDamage()
	for _, frame in vignette do
		frame.BackgroundTransparency = 0.35
		TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end
	ClientState.shake:Fire(0.8)
end

-- PvP tags -----------------------------------------------------------------

local function makeTag(model: Model, hull: BasePart): BillboardGui
	local tag = Instance.new("BillboardGui")
	tag.Name = "GaG_PvPTag"
	tag.Size = UDim2.fromOffset(90, 30)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = C.TAG_DISTANCE
	tag.Adornee = hull
	tag.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromOffset(46, 16)
	label.BackgroundColor3 = PVP_RED
	label.Text = "PvP"
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 12
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = tag
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = label

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	track.BorderSizePixel = 0
	track.Visible = false
	track.Parent = tag
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 230, 150)
	fill.BorderSizePixel = 0
	fill.Parent = track
	tag.Parent = model
	return tag
end

local function healthOf(model: Model): number
	local value = model:GetAttribute("Health")
	return if type(value) == "number" then math.clamp(value, 0, 1) else 1
end

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local last = healthOf(model)
	model:GetAttributeChangedSignal("Health"):Connect(function()
		local now = healthOf(model)
		if now < last then
			if model == ClientState.ship then
				flashDamage()
			elseif os.clock() - ClientState.beam.lastShot < HIT_WINDOW then
				showHitMarker()
			end
		end
		last = now
	end)
end

local function refreshTags()
	local ships = Workspace:FindFirstChild("Ships")
	if ships == nil then
		return
	end
	for _, model in ships:GetChildren() do
		local hull = if model:IsA("Model") then model.PrimaryPart else nil
		if not model:IsA("Model") or hull == nil then
			continue
		end
		local userId = model:GetAttribute("OwnerUserId")
		local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		local show = owner ~= nil
			and owner ~= Players.LocalPlayer
			and owner:GetAttribute("PvP") == true
		local tag = tags[model]
		if show and not tag then
			tag = makeTag(model, hull)
			tags[model] = tag
		end
		if tag then
			tag.Enabled = show
			local health = healthOf(model)
			local trackFrame = tag:FindFirstChild("Track") :: Frame
			trackFrame.Visible = health < 1
			local fill = trackFrame:FindFirstChild("Fill") :: Frame
			fill.Size = UDim2.fromScale(health, 1)
			fill.BackgroundColor3 = Color3.fromRGB(255, 80, 60)
				:Lerp(Color3.fromRGB(110, 230, 150), health)
		end
	end
	for model in tags do
		if model.Parent == nil then
			tags[model] = nil
		end
	end
end

function CombatController.init()
	buildScreen()
end

function CombatController.start()
	Net.ShipDestroyed.OnClientEvent:Connect(explode)
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		local ships = Workspace:WaitForChild("Ships")
		for _, model in ships:GetChildren() do
			track(model)
		end
		ships.ChildAdded:Connect(track)
		while true do
			refreshTags()
			task.wait(TAG_REFRESH)
		end
	end)
end

return CombatController

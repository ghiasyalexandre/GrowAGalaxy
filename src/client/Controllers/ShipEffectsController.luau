--!strict
-- Effects this client draws for every ship in Workspace.Ships: engine glow
-- and exhaust that follow the throttle (and flare white-hot while boosting),
-- wing-tip trails, and mining laser bolts. Purely local and visual.
--
-- A laser shot: a flash at the nose, a three-layer bolt that races out to
-- what it hits, then a flash, an expanding shockwave, a burst of sparks, a
-- light and (on asteroids) rock chips where it lands.
--
-- Your own ship follows your input straight away (ClientState.flight and
-- ClientState.beam). Other ships follow their replicated velocity and the
-- attributes the server sets: Piloted, MaxSpeed, BeamRange, Shot, BeamAim.
-- Another ship faster than its MaxSpeed is boosting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FlightMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("FlightMath")
)

local B = Config.Beam

local RENDER_STEP = "GaG_ShipEffects"
local FORWARD = Vector3.new(0, 0, -1)
local GLOW_IDLE = Color3.fromHex("#2E5E85")
local GLOW_FULL = Color3.fromHex("#D2F4FF")
local IDLE_POWER = 0.15 -- engine output of a piloted ship sitting still
local POWER_RESPONSE = 6
local EXHAUST_RATE = 70 -- particles per second per engine at full power
local TRAIL_MIN_SPEED = 25
-- A ship that moves further than this in one frame was teleported (docked,
-- relaunched): its trails are cleared instead of drawing a streak.
local JUMP_DISTANCE = 60
local DEFAULT_MAX_SPEED = 120
local DEFAULT_BEAM_RANGE = 120
local GLOW_BOOST = Color3.fromHex("#FFFFFF")
local BOOST_EXHAUST = 2.4 -- exhaust rate multiplier while boosting
local BOOSTING_SPEED_SHARE = 1.08 -- other ships above MaxSpeed x this are boosting
local MUZZLE_TIME = 0.09 -- seconds the muzzle flash lasts
local IMPACT_TIME = 0.28 -- seconds the impact flash and shockwave last
local DEBRIS_COLOR = Color3.fromHex("#8C7B6B")

type BeamFx = {
	target: Attachment, -- where the bolt lands (sparks, chips, light)
	head: Attachment, -- the bolt's leading end, racing out to `target`
	glow: Beam,
	outer: Beam,
	core: Beam,
	sparks: ParticleEmitter,
	debris: ParticleEmitter,
	light: PointLight,
	flash: Part, -- muzzle flash
	flashLight: PointLight,
	impact: Part, -- impact flash
	ring: Part, -- impact shockwave
	impactAt: number, -- os.clock() of the last impact
	impactPos: Vector3?,
	impactFacing: Vector3, -- direction back towards the shooter
}

type Visual = {
	model: Model,
	hull: BasePart?,
	glows: { BasePart },
	exhaust: { ParticleEmitter },
	trails: { Trail },
	muzzle: Attachment?,
	beam: BeamFx?,
	power: number, -- smoothed engine output, 0 to 1
	lastPosition: Vector3?,
	dirty: boolean, -- parts were added or removed (streaming): look again
	parked: boolean, -- effects already set to the parked look; nothing to update
	rayParams: RaycastParams,
	rayCharacter: Model?, -- the pilot character rayParams currently excludes
	shotSeen: any, -- the ship's last seen Shot attribute
	shotAt: number, -- os.clock() when that shot was seen
	shotDrawn: number, -- shotAt of the bolt whose sparks were already emitted
	connections: { RBXScriptConnection },
}

local ShipEffectsController = {}

local visuals: { [Model]: Visual } = {}

local function sequence(from: number, to: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to),
	})
end

local function makeBeam(name: string, color: string, transparency: number, head: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment1 = head
	beam.Color = ColorSequence.new(Color3.fromHex(color))
	beam.Transparency = NumberSequence.new(transparency)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = head
	return beam
end

-- Local flash parts live under the camera folder, shown only while needed.
local fxFolder: Folder? = nil

local function fxParent(): Folder
	local existing = fxFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "GaG_LaserFx"
	created.Parent = Workspace.CurrentCamera
	fxFolder = created
	return created
end

local function flashPart(name: string, shape: Enum.PartType, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = fxParent()
	return part
end

-- The bolt's ends live in Terrain, so they can sit anywhere in the world.
-- `color` is the ship's BeamColor cosmetic, or nil for the standard laser.
local function makeBeamFx(color: string?): BeamFx
	local hex = color or B.COLOR
	local tint = Color3.fromHex(hex)
	local target = Instance.new("Attachment")
	target.Name = "GaG_BeamTarget"
	target.Parent = Workspace.Terrain
	local head = Instance.new("Attachment")
	head.Name = "GaG_BeamHead"
	head.Parent = Workspace.Terrain

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(18, 45)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Size = sequence(0.8, 0)
	sparks.Drag = 4
	sparks.Color = ColorSequence.new(Color3.fromHex(B.CORE_COLOR), tint)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = target

	local debris = Instance.new("ParticleEmitter")
	debris.Name = "Debris"
	debris.Rate = 0
	debris.Speed = NumberRange.new(10, 26)
	debris.SpreadAngle = Vector2.new(180, 180)
	debris.Lifetime = NumberRange.new(0.5, 0.9)
	debris.Size = sequence(0.9, 0.2)
	debris.Drag = 2.5
	debris.Rotation = NumberRange.new(0, 360)
	debris.RotSpeed = NumberRange.new(-200, 200)
	debris.Color = ColorSequence.new(DEBRIS_COLOR)
	debris.LightInfluence = 1
	debris.Parent = target

	local light = Instance.new("PointLight")
	light.Color = tint
	light.Range = 28
	light.Brightness = 0
	light.Enabled = false
	light.Parent = target

	local flash = flashPart("MuzzleFlash", Enum.PartType.Ball, Color3.fromHex(B.CORE_COLOR))
	local flashLight = Instance.new("PointLight")
	flashLight.Color = tint
	flashLight.Range = 18
	flashLight.Enabled = false
	flashLight.Parent = flash

	return {
		target = target,
		head = head,
		glow = makeBeam("Glow", hex, 0.65, head),
		outer = makeBeam("Beam", hex, 0.1, head),
		core = makeBeam("Core", B.CORE_COLOR, 0, head),
		sparks = sparks,
		debris = debris,
		light = light,
		flash = flash,
		flashLight = flashLight,
		impact = flashPart("ImpactFlash", Enum.PartType.Ball, tint),
		ring = flashPart("Shockwave", Enum.PartType.Cylinder, tint),
		impactAt = 0,
		impactPos = nil,
		impactFacing = FORWARD,
	}
end

local function hideBolt(fx: BeamFx)
	fx.glow.Enabled = false
	fx.outer.Enabled = false
	fx.core.Enabled = false
end

local function hideBeam(v: Visual)
	local fx = v.beam
	if fx then
		hideBolt(fx)
		fx.light.Enabled = false
		fx.flashLight.Enabled = false
		fx.flash.Transparency = 1
		fx.impact.Transparency = 1
		fx.ring.Transparency = 1
	end
end

-- Finds the effect instances in a ship model (again, after streaming).
local function collect(v: Visual)
	v.dirty = false
	v.parked = false
	local hull = v.model:FindFirstChild("Hull")
	v.hull = if hull and hull:IsA("BasePart") then hull else nil
	table.clear(v.glows)
	table.clear(v.exhaust)
	table.clear(v.trails)
	v.muzzle = nil
	for _, item in v.model:GetDescendants() do
		if item:IsA("BasePart") and item.Name == "EngineGlow" then
			table.insert(v.glows, item)
		elseif item:IsA("ParticleEmitter") and item.Name == "Exhaust" then
			table.insert(v.exhaust, item)
		elseif item:IsA("Trail") and item.Name == "WingTrail" then
			table.insert(v.trails, item)
		elseif item:IsA("Attachment") and item.Name == "BeamOrigin" then
			v.muzzle = item
		end
	end
end

local function ownerCharacter(model: Model): Model?
	local userId = model:GetAttribute("OwnerUserId")
	local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return if owner then owner.Character else nil
end

local function numberAttribute(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" and value > 0 then value else default
end

local function updateBeam(v: Visual, hull: BasePart, mine: boolean)
	-- A bolt shows for BOLT_TIME after each shot: your own at once, other
	-- ships' when their Shot attribute changes.
	local aim: Vector3
	local shotAt: number
	if mine then
		aim = ClientState.beam.direction
		shotAt = ClientState.beam.lastShot
	else
		local shot = v.model:GetAttribute("Shot")
		if shot ~= v.shotSeen then
			v.shotSeen = shot
			v.shotAt = os.clock()
		end
		local value = v.model:GetAttribute("BeamAim")
		aim = if typeof(value) == "Vector3" then value else FORWARD
		shotAt = v.shotAt
	end
	local age = os.clock() - shotAt
	local muzzle = v.muzzle
	if muzzle == nil or age > B.BOLT_TIME + IMPACT_TIME then
		hideBeam(v)
		return
	end

	local beamColor = v.model:GetAttribute("BeamColor")
	local fx = v.beam or makeBeamFx(if type(beamColor) == "string" then beamColor else nil)
	v.beam = fx
	local origin = muzzle.WorldPosition

	-- The bolt races out to what it hits, then thins out as it fades.
	if age < B.BOLT_TIME then
		fx.glow.Attachment0 = muzzle
		fx.outer.Attachment0 = muzzle
		fx.core.Attachment0 = muzzle
		local reach = hull.CFrame:VectorToWorldSpace(aim)
			* numberAttribute(v.model, "BeamRange", DEFAULT_BEAM_RANGE)
		-- The beam passes through its own ship and pilot.
		local character = ownerCharacter(v.model)
		if character ~= v.rayCharacter then
			v.rayCharacter = character
			v.rayParams.FilterDescendantsInstances = if character
				then { v.model, character }
				else { v.model }
		end
		local hit = Workspace:Raycast(origin, reach, v.rayParams)
		local finish = if hit then hit.Position else origin + reach
		local travel = math.clamp(age / B.BOLT_TRAVEL_TIME, 0, 1)
		fx.head.WorldPosition = origin:Lerp(finish, travel)

		local pulse = 1.4 * (1 - age / B.BOLT_TIME) + 0.25
		fx.glow.Width0 = B.WIDTH * 2.8 * pulse
		fx.glow.Width1 = B.WIDTH * 2.2 * pulse
		fx.outer.Width0 = B.WIDTH * pulse
		fx.outer.Width1 = B.WIDTH * 0.85 * pulse
		fx.core.Width0 = B.WIDTH * 0.4 * pulse
		fx.core.Width1 = B.WIDTH * 0.3 * pulse
		fx.glow.Enabled = true
		fx.outer.Enabled = true
		fx.core.Enabled = true

		if travel >= 1 and v.shotDrawn ~= shotAt then
			-- The bolt lands: one impact per shot.
			v.shotDrawn = shotAt
			fx.impactPos = if hit then hit.Position else nil
			if hit then
				fx.impactAt = os.clock()
				fx.impactFacing = (origin - hit.Position).Unit
				fx.target.WorldPosition = hit.Position
				fx.sparks:Emit(B.SPARK_BURST)
				if hit.Instance:FindFirstAncestor("Asteroids") then
					fx.debris:Emit(B.DEBRIS_BURST)
				end
				if mine then
					ClientState.beam.hitAt = os.clock()
				end
			end
		end
	else
		hideBolt(fx)
	end

	-- Muzzle flash: a white-hot ball that swells and fades.
	if age < MUZZLE_TIME then
		local t = age / MUZZLE_TIME
		fx.flash.CFrame = CFrame.new(origin)
		fx.flash.Size = Vector3.one * B.MUZZLE_FLASH_SIZE * (0.6 + 0.8 * t)
		fx.flash.Transparency = 0.05 + 0.95 * t
		fx.flashLight.Enabled = true
		fx.flashLight.Brightness = 8 * (1 - t)
	else
		fx.flash.Transparency = 1
		fx.flashLight.Enabled = false
	end

	-- Impact: a flash, a shockwave ring facing the shooter, a fading light.
	local position = fx.impactPos
	local impactAge = os.clock() - fx.impactAt
	if position and impactAge < IMPACT_TIME then
		local t = impactAge / IMPACT_TIME
		fx.impact.CFrame = CFrame.new(position)
		fx.impact.Size = Vector3.one * B.IMPACT_FLASH_SIZE * (0.4 + 0.6 * t)
		fx.impact.Transparency = 0.1 + 0.9 * t
		local ringSize = B.IMPACT_FLASH_SIZE * (0.5 + 2 * t)
		fx.ring.CFrame = CFrame.lookAt(position, position + fx.impactFacing)
			* CFrame.Angles(0, math.rad(90), 0)
		fx.ring.Size = Vector3.new(0.15, ringSize, ringSize)
		fx.ring.Transparency = 0.3 + 0.7 * t
		fx.light.Enabled = true
		fx.light.Brightness = 10 * (1 - t)
	else
		fx.impact.Transparency = 1
		fx.ring.Transparency = 1
		fx.light.Enabled = false
	end
end

local function updateVisual(v: Visual, dt: number)
	if v.dirty then
		collect(v)
	end
	local hull = v.hull
	if hull == nil or hull.Parent == nil then
		hideBeam(v)
		return
	end

	local position = hull.Position
	local last = v.lastPosition
	local jumped = last ~= nil and (position - last).Magnitude > JUMP_DISTANCE
	v.lastPosition = position

	local mine = v.model == ClientState.ship and ClientState.mode == "ship"
	local piloted = mine or v.model:GetAttribute("Piloted") == true
	if not piloted and v.power < 0.01 then
		-- Parked with its engines wound down: set the parked look once.
		if not v.parked then
			v.parked = true
			v.power = 0
			for _, glow in v.glows do
				glow.Color = GLOW_IDLE
				glow.Transparency = 0.5
			end
			for _, emitter in v.exhaust do
				emitter.Rate = 0
			end
			for _, trail in v.trails do
				trail.Enabled = false
			end
			hideBeam(v)
		end
		return
	end
	v.parked = false
	local speed = hull.AssemblyLinearVelocity.Magnitude
	local maxSpeed = numberAttribute(v.model, "MaxSpeed", DEFAULT_MAX_SPEED)
	local speedShare = math.clamp(speed / maxSpeed, 0, 1)
	local boosting = if mine
		then ClientState.flight.boosting
		else speed > maxSpeed * BOOSTING_SPEED_SHARE

	-- Engines: dark when parked, a low idle when piloted, brighter and with
	-- more exhaust as the ship speeds up (or, for your own, as you throttle).
	local target = 0
	if piloted then
		local drive = if mine
			then math.max(ClientState.flight.throttle, speedShare * 0.6)
			else speedShare
		target = math.max(IDLE_POWER, drive)
	end
	-- Boosting overdrives the engines past full power: white-hot, more exhaust.
	if piloted and boosting then
		target = 1.6
	end
	v.power = FlightMath.smooth(v.power, target, POWER_RESPONSE, dt)
	local overdrive = math.clamp(v.power - 1, 0, 0.6) / 0.6
	for _, glow in v.glows do
		glow.Color = GLOW_IDLE:Lerp(GLOW_FULL, math.min(v.power, 1)):Lerp(GLOW_BOOST, overdrive)
		glow.Transparency = 0.5 * (1 - math.min(v.power, 1))
	end
	local rate = if v.power > IDLE_POWER + 0.05
		then EXHAUST_RATE * math.min(v.power, 1) * (1 + (BOOST_EXHAUST - 1) * overdrive)
		else 0
	for _, emitter in v.exhaust do
		emitter.Rate = rate
	end
	for _, trail in v.trails do
		if jumped then
			trail:Clear()
		end
		trail.Enabled = piloted and not jumped and speed > TRAIL_MIN_SPEED
	end

	if piloted then
		updateBeam(v, hull, mine)
	else
		hideBeam(v)
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or visuals[model] then
		return
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	local v: Visual = {
		model = model,
		hull = nil,
		glows = {},
		exhaust = {},
		trails = {},
		muzzle = nil,
		beam = nil,
		power = 0,
		lastPosition = nil,
		dirty = true,
		parked = false,
		rayParams = rayParams,
		rayCharacter = nil,
		shotSeen = model:GetAttribute("Shot"),
		shotAt = 0,
		shotDrawn = 0,
		connections = {},
	}
	local function markDirty()
		v.dirty = true
	end
	table.insert(v.connections, model.DescendantAdded:Connect(markDirty))
	table.insert(v.connections, model.DescendantRemoving:Connect(markDirty))
	visuals[model] = v
end

local function untrack(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local v = visuals[model]
	if v == nil then
		return
	end
	visuals[model] = nil
	for _, connection in v.connections do
		connection:Disconnect()
	end
	local fx = v.beam
	if fx then
		fx.target:Destroy()
		fx.head:Destroy()
		fx.flash:Destroy()
		fx.impact:Destroy()
		fx.ring:Destroy()
	end
end

local function update(dt: number)
	for _, v in visuals do
		updateVisual(v, dt)
	end
end

function ShipEffectsController.start()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Ships")
		for _, model in folder:GetChildren() do
			track(model)
		end
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(untrack)
		-- After the flight camera, so beams start from where the ship is drawn.
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 2, update)
	end)
end

return ShipEffectsController

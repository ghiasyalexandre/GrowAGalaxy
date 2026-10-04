--!strict
-- Effects this client draws for every ship in Workspace.Ships: engine glow
-- and exhaust that follow the throttle, wing-tip trails, and mining laser
-- beams with sparks where they hit. Purely local and visual.
--
-- Your own ship follows your input straight away (ClientState.flight and
-- ClientState.beam). Other ships follow their replicated velocity and the
-- attributes the server sets: Piloted, MaxSpeed, BeamRange, BeamOn, BeamAim.

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
local SPARK_RATE = 60
local PULSE_SPEED = 40 -- radians per second of the beam's flicker

type BeamFx = {
	target: Attachment,
	outer: Beam,
	core: Beam,
	sparks: ParticleEmitter,
	light: PointLight,
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

local function makeBeam(name: string, color: string, transparency: number, target: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment1 = target
	beam.Color = ColorSequence.new(Color3.fromHex(color))
	beam.Transparency = NumberSequence.new(transparency)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = target
	return beam
end

-- The far end of a beam lives in Terrain, so it can sit anywhere in the world.
local function makeBeamFx(): BeamFx
	local target = Instance.new("Attachment")
	target.Name = "GaG_BeamTarget"
	target.Parent = Workspace.Terrain

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(8, 22)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Size = sequence(0.5, 0)
	sparks.Drag = 3
	sparks.Color = ColorSequence.new(Color3.fromHex(B.CORE_COLOR), Color3.fromHex(B.COLOR))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = target

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(B.COLOR)
	light.Range = 14
	light.Brightness = 3
	light.Enabled = false
	light.Parent = target

	return {
		target = target,
		outer = makeBeam("Beam", B.COLOR, 0.15, target),
		core = makeBeam("Core", B.CORE_COLOR, 0, target),
		sparks = sparks,
		light = light,
	}
end

local function hideBeam(v: Visual)
	local fx = v.beam
	if fx then
		fx.outer.Enabled = false
		fx.core.Enabled = false
		fx.sparks.Rate = 0
		fx.light.Enabled = false
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

local function updateBeam(v: Visual, hull: BasePart, mine: boolean, now: number)
	local firing: boolean
	local aim: Vector3
	if mine then
		firing = ClientState.beam.firing
		aim = ClientState.beam.direction
	else
		firing = v.model:GetAttribute("BeamOn") == true
		local value = v.model:GetAttribute("BeamAim")
		aim = if typeof(value) == "Vector3" then value else FORWARD
	end
	local muzzle = v.muzzle
	if not firing or muzzle == nil then
		hideBeam(v)
		return
	end

	local fx = v.beam or makeBeamFx()
	v.beam = fx
	fx.outer.Attachment0 = muzzle
	fx.core.Attachment0 = muzzle

	local origin = muzzle.WorldPosition
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
	fx.target.WorldPosition = if hit then hit.Position else origin + reach

	local pulse = 1 + 0.15 * math.sin(now * PULSE_SPEED)
	fx.outer.Width0 = B.WIDTH * pulse
	fx.outer.Width1 = B.WIDTH * 0.8 * pulse
	fx.core.Width0 = B.WIDTH * 0.35 * pulse
	fx.core.Width1 = B.WIDTH * 0.25 * pulse
	fx.outer.Enabled = true
	fx.core.Enabled = true
	fx.sparks.Rate = if hit then SPARK_RATE else 0
	fx.light.Enabled = hit ~= nil
end

local function updateVisual(v: Visual, dt: number, now: number)
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
	local speedShare =
		math.clamp(speed / numberAttribute(v.model, "MaxSpeed", DEFAULT_MAX_SPEED), 0, 1)

	-- Engines: dark when parked, a low idle when piloted, brighter and with
	-- more exhaust as the ship speeds up (or, for your own, as you throttle).
	local target = 0
	if piloted then
		local drive = if mine
			then math.max(ClientState.flight.throttle, speedShare * 0.6)
			else speedShare
		target = math.max(IDLE_POWER, drive)
	end
	v.power = FlightMath.smooth(v.power, target, POWER_RESPONSE, dt)
	for _, glow in v.glows do
		glow.Color = GLOW_IDLE:Lerp(GLOW_FULL, v.power)
		glow.Transparency = 0.5 * (1 - v.power)
	end
	local rate = if v.power > IDLE_POWER + 0.05 then EXHAUST_RATE * v.power else 0
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
		updateBeam(v, hull, mine, now)
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
	if v.beam then
		v.beam.target:Destroy()
	end
end

local function update(dt: number)
	local now = os.clock()
	for _, v in visuals do
		updateVisual(v, dt, now)
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

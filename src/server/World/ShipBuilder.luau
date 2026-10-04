--!strict
-- Ship models built from parts. Stage 2 has one greybox design, the Starter
-- Shuttle; every ship uses it until later stages add their own silhouettes.
--
-- The names below are the contract ShipSystem and the client rely on:
--   Hull                  PrimaryPart. Every other part is welded to it.
--   PilotSeat             Seat with CanTouch off, so nobody sits by bumping it.
--   Hull.Thrust           Attachment at the hull centre, used by:
--   Hull.Engine           LinearVelocity, world-relative target velocity
--   Hull.Steer            AlignOrientation, one-attachment target orientation
--   Hull.ExitLeft/ExitRight/ExitTop   where the pilot floats when leaving
--   Hull.BoardPrompt      ProximityPrompt tagged "BoardPrompt"
--   Hull.BeamOrigin       Attachment at the laser's muzzle, under the nose
--   Hull.NozzleL/NozzleR  Attachments behind the engines (+Y points back),
--                         each with an "Exhaust" ParticleEmitter (Rate 0)
--   Hull.WingTrail        Two Trails off the wing tips (disabled)
--   EngineGlow, BeamEmitter   neon parts; clients animate the glow
-- Effects start idle: each client's ShipEffectsController drives them.
-- Ship space: -Z is forward (the hull's LookVector), +Y is up.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local COLORS = Config.World.COLORS

local BOARD_TAG = "BoardPrompt"

-- Force and torque limits for the flight constraints. High enough that the
-- target velocity and orientation are reached almost immediately; the
-- controller limits acceleration and turn rate itself.
local ENGINE_MAX_FORCE = 1e6
local STEER_MAX_TORQUE = 1e7
local STEER_RESPONSIVENESS = 30
local STEER_MAX_ANGULAR_VELOCITY = 6

type PartSpec = {
	name: string,
	className: string?,
	size: Vector3,
	offset: CFrame,
	color: string?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
}

-- Starter Shuttle: about 16 studs wide, 19 long and 7 tall.
local function shuttle(accent: string): { PartSpec }
	return {
		{
			name = "Nose",
			className = "WedgePart",
			size = Vector3.new(6, 4, 4),
			offset = CFrame.new(0, 0, -8),
		},
		{
			name = "Windscreen",
			size = Vector3.new(4, 2, 0.4),
			offset = CFrame.new(0, 3, -4) * CFrame.Angles(math.rad(25), 0, 0),
			color = COLORS.glass,
			material = Enum.Material.Glass,
			transparency = 0.35,
			collide = false,
		},
		{
			name = "Wing",
			size = Vector3.new(4.5, 0.6, 6),
			offset = CFrame.new(-5.25, -0.6, 1.5),
			color = COLORS.hullAlt,
		},
		{
			name = "Wing",
			size = Vector3.new(4.5, 0.6, 6),
			offset = CFrame.new(5.25, -0.6, 1.5),
			color = COLORS.hullAlt,
		},
		{
			name = "WingLight",
			size = Vector3.new(0.6, 0.8, 6),
			offset = CFrame.new(-7.8, -0.6, 1.5),
			color = accent,
			material = Enum.Material.Neon,
		},
		{
			name = "WingLight",
			size = Vector3.new(0.6, 0.8, 6),
			offset = CFrame.new(7.8, -0.6, 1.5),
			color = accent,
			material = Enum.Material.Neon,
		},
		{
			name = "EnginePod",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(4, 2.4, 2.4),
			offset = CFrame.new(-1.8, -0.2, 7) * CFrame.Angles(0, math.pi / 2, 0),
			color = COLORS.truss,
		},
		{
			name = "EnginePod",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(4, 2.4, 2.4),
			offset = CFrame.new(1.8, -0.2, 7) * CFrame.Angles(0, math.pi / 2, 0),
			color = COLORS.truss,
		},
		{
			name = "EngineGlow",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.4, 2, 2),
			offset = CFrame.new(-1.8, -0.2, 9.2) * CFrame.Angles(0, math.pi / 2, 0),
			color = "#7FD4FF",
			material = Enum.Material.Neon,
			collide = false,
		},
		{
			name = "EngineGlow",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.4, 2, 2),
			offset = CFrame.new(1.8, -0.2, 9.2) * CFrame.Angles(0, math.pi / 2, 0),
			color = "#7FD4FF",
			material = Enum.Material.Neon,
			collide = false,
		},
		{
			name = "TailFin",
			size = Vector3.new(0.6, 3, 4),
			offset = CFrame.new(0, 3.5, 4),
			color = accent,
		},
		{
			-- Mining laser lens, poking out of the nose's lower front.
			name = "BeamEmitter",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1.6, 0.8, 0.8),
			offset = CFrame.new(0, -1.6, -9.8) * CFrame.Angles(0, math.pi / 2, 0),
			color = Config.Beam.COLOR,
			material = Enum.Material.Neon,
			collide = false,
		},
	}
end

local function sequence(from: number, to: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to),
	})
end

-- Engine exhaust: particles left behind in space, so they stream into a
-- tail at speed. Rate stays 0 here; clients set it from the throttle.
local function exhaust(parent: Attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Exhaust"
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Speed = NumberRange.new(22, 30)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Lifetime = NumberRange.new(0.18, 0.32)
	emitter.Size = sequence(1.1, 0.15)
	emitter.Transparency = sequence(0.1, 1)
	emitter.Color = ColorSequence.new(Color3.fromHex("#D6F4FF"), Color3.fromHex("#3A7BFF"))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.VelocityInheritance = 0
	emitter.LockedToPart = false
	emitter.Parent = parent
end

-- A thin ribbon off a wing tip, between two attachments 0.6 studs apart.
local function wingTrail(hull: BasePart, side: string, x: number, accent: string)
	local top = Instance.new("Attachment")
	top.Name = `Trail{side}Top`
	top.CFrame = CFrame.new(x, -0.3, 4.5)
	top.Parent = hull
	local bottom = Instance.new("Attachment")
	bottom.Name = `Trail{side}Bottom`
	bottom.CFrame = CFrame.new(x, -0.9, 4.5)
	bottom.Parent = hull

	local trail = Instance.new("Trail")
	trail.Name = "WingTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(Color3.fromHex(accent))
	trail.Transparency = sequence(0.35, 1)
	trail.WidthScale = sequence(1, 0.2)
	trail.Lifetime = 0.5
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.LightEmission = 0.7
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = hull
end

local function style(
	part: BasePart,
	color: string?,
	material: Enum.Material?,
	transparency: number?
)
	part.Color = Color3.fromHex(color or COLORS.hull)
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.CastShadow = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function weld(hull: BasePart, part: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = hull
	joint.Part1 = part
	joint.Parent = part
end

local function attachment(name: string, position: Vector3, parent: BasePart): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = CFrame.new(position)
	att.Parent = parent
	return att
end

local ShipBuilder = {}

ShipBuilder.BOARD_TAG = BOARD_TAG
-- Box around a berth (centred on the hull) that every ship fits inside. It
-- must be clear of other ships and players before a ship appears there.
ShipBuilder.BERTH_BOX = Vector3.new(20, 14, 24)

-- Builds a parked ship with its hull centred on `cframe`. The hull is
-- anchored; ShipSystem unanchors it when the owner boards.
function ShipBuilder.build(shipId: string, cframe: CFrame, accent: string): Model
	local def = Config.Ships.BY_ID[shipId] or Config.Ships.BY_ID[Config.Ships.STARTER_SHIP]
	local paint = Color3.fromHex(def.paint)
	local plain = Color3.fromHex(COLORS.hull)

	local model = Instance.new("Model")
	model.Name = def.id

	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(6, 4, 12)
	hull.CFrame = cframe
	hull.Anchored = true
	style(hull, COLORS.hull)
	hull.Parent = model
	model.PrimaryPart = hull

	for _, spec in shuttle(accent) do
		local part = Instance.new(spec.className or "Part") :: BasePart
		part.Name = spec.name
		if spec.shape and part:IsA("Part") then
			part.Shape = spec.shape
		end
		part.Size = spec.size
		part.CFrame = cframe * spec.offset
		part.Anchored = false
		part.CanCollide = spec.collide ~= false
		style(part, spec.color, spec.material, spec.transparency)
		weld(hull, part)
		part.Parent = model
	end

	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = cframe * CFrame.new(0, 2.5, -1)
	seat.Anchored = false
	style(seat, COLORS.console)
	weld(hull, seat)
	seat.Parent = model

	local thrust = attachment("Thrust", Vector3.zero, hull)
	attachment("ExitLeft", Vector3.new(-10, 2, -1), hull)
	attachment("ExitRight", Vector3.new(10, 2, -1), hull)
	attachment("ExitTop", Vector3.new(0, 8, 2), hull)
	attachment("BeamOrigin", Vector3.new(0, -1.6, -10.7), hull)
	for _, nozzle in { { name = "NozzleL", x = -1.8 }, { name = "NozzleR", x = 1.8 } } do
		local att = attachment(nozzle.name, Vector3.new(nozzle.x, -0.2, 9.5), hull)
		-- Particle emitters on an attachment emit along its +Y: point it back.
		att.CFrame *= CFrame.Angles(math.rad(90), 0, 0)
		exhaust(att)
	end
	wingTrail(hull, "L", -7.8, accent)
	wingTrail(hull, "R", 7.8, accent)

	local engine = Instance.new("LinearVelocity")
	engine.Name = "Engine"
	engine.Attachment0 = thrust
	engine.RelativeTo = Enum.ActuatorRelativeTo.World
	engine.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	engine.MaxForce = ENGINE_MAX_FORCE
	engine.VectorVelocity = Vector3.zero
	engine.Parent = hull

	local steer = Instance.new("AlignOrientation")
	steer.Name = "Steer"
	steer.Mode = Enum.OrientationAlignmentMode.OneAttachment
	steer.Attachment0 = thrust
	steer.MaxTorque = STEER_MAX_TORQUE
	steer.MaxAngularVelocity = STEER_MAX_ANGULAR_VELOCITY
	steer.Responsiveness = STEER_RESPONSIVENESS
	steer.Parent = hull

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Board"
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Movement.BOARD_DISTANCE
	prompt.RequiresLineOfSight = false
	CollectionService:AddTag(prompt, BOARD_TAG)
	prompt.Parent = hull

	model:SetAttribute("ShipId", def.id)
	-- Each ship type has its own paint: recolour the plain hull parts.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Color == plain then
			part.Color = paint
		end
	end
	return model
end

return ShipBuilder

--!strict
-- Ship models. A ship whose imported model exists (Util/ShipModel, under
-- ReplicatedStorage/Assets/Ships) wears it as a "Skin" Model of massless,
-- non-colliding parts welded to an invisible Hull; the engine glows, nozzles,
-- laser muzzle and wing trails move to the model's measured extents. Without
-- the model, the greybox shuttle below stands in.
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
local ShipModel = require(ReplicatedStorage.Shared.Util.ShipModel)

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

-- Where a ship's effects sit, in hull space (studs, -Z forward).
type Layout = {
	nozzleX: number, -- engines at +-nozzleX
	nozzleY: number,
	glowZ: number, -- engine glow discs
	glowSize: number,
	nozzleZ: number, -- exhaust attachments, just behind the glow
	beamY: number,
	beamZ: number, -- laser muzzle (BeamOrigin); the lens sits just behind it
	wingX: number, -- wing trails at +-wingX
	wingZ: number,
	seatY: number,
	exitX: number,
	exitTop: number,
}

-- The greybox shuttle's layout.
local SHUTTLE_LAYOUT: Layout = {
	nozzleX = 1.8,
	nozzleY = -0.2,
	glowZ = 9.2,
	glowSize = 2,
	nozzleZ = 9.5,
	beamY = -1.6,
	beamZ = -10.7,
	wingX = 7.8,
	wingZ = 4.5,
	seatY = 2.5,
	exitX = 10,
	exitTop = 8,
}

-- A layout fitted to a model's bounding box (centred on the hull).
local function measuredLayout(size: Vector3): Layout
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local glow = math.clamp(size.Y * 0.5, 0.8, 2.2)
	return {
		nozzleX = math.max(hx * 0.2, glow * 0.6),
		nozzleY = 0,
		glowZ = hz - 0.1,
		glowSize = glow,
		nozzleZ = hz + 0.3,
		beamY = -hy * 0.3,
		beamZ = -hz - 0.6,
		wingX = hx * 0.95,
		wingZ = hz * 0.4,
		seatY = hy,
		exitX = hx + 4,
		exitTop = hy + 6,
	}
end

-- Neon parts every ship has, wherever its layout puts them.
local function effectParts(layout: Layout): { PartSpec }
	local specs: { PartSpec } = {}
	for _, side in { -1, 1 } do
		table.insert(specs, {
			name = "EngineGlow",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.4, layout.glowSize, layout.glowSize),
			offset = CFrame.new(side * layout.nozzleX, layout.nozzleY, layout.glowZ)
				* CFrame.Angles(0, math.pi / 2, 0),
			color = "#7FD4FF",
			material = Enum.Material.Neon,
			collide = false,
		})
	end
	table.insert(specs, {
		-- Mining laser lens, just behind the muzzle.
		name = "BeamEmitter",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1.6, 0.8, 0.8),
		offset = CFrame.new(0, layout.beamY, layout.beamZ + 0.9) * CFrame.Angles(0, math.pi / 2, 0),
		color = Config.Beam.COLOR,
		material = Enum.Material.Neon,
		collide = false,
	})
	return specs
end

-- Starter Shuttle greybox: about 16 studs wide, 19 long and 7 tall.
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
			name = "TailFin",
			size = Vector3.new(0.6, 3, 4),
			offset = CFrame.new(0, 3.5, 4),
			color = accent,
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
local function wingTrail(hull: BasePart, side: string, x: number, z: number, accent: string)
	local top = Instance.new("Attachment")
	top.Name = `Trail{side}Top`
	top.CFrame = CFrame.new(x, -0.3, z)
	top.Parent = hull
	local bottom = Instance.new("Attachment")
	bottom.Name = `Trail{side}Bottom`
	bottom.CFrame = CFrame.new(x, -0.9, z)
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

-- Imported models are shrunk if needed to fit inside this (within the berth).
local SKIN_LIMIT = Vector3.new(19, 12, 23)

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

	-- The imported model, if it's there, fitted inside the berth.
	local source = ShipModel.find(def)
	local skin: Model? = nil
	local layout = SHUTTLE_LAYOUT
	if source then
		local ok, fitted, size = pcall(ShipModel.fit, source, def, SKIN_LIMIT)
		if ok then
			skin = fitted
			layout = measuredLayout(size)
		else
			warn(`[ShipBuilder] Could not fit the {def.model} model: {fitted}`)
		end
	end

	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(6, 4, 12)
	hull.CFrame = cframe
	hull.Anchored = true
	style(hull, COLORS.hull, nil, if skin then 1 else 0)
	hull.Parent = model
	model.PrimaryPart = hull

	local specs = effectParts(layout)
	if skin == nil then
		for _, spec in shuttle(accent) do
			table.insert(specs, spec)
		end
	end
	for _, spec in specs do
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
	seat.CFrame = cframe * CFrame.new(0, layout.seatY, -1)
	seat.Anchored = false
	style(seat, COLORS.console, nil, if skin then 1 else 0)
	weld(hull, seat)
	seat.Parent = model

	local thrust = attachment("Thrust", Vector3.zero, hull)
	attachment("ExitLeft", Vector3.new(-layout.exitX, 2, -1), hull)
	attachment("ExitRight", Vector3.new(layout.exitX, 2, -1), hull)
	attachment("ExitTop", Vector3.new(0, layout.exitTop, 2), hull)
	attachment("BeamOrigin", Vector3.new(0, layout.beamY, layout.beamZ), hull)
	for _, nozzle in { { name = "NozzleL", side = -1 }, { name = "NozzleR", side = 1 } } do
		local position = Vector3.new(nozzle.side * layout.nozzleX, layout.nozzleY, layout.nozzleZ)
		local att = attachment(nozzle.name, position, hull)
		-- Particle emitters on an attachment emit along its +Y: point it back.
		att.CFrame *= CFrame.Angles(math.rad(90), 0, 0)
		exhaust(att)
	end
	wingTrail(hull, "L", -layout.wingX, layout.wingZ, accent)
	wingTrail(hull, "R", layout.wingX, layout.wingZ, accent)

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

	if skin then
		-- Cosmetic only: the hidden Hull does the physics and collisions.
		skin:PivotTo(cframe * skin:GetPivot())
		for _, part in skin:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				if not ShipModel.textured(part) then
					part.Color = paint
				end
				weld(hull, part)
			end
		end
		skin.Parent = model
	end
	return model
end

return ShipBuilder

--!strict
-- Big moments in a star's life, drawn on this client for every star
-- (yours and other players'), so the galaxy feels alive:
--
--   birth(at, radius, color)       a new star ignites: flash, twin shockwaves,
--                                  sparks and a burst of light
--   levelUp(at, radius, color)     rising rings and a sparkle fountain
--   supernova(at, radius, color)   evolving: a white-hot blast, a huge
--                                  shockwave in the orbital plane, then the
--                                  new colour washing outwards
--   materialize(part, color)       a planet condenses out of sparkles
--
-- Parts are local (anchored, no collisions, under the camera) and cleaned up
-- with Debris. Shockwaves use the ForceField material, which glows brightest
-- at its edges, so a flat disc reads as a ring. Reduced effects draws fewer
-- particles.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)

local StarFx = {}

local folder: Folder? = nil

local function parent(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "GaG_StarFx"
	created.Parent = Workspace.CurrentCamera
	folder = created
	return created
end

local function count(n: number): number
	return if ClientState.reducedEffects then math.ceil(n / 4) else n
end

local function part(shape: Enum.PartType, color: Color3, cframe: CFrame, size: Vector3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = cframe
	p.Size = size
	p.Parent = parent()
	return p
end

-- A neon ball that grows from `from` to `to` studs across while fading.
local function flash(
	at: Vector3,
	from: number,
	to: number,
	color: Color3,
	time: number,
	alpha: number
)
	local ball = part(Enum.PartType.Ball, color, CFrame.new(at), Vector3.one * from)
	ball.Transparency = alpha
	TweenService:Create(
		ball,
		TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * to, Transparency = 1 }
	):Play()
	Debris:AddItem(ball, time + 0.1)
end

-- A flat glowing ring in the plane `cframe` faces along its X axis.
local function shockwave(cframe: CFrame, from: number, to: number, color: Color3, time: number)
	local ring = part(Enum.PartType.Cylinder, color, cframe, Vector3.new(0.3, from, from))
	ring.Material = Enum.Material.ForceField
	ring.Transparency = 0.15
	TweenService:Create(
		ring,
		TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, to, to), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, time + 0.1)
end

local function light(at: Vector3, color: Color3, range: number, brightness: number, time: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = at
	attachment.Parent = Workspace.Terrain
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = math.min(range, 60)
	glow.Brightness = brightness
	glow.Parent = attachment
	TweenService:Create(glow, TweenInfo.new(time), { Brightness = 0 }):Play()
	Debris:AddItem(attachment, time + 0.1)
end

local function sparks(
	at: Vector3,
	amount: number,
	color: Color3,
	speed: NumberRange,
	size: number,
	lifetime: NumberRange,
	direction: Vector3?
)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = at
	if direction then
		attachment.WorldCFrame = CFrame.lookAt(at, at + direction)
			* CFrame.Angles(-math.pi / 2, 0, 0)
	end
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Speed = speed
	emitter.Lifetime = lifetime
	emitter.SpreadAngle = if direction then Vector2.new(25, 25) else Vector2.new(180, 180)
	emitter.Drag = 1.5
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(0.3, size * 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = attachment
	emitter:Emit(count(amount))
	Debris:AddItem(attachment, lifetime.Max + 0.2)
end

function StarFx.birth(at: Vector3, radius: number, color: Color3)
	flash(at, radius * 0.5, radius * 6, WHITE, 0.6, 0)
	flash(at, radius, radius * 4, color, 1.1, 0.2)
	local plane = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	shockwave(plane, radius * 2, radius * 16, color, 1.4)
	shockwave(CFrame.new(at) * CFrame.Angles(0, math.rad(90), 0), radius * 2, radius * 10, WHITE, 1)
	sparks(
		at,
		70,
		color,
		NumberRange.new(radius * 2, radius * 5),
		radius * 0.35,
		NumberRange.new(1, 2)
	)
	light(at, color, radius * 8, 12, 1.5)
end

function StarFx.levelUp(at: Vector3, radius: number, color: Color3)
	flash(at, radius * 2, radius * 3.2, color, 0.6, 0.3)
	-- Three rings rise past the star, one after another.
	for index = 0, 2 do
		task.delay(index * 0.15, function()
			local start = CFrame.new(at + Vector3.new(0, -radius, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			local ring = part(
				Enum.PartType.Cylinder,
				color:Lerp(WHITE, 0.4),
				start,
				Vector3.new(0.3, radius * 2.4, radius * 2.4)
			)
			ring.Transparency = 0.2
			TweenService
				:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = start + Vector3.new(0, radius * 3.5, 0),
					Size = Vector3.new(0.1, radius * 3.4, radius * 3.4),
					Transparency = 1,
				})
				:Play()
			Debris:AddItem(ring, 1)
		end)
	end
	sparks(
		at + Vector3.new(0, radius, 0),
		45,
		color,
		NumberRange.new(radius * 1.5, radius * 3),
		radius * 0.25,
		NumberRange.new(0.8, 1.5),
		Vector3.yAxis
	)
	light(at, color, radius * 6, 8, 1)
end

function StarFx.supernova(at: Vector3, radius: number, color: Color3)
	flash(at, radius * 2, radius * 14, WHITE, 0.9, 0)
	task.delay(0.12, function()
		flash(at, radius * 2, radius * 8, color, 1.4, 0.1)
	end)
	local plane = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	shockwave(plane, radius * 2, radius * 30, WHITE, 1.8)
	task.delay(0.2, function()
		shockwave(plane * CFrame.Angles(math.rad(25), 0, 0), radius * 2, radius * 22, color, 1.6)
	end)
	sparks(
		at,
		140,
		color,
		NumberRange.new(radius * 3, radius * 8),
		radius * 0.45,
		NumberRange.new(1.2, 2.4)
	)
	light(at, color, radius * 12, 18, 2.2)
end

function StarFx.materialize(planet: BasePart, color: Color3)
	local at = planet.Position
	local size = planet.Size.X
	-- Sparkles rush inwards from a shell around the planet.
	local shell = part(Enum.PartType.Ball, color, CFrame.new(at), Vector3.one * size * 4)
	shell.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Speed = NumberRange.new(size * 2.5, size * 3)
	emitter.Lifetime = NumberRange.new(0.5, 0.65)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = true
	emitter.Color = ColorSequence.new(color, WHITE)
	emitter.Size = NumberSequence.new(size * 0.18, size * 0.05)
	emitter.Parent = shell
	emitter:Emit(count(60))
	Debris:AddItem(shell, 1)
	task.delay(0.5, function()
		flash(planet.Position, size, size * 3, WHITE, 0.5, 0)
		shockwave(
			CFrame.new(planet.Position) * CFrame.Angles(0, 0, math.rad(90)),
			size,
			size * 6,
			color,
			0.8
		)
		light(planet.Position, color, size * 6, 8, 0.8)
	end)
end

return StarFx

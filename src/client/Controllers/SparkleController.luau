--!strict
-- Ambient sparkles: tiny twinkling specks of light scattered through space
-- around the camera, in the suit and in a ship, for a spacey atmosphere.
-- Local to this client and purely visual.
--
-- An invisible box centred on the camera scatters still particles through
-- its volume. Each one fades in, twinkles and fades out where it appeared,
-- so they drift past as you move. Reduced effects shows far fewer.
-- The sparkle texture ships with every Roblox client.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local RENDER_STEP = "GaG_Sparkles"
local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local BOX_SIZE = 420
local RATE = 45
local REDUCED_RATE = 8
local LIFETIME = NumberRange.new(4, 8)

local SparkleController = {}

local box: Part
local sparkles: ParticleEmitter
local specks: ParticleEmitter

local function emitter(name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Lifetime = LIFETIME
	e.Speed = NumberRange.new(0)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.LockedToPart = false
	-- Fade in, hold, fade out, so nothing pops.
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.2),
		NumberSequenceKeypoint.new(0.75, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = box
	return e
end

local function build()
	box = Instance.new("Part")
	box.Name = "GaG_Sparkles"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.one * BOX_SIZE

	-- Star-shaped glints that grow and shrink as they twinkle.
	sparkles = emitter("Sparkles")
	sparkles.Texture = TEXTURE
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.3, 1.6),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(0.7, 1.4),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-30, 30)
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 215, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 225, 170)),
	})

	-- Plain pinpoints in between, for depth.
	specks = emitter("Specks")
	specks.Size = NumberSequence.new(0.18)
	specks.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255))
end

local function follow()
	box.CFrame = CFrame.new(Workspace.CurrentCamera.CFrame.Position)
end

local function refresh()
	local reduced = ClientState.reducedEffects
	sparkles.Rate = if reduced then REDUCED_RATE else RATE
	specks.Rate = if reduced then REDUCED_RATE else RATE * 1.5
end

function SparkleController.init()
	build()
	ClientState.effectsChanged:Connect(refresh)
end

function SparkleController.start()
	refresh()
	box.Parent = Workspace.CurrentCamera
	follow()
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 4, follow)
end

return SparkleController

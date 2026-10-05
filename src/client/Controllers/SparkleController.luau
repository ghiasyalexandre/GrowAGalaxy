--!strict
-- Ambient sparkles: twinkling specks of light scattered through space around
-- the camera, in the suit and in a ship, for a vivid, spacey atmosphere.
-- Local to this client and purely visual.
--
-- An invisible box centred on the camera scatters still particles through
-- its volume. Each fades in, twinkles and fades out where it appeared, so
-- they drift past as you move:
--   * glints in four saturated colours (cyan, magenta, gold, violet), drawn
--     extra bright (Brightness above 1 blooms),
--   * rare big flares that flash white and spin,
--   * fine pinpoints in between, for depth.
-- Reduced effects shows far fewer. The sparkle texture ships with every
-- Roblox client.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local RENDER_STEP = "GaG_Sparkles"
local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local BOX_SIZE = 460
local LIFETIME = NumberRange.new(3, 7)
local PALETTE = {
	Color3.fromRGB(90, 230, 255), -- cyan
	Color3.fromRGB(255, 90, 220), -- magenta
	Color3.fromRGB(255, 210, 80), -- gold
	Color3.fromRGB(170, 120, 255), -- violet
}
-- Particles per second, full and reduced effects.
local GLINT_RATE, GLINT_REDUCED = 22, 3 -- per colour
local FLARE_RATE, FLARE_REDUCED = 3, 0.5
local SPECK_RATE, SPECK_REDUCED = 90, 12

local SparkleController = {}

local box: Part
local glints: { ParticleEmitter } = {}
local flares: ParticleEmitter
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
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.8, 0),
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

	-- Star-shaped glints that swell and shrink twice as they twinkle, white at
	-- the heart of each twinkle and saturated colour around it.
	for index, color in PALETTE do
		local glint = emitter(`Glints{index}`)
		glint.Texture = TEXTURE
		glint.Brightness = 4
		glint.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.25, 2.6),
			NumberSequenceKeypoint.new(0.45, 0.9),
			NumberSequenceKeypoint.new(0.7, 2.2),
			NumberSequenceKeypoint.new(1, 0.4),
		})
		glint.Rotation = NumberRange.new(0, 360)
		glint.RotSpeed = NumberRange.new(-45, 45)
		glint.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.25, color:Lerp(Color3.new(1, 1, 1), 0.6)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(0.7, color:Lerp(Color3.new(1, 1, 1), 0.5)),
			ColorSequenceKeypoint.new(1, color),
		})
		table.insert(glints, glint)
	end

	-- Now and then a big flare flashes white, spins and fades to a colour.
	flares = emitter("Flares")
	flares.Texture = TEXTURE
	flares.Brightness = 6
	flares.Lifetime = NumberRange.new(1.2, 2)
	flares.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 7),
		NumberSequenceKeypoint.new(0.4, 3),
		NumberSequenceKeypoint.new(1, 0),
	})
	flares.Rotation = NumberRange.new(0, 360)
	flares.RotSpeed = NumberRange.new(-180, 180)
	flares.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(200, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 230)),
	})

	-- Fine pinpoints in between, for depth.
	specks = emitter("Specks")
	specks.Brightness = 3
	specks.Size = NumberSequence.new(0.22)
	specks.Color = ColorSequence.new(Color3.fromRGB(200, 225, 255), Color3.fromRGB(255, 230, 200))
end

local function follow()
	box.CFrame = CFrame.new(Workspace.CurrentCamera.CFrame.Position)
end

local function refresh()
	local reduced = ClientState.reducedEffects
	for _, glint in glints do
		glint.Rate = if reduced then GLINT_REDUCED else GLINT_RATE
	end
	flares.Rate = if reduced then FLARE_REDUCED else FLARE_RATE
	specks.Rate = if reduced then SPECK_REDUCED else SPECK_RATE
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

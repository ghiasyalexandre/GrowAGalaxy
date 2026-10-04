--!strict
-- Faint dust drifting in space around the flight camera, so speed and
-- turning are visible even far from anything else. Local to this client and
-- only while flying.
--
-- An invisible box ahead of the camera scatters still particles through its
-- volume. They stay where they appear, so the ship flies through them.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local RENDER_STEP = "GaG_SpaceDust"
local BOX_SIZE = 140
local BOX_AHEAD = 50 -- studs in front of the camera
local RATE = 90
local LIFETIME = 5

local SpaceDustController = {}

local box: Part
local dust: ParticleEmitter

local function build()
	box = Instance.new("Part")
	box.Name = "GaG_SpaceDust"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.new(BOX_SIZE, BOX_SIZE, BOX_SIZE)

	dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = RATE
	dust.Lifetime = NumberRange.new(LIFETIME)
	dust.Speed = NumberRange.new(0)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	-- Fade in and out so particles never pop.
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(205, 220, 255))
	dust.LightEmission = 1
	dust.LightInfluence = 0
	dust.LockedToPart = false
	dust.Enabled = false
	dust.Parent = box
	-- Parented to the camera (local only) the first time you fly.
end

local function follow()
	local camera = Workspace.CurrentCamera.CFrame
	box.CFrame = CFrame.new(camera.Position + camera.LookVector * BOX_AHEAD)
end

local function refresh()
	local flying = ClientState.mode == "ship"
	dust.Enabled = flying
	dust.Rate = if ClientState.reducedEffects then RATE / 3 else RATE
	if flying then
		box.Parent = Workspace.CurrentCamera
		follow()
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 3, follow)
	else
		-- Leave the box in place so the last particles fade out, but stop
		-- moving it.
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end
end

function SpaceDustController.init()
	build()
	ClientState.modeChanged:Connect(refresh)
	ClientState.effectsChanged:Connect(refresh)
end

return SpaceDustController

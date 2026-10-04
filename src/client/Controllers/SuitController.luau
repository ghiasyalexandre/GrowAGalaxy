--!strict
-- Zero-g spacesuit. Whenever the player isn't seated, their character floats
-- (Humanoid.PlatformStand) and two constraints on its root part move it:
-- a LinearVelocity towards the input direction, relative to the camera, and
-- an AlignOrientation facing the camera's heading.
--
-- Gentle acceleration, a strong brake, and an optional stabilizer that slows
-- you to a stop when you let go. With the stabilizer off you keep drifting.
-- This runs on the client because each client simulates its own character;
-- the server checks the result (FlightGuard).
--
-- So floating doesn't look frozen, R15 characters play their avatar's own
-- swim animations (a slow tread while still or drifting, the stroke while
-- thrusting), and every character leans into the direction it's moving.
-- Animations played on your own character replicate, so everyone sees them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FlightMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("FlightMath")
)
local Input = require(script.Parent.Parent.Input)

local M = Config.Movement

local MAX_FORCE = 20000
local MAX_TORQUE = 100000
local TURN_RESPONSIVENESS = 20
-- A jump bigger than this between frames means the server moved us
-- (airlock, Return to Station, leaving a ship): stop drifting afterwards.
local TELEPORT_DISTANCE = 30
local SETTLE_TIME = 0.4
local INPUT_DEADZONE = 0.05
local LEAN = math.rad(M.SUIT_LEAN_DEGREES)
local ROLL = math.rad(M.SUIT_ROLL_DEGREES)
local BACK_LEAN_SHARE = 0.4 -- moving backwards leans back less far
local ANIMATION_FADE = 0.35
-- Roblox's default R15 swim animations, used when the avatar's Animate
-- script doesn't name its own.
local DEFAULT_SWIM = "rbxassetid://507784897"
local DEFAULT_SWIM_IDLE = "rbxassetid://507785072"

local SuitController = {}

type Suit = {
	humanoid: Humanoid,
	root: BasePart,
	linear: LinearVelocity,
	align: AlignOrientation,
	swim: AnimationTrack?,
	swimIdle: AnimationTrack?,
}

local suit: Suit? = nil
local active = false
local lastPosition: Vector3? = nil
local settleUntil = 0
local facing = CFrame.new()
local lean = 0
local roll = 0
local swimming: boolean? = nil -- which track is playing; nil = neither

-- One of the avatar's swim animations (from its Animate script, so custom
-- animation packs carry over), loaded as a looping Movement-priority track.
local function loadTrack(
	character: Model,
	animator: Animator,
	name: string,
	fallback: string
): AnimationTrack?
	local animate = character:FindFirstChild("Animate")
	local value = animate and animate:FindFirstChild(name)
	local source = value and value:FindFirstChildOfClass("Animation")
	local animation = Instance.new("Animation")
	animation.AnimationId = if source and source.AnimationId ~= ""
		then source.AnimationId
		else fallback
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[SuitController] Could not load the {name} animation: {track}`)
		return nil
	end
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	return track
end

local function stopAnimations(s: Suit)
	if s.swim then
		s.swim:Stop(ANIMATION_FADE)
	end
	if s.swimIdle then
		s.swimIdle:Stop(ANIMATION_FADE)
	end
	swimming = nil
end

-- Stroke while thrusting, tread while still or drifting; the stroke speeds
-- up with speed.
local function animate(s: Suit, pushing: boolean, speed: number)
	if pushing ~= swimming then
		swimming = pushing
		local play = if pushing then s.swim else s.swimIdle
		local stop = if pushing then s.swimIdle else s.swim
		if stop then
			stop:Stop(ANIMATION_FADE)
		end
		if play then
			play:Play(ANIMATION_FADE)
		end
	end
	if pushing and s.swim then
		s.swim:AdjustSpeed(0.6 + 0.8 * math.clamp(speed / M.SUIT_MAX_SPEED, 0, 1))
	end
end

local function setup(character: Model)
	suit = nil
	active = false
	lastPosition = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	-- A quick respawn can start a newer setup while this one waited.
	if Players.LocalPlayer.Character ~= character then
		return
	end
	-- No jumping in zero-g. This also stops Space from leaving a ship's seat
	-- and hides the touch jump button.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local attachment = Instance.new("Attachment")
	attachment.Name = "SuitAttachment"
	attachment.Parent = root

	local linear = Instance.new("LinearVelocity")
	linear.Name = "SuitThrust"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = MAX_FORCE
	linear.Enabled = false
	linear.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "SuitStabilizer"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = MAX_TORQUE
	align.Responsiveness = TURN_RESPONSIVENESS
	align.Enabled = false
	align.Parent = root

	local swim: AnimationTrack? = nil
	local swimIdle: AnimationTrack? = nil
	local animator = humanoid:WaitForChild("Animator", 10)
	if Players.LocalPlayer.Character ~= character then
		return
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 and animator and animator:IsA("Animator") then
		swim = loadTrack(character, animator, "swim", DEFAULT_SWIM)
		swimIdle = loadTrack(character, animator, "swimidle", DEFAULT_SWIM_IDLE)
	end

	facing = root.CFrame.Rotation
	lean, roll = 0, 0
	swimming = nil
	settleUntil = os.clock() + SETTLE_TIME
	suit = {
		humanoid = humanoid,
		root = root,
		linear = linear,
		align = align,
		swim = swim,
		swimIdle = swimIdle,
	}
end

local function targetVelocity(current: Vector3, position: Vector3, dt: number): Vector3
	if os.clock() < settleUntil then
		return Vector3.zero
	end
	local camera = Workspace.CurrentCamera
	local input = Input.moveVector()
	local velocity: Vector3
	if Input.isHeld("Brake") then
		velocity = FlightMath.step(current, Vector3.zero, M.SUIT_ACCELERATION, M.SUIT_BRAKING, dt)
	elseif input.Magnitude > INPUT_DEADZONE then
		local target = FlightMath.suitTarget(input, camera.CFrame, M.SUIT_MAX_SPEED)
		velocity = FlightMath.step(current, target, M.SUIT_ACCELERATION, M.SUIT_BRAKING, dt)
	elseif ClientState.stabilization then
		velocity =
			FlightMath.step(current, Vector3.zero, M.SUIT_ACCELERATION, M.SUIT_STABILIZE_DRAG, dt)
	elseif current.Magnitude > M.SUIT_MAX_SPEED then
		-- Drifting, but never faster than the suit can go (after a bump).
		velocity = FlightMath.step(current, current.Unit * M.SUIT_MAX_SPEED, 0, M.SUIT_BRAKING, dt)
	else
		velocity = current
	end
	return FlightMath.clampToBounds(
		position,
		velocity,
		M.FLIGHT_BOUNDS_RADIUS,
		M.FLIGHT_BOUNDS_HEIGHT
	)
end

local function step(dt: number)
	local s = suit
	if s == nil or s.root.Parent == nil then
		return
	end
	local shouldFloat = s.humanoid.Health > 0 and s.humanoid.SeatPart == nil
	if shouldFloat ~= active then
		active = shouldFloat
		s.linear.Enabled = active
		s.align.Enabled = active
		s.humanoid.PlatformStand = active
		if active then
			settleUntil = os.clock() + SETTLE_TIME
			facing = s.root.CFrame.Rotation
			lean, roll = 0, 0
		else
			-- Seated (the ship's sit pose takes over) or dead.
			stopAnimations(s)
		end
	end
	if not active then
		lastPosition = nil
		return
	end
	-- Something else (the server, a respawn) may have cleared it.
	if not s.humanoid.PlatformStand then
		s.humanoid.PlatformStand = true
	end

	local position = s.root.Position
	if lastPosition and (position - lastPosition).Magnitude > TELEPORT_DISTANCE then
		settleUntil = os.clock() + SETTLE_TIME
	end
	lastPosition = position

	local velocity = targetVelocity(s.root.AssemblyLinearVelocity, position, dt)
	s.linear.VectorVelocity = velocity

	-- Face where the camera is looking, leaning forwards (or back) and to the
	-- side with the velocity relative to that heading.
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.1 then
		facing = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
	local relative = facing:VectorToObjectSpace(velocity) / M.SUIT_MAX_SPEED
	local ahead = math.clamp(-relative.Z, -1, 1)
	local targetLean = if ahead >= 0 then ahead * LEAN else ahead * LEAN * BACK_LEAN_SHARE
	local targetRoll = -math.clamp(relative.X, -1, 1) * ROLL
	lean = FlightMath.smooth(lean, targetLean, M.SUIT_LEAN_SMOOTHING, dt)
	roll = FlightMath.smooth(roll, targetRoll, M.SUIT_LEAN_SMOOTHING, dt)
	s.align.CFrame = facing * CFrame.Angles(-lean, 0, roll)

	local pushing = os.clock() >= settleUntil
		and not Input.isHeld("Brake")
		and Input.moveVector().Magnitude > INPUT_DEADZONE
	animate(s, pushing, velocity.Magnitude)
end

function SuitController.init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(setup)
	if player.Character then
		task.spawn(setup, player.Character)
	end
	RunService.PreSimulation:Connect(step)

	Input.pressed:Connect(function(action)
		if action == "Stabilize" then
			local on = not ClientState.stabilization
			ClientState.setStabilization(on)
			ClientState.notify:Fire(
				if on then "Stabilizer on" else "Stabilizer off: you'll keep drifting"
			)
		end
	end)
end

return SuitController

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

local SuitController = {}

type Suit = {
	humanoid: Humanoid,
	root: BasePart,
	linear: LinearVelocity,
	align: AlignOrientation,
}

local suit: Suit? = nil
local active = false
local lastPosition: Vector3? = nil
local settleUntil = 0
local facing = CFrame.new()

local function setup(character: Model)
	suit = nil
	active = false
	lastPosition = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
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

	facing = root.CFrame.Rotation
	settleUntil = os.clock() + SETTLE_TIME
	suit = { humanoid = humanoid, root = root, linear = linear, align = align }
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

	s.linear.VectorVelocity = targetVelocity(s.root.AssemblyLinearVelocity, position, dt)

	-- Stay upright and face where the camera is looking.
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.1 then
		facing = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
	s.align.CFrame = facing
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

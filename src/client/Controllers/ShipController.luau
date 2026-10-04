--!strict
-- Flying your own ship, active while you sit in its PilotSeat. The server
-- hands this client network ownership when you board; this controller then
-- drives the ship's Engine (LinearVelocity) and Steer (AlignOrientation).
--
-- Steering: the mouse, the right stick or a drag on the screen moves an aim
-- direction, and the ship turns towards it at its turn rate. A chase camera
-- follows the aim. Thrust is relative to the ship: throttle, strafe and
-- up/down. Letting go glides to a stop; Brake stops quickly.
--
-- Also owns the suit/ship mode switch, hides Board prompts that aren't
-- yours, and works out whether you can dock right now.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FlightMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("FlightMath")
)
local Input = require(script.Parent.Parent.Input)
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local M = Config.Movement

local RENDER_STEP = "GaG_ShipFlight"
local BOARD_TAG = "BoardPrompt"
local DOCK_ZONE_TAG = "DockZone"
local MAX_PITCH = math.rad(M.SHIP_MAX_PITCH_DEGREES)
local LOOK_AHEAD = 30 -- studs ahead of the ship the camera looks at
local INPUT_DEADZONE = 0.05
-- When the ship hits something, the commanded speed drops to at most this
-- much above the real speed, so it doesn't keep pushing at full throttle.
local COLLISION_SLACK = 15

type Handling = {
	maxSpeed: number,
	acceleration: number,
	braking: number,
	turnRate: number,
}

type Flight = {
	ship: Model,
	hull: BasePart,
	engine: LinearVelocity,
	steer: AlignOrientation,
	handling: Handling,
	yaw: number,
	pitch: number,
	orientation: CFrame, -- where the ship is told to point
	localVelocity: Vector3, -- commanded velocity in ship space
	cameraPosition: Vector3,
}

local ShipController = {}

local flight: Flight? = nil
local seatConnection: RBXScriptConnection? = nil

local function isMine(instance: Instance): boolean
	local ship = instance:FindFirstAncestorWhichIsA("Model")
	return ship ~= nil and ship:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

local function handlingFor(ship: Model): Handling
	local info = ClientState.shipInfo
	if info and ClientState.ship == ship then
		return info
	end
	local shipId = ship:GetAttribute("ShipId")
	local def = Config.Ships.BY_ID[if type(shipId) == "string"
		then shipId
		else Config.Ships.STARTER_SHIP] or Config.Ships.BY_ID[Config.Ships.STARTER_SHIP]
	return def.stats
end

local function setOwnPrompt(ship: Model, enabled: boolean)
	local hull = ship:FindFirstChild("Hull")
	local prompt = hull and hull:FindFirstChild("BoardPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

local function dockStatus(position: Vector3, speed: number): ClientState.DockStatus
	local me = Players.LocalPlayer.UserId
	for _, zone in CollectionService:GetTagged(DOCK_ZONE_TAG) do
		local owner = zone:GetAttribute("OwnerUserId")
		if
			zone:IsA("BasePart")
			and (owner == 0 or owner == me)
			and FlightMath.insideBox(zone.CFrame, zone.Size, position)
		then
			return if speed <= M.DOCK_MAX_SPEED then "ready" else "tooFast"
		end
	end
	return "none"
end

local function leave()
	local f = flight
	if f == nil then
		return
	end
	flight = nil
	RunService:UnbindFromRenderStep(RENDER_STEP)
	setOwnPrompt(f.ship, true)

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	ClientState.flight.speed = 0
	ClientState.flight.dock = "none"
	Input.setMode("suit")
	ClientState.setMode("suit")
end

local function update(dt: number)
	local f = flight
	if f == nil then
		return
	end
	if f.hull.Parent == nil then
		leave()
		return
	end

	-- Mouse steering locks the cursor; hold Alt to use the cursor instead.
	local steerWithMouse = Input.device() == "keyboard" and not Input.isHeld("FreeCursor")
	UserInputService.MouseBehavior = if steerWithMouse
		then Enum.MouseBehavior.LockCenter
		else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not steerWithMouse

	-- Aim, then turn the ship towards it no faster than its turn rate.
	local look = Input.lookDelta(dt)
	f.yaw -= look.X
	f.pitch = math.clamp(f.pitch - look.Y, -MAX_PITCH, MAX_PITCH)
	local aim = FlightMath.aim(f.yaw, f.pitch)
	f.orientation = FlightMath.turnTowards(f.orientation, aim, f.handling.turnRate * dt)
	f.steer.CFrame = f.orientation

	-- Thrust, worked out in ship space so the velocity follows the nose.
	local input = Input.moveVector()
	local braking = Input.isHeld("Brake")
	local thrusting = not braking and input.Magnitude > INPUT_DEADZONE
	local target = if thrusting
		then FlightMath.shipTarget(input, CFrame.identity, {
			maxSpeed = f.handling.maxSpeed,
			reverseFactor = M.SHIP_REVERSE_FACTOR,
			strafeFactor = M.SHIP_STRAFE_FACTOR,
		})
		else Vector3.zero
	local decel = if thrusting or braking
		then f.handling.braking
		else f.handling.braking * M.SHIP_IDLE_BRAKE_FACTOR

	local actual = f.hull.AssemblyLinearVelocity
	if f.localVelocity.Magnitude > actual.Magnitude + COLLISION_SLACK then
		f.localVelocity = f.localVelocity.Unit * (actual.Magnitude + COLLISION_SLACK)
	end
	f.localVelocity = FlightMath.step(f.localVelocity, target, f.handling.acceleration, decel, dt)
	local velocity = f.orientation:VectorToWorldSpace(f.localVelocity)
	f.engine.VectorVelocity = FlightMath.clampToBounds(
		f.hull.Position,
		velocity,
		M.FLIGHT_BOUNDS_RADIUS,
		M.FLIGHT_BOUNDS_HEIGHT
	)

	-- Chase camera: behind and above the aim, smoothed, looking ahead.
	local position = f.hull.Position
	local desired = position
		+ aim:VectorToWorldSpace(Vector3.new(0, M.CAMERA_HEIGHT, M.CAMERA_DISTANCE))
	f.cameraPosition = f.cameraPosition:Lerp(desired, 1 - math.exp(-M.CAMERA_SMOOTHING * dt))
	local camera = Workspace.CurrentCamera
	camera.CFrame =
		CFrame.lookAt(f.cameraPosition, position + aim.LookVector * LOOK_AHEAD, aim.UpVector)

	local speed = actual.Magnitude
	ClientState.flight.speed = speed
	ClientState.flight.maxSpeed = f.handling.maxSpeed
	ClientState.flight.dock = dockStatus(position, speed)
end

local function enter(ship: Model)
	if flight and flight.ship == ship then
		return
	end
	leave()
	local hull = ship:FindFirstChild("Hull")
	local engine = hull and hull:FindFirstChild("Engine")
	local steer = hull and hull:FindFirstChild("Steer")
	if
		not (
			hull
			and hull:IsA("BasePart")
			and engine
			and engine:IsA("LinearVelocity")
			and steer
			and steer:IsA("AlignOrientation")
		)
	then
		return
	end

	local yaw, pitch = FlightMath.yawPitchOf(hull.CFrame)
	local camera = Workspace.CurrentCamera
	local f: Flight = {
		ship = ship,
		hull = hull,
		engine = engine,
		steer = steer,
		handling = handlingFor(ship),
		yaw = yaw,
		pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH),
		orientation = hull.CFrame.Rotation,
		localVelocity = Vector3.zero,
		cameraPosition = camera.CFrame.Position,
	}
	flight = f
	setOwnPrompt(ship, false)
	camera.CameraType = Enum.CameraType.Scriptable
	ClientState.flight.maxSpeed = f.handling.maxSpeed
	Input.setMode("ship")
	ClientState.setMode("ship")
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, update)
end

local function onSeat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if seat and seat.Name == "PilotSeat" and isMine(seat) then
		local ship = seat:FindFirstAncestorWhichIsA("Model")
		if ship then
			enter(ship)
			return
		end
	end
	leave()
end

local function watchCharacter(character: Model)
	leave()
	if seatConnection then
		seatConnection:Disconnect()
		seatConnection = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		seatConnection = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			onSeat(humanoid)
		end)
		onSeat(humanoid)
	end
end

-- Other players' ships can't be boarded, so their prompts are hidden here.
-- Your own is hidden while you fly it.
local function filterPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or isMine(prompt) then
		return
	end
	prompt.Enabled = false
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if prompt.Enabled then
			prompt.Enabled = false
		end
	end)
end

function ShipController.init()
	Input.setMode("suit")

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	for _, prompt in CollectionService:GetTagged(BOARD_TAG) do
		filterPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(filterPrompt)

	ClientState.shipChanged:Connect(function()
		local f = flight
		if f and ClientState.ship == f.ship then
			f.handling = handlingFor(f.ship)
		end
	end)

	Input.pressed:Connect(function(action)
		if flight == nil then
			return
		end
		if action == "Exit" then
			Net.ShipRequest:FireServer("exit")
		elseif action == "Dock" then
			if ClientState.flight.dock == "none" then
				ClientState.notify:Fire(
					"Fly into the docking area at the ISS or your own station to dock."
				)
			else
				Net.ShipRequest:FireServer("dock")
			end
		end
	end)
end

return ShipController

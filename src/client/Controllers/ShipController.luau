--!strict
-- Flying your own ship, active while you sit in its PilotSeat. The server
-- hands this client network ownership when you board; this controller then
-- drives the ship's Engine (LinearVelocity) and Steer (AlignOrientation).
--
-- Steering: the mouse, the right stick or a drag on the screen moves an aim
-- direction, and the nose eases towards it, never faster than the ship's
-- turn rate. The hull banks into turns and strafes. A chase camera follows
-- the aim, pulls back and widens its view with speed, and rolls a little with
-- the bank. Thrust is relative to the ship: throttle, strafe and up/down.
-- Letting go glides to a stop; Brake stops quickly.
--
-- The laser (hold click, RT or the Laser button) fires where the reticle
-- points, within a cone around the nose. This client draws its own beam at
-- once; the server decides heat and overheating (BeamSystem).
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
local BeamMath =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("BeamMath"))
local FlightMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("FlightMath")
)
local Input = require(script.Parent.Parent.Input)
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local B = Config.Beam
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
local MAX_BANK = math.rad(M.SHIP_MAX_BANK_DEGREES)
local STRAFE_BANK = math.rad(M.SHIP_STRAFE_BANK_DEGREES)
local BEAM_CONE = math.rad(B.AIM_CONE_DEGREES)
-- While firing, the aim is sent again once it has moved this much, and at
-- least this often anyway (which also restarts a beam whose "start" the
-- server dropped).
local AIM_RESEND_COS = math.cos(math.rad(1))
local AIM_KEEPALIVE = 0.5

type Handling = {
	maxSpeed: number,
	acceleration: number,
	braking: number,
	turnRate: number,
	beamRange: number,
}

type Flight = {
	ship: Model,
	hull: BasePart,
	engine: LinearVelocity,
	steer: AlignOrientation,
	handling: Handling,
	yaw: number,
	pitch: number,
	orientation: CFrame, -- where the ship is told to point, without bank
	heading: number, -- yaw of `orientation` last frame, for the turn rate
	bank: number, -- roll in radians, positive lowers the left wing
	localVelocity: Vector3, -- commanded velocity in ship space
	cameraPosition: Vector3,
	muzzle: Attachment?,
	rayParams: RaycastParams,
	beamSent: boolean, -- the server was told the beam is on
	aimSent: Vector3,
	aimTimer: number,
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
	if f.beamSent then
		Net.BeamInput:FireServer("stop")
	end
	ClientState.beam.firing = false

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = M.CAMERA_FOV
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	ClientState.flight.speed = 0
	ClientState.flight.throttle = 0
	ClientState.flight.dock = "none"
	Input.setMode("suit")
	ClientState.setMode("suit")
end

-- Where the laser should point, in ship space: at whatever is under the
-- reticle within beam range, kept inside the cone around the nose.
local function beamAim(f: Flight, muzzle: Attachment): Vector3
	local camera = Workspace.CurrentCamera.CFrame
	local origin = muzzle.WorldPosition
	-- Start the reticle ray level with the muzzle, so nothing between the
	-- camera and the ship can catch it.
	local depth = math.max(0, (origin - camera.Position):Dot(camera.LookVector))
	local start = camera.Position + camera.LookVector * depth
	local reach = camera.LookVector * f.handling.beamRange
	local hit = Workspace:Raycast(start, reach, f.rayParams)
	local point = if hit then hit.Position else start + reach
	local toPoint = point - origin
	if toPoint.Magnitude < 1 then
		return BeamMath.FORWARD
	end
	local direction = f.hull.CFrame:VectorToObjectSpace(toPoint.Unit)
	return BeamMath.clampToCone(BeamMath.FORWARD, direction, BEAM_CONE)
end

local function updateBeam(f: Flight, dt: number)
	local beam = ClientState.beam
	local muzzle = f.muzzle
	local overheated = f.ship:GetAttribute("Overheated") == true
	if muzzle == nil or overheated or not Input.isHeld("Beam") then
		if f.beamSent then
			Net.BeamInput:FireServer("stop")
			f.beamSent = false
		end
		beam.firing = false
		return
	end
	local direction = beamAim(f, muzzle)
	beam.firing = true
	beam.direction = direction
	f.aimTimer += dt
	if not f.beamSent then
		Net.BeamInput:FireServer("start", direction)
		f.beamSent = true
		f.aimSent = direction
		f.aimTimer = 0
	elseif
		f.aimTimer >= B.AIM_SEND_INTERVAL
		and (direction:Dot(f.aimSent) < AIM_RESEND_COS or f.aimTimer >= AIM_KEEPALIVE)
	then
		Net.BeamInput:FireServer("aim", direction)
		f.aimSent = direction
		f.aimTimer = 0
	end
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

	-- Aim, then ease the nose towards it, no faster than the turn rate.
	local look = Input.lookDelta(dt)
	f.yaw -= look.X
	f.pitch = math.clamp(f.pitch - look.Y, -MAX_PITCH, MAX_PITCH)
	local aim = FlightMath.aim(f.yaw, f.pitch)
	f.orientation =
		FlightMath.easeTowards(f.orientation, aim, f.handling.turnRate, M.SHIP_TURN_RESPONSE, dt)

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

	-- Bank into turns and strafes. Only the hull rolls; thrust and the camera
	-- work from the level orientation.
	local heading, pitch = FlightMath.yawPitchOf(f.orientation)
	-- Steeply nose-up or down, a change of heading is a smaller real turn.
	local yawRate = if dt > 0
		then FlightMath.wrapAngle(heading - f.heading) / dt * math.cos(pitch)
		else 0
	f.heading = heading
	local strafe = if thrusting then input.X else 0
	local bank = FlightMath.bankAngle(yawRate, strafe, M.SHIP_BANK_PER_TURN, STRAFE_BANK, MAX_BANK)
	f.bank = FlightMath.smooth(f.bank, bank, M.SHIP_BANK_SMOOTHING, dt)
	f.steer.CFrame = f.orientation * CFrame.Angles(0, 0, f.bank)

	-- Chase camera: behind and above the aim, smoothed, looking ahead. It
	-- pulls back and widens with forward speed and follows some of the bank.
	local forward = math.clamp(-f.localVelocity.Z / f.handling.maxSpeed, 0, 1)
	local position = f.hull.Position
	local distance = M.CAMERA_DISTANCE + M.CAMERA_SPEED_PULLBACK * forward
	local desired = position + aim:VectorToWorldSpace(Vector3.new(0, M.CAMERA_HEIGHT, distance))
	f.cameraPosition = f.cameraPosition:Lerp(desired, 1 - math.exp(-M.CAMERA_SMOOTHING * dt))
	local up = (aim * CFrame.Angles(0, 0, f.bank * M.CAMERA_ROLL_SHARE)).UpVector
	local camera = Workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(f.cameraPosition, position + aim.LookVector * LOOK_AHEAD, up)
	camera.FieldOfView = M.CAMERA_FOV + M.CAMERA_FOV_BOOST * forward

	updateBeam(f, dt)

	local speed = actual.Magnitude
	ClientState.flight.speed = speed
	ClientState.flight.maxSpeed = f.handling.maxSpeed
	ClientState.flight.throttle = if thrusting then math.max(input.Z, 0) else 0
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
	local muzzle = hull:FindFirstChild("BeamOrigin")
	local exclude: { Instance } = { ship }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = exclude
	local f: Flight = {
		ship = ship,
		hull = hull,
		engine = engine,
		steer = steer,
		handling = handlingFor(ship),
		yaw = yaw,
		pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH),
		orientation = hull.CFrame.Rotation,
		heading = yaw,
		bank = 0,
		localVelocity = Vector3.zero,
		cameraPosition = camera.CFrame.Position,
		muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil,
		rayParams = rayParams,
		beamSent = false,
		aimSent = BeamMath.FORWARD,
		aimTimer = 0,
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

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
-- Boost (Shift, L3 or the Boost button, while throttling forward) raises top
-- speed and acceleration by the ship's boost stats until the tank runs dry
-- (FlightMath.boostStep); the camera pulls back, widens and shakes.
--
-- The laser fires one shot per click (RT, or the Laser button) where the
-- reticle points, within a cone around the nose. This client draws its own
-- bolt at once; the server decides heat and overheating (BeamSystem). Each
-- shot kicks the camera up, nudges the ship back and shakes the view; a hit
-- shakes it harder.
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

type Handling = {
	maxSpeed: number,
	acceleration: number,
	braking: number,
	turnRate: number,
	beamRange: number,
	boostMultiplier: number,
	boostDuration: number,
	boostRecharge: number,
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
	wasHeld: boolean, -- the fire button was down last frame
	lastShot: number, -- os.clock() of the last shot
	boost: FlightMath.BoostState,
	boostBlend: number, -- 0 to 1, smoothed, for the camera
	kick: number, -- camera recoil pitch in radians, recovering to 0
	shake: number, -- camera shake in studs, dying away
	hitSeen: number, -- ClientState.beam.hitAt already shaken for
	shoulder: number, -- 0 to 1, smoothed over-the-shoulder offset
}

-- M pressed while flying: the mouse cursor is free instead of steering.
local cursorFree = false

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
	camera.FieldOfView = M.CAMERA_FOV
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	cursorFree = false

	ClientState.flight.speed = 0
	ClientState.flight.throttle = 0
	ClientState.flight.dock = "none"
	ClientState.flight.boosting = false
	ClientState.flight.boost = 1
	ClientState.flight.boostLocked = false
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

-- One shot per press of the fire button, no faster than FIRE_INTERVAL. The
-- bolt is drawn at once; the server decides heat and what the shot hits.
local function updateBeam(f: Flight)
	local held = Input.isHeld("Beam")
	local pressed = held and not f.wasHeld
	f.wasHeld = held
	local muzzle = f.muzzle
	if not pressed or muzzle == nil or f.ship:GetAttribute("Overheated") == true then
		return
	end
	local now = os.clock()
	if now - f.lastShot < B.FIRE_INTERVAL then
		return
	end
	f.lastShot = now
	local direction = beamAim(f, muzzle)
	ClientState.beam.direction = direction
	ClientState.beam.lastShot = now
	Net.BeamInput:FireServer("shot", direction)
	-- Weight: the camera kicks up, the ship is pushed back a little.
	f.kick = math.rad(B.RECOIL_DEGREES)
	f.shake = math.max(f.shake, B.SHOT_SHAKE)
	f.localVelocity += Vector3.new(0, 0, B.RECOIL_PUSH)
end

-- A random offset of up to `amount` studs, for camera shake.
local function jitter(amount: number): Vector3
	if amount <= 0.001 then
		return Vector3.zero
	end
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
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
	if ClientState.inspecting then
		-- The inspect view has the camera and mouse: the ship coasts to a stop.
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		f.localVelocity = FlightMath.step(f.localVelocity, Vector3.zero, 0, f.handling.braking, dt)
		f.engine.VectorVelocity = f.orientation:VectorToWorldSpace(f.localVelocity)
		f.wasHeld = true -- a click while inspecting doesn't fire on return
		return
	end

	-- Mouse steering locks the cursor; M (or holding Alt) frees it to click
	-- the HUD.
	local steerWithMouse = Input.device() == "keyboard"
		and not Input.isHeld("FreeCursor")
		and not cursorFree
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
	-- Boost only pushes forward.
	local boostWanted = Input.isHeld("Boost") and thrusting and input.Z > INPUT_DEADZONE
	local boosting
	f.boost, boosting = FlightMath.boostStep(
		f.boost,
		boostWanted,
		f.handling.boostDuration,
		f.handling.boostRecharge,
		M.BOOST_RESTART_SHARE,
		dt
	)
	local target = if thrusting
		then FlightMath.shipTarget(input, CFrame.identity, {
			maxSpeed = f.handling.maxSpeed * (if boosting then f.handling.boostMultiplier else 1),
			reverseFactor = M.SHIP_REVERSE_FACTOR,
			strafeFactor = M.SHIP_STRAFE_FACTOR,
		})
		else Vector3.zero
	local decel = if thrusting or braking
		then f.handling.braking
		else f.handling.braking * M.SHIP_IDLE_BRAKE_FACTOR
	if thrusting and not boosting and f.localVelocity.Magnitude > f.handling.maxSpeed then
		-- Coming off a boost: ease back down to top speed instead of braking.
		decel = f.handling.braking * M.SHIP_IDLE_BRAKE_FACTOR
	end
	local accel = f.handling.acceleration * (if boosting then M.BOOST_ACCEL_FACTOR else 1)

	local actual = f.hull.AssemblyLinearVelocity
	if f.localVelocity.Magnitude > actual.Magnitude + COLLISION_SLACK then
		f.localVelocity = f.localVelocity.Unit * (actual.Magnitude + COLLISION_SLACK)
	end
	f.localVelocity = FlightMath.step(f.localVelocity, target, accel, decel, dt)
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
	-- pulls back and widens with forward speed and boost, follows some of the
	-- bank, kicks up with each shot and shakes when boosting or hitting.
	local forward = math.clamp(-f.localVelocity.Z / f.handling.maxSpeed, 0, 1)
	f.boostBlend = FlightMath.smooth(f.boostBlend, if boosting then 1 else 0, 6, dt)
	local position = f.hull.Position
	local distance = M.CAMERA_DISTANCE
		+ M.CAMERA_SPEED_PULLBACK * forward
		+ M.CAMERA_BOOST_PULLBACK * f.boostBlend
	-- Over the shoulder: camera and look point both slide right, so the ship
	-- sits left of the reticle.
	f.shoulder = FlightMath.smooth(
		f.shoulder,
		if ClientState.shoulder then 1 else 0,
		M.SHOULDER_SMOOTHING,
		dt
	)
	local side = aim.RightVector * M.CAMERA_SHOULDER_OFFSET * f.shoulder
	local desired = position
		+ side
		+ aim:VectorToWorldSpace(Vector3.new(0, M.CAMERA_HEIGHT, distance))
	f.cameraPosition = f.cameraPosition:Lerp(desired, 1 - math.exp(-M.CAMERA_SMOOTHING * dt))
	local up = (aim * CFrame.Angles(0, 0, f.bank * M.CAMERA_ROLL_SHARE)).UpVector
	if ClientState.beam.hitAt ~= f.hitSeen then
		f.hitSeen = ClientState.beam.hitAt
		f.shake = math.max(f.shake, B.HIT_SHAKE)
	end
	f.shake *= math.exp(-B.SHAKE_DECAY * dt)
	f.kick *= math.exp(-B.RECOIL_RECOVERY * dt)
	local shake = jitter(f.shake + M.CAMERA_BOOST_SHAKE * f.boostBlend)
	local camera = Workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(
		f.cameraPosition + shake,
		position + side + aim.LookVector * LOOK_AHEAD,
		up
	) * CFrame.Angles(f.kick, 0, 0)
	local kickShare = f.kick / math.rad(math.max(B.RECOIL_DEGREES, 0.01))
	camera.FieldOfView = M.CAMERA_FOV
		+ M.CAMERA_FOV_BOOST * forward
		+ M.CAMERA_BOOST_FOV * f.boostBlend
		- B.RECOIL_FOV * kickShare

	updateBeam(f)

	local speed = actual.Magnitude
	ClientState.flight.speed = speed
	ClientState.flight.maxSpeed = f.handling.maxSpeed
	ClientState.flight.throttle = if thrusting then math.max(input.Z, 0) else 0
	ClientState.flight.dock = dockStatus(position, speed)
	ClientState.flight.boost = f.boost.energy / math.max(f.handling.boostDuration, 0.01)
	ClientState.flight.boosting = boosting
	ClientState.flight.boostLocked = f.boost.locked
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
	local handling = handlingFor(ship)
	local f: Flight = {
		ship = ship,
		hull = hull,
		engine = engine,
		steer = steer,
		handling = handling,
		yaw = yaw,
		pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH),
		orientation = hull.CFrame.Rotation,
		heading = yaw,
		bank = 0,
		localVelocity = Vector3.zero,
		cameraPosition = camera.CFrame.Position,
		muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil,
		rayParams = rayParams,
		wasHeld = true, -- a click that boarded the ship doesn't fire
		lastShot = 0,
		boost = { energy = handling.boostDuration, locked = false },
		boostBlend = 0,
		kick = 0,
		shake = 0,
		hitSeen = ClientState.beam.hitAt,
		shoulder = if ClientState.shoulder then 1 else 0,
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
	-- Explosions nearby and hits taken shake the flight camera.
	ClientState.shake:Connect(function(amount)
		local f = flight
		if f then
			f.shake = math.max(f.shake, amount)
		end
	end)

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
		if action == "CursorToggle" then
			cursorFree = not cursorFree
			ClientState.notify:Fire(
				if cursorFree
					then "Mouse cursor on: click any button. Press M to steer again."
					else "Steering with the mouse again."
			)
		elseif action == "Exit" then
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

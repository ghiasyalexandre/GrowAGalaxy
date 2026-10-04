--!strict
-- One input layer for keyboard and mouse, touch and gamepad. Controllers ask
-- it for movement and steering and listen for named actions; none of them
-- read devices directly.
--
--   moveVector()    x = right, y = up, z = forward, each in [-1, 1]
--   isHeld(name)    "Up", "Down", "Brake", "FreeCursor"
--   lookDelta(dt)   steering in radians since the last call (x = yaw right,
--                   y = pitch down). Ship mode only.
--   pressed         Signal fired with "Stabilize", "Exit" or "Dock"
--   setMode(mode)   "suit" or "ship": which actions are bound
--   device()        "keyboard", "gamepad" or "touch", the last one used
--   hint(mode)      one-line control summary for the HUD
--
-- Walking input (WASD, the thumbstick, the left stick) comes from Roblox's
-- own ControlModule, so it works the same on every device. Everything else
-- is bound with ContextActionService, which also makes the touch buttons.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Signal =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local M = Config.Movement

export type Mode = "suit" | "ship"
export type Device = "keyboard" | "gamepad" | "touch"

type Binding = {
	keys: { Enum.KeyCode },
	title: string,
	hold: boolean,
	modes: { [Mode]: boolean },
	touch: boolean,
}

local BOTH = { suit = true, ship = true }

local BINDINGS: { [string]: Binding } = {
	Up = {
		keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR1 },
		title = "Up",
		hold = true,
		modes = BOTH,
		touch = true,
	},
	Down = {
		keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonL1 },
		title = "Down",
		hold = true,
		modes = BOTH,
		touch = true,
	},
	Brake = {
		keys = { Enum.KeyCode.X, Enum.KeyCode.ButtonL2 },
		title = "Brake",
		hold = true,
		modes = BOTH,
		touch = true,
	},
	Stabilize = {
		keys = { Enum.KeyCode.Z, Enum.KeyCode.DPadUp },
		title = "Stabilizer",
		hold = false,
		modes = { suit = true },
		touch = true,
	},
	Exit = {
		keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonY },
		title = "Exit",
		hold = false,
		modes = { ship = true },
		touch = true,
	},
	Dock = {
		keys = { Enum.KeyCode.G, Enum.KeyCode.ButtonX },
		title = "Dock",
		hold = false,
		modes = { ship = true },
		touch = true,
	},
	FreeCursor = {
		keys = { Enum.KeyCode.LeftAlt },
		title = "Cursor",
		hold = true,
		modes = { ship = true },
		touch = false,
	},
}

-- Bind order, so touch buttons always appear in the same places.
local ORDER = { "Up", "Down", "Brake", "Stabilize", "Exit", "Dock", "FreeCursor" }

-- Above the default character controls, so Space and A don't also jump.
local PRIORITY = Enum.ContextActionPriority.High.Value
local PREFIX = "GaG_"
local STICK_DEADZONE = 0.15

local HINTS: { [Mode]: { [Device]: string } } = {
	suit = {
		keyboard = "WASD float  ·  Space up  ·  Ctrl down  ·  X brake  ·  Z stabilizer",
		gamepad = "Left stick float  ·  RB up  ·  LB down  ·  LT brake  ·  D-pad up stabilizer",
		touch = "Thumbstick to float  ·  Up, Down and Brake buttons",
	},
	ship = {
		keyboard = "Mouse steer  ·  W/S throttle  ·  A/D strafe  ·  Space/Ctrl up/down  ·  X brake  ·  F exit  ·  Alt cursor",
		gamepad = "Right stick steer  ·  Left stick throttle and strafe  ·  RB/LB up/down  ·  LT brake  ·  Y exit",
		touch = "Drag to steer  ·  Thumbstick throttle and strafe  ·  Exit button to leave",
	},
}

local Input = {}

Input.pressed = Signal.new() :: Signal.Signal<string>
Input.deviceChanged = Signal.new() :: Signal.Signal<()>

local mode: Mode? = nil
local held: { [string]: boolean } = {}
local controls: any = nil
local lastDevice: Device = "keyboard"
local touchLook: { [InputObject]: Vector3 } = {}
local touchDelta = Vector2.zero

local function classify(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "keyboard"
	end
	return nil
end

local function handle(name: string, state: Enum.UserInputState): Enum.ContextActionResult
	local binding = BINDINGS[name]
	if binding.hold then
		if state == Enum.UserInputState.Begin then
			held[name] = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held[name] = false
		end
	elseif state == Enum.UserInputState.Begin then
		Input.pressed:Fire(name)
	end
	return Enum.ContextActionResult.Sink
end

function Input.setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	table.clear(held)
	table.clear(touchLook)
	for _, name in ORDER do
		ContextActionService:UnbindAction(PREFIX .. name)
	end
	for _, name in ORDER do
		local binding = BINDINGS[name]
		if binding.modes[newMode] then
			ContextActionService:BindActionAtPriority(PREFIX .. name, function(_, state)
				return handle(name, state)
			end, binding.touch, PRIORITY, table.unpack(binding.keys))
			if binding.touch then
				ContextActionService:SetTitle(PREFIX .. name, binding.title)
			end
		end
	end
end

function Input.mode(): Mode?
	return mode
end

function Input.isHeld(name: string): boolean
	return held[name] == true
end

function Input.moveVector(): Vector3
	local move = Vector3.zero
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			move = vector
		end
	end
	local vertical = (if held.Up then 1 else 0) - (if held.Down then 1 else 0)
	-- The ControlModule uses -Z for forward.
	return Vector3.new(move.X, vertical, -move.Z)
end

function Input.lookDelta(dt: number): Vector2
	local delta = touchDelta * M.LOOK_SENSITIVITY_TOUCH
	touchDelta = Vector2.zero
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		delta += UserInputService:GetMouseDelta() * M.LOOK_SENSITIVITY_MOUSE
	end
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stick = Vector2.new(state.Position.X, -state.Position.Y)
			if stick.Magnitude > STICK_DEADZONE then
				delta += stick * M.LOOK_SPEED_GAMEPAD * dt
			end
		end
	end
	return delta
end

function Input.device(): Device
	return lastDevice
end

function Input.hint(forMode: Mode): string
	return HINTS[forMode][lastDevice]
end

function Input.init()
	lastDevice = classify(UserInputService:GetLastInputType())
		or (
			if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
				then "touch"
				else "keyboard"
		)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local device = classify(inputType)
		if device and device ~= lastDevice then
			lastDevice = device :: Device
			Input.deviceChanged:Fire()
		end
	end)

	-- Touch steering: drags that start on open screen, not on a button or
	-- the movement thumbstick (those arrive already processed).
	UserInputService.TouchStarted:Connect(function(touch, processed)
		if mode == "ship" and not processed then
			touchLook[touch] = touch.Position
		end
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		local last = touchLook[touch]
		if last then
			touchDelta += Vector2.new(touch.Position.X - last.X, touch.Position.Y - last.Y)
			touchLook[touch] = touch.Position
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		touchLook[touch] = nil
	end)

	task.spawn(function()
		local playerModule =
			Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		controls = (require :: any)(playerModule):GetControls()
	end)
end

return Input

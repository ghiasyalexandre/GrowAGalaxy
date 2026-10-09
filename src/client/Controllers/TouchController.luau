--!strict
-- On-screen touch buttons, on phones and tablets (UI/Layout.compact()).
--
-- Input's touch actions for the current mode (Laser, Boost, Up, Down, Brake,
-- Rocket, Dock, Exit flying; Up, Down, Brake, Stabilizer on foot) plus any
-- extras another controller adds (setExtras: the Zero G Dodgeball's Throw
-- and Launch), drawn as round buttons in arcs round Roblox's jump button,
-- found where it really is on screen (or where it would be), so nothing
-- overlaps it, the thumbstick or each other. The most used actions sit in
-- the inner arc, nearest the thumb.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Layout = require(script.Parent.Parent.UI.Layout)

local TouchController = {}

export type Extra = { id: string, title: string, press: () -> () }

-- Arcs round the jump button's centre: angles in degrees (180 = left of it,
-- 270 = straight above), from the inside out. Slots fill in this order.
local SLOTS: { { ring: number, angle: number } } = {
	{ ring = 1, angle = 180 },
	{ ring = 1, angle = 225 },
	{ ring = 1, angle = 270 },
	{ ring = 2, angle = 180 },
	{ ring = 2, angle = 210 },
	{ ring = 2, angle = 240 },
	{ ring = 2, angle = 270 },
	{ ring = 3, angle = 195 },
	{ ring = 3, angle = 228 },
	{ ring = 3, angle = 260 },
}
local RADIUS = 30 -- pixels, before the HUD's scale
local BIG_RADIUS = 38 -- the first (most used) button
local GAP = 10
local COLORS: { [string]: Color3 } = {
	Beam = Color3.fromRGB(255, 110, 90),
	Boost = Color3.fromRGB(120, 230, 255),
	Up = Color3.fromRGB(150, 220, 160),
	Down = Color3.fromRGB(150, 220, 160),
	Brake = Color3.fromRGB(255, 214, 110),
	Rocket = Color3.fromRGB(255, 150, 60),
	Dock = Color3.fromRGB(176, 107, 255),
	Exit = Color3.fromRGB(200, 205, 225),
	Stabilize = Color3.fromRGB(120, 230, 255),
}
-- Short titles that fit a round button (Input's titles are for keyboards).
local TITLES: { [string]: string } = {
	Stabilize = "Hover",
	Rocket = "Fire",
}
-- What goes nearest the thumb, by mode (the rest follow in Input's order).
local PRIORITY: { [string]: { string } } = {
	ship = { "Beam", "Boost", "Up", "Down", "Brake", "Rocket", "Dock", "Exit" },
	suit = { "Up", "Down", "Brake", "Stabilize" },
}

local gui: ScreenGui
local extras: { Extra } = {}
local lastJump: Vector3? = nil -- jump button centre and radius, last laid out

-- The jump button's centre and radius on screen (Roblox's TouchGui), or
-- where Roblox puts it on a screen this size.
local function jumpButton(): (Vector2, number)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition + jump.AbsoluteSize / 2, jump.AbsoluteSize.X / 2
	end
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(844, 390)
	local small = math.min(size.X, size.Y) <= 500
	local side = if small then 70 else 120
	local offset = if small then Vector2.new(95, 90) else Vector2.new(170, 210)
	return Vector2.new(size.X - offset.X + side / 2, size.Y - offset.Y + side / 2), side / 2
end

local function makeButton(title: string, color: Color3, radius: number, centre: Vector2): TextButton
	local button = Instance.new("TextButton")
	button.Name = title
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(centre.X, centre.Y)
	button.Size = UDim2.fromOffset(radius * 2, radius * 2)
	button.BackgroundColor3 = Color3.fromRGB(14, 16, 34)
	button.BackgroundTransparency = 0.35
	button.AutoButtonColor = false
	button.Text = title
	button.Font = Enum.Font.GothamBlack
	button.TextScaled = true
	button.TextColor3 = color
	button.TextStrokeTransparency = 0.5
	button.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = button
	local edge = Instance.new("UIStroke")
	edge.Color = color
	edge.Thickness = 2
	edge.Transparency = 0.2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0, math.floor(radius * 0.32))
	padding.PaddingLeft, padding.PaddingRight = inset, inset
	padding.PaddingTop, padding.PaddingBottom = inset, inset
	padding.Parent = button
	return button
end

-- Wires a button: held while touched (or clicked, for the Studio emulator).
local function wire(button: TextButton, began: () -> (), ended: () -> ())
	local down = false
	local function release()
		if down then
			down = false
			button.BackgroundTransparency = 0.35
			ended()
		end
	end
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			down = true
			button.BackgroundTransparency = 0.05
			began()
			local connection: RBXScriptConnection? = nil
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					release()
					if connection then
						connection:Disconnect()
					end
				end
			end)
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			release()
		end
	end)
end

local function rebuild()
	for _, child in gui:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	gui.Enabled = Layout.compact()
	local mode = Input.mode()
	if not gui.Enabled or mode == nil then
		return
	end
	local actions = Input.touchActions(mode :: Input.Mode)
	-- Actions in priority order, then any extras.
	type Action = { name: string, title: string, hold: boolean }
	local available: { [string]: Action } = {}
	for _, action in actions do
		available[action.name] = action
	end
	local ordered: { Action } = {}
	local priority: { string } = PRIORITY[mode :: string] or {}
	for _, name in priority do
		local action = available[name]
		if action then
			table.insert(ordered, action)
			available[name] = nil
		end
	end
	for _, action in actions do
		if available[action.name] then
			table.insert(ordered, action)
		end
	end

	local centre, jumpRadius = jumpButton()
	lastJump = Vector3.new(centre.X, centre.Y, jumpRadius)
	local scale = Layout.scale()
	local radius = RADIUS * scale
	local big = BIG_RADIUS * scale
	local gap = GAP * scale
	local rings = {
		jumpRadius + gap + big,
		jumpRadius + gap * 2 + big * 2 + radius,
		jumpRadius + gap * 3 + big * 2 + radius * 3,
	}
	local slot = 0
	local function nextCentre(): Vector2?
		slot += 1
		local spot = SLOTS[slot]
		if spot == nil then
			return nil
		end
		local a = math.rad(spot.angle)
		return centre + Vector2.new(math.cos(a), math.sin(a)) * rings[spot.ring]
	end
	for index, action in ordered do
		local at = nextCentre()
		if at == nil then
			break
		end
		local button = makeButton(
			TITLES[action.name] or action.title,
			COLORS[action.name] or Color3.new(1, 1, 1),
			if index == 1 then big else radius,
			at
		)
		local name = action.name
		wire(button, function()
			Input.touchInput(name, true)
		end, function()
			Input.touchInput(name, false)
		end)
	end
	for _, extra in extras do
		local at = nextCentre()
		if at == nil then
			break
		end
		local button = makeButton(extra.title, Color3.fromRGB(255, 214, 110), radius, at)
		local press = extra.press
		wire(button, press, function() end)
	end
end

-- Extra buttons for a moment (e.g. Throw and Launch in the dodgeball arena);
-- an empty list removes them.
function TouchController.setExtras(list: { Extra })
	extras = list
	if gui then
		rebuild()
	end
end

function TouchController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	-- The same screen space as Roblox's own TouchGui, to line up with it.
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TouchController.start()
	rebuild()
	ClientState.modeChanged:Connect(function()
		task.defer(rebuild)
	end)
	Layout.changed:Connect(rebuild)
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(rebuild)
	end)
	-- Roblox moves or shows its jump button on its own schedule: follow it.
	task.spawn(function()
		while true do
			task.wait(1)
			if gui.Enabled then
				local centre, jumpRadius = jumpButton()
				local seen = Vector3.new(centre.X, centre.Y, jumpRadius)
				if lastJump == nil or (seen - lastJump).Magnitude > 2 then
					rebuild()
				end
			end
		end
	end)
end

return TouchController

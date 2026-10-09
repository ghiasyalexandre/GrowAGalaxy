--!strict
-- One layout for every always-on HUD element, on desktop, tablet and phone.
--
-- A single ScreenGui ("GaG_HUD", inside the device's safe area, under every
-- panel) holds seven docks: TopLeft, TopRight, RightColumn (a column
-- right under the TopRight row), TopCenter, BottomLeft, BottomRight and
-- BottomCenter. Each dock stacks what's put in it with a
-- list layout, so nothing ever overlaps, and each carries one UIScale, so
-- the whole HUD grows and shrinks with the screen.
--
--   form()          "phone", "tablet" or "desktop" (touch, and the screen's
--                   short side)
--   scale()         the HUD's scale for this screen
--   compact()       phone or tablet: menus become icon grids, the bottom-left
--                   is left to Roblox's thumbstick, our touch buttons sit
--                   bottom-right (Controllers/TouchController)
--   dock(name)      the dock Frame
--   place(item, dock, order)  moves a HUD element into a dock
--   centerGap()     the free band between the TopLeft and TopRight docks, in
--                   screen pixels (x from, x to, y bottom of the taller one):
--                   the tutorial card sits in it
--   changed         Signal: the form or scale changed (rearrange then)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Input = require(script.Parent.Parent.Input)

local Signal =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

export type Form = "phone" | "tablet" | "desktop"

local PAD = 10 -- pixels between the docks and the screen's safe edge
local GAP = 8 -- pixels between items in a dock (before scaling)
-- Extra room under the TopRight row before RightColumn: the Premium button's
-- glow and the Daily button's badge reach past their boxes.
local COLUMN_CLEARANCE = 22
local PHONE_SHORT_SIDE = 520 -- a touch screen shorter than this is a phone

local Layout = {}

Layout.changed = Signal.new()

local gui: ScreenGui? = nil
local docks: { [string]: Frame } = {}
local scales: { UIScale } = {}
local current: { form: Form, scale: number } = { form = "desktop" :: Form, scale = 1 }

local function viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function isTouch(): boolean
	if Players.LocalPlayer:GetAttribute("GaG_LayoutForm") ~= nil then
		return Players.LocalPlayer:GetAttribute("GaG_LayoutForm") ~= "desktop"
	end
	return Input.device() == "touch"
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

local function measure(): (Form, number)
	local size = viewport()
	local short = math.min(size.X, size.Y)
	local phone: Form, tablet: Form, desktop: Form = "phone", "tablet", "desktop"
	-- Testing: the local player's GaG_LayoutForm attribute forces a form.
	local forced = Players.LocalPlayer:GetAttribute("GaG_LayoutForm")
	if forced == phone or forced == tablet or forced == desktop then
		local forcedScales = { phone = 0.72, tablet = 0.9, desktop = 1 }
		return forced :: Form, forcedScales[forced :: string]
	end
	if isTouch() then
		if short < PHONE_SHORT_SIDE then
			return phone, math.clamp(short / 540, 0.6, 0.85)
		end
		return tablet, math.clamp(short / 820, 0.8, 1.05)
	end
	return desktop, math.clamp(short / 1000, 0.8, 1.2)
end

local SPECS: {
	[string]: {
		anchor: Vector2,
		position: UDim2,
		direction: Enum.FillDirection,
		horizontal: Enum.HorizontalAlignment,
		vertical: Enum.VerticalAlignment,
	},
} =
	{
		TopLeft = {
			anchor = Vector2.new(0, 0),
			position = UDim2.new(0, PAD, 0, PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Left,
			vertical = Enum.VerticalAlignment.Top,
		},
		TopRight = {
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -PAD, 0, PAD),
			direction = Enum.FillDirection.Horizontal,
			horizontal = Enum.HorizontalAlignment.Right,
			vertical = Enum.VerticalAlignment.Top,
		},
		-- A column hanging under the TopRight row (desktop: Spin and Daily
		-- under the Premium button); repositioned as the row's height changes.
		RightColumn = {
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -PAD, 0, PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Right,
			vertical = Enum.VerticalAlignment.Top,
		},
		TopCenter = {
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Center,
			vertical = Enum.VerticalAlignment.Top,
		},
		BottomLeft = {
			anchor = Vector2.new(0, 1),
			position = UDim2.new(0, PAD, 1, -PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Left,
			vertical = Enum.VerticalAlignment.Bottom,
		},
		BottomRight = {
			anchor = Vector2.new(1, 1),
			position = UDim2.new(1, -PAD, 1, -PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Right,
			vertical = Enum.VerticalAlignment.Bottom,
		},
		BottomCenter = {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -PAD),
			direction = Enum.FillDirection.Vertical,
			horizontal = Enum.HorizontalAlignment.Center,
			vertical = Enum.VerticalAlignment.Bottom,
		},
	}

local function build(): ScreenGui
	local existing = gui
	if existing then
		return existing
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "GaG_HUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Under every panel (they're DisplayOrder 0 and up).
	screen.DisplayOrder = -1
	for name, spec in SPECS do
		local dock = Instance.new("Frame")
		dock.Name = name
		dock.AnchorPoint = spec.anchor
		dock.Position = spec.position
		dock.Size = UDim2.fromOffset(0, 0)
		dock.AutomaticSize = Enum.AutomaticSize.XY
		dock.BackgroundTransparency = 1
		dock.Parent = screen
		local list = Instance.new("UIListLayout")
		list.FillDirection = spec.direction
		list.HorizontalAlignment = spec.horizontal
		list.VerticalAlignment = spec.vertical
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, GAP)
		list.Parent = dock
		local scale = Instance.new("UIScale")
		scale.Parent = dock
		table.insert(scales, scale)
		docks[name] = dock
	end
	local row, column = docks.TopRight, docks.RightColumn
	local function underRow()
		column.Position = UDim2.new(
			1,
			-PAD,
			0,
			PAD + row.AbsoluteSize.Y + (GAP + COLUMN_CLEARANCE) * current.scale
		)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(underRow)
	underRow()
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

local function refresh()
	local form, scale = measure()
	for _, item in scales do
		item.Scale = scale
	end
	if form ~= current.form or math.abs(scale - current.scale) > 0.01 then
		current.form = form :: Form
		current.scale = scale
		Layout.changed:Fire(form)
	end
end

function Layout.form(): Form
	return current.form
end

function Layout.scale(): number
	return current.scale
end

function Layout.compact(): boolean
	return current.form ~= "desktop"
end

function Layout.dock(name: string): Frame
	build()
	return docks[name]
end

-- Moves `item` into a dock: the dock's list layout positions it (its own
-- Position and AnchorPoint stop mattering), `order` sorts it.
function Layout.place(item: GuiObject, dock: string, order: number)
	item.AnchorPoint = Vector2.zero
	item.Position = UDim2.fromOffset(0, 0)
	item.LayoutOrder = order
	item.Parent = Layout.dock(dock)
end

function Layout.centerGap(): (number, number, number)
	build()
	local left, right = docks.TopLeft, docks.TopRight
	local from = left.AbsolutePosition.X + left.AbsoluteSize.X
	local to = right.AbsolutePosition.X
	local bottom = math.max(
		left.AbsolutePosition.Y + left.AbsoluteSize.Y,
		right.AbsolutePosition.Y + right.AbsoluteSize.Y
	)
	if to - from < 200 then
		-- Too narrow: use the middle of the screen below both docks.
		local size = viewport()
		return size.X * 0.15, size.X * 0.85, bottom
	end
	return from, to, docks.TopCenter.AbsolutePosition.Y + docks.TopCenter.AbsoluteSize.Y
end

function Layout.init()
	build()
	local form, scale = measure()
	current.form = form :: Form
	current.scale = scale
	for _, item in scales do
		item.Scale = scale
	end
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		refresh()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(refresh)
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("GaG_LayoutForm"):Connect(refresh)
end

return Layout

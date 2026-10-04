--!strict
-- Shared look and feel for every panel: colours, rounded panels with a soft
-- gradient and glowing edge, buttons that grow on hover and squash on press,
-- and a springy pop-in when a panel opens. Plain helpers, no state.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.COLORS = {
	panel = Color3.fromRGB(14, 18, 36),
	panelTop = Color3.fromRGB(30, 36, 72),
	row = Color3.fromRGB(26, 32, 60),
	edge = Color3.fromRGB(120, 140, 255),
	gold = Color3.fromRGB(255, 205, 90),
	text = Color3.fromRGB(240, 243, 255),
	subtle = Color3.fromRGB(170, 180, 215),
	good = Color3.fromRGB(110, 230, 150),
	bad = Color3.fromRGB(255, 110, 100),
	primary = Color3.fromRGB(76, 110, 255),
	primaryTop = Color3.fromRGB(130, 90, 255),
	buy = Color3.fromRGB(255, 176, 50),
	buyTop = Color3.fromRGB(255, 120, 60),
	disabled = Color3.fromRGB(56, 60, 82),
}

export type ButtonStyle = "primary" | "buy" | "disabled"

local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local QUICK = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function gradient(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
end

function Theme.screen(name: string, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	return gui
end

-- A rounded panel with a gradient and a glowing edge.
function Theme.panel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 14)
	gradient(frame, Theme.COLORS.panelTop, Theme.COLORS.panel)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.COLORS.edge
	stroke.Transparency = 0.45
	stroke.Thickness = 2
	stroke.Parent = frame
	return frame
end

-- A row background inside a panel.
function Theme.row(parent: Instance, height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = Theme.COLORS.row
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 8)
	return frame
end

function Theme.label(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Theme.COLORS.text
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- A round colour swatch (star or planet preview).
function Theme.swatch(parent: Instance, color: Color3, size: number, glow: boolean?): Frame
	local dot = Instance.new("Frame")
	dot.Name = "Swatch"
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = dot
	if glow then
		local stroke = Instance.new("UIStroke")
		stroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.4)
		stroke.Thickness = 3
		stroke.Transparency = 0.3
		stroke.Parent = dot
	end
	return dot
end

-- A button that grows on hover and squashes on press. Disabled buttons
-- ignore clicks.
function Theme.button(
	parent: Instance,
	text: string,
	style: ButtonStyle,
	onClick: (() -> ())?
): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 14
	button.TextColor3 = if style == "disabled" then Theme.COLORS.subtle else Color3.new(1, 1, 1)
	button.TextStrokeTransparency = if style == "disabled" then 1 else 0.6
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.BorderSizePixel = 0
	button.Parent = parent
	corner(button, 8)
	if style == "primary" then
		gradient(button, Theme.COLORS.primaryTop, Theme.COLORS.primary)
	elseif style == "buy" then
		gradient(button, Theme.COLORS.buy, Theme.COLORS.buyTop)
	else
		button.BackgroundColor3 = Theme.COLORS.disabled
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button
	if style ~= "disabled" and onClick then
		button.MouseEnter:Connect(function()
			TweenService:Create(scale, QUICK, { Scale = 1.06 }):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(scale, QUICK, { Scale = 1 }):Play()
		end)
		button.Activated:Connect(function()
			scale.Scale = 0.9
			TweenService:Create(scale, POP, { Scale = 1 }):Play()
			onClick()
		end)
	else
		button.Selectable = false
	end
	return button
end

-- Springs a panel open from slightly small.
function Theme.popIn(frame: GuiObject)
	local s = frame:FindFirstChildOfClass("UIScale")
	if s == nil then
		local created = Instance.new("UIScale")
		created.Parent = frame
		s = created
	end
	assert(s, "UIScale")
	s.Scale = 0.85
	TweenService:Create(s, POP, { Scale = 1 }):Play()
end

-- A vertical scrolling list that sizes its canvas to its rows.
function Theme.list(parent: Instance, padding: number): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Theme.COLORS.edge
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

function Theme.clear(list: Instance)
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

return Theme

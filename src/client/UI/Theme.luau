--!strict
-- Shared look and feel for every panel: colours, rounded panels with a soft
-- gradient and glowing edge, buttons that grow on hover and squash on press,
-- a springy pop-in when a panel opens, animated star and planet icons,
-- progress bars and a shine that sweeps across buy buttons.
--
-- Once the UI sprite sheet is uploaded (Config.Sprites.IMAGE), panels,
-- buttons and progress bars wear its art (UI/Sprites) and Theme.icon gives
-- its icons; until then everything keeps the plain look below.
--
-- Looping animations (spin, pulse, shine) are driven by the clock from one
-- Heartbeat connection, not by tweens, so a panel that rebuilds its rows
-- (on every Stardust change) carries on smoothly instead of restarting.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sprites = require(script.Parent.Sprites)

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

-- primary: blue, buy: gold, special: purple (big moves like Evolve), disabled.
export type ButtonStyle = "primary" | "buy" | "special" | "disabled"

local BUTTON_SPRITES: { [ButtonStyle]: string } = {
	primary = "ButtonBlue",
	buy = "ButtonGold",
	special = "ButtonPurple",
	disabled = "ButtonDark",
}

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

-- A rounded panel with a gradient and a glowing edge, or the sprite sheet's
-- panel frame once it's uploaded (the stroke stays, switched off, so callers
-- may still find it).
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
	Sprites.panelSkin(frame)
	return frame
end

-- A sprite-sheet icon (Config.Sprites), or nil while the sheet isn't set up.
function Theme.icon(parent: Instance, name: string, size: number): ImageLabel?
	return Sprites.icon(parent, name, size)
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
	-- Rows light up under the pointer.
	frame.MouseEnter:Connect(function()
		if frame.BackgroundTransparency < 1 then
			TweenService:Create(frame, QUICK, {
				BackgroundColor3 = Theme.COLORS.row:Lerp(Theme.COLORS.edge, 0.25),
				BackgroundTransparency = 0,
			}):Play()
		end
	end)
	frame.MouseLeave:Connect(function()
		if frame.BackgroundTransparency < 1 then
			TweenService:Create(frame, QUICK, {
				BackgroundColor3 = Theme.COLORS.row,
				BackgroundTransparency = 0.15,
			}):Play()
		end
	end)
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
	elseif style == "special" then
		gradient(button, Color3.fromRGB(200, 110, 255), Color3.fromRGB(120, 50, 220))
	else
		button.BackgroundColor3 = Theme.COLORS.disabled
	end
	if Sprites.skin(button, BUTTON_SPRITES[style]) then
		-- A skin is a child, so it would cover the button's own text: the
		-- text moves to a label above the skin.
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 2
		label.Font = button.Font
		label.TextSize = button.TextSize
		label.TextColor3 = button.TextColor3
		label.TextStrokeTransparency = if style == "disabled" then 1 else 0.3
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = text
		label.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.1, 0)
		padding.PaddingRight = UDim.new(0.1, 0)
		padding.Parent = label
		button.Text = ""
	end
	if style ~= "disabled" and onClick then
		Theme.hover(button, onClick)
	else
		button.Selectable = false
	end
	return button
end

local HOVER = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SWEEP = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A one-off bright band across `target` (on hover).
local function sweep(target: GuiObject)
	local overlay = target:FindFirstChild("HoverShine") :: Frame?
	if overlay == nil then
		local made = Instance.new("Frame")
		made.Name = "HoverShine"
		made.BackgroundColor3 = Color3.new(1, 1, 1)
		made.BorderSizePixel = 0
		made.ZIndex = 4
		made.Active = false
		if target:FindFirstChild("Skin") then
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.Position = UDim2.fromScale(0.5, 0.5)
			made.Size = UDim2.fromScale(0.82, 0.6)
		else
			made.Size = UDim2.fromScale(1, 1)
		end
		corner(made, 8)
		local band = Instance.new("UIGradient")
		band.Rotation = 20
		band.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		band.Parent = made
		made.Parent = target
		overlay = made
	end
	local band = (overlay :: Frame):FindFirstChildOfClass("UIGradient")
	if band then
		band.Offset = Vector2.new(-1, 0)
		TweenService:Create(band, SWEEP, { Offset = Vector2.new(1, 0) }):Play()
	end
end

-- Hover and press feel for any button: it springs up with a little tilt, a
-- shine sweeps across, its icon (an "Icon_*" child) bounces; pressing
-- squashes it and it pops back as `onClick` runs. Gamepad selection counts
-- as hovering.
function Theme.hover(button: GuiButton, onClick: (() -> ())?)
	local scale = button:FindFirstChildOfClass("UIScale")
	if scale == nil then
		local made = Instance.new("UIScale")
		made.Parent = button
		scale = made
	end
	local s = scale :: UIScale
	local function icon(): ImageLabel?
		for _, child in button:GetChildren() do
			if child:IsA("ImageLabel") and string.sub(child.Name, 1, 5) == "Icon_" then
				return child
			end
		end
		return nil
	end
	local function enter()
		TweenService:Create(s, HOVER, { Scale = 1.08 }):Play()
		TweenService:Create(button, HOVER, { Rotation = if math.random() < 0.5 then -2 else 2 })
			:Play()
		sweep(button)
		local image = icon()
		if image then
			image.Rotation = -15
			TweenService:Create(image, HOVER, { Rotation = 0 }):Play()
		end
	end
	local function leave()
		TweenService:Create(s, QUICK, { Scale = 1 }):Play()
		TweenService:Create(button, QUICK, { Rotation = 0 }):Play()
	end
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
	button.SelectionGained:Connect(enter)
	button.SelectionLost:Connect(leave)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(s, QUICK, { Scale = 0.92 }):Play()
	end)
	button.Activated:Connect(function()
		s.Scale = 0.9
		TweenService:Create(s, POP, { Scale = 1.04 }):Play()
		if onClick then
			onClick()
		end
	end)
end

-- Puts a sprite icon at the left of a sprite-skinned button, its text moved
-- over. Does nothing without the sheet.
function Theme.buttonIcon(button: TextButton, name: string)
	local label = button:FindFirstChild("Label") :: TextLabel?
	local height = math.max(button.AbsoluteSize.Y, 30)
	local image = Sprites.icon(button, name, math.floor(height * 1.15))
	if image == nil or label == nil then
		return
	end
	image.AnchorPoint = Vector2.new(0, 0.5)
	image.Position = UDim2.new(0, 0, 0.5, 0)
	image.Size = UDim2.new(1, 0, 1.15, 0)
	image.SizeConstraint = Enum.SizeConstraint.RelativeYY
	image.ZIndex = 3
	label.Position = UDim2.new(0.22, 0, 0, 0)
	label.Size = UDim2.new(0.78, 0, 1, 0)
end

-- The red close tile in a panel's top-right corner (a "Close" button
-- without the sheet). Positions itself.
function Theme.closeButton(parent: GuiObject, onClick: () -> ()): GuiButton
	if Sprites.enabled() then
		local button = Instance.new("ImageButton")
		button.Name = "Close"
		button.BackgroundTransparency = 1
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -8, 0, 6)
		button.Size = UDim2.fromOffset(42, 42)
		button.ZIndex = 3
		button.Parent = parent
		local image = Sprites.icon(button, "Close", 42) :: ImageLabel
		image.Size = UDim2.fromScale(1, 1)
		image.ZIndex = 3
		Theme.hover(button, onClick)
		return button
	end
	local button = Theme.button(parent, "Close", "primary", onClick)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, 10)
	button.Size = UDim2.fromOffset(80, 30)
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

-- Clock-driven animations ------------------------------------------------

local animated: { [Instance]: (number) -> () } = {}
local animating: RBXScriptConnection? = nil

-- Calls `step(clock)` every frame while `instance` is in the game.
function Theme.animate(instance: Instance, step: (number) -> ())
	animated[instance] = step
	if animating == nil then
		animating = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for item, fn in animated do
				if item.Parent == nil then
					animated[item] = nil
				else
					fn(now)
				end
			end
		end)
	end
end

-- Spins a gradient by `speed` degrees per second.
function Theme.spin(target: UIGradient, speed: number)
	Theme.animate(target, function(now)
		target.Rotation = (now * speed) % 360
	end)
end

-- Pulses a stroke's transparency between `low` and `high`.
function Theme.pulse(stroke: UIStroke, low: number, high: number, speed: number)
	Theme.animate(stroke, function(now)
		stroke.Transparency = low + (high - low) * (0.5 + 0.5 * math.sin(now * speed))
	end)
end

-- A bright band that sweeps across `target` every few seconds.
function Theme.shine(target: GuiObject)
	local overlay = Instance.new("Frame")
	overlay.Name = "Shine"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BorderSizePixel = 0
	overlay.ZIndex = target.ZIndex + 1
	overlay.Active = false
	if target:FindFirstChild("Skin") then
		-- Sprite art has a glow margin: keep the band on the body.
		overlay.AnchorPoint = Vector2.new(0.5, 0.5)
		overlay.Position = UDim2.fromScale(0.5, 0.5)
		overlay.Size = UDim2.fromScale(0.82, 0.6)
	end
	overlay.Parent = target
	corner(overlay, 8)
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Parent = overlay
	Theme.animate(band, function(now)
		-- Sweep for 0.8 s out of every 2.5 s.
		local t = (now % 2.5) / 0.8
		band.Offset = Vector2.new(if t < 1 then -1 + 2 * t else 1, 0)
	end)
end

local function circle(parent: Instance, size: number, color: Color3): Frame
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = dot
	return dot
end

export type StarIconStyle = "star" | "blackHole" | "locked"

-- A living star icon `size` pixels across: a pulsing halo around a core
-- whose gradient slowly turns. A black hole is a dark core in a swirling
-- accretion ring; a locked star is a dim silhouette.
function Theme.starIcon(
	parent: Instance,
	color: Color3,
	light: Color3,
	size: number,
	style: StarIconStyle
): Frame
	local holder = Instance.new("Frame")
	holder.Name = "StarIcon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	if style == "locked" then
		local core = circle(holder, size * 0.8, Color3.fromRGB(40, 44, 66))
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(90, 96, 130)
		edge.Thickness = 2
		edge.Parent = core
		Theme.label(core, {
			Size = UDim2.fromScale(1, 1),
			Text = "?",
			Font = Enum.Font.GothamBlack,
			TextSize = math.floor(size * 0.45),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(120, 128, 170),
		})
		return holder
	end
	local halo = circle(holder, size * 1.25, light)
	halo.BackgroundTransparency = 1
	local haloStroke = Instance.new("UIStroke")
	haloStroke.Color = light
	haloStroke.Thickness = math.max(2, size * 0.12)
	haloStroke.Parent = halo
	Theme.pulse(haloStroke, 0.45, 0.9, 3)
	local core = circle(holder, size * 0.8, Color3.new(1, 1, 1))
	local fill = Instance.new("UIGradient")
	if style == "blackHole" then
		fill.Color = ColorSequence.new(Color3.fromRGB(10, 4, 20), Color3.fromRGB(0, 0, 0))
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = math.max(3, size * 0.14)
		ring.Parent = core
		local swirl = Instance.new("UIGradient")
		swirl.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, light),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 160, 90)),
			ColorSequenceKeypoint.new(1, light),
		})
		swirl.Parent = ring
		Theme.spin(swirl, 160)
	else
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.35, light),
			ColorSequenceKeypoint.new(1, color),
		})
		Theme.spin(fill, 40)
	end
	fill.Parent = core
	return holder
end

-- A planet icon: a lit sphere, ringed for ringed planets.
function Theme.planetIcon(parent: Instance, color: Color3, size: number, ring: Color3?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "PlanetIcon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	local body = circle(holder, size * 0.72, Color3.new(1, 1, 1))
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.45)),
		ColorSequenceKeypoint.new(0.6, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.55)),
	})
	shade.Rotation = 45
	shade.Parent = body
	if ring then
		local band = Instance.new("Frame")
		band.AnchorPoint = Vector2.new(0.5, 0.5)
		band.Position = UDim2.fromScale(0.5, 0.5)
		band.Size = UDim2.fromOffset(size * 1.15, size * 0.3)
		band.Rotation = -18
		band.BackgroundTransparency = 1
		band.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = band
		local edge = Instance.new("UIStroke")
		edge.Color = ring
		edge.Thickness = 2
		edge.Parent = band
	end
	return holder
end

-- Height for a progress bar: sprite bars need more room than plain ones.
function Theme.barHeight(plain: number): number
	return if Sprites.enabled() then math.max(plain, 14) else plain
end

export type BarStyle = "orange" | "cyan"

-- A thin progress bar along the bottom of `parent`; returns its fill. With
-- the sprite sheet: a dark track with an orange or cyan glowing fill.
function Theme.progress(
	parent: Instance,
	share: number,
	color: Color3,
	height: number?,
	style: BarStyle?
): Frame
	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Size = UDim2.new(1, 0, 0, Theme.barHeight(height or 6))
	track.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)
	gradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	local cyan = style == "cyan"
	Sprites.skin(track, if cyan then "TrackCyan" else "TrackHeat")
	Sprites.skin(fill, if cyan then "FillCyan" else "FillHeat")
	return fill
end

return Theme

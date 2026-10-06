--!strict
-- Heads-up display: Stardust and the player's galaxy sector (top left), the
-- controls hint (bottom centre), the suit or flight readout and the Return to
-- Hangar and Station travel buttons (bottom left), the Settings and PvP buttons and the Star
-- Shop, Shipyard and Store buttons stacked under the wallet, and
-- while flying a reticle, the laser's heat gauge, the boost tank and, while
-- the beam extracts an asteroid, the extraction bar.
-- Display only; the server owns every value shown here.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local StarController = require(script.Parent.StarController)
local Sprites = require(script.Parent.Parent.UI.Sprites)
local Theme = require(script.Parent.Parent.UI.Theme)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RegionMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("RegionMath")
)
local StarMath =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("StarMath"))
local Format =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Format"))
local Input = require(script.Parent.Parent.Input)
local RewardMath = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("RewardMath")
)
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local READOUT_INTERVAL = 0.1
local HEAT_COOL = Color3.fromRGB(255, 170, 70)
local HEAT_HOT = Color3.fromRGB(255, 70, 50)
local EXTRACT_ROCK = Color3.fromRGB(150, 200, 255)
local EXTRACT_WEAK = Color3.fromRGB(127, 247, 255)

local DOCK_HINTS: { [string]: string } = {
	keyboard = "Docking area: press G to dock",
	gamepad = "Docking area: press X to dock",
	touch = "Docking area: tap Dock",
}

local HudController = {}

local stardustLabel: TextLabel
local walletPanel: Frame
local walletScale: UIScale
local shown = Instance.new("NumberValue") -- the wallet number as displayed, tweened
local COUNT_UP = TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local BUMP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WALLET_GOLD = Color3.fromRGB(255, 214, 110)
local sectorLabel: TextLabel
local hintLabel: TextLabel
local readoutLabel: TextLabel
local reticle: TextLabel
local hangarButton: TextButton
local stationButton: TextButton
local effectsButton: TextButton
local shipyardButton: TextButton
local storeButton: TextButton
local planetsButton: TextButton
local boostBar: Frame
local boostsAt = 0 -- os.clock() when the boost times last arrived
local launchButton: TextButton
local pvpButton: TextButton
local setPvpText: (string) -> ()
local hullPanel: Frame
local hullFill: Frame
local hullLabel: TextLabel
local heatPanel: Frame
local heatFill: Frame
local heatLabel: TextLabel
local extractPanel: Frame
local extractFill: Frame
local extractLabel: TextLabel
local boostPanel: Frame
local boostFill: Frame
local boostLabel: TextLabel
local shopButton: TextButton
local setEffectsText: (string) -> ()
local goalButton: TextButton
local goalEdge: UIStroke
local goalTitle: TextLabel
local goalAmount: TextLabel
local goalFill: Frame
local goalShine: Frame
local goalReady = false
local GOAL_INTERVAL = 1
local BOOST_READY = Color3.fromRGB(120, 230, 255)
local BOOST_ON = Color3.fromRGB(255, 255, 255)
local BOOST_EMPTY = Color3.fromRGB(110, 120, 150)
local HULL_GOOD = Color3.fromRGB(110, 230, 150)
local HULL_LOW = Color3.fromRGB(255, 80, 60)
local PVP_ON = Color3.fromRGB(255, 110, 100)
local PVP_OFF = Color3.fromRGB(180, 190, 220)

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildWallet(gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "Wallet"
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.Size = UDim2.new(0.22, 0, 0.11, 0)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	corner(panel, 12)
	walletPanel = panel
	local background = Instance.new("UIGradient")
	background.Color = ColorSequence.new(Color3.fromRGB(34, 38, 80), Color3.fromRGB(14, 16, 34))
	background.Rotation = 90
	background.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = WALLET_GOLD
	edge.Transparency = 0.6
	edge.Thickness = 2
	edge.Parent = panel
	walletScale = Instance.new("UIScale")
	walletScale.Parent = panel

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(180, 64)
	constraint.MaxSize = Vector2.new(300, 96)
	constraint.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = panel

	local inset = 0
	makeLabel(panel, {
		Name = "StardustTitle",
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset, 0.25, 0),
		Text = Config.Economy.CURRENCY_NAME:upper(),
		TextColor3 = Color3.fromRGB(255, 196, 92),
	})
	stardustLabel = makeLabel(panel, {
		Name = "Stardust",
		Position = UDim2.new(0, inset, 0.25, 0),
		Size = UDim2.new(1, -inset, 0.48, 0),
		Text = "...",
		Font = Enum.Font.GothamBlack,
	})
	-- A bright band sweeps across the number now and then.
	local shimmer = Instance.new("UIGradient")
	shimmer.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, WALLET_GOLD),
		ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	shimmer.Offset = Vector2.new(-1, 0)
	shimmer.Parent = stardustLabel
	task.spawn(function()
		local sweep = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		while shimmer.Parent do
			shimmer.Offset = Vector2.new(-1, 0)
			TweenService:Create(shimmer, sweep, { Offset = Vector2.new(1, 0) }):Play()
			task.wait(4)
		end
	end)
	shown.Changed:Connect(function(value)
		stardustLabel.Text = Format.abbreviate(math.floor(value + 0.5))
	end)
	sectorLabel = makeLabel(panel, {
		Name = "Sector",
		Position = UDim2.new(0, inset, 0.75, 0),
		Size = UDim2.new(1, -inset, 0.25, 0),
		Text = "Finding your galaxy...",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 190, 220),
	})

	-- Sprite sheet: the Stardust HUD panel, whose art has the Stardust star on
	-- its left; the text keeps clear of it as the panel resizes.
	if Sprites.skin(panel, "PanelHud") then
		constraint.MinSize = Vector2.new(240, 64)
		constraint.MaxSize = Vector2.new(360, 96)
		local title = panel:FindFirstChild("StardustTitle") :: TextLabel
		local function fit()
			local cap = math.max(0, Sprites.leftCap("PanelHud", panel.AbsoluteSize.Y) - 10)
			for _, label in { title, stardustLabel, sectorLabel } do
				label.Position = UDim2.new(0, cap, label.Position.Y.Scale, 0)
				label.Size = UDim2.new(1, -cap, label.Size.Y.Scale, 0)
			end
		end
		fit()
		panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end
end

-- Gives a HUD button the sprite sheet's art and an icon, moving its text to
-- a label above the art. Returns a function that sets the button's text.
local function dressButton(
	button: TextButton,
	spriteName: string,
	iconName: string?
): (string) -> ()
	if not Sprites.enabled() then
		return function(text: string)
			button.Text = text
		end
	end
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Font = button.Font
	label.TextSize = button.TextSize
	label.TextScaled = button.TextScaled
	label.TextColor3 = button.TextColor3
	label.TextStrokeTransparency = 0.4
	label.Text = button.Text
	label.Parent = button
	-- Text padding belongs to the label now, not the art.
	local padding = button:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.Parent = label
	end
	Sprites.skin(button, spriteName)
	local height = button.Size.Y.Offset
	local icon = if iconName then Sprites.icon(button, iconName, math.floor(height * 1.1)) else nil
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 2, 0.5, 0)
		icon.ZIndex = 3
		label.Position = UDim2.fromOffset(height, 0)
		label.Size = UDim2.new(1, -height - 10, 1, 0)
	end
	button.Text = ""
	return function(text: string)
		label.Text = text
	end
end

-- Recolours a gauge fill: its background, or its sprite art.
local function paintFill(fill: Frame, color: Color3)
	fill.BackgroundColor3 = color
	Sprites.tint(fill, Color3.new(1, 1, 1):Lerp(color, 0.4))
end

-- A titled bar: the laser heat gauge, the boost tank and the extraction bar.
local function makeGauge(
	gui: ScreenGui,
	name: string,
	y: number,
	title: string,
	color: Color3,
	style: Theme.BarStyle,
	iconName: string?
): (Frame, Frame, TextLabel)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, y)
	panel.Size = UDim2.new(0, 220, 0, 30)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	local label = makeLabel(panel, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 14),
		Text = title,
		TextColor3 = color,
		TextStrokeTransparency = 0.5,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, 0, 0, 18)
	track.Size = UDim2.new(1, 0, 0, Theme.barHeight(10))
	track.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	track.BackgroundTransparency = 0.25
	track.Parent = panel
	corner(track, 5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 5)
	local cyan = style == "cyan"
	Sprites.skin(track, if cyan then "TrackCyan" else "TrackHeat")
	Sprites.skin(fill, if cyan then "FillCyan" else "FillHeat")
	local icon = if iconName then Sprites.icon(panel, iconName, 30) else nil
	if icon then
		-- The icon sits left of the gauge, which moves over to make room.
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(0, -4, 0.5, 2)
		panel.Position = UDim2.new(0, 50, 1, y)
		panel.Size = UDim2.new(0, 186, 0, 30)
	end
	return panel, fill, label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	buildWallet(gui)

	hintLabel = makeLabel(gui, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.7, 0, 0, 22),
		Text = "",
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 210, 235),
		TextStrokeTransparency = 0.5,
	})

	readoutLabel = makeLabel(gui, {
		Name = "Readout",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -76),
		Size = UDim2.new(0, 220, 0, 24),
		Text = "",
		TextColor3 = Color3.fromRGB(150, 220, 255),
		TextStrokeTransparency = 0.5,
	})

	-- Travel: Hangar takes you to your own station (your tycoon), Station
	-- to the ISS, where everyone spawns.
	local function travelButton(name: string, x: number, sprite: string, icon: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.AnchorPoint = Vector2.new(0, 1)
		button.Position = UDim2.new(0, x, 1, -24)
		button.Size = UDim2.new(0, 130, 0, 40)
		button.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
		button.BackgroundTransparency = 0.2
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = Color3.fromRGB(255, 214, 120)
		button.Text = name
		button.Parent = gui
		corner(button, 8)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = button
		dressButton(button, sprite, icon)
		Theme.hover(button)
		return button
	end
	hangarButton = travelButton("Hangar", 16, "ButtonBlue", "Station")
	stationButton = travelButton("Station", 152, "ButtonPurple", "Earth")

	-- Settings (effects, sound, music, boundary box) under the wallet.
	effectsButton = Instance.new("TextButton")
	effectsButton.Name = "Settings"
	effectsButton.Position = UDim2.new(0, 16, 0, 116)
	effectsButton.Size = UDim2.new(0, 150, 0, 30)
	effectsButton.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	effectsButton.BackgroundTransparency = 0.3
	effectsButton.Font = Enum.Font.Gotham
	effectsButton.TextSize = 14
	effectsButton.TextColor3 = Color3.fromRGB(180, 190, 220)
	effectsButton.Parent = gui
	corner(effectsButton, 6)
	setEffectsText = dressButton(effectsButton, "ButtonDark", "Gear")
	Theme.hover(effectsButton)

	-- PvP switch beside it (Config.Combat): both pilots must have it on.
	pvpButton = Instance.new("TextButton")
	pvpButton.Name = "PvP"
	pvpButton.Position = UDim2.new(0, 172, 0, 116)
	pvpButton.Size = UDim2.new(0, 120, 0, 30)
	pvpButton.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	pvpButton.BackgroundTransparency = 0.3
	pvpButton.Font = Enum.Font.GothamBold
	pvpButton.TextSize = 14
	pvpButton.TextColor3 = PVP_OFF
	pvpButton.Text = "PvP: off"
	pvpButton.Parent = gui
	corner(pvpButton, 6)
	setPvpText = dressButton(pvpButton, "ButtonDark", "Shield")
	Theme.hover(pvpButton)

	-- Opens the Star Shop from anywhere (also the B key).
	shopButton = Instance.new("TextButton")
	shopButton.Name = "StarShop"
	shopButton.Position = UDim2.new(0, 16, 0, 152)
	shopButton.Size = UDim2.new(0, 180, 0, 40)
	shopButton.BackgroundColor3 = Color3.new(1, 1, 1)
	shopButton.AutoButtonColor = false
	shopButton.Font = Enum.Font.GothamBlack
	shopButton.TextSize = 15
	shopButton.TextColor3 = Color3.new(1, 1, 1)
	shopButton.TextStrokeTransparency = 0.6
	shopButton.Text = "Star Shop  [B]"
	shopButton.Parent = gui
	corner(shopButton, 8)
	local shopGradient = Instance.new("UIGradient")
	shopGradient.Color =
		ColorSequence.new(Color3.fromRGB(255, 176, 50), Color3.fromRGB(255, 120, 60))
	shopGradient.Rotation = 90
	shopGradient.Parent = shopButton
	dressButton(shopButton, "ButtonGold", "Shop")
	Theme.hover(shopButton)

	-- Opens the Shipyard (ships and upgrades) from anywhere.
	shipyardButton = Instance.new("TextButton")
	shipyardButton.Name = "Shipyard"
	shipyardButton.Position = UDim2.new(0, 16, 0, 198)
	shipyardButton.Size = UDim2.new(0, 180, 0, 40)
	shipyardButton.BackgroundColor3 = Color3.new(1, 1, 1)
	shipyardButton.AutoButtonColor = false
	shipyardButton.Font = Enum.Font.GothamBlack
	shipyardButton.TextSize = 15
	shipyardButton.TextColor3 = Color3.new(1, 1, 1)
	shipyardButton.TextStrokeTransparency = 0.6
	shipyardButton.Text = "Shipyard"
	shipyardButton.Parent = gui
	corner(shipyardButton, 8)
	local shipyardGradient = Instance.new("UIGradient")
	shipyardGradient.Color =
		ColorSequence.new(Color3.fromRGB(200, 110, 255), Color3.fromRGB(120, 50, 220))
	shipyardGradient.Rotation = 90
	shipyardGradient.Parent = shipyardButton
	dressButton(shipyardButton, "ButtonPurple", "Ship")
	Theme.hover(shipyardButton)

	-- Opens the optional Galaxy Store. Only ever opened by the player.
	storeButton = Instance.new("TextButton")
	storeButton.Name = "Store"
	storeButton.Position = UDim2.new(0, 16, 0, 244)
	storeButton.Size = UDim2.new(0, 180, 0, 40)
	storeButton.BackgroundColor3 = Color3.new(1, 1, 1)
	storeButton.AutoButtonColor = false
	storeButton.Font = Enum.Font.GothamBlack
	storeButton.TextSize = 15
	storeButton.TextColor3 = Color3.new(1, 1, 1)
	storeButton.TextStrokeTransparency = 0.6
	storeButton.Text = "Store"
	storeButton.Parent = gui
	corner(storeButton, 8)
	local storeGradient = Instance.new("UIGradient")
	storeGradient.Color =
		ColorSequence.new(Color3.fromRGB(95, 227, 255), Color3.fromRGB(150, 90, 255))
	storeGradient.Rotation = 90
	storeGradient.Parent = storeButton
	dressButton(storeButton, "ButtonBlue", "Gift")
	Theme.hover(storeButton)

	-- Opens the Planets panel (owned planets, equip and level; also P).
	planetsButton = Instance.new("TextButton")
	planetsButton.Name = "Planets"
	planetsButton.Position = UDim2.new(0, 16, 0, 290)
	planetsButton.Size = UDim2.new(0, 180, 0, 40)
	planetsButton.BackgroundColor3 = Color3.new(1, 1, 1)
	planetsButton.AutoButtonColor = false
	planetsButton.Font = Enum.Font.GothamBlack
	planetsButton.TextSize = 15
	planetsButton.TextColor3 = Color3.new(1, 1, 1)
	planetsButton.TextStrokeTransparency = 0.6
	planetsButton.Text = "Planets  [P]"
	planetsButton.Parent = gui
	corner(planetsButton, 8)
	local planetsGradient = Instance.new("UIGradient")
	planetsGradient.Color =
		ColorSequence.new(Color3.fromRGB(110, 235, 160), Color3.fromRGB(40, 160, 140))
	planetsGradient.Rotation = 90
	planetsGradient.Parent = planetsButton
	dressButton(planetsButton, "ButtonBlue", "RingedPlanet")
	Theme.hover(planetsButton)

	-- Active boosts with their time left, under the goal panel.
	boostBar = Instance.new("Frame")
	boostBar.Name = "Boosts"
	boostBar.Position = UDim2.new(0, 16, 0, 396)
	boostBar.Size = UDim2.new(0, 300, 0, 26)
	boostBar.BackgroundTransparency = 1
	boostBar.Parent = gui
	local boostLayout = Instance.new("UIListLayout")
	boostLayout.FillDirection = Enum.FillDirection.Horizontal
	boostLayout.Padding = UDim.new(0, 6)
	boostLayout.Parent = boostBar
	for _, source in { "mining", "star" } do
		local chip = makeLabel(boostBar, {
			Name = source,
			Size = UDim2.new(0, 146, 1, 0),
			BackgroundColor3 = Color3.fromRGB(16, 20, 44),
			BackgroundTransparency = 0.15,
			Text = "",
			TextScaled = false,
			TextSize = 13,
			Font = Enum.Font.GothamBlack,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if source == "mining"
				then Color3.fromRGB(95, 227, 255)
				else Color3.fromRGB(196, 150, 255),
			Visible = false,
		})
		corner(chip, 13)
		local edge = Instance.new("UIStroke")
		edge.Color = chip.TextColor3
		edge.Thickness = 1.5
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = chip
	end

	-- Spawns your ship at your station's berth and seats you in it.
	launchButton = Instance.new("TextButton")
	launchButton.Name = "LaunchShip"
	launchButton.AnchorPoint = Vector2.new(0, 1)
	launchButton.Position = UDim2.new(0, 288, 1, -24)
	launchButton.Size = UDim2.new(0, 190, 0, 40)
	launchButton.BackgroundColor3 = Color3.new(1, 1, 1)
	launchButton.AutoButtonColor = false
	launchButton.Font = Enum.Font.GothamBlack
	launchButton.TextSize = 16
	launchButton.TextColor3 = Color3.new(1, 1, 1)
	launchButton.TextStrokeTransparency = 0.6
	launchButton.Text = "Launch Ship"
	launchButton.Parent = gui
	corner(launchButton, 8)
	local launchGradient = Instance.new("UIGradient")
	launchGradient.Color =
		ColorSequence.new(Color3.fromRGB(90, 200, 255), Color3.fromRGB(60, 110, 255))
	launchGradient.Rotation = 90
	launchGradient.Parent = launchButton
	dressButton(launchButton, "ButtonBlue", "Rocket")
	Theme.hover(launchButton)

	-- Next goal: the next star tier, with progress towards its price. Opens
	-- the Star Shop when clicked.
	goalButton = Instance.new("TextButton")
	goalButton.Name = "NextGoal"
	goalButton.Text = ""
	goalButton.AutoButtonColor = false
	goalButton.Position = UDim2.new(0, 16, 0, 338)
	goalButton.Size = UDim2.new(0, 220, 0, 52)
	goalButton.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	goalButton.BackgroundTransparency = 0.2
	goalButton.Visible = false
	goalButton.Parent = gui
	corner(goalButton, 8)
	goalEdge = Instance.new("UIStroke")
	goalEdge.Color = WALLET_GOLD
	goalEdge.Thickness = 2
	goalEdge.Transparency = 1
	goalEdge.Parent = goalButton
	-- Sprite sheet: a wide panel frame with the Stardust icon.
	local goalInset = 10
	if Sprites.panelSkin(goalButton) then
		local icon = Sprites.icon(goalButton, "StarPlus", 34)
		if icon then
			icon.Position = UDim2.fromOffset(8, 4)
			icon.ZIndex = 2
			goalInset = 46
		end
	end
	goalTitle = makeLabel(goalButton, {
		Position = UDim2.fromOffset(goalInset, 6),
		Size = UDim2.new(1, -goalInset - 10, 0, 16),
		TextScaled = false,
		TextSize = 14,
		TextColor3 = WALLET_GOLD,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	goalAmount = makeLabel(goalButton, {
		Position = UDim2.fromOffset(goalInset, 22),
		Size = UDim2.new(1, -goalInset - 10, 0, 14),
		TextScaled = false,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 190, 220),
	})
	goalFill = Theme.progress(goalButton, 0, WALLET_GOLD, 6)
	local goalTrack = goalFill.Parent :: Frame
	goalTrack.Position = UDim2.new(0, goalInset, 1, -4)
	goalTrack.Size = UDim2.new(1, -goalInset - 10, 0, Theme.barHeight(6))
	Theme.shine(goalButton)
	goalShine = goalButton:FindFirstChild("Shine") :: Frame
	goalShine.Visible = false

	heatPanel, heatFill, heatLabel =
		makeGauge(gui, "LaserHeat", -108, "LASER HEAT", HEAT_COOL, "orange")
	boostPanel, boostFill, boostLabel =
		makeGauge(gui, "Boost", -142, "BOOST", BOOST_READY, "cyan", "Energy")
	extractPanel, extractFill, extractLabel =
		makeGauge(gui, "Extraction", -176, "EXTRACTING", EXTRACT_ROCK, "cyan", "Mining")
	hullPanel, hullFill, hullLabel =
		makeGauge(gui, "Hull", -210, "HULL", HULL_GOOD, "orange", "Shield")
	-- The flight gauges only show while flying, at the top of the screen in
	-- a 2 x 2 block under the speed readout.
	for index, panel in { heatPanel, boostPanel, hullPanel, extractPanel } do
		local column = (index - 1) % 2
		local row = (index - 1) // 2
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, if column == 0 then -118 else 118, 0, 30 + row * 36)
	end

	reticle = makeLabel(gui, {
		Name = "Reticle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		Text = "+",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(150, 220, 255),
		TextStrokeTransparency = 0.4,
		Visible = false,
	})

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- The wallet counts up (or down) to the new balance instead of jumping.
local function refreshStardust()
	local profile = ClientState.profile
	if profile == nil then
		stardustLabel.Text = "..."
		return
	end
	if profile.stardust > shown.Value then
		TweenService:Create(shown, COUNT_UP, { Value = profile.stardust }):Play()
	else
		shown.Value = profile.stardust
	end
end

-- Sector, star production and Stardust waiting at the Collect console.
local function refreshSector()
	local slot = ClientState.mySlot()
	local profile = ClientState.profile
	if slot == nil then
		sectorLabel.Text = "Finding your galaxy..."
	elseif profile and profile.incomeRate > 0 then
		sectorLabel.Text = `Sector {slot} · +{profile.incomeRate}/s · {Format.abbreviate(
			profile.uncollected
		)} to collect`
	else
		sectorLabel.Text = `Your galaxy: Sector {slot}`
	end
end

-- The next star tier to buy and how close you are. When you can afford it
-- the panel glows and shines.
local function refreshGoal()
	local profile = ClientState.profile
	local records = StarController.myRecords()
	local goal = StarMath.nextTier(records)
	local def = if goal then Config.Stars.BY_ID[goal] else nil
	if profile == nil or goal == nil or def == nil then
		goalButton.Visible = false
		return
	end
	goalButton.Visible = true
	local owned = 0
	for _ in records do
		owned += 1
	end
	if owned >= RegionMath.maxSystems(profile.expansion) then
		goalTitle.Text = `NEXT: {def.displayName}`
		goalAmount.Text = "Galaxy full: expand it at the Shipyard"
		goalFill.Size = UDim2.fromScale(1, 1)
		goalReady = false
	else
		local cost = StarMath.placeCost(goal, owned) or def.cost
		local share = math.clamp(profile.stardust / math.max(cost, 1), 0, 1)
		local ready = share >= 1
		goalTitle.Text = if ready
			then `READY: {def.displayName}  ·  press B`
			else `NEXT GOAL: {def.displayName}`
		goalAmount.Text =
			`{Format.abbreviate(math.min(profile.stardust, cost))} / {Format.abbreviate(cost)} {Config.Economy.CURRENCY_NAME}`
		TweenService:Create(goalFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(share, 1) })
			:Play()
		if ready and not goalReady then
			-- Just became affordable: a little bounce.
			Theme.popIn(goalButton)
		end
		goalReady = ready
	end
	goalShine.Visible = goalReady
	if goalReady then
		Theme.pulse(goalEdge, 0, 0.6, 4)
	else
		Theme.animate(goalEdge, function() end)
		goalEdge.Transparency = 1
	end
end

-- Heat comes from the server (BeamSystem's attributes on your ship).
local function refreshHeat()
	local ship = ClientState.ship
	local heat = if ship then ship:GetAttribute("Heat") else nil
	local share = if type(heat) == "number" then math.clamp(heat, 0, 1) else 0
	local overheated = ship ~= nil and ship:GetAttribute("Overheated") == true
	heatFill.Size = UDim2.fromScale(share, 1)
	paintFill(heatFill, if overheated then HEAT_HOT else HEAT_COOL:Lerp(HEAT_HOT, share))
	heatLabel.Text = if overheated then "LASER OVERHEATED: COOLING" else "LASER HEAT"
	heatLabel.TextColor3 = if overheated then HEAT_HOT else HEAT_COOL
end

-- Extraction comes from the server too (MiningSystem's attributes).
local function refreshExtraction(flying: boolean)
	local ship = ClientState.ship
	local target = if ship then ship:GetAttribute("MiningTarget") else nil
	local active = flying and type(target) == "number" and target ~= 0
	extractPanel.Visible = active
	if not active or ship == nil then
		return
	end
	local progress = ship:GetAttribute("MiningProgress")
	local share = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
	local weak = ship:GetAttribute("MiningWeak") == true
	local color = if weak then EXTRACT_WEAK else EXTRACT_ROCK
	extractFill.Size = UDim2.fromScale(share, 1)
	paintFill(extractFill, color)
	extractLabel.TextColor3 = color
	extractLabel.Text = if weak
		then "EXTRACTING: WEAK POINT"
		else "EXTRACTING: AIM AT THE GLOWING WEAK POINT"
end

-- Boost times come from the server; between updates they count down here.
local function refreshBoosts()
	local profile = ClientState.profile
	local boosts = profile and profile.boosts
	local since = os.clock() - boostsAt
	for _, source in { "mining", "star" } do
		local chip = boostBar:FindFirstChild(source) :: TextLabel
		local left = if boosts then math.max((boosts :: any)[source] - since, 0) else 0
		chip.Visible = left > 0
		if left > 0 then
			local name = if source == "mining" then "MINING" else "STARS"
			chip.Text = `2x {name}  {RewardMath.clock(left)}`
		end
	end
end

-- Hull comes from the server (CombatSystem's Health attribute on your ship).
local function refreshHull()
	local ship = ClientState.ship
	local value = if ship then ship:GetAttribute("Health") else nil
	local share = if type(value) == "number" then math.clamp(value, 0, 1) else 1
	local info = ClientState.shipInfo
	hullFill.Size = UDim2.fromScale(share, 1)
	local color = HULL_LOW:Lerp(HULL_GOOD, share)
	paintFill(hullFill, color)
	hullLabel.TextColor3 = color
	hullLabel.Text = if info then `HULL  {math.ceil(share * info.hull)} / {info.hull}` else "HULL"
end

-- Boost comes from this client's flight (ShipController).
local function refreshBoost()
	local flight = ClientState.flight
	boostFill.Size = UDim2.fromScale(math.clamp(flight.boost, 0, 1), 1)
	local color = if flight.boosting
		then BOOST_ON
		elseif flight.boostLocked then BOOST_EMPTY
		else BOOST_READY
	paintFill(boostFill, color)
	boostLabel.TextColor3 = color
	boostLabel.Text = if flight.boosting
		then "BOOSTING"
		elseif flight.boostLocked then "BOOST RECHARGING"
		else `BOOST  [{if Input.device() == "gamepad" then "L3" else "Shift"}]`
end

local function refreshReadout()
	local flying = ClientState.mode == "ship"
	-- Flying, the readout sits above the gauges at the top of the screen.
	readoutLabel.AnchorPoint = if flying then Vector2.new(0.5, 0) else Vector2.new(0, 1)
	readoutLabel.Position = if flying then UDim2.new(0.5, 0, 0, 6) else UDim2.new(0, 16, 1, -76)
	readoutLabel.TextXAlignment = if flying
		then Enum.TextXAlignment.Center
		else Enum.TextXAlignment.Left
	readoutLabel.Size = UDim2.new(0, if flying then 460 else 220, 0, 24)
	local settings = ClientState.profile and ClientState.profile.settings
	hintLabel.Visible = settings == nil or settings.showControls ~= false
	reticle.Visible = flying
	launchButton.Visible = not flying
	heatPanel.Visible = flying
	boostPanel.Visible = flying
	hullPanel.Visible = flying
	refreshExtraction(flying)
	if flying then
		refreshHeat()
		refreshBoost()
		refreshHull()
		local flight = ClientState.flight
		local readyAt = Players.LocalPlayer:GetAttribute("RocketReadyAt")
		local reload = if type(readyAt) == "number"
			then math.ceil(readyAt - Workspace:GetServerTimeNow())
			else 0
		readoutLabel.Text =
			`Speed {math.floor(flight.speed)} / {math.floor(flight.maxSpeed)}{if flight.boosting
				then "  ·  BOOST"
				else ""}  ·  {if reload > 0 then `Rocket {reload}s` else "Rocket ready"}`
		if flight.dock == "ready" then
			hintLabel.Text = DOCK_HINTS[Input.device()]
		elseif flight.dock == "tooFast" then
			hintLabel.Text =
				`Docking area: slow down below {Config.Movement.DOCK_MAX_SPEED} to dock`
		else
			hintLabel.Text = Input.hint("ship")
		end
	else
		readoutLabel.Text = if ClientState.stabilization then "Stabilizer on" else "Stabilizer off"
		hintLabel.Text = Input.hint("suit")
	end
end

-- Where reward orbs should fly to: the wallet number's centre, in screen
-- pixels including the top bar inset (for a ScreenGui with IgnoreGuiInset).
function HudController.walletTarget(): Vector2
	local inset = GuiService:GetGuiInset()
	return stardustLabel.AbsolutePosition + stardustLabel.AbsoluteSize / 2 + inset
end

-- A quick bounce and gold flash of the wallet as Stardust lands in it.
function HudController.bumpWallet()
	walletScale.Scale = 1.12
	TweenService:Create(walletScale, BUMP, { Scale = 1 }):Play()
	local edge = walletPanel:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Transparency = 0
		TweenService:Create(edge, TweenInfo.new(0.5), { Transparency = 0.6 }):Play()
	end
end

function HudController.init()
	build()
	ClientState.profileChanged:Connect(function(field)
		if field == "stardust" or field == "*" then
			refreshStardust()
		end
		if field == "stardust" or field == "expansion" or field == "*" then
			refreshGoal()
		end
		if field == "incomeRate" or field == "uncollected" or field == "*" then
			refreshSector()
		end
		if field == "boosts" or field == "*" then
			boostsAt = os.clock()
			refreshBoosts()
		end
	end)
	ClientState.regionsChanged:Connect(refreshSector)
	ClientState.modeChanged:Connect(refreshReadout)
	ClientState.stabilizationChanged:Connect(refreshReadout)
	Input.deviceChanged:Connect(refreshReadout)
	setEffectsText("Settings")
	effectsButton.Activated:Connect(function()
		ClientState.openSettings:Fire()
	end)
	local player = Players.LocalPlayer
	local function refreshPvp()
		local on = player:GetAttribute("PvP") == true
		setPvpText(if on then "PvP: ON" else "PvP: off")
		pvpButton.TextColor3 = if on then PVP_ON else PVP_OFF
		local label = pvpButton:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = pvpButton.TextColor3
		end
	end
	player:GetAttributeChangedSignal("PvP"):Connect(refreshPvp)
	refreshPvp()
	pvpButton.Activated:Connect(function()
		ClientState.setPvp(player:GetAttribute("PvP") ~= true)
	end)
	hangarButton.Activated:Connect(function()
		Net.SuitRecover:FireServer("hangar")
	end)
	stationButton.Activated:Connect(function()
		Net.SuitRecover:FireServer("station")
	end)
	shopButton.Activated:Connect(function()
		ClientState.openStarShop:Fire()
	end)
	shipyardButton.Activated:Connect(function()
		ClientState.openShipyard:Fire()
	end)
	storeButton.Activated:Connect(function()
		ClientState.openStore:Fire(nil)
	end)
	planetsButton.Activated:Connect(function()
		ClientState.openPlanets:Fire()
	end)
	launchButton.Activated:Connect(function()
		Net.ShipRequest:FireServer("launch")
	end)
	Theme.hover(goalButton)
	goalButton.Activated:Connect(function()
		ClientState.openStarShop:Fire()
	end)
	refreshReadout()
end

function HudController.start()
	refreshStardust()
	refreshSector()
	refreshReadout()
	ClientState.profileChanged:Connect(function(field)
		if field == "settings" or field == "*" then
			refreshReadout()
		end
	end)
	-- Stars come and go (placed, evolved) without a profile field changing.
	task.spawn(function()
		while true do
			refreshGoal()
			task.wait(GOAL_INTERVAL)
		end
	end)
	task.spawn(function()
		while true do
			refreshBoosts()
			task.wait(1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(READOUT_INTERVAL)
			if ClientState.mode == "ship" then
				refreshReadout()
			end
		end
	end)
end

return HudController

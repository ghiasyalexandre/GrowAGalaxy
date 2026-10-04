--!strict
-- Heads-up display: Stardust and the player's galaxy sector (top left), the
-- controls hint (bottom centre), the suit or flight readout and the Return to
-- Station button (bottom left), and while flying a reticle, the laser's
-- heat gauge and, while the beam extracts an asteroid, the extraction bar.
-- Display only; the server owns every value shown here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Format"))
local Input = require(script.Parent.Parent.Input)
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
local tutorialLabel: TextLabel
local sectorLabel: TextLabel
local hintLabel: TextLabel
local readoutLabel: TextLabel
local reticle: TextLabel
local recoverButton: TextButton
local effectsButton: TextButton
local heatPanel: Frame
local heatFill: Frame
local heatLabel: TextLabel
local extractPanel: Frame
local extractFill: Frame
local extractLabel: TextLabel

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
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	corner(panel, 10)

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

	makeLabel(panel, {
		Name = "StardustTitle",
		Size = UDim2.fromScale(1, 0.25),
		Text = Config.Economy.CURRENCY_NAME:upper(),
		TextColor3 = Color3.fromRGB(255, 196, 92),
	})
	stardustLabel = makeLabel(panel, {
		Name = "Stardust",
		Position = UDim2.fromScale(0, 0.25),
		Size = UDim2.fromScale(1, 0.48),
		Text = "...",
	})
	sectorLabel = makeLabel(panel, {
		Name = "Sector",
		Position = UDim2.fromScale(0, 0.75),
		Size = UDim2.fromScale(1, 0.25),
		Text = "Finding your galaxy...",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 190, 220),
	})
end

-- A titled bar: the laser heat gauge and the extraction bar.
local function makeGauge(
	gui: ScreenGui,
	name: string,
	y: number,
	title: string,
	color: Color3
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
	track.Size = UDim2.new(1, 0, 0, 10)
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
	return panel, fill, label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	buildWallet(gui)

	-- Tutorial hint, top centre (Config.Tutorial).
	tutorialLabel = makeLabel(gui, {
		Name = "Tutorial",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.new(0.6, 0, 0, 30),
		BackgroundColor3 = Color3.fromRGB(16, 20, 36),
		BackgroundTransparency = 0.25,
		Text = "",
		TextScaled = false,
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 230, 160),
		Visible = false,
	})
	corner(tutorialLabel, 8)

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

	recoverButton = Instance.new("TextButton")
	recoverButton.Name = "ReturnToStation"
	recoverButton.AnchorPoint = Vector2.new(0, 1)
	recoverButton.Position = UDim2.new(0, 16, 1, -24)
	recoverButton.Size = UDim2.new(0, 190, 0, 40)
	recoverButton.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	recoverButton.BackgroundTransparency = 0.2
	recoverButton.Font = Enum.Font.GothamBold
	recoverButton.TextScaled = true
	recoverButton.TextColor3 = Color3.fromRGB(255, 214, 120)
	recoverButton.Text = "Return to Station"
	recoverButton.Parent = gui
	corner(recoverButton, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = recoverButton

	-- Settings toggle under the wallet.
	effectsButton = Instance.new("TextButton")
	effectsButton.Name = "Effects"
	effectsButton.Position = UDim2.new(0, 16, 0, 116)
	effectsButton.Size = UDim2.new(0, 150, 0, 26)
	effectsButton.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	effectsButton.BackgroundTransparency = 0.3
	effectsButton.Font = Enum.Font.Gotham
	effectsButton.TextSize = 14
	effectsButton.TextColor3 = Color3.fromRGB(180, 190, 220)
	effectsButton.Parent = gui
	corner(effectsButton, 6)

	heatPanel, heatFill, heatLabel = makeGauge(gui, "LaserHeat", -108, "LASER HEAT", HEAT_COOL)
	extractPanel, extractFill, extractLabel =
		makeGauge(gui, "Extraction", -142, "EXTRACTING", EXTRACT_ROCK)

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

local function refreshStardust()
	local profile = ClientState.profile
	stardustLabel.Text = if profile then Format.abbreviate(profile.stardust) else "..."
end

local function refreshTutorial()
	local profile = ClientState.profile
	local step = if profile then Config.Tutorial.STEPS[profile.tutorialStep] else nil
	tutorialLabel.Visible = step ~= nil
	tutorialLabel.Text = if step then `Next: {step.text}` else ""
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

-- Heat comes from the server (BeamSystem's attributes on your ship).
local function refreshHeat()
	local ship = ClientState.ship
	local heat = if ship then ship:GetAttribute("Heat") else nil
	local share = if type(heat) == "number" then math.clamp(heat, 0, 1) else 0
	local overheated = ship ~= nil and ship:GetAttribute("Overheated") == true
	heatFill.Size = UDim2.fromScale(share, 1)
	heatFill.BackgroundColor3 = if overheated then HEAT_HOT else HEAT_COOL:Lerp(HEAT_HOT, share)
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
	extractFill.BackgroundColor3 = color
	extractLabel.TextColor3 = color
	extractLabel.Text = if weak
		then "EXTRACTING: WEAK POINT"
		else "EXTRACTING: AIM AT THE GLOWING WEAK POINT"
end

local function refreshReadout()
	local flying = ClientState.mode == "ship"
	reticle.Visible = flying
	heatPanel.Visible = flying
	refreshExtraction(flying)
	if flying then
		refreshHeat()
		local flight = ClientState.flight
		readoutLabel.Text = `Speed {math.floor(flight.speed)} / {math.floor(flight.maxSpeed)}`
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

function HudController.init()
	build()
	ClientState.profileChanged:Connect(function(field)
		if field == "stardust" or field == "*" then
			refreshStardust()
		end
		if field == "incomeRate" or field == "uncollected" or field == "*" then
			refreshSector()
		end
		if field == "tutorialStep" or field == "*" then
			refreshTutorial()
		end
	end)
	ClientState.regionsChanged:Connect(refreshSector)
	ClientState.modeChanged:Connect(refreshReadout)
	ClientState.stabilizationChanged:Connect(refreshReadout)
	Input.deviceChanged:Connect(refreshReadout)
	local function refreshEffects()
		effectsButton.Text = if ClientState.reducedEffects
			then "Effects: reduced"
			else "Effects: full"
	end
	ClientState.effectsChanged:Connect(refreshEffects)
	refreshEffects()
	effectsButton.Activated:Connect(function()
		ClientState.setReducedEffects(not ClientState.reducedEffects)
	end)
	recoverButton.Activated:Connect(function()
		Net.SuitRecover:FireServer()
	end)
	refreshReadout()
end

function HudController.start()
	refreshStardust()
	refreshSector()
	refreshReadout()
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

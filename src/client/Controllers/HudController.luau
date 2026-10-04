--!strict
-- Heads-up display: Credits and the player's galaxy sector (top left), the
-- controls hint (bottom centre), the suit or flight readout and the Return to
-- Station button (bottom left), and a reticle while flying.
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

local DOCK_HINTS: { [string]: string } = {
	keyboard = "Docking area: press G to dock",
	gamepad = "Docking area: press X to dock",
	touch = "Docking area: tap Dock",
}

local HudController = {}

local creditsLabel: TextLabel
local sectorLabel: TextLabel
local hintLabel: TextLabel
local readoutLabel: TextLabel
local reticle: TextLabel
local recoverButton: TextButton

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
		Name = "CreditsTitle",
		Size = UDim2.fromScale(1, 0.25),
		Text = Config.Economy.CURRENCY_NAME:upper(),
		TextColor3 = Color3.fromRGB(255, 196, 92),
	})
	creditsLabel = makeLabel(panel, {
		Name = "Credits",
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

local function refreshCredits()
	local profile = ClientState.profile
	creditsLabel.Text = if profile then Format.abbreviate(profile.credits) else "..."
end

local function refreshSector()
	local slot = ClientState.mySlot()
	sectorLabel.Text = if slot then `Your galaxy: Sector {slot}` else "Finding your galaxy..."
end

local function refreshReadout()
	local flying = ClientState.mode == "ship"
	reticle.Visible = flying
	if flying then
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
		if field == "credits" or field == "*" then
			refreshCredits()
		end
	end)
	ClientState.regionsChanged:Connect(refreshSector)
	ClientState.modeChanged:Connect(refreshReadout)
	ClientState.stabilizationChanged:Connect(refreshReadout)
	Input.deviceChanged:Connect(refreshReadout)
	recoverButton.Activated:Connect(function()
		Net.SuitRecover:FireServer()
	end)
	refreshReadout()
end

function HudController.start()
	refreshCredits()
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

--!strict
-- Heads-up display: Credits, the player's galaxy sector and a hint line.
-- Display only; the server owns every value shown here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Format"))

local HudController = {}

local creditsLabel: TextLabel
local sectorLabel: TextLabel

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

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Wallet"
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.Size = UDim2.new(0.22, 0, 0.11, 0)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(180, 64)
	constraint.MaxSize = Vector2.new(300, 96)
	constraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

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

	makeLabel(gui, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.6, 0, 0, 22),
		Text = "Use the Navigation console to warp between the ISS and your station.",
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 210, 235),
		TextStrokeTransparency = 0.5,
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

function HudController.init()
	build()
	ClientState.profileChanged:Connect(function(field)
		if field == "credits" or field == "*" then
			refreshCredits()
		end
	end)
	ClientState.regionsChanged:Connect(refreshSector)
end

function HudController.start()
	refreshCredits()
	refreshSector()
end

return HudController

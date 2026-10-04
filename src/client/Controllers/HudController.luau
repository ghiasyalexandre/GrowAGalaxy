--!strict
-- Stardust counter at the top of the screen. Display only: the server owns
-- the real balance and replicates it through leaderstats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config") :: ModuleScript) :: any
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format") :: ModuleScript) :: any

local HudController = {}

local label: TextLabel? = nil

local function build(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12)
	frame.Size = UDim2.fromOffset(260, 52)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	frame.BackgroundTransparency = 0.2
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 120, 255)
	stroke.Thickness = 2
	stroke.Parent = frame

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 230, 140)
	text.Text = `✦ 0 {Config.CURRENCY_NAME}`
	text.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = text

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return text
end

local function show(amount: number, previous: number)
	local text = label
	if not text then
		return
	end
	text.Text = `✦ {Format.abbreviate(amount)} {Config.CURRENCY_NAME}`
	if amount > previous then
		text.TextColor3 = Color3.fromRGB(255, 255, 255)
		TweenService:Create(text, TweenInfo.new(0.4), {
			TextColor3 = Color3.fromRGB(255, 230, 140),
		}):Play()
	end
end

function HudController.init()
	label = build()
end

function HudController.start()
	local leaderstats = Players.LocalPlayer:WaitForChild("leaderstats")
	local value = leaderstats:WaitForChild(Config.CURRENCY_NAME)
	if not value:IsA("IntValue") then
		return
	end
	local last = value.Value
	show(last, last)
	value.Changed:Connect(function(amount: number)
		show(amount, last)
		last = amount
	end)
end

return HudController

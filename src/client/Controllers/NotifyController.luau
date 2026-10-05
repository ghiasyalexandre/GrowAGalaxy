--!strict
-- Short messages near the top of the screen, from the server (Notify remote)
-- or from other controllers (ClientState.notify). The newest is at the
-- bottom; each fades after a few seconds.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Sprites = require(script.Parent.Parent.UI.Sprites)

local MAX_SHOWN = 3
local SHOW_FOR = 4 -- seconds
local FADE = TweenInfo.new(0.4)
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local NotifyController = {}

local list: Frame

local function show(text: string)
	local toasts = {}
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	-- Drop the oldest beyond the limit, and an identical message already shown.
	for index, toast in toasts do
		if index <= #toasts - (MAX_SHOWN - 1) or toast:GetAttribute("Text") == text then
			toast:Destroy()
		end
	end

	-- A frame holding the text, so a sprite-sheet frame can sit behind it.
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.LayoutOrder = math.floor(os.clock() * 1000) % 1e9
	toast.Size = UDim2.new(1, 0, 0, if Sprites.enabled() then 40 else 30)
	toast.BackgroundColor3 = Color3.new(1, 1, 1)
	toast.BackgroundTransparency = 0.1
	toast:SetAttribute("Text", text)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(Color3.fromRGB(40, 46, 92), Color3.fromRGB(16, 18, 38))
	fill.Rotation = 90
	fill.Parent = toast
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Color3.fromRGB(120, 140, 255)
	edge.Transparency = 0.5
	edge.Parent = toast
	local skin = Sprites.panelSkin(toast)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = toast
	TweenService:Create(scale, POP, { Scale = 1 }):Play()

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Parent = toast
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, if skin then 9 else 5)
	padding.PaddingBottom = UDim.new(0, if skin then 9 else 5)
	padding.PaddingLeft = UDim.new(0, if skin then 28 else 12)
	padding.PaddingRight = UDim.new(0, if skin then 28 else 12)
	padding.Parent = label
	toast.Parent = list

	task.delay(SHOW_FOR, function()
		if toast.Parent then
			TweenService:Create(toast, FADE, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, FADE, { TextTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
			if skin then
				TweenService:Create(skin, FADE, { ImageTransparency = 1 }):Play()
			end
			task.wait(FADE.Time)
			toast:Destroy()
		end
	end)
end

function NotifyController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Notifications"
	gui.ResetOnSpawn = false

	list = Instance.new("Frame")
	list.Name = "List"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.new(0.5, 0, 0, 56) -- below the tutorial hint
	list.Size = UDim2.new(0.5, 0, 0, 140)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ClientState.notify:Connect(show)
end

return NotifyController

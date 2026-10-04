--!strict
-- Short messages near the top of the screen, from the server (Notify remote)
-- or from other controllers (ClientState.notify). The newest is at the
-- bottom; each fades after a few seconds.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)

local MAX_SHOWN = 3
local SHOW_FOR = 4 -- seconds
local FADE = TweenInfo.new(0.4)
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local NotifyController = {}

local list: Frame

local function show(text: string)
	local toasts = {}
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	-- Drop the oldest beyond the limit, and an identical message already shown.
	for index, toast in toasts do
		if index <= #toasts - (MAX_SHOWN - 1) or toast.Text == text then
			toast:Destroy()
		end
	end

	local label = Instance.new("TextLabel")
	label.LayoutOrder = math.floor(os.clock() * 1000) % 1e9
	label.Size = UDim2.new(1, 0, 0, 30)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(Color3.fromRGB(40, 46, 92), Color3.fromRGB(16, 18, 38))
	fill.Rotation = 90
	fill.Parent = label
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Color3.fromRGB(120, 140, 255)
	edge.Transparency = 0.5
	edge.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = label
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = label
	label.Parent = list

	task.delay(SHOW_FOR, function()
		if label.Parent then
			TweenService:Create(label, FADE, { BackgroundTransparency = 1, TextTransparency = 1 })
				:Play()
			task.wait(FADE.Time)
			label:Destroy()
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
	list.Size = UDim2.new(0.5, 0, 0, 110)
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

--!strict
-- Visiting other players' hangars: a Visit button in the bottom-right
-- corner opens a list of everyone else in this server, each
-- with a Visit button that travels to their hangar (SuitRecover "visit";
-- the server checks the player is here and shares the travel cooldown).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local C = Theme.COLORS

local VisitController = {}

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local header: TextLabel

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function refresh()
	if not gui.Enabled then
		return
	end
	Theme.clear(list)
	local others: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			table.insert(others, player)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	header.Text = if #others == 0
		then "Nobody else is in this server right now."
		else "Pick a player to visit their hangar and galaxy."
	local first: TextButton? = nil
	for order, player in others do
		local row = Theme.row(list, 52, order)
		Theme.label(row, {
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -160, 0, 22),
			Text = player.DisplayName,
			TextSize = 18,
		})
		Theme.label(row, {
			Position = UDim2.fromOffset(14, 28),
			Size = UDim2.new(1, -160, 0, 18),
			Text = `@{player.Name}`,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.subtle,
		})
		local userId = player.UserId
		local button = Theme.button(row, "Visit", "buy", function()
			Net.SuitRecover:FireServer("visit", userId)
			close()
		end)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(130, 38)
		first = first or button
	end
	if Input.device() == "gamepad" and first then
		GuiService.SelectedObject = first
	end
end

local function open()
	gui.Enabled = true
	refresh()
	Theme.popIn(panel)
end

local function buildButton()
	local rail = Instance.new("ScreenGui")
	rail.Name = "VisitButton"
	rail.ResetOnSpawn = false
	rail.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rail.DisplayOrder = -1
	local button = Instance.new("TextButton")
	-- Desktop: bottom right. Touch screens: an icon in the top-right row (the
	-- bottom right is for the touch buttons). See place() below.
	button.Name = "Visit"
	button.Size = UDim2.new(0, 130, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	button.BackgroundTransparency = 0.2
	button.Text = ""
	button.Parent = rail
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 8)
	round.Parent = button
	-- The text is a label so the icon (wider than the button is tall) can sit
	-- left of it without overlapping.
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.TextStrokeTransparency = 0.4
	label.Text = "Visit"
	label.Parent = button
	local icon = Theme.icon(button, "Portal", 44)
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 2, 0.5, 0)
		icon.ZIndex = 3
		label.Position = UDim2.fromOffset(48, 0)
		label.Size = UDim2.new(1, -56, 1, 0)
	end
	Theme.hover(button, function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	rail.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function place()
		local compact = Layout.compact()
		if compact then
			Layout.place(button, "TopRight", 1)
			button.Size = UDim2.fromOffset(64, 64)
		else
			Layout.place(button, "BottomRight", 1)
			button.Size = UDim2.new(0, 130, 0, 40)
		end
		label.Visible = not compact or icon == nil
		if icon then
			icon.AnchorPoint = if compact then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
			icon.Position = if compact then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 2, 0.5, 0)
			icon.Size = UDim2.fromOffset(if compact then 56 else 44, if compact then 56 else 44)
		end
	end
	place()
	Layout.changed:Connect(place)
	-- Only on foot: travelling from a ship stows it, which surprises players.
	local function fit()
		button.Visible = ClientState.mode ~= "ship"
	end
	fit()
	ClientState.modeChanged:Connect(fit)
end

function VisitController.init()
	gui = Theme.screen("Visit", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.7, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(480, 560)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -90, 0, 28),
		Text = "Visit a galaxy",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
	header = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	Theme.closeButton(panel, close)
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(1, -28, 1, -78)
	buildButton()
end

function VisitController.start()
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return VisitController

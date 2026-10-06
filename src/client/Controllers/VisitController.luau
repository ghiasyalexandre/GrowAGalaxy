--!strict
-- Visiting other players' hangars: a Visit button in the HUD's bottom row
-- (beside Launch Ship) opens a list of everyone else in this server, each
-- with a Visit button that travels to their hangar (SuitRecover "visit";
-- the server checks the player is here and shares the travel cooldown).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

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
	-- Bottom row, right of Launch Ship (HudController: 288 + 190).
	button.Name = "Visit"
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 484, 1, -24)
	button.Size = UDim2.new(0, 120, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	button.BackgroundTransparency = 0.2
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 214, 120)
	button.Text = "Visit"
	button.Parent = rail
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 8)
	round.Parent = button
	Theme.buttonIcon(button, "Portal")
	Theme.hover(button, function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	rail.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
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

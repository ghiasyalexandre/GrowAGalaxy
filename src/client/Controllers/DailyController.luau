--!strict
-- Daily rewards: one "Daily" button in the HUD's top-right row, with a
-- pulsing red badge while today's prize or the free wheel spin is waiting,
-- and the calendar panel (Config.Daily): 14 tiles (claimed, today, still to
-- come; days 7 and 14 are big prizes), a Claim button with a countdown to
-- the next prize, and a Daily Wheel button that opens the wheel
-- (WheelController). The calendar opens by
-- itself once per session when a prize is waiting. The server decides every
-- claim (DailySystem); the day is UTC.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local WheelController = require(script.Parent.WheelController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DailyMath = require(Shared:WaitForChild("Logic"):WaitForChild("DailyMath"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local RewardMath = require(Shared:WaitForChild("Logic"):WaitForChild("RewardMath"))

local D = Config.Daily
local GOLD = Color3.fromRGB(255, 211, 107)
local VIOLET = Color3.fromRGB(176, 120, 255)
local CYAN = Color3.fromRGB(95, 227, 255)
local RED = Color3.fromRGB(255, 70, 70)
local COLUMNS = 7

local DailyController = {}

local gui: ScreenGui
local panel: Frame
local grid: Frame
local claimButtonHolder: Frame
local dayLabel: TextLabel
local badge: Frame
local claiming = false
local autoOpened = false
local shownKey = "" -- the state the calendar was last built for
local claimButton: TextButton? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function record(): { day: number, lastClaim: number }?
	local profile = ClientState.profile
	return if profile then (profile :: any).daily else nil
end

-- Today's reward rate R (prizes are minutes of it).
local function rewardRate(): number
	local profile = ClientState.profile
	local economy = if profile then (profile :: any).economy else nil
	return if economy then economy.reward else 1
end

local function claimable(): boolean
	local r = record()
	return r ~= nil and DailyMath.canClaim(r, DailyMath.today(now()))
end

local function prizeIcon(prize: any): string
	return if prize.big then "OpenChest" else "Stardust"
end

local refresh: () -> ()

local function claim()
	if claiming or not claimable() then
		return
	end
	claiming = true
	refresh()
	local ok, message = Net.DailyRequest:InvokeServer("claim")
	claiming = false
	if ok then
		local r = record()
		local day = if r then (if r.day == 1 then #D.PRIZES else r.day - 1) else 1
		ClientState.celebrate:Fire(
			"DAILY PRIZE",
			`Day {day} of {#D.PRIZES}`,
			if type(message) == "string" then message else "",
			GOLD,
			true
		)
	else
		ClientState.notify:Fire(
			if type(message) == "string" then message else "Couldn't claim right now."
		)
	end
	refresh()
end

local function tile(index: number, r: { day: number, lastClaim: number }, ready: boolean)
	local prize = D.PRIZES[index]
	local done = index < r.day
	local current = index == r.day
	local frame = Instance.new("Frame")
	frame.LayoutOrder = index
	frame.BackgroundColor3 = if done
		then Color3.fromRGB(24, 28, 44)
		elseif prize.big then Color3.fromRGB(52, 30, 92)
		else Color3.fromRGB(22, 30, 64)
	frame.BorderSizePixel = 0
	frame.Parent = grid
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 10)
	round.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Thickness = if current then 3 else 1.5
	edge.Color = if current then GOLD elseif prize.big then VIOLET else CYAN
	edge.Transparency = if done then 0.7 else 0.2
	edge.Parent = frame
	if current and ready then
		Theme.pulse(edge, 0, 0.6, 5)
		Theme.shine(frame)
	end

	Theme.label(frame, {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 3),
		Text = if current and ready then "TODAY" elseif current then "NEXT" else `DAY {index}`,
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if current then GOLD else Theme.COLORS.subtle,
	})
	local icon = Theme.icon(frame, prizeIcon(prize), if prize.big then 44 else 36)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.48)
		icon.ImageTransparency = if done then 0.6 else 0
	end
	local amount = Format.abbreviate(DailyMath.amount(index, rewardRate()))
	Theme.label(frame, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 18),
		Text = if done then "CLAIMED" else amount,
		Font = Enum.Font.GothamBlack,
		TextSize = if done then 11 else 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if done then Theme.COLORS.subtle else GOLD,
	})
end

refresh = function()
	local ready = claimable()
	local spinReady = WheelController.isReady()
	badge.Visible = ready or spinReady
	if not gui.Enabled then
		return
	end
	local r = record()
	if r == nil then
		return
	end
	local key = `{r.day}|{r.lastClaim}|{ready}|{claiming}|{rewardRate()}|{spinReady}`
	local current = claimButton
	if key == shownKey and current then
		-- Same state: only the countdown moves.
		if not ready then
			local text = `Next prize in {RewardMath.clock(DailyMath.secondsToNext(now()))}`
			local label = current:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.Text = text
			else
				current.Text = text
			end
		end
		return
	end
	shownKey = key
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	for index = 1, #D.PRIZES do
		tile(index, r, ready)
	end
	dayLabel.Text =
		`Day {r.day} of {#D.PRIZES}  ·  one prize a day (UTC)  ·  after day {#D.PRIZES} it starts again`

	Theme.clear(claimButtonHolder)
	local text = if claiming
		then "Claiming..."
		elseif ready then `CLAIM: {DailyMath.describe(DailyMath.amount(r.day, rewardRate()))}`
		else `Next prize in {RewardMath.clock(DailyMath.secondsToNext(now()))}`
	local button = Theme.button(
		claimButtonHolder,
		text,
		if ready and not claiming then "buy" else "disabled",
		if ready then claim else nil
	)
	button.Size = UDim2.new(0.62, -4, 1, 0)
	claimButton = button
	local wheel = Theme.button(
		claimButtonHolder,
		if spinReady then "DAILY WHEEL: SPIN!" else "Daily Wheel",
		if spinReady then "special" else "primary",
		function()
			gui.Enabled = false -- this panel closes; the wheel opens over the HUD
			WheelController.open()
		end
	)
	wheel.AnchorPoint = Vector2.new(1, 0)
	wheel.Position = UDim2.fromScale(1, 0)
	wheel.Size = UDim2.new(0.38, -4, 1, 0)
	if spinReady then
		Theme.shine(wheel)
	end
	if ready and not claiming then
		Theme.shine(button)
		if Input.device() == "gamepad" then
			GuiService.SelectedObject = button
		end
	end
end

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function open()
	gui.Enabled = true
	shownKey = ""
	refresh()
	Theme.popIn(panel)
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- The right-edge button (always visible).
	local rail = Instance.new("ScreenGui")
	rail.Name = "DailyButton"
	rail.ResetOnSpawn = false
	rail.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local button = Instance.new("TextButton")
	button.Name = "Daily"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.fromOffset(76, 76)
	button.BackgroundColor3 = Color3.fromRGB(20, 24, 54)
	button.AutoButtonColor = false
	button.Text = ""
	-- Desktop: in the column under the Premium button (Spin above Daily).
	-- Phones and tablets: in the HUD's top-right row (UI/Layout).
	local function place()
		if Layout.compact() then
			Layout.place(button, "TopRight", 3)
		else
			Layout.place(button, "RightColumn", 2)
		end
	end
	place()
	Layout.changed:Connect(place)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = button
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 3
	ring.Parent = button
	local icon = Theme.icon(button, "Gift", 58)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
	else
		button.Text = "DAILY"
		button.Font = Enum.Font.GothamBlack
		button.TextColor3 = GOLD
		button.TextSize = 16
	end
	Theme.label(button, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(90, 18),
		Text = "DAILY",
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
	})
	badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.85, 0.15)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundColor3 = RED
	badge.ZIndex = 3
	badge.Visible = false
	badge.Parent = button
	local badgeRound = Instance.new("UICorner")
	badgeRound.CornerRadius = UDim.new(1, 0)
	badgeRound.Parent = badge
	Theme.label(badge, {
		Size = UDim2.fromScale(1, 1),
		Text = "!",
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	local badgeScale = Instance.new("UIScale")
	badgeScale.Parent = badge
	Theme.animate(badgeScale, function(t)
		badgeScale.Scale = 1 + 0.2 * math.abs(math.sin(t * 4))
	end)
	Theme.hover(button, function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	rail.Parent = playerGui

	-- The calendar.
	gui = Theme.screen("Daily", playerGui)
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- Up to 400 tall, shrinking on short (phone) screens.
	panel.Size = UDim2.new(0.94, 0, 0.92, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 400)
	size.Parent = panel
	local titleIcon = Theme.icon(panel, "Gift", 50)
	local titleX = 16
	if titleIcon then
		titleIcon.Position = UDim2.fromOffset(10, 0)
		titleIcon.ZIndex = 2
		titleX = 66
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 30),
		Text = "DAILY PRIZES",
		TextSize = 26,
		Font = Enum.Font.GothamBlack,
		TextColor3 = GOLD,
	})
	Theme.closeButton(panel, close)
	dayLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 18),
		Text = "",
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})

	grid = Instance.new("Frame")
	grid.Name = "Calendar"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(16, 72)
	grid.Size = UDim2.new(1, -32, 1, -150) -- between the day line and the buttons
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(8, 10)
	layout.CellSize = UDim2.new(1 / COLUMNS, -8, 0.5, -6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	claimButtonHolder = Instance.new("Frame")
	claimButtonHolder.BackgroundTransparency = 1
	claimButtonHolder.AnchorPoint = Vector2.new(0.5, 1)
	claimButtonHolder.Position = UDim2.new(0.5, 0, 1, -16)
	claimButtonHolder.Size = UDim2.new(1, -32, 0, 46)
	claimButtonHolder.Parent = panel
end

function DailyController.init()
	build()
end

function DailyController.start()
	ClientState.profileChanged:Connect(function(field)
		if field == "daily" or field == "economy" or field == "*" then
			refresh()
			if field == "*" and D.OPEN_ON_JOIN and not autoOpened and claimable() then
				autoOpened = true
				task.delay(3, function()
					if claimable() and not gui.Enabled then
						open()
					end
				end)
			end
		end
	end)
	-- The countdown ticks, and a new day lights the badge without a rejoin.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return DailyController

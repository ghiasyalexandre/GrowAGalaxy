--!strict
-- The Daily Wheel: a button on the right edge (next to Daily) with the time
-- to the next spin and a badge when it's ready, and the wheel panel:
-- six equal segments with their Stardust prizes, the exact odds beside the
-- wheel, the countdown and the Spin button.
--
-- The ISS Star Lounge's Daily Wheel kiosk (prompt OpenPanel = "Wheel")
-- opens the same panel.
--
-- Spin asks the server (WheelSystem), which picks and grants the prize first;
-- the wheel then turns to land on it. With Reduced effects the wheel turns
-- less than once in a second and the rim lights and badge stay still. There
-- are no Robux spins: each costs Config.Wheel.SPIN_COST Stardust, and only
-- where paid random items are allowed (EggRequest "status").

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EggMath = require(Shared:WaitForChild("Logic"):WaitForChild("EggMath"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local WheelMath = require(Shared:WaitForChild("Logic"):WaitForChild("WheelMath"))

local W = Config.Wheel
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local GOLD = Color3.fromRGB(255, 205, 90)
local RED = Color3.fromRGB(255, 70, 90)
local LIGHTS = 18 -- bulbs round the rim

local WheelController = {}

local gui: ScreenGui
local panel: Frame
local rotor: Frame
local chips: { Frame } = {}
local bulbs: { Frame } = {}
local status: TextLabel
local spinButton: TextButton? = nil
local spinReady: string? = nil -- what the Spin button currently shows
local spin: () -> ()
local railLabel: TextLabel
local badge: Frame
local spinning = false
-- Paid random prizes allowed for this player (EggRequest "status").
local policy = "unknown"

local function nextSpin(): number
	local profile = ClientState.profile
	return if profile and profile.wheel then profile.wheel.nextSpin else 0
end

local function ready(): boolean
	return WheelMath.ready(nextSpin(), Workspace:GetServerTimeNow())
end

local function affordable(): boolean
	local profile = ClientState.profile
	return profile ~= nil and profile.stardust >= W.SPIN_COST
end

local function fetchPolicy()
	task.spawn(function()
		local ok, okFlag, _, answer = pcall(function()
			return Net.EggRequest:InvokeServer("status")
		end)
		if ok and okFlag and type(answer) == "string" then
			policy = answer
		end
	end)
end

local function clockText(seconds: number): string
	local s = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

local function close()
	if spinning then
		return
	end
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function refresh()
	local isReady = ready()
	local left = WheelMath.wait(nextSpin(), Workspace:GetServerTimeNow())
	railLabel.Text = if isReady then "SPIN!" else clockText(left)
	railLabel.TextColor3 = if isReady then GOLD else C.subtle
	badge.Visible = isReady
	if gui.Enabled and not spinning then
		status.Text = if isReady
			then (if policy ~= "allowed"
				then "The wheel isn't available for you (paid random prizes)."
				else `Your spin is ready: {Format.commas(W.SPIN_COST)} {CURRENCY}`)
			else `Next spin in {clockText(left)}`
		local state = if not isReady
			then "wait"
			elseif policy ~= "allowed" then "blocked"
			elseif not affordable() then "poor"
			else "ready"
		if spinReady ~= state or spinButton == nil then
			-- Rebuilt rather than restyled: a button's look is set when made.
			spinReady = state
			if spinButton then
				spinButton:Destroy()
			end
			local cost = Format.commas(W.SPIN_COST)
			local button = Theme.button(
				panel,
				if state == "ready"
					then `SPIN · {cost}`
					elseif state == "poor" then `Need {cost} {CURRENCY}`
					elseif state == "blocked" then "Unavailable"
					else "Come back tomorrow",
				if state == "ready" then "buy" else "disabled",
				if state == "ready" then spin else nil
			)
			button.AnchorPoint = Vector2.new(0.5, 1)
			button.Position = UDim2.new(0.5, 0, 1, -12)
			button.Size = UDim2.fromOffset(240, 46)
			spinButton = button
		end
	end
end

local function highlight(index: number)
	for i, chip in chips do
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if i == index then 4 else 1.5
			stroke.Color = if i == index then Color3.new(1, 1, 1) else Color3.fromRGB(20, 16, 40)
		end
	end
end

spin = function()
	if spinning or not ready() or not affordable() or policy ~= "allowed" then
		return
	end
	spinning = true
	status.Text = "Spinning..."
	local ok, message, index = Net.WheelRequest:InvokeServer("spin")
	if not ok or type(index) ~= "number" or W.PRIZES[index] == nil then
		spinning = false
		ClientState.notify:Fire(
			if type(message) == "string" then message else "The wheel couldn't spin."
		)
		refresh()
		return
	end
	-- The prize is already ours; now the show.
	highlight(0)
	local reduced = ClientState.reducedEffects == true
	local duration = if reduced then 1 else W.SPIN_SECONDS
	local goal = WheelMath.landing(rotor.Rotation, index, if reduced then 0 else 5)
	local tween = TweenService:Create(
		rotor,
		TweenInfo.new(
			duration,
			if reduced then Enum.EasingStyle.Quad else Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		{ Rotation = goal }
	)
	tween:Play()
	tween.Completed:Wait()
	rotor.Rotation %= 360
	highlight(index)
	spinning = false
	local prize = W.PRIZES[index]
	ClientState.celebrate:Fire(
		"DAILY WHEEL",
		`+{Format.commas(prize.stardust)} {CURRENCY}`,
		`{EggMath.percentText(prize.weight / WheelMath.total() * 100)} chance  ·  next spin in 24 h`,
		Color3.fromHex(prize.color),
		prize.weight <= 6
	)
	ClientState.notify:Fire(if type(message) == "string" then message else "You won!")
	refresh()
end

local function open()
	gui.Enabled = true
	fetchPolicy()
	refresh()
	Theme.popIn(panel)
	if Input.device() == "gamepad" and spinButton then
		GuiService.SelectedObject = spinButton
	end
end

-- A spoke from the wheel's centre at `angle` degrees clockwise from the top.
local function spoke(parent: Frame, angle: number)
	local rad = math.rad(angle)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5 + math.sin(rad) * 0.24, 0.5 - math.cos(rad) * 0.24)
	line.Size = UDim2.new(0, 3, 0.48, 0)
	line.Rotation = angle
	line.BackgroundColor3 = GOLD
	line.BackgroundTransparency = 0.2
	line.BorderSizePixel = 0
	line.Parent = parent
end

local function buildWheel(parent: Frame)
	local disc = Instance.new("Frame")
	disc.Name = "Wheel"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.54)
	disc.Size = UDim2.fromScale(0.88, 0.88)
	disc.BackgroundColor3 = Color3.fromRGB(22, 16, 46)
	disc.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = disc
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = disc
	local rim = Instance.new("UIStroke")
	rim.Color = GOLD
	rim.Thickness = 5
	rim.Parent = disc

	rotor = Instance.new("Frame")
	rotor.Name = "Rotor"
	rotor.Size = UDim2.fromScale(1, 1)
	rotor.BackgroundTransparency = 1
	rotor.Parent = disc
	local count = #W.PRIZES
	for index, prize in W.PRIZES do
		local angle = WheelMath.segmentAngle(index)
		spoke(rotor, angle + 180 / count)
		local rad = math.rad(angle)
		local chip = Instance.new("Frame")
		chip.Name = `Prize{index}`
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5 + math.sin(rad) * 0.31, 0.5 - math.cos(rad) * 0.31)
		chip.Size = UDim2.fromScale(0.27, 0.27)
		chip.Rotation = angle
		chip.BackgroundColor3 = Color3.fromHex(prize.color)
		chip.Parent = rotor
		local chipRound = Instance.new("UICorner")
		chipRound.CornerRadius = UDim.new(1, 0)
		chipRound.Parent = chip
		local edge = Instance.new("UIStroke")
		edge.Thickness = 1.5
		edge.Color = Color3.fromRGB(20, 16, 40)
		edge.Parent = chip
		Theme.label(chip, {
			Size = UDim2.fromScale(1, 1),
			Text = Format.abbreviate(prize.stardust),
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(20, 16, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.14, 0)
		pad.PaddingRight = UDim.new(0.14, 0)
		pad.PaddingTop = UDim.new(0.28, 0)
		pad.PaddingBottom = UDim.new(0.28, 0)
		pad.Parent = chip
		table.insert(chips, chip)
	end
	-- Bulbs round the rim (on the disc, so they don't turn with the rotor).
	for i = 1, LIGHTS do
		local rad = math.rad(i / LIGHTS * 360)
		local bulb = Instance.new("Frame")
		bulb.AnchorPoint = Vector2.new(0.5, 0.5)
		bulb.Position = UDim2.fromScale(0.5 + math.sin(rad) * 0.47, 0.5 - math.cos(rad) * 0.47)
		bulb.Size = UDim2.fromScale(0.035, 0.035)
		bulb.BackgroundColor3 = GOLD
		bulb.Parent = disc
		local bulbRound = Instance.new("UICorner")
		bulbRound.CornerRadius = UDim.new(1, 0)
		bulbRound.Parent = bulb
		table.insert(bulbs, bulb)
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromScale(0.14, 0.14)
	hub.BackgroundColor3 = GOLD
	hub.Parent = disc
	local hubRound = Instance.new("UICorner")
	hubRound.CornerRadius = UDim.new(1, 0)
	hubRound.Parent = hub
	-- The pointer over the top of the rim.
	Theme.label(disc, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.02),
		Size = UDim2.fromScale(0.16, 0.12),
		Text = "▼",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = RED,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
end

local function buildOdds(parent: Frame)
	local list = Instance.new("Frame")
	list.Name = "Odds"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0, 0)
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local head = Theme.label(list, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Prizes and odds",
		Font = Enum.Font.GothamBlack,
		TextColor3 = GOLD,
	})
	head.TextSize = 16
	for index, prize in W.PRIZES do
		local row = Theme.row(list, 34, index)
		Theme.swatch(row, Color3.fromHex(prize.color), 18, true).Position = UDim2.fromOffset(10, 8)
		Theme.label(row, {
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -110, 1, 0),
			Text = `{Format.commas(prize.stardust)} {CURRENCY}`,
			TextSize = 15,
		})
		Theme.label(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 70, 1, 0),
			Text = EggMath.percentText(prize.weight / WheelMath.total() * 100),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBlack,
			TextColor3 = GOLD,
		})
	end
	Theme.label(list, {
		LayoutOrder = 99,
		Size = UDim2.new(1, 0, 0, 52),
		Text = `One spin every 24 hours for {Format.commas(W.SPIN_COST)} {CURRENCY} (no Robux). Prizes are fixed: no boost or pass changes them.`,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
end

local function buildPanel()
	gui = Theme.screen("DailyWheel", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(720, 500)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -120, 0, 28),
		Text = "Daily Wheel",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = GOLD,
	})
	status = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	Theme.closeButton(panel, close)

	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(12, 64)
	left.Size = UDim2.new(0.55, -12, 1, -124)
	left.Parent = panel
	buildWheel(left)
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(0.55, 8, 0, 64)
	right.Size = UDim2.new(0.45, -24, 1, -124)
	right.Parent = panel
	buildOdds(right)
end

local function buildRail()
	local rail = Instance.new("ScreenGui")
	rail.Name = "WheelButton"
	rail.ResetOnSpawn = false
	rail.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rail.DisplayOrder = -1
	local button = Instance.new("TextButton")
	button.Name = "DailyWheel"
	button.AnchorPoint = Vector2.new(1, 0.5)
	-- Beside the Daily button (DailyController), one slot to its left.
	button.Position = UDim2.new(1, -108, 0.5, -130)
	button.Size = UDim2.fromOffset(76, 76)
	button.BackgroundColor3 = Color3.fromRGB(26, 18, 54)
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = rail
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = button
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 3
	ring.Parent = button
	-- A tiny wheel as the icon.
	local mini = Instance.new("Frame")
	mini.AnchorPoint = Vector2.new(0.5, 0.5)
	mini.Position = UDim2.fromScale(0.5, 0.48)
	mini.Size = UDim2.fromScale(0.7, 0.7)
	mini.BackgroundTransparency = 1
	mini.Parent = button
	for index, prize in W.PRIZES do
		local rad = math.rad(WheelMath.segmentAngle(index))
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.sin(rad) * 0.32, 0.5 - math.cos(rad) * 0.32)
		dot.Size = UDim2.fromScale(0.34, 0.34)
		dot.BackgroundColor3 = Color3.fromHex(prize.color)
		dot.Parent = mini
		local dotRound = Instance.new("UICorner")
		dotRound.CornerRadius = UDim.new(1, 0)
		dotRound.Parent = dot
	end
	railLabel = Theme.label(button, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(90, 18),
		Text = "WHEEL",
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
		badgeScale.Scale = if ClientState.reducedEffects
			then 1
			else 1 + 0.2 * math.abs(math.sin(t * 4))
	end)
	Theme.hover(button, function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	rail.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function WheelController.init()
	buildPanel()
	buildRail()
end

function WheelController.start()
	-- The ISS Star Lounge kiosk opens the wheel too.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("OpenPanel") == "Wheel" and not gui.Enabled then
			open()
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		-- Rim bulbs chase round while the panel is open (still when reduced).
		if gui.Enabled then
			local t = os.clock()
			for i, bulb in bulbs do
				local on = ClientState.reducedEffects
					or (math.floor(t * (if spinning then 12 else 3)) + i) % 2 == 0
				bulb.BackgroundTransparency = if on then 0 else 0.7
			end
		end
		if elapsed >= 0.5 then
			elapsed = 0
			refresh()
		end
	end)
	ClientState.profileChanged:Connect(function(field)
		if field == "wheel" or field == "*" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return WheelController

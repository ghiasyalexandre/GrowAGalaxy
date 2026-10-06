--!strict
-- The new-player tutorial on screen (Config.Tutorial), made for young
-- players: one big card at the top with a picture, a title, a few simple
-- sentences written for the device in use (keyboard, controller, touch), a
-- progress bar and big buttons.
--
--   Pointers   an arrow bounces next to the HUD button the step needs (and
--              the button glows); a "Here!" marker with the distance floats
--              over the place in the world the step needs (your Collect
--              console, the Egg Lab, your incubator, your star), visible
--              through walls.
--   Buttons    Next / Finish on steps the player confirms (the move and fly
--              steps also complete by themselves once you move or fly),
--              Hide (shrinks the card to a small tab), How to play (the
--              guide), Skip (asks twice; no reward).
--   Guide      every step's instructions in one scrolling panel, any time
--              (also from Settings), plus a few tips.
--
-- The server decides progress: gameplay steps complete from stats, the
-- rest through TutorialRequest (TutorialSystem). This only shows it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("Tutorial"))

local T = Config.Tutorial
local C = Theme.COLORS
local GOLD = Color3.fromRGB(255, 205, 90)
local CARD_COLOR = Color3.fromRGB(18, 20, 44)
local GLOW_NAME = "GaG_TutorialGlow"
local WORLD_LABELS: { [string]: string } = {
	collect = "Collect here!",
	eggLab = "Planet Egg Lab",
	incubator = "Incubator",
	star = "Your star",
}

type StepDef = TutorialConfig.StepDef

local TutorialController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local card: Frame
local icon: ImageLabel?
local iconHolder: Frame
local title: TextLabel
local counter: TextLabel
local body: TextLabel
local fill: Frame
local buttonRow: Frame
local tab: TextButton
local arrow: TextLabel
local guide: ScreenGui
local guideList: ScrollingFrame

local hidden = false
local shownIndex = 0
local skipArmedAt = 0
local busy = false
local hudTarget: GuiObject? = nil
local glow: UIStroke? = nil
local beacon: BillboardGui? = nil
local beaconPart: BasePart? = nil
local highlight: Highlight? = nil
-- Auto steps: distance covered since the step started.
local travelled = 0
local lastPosition: Vector3? = nil

local function currentIndex(): number
	local profile = ClientState.profile
	return if profile then profile.tutorialStep else 0
end

local function currentStep(): StepDef?
	return T.STEPS[currentIndex()]
end

local function textFor(step: StepDef): string
	local device = Input.device()
	if device == "gamepad" and step.gamepad then
		return step.gamepad
	elseif device == "touch" and step.touch then
		return step.touch
	end
	return step.text
end

-- World targets ----------------------------------------------------------

local function myRegion(): Instance?
	local regions = Workspace:FindFirstChild("Regions")
	if regions == nil then
		return nil
	end
	for _, region in regions:GetChildren() do
		if region:GetAttribute("OwnerUserId") == player.UserId then
			return region
		end
	end
	return nil
end

local function worldPart(kind: string): BasePart?
	local found: Instance? = nil
	if kind == "eggLab" then
		local iss = Workspace:FindFirstChild("ISS")
		found = if iss then iss:FindFirstChild("EggConsole", true) else nil
	else
		local region = myRegion()
		if region == nil then
			return nil
		end
		if kind == "collect" then
			found = region:FindFirstChild("CollectConsole", true)
		elseif kind == "incubator" then
			found = region:FindFirstChild("Chamber1", true)
		elseif kind == "star" then
			local stars = region:FindFirstChild("Stars", true)
			local first = if stars then stars:FindFirstChildOfClass("Model") else nil
			found = if first then first.PrimaryPart or first:FindFirstChild("Core") else nil
		end
	end
	return if found and found:IsA("BasePart") then found else nil
end

local function clearBeacon()
	if beacon then
		beacon:Destroy()
	end
	if highlight then
		highlight:Destroy()
	end
	beacon, beaconPart, highlight = nil, nil, nil
end

local function makeBeacon(part: BasePart, label: string)
	clearBeacon()
	local board = Instance.new("BillboardGui")
	board.Name = "GaG_TutorialBeacon"
	board.Adornee = part
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Size = UDim2.fromOffset(180, 92)
	board.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 4, 0)
	board.Parent = player:WaitForChild("PlayerGui")
	local name = Theme.label(board, {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 30),
		Text = label,
		Font = Enum.Font.GothamBlack,
		TextSize = 24,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	name.TextTruncate = Enum.TextTruncate.None
	Theme.label(board, {
		Name = "Distance",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Theme.label(board, {
		Name = "Arrow",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 40),
		Text = "▼",
		Font = Enum.Font.GothamBlack,
		TextSize = 40,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	beacon = board
	beaconPart = part
	local model = part:FindFirstAncestorOfClass("Model")
	local outline = Instance.new("Highlight")
	outline.Name = GLOW_NAME
	outline.Adornee = if model and model ~= Workspace then model else part
	outline.FillTransparency = 1
	outline.OutlineColor = GOLD
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = part
	highlight = outline
end

-- HUD targets ------------------------------------------------------------

local function findHud(name: string): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return nil
	end
	for _, item in playerGui:GetDescendants() do
		if item.Name == name and item:IsA("GuiButton") then
			local screen = item:FindFirstAncestorOfClass("ScreenGui")
			if screen and screen.Enabled and screen ~= gui then
				return item
			end
		end
	end
	return nil
end

local function clearHud()
	if glow then
		glow:Destroy()
	end
	glow, hudTarget = nil, nil
	arrow.Visible = false
end

local function pointAt(target: GuiObject)
	if hudTarget == target then
		return
	end
	clearHud()
	hudTarget = target
	local stroke = Instance.new("UIStroke")
	stroke.Name = GLOW_NAME
	stroke.Color = GOLD
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = target
	glow = stroke
end

-- Card ---------------------------------------------------------------------

local function ack(index: number)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = pcall(function()
			return Net.TutorialRequest:InvokeServer("ack", index)
		end)
		busy = false
		if not ok then
			warn(`[Tutorial] {message}`)
		end
	end)
end

local refresh: () -> ()

local function setIcon(name: string?)
	if icon then
		icon:Destroy()
		icon = nil
	end
	if name then
		local made = Theme.icon(iconHolder, name, 64)
		if made then
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.Position = UDim2.fromScale(0.5, 0.5)
			icon = made
		end
	end
end

local function buildButtons(step: StepDef, index: number)
	Theme.clear(buttonRow)
	local buttons: { TextButton } = {}
	if step.ack then
		local nextB = Theme.button(
			buttonRow,
			if step.final then `Finish (+{Format.commas(T.FINISH_REWARD)} Stardust)` else "Next",
			"buy",
			function()
				ack(index)
			end
		)
		nextB.Size = UDim2.new(0, if step.final then 230 else 130, 1, 0)
		table.insert(buttons, nextB)
	end
	local help = Theme.button(buttonRow, "How to play", "primary", function()
		ClientState.openGuide:Fire()
	end)
	help.Size = UDim2.new(0, 130, 1, 0)
	table.insert(buttons, help)
	local hide = Theme.button(buttonRow, "Hide", "primary", function()
		hidden = true
		refresh()
	end)
	hide.Size = UDim2.new(0, 80, 1, 0)
	table.insert(buttons, hide)
	if not step.final then
		local armed = os.clock() - skipArmedAt < 3
		local skip = Theme.button(
			buttonRow,
			if armed then "Sure? Skip" else "Skip",
			"disabled",
			function()
				if os.clock() - skipArmedAt < 3 then
					task.spawn(function()
						local ok, message = Net.TutorialRequest:InvokeServer("skip")
						ClientState.notify:Fire(
							if type(message) == "string"
								then message
								elseif ok then "Skipped"
								else "Try again"
						)
					end)
				else
					skipArmedAt = os.clock()
					refresh()
					task.delay(3.1, refresh)
				end
			end
		)
		skip.Size = UDim2.new(0, 96, 1, 0)
		table.insert(buttons, skip)
	end
	local x = 0
	for _, button in buttons do
		button.Position = UDim2.fromOffset(x, 0)
		x += button.Size.X.Offset + 8
	end
end

refresh = function()
	local index = currentIndex()
	local step = currentStep()
	if step == nil then
		gui.Enabled = false
		clearHud()
		clearBeacon()
		return
	end
	gui.Enabled = true
	if index ~= shownIndex then
		local advanced = shownIndex ~= 0 and index > shownIndex
		shownIndex = index
		hidden = false
		travelled, lastPosition = 0, nil
		clearHud()
		clearBeacon()
		if advanced then
			Theme.popIn(card)
			ClientState.notify:Fire("Great job! Here's what to do next.")
		end
	end
	card.Visible = not hidden
	tab.Visible = hidden
	tab.Text = `Tutorial: step {index} of {#T.STEPS}  (tap to show)`
	setIcon(step.icon)
	title.Text = step.title
	counter.Text = `Step {index} of {#T.STEPS}`
	body.Text = textFor(step)
	fill.Size = UDim2.fromScale((index - 1) / #T.STEPS, 1)
	buildButtons(step, index)
	-- When flying, the flight gauges sit at the top: move below them.
	local flying = ClientState.mode == "ship"
	card.Position = UDim2.new(0.5, 0, 0, if flying then 104 else 12)
	tab.Position = card.Position
end

-- Every frame: pointers follow their targets, auto steps watch movement.
local function step()
	local current = currentStep()
	if current == nil or not gui.Enabled then
		return
	end
	local t = os.clock()
	-- HUD arrow.
	if current.hud then
		local target = hudTarget
		if target == nil or target.Parent == nil or not target.Visible then
			local found = findHud(current.hud)
			if found then
				pointAt(found)
			else
				clearHud()
			end
			target = hudTarget
		end
		if target then
			local position, size = target.AbsolutePosition, target.AbsoluteSize
			local onLeft = position.X + size.X / 2 < gui.AbsoluteSize.X / 2
			local bounce = math.sin(t * 6) * 8
			arrow.Visible = true
			arrow.Text = if onLeft then "◀" else "▶"
			arrow.AnchorPoint = Vector2.new(if onLeft then 0 else 1, 0.5)
			arrow.Position = UDim2.fromOffset(
				if onLeft then position.X + size.X + 6 + bounce else position.X - 6 - bounce,
				position.Y + size.Y / 2
			)
			if glow then
				glow.Transparency = 0.5 + 0.5 * math.sin(t * 5)
			end
		end
	end
	-- World marker.
	if current.world then
		if beaconPart == nil or beaconPart.Parent == nil then
			local part = worldPart(current.world)
			if part then
				makeBeacon(part, WORLD_LABELS[current.world] or "Here!")
			end
		end
		local board = beacon
		local part = beaconPart
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if board and part then
			local distance = board:FindFirstChild("Distance")
			if distance and distance:IsA("TextLabel") and root and root:IsA("BasePart") then
				distance.Text = `{math.floor((root.Position - part.Position).Magnitude)} studs away`
			end
			local pointer = board:FindFirstChild("Arrow")
			if pointer and pointer:IsA("TextLabel") then
				pointer.Position = UDim2.fromOffset(0, 50 + math.abs(math.sin(t * 4)) * 8)
			end
		end
	end
	-- Auto steps: moving in the suit, flying the ship.
	if current.auto and not busy then
		local subject: BasePart? = nil
		if current.auto == "move" and ClientState.mode == "suit" then
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			subject = if root and root:IsA("BasePart") then root else nil
		elseif current.auto == "fly" and ClientState.mode == "ship" then
			local ship = ClientState.ship
			subject = if ship then ship.PrimaryPart else nil
		end
		if subject then
			local position = subject.Position
			if lastPosition then
				local moved = (position - lastPosition).Magnitude
				-- Teleports (travel buttons, launching) don't count.
				if moved < 30 then
					travelled += moved
				end
			end
			lastPosition = position
			local goal = if current.auto == "move" then T.MOVE_DISTANCE else T.FLY_DISTANCE
			if travelled >= goal then
				ack(currentIndex())
			end
		else
			lastPosition = nil
		end
	end
end

-- Guide ------------------------------------------------------------------

local TIPS = {
	{ "Daily prizes", "Press the Daily button on the right every day for free Stardust." },
	{
		"Daily Wheel",
		"Spin the wheel once a day for a Stardust prize (it costs a little Stardust).",
	},
	{ "Shipyard", "Buy faster ships with bigger lasers in the Shipyard." },
	{ "More planets", "Each star has orbits for planets. Evolve a star to open more orbits!" },
	{ "Stuck?", "Press Hangar to go home or Station to go to the big space station." },
}

local function fillGuide()
	Theme.clear(guideList)
	local order = 0
	local function card_(heading: string, text: string, color: Color3)
		order += 1
		local row = Theme.row(guideList, 40, order)
		row.AutomaticSize = Enum.AutomaticSize.Y
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = row
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = row
		Theme.label(row, {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			Text = heading,
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextColor3 = color,
		})
		local words = Theme.label(row, {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = text,
			TextWrapped = true,
			Font = Enum.Font.GothamMedium,
			TextSize = 16,
		})
		words.TextTruncate = Enum.TextTruncate.None
	end
	local index = currentIndex()
	for number, stepDef in T.STEPS do
		local done = index == 0 or number < index
		card_(
			`{number}. {stepDef.title}{if done
				then "  ✓"
				elseif number == index then "  (now)"
				else ""}`,
			textFor(stepDef),
			if number == index then GOLD else if done then Color3.fromRGB(120, 230, 150) else C.text
		)
	end
	for _, tip in TIPS do
		card_(tip[1], tip[2], Color3.fromRGB(150, 210, 255))
	end
end

local function buildGuide()
	guide = Theme.screen("HowToPlay", player:WaitForChild("PlayerGui"))
	guide.Enabled = false
	guide.DisplayOrder = 7
	local panel = Theme.panel(guide, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.86, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 720)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -90, 0, 30),
		Text = "How to play",
		TextSize = 26,
		Font = Enum.Font.GothamBlack,
		TextColor3 = GOLD,
	})
	Theme.closeButton(panel, function()
		guide.Enabled = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(guide) then
			GuiService.SelectedObject = nil
		end
	end)
	guideList = Theme.list(panel, 8)
	guideList.Position = UDim2.fromOffset(14, 52)
	guideList.Size = UDim2.new(1, -28, 1, -64)
end

-- Build ------------------------------------------------------------------

local function build()
	gui = Theme.screen("Tutorial", player:WaitForChild("PlayerGui"))
	-- Under every panel: an open shop or menu covers the card, not the
	-- other way round.
	gui.DisplayOrder = -1
	gui.Enabled = false

	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 12)
	card.Size = UDim2.new(0.92, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CARD_COLOR
	card.BackgroundTransparency = 0.08
	card.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, math.huge)
	limit.Parent = card
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 14)
	round.Parent = card
	local edge = Instance.new("UIStroke")
	edge.Color = GOLD
	edge.Thickness = 3
	edge.Parent = card
	Theme.pulse(edge, 0, 0.5, 2)
	-- The picture on the left, everything else in a column beside it.
	iconHolder = Instance.new("Frame")
	iconHolder.Name = "Picture"
	iconHolder.BackgroundColor3 = Color3.fromRGB(40, 36, 84)
	iconHolder.Size = UDim2.fromOffset(70, 70)
	iconHolder.Position = UDim2.fromOffset(12, 14)
	iconHolder.Parent = card
	local holderRound = Instance.new("UICorner")
	holderRound.CornerRadius = UDim.new(1, 0)
	holderRound.Parent = iconHolder
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(94, 10)
	content.Size = UDim2.new(1, -108, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content
	local bottom = Instance.new("UIPadding")
	bottom.PaddingBottom = UDim.new(0, 12)
	bottom.Parent = content

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.LayoutOrder = 1
	top.Size = UDim2.new(1, 0, 0, 28)
	top.Parent = content
	title = Theme.label(top, {
		Size = UDim2.new(1, -110, 1, 0),
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = GOLD,
	})
	counter = Theme.label(top, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 110, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = C.subtle,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	body = Theme.label(content, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Font = Enum.Font.GothamMedium,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(240, 242, 255),
	})
	body.TextTruncate = Enum.TextTruncate.None
	local track = Instance.new("Frame")
	track.LayoutOrder = 3
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(44, 46, 80)
	track.BorderSizePixel = 0
	track.Parent = content
	local trackRound = Instance.new("UICorner")
	trackRound.CornerRadius = UDim.new(1, 0)
	trackRound.Parent = track
	fill = Instance.new("Frame")
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(1, 0)
	fillRound.Parent = fill
	buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.LayoutOrder = 4
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, 40)
	buttonRow.Parent = content

	-- The hidden card's tab.
	tab = Instance.new("TextButton")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(0.5, 0)
	tab.Size = UDim2.fromOffset(320, 36)
	tab.BackgroundColor3 = CARD_COLOR
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 16
	tab.TextColor3 = GOLD
	tab.Visible = false
	tab.Parent = gui
	local tabRound = Instance.new("UICorner")
	tabRound.CornerRadius = UDim.new(1, 0)
	tabRound.Parent = tab
	tab.Activated:Connect(function()
		hidden = false
		refresh()
	end)

	arrow = Theme.label(gui, {
		Name = "Arrow",
		Size = UDim2.fromOffset(44, 44),
		Font = Enum.Font.GothamBlack,
		TextSize = 44,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	-- Small screens: everything a bit smaller.
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local function fit()
		local camera = Workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else 720
		scale.Scale = if height < 500 then 0.8 else 1
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

function TutorialController.init()
	build()
	buildGuide()
end

function TutorialController.start()
	ClientState.profileChanged:Connect(function(field)
		if field == "tutorialStep" or field == "*" then
			refresh()
			if guide.Enabled then
				fillGuide()
			end
		end
	end)
	ClientState.modeChanged:Connect(refresh)
	Input.deviceChanged:Connect(function()
		refresh()
		if guide.Enabled then
			fillGuide()
		end
	end)
	ClientState.openGuide:Connect(function()
		guide.Enabled = not guide.Enabled
		if guide.Enabled then
			fillGuide()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local ok, problem = pcall(step :: any)
		if not ok then
			warn(`[Tutorial] {problem}`)
		end
	end)
	refresh()
end

return TutorialController

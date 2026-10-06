--!strict
-- The Settings panel, opened from the HUD's Settings button
-- (ClientState.openSettings). Everything here is saved on the server
-- (SettingChanged) and only changes this player's view:
--
--   Effects         full or reduced (fewer particles, no ambient motion)
--   Floating        float everywhere, or walk on floors (SuitController)
--   Auto-incubate   a freed incubator chamber takes the next waiting egg
--   Sound effects   SFX volume, 0 to 100% (AudioController)
--   Music           music volume, 0 to 100%
--   Galaxy boundary whether your own region's glowing boundary box shows
--   Controls hint   whether the list of controls along the bottom shows
--   Hangar color    the highlight colour of your station (swatches; the
--                   server repaints it, StationSystem)
--   How to play     opens the tutorial guide (TutorialController)
--   Codes           a box to redeem codes for rewards (CodeSystem)
--
-- Sliders preview live and save when released.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AudioController = require(script.Parent.AudioController)
local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Parent.UI.Theme)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SettingsController = {}

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local refresh: () -> ()
local codeRow: (order: number) -> ()
-- The slider being dragged, if any.
local drag: { follow: (number) -> (), release: () -> () }? = nil

local function settings(): any
	local profile = ClientState.profile
	return profile and profile.settings
end

local function save(name: string, value: any)
	Net.SettingChanged:FireServer(name, value)
	-- Show it straight away; the server's copy arrives a moment later.
	local current = settings()
	if current then
		current[name] = value
	end
end

local function rowFrame(order: number, title: string, detail: string): Frame
	local row = Theme.row(list, 58, order)
	Theme.label(row, {
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(0.5, -12, 0, 22),
		Text = title,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(0.5, -12, 0, 18),
		Text = detail,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})
	return row
end

local function toggle(
	order: number,
	title: string,
	detail: string,
	on: boolean,
	onText: string,
	offText: string,
	flip: () -> ()
)
	local row = rowFrame(order, title, detail)
	local button = Theme.button(
		row,
		if on then onText else offText,
		if on then "buy" else "primary",
		function()
			flip()
			refresh()
		end
	)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(150, 36)
end

-- A 0..1 slider: drag or click the track.
local function slider(order: number, title: string, detail: string, name: string, value: number)
	local row = rowFrame(order, title, detail)
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -64, 0.5, 0)
	track.Size = UDim2.new(0.42, -60, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = row
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = track
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.COLORS.primary
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(1, 0)
	fillRound.Parent = fill
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(20, 20)
	knob.BackgroundColor3 = Theme.COLORS.gold
	knob.BorderSizePixel = 0
	knob.Parent = track
	local knobRound = Instance.new("UICorner")
	knobRound.CornerRadius = UDim.new(1, 0)
	knobRound.Parent = knob
	local percent = Theme.label(row, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(48, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local current = value
	local function show(v: number)
		current = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		knob.Position = UDim2.fromScale(current, 0.5)
		percent.Text = `{math.floor(current * 100 + 0.5)}%`
	end
	show(value)
	local function follow(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		show((x - track.AbsolutePosition.X) / width)
		AudioController.preview(name, current)
	end
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			follow(input.Position.X)
			drag = {
				follow = follow,
				release = function()
					save(name, math.floor(current * 100 + 0.5) / 100)
				end,
			}
		end
	end)
end

-- Your own region's boundary box: shown or hidden on this client only.
local function applyBounds()
	local current = settings()
	local show = current == nil or current.showBounds ~= false
	local regions = Workspace:FindFirstChild("Regions")
	if regions == nil then
		return
	end
	for _, region in regions:GetChildren() do
		if region:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			continue
		end
		local bounds = region:FindFirstChild("Bounds")
		if bounds then
			for _, part in bounds:GetDescendants() do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = if show then 0 else 1
				end
			end
		end
	end
end

-- A code box: type a code, press Redeem (or Enter); the server answers.
codeRow = function(order: number)
	local row = rowFrame(order, "Codes", "Got a code? Redeem it for rewards")
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -116, 0.5, 0)
	box.Size = UDim2.new(0.42, -70, 0, 34)
	box.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = "Enter code"
	box.PlaceholderColor3 = Theme.COLORS.subtle
	box.Text = ""
	box.Font = Enum.Font.GothamBold
	box.TextSize = 15
	box.TextColor3 = Theme.COLORS.text
	box.Parent = row
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 8)
	round.Parent = box
	local busy = false
	local function redeem()
		if busy or box.Text == "" then
			return
		end
		busy = true
		local ok, message = Net.CodeRequest:InvokeServer(box.Text)
		busy = false
		ClientState.notify:Fire(if type(message) == "string" then message else "Try again.")
		if ok then
			box.Text = ""
		end
	end
	local button = Theme.button(row, "Redeem", "buy", redeem)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(100, 36)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)
end

-- The hangar highlight colour: Default (the region's colour) and every
-- colour in Config.Hangar.HIGHLIGHT_COLORS as round swatches.
local function colorRow(order: number)
	local row = Theme.row(list, 96, order)
	Theme.label(row, {
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -24, 0, 22),
		Text = "Hangar color",
	})
	local profile = ClientState.profile
	local current = if profile then profile.hangarColor else nil
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(12, 40)
	holder.Size = UDim2.new(1, -24, 0, 44)
	holder.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	local choices: { { id: string, hex: string?, name: string } } = {
		{ id = "", hex = nil, name = "Default" },
	}
	for _, choice in Config.Hangar.HIGHLIGHT_COLORS do
		table.insert(choices, { id = choice.id, hex = choice.hex, name = choice.name })
	end
	for index, choice in choices do
		local picked = (current or "") == choice.id
		local swatch = Instance.new("TextButton")
		swatch.Name = choice.name
		swatch.LayoutOrder = index
		swatch.Size = UDim2.fromOffset(if picked then 38 else 32, if picked then 38 else 32)
		swatch.AutoButtonColor = false
		swatch.BackgroundColor3 = if choice.hex
			then Color3.fromHex(choice.hex)
			else Color3.fromRGB(40, 44, 70)
		swatch.Text = if choice.hex then "" else "Auto"
		swatch.TextScaled = true
		swatch.Font = Enum.Font.GothamBold
		swatch.TextColor3 = Color3.new(1, 1, 1)
		swatch.Parent = holder
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = swatch
		local edge = Instance.new("UIStroke")
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = if picked then Color3.new(1, 1, 1) else Color3.fromRGB(20, 22, 40)
		edge.Thickness = if picked then 3 else 1
		edge.Parent = swatch
		Theme.hover(swatch, function()
			Net.SettingChanged:FireServer("hangarColor", choice.id)
			if profile then
				profile.hangarColor = if choice.id == "" then nil else choice.id
			end
			ClientState.notify:Fire(`Hangar color: {choice.name}`)
			refresh()
		end)
	end
end

refresh = function()
	if not gui.Enabled then
		return
	end
	Theme.clear(list)
	local current = settings()
	if current == nil then
		return
	end
	toggle(
		1,
		"Effects",
		"Particles, glows and ambient motion",
		not ClientState.reducedEffects,
		"Full",
		"Reduced",
		function()
			ClientState.setReducedEffects(not ClientState.reducedEffects)
		end
	)
	toggle(
		2,
		"Floating",
		"Off: walk on floors; you still float in open space",
		current.floating ~= false,
		"Float",
		"Walk",
		function()
			save("floating", current.floating == false)
		end
	)
	slider(3, "Sound effects", "Lasers, explosions, your suit", "sfxVolume", current.sfxVolume)
	slider(4, "Music", "Space music; disco in boss fights", "musicVolume", current.musicVolume)
	toggle(
		6,
		"Controls hint",
		"The list of controls along the bottom of the screen",
		current.showControls ~= false,
		"Shown",
		"Hidden",
		function()
			save("showControls", current.showControls == false)
			ClientState.profileChanged:Fire("settings")
		end
	)
	toggle(
		5,
		"Galaxy boundary",
		"The glowing box around your region",
		current.showBounds ~= false,
		"Shown",
		"Hidden",
		function()
			save("showBounds", current.showBounds == false)
			applyBounds()
		end
	)
	toggle(
		7,
		"Auto-incubate",
		"A free incubator chamber starts your next egg, even offline",
		current.autoIncubate ~= false,
		"On",
		"Off",
		function()
			save("autoIncubate", current.autoIncubate == false)
		end
	)
	colorRow(8)
	local guideRow = rowFrame(9, "How to play", "Every tutorial step and tips")
	local guideButton = Theme.button(guideRow, "Open guide", "primary", function()
		ClientState.openGuide:Fire()
	end)
	guideButton.AnchorPoint = Vector2.new(1, 0.5)
	guideButton.Position = UDim2.new(1, -10, 0.5, 0)
	guideButton.Size = UDim2.fromOffset(150, 36)
	codeRow(10)
end

local function build()
	gui = Theme.screen("Settings", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	gui.DisplayOrder = 6
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, 480)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(520, 480)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 30),
		Text = "Settings",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.COLORS.gold,
	})
	Theme.closeButton(panel, function()
		gui.Enabled = false
	end)
	list = Theme.list(panel, 8)
	list.Position = UDim2.fromOffset(14, 52)
	list.Size = UDim2.new(1, -28, 1, -64)
end

function SettingsController.init()
	build()
end

function SettingsController.start()
	UserInputService.InputChanged:Connect(function(input)
		local active = drag
		if
			active
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			active.follow(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local active = drag
		if
			active
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			drag = nil
			active.release()
		end
	end)
	ClientState.openSettings:Connect(function()
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			refresh()
			Theme.popIn(panel)
		end
	end)
	ClientState.effectsChanged:Connect(refresh)
	ClientState.profileChanged:Connect(function(field)
		if field == "settings" or field == "*" then
			applyBounds()
		end
	end)
	-- Bounds are rebuilt when a region grows: hide the new ones too.
	task.spawn(function()
		local regions = Workspace:WaitForChild("Regions")
		regions.DescendantAdded:Connect(function(item)
			if
				item.Name == "Bounds"
				or (item:IsA("BasePart") and item.Parent and item.Parent.Name == "Bounds")
			then
				applyBounds()
			end
		end)
		applyBounds()
	end)
end

return SettingsController

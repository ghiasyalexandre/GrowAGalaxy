--!strict
-- The Shipyard panel, opened from your station's Shipyard console. Two tabs:
--   Ships     the 11-ship ladder as cards with a spinning preview of each
--             ship's model, its stats, and Buy / Select. A ship can be bought
--             once you own the one before it (Progression.shipUnlocked).
--   Upgrades  equipment and galaxy expansion.
-- Prices and ownership come from config and your profile view; the server
-- (ShopSystem) checks and performs every purchase.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Logic"):WaitForChild("Progression"))
local ShipModel = require(Shared:WaitForChild("Util"):WaitForChild("ShipModel"))
local Ships = require(Shared:WaitForChild("Config"):WaitForChild("Ships"))

type ShipDef = Ships.ShipDef

local CURRENCY = Config.Economy.CURRENCY_NAME
local STAT_NAMES: { [string]: string } = {
	maxSpeed = "speed",
	acceleration = "acceleration",
	braking = "braking",
	turnRate = "turning",
	beamPower = "laser power",
	beamRange = "laser range",
	heatCapacity = "heat capacity",
	coolingRate = "cooling",
	cargoCapacity = "cargo",
	boostMultiplier = "boost",
	boostDuration = "boost time",
	boostRecharge = "boost recharge",
}

-- Stat bars on a ship card: label, stat, bar colour.
local CARD_STATS: { { label: string, stat: string, color: Color3 } } = {
	{ label = "Speed", stat = "maxSpeed", color = Color3.fromRGB(90, 200, 255) },
	{ label = "Laser", stat = "beamPower", color = Color3.fromRGB(255, 120, 90) },
	{ label = "Boost", stat = "boostMultiplier", color = Color3.fromRGB(150, 120, 255) },
	{ label = "Heat", stat = "heatCapacity", color = Color3.fromRGB(255, 190, 80) },
}
local CARD_HEIGHT = 124
local PREVIEW_SIZE = 108

type Tab = "ships" | "upgrades"

local ShopController = {}

local gui: ScreenGui
local list: ScrollingFrame
local panel: Frame
local tabBar: Frame
local tab: Tab = "ships"
local firstButton: TextButton? = nil
-- Ship previews survive refreshes (the panel refreshes on every Stardust
-- change); only the cards around them are rebuilt.
local previews: { [string]: ViewportFrame } = {}
-- The best value of each card stat across the ladder, for bar lengths.
local statMax: { [string]: number } = {}

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function request(action: string, id: string?)
	local ok, message = Net.ShopRequest:InvokeServer(action, id)
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
end

local function heading(text: string, order: number, iconName: string?)
	local holder = Theme.row(list, 28, order)
	holder.BackgroundTransparency = 1
	local icon = if iconName then Theme.icon(holder, iconName, 30) else nil
	local inset = 0
	if icon then
		icon.Position = UDim2.fromOffset(0, -1)
		inset = 36
	end
	Theme.label(holder, {
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset, 1, 0),
		Text = text,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.COLORS.gold,
	})
end

local function remember(button: TextButton)
	if firstButton == nil then
		firstButton = button
	end
end

-- A row: description on the left, an action button (or status) on the right.
local function row(
	order: number,
	title: string,
	detail: string,
	buttonText: string,
	onClick: (() -> ())?
)
	local frame = Theme.row(list, 54, order)
	Theme.label(frame, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -170, 0, 22),
		Text = title,
	})
	Theme.label(frame, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -170, 0, 18),
		Text = detail,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})
	local style: Theme.ButtonStyle = if onClick == nil
		then "disabled"
		elseif string.find(buttonText, "Buy") then "buy"
		else "primary"
	local button = Theme.button(frame, buttonText, style, onClick)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(140, 36)
	if onClick then
		remember(button)
	end
end

local function priceText(cost: number, stardust: number): string
	return if stardust >= cost
		then `Buy: {Format.abbreviate(cost)}`
		else `{Format.abbreviate(cost)} {CURRENCY}`
end

-- Ship previews ------------------------------------------------------------

-- A ViewportFrame showing the ship's imported model turning slowly, or the
-- ship icon on a disc of its paint while the model isn't imported yet.
local function makePreview(def: ShipDef): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Name = "Preview"
	view.Size = UDim2.fromOffset(PREVIEW_SIZE, PREVIEW_SIZE)
	view.BackgroundColor3 = Color3.fromRGB(8, 10, 24)
	view.BackgroundTransparency = 0.1
	view.BorderSizePixel = 0
	view.Ambient = Color3.fromRGB(150, 155, 185)
	view.LightColor = Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-1, -2, -1)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = view
	local glow = Instance.new("UIStroke")
	glow.Color = Color3.fromHex(def.paint)
	glow.Thickness = 2
	glow.Transparency = 0.35
	glow.Parent = view

	local source = ShipModel.find(def)
	local ok, model, size = false, nil :: Model?, Vector3.one
	if source then
		ok, model, size = pcall(ShipModel.fit, source, def, nil)
	end
	if ok and model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and not ShipModel.textured(part) then
				part.Color = Color3.fromHex(def.paint)
			end
		end
		model.Parent = view
		local camera = Instance.new("Camera")
		camera.FieldOfView = 35
		local reach = math.max(size.X, size.Y, size.Z)
		local eye = Vector3.new(0.9, 0.55, -1).Unit * reach * 1.75
		camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
		camera.Parent = view
		view.CurrentCamera = camera
	else
		local disc = Theme.swatch(view, Color3.fromHex(def.paint), 70, true)
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		local icon = Theme.icon(view, "Ship", 64)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 2
		end
	end
	return view
end

-- Starts (or restarts, after a refresh reparented it) a preview's turntable.
local function spin(view: ViewportFrame)
	local model = view:FindFirstChildOfClass("Model")
	if model == nil then
		return
	end
	local base = model:GetPivot()
	local start = os.clock()
	local angle = model:GetAttribute("Angle")
	local offset = if type(angle) == "number" then angle else 0
	-- Undo the last stored angle so the turntable continues where it was.
	base = CFrame.Angles(0, -offset, 0) * base
	Theme.animate(view, function(now)
		local a = offset + (now - start) * Config.Ships.PREVIEW_SPIN
		model:SetAttribute("Angle", a)
		model:PivotTo(CFrame.Angles(0, a, 0) * base)
	end)
end

local function preview(def: ShipDef): ViewportFrame
	local cached = previews[def.id]
	if cached then
		return cached
	end
	local view = makePreview(def)
	previews[def.id] = view
	return view
end

-- Ship cards ---------------------------------------------------------------

local function statBar(
	card: Frame,
	index: number,
	label: string,
	value: number,
	share: number,
	color: Color3
)
	local y = 52 + (index - 1) * 17
	Theme.label(card, {
		Position = UDim2.fromOffset(128, y),
		Size = UDim2.fromOffset(84, 16),
		Text = `{label} {value}`,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Theme.COLORS.subtle,
	})
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(214, y)
	holder.Size = UDim2.new(1, -214 - 162, 0, 16)
	holder.Parent = card
	local track = Theme.progress(holder, share, color, 6, "cyan")
	local parentTrack = track.Parent :: Frame
	parentTrack.Position = UDim2.new(0, 0, 1, -3)
end

local function shipCard(order: number, shipId: string, profile: any, isNext: boolean)
	local def = Config.Ships.BY_ID[shipId]
	local index = table.find(Config.Ships.ORDER, shipId) or 0
	local owned = profile.ownedShips[shipId] == true
	local active = profile.activeShip == shipId
	local unlocked = owned or Progression.shipUnlocked(shipId, profile.ownedShips)

	local card = Theme.row(list, CARD_HEIGHT, order)
	if active then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.COLORS.gold
		stroke.Thickness = 2
		stroke.Parent = card
		Theme.pulse(stroke, 0.05, 0.6, 3)
	end

	local view = preview(def)
	view.Position = UDim2.fromOffset(8, 8)
	view.ImageColor3 = if unlocked then Color3.new(1, 1, 1) else Color3.fromRGB(70, 70, 90)
	view.Parent = card
	spin(view)

	local badge = Theme.label(card, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(30, 20),
		Text = `#{index}`,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = Theme.COLORS.gold,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
	})
	badge.TextXAlignment = Enum.TextXAlignment.Left
	if not unlocked then
		Theme.label(card, {
			Position = UDim2.fromOffset(8, 8 + PREVIEW_SIZE / 2 - 10),
			Size = UDim2.fromOffset(PREVIEW_SIZE, 20),
			Text = "LOCKED",
			Font = Enum.Font.GothamBlack,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
		})
	end

	Theme.label(card, {
		Position = UDim2.fromOffset(128, 8),
		Size = UDim2.new(1, -128 - 162, 0, 22),
		Text = def.displayName,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = if active then Theme.COLORS.gold else Theme.COLORS.text,
	})
	local s = def.stats
	Theme.label(card, {
		Position = UDim2.fromOffset(128, 30),
		Size = UDim2.new(1, -128 - 162, 0, 18),
		Text = `{def.role} · boost x{s.boostMultiplier} for {s.boostDuration}s`,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.fromHex(def.paint):Lerp(Color3.new(1, 1, 1), 0.45),
	})
	for i, entry in CARD_STATS do
		local value = (s :: any)[entry.stat] :: number
		statBar(card, i, entry.label, value, value / (statMax[entry.stat] or value), entry.color)
	end

	local text: string
	local style: Theme.ButtonStyle
	local action: (() -> ())? = nil
	local note: string? = nil
	if active then
		text, style = "Active", "disabled"
		note = "Launches from your hangars"
	elseif owned then
		text, style = "Select", "primary"
		action = function()
			request("selectShip", shipId)
		end
	else
		local cost = Progression.shipCost(shipId)
		if cost == nil then
			text, style = "Unavailable", "disabled"
		elseif not unlocked then
			local previous = Progression.previousShip(shipId)
			text, style = Format.abbreviate(cost), "disabled"
			note = `Own the {if previous
				then Config.Ships.BY_ID[previous].displayName
				else "previous ship"} first`
		else
			text = priceText(cost, profile.stardust)
			style = if profile.stardust >= cost then "buy" else "disabled"
			if profile.stardust < cost then
				note = `{Format.abbreviate(cost - profile.stardust)} more {CURRENCY}`
			end
			action = function()
				request("buyShip", shipId)
			end
		end
	end
	-- An unaffordable next ship still gets a working button: the server explains.
	local button = Theme.button(
		card,
		text,
		if action and style == "disabled" then "special" else style,
		action
	)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, if note then -10 else 0)
	button.Size = UDim2.fromOffset(144, 38)
	if action then
		remember(button)
	end
	if isNext and action then
		Theme.shine(button)
		local tag = Theme.label(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.fromOffset(144, 16),
			Text = "NEXT SHIP",
			Font = Enum.Font.GothamBlack,
			TextSize = 12,
			TextColor3 = Theme.COLORS.gold,
		})
		tag.TextXAlignment = Enum.TextXAlignment.Center
	end
	if note then
		local hint = Theme.label(card, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 22),
			Size = UDim2.fromOffset(150, 16),
			Text = note,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.COLORS.subtle,
		})
		hint.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function shipsTab(profile: any)
	-- The first ship you don't own yet is the next goal.
	local nextShip: string? = nil
	for _, shipId in Config.Ships.ORDER do
		if not profile.ownedShips[shipId] then
			nextShip = shipId
			break
		end
	end
	local order = 0
	for _, shipId in Config.Ships.ORDER do
		if Config.Ships.BY_ID[shipId].enabled then
			order += 1
			shipCard(order, shipId, profile, shipId == nextShip)
		end
	end
end

local function upgradesTab(profile: any)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	heading("Equipment (fitted to every ship you own)", nextOrder(), "Mining")
	for _, itemId in Config.Equipment.ORDER do
		local def = Config.Equipment.BY_ID[itemId]
		local cost = Progression.equipmentCost(itemId)
		if cost == nil then
			continue
		end
		local effects: { string } = {}
		for stat, multiplier in def.modifiers do
			table.insert(
				effects,
				`+{math.floor((multiplier - 1) * 100 + 0.5)}% {STAT_NAMES[stat] or stat}`
			)
		end
		local detail = table.concat(effects, ", ")
		if profile.ownedEquipment[itemId] then
			row(nextOrder(), def.displayName, detail, "Owned", nil)
		else
			row(nextOrder(), def.displayName, detail, priceText(cost, profile.stardust), function()
				request("buyEquipment", itemId)
			end)
		end
	end

	heading("Galaxy", nextOrder(), "Galaxy")
	local level = profile.expansion
	local current = Config.Galaxy.EXPANSIONS[level]
	local cost = Progression.expansionCost(level)
	if cost then
		local nextDef = Config.Galaxy.EXPANSIONS[level + 1]
		local detail =
			`Holds {current.maxSystems} stars now; expanding raises it to {nextDef.maxSystems} and grows your region`
		row(
			nextOrder(),
			`Expansion {level + 1}`,
			detail,
			priceText(cost, profile.stardust),
			function()
				request("expand")
			end
		)
	else
		row(nextOrder(), "Galaxy fully expanded", `Holds {current.maxSystems} stars`, "Max", nil)
	end
end

local refresh: () -> ()

local function buildTabs()
	Theme.clear(tabBar)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tabBar
	for order, entry in
		{
			{ id = "ships", text = "Ships", icon = "Rocket" },
			{ id = "upgrades", text = "Upgrades", icon = "Gear" },
		}
	do
		local selected = tab == entry.id
		local button = Theme.button(
			tabBar,
			entry.text,
			if selected then "buy" else "primary",
			function()
				if tab ~= entry.id then
					tab = entry.id :: Tab
					list.CanvasPosition = Vector2.zero
					buildTabs()
					refresh()
				end
			end
		)
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(140, 34)
		Theme.buttonIcon(button, entry.icon)
	end
end

function refresh()
	local profile = ClientState.profile
	if profile == nil or not gui.Enabled then
		return
	end
	-- Keep the cached previews out of the way while the list is cleared.
	for _, view in previews do
		view.Parent = nil
	end
	Theme.clear(list)
	firstButton = nil
	if tab == "ships" then
		shipsTab(profile)
	else
		upgradesTab(profile)
	end
	if Input.device() == "gamepad" and firstButton then
		GuiService.SelectedObject = firstButton
	end
end

local function open(which: Tab?)
	if which and which ~= tab then
		tab = which
		buildTabs()
	end
	gui.Enabled = true
	refresh()
	Theme.popIn(panel)
end

local function build()
	gui = Theme.screen("Shipyard", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false

	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 580)
	size.Parent = panel

	-- Sprite sheet: the ship icon before the title.
	local titleX = 16
	local icon = Theme.icon(panel, "Ship", 50)
	if icon then
		icon.Position = UDim2.fromOffset(10, 0)
		icon.ZIndex = 2
		titleX = 66
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 30),
		Text = "Shipyard",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.COLORS.gold,
	})
	Theme.closeButton(panel, close)

	tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(14, 50)
	tabBar.Size = UDim2.new(1, -28, 0, 36)
	tabBar.Parent = panel
	buildTabs()

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 94)
	list.Size = UDim2.new(1, -28, 1, -106)

	for _, def in Config.Ships.BY_ID do
		for _, entry in CARD_STATS do
			local value = (def.stats :: any)[entry.stat] :: number
			statMax[entry.stat] = math.max(statMax[entry.stat] or 0, value)
		end
	end
end

function ShopController.init()
	build()
end

function ShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("TycoonAction") ~= "Shipyard" then
			return
		end
		-- The console sits inside its owner's region model.
		local owner: Instance? = prompt:FindFirstAncestorOfClass("Model")
		while owner and owner:GetAttribute("OwnerUserId") == nil do
			owner = owner:FindFirstAncestorOfClass("Model")
		end
		if owner and owner:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			ClientState.notify:Fire("This is someone else's Shipyard.")
			return
		end
		open(nil)
	end)
	ClientState.profileChanged:Connect(function(field)
		if
			field == "stardust"
			or field == "ownedShips"
			or field == "activeShip"
			or field == "ownedEquipment"
			or field == "expansion"
			or field == "*"
		then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return ShopController

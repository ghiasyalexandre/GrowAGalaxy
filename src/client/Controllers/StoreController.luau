--!strict
-- The Galaxy Store: optional Robux purchases (Config.Products), opened only
-- by the player (HUD Store button). Four tabs: Passes, Boosts, Stardust,
-- Ships. Every offer shows its exact benefit, whether it's permanent or
-- timed, how it stacks, the price Roblox reports for this player, whether
-- it's owned, and how to get the same thing by playing, when there is a way.
--
-- Prices come from MarketplaceService:GetProductInfoAsync on this client, so
-- they match the purchase prompt (including any regional or personalised
-- price). An offer that isn't configured (no id, disabled, or purchases
-- switched off), or whose price can't be loaded, can't be bought.
--
-- This panel only opens Roblox's prompt. The server decides what's owned
-- and grants every purchase (MonetizationSystem); nothing here grants
-- anything.
--
-- Looks: a rotating rainbow border, a twinkling star field, a gradient
-- header with a shimmering gold title, cards that glow in their
-- category's colour, and shine sweeps across every Buy button.
--
-- Repeat purchases: developer products (boosts, Stardust packs) can be
-- bought again and again. While Roblox's prompt is open the card says
-- "Waiting..."; it frees up when the prompt reports back, when the server
-- delivers the purchase (Stardust or boost time arrives), or after
-- PENDING_TIMEOUT, whichever comes first.
--
-- Phones: on a short screen the cards shrink to the essentials. Consoles:
-- the first Buy button is selected, LB / RB switch tabs, B closes, and a
-- hint line says so.

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Progression = require(Shared:WaitForChild("Logic"):WaitForChild("Progression"))
local RewardMath = require(Shared:WaitForChild("Logic"):WaitForChild("RewardMath"))

local P = Config.Products
local CURRENCY = Config.Economy.CURRENCY_NAME

local CYAN = Color3.fromRGB(95, 227, 255)
local VIOLET = Color3.fromRGB(176, 120, 255)
local GOLD = Color3.fromRGB(255, 211, 107)
local MAGENTA = Color3.fromRGB(255, 110, 200)
local NAVY = Color3.fromRGB(14, 18, 44)
local DEEP_VIOLET = Color3.fromRGB(46, 22, 86)
local STAR_COUNT = 40
local PENDING_TIMEOUT = 20 -- seconds before a silent prompt frees its card
local COMPACT_HEIGHT = 430 -- panel heights below this use compact cards

type Tab = "pass" | "boost" | "pack" | "ship"
type Price = { state: "loading" | "ok" | "failed", robux: number? }

local TABS: { { id: Tab, text: string, icon: string } } = {
	{ id = "pass", text = "Passes", icon = "Medal" },
	{ id = "boost", text = "Boosts", icon = "Energy" },
	{ id = "pack", text = "Stardust", icon = "CoinPile" },
	{ id = "ship", text = "Ships", icon = "Rocket" },
}

local NOTES: { [Tab]: string } = {
	pass = "Optional and permanent. Everything in the game can also be reached with Stardust.",
	boost = "Boost timers only count down while you're in the game, and pause while you're offline.",
	pack = "Fixed amounts of Stardust. Multipliers and boosts never apply to packs.",
	ship = "The same ships you can buy with Stardust in the Shipyard, with identical stats.",
}

local StoreController = {}

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local tabBar: Frame
local noteLabel: TextLabel
local tab: Tab = "pass"
local prices: { [string]: Price } = {}
local pending: { [string]: number } = {} -- os.clock() a prompt opened, by key
local firstButton: GuiButton? = nil
local hintLabel: TextLabel

local function configured(def: any): boolean
	return P.PURCHASES_ENABLED and def.enabled and def.id > 0
end

local function iconFor(def: any): string
	local grants = def.grants
	if grants.multiplier then
		return if grants.multiplier.source == "mining" then "Mining" else "StarPlus"
	elseif grants.beamPower then
		return "Energy"
	elseif grants.autoCollect then
		return "CoinPile"
	elseif grants.boost then
		return if grants.boost.source == "mining" then "Rocket" else "RainbowStar"
	elseif grants.stardust then
		return if grants.stardust >= 400000
			then "OpenChest"
			elseif grants.stardust >= 100000 then "Chest"
			else "CoinPile"
	elseif grants.ship then
		return "Ship"
	end
	return "Gift"
end

local function owned(def: any): boolean
	local profile = ClientState.profile
	if profile == nil then
		return false
	end
	if def.grants.ship and profile.ownedShips[def.grants.ship] then
		return true -- earned or bought: either way, nothing to sell
	end
	return def.kind == "GamePass" and profile.passes ~= nil and profile.passes[def.key] == true
end

-- How to get this by playing, when there is a way.
local function playPath(def: any): string?
	local ship = def.grants.ship
	if ship then
		local shipDef = Config.Ships.BY_ID[ship]
		local cost = Progression.shipCost(ship)
		local previous = Progression.previousShip(ship)
		if shipDef and cost then
			local after = if previous
				then ` after the {Config.Ships.BY_ID[previous].displayName}`
				else ""
			return `Or earn it: Shipyard, {Format.abbreviate(cost)} {CURRENCY}{after}.`
		end
	elseif def.grants.stardust then
		return `Or earn it: mine asteroids and collect from your stars.`
	end
	return nil
end

local function statusLine(def: any): string
	if def.kind == "GamePass" then
		return `PERMANENT  ·  {def.stacking}`
	end
	local boost = def.grants.boost
	if boost then
		local profile = ClientState.profile
		local left = if profile and profile.boosts then profile.boosts[boost.source] or 0 else 0
		local active = if left > 0 then `  ·  ACTIVE: {RewardMath.clock(left)} left` else ""
		return `TEMPORARY: {boost.seconds // 60} MIN  ·  {def.stacking}{active}`
	end
	return `ONE-TIME  ·  {def.stacking}`
end

local refresh: () -> ()
local buildTabs: () -> ()

local function loadPrice(def: any)
	if prices[def.key] ~= nil or not configured(def) then
		return
	end
	prices[def.key] = { state = "loading" }
	task.spawn(function()
		local infoType = if def.kind == "GamePass"
			then Enum.InfoType.GamePass
			else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(def.id, infoType)
		end)
		local robux = if ok and type(info) == "table" then info.PriceInRobux else nil
		local forSale = not (ok and type(info) == "table" and info.IsForSale == false)
		if type(robux) == "number" and forSale then
			prices[def.key] = { state = "ok", robux = robux }
		else
			prices[def.key] = { state = "failed" }
		end
		refresh()
	end)
end

local function prompt(def: any)
	local price = prices[def.key]
	if not configured(def) or owned(def) or price == nil or price.state ~= "ok" then
		return
	end
	local opened = os.clock()
	pending[def.key] = opened
	-- Free the card even if Roblox never reports back.
	task.delay(PENDING_TIMEOUT, function()
		if pending[def.key] == opened then
			pending[def.key] = nil
			refresh()
		end
	end)
	local player = Players.LocalPlayer
	local ok = pcall(function()
		if def.kind == "GamePass" then
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		else
			MarketplaceService:PromptProductPurchase(player, def.id)
		end
	end)
	if not ok then
		pending[def.key] = nil
		ClientState.notify:Fire("Roblox couldn't open the purchase right now. Nothing was charged.")
	end
	refresh()
end

-- Short screens (phones in landscape) get smaller cards with the essentials.
local function compact(): boolean
	return panel.AbsoluteSize.Y > 0 and panel.AbsoluteSize.Y < COMPACT_HEIGHT
end

local function card(order: number, def: any)
	local small = compact()
	local frame = Theme.row(list, if small then 84 else 112, order)
	-- Deep navy fading into violet, edged in the category's colour.
	local accent = if def.kind == "GamePass"
		then VIOLET
		elseif def.category == "pack" then GOLD
		else CYAN
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(NAVY, DEEP_VIOLET)
	fill.Rotation = 0
	fill.Parent = frame
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local edge = Instance.new("UIStroke")
	edge.Color = accent
	edge.Thickness = 1.5
	edge.Parent = frame
	Theme.pulse(edge, 0.1, 0.7, 2 + (order % 3) * 0.4)
	local isOwned = owned(def)
	local icon = Theme.icon(frame, iconFor(def), if small then 48 else 64)
	local inset = 14
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		inset = 82
	end
	local right = 170
	Theme.label(frame, {
		Position = UDim2.fromOffset(inset, 6),
		Size = UDim2.new(1, -inset - right, 0, 22),
		Text = def.displayName,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = if def.category == "pack" then GOLD else Theme.COLORS.text,
	})
	local benefit = Theme.label(frame, {
		Position = UDim2.fromOffset(inset, 28),
		Size = UDim2.new(1, -inset - right, 0, 34),
		Text = def.benefit,
		Font = Enum.Font.Gotham,
		TextSize = if small then 12 else 13,
		TextColor3 = Theme.COLORS.text,
	})
	benefit.TextWrapped = true
	benefit.TextYAlignment = Enum.TextYAlignment.Top
	local status = Theme.label(frame, {
		Position = UDim2.fromOffset(inset, 64),
		Size = UDim2.new(1, -inset - right, 0, 28),
		Text = statusLine(def),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = if def.kind == "GamePass" then VIOLET else CYAN,
	})
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.Visible = not small
	local path = playPath(def)
	if path and not small then
		Theme.label(frame, {
			Position = UDim2.fromOffset(inset, 92),
			Size = UDim2.new(1, -inset - right, 0, 16),
			Text = path,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.COLORS.subtle,
		})
	end

	-- Price and button on the right.
	local price = prices[def.key]
	local priceText: string
	local buttonText: string
	local action: (() -> ())? = nil
	if isOwned then
		priceText, buttonText = "", "Owned"
	elseif not configured(def) then
		priceText, buttonText = "", "Not available yet"
	elseif price == nil or price.state == "loading" then
		priceText, buttonText = "Loading price...", "Buy"
	elseif price.state == "failed" then
		priceText, buttonText = "Price unavailable", "Unavailable"
	elseif pending[def.key] then
		priceText, buttonText = `R$ {price.robux}`, "Waiting..."
	else
		priceText, buttonText = `R$ {price.robux}`, "Buy"
		action = function()
			prompt(def)
		end
	end
	Theme.label(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, if small then 6 else 18),
		Size = UDim2.fromOffset(150, 22),
		Text = priceText,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local style: Theme.ButtonStyle = if action then "buy" else "disabled"
	local button = Theme.button(frame, buttonText, style, action)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, if small then 32 else 46)
	button.Size = UDim2.fromOffset(150, if small then 42 else 38)
	if action then
		Theme.shine(button)
	end
	if action and firstButton == nil then
		firstButton = button
	end
end

refresh = function()
	if not gui.Enabled then
		return
	end
	Theme.clear(list)
	firstButton = nil
	noteLabel.Text = if P.PURCHASES_ENABLED
		then NOTES[tab]
		else "The Store isn't open yet. " .. NOTES[tab]
	hintLabel.Visible = Input.device() == "gamepad"
	-- The controls hint takes the note's place on a gamepad.
	noteLabel.Visible = not hintLabel.Visible
	local order = 0
	for _, key in P.ORDER do
		local def = P.BY_KEY[key]
		if def.enabled and def.category == tab then
			loadPrice(def)
			order += 1
			card(order, def)
		end
	end
	if Input.device() == "gamepad" and firstButton then
		GuiService.SelectedObject = firstButton
	end
end

-- The tab next to the current one (LB / RB on a gamepad).
local function cycleTab(step: number)
	local index = 1
	for i, entry in TABS do
		if entry.id == tab then
			index = i
		end
	end
	tab = TABS[(index - 1 + step) % #TABS + 1].id
	list.CanvasPosition = Vector2.zero
	buildTabs()
	refresh()
end

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

buildTabs = function()
	Theme.clear(tabBar)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tabBar
	for order, entry in TABS do
		local selected = tab == entry.id
		local button = Theme.button(
			tabBar,
			entry.text,
			if selected then "buy" else "special",
			function()
				if tab ~= entry.id then
					tab = entry.id
					list.CanvasPosition = Vector2.zero
					buildTabs()
					refresh()
				end
			end
		)
		button.LayoutOrder = order
		button.Size = UDim2.new(0.25, -6, 1, 0)
		Theme.buttonIcon(button, entry.icon)
	end
end

-- The flashy layer: rainbow border, star field and header banner.
local function flair()
	local border = Instance.new("UIStroke")
	border.Thickness = 3
	border.Color = Color3.new(1, 1, 1)
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = panel
	local rainbow = Instance.new("UIGradient")
	rainbow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYAN),
		ColorSequenceKeypoint.new(0.33, VIOLET),
		ColorSequenceKeypoint.new(0.66, MAGENTA),
		ColorSequenceKeypoint.new(1, GOLD),
	})
	rainbow.Parent = border
	Theme.spin(rainbow, 90)

	local sky = Instance.new("Frame")
	sky.Name = "StarField"
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundTransparency = 1
	sky.ClipsDescendants = true
	sky.ZIndex = 1
	sky.Parent = panel
	for i = 1, STAR_COUNT do
		local star = Instance.new("Frame")
		local size = math.random(2, 4)
		star.Size = UDim2.fromOffset(size, size)
		star.Position = UDim2.fromScale(math.random(), math.random())
		star.BackgroundColor3 = if i % 3 == 0
			then CYAN
			elseif i % 3 == 1 then Color3.new(1, 1, 1)
			else VIOLET
		star.BorderSizePixel = 0
		star.ZIndex = 1
		star.Parent = sky
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = star
		local phase, speed = math.random() * 6, 1 + math.random() * 2
		Theme.animate(star, function(now)
			star.BackgroundTransparency = 0.25 + 0.7 * (0.5 + 0.5 * math.sin(now * speed + phase))
		end)
	end

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Position = UDim2.fromOffset(8, 6)
	banner.Size = UDim2.new(1, -110, 0, 38)
	banner.BackgroundColor3 = Color3.new(1, 1, 1)
	banner.BackgroundTransparency = 0.35
	banner.BorderSizePixel = 0
	banner.ZIndex = 2
	banner.Parent = panel
	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner
	local bannerFill = Instance.new("UIGradient")
	bannerFill.Color = ColorSequence.new(Color3.fromRGB(40, 120, 200), Color3.fromRGB(110, 50, 200))
	bannerFill.Parent = banner
	Theme.shine(banner)
end

local function build()
	gui = Theme.screen("Store", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false

	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.94, 0, 0.84, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(680, 600)
	size.Parent = panel

	flair()

	local titleX = 16
	local icon = Theme.icon(panel, "Gift", 50)
	if icon then
		icon.Position = UDim2.fromOffset(10, 0)
		icon.ZIndex = 3
		titleX = 66
		Theme.animate(icon, function(now)
			icon.Rotation = math.sin(now * 2) * 8
		end)
	end
	local title = Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 8),
		Size = UDim2.new(1, -titleX - 104, 0, 34),
		Text = "PREMIUM GALAXY STORE",
		TextSize = 26,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		ZIndex = 3,
	})
	-- Gold text with a bright band sliding across it.
	local shimmer = Instance.new("UIGradient")
	shimmer.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD),
		ColorSequenceKeypoint.new(0.45, GOLD),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, GOLD),
		ColorSequenceKeypoint.new(1, GOLD),
	})
	shimmer.Parent = title
	Theme.animate(shimmer, function(now)
		shimmer.Offset = Vector2.new(((now * 0.6) % 2) - 1, 0)
	end)
	Theme.closeButton(panel, close)

	tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(14, 50)
	tabBar.Size = UDim2.new(1, -28, 0, 36)
	tabBar.Parent = panel
	buildTabs()

	noteLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.new(1, -32, 0, 30),
		Text = "",
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})
	noteLabel.TextWrapped = true

	hintLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.new(1, -32, 0, 30),
		Text = "LB / RB: switch tabs  ·  A: buy  ·  B: close",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	})

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 126)
	list.Size = UDim2.new(1, -28, 1, -138)
	-- Re-lay the cards when the panel changes size (rotating a phone).
	local wasCompact: boolean? = nil
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local now = compact()
		if now ~= wasCompact then
			wasCompact = now
			refresh()
		end
	end)
end

local function finished(key: string?, purchased: boolean)
	if key then
		pending[key] = nil
	end
	if not purchased then
		ClientState.notify:Fire("Purchase cancelled. Nothing was charged.")
	end
	-- A successful purchase is announced by the server once it's granted.
	refresh()
end

-- The server delivered a purchase (Stardust or boost time arrived): free any
-- card still waiting on that kind of grant.
local function delivered(field: string)
	local changed = false
	for key in pending do
		local grants = P.BY_KEY[key] and P.BY_KEY[key].grants
		if
			grants
			and ((field == "stardust" and grants.stardust) or (field == "boosts" and grants.boost))
		then
			pending[key] = nil
			changed = true
		end
	end
	if changed then
		refresh()
	end
end

local function keyFor(kind: string, id: number): string?
	for key, def in P.BY_KEY do
		if def.kind == kind and def.id == id then
			return key
		end
	end
	return nil
end

function StoreController.init()
	build()
end

function StoreController.start()
	ClientState.openStore:Connect(function(which: string?)
		local wanted: Tab? = nil
		for _, entry in TABS do
			if entry.id == which then
				wanted = entry.id
			end
		end
		if gui.Enabled and wanted == nil then
			close()
			return
		end
		if wanted and wanted ~= tab then
			tab = wanted
			buildTabs()
		end
		local opening = not gui.Enabled
		gui.Enabled = true
		refresh()
		if opening then
			Theme.popIn(panel)
		end
	end)
	-- For the panel's state only: the server grants purchases.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player == Players.LocalPlayer then
			finished(keyFor("GamePass", passId), purchased)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId == Players.LocalPlayer.UserId then
			finished(keyFor("DeveloperProduct", productId), purchased)
		end
	end)
	ClientState.profileChanged:Connect(function(field)
		if field == "stardust" or field == "boosts" then
			delivered(field)
		end
		if field == "passes" or field == "ownedShips" or field == "boosts" or field == "*" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not gui.Enabled then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB or (not processed and key == Enum.KeyCode.Backspace) then
			close()
		elseif key == Enum.KeyCode.ButtonL1 then
			cycleTab(-1)
		elseif key == Enum.KeyCode.ButtonR1 then
			cycleTab(1)
		end
	end)
	Input.deviceChanged:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
end

return StoreController

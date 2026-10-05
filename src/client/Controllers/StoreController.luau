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
local pending: { [string]: boolean } = {} -- prompt open for this key
local firstButton: GuiButton? = nil

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
		return if grants.stardust >= 40000
			then "OpenChest"
			elseif grants.stardust >= 10000 then "Chest"
			else "Stardust"
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
	pending[def.key] = true
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

local function card(order: number, def: any)
	local frame = Theme.row(list, 112, order)
	local isOwned = owned(def)
	local icon = Theme.icon(frame, iconFor(def), 64)
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
		TextSize = 13,
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
	local path = playPath(def)
	if path then
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
		Position = UDim2.new(1, -12, 0, 18),
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
	button.Position = UDim2.new(1, -12, 0, 46)
	button.Size = UDim2.fromOffset(150, 38)
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

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function buildTabs()
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

	local titleX = 16
	local icon = Theme.icon(panel, "Gift", 50)
	if icon then
		icon.Position = UDim2.fromOffset(10, 0)
		icon.ZIndex = 2
		titleX = 66
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 30),
		Text = "Galaxy Store",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = CYAN,
	})
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

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 126)
	list.Size = UDim2.new(1, -28, 1, -138)
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
	ClientState.openStore:Connect(function()
		if gui.Enabled then
			close()
		else
			gui.Enabled = true
			refresh()
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
		if field == "passes" or field == "ownedShips" or field == "boosts" or field == "*" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return StoreController

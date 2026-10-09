--!strict
-- The Egg Lab panel, opened from the Egg Lab in your station's Incubator
-- Bay (TycoonAction "Eggs"). One page, top to bottom:
--
--   the pedestal egg  rarity and tier (the planet stays a mystery), its
--                     income range, Keep; rolling is the lab's own ROLL
--                     button, so the card shows the roll price instead
--   the lab           level, Upgrade (price, star tier needed)
--   odds              every rarity (base range, hatch time) and tier, now
--                     and at the next lab level
--   folded away       every planet type's odds (and your Planet Index), and
--                     how it all works
--
-- When random eggs are off for the player, a line under the egg says why.
--
-- The server (EggSystem) decides everything: the policy check, the price
-- (the shown price is sent along; if it changed, nothing happens) and the
-- egg's planet, which the client only learns when it hatches.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)
local StarController = require(script.Parent.StarController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EggMath = require(Shared:WaitForChild("Logic"):WaitForChild("EggMath"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))

local P = Config.Planets
local E = Config.Eggs
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local EGG_COLOR = Color3.fromRGB(255, 110, 200)

local EggShopController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: ScrollingFrame
-- Folded sections opened this session.
local showPlanets = false
local showHelp = false
local policy: EggMath.Policy = "unknown"
local policyMessage = ""
local busy = false

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function whole(n: number): string
	return Format.commas(n)
end

-- The next roll's price, as the server last told us (economy.eggPrice).
local function eggPrice(): number
	local profile = ClientState.profile
	local economy = if profile then (profile :: any).economy else nil
	return if economy then economy.eggPrice else E.PRICE_BASE
end

local function profileNumbers(): (number, number, number)
	local profile = ClientState.profile
	if profile == nil then
		return 0, 0, 0
	end
	local held = EggMath.held(profile.eggs or {}, profile.hatches or {})
	return profile.stardust, profile.eggsBought or 0, held
end

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local refresh: () -> ()

local function ringOf(def: PlanetsConfig.PlanetTypeDef): Color3?
	return if table.find(def.features, "ring") then Color3.fromHex(def.accent) else nil
end

local function textRow(order: number, text: string, height: number, color: Color3?, bold: boolean?)
	local row = Theme.row(list, height, order)
	row.BackgroundTransparency = 0.5
	local label = Theme.label(row, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = text,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = color or C.text,
	})
	return row, label
end

local function send(action: string, ...: any)
	if busy then
		return
	end
	busy = true
	local ok, message = Net.EggRequest:InvokeServer(action, ...)
	busy = false
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	refresh()
end

-- Whether this planet type is in the player's Planet Index.
local function discovered(typeId: string): boolean
	local profile = ClientState.profile
	return profile ~= nil and profile.discovered ~= nil and profile.discovered[typeId] == true
end

local function indexCount(): number
	local profile = ClientState.profile
	local seen: { [string]: boolean } = if profile and profile.discovered
		then profile.discovered
		else {}
	local n = 0
	for _ in seen do
		n += 1
	end
	return n
end

local function planetRow(
	order: number,
	def: PlanetsConfig.PlanetTypeDef,
	right: string,
	rightColor: Color3?
)
	local row = Theme.row(list, 46, order)
	local dot = Theme.planetIcon(row, Color3.fromHex(def.color), 30, ringOf(def))
	dot.Position = UDim2.fromOffset(12, 8)
	Theme.label(row, {
		Position = UDim2.fromOffset(52, 4),
		Size = UDim2.new(1, -170, 0, 20),
		Text = if discovered(def.id) then `{def.displayName}  ✓` else `{def.displayName}  ·  ?`,
		TextSize = 15,
		-- The rarity's colour; dimmer for types not found yet.
		TextColor3 = if discovered(def.id)
			then Color3.fromHex(P.RARITIES[def.rarity].color)
			else Color3.fromHex(P.RARITIES[def.rarity].color):Lerp(C.subtle, 0.5),
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(52, 24),
		Size = UDim2.new(1, -170, 0, 16),
		Text = `+{fmt(def.income)}% of its star at level 1  ·  {def.description}`,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = C.subtle,
	})
	Theme.label(row, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, 110, 1, 0),
		Text = right,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = rightColor or C.gold,
	})
	return row
end

local function labLevel(): number
	local profile = ClientState.profile
	local lab = if profile then profile.eggLab else nil
	return if lab then lab.level else 1
end

local function current(): { rarity: string, tier: number }?
	local profile = ClientState.profile
	local lab = if profile then profile.eggLab else nil
	return if lab then lab.current else nil
end

local function sectionTitle(order: number, text: string)
	local row = Theme.row(list, 30, order)
	row.BackgroundTransparency = 1
	Theme.label(row, {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 1, -4),
		Text = text,
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
end

-- A small right-aligned label in a row.
local function rightLabel(row: Frame, text: string, width: number, color: Color3?)
	Theme.label(row, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, width, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color or C.gold,
	})
end

-- "12.8%" or "12.8% → 14.1%" when the next lab level would change it.
local function chanceText(now: number, after: number?): string
	local text = EggMath.percentText(now)
	if after and EggMath.percentText(after) ~= text then
		text ..= ` → {EggMath.percentText(after)}`
	end
	return text
end

-- A folding section header: tap to open or close.
local function foldRow(order: number, text: string, open: boolean, toggle: () -> ())
	local row = Theme.row(list, 36, order)
	local button = Theme.button(row, `{if open then "▾" else "▸"}  {text}`, "primary", toggle)
	button.Size = UDim2.fromScale(1, 1)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.TextSize = 14
	return row
end

-- The pedestal egg and Keep.
local function eggCard(
	order: number,
	price: number,
	held: number,
	allowed: boolean,
	stardust: number
)
	local egg = current()
	local card = Theme.row(list, 92, order)
	local rarity = if egg then P.RARITIES[egg.rarity] else nil
	local tierDef = if egg then P.TIERS[egg.tier] else nil
	local tint = if rarity then Color3.fromHex(rarity.color) else EGG_COLOR
	local icon = Theme.planetIcon(
		card,
		tint,
		56,
		if tierDef and egg and egg.tier > 1 then Color3.fromHex(tierDef.color) else nil
	)
	icon.Position = UDim2.fromOffset(12, 18)
	Theme.label(card, {
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -210, 0, 26),
		Text = if rarity and tierDef
			then `{tierDef.name} {rarity.displayName} egg`
			else "No egg on the pedestal",
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextColor3 = tint,
	})
	local low, high = 0, 0
	if egg then
		low, high = EggMath.rarityRange(egg.rarity)
	end
	local rollLine = if not allowed
		then "Rolling is off for you (see below)."
		elseif stardust < price then `A roll costs {whole(price)}: you need {whole(
			price - stardust
		)} more.`
		else `Press ROLL on the lab: {whole(price)} {CURRENCY} a roll.`
	Theme.label(card, {
		Position = UDim2.fromOffset(80, 36),
		Size = UDim2.new(1, -210, 0, 50),
		Text = if egg and tierDef
			then `+{fmt(low * tierDef.multiplier)}-{fmt(high * tierDef.multiplier)}% of its star's output (x{tierDef.multiplier}). Keep it, or roll again to replace it. {rollLine}`
			else rollLine,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	local room = held < E.MAX_UNHATCHED
	local canKeep = egg ~= nil and room
	local keepButton = Theme.button(
		card,
		if egg and not room then "No room" else "Keep",
		if canKeep then "primary" else "disabled",
		if canKeep
			then function()
				send("keep")
			end
			else nil
	)
	keepButton.AnchorPoint = Vector2.new(1, 0.5)
	keepButton.Position = UDim2.new(1, -10, 0.5, 0)
	keepButton.Size = UDim2.fromOffset(110, 44)
	return keepButton, canKeep
end

-- The lab's level and Upgrade.
local function labCard(order: number, stardust: number): (TextButton, boolean)
	local level = labLevel()
	local cost = EggMath.upgradeCost(level)
	local needTier = EggMath.upgradeTier(level)
	local tierOk = needTier == nil or StarController.bestTier() >= needTier
	local card = Theme.row(list, 64, order)
	Theme.label(card, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -190, 0, 24),
		Text = `Egg Lab level {level}/{#E.LAB_LEVELS}`,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = EGG_COLOR,
	})
	Theme.label(card, {
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -190, 0, 26),
		Text = if cost
			then `Better odds for rarer planets and higher tiers.{if needTier and not tierOk
				then ` Needs a tier {needTier} star.`
				else ""}`
			else "Best level: the odds can't get better.",
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	local canBuy = cost ~= nil and stardust >= cost and tierOk
	local button = Theme.button(
		card,
		if cost == nil
			then "Max level"
			elseif not tierOk then `Star tier {needTier}`
			elseif canBuy then `Upgrade · {fmt(cost)}`
			else `Need {fmt(cost)}`,
		if canBuy then "buy" else "disabled",
		if canBuy
			then function()
				send("upgrade", cost)
			end
			else nil
	)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(160, 44)
	button.TextSize = 13
	return button, canBuy
end

-- Rarities and tiers: chance now (→ at the next lab level).
local function oddsRows(order: number, level: number, compare: number?): number
	sectionTitle(
		order,
		if compare then `Odds now → at lab level {compare}` else `Odds at lab level {level}`
	)
	order += 1
	for _, rarityId in P.RARITY_ORDER do
		local rarity = P.RARITIES[rarityId]
		local low, high = EggMath.rarityRange(rarityId)
		local row = Theme.row(list, 32, order)
		Theme.label(row, {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -190, 1, 0),
			Text = `{rarity.displayName}  ·  {fmt(low)}-{fmt(high)}%  ·  hatches in {EggMath.durationText(
				rarity.hatchSeconds
			)}`,
			TextSize = 14,
			TextColor3 = Color3.fromHex(rarity.color),
		})
		rightLabel(
			row,
			chanceText(
				EggMath.rarityPercent(rarityId, level),
				if compare then EggMath.rarityPercent(rarityId, compare) else nil
			),
			170
		)
		order += 1
	end
	for tier, def in P.TIERS do
		local row = Theme.row(list, 32, order)
		local swatch = Theme.planetIcon(row, Color3.fromHex(def.color), 20, nil)
		swatch.Position = UDim2.fromOffset(12, 6)
		Theme.label(row, {
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -220, 1, 0),
			Text = `Tier {tier} {def.name}  ·  x{def.multiplier}`,
			TextSize = 14,
			TextColor3 = Color3.fromHex(def.color),
		})
		rightLabel(
			row,
			chanceText(
				EggMath.tierPercent(tier, level),
				if compare then EggMath.tierPercent(tier, compare) else nil
			),
			170
		)
		order += 1
	end
	return order
end

local HELP = {
	"Each roll costs about a minute of your best production (at least "
		.. tostring(E.PRICE_BASE)
		.. " "
		.. CURRENCY
		.. "). The server picks the planet and tier; you see the rarity and tier, the planet stays a mystery until it hatches. Rolling again replaces the egg on the pedestal.",
	"Rarity sets how big a share of its star's output a planet adds; the tier multiplies it. Planets earn more on stronger stars.",
	`Kept eggs hatch in your {E.HATCH_SLOTS} incubator chambers, even while you're offline. You can hold {E.MAX_UNHATCHED} unhatched eggs, and eggs count towards your {P.MAX_PLANETS} planet storage.`,
	"Upgrading the lab changes the odds of future rolls only. Where Roblox restricts paid random items, or until we can confirm they're allowed, rolling is off. Nothing here is sold for Robux.",
}

local function showLab()
	local stardust, _, held = profileNumbers()
	local price = eggPrice()
	local allowed = EggMath.canBuyRandom(policy)
	local level = labLevel()
	local order = 1

	local keepButton, canKeep = eggCard(order, price, held, allowed, stardust)
	order += 1
	if not allowed then
		textRow(
			order,
			if policyMessage ~= ""
				then policyMessage
				else "Checking whether planet eggs are available for you...",
			44,
			Color3.fromRGB(255, 180, 120),
			true
		)
		order += 1
	end
	local upgradeButton, canBuy = labCard(order, stardust)
	order += 1
	if Input.device() == "gamepad" then
		GuiService.SelectedObject = if canKeep
			then keepButton
			elseif canBuy then upgradeButton
			else keepButton
	end

	local compare = if EggMath.upgradeCost(level) then level + 1 else nil
	order = oddsRows(order, level, compare)

	foldRow(
		order,
		`Every planet's odds  ·  Planet Index {indexCount()}/{#P.ORDER}`,
		showPlanets,
		function()
			showPlanets = not showPlanets
			refresh()
		end
	)
	order += 1
	if showPlanets then
		for _, rarityId in P.RARITY_ORDER do
			for _, id in P.BY_RARITY[rarityId] do
				planetRow(order, P.BY_ID[id], EggMath.percentText(EggMath.typePercent(id, level)))
				order += 1
			end
		end
	end

	foldRow(order, "How the Egg Lab works", showHelp, function()
		showHelp = not showHelp
		refresh()
	end)
	order += 1
	if showHelp then
		for _, text in HELP do
			local row, label = textRow(order, text, 40)
			-- Grow each paragraph to fit its text once it has a width.
			task.defer(function()
				if label.Parent then
					row.Size = UDim2.new(1, 0, 0, label.TextBounds.Y + 16)
				end
			end)
			order += 1
		end
	end
end

refresh = function()
	if not gui.Enabled then
		return
	end
	local stardust, _, held = profileNumbers()
	header.Text =
		`{whole(stardust)} {CURRENCY}  ·  eggs waiting {held}/{E.MAX_UNHATCHED}  ·  next roll {whole(
			eggPrice()
		)}`
	Theme.clear(list)
	showLab()
end

local function fetchPolicy()
	task.spawn(function()
		local ok, okFlag, message, answer = pcall(function()
			return Net.EggRequest:InvokeServer("status")
		end)
		if
			ok
			and okFlag
			and (answer == "allowed" or answer == "restricted" or answer == "unknown")
		then
			policy = answer
			policyMessage = if type(message) == "string" then message else ""
			refresh()
		end
	end)
end

local function open()
	gui.Enabled = true
	local ok, problem = pcall(refresh :: any)
	if not ok then
		warn(`[EggShop] Could not show the Egg Lab: {problem}`)
	end
	fetchPolicy()
	Theme.popIn(panel)
end

function EggShopController.init()
	gui = Theme.screen("EggLab", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.84, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(720, 720)
	size.Parent = panel
	local titleX = 16
	local icon = Theme.icon(panel, "GalaxyOrb", 44)
	if icon then
		icon.Position = UDim2.fromOffset(12, 2)
		icon.ZIndex = 2
		titleX = 60
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 28),
		Text = "Planet Egg Lab",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = EGG_COLOR,
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
end

function EggShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("TycoonAction") == "Eggs" then
			open()
		end
	end)
	ClientState.profileChanged:Connect(function(field)
		if
			field == "stardust"
			or field == "eggs"
			or field == "eggsBought"
			or field == "economy"
			or field == "eggLab"
			or field == "hatches"
			or field == "discovered"
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

return EggShopController

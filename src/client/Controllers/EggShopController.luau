--!strict
-- The Planet Egg Lab panel, opened from the ISS Egg Lab console (TycoonAction
-- "Eggs"). Everything a player needs before buying is on screen:
--
--   Mystery egg     the price, your balance, the Buy button, and every planet
--                   type's exact chance grouped by rarity with each rarity's
--                   hatch time; that hatching starts at your hangar; and,
--                   when random eggs are off for you, why.
--   Details         how the roll, prices, hatching and restrictions work.
--
-- The server (EggSystem) decides everything: the policy check, the price
-- (the shown price is sent along; if it changed, nothing is bought) and the
-- mystery egg's planet, which the client only learns when it hatches.

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
local EggMath = require(Shared:WaitForChild("Logic"):WaitForChild("EggMath"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))

local P = Config.Planets
local E = Config.Eggs
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local EGG_COLOR = Color3.fromRGB(255, 110, 200)

type Tab = "mystery" | "details"

local EggShopController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local tabs: Frame
local list: ScrollingFrame
local tab: Tab = "mystery"
local policy: EggMath.Policy = "unknown"
local policyMessage = ""
local busy = false

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function whole(n: number): string
	return Format.commas(n)
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

local function buy(action: string, ...: any)
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
		Text = if discovered(def.id)
			then `{def.displayName}  ✓`
			else `{def.displayName}  ·  not in your Planet Index yet`,
		TextSize = 15,
		TextColor3 = if discovered(def.id) then C.text else C.subtle,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(52, 24),
		Size = UDim2.new(1, -170, 0, 16),
		Text = `+{fmt(def.income)} {CURRENCY}/s at level 1  ·  {def.description}`,
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

local function rarityHeader(order: number, rarityId: string)
	local rarity = P.RARITIES[rarityId]
	local row = Theme.row(list, 30, order)
	row.BackgroundTransparency = 1
	Theme.label(row, {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Text = `{string.upper(rarity.displayName)}  ·  {EggMath.percentText(
			rarity.weight / P.WEIGHT_TOTAL * 100
		)} in total  ·  hatches in {EggMath.durationText(rarity.hatchSeconds)}`,
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromHex(rarity.color),
	})
end

local function showMystery()
	local stardust, bought, held = profileNumbers()
	local price = EggMath.price(bought)
	local allowed = EggMath.canBuyRandom(policy)

	local card = Theme.row(list, 84, 1)
	local icon = Theme.planetIcon(card, EGG_COLOR, 52, Color3.fromRGB(255, 230, 140))
	icon.Position = UDim2.fromOffset(12, 16)
	Theme.label(card, {
		Position = UDim2.fromOffset(78, 8),
		Size = UDim2.new(1, -90 - #E.MULTI_BUY * 112, 0, 24),
		Text = "Mystery Planet Egg",
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextColor3 = EGG_COLOR,
	})
	Theme.label(card, {
		Position = UDim2.fromOffset(78, 34),
		Size = UDim2.new(1, -90 - #E.MULTI_BUY * 112, 0, 40),
		Text = `{whole(price)} {CURRENCY}  ·  each, one random planet, duplicates possible  ·  you have {whole(
			stardust
		)}`,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	-- Buy 1, 5 or 10 at once (Config.Eggs.MULTI_BUY), each egg at its own price.
	local first: TextButton? = nil
	for index = #E.MULTI_BUY, 1, -1 do
		local count = E.MULTI_BUY[index]
		local _, total = EggMath.batch(bought, count)
		local room = held + count <= E.MAX_UNHATCHED
		local label = if not allowed
			then "Unavailable"
			elseif not room then "No room"
			elseif stardust < total then `x{count} · need {fmt(total)}`
			else `x{count} · {fmt(total)}`
		local ok = allowed and room and stardust >= total
		local button = Theme.button(
			card,
			label,
			if ok then "buy" else "disabled",
			if ok
				then function()
					buy("buyMystery", total, count)
				end
				else nil
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10 - (#E.MULTI_BUY - index) * 112, 0.5, 0)
		button.Size = UDim2.fromOffset(106, 38)
		button.TextSize = 13
		if count == 1 then
			first = button
		end
	end
	if Input.device() == "gamepad" and allowed and first then
		GuiService.SelectedObject = first
	end

	local order = 2
	if not allowed then
		textRow(
			order,
			if policyMessage ~= ""
				then policyMessage
				else "Checking whether mystery eggs are available for you...",
			48,
			Color3.fromRGB(255, 180, 120),
			true
		)
		order += 1
	end
	textRow(
		order,
		`Hatching starts when you put the egg in one of your hangar's {E.HATCH_SLOTS} incubator chambers, not when you buy it. Eggs waiting: {held}/{E.MAX_UNHATCHED}.`,
		56
	)
	order += 1
	local odds = Theme.row(list, 30, order)
	odds.BackgroundTransparency = 1
	Theme.label(odds, {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 1, -4),
		Text = `Odds for every planet in a mystery egg  ·  Planet Index {indexCount()}/{#P.ORDER}`,
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
	order += 1
	for _, rarityId in P.RARITY_ORDER do
		rarityHeader(order, rarityId)
		order += 1
		for _, id in P.BY_RARITY[rarityId] do
			local def = P.BY_ID[id]
			planetRow(order, def, EggMath.percentText(EggMath.percent(id)))
			order += 1
		end
	end
end

local function showDetails()
	local _, bought = profileNumbers()
	local hatchTimes: { string } = {}
	local shares: { string } = {}
	for _, rarityId in P.RARITY_ORDER do
		local rarity = P.RARITIES[rarityId]
		table.insert(hatchTimes, `{rarity.displayName} {EggMath.durationText(rarity.hatchSeconds)}`)
		table.insert(
			shares,
			`{rarity.displayName} {EggMath.percentText(rarity.weight / P.WEIGHT_TOTAL * 100)} ({#P.BY_RARITY[rarityId]} types, {EggMath.percentText(
				rarity.weight / #P.BY_RARITY[rarityId] / P.WEIGHT_TOTAL * 100
			)} each)`
		)
	end
	local paragraphs = {
		{
			"How a mystery egg works",
			"The server picks the planet the moment you buy the egg, using the odds below, and saves it with the egg. It never changes, and nothing you do afterwards affects it. You see it when the egg hatches.",
		},
		{
			"Odds",
			`Every planet type has a fixed weight out of {whole(P.WEIGHT_TOTAL)}; its chance is its weight divided by that total. By rarity: {table.concat(
				shares,
				"; "
			)}. Duplicates are possible.`,
		},
		{
			"Price",
			`Every mystery egg costs {whole(EggMath.price(bought))} {CURRENCY}. Only {CURRENCY} is used.`,
		},
		{
			"Hatching",
			`Put eggs in your hangar's incubator ({E.HATCH_SLOTS} chambers) to start them. Hatch times: {table.concat(
				hatchTimes,
				", "
			)}. Eggs keep hatching while you're offline. You can hold {E.MAX_UNHATCHED} unhatched eggs.`,
		},
		{
			"Restrictions",
			"Where Roblox restricts paid random items, or while we can't confirm that they're allowed for you, eggs are switched off. Planets can only come from eggs: they can't be bought directly. There is no paid luck, no rerolls, no paid hatch speed-ups and no trading.",
		},
	}
	for index, paragraph in paragraphs do
		textRow(index * 2 - 1, paragraph[1], 28, C.gold, true).BackgroundTransparency = 1
		local row, label = textRow(index * 2, paragraph[2], 40)
		-- Grow each paragraph to fit its text once it has a width.
		task.defer(function()
			if label.Parent then
				row.Size = UDim2.new(1, 0, 0, label.TextBounds.Y + 16)
			end
		end)
	end
end

local tabButtons: { [Tab]: TextButton } = {}

refresh = function()
	if not gui.Enabled then
		return
	end
	local stardust, _, held = profileNumbers()
	header.Text = `You have {whole(stardust)} {CURRENCY}  ·  eggs waiting {held}/{E.MAX_UNHATCHED}`
	for id, button in tabButtons do
		button.BackgroundTransparency = if id == tab then 0 else 0.45
	end
	Theme.clear(list)
	if tab == "mystery" then
		showMystery()
	else
		showDetails()
	end
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

	tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(13, 64)
	tabs.Size = UDim2.new(1, -26, 0, 36)
	tabs.Parent = panel
	local tabDefs: { { id: Tab, text: string, style: Theme.ButtonStyle } } = {
		{ id = "mystery", text = "Mystery egg", style = "buy" },
		{ id = "details", text = "Details", style = "special" },
	}
	for index, def in tabDefs do
		local button = Theme.button(tabs, def.text, def.style, function()
			tab = def.id
			refresh()
		end)
		button.Size = UDim2.new(1 / #tabDefs, -6, 1, 0)
		button.Position = UDim2.new((index - 1) / #tabDefs, 3, 0, 0)
		tabButtons[def.id] = button
	end

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 110)
	list.Size = UDim2.new(1, -28, 1, -122)
end

function EggShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("TycoonAction") == "Eggs" then
			tab = "mystery"
			open()
		end
	end)
	ClientState.profileChanged:Connect(function(field)
		if
			field == "stardust"
			or field == "eggs"
			or field == "eggsBought"
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

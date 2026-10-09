--!strict
-- The Planets panel (HUD's Planets button, P key): every planet you own and
-- the tools to manage them. Only planets in orbit produce Stardust.
--
--   List       filter by rarity and by where (in orbit / inventory), sort by
--              rarity, income or level. Each planet: Lock (protects it from
--              any selling), Level, Equip (choose a star; first free orbit)
--              or Unequip, and Sell (inventory, unlocked; Rare and rarer ask
--              twice). Equip best fills every orbit with your top earners.
--   Sell       bulk selling per rarity: every unlocked inventory planet, or
--              only duplicates (the best of each type is kept, in orbit or
--              not). Each asks twice before selling.
--   Auto-sell  sell newly hatched planets of chosen rarities on the spot
--              (Config.Planets.AUTO_SELL_RARITIES), optionally keeping any
--              type you've never had.
--
-- The server (StarSystem, DataSystem) checks every action; this panel only
-- asks.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local StarController = require(script.Parent.StarController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))
local PlanetInventory = require(Shared:WaitForChild("Logic"):WaitForChild("PlanetInventory"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))
local Types = require(Shared:WaitForChild("Types"))

local S = Config.Stars
local P = Config.Planets
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
-- Rarity index from which selling asks for a second click.
local CONFIRM_FROM = 2 -- Rare
local CONFIRM_SECONDS = 3

type View = "list" | "stars" | "bulk" | "autosell"
type Where = "all" | "orbit" | "inventory"
type Sort = "rarity" | "income" | "level"
type Entry = { id: string, planet: Types.PlanetRecord, def: PlanetsConfig.PlanetTypeDef }

local PlanetsController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local toolbar: Frame
local filters: Frame
local list: ScrollingFrame
local view: View = "list"
local choosingFor: string? = nil -- the planet whose star is being chosen
local rarityFilter: string? = nil
local where: Where = "all"
local sortBy: Sort = "rarity"
-- A sell button pressed once: its key and when, so a second press confirms.
local armed: { key: string, at: number }? = nil

local WHERE_TEXT: { [Where]: string } =
	{ all = "All places", orbit = "In orbit", inventory = "Inventory" }
local WHERE_NEXT: { [Where]: Where } = { all = "orbit", orbit = "inventory", inventory = "all" }
local SORT_TEXT: { [Sort]: string } =
	{ rarity = "Sort: rarity", income = "Sort: income", level = "Sort: level" }
local SORT_NEXT: { [Sort]: Sort } = { rarity = "income", income = "level", level = "rarity" }

local RARITY_RANK: { [string]: number } = {}
for index, rarity in P.RARITY_ORDER do
	RARITY_RANK[rarity] = index
end

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function planets(): { [string]: Types.PlanetRecord }
	local profile = ClientState.profile
	return if profile and profile.planets then profile.planets else {}
end

local function settings(): Types.Settings?
	local profile = ClientState.profile
	return if profile then profile.settings else nil
end

local function close()
	gui.Enabled = false
	view, choosingFor, armed = "list", nil, nil
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local refresh: () -> ()

local function request(...: any)
	local ok, message = Net.StarRequest:InvokeServer(...)
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	armed = nil
	refresh()
end

-- A button that needs a second press within CONFIRM_SECONDS when `confirm`.
local function confirmed(key: string, confirm: boolean, action: () -> ()): () -> ()
	return function()
		local now = os.clock()
		if not confirm or (armed and armed.key == key and now - armed.at <= CONFIRM_SECONDS) then
			armed = nil
			action()
		else
			armed = { key = key, at = now }
			refresh()
			task.delay(CONFIRM_SECONDS + 0.1, function()
				if armed and armed.key == key and os.clock() - armed.at > CONFIRM_SECONDS then
					armed = nil
					refresh()
				end
			end)
		end
	end
end

local function isArmed(key: string): boolean
	return armed ~= nil and armed.key == key and os.clock() - armed.at <= CONFIRM_SECONDS
end

local function ringOf(def: PlanetsConfig.PlanetTypeDef): Color3?
	return if table.find(def.features, "ring") then Color3.fromHex(def.accent) else nil
end

local function starName(model: Model?): string
	local typeId = if model then model:GetAttribute("TypeId") else nil
	local def = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	return if def then def.displayName else "a star"
end

local function text(row: Frame, titleText: string, detail: string, right: number, color: Color3?)
	Theme.label(row, {
		Position = UDim2.fromOffset(52, 6),
		Size = UDim2.new(1, -52 - right, 0, 20),
		Text = titleText,
		TextColor3 = color or C.text,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(52, 28),
		Size = UDim2.new(1, -52 - right, 0, 18),
		Text = detail,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
end

-- Places a button `x` px from the row's right edge, `width` wide.
local function at(button: TextButton, x: number, width: number): TextButton
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -x, 0.5, 0)
	button.Size = UDim2.fromOffset(width, 34)
	return button
end

local function backRow(label: string)
	local back = Theme.row(list, 36, 0)
	back.BackgroundTransparency = 1
	Theme.button(back, label, "primary", function()
		view, choosingFor, armed = "list", nil, nil
		refresh()
	end).Size =
		UDim2.new(0, 170, 1, -4)
end

local function entries(): { Entry }
	local result: { Entry } = {}
	for id, planet in planets() do
		local def = P.BY_ID[planet.typeId]
		if def then
			table.insert(result, { id = id, planet = planet, def = def })
		end
	end
	return result
end

-- Views --------------------------------------------------------------------

-- A planet's share of its host star's own output, as a percentage.
local function sharePercent(planet: Types.PlanetRecord): number
	return StarMath.planetFactor(planet.typeId, planet.level, planet.tier) * 100
end

-- What a planet makes now: its share of the star it orbits (0 in inventory).
local function earning(planet: Types.PlanetRecord, records: { [string]: Types.StarRecord }): number
	local host = if planet.star then records[planet.star] else nil
	if host == nil then
		return 0
	end
	return StarMath.planetIncome(
		planet.typeId,
		planet.level,
		planet.tier,
		StarMath.starIncome(host.typeId, host.level)
	)
end

-- The next egg roll's price as the server last told us (planet level
-- prices are a share of it).
local function eggPrice(): number
	local profile = ClientState.profile
	local economy = if profile then (profile :: any).economy else nil
	return if economy then economy.eggPrice else Config.Eggs.PRICE_BASE
end

-- Choosing a star for one planet.
local function showStars(planetId: string)
	local planet = planets()[planetId]
	local def = if planet then P.BY_ID[planet.typeId] else nil
	if planet == nil or def == nil then
		view, choosingFor = "list", nil
		refresh()
		return
	end
	header.Text =
		`Choose a star for your {def.displayName} (+{Format.rate(sharePercent(planet))}% of the star's output)`
	backRow("Back to planets")
	local stars = StarController.myStars()
	local ids: { string } = {}
	for id in stars do
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then
		local row = Theme.row(list, 52, 1)
		text(row, "No stars yet", "Buy a star at the Star Shop first (B).", 14)
		return
	end
	for order, starId in ids do
		local model = stars[starId]
		local typeId = model:GetAttribute("TypeId")
		local open = StarMath.slots(if type(typeId) == "string" then typeId else S.DEFAULT_TYPE)
		local used = 0
		for _ in PlanetInventory.idsOn(planets(), starId) do
			used += 1
		end
		local here = planet.star == starId
		local row = Theme.row(list, 52, order)
		local starDef = if type(typeId) == "string" then S.BY_ID[typeId] else nil
		local icon = Theme.starIcon(
			row,
			if starDef then Color3.fromHex(starDef.color) else C.gold,
			if starDef then Color3.fromHex(starDef.light) else C.gold,
			36,
			if typeId == "BlackHole" or typeId == "VoidFlame" then "blackHole" else "star"
		)
		icon.Position = UDim2.fromOffset(8, 8)
		local income = model:GetAttribute("Income")
		local now = if type(income) == "number" then income else 0
		local level = model:GetAttribute("Level")
		local gain = if type(typeId) == "string"
			then StarMath.planetIncome(
				planet.typeId,
				planet.level,
				planet.tier,
				StarMath.starIncome(typeId, if type(level) == "number" then level else 1)
			)
			else 0
		text(
			row,
			`{starName(model)}  ·  orbits {used}/{open}`,
			if here
				then "This planet already orbits here"
				else `This star {fmt(now)} -> {fmt(now + gain)} {CURRENCY}/s`,
			170
		)
		local full = used >= open
		at(
			Theme.button(
				row,
				if here then "Here" elseif full then "No free orbit" else "Equip here",
				if here or full then "disabled" else "buy",
				if here or full
					then nil
					else function()
						view, choosingFor = "list", nil
						request("equipPlanet", planetId, starId)
					end
			),
			8,
			160
		)
	end
end

-- Bulk selling, per rarity.
local function showBulk()
	header.Text = "Sell planets in bulk: only unlocked planets in your inventory are ever sold"
	backRow("Back to planets")
	local all = entries()
	-- The best of each type (by level, in orbit first) is what "duplicates" keeps.
	local keep: { [string]: string } = {}
	for _, entry in all do
		local best = keep[entry.def.id]
		local current = if best then planets()[best] else nil
		if
			current == nil
			or entry.planet.level > current.level
			or (
				entry.planet.level == current.level
				and entry.planet.star ~= nil
				and current.star == nil
			)
		then
			keep[entry.def.id] = entry.id
		end
	end
	for order, rarityId in P.RARITY_ORDER do
		local rarity = P.RARITIES[rarityId]
		local sellable: { string } = {}
		local dupes: { string } = {}
		local sellTotal, dupeTotal = 0, 0
		for _, entry in all do
			if entry.def.rarity == rarityId and PlanetInventory.canSell(planets(), entry.id) then
				local value = PlanetInventory.sellValue(entry.planet)
				table.insert(sellable, entry.id)
				sellTotal += value
				if keep[entry.def.id] ~= entry.id then
					table.insert(dupes, entry.id)
					dupeTotal += value
				end
			end
		end
		local row = Theme.row(list, 52, order)
		Theme.swatch(row, Color3.fromHex(rarity.color), 22, true).Position =
			UDim2.fromOffset(14, 15)
		text(
			row,
			rarity.displayName,
			`{#sellable} sellable  ·  {#dupes} duplicates  ·  sells for {math.floor(
				(P.SELL_FRACTION[rarityId] or 0) * 100 + 0.5
			)}% of its roll price`,
			300,
			Color3.fromHex(rarity.color)
		)
		local dupeKey, allKey = `dupes{rarityId}`, `all{rarityId}`
		at(
			Theme.button(
				row,
				if #dupes == 0
					then "No duplicates"
					elseif isArmed(dupeKey) then `Sure? +{fmt(dupeTotal)}`
					else `Duplicates · +{fmt(dupeTotal)}`,
				if #dupes == 0 then "disabled" elseif isArmed(dupeKey) then "special" else "primary",
				if #dupes == 0
					then nil
					else confirmed(dupeKey, true, function()
						request("sellPlanets", dupes)
					end)
			),
			150,
			140
		)
		at(
			Theme.button(
				row,
				if #sellable == 0
					then "Nothing to sell"
					elseif isArmed(allKey) then `Sure? +{fmt(sellTotal)}`
					else `All · +{fmt(sellTotal)}`,
				if #sellable == 0 then "disabled" elseif isArmed(allKey) then "special" else "buy",
				if #sellable == 0
					then nil
					else confirmed(allKey, true, function()
						request("sellPlanets", sellable)
					end)
			),
			8,
			136
		)
	end
end

-- Auto-sell choices.
local function showAutoSell()
	local current = settings()
	header.Text = "Auto-sell: newly hatched planets of these rarities are sold on the spot"
	backRow("Back to planets")
	if current == nil then
		return
	end
	local order = 1
	for _, rarityId in P.AUTO_SELL_RARITIES do
		local rarity = P.RARITIES[rarityId]
		local on = current.autoSell[rarityId] == true
		local row = Theme.row(list, 52, order)
		Theme.swatch(row, Color3.fromHex(rarity.color), 22, true).Position =
			UDim2.fromOffset(14, 15)
		text(
			row,
			rarity.displayName,
			`Sold as they hatch, for {math.floor((P.SELL_FRACTION[rarityId] or 0) * 100 + 0.5)}% of the roll price`,
			170,
			Color3.fromHex(rarity.color)
		)
		at(
			Theme.button(
				row,
				if on then "Auto-sell: ON" else "Auto-sell: off",
				if on then "special" else "primary",
				function()
					Net.SettingChanged:FireServer("autoSell", rarityId, not on)
					if on then
						current.autoSell[rarityId] = nil
					else
						current.autoSell[rarityId] = true
					end
					refresh()
				end
			),
			8,
			160
		)
		order += 1
	end
	local keepRow = Theme.row(list, 52, order)
	text(
		keepRow,
		"Keep new types",
		"Never auto-sell a planet type you've never had (it joins your Planet Index)",
		170
	)
	at(
		Theme.button(
			keepRow,
			if current.keepNewTypes then "Keep: ON" else "Keep: off",
			if current.keepNewTypes then "buy" else "primary",
			function()
				local on = not current.keepNewTypes
				Net.SettingChanged:FireServer("keepNewTypes", on)
				current.keepNewTypes = on
				refresh()
			end
		),
		8,
		160
	)
	local note = Theme.row(list, 52, order + 1)
	note.BackgroundTransparency = 0.5
	Theme.label(note, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = `Legendary and Interstellar planets are never auto-sold. If you own {P.MAX_PLANETS} planets, new ones are sold as they hatch, so make room by selling.`,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
end

local function sorted(list_: { Entry }): { Entry }
	table.sort(list_, function(a, b)
		local ia = sharePercent(a.planet)
		local ib = sharePercent(b.planet)
		local ra, rb = RARITY_RANK[a.def.rarity], RARITY_RANK[b.def.rarity]
		if sortBy == "rarity" and ra ~= rb then
			return ra > rb
		elseif sortBy == "level" and a.planet.level ~= b.planet.level then
			return a.planet.level > b.planet.level
		end
		if ia ~= ib then
			return ia > ib
		end
		return a.id < b.id
	end)
	return list_
end

local function showList()
	local all = entries()
	local inOrbit, production = 0, 0
	local records = StarController.myRecords()
	for _, entry in all do
		if entry.planet.star then
			inOrbit += 1
			production += earning(entry.planet, records)
		end
	end
	local profile = ClientState.profile
	local index = 0
	local discovered: { [string]: boolean } = if profile and profile.discovered
		then profile.discovered
		else {}
	for _ in discovered do
		index += 1
	end
	header.Text =
		`{#all}/{P.MAX_PLANETS} owned  ·  {inOrbit} in orbit (+{fmt(production)}/s)  ·  Planet Index {index}/{#P.ORDER}`
	local shown: { Entry } = {}
	for _, entry in all do
		local placeOk = where == "all"
			or (where == "orbit" and entry.planet.star ~= nil)
			or (where == "inventory" and entry.planet.star == nil)
		if placeOk and (rarityFilter == nil or entry.def.rarity == rarityFilter) then
			table.insert(shown, entry)
		end
	end
	if #all == 0 then
		local row = Theme.row(list, 52, 1)
		text(
			row,
			"No planets yet",
			"Roll planet eggs at your Planet Egg Lab (beside the Collector), hatch them, then put them in orbit.",
			14
		)
		return
	end
	if #shown == 0 then
		local row = Theme.row(list, 52, 1)
		text(row, "Nothing here", "No planets match these filters.", 14)
		return
	end
	local stars = StarController.myStars()
	local stardust = if profile then profile.stardust else 0
	local first: TextButton? = nil
	for order, entry in sorted(shown) do
		local planet, def = entry.planet, entry.def
		local rarity = P.RARITIES[def.rarity]
		local row = Theme.row(list, 52, order)
		local dot = Theme.planetIcon(row, Color3.fromHex(def.color), 32, ringOf(def))
		dot.Position = UDim2.fromOffset(10, 10)
		local placeText = if planet.star
			then `orbit {planet.slot or "?"} of your {starName(stars[planet.star])}`
			else "inventory: not producing"
		text(
			row,
			`{if planet.locked then "[locked] " else ""}{P.TIERS[planet.tier].name} {def.displayName}  ·  Lv {planet.level}  ·  {rarity.displayName} T{planet.tier}`,
			if planet.star
				then `+{fmt(earning(planet, records))}/s ({Format.rate(sharePercent(planet))}% of its star)  ·  {placeText}`
				else `{Format.rate(sharePercent(planet))}% of a star's output  ·  {placeText}`,
			400,
			Color3.fromHex(rarity.color):Lerp(Color3.new(1, 1, 1), 0.35)
		)
		-- Right to left: Sell, Equip/Unequip, Level, Lock.
		local value = PlanetInventory.sellValue(planet)
		local sellKey = `sell{entry.id}`
		local canSell = PlanetInventory.canSell(planets(), entry.id)
		at(
			Theme.button(
				row,
				if not canSell
					then (if planet.locked then "Locked" else "In orbit")
					elseif isArmed(sellKey) then `Sure? +{fmt(value)}`
					else `Sell +{fmt(value)}`,
				if not canSell then "disabled" elseif isArmed(sellKey) then "special" else "primary",
				if not canSell
					then nil
					else confirmed(sellKey, rarity.index >= CONFIRM_FROM, function()
						request("sellPlanets", { entry.id })
					end)
			),
			8,
			104
		)
		local equipButton = at(
			if planet.star
				then Theme.button(row, "Unequip", "primary", function()
					request("unequipPlanet", entry.id)
				end)
				else Theme.button(row, "Equip", "special", function()
					view, choosingFor = "stars", entry.id
					refresh()
				end),
			116,
			92
		)
		local cost = StarMath.planetLevelCost(def.id, planet.level, eggPrice())
		local affordable = cost ~= nil and stardust >= (cost :: number)
		at(
			Theme.button(
				row,
				if cost then `Lv up {fmt(cost)}` else "Max level",
				if affordable then "buy" else "disabled",
				if affordable
					then function()
						request("levelPlanet", entry.id)
					end
					else nil
			),
			212,
			112
		)
		at(
			Theme.button(row, if planet.locked then "Unlock" else "Lock", "primary", function()
				request("lockPlanet", entry.id, not planet.locked)
			end),
			328,
			66
		)
		first = first or equipButton
	end
	if Input.device() == "gamepad" and first and GuiService.SelectedObject == nil then
		GuiService.SelectedObject = first
	end
end

-- Toolbars ------------------------------------------------------------------

local function buildBars()
	Theme.clear(filters)
	Theme.clear(toolbar)
	local chips: { { id: string?, label: string, color: Color3 } } = {
		{ id = nil, label = "All", color = C.text },
	}
	for _, rarityId in P.RARITY_ORDER do
		local rarity = P.RARITIES[rarityId]
		table.insert(
			chips,
			{ id = rarityId, label = rarity.displayName, color = Color3.fromHex(rarity.color) }
		)
	end
	for index, chip in chips do
		local selected = rarityFilter == chip.id
		local button = Theme.button(
			filters,
			chip.label,
			if selected then "buy" else "primary",
			function()
				rarityFilter = chip.id
				view = "list"
				refresh()
			end
		)
		button.Size = UDim2.new(1 / #chips, -4, 1, 0)
		button.Position = UDim2.new((index - 1) / #chips, 2, 0, 0)
		button.TextSize = 12
	end
	local tools: { { label: string, style: Theme.ButtonStyle, onClick: () -> () } } = {
		{
			label = WHERE_TEXT[where],
			style = "primary",
			onClick = function()
				where = WHERE_NEXT[where]
				view = "list"
				refresh()
			end,
		},
		{
			label = SORT_TEXT[sortBy],
			style = "primary",
			onClick = function()
				sortBy = SORT_NEXT[sortBy]
				view = "list"
				refresh()
			end,
		},
		{
			label = "Equip best",
			style = "special",
			onClick = function()
				request("equipBest")
			end,
		},
		{
			label = "Sell...",
			style = if view == "bulk" then "buy" else "primary",
			onClick = function()
				view = if view == "bulk" then "list" else "bulk"
				armed = nil
				refresh()
			end,
		},
		{
			label = "Auto-sell...",
			style = if view == "autosell" then "buy" else "primary",
			onClick = function()
				view = if view == "autosell" then "list" else "autosell"
				refresh()
			end,
		},
	}
	for index, tool in tools do
		local button = Theme.button(toolbar, tool.label, tool.style, tool.onClick)
		button.Size = UDim2.new(1 / #tools, -6, 1, 0)
		button.Position = UDim2.new((index - 1) / #tools, 3, 0, 0)
		button.TextSize = 13
	end
end

refresh = function()
	if not gui.Enabled then
		return
	end
	buildBars()
	Theme.clear(list)
	if view == "stars" and choosingFor then
		showStars(choosingFor)
	elseif view == "bulk" then
		showBulk()
	elseif view == "autosell" then
		showAutoSell()
	else
		showList()
	end
end

local function open()
	gui.Enabled = true
	view, choosingFor, armed = "list", nil, nil
	local ok, problem = pcall(refresh :: any)
	if not ok then
		warn(`[Planets] Could not list the planets: {problem}`)
	end
	Theme.popIn(panel)
end

function PlanetsController.init()
	gui = Theme.screen("Planets", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.94, 0, 0.86, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(820, 720)
	size.Parent = panel
	local titleX = 16
	local icon = Theme.icon(panel, "RingedPlanet", 44)
	if icon then
		icon.Position = UDim2.fromOffset(12, 2)
		icon.ZIndex = 2
		titleX = 60
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 28),
		Text = "Planets",
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
	filters = Instance.new("Frame")
	filters.Name = "Filters"
	filters.BackgroundTransparency = 1
	filters.Position = UDim2.fromOffset(12, 64)
	filters.Size = UDim2.new(1, -24, 0, 30)
	filters.Parent = panel
	toolbar = Instance.new("Frame")
	toolbar.Name = "Tools"
	toolbar.BackgroundTransparency = 1
	toolbar.Position = UDim2.fromOffset(12, 100)
	toolbar.Size = UDim2.new(1, -24, 0, 32)
	toolbar.Parent = panel
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 140)
	list.Size = UDim2.new(1, -28, 1, -152)
end

function PlanetsController.start()
	ClientState.profileChanged:Connect(function(field)
		if
			field == "planets"
			or field == "stardust"
			or field == "settings"
			or field == "discovered"
			or field == "*"
		then
			refresh()
		end
	end)
	ClientState.openPlanets:Connect(function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		elseif input.KeyCode == Enum.KeyCode.P then
			ClientState.openPlanets:Fire()
		end
	end)
end

return PlanetsController

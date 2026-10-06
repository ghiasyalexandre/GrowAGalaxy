--!strict
-- The Planets panel (HUD's Planets button, P key): every planet you own,
-- rarest and most productive first, with where it is: in orbit around one of
-- your stars or in your inventory. From here you can level a planet, take it
-- out of orbit, or equip it: choose one of your stars and it goes into that
-- star's first free orbit (moving it there if it orbits another star). Only
-- planets in orbit produce Stardust. The server (StarSystem) checks every
-- action; this panel only asks.

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

local PlanetsController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: ScrollingFrame
-- While set, the panel lists your stars to put this planet around.
local choosingFor: string? = nil

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function planets(): { [string]: Types.PlanetRecord }
	local profile = ClientState.profile
	return if profile and profile.planets then profile.planets else {}
end

local function close()
	gui.Enabled = false
	choosingFor = nil
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
	refresh()
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
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.new(1, -56 - right, 0, 20),
		Text = titleText,
		TextColor3 = color or C.text,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(56, 28),
		Size = UDim2.new(1, -56 - right, 0, 18),
		Text = detail,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
end

local function sized(button: TextButton, x: number, width: number): TextButton
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -x, 0.5, 0)
	button.Size = UDim2.fromOffset(width, 34)
	return button
end

-- Choosing a star for one planet.
local function showStars(planetId: string)
	local planet = planets()[planetId]
	local def = if planet then P.BY_ID[planet.typeId] else nil
	if planet == nil or def == nil then
		choosingFor = nil
		refresh()
		return
	end
	local gain = StarMath.planetIncome(def.id, planet.level)
	header.Text = `Choose a star for your {def.displayName} (+{fmt(gain)} {CURRENCY}/s)`
	local back = Theme.row(list, 36, 0)
	back.BackgroundTransparency = 1
	Theme.button(back, "Back to planets", "primary", function()
		choosingFor = nil
		refresh()
	end).Size =
		UDim2.new(0, 170, 1, -4)
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
		local def2 = if type(typeId) == "string" then S.BY_ID[typeId] else nil
		local icon = Theme.starIcon(
			row,
			if def2 then Color3.fromHex(def2.color) else C.gold,
			if def2 then Color3.fromHex(def2.light) else C.gold,
			36,
			if typeId == S.ORDER[#S.ORDER] then "blackHole" else "star"
		)
		icon.Position = UDim2.fromOffset(10, 8)
		local income = model:GetAttribute("Income")
		local now = if type(income) == "number" then income else 0
		text(
			row,
			`{starName(model)}  ·  orbits {used}/{open}`,
			if here
				then "This planet already orbits here"
				else `This star {fmt(now)} -> {fmt(now + gain)} {CURRENCY}/s`,
			170
		)
		local full = used >= open
		local button = Theme.button(
			row,
			if here then "Here" elseif full then "No free orbit" else "Equip here",
			if here or full then "disabled" else "buy",
			if here or full
				then nil
				else function()
					choosingFor = nil
					request("equipPlanet", planetId, starId)
				end
		)
		sized(button, 8, 160)
	end
end

local RARITY_RANK: { [string]: number } = {}
for index, rarity in P.RARITY_ORDER do
	RARITY_RANK[rarity] = index
end

refresh = function()
	if not gui.Enabled then
		return
	end
	Theme.clear(list)
	if choosingFor then
		showStars(choosingFor)
		return
	end
	local owned = planets()
	local entries: { { id: string, planet: Types.PlanetRecord, def: PlanetsConfig.PlanetTypeDef } } =
		{}
	local inOrbit, production = 0, 0
	for id, planet in owned do
		local def = P.BY_ID[planet.typeId]
		if def then
			table.insert(entries, { id = id, planet = planet, def = def })
			if planet.star then
				inOrbit += 1
				production += StarMath.planetIncome(def.id, planet.level)
			end
		end
	end
	table.sort(entries, function(a, b)
		local ra, rb = RARITY_RANK[a.def.rarity], RARITY_RANK[b.def.rarity]
		if ra ~= rb then
			return ra > rb
		end
		local ia = StarMath.planetIncome(a.def.id, a.planet.level)
		local ib = StarMath.planetIncome(b.def.id, b.planet.level)
		if ia ~= ib then
			return ia > ib
		end
		return a.id < b.id
	end)
	header.Text =
		`{#entries} owned  ·  {inOrbit} in orbit  ·  planets make +{fmt(production)} {CURRENCY}/s`
	if #entries == 0 then
		local row = Theme.row(list, 52, 1)
		text(
			row,
			"No planets yet",
			"Buy planet eggs at the ISS, hatch them in your hangar, then put them in orbit.",
			14
		)
		return
	end
	local stars = StarController.myStars()
	local stardust = if ClientState.profile then ClientState.profile.stardust else 0
	local first: TextButton? = nil
	for order, entry in entries do
		local planet, def = entry.planet, entry.def
		local rarity = P.RARITIES[def.rarity]
		local row = Theme.row(list, 52, order)
		local dot = Theme.planetIcon(row, Color3.fromHex(def.color), 34, ringOf(def))
		dot.Position = UDim2.fromOffset(10, 9)
		local where = if planet.star
			then `Orbit {planet.slot or "?"} of your {starName(stars[planet.star])}`
			else "In inventory: not producing"
		text(
			row,
			`{def.displayName}  ·  Lv {planet.level}/{P.MAX_LEVEL}  ·  {rarity.displayName}`,
			`+{fmt(StarMath.planetIncome(def.id, planet.level))}/s  ·  {where}`,
			300,
			Color3.fromHex(rarity.color):Lerp(Color3.new(1, 1, 1), 0.35)
		)
		local cost = StarMath.planetLevelCost(def.id, planet.level)
		if cost then
			local affordable = stardust >= cost
			sized(
				Theme.button(
					row,
					`Level · {fmt(cost)}`,
					if affordable then "buy" else "disabled",
					if affordable
						then function()
							request("levelPlanet", entry.id)
						end
						else nil
				),
				148,
				140
			)
		end
		local button = if planet.star
			then Theme.button(row, "Unequip", "primary", function()
				request("unequipPlanet", entry.id)
			end)
			else Theme.button(row, "Equip", "special", function()
				choosingFor = entry.id
				refresh()
			end)
		sized(button, 8, 132)
		first = first or button
	end
	if Input.device() == "gamepad" and first and GuiService.SelectedObject == nil then
		GuiService.SelectedObject = first
	end
end

local function open()
	gui.Enabled = true
	choosingFor = nil
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
	panel.Size = UDim2.new(0.9, 0, 0.8, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(680, 700)
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
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(1, -28, 1, -78)
end

function PlanetsController.start()
	ClientState.profileChanged:Connect(function(field)
		if field == "planets" or field == "stardust" or field == "*" then
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

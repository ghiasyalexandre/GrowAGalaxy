--!strict
-- Every placed star, on this client: its planets orbiting in their slots on
-- tilted orbits (drawn as faint rings), a production label, and for your own
-- stars the Manage panel: level up, evolve to the next star type, move, and
-- for each open orbit equip one of your planets, level it or unequip it
-- (back to the planet inventory). Planets are local, drawn from the star's
-- Planets and PlanetLevels attributes with Fx/PlanetLook; the server
-- (StarSystem) checks every action.
--
-- Watching the attributes also drives the spectacle (Fx/StarFx) for every
-- star: birth (BornAt), level up, evolution (supernova) and planets joining
-- or levelling up. Your own stars' milestones also get a banner
-- (ClientState.celebrate).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local PlacementController = require(script.Parent.PlacementController)
local PlanetLook = require(script.Parent.Parent.Fx.PlanetLook)
local StarFx = require(script.Parent.Parent.Fx.StarFx)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))
local StarsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Stars"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local OrbitTime = require(Shared:WaitForChild("Logic"):WaitForChild("OrbitTime"))
local PlanetInventory = require(Shared:WaitForChild("Logic"):WaitForChild("PlanetInventory"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))
local Types = require(Shared:WaitForChild("Types"))

local S = Config.Stars
local P = Config.Planets
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local RING_COLOR = Color3.fromRGB(150, 180, 255)
-- Seconds after placement during which a newly seen star plays its birth.
local BIRTH_WINDOW = 4

type Planet = {
	part: Part,
	slot: number,
	phase: number,
	id: string,
	level: number,
	moons: { Part }, -- one per level past the first
}

type Visual = {
	model: Model,
	core: BasePart,
	planets: { Planet },
	rings: { Instance },
	label: BillboardGui,
	connections: { RBXScriptConnection },
	-- Last seen attributes, to tell what changed (and play its effect).
	typeId: any,
	level: number,
	planetsText: string,
	levelsText: string,
}

local StarController = {}

local visuals: { [Model]: Visual } = {}
local clock = { time = 0, rate = nil :: number?, paused = false }
local panel: Frame
local title: TextLabel
local subtitle: TextLabel
local actions: Frame
local list: ScrollingFrame
local panelStar: Model? = nil
local pickingSlot: number? = nil -- the planet picker is showing for this orbit

local function isMine(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

local function fmt(n: number): string
	return Format.abbreviate(n)
end

-- The ring colour a planet's icon shows, if its type has rings.
local function planetRing(def: PlanetsConfig.PlanetTypeDef): Color3?
	return if table.find(def.features, "ring") then Color3.fromHex(def.accent) else nil
end

local ring = PlanetLook.ring

local function clearPlanets(v: Visual)
	for _, planet in v.planets do
		planet.part:Destroy()
		for _, moon in planet.moons do
			moon:Destroy()
		end
	end
	for _, item in v.rings do
		item:Destroy()
	end
	v.planets = {}
	v.rings = {}
end

local function buildPlanets(v: Visual)
	clearPlanets(v)
	local encoded = v.model:GetAttribute("Planets")
	local level = v.model:GetAttribute("Level")
	if type(encoded) ~= "string" or type(level) ~= "number" then
		return
	end
	local planets = StarMath.decodePlanets(encoded)
	local levelsText = v.model:GetAttribute("PlanetLevels")
	local levels =
		StarMath.decodePlanetLevels(if type(levelsText) == "string" then levelsText else "")
	local typeId = v.model:GetAttribute("TypeId")
	local starDefNow = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	local sunlight = if starDefNow then Color3.fromHex(starDefNow.light) else Color3.new(1, 1, 1)
	for slot = 1, StarMath.slots(if type(typeId) == "string" then typeId else S.DEFAULT_TYPE) do
		local slotDef = S.SLOTS[slot]
		local planetId = planets[slot]
		local def = if planetId then P.BY_ID[planetId] else nil
		if def then
			-- An orbit's ring shows once a planet has been bought for it.
			for _, item in ring(v.core, slotDef.orbit, slotDef.tilt, RING_COLOR, 0.35) do
				table.insert(v.rings, item)
			end
			local planetLevel = levels[slot] or 1
			local radius = StarMath.planetRadius(def.id, planetLevel)
			local part = PlanetLook.build(def, radius, ClientState.reducedEffects == true)
			part.Name = `GaG_Planet_{def.id}`
			part.Parent = v.model
			-- Far from the star its light doesn't reach, so each planet carries
			-- its own: a light just sunward of it (the planet faces its star,
			-- see animate) lights the day side in the star's colour.
			local sunward = Instance.new("Attachment")
			sunward.Name = "GaG_Sunward"
			sunward.Position = Vector3.new(0, 0, -radius * 2.2)
			sunward.Parent = part
			local light = Instance.new("PointLight")
			light.Color = sunlight
			light.Range = radius * 4.5
			light.Brightness = 3
			light.Shadows = false
			light.Parent = sunward
			-- A glowing trail along its orbit, so planets read from afar.
			local top = Instance.new("Attachment")
			top.Position = Vector3.new(0, radius * 0.7, 0)
			top.Parent = part
			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, -radius * 0.7, 0)
			bottom.Parent = part
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Lifetime = 1.4
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color =
				ColorSequence.new(Color3.fromHex(def.color):Lerp(Color3.new(1, 1, 1), 0.35))
			trail.Transparency = NumberSequence.new(0.45, 1)
			trail.WidthScale = NumberSequence.new(1, 0.2)
			trail.Parent = part
			-- A little moon for every level past the first.
			local moons: { Part } = {}
			for _ = 2, planetLevel do
				local moon = Instance.new("Part")
				moon.Name = "GaG_Moon"
				moon.Shape = Enum.PartType.Ball
				moon.Size = Vector3.one * math.max(radius * 0.26, 0.8)
				moon.Color = Color3.fromHex(def.color):Lerp(Color3.fromRGB(220, 222, 230), 0.7)
				moon.Material = Enum.Material.Slate
				moon.Anchored = true
				moon.CanCollide = false
				moon.CanQuery = false
				moon.CanTouch = false
				moon.CastShadow = false
				moon.Parent = v.model
				table.insert(moons, moon)
			end
			table.insert(v.planets, {
				part = part,
				slot = slot,
				phase = slot * 2.1,
				id = def.id,
				level = planetLevel,
				moons = moons,
			})
		end
	end
end

local function refreshLabel(v: Visual)
	local text = v.label:FindFirstChildOfClass("TextLabel")
	local income = v.model:GetAttribute("Income")
	local typeId = v.model:GetAttribute("TypeId")
	local def = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	if text then
		local name = if def then def.displayName else "Star"
		text.Text = `{name}  +{fmt(if type(income) == "number" then income else 0)}/s`
	end
	v.label.StudsOffsetWorldSpace = Vector3.new(0, v.core.Size.Y / 2 + 8, 0)
end

local function makeLabel(core: BasePart, mine: boolean): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "GaG_StarLabel"
	gui.Size = UDim2.fromOffset(200, 26)
	gui.LightInfluence = 0
	gui.MaxDistance = 3000
	gui.Adornee = core
	gui.Parent = core
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = if mine then C.gold else Color3.fromRGB(200, 205, 220)
	text.TextStrokeTransparency = 0.4
	text.Parent = gui
	return gui
end

-- Panel ------------------------------------------------------------------

local refreshPanel: () -> ()

local function request(...: any)
	local ok, message = Net.StarRequest:InvokeServer(...)
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	-- The star's attributes have replicated by the time the answer arrives:
	-- show the new level, price and buttons straight away.
	if panelStar then
		refreshPanel()
	end
end

local function stardust(): number
	local profile = ClientState.profile
	return if profile then profile.stardust else 0
end

local function priceButton(
	parent: Instance,
	verb: string,
	cost: number,
	onClick: () -> (),
	style: Theme.ButtonStyle?
): TextButton
	local affordable = stardust() >= cost
	return Theme.button(
		parent,
		`{verb} · {fmt(cost)}`,
		if affordable then style or "buy" else "disabled",
		if affordable then onClick else nil
	)
end

local function placeRight(button: TextButton, width: number)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(width, 34)
end

local function rowText(
	row: Frame,
	titleText: string,
	detail: string?,
	indent: number,
	right: number?,
	color: Color3?
)
	local margin = right or 186
	Theme.label(row, {
		Position = UDim2.fromOffset(indent, if detail then 6 else 0),
		Size = UDim2.new(1, -indent - margin, 0, if detail then 20 else 52),
		Text = titleText,
		TextColor3 = color or (if detail then C.text else C.subtle),
	})
	if detail then
		Theme.label(row, {
			Position = UDim2.fromOffset(indent, 27),
			Size = UDim2.new(1, -indent - margin, 0, 18),
			Text = detail,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.subtle,
		})
	end
end

-- Marks an action button for an icon, added once it has its size.
local function tagIcon(button: TextButton, icon: string): TextButton
	button:SetAttribute("Icon", icon)
	return button
end

-- My planets, from the profile.
local function myPlanets(): { [string]: Types.PlanetRecord }
	local profile = ClientState.profile
	return if profile and profile.planets then profile.planets else {}
end

local function rarityText(def: PlanetsConfig.PlanetTypeDef): string
	return P.RARITIES[def.rarity].displayName
end

-- Choosing a planet for one orbit: inventory planets first, then planets on
-- other stars (moved here in one step), best producers first.
local function showPicker(model: Model, slot: number)
	Theme.clear(list)
	local starId = model:GetAttribute("StarId")
	local income = model:GetAttribute("Income")
	local now = if type(income) == "number" then income else 0
	local back = Theme.row(list, 36, 0)
	back.BackgroundTransparency = 1
	local backButton = Theme.button(back, "Back to orbits", "primary", function()
		pickingSlot = nil
		refreshPanel()
	end)
	backButton.Size = UDim2.new(0, 160, 1, -4)
	local choices: { { id: string, planet: Types.PlanetRecord, income: number } } = {}
	for id, planet in myPlanets() do
		if planet.star ~= starId and P.BY_ID[planet.typeId] then
			table.insert(choices, {
				id = id,
				planet = planet,
				income = StarMath.planetIncome(planet.typeId, planet.level),
			})
		end
	end
	table.sort(choices, function(a, b)
		local aFree, bFree = a.planet.star == nil, b.planet.star == nil
		if aFree ~= bFree then
			return aFree
		end
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.id < b.id
	end)
	if #choices == 0 then
		local row = Theme.row(list, 52, 1)
		rowText(
			row,
			"No free planets yet",
			"Hatch planet eggs at the ISS, or unequip a planet from another star.",
			14,
			14
		)
		return
	end
	for order, choice in choices do
		local def = P.BY_ID[choice.planet.typeId]
		local row = Theme.row(list, 52, order)
		local dot = Theme.planetIcon(row, Color3.fromHex(def.color), 34, planetRing(def))
		dot.Position = UDim2.fromOffset(8, 9)
		rowText(
			row,
			`{def.displayName}  ·  Lv {choice.planet.level}  ·  {rarityText(def)}`,
			`+{fmt(choice.income)}/s  ·  this star {fmt(now)} -> {fmt(now + choice.income)}/s{if choice.planet.star
				then "  ·  on another star"
				else ""}`,
			48,
			nil,
			Color3.fromHex(P.RARITIES[def.rarity].color)
		)
		local button = Theme.button(
			row,
			if choice.planet.star then "Move here" else "Equip",
			"buy",
			function()
				pickingSlot = nil
				request("equipPlanet", choice.id, starId, slot)
			end
		)
		placeRight(button, 170)
	end
end

refreshPanel = function()
	local model = panelStar
	if model == nil or model.Parent == nil then
		panel.Visible = false
		panelStar = nil
		return
	end
	local typeId = model:GetAttribute("TypeId") :: string
	local level = model:GetAttribute("Level") :: number
	local def = S.BY_ID[typeId]
	local income = model:GetAttribute("Income")
	local starId = model:GetAttribute("StarId")

	local top = StarMath.maxLevel(typeId)
	local open = StarMath.slots(typeId)
	local target = StarMath.evolveTarget(typeId)
	local nextOpen = if target then StarMath.slots(target) else nil
	local planets = myPlanets()
	local ids: { [number]: string } = if type(starId) == "string"
		then PlanetInventory.idsOn(planets, starId)
		else {}
	local used = 0
	for _ in ids do
		used += 1
	end
	title.Text = `{if def then def.displayName else typeId}  ·  level {level}/{top}`
	title.TextColor3 = if def then Color3.fromHex(def.light) else C.gold
	subtitle.Text =
		`+{fmt(if type(income) == "number" then income else 0)} {CURRENCY}/s  ·  orbits {used}/{open}  ·  {if nextOpen
			then `next evolution: {nextOpen}`
			else "max orbits"}`

	-- Actions: level up, evolve, move.
	Theme.clear(actions)
	local buttons: { TextButton } = {}
	local upgradeCost = StarMath.upgradeCost(typeId, level)
	if upgradeCost then
		table.insert(
			buttons,
			tagIcon(
				priceButton(actions, "Level up", upgradeCost, function()
					request("upgrade", starId)
				end),
				"LevelUp"
			)
		)
	end
	if target then
		local targetDef = S.BY_ID[target]
		-- Evolving needs max level; until then the button says when.
		table.insert(
			buttons,
			tagIcon(
				if level >= top
					then priceButton(
						actions,
						`Evolve: {targetDef.displayName}`,
						targetDef.cost,
						function()
							request("evolve", starId)
						end,
						"special"
					)
					else Theme.button(actions, `Evolve at level {top}`, "disabled", nil),
				"RainbowStar"
			)
		)
	end
	table.insert(
		buttons,
		tagIcon(
			Theme.button(actions, "Move", "primary", function()
				panel.Visible = false
				panelStar = nil
				if type(starId) == "string" then
					PlacementController.begin({ mode = "move", starId = starId })
				end
			end),
			"Rocket"
		)
	)
	for index, button in buttons do
		button.Size = UDim2.new(1 / #buttons, -6, 1, 0)
		button.Position = UDim2.new((index - 1) / #buttons, 3, 0, 0)
		local icon = button:GetAttribute("Icon")
		if type(icon) == "string" then
			Theme.buttonIcon(button, icon)
		end
	end

	if pickingSlot then
		showPicker(model, pickingSlot)
		return
	end

	-- Orbits: the open ones, plus a preview of those the evolution opens.
	Theme.clear(list)
	for slot = 1, math.max(open, nextOpen or 0) do
		local row = Theme.row(list, 52, slot)
		local planetId = ids[slot]
		local planet = if planetId then planets[planetId] else nil
		local planetDef = if planet then P.BY_ID[planet.typeId] else nil
		local button: TextButton
		if planet and planetDef and planetId then
			local dot =
				Theme.planetIcon(row, Color3.fromHex(planetDef.color), 34, planetRing(planetDef))
			dot.Position = UDim2.fromOffset(8, 9)
			rowText(
				row,
				`{planetDef.displayName}  ·  Lv {planet.level}/{P.MAX_LEVEL}`,
				`Orbit {slot}  ·  {rarityText(planetDef)}  ·  +{fmt(
					StarMath.planetIncome(planetDef.id, planet.level)
				)}/s`,
				48,
				300,
				Color3.fromHex(P.RARITIES[planetDef.rarity].color)
			)
			local levelCost = StarMath.planetLevelCost(planetDef.id, planet.level)
			if levelCost then
				local levelButton = priceButton(row, "Level", levelCost, function()
					request("levelPlanet", planetId)
				end)
				levelButton.AnchorPoint = Vector2.new(1, 0.5)
				levelButton.Position = UDim2.new(1, -144, 0.5, 0)
				levelButton.Size = UDim2.fromOffset(130, 34)
			end
			button = Theme.button(row, "Unequip", "primary", function()
				request("unequipPlanet", planetId)
			end)
			placeRight(button, 130)
		elseif slot <= open then
			local icon = Theme.icon(row, "PlanetUp", 40)
			if icon then
				icon.Position = UDim2.fromOffset(6, 6)
			end
			rowText(row, `Orbit {slot}: empty`, nil, if icon then 52 else 14)
			button = Theme.button(row, "Equip a planet", "buy", function()
				pickingSlot = slot
				refreshPanel()
			end)
			placeRight(button, 170)
		else
			rowText(row, `Orbit {slot}: opens when this star evolves`, nil, 14)
			button = Theme.button(row, "Evolve to open", "disabled", nil)
			placeRight(button, 170)
		end
	end
	if ClientState.mode == "ship" and Input.device() == "keyboard" then
		local hint = Theme.row(list, 22, 99)
		hint.BackgroundTransparency = 1
		Theme.label(hint, {
			Size = UDim2.fromScale(1, 1),
			Text = "Hold Alt to use the mouse while flying",
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.subtle,
		})
	end
end

local function closePanel()
	panelStar = nil
	panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
end

local function openPanel(model: Model)
	panelStar = model
	pickingSlot = nil
	panel.Visible = true
	refreshPanel()
	Theme.popIn(panel)
	if Input.device() == "gamepad" then
		GuiService.SelectedObject = actions:FindFirstChildOfClass("TextButton")
	end
end

local function buildPanel()
	local gui = Theme.screen("StarPanel", Players.LocalPlayer:WaitForChild("PlayerGui"))
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -16, 0.5, 0)
	panel.Size = UDim2.new(0.42, 0, 0.62, 0)
	panel.Visible = false
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(330, 360)
	size.MaxSize = Vector2.new(470, 480)
	size.Parent = panel

	title = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -190, 0, 26),
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
	})
	subtitle = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 38),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	local close = Theme.closeButton(panel, closePanel)
	-- Inspect: watch this system up close with its own clock.
	local inspect = Theme.button(panel, "Inspect", "primary", function()
		local model = panelStar
		closePanel()
		if model then
			ClientState.inspectStar:Fire(model)
		end
	end)
	inspect.AnchorPoint = Vector2.new(1, 0)
	inspect.Position = UDim2.new(1, -close.Size.X.Offset - 18, 0, 10)
	inspect.Size = UDim2.fromOffset(110, 32)
	Theme.buttonIcon(inspect, "Telescope")

	actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.fromOffset(13, 64)
	actions.Size = UDim2.new(1, -26, 0, 36)
	actions.Parent = panel

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(16, 110)
	list.Size = UDim2.new(1, -32, 1, -122)
end

-- Stars ------------------------------------------------------------------

local animate: (dt: number?) -> ()

local function starDef(v: Visual): StarsConfig.StarTypeDef?
	local typeId = v.model:GetAttribute("TypeId")
	return if type(typeId) == "string" then S.BY_ID[typeId] else nil
end

local function starColor(v: Visual): Color3
	local def = starDef(v)
	return if def then Color3.fromHex(def.light) else C.gold
end

-- A banner for your own star's milestones.
local function celebrate(v: Visual, header: string, titleText: string, body: string, flash: boolean)
	if isMine(v.model) then
		ClientState.celebrate:Fire(header, titleText, body, starColor(v), flash)
	end
end

local function onTypeChanged(v: Visual)
	local typeId = v.model:GetAttribute("TypeId")
	if typeId == v.typeId then
		return
	end
	v.typeId = typeId
	local def = starDef(v)
	-- A new orbit ring and the new star's light on its planets.
	buildPlanets(v)
	animate()
	StarFx.supernova(v.core.Position, v.core.Size.X / 2, starColor(v))
	if def then
		celebrate(
			v,
			"STAR EVOLVED",
			def.displayName,
			`{StarMath.slots(def.id)} orbits  ·  levels up to {StarMath.maxLevel(def.id)}`,
			true
		)
	end
end

local function onLevelChanged(v: Visual)
	local level = v.model:GetAttribute("Level")
	if type(level) ~= "number" or level == v.level then
		return
	end
	local raised = level > v.level
	v.level = level
	if raised then
		StarFx.levelUp(v.core.Position, v.core.Size.X / 2, starColor(v))
		local def = starDef(v)
		local top = if def then StarMath.maxLevel(def.id) else level
		local nextDef = if def then StarMath.evolveTarget(def.id) else nil
		if level >= top and nextDef then
			celebrate(
				v,
				"MAX LEVEL",
				`{if def then def.displayName else "Star"}  ·  level {level}`,
				`Ready to evolve into a {S.BY_ID[nextDef].displayName}`,
				false
			)
		else
			celebrate(
				v,
				"LEVEL UP",
				`{if def then def.displayName else "Star"}  ·  level {level}/{top}`,
				`Production x{math.floor(StarMath.levelMultiplier(level) + 0.5)}`,
				false
			)
		end
	end
end

local function onPlanetLevelsChanged(v: Visual)
	local text = v.model:GetAttribute("PlanetLevels")
	local encoded = if type(text) == "string" then text else ""
	local before = StarMath.decodePlanetLevels(v.levelsText)
	local after = StarMath.decodePlanetLevels(encoded)
	v.levelsText = encoded
	buildPlanets(v)
	animate()
	for _, planet in v.planets do
		local def = P.BY_ID[planet.id]
		local was, now = before[planet.slot] or 1, after[planet.slot] or 1
		if def and now > was then
			StarFx.materialize(planet.part, Color3.fromHex(def.color))
			celebrate(
				v,
				"PLANET LEVEL UP",
				`{def.displayName}  ·  level {now}/{P.MAX_LEVEL}`,
				`+{fmt(StarMath.planetIncome(def.id, now))} {CURRENCY}/s  ·  a new moon joins it`,
				false
			)
		end
	end
end

local function onPlanetsChanged(v: Visual)
	local text = v.model:GetAttribute("Planets")
	local encoded = if type(text) == "string" then text else ""
	local before = StarMath.decodePlanets(v.planetsText)
	local after = StarMath.decodePlanets(encoded)
	v.planetsText = encoded
	buildPlanets(v)
	animate()
	for _, planet in v.planets do
		local planetId = after[planet.slot]
		local def = if planetId then P.BY_ID[planetId] else nil
		if def and planetId ~= before[planet.slot] then
			StarFx.materialize(planet.part, Color3.fromHex(def.color))
			celebrate(
				v,
				"NEW WORLD",
				def.displayName,
				`Orbit {planet.slot}  ·  {rarityText(def)}  ·  +{fmt(
					StarMath.planetIncome(def.id, planet.level)
				)} {CURRENCY}/s`,
				false
			)
		end
	end
end

local waitingForCore: { [Instance]: boolean } = {}
local orbitWarned = false

local function add(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("StarId") == nil or visuals[model] then
		return
	end
	local core = model.PrimaryPart or model:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		-- Its core may replicate a moment after the model: try again then.
		if not waitingForCore[model] then
			waitingForCore[model] = true
			model.ChildAdded:Once(function()
				waitingForCore[model] = nil
				add(model)
			end)
		end
		return
	end
	local mine = isMine(model)
	local prompt = core:FindFirstChild("Manage")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = mine and not ClientState.inspecting
	end
	-- Anyone may inspect any system (R / R3): a local prompt on this client.
	local inspect = Instance.new("ProximityPrompt")
	inspect.Name = "GaG_Inspect"
	inspect.ActionText = "Inspect system"
	inspect.ObjectText = "Solar system"
	inspect.KeyboardKeyCode = Enum.KeyCode.R
	inspect.GamepadKeyCode = Enum.KeyCode.ButtonR3
	inspect.HoldDuration = 0
	inspect.MaxActivationDistance = S.MANAGE_DISTANCE
	inspect.RequiresLineOfSight = false
	inspect.UIOffset = Vector2.new(0, 70)
	inspect:SetAttribute("GaG_Inspect", true)
	inspect.Enabled = not ClientState.inspecting
	inspect.Parent = core
	local level = model:GetAttribute("Level")
	local planetsText = model:GetAttribute("Planets")
	local v: Visual = {
		model = model,
		core = core,
		planets = {},
		rings = {},
		label = makeLabel(core, mine),
		connections = {},
		typeId = model:GetAttribute("TypeId"),
		level = if type(level) == "number" then level else 1,
		planetsText = if type(planetsText) == "string" then planetsText else "",
		levelsText = if type(model:GetAttribute("PlanetLevels")) == "string"
			then model:GetAttribute("PlanetLevels") :: string
			else "",
	}
	visuals[model] = v
	buildPlanets(v)
	refreshLabel(v)

	-- A star placed moments ago ignites (BornAt is set by the server).
	local function birth()
		local born = model:GetAttribute("BornAt")
		if type(born) == "number" and Workspace:GetServerTimeNow() - born < BIRTH_WINDOW then
			StarFx.birth(core.Position, core.Size.X / 2, starColor(v))
			local def = starDef(v)
			celebrate(
				v,
				"NEW STAR",
				if def then def.displayName else "Star",
				"Manage it to add planets and level it up",
				false
			)
		end
	end
	birth()
	table.insert(v.connections, model:GetAttributeChangedSignal("BornAt"):Connect(birth))

	local handlers: { [string]: (Visual) -> () } = {
		TypeId = onTypeChanged,
		Level = onLevelChanged,
		Planets = onPlanetsChanged,
		PlanetLevels = onPlanetLevelsChanged,
		Income = function() end,
	}
	for attribute, handler in handlers do
		table.insert(
			v.connections,
			model:GetAttributeChangedSignal(attribute):Connect(function()
				-- The panel and label first: a failing effect or banner must
				-- never leave them showing the old level.
				refreshLabel(v)
				if panelStar == model then
					refreshPanel()
				end
				local ok, problem = pcall(handler :: any, v)
				if not ok then
					warn(`[StarController] {attribute} change effect failed: {problem}`)
				end
				if panelStar == model then
					refreshPanel()
				end
			end)
		)
	end
	table.insert(
		v.connections,
		model.AncestryChanged:Connect(function()
			if model.Parent == nil then
				for _, connection in v.connections do
					connection:Disconnect()
				end
				visuals[model] = nil
			end
		end)
	)
end

-- Orbit clock: simulated seconds. Normally it follows the server clock at
-- ORBIT_DEFAULT_RATE, so every client sees the same positions; while a system
-- is inspected the inspect slider sets its own rate (StarController.clock).
animate = function(dt: number?)
	if clock.rate == nil then
		clock.time = Workspace:GetServerTimeNow() * S.ORBIT_DEFAULT_RATE
	elseif dt and not clock.paused then
		clock.time += dt * (clock.rate :: number)
	end
	for _, v in visuals do
		-- One broken system must not stop every other one from turning; the
		-- first failure is reported once in Output.
		local ok, problem = pcall(function()
			local center = v.core.CFrame.Position
			for _, planet in v.planets do
				local slot = S.SLOTS[planet.slot]
				local angle = OrbitTime.angle(planet.slot, clock.time, planet.phase)
				local offset = CFrame.Angles(math.rad(slot.tilt), 0, 0)
					* Vector3.new(math.cos(angle) * slot.orbit, 0, math.sin(angle) * slot.orbit)
				-- Facing the star, so the sunward light sits on the day side.
				local at = center + offset
				planet.part.CFrame = CFrame.lookAt(at, center)
				-- Moons circle the planet, faster the closer they are.
				local size = planet.part.Size.X / 2
				for index, moon in planet.moons do
					local reach = size * (1.7 + index * 0.45)
					local turn = clock.time / (86400 * (2 + index * 1.5)) * 2 * math.pi
						+ index * 1.9
					moon.CFrame = CFrame.new(at)
						* CFrame.Angles(math.rad(15 * index), 0, 0)
						* CFrame.new(math.cos(turn) * reach, 0, math.sin(turn) * reach)
				end
			end
		end)
		if not ok and not orbitWarned then
			orbitWarned = true
			warn(`[StarController] orbit update failed: {problem}`)
		end
	end
end

-- The orbit clock: `rate` nil follows the server; otherwise simulated
-- seconds per real second (set by the inspect view), optionally paused.
StarController.clock = clock

-- The planets drawn around a star: part, orbit slot and planet type id.
-- Shows or hides every star's Manage and Inspect prompts (hidden while a
-- system is being inspected, so they don't cover the view).
function StarController.setPromptsShown(shown: boolean)
	for model, v in visuals do
		local manage = v.core:FindFirstChild("Manage")
		if manage and manage:IsA("ProximityPrompt") then
			manage.Enabled = shown and isMine(model)
		end
		local inspect = v.core:FindFirstChild("GaG_Inspect")
		if inspect and inspect:IsA("ProximityPrompt") then
			inspect.Enabled = shown
		end
	end
end

-- Opens a star's Manage panel (Galaxy Control uses it).
function StarController.openPanel(model: Model)
	openPanel(model)
end

function StarController.planetsOf(model: Model): { { part: Part, slot: number, id: string } }
	local v = visuals[model]
	local result: { { part: Part, slot: number, id: string } } = {}
	if v then
		for _, planet in v.planets do
			table.insert(result, { part = planet.part, slot = planet.slot, id = planet.id })
		end
	end
	return result
end

-- The local player's own star models by id, for the shop and placement.
function StarController.myStars(): { [string]: Model }
	local mine: { [string]: Model } = {}
	for model in visuals do
		local id = model:GetAttribute("StarId")
		if isMine(model) and type(id) == "string" then
			mine[id] = model
		end
	end
	return mine
end

-- My stars as save-like records (type only), for the tier rules in the shop
-- and the HUD's next goal.
function StarController.myRecords(): { [string]: Types.StarRecord }
	local records: { [string]: Types.StarRecord } = {}
	for id, model in StarController.myStars() do
		local typeId = model:GetAttribute("TypeId")
		records[id] = {
			typeId = if type(typeId) == "string" then typeId else S.DEFAULT_TYPE,
			level = 1,
			pos = { x = 0, y = 0, z = 0 },
		}
	end
	return records
end

function StarController.init()
	buildPanel()
	PlacementController.setStarSource(StarController.myStars)
end

function StarController.start()
	task.spawn(function()
		local regions = Workspace:WaitForChild("Regions")
		regions.DescendantAdded:Connect(add)
		for _, descendant in regions:GetDescendants() do
			add(descendant)
		end
	end)
	RunService.RenderStepped:Connect(animate)
	ClientState.profileChanged:Connect(function(field)
		if panelStar and (field == "stardust" or field == "planets" or field == "*") then
			refreshPanel()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("GaG_Inspect") == true then
			local model = prompt:FindFirstAncestorOfClass("Model")
			if model then
				ClientState.inspectStar:Fire(model)
			end
		elseif prompt:GetAttribute("TycoonAction") == "Manage" then
			local model = prompt:FindFirstAncestorOfClass("Model")
			if model and isMine(model) then
				openPanel(model)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and panelStar and input.KeyCode == Enum.KeyCode.Backspace then
			closePanel()
		end
	end)
end

return StarController

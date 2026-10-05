--!strict
-- Every placed star, on this client: its planets orbiting in their slots on
-- tilted orbits (drawn as faint rings), a production label, and for your own
-- stars the Manage panel: level up, evolve to the next star type, move, and
-- buy or upgrade the planet in each orbit slot. Planets are local, drawn from
-- the star's Planets attribute; the server (StarSystem) checks every action.
--
-- Watching the attributes also drives the spectacle (Fx/StarFx) for every
-- star: birth (BornAt), level up, evolution (supernova) and new or upgraded
-- planets. Your own stars' milestones also get a banner (ClientState.celebrate).

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
local StarFx = require(script.Parent.Parent.Fx.StarFx)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))
local StarsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Stars"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local OrbitTime = require(Shared:WaitForChild("Logic"):WaitForChild("OrbitTime"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))
local Types = require(Shared:WaitForChild("Types"))

local S = Config.Stars
local P = Config.Planets
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local RING_COLOR = Color3.fromRGB(150, 180, 255)
-- Bezier handle length for a quarter circle of radius 1.
local QUARTER = 0.5523
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
local picking = false -- the planet picker is showing instead of the slots

local function isMine(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function planetRing(def: { ring: string? }): Color3?
	local ringColor = def.ring
	return if ringColor then Color3.fromHex(ringColor) else nil
end

-- A faint circle of `radius` around `core`, tilted `tilt` degrees, drawn
-- with four curved beams between attachments on the core.
local function ring(
	core: BasePart,
	radius: number,
	tilt: number,
	color: Color3,
	width: number
): { Instance }
	local made: { Instance } = {}
	local plane = CFrame.Angles(math.rad(tilt), 0, 0)
	local points: { Attachment } = {}
	for index = 0, 3 do
		local angle = index * math.pi / 2
		local attachment = Instance.new("Attachment")
		attachment.Name = "GaG_Orbit"
		-- Each attachment's +X axis is the tangent the beam curves along.
		attachment.CFrame = plane
			* CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			* CFrame.Angles(0, -angle - math.pi / 2, 0)
		attachment.Parent = core
		table.insert(points, attachment)
		table.insert(made, attachment)
	end
	for index = 1, 4 do
		local beam = Instance.new("Beam")
		beam.Name = "GaG_OrbitRing"
		beam.Attachment0 = points[index]
		beam.Attachment1 = points[index % 4 + 1]
		beam.CurveSize0 = radius * QUARTER
		beam.CurveSize1 = radius * QUARTER
		beam.Segments = 16
		beam.Width0 = width
		beam.Width1 = width
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(0.6)
		beam.Parent = core
		table.insert(made, beam)
	end
	return made
end

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

-- Makes a planet look its part: a shimmering atmosphere in a lighter shade,
-- embers off molten worlds, glints off crystal ones, swirling storms on gas
-- giants.
local function dress(part: Part, def: PlanetsConfig.PlanetTypeDef, radius: number)
	local color = Color3.fromHex(def.color)
	local air = Instance.new("Part")
	air.Name = "Atmosphere"
	air.Shape = Enum.PartType.Ball
	air.Size = Vector3.one * radius * 2.36
	air.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
	air.Material = Enum.Material.ForceField
	air.Anchored = true
	air.CanCollide = false
	air.CanQuery = false
	air.CanTouch = false
	air.CastShadow = false
	air.Parent = part
	if ClientState.reducedEffects then
		return
	end
	if def.id == "Molten" then
		local embers = Instance.new("ParticleEmitter")
		embers.Rate = 6
		embers.Speed = NumberRange.new(radius * 0.4, radius * 0.9)
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Lifetime = NumberRange.new(0.8, 1.4)
		embers.Size = NumberSequence.new(radius * 0.18, 0)
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 70, 30))
		embers.LightEmission = 1
		embers.Parent = part
	elseif def.id == "Crystal" then
		local glints = Instance.new("Sparkles")
		glints.SparkleColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
		glints.Parent = part
	elseif def.id == "GasGiant" or def.id == "IceGiant" then
		local storm = Instance.new("ParticleEmitter")
		storm.Rate = 3
		storm.Speed = NumberRange.new(0)
		storm.Lifetime = NumberRange.new(2, 3)
		storm.Size = NumberSequence.new(radius * 0.7, radius * 1.1)
		storm.Transparency = NumberSequence.new(0.6, 1)
		storm.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3))
		storm.RotSpeed = NumberRange.new(40, 80)
		storm.LockedToPart = true
		storm.Parent = part
	end
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
		-- Open orbits show as rings even before a planet is bought.
		for _, item in
			ring(v.core, slotDef.orbit, slotDef.tilt, RING_COLOR, if def then 0.35 else 0.2)
		do
			table.insert(v.rings, item)
		end
		if def then
			local planetLevel = levels[slot] or 1
			local radius = StarMath.planetRadius(def.id, planetLevel)
			local part = Instance.new("Part")
			part.Name = `GaG_Planet_{def.id}`
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * radius * 2
			part.Color = Color3.fromHex(def.color)
			part.Material = (Enum.Material :: any)[def.material] or Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = v.model
			-- Far from the star its light doesn't reach, so each planet carries
			-- its own: a light just sunward of it (the planet faces its star,
			-- see animate) lights the day side in the star's colour.
			local sunward = Instance.new("Attachment")
			sunward.Name = "GaG_Sunward"
			sunward.Position = Vector3.new(0, 0, -def.radius * 2.2)
			sunward.Parent = part
			local light = Instance.new("PointLight")
			light.Color = sunlight
			light.Range = def.radius * 4.5
			light.Brightness = 3
			light.Shadows = false
			light.Parent = sunward
			-- A glowing trail along its orbit, so planets read from afar.
			local top = Instance.new("Attachment")
			top.Position = Vector3.new(0, def.radius * 0.7, 0)
			top.Parent = part
			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, -def.radius * 0.7, 0)
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
			local ringHex = def.ring
			if ringHex then
				for _, item in
					ring(part, def.radius * 1.6, 20, Color3.fromHex(ringHex), def.radius * 0.45)
				do
					table.insert(v.rings, item)
				end
			end
			-- Start planets spread around their orbits, same on every client.
			dress(part, def, radius)
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
	right: number?
)
	local margin = right or 186
	Theme.label(row, {
		Position = UDim2.fromOffset(indent, if detail then 6 else 0),
		Size = UDim2.new(1, -indent - margin, 0, if detail then 20 else 52),
		Text = titleText,
		TextColor3 = if detail then C.text else C.subtle,
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

local function showPicker(model: Model, typeId: string)
	Theme.clear(list)
	local back = Theme.row(list, 36, 0)
	back.BackgroundTransparency = 1
	local backButton = Theme.button(back, "Back to orbits", "primary", function()
		picking = false
		refreshPanel()
	end)
	backButton.Size = UDim2.new(0, 160, 1, -4)
	for order, planetId in P.ORDER do
		local def = P.BY_ID[planetId]
		local row = Theme.row(list, 52, order)
		local dot = Theme.planetIcon(row, Color3.fromHex(def.color), 34, planetRing(def))
		dot.Position = UDim2.fromOffset(8, 9)
		rowText(
			row,
			`{def.displayName}  ·  tier {def.tier}`,
			`+{fmt(def.income)} {CURRENCY}/s`,
			48
		)
		local button
		if StarMath.planetAllowed(typeId, planetId) then
			button = priceButton(row, "Buy", def.cost, function()
				picking = false
				request("buyPlanet", model:GetAttribute("StarId"), planetId)
			end)
		else
			local needed = S.BY_ID[S.ORDER[def.tier]]
			button = Theme.button(
				row,
				`Needs {if needed then needed.displayName else "a bigger star"}`,
				"disabled",
				nil
			)
		end
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
	local encoded = model:GetAttribute("Planets")
	local planets = StarMath.decodePlanets(if type(encoded) == "string" then encoded else "")
	local levelsAttr = model:GetAttribute("PlanetLevels")
	local planetLevels =
		StarMath.decodePlanetLevels(if type(levelsAttr) == "string" then levelsAttr else "")
	local def = S.BY_ID[typeId]
	local income = model:GetAttribute("Income")
	local starId = model:GetAttribute("StarId")

	local top = StarMath.maxLevel(typeId)
	local open = StarMath.slots(typeId)
	title.Text = `{if def then def.displayName else typeId}  ·  level {level}/{top}`
	title.TextColor3 = if def then Color3.fromHex(def.light) else C.gold
	subtitle.Text =
		`+{fmt(if type(income) == "number" then income else 0)} {CURRENCY}/s  ·  {open} orbits  ·  planets up to tier {if def
			then def.tier
			else 1}`

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
	local target = StarMath.evolveTarget(typeId)
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

	if picking then
		showPicker(model, typeId)
		return
	end

	-- Orbits: the star's own, plus a preview of the one its evolution opens.
	Theme.clear(list)
	local shown = if target then math.min(open + 1, #S.SLOTS) else open
	for slot = 1, shown do
		local row = Theme.row(list, 52, slot)
		local planetId = planets[slot]
		local planetDef = if planetId then P.BY_ID[planetId] else nil
		local button: TextButton
		if planetDef and planetId then
			local dot =
				Theme.planetIcon(row, Color3.fromHex(planetDef.color), 34, planetRing(planetDef))
			dot.Position = UDim2.fromOffset(8, 9)
			local record: Types.StarRecord = {
				typeId = typeId,
				level = level,
				pos = { x = 0, y = 0, z = 0 },
				planets = { [tostring(slot)] = planetId },
				planetLevels = { [tostring(slot)] = planetLevels[slot] or 1 },
			}
			local planetLevel = StarMath.planetLevel(record, tostring(slot))
			rowText(
				row,
				`{planetDef.displayName}  ·  Lv {planetLevel}/{P.MAX_LEVEL}`,
				`Orbit {slot}  ·  +{fmt(StarMath.planetIncome(planetId, planetLevel))}/s`,
				48,
				300
			)
			local levelCost = StarMath.planetLevelCost(planetId, planetLevel)
			if levelCost then
				local levelButton = priceButton(row, "Level", levelCost, function()
					request("levelPlanet", starId, tostring(slot))
				end)
				levelButton.AnchorPoint = Vector2.new(1, 0.5)
				levelButton.Position = UDim2.new(1, -184, 0.5, 0)
				levelButton.Size = UDim2.fromOffset(110, 34)
			end
			local nextId, cost = StarMath.planetUpgrade(planetId)
			if nextId and cost and StarMath.planetAllowed(typeId, nextId) then
				button = priceButton(row, `To {P.BY_ID[nextId].displayName}`, cost, function()
					request("upgradePlanet", starId, tostring(slot))
				end)
			elseif nextId then
				button = Theme.button(row, "Evolve star to upgrade", "disabled", nil)
			else
				button = Theme.button(row, "Finest planet", "disabled", nil)
			end
		elseif slot <= open then
			local icon = Theme.icon(row, "PlanetUp", 40)
			if icon then
				icon.Position = UDim2.fromOffset(6, 6)
			end
			rowText(row, `Orbit {slot}: empty`, nil, if icon then 52 else 14)
			button = Theme.button(row, "Buy a planet", "buy", function()
				picking = true
				refreshPanel()
			end)
		else
			rowText(row, `Orbit {slot}: opens when this star evolves`, nil, 14)
			button = Theme.button(row, "Evolve to open", "disabled", nil)
		end
		placeRight(button, 170)
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
	picking = false
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
			`{StarMath.slots(def.id)} orbits  ·  levels up to {StarMath.maxLevel(def.id)}  ·  planets up to tier {def.tier}`,
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
				if before[planet.slot] then "WORLD UPGRADED" else "NEW WORLD",
				def.displayName,
				`Orbit {planet.slot}  ·  +{fmt(def.income)} {CURRENCY}/s`,
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
		prompt.Enabled = mine
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
				local air = planet.part:FindFirstChild("Atmosphere")
				if air and air:IsA("BasePart") then
					air.CFrame = planet.part.CFrame
				end
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
			planets = {},
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
		if panelStar and (field == "stardust" or field == "*") then
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

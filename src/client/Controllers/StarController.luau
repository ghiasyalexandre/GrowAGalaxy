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
local StarsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Stars"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
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

type Planet = { part: Part, slot: number, phase: number }

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
}

local StarController = {}

local visuals: { [Model]: Visual } = {}
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
	for slot = 1, StarMath.slots(level) do
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
			local part = Instance.new("Part")
			part.Name = `GaG_Planet_{def.id}`
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * def.radius * 2
			part.Color = Color3.fromHex(def.color)
			part.Material = (Enum.Material :: any)[def.material] or Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = v.model
			local ringHex = def.ring
			if ringHex then
				for _, item in
					ring(part, def.radius * 1.8, 20, Color3.fromHex(ringHex), def.radius * 0.5)
				do
					table.insert(v.rings, item)
				end
			end
			-- Start planets spread around their orbits, same on every client.
			table.insert(v.planets, { part = part, slot = slot, phase = slot * 2.1 })
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

local function request(...: any)
	local ok, message = Net.StarRequest:InvokeServer(...)
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
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

local function rowText(row: Frame, titleText: string, detail: string?, indent: number)
	Theme.label(row, {
		Position = UDim2.fromOffset(indent, if detail then 6 else 0),
		Size = UDim2.new(1, -indent - 186, 0, if detail then 20 else 52),
		Text = titleText,
		TextColor3 = if detail then C.text else C.subtle,
	})
	if detail then
		Theme.label(row, {
			Position = UDim2.fromOffset(indent, 27),
			Size = UDim2.new(1, -indent - 186, 0, 18),
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

local refreshPanel: () -> ()

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
	local def = S.BY_ID[typeId]
	local income = model:GetAttribute("Income")
	local starId = model:GetAttribute("StarId")

	title.Text =
		`{if def then def.displayName else typeId}  ·  level {level}/{StarMath.maxLevel()}`
	title.TextColor3 = if def then Color3.fromHex(def.light) else C.gold
	subtitle.Text =
		`+{fmt(if type(income) == "number" then income else 0)} {CURRENCY}/s  ·  holds planets up to tier {if def
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
		table.insert(
			buttons,
			tagIcon(
				priceButton(actions, `Evolve: {targetDef.displayName}`, targetDef.cost, function()
					request("evolve", starId)
				end, "special"),
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

	-- Orbit slots.
	Theme.clear(list)
	local open = StarMath.slots(level)
	for slot = 1, #S.SLOTS do
		local row = Theme.row(list, 52, slot)
		local planetId = planets[slot]
		local planetDef = if planetId then P.BY_ID[planetId] else nil
		local button: TextButton
		if planetDef and planetId then
			local dot =
				Theme.planetIcon(row, Color3.fromHex(planetDef.color), 34, planetRing(planetDef))
			dot.Position = UDim2.fromOffset(8, 9)
			rowText(row, planetDef.displayName, `Orbit {slot}  ·  +{fmt(planetDef.income)}/s`, 48)
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
			local needLevel = #S.LEVELS
			for index, levelDef in S.LEVELS do
				if levelDef.slots >= slot then
					needLevel = index
					break
				end
			end
			rowText(row, `Orbit {slot}: locked`, nil, 14)
			button = Theme.button(row, `Star level {needLevel}`, "disabled", nil)
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
		Size = UDim2.new(1, -110, 0, 26),
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
	Theme.closeButton(panel, closePanel)

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

local animate: () -> ()

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
	StarFx.supernova(v.core.Position, v.core.Size.X / 2, starColor(v))
	if def then
		local best = P.BY_ID[P.ORDER[math.min(def.tier, #P.ORDER)]]
		celebrate(
			v,
			"STAR EVOLVED",
			def.displayName,
			`Tier {def.tier}  ·  now holds planets up to {best.displayName}`,
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
	buildPlanets(v)
	animate()
	if raised then
		StarFx.levelUp(v.core.Position, v.core.Size.X / 2, starColor(v))
		local def = starDef(v)
		celebrate(
			v,
			"LEVEL UP",
			`{if def then def.displayName else "Star"}  ·  level {level}`,
			`{StarMath.slots(level)} orbits open  ·  production x{StarMath.levelDef(level).incomeMultiplier}`,
			false
		)
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

local function add(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("StarId") == nil or visuals[model] then
		return
	end
	local core = model.PrimaryPart or model:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		return
	end
	local mine = isMine(model)
	local prompt = core:FindFirstChild("Manage")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = mine
	end
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
		Income = function() end,
	}
	for attribute, handler in handlers do
		table.insert(
			v.connections,
			model:GetAttributeChangedSignal(attribute):Connect(function()
				handler(v)
				refreshLabel(v)
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

animate = function()
	local now = Workspace:GetServerTimeNow()
	for _, v in visuals do
		local center = v.core.CFrame.Position
		for _, planet in v.planets do
			local slot = S.SLOTS[planet.slot]
			local angle = planet.phase + now / slot.period * 2 * math.pi
			local offset = CFrame.Angles(math.rad(slot.tilt), 0, 0)
				* Vector3.new(math.cos(angle) * slot.orbit, 0, math.sin(angle) * slot.orbit)
			planet.part.CFrame = CFrame.new(center + offset) * CFrame.Angles(0, angle, 0)
		end
	end
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
		if prompt:GetAttribute("TycoonAction") == "Manage" then
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

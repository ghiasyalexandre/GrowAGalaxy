--!strict
-- Every placed star, on this client: its planets orbiting on tilted orbits
-- (drawn as faint rings), a production label, and for your own stars the
-- Manage panel (upgrade preview, Upgrade and Move). Planets are local and
-- derived from the star's Level attribute (Logic/StarMath), so the server
-- only sends the star. Prompts on other players' stars are hidden here; the
-- server checks ownership anyway.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local PlacementController = require(script.Parent.PlacementController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local StarsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Stars"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))

local S = Config.Stars
local CURRENCY = Config.Economy.CURRENCY_NAME
local RING_COLOR = Color3.fromRGB(150, 180, 255)
-- Bezier handle length for a quarter circle of radius 1.
local QUARTER = 0.5523

type Planet = { part: Part, def: StarsConfig.PlanetDef, phase: number }

type Visual = {
	model: Model,
	core: BasePart,
	level: number,
	planets: { Planet },
	rings: { Instance },
	label: BillboardGui,
	connections: { RBXScriptConnection },
}

local StarController = {}

local visuals: { [Model]: Visual } = {}
local panel: Frame
local panelTitle: TextLabel
local panelBody: TextLabel
local upgradeButton: TextButton
local moveButton: TextButton
local panelStar: Model? = nil

local function isMine(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

-- A faint circle of `radius` around `core`, tilted `tilt` degrees, drawn
-- with four curved beams between attachments on the core.
local function ring(core: BasePart, radius: number, tilt: number): { Instance }
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
		beam.Width0 = 0.35
		beam.Width1 = 0.35
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(RING_COLOR)
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
	local typeId = v.model:GetAttribute("TypeId")
	local level = v.model:GetAttribute("Level")
	if type(typeId) ~= "string" or type(level) ~= "number" then
		return
	end
	v.level = level
	for _, index in StarMath.planetsAt(typeId, level) do
		local def = S.PLANETS[index]
		local part = Instance.new("Part")
		part.Name = `GaG_Planet_{def.name}`
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
		-- Start planets spread around their orbits, same on every client.
		table.insert(v.planets, { part = part, def = def, phase = index * 2.1 })
		for _, item in ring(v.core, def.orbit, def.tilt) do
			table.insert(v.rings, item)
		end
	end
end

local function refreshLabel(v: Visual)
	local text = v.label:FindFirstChildOfClass("TextLabel")
	local income = v.model:GetAttribute("Income")
	if text then
		text.Text = `+{if type(income) == "number" then income else 0}/s`
	end
	v.label.StudsOffsetWorldSpace = Vector3.new(0, v.core.Size.Y / 2 + 6, 0)
end

local function makeLabel(core: BasePart, mine: boolean): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "GaG_StarLabel"
	gui.Size = UDim2.fromOffset(120, 26)
	gui.LightInfluence = 0
	gui.MaxDistance = 3000
	gui.Adornee = core
	gui.Parent = core
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = if mine then Color3.fromRGB(255, 214, 120) else Color3.fromRGB(200, 205, 220)
	text.TextStrokeTransparency = 0.4
	text.Parent = gui
	return gui
end

local function refreshPanel()
	local model = panelStar
	if model == nil or model.Parent == nil then
		panel.Visible = false
		panelStar = nil
		return
	end
	local typeId = model:GetAttribute("TypeId") :: string
	local level = model:GetAttribute("Level") :: number
	local def = S.BY_ID[typeId]
	local maxLevel = StarMath.maxLevel(typeId)
	local now = StarMath.income(typeId, level)
	local cost = StarMath.upgradeCost(typeId, level)
	panelTitle.Text = `{if def then def.displayName else typeId}: level {level} / {maxLevel}`
	local lines = { `Produces {now} {CURRENCY}/s` }
	if cost then
		local nextDef = StarMath.levelDef(typeId, level + 1)
		local planet = if nextDef and nextDef.planet then S.PLANETS[nextDef.planet] else nil
		table.insert(lines, `Upgrade: {Format.abbreviate(cost)} {CURRENCY}`)
		table.insert(lines, `  {now} -> {StarMath.income(typeId, level + 1)} {CURRENCY}/s`)
		if planet then
			table.insert(lines, `  Adds the planet {planet.name}`)
		end
		local profile = ClientState.profile
		if profile and profile.stardust < cost then
			table.insert(lines, `  You need {Format.abbreviate(cost - profile.stardust)} more`)
		end
	else
		table.insert(lines, "Fully upgraded")
	end
	if ClientState.mode == "ship" and Input.device() == "keyboard" then
		table.insert(lines, "(Hold Alt to use the mouse while flying)")
	end
	panelBody.Text = table.concat(lines, "\n")
	upgradeButton.Visible = cost ~= nil
	upgradeButton.Text = "Upgrade (U)"
	moveButton.Text = "Move (M)"
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
	panel.Visible = true
	refreshPanel()
	if Input.device() == "gamepad" then
		GuiService.SelectedObject = if upgradeButton.Visible then upgradeButton else moveButton
	end
end

local function doUpgrade()
	local model = panelStar
	if model == nil then
		return
	end
	local ok, message = Net.StarRequest:InvokeServer("upgrade", model:GetAttribute("StarId"))
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Upgraded" else "Failed"
	)
	refreshPanel()
end

local function doMove()
	local model = panelStar
	if model == nil then
		return
	end
	local starId = model:GetAttribute("StarId")
	closePanel()
	if type(starId) == "string" then
		PlacementController.begin({ mode = "move", starId = starId })
	end
end

local function button(parent: Instance, name: string, x: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(x, 4, 1, -8)
	b.Size = UDim2.new(1 / 3, -8, 0, 34)
	b.BackgroundColor3 = Color3.fromRGB(40, 52, 90)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	return b
end

local function buildPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StarPanel"
	gui.ResetOnSpawn = false
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -16, 0.5, 0)
	panel.Size = UDim2.fromOffset(300, 210)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	panelTitle = Instance.new("TextLabel")
	panelTitle.Position = UDim2.fromOffset(12, 8)
	panelTitle.Size = UDim2.new(1, -24, 0, 24)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextScaled = true
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.TextColor3 = Color3.fromRGB(255, 214, 120)
	panelTitle.Parent = panel
	panelBody = Instance.new("TextLabel")
	panelBody.Position = UDim2.fromOffset(12, 38)
	panelBody.Size = UDim2.new(1, -24, 1, -88)
	panelBody.BackgroundTransparency = 1
	panelBody.Font = Enum.Font.Gotham
	panelBody.TextSize = 15
	panelBody.TextWrapped = true
	panelBody.TextXAlignment = Enum.TextXAlignment.Left
	panelBody.TextYAlignment = Enum.TextYAlignment.Top
	panelBody.TextColor3 = Color3.fromRGB(220, 225, 240)
	panelBody.Parent = panel
	upgradeButton = button(panel, "Upgrade", 0)
	moveButton = button(panel, "Move", 1 / 3)
	local close = button(panel, "Close", 2 / 3)
	close.Text = "Close"
	upgradeButton.Activated:Connect(doUpgrade)
	moveButton.Activated:Connect(doMove)
	close.Activated:Connect(closePanel)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
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
	local v: Visual = {
		model = model,
		core = core,
		level = 0,
		planets = {},
		rings = {},
		label = makeLabel(core, mine),
		connections = {},
	}
	visuals[model] = v
	buildPlanets(v)
	refreshLabel(v)
	table.insert(
		v.connections,
		model:GetAttributeChangedSignal("Level"):Connect(function()
			buildPlanets(v)
			refreshLabel(v)
			if panelStar == model then
				refreshPanel()
			end
		end)
	)
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

local function animate()
	local now = Workspace:GetServerTimeNow()
	for _, v in visuals do
		local center = v.core.CFrame.Position
		for _, planet in v.planets do
			local def = planet.def
			local angle = planet.phase + now / def.period * 2 * math.pi
			local offset = CFrame.Angles(math.rad(def.tilt), 0, 0)
				* Vector3.new(math.cos(angle) * def.orbit, 0, math.sin(angle) * def.orbit)
			planet.part.CFrame = CFrame.new(center + offset) * CFrame.Angles(0, angle, 0)
		end
	end
end

-- Stars owned by the local player: region-space positions and count, for
-- the shop price and placement checks.
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
		local action = prompt:GetAttribute("TycoonAction")
		if action == "Manage" then
			local model = prompt:FindFirstAncestorOfClass("Model")
			if model and isMine(model) then
				openPanel(model)
			end
		elseif action == "Shop" then
			-- The station sits inside its owner's region model.
			local owner: Instance? = prompt:FindFirstAncestorOfClass("Model")
			while owner and owner:GetAttribute("OwnerUserId") == nil do
				owner = owner:FindFirstAncestorOfClass("Model")
			end
			if owner and owner:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
				ClientState.notify:Fire("This is someone else's Star Shop.")
				return
			end
			PlacementController.begin({ mode = "place", typeId = S.DEFAULT_TYPE })
		end
	end)

	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed or panelStar == nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.U then
			doUpgrade()
		elseif input.KeyCode == Enum.KeyCode.M then
			doMove()
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			closePanel()
		end
	end)
end

return StarController

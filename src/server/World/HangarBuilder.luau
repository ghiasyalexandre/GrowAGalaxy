--!strict
-- Hangar upgrade geometry (Config.Hangar), built on a station deck by
-- HangarSystem. Two forms per upgrade, both standing on the floor point
-- `floor` (station space, so -Z faces the berth):
--   pad(def, floor)        a glowing red ground circle with a sign above it
--                          (name, what it does, cost) and a "Build" prompt.
--                          The circle part is named "Circle".
--   structure(def, floor)  the finished building, with a small name plate
--                          (none for one built at its `site`, off its pad).
-- Both return a Model; the caller parents it.
--
-- A building's look, best first:
--   1. its Blender mesh model (tools/hangar_meshes), imported into Studio and
--      saved under ServerStorage/Assets/Hangar (assets/roblox/Hangar). Parts
--      are named Role__RRGGBB__Material and carry markers; see meshBuilding.
--      Roles starting "Accent" take the station's highlight colour (Settings).
--   2. its voxel design (HangarVoxels, tools/hangar_voxels), until the mesh
--      has been imported.
-- Either way it's then dressed with lights, smoke, sparks and spinning parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Build = require(script.Parent.Build)
local HangarConfig = require(ReplicatedStorage.Shared.Config.Hangar)
local HangarVoxels = require(script.Parent.HangarVoxels)
local MeshAsset = require(script.Parent.MeshAsset)

local COLORS = Config.World.COLORS
local H = Config.Hangar

type HangarDef = HangarConfig.HangarDef

local HangarBuilder = {}

local light = MeshAsset.light
local spin = MeshAsset.spin
local pulse = MeshAsset.pulse
local emit = MeshAsset.emit
local skyBeam = MeshAsset.skyBeam
local SMOKE, STEAM, SPARKS = MeshAsset.SMOKE, MeshAsset.STEAM, MeshAsset.SPARKS

local function flat(
	name: string,
	radius: number,
	height: number,
	floor: CFrame,
	color: string,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, radius * 2, radius * 2),
		cframe = floor * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
end

-- An upright cylinder of `height` standing on `floor`.
local function column(
	name: string,
	diameter: number,
	height: number,
	floor: CFrame,
	color: string,
	material: Enum.Material?,
	parent: Instance
): Part
	return Build.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = floor * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material or Enum.Material.Metal,
		parent = parent,
	})
end

local function box(
	name: string,
	size: Vector3,
	where: CFrame,
	color: string,
	material: Enum.Material?,
	parent: Instance
): Part
	return Build.part({
		name = name,
		size = size,
		cframe = where,
		color = color,
		material = material or Enum.Material.Metal,
		parent = parent,
	})
end

local function textLine(
	parent: Instance,
	text: string,
	y: number,
	height: number,
	size: number,
	color: Color3,
	font: Enum.Font
)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.Font = font
	label.TextWrapped = true
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
end

function HangarBuilder.pad(def: HangarDef, floor: CFrame): Model
	local model = Instance.new("Model")
	model.Name = def.id
	local radius = H.PAD_RADIUS

	-- Outer glowing ring, dark inner disc, bright centre dot.
	local circle = flat("Circle", radius, 0.25, floor, H.PAD_COLOR, model)
	circle.Transparency = 0.1
	circle.CanTouch = true
	circle.CanCollide = false
	local inner = flat("Inner", radius - 0.7, 0.3, floor, "#4A0C0C", model)
	inner.Material = Enum.Material.SmoothPlastic
	flat("Dot", 0.9, 0.35, floor, "#FFB0A0", model)
	light(circle, H.PAD_COLOR, 12)
	local padLight = circle:FindFirstChildOfClass("PointLight")
	if padLight then
		padLight.Brightness *= H.PAD_LIGHT_SCALE
		padLight.Range *= math.sqrt(H.PAD_LIGHT_SCALE)
	end

	-- The sign: name, what it does, price.
	local anchor = Build.marker("SignAnchor", floor * CFrame.new(0, 6, 0), model)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(240, 96)
	sign.LightInfluence = 0
	sign.MaxDistance = H.SIGN_DISTANCE
	sign.Adornee = anchor
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
	panel.BackgroundTransparency = 0.2
	panel.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(H.PAD_COLOR)
	stroke.Thickness = 2
	stroke.Parent = panel
	textLine(
		panel,
		def.displayName,
		6,
		24,
		20,
		Color3.fromRGB(255, 214, 110),
		Enum.Font.GothamBlack
	)
	textLine(panel, def.effect, 32, 32, 14, Color3.fromRGB(235, 240, 255), Enum.Font.GothamBold)
	-- Vanity is priced in minutes of the owner's production (HangarMath.price).
	local price = if def.minutes
		then `{def.minutes} min of production (at least {Format.abbreviate(def.cost)})`
		else `{Format.abbreviate(def.cost)} {Config.Economy.CURRENCY_NAME}`
	textLine(
		panel,
		`{price}  ·  step on to build`,
		68,
		22,
		14,
		Color3.fromHex(H.PAD_COLOR):Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Font.GothamBold
	)
	sign.Parent = anchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuildPrompt"
	prompt.ActionText = if def.minutes
		then `Build ({def.minutes} min)`
		else `Build ({Format.abbreviate(def.cost)})`
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = circle

	model:SetAttribute("State", "pad")
	model:SetAttribute("UpgradeId", def.id)
	Build.dimEmissive(model, Config.World.EMISSIVE_DIM)
	return model
end

-- Builds a voxel design's boxes on `floor`. Parts of a palette entry with a
-- group go into a child Model of that name (pivoted on its centre, so it can
-- spin). Returns the groups by name.
local function voxels(
	model: Model,
	floor: CFrame,
	design: HangarVoxels.VoxelModel
): { [string]: Model }
	local groups: { [string]: Model } = {}
	-- Each group's extent in floor space, for its pivot.
	local lows: { [string]: Vector3 } = {}
	local highs: { [string]: Vector3 } = {}
	for _, cell in design.boxes do
		local entry = design.palette[cell[7]]
		local corner = Vector3.new(cell[1], cell[2], cell[3])
		local size = Vector3.new(cell[4], cell[5], cell[6])
		local parent: Instance = model
		local groupName = entry.group
		if groupName then
			local group = groups[groupName]
			if not group then
				local made = Instance.new("Model")
				made.Name = groupName
				made.Parent = model
				groups[groupName] = made
				lows[groupName] = corner
				highs[groupName] = corner + size
				group = made
			end
			lows[groupName] = lows[groupName]:Min(corner)
			highs[groupName] = highs[groupName]:Max(corner + size)
			parent = group :: Model
		end
		local part = Build.part({
			name = entry.name,
			size = size,
			cframe = floor * CFrame.new(corner + size / 2),
			color = entry.color,
			material = (Enum.Material :: any)[entry.material],
			transparency = entry.transparency,
			collide = entry.collide,
			parent = parent,
		})
		if entry.pulse then
			pulse(part, entry.pulse[1], entry.pulse[2])
		end
	end
	for name, group in groups do
		group.WorldPivot = floor * CFrame.new((lows[name] + highs[name]) / 2)
	end
	return groups
end

-- The first part named `name` anywhere in the model.
local function find(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local showcaseExtras: (model: Model, floor: CFrame) -> ()

-- Dressing for the voxel designs: what voxels can't hold (lights, smoke,
-- steam, sparks, spinning groups, the spire's sky beam, the dock's cradles).
-- Parts are found by their palette names (tools/hangar_voxels/models).
local dressers: { [string]: (Model, { [string]: Model }, CFrame) -> () } = {}

-- A white silo with a Stardust gauge, a chute and hopper, a control booth
-- and a turning gold star on top.
dressers.StardustSilo = function(model, groups)
	local core = find(model, "Core")
	if core then
		light(core, "#FFD36B", 14)
	end
	if groups.TopStar then
		spin(groups.TopStar, 0.8)
	end
end

-- Stacked fuel tanks, a pump and jerry cans, under a pulsing boost arrow.
dressers.FuelDepot = function(model)
	local screen = find(model, "Valve")
	if screen then
		light(screen, "#7FD4FF", 10)
	end
	local arrow = find(model, "BoostArrow")
	if arrow then
		light(arrow, "#5FE3FF", 16)
	end
end

-- A factory hall: smoking chimney, roof fan, glowing furnace and output.
dressers.Refinery = function(model, groups)
	local chimney = find(model, "ChimneyGlow")
	if chimney then
		emit(chimney, SMOKE)
		light(chimney, "#FFB347", 12)
	end
	local furnace = find(model, "Furnace")
	if furnace then
		light(furnace, "#FF9A2E", 12)
	end
	local output = find(model, "Output")
	if output then
		light(output, "#FFC94A", 8)
	end
	if groups.Fan then
		spin(groups.Fan, 1.6)
	end
end

-- A cooling tower: steam off its coolant pool, a fan turning over it.
dressers.CoolingTower = function(model, groups)
	local pool = find(model, "Vent")
	if pool then
		emit(pool, STEAM)
		light(pool, "#5FE3FF", 14)
	end
	if groups.Fan then
		spin(groups.Fan, 2)
	end
end

-- A lab and a mining laser beaming into a turning asteroid.
dressers.MiningLab = function(model, groups)
	local tip = find(model, "LaserTip")
	if tip then
		light(tip, "#FF6A3D", 12)
	end
	local crystal = find(model, "Crystal")
	if crystal then
		light(crystal, "#B06BFF", 12)
	end
	if groups.Asteroid then
		spin(groups.Asteroid, 0.25)
	end
end

-- An open garage: a robot arm welding armour onto a hull (sparks fly).
dressers.ArmorWorkshop = function(model)
	local torch = find(model, "Torch")
	if torch then
		emit(torch, SPARKS)
		light(torch, "#FFC870", 10)
	end
	local strip = find(model, "RoofStrip")
	if strip then
		light(strip, "#FFB347", 12)
	end
	local shield = find(model, "Shield")
	if shield then
		light(shield, "#3FB6FF", 14)
	end
end

-- Vanity -------------------------------------------------------------------

-- A voxel galaxy turning over the deck, beamed up from a projector.
dressers.HoloGalaxy = function(model, groups)
	local core = find(model, "Core")
	if core then
		light(core, "#B06BFF", 24)
	end
	if groups.Hologram then
		spin(groups.Hologram, 0.35)
	end
end

-- A stepped tower with turning rings and a trophy holding the beacon, which
-- shoots a beam of light into the sky.
dressers.VictorySpire = function(model, groups)
	for index, speed in { 0.4, -0.5, 0.4 } do
		local ring = groups[`Ring{index}`]
		if ring then
			spin(ring, speed)
		end
	end
	local beacon = find(model, "Beacon")
	if beacon then
		light(beacon, "#FFD36B", 60)
		skyBeam(beacon)
	end
end

-- A platform off the deck's side and its cradles (showcaseExtras).
dressers.ShowcaseDock = function(model, _groups, floor)
	showcaseExtras(model, floor)
	local lamp = find(model, "TowerLamp")
	if lamp then
		light(lamp, "#FFF4D6", 30)
	end
end

-- The dock's three cradles. The cradles stay round parts built
-- here (not mesh or voxels): HangarSystem puts the player's chosen ships on
-- them ("Cradle1".."Cradle3"; their tops are where a ship's bottom sits) and
-- relies on their shape and orientation.
showcaseExtras = function(model: Model, floor: CFrame)
	for index, z in { -21, 0, 21 } do
		local cradle = column(
			`Cradle{index}`,
			12,
			1,
			floor * CFrame.new(0, 0, z),
			COLORS.hullAlt,
			Enum.Material.Metal,
			model
		)
		cradle.Name = `Cradle{index}`
		local rim = flat("CradleGlow", 6.4, 0.2, floor * CFrame.new(0, 1, z), "#FFFFFF", model)
		pulse(rim, 0.1, 0.6)
		light(rim, "#FFFFFF", 22)
	end
end

function HangarBuilder.structure(def: HangarDef, floor: CFrame): Model
	local model = Instance.new("Model")
	model.Name = def.id
	local site = def.site
	if site and site.y then
		model:SetAttribute("SiteHeight", site.y)
	end
	local source = MeshAsset.source(def.id)
	local design = HangarVoxels[def.id]
	if source and MeshAsset.place(source, floor, model) then
		if def.id == "ShowcaseDock" then
			showcaseExtras(model, floor)
		end
		model:SetAttribute("Mesh", true)
	elseif design then
		local groups = voxels(model, floor, design)
		local dress = dressers[def.id]
		if dress then
			dress(model, groups, floor)
		end
	else
		box(
			"Building",
			Vector3.new(8, 5, 8),
			floor * CFrame.new(0, 2.5, 0),
			COLORS.hullAlt,
			nil,
			model
		)
	end
	model:SetAttribute("State", "built")
	model:SetAttribute("UpgradeId", def.id)
	if model:GetAttribute("Mesh") then
		-- Softer lights on mesh buildings (Config.Hangar.MESH_LIGHT_SCALE).
		for _, item in model:GetDescendants() do
			if item:IsA("PointLight") or item:IsA("SpotLight") then
				item.Brightness *= H.MESH_LIGHT_SCALE
				item.Range *= math.sqrt(H.MESH_LIGHT_SCALE)
			end
		end
	end
	-- Mesh buildings glow less: their accents are meant to be subtle.
	local dim = if model:GetAttribute("Mesh") then H.MESH_GLOW_DIM else Config.World.EMISSIVE_DIM
	if site then
		-- Built away from its pad: no name plate on the deck.
		Build.dimEmissive(model, dim)
		return model
	end
	-- Name plate at the front edge, facing the deck's centre line.
	local plate = Build.sign({
		name = "Plate",
		text = `{def.displayName}\n{def.effect}`,
		size = Vector3.new(7, 1.6, 0.3),
		cframe = floor * CFrame.new(0, 0.8, -6.2),
		faces = { Enum.NormalId.Front },
		parent = model,
		textColor = "#FFD36B",
	})
	plate.CanCollide = false
	Build.dimEmissive(model, dim)
	return model
end

return HangarBuilder

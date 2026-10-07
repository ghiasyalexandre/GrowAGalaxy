--!strict
-- A player's personal hangar station, floating just in front of their
-- region's near face. Station space: -Z faces into the region, +Z faces back
-- towards the ISS; x is right as you walk from the spawn towards the berth.
--
-- A hangar deck under three lit truss arches, with half walls and windows,
-- lane lights from the spawn to the gangway, crates, the hub tower and
-- beacon at the back, the Stardust Collector and Galaxy Control beside it
-- (launching, the Star Shop and the Shipyard are HUD buttons). The ship berth and its
-- docking zone sit off the -Z edge. Hangar upgrades (HangarSystem) are built
-- on the deck at Config.Hangar pads, inside the "Hangar" model.
--
-- Highlight colour: the glowing strips, back rail, beacon and name signs use
-- the region's colour, or the owner's pick (recolor, Config.Hangar
-- HIGHLIGHT_COLORS); they carry the attribute GaG_Accent.
--
-- Incubator Bay: an annex off the left side (-X), through a doorway in the
-- left wall, holding Config.Eggs.HATCH_SLOTS incubator chambers in a row
-- ("Incubator" model, parts "Chamber1".., tagged "GaG_Incubator" with
-- Chamber and OwnerUserId attributes). Each chamber's base has an
-- "Incubate" prompt (attribute HatchChamber). HatchSystem writes each
-- chamber's state into its attributes; clients draw the eggs, progress and
-- reveals from them (HatchController).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local DeviceBuilder = require(script.Parent.DeviceBuilder)

local COLORS = Config.World.COLORS
local WIDTH = 64 -- deck, x
local LENGTH = 72 -- deck, z
local FLOOR_Y = -5
local WALL_HEIGHT = 7
local ARCH_HEIGHT = 18
local BERTH_PAD = 20
local BERTH_Z = LENGTH / 2 + 4 + BERTH_PAD / 2 -- berth centre, along -Z
local BERTH_Z_NEAR = BERTH_Z - BERTH_PAD / 2
local PANEL_DARK = "#252A36"
-- The doorway to the Incubator Bay in the left wall, between the hangar pads
-- at z -20 and -4 (Config.Hangar PAD_RADIUS 4), and the bay itself.
local DOOR_FROM, DOOR_TO = -16, -8
local BAY_WIDTH = 24 -- x, beyond the left wall
local BAY_FROM, BAY_TO = -30, 6 -- z
local INCUBATOR_TAG = "GaG_Incubator"
-- Parts and labels in the station's highlight colour (recolor() changes them).
local ACCENT = "GaG_Accent"

local StationBuilder = {}

export type Station = {
	model: Model,
	spawn: CFrame,
	berth: CFrame, -- where the owner's ship parks, facing out
	dockZone: BasePart,
	floor: CFrame, -- deck centre at floor level (station space origin)
}

function StationBuilder.build(
	region: Model,
	origin: CFrame,
	ownerName: string,
	ownerUserId: number,
	color: string
): Station
	local station = Build.model("Station", region)
	local cf = origin
		* CFrame.new(0, 0, -Config.World.STATION_DISTANCE)
		* CFrame.Angles(0, math.pi, 0)

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	local function neon(name: string, size: Vector3, where: CFrame, tint: string?)
		local part = Build.part({
			name = name,
			size = size,
			cframe = where,
			color = tint or color,
			material = Enum.Material.Neon,
			collide = false,
			parent = station,
		})
		if tint == nil then
			part:SetAttribute(ACCENT, true)
		end
	end

	-- Deck: a plated slab with darker inset panels and a docking ring below.
	Build.part({
		name = "Deck",
		size = Vector3.new(WIDTH, 2, LENGTH),
		cframe = at(0, FLOOR_Y - 1, 0),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	for _, x in { -20, 20 } do
		for _, z in { -20, -4, 12 } do
			Build.part({
				name = "Panel",
				size = Vector3.new(14, 0.1, 14),
				cframe = at(x, FLOOR_Y + 0.02, z),
				color = PANEL_DARK,
				material = Enum.Material.Metal,
				collide = false,
				parent = station,
			})
		end
	end
	Build.part({
		name = "DockingRing",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3, LENGTH + 8, LENGTH + 8),
		cframe = at(0, FLOOR_Y - 3.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hullAlt,
		parent = station,
	})

	-- Half walls down both sides with a window band and a glowing top trim;
	-- a rail across the back. The front stays open towards the berth.
	-- A run of half wall from z0 to z1, with its window band and top trim.
	local function wallRun(x: number, z0: number, z1: number, windowFrom: number, windowTo: number)
		local length, middle = z1 - z0, (z0 + z1) / 2
		Build.part({
			name = "Wall",
			size = Vector3.new(1, WALL_HEIGHT, length),
			cframe = at(x, FLOOR_Y + WALL_HEIGHT / 2, middle),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = station,
		})
		Build.part({
			name = "Window",
			size = Vector3.new(1.2, 2.2, windowTo - windowFrom),
			cframe = at(x, FLOOR_Y + 4.2, (windowFrom + windowTo) / 2),
			color = COLORS.glass,
			material = Enum.Material.Glass,
			transparency = 0.35,
			parent = station,
		})
		neon("WallTrim", Vector3.new(1.4, 0.4, length), at(x, FLOOR_Y + WALL_HEIGHT, middle))
	end
	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.5)
		local half = LENGTH / 2
		if side < 0 then
			-- The left wall has the doorway to the Incubator Bay.
			wallRun(x, -half, DOOR_FROM, -half + 4, DOOR_FROM - 2)
			wallRun(x, DOOR_TO, half, DOOR_TO + 2, half - 4)
		else
			wallRun(x, -half, half, -half + 4, half - 4)
		end
		neon(
			"FloorStrip",
			Vector3.new(0.5, 0.15, LENGTH - 4),
			at(side * (WIDTH / 2 - 2), FLOOR_Y + 0.08, 0)
		)
	end

	-- Incubator Bay: a floor beyond the doorway, a low rail round its edge,
	-- and the incubator chambers in a row along the far side.
	local bayX = -WIDTH / 2 - BAY_WIDTH / 2
	local bayLength = BAY_TO - BAY_FROM
	local bayMiddle = (BAY_FROM + BAY_TO) / 2
	Build.part({
		name = "BayFloor",
		size = Vector3.new(BAY_WIDTH, 2, bayLength),
		cframe = at(bayX, FLOOR_Y - 1, bayMiddle),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	Build.part({
		name = "BayRail",
		size = Vector3.new(0.6, 3, bayLength),
		cframe = at(-WIDTH / 2 - BAY_WIDTH + 0.3, FLOOR_Y + 1.5, bayMiddle),
		color = COLORS.hullAlt,
		material = Enum.Material.Metal,
		parent = station,
	})
	for _, z in { BAY_FROM + 0.3, BAY_TO - 0.3 } do
		Build.part({
			name = "BayRail",
			size = Vector3.new(BAY_WIDTH, 3, 0.6),
			cframe = at(bayX, FLOOR_Y + 1.5, z),
			color = COLORS.hullAlt,
			material = Enum.Material.Metal,
			parent = station,
		})
	end
	local incubator = Build.model("Incubator", station)
	local chambers = Config.Eggs.HATCH_SLOTS
	local spacing = (bayLength - 8) / math.max(chambers - 1, 1)
	for index = 1, chambers do
		local z = BAY_FROM + 4 + (index - 1) * spacing
		local base = Build.part({
			name = `Chamber{index}`,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1.4, 5, 5),
			cframe = at(bayX - 4, FLOOR_Y + 0.7, z) * CFrame.Angles(0, 0, math.pi / 2),
			color = PANEL_DARK,
			material = Enum.Material.Metal,
			parent = incubator,
		})
		base:SetAttribute("Chamber", index)
		base:SetAttribute("OwnerUserId", ownerUserId)
		CollectionService:AddTag(base, INCUBATOR_TAG)
		local dome = Build.part({
			name = "Dome",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 4.6,
			cframe = at(bayX - 4, FLOOR_Y + 1.4 + 2.1, z),
			color = COLORS.glass,
			material = Enum.Material.Glass,
			transparency = 0.7,
			collide = false,
			parent = base,
		})
		dome.CanQuery = false
		local prompt =
			Build.prompt(base, { action = "Incubate an egg", object = `Chamber {index}` })
		prompt.Name = "Incubate"
		prompt.MaxActivationDistance = 10
		prompt:SetAttribute("HatchChamber", index)
	end
	Build.part({
		name = "Rail",
		size = Vector3.new(WIDTH, 3, 0.6),
		cframe = at(0, FLOOR_Y + 1.5, LENGTH / 2),
		color = color,
		parent = station,
	}):SetAttribute(ACCENT, true)

	-- Truss arches overhead, each with a light panel underneath.
	for _, z in { -26, -4, 18 } do
		for _, side in { -1, 1 } do
			Build.part({
				name = "ArchPillar",
				size = Vector3.new(1.6, ARCH_HEIGHT, 1.6),
				cframe = at(side * (WIDTH / 2 - 1), FLOOR_Y + ARCH_HEIGHT / 2, z),
				color = COLORS.truss,
				material = Enum.Material.Metal,
				parent = station,
			})
		end
		Build.part({
			name = "ArchBeam",
			size = Vector3.new(WIDTH, 1.6, 1.6),
			cframe = at(0, FLOOR_Y + ARCH_HEIGHT, z),
			color = COLORS.truss,
			material = Enum.Material.Metal,
			parent = station,
		})
		local panel = Build.part({
			name = "LightPanel",
			size = Vector3.new(WIDTH - 12, 0.3, 1.2),
			cframe = at(0, FLOOR_Y + ARCH_HEIGHT - 1, z),
			color = "#E8F4FF",
			material = Enum.Material.Neon,
			collide = false,
			parent = station,
		})
		local light = Instance.new("PointLight")
		light.Range = 40
		light.Brightness = 1.4
		light.Color = Color3.fromHex("#DCEBFF")
		light.Shadows = false
		light.Parent = panel
	end

	-- Lane from the spawn to the gangway, lit at its edges.
	for _, side in { -1, 1 } do
		neon(
			"LaneStripe",
			Vector3.new(0.4, 0.15, LENGTH / 2 + 6),
			at(side * 4, FLOOR_Y + 0.08, -LENGTH / 4 - 3),
			COLORS.accent
		)
	end
	for z = -LENGTH / 2 + 3, 0, 6 do
		for _, side in { -1, 1 } do
			neon(
				"LaneLight",
				Vector3.new(0.8, 0.4, 0.8),
				at(side * 5.5, FLOOR_Y + 0.2, z),
				COLORS.accent
			)
		end
	end

	-- Crates and barrels by the back corners.
	for _, crate in
		{
			{ x = -27, z = 30, s = 4, y = 0 },
			{ x = -28, z = 24, s = 3.2, y = 0 },
			{ x = -26.5, z = 30.2, s = 2.6, y = 4 },
			{ x = 26, z = 30, s = 4, y = 0 },
			{ x = 28, z = 24.5, s = 3, y = 0 },
		}
	do
		Build.part({
			name = "Crate",
			size = Vector3.one * crate.s,
			cframe = at(crate.x, FLOOR_Y + crate.y + crate.s / 2, crate.z)
				* CFrame.Angles(0, math.rad(crate.x * 7), 0),
			color = "#6E5A3F",
			material = Enum.Material.WoodPlanks,
			parent = station,
		})
	end
	for _, x in { -14, -11.5, 12, 14.5 } do
		Build.part({
			name = "Barrel",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(3, 2, 2),
			cframe = at(x, FLOOR_Y + 1.5, 31) * CFrame.Angles(0, 0, math.pi / 2),
			color = "#C9622F",
			material = Enum.Material.Metal,
			parent = station,
		})
	end

	-- Hub tower at the back, with a beacon visible from the ISS.
	Build.part({
		name = "Hub",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(18, 16, 16),
		cframe = at(0, FLOOR_Y + 9, 26) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hull,
		parent = station,
	})
	neon(
		"HubRing",
		Vector3.new(0.6, 16.6, 16.6),
		at(0, FLOOR_Y + 14, 26) * CFrame.Angles(0, 0, math.pi / 2)
	)
	Build.part({
		name = "BeaconMast",
		size = Vector3.new(1, 20, 1),
		cframe = at(0, FLOOR_Y + 28, 26),
		color = COLORS.truss,
		parent = station,
	})
	local beacon = Build.part({
		name = "Beacon",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 5,
		cframe = at(0, FLOOR_Y + 40, 26),
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = station,
	})
	beacon:SetAttribute(ACCENT, true)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerTag"
	billboard.Size = UDim2.fromOffset(260, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.LightInfluence = 0
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.Text = `{ownerName}'s Galaxy`
	tag.TextScaled = true
	tag.Font = Enum.Font.GothamBold
	tag.TextColor3 = Color3.fromHex(color)
	tag:SetAttribute(ACCENT, true)
	tag.TextStrokeTransparency = 0.4
	tag.Parent = billboard
	billboard.Parent = beacon

	local nameSign = Build.sign({
		name = "NameSign",
		text = `{ownerName}'s Hangar`,
		size = Vector3.new(16, 3, 0.4),
		cframe = at(0, FLOOR_Y + 13, 17.6),
		faces = { Enum.NormalId.Front },
		parent = station,
		textColor = color,
	})
	for _, item in nameSign:GetDescendants() do
		if item:IsA("TextLabel") then
			item:SetAttribute(ACCENT, true)
		end
	end

	-- Galaxy Control, beside Collect: manage every solar system and buy a
	-- bigger galaxy (GalaxyController; prompt attribute OpenPanel = "Galaxy").
	local control = DeviceBuilder.galaxyControl(at(-9, FLOOR_Y, 10), station)
	local controlPrompt =
		Build.prompt(control, { action = "Open Galaxy Control", object = "Galaxy Control" })
	controlPrompt:SetAttribute("OpenPanel", "Galaxy")

	-- The Stardust Collector, facing the spawn (DeviceBuilder).
	local collect = DeviceBuilder.collector(at(0, FLOOR_Y, 10), station)
	Build.prompt(collect, { action = "Collect Stardust", object = "Collector", tycoon = "Collect" })

	-- Berth pad off the -Z edge, joined by a gangway lined with landing
	-- lights. The ship parks above it facing into the region. The docking
	-- zone covers the berth, the approach and the front of the deck.
	Build.part({
		name = "Gangway",
		size = Vector3.new(8, 1, BERTH_Z_NEAR - LENGTH / 2),
		cframe = at(0, FLOOR_Y - 0.5, -(LENGTH / 2 + BERTH_Z_NEAR) / 2),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	for z = LENGTH / 2 + 1, BERTH_Z_NEAR - 1, 2 do
		for _, side in { -1, 1 } do
			neon(
				"LandingLight",
				Vector3.new(0.6, 0.6, 0.6),
				at(side * 4.5, FLOOR_Y + 0.2, -z),
				"#FF5A3D"
			)
		end
	end
	Build.part({
		name = "DockPad",
		size = Vector3.new(BERTH_PAD, 2, BERTH_PAD),
		cframe = at(0, FLOOR_Y - 1, -BERTH_Z),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	Build.dockOutline(at(0, FLOOR_Y + 0.1, -BERTH_Z), 16, station)
	local berth = at(0, FLOOR_Y + 6, -BERTH_Z)
	Build.marker("StationDock", berth, station)
	local dockZone = Build.dockZone(
		at(0, FLOOR_Y + 9, -BERTH_Z - 13),
		Vector3.new(60, 36, 70),
		ownerUserId,
		station
	)

	local spawn = at(0, FLOOR_Y + 3, -2)
	Build.marker("StationSpawn", spawn, station)

	Build.dimEmissive(station, Config.World.EMISSIVE_DIM)
	return {
		model = station,
		spawn = spawn,
		berth = berth,
		dockZone = dockZone,
		floor = at(0, FLOOR_Y, 0),
	}
end

-- Changes the station's highlight colour (Config.Hangar.HIGHLIGHT_COLORS or
-- the region's): every piece built in it, glowing ones dimmed like the rest
-- (Config.World.EMISSIVE_DIM).
function StationBuilder.recolor(station: Model, hex: string)
	local base = Color3.fromHex(hex)
	local keep = 1 - Config.World.EMISSIVE_DIM
	local dimmed = Color3.new(base.R * keep, base.G * keep, base.B * keep)
	for _, item in station:GetDescendants() do
		if item:GetAttribute(ACCENT) ~= true then
			continue
		end
		if item:IsA("BasePart") then
			item.Color = if item.Material == Enum.Material.Neon then dimmed else base
		elseif item:IsA("TextLabel") then
			item.TextColor3 = base
		end
	end
end

return StationBuilder

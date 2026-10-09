--!strict
-- A player's personal hangar station, floating just in front of their
-- region's near face. Station space: -Z faces into the region, +Z faces back
-- towards the ISS; x is right as you walk from the spawn towards the berth.
--
-- An enclosed sci-fi hangar: a plated deck under five truss arches and a
-- glass roof, open sides onto the Incubator Bay and Showcase Dock,
-- a hazard-striped front portal with the owner's name and a faint force
-- field, chevrons down the lane to the berth, lockers and a
-- gantry crane, the control tower (ops windows, radar dish, beacon) at the
-- back, and the Stardust Collector, Galaxy Control and Planet Egg Lab
-- (launching, the Star Shop and the Shipyard are HUD buttons). The ship berth and its
-- docking zone sit off the -Z edge. Hangar upgrades (HangarSystem) are built
-- on the deck at Config.Hangar pads, inside the "Hangar" model.
--
-- Highlight colour: the glowing strips, back rail, beacon and name signs use
-- the region's colour, or the owner's pick (recolor, Config.Hangar
-- HIGHLIGHT_COLORS); they carry the attribute GaG_Accent.
--
-- Incubator Bay: an annex open to the left side (-X), holding Config.Eggs.HATCH_SLOTS incubator chambers in a row
-- ("Incubator" model, parts "Chamber1".., tagged "GaG_Incubator" with
-- Chamber and OwnerUserId attributes). Each chamber's base has an
-- "Incubate" prompt (attribute HatchChamber). HatchSystem writes each
-- chamber's state into its attributes; clients draw the eggs, progress and
-- reveals from them (HatchController). The owner's Planet Egg Lab ("EggLab"
-- model, DeviceBuilder.eggLab), where eggs are rolled, stands left of the
-- Stardust Collector.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local DeviceBuilder = require(script.Parent.DeviceBuilder)
local MeshAsset = require(script.Parent.MeshAsset)

local COLORS = Config.World.COLORS
local WIDTH = 64 -- deck, x
local LENGTH = 72 -- deck, z
local FLOOR_Y = -5
local ARCH_HEIGHT = 18
-- Arch positions along the deck.
local ARCH_Z = { -30, -18, -2, 14, 30 }
local TOWER_Z = 28 -- the control tower's centre, at the back
local BERTH_PAD = 20
local BERTH_Z = LENGTH / 2 + 4 + BERTH_PAD / 2 -- berth centre, along -Z
local BERTH_Z_NEAR = BERTH_Z - BERTH_PAD / 2
local PANEL_DARK = "#252A36"
-- The Incubator Bay, open to the deck's left side.
local BAY_WIDTH = 24 -- x, beyond the left wall
local BAY_FROM, BAY_TO = -30, 6 -- z
local INCUBATOR_TAG = "GaG_Incubator"
-- The Showcase Dock's platform (tools/hangar_meshes ShowcaseDock: 30 x 66).
local DOCK_PLATFORM_WIDTH = 30
local DOCK_LENGTH = 66
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
		for _, z in { -8, 8, 24 } do
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

	-- No side walls: the deck opens onto the Incubator Bay on the left and
	-- the Showcase Dock on the right; a rail runs across the back.
	for _, side in { -1, 1 } do
		neon(
			"FloorStrip",
			Vector3.new(0.5, 0.15, LENGTH - 4),
			at(side * (WIDTH / 2 - 2), FLOOR_Y + 0.08, 0)
		)
	end

	-- A glass roof resting on the arches: you can still see the galaxy
	-- through it.
	Build.part({
		name = "GlassRoof",
		size = Vector3.new(WIDTH, 0.4, LENGTH),
		cframe = at(0, FLOOR_Y + ARCH_HEIGHT + 1, 0),
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.82,
		parent = station,
	})

	-- Showcase Dock walkway: a floor flush with the deck from its right edge
	-- to the dock's platform (Config.Hangar ShowcaseDock site, a platform
	-- DOCK_PLATFORM_WIDTH wide and DOCK_LENGTH long), so the dock reads as part
	-- of the hangar like the Incubator Bay. A glowing seam marks the join.
	local dockDef = Config.Hangar.BY_ID.ShowcaseDock
	local dockSite = dockDef and dockDef.site
	if dockSite then
		local from = WIDTH / 2
		local to = dockSite.x - DOCK_PLATFORM_WIDTH / 2 + 1 -- overlaps the platform a little
		Build.part({
			name = "DockFloor",
			size = Vector3.new(to - from, 2, DOCK_LENGTH),
			cframe = at((from + to) / 2, FLOOR_Y - 1, dockSite.z),
			color = COLORS.deck,
			material = Enum.Material.DiamondPlate,
			parent = station,
		})
		neon(
			"DockSeam",
			Vector3.new(0.4, 0.15, DOCK_LENGTH - 4),
			at(dockSite.x - DOCK_PLATFORM_WIDTH / 2, FLOOR_Y + 0.08, dockSite.z)
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
	local chamberMesh = MeshAsset.source("IncubatorChamber")
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
		-- With the imported mesh (tools/hangar_meshes, IncubatorChamber),
		-- the base stays as an invisible collider carrying the attributes
		-- and prompt; the mesh faces the deck (+x).
		local meshed = false
		if chamberMesh then
			local look = Build.model(`ChamberMesh{index}`, incubator)
			meshed = MeshAsset.place(
				chamberMesh,
				at(bayX - 4, FLOOR_Y, z) * CFrame.Angles(0, -math.pi / 2, 0),
				look
			)
			if meshed then
				base.Transparency = 1
			else
				look:Destroy()
			end
		end
		base:SetAttribute("Chamber", index)
		base:SetAttribute("OwnerUserId", ownerUserId)
		CollectionService:AddTag(base, INCUBATOR_TAG)
		local dome = if meshed
			then nil
			else Build.part({
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
		if dome then
			dome.CanQuery = false
		end
		-- Detail (all welded to nothing: anchored, children of the base): a
		-- glowing floor ring and the cap light (HatchController tints them
		-- the hatching egg's rarity colour), a seal collar between base and
		-- dome, the egg's cradle, the heater cap on top and a coolant pipe
		-- up the back.
		local cx = bayX - 4
		local function piece(
			name: string,
			size: Vector3,
			y: number,
			tint: string,
			material: Enum.Material
		)
			local made = Build.part({
				name = name,
				shape = Enum.PartType.Cylinder,
				size = size,
				cframe = at(cx, y, z) * CFrame.Angles(0, 0, math.pi / 2),
				color = tint,
				material = material,
				collide = false,
				parent = base,
			})
			made.CanQuery = false
			return made
		end
		piece(
			"ChamberRing",
			Vector3.new(0.2, 5.6, 5.6),
			FLOOR_Y + 0.1,
			"#FF6EC8",
			Enum.Material.Neon
		)
		if not meshed then
			piece(
				"SealCollar",
				Vector3.new(0.35, 5, 5),
				FLOOR_Y + 1.55,
				"#C9CED9",
				Enum.Material.Metal
			)
			piece(
				"Cradle",
				Vector3.new(0.5, 1.7, 1.7),
				FLOOR_Y + 1.75,
				PANEL_DARK,
				Enum.Material.Metal
			)
			piece(
				"HeaterCap",
				Vector3.new(0.7, 1.9, 1.9),
				FLOOR_Y + 5.85,
				PANEL_DARK,
				Enum.Material.Metal
			)
		end
		local capLight = Build.part({
			name = "CapLight",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 0.7,
			cframe = at(cx, FLOOR_Y + 6.4, z),
			color = "#FF6EC8",
			material = Enum.Material.Neon,
			collide = false,
			parent = base,
		})
		capLight.CanQuery = false
		if not meshed then
			local pipe = Build.part({
				name = "CoolantPipe",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(5.4, 0.45, 0.45),
				cframe = at(cx - 2.7, FLOOR_Y + 3.3, z) * CFrame.Angles(0, 0, math.pi / 2),
				color = "#5FE3FF",
				material = Enum.Material.Glass,
				transparency = 0.3,
				collide = false,
				parent = base,
			})
			pipe.CanQuery = false
		end
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

	-- Truss arches overhead holding the roof, each with a light panel
	-- underneath.
	for _, z in ARCH_Z do
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
			color = Config.Hangar.CEILING_LIGHT.color,
			material = Enum.Material.Neon,
			collide = false,
			parent = station,
		})
		local light = Instance.new("PointLight")
		light.Range = Config.Hangar.CEILING_LIGHT.range
		light.Brightness = Config.Hangar.CEILING_LIGHT.brightness
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
	-- Chevrons down the lane, pointing out to the berth.
	for z = -6, -LENGTH / 2 + 4, -6 do
		for _, side in { -1, 1 } do
			neon(
				"LaneChevron",
				Vector3.new(0.5, 0.15, 3.2),
				at(side * 1.1, FLOOR_Y + 0.08, z) * CFrame.Angles(0, side * math.rad(50), 0),
				COLORS.accent
			)
		end
	end

	-- Equipment lockers against the back wall either side of the tower, each
	-- with a lit status strip; fuel lines along both side walls; and a
	-- gantry crane on the middle arch with its hoist hanging over the deck.
	for _, x in { -12.5, -9, 9, 12.5 } do
		local locker = Build.part({
			name = "Locker",
			size = Vector3.new(3, 7, 2),
			cframe = at(x, FLOOR_Y + 3.5, LENGTH / 2 - 2),
			color = "#D8DCE6",
			material = Enum.Material.Metal,
			parent = station,
		})
		Build.part({
			name = "LockerStrip",
			size = Vector3.new(2.2, 0.3, 0.2),
			cframe = locker.CFrame * CFrame.new(0, 2.6, -1.05),
			color = if x < 0 then "#5CFF8A" else "#FFB020",
			material = Enum.Material.Neon,
			collide = false,
			parent = station,
		})
	end
	Build.part({
		name = "GantryHoist",
		size = Vector3.new(3, 2, 2.4),
		cframe = at(14, FLOOR_Y + ARCH_HEIGHT - 2.4, ARCH_Z[3]),
		color = "#FFC21A",
		material = Enum.Material.Metal,
		parent = station,
	})
	Build.part({
		name = "GantryCable",
		size = Vector3.new(0.2, 6, 0.2),
		cframe = at(14, FLOOR_Y + ARCH_HEIGHT - 6.4, ARCH_Z[3]),
		color = "#1A1A1A",
		collide = false,
		parent = station,
	})
	Build.part({
		name = "GantryHook",
		size = Vector3.new(1.2, 1, 1.2),
		cframe = at(14, FLOOR_Y + ARCH_HEIGHT - 9.8, ARCH_Z[3]),
		color = "#3A3F4E",
		material = Enum.Material.Metal,
		collide = false,
		parent = station,
	})

	-- The control tower at the back: a slim tower with a lit operations
	-- window band, a spinning radar dish, and the beacon mast visible from
	-- the ISS.
	Build.part({
		name = "Hub",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(ARCH_HEIGHT + 4, 12, 12),
		cframe = at(0, FLOOR_Y + (ARCH_HEIGHT + 4) / 2, TOWER_Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hull,
		material = Enum.Material.SmoothPlastic,
		parent = station,
	})
	Build.part({
		name = "OpsWindows",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3, 12.6, 12.6),
		cframe = at(0, FLOOR_Y + ARCH_HEIGHT - 3, TOWER_Z) * CFrame.Angles(0, 0, math.pi / 2),
		color = "#9FD8FF",
		material = Enum.Material.Glass,
		transparency = 0.25,
		parent = station,
	})
	neon(
		"HubRing",
		Vector3.new(0.6, 12.8, 12.8),
		at(0, FLOOR_Y + ARCH_HEIGHT - 0.8, TOWER_Z) * CFrame.Angles(0, 0, math.pi / 2)
	)
	local dish = Build.part({
		name = "RadarDish",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.5, 7, 7),
		cframe = at(0, FLOOR_Y + ARCH_HEIGHT + 6, TOWER_Z) * CFrame.Angles(0, 0, math.rad(60)),
		color = "#F2F2F2",
		material = Enum.Material.SmoothPlastic,
		collide = false,
		parent = station,
	})
	dish:SetAttribute("SpinSpeed", 0.6)
	CollectionService:AddTag(dish, "GaG_Spin")
	Build.part({
		name = "BeaconMast",
		size = Vector3.new(1, 20, 1),
		cframe = at(0, FLOOR_Y + 28, TOWER_Z),
		color = COLORS.truss,
		parent = station,
	})
	local beacon = Build.part({
		name = "Beacon",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 5,
		cframe = at(0, FLOOR_Y + 40, TOWER_Z),
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

	-- The front portal: hazard-striped blast-door posts, a header carrying
	-- the owner's name (facing out towards the berth and the galaxy), a
	-- yellow hazard line on the deck edge and a faint force field across
	-- the opening.
	for _, side in { -1, 1 } do
		for step = 0, 3 do
			Build.part({
				name = "PortalPost",
				size = Vector3.new(2.4, ARCH_HEIGHT / 4, 2.4),
				cframe = at(
					side * (WIDTH / 2 - 2.2),
					FLOOR_Y + ARCH_HEIGHT / 8 + step * ARCH_HEIGHT / 4,
					-LENGTH / 2 + 1.2
				),
				color = if step % 2 == 0 then "#FFC21A" else "#1A1A1A",
				material = Enum.Material.SmoothPlastic,
				parent = station,
			})
		end
	end
	local header = Build.part({
		name = "PortalHeader",
		size = Vector3.new(WIDTH, 3.4, 2.6),
		cframe = at(0, FLOOR_Y + ARCH_HEIGHT - 0.7, -LENGTH / 2 + 1.2),
		color = PANEL_DARK,
		material = Enum.Material.Metal,
		parent = station,
	})
	local nameSign = Build.sign({
		name = "NameSign",
		text = `{ownerName}'s Hangar`,
		size = Vector3.new(26, 2.6, 0.3),
		cframe = header.CFrame * CFrame.new(0, 0, -1.45),
		faces = { Enum.NormalId.Front },
		parent = station,
		textColor = color,
	})
	for _, item in nameSign:GetDescendants() do
		if item:IsA("TextLabel") then
			item:SetAttribute(ACCENT, true)
		end
	end
	neon(
		"PortalTrim",
		Vector3.new(WIDTH, 0.4, 2.8),
		at(0, FLOOR_Y + ARCH_HEIGHT - 2.6, -LENGTH / 2 + 1.2)
	)
	Build.part({
		name = "HazardLine",
		size = Vector3.new(WIDTH - 8, 0.12, 0.8),
		cframe = at(0, FLOOR_Y + 0.07, -LENGTH / 2 + 2.8),
		color = "#FFC21A",
		material = Enum.Material.Neon,
		collide = false,
		parent = station,
	})
	local field = Build.part({
		name = "ForceField",
		size = Vector3.new(WIDTH - 7, ARCH_HEIGHT - 3, 0.2),
		cframe = at(0, FLOOR_Y + (ARCH_HEIGHT - 3) / 2, -LENGTH / 2 + 1.2),
		color = "#7FD8FF",
		material = Enum.Material.ForceField,
		transparency = 0.55,
		collide = false,
		parent = station,
	})
	field.CanQuery = false
	field.CastShadow = false

	-- Galaxy Control, beside Collect: manage every solar system and buy a
	-- bigger galaxy (GalaxyController; prompt attribute OpenPanel = "Galaxy").
	local control = DeviceBuilder.galaxyControl(at(-9, FLOOR_Y, 10), station)
	local controlPrompt =
		Build.prompt(control, { action = "Open Galaxy Control", object = "Galaxy Control" })
	controlPrompt:SetAttribute("OpenPanel", "Galaxy");
	(control.Parent :: Instance):SetAttribute("OwnerUserId", ownerUserId)

	-- The Stardust Collector, facing the spawn (DeviceBuilder).
	local collect = DeviceBuilder.collector(at(0, FLOOR_Y, 10), station)
	Build.prompt(collect, { action = "Collect Stardust", object = "Collector", tycoon = "Collect" });
	(collect.Parent :: Instance):SetAttribute("OwnerUserId", ownerUserId)

	-- The Planet Egg Lab, left of the collector as you face it from the
	-- spawn: roll, keep and upgrade (EggSystem; prompt TycoonAction "Eggs",
	-- EggShopController).
	local lab = DeviceBuilder.eggLab(at(9, FLOOR_Y, 10), station)
	-- The panel's prompt sits behind the lab (its back, +Z), so it never
	-- covers the egg or the ROLL and KEEP keys at the front.
	local labBack = Build.part({
		name = "EggLabPromptAnchor",
		size = Vector3.one * 0.5,
		cframe = lab.CFrame * CFrame.new(0, 0, 3.5),
		transparency = 1,
		collide = false,
		parent = lab.Parent :: Instance,
	})
	labBack.CanQuery = false
	labBack.CanTouch = false
	local labPrompt = Build.prompt(
		labBack,
		{ action = "Odds & upgrades", object = "Planet Egg Lab", tycoon = "Eggs" }
	)
	labPrompt.RequiresLineOfSight = false
	labPrompt.MaxActivationDistance = 12;
	(lab.Parent :: Instance):SetAttribute("OwnerUserId", ownerUserId)
	CollectionService:AddTag(lab.Parent :: Instance, "GaG_EggLab")

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
	for _, item in station:GetDescendants() do
		if item:GetAttribute(ACCENT) ~= true then
			continue
		end
		if item:IsA("BasePart") then
			-- Glowing accents are dimmed like their building (mesh hangar
			-- buildings carry a stronger GlowDim, HangarBuilder).
			local dim = item:GetAttribute("GlowDim")
			local keep = 1 - (if type(dim) == "number" then dim else Config.World.EMISSIVE_DIM)
			local dimmed = Color3.new(base.R * keep, base.G * keep, base.B * keep)
			item.Color = if item.Material == Enum.Material.Neon then dimmed else base
		elseif item:IsA("TextLabel") then
			item.TextColor3 = base
		end
	end
end

return StationBuilder

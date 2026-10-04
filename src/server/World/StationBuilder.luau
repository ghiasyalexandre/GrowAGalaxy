--!strict
-- A player's personal station, floating just in front of their region's near
-- face. Station space: -Z faces into the region, +Z faces back towards the ISS.
-- It has the deck, hub, beacon, name sign, a navigation console, a hangar
-- console, and a ship berth with its docking zone off the -Z edge of the deck.
-- The deposit and collect consoles are placeholders for later stages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local COLORS = Config.World.COLORS
local DECK = 44
local FLOOR_Y = -5
local BERTH_Z = 42 -- berth centre, studs out from the deck centre along -Z
local BERTH_PAD = 20
local BERTH_Z_NEAR = BERTH_Z - BERTH_PAD / 2

local StationBuilder = {}

export type Station = {
	model: Model,
	spawn: CFrame,
	berth: CFrame, -- where the owner's ship parks, facing out
	dockZone: BasePart,
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

	Build.part({
		name = "Deck",
		size = Vector3.new(DECK, 2, DECK),
		cframe = at(0, FLOOR_Y - 1, 0),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	Build.part({
		name = "DockingRing",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3, DECK + 8, DECK + 8),
		cframe = at(0, FLOOR_Y - 3.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hullAlt,
		parent = station,
	})
	for _, rail in
		{
			{ size = Vector3.new(DECK, 3, 0.6), offset = Vector3.new(0, 0, -DECK / 2) },
			{ size = Vector3.new(DECK, 3, 0.6), offset = Vector3.new(0, 0, DECK / 2) },
			{ size = Vector3.new(0.6, 3, DECK), offset = Vector3.new(-DECK / 2, 0, 0) },
			{ size = Vector3.new(0.6, 3, DECK), offset = Vector3.new(DECK / 2, 0, 0) },
		}
	do
		Build.part({
			name = "Rail",
			size = rail.size,
			cframe = at(rail.offset.X, FLOOR_Y + 1.5, rail.offset.Z),
			color = color,
			parent = station,
		})
	end

	-- Hub tower at the back of the deck, with a beacon visible from the ISS.
	Build.part({
		name = "Hub",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(18, 16, 16),
		cframe = at(0, FLOOR_Y + 9, 14) * CFrame.Angles(0, 0, math.pi / 2),
		color = COLORS.hull,
		parent = station,
	})
	Build.part({
		name = "BeaconMast",
		size = Vector3.new(1, 20, 1),
		cframe = at(0, FLOOR_Y + 28, 14),
		color = COLORS.truss,
		parent = station,
	})
	local beacon = Build.part({
		name = "Beacon",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 5,
		cframe = at(0, FLOOR_Y + 40, 14),
		color = color,
		material = Enum.Material.Neon,
		collide = false,
		parent = station,
	})
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
	tag.TextStrokeTransparency = 0.4
	tag.Parent = billboard
	billboard.Parent = beacon

	Build.sign({
		name = "NameSign",
		text = `{ownerName}'s Station`,
		size = Vector3.new(14, 3, 0.4),
		cframe = at(0, FLOOR_Y + 6, 5.6),
		faces = { Enum.NormalId.Front },
		parent = station,
		textColor = color,
	})

	-- Console row in front of the hub, screens facing the deck.
	local navigation = Build.console(
		"NavigationConsole",
		"Navigation\nRoute to the ISS",
		at(-12, FLOOR_Y, 4),
		station
	)
	Build.prompt(
		navigation,
		{ action = "Show route to the ISS", object = "Station navigation", route = "ISS" }
	)
	local hangar =
		Build.console("HangarConsole", "Hangar\nLaunch your ship", at(-4, FLOOR_Y, 4), station)
	Build.prompt(hangar, { action = "Launch ship", object = "Station hangar", launch = "Station" })
	Build.console("DepositConsole", "Cargo deposit\n(Stage 4)", at(4, FLOOR_Y, 4), station)
	Build.console("CollectConsole", "Collect Credits\n(Stage 5)", at(12, FLOOR_Y, 4), station)

	-- Berth pad off the -Z edge of the deck, joined by a short gangway. The
	-- ship parks above it facing into the region. The docking zone covers the
	-- berth and the approach in front of it.
	Build.part({
		name = "Gangway",
		size = Vector3.new(8, 1, BERTH_Z_NEAR - DECK / 2),
		cframe = at(0, FLOOR_Y - 0.5, -(DECK / 2 + BERTH_Z_NEAR) / 2),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	Build.part({
		name = "BerthPad",
		size = Vector3.new(BERTH_PAD, 2, BERTH_PAD),
		cframe = at(0, FLOOR_Y - 1, -BERTH_Z),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = station,
	})
	Build.berthOutline(at(0, FLOOR_Y + 0.1, -BERTH_Z), 16, station)
	local berth = at(0, FLOOR_Y + 6, -BERTH_Z)
	Build.marker("StationBerth", berth, station)
	local dockZone = Build.dockZone(
		at(0, FLOOR_Y + 9, -BERTH_Z - 13),
		Vector3.new(60, 36, 70),
		ownerUserId,
		station
	)

	local spawn = at(0, FLOOR_Y + 3, -6)
	Build.marker("StationSpawn", spawn, station)

	return { model = station, spawn = spawn, berth = berth, dockZone = dockZone }
end

return StationBuilder

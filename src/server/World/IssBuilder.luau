--!strict
-- Greybox International Space Station, built from parts at the world origin.
--
-- Exterior: a line of connected cylindrical modules, a long truss crossing
-- above them, four solar-array assemblies, two radiators, a docking platform
-- and a glass-walled observation cupola at the far end.
-- Interior: one module per hub area, with floors (Stage 1 keeps normal
-- gravity; Stage 2 switches to zero-g).
--
-- The parts named in WorldSystem.MARKERS are the contract with the rest of the
-- game: a hand-built replacement model must contain them too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local COLORS = Config.World.COLORS

local TUBE_RADIUS = 10
local TUBE_SIDES = 12
local FLOOR_Y = -5
local FLOOR_WIDTH = 17
local TRUSS_Y = 22
local TRUSS_LENGTH = 340

type ModuleDef = {
	id: string,
	label: string,
	length: number,
	glass: boolean?,
}

-- From the -X end to the +X end. The Navigation module is centred on the origin.
local MODULES: { ModuleDef } = {
	{ id = "Cupola", label = "Observation Cupola", length = 20, glass = true },
	{ id = "Arrival", label = "Arrival", length = 36 },
	{ id = "Missions", label = "Mission Terminal", length = 28 },
	{ id = "Navigation", label = "Navigation", length = 28 },
	{ id = "Showroom", label = "Ship Showroom", length = 44 },
	{ id = "Workshop", label = "Upgrade Workshop", length = 32 },
	{ id = "Docking", label = "Docking Airlock", length = 24 },
}

type Span = { from: number, to: number, center: number }

local function layout(): { [string]: Span }
	local offset = 0
	for _, def in MODULES do
		if def.id == "Navigation" then
			offset += def.length / 2
			break
		end
		offset += def.length
	end
	local spans: { [string]: Span } = {}
	local x = -offset
	for _, def in MODULES do
		spans[def.id] = { from = x, to = x + def.length, center = x + def.length / 2 }
		x += def.length
	end
	return spans
end

-- A hollow polygonal tube along X, open at both ends.
local function tube(parent: Instance, span: Span, color: string, glassBottom: boolean)
	local width = 2 * (TUBE_RADIUS + 1) * math.tan(math.pi / TUBE_SIDES) + 0.2
	for i = 0, TUBE_SIDES - 1 do
		local angle = i / TUBE_SIDES * 2 * math.pi
		local glass = glassBottom and math.cos(angle) < -0.4
		Build.part({
			name = "Hull",
			size = Vector3.new(span.to - span.from, 1, width),
			cframe = CFrame.new(span.center, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, TUBE_RADIUS + 0.5, 0),
			color = if glass then COLORS.glass else color,
			material = if glass then Enum.Material.Glass else Enum.Material.SmoothPlastic,
			transparency = if glass then 0.45 else 0,
			parent = parent,
		})
	end
end

local function endCap(parent: Instance, x: number, glass: boolean)
	Build.part({
		name = "EndCap",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1, 2 * TUBE_RADIUS + 3, 2 * TUBE_RADIUS + 3),
		cframe = CFrame.new(x, 0, 0),
		color = if glass then COLORS.glass else COLORS.hullAlt,
		material = if glass then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		transparency = if glass then 0.45 else 0,
		parent = parent,
	})
end

local function interior(parent: Instance, def: ModuleDef, span: Span)
	Build.part({
		name = "Floor",
		size = Vector3.new(span.to - span.from, 1, FLOOR_WIDTH),
		cframe = CFrame.new(span.center, FLOOR_Y - 0.5, 0),
		color = if def.glass then COLORS.glass else COLORS.deck,
		material = if def.glass then Enum.Material.Glass else Enum.Material.DiamondPlate,
		transparency = if def.glass then 0.35 else 0,
		parent = parent,
	})

	local fixture = Build.part({
		name = "Light",
		size = Vector3.new(4, 0.4, 2),
		cframe = CFrame.new(span.center, TUBE_RADIUS - 1, 0),
		color = "#FFFFFF",
		material = Enum.Material.Neon,
		collide = false,
		parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = fixture

	-- Hanging area sign, readable from both directions along the walkway.
	Build.sign({
		name = "AreaSign",
		text = def.label,
		size = Vector3.new(0.4, 2.6, 11),
		cframe = CFrame.new(span.from + 2, 5.5, 0),
		faces = { Enum.NormalId.Left, Enum.NormalId.Right },
		parent = parent,
	})
end

-- Floor point against the -Z wall of a module, facing the walkway.
local function wallSpot(x: number): CFrame
	return CFrame.new(x, FLOOR_Y, -6) * CFrame.Angles(0, math.pi, 0)
end

local function areaContents(parent: Instance, def: ModuleDef, span: Span)
	if def.id == "Arrival" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "ArrivalSpawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(8, 0.2, 8)
		spawn.CFrame = CFrame.lookAt(
			Vector3.new(span.center, FLOOR_Y + 0.1, 0),
			Vector3.new(span.to, FLOOR_Y + 0.1, 0)
		)
		spawn.Color = Color3.fromHex(COLORS.accent)
		spawn.Material = Enum.Material.Neon
		spawn.CastShadow = false
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = parent
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end

		Build.sign({
			name = "Welcome",
			text = "Welcome to Grow a Galaxy!\nHead to Navigation to warp to your own galaxy.",
			size = Vector3.new(16, 5, 0.4),
			cframe = CFrame.new(span.center, 0, -8.3),
			faces = { Enum.NormalId.Back },
			parent = parent,
		})
	elseif def.id == "Missions" then
		Build.console(
			"MissionTerminal",
			"Mission Terminal\n(coming soon)",
			wallSpot(span.center),
			parent
		)
	elseif def.id == "Navigation" then
		local console = Build.console(
			"NavigationConsole",
			"Navigation\nWarp to your station",
			wallSpot(span.center),
			parent
		)
		Build.prompt(
			console,
			{ action = "Warp to my station", object = "Navigation", warp = "OwnStation" }
		)
	elseif def.id == "Showroom" then
		Build.console(
			"Showroom",
			"Ship Showroom\nShips arrive in Stage 2",
			wallSpot(span.center),
			parent
		)
		for _, x in { span.center - 12, span.center + 12 } do
			Build.part({
				name = "DisplayPad",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(0.6, 8, 8),
				cframe = CFrame.new(x, FLOOR_Y + 0.3, 3) * CFrame.Angles(0, 0, math.pi / 2),
				color = COLORS.accent,
				material = Enum.Material.Neon,
				parent = parent,
			})
		end
	elseif def.id == "Workshop" then
		Build.console("Workshop", "Upgrade Workshop\n(coming soon)", wallSpot(span.center), parent)
	elseif def.id == "Docking" then
		local console = Build.console(
			"AirlockConsole",
			"Airlock\nTo the docking area",
			wallSpot(span.center),
			parent
		)
		Build.prompt(console, { action = "Go outside", object = "Airlock", warp = "DockingArea" })
		Build.marker(
			"AirlockInside",
			CFrame.lookAt(
				Vector3.new(span.center, FLOOR_Y + 3, 2),
				Vector3.new(span.from, FLOOR_Y + 3, 2)
			),
			parent
		)
	end
end

local function truss(parent: Instance)
	Build.part({
		name = "Truss",
		size = Vector3.new(6, 5, TRUSS_LENGTH),
		cframe = CFrame.new(0, TRUSS_Y, 0),
		color = COLORS.truss,
		material = Enum.Material.DiamondPlate,
		parent = parent,
	})
	for _, x in { -3.6, 3.6 } do
		Build.part({
			name = "TrussRail",
			size = Vector3.new(1, 1, TRUSS_LENGTH),
			cframe = CFrame.new(x, TRUSS_Y + 2.5, 0),
			color = COLORS.hullAlt,
			parent = parent,
		})
	end
	Build.part({
		name = "TrussPylon",
		size = Vector3.new(4, TRUSS_Y - 2.5 - TUBE_RADIUS, 4),
		cframe = CFrame.new(0, (TRUSS_Y - 2.5 + TUBE_RADIUS) / 2, 0),
		color = COLORS.truss,
		parent = parent,
	})

	-- Four solar-array assemblies: a mast across the truss with two blankets on each side.
	for _, z in { -160, -110, 110, 160 } do
		Build.part({
			name = "ArrayJoint",
			size = Vector3.new(8, 7, 8),
			cframe = CFrame.new(0, TRUSS_Y, z),
			color = COLORS.hullAlt,
			parent = parent,
		})
		Build.part({
			name = "ArrayMast",
			size = Vector3.new(160, 0.8, 0.8),
			cframe = CFrame.new(0, TRUSS_Y, z),
			color = COLORS.solarFrame,
			parent = parent,
		})
		for _, side in { -1, 1 } do
			for _, offset in { -6.5, 6.5 } do
				Build.part({
					name = "SolarArray",
					size = Vector3.new(72, 0.3, 11),
					cframe = CFrame.new(side * 42, TRUSS_Y, z + offset)
						* CFrame.Angles(math.rad(25), 0, 0),
					color = COLORS.solar,
					material = Enum.Material.Glass,
					collide = false,
					parent = parent,
				})
			end
		end
	end

	-- Radiators hang below the truss, clear of the modules.
	for _, z in { -62, 62 } do
		Build.part({
			name = "Radiator",
			size = Vector3.new(0.4, 22, 16),
			cframe = CFrame.new(0, TRUSS_Y - 2.5 - 11, z),
			color = COLORS.radiator,
			collide = false,
			parent = parent,
		})
	end
end

local function dockingArea(parent: Instance, dockingSpan: Span)
	local x0 = dockingSpan.to
	Build.part({
		name = "DockingTunnel",
		size = Vector3.new(6, 10, 10),
		cframe = CFrame.new(x0 + 3, 0, 0),
		color = COLORS.hullAlt,
		parent = parent,
	})

	local length, width = 80, 70
	local cx = x0 + 6 + length / 2
	Build.part({
		name = "DockingPlatform",
		size = Vector3.new(length, 2, width),
		cframe = CFrame.new(cx, FLOOR_Y - 1, 0),
		color = COLORS.deck,
		material = Enum.Material.DiamondPlate,
		parent = parent,
	})
	-- Railings on the three open sides.
	Build.part({
		name = "Rail",
		size = Vector3.new(0.6, 3, width),
		cframe = CFrame.new(cx + length / 2, FLOOR_Y + 1.5, 0),
		color = COLORS.accent,
		parent = parent,
	})
	for _, z in { -width / 2, width / 2 } do
		Build.part({
			name = "Rail",
			size = Vector3.new(length, 3, 0.6),
			cframe = CFrame.new(cx, FLOOR_Y + 1.5, z),
			color = COLORS.accent,
			parent = parent,
		})
	end

	-- Three berths, marked by glowing outlines on the deck (ships use them in Stage 2).
	local berthX = cx + 12
	for index, z in { -22, 0, 22 } do
		Build.marker(`Berth{index}`, CFrame.new(berthX, FLOOR_Y + 6, z), parent)
		local half = 8
		for _, edge in
			{
				{ size = Vector3.new(16, 0.2, 0.6), offset = Vector3.new(0, 0, -half) },
				{ size = Vector3.new(16, 0.2, 0.6), offset = Vector3.new(0, 0, half) },
				{ size = Vector3.new(0.6, 0.2, 16), offset = Vector3.new(-half, 0, 0) },
				{ size = Vector3.new(0.6, 0.2, 16), offset = Vector3.new(half, 0, 0) },
			}
		do
			Build.part({
				name = "BerthOutline",
				size = edge.size,
				cframe = CFrame.new(berthX, FLOOR_Y + 0.1, z) + edge.offset,
				color = COLORS.accent,
				material = Enum.Material.Neon,
				collide = false,
				parent = parent,
			})
		end
	end

	Build.marker(
		"DockingSpawn",
		CFrame.lookAt(Vector3.new(x0 + 12, FLOOR_Y + 3, 0), Vector3.new(x0 + 40, FLOOR_Y + 3, 0)),
		parent
	)
	local console = Build.console(
		"AirlockReturn",
		"Airlock\nBack inside",
		CFrame.new(x0 + 10, FLOOR_Y, -10) * CFrame.Angles(0, math.pi, 0),
		parent
	)
	Build.prompt(console, { action = "Go inside", object = "Airlock", warp = "Interior" })
	Build.sign({
		name = "DockingSign",
		text = "Docking Area\nShips arrive in Stage 2",
		size = Vector3.new(0.4, 6, 20),
		cframe = CFrame.new(x0 + length + 2, FLOOR_Y + 6, 0),
		faces = { Enum.NormalId.Left },
		parent = parent,
	})
end

local IssBuilder = {}

function IssBuilder.build(): Model
	local model = Build.model("ISS")
	local spans = layout()

	local hull = Build.model("Hull", model)
	local rooms = Build.model("Interior", model)
	for index, def in MODULES do
		local span = spans[def.id]
		local area = Build.model(def.id, rooms)
		tube(hull, span, if index % 2 == 0 then COLORS.hull else COLORS.hullAlt, def.glass == true)
		interior(area, def, span)
		areaContents(area, def, span)
	end
	endCap(hull, spans[MODULES[1].id].from - 0.5, true)
	endCap(hull, spans[MODULES[#MODULES].id].to + 0.5, false)

	truss(Build.model("Truss", model))
	dockingArea(Build.model("DockingArea", model), spans.Docking)

	model.WorldPivot = CFrame.new()
	return model
end

return IssBuilder

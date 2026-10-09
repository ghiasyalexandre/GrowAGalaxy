-- Smoke test for the server's world builders, run outside Studio.
--
-- Loads the place built by Rojo with Lune's Roblox library, runs WorldSystem.init,
-- builds every region and station, puts a ship on every berth and builds
-- sample asteroids of every size. Then checks
-- part budgets, the markers and tags other systems rely on, and that berths,
-- launch paths and exit points are clear of solid parts. This catches runtime
-- errors and layout mistakes in builder code; it does not simulate physics,
-- render anything or replace a playtest.
--
-- Usage, from the repository root:
--   rojo build -o build.rbxl
--   lune run tests/WorldSmoke build.rbxl

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ISS_PART_BUDGET = 850 -- one shared hub per server: modules, truss, gravity wheel
local REGION_PART_BUDGET = 320 -- the station before any hangar upgrades, with the imported machine and chamber meshes
local HANGAR_PART_BUDGET = 120 -- per hangar building (voxel designs, tools/hangar_voxels)
local VANITY_PART_BUDGET = 120 -- per vanity building (runway, hologram, spire, dock)
local SHIP_PART_BUDGET = 20
-- How far a ship's launch path (straight out of its berth) must be clear.
local LAUNCH_PATH = 150
-- Room a floating player needs at a ship's exit point.
local EXIT_BOX = { x = 4, y = 6, z = 4 }

local placePath = process.args[1] or "build.rbxl"
local game = roblox.deserializePlace(fs.readFile(placePath))

-- Lune's CollectionService has no tag methods, so builders get a small stand-in.
local tagged: { [string]: { any } } = {}
local collectionService = {
	AddTag = function(_, instance, tag: string)
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], instance)
	end,
}
local gameProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name: string)
				if name == "CollectionService" then
					return collectionService
				end
				return game:GetService(name)
			end
		end
		return game[key]
	end,
})

local warnings = {}
local modelFallbacks = 0
local cache = {}
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local env = setmetatable({
		script = module,
		game = gameProxy,
		require = requireModule,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		warn = function(...)
			local text = table.concat({ ... }, " ")
			-- Lune can't fit imported ship models (no Model:GetBoundingBox or
			-- ScaleTo), so ShipBuilder falls back to the greybox here. That path
			-- needs a Studio playtest; the greybox path is what this checks.
			if
				string.find(text, "Could not fit the", 1, true)
				or string.find(text, "Could not place the Saturn V", 1, true)
			then
				modelFallbacks += 1
				return
			end
			table.insert(warnings, text)
		end,
	}, { __index = getfenv() })
	local chunk = luau.load(module.Source, { debugName = module:GetFullName(), environment = env })
	local result = chunk()
	cache[module] = result
	return result
end

local failures = 0
local function check(ok: boolean, label: string)
	print(`  {if ok then "ok  " else "FAIL"}  {label}`)
	if not ok then
		failures += 1
	end
end

local function count(list): number
	return #(list or {})
end

-- Axis-aligned bounds of a part in world space (exact for unrotated boxes,
-- larger than the part otherwise, so overlap checks err on the safe side).
local function bounds(cframe, size)
	local lo = { x = math.huge, y = math.huge, z = math.huge }
	local hi = { x = -math.huge, y = -math.huge, z = -math.huge }
	for _, sx in { -0.5, 0.5 } do
		for _, sy in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				local p = cframe:PointToWorldSpace(
					roblox.Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
				)
				lo.x, lo.y, lo.z = math.min(lo.x, p.X), math.min(lo.y, p.Y), math.min(lo.z, p.Z)
				hi.x, hi.y, hi.z = math.max(hi.x, p.X), math.max(hi.y, p.Y), math.max(hi.z, p.Z)
			end
		end
	end
	return { lo = lo, hi = hi }
end

local function merge(a, b)
	return {
		lo = {
			x = math.min(a.lo.x, b.lo.x),
			y = math.min(a.lo.y, b.lo.y),
			z = math.min(a.lo.z, b.lo.z),
		},
		hi = {
			x = math.max(a.hi.x, b.hi.x),
			y = math.max(a.hi.y, b.hi.y),
			z = math.max(a.hi.z, b.hi.z),
		},
	}
end

local function overlaps(a, b): boolean
	return a.lo.x < b.hi.x
		and b.lo.x < a.hi.x
		and a.lo.y < b.hi.y
		and b.lo.y < a.hi.y
		and a.lo.z < b.hi.z
		and b.lo.z < a.hi.z
end

local function solidParts(root)
	local list = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Names of the solid parts in `obstacles` that the box overlaps.
local function blockers(box, obstacles): { string }
	local names = {}
	for _, part in obstacles do
		if overlaps(box, bounds(part.CFrame, part.Size)) then
			table.insert(names, part:GetFullName())
		end
	end
	return names
end

local function countParts(root): number
	local n = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local shared = game:GetService("ReplicatedStorage").Shared
local server = game:GetService("ServerScriptService").Server

print("WorldSmoke")
local WorldSystem = requireModule(server.Systems.WorldSystem)
WorldSystem.init()

local world = game:GetService("Workspace").World
local issParts = countParts(world.ISS)
check(
	issParts > 0 and issParts <= ISS_PART_BUDGET,
	`ISS has {issParts} parts (budget {ISS_PART_BUDGET})`
)
for _, name in WorldSystem.MARKERS do
	check(WorldSystem.getMarker(name) ~= nil, `ISS marker {name} exists`)
end
local arrival = WorldSystem.getMarker("ArrivalSpawn")
check(arrival ~= nil and arrival:IsA("SpawnLocation"), "ArrivalSpawn is a SpawnLocation")
check(count(tagged.WarpPrompt) == 3, "ISS has 2 airlock warp prompts and the Dodgeball portal")
check(count(tagged.LaunchPrompt) == 0, "ISS has no hangar (raids replace the berths)")
check(count(tagged.RoutePrompt) == 0, "ISS has no navigation console (the Central Hub has signs)")
check(count(tagged.DockZone) == 0, "ISS has no docking zone")
check(count(tagged.SafeZone) == 1, "ISS has a PvP safe zone")
local workspace = game:GetService("Workspace")
check(workspace.Gravity == 0, "the place has zero gravity")
check(workspace.FallenPartsDestroyHeight <= -5000, "parts below the ISS are not destroyed")
check(countParts(world.Nebula) > 0, "Helix Nebula backdrop built")
check(#warnings == 0, `no warnings ({table.concat(warnings, "; ")})`)

local RegionMath = requireModule(shared.Logic.RegionMath)
local RegionBuilder = requireModule(server.World.RegionBuilder)
local StationBuilder = requireModule(server.World.StationBuilder)
local stations = {}

for slot = 1, requireModule(shared.Config).World.MAX_PLAYERS do
	local position, yaw = RegionMath.slotOrigin(slot)
	local origin = roblox.CFrame.new(position.x, position.y, position.z)
		* roblox.CFrame.Angles(0, yaw, 0)
	local size = RegionMath.regionSize(1)
	local region = roblox.Instance.new("Model")
	RegionBuilder.buildBounds(region, origin, roblox.Vector3.new(size.x, size.y, size.z), "#4FC3F7")
	local station = StationBuilder.build(region, origin, "Tester", 1, "#4FC3F7")
	local parts = countParts(region)
	local spawn = station.spawn
	local facesRegion = spawn.LookVector:Dot(origin.LookVector) < -0.99
	if slot == 1 then
		check(
			parts <= REGION_PART_BUDGET,
			`region and station have {parts} parts (budget {REGION_PART_BUDGET})`
		)
		check(
			#region:GetDescendants() > 0 and region:FindFirstChild("Station") ~= nil,
			"station built in region"
		)
	end
	check(facesRegion, `slot {slot}: station spawn faces into the region`)
	table.insert(stations, { slot = slot, region = region, station = station })
end
check(count(tagged.GaG_EggLab) == 8, "every station has its own Egg Lab")
check(count(tagged.WarpPrompt) == 3, "stations have no warp prompts (ships replace them)")
check(count(tagged.LaunchPrompt) == 0, "stations have no launch consoles (HUD button)")
check(count(tagged.RoutePrompt) == 0, "stations have no navigation consoles")
check(
	count(tagged.TycoonPrompt) == 16,
	"every station has exactly two consoles (Collect, Egg Lab); the ISS has none"
)

-- Hangar upgrades: every pad and building builds on the first station's deck.
print("Hangar")
local HangarBuilder = requireModule(server.World.HangarBuilder)
local HangarConfig = requireModule(shared.Config).Hangar
for _, id in HangarConfig.ORDER do
	local def = HangarConfig.BY_ID[id]
	local floor = stations[1].station.floor * roblox.CFrame.new(def.pad.x, 0, def.pad.z)
	local pad = HangarBuilder.pad(def, floor)
	local circle = pad:FindFirstChild("Circle")
	check(
		circle ~= nil and circle:FindFirstChild("BuildPrompt") ~= nil,
		`{id}: pad has a circle with a Build prompt`
	)
	local building = HangarBuilder.structure(def, floor)
	if building:GetAttribute("Mesh") then
		-- An imported mesh model: its markers must land on the floor point and
		-- 8 studs out of the front, upright.
		local origin = building:FindFirstChild("Marker_Origin")
		local front = building:FindFirstChild("Marker_Front")
		local up = building:FindFirstChild("Marker_Up")
		check(
			origin ~= nil
				and front ~= nil
				and up ~= nil
				and (origin.CFrame.Position - floor.Position).Magnitude < 0.05
				and (front.CFrame.Position - (floor * roblox.CFrame.new(0, 0, -8)).Position).Magnitude < 0.05
				and (up.CFrame.Position - (floor * roblox.CFrame.new(0, 8, 0)).Position).Magnitude
					< 0.05,
			`{id}: mesh model placed on its pad, facing front, upright`
		)
	end
	local n = countParts(building)
	local budget = if def.vanity then VANITY_PART_BUDGET else HANGAR_PART_BUDGET
	check(n > 3 and n <= budget, `{id}: building has {n} parts (budget {budget})`)
	if id == "ShowcaseDock" then
		check(
			building:FindFirstChild("Cradle1") ~= nil
				and building:FindFirstChild("Cradle2") ~= nil
				and building:FindFirstChild("Cradle3") ~= nil,
			"ShowcaseDock: three cradles for the showcased ships"
		)
	end
	pad:Destroy()
	building:Destroy()
end
check(count(tagged.DockZone) == 8, "every station has a docking zone")

-- Raids: the beacon, a pad per difficulty and the boss build at the ISS.
print("Dodgeball")
local DodgeballBuilder = requireModule(server.World.DodgeballBuilder)
local DodgeballMath = requireModule(shared.Logic.DodgeballMath)
local warpsBefore = count(tagged.WarpPrompt)
local arenaModel = DodgeballBuilder.build(roblox.Instance.new("Folder"))
local blockCount = #DodgeballMath.blocks()
check(count(tagged.DodgeBlock) == blockCount, `arena has {blockCount} tagged cover blocks`)
local spawnsFound = 0
for index = 1, requireModule(shared.Config).Dodgeball.SPAWN_COUNT do
	if arenaModel:FindFirstChild(`Spawn{index}`) then
		spawnsFound += 1
	end
end
check(
	spawnsFound == requireModule(shared.Config).Dodgeball.SPAWN_COUNT,
	"arena has every spawn marker"
)
check(count(tagged.WarpPrompt) == warpsBefore + 1, "arena has an exit portal back to the ISS")
local arenaParts = countParts(arenaModel)
check(arenaParts <= 120, `arena has {arenaParts} parts (budget 120)`)
check(#warnings == 0, `no arena warnings ({table.concat(warnings, "; ")})`)

print("Raids")
local RaidBuilder = requireModule(server.World.RaidBuilder)
local Raids = requireModule(shared.Config).Raids
local beaconMarker = WorldSystem.getMarker("RaidBeacon")
local raidArea = roblox.Instance.new("Model")
local beacon = RaidBuilder.beacon(roblox.CFrame.new(beaconMarker.CFrame.Position), raidArea)
check(beacon:FindFirstChild("SaturnV") ~= nil, "raid beacon has a Saturn V (asset or greybox)")
local spinners = count(tagged.GaG_Spin)
check(spinners >= 3, `raid beacon has spinning glow rings ({spinners} spinners)`)
for _, id in Raids.ORDER do
	local pad =
		RaidBuilder.pad(Raids.BY_ID[id], roblox.CFrame.new(beaconMarker.CFrame.Position), raidArea)
	local circle = pad:FindFirstChild("Circle")
	check(
		circle ~= nil and circle:FindFirstChild("JoinPrompt") ~= nil,
		`{id}: raid pad has a circle with a Join prompt`
	)
	local sign = pad:FindFirstChild("Sign", true)
	check(
		sign ~= nil
			and sign:FindFirstChild("Queue", true) ~= nil
			and sign:FindFirstChild("Status", true) ~= nil,
		`{id}: raid pad sign has Queue and Status labels`
	)
end
local bossModel, bossBody, weakPoint = RaidBuilder.boss(roblox.CFrame.new(0, 1100, 0), raidArea)
check(bossModel.Parent == raidArea and bossBody.Anchored, "boss is anchored and parented")
check(weakPoint.Name == "WeakPoint" and weakPoint.Parent == bossModel, "boss has a weak point")
check(weakPoint:FindFirstChild("Target") ~= nil, "weak point has a target marker")
local weakBefore = weakPoint.CFrame.Position
RaidBuilder.placeWeakPoint(weakPoint, bossBody.CFrame.Position, roblox.Vector3.new(0, 0, 1))
local moved = weakPoint.CFrame.Position
check(
	(moved - weakBefore).Magnitude > 10
		and math.abs((moved - bossBody.CFrame.Position).Magnitude - Raids.BOSS_SIZE * 0.49)
			< 0.5,
	"the weak point moves to a new spot on the hull"
)
local drone = RaidBuilder.drone(roblox.Vector3.new(0, 1100, -300), bossModel)
check(
	drone:GetAttribute("Drone") == true and drone.Parent == bossModel and not drone.CanCollide,
	"drones build inside the boss model, tagged and not collidable"
)
check(#warnings == 0, `no raid warnings ({table.concat(warnings, "; ")})`)
raidArea:Destroy()

-- Ships
print("Ships")
local Config = requireModule(shared.Config)
local FlightMath = requireModule(shared.Logic.FlightMath)
local ShipBuilder = requireModule(server.World.ShipBuilder)

local function shipBounds(ship)
	local box = nil
	for _, part in ship:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			local b = bounds(part.CFrame, part.Size)
			box = if box then merge(box, b) else b
		end
	end
	return box
end

-- Builds a ship on `berth` and checks it, its launch path (along the berth's
-- look direction) and its exit points against the solid parts around it.
local function checkBerth(label: string, berth, zone, obstacles)
	local ship = ShipBuilder.build(Config.Ships.STARTER_SHIP, berth, "#4FC3F7")
	check(
		FlightMath.insideBox(zone.CFrame, zone.Size, berth.Position),
		`{label}: berth is inside its docking zone`
	)
	check(
		FlightMath.insideBox(zone.CFrame, zone.Size, berth.Position + berth.LookVector * 40),
		`{label}: the docking zone reaches 40 studs beyond the berth`
	)
	local hits = blockers(shipBounds(ship), obstacles)
	check(#hits == 0, `{label}: ship fits its berth ({table.concat(hits, ", ")})`)
	local path = merge(
		shipBounds(ship),
		bounds(berth * roblox.CFrame.new(0, 0, -LAUNCH_PATH), ship.PrimaryPart.Size)
	)
	hits = blockers(path, obstacles)
	check(
		#hits == 0,
		`{label}: launch path is clear for {LAUNCH_PATH} studs ({table.concat(hits, ", ")})`
	)
	local clear = 0
	for _, name in { "ExitLeft", "ExitRight", "ExitTop" } do
		local point = ship.PrimaryPart:FindFirstChild(name)
		local at = ship.PrimaryPart.CFrame:PointToWorldSpace(point.CFrame.Position)
		local box =
			bounds(roblox.CFrame.new(at), roblox.Vector3.new(EXIT_BOX.x, EXIT_BOX.y, EXIT_BOX.z))
		if #blockers(box, obstacles) == 0 then
			clear += 1
		end
	end
	check(clear >= 2, `{label}: at least 2 of 3 exit points are clear ({clear})`)
	return ship
end

for _, entry in stations do
	checkBerth(
		`slot {entry.slot} station berth`,
		entry.station.berth,
		entry.station.dockZone,
		solidParts(entry.region)
	)
	check(
		entry.station.dockZone:GetAttribute("OwnerUserId") == 1,
		`slot {entry.slot}: station docking zone belongs to its owner`
	)
end

local sample = ShipBuilder.build(Config.Ships.STARTER_SHIP, roblox.CFrame.new(), "#4FC3F7")
local hull = sample.PrimaryPart
local shipParts = countParts(sample)
check(hull ~= nil and hull.Name == "Hull" and hull.Anchored, "Hull is the anchored PrimaryPart")
check(shipParts <= SHIP_PART_BUDGET, `ship has {shipParts} parts (budget {SHIP_PART_BUDGET})`)
local seat = sample:FindFirstChild("PilotSeat")
check(
	seat ~= nil and seat:IsA("Seat") and not seat.CanTouch,
	"PilotSeat is a Seat nobody can sit in by touch"
)
-- Lune makes a new wrapper each time an instance is read, so instances are
-- compared with == rather than used as table keys.
local welds = {}
for _, descendant in sample:GetDescendants() do
	if descendant:IsA("WeldConstraint") and descendant.Part0 == hull then
		table.insert(welds, descendant.Part1)
	end
end
local function isWelded(part): boolean
	for _, other in welds do
		if other == part then
			return true
		end
	end
	return false
end
local loose = {}
for _, part in sample:GetDescendants() do
	if part:IsA("BasePart") and part ~= hull and (part.Anchored or not isWelded(part)) then
		table.insert(loose, part.Name)
	end
end
check(
	#loose == 0,
	`every other part is unanchored and welded to the hull ({table.concat(loose, ", ")})`
)
local engine = hull:FindFirstChild("Engine")
local steer = hull:FindFirstChild("Steer")
check(engine ~= nil and engine:IsA("LinearVelocity"), "hull has the Engine LinearVelocity")
check(steer ~= nil and steer:IsA("AlignOrientation"), "hull has the Steer AlignOrientation")
check(engine.Attachment0 == hull:FindFirstChild("Thrust"), "Engine uses the Thrust attachment")
check(count(tagged.BoardPrompt) == 1 + 8, "every ship has a tagged Board prompt")
local muzzle = hull:FindFirstChild("BeamOrigin")
check(
	muzzle ~= nil and muzzle:IsA("Attachment") and muzzle.CFrame.Position.Z < -hull.Size.Z / 2,
	"hull has a BeamOrigin attachment ahead of the hull"
)
local emitter = sample:FindFirstChild("BeamEmitter")
check(
	emitter ~= nil and not emitter.CanCollide,
	"the laser lens doesn't collide (berth fit ignores it)"
)
for _, name in { "NozzleL", "NozzleR" } do
	local nozzle = hull:FindFirstChild(name)
	local plume = nozzle and nozzle:FindFirstChild("Exhaust")
	check(
		plume ~= nil and plume:IsA("ParticleEmitter") and plume.Rate == 0,
		`{name} has an idle Exhaust emitter`
	)
	-- Emitters on an attachment fire along its +Y, which must point back (+Z).
	check(
		nozzle ~= nil and nozzle.CFrame.UpVector.Z > 0.99,
		`{name} points its exhaust out of the back`
	)
end
local trails = 0
for _, child in hull:GetChildren() do
	if child:IsA("Trail") and child.Name == "WingTrail" then
		trails += if child.Attachment0 and child.Attachment1 and not child.Enabled then 1 else 0
	end
end
check(trails == 2, `two idle wing trails with attachments ({trails})`)
local box = ShipBuilder.BERTH_BOX
local own = shipBounds(sample)
check(
	math.max(-own.lo.x, own.hi.x) * 2 <= box.X
		and math.max(-own.lo.y, own.hi.y) * 2 <= box.Y
		and math.max(-own.lo.z, own.hi.z) * 2 <= box.Z,
	"the ship fits inside ShipBuilder.BERTH_BOX"
)

-- Asteroids: one of every size, built the way AsteroidSystem builds them.
print("Asteroids")
local AsteroidBuilder = requireModule(server.World.AsteroidBuilder)
local AsteroidConfig = requireModule(game:GetService("ReplicatedStorage").Shared.Config.Asteroids)
local seed = 0
local function rng()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
for index, sizeId in AsteroidConfig.SIZE_ORDER do
	local size = AsteroidConfig.SIZES[sizeId]
	for trial = 1, 20 do
		local built =
			AsteroidBuilder.build(index * 100 + trial, size, roblox.Vector3.new(0, 0, 0), rng)
		local model, rock, weak = built.model, built.rock, built.weakPoint
		local ok = model.PrimaryPart == rock
			and model.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Persistent
			and #built.parts == 4
			and not weak.CanCollide
			and weak.CanQuery
			and weak.Material == roblox.Enum.Material.Neon
			and model:GetAttribute("Size") == sizeId
		-- The weak point must poke out of the rock and not sit inside a lump.
		local exposed = weak.CFrame.Position.Magnitude + weak.Size.X / 2 > rock.Size.X / 2
		for _, part in built.parts do
			if part.Name:match("^Lump") then
				local gap = (weak.CFrame.Position - part.CFrame.Position).Magnitude
				exposed = exposed and gap > part.Size.X / 2
			end
		end
		-- Placement treats an asteroid as 1.4 x its radius (AsteroidSystem EXTENT).
		local extent = 0
		for _, part in built.parts do
			extent = math.max(extent, part.CFrame.Position.Magnitude + part.Size.X / 2)
		end
		if trial == 1 or not (ok and exposed and extent <= size.radius * 1.4) then
			check(ok, `{sizeId} asteroid has its rock, lumps and a non-colliding neon weak point`)
			check(exposed, `{sizeId} asteroid's weak point is exposed (trial {trial})`)
			check(
				extent <= size.radius * 1.4,
				`{sizeId} asteroid fits its placement extent ({extent} vs {size.radius * 1.4})`
			)
		end
		model:Destroy()
	end
end

check(#warnings == 0, `no warnings ({table.concat(warnings, "; ")})`)

print(`\n{failures} failed`)
if failures > 0 then
	process.exit(1)
end

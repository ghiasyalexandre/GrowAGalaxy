--!strict
-- Keeps the flight area stocked with asteroids and owns their state:
-- extraction progress, who has reserved each one, and breaking them.
--
-- Every SPAWN_INTERVAL seconds, while fewer than TARGET_COUNT exist, it
-- starts a few small clusters at random valid spots (Logic/AsteroidField),
-- never going over MAX_COUNT. Broken asteroids are replaced the same way.
-- The same pass releases reservations nobody has used for
-- RESERVATION_TIMEOUT seconds; releasing resets the asteroid's progress, so
-- abandoned work can't be finished by someone else for free.
--
-- MiningSystem does the mining itself and calls reserve() and breakAsteroid().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AsteroidBuilder = require(script.Parent.Parent.World.AsteroidBuilder)
local AsteroidField = require(ReplicatedStorage.Shared.Logic.AsteroidField)
local AsteroidConfig = require(ReplicatedStorage.Shared.Config.Asteroids)
local Config = require(ReplicatedStorage.Shared.Config)
local MiningMath = require(ReplicatedStorage.Shared.Logic.MiningMath)
local Types = require(ReplicatedStorage.Shared.Types)

type Vec3 = Types.Vec3
type Sphere = AsteroidField.Sphere

local A = Config.Asteroids

-- Lumps stick out past the main rock (see AsteroidBuilder), so placement
-- treats each asteroid as this much bigger than its radius.
local EXTENT = 1.4

export type Asteroid = {
	id: number,
	size: AsteroidConfig.SizeDef,
	model: Model,
	weakPoint: BasePart,
	position: Vector3,
	extent: number, -- placement radius, lumps included
	progress: number,
	weakProgress: number, -- the part of progress made on the weak point
	reservedBy: Player?,
	lastHit: number, -- os.clock() of the reserving player's last hit
	broken: boolean,
}

local AsteroidSystem = {}

local folder: Folder
local asteroids: { [number]: Asteroid } = {}
local byPart: { [BasePart]: Asteroid } = {}
local count = 0
local nextId = 1
local elapsed = 0
local random = Random.new()

local function rng(): number
	return random:NextNumber()
end

local function vec(v: Vector3): Vec3
	return { x = v.X, y = v.Y, z = v.Z }
end

-- Ships and players, each with the clearance asteroids must keep from it.
local function blockers(): { Sphere }
	local list: { Sphere } = {}
	local ships = Workspace:FindFirstChild("Ships")
	if ships then
		for _, ship in ships:GetChildren() do
			if ship:IsA("Model") then
				table.insert(
					list,
					{ position = vec(ship:GetPivot().Position), radius = A.SHIP_CLEARANCE }
				)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(list, { position = vec(root.Position), radius = A.PLAYER_CLEARANCE })
		end
	end
	return list
end

local function spheres(): { Sphere }
	local list: { Sphere } = {}
	for _, asteroid in asteroids do
		table.insert(list, { position = vec(asteroid.position), radius = asteroid.extent })
	end
	return list
end

local function spawnAt(position: Vec3, size: AsteroidConfig.SizeDef)
	local id = nextId
	nextId += 1
	local built =
		AsteroidBuilder.build(id, size, Vector3.new(position.x, position.y, position.z), rng)
	local asteroid: Asteroid = {
		id = id,
		size = size,
		model = built.model,
		weakPoint = built.weakPoint,
		position = built.rock.Position,
		extent = size.radius * EXTENT,
		progress = 0,
		weakProgress = 0,
		reservedBy = nil,
		lastHit = 0,
		broken = false,
	}
	for _, part in built.parts do
		byPart[part] = asteroid
	end
	asteroids[id] = asteroid
	count += 1
	built.model.Parent = folder
end

-- Tries to place one asteroid in the group around `centre` (or anywhere
-- when nil). Returns where it went, or nil if no valid spot was found.
local function placeOne(
	centre: Vec3?,
	plan: AsteroidField.GroupPlan,
	existing: { Sphere },
	blocked: { Sphere }
): Vec3?
	if count >= A.MAX_COUNT then
		return nil
	end
	local size = AsteroidField.varied(A.SIZES[AsteroidField.pickSize(rng)], rng)
	local extent = size.radius * EXTENT
	for _ = 1, A.PLACEMENT_ATTEMPTS do
		local position = if centre
			then AsteroidField.inGroup(centre, plan, rng)
			else AsteroidField.randomPoint(rng)
		if AsteroidField.isValid(position, extent, existing, blocked) then
			spawnAt(position, size)
			table.insert(existing, { position = position, radius = extent })
			return position
		end
	end
	return nil
end

-- Starts up to `clusters` clusters, staying within TARGET_COUNT.
local function spawnClusters(clusters: number)
	local existing = spheres()
	local blocked = blockers()
	for _ = 1, clusters do
		if count >= A.TARGET_COUNT then
			return
		end
		local plan = AsteroidField.groupPlan(rng)
		local first = placeOne(nil, plan, existing, blocked)
		if first == nil then
			continue
		end
		for _ = 2, plan.members do
			if count >= A.TARGET_COUNT then
				return
			end
			placeOne(first, plan, existing, blocked)
		end
	end
end

local function resetProgress(asteroid: Asteroid)
	asteroid.reservedBy = nil
	asteroid.progress = 0
	asteroid.weakProgress = 0
	asteroid.model:SetAttribute("ReservedBy", 0)
	asteroid.model:SetAttribute("Progress", 0)
end

local function releaseStale(now: number)
	for _, asteroid in asteroids do
		local owner = asteroid.reservedBy
		if
			owner
			and (owner.Parent ~= Players or now - asteroid.lastHit >= A.RESERVATION_TIMEOUT)
		then
			resetProgress(asteroid)
		end
	end
end

-- The asteroid a part belongs to, if it is one that can still be mined.
function AsteroidSystem.fromPart(part: Instance): Asteroid?
	local asteroid = if part:IsA("BasePart") then byPart[part] else nil
	if asteroid and not asteroid.broken then
		return asteroid
	end
	return nil
end

-- Reserves the asteroid for `player` (or renews their reservation). False
-- when someone else holds it.
function AsteroidSystem.reserve(asteroid: Asteroid, player: Player, now: number): boolean
	if asteroid.broken then
		return false
	end
	if
		not MiningMath.mayMine(
			asteroid.reservedBy,
			player,
			asteroid.lastHit,
			now,
			A.RESERVATION_TIMEOUT
		)
	then
		return false
	end
	if asteroid.reservedBy ~= player then
		-- Taking over a lapsed reservation starts from scratch.
		resetProgress(asteroid)
		asteroid.reservedBy = player
		asteroid.model:SetAttribute("ReservedBy", player.UserId)
	end
	asteroid.lastHit = now
	return true
end

-- Marks the asteroid broken and removes it. Returns false if it already was,
-- so a caller can pay out exactly once.
function AsteroidSystem.breakAsteroid(asteroid: Asteroid): boolean
	if asteroid.broken then
		return false
	end
	asteroid.broken = true
	asteroids[asteroid.id] = nil
	count -= 1
	local model = asteroid.model
	model:SetAttribute("Progress", 1)
	model:SetAttribute("Broken", true)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			byPart[part] = nil
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	-- Lingers briefly so clients see "Broken" and play the break effect.
	task.delay(A.BREAK_LINGER, function()
		model:Destroy()
	end)
	return true
end

function AsteroidSystem.getFolder(): Folder
	return folder
end

function AsteroidSystem.count(): number
	return count
end

function AsteroidSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Asteroids"
	folder.Parent = Workspace
end

function AsteroidSystem.start()
	-- Fill the field at once so the first players have something to mine.
	for _ = 1, 200 do
		if count >= A.TARGET_COUNT then
			break
		end
		spawnClusters(1)
	end

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < A.SPAWN_INTERVAL then
			return
		end
		elapsed = 0
		releaseStale(os.clock())
		spawnClusters(A.CLUSTERS_PER_PASS)
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, asteroid in asteroids do
			if asteroid.reservedBy == player then
				resetProgress(asteroid)
			end
		end
	end)
end

return AsteroidSystem

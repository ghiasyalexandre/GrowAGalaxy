--!strict
-- Spawns, boards, docks and stows ships. Each player has at most one ship in
-- the world. The server owns it; while its owner pilots it, their client
-- drives it (network ownership) and FlightGuard checks the result.
--
--   Launch  A hangar console (prompt tagged "LaunchPrompt") spawns the
--           player's active ship at a free berth: one of the ISS berths, or
--           their own station's berth. Launching again brings the ship back.
--   Board   The ship's BoardPrompt seats its owner. Nobody else can board
--           (clients also hide other players' prompts, and their own while
--           flying).
--   Exit    ShipRequest "exit" parks the ship where it is and floats the
--           pilot out beside it.
--   Dock    ShipRequest "dock", inside the ISS docking zone or the player's
--           own, below DOCK_MAX_SPEED, parks the ship at a free berth there.
--   Stow    Leaving the game or Return to Station removes the ship.
--
-- Ship model attributes: OwnerUserId, ShipId, MaxSpeed, BeamRange, and
-- Piloted (someone is flying it). BeamSystem adds the beam's state.
--
-- Cargo lives on the profile, never on the ship, so moving, stowing or
-- respawning a ship can't lose or duplicate it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Build = require(script.Parent.Parent.World.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local FlightGuard = require(script.Parent.FlightGuard)
local FlightMath = require(ReplicatedStorage.Shared.Logic.FlightMath)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local RegionSystem = require(script.Parent.RegionSystem)
local ShipBuilder = require(script.Parent.Parent.World.ShipBuilder)
local ShipStats = require(ReplicatedStorage.Shared.Logic.ShipStats)
local StationSystem = require(script.Parent.StationSystem)
local Teleport = require(script.Parent.Parent.Util.Teleport)
local Types = require(ReplicatedStorage.Shared.Types)
local WorldSystem = require(script.Parent.WorldSystem)

local M = Config.Movement

local ISS_BERTHS = { "Berth1", "Berth2", "Berth3" }
-- Room a floating player needs when leaving a ship.
local EXIT_BOX = Vector3.new(4, 6, 4)
local EXIT_POINTS = { "ExitLeft", "ExitRight", "ExitTop" }
-- Extra reach allowed beyond a prompt's activation distance (lag, avatar size).
local REACH_TOLERANCE = 8
-- The server sees the ship's speed slightly late, so it allows some slack.
local DOCK_SPEED_SLACK = 1.5
-- If the seat hasn't taken the pilot by then, boarding is undone.
local BOARD_TIMEOUT = 2

type Ship = {
	owner: Player,
	model: Model,
	hull: BasePart,
	seat: Seat,
	engine: LinearVelocity,
	steer: AlignOrientation,
	prompt: ProximityPrompt,
	info: Types.ShipInfo,
	piloting: boolean,
	parkedAt: number,
}

local ShipSystem = {}

local ships: { [Player]: Ship } = {}
local byModel: { [Model]: Ship } = {}
local lastLaunch: { [Player]: number } = {}
local folder: Folder
local requestLimit = RateLimiter.new(5, 2)

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and Teleport.rootOf(player) then
		return humanoid
	end
	return nil
end

local function infoFor(profile: Types.Profile): Types.ShipInfo
	local def = Config.Ships.BY_ID[profile.activeShip]
		or Config.Ships.BY_ID[Config.Ships.STARTER_SHIP]
	local stats = ShipStats.forProfile(profile)
	return {
		shipId = def.id,
		displayName = def.displayName,
		maxSpeed = stats.maxSpeed,
		acceleration = stats.acceleration,
		braking = stats.braking,
		turnRate = stats.turnRate,
		beamPower = stats.beamPower,
		beamRange = stats.beamRange,
		heatCapacity = stats.heatCapacity,
		coolingRate = stats.coolingRate,
		cargoCapacity = math.floor(stats.cargoCapacity),
	}
end

local function sendState(player: Player)
	local ship = ships[player]
	Net.ShipState:FireClient(
		player,
		if ship then ship.model else nil,
		if ship then ship.info else nil
	)
end

-- Is the berth clear of players and ships? `ignore` is the ship being moved
-- there, with its pilot. A berth taken only by someone else's parked ship
-- reports that ship, so it can be stowed if idle.
local function berthStatus(berth: CFrame, ignore: Ship?): (boolean, Ship?)
	local pilot = if ignore and ignore.piloting then ignore.owner.Character else nil
	local include: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(include, player.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include

	local parked: Ship? = nil
	for _, part in Workspace:GetPartBoundsInBox(berth, ShipBuilder.BERTH_BOX, params) do
		local model = part.Parent
		local ship = if model and model:IsA("Model") then byModel[model] else nil
		if pilot and part:IsDescendantOf(pilot) then
			continue
		elseif ship == nil then
			return false, nil -- a player is in the way
		elseif ship ~= ignore then
			if ship.piloting or (parked and parked ~= ship) then
				return false, nil
			end
			parked = ship
		end
	end
	return parked == nil, parked
end

local function issBerths(): { CFrame }
	local berths = {}
	for _, name in ISS_BERTHS do
		local marker = WorldSystem.getMarker(name)
		if marker then
			table.insert(berths, marker.CFrame)
		end
	end
	return berths
end

local despawn: (ship: Ship) -> ()

-- First free berth. If none is free, a berth holding someone else's ship
-- that has sat there unpiloted for BERTH_IDLE_STOW seconds is cleared.
local function pickBerth(berths: { CFrame }, ignore: Ship?): CFrame?
	local idlest: Ship? = nil
	local idlestBerth: CFrame? = nil
	for _, berth in berths do
		local free, parked = berthStatus(berth, ignore)
		if free then
			return berth
		end
		if parked and os.clock() - parked.parkedAt >= M.BERTH_IDLE_STOW then
			if idlest == nil or parked.parkedAt < idlest.parkedAt then
				idlest, idlestBerth = parked, berth
			end
		end
	end
	if idlest and idlestBerth then
		Notify.send(
			idlest.owner,
			"Your ship was stowed to free a berth. Launch it again from any hangar."
		)
		despawn(idlest)
		return idlestBerth
	end
	return nil
end

-- Puts the pilot's character beside the ship, at the first exit point with
-- room for them.
local function floatOut(ship: Ship, character: Model)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ship.model, character }
	params.RespectCanCollide = true

	local chosen: CFrame? = nil
	for _, name in EXIT_POINTS do
		local point = ship.hull:FindFirstChild(name)
		if point and point:IsA("Attachment") then
			local spot = CFrame.new(point.WorldPosition) * ship.hull.CFrame.Rotation
			chosen = chosen or spot
			if #Workspace:GetPartBoundsInBox(spot, EXIT_BOX, params) == 0 then
				chosen = spot
				break
			end
		end
	end
	if chosen then
		character:PivotTo(chosen)
	end
	FlightGuard.reset(ship.owner)
end

-- Stops piloting: frees the seat and parks the ship, anchored, where it is.
local function leaveSeat(ship: Ship)
	ship.piloting = false
	ship.model:SetAttribute("Piloted", false)
	local weld = ship.seat:FindFirstChild("SeatWeld")
	local occupant = ship.seat.Occupant
	if weld then
		weld:Destroy()
	end
	if occupant then
		occupant.Sit = false
	end
	ship.engine.VectorVelocity = Vector3.zero
	ship.hull.AssemblyLinearVelocity = Vector3.zero
	ship.hull.AssemblyAngularVelocity = Vector3.zero
	ship.hull.Anchored = true
	ship.parkedAt = os.clock()
	FlightGuard.untrack(ship.owner)
	sendState(ship.owner)
end

despawn = function(ship: Ship)
	if ship.piloting then
		leaveSeat(ship)
	end
	byModel[ship.model] = nil
	if ships[ship.owner] == ship then
		ships[ship.owner] = nil
	end
	ship.model:Destroy()
	sendState(ship.owner)
end

local function board(ship: Ship, player: Player)
	if player ~= ship.owner then
		Notify.send(player, `This ship belongs to {ship.owner.DisplayName}.`)
		return
	end
	local humanoid = humanoidOf(player)
	local root = Teleport.rootOf(player)
	if ship.piloting or humanoid == nil or root == nil or humanoid.SeatPart ~= nil then
		return
	end
	if (root.Position - ship.hull.Position).Magnitude > M.BOARD_DISTANCE + REACH_TOLERANCE then
		return
	end

	ship.engine.VectorVelocity = Vector3.zero
	ship.steer.CFrame = ship.hull.CFrame.Rotation
	ship.hull.Anchored = false
	local ok, problem = pcall(function()
		ship.hull:SetNetworkOwner(player)
	end)
	if not ok then
		warn(`[ShipSystem] Could not hand {player.Name} their ship: {problem}`)
		ship.hull.Anchored = true
		return
	end
	ship.piloting = true
	ship.model:SetAttribute("Piloted", true)
	humanoid.PlatformStand = false
	ship.seat:Sit(humanoid)
	FlightGuard.track(player, ship.hull, ship.info.maxSpeed)
	sendState(player)

	humanoid.Died:Once(function()
		if ship.piloting and ships[player] == ship then
			leaveSeat(ship)
		end
	end)
	task.delay(BOARD_TIMEOUT, function()
		if ship.piloting and ships[player] == ship and ship.seat.Occupant ~= humanoid then
			leaveSeat(ship)
		end
	end)
end

local function spawnShip(player: Player, info: Types.ShipInfo, berth: CFrame): Ship
	local region = RegionSystem.getRegion(player)
	local accent = if region then region.color else Config.World.COLORS.accent
	local model = ShipBuilder.build(info.shipId, berth, accent)
	model.Name = `Ship_{player.UserId}`
	model:SetAttribute("OwnerUserId", player.UserId)
	-- Read by every client's ship effects (engine glow, beam reach).
	model:SetAttribute("MaxSpeed", info.maxSpeed)
	model:SetAttribute("BeamRange", info.beamRange)
	-- An owned beam-colour cosmetic recolours the laser for everyone.
	local profile = DataSystem.getProfile(player)
	for cosmeticId, def in Config.Cosmetics.BY_ID do
		if
			def.kind == "BeamColor"
			and def.enabled
			and def.color
			and profile
			and profile.ownedCosmetics[cosmeticId]
		then
			model:SetAttribute("BeamColor", def.color)
			break
		end
	end
	model:SetAttribute("Piloted", false)
	model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer

	local hull = model:FindFirstChild("Hull") :: BasePart
	local prompt = hull:FindFirstChild("BoardPrompt") :: ProximityPrompt
	prompt.ObjectText = `{player.DisplayName}'s {info.displayName}`

	local ship: Ship = {
		owner = player,
		model = model,
		hull = hull,
		seat = model:FindFirstChild("PilotSeat") :: Seat,
		engine = hull:FindFirstChild("Engine") :: LinearVelocity,
		steer = hull:FindFirstChild("Steer") :: AlignOrientation,
		prompt = prompt,
		info = info,
		piloting = false,
		parkedAt = os.clock(),
	}

	prompt.Triggered:Connect(function(who)
		board(ship, who)
	end)
	ship.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = ship.seat.Occupant
		if occupant == nil then
			-- Left without asking (reset, died): park where it is.
			if ship.piloting then
				leaveSeat(ship)
			end
		elseif occupant.Parent ~= player.Character then
			local weld = ship.seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
	end)

	model.Parent = folder
	model:AddPersistentPlayer(player)
	ships[player] = ship
	byModel[model] = ship
	return ship
end

-- Spawns (or brings back) the player's active ship at a free berth of the
-- given hangar. Reach and ownership of the console are checked by the caller.
function ShipSystem.launch(player: Player, hangar: string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or humanoidOf(player) == nil then
		return
	end
	local now = os.clock()
	if now - (lastLaunch[player] or -math.huge) < M.LAUNCH_COOLDOWN then
		return
	end
	local existing = ships[player]
	if existing and existing.piloting then
		Notify.send(player, "Leave your ship before launching it again.")
		return
	end

	local berths: { CFrame } = {}
	if hangar == "ISS" then
		berths = issBerths()
	elseif hangar == "Station" then
		local station = StationSystem.getStation(player)
		if station then
			berths = { station.berth }
		end
	end
	local berth = pickBerth(berths, existing)
	if berth == nil then
		Notify.send(
			player,
			"Every berth here is busy. Move clear of the berths or try again in a moment."
		)
		return
	end

	lastLaunch[player] = now
	if existing then
		despawn(existing)
	end
	local ship = spawnShip(player, infoFor(profile), berth)
	sendState(player)
	DataSystem.addStat(player, "shipsLaunched", 1)
	Notify.send(
		player,
		if existing
			then `Your {ship.info.displayName} is back at a berth.`
			else `Your {ship.info.displayName} is ready at the berth. Float over and board it.`
	)
end

local function exit(player: Player)
	local ship = ships[player]
	if ship == nil or not ship.piloting then
		return
	end
	local character = player.Character
	leaveSeat(ship)
	if character then
		floatOut(ship, character)
	end
end

local function dock(player: Player)
	local ship = ships[player]
	if ship == nil or not ship.piloting then
		return
	end
	local position = ship.hull.Position

	local berths: { CFrame }? = nil
	local issZone = WorldSystem.getMarker("DockZone")
	local station = StationSystem.getStation(player)
	if issZone and FlightMath.insideBox(issZone.CFrame, issZone.Size, position) then
		berths = issBerths()
	elseif
		station and FlightMath.insideBox(station.dockZone.CFrame, station.dockZone.Size, position)
	then
		berths = { station.berth }
	end
	if berths == nil then
		Notify.send(player, "Fly into the docking area at the ISS or at your own station to dock.")
		return
	end
	if ship.hull.AssemblyLinearVelocity.Magnitude > M.DOCK_MAX_SPEED * DOCK_SPEED_SLACK then
		Notify.send(player, `Slow down below {M.DOCK_MAX_SPEED} to dock.`)
		return
	end
	local berth = pickBerth(berths, ship)
	if berth == nil then
		Notify.send(player, "Every berth here is busy. Try again in a moment.")
		return
	end

	local character = player.Character
	leaveSeat(ship)
	ship.model:PivotTo(berth)
	if character then
		floatOut(ship, character)
	end
	Notify.send(player, "Docked.")
end

-- Removes the player's ship, unseating them first. Used by Return to Station.
function ShipSystem.stow(player: Player): boolean
	local ship = ships[player]
	if ship == nil then
		return false
	end
	despawn(ship)
	return true
end

function ShipSystem.isPiloting(player: Player): boolean
	local ship = ships[player]
	return ship ~= nil and ship.piloting
end

-- The ship the player is flying right now and its stats, or nil.
function ShipSystem.getPiloted(player: Player): (Model?, Types.ShipInfo?)
	local ship = ships[player]
	if ship and ship.piloting then
		return ship.model, ship.info
	end
	return nil, nil
end

local function onLaunchPrompt(prompt: ProximityPrompt, player: Player)
	local hangar = prompt:GetAttribute("Hangar")
	local anchor = prompt.Parent
	local root = Teleport.rootOf(player)
	if type(hangar) ~= "string" or root == nil or anchor == nil or not anchor:IsA("BasePart") then
		return
	end
	if
		(root.Position - anchor.Position).Magnitude
		> prompt.MaxActivationDistance + REACH_TOLERANCE
	then
		return
	end
	if hangar == "Station" then
		local region = RegionSystem.getRegion(player)
		if region == nil or not prompt:IsDescendantOf(region.model) then
			Notify.send(
				player,
				"This hangar belongs to another player. Use your own station or the ISS."
			)
			return
		end
	end
	ShipSystem.launch(player, hangar)
end

local function hookLaunch(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Triggered:Connect(function(player)
			onLaunchPrompt(instance, player)
		end)
	end
end

function ShipSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Ships"
	folder.Parent = Workspace
end

function ShipSystem.start()
	for _, prompt in CollectionService:GetTagged(Build.LAUNCH_TAG) do
		hookLaunch(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Build.LAUNCH_TAG):Connect(hookLaunch)

	Net.ShipRequest.OnServerEvent:Connect(function(player: Player, action: unknown)
		if not requestLimit.allow(player) then
			return
		end
		if action == "exit" then
			exit(player)
		elseif action == "dock" then
			dock(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local ship = ships[player]
		if ship then
			despawn(ship)
		end
		lastLaunch[player] = nil
	end)
end

return ShipSystem

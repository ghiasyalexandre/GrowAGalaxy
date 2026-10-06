--!strict
-- Spawns, boards, docks and stows ships. Each player has at most one ship in
-- the world. The server owns it; while its owner pilots it, their client
-- drives it (network ownership) and FlightGuard checks the result.
--
--   Launch  The HUD's Launch Ship button (ShipRequest "launch") spawns the
--           active ship at the player's own station berth and seats them in
--           it (a station hangar console, prompt tagged "LaunchPrompt", does
--           the same without seating). Raids use spawnAndBoard. The ISS has
--           no berths. Launching again brings the ship back.
--   Board   The ship's BoardPrompt seats its owner. Nobody else can board
--           (clients also hide other players' prompts, and their own while
--           flying).
--   Exit    ShipRequest "exit" parks the ship where it is and floats the
--           pilot out beside it.
--   Dock    ShipRequest "dock", inside the player's own docking zone below
--           DOCK_MAX_SPEED, parks the ship at their berth.
--   Stow    Leaving the game or a travel button removes the ship.
--   Destroy PvP (CombatSystem) blows the ship up: the pilot floats free,
--           every client draws the explosion (ShipDestroyed), and the
--           owner can relaunch after Config.Combat.RELAUNCH_DELAY.
--
-- Ship model attributes: OwnerUserId, ShipId, MaxSpeed, BeamRange, Health,
-- Paint, and Piloted (someone is flying it). BeamSystem adds the beam's state.
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

local M = Config.Movement

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
local destroyedAt: { [Player]: number } = {}
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
		boostMultiplier = stats.boostMultiplier,
		boostDuration = stats.boostDuration,
		boostRecharge = stats.boostRecharge,
		hull = stats.hull,
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

local despawn: (ship: Ship) -> ()
local launchAndBoard: (player: Player) -> ()

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
			"Your ship was stowed to free a dock. Launch it again from any hangar."
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
	-- Boost is driven by the pilot's client, so the guard allows the boosted
	-- top speed (Config.Ships boostMultiplier).
	FlightGuard.track(player, ship.hull, ship.info.maxSpeed * ship.info.boostMultiplier)
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
	local profile = DataSystem.getProfile(player)
	local loadout = profile and profile.loadouts[info.shipId]
	local look = {
		laserColor = loadout and loadout.laserColor,
		boostColor = loadout and loadout.boostColor,
	}
	local model = ShipBuilder.build(info.shipId, berth, accent, look)
	model.Name = `Ship_{player.UserId}`
	model:SetAttribute("OwnerUserId", player.UserId)
	-- Read by every client's ship effects (engine glow, beam reach).
	model:SetAttribute("MaxSpeed", info.maxSpeed)
	model:SetAttribute("BeamRange", info.beamRange)
	model:SetAttribute("Health", 1)
	local shipDef = Config.Ships.BY_ID[info.shipId]
	model:SetAttribute("Paint", if shipDef then shipDef.paint else Config.World.COLORS.hull)
	-- Without a chosen laser colour, an owned beam-colour cosmetic recolours
	-- the laser for everyone.
	for cosmeticId, def in Config.Cosmetics.BY_ID do
		if
			look.laserColor == nil
			and def.kind == "BeamColor"
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
	local rebuilt = (destroyedAt[player] or -math.huge) + Config.Combat.RELAUNCH_DELAY
	if now < rebuilt then
		Notify.send(
			player,
			`Your ship is being rebuilt. Launch again in {math.ceil(rebuilt - now)}s.`
		)
		return
	end

	local berths: { CFrame } = {}
	if hangar == "Station" then
		local station = StationSystem.getStation(player)
		if station then
			berths = { station.berth }
		end
	end
	local berth = pickBerth(berths, existing)
	if berth == nil then
		Notify.send(
			player,
			"Every dock here is busy. Move clear of the docks or try again in a moment."
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
			then `Your {ship.info.displayName} is back at a dock.`
			else `Your {ship.info.displayName} is ready at the dock. Float over and board it.`
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
	local station = StationSystem.getStation(player)
	if
		station and FlightMath.insideBox(station.dockZone.CFrame, station.dockZone.Size, position)
	then
		berths = { station.berth }
	end
	if berths == nil then
		Notify.send(player, "Fly into the docking area at your own station to dock.")
		return
	end
	if ship.hull.AssemblyLinearVelocity.Magnitude > M.DOCK_MAX_SPEED * DOCK_SPEED_SLACK then
		Notify.send(player, `Slow down below {M.DOCK_MAX_SPEED} to dock.`)
		return
	end
	local berth = pickBerth(berths, ship)
	if berth == nil then
		Notify.send(player, "Every dock here is busy. Try again in a moment.")
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

-- Recolours the player's spawned ship after its colours changed.
function ShipSystem.refreshLook(player: Player)
	local ship = ships[player]
	local profile = DataSystem.getProfile(player)
	if ship == nil or profile == nil then
		return
	end
	local shipId = ship.model:GetAttribute("ShipId")
	local loadout = if type(shipId) == "string" then profile.loadouts[shipId] else nil
	if loadout == nil then
		return
	end
	local region = RegionSystem.getRegion(player)
	ShipBuilder.applyColors(
		ship.model,
		{ laserColor = loadout.laserColor, boostColor = loadout.boostColor },
		if region then region.color else Config.World.COLORS.accent
	)
end

-- Blows up the player's ship (PvP): the pilot floats out, every client
-- draws the explosion, and relaunching waits RELAUNCH_DELAY seconds.
function ShipSystem.destroy(player: Player)
	local ship = ships[player]
	if ship == nil then
		return
	end
	local pivot = ship.hull.CFrame
	local _, size = ship.model:GetBoundingBox()
	local paint = ship.model:GetAttribute("Paint")
	local character = player.Character
	if ship.piloting then
		leaveSeat(ship)
		if character then
			floatOut(ship, character)
		end
	end
	destroyedAt[player] = os.clock()
	Net.ShipDestroyed:FireAllClients(
		pivot,
		size,
		if type(paint) == "string" then paint else Config.World.COLORS.hull,
		player.UserId
	)
	despawn(ship)
end

-- The owner of the ship a part belongs to, the ship, and whether it's
-- being piloted. Nil for anything that isn't part of a spawned ship.
function ShipSystem.shipOf(part: Instance): (Player?, Model?, boolean)
	local current: Instance? = part
	while current and current.Parent ~= folder do
		current = current.Parent
	end
	local ship = if current and current:IsA("Model") then byModel[current] else nil
	if ship == nil then
		return nil, nil, false
	end
	return ship.owner, ship.model, ship.piloting
end

-- Removes the player's ship, unseating them first. Used by the travel buttons.
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

-- The HUD's Launch Ship button: spawns the active ship at the player's own
-- station berth, moves them beside it and seats them, wherever they were.
launchAndBoard = function(player: Player)
	local before = ships[player]
	ShipSystem.launch(player, "Station")
	local ship = ships[player]
	if ship == nil or ship == before or ship.piloting then
		return
	end
	if Teleport.character(player, ship.seat.CFrame * CFrame.new(0, 3, 0)) then
		FlightGuard.reset(player)
		if ships[player] == ship then
			board(ship, player)
		end
	end
end

-- Raids (RaidSystem): puts the player's active ship at `cframe` (no berth
-- needed), moves them beside it and seats them. Any ship they had out is
-- removed first. Yields; returns true once they're piloting it.
function ShipSystem.spawnAndBoard(player: Player, cframe: CFrame): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil or humanoidOf(player) == nil then
		return false
	end
	local existing = ships[player]
	if existing then
		despawn(existing)
	end
	local ship = spawnShip(player, infoFor(profile), cframe)
	sendState(player)
	if not Teleport.character(player, ship.seat.CFrame * CFrame.new(0, 3, 0)) then
		return false
	end
	FlightGuard.reset(player)
	if ships[player] ~= ship then
		return false
	end
	board(ship, player)
	return ship.piloting
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
		elseif action == "launch" then
			task.spawn(launchAndBoard, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local ship = ships[player]
		if ship then
			despawn(ship)
		end
		lastLaunch[player] = nil
		destroyedAt[player] = nil
	end)
end

return ShipSystem

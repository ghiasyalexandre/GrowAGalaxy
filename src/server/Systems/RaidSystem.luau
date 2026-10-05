--!strict
-- Death Star raids (Config.Raids, Logic/RaidMath).
--
-- Queues: the Saturn V beacon on the ISS raid platform has one pad per
-- difficulty. Stepping on a pad, its Join prompt, or RaidRequest
-- ("join", difficulty) puts the player in that queue (and out of any other);
-- the prompt again, or RaidRequest "leave", takes them out. A queue launches
-- QUEUE_COUNTDOWN after its first player joined (FULL_COUNTDOWN once full),
-- as soon as no raid of that difficulty is running.
--
-- Raids: the Death Star appears at the difficulty's arena; every queued
-- player is put in their active ship facing it (ShipSystem.spawnAndBoard).
-- BeamSystem hands each shot to shot(): hits on the boss damage it (the weak
-- point more; it jumps to a new spot every WEAK_POINT_MOVE_SHARE of health
-- lost), hits on a drone destroy it. The boss's moves (see Config.Raids):
-- turbolaser volleys, homing drones, shockwave rings, the superlaser and
-- bombardment, each on its own timer, faster once enraged; the big ones never
-- overlap. All of them hurt ships through CombatSystem.damageShip. A raider
-- whose ship is destroyed, who leaves their ship or the game is out. The raid
-- is won when the boss's health runs out, lost when TIME_LIMIT passes or
-- nobody is left. Winners who helped (RaidMath.earnsReward) get the
-- difficulty's fixed reward. Then everyone still there goes back to the ISS.
--
-- Clients draw every effect from RaidEvent: "bolt", "drone" (one destroyed),
-- "shockCharge", "shockwave", "charge", "superlaser", "bombard",
-- "bombardBlast", "weakMoved", "enraged", "bossDown", "result".
--
-- Pad attributes (for clients): Count, StartsAt (server time, 0 = no
-- countdown), Busy (a raid is running). Player attributes: RaidQueue and
-- Raid (the difficulty). Boss model attributes: Difficulty, Health (0..1),
-- EndsAt (server time), Raiders (still flying), Enraged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatSystem = require(script.Parent.CombatSystem)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local FlightGuard = require(script.Parent.FlightGuard)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RaidBuilder = require(script.Parent.Parent.World.RaidBuilder)
local RaidMath = require(ReplicatedStorage.Shared.Logic.RaidMath)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ShipSystem = require(script.Parent.ShipSystem)
local Teleport = require(script.Parent.Parent.Util.Teleport)
local Types = require(ReplicatedStorage.Shared.Types)
local WorldSystem = require(script.Parent.WorldSystem)

local R = Config.Raids
local TICK = 0.25
local TOUCH_COOLDOWN = 1.5
-- Seconds after the raid starts before each move first comes.
local FIRST_MOVE: { [string]: number } =
	{ volley = 4, drones = 8, shockwave = 13, superlaser = 20, bombard = 17 }

type Queue = { players: { Player }, firstAt: number?, filledAt: number? }
type Raider = { damage: number, flying: boolean }
type Drone = {
	part: BasePart,
	target: Player,
	heading: Vector3,
	diesAt: number,
	damage: number,
}
type Wave = {
	center: Vector3,
	normal: Vector3,
	startsAt: number,
	reached: number, -- radius already swept
	damage: number,
	hit: { [Player]: boolean },
}
type Raid = {
	difficulty: string,
	model: Model,
	body: BasePart,
	weak: BasePart,
	weakDirection: RaidMath.Point,
	weakStage: number,
	health: number,
	max: number,
	endsAt: number,
	nextMove: { [string]: number },
	bigUntil: number,
	enraged: boolean,
	drones: { Drone },
	waves: { Wave },
	raiders: { [Player]: Raider },
	over: boolean,
}

local RaidSystem = {}

local queues: { [string]: Queue } = {}
local raids: { [string]: Raid } = {}
local pads: { [string]: Model } = {}
local folder: Folder
local limit = RateLimiter.new(4, 1)
local lastTouch: { [Player]: number } = {}
local elapsed = 0
local random = Random.new()

local function rng(): number
	return random:NextNumber()
end

local function v(point: Vector3): RaidMath.Point
	return { x = point.X, y = point.Y, z = point.Z }
end

local function vec(point: RaidMath.Point): Vector3
	return Vector3.new(point.x, point.y, point.z)
end

local function arenaCenter(difficulty: string): Vector3
	local a = R.BY_ID[difficulty].arena
	return Vector3.new(a.x, a.y, a.z)
end

local function queueOf(player: Player): string?
	for difficulty, queue in queues do
		if table.find(queue.players, player) then
			return difficulty
		end
	end
	return nil
end

local function raidOf(player: Player): Raid?
	for _, raid in raids do
		if raid.raiders[player] then
			return raid
		end
	end
	return nil
end

local function leaveQueue(player: Player)
	for _, queue in queues do
		local index = table.find(queue.players, player)
		if index then
			table.remove(queue.players, index)
			if #queue.players == 0 then
				queue.firstAt, queue.filledAt = nil, nil
			elseif #queue.players < R.MAX_RAIDERS then
				queue.filledAt = nil
			end
		end
	end
	if player.Parent then
		player:SetAttribute("RaidQueue", nil)
	end
end

local function join(player: Player, difficulty: string)
	local queue = queues[difficulty]
	if queue == nil or DataSystem.getProfile(player) == nil then
		return
	end
	if raidOf(player) then
		Notify.send(player, "You're already in a raid.")
		return
	end
	if table.find(queue.players, player) then
		return
	end
	if #queue.players >= R.MAX_RAIDERS then
		Notify.send(
			player,
			`The {difficulty} queue is full. Try another difficulty or wait for the next raid.`
		)
		return
	end
	leaveQueue(player)
	table.insert(queue.players, player)
	local now = Workspace:GetServerTimeNow()
	queue.firstAt = queue.firstAt or now
	if #queue.players >= R.MAX_RAIDERS then
		queue.filledAt = now
	end
	player:SetAttribute("RaidQueue", difficulty)
	Notify.send(
		player,
		`Joined the {difficulty} raid queue. Use the pad's prompt or Leave to cancel.`
	)
end

-- Sends a raider home to the ISS raid platform, without their ship.
local function sendHome(player: Player)
	player:SetAttribute("Raid", nil)
	if player.Parent ~= Players then
		return
	end
	ShipSystem.stow(player)
	local marker = WorldSystem.getMarker("DockingSpawn")
	if marker and Teleport.character(player, marker.CFrame) then
		FlightGuard.reset(player)
	end
end

local function knockOut(raid: Raid, player: Player, reason: string)
	local raider = raid.raiders[player]
	if raider == nil or not raider.flying then
		return
	end
	raider.flying = false
	Notify.send(player, reason)
	task.delay(R.OUT_DELAY, function()
		if not raid.over and raid.raiders[player] then
			sendHome(player)
		end
	end)
end

local function flyingRaiders(raid: Raid): { Player }
	local list: { Player } = {}
	for player, raider in raid.raiders do
		if raider.flying then
			table.insert(list, player)
		end
	end
	return list
end

local function shipPosition(player: Player): Vector3?
	local model = ShipSystem.getPiloted(player)
	local hull = model and model.PrimaryPart
	return if hull then hull.Position else nil
end

local function isFlying(raid: Raid, player: Player): boolean
	local raider = raid.raiders[player]
	return raider ~= nil and raider.flying
end

local function hurt(raid: Raid, player: Player, amount: number)
	if CombatSystem.damageShip(player, amount) then
		knockOut(raid, player, "Your ship was destroyed. You're out of this raid.")
	end
end

local function finish(raid: Raid, won: boolean)
	if raid.over then
		return
	end
	raid.over = true
	local def = R.BY_ID[raid.difficulty]
	if won then
		local cf = raid.body.CFrame
		Net.RaidEvent:FireAllClients("bossDown", cf, raid.body.Size)
		task.delay(1.5, function()
			raid.model:Destroy()
		end)
	else
		raid.model:Destroy()
	end
	for player, raider in raid.raiders do
		if player.Parent ~= Players then
			continue
		end
		if won and RaidMath.earnsReward(raider.damage, raid.max, raider.flying) then
			DataSystem.grantRaidReward(player, def.reward)
			DataSystem.addStat(player, "raidsWon", 1)
			DataSystem.addStat(player, `raidsWon{raid.difficulty}`, 1)
			Net.RaidEvent:FireClient(player, "result", true, raid.difficulty)
		else
			Net.RaidEvent:FireClient(player, "result", false, raid.difficulty)
		end
	end
	task.delay(R.END_DELAY, function()
		for player in raid.raiders do
			if player.Parent == Players and player:GetAttribute("Raid") == raid.difficulty then
				task.spawn(sendHome, player)
			end
		end
		if raids[raid.difficulty] == raid then
			raids[raid.difficulty] = nil
		end
	end)
end

local function start(difficulty: string, players: { Player })
	local center = arenaCenter(difficulty)
	local model, body, weak = RaidBuilder.boss(CFrame.new(center), folder)
	local max = RaidMath.bossHealth(difficulty, #players)
	local now = Workspace:GetServerTimeNow()
	local nextMove: { [string]: number } = {}
	for move, delay in FIRST_MOVE do
		nextMove[move] = now + delay
	end
	local raid: Raid = {
		difficulty = difficulty,
		model = model,
		body = body,
		weak = weak,
		weakDirection = v(Vector3.new(0, 0.42, -1).Unit),
		weakStage = 0,
		health = max,
		max = max,
		endsAt = now + R.TIME_LIMIT,
		nextMove = nextMove,
		bigUntil = 0,
		enraged = false,
		drones = {},
		waves = {},
		raiders = {},
		over = false,
	}
	model:SetAttribute("Difficulty", difficulty)
	model:SetAttribute("Health", 1)
	model:SetAttribute("EndsAt", raid.endsAt)
	model:SetAttribute("Raiders", #players)
	model:SetAttribute("Enraged", false)
	raids[difficulty] = raid

	for index, player in players do
		raid.raiders[player] = { damage = 0, flying = true }
		player:SetAttribute("RaidQueue", nil)
		player:SetAttribute("Raid", difficulty)
		-- Spread along an arc in front of the boss, facing it.
		local angle = math.rad((index - (#players + 1) / 2) * 14)
		local spot = center + Vector3.new(math.sin(angle), 0.1, -math.cos(angle)) * R.START_DISTANCE
		task.spawn(function()
			if not ShipSystem.spawnAndBoard(player, CFrame.lookAt(spot, center)) then
				knockOut(raid, player, "Couldn't put you in your ship, so you're out of this raid.")
			else
				Notify.send(
					player,
					`{difficulty} raid: destroy the Death Star! Hit its green weak point; it moves as the boss takes damage.`
				)
			end
		end)
	end
end

-- Moves ---------------------------------------------------------------------

local function volley(raid: Raid, move: { bolts: number, damage: number })
	local targets = flyingRaiders(raid)
	for _ = 1, math.min(move.bolts, #targets * 2) do
		local player = targets[math.random(#targets)]
		local aim = shipPosition(player)
		if aim == nil then
			continue
		end
		local center = raid.body.Position
		local from = center + (aim - center).Unit * raid.body.Size.X * 0.5
		local travel = RaidMath.boltTime((aim - from).Magnitude)
		Net.RaidEvent:FireAllClients("bolt", from, aim, travel)
		task.delay(travel, function()
			local at = shipPosition(player)
			if
				not raid.over
				and at
				and isFlying(raid, player)
				and RaidMath.boltHits(v(aim), v(at))
			then
				hurt(raid, player, move.damage)
			end
		end)
	end
end

local function launchDrones(raid: Raid, move: { count: number, damage: number }, now: number)
	local targets = flyingRaiders(raid)
	if #targets == 0 then
		return
	end
	local center = raid.body.Position
	for i = 1, move.count do
		local target = targets[(i - 1) % #targets + 1]
		local aim = shipPosition(target)
		if aim == nil then
			continue
		end
		-- Out of the hull on the side facing the target, spread a little.
		local out = ((aim - center).Unit + vec(RaidMath.direction(rng(), rng())) * 0.35).Unit
		local part = RaidBuilder.drone(center + out * R.BOSS_SIZE * 0.6, raid.model)
		table.insert(raid.drones, {
			part = part,
			target = target,
			heading = out,
			diesAt = now + R.DRONE_LIFETIME,
			damage = move.damage,
		})
	end
end

local function popDrone(drone: Drone)
	if drone.part.Parent then
		Net.RaidEvent:FireAllClients("drone", drone.part.Position)
		drone.part:Destroy()
	end
end

-- Steers every drone towards its target; runs every frame for smooth flight.
local function stepDrones(raid: Raid, dt: number, now: number)
	for i = #raid.drones, 1, -1 do
		local drone = raid.drones[i]
		if drone.part.Parent == nil then -- shot down
			table.remove(raid.drones, i)
			continue
		end
		if now >= drone.diesAt then
			popDrone(drone)
			table.remove(raid.drones, i)
			continue
		end
		if not isFlying(raid, drone.target) then
			local others = flyingRaiders(raid)
			if #others == 0 then
				continue
			end
			drone.target = others[math.random(#others)]
		end
		local aim = shipPosition(drone.target)
		if aim == nil then
			continue
		end
		local position = drone.part.Position
		local toward = aim - position
		if toward.Magnitude <= R.DRONE_HIT_RADIUS then
			hurt(raid, drone.target, drone.damage)
			popDrone(drone)
			table.remove(raid.drones, i)
			continue
		end
		-- Turn at most DRONE_TURN radians per second towards the target.
		local want = toward.Unit
		local angle = math.acos(math.clamp(drone.heading:Dot(want), -1, 1))
		local turn = R.DRONE_TURN * dt
		if angle > turn then
			local turned = drone.heading:Lerp(want, turn / angle)
			drone.heading = if turned.Magnitude > 1e-3 then turned.Unit else want
		else
			drone.heading = want
		end
		local nextPosition = position + drone.heading * R.DRONE_SPEED * dt
		drone.part.CFrame = CFrame.lookAt(nextPosition, nextPosition + drone.heading)
	end
end

local function shockwave(raid: Raid, move: { damage: number }, now: number)
	local targets = flyingRaiders(raid)
	if #targets == 0 then
		return
	end
	local center = raid.body.Position
	local aim = shipPosition(targets[math.random(#targets)]) or center + Vector3.zAxis
	-- A plane through the boss containing a raider, at a random roll.
	local toward = (aim - center).Unit
	local normal = toward:Cross(vec(RaidMath.direction(rng(), rng())))
	if normal.Magnitude < 1e-3 then
		normal = toward:Cross(Vector3.yAxis)
	end
	normal = normal.Unit
	Net.RaidEvent:FireAllClients("shockCharge", center, normal, R.SHOCKWAVE_CHARGE)
	table.insert(raid.waves, {
		center = center,
		normal = normal,
		startsAt = now + R.SHOCKWAVE_CHARGE,
		reached = 0,
		damage = move.damage,
		hit = {},
	})
	task.delay(R.SHOCKWAVE_CHARGE, function()
		if not raid.over then
			Net.RaidEvent:FireAllClients("shockwave", center, normal)
		end
	end)
end

-- Grows every shockwave ring and hurts raiders it sweeps over.
local function stepWaves(raid: Raid, now: number)
	for i = #raid.waves, 1, -1 do
		local wave = raid.waves[i]
		if now < wave.startsAt then
			continue
		end
		local radius = (now - wave.startsAt) * R.SHOCKWAVE_SPEED
		for _, player in flyingRaiders(raid) do
			local at = shipPosition(player)
			if
				at
				and not wave.hit[player]
				and RaidMath.ringHits(v(at), v(wave.center), v(wave.normal), wave.reached, radius)
			then
				wave.hit[player] = true
				hurt(raid, player, wave.damage)
			end
		end
		wave.reached = radius
		if radius > R.SHOCKWAVE_RANGE then
			table.remove(raid.waves, i)
		end
	end
end

local function superlaser(raid: Raid, move: { damage: number })
	local targets = flyingRaiders(raid)
	if #targets == 0 then
		return
	end
	local aim = shipPosition(targets[math.random(#targets)])
	if aim == nil then
		return
	end
	local from = raid.weak.Position
	local to = from + (aim - from).Unit * (R.START_DISTANCE * 3)
	Net.RaidEvent:FireAllClients("charge", from, to, R.SUPERLASER_CHARGE)
	task.delay(R.SUPERLASER_CHARGE, function()
		if raid.over then
			return
		end
		Net.RaidEvent:FireAllClients("superlaser", from, to)
		for _, player in flyingRaiders(raid) do
			local at = shipPosition(player)
			if at and RaidMath.distanceToSegment(v(at), v(from), v(to)) <= R.SUPERLASER_WIDTH then
				hurt(raid, player, move.damage)
			end
		end
	end)
end

local function bombard(raid: Raid, move: { count: number, damage: number })
	local targets = flyingRaiders(raid)
	if #targets == 0 then
		return
	end
	-- One blast where each raider is now, the rest scattered around them.
	local spots: { Vector3 } = {}
	for _, player in targets do
		local at = shipPosition(player)
		if at and #spots < move.count then
			table.insert(spots, at)
		end
	end
	if #spots == 0 then
		return
	end
	local anchors = table.clone(spots)
	while #spots < move.count do
		local around = anchors[math.random(#anchors)]
		local offset = vec(RaidMath.direction(rng(), rng()))
			* R.BOMBARD_SPREAD
			* (0.4 + rng() * 0.6)
		table.insert(spots, around + offset)
	end
	Net.RaidEvent:FireAllClients("bombard", spots, R.BOMBARD_DELAY)
	task.delay(R.BOMBARD_DELAY, function()
		if raid.over then
			return
		end
		Net.RaidEvent:FireAllClients("bombardBlast", spots)
		for _, player in flyingRaiders(raid) do
			local at = shipPosition(player)
			if at == nil then
				continue
			end
			for _, spot in spots do
				if RaidMath.inBlast(v(spot), v(at)) then
					hurt(raid, player, move.damage)
					break
				end
			end
		end
	end)
end

-- True (and the move's timer restarted) when the move is due now. A big
-- move also waits for the last big move's BIG_MOVE_GAP.
local function due(raid: Raid, name: string, interval: number, now: number, big: boolean): boolean
	if now < raid.nextMove[name] or (big and now < raid.bigUntil) then
		return false
	end
	raid.nextMove[name] = now + RaidMath.moveInterval(interval, raid.enraged)
	if big then
		raid.bigUntil = now + R.BIG_MOVE_GAP
	end
	return true
end

local function moveWeakPoint(raid: Raid)
	local from = raid.weak.Position
	raid.weakDirection = RaidMath.nextWeakDirection(raid.weakDirection, rng)
	RaidBuilder.placeWeakPoint(raid.weak, raid.body.Position, vec(raid.weakDirection))
	Net.RaidEvent:FireAllClients("weakMoved", from, raid.weak.Position)
end

local function tickRaid(raid: Raid, now: number)
	if raid.over then
		return
	end
	-- Raiders who left their ship or the game are out.
	for player, raider in raid.raiders do
		if raider.flying and (player.Parent ~= Players or ShipSystem.getPiloted(player) == nil) then
			if player.Parent == Players then
				knockOut(raid, player, "You left your ship, so you're out of this raid.")
			else
				raider.flying = false
			end
		end
	end
	local flying = flyingRaiders(raid)
	raid.model:SetAttribute("Raiders", #flying)
	if #flying == 0 or now >= raid.endsAt then
		finish(raid, false)
		return
	end

	local enraged = RaidMath.enraged(raid.health, raid.max)
	if enraged and not raid.enraged then
		raid.enraged = true
		raid.model:SetAttribute("Enraged", true)
		Net.RaidEvent:FireAllClients("enraged", raid.body.Position)
	end

	local moves = R.BY_ID[raid.difficulty].moves
	if due(raid, "volley", moves.volley.interval, now, false) then
		volley(raid, moves.volley)
	end
	local drones = moves.drones
	if drones and due(raid, "drones", drones.interval, now, false) then
		launchDrones(raid, drones, now)
	end
	local wave = moves.shockwave
	if wave and due(raid, "shockwave", wave.interval, now, true) then
		shockwave(raid, wave, now)
	end
	local laser = moves.superlaser
	if laser and due(raid, "superlaser", laser.interval, now, true) then
		superlaser(raid, laser)
	end
	local blast = moves.bombard
	if blast and due(raid, "bombard", blast.interval, now, true) then
		bombard(raid, blast)
	end
end

local function tickQueues(now: number)
	for _, difficulty in R.ORDER do
		local queue = queues[difficulty]
		local pad = pads[difficulty]
		-- Drop players who left.
		for i = #queue.players, 1, -1 do
			if queue.players[i].Parent ~= Players then
				table.remove(queue.players, i)
			end
		end
		if #queue.players == 0 then
			queue.firstAt, queue.filledAt = nil, nil
		end
		local busy = raids[difficulty] ~= nil
		local startsAt = if queue.firstAt
			then RaidMath.startTime(queue.firstAt, queue.filledAt)
			else 0
		if #queue.players > 0 and not busy and now >= startsAt then
			local players = table.clone(queue.players)
			table.clear(queue.players)
			queue.firstAt, queue.filledAt = nil, nil
			start(difficulty, players)
			busy = true
			startsAt = 0
		end
		if pad then
			pad:SetAttribute("Count", #queue.players)
			pad:SetAttribute("StartsAt", startsAt)
			pad:SetAttribute("Busy", busy)
			local sign = pad:FindFirstChild("Sign", true)
			local queueLabel = sign and sign:FindFirstChild("Queue", true)
			local statusLabel = sign and sign:FindFirstChild("Status", true)
			if queueLabel and queueLabel:IsA("TextLabel") then
				queueLabel.Text = `{#queue.players} / {R.MAX_RAIDERS} in queue`
			end
			if statusLabel and statusLabel:IsA("TextLabel") then
				statusLabel.Text = if busy and #queue.players > 0
					then "Raid in progress: you're next"
					elseif busy then "Raid in progress"
					elseif #queue.players > 0 then `Launching in {math.max(
						math.ceil(startsAt - now),
						0
					)}s`
					else "Step on to join"
			end
		end
	end
end

local damageBoss: (raid: Raid, player: Player, damage: number) -> ()

-- A rocket blast (RocketSystem) in the player's raid: damages the boss if
-- the blast reaches its hull, and pops any drones it catches.
function RaidSystem.blast(player: Player, center: Vector3, radius: number, power: number)
	local raid = raidOf(player)
	if raid == nil or raid.over then
		return
	end
	for _, drone in raid.drones do
		if drone.part.Parent and (drone.part.Position - center).Magnitude <= radius then
			popDrone(drone)
		end
	end
	if (raid.body.Position - center).Magnitude <= radius + R.BOSS_SIZE / 2 then
		damageBoss(raid, player, RaidMath.bossDamage(power, false))
	end
end

-- Called by BeamSystem for each shot fired.
function RaidSystem.shot(player: Player, model: Model, info: Types.ShipInfo, aim: Vector3)
	local raid = raidOf(player)
	local hull = model.PrimaryPart
	local muzzle = hull and hull:FindFirstChild("BeamOrigin")
	if raid == nil or raid.over or hull == nil or muzzle == nil or not muzzle:IsA("Attachment") then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { raid.model }
	local result = Workspace:Raycast(
		muzzle.WorldPosition,
		hull.CFrame:VectorToWorldSpace(aim) * info.beamRange,
		params
	)
	if result == nil then
		return
	end
	if result.Instance:GetAttribute("Drone") then
		for _, drone in raid.drones do
			if drone.part == result.Instance then
				popDrone(drone)
				break
			end
		end
		return
	end
	damageBoss(raid, player, RaidMath.bossDamage(info.beamPower, result.Instance == raid.weak))
end

-- Takes `damage` off the boss for `player`: the win, and the weak point's
-- jump every WEAK_POINT_MOVE_SHARE.
damageBoss = function(raid: Raid, player: Player, damage: number)
	raid.health = math.max(raid.health - damage, 0)
	raid.raiders[player].damage += damage
	raid.model:SetAttribute("Health", math.floor(raid.health / raid.max * 1000) / 1000)
	if raid.health <= 0 then
		finish(raid, true)
		return
	end
	local stage = RaidMath.weakStage(raid.health, raid.max)
	if stage > raid.weakStage then
		raid.weakStage = stage
		moveWeakPoint(raid)
	end
end

function RaidSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Raids"
	folder.Parent = Workspace
	for _, difficulty in R.ORDER do
		queues[difficulty] = { players = {} }
	end
end

function RaidSystem.start()
	local marker = WorldSystem.getMarker("RaidBeacon")
	if marker == nil then
		warn("[RaidSystem] The ISS has no RaidBeacon marker; raids are unavailable")
		return
	end
	local floor = CFrame.new(marker.Position)
	local area = Instance.new("Model")
	area.Name = "RaidBeaconArea"
	area.Parent = marker.Parent
	RaidBuilder.beacon(floor, area)
	for _, difficulty in R.ORDER do
		local def = R.BY_ID[difficulty]
		-- Pads face the airlock (-X), spread around the rocket.
		local angle = math.rad(180 + def.pad.angle)
		local spot = floor
			* CFrame.new(math.cos(angle) * R.PAD_DISTANCE, 0, math.sin(angle) * R.PAD_DISTANCE)
		local pad = RaidBuilder.pad(def, spot, area)
		pads[difficulty] = pad
		local circle = pad:FindFirstChild("Circle") :: BasePart
		circle.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player == nil or queueOf(player) == difficulty then
				return
			end
			local now = os.clock()
			if now - (lastTouch[player] or 0) < TOUCH_COOLDOWN then
				return
			end
			lastTouch[player] = now
			join(player, difficulty)
		end)
		local prompt = circle:FindFirstChild("JoinPrompt") :: ProximityPrompt
		prompt.Triggered:Connect(function(player)
			if queueOf(player) == difficulty then
				leaveQueue(player)
				Notify.send(player, `Left the {difficulty} raid queue.`)
			else
				join(player, difficulty)
			end
		end)
	end

	Net.RaidRequest.OnServerEvent:Connect(function(player, action: unknown, difficulty: unknown)
		if not limit.allow(player) then
			return
		end
		if action == "leave" then
			if queueOf(player) then
				leaveQueue(player)
				Notify.send(player, "Left the raid queue.")
			end
		elseif action == "join" and type(difficulty) == "string" and R.BY_ID[difficulty] then
			join(player, difficulty)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		-- Drones and shockwaves move every frame; the rest runs on TICK.
		for _, raid in raids do
			if not raid.over then
				stepDrones(raid, dt, now)
				stepWaves(raid, now)
			end
		end
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		tickQueues(now)
		for _, raid in raids do
			tickRaid(raid, now)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leaveQueue(player)
		lastTouch[player] = nil
	end)
end

return RaidSystem

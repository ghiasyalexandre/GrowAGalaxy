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
-- point more). The boss fires turbolaser volleys at raiders (aimed where
-- they were, so they can dodge) and, on harder raids, a telegraphed
-- superlaser; both hurt ships through CombatSystem.damageShip. A raider
-- whose ship is destroyed, who leaves their ship or the game is out. The
-- raid is won when the boss's health runs out, lost when TIME_LIMIT passes
-- or nobody is left. Winners who helped (RaidMath.earnsReward) get the
-- difficulty's fixed reward. Then everyone still there goes back to the ISS.
--
-- Pad attributes (for clients): Count, StartsAt (server time, 0 = no
-- countdown), Busy (a raid is running). Player attributes: RaidQueue and
-- Raid (the difficulty). Boss model attributes: Difficulty, Health (0..1),
-- EndsAt (server time), Raiders (still flying).

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

type Queue = { players: { Player }, firstAt: number?, filledAt: number? }
type Raider = { damage: number, flying: boolean }
type Raid = {
	difficulty: string,
	model: Model,
	body: BasePart,
	weak: BasePart,
	health: number,
	max: number,
	endsAt: number,
	nextVolley: number,
	nextLaser: number,
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

local function v(point: Vector3): RaidMath.Point
	return { x = point.X, y = point.Y, z = point.Z }
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
	local def = R.BY_ID[difficulty]
	local raid: Raid = {
		difficulty = difficulty,
		model = model,
		body = body,
		weak = weak,
		health = max,
		max = max,
		endsAt = now + R.TIME_LIMIT,
		nextVolley = now + 4,
		nextLaser = now + math.max(def.superlaserInterval, 8),
		raiders = {},
		over = false,
	}
	model:SetAttribute("Difficulty", difficulty)
	model:SetAttribute("Health", 1)
	model:SetAttribute("EndsAt", raid.endsAt)
	model:SetAttribute("Raiders", #players)
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
					`{difficulty} raid: destroy the Death Star! Its glowing green dish takes extra damage.`
				)
			end
		end)
	end
end

local function volley(raid: Raid, now: number)
	local def = R.BY_ID[raid.difficulty]
	local targets = flyingRaiders(raid)
	for _ = 1, math.min(def.boltsPerVolley, #targets * 2) do
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
				and raid.raiders[player].flying
				and RaidMath.boltHits(v(aim), v(at))
			then
				hurt(raid, player, def.boltDamage)
			end
		end)
	end
	raid.nextVolley = now + def.volleyInterval
end

local function superlaser(raid: Raid, now: number)
	local def = R.BY_ID[raid.difficulty]
	raid.nextLaser = now + def.superlaserInterval
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
				hurt(raid, player, def.superlaserDamage)
			end
		end
	end)
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
	if #flying == 0 then
		finish(raid, false)
		return
	end
	if now >= raid.endsAt then
		finish(raid, false)
		return
	end
	if now >= raid.nextVolley then
		volley(raid, now)
	end
	if R.BY_ID[raid.difficulty].superlaser and now >= raid.nextLaser then
		superlaser(raid, now)
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
	local damage = RaidMath.bossDamage(info.beamPower, result.Instance == raid.weak)
	raid.health = math.max(raid.health - damage, 0)
	raid.raiders[player].damage += damage
	raid.model:SetAttribute("Health", math.floor(raid.health / raid.max * 1000) / 1000)
	if raid.health <= 0 then
		finish(raid, true)
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
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		local now = Workspace:GetServerTimeNow()
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

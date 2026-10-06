--!strict
-- Zero G Dodgeball (Config.Dodgeball, Logic/DodgeballMath).
--
-- The arena is built once (World/DodgeballBuilder). The ISS portal's warp
-- target "Dodgeball" (NavigationSystem.addTarget) drops a player at a random
-- spawn point; the arena's exit portal warps back to the ISS.
--
-- Membership: every MEMBERSHIP_TICK, anyone whose character is inside the
-- arena is playing (player attribute Dodgeball = true, and a small sun in
-- their hand); leaving the box ends it. No queue. A piloted ship that comes
-- inside is stowed: no ships in the arena.
--
-- Throwing (DodgeballThrow, a direction): a player who is playing, not out
-- and off cooldown throws a ball from their position. The server flies it in
-- a straight line, sweeping a sphere each frame: it stops on a wall or block,
-- or hits another player who is playing, who is then out: flung back (their
-- client is told, DodgeballEvent "hit") and moved to a random spawn after
-- OUT_TIME. Every client draws the balls from DodgeballEvent "throw" and
-- "end". Player attributes for the HUD: DodgeReady (ball ready), DodgeOut,
-- DodgeHits and DodgeOuts (this session), DodgeBig (giant ball charged).
--
-- Giant ball powerup: every POWERUP_INTERVAL seconds, if none is out, an orb
-- ("BigBallPowerup") appears at a random spawn point. The first player who
-- floats within POWERUP_REACH of it takes it: their next ball is
-- POWERUP_SCALE x bigger (the server sweeps a sphere that much bigger, so it
-- hits that much more easily), and the sun in their hand grows to show it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local DodgeballBuilder = require(script.Parent.Parent.World.DodgeballBuilder)
local DodgeballMath = require(ReplicatedStorage.Shared.Logic.DodgeballMath)
local FlightGuard = require(script.Parent.FlightGuard)
local NavigationSystem = require(script.Parent.NavigationSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local ShipSystem = require(script.Parent.ShipSystem)
local Teleport = require(script.Parent.Parent.Util.Teleport)

local D = Config.Dodgeball
local SUN_COLOR = Color3.fromRGB(255, 176, 32)

type Ball = {
	id: number,
	thrower: Player,
	position: Vector3,
	direction: Vector3,
	born: number,
	radius: number,
}

local DodgeballSystem = {}

local arena: Model
local members: { [Player]: boolean } = {}
local lastThrow: { [Player]: number } = {}
local out: { [Player]: boolean } = {}
local balls: { Ball } = {}
local nextBall = 1
local elapsed = 0
local ignore: { Instance } = {} -- arena decorations balls fly through
local big: { [Player]: boolean } = {} -- giant ball charged
local powerup: Part? = nil
local powerupTimer = 0

local function vec(point: DodgeballMath.Point): Vector3
	return Vector3.new(point.x, point.y, point.z)
end

local function randomSpawn(): CFrame?
	local spawns = DodgeballMath.spawnPoints()
	local index = math.random(#spawns)
	local marker = arena:FindFirstChild(`Spawn{index}`)
	return if marker and marker:IsA("BasePart")
		then marker.CFrame
		else CFrame.new(vec(spawns[index]))
end

-- The sun in the player's hand: bright when a ball is ready.
local function setHeld(player: Player, on: boolean)
	local character = player.Character
	local existing = character and character:FindFirstChild("DodgeSun")
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing or character == nil then
		return
	end
	local hand = character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local sun = Instance.new("Part")
	sun.Name = "DodgeSun"
	sun.Shape = Enum.PartType.Ball
	sun.Size = Vector3.one * (if big[player] then 3.2 else 1.8)
	sun.Material = Enum.Material.Neon
	sun.Color = SUN_COLOR
	sun.CanCollide = false
	sun.CanQuery = false
	sun.CanTouch = false
	sun.Massless = true
	sun.CastShadow = false
	sun.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.6, 0)
	local light = Instance.new("PointLight")
	light.Color = SUN_COLOR
	light.Range = 10
	light.Brightness = 2 * (1 - Config.World.EMISSIVE_DIM)
	light.Parent = sun
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = sun
	weld.Parent = sun
	sun.Parent = character
end

local function setReady(player: Player, ready: boolean)
	player:SetAttribute("DodgeReady", ready)
	local character = player.Character
	local sun = character and character:FindFirstChild("DodgeSun")
	if sun and sun:IsA("BasePart") then
		sun.Transparency = if ready then 0 else 0.85
	end
end

local function join(player: Player)
	members[player] = true
	player:SetAttribute("Dodgeball", true)
	player:SetAttribute("DodgeHits", player:GetAttribute("DodgeHits") or 0)
	player:SetAttribute("DodgeOuts", player:GetAttribute("DodgeOuts") or 0)
	setHeld(player, true)
	setReady(player, true)
	Notify.send(player, "Zero G Dodgeball! Click to throw your sun, Shift to launch off a block.")
end

local function setBig(player: Player, on: boolean)
	if on then
		big[player] = true
	else
		big[player] = nil
	end
	if player.Parent then
		player:SetAttribute("DodgeBig", if on then true else nil)
		-- Re-make the hand sun at its new size.
		setHeld(player, false)
		if members[player] then
			setHeld(player, true)
			setReady(player, player:GetAttribute("DodgeReady") == true)
		end
	end
end

local function leave(player: Player)
	members[player] = nil
	out[player] = nil
	big[player] = nil
	if player.Parent then
		player:SetAttribute("DodgeBig", nil)
	end
	if player.Parent then
		player:SetAttribute("Dodgeball", nil)
		player:SetAttribute("DodgeOut", nil)
		player:SetAttribute("DodgeReady", nil)
		setHeld(player, false)
	end
end

local function tickMembership()
	for _, player in Players:GetPlayers() do
		local root = Teleport.rootOf(player)
		local inside = root ~= nil
			and DodgeballMath.inside(
				{ x = root.Position.X, y = root.Position.Y, z = root.Position.Z },
				-4
			)
		if inside and not members[player] then
			join(player)
		elseif not inside and members[player] then
			leave(player)
		elseif inside then
			-- A respawned character needs its sun again.
			setHeld(player, true)
		end
		-- No ships in the arena.
		local ship = ShipSystem.getPiloted(player)
		local hull = ship and ship.PrimaryPart
		if
			hull
			and DodgeballMath.inside(
				{ x = hull.Position.X, y = hull.Position.Y, z = hull.Position.Z },
				-40
			)
		then
			ShipSystem.stow(player)
			Notify.send(player, "Ships aren't allowed in the Dodgeball arena: float in and play!")
		end
	end
end

-- A whole-number player attribute, 0 when unset.
local function counter(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function knockOut(victim: Player, thrower: Player, direction: Vector3)
	out[victim] = true
	victim:SetAttribute("DodgeOut", true)
	victim:SetAttribute("DodgeOuts", counter(victim, "DodgeOuts") + 1)
	thrower:SetAttribute("DodgeHits", counter(thrower, "DodgeHits") + 1)
	DataSystem.addStat(thrower, "dodgeballHits", 1)
	Net.DodgeballEvent:FireClient(victim, "hit", direction, thrower.DisplayName)
	Notify.send(thrower, `Hit! You got {victim.DisplayName}.`)
	task.delay(D.OUT_TIME, function()
		out[victim] = nil
		if victim.Parent == nil then
			return
		end
		victim:SetAttribute("DodgeOut", nil)
		local goal = randomSpawn()
		if members[victim] and goal and Teleport.character(victim, goal) then
			FlightGuard.reset(victim)
		end
	end)
end

local function playerOf(part: Instance): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function stepBalls(dt: number)
	local now = os.clock()
	for i = #balls, 1, -1 do
		local ball = balls[i]
		local function finish(at: Vector3, victim: Player?)
			Net.DodgeballEvent:FireAllClients(
				"end",
				ball.id,
				at,
				if victim then victim.UserId else 0
			)
			table.remove(balls, i)
		end
		if now - ball.born >= D.BALL_LIFETIME then
			finish(ball.position, nil)
			continue
		end
		local step = ball.direction * D.BALL_SPEED * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip = table.clone(ignore)
		if ball.thrower.Character then
			table.insert(skip, ball.thrower.Character)
		end
		if powerup then
			table.insert(skip, powerup)
		end
		params.FilterDescendantsInstances = skip
		local result = Workspace:Spherecast(ball.position, ball.radius, step, params)
		if result == nil then
			ball.position += step
			continue
		end
		local victim = playerOf(result.Instance)
		if victim and members[victim] and not out[victim] and victim ~= ball.thrower then
			knockOut(victim, ball.thrower, ball.direction)
			finish(result.Position, victim)
		elseif victim then
			-- Someone out (or not playing): the ball flies through them.
			ball.position += step
		else
			finish(result.Position, nil)
		end
	end
end

local function throw(player: Player, direction: unknown)
	if not members[player] or out[player] or typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	if dir.Magnitude < 0.1 or dir.Magnitude ~= dir.Magnitude then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or -math.huge) < D.THROW_COOLDOWN then
		return
	end
	local root = Teleport.rootOf(player)
	if root == nil then
		return
	end
	lastThrow[player] = now
	local unit = dir.Unit
	local scale = if big[player] then D.POWERUP_SCALE else 1
	local ball: Ball = {
		id = nextBall,
		thrower = player,
		position = root.Position + unit * (3 + D.BALL_RADIUS * (scale - 1)),
		direction = unit,
		born = now,
		radius = D.BALL_RADIUS * scale,
	}
	nextBall += 1
	table.insert(balls, ball)
	Net.DodgeballEvent:FireAllClients("throw", ball.id, ball.position, unit, player.UserId, scale)
	if scale > 1 then
		setBig(player, false)
	end
	setReady(player, false)
	task.delay(D.THROW_COOLDOWN, function()
		if members[player] then
			setReady(player, true)
		end
	end)
end

-- A new powerup orb at a random spawn point, a little off it.
local function spawnPowerup()
	local spawns = DodgeballMath.spawnPoints()
	local at = vec(spawns[math.random(#spawns)])
		+ Vector3.new(math.random(-12, 12), 10, math.random(-12, 12))
	local orb = Instance.new("Part")
	orb.Name = "BigBallPowerup"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * 4
	orb.CFrame = CFrame.new(at)
	orb.Color = Color3.fromHex(D.POWERUP_COLOR)
	orb.Material = Enum.Material.Neon
	orb.Transparency = 0.15
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb:SetAttribute("SpinSpeed", 1.5)
	CollectionService:AddTag(orb, "GaG_Spin")
	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Range = 18
	light.Brightness = 2 * (1 - Config.World.EMISSIVE_DIM)
	light.Parent = orb
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(160, 40)
	label.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	label.MaxDistance = 150
	label.LightInfluence = 0
	label.AlwaysOnTop = true
	label.Parent = orb
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = orb.Color
	text.TextStrokeTransparency = 0.2
	text.Text = "GIANT BALL!"
	text.Parent = label
	orb.Parent = arena
	powerup = orb
end

-- Every tick: a member touching the orb takes it; with none out, a new one
-- appears every POWERUP_INTERVAL seconds.
local function tickPowerup(dt: number)
	local orb = powerup
	if orb == nil then
		powerupTimer += dt
		if powerupTimer >= D.POWERUP_INTERVAL then
			powerupTimer = 0
			spawnPowerup()
		end
		return
	end
	for player in members do
		local root = Teleport.rootOf(player)
		if
			not out[player]
			and root
			and (root.Position - orb.Position).Magnitude <= D.POWERUP_REACH
		then
			orb:Destroy()
			powerup = nil
			powerupTimer = 0
			setBig(player, true)
			Notify.send(player, "GIANT BALL! Your next throw is 3 times bigger.")
			return
		end
	end
end

function DodgeballSystem.init()
	arena = DodgeballBuilder.build(Workspace)
	for _, part in arena:GetDescendants() do
		if part:IsA("BasePart") and not part.CanCollide then
			table.insert(ignore, part)
		end
	end
end

function DodgeballSystem.start()
	NavigationSystem.addTarget("Dodgeball", function()
		return randomSpawn()
	end)
	Net.DodgeballThrow.OnServerEvent:Connect(throw)
	RunService.Heartbeat:Connect(function(dt)
		stepBalls(dt)
		tickPowerup(dt)
		elapsed += dt
		if elapsed >= D.MEMBERSHIP_TICK then
			elapsed = 0
			tickMembership()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		lastThrow[player] = nil
		big[player] = nil
	end)
end

return DodgeballSystem

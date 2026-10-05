--!strict
-- Ship rockets (Config.Rockets). RocketRequest(direction) from a pilot fires
-- one from their ship's nose, if it's off cooldown; the aim may be at most
-- MAX_AIM_ANGLE off the nose (otherwise it flies straight ahead).
--
-- The server flies each rocket in a straight line, sweeping a sphere each
-- frame, and it bursts on the first thing it touches (not its own ship or
-- pilot) or after LIFETIME. The blast (BLAST_RADIUS, strength = the ship's
-- beam power x POWER) goes to MiningSystem.blast (asteroids), RaidSystem.blast
-- (the Death Star and its drones) and CombatSystem.blast (PvP ships).
--
-- Every client draws it from RocketEvent: "launch" (id, origin, direction,
-- colour) and "boom" (id, position, colour); the colour is the ship's laser
-- colour. Player attribute RocketReadyAt (server time) drives the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatSystem = require(script.Parent.CombatSystem)
local Config = require(ReplicatedStorage.Shared.Config)
local MiningSystem = require(script.Parent.MiningSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RaidSystem = require(script.Parent.RaidSystem)
local ShipSystem = require(script.Parent.ShipSystem)

local K = Config.Rockets

type Rocket = {
	id: number,
	owner: Player,
	ship: Model,
	position: Vector3,
	direction: Vector3,
	born: number,
	power: number,
	color: string,
}

local RocketSystem = {}

local rockets: { Rocket } = {}
local readyAt: { [Player]: number } = {}
local nextId = 1

local function explode(rocket: Rocket, at: Vector3)
	Net.RocketEvent:FireAllClients("boom", rocket.id, at, rocket.color)
	local owner = rocket.owner
	if owner.Parent ~= Players then
		return
	end
	MiningSystem.blast(owner, at, K.BLAST_RADIUS, rocket.power)
	RaidSystem.blast(owner, at, K.BLAST_RADIUS, rocket.power * Config.Raids.DAMAGE_PER_POWER)
	CombatSystem.blast(owner, at, K.BLAST_RADIUS, rocket.power * Config.Combat.DAMAGE_PER_POWER)
end

local function step(dt: number)
	local now = os.clock()
	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		if now - rocket.born >= K.LIFETIME then
			table.remove(rockets, i)
			explode(rocket, rocket.position)
			continue
		end
		local move = rocket.direction * K.SPEED * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip: { Instance } = { rocket.ship }
		if rocket.owner.Character then
			table.insert(skip, rocket.owner.Character)
		end
		params.FilterDescendantsInstances = skip
		local result = Workspace:Spherecast(rocket.position, K.HIT_RADIUS, move, params)
		if result then
			table.remove(rockets, i)
			explode(rocket, result.Position)
		else
			rocket.position += move
		end
	end
end

local function fire(player: Player, direction: unknown)
	local model, info = ShipSystem.getPiloted(player)
	local hull = model and model.PrimaryPart
	if model == nil or info == nil or hull == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < (readyAt[player] or 0) then
		return
	end
	local forward = hull.CFrame.LookVector
	local aim = forward
	if
		typeof(direction) == "Vector3"
		and direction.Magnitude > 0.1
		and direction.Magnitude == direction.Magnitude
	then
		local wanted = (direction :: Vector3).Unit
		if wanted:Dot(forward) >= math.cos(math.rad(K.MAX_AIM_ANGLE)) then
			aim = wanted
		end
	end
	readyAt[player] = now + K.COOLDOWN
	player:SetAttribute("RocketReadyAt", now + K.COOLDOWN)
	local color = model:GetAttribute("BeamColor")
	local rocket: Rocket = {
		id = nextId,
		owner = player,
		ship = model,
		position = hull.Position + forward * (hull.Size.Z / 2 + 3),
		direction = aim,
		born = os.clock(),
		power = info.beamPower * K.POWER,
		color = if type(color) == "string" then color else Config.Beam.COLOR,
	}
	nextId += 1
	table.insert(rockets, rocket)
	Net.RocketEvent:FireAllClients("launch", rocket.id, rocket.position, aim, rocket.color)
end

function RocketSystem.start()
	Net.RocketRequest.OnServerEvent:Connect(fire)
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
	end)
end

return RocketSystem

--!strict
-- Asteroid mining with ship beams. BeamSystem calls step() every tick for
-- each piloted ship whose beam is firing, and stop() otherwise.
--
-- The server casts its own ray from the ship's muzzle along the beam's aim
-- (already clamped to the aim cone) out to the ship's beamRange. The ISS
-- blocks it; ships and players don't. If it hits an asteroid the player can
-- reserve, extraction progress grows at the ship's beamPower on the weak
-- point, or a share of it on plain rock (Logic/MiningMath). At the asteroid's
-- durability it breaks and pays Stardust exactly once: AsteroidSystem marks
-- it broken before anything is paid, and a broken asteroid can't be hit.
--
-- Stats: asteroidsMined for every break; coolExtractions when the beam never
-- overheated while extracting that asteroid (BeamSystem reports overheats).
--
-- Ship model attributes, for the pilot's HUD and everyone's effects:
--   MiningTarget    number   AsteroidId being extracted, 0 for none
--   MiningProgress  number   0 to 1
--   MiningWeak      boolean  the beam is on the weak point

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AsteroidSystem = require(script.Parent.AsteroidSystem)
local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local MiningMath = require(ReplicatedStorage.Shared.Logic.MiningMath)
local Notify = require(script.Parent.Parent.Util.Notify)
local Types = require(ReplicatedStorage.Shared.Types)

local A = Config.Asteroids
local CURRENCY = Config.Economy.CURRENCY_NAME

local MiningSystem = {}

local rayParams: RaycastParams? = nil
local lastBusyNotice: { [Player]: number } = {}
-- The asteroid each player last extracted, and the one they last overheated on.
local currentTarget: { [Player]: number } = {}
local overheatedOn: { [Player]: number } = {}

-- Asteroids and the shared world (the ISS) stop the beam; ships, players and
-- region boundaries don't.
local function params(): RaycastParams
	local existing = rayParams
	if existing then
		return existing
	end
	local filter: { Instance } = { AsteroidSystem.getFolder() }
	local world = Workspace:FindFirstChild("World")
	if world then
		table.insert(filter, world)
	end
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Include
	created.FilterDescendantsInstances = filter
	rayParams = created
	return created
end

local function show(model: Model, target: number, progress: number, weak: boolean)
	model:SetAttribute("MiningTarget", target)
	model:SetAttribute("MiningProgress", math.floor(progress * 100 + 0.5) / 100)
	model:SetAttribute("MiningWeak", weak)
end

-- Clears the mining readout on a ship whose beam isn't extracting.
function MiningSystem.stop(model: Model?)
	if model and model.Parent and model:GetAttribute("MiningTarget") ~= 0 then
		show(model, 0, 0, false)
	end
end

local function busy(player: Player, now: number)
	local last = lastBusyNotice[player]
	if last == nil or now - last >= A.BUSY_NOTICE_COOLDOWN then
		lastBusyNotice[player] = now
		Notify.send(player, "Someone else is mining that asteroid. Find another one.")
	end
end

local function payOut(player: Player, asteroid: AsteroidSystem.Asteroid)
	local reward = MiningMath.reward(
		asteroid.size.reward,
		asteroid.weakProgress,
		asteroid.progress,
		A.PRECISION_BONUS
	)
	if not AsteroidSystem.breakAsteroid(asteroid) then
		return
	end
	DataSystem.addStardust(player, reward)
	DataSystem.addStat(player, "asteroidsMined", 1)
	if overheatedOn[player] ~= asteroid.id then
		DataSystem.addStat(player, "coolExtractions", 1)
	end
	local bonus = reward - asteroid.size.reward
	Notify.send(
		player,
		if bonus > 0
			then `+{reward} {CURRENCY} ({asteroid.size.displayName}, +{bonus} precision bonus)`
			else `+{reward} {CURRENCY} ({asteroid.size.displayName})`
	)
end

-- One tick of a firing beam. `aim` is the beam direction in ship space.
function MiningSystem.step(
	player: Player,
	model: Model,
	info: Types.ShipInfo,
	aim: Vector3,
	dt: number
)
	local hull = model.PrimaryPart
	local muzzle = hull and hull:FindFirstChild("BeamOrigin")
	if hull == nil or muzzle == nil or not muzzle:IsA("Attachment") then
		MiningSystem.stop(model)
		return
	end
	local direction = hull.CFrame:VectorToWorldSpace(aim) * info.beamRange
	local hit = Workspace:Raycast(muzzle.WorldPosition, direction, params())
	local asteroid = if hit then AsteroidSystem.fromPart(hit.Instance) else nil
	if hit == nil or asteroid == nil then
		MiningSystem.stop(model)
		return
	end

	local now = os.clock()
	if not AsteroidSystem.reserve(asteroid, player, now) then
		MiningSystem.stop(model)
		busy(player, now)
		return
	end

	currentTarget[player] = asteroid.id
	local onWeakPoint = hit.Instance == asteroid.weakPoint
	local gained = MiningMath.rate(info.beamPower, onWeakPoint, A.ROCK_EFFICIENCY) * dt
	asteroid.progress += gained
	if onWeakPoint then
		asteroid.weakProgress += gained
	end

	local share = math.min(asteroid.progress / asteroid.size.durability, 1)
	asteroid.model:SetAttribute("Progress", math.floor(share * 100 + 0.5) / 100)
	show(model, asteroid.id, share, onWeakPoint)

	if share >= 1 then
		payOut(player, asteroid)
		show(model, 0, 0, false)
	end
end

-- BeamSystem calls this when a player's beam overheats: the asteroid they
-- were extracting no longer counts as a cool extraction.
function MiningSystem.noteOverheat(player: Player)
	local target = currentTarget[player]
	if target then
		overheatedOn[player] = target
	end
end

function MiningSystem.start()
	Players.PlayerRemoving:Connect(function(player)
		lastBusyNotice[player] = nil
		currentTarget[player] = nil
		overheatedOn[player] = nil
	end)
end

return MiningSystem

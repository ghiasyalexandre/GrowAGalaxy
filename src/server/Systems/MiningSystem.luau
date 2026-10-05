--!strict
-- Asteroid mining with ship lasers. BeamSystem calls shot() for every shot a
-- pilot fires, and refresh() every tick.
--
-- The server casts its own ray from the ship's muzzle along the shot's aim
-- (already clamped to the aim cone) out to the ship's beamRange. The ISS
-- blocks it; ships and players don't. If it hits an asteroid the player can
-- reserve, each shot adds Config.Beam.SHOT_POWER seconds of the ship's
-- beamPower on the weak point, or a share of it on plain rock (Logic/MiningMath). At the asteroid's
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
local Entitlements = require(script.Parent.Parent.Util.Entitlements)
local ProfileSchema = require(ReplicatedStorage.Shared.Logic.ProfileSchema)
local MiningMath = require(ReplicatedStorage.Shared.Logic.MiningMath)
local RewardMath = require(ReplicatedStorage.Shared.Logic.RewardMath)
local Notify = require(script.Parent.Parent.Util.Notify)
local Reward = require(script.Parent.Parent.Util.Reward)
local Types = require(ReplicatedStorage.Shared.Types)

local A = Config.Asteroids

local MiningSystem = {}

local SHOT_POWER = Config.Beam.SHOT_POWER

local rayParams: RaycastParams? = nil
local lastBusyNotice: { [Player]: number } = {}
-- The asteroid each player last extracted, and the one they last overheated on.
local currentTarget: { [Player]: number } = {}
local overheatedOn: { [Player]: number } = {}
local lastHitAt: { [Player]: number } = {}

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
	local base = MiningMath.reward(
		asteroid.size.reward,
		asteroid.weakProgress,
		asteroid.progress,
		A.PRECISION_BONUS
	)
	if not AsteroidSystem.breakAsteroid(asteroid) then
		return
	end
	-- Mining pass and boost multiply the reward here, once (RewardMath).
	local profile = DataSystem.getProfile(player)
	local entitlements: RewardMath.Entitlements = {
		passes = Entitlements.passes(player),
		boosts = if profile then profile.boosts else RewardMath.none().boosts,
		trail = if profile then ProfileSchema.trailMultiplier(profile) else 1,
	}
	local multiplier = RewardMath.multiplier("mining", entitlements)
	local reward = RewardMath.miningReward(base, entitlements)
	DataSystem.addStardust(player, reward)
	DataSystem.addStat(player, "asteroidsMined", 1)
	if overheatedOn[player] ~= asteroid.id then
		DataSystem.addStat(player, "coolExtractions", 1)
	end
	local bonus = base - asteroid.size.reward
	local label = if bonus > 0
		then `{asteroid.size.displayName}  ·  +{bonus} precision`
		else asteroid.size.displayName
	if multiplier > 1 then
		label ..= `  ·  x{multiplier}`
	end
	Reward.send(player, "mine", reward, asteroid.position, label)
end

-- Clears the readout once the player hasn't hit their asteroid for as long
-- as its reservation lasts (by then its progress is gone anyway).
function MiningSystem.refresh(player: Player, model: Model)
	local last = lastHitAt[player]
	if last and os.clock() - last >= A.RESERVATION_TIMEOUT then
		lastHitAt[player] = nil
		MiningSystem.stop(model)
	end
end

-- One shot. `aim` is its direction in ship space. A miss leaves the readout
-- (and the reservation) alone, so a stray shot doesn't cost progress.
function MiningSystem.shot(player: Player, model: Model, info: Types.ShipInfo, aim: Vector3)
	local hull = model.PrimaryPart
	local muzzle = hull and hull:FindFirstChild("BeamOrigin")
	if hull == nil or muzzle == nil or not muzzle:IsA("Attachment") then
		return
	end
	local direction = hull.CFrame:VectorToWorldSpace(aim) * info.beamRange
	local hit = Workspace:Raycast(muzzle.WorldPosition, direction, params())
	local asteroid = if hit then AsteroidSystem.fromPart(hit.Instance) else nil
	if hit == nil or asteroid == nil then
		return
	end

	local now = os.clock()
	if not AsteroidSystem.reserve(asteroid, player, now) then
		busy(player, now)
		return
	end
	lastHitAt[player] = now

	currentTarget[player] = asteroid.id
	local onWeakPoint = hit.Instance == asteroid.weakPoint
	-- The Enhanced Beam pass speeds up extraction only (never the payout).
	local power = info.beamPower * RewardMath.beamPower(Entitlements.passes(player))
	local gained = MiningMath.rate(power, onWeakPoint, A.ROCK_EFFICIENCY) * SHOT_POWER
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

-- A rocket blast (RocketSystem): every asteroid it catches gains `power`
-- extraction progress, as if hit on rock; any that break pay out as usual.
-- Asteroids someone else is mining are left alone.
function MiningSystem.blast(player: Player, center: Vector3, radius: number, power: number)
	local now = os.clock()
	for _, asteroid in AsteroidSystem.within(center, radius) do
		if not AsteroidSystem.reserve(asteroid, player, now) then
			continue
		end
		asteroid.progress += power
		local share = math.min(asteroid.progress / asteroid.size.durability, 1)
		asteroid.model:SetAttribute("Progress", math.floor(share * 100 + 0.5) / 100)
		if share >= 1 then
			payOut(player, asteroid)
		end
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
		lastHitAt[player] = nil
	end)
end

return MiningSystem

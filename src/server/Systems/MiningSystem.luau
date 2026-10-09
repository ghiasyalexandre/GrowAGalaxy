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
-- Payout (economy v2, Logic/EconomyMath.miningPayout): the miner's
-- production B when they first hit it x their mining factor a x the rock's
-- reference work seconds, plus the precision bonus, times the mining pass
-- and boost. Golden swarm rocks pay SWARM_REWARD x for up to
-- SWARM_BONUS_WORK seconds of work per player in any SWARM_BONUS_WINDOW.
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
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
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
-- Each player's production when they first hit the asteroid they're mining.
local rateAtHit: { [Player]: { id: number, rate: number } } = {}
-- Swarm bonus work each player was paid for recently: { at, work }.
local swarmPaid: { [Player]: { { at: number, work: number } } } = {}

-- The share of `work` seconds still inside the player's swarm allowance,
-- recording it as used.
local function swarmShare(player: Player, work: number, now: number): number
	local list = swarmPaid[player] or {}
	swarmPaid[player] = list
	local used = 0
	for index = #list, 1, -1 do
		if now - list[index].at > A.SWARM_BONUS_WINDOW then
			table.remove(list, index)
		else
			used += list[index].work
		end
	end
	local covered = math.clamp(A.SWARM_BONUS_WORK - used, 0, work)
	if covered > 0 then
		table.insert(list, { at = now, work = covered })
	end
	return if work > 0 then covered / work else 0
end

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
	local weakShare = if asteroid.progress > 0
		then math.clamp(asteroid.weakProgress / asteroid.progress, 0, 1)
		else 0
	if not AsteroidSystem.breakAsteroid(asteroid) then
		return
	end
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return
	end
	-- B when first hit (B already includes the trail and the Refinery).
	local hitRate = rateAtHit[player]
	local rate = if hitRate and hitRate.id == asteroid.id
		then hitRate.rate
		else ProfileSchema.incomeRate(profile)
	rateAtHit[player] = nil
	-- Mining pass and boost multiply the reward here, once (RewardMath).
	local entitlements: RewardMath.Entitlements = {
		passes = Entitlements.passes(player),
		boosts = profile.boosts,
	}
	local multiplier = RewardMath.multiplier("mining", entitlements)
	local golden = asteroid.model:GetAttribute("Golden") == true
	local swarm = if golden
		then 1 + (A.SWARM_REWARD - 1) * swarmShare(player, asteroid.size.work, os.clock())
		else 1
	local factor = EconomyMath.profileMiningFactor(profile)
	local reward =
		EconomyMath.miningPayout(rate, factor, asteroid.size.work, weakShare, multiplier * swarm)
	local base = EconomyMath.miningPayout(rate, factor, asteroid.size.work, 0, 1)
	DataSystem.addStardust(player, reward, if swarm > 1 then "swarm_bonus" else "asteroid")
	DataSystem.addStat(player, "asteroidsMined", 1)
	if overheatedOn[player] ~= asteroid.id then
		DataSystem.addStat(player, "coolExtractions", 1)
	end
	local bonus = math.floor(base * A.PRECISION_BONUS * weakShare + 0.5)
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
	-- The payout uses the miner's production when they first hit it.
	local hitRate = rateAtHit[player]
	if hitRate == nil or hitRate.id ~= asteroid.id or asteroid.progress == 0 then
		local profile = DataSystem.getProfile(player)
		rateAtHit[player] = {
			id = asteroid.id,
			rate = if profile then ProfileSchema.incomeRate(profile) else 0,
		}
	end
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
		rateAtHit[player] = nil
		swarmPaid[player] = nil
	end)
end

return MiningSystem

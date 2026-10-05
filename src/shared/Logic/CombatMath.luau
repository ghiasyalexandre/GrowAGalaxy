--!strict
-- PvP rules shared by the server (CombatSystem) and tests: who can damage
-- whom, how much, hull repair, and when PvP may be switched.
-- Pure module: no Roblox services.

local Config = require(script.Parent.Parent.Config)

local C = Config.Combat

local CombatMath = {}

-- Hull damage dealt by one shot from a ship with this beam power.
function CombatMath.damage(beamPower: number): number
	return math.max(beamPower, 0) * C.DAMAGE_PER_POWER
end

-- Whether a shot from the attacker may damage the victim's ship.
function CombatMath.canDamage(
	attackerPvp: boolean,
	victimPvp: boolean,
	sameOwner: boolean,
	victimPiloted: boolean,
	inSafeZone: boolean
): boolean
	return attackerPvp and victimPvp and not sameOwner and victimPiloted and not inSafeZone
end

-- Hull after `dt` seconds, `sinceHit` seconds after the last hit.
function CombatMath.repair(hull: number, maxHull: number, sinceHit: number, dt: number): number
	if sinceHit < C.REGEN_DELAY or hull >= maxHull then
		return math.min(hull, maxHull)
	end
	return math.min(hull + maxHull * C.REGEN_SHARE * dt, maxHull)
end

-- Whether PvP may be switched to `wanted` now. Returns a reason when not.
function CombatMath.canToggle(
	wanted: boolean,
	now: number,
	lastToggle: number,
	lastCombat: number
): (boolean, string?)
	if now - lastToggle < C.TOGGLE_COOLDOWN then
		return false, "Wait a moment before switching PvP again."
	end
	if not wanted and now - lastCombat < C.COMBAT_LOCK then
		local left = math.ceil(C.COMBAT_LOCK - (now - lastCombat))
		return false, `You're in combat: PvP can be switched off in {left}s.`
	end
	return true, nil
end

return CombatMath

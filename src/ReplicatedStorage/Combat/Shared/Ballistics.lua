--!strict
-- Penetration and ricochet calculations. The model intentionally works in
-- millimetres of RHA equivalent (RHAe) while projectile travel is in studs.

local Util = require(script.Parent.Util)

local Ballistics = {}

function Ballistics.velocityToMps(velocityStudsPerSecond: Vector3): number
	return velocityStudsPerSecond.Magnitude * Util.METERS_PER_STUD
end

function Ballistics.velocityToStudsPerSecond(velocityMps: number): number
	return velocityMps * Util.STUDS_PER_METER
end

function Ballistics.kineticEnergy(shell: {[string]: any}, velocityMps: number): number
	return Util.kineticEnergyJoules(shell.massKg, velocityMps)
end

function Ballistics.penetrationAtVelocity(shell: {[string]: any}, velocityMps: number): number
	if shell.shapedCharge then
		-- Shaped-charge penetration mainly depends on liner geometry; travel
		-- velocity has very little effect until the round becomes unstable.
		return shell.penetrationAtZeroMm
	end

	if shell.muzzleVelocityMps <= 0 then
		return 0
	end
	local ratio = Util.clamp(velocityMps / shell.muzzleVelocityMps, 0, 1.35)
	return shell.penetrationAtZeroMm * (ratio ^ shell.penetrationExponent)
end

function Ballistics.effectiveArmour(profile: {[string]: any}, impactAngleDegrees: number, shell: {[string]: any}): (number, number)
	local cosine = math.cos(math.rad(Util.clamp(impactAngleDegrees, 0, 85)))
	cosine = math.max(cosine, 0.087) -- avoid infinite armour at an exact graze
	local integrity = Util.clamp(profile.integrity or 1, 0.05, 1)
	local material = profile.material
	local rawThickness = math.max(profile.thicknessMm or 0, 0)
	local effectiveThickness = rawThickness / cosine
	local rhae = effectiveThickness * material.rhaMultiplier * (0.35 + 0.65 * integrity)

	if shell.shapedCharge and profile.reactiveArmour then
		rhae *= profile.reactiveArmourMultiplier or 1.8
	end
	if shell.shapedCharge and profile.spacedArmourMm then
		rhae += profile.spacedArmourMm * 0.75
	end
	return effectiveThickness, rhae
end

function Ballistics.ricochetChance(shell: {[string]: any}, profile: {[string]: any}, impactAngleDegrees: number): number
	if shell.shapedCharge or shell.ricochetEnergyRetention <= 0 or profile.canRicochet == false then
		return 0
	end

	local material = profile.material
	local threshold = Util.clamp(shell.ricochetStartAngleDegrees + (material.ricochetBonusDegrees or 0), 1, 89)
	if impactAngleDegrees <= threshold then
		return 0
	end

	local normalized = (impactAngleDegrees - threshold) / math.max(90 - threshold, 0.1)
	-- At the threshold there is still a small chance; close to 90° a kinetic
	-- projectile will almost always glance off rather than drill sideways.
	return Util.clamp(0.12 + normalized * 0.84, 0, 0.96)
end

export type ImpactResult = {
	kind: "Penetrated" | "Ricochet" | "Stopped",
	penetrationMm: number,
	effectiveThicknessMm: number,
	rhaeMm: number,
	residualPenetrationMm: number,
	impactEnergyJoules: number,
	ricochetChance: number,
}

function Ballistics.resolveImpact(
	shell: {[string]: any},
	velocityMps: number,
	profile: {[string]: any},
	impactAngleDegrees: number,
	random: Random
): ImpactResult
	local penetration = Ballistics.penetrationAtVelocity(shell, velocityMps)
	local effectiveThickness, rhae = Ballistics.effectiveArmour(profile, impactAngleDegrees, shell)
	local chance = Ballistics.ricochetChance(shell, profile, impactAngleDegrees)
	local impactEnergy = Ballistics.kineticEnergy(shell, velocityMps)

	if chance > 0 and random:NextNumber() < chance then
		return {
			kind = "Ricochet",
			penetrationMm = penetration,
			effectiveThicknessMm = effectiveThickness,
			rhaeMm = rhae,
			residualPenetrationMm = 0,
			impactEnergyJoules = impactEnergy,
			ricochetChance = chance,
		}
	end

	if penetration > rhae and shell.maxPenetrations > 0 then
		return {
			kind = "Penetrated",
			penetrationMm = penetration,
			effectiveThicknessMm = effectiveThickness,
			rhaeMm = rhae,
			residualPenetrationMm = penetration - rhae,
			impactEnergyJoules = impactEnergy,
			ricochetChance = chance,
		}
	end

	return {
		kind = "Stopped",
		penetrationMm = penetration,
		effectiveThicknessMm = effectiveThickness,
		rhaeMm = rhae,
		residualPenetrationMm = 0,
		impactEnergyJoules = impactEnergy,
		ricochetChance = chance,
	}
end

function Ballistics.postPenetrationVelocity(shell: {[string]: any}, incomingMps: number, result: ImpactResult): number
	if result.penetrationMm <= 0 then
		return 0
	end
	-- Penetration capability scales approximately with velocity^exponent.
	-- This preserves a useful amount of residual energy without allowing one
	-- round to travel forever through thin parts.
	local ratio = Util.clamp(result.residualPenetrationMm / result.penetrationMm, 0.02, 0.92)
	local exponent = math.max(shell.penetrationExponent, 0.2)
	return incomingMps * (ratio ^ (1 / exponent))
end

return Ballistics

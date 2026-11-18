--!strict
-- Applies authoritative health and structural damage after ProjectileService
-- has already resolved armour. It deliberately does not create Roblox
-- Explosion instances: those can break arbitrary joints and are not safe for
-- a predictable combat system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local Util = require(Shared.Util)

local ArmorService = require(script.Parent.ArmorService)

local DamageService = {}

local function humanoidFromInstance(instance: Instance): Humanoid?
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid
			end
		end
		current = current.Parent
	end
	return nil
end

local function markAttacker(humanoid: Humanoid, attacker: Player?)
	if attacker then
		humanoid:SetAttribute("LastDamagedByUserId", attacker.UserId)
		humanoid:SetAttribute("LastDamageTime", workspace:GetServerTimeNow())
	end
end

function DamageService.applyPenetrationDamage(
	hitPart: Instance,
	shell: {[string]: any},
	impact: {[string]: any},
	attacker: Player?
): number
	local humanoid = humanoidFromInstance(hitPart)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	local residualFraction = if impact.penetrationMm > 0
		then Util.clamp(impact.residualPenetrationMm / impact.penetrationMm, 0.1, 1)
		else 0.1
	local damage = shell.directDamage * (0.55 + 0.65 * residualFraction)
	humanoid:TakeDamage(damage)
	markAttacker(humanoid, attacker)
	return damage
end

function DamageService.applyExplosion(
	position: Vector3,
	shell: {[string]: any},
	attacker: Player?
): number
	if shell.explosiveMassKg <= 0 or shell.explosionRadiusM <= 0 then
		return 0
	end

	local radiusStuds = shell.explosionRadiusM * Util.STUDS_PER_METER
	local baseDamage = shell.explosiveMassKg * 950
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = {}

	local seenHumanoids: {[Humanoid]: boolean} = {}
	local damagedParts: {[BasePart]: boolean} = {}
	local totalDamage = 0

	for _, part in ipairs(workspace:GetPartBoundsInRadius(position, radiusStuds, overlap)) do
		local distance = (part.Position - position).Magnitude
		local falloff = Util.clamp(1 - distance / radiusStuds, 0, 1)
		if falloff <= 0 then
			continue
		end

		if not damagedParts[part] then
			damagedParts[part] = true
			ArmorService.applyBlastDamage(part, baseDamage * falloff * falloff)
		end

		local humanoid = humanoidFromInstance(part)
		if humanoid and not seenHumanoids[humanoid] and humanoid.Health > 0 then
			seenHumanoids[humanoid] = true
			local targetPoint = part.Position
			local direction = targetPoint - position
			local blocked = false
			if direction.Magnitude > 0.05 then
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = {}
				local obstruction = workspace:Raycast(position + direction.Unit * 0.03, direction, rayParams)
				if obstruction and not obstruction.Instance:IsDescendantOf(humanoid.Parent :: Instance) then
					blocked = true
				end
			end
			if not blocked then
				local damage = baseDamage * falloff * falloff
				humanoid:TakeDamage(damage)
				markAttacker(humanoid, attacker)
				totalDamage += damage
			end
		end
	end

	return totalDamage
end

return DamageService

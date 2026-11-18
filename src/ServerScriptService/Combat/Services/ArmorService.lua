--!strict
-- Resolves armour attributes on a struck part (or one of its ancestors) into a
-- profile consumed by Ballistics. All attributes are deliberately editable in
-- Roblox Studio, so level designers need no code for each armour plate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local Util = require(Shared.Util)
local ArmorMaterials = require(Shared.ArmorMaterials)

local ArmorService = {}

local function ancestorWithAttribute(instance: Instance, attribute: string): (Instance?, any)
	local current: Instance? = instance
	while current and current ~= workspace do
		local value = current:GetAttribute(attribute)
		if value ~= nil then
			return current, value
		end
		current = current.Parent
	end
	return nil, nil
end

local function findHumanoidModel(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function estimatedThicknessMm(part: BasePart): number
	-- A part's thinnest local dimension is a useful default for simple map
	-- geometry. Important armour should always use ArmorThicknessMm explicitly.
	local smallestStuds = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	return math.max(1, smallestStuds * Util.MM_PER_STUD)
end

function ArmorService.getProfile(hitPart: Instance): {[string]: any}
	local thicknessOwner, thicknessValue = ancestorWithAttribute(hitPart, "ArmorThicknessMm")
	local materialOwner, materialValue = ancestorWithAttribute(hitPart, "ArmorMaterial")
	local integrityOwner, integrityValue = ancestorWithAttribute(hitPart, "ArmorIntegrity")
	local reactiveOwner, reactiveValue = ancestorWithAttribute(hitPart, "ReactiveArmor")
	local _, spacingValue = ancestorWithAttribute(hitPart, "SpacedArmorMm")
	local canRicochetOwner, canRicochetValue = ancestorWithAttribute(hitPart, "CanRicochet")

	local humanoidModel = findHumanoidModel(hitPart)
	local isBodyPart = humanoidModel ~= nil and not thicknessOwner and not materialOwner
	local materialName: string
	local thicknessMm: number

	if isBodyPart then
		materialName = "Flesh"
		thicknessMm = 1
	else
		materialName = if type(materialValue) == "string" then materialValue else ""
		if materialName == "" then
			if hitPart:IsA("BasePart") then
				materialName = ArmorMaterials.fromRobloxMaterial(hitPart.Material)
			else
				materialName = "Steel"
			end
		end

		if type(thicknessValue) == "number" and Util.isFinite(thicknessValue) then
			thicknessMm = math.max(0, thicknessValue)
		elseif hitPart:IsA("BasePart") then
			thicknessMm = estimatedThicknessMm(hitPart)
		else
			thicknessMm = 10
		end
	end

	local integrity = if type(integrityValue) == "number" and Util.isFinite(integrityValue)
		then Util.clamp(integrityValue, 0, 1)
		else 1
	local material = ArmorMaterials.get(materialName)
	local source = thicknessOwner or materialOwner or integrityOwner or hitPart
	local explicitlyConfigured = thicknessOwner ~= nil or materialOwner ~= nil or integrityOwner ~= nil

	return {
		source = source,
		hitPart = hitPart,
		materialName = materialName,
		material = material,
		thicknessMm = thicknessMm,
		integrity = integrity,
		reactiveArmour = reactiveValue == true,
		reactiveArmourMultiplier = if reactiveOwner and type(reactiveOwner:GetAttribute("ReactiveArmorMultiplier")) == "number"
			then reactiveOwner:GetAttribute("ReactiveArmorMultiplier")
			else 1.8,
		spacedArmourMm = if type(spacingValue) == "number" then math.max(0, spacingValue) else 0,
		canRicochet = if canRicochetOwner then canRicochetValue ~= false else materialName ~= "Flesh",
		isBodyPart = isBodyPart,
		explicitlyConfigured = explicitlyConfigured,
	}
end

function ArmorService.applyImpactDamage(profile: {[string]: any}, impact: {[string]: any}, shell: {[string]: any}): number
	if not profile.explicitlyConfigured or profile.isBodyPart then
		return profile.integrity
	end

	local source: Instance = profile.source
	local current = source:GetAttribute("ArmorIntegrity")
	if type(current) ~= "number" or not Util.isFinite(current) then
		current = 1
	end

	local material = profile.material
	local hitPoints = source:GetAttribute("ArmorHitPointsJoules")
	if type(hitPoints) ~= "number" or hitPoints <= 0 then
		-- This default makes armour deteriorate under repeated, comparable hits
		-- without collapsing from a single glancing fragment.
		hitPoints = math.max(25000, profile.thicknessMm * material.rhaMultiplier * 10000)
	end
	local absorbedFraction = 1
	if impact.kind == "Penetrated" and impact.penetrationMm > 0 then
		absorbedFraction = Util.clamp(impact.rhaeMm / impact.penetrationMm, 0.1, 0.9)
	elseif impact.kind == "Ricochet" then
		absorbedFraction = 1 - shell.ricochetEnergyRetention
	end
	local loss = (impact.impactEnergyJoules * absorbedFraction * shell.armorDamageFactor * material.integrityLossMultiplier) / hitPoints
	local remaining = Util.clamp(current - loss, 0, 1)
	source:SetAttribute("ArmorIntegrity", remaining)
	return remaining
end

function ArmorService.applyBlastDamage(hitPart: Instance, blastEnergyJoules: number): number?
	local profile = ArmorService.getProfile(hitPart)
	if not profile.explicitlyConfigured or profile.isBodyPart then
		return nil
	end

	local source: Instance = profile.source
	local current = source:GetAttribute("ArmorIntegrity")
	if type(current) ~= "number" or not Util.isFinite(current) then
		current = 1
	end
	local hitPoints = source:GetAttribute("ArmorHitPointsJoules")
	if type(hitPoints) ~= "number" or hitPoints <= 0 then
		hitPoints = math.max(25000, profile.thicknessMm * profile.material.rhaMultiplier * 10000)
	end
	local remaining = Util.clamp(current - blastEnergyJoules * profile.material.integrityLossMultiplier / hitPoints, 0, 1)
	source:SetAttribute("ArmorIntegrity", remaining)
	return remaining
end

return ArmorService

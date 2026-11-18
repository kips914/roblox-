--!strict
-- Relative RHAe (Rolled Homogeneous Armour equivalent) values.
-- They are gameplay coefficients, not a substitute for certified armour data.

local ArmorMaterials = {
	Steel = {
		displayName = "RHA steel",
		rhaMultiplier = 1.00,
		ricochetBonusDegrees = 0,
		integrityLossMultiplier = 1.00,
	},
	CastSteel = {
		displayName = "Cast steel",
		rhaMultiplier = 0.88,
		ricochetBonusDegrees = -2,
		integrityLossMultiplier = 1.15,
	},
	Titanium = {
		displayName = "Titanium alloy",
		rhaMultiplier = 0.82,
		ricochetBonusDegrees = 1,
		integrityLossMultiplier = 0.92,
	},
	Aluminum = {
		displayName = "Aluminium alloy",
		rhaMultiplier = 0.43,
		ricochetBonusDegrees = -5,
		integrityLossMultiplier = 1.55,
	},
	Ceramic = {
		displayName = "Ceramic composite",
		rhaMultiplier = 1.25,
		ricochetBonusDegrees = -8,
		integrityLossMultiplier = 2.00,
	},
	UHMWPE = {
		displayName = "UHMWPE",
		rhaMultiplier = 0.35,
		ricochetBonusDegrees = -12,
		integrityLossMultiplier = 1.80,
	},
	Concrete = {
		displayName = "Concrete",
		rhaMultiplier = 0.17,
		ricochetBonusDegrees = -18,
		integrityLossMultiplier = 2.50,
	},
	Brick = {
		displayName = "Brick",
		rhaMultiplier = 0.12,
		ricochetBonusDegrees = -20,
		integrityLossMultiplier = 2.10,
	},
	Wood = {
		displayName = "Wood",
		rhaMultiplier = 0.035,
		ricochetBonusDegrees = -30,
		integrityLossMultiplier = 1.20,
	},
	Glass = {
		displayName = "Glass",
		rhaMultiplier = 0.06,
		ricochetBonusDegrees = -25,
		integrityLossMultiplier = 3.00,
	},
	Flesh = {
		displayName = "Unprotected body",
		rhaMultiplier = 0.01,
		ricochetBonusDegrees = -90,
		integrityLossMultiplier = 0,
	},
}

local robloxMaterialMap = {
	[Enum.Material.Metal] = "Steel",
	[Enum.Material.DiamondPlate] = "Steel",
	[Enum.Material.CorrodedMetal] = "CastSteel",
	[Enum.Material.Foil] = "Aluminum",
	[Enum.Material.Concrete] = "Concrete",
	[Enum.Material.Brick] = "Brick",
	[Enum.Material.Wood] = "Wood",
	[Enum.Material.WoodPlanks] = "Wood",
	[Enum.Material.Glass] = "Glass",
	[Enum.Material.Ice] = "Glass",
	[Enum.Material.Plastic] = "UHMWPE",
	[Enum.Material.SmoothPlastic] = "UHMWPE",
}

function ArmorMaterials.get(name: string?): {[string]: any}
	local candidate = ArmorMaterials[name or ""]
	if type(candidate) == "table" and type(candidate.rhaMultiplier) == "number" then
		return candidate
	end
	return ArmorMaterials.Steel
end

function ArmorMaterials.fromRobloxMaterial(material: Enum.Material): string
	return robloxMaterialMap[material] or "Steel"
end

return ArmorMaterials

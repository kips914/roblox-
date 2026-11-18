--!strict
-- Server-authoritative ammunition registry. The client can read it for labels
-- and tracer colours, but only the server uses its penetration numbers.

local Util = require(script.Parent.Util)

local ShellCatalog = {}
local shells: {[string]: {[string]: any}} = {}

local defaults = {
	family = "Kinetic",
	caliberMm = 30,
	massKg = 0.3,
	muzzleVelocityMps = 800,
	penetrationAtZeroMm = 25,
	penetrationExponent = 1.1,
	directDamage = 45,
	maxPenetrations = 1,
	maxDistanceM = 2500,
	maxLifetimeSeconds = 8,
	airDrag = 0.00018,
	ricochetStartAngleDegrees = 67,
	ricochetEnergyRetention = 0.55,
	armorDamageFactor = 1,
	tracerColor = Color3.fromRGB(255, 190, 75),
	explosiveMassKg = 0,
	explosionRadiusM = 0,
	shapedCharge = false,
	detonateOnImpact = false,
	detonateAfterPenetrationM = 0,
}

local function positiveNumber(value: any): boolean
	return type(value) == "number" and Util.isFinite(value) and value > 0
end

local function nonNegativeNumber(value: any): boolean
	return type(value) == "number" and Util.isFinite(value) and value >= 0
end

function ShellCatalog.validate(definition: any): (boolean, string?)
	if type(definition) ~= "table" then
		return false, "definition must be a table"
	end
	if type(definition.id) ~= "string" or #definition.id == 0 or not string.match(definition.id, "^[%w_%-]+$") then
		return false, "id must use letters, digits, _ or -"
	end
	if type(definition.displayName) ~= "string" or #definition.displayName == 0 then
		return false, "displayName is required"
	end

	for _, fieldName in ipairs({ "caliberMm", "massKg", "muzzleVelocityMps", "penetrationAtZeroMm", "directDamage" }) do
		if not nonNegativeNumber(definition[fieldName] ~= nil and definition[fieldName] or defaults[fieldName]) then
			return false, fieldName .. " must be a non-negative finite number"
		end
	end
	for _, fieldName in ipairs({ "maxPenetrations", "maxDistanceM", "maxLifetimeSeconds", "ricochetEnergyRetention", "armorDamageFactor", "explosiveMassKg", "explosionRadiusM", "detonateAfterPenetrationM" }) do
		if not nonNegativeNumber(definition[fieldName] ~= nil and definition[fieldName] or defaults[fieldName]) then
			return false, fieldName .. " must be a non-negative finite number"
		end
	end
	if not positiveNumber(definition.muzzleVelocityMps ~= nil and definition.muzzleVelocityMps or defaults.muzzleVelocityMps) then
		return false, "muzzleVelocityMps must be greater than zero"
	end
	if typeof(definition.tracerColor ~= nil and definition.tracerColor or defaults.tracerColor) ~= "Color3" then
		return false, "tracerColor must be Color3"
	end
	return true, nil
end

function ShellCatalog.register(definition: {[string]: any}, overwrite: boolean?): (boolean, string?)
	local valid, reason = ShellCatalog.validate(definition)
	if not valid then
		return false, reason
	end
	if shells[definition.id] and not overwrite then
		return false, "a shell with this id is already registered"
	end

	local shell = Util.copyTable(defaults)
	for key, value in pairs(definition) do
		shell[key] = Util.copyTable(value)
	end
	-- Clamp values that would produce nonsensical physics rather than trusting configs.
	shell.maxPenetrations = math.floor(Util.clamp(shell.maxPenetrations, 0, 16))
	shell.ricochetEnergyRetention = Util.clamp(shell.ricochetEnergyRetention, 0, 0.95)
	shell.ricochetStartAngleDegrees = Util.clamp(shell.ricochetStartAngleDegrees, 1, 89.5)
	shell.airDrag = Util.clamp(shell.airDrag, 0, 0.1)
	shells[shell.id] = shell
	return true, nil
end

function ShellCatalog.get(id: string): {[string]: any}?
	local shell = shells[id]
	if not shell then
		return nil
	end
	return Util.copyTable(shell)
end

function ShellCatalog.getAll(): {{[string]: any}}
	local result = {}
	for _, shell in pairs(shells) do
		table.insert(result, Util.copyTable(shell))
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

-- Default 30 mm family. Values are balanced game values expressed in SI units
-- and RHAe millimetres, not ammunition specifications for real weapons.
for _, shell in ipairs({
	{
		id = "AP_30MM",
		displayName = "30 mm AP",
		family = "Armour Piercing",
		caliberMm = 30,
		massKg = 0.39,
		muzzleVelocityMps = 1080,
		penetrationAtZeroMm = 54,
		penetrationExponent = 1.18,
		directDamage = 72,
		maxPenetrations = 3,
		ricochetStartAngleDegrees = 66,
		ricochetEnergyRetention = 0.57,
		armorDamageFactor = 1.0,
		tracerColor = Color3.fromRGB(255, 213, 120),
	},
	{
		id = "HE_30MM",
		displayName = "30 mm HE",
		family = "High Explosive",
		caliberMm = 30,
		massKg = 0.36,
		muzzleVelocityMps = 810,
		penetrationAtZeroMm = 8,
		penetrationExponent = 0.7,
		directDamage = 28,
		maxPenetrations = 0,
		ricochetStartAngleDegrees = 75,
		ricochetEnergyRetention = 0.25,
		armorDamageFactor = 2.1,
		explosiveMassKg = 0.19,
		explosionRadiusM = 4.8,
		detonateOnImpact = true,
		tracerColor = Color3.fromRGB(255, 95, 35),
	},
	{
		id = "HEAT_30MM",
		displayName = "30 mm HEAT",
		family = "Shaped Charge",
		caliberMm = 30,
		massKg = 0.42,
		muzzleVelocityMps = 900,
		penetrationAtZeroMm = 220,
		penetrationExponent = 0,
		directDamage = 105,
		maxPenetrations = 1,
		ricochetStartAngleDegrees = 82,
		ricochetEnergyRetention = 0,
		armorDamageFactor = 2.8,
		explosiveMassKg = 0.20,
		explosionRadiusM = 2.7,
		shapedCharge = true,
		detonateOnImpact = true,
		tracerColor = Color3.fromRGB(130, 255, 140),
	},
	{
		id = "APFSDS_30MM",
		displayName = "30 mm APFSDS",
		family = "Fin-Stabilised Sabot",
		caliberMm = 30,
		massKg = 0.19,
		muzzleVelocityMps = 1430,
		penetrationAtZeroMm = 125,
		penetrationExponent = 1.35,
		directDamage = 110,
		maxPenetrations = 5,
		ricochetStartAngleDegrees = 71,
		ricochetEnergyRetention = 0.64,
		armorDamageFactor = 0.85,
		tracerColor = Color3.fromRGB(210, 240, 255),
	},
}) do
	local registered, reason = ShellCatalog.register(shell)
	if not registered then
		error("Default shell failed validation: " .. (reason or "unknown error"))
	end
end

-- The same definitions are registered in the client process so the HUD can
-- show a custom display name. Statistics remain harmless client-side: the
-- server has its own module cache and remains the sole authority for damage.
local customShellsModule = script.Parent.Parent:FindFirstChild("CustomShells")
if customShellsModule and customShellsModule:IsA("ModuleScript") then
	local loaded, customShells = pcall(require, customShellsModule)
	if loaded and type(customShells) == "table" then
		for _, definition in ipairs(customShells) do
			local registered, reason = ShellCatalog.register(definition)
			if not registered then
				warn("[Combat] Custom shell was skipped: " .. tostring(reason))
			end
		end
	elseif not loaded then
		warn("[Combat] CustomShells failed: " .. tostring(customShells))
	else
		warn("[Combat] CustomShells must return an array of definitions.")
	end
end

return ShellCatalog

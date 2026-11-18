--!strict
-- Small, dependency-free helpers shared by the server and the client.

local Util = {}

Util.STUDS_PER_METER = 1 / 0.28 -- Roblox's commonly used real-world scale.
Util.METERS_PER_STUD = 0.28
Util.MM_PER_STUD = Util.METERS_PER_STUD * 1000

function Util.clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

function Util.isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Util.isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and Util.isFinite(value.X)
		and Util.isFinite(value.Y)
		and Util.isFinite(value.Z)
end

function Util.safeUnit(value: Vector3, fallback: Vector3?): Vector3
	if value.Magnitude > 1e-5 then
		return value.Unit
	end
	return fallback or Vector3.zAxis
end

function Util.reflect(direction: Vector3, normal: Vector3): Vector3
	return direction - 2 * direction:Dot(normal) * normal
end

-- 0 degrees is a square, head-on strike. 90 degrees is a grazing strike.
function Util.impactAngleDegrees(direction: Vector3, surfaceNormal: Vector3): number
	local incoming = -Util.safeUnit(direction)
	local cosine = Util.clamp(incoming:Dot(Util.safeUnit(surfaceNormal)), -1, 1)
	return math.deg(math.acos(cosine))
end

function Util.kineticEnergyJoules(massKg: number, velocityMps: number): number
	return 0.5 * massKg * velocityMps * velocityMps
end

function Util.copyTable<T>(source: T): T
	if type(source) ~= "table" then
		return source
	end

	local result = {} :: any
	for key, value in pairs(source :: any) do
		result[key] = Util.copyTable(value)
	end
	return result
end

function Util.splitCommaList(value: any): {string}
	if type(value) ~= "string" then
		return {}
	end

	local result = {}
	for item in string.gmatch(value, "[^,%s]+") do
		table.insert(result, item)
	end
	return result
end

function Util.listContains(list: {string}, wanted: string): boolean
	for _, value in ipairs(list) do
		if value == wanted then
			return true
		end
	end
	return false
end

return Util

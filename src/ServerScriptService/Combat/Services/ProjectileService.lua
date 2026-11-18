--!strict
-- Authoritative, raycast-based projectile simulation. No server-side tracer
-- parts are created, which keeps automatic cannons performant; clients receive
-- cosmetic projectile and impact events through CombatRemotes.ProjectileFX.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local Util = require(Shared.Util)
local Ballistics = require(Shared.Ballistics)

local ArmorService = require(script.Parent.ArmorService)
local DamageService = require(script.Parent.DamageService)

local ProjectileService = {}
ProjectileService.__index = ProjectileService

local MAX_ACTIVE_PROJECTILES = 512
local MAX_SUBSTEP_SECONDS = 1 / 90
local SURFACE_EPSILON = 0.045

local function appendUnique(list: {Instance}, instance: Instance?)
	if not instance then
		return
	end
	for _, existing in ipairs(list) do
		if existing == instance then
			return
		end
	end
	table.insert(list, instance)
end

local function impactEffectName(kind: string): string
	if kind == "Penetrated" then
		return "Penetration"
	elseif kind == "Ricochet" then
		return "Ricochet"
	end
	return "Stopped"
end

function ProjectileService.new(projectileFX: RemoteEvent)
	local self = setmetatable({}, ProjectileService)
	self._projectileFX = projectileFX
	self._active = {} :: {[number]: {[string]: any}}
	self._nextId = 0
	self._connection = nil
	return self
end

function ProjectileService:start()
	if self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_stepAll(math.min(deltaTime, 0.2))
	end)
end

function ProjectileService:spawn(
	origin: Vector3,
	direction: Vector3,
	shell: {[string]: any},
	attacker: Player?,
	weapon: Tool?
): number?
	if not Util.isFiniteVector3(origin) or not Util.isFiniteVector3(direction) or direction.Magnitude < 0.001 then
		return nil
	end
	if self:getActiveCount() >= MAX_ACTIVE_PROJECTILES then
		warn("[Combat] Active projectile cap reached; fire request ignored.")
		return nil
	end

	self._nextId += 1
	local id = self._nextId
	local unitDirection = direction.Unit
	local ignored = {}
	if attacker and attacker.Character then
		appendUnique(ignored, attacker.Character)
	end
	appendUnique(ignored, weapon)

	local speedStuds = Ballistics.velocityToStudsPerSecond(shell.muzzleVelocityMps)
	local state = {
		id = id,
		shell = shell,
		attacker = attacker,
		weapon = weapon,
		position = origin,
		velocity = unitDirection * speedStuds,
		spawnPosition = origin,
		age = 0,
		distanceStuds = 0,
		remainingPenetrations = shell.maxPenetrations,
		ricochets = 0,
		ignored = ignored,
		random = Random.new((id * 1103515245 + math.floor(workspace:GetServerTimeNow() * 1000)) % 2147483646),
		fuseDistanceStuds = nil,
	}
	self._active[id] = state

	self._projectileFX:FireAllClients("Spawn", id, origin, state.velocity, {
		color = shell.tracerColor,
		caliberMm = shell.caliberMm,
	})
	return id
end

function ProjectileService:getActiveCount(): number
	local count = 0
	for _ in pairs(self._active) do
		count += 1
	end
	return count
end

function ProjectileService:_stop(state: {[string]: any}, reason: string)
	if not self._active[state.id] then
		return
	end
	self._active[state.id] = nil
	self._projectileFX:FireAllClients("Stop", state.id, state.position, reason)
end

function ProjectileService:_explode(state: {[string]: any}, position: Vector3)
	DamageService.applyExplosion(position, state.shell, state.attacker)
	self._projectileFX:FireAllClients("Explosion", state.id, position, state.shell.explosionRadiusM, state.shell.tracerColor)
end

function ProjectileService:_sendImpact(
	state: {[string]: any},
	position: Vector3,
	normal: Vector3,
	kind: string,
	materialName: string
)
	self._projectileFX:FireAllClients(
		"Impact",
		state.id,
		position,
		normal,
		impactEffectName(kind),
		materialName,
		state.shell.tracerColor
	)
end

function ProjectileService:_handleImpact(state: {[string]: any}, cast: RaycastResult): boolean
	local velocity = state.velocity
	local direction = Util.safeUnit(velocity)
	local velocityMps = Ballistics.velocityToMps(velocity)
	if velocityMps < 20 then
		self:_stop(state, "LowVelocity")
		return false
	end

	local profile = ArmorService.getProfile(cast.Instance)
	local impactAngle = Util.impactAngleDegrees(direction, cast.Normal)
	local outcome = Ballistics.resolveImpact(state.shell, velocityMps, profile, impactAngle, state.random)
	ArmorService.applyImpactDamage(profile, outcome, state.shell)
	state.position = cast.Position
	self:_sendImpact(state, cast.Position, cast.Normal, outcome.kind, profile.materialName)

	-- HE detonates at the first surface it reaches. HEAT performs its armour
	-- calculation first so that its shaped-charge jet can injure a target behind
	-- a penetrated plate, then its residual explosive effect is applied.
	if state.shell.detonateOnImpact and not state.shell.shapedCharge then
		self:_explode(state, cast.Position)
		self:_stop(state, "Detonated")
		return false
	end

	if outcome.kind == "Ricochet" then
		state.ricochets += 1
		if state.ricochets > 4 then
			self:_stop(state, "RicochetLimit")
			return false
		end
		local reflected = Util.safeUnit(Util.reflect(direction, cast.Normal), direction)
		local reflectedSpeed = velocity.Magnitude * state.shell.ricochetEnergyRetention
		if reflectedSpeed * Util.METERS_PER_STUD < 20 then
			self:_stop(state, "RicochetLowVelocity")
			return false
		end
		state.velocity = reflected * reflectedSpeed
		state.position = cast.Position + reflected * SURFACE_EPSILON
		appendUnique(state.ignored, cast.Instance)
		return true
	end

	if outcome.kind == "Stopped" then
		if state.shell.shapedCharge and state.shell.explosiveMassKg > 0 then
			self:_explode(state, cast.Position)
		end
		self:_stop(state, "Stopped")
		return false
	end

	-- A successful perforation transfers damage to any Humanoid that owns the
	-- hit part. It also allows intentionally configured armour to lose integrity.
	DamageService.applyPenetrationDamage(cast.Instance, state.shell, outcome, state.attacker)
	if state.shell.shapedCharge then
		if state.shell.explosiveMassKg > 0 then
			self:_explode(state, cast.Position + direction * SURFACE_EPSILON)
		end
		self:_stop(state, "ShapedChargeDetonated")
		return false
	end

	state.remainingPenetrations -= 1
	if state.remainingPenetrations <= 0 then
		self:_stop(state, "PenetrationLimit")
		return false
	end

	local postVelocityMps = Ballistics.postPenetrationVelocity(state.shell, velocityMps, outcome)
	if postVelocityMps < 20 then
		self:_stop(state, "PostPenetrationLowVelocity")
		return false
	end
	state.velocity = direction * Ballistics.velocityToStudsPerSecond(postVelocityMps)
	state.position = cast.Position + direction * SURFACE_EPSILON
	appendUnique(state.ignored, cast.Instance)

	if state.shell.detonateAfterPenetrationM > 0 then
		state.fuseDistanceStuds = state.shell.detonateAfterPenetrationM * Util.STUDS_PER_METER
	end
	return true
end

function ProjectileService:_stepProjectile(state: {[string]: any}, deltaTime: number): boolean
	local shell = state.shell
	state.age += deltaTime
	if state.age > shell.maxLifetimeSeconds then
		self:_stop(state, "Lifetime")
		return false
	end
	if state.distanceStuds * Util.METERS_PER_STUD > shell.maxDistanceM then
		self:_stop(state, "Range")
		return false
	end

	-- Air drag is applied to speed before gravity. Shell values are deliberately
	-- small and represent a stable, game-friendly approximation.
	local speedMps = Ballistics.velocityToMps(state.velocity)
	local dragMultiplier = math.exp(-shell.airDrag * speedMps * deltaTime)
	state.velocity *= dragMultiplier
	state.velocity += Vector3.new(0, -workspace.Gravity, 0) * deltaTime

	local displacement = state.velocity * deltaTime
	local displacementLength = displacement.Magnitude
	if displacementLength < 0.001 then
		return true
	end

	if state.fuseDistanceStuds and state.fuseDistanceStuds <= displacementLength then
		local fusePosition = state.position + displacement.Unit * state.fuseDistanceStuds
		state.position = fusePosition
		self:_explode(state, fusePosition)
		self:_stop(state, "Fuse")
		return false
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = state.ignored
	raycastParams.IgnoreWater = false
	local cast = workspace:Raycast(state.position, displacement, raycastParams)

	if not cast then
		state.position += displacement
		state.distanceStuds += displacementLength
		if state.fuseDistanceStuds then
			state.fuseDistanceStuds -= displacementLength
		end
		return true
	end

	local traveled = (cast.Position - state.position).Magnitude
	state.distanceStuds += traveled
	return self:_handleImpact(state, cast)
end

function ProjectileService:_stepAll(deltaTime: number)
	local remaining = deltaTime
	while remaining > 0 do
		local step = math.min(remaining, MAX_SUBSTEP_SECONDS)
		remaining -= step
		for _, state in pairs(self._active) do
			if self._active[state.id] then
				self:_stepProjectile(state, step)
			end
		end
	end
end

return ProjectileService

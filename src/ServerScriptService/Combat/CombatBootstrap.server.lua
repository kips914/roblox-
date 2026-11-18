--!strict
-- Entry point for the server side of the armour/ballistics system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local ShellCatalog = require(Shared.ShellCatalog)

local ProjectileService = require(script.Parent.Services.ProjectileService)
local WeaponService = require(script.Parent.Services.WeaponService)

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName ~= className then
			error(string.format("[Combat] %s must be a %s, not a %s", existing:GetFullName(), className, existing.ClassName))
		end
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local remotes = ensure(Combat, "Folder", "CombatRemotes") :: Folder
local weaponRequest = ensure(remotes, "RemoteEvent", "WeaponRequest") :: RemoteEvent
local weaponFeedback = ensure(remotes, "RemoteEvent", "WeaponFeedback") :: RemoteEvent
local projectileFX = ensure(remotes, "RemoteEvent", "ProjectileFX") :: RemoteEvent

-- ShellCatalog loads developer-authored CustomShells during module startup.
-- Its server-side module cache is the only source used for live ballistics.

local projectileService = ProjectileService.new(projectileFX)
projectileService:start()

local weaponService = WeaponService.new(projectileService, weaponFeedback)
weaponService:start(weaponRequest)

Combat:SetAttribute("CombatVersion", "1.0.0")
print("[Combat] Ballistics system started with " .. tostring(#ShellCatalog.getAll()) .. " shell types.")

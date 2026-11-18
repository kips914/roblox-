--!strict
-- Validates client fire/reload requests and turns a Tool into a server-driven
-- weapon. A client can request an aim direction but can never choose the
-- muzzle position, ammunition data, rate of fire, penetration or damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local Util = require(Shared.Util)
local ShellCatalog = require(Shared.ShellCatalog)

local WeaponService = {}
WeaponService.__index = WeaponService

local DEFAULT_CONFIG = {
	MuzzleName = "Muzzle",
	MagazineSize = 12,
	ReloadTimeSeconds = 2.5,
	FireIntervalSeconds = 0.25,
	MaxAimAngleDegrees = 89,
	AllowedShells = { "AP_30MM" },
}

local function mergeConfig(overrides: any): {[string]: any}
	local config = Util.copyTable(DEFAULT_CONFIG)
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			config[key] = value
		end
	end
	return config
end

local function validNumber(value: any, fallback: number, minimum: number, maximum: number): number
	if type(fallback) ~= "number" or not Util.isFinite(fallback) then
		fallback = minimum
	end
	if type(value) ~= "number" or not Util.isFinite(value) then
		return Util.clamp(fallback, minimum, maximum)
	end
	return Util.clamp(value, minimum, maximum)
end

function WeaponService.new(projectileService: any, feedback: RemoteEvent)
	local self = setmetatable({}, WeaponService)
	self._projectileService = projectileService
	self._feedback = feedback
	self._states = setmetatable({}, { __mode = "k" }) :: {[Tool]: {[string]: any}}
	return self
end

function WeaponService:_configFor(tool: Tool): {[string]: any}
	local configModule = tool:FindFirstChild("WeaponConfig")
	if configModule and configModule:IsA("ModuleScript") then
		local ok, value = pcall(require, configModule)
		if ok then
			return mergeConfig(value)
		end
		warn("[Combat] WeaponConfig failed for " .. tool:GetFullName() .. ": " .. tostring(value))
	end
	return mergeConfig(nil)
end

function WeaponService:_allowedShells(tool: Tool, config: {[string]: any}): {string}
	local fromAttribute = Util.splitCommaList(tool:GetAttribute("AmmoTypes"))
	if #fromAttribute > 0 then
		return fromAttribute
	end
	if type(config.AllowedShells) == "table" then
		local result = {}
		for _, shellId in ipairs(config.AllowedShells) do
			if type(shellId) == "string" then
				table.insert(result, shellId)
			end
		end
		return result
	end
	return {}
end

function WeaponService:_isCombatTool(tool: any): boolean
	return typeof(tool) == "Instance" and tool:IsA("Tool") and tool:GetAttribute("CombatWeapon") == true
end

function WeaponService:_initialize(tool: Tool): {[string]: any}
	local state = self._states[tool]
	if state then
		return state
	end

	local config = self:_configFor(tool)
	local magazineSize = math.floor(validNumber(tool:GetAttribute("MagazineSize"), config.MagazineSize, 1, 1000))
	local shells = self:_allowedShells(tool, config)
	if #shells == 0 then
		shells = Util.copyTable(DEFAULT_CONFIG.AllowedShells)
	end
	local usableShells = {}
	for _, shellId in ipairs(shells) do
		if ShellCatalog.get(shellId) then
			table.insert(usableShells, shellId)
		else
			warn("[Combat] " .. tool:GetFullName() .. " refers to unknown shell " .. shellId)
		end
	end
	if #usableShells == 0 then
		usableShells = { "AP_30MM" }
	end

	tool:SetAttribute("MagazineSize", magazineSize)
	tool:SetAttribute("AmmoTypes", table.concat(usableShells, ","))
	tool:SetAttribute("AmmoInMagazine", math.floor(validNumber(tool:GetAttribute("AmmoInMagazine"), 0, 0, magazineSize)))
	local selected = tool:GetAttribute("SelectedShellType")
	if type(selected) ~= "string" or not Util.listContains(usableShells, selected) then
		selected = usableShells[1]
		tool:SetAttribute("SelectedShellType", selected)
	end
	local loaded = tool:GetAttribute("LoadedShellType")
	if type(loaded) ~= "string" or not Util.listContains(usableShells, loaded) then
		tool:SetAttribute("LoadedShellType", selected)
	end
	if tool:GetAttribute("Reloading") == nil then
		tool:SetAttribute("Reloading", false)
	end

	state = {
		config = config,
		allowedShells = usableShells,
		lastFireTime = -math.huge,
		reloadToken = 0,
	}
	self._states[tool] = state
	return state
end

function WeaponService:_feedbackTo(player: Player, eventName: string, tool: Tool, extra: any?)
	self._feedback:FireClient(player, eventName, tool, extra)
end

function WeaponService:_validOwnedTool(player: Player, tool: any): Tool?
	if not self:_isCombatTool(tool) then
		return nil
	end
	if not player.Character or not tool:IsDescendantOf(player.Character) then
		return nil
	end
	return tool
end

function WeaponService:_muzzleCFrame(tool: Tool, config: {[string]: any}): CFrame?
	local configuredName = tool:GetAttribute("MuzzleName")
	local muzzleName = if type(configuredName) == "string" and #configuredName > 0 then configuredName else config.MuzzleName
	if type(muzzleName) ~= "string" then
		muzzleName = DEFAULT_CONFIG.MuzzleName
	end
	local muzzle = tool:FindFirstChild(muzzleName, true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldCFrame
	elseif muzzle and muzzle:IsA("BasePart") then
		return muzzle.CFrame
	end
	return nil
end

function WeaponService:_fire(player: Player, candidateTool: any, requestedDirection: any)
	local tool = self:_validOwnedTool(player, candidateTool)
	if not tool then
		return
	end
	if not Util.isFiniteVector3(requestedDirection) or requestedDirection.Magnitude < 0.01 then
		return
	end

	local state = self:_initialize(tool)
	local config = state.config
	if tool:GetAttribute("Reloading") == true then
		self:_feedbackTo(player, "Reloading", tool)
		return
	end
	local now = workspace:GetServerTimeNow()
	local fireInterval = validNumber(tool:GetAttribute("FireIntervalSeconds"), config.FireIntervalSeconds, 0.03, 10)
	if now - state.lastFireTime < fireInterval then
		return
	end

	local ammo = math.floor(validNumber(tool:GetAttribute("AmmoInMagazine"), 0, 0, 1000))
	if ammo <= 0 then
		self:_feedbackTo(player, "Empty", tool)
		return
	end
	local loadedShell = tool:GetAttribute("LoadedShellType")
	if type(loadedShell) ~= "string" or not Util.listContains(state.allowedShells, loadedShell) then
		self:_feedbackTo(player, "InvalidLoad", tool)
		return
	end
	local shell = ShellCatalog.get(loadedShell)
	if not shell then
		self:_feedbackTo(player, "InvalidLoad", tool)
		return
	end

	local muzzleCFrame = self:_muzzleCFrame(tool, config)
	if not muzzleCFrame then
		self:_feedbackTo(player, "MissingMuzzle", tool)
		return
	end
	local direction = requestedDirection.Unit
	local maxAngle = validNumber(tool:GetAttribute("MaxAimAngleDegrees"), config.MaxAimAngleDegrees, 1, 89.9)
	local forwardDot = Util.clamp(muzzleCFrame.LookVector:Dot(direction), -1, 1)
	if math.deg(math.acos(forwardDot)) > maxAngle then
		self:_feedbackTo(player, "AimRejected", tool)
		return
	end

	state.lastFireTime = now
	tool:SetAttribute("AmmoInMagazine", ammo - 1)
	tool:SetAttribute("SelectedShellType", loadedShell)
	local projectileId = self._projectileService:spawn(muzzleCFrame.Position, direction, shell, player, tool)
	if not projectileId then
		tool:SetAttribute("AmmoInMagazine", ammo) -- server cap, so do not consume a round
		return
	end
	self:_feedbackTo(player, "Fired", tool, {
		ammo = ammo - 1,
		shellId = loadedShell,
	})
end

function WeaponService:_selectShell(player: Player, candidateTool: any, desiredShell: any)
	local tool = self:_validOwnedTool(player, candidateTool)
	if not tool or type(desiredShell) ~= "string" then
		return
	end
	local state = self:_initialize(tool)
	if not Util.listContains(state.allowedShells, desiredShell) then
		self:_feedbackTo(player, "ShellNotAllowed", tool)
		return
	end
	local ammo = math.floor(validNumber(tool:GetAttribute("AmmoInMagazine"), 0, 0, 1000))
	local loaded = tool:GetAttribute("LoadedShellType")
	if ammo > 0 and loaded ~= desiredShell then
		self:_feedbackTo(player, "MagazineNotEmpty", tool)
		return
	end
	tool:SetAttribute("SelectedShellType", desiredShell)
	if ammo <= 0 then
		tool:SetAttribute("LoadedShellType", desiredShell)
	end
	self:_feedbackTo(player, "ShellSelected", tool, desiredShell)
end

function WeaponService:_reload(player: Player, candidateTool: any, desiredShell: any)
	local tool = self:_validOwnedTool(player, candidateTool)
	if not tool then
		return
	end
	local state = self:_initialize(tool)
	if tool:GetAttribute("Reloading") == true then
		return
	end

	local selected = if type(desiredShell) == "string" then desiredShell else tool:GetAttribute("SelectedShellType")
	if type(selected) ~= "string" or not Util.listContains(state.allowedShells, selected) then
		self:_feedbackTo(player, "ShellNotAllowed", tool)
		return
	end
	local ammo = math.floor(validNumber(tool:GetAttribute("AmmoInMagazine"), 0, 0, 1000))
	local loaded = tool:GetAttribute("LoadedShellType")
	if ammo > 0 and loaded ~= selected then
		self:_feedbackTo(player, "MagazineNotEmpty", tool)
		return
	end

	local reserveKey = "Ammo_" .. selected
	local reserve = math.floor(validNumber(tool:GetAttribute(reserveKey), 0, 0, 100000))
	if reserve <= 0 then
		self:_feedbackTo(player, "NoReserveAmmo", tool, selected)
		return
	end
	local capacity = math.floor(validNumber(tool:GetAttribute("MagazineSize"), state.config.MagazineSize, 1, 1000))
	if ammo >= capacity then
		self:_feedbackTo(player, "MagazineFull", tool)
		return
	end

	state.reloadToken += 1
	local token = state.reloadToken
	tool:SetAttribute("Reloading", true)
	tool:SetAttribute("SelectedShellType", selected)
	self:_feedbackTo(player, "ReloadStarted", tool, selected)
	local reloadTime = validNumber(tool:GetAttribute("ReloadTimeSeconds"), state.config.ReloadTimeSeconds, 0.05, 30)

	task.delay(reloadTime, function()
		if not tool.Parent or self._states[tool] ~= state or state.reloadToken ~= token then
			return
		end
		tool:SetAttribute("Reloading", false)
		if not player.Character or not tool:IsDescendantOf(player.Character) then
			return
		end
		local currentAmmo = math.floor(validNumber(tool:GetAttribute("AmmoInMagazine"), 0, 0, capacity))
		local currentReserve = math.floor(validNumber(tool:GetAttribute(reserveKey), 0, 0, 100000))
		local loadedNow = tool:GetAttribute("LoadedShellType")
		if currentAmmo > 0 and loadedNow ~= selected then
			return
		end
		local moved = math.min(capacity - currentAmmo, currentReserve)
		if moved <= 0 then
			self:_feedbackTo(player, "NoReserveAmmo", tool, selected)
			return
		end
		tool:SetAttribute("LoadedShellType", selected)
		tool:SetAttribute("SelectedShellType", selected)
		tool:SetAttribute("AmmoInMagazine", currentAmmo + moved)
		tool:SetAttribute(reserveKey, currentReserve - moved)
		self:_feedbackTo(player, "Reloaded", tool, {
			shellId = selected,
			ammo = currentAmmo + moved,
			reserve = currentReserve - moved,
		})
	end)
end

function WeaponService:handleRequest(player: Player, action: any, tool: any, argument: any)
	if type(action) ~= "string" then
		return
	end
	if action == "Fire" then
		self:_fire(player, tool, argument)
	elseif action == "Reload" then
		self:_reload(player, tool, argument)
	elseif action == "SelectShell" then
		self:_selectShell(player, tool, argument)
	end
end

function WeaponService:_observeCharacter(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Tool") and self:_isCombatTool(descendant) then
			self:_initialize(descendant)
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Tool") then
			task.defer(function()
			if descendant.Parent and self:_isCombatTool(descendant) then
				self:_initialize(descendant)
			end
		end)
		end
	end)
end

function WeaponService:start(requestRemote: RemoteEvent)
	requestRemote.OnServerEvent:Connect(function(player, action, tool, argument)
		self:handleRequest(player, action, tool, argument)
	end)

	local function observePlayer(player: Player)
		if player.Character then
			self:_observeCharacter(player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			self:_observeCharacter(character)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)
end

return WeaponService

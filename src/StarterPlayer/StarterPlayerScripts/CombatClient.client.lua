--!strict
-- Client input, a compact ammunition HUD, and cosmetic tracer/impact effects.
-- This script contains no trusted damage calculation; the server owns it all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Shared = Combat:WaitForChild("Shared")
local ShellCatalog = require(Shared.ShellCatalog)
local Remotes = Combat:WaitForChild("CombatRemotes")
local WeaponRequest = Remotes:WaitForChild("WeaponRequest") :: RemoteEvent
local WeaponFeedback = Remotes:WaitForChild("WeaponFeedback") :: RemoteEvent
local ProjectileFX = Remotes:WaitForChild("ProjectileFX") :: RemoteEvent

local currentTool: Tool? = nil
local currentAttributeConnections: {RBXScriptConnection} = {}
local toolConnections: {[Tool]: {RBXScriptConnection}} = {}
local tracers: {[number]: {[string]: any}} = {}

local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "AmmoPanel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.fromOffset(20, -24)
panel.Size = UDim2.fromOffset(340, 76)
panel.BackgroundColor3 = Color3.fromRGB(10, 13, 18)
panel.BackgroundTransparency = 0.22
panel.BorderSizePixel = 0
panel.Parent = gui

local shellLabel = Instance.new("TextLabel")
shellLabel.Name = "Shell"
shellLabel.Position = UDim2.fromOffset(12, 8)
shellLabel.Size = UDim2.fromOffset(316, 27)
shellLabel.BackgroundTransparency = 1
shellLabel.Font = Enum.Font.GothamBold
shellLabel.TextSize = 18
shellLabel.TextXAlignment = Enum.TextXAlignment.Left
shellLabel.TextColor3 = Color3.fromRGB(240, 244, 255)
shellLabel.Text = "Оружие не выбрано"
shellLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Position = UDim2.fromOffset(12, 37)
statusLabel.Size = UDim2.fromOffset(316, 27)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = Color3.fromRGB(180, 196, 217)
statusLabel.Text = "R — перезарядка | 1–4 — тип снаряда"
statusLabel.Parent = panel

local function disconnectAll(connections: {RBXScriptConnection})
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function isCombatTool(tool: Instance?): boolean
	return tool ~= nil and tool:IsA("Tool") and tool:GetAttribute("CombatWeapon") == true
end

local function reserveFor(tool: Tool, shellId: string): number
	local value = tool:GetAttribute("Ammo_" .. shellId)
	return if type(value) == "number" then math.max(0, math.floor(value)) else 0
end

local function updateHud(message: string?)
	if not currentTool or not currentTool.Parent then
		shellLabel.Text = "Оружие не выбрано"
		statusLabel.Text = message or "R — перезарядка | 1–4 — тип снаряда"
		return
	end

	local shellId = currentTool:GetAttribute("SelectedShellType")
	local shell = if type(shellId) == "string" then ShellCatalog.get(shellId) else nil
	local readableName = if shell then shell.displayName else tostring(shellId or "—")
	local ammo = currentTool:GetAttribute("AmmoInMagazine")
	local capacity = currentTool:GetAttribute("MagazineSize")
	local ammoNumber = if type(ammo) == "number" then math.max(0, math.floor(ammo)) else 0
	local capacityNumber = if type(capacity) == "number" then math.max(0, math.floor(capacity)) else 0
	local reserve = if type(shellId) == "string" then reserveFor(currentTool, shellId) else 0

	shellLabel.Text = string.format("%s   %d / %d", readableName, ammoNumber, capacityNumber)
	if currentTool:GetAttribute("Reloading") == true then
		statusLabel.Text = "Перезарядка…"
	else
		statusLabel.Text = message or string.format("Запас: %d   |   R — перезарядка   |   1–4 — снаряд", reserve)
	end
end

local function aimDirection(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	return camera.CFrame.LookVector
end

local function equip(tool: Tool)
	if not isCombatTool(tool) then
		return
	end
	currentTool = tool
	disconnectAll(currentAttributeConnections)
	for _, attributeName in ipairs({ "SelectedShellType", "LoadedShellType", "AmmoInMagazine", "MagazineSize", "Reloading", "AmmoTypes" }) do
		table.insert(currentAttributeConnections, tool:GetAttributeChangedSignal(attributeName):Connect(function()
			updateHud()
		end))
	end
	updateHud()
end

local function unequip(tool: Tool)
	if currentTool == tool then
		currentTool = nil
		disconnectAll(currentAttributeConnections)
		updateHud()
	end
end

local function bindTool(tool: Tool)
	if toolConnections[tool] then
		return
	end
	local connections = {}
	toolConnections[tool] = connections
	table.insert(connections, tool.Equipped:Connect(function()
		equip(tool)
	end))
	table.insert(connections, tool.Unequipped:Connect(function()
		unequip(tool)
	end))
	table.insert(connections, tool.Activated:Connect(function()
		if currentTool ~= tool or not isCombatTool(tool) then
			return
		end
		local direction = aimDirection()
		if direction then
			WeaponRequest:FireServer("Fire", tool, direction)
		end
	end))
	table.insert(connections, tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unequip(tool)
			disconnectAll(connections)
			toolConnections[tool] = nil
		end
	end))
end

local function observeCharacter(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
end

if player.Character then
	observeCharacter(player.Character)
end
player.CharacterAdded:Connect(observeCharacter)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not currentTool or not isCombatTool(currentTool) then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		WeaponRequest:FireServer("Reload", currentTool, currentTool:GetAttribute("SelectedShellType"))
		return
	end

	local shellIndexByKey = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
	}
	local index = shellIndexByKey[input.KeyCode]
	if index then
		local shellIds = string.split(currentTool:GetAttribute("AmmoTypes") or "", ",")
		local shellId = shellIds[index]
		if shellId and #shellId > 0 then
			WeaponRequest:FireServer("SelectShell", currentTool, shellId)
		end
	end
end)

local feedbackText = {
	Empty = "Магазин пуст — нажмите R",
	Reloading = "Перезарядка…",
	ReloadStarted = "Перезарядка начата…",
	MagazineNotEmpty = "Сначала израсходуйте текущий тип снарядов",
	NoReserveAmmo = "Нет боеприпасов этого типа",
	MagazineFull = "Магазин уже заполнен",
	MissingMuzzle = "Не найден Muzzle у оружия",
	AimRejected = "Недопустимое направление выстрела",
	InvalidLoad = "Некорректный тип снаряда",
	ShellNotAllowed = "Этот снаряд не поддерживается оружием",
	ShellSelected = "Тип снаряда выбран",
	Reloaded = "Магазин снаряжён",
}

WeaponFeedback.OnClientEvent:Connect(function(eventName: string, tool: Tool, extra: any)
	if tool ~= currentTool then
		return
	end
	updateHud(feedbackText[eventName])
end)

local function createEffectPart(position: Vector3, color: Color3, size: number): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Position = position
	part.Parent = workspace
	return part
end

local function impactEffect(position: Vector3, normal: Vector3, kind: string, color: Color3)
	local size = if kind == "Ricochet" then 0.22 else 0.16
	local flash = createEffectPart(position + normal * 0.02, color, size)
	local tween = TweenService:Create(flash, TweenInfo.new(0.12), {
		Transparency = 1,
		Size = flash.Size * 3,
	})
	tween:Play()
	Debris:AddItem(flash, 0.14)
end

local function explosionEffect(position: Vector3, radiusMeters: number, color: Color3)
	local radiusStuds = math.max(1, radiusMeters / 0.28)
	local flash = createEffectPart(position, color, 0.35)
	local tween = TweenService:Create(flash, TweenInfo.new(0.18), {
		Transparency = 1,
		Size = Vector3.new(radiusStuds * 2, radiusStuds * 2, radiusStuds * 2),
	})
	tween:Play()
	Debris:AddItem(flash, 0.22)
end

ProjectileFX.OnClientEvent:Connect(function(action: string, id: number, a: any, b: any, c: any, d: any, e: any)
	if action == "Spawn" then
		local position = a :: Vector3
		local velocity = b :: Vector3
		local style = c
		if typeof(position) ~= "Vector3" or typeof(velocity) ~= "Vector3" or type(style) ~= "table" then
			return
		end
		local caliberMm = if type(style.caliberMm) == "number" then style.caliberMm else 20
		local tracer = createEffectPart(position, style.color or Color3.new(1, 0.8, 0.3), math.clamp(caliberMm / 500, 0.045, 0.16))
		tracers[id] = {
			part = tracer,
			position = position,
			velocity = velocity,
			age = 0,
		}
	elseif action == "Impact" then
		local position = a :: Vector3
		local normal = b :: Vector3
		local kind = c
		local color = e
		if typeof(position) == "Vector3" and typeof(normal) == "Vector3" and type(kind) == "string" and typeof(color) == "Color3" then
			impactEffect(position, normal, kind, color)
		end
	elseif action == "Explosion" then
		local position = a :: Vector3
		local radius = b
		local color = c
		if typeof(position) == "Vector3" and type(radius) == "number" and typeof(color) == "Color3" then
			explosionEffect(position, radius, color)
		end
	elseif action == "Stop" then
		local tracer = tracers[id]
		if tracer then
			tracer.part:Destroy()
			tracers[id] = nil
		end
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	for id, tracer in pairs(tracers) do
		tracer.age += deltaTime
		if tracer.age > 10 or not tracer.part.Parent then
			if tracer.part.Parent then
				tracer.part:Destroy()
			end
			tracers[id] = nil
		else
			tracer.velocity += Vector3.new(0, -workspace.Gravity, 0) * deltaTime
			tracer.position += tracer.velocity * deltaTime
			tracer.part.Position = tracer.position
		end
	end
end)

--!strict
--[[
	InventoryController — commandes d'objets du joueur local (priorité 36, après ActionController).

	  Clavier : 1..4 choisissent une case, E utilise l'objet choisi.
	  Manette : L1 / R1 case précédente / suivante, R2 utilise.
	  Objets « à maintenir » (Items.holdToUse : lance-fusées, lance-rail) : appuyer = Items.UseStart,
	  relâcher = Items.Use ; une annulation (KO, case changée) envoie Items.UseCancel.
	Le client n'envoie que des intentions (case, visée = regard de la caméra) : phase, RoundId, délais, cible,
	ligne de vue et effet sont décidés par ItemService. Retours : Items.Gained / Items.Feedback / Items.Warning /
	Items.LockState (messages, repère de verrouillage) ; l'éblouissement (attribut Dazzled du personnage)
	pose un voile clair, atténué en mode « sans flash ».

	API : GetSelected() -> (slot, itemId?) ; IsHolding() -> boolean
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)
local Items = require(Shared.Config.Items)

local InputController = require(script.Parent.InputController)

local InventoryController = {}
InventoryController.Priority = 36

local localPlayer = Players.LocalPlayer
local MAX_SLOTS = 4
local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local runtimeTrove = Trove.new()
local holding: number? = nil
local lockedUserId = 0
local overlay: Frame? = nil

--------------------------------------------------------------------------------
-- Lectures
--------------------------------------------------------------------------------

local optionalCache: { [string]: any } = {}

local function optionalController(name: string): any
	local cached = optionalCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local module = script.Parent:FindFirstChild(name)
	local result: any = false
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			result = loaded
		end
	end
	optionalCache[name] = result
	return result or nil
end

local function toast(text: string, kind: string?)
	local hud = optionalController("HUDController")
	if hud and type(hud.ShowToast) == "function" then
		pcall(hud.ShowToast, text, kind)
	end
end

local function roundId(): number
	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		local value = (folder :: Folder):GetAttribute("RoundId")
		if type(value) == "number" and value == value then
			return math.floor(value)
		end
	end
	return 0
end

local function inventoryIds(): { string }
	local raw = localPlayer:GetAttribute("Inventory")
	local ids: { string } = {}
	if type(raw) == "string" and raw ~= "" then
		for part in string.gmatch(raw .. ",", "([^,]*),") do
			table.insert(ids, part)
		end
	end
	return ids
end

local function capacity(): number
	local value = localPlayer:GetAttribute("InventoryCapacity")
	return if type(value) == "number" then math.clamp(math.floor(value), 0, MAX_SLOTS) else 0
end

local function selectedSlot(): number
	local value = localPlayer:GetAttribute("SelectedSlot")
	return if type(value) == "number" then math.floor(value) else 1
end

local function canAct(): boolean
	return localPlayer:GetAttribute("KnockedOut") ~= true
		and localPlayer:GetAttribute("Spectating") ~= true
		and localPlayer:GetAttribute("HoleFinished") ~= true
end

local function aimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.CFrame.LookVector
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
end

function InventoryController.GetSelected(): (number, string?)
	local slot = selectedSlot()
	local id = inventoryIds()[slot]
	return slot, if id and id ~= "" then id else nil
end

function InventoryController.IsHolding(): boolean
	return holding ~= nil
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function selectSlot(slot: number)
	if slot < 1 or slot > capacity() then
		return
	end
	if holding and holding ~= slot then
		Net.send("Items.UseCancel", roundId(), holding)
		holding = nil
	end
	Net.send("Items.Select", slot)
end

local function cycle(step: number)
	local cap = capacity()
	if cap <= 0 then
		return
	end
	local slot = selectedSlot()
	for _ = 1, cap do
		slot = ((slot - 1 + step) % cap) + 1
		local id = inventoryIds()[slot]
		if id and id ~= "" then
			break
		end
	end
	selectSlot(slot)
end

local function useBegin()
	if not canAct() then
		return
	end
	local slot, id = InventoryController.GetSelected()
	if not id then
		toast(Locale.t("item.fb.empty"), "info")
		return
	end
	local def = Items.get(id)
	if def and def.holdToUse then
		holding = slot
		Net.send("Items.UseStart", roundId(), slot)
	else
		Net.send("Items.Use", roundId(), slot, aimDirection(), nil)
	end
end

local function useEnd()
	local slot = holding
	if not slot then
		return
	end
	holding = nil
	local target = if lockedUserId ~= 0 then lockedUserId else nil
	Net.send("Items.Use", roundId(), slot, aimDirection(), target)
end

local function cancelHold()
	local slot = holding
	if slot then
		holding = nil
		lockedUserId = 0
		Net.send("Items.UseCancel", roundId(), slot)
	end
end

--------------------------------------------------------------------------------
-- Retours serveur
--------------------------------------------------------------------------------

local function localizedOr(key: string, fallbackKey: string, vars: { [string]: any }?): string
	if Locale.has(key) or Locale.has(key, "fr") then
		return Locale.t(key, vars)
	end
	return Locale.t(fallbackKey, vars)
end

local function onFeedback(key: any, vars: any)
	if type(key) ~= "string" then
		return
	end
	toast(localizedOr(key, "item.fb.state", if type(vars) == "table" then vars else nil), "warn")
end

local function onGained(itemId: any, _slot: any)
	if type(itemId) ~= "string" then
		return
	end
	local def = Items.get(itemId)
	local name = if def then Locale.t(def.nameKey) else itemId
	toast(Locale.t("item.gained", { name = name }), "info")
end

local function onWarning(itemId: any, _attackerUserId: any)
	local key = if type(itemId) == "string" then "item.warn." .. itemId else "item.warn.default"
	toast(localizedOr(key, "item.warn.default", nil), "warn")
end

local function onLockState(targetUserId: any)
	lockedUserId = if type(targetUserId) == "number" then targetUserId else 0
end

--------------------------------------------------------------------------------
-- Voile d'éblouissement
--------------------------------------------------------------------------------

local function ensureOverlay(): Frame?
	if overlay and overlay.Parent then
		return overlay
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "EblouissementObjets"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Name = "Voile"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = gui
	overlay = frame
	runtimeTrove:Add(gui)
	return frame
end

local function refreshDazzle()
	local character = localPlayer.Character
	local dazzled = character ~= nil and character:GetAttribute("Dazzled") == true
	local frame = ensureOverlay()
	if not frame then
		return
	end
	local noFlash = false
	local settings = optionalController("SettingsController")
	if settings and type(settings.Get) == "function" then
		local ok, value = pcall(settings.Get, "noFlash")
		noFlash = ok and value == true
	end
	if dazzled then
		frame.BackgroundColor3 = if noFlash then Color3.fromRGB(120, 120, 130) else Color3.new(1, 1, 1)
		frame.BackgroundTransparency = if noFlash then 0.55 else 0.1
	else
		frame.BackgroundTransparency = 1
	end
end

local function watchCharacter(character: Model?)
	if not character then
		return
	end
	runtimeTrove:Connect(character:GetAttributeChangedSignal("Dazzled"), refreshDazzle)
	refreshDazzle()
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function InventoryController.Init()
	for index = 1, MAX_SLOTS do
		local action = "GC_ItemSlot" .. index
		InputController.Bind(action, function(inputState: Enum.UserInputState): boolean?
			if inputState ~= Enum.UserInputState.Begin or capacity() < index then
				return false
			end
			selectSlot(index)
			return true
		end, NUMBER_KEYS[index])
		runtimeTrove:Add(function()
			InputController.Unbind(action)
		end)
	end
	InputController.Bind("GC_ItemUse", function(inputState: Enum.UserInputState): boolean?
		if inputState == Enum.UserInputState.Begin then
			useBegin()
			return true
		elseif inputState == Enum.UserInputState.End then
			useEnd()
			return true
		end
		return false
	end, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
	InputController.Bind("GC_ItemPrev", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		cycle(-1)
		return true
	end, Enum.KeyCode.ButtonL1)
	InputController.Bind("GC_ItemNext", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		cycle(1)
		return true
	end, Enum.KeyCode.ButtonR1)
	runtimeTrove:Add(function()
		InputController.Unbind("GC_ItemUse")
		InputController.Unbind("GC_ItemPrev")
		InputController.Unbind("GC_ItemNext")
	end)

	runtimeTrove:Add(Net.listen("Items.Feedback", onFeedback))
	runtimeTrove:Add(Net.listen("Items.Gained", onGained))
	runtimeTrove:Add(Net.listen("Items.Warning", onWarning))
	runtimeTrove:Add(Net.listen("Items.LockState", onLockState))
end

function InventoryController.Start()
	-- Un KO ou la perte de l'objet interrompt une utilisation maintenue.
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("KnockedOut"), function()
		if localPlayer:GetAttribute("KnockedOut") == true then
			cancelHold()
		end
	end)
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("Inventory"), function()
		local slot = holding
		if slot then
			local id = inventoryIds()[slot]
			if not id or id == "" then
				holding = nil
				lockedUserId = 0
			end
		end
	end)
	runtimeTrove:Connect(localPlayer.CharacterAdded, function(character: Model)
		watchCharacter(character)
	end)
	watchCharacter(localPlayer.Character)
	Log.info("Inventory", "commandes d'objets prêtes")
end

return InventoryController

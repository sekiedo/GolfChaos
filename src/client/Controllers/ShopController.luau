--!strict
--[[
	ShopController — ouvre la Boutique (écran Shop) et annonce le résultat des actions de boutique.

	  ShopController.Open(slot?) / Close() / Toggle()      slot = onglet à ouvrir ("Head", "Club"...)

	Chaque réponse du serveur (Shop.Result : buy, equip, variant, saveLoadout, useLoadout) devient un toast :
	succès « shop.result.<action> », refus = la clé d'erreur renvoyée par CosmeticService (shop.err.*).
	Les contrôleurs Personnaliser et Défis passent par ces toasts : ils n'en créent pas d'autres.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Cosmetics = require(Shared.Cosmetics)

local UI = script.Parent.Parent:WaitForChild("UI")
local ScreenManager = require(UI.ScreenManager)

local ShopController = {}
ShopController.Priority = 60

local function controller(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

function ShopController.Open(slot: string?)
	ScreenManager.Show("Shop", slot)
end

function ShopController.Close()
	ScreenManager.Hide("Shop")
end

function ShopController.Toggle()
	ScreenManager.Toggle("Shop")
end

local function onResult(action: string, ok: boolean, reasonKey: string?, payload: { [string]: any }?)
	local notifications = controller("NotificationController")
	if not notifications or type(notifications.NotifyKey) ~= "function" then
		return
	end
	if not ok then
		pcall(notifications.NotifyKey, reasonKey or "shop.err.profile", nil, "error")
		return
	end
	local vars: { [string]: any } = {}
	local def = if payload and type(payload.id) == "string" then Cosmetics.get(payload.id) else nil
	if def and Locale.has(def.nameKey) then
		vars.name = Locale.t(def.nameKey)
	end
	if payload and type(payload.index) == "number" then
		vars.n = payload.index
	end
	pcall(notifications.NotifyKey, "shop.result." .. action, vars, "success")
end

function ShopController.Start()
	local profile = controller("ProfileController")
	if profile and profile.ResultReceived then
		profile.ResultReceived:Connect(onResult)
	end
end

return ShopController

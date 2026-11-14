--!strict
--[[
	CustomizeController — ouvre l'écran Personnaliser (équiper, couleurs, ensembles).

	  CustomizeController.Open(slot?) / Close() / Toggle()      slot = onglet à ouvrir ("Outfit", "Emote"...)
]]

local UI = script.Parent.Parent:WaitForChild("UI")
local ScreenManager = require(UI.ScreenManager)

local CustomizeController = {}
CustomizeController.Priority = 61

function CustomizeController.Open(slot: string?)
	ScreenManager.Show("Customize", slot)
end

function CustomizeController.Close()
	ScreenManager.Hide("Customize")
end

function CustomizeController.Toggle()
	ScreenManager.Toggle("Customize")
end

return CustomizeController

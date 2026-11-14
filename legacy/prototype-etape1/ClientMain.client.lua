--[[
	StarterPlayer/StarterPlayerScripts/ClientMain  (LocalScript)
	------------------------------------------------------------
	Point d'entrée client. Les contrôleurs des étapes suivantes (inventaire, FX des pouvoirs,
	roue d'émotes...) s'ajouteront ici.
]]

local controllers = script.Parent:WaitForChild("Controllers")

local AimController = require(controllers:WaitForChild("AimController"))
AimController.Init()

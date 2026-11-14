--[[
	ReplicatedStorage/Shared/Net  (ModuleScript)
	--------------------------------------------
	Point d'accès unique aux RemoteEvents. Le serveur crée le dossier
	ReplicatedStorage/Remotes et tous les remotes au premier require ;
	le client les attend. Rien à créer à la main.

	Client -> Serveur :  AimState(isAiming)   SwingStart()   Shoot(direction, loftDeg, clientPower)
	Serveur -> Client :  AimCancelled(reason) Notify(text, kind)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFINITIONS = {
	AimState = "RemoteEvent",
	SwingStart = "RemoteEvent",
	Shoot = "RemoteEvent",
	AimCancelled = "RemoteEvent",
	Notify = "RemoteEvent",
}

local Net = {}
local folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Net.Get(name)
	assert(DEFINITIONS[name], "Remote inconnu : " .. tostring(name))
	return folder:WaitForChild(name)
end

return Net

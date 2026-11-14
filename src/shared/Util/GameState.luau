--!strict
--[[
	Accès unique au dossier répliqué ReplicatedStorage.GameState (attributs : docs/ARCHITECTURE.md §6).

	  Serveur : GameState.get()  -> Folder (créé s'il n'existe pas ; plusieurs services peuvent l'appeler
	                                 dans n'importe quel ordre, un seul dossier est créé)
	            GameState.set(nom, valeur)
	  Client  : GameState.get()  -> Folder (attend sa réplication, 60 s max)
	            GameState.read(nom) -> any
	            GameState.changed(nom, callback(valeur)) -> RBXScriptConnection
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GameState"
local IS_SERVER = RunService:IsServer() and not RunService:IsClient()

local GameState = {}

local cached: Folder? = nil

function GameState.get(): Folder
	if cached and cached.Parent then
		return cached
	end
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		cached = existing
		return existing
	end
	if IS_SERVER then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		cached = folder
		return folder
	end
	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME, 60)
	if not waited or not waited:IsA("Folder") then
		error("GameState introuvable : le serveur n'a pas démarré MatchService")
	end
	cached = waited
	return waited
end

function GameState.set(name: string, value: any)
	assert(IS_SERVER, "GameState.set est réservé au serveur")
	GameState.get():SetAttribute(name, value)
end

function GameState.read(name: string): any
	return GameState.get():GetAttribute(name)
end

function GameState.changed(name: string, callback: (any) -> ()): RBXScriptConnection
	local folder = GameState.get()
	return folder:GetAttributeChangedSignal(name):Connect(function()
		callback(folder:GetAttribute(name))
	end)
end

return GameState

--!strict
--[[
	CollisionService — groupes de collision (docs/ARCHITECTURE.md §8, priorité 0 : avant tout le reste).

	Groupes (noms : Config/Gameplay.CollisionGroups) :
	  Balls        balles de golf (Part serveur de référence, identique pour tous)
	  Characters   tous les BaseParts des avatars (accessoires, clubs, cosmétiques compris)
	  Vehicles     voiturettes
	  Projectiles  éventuelles pièces physiques de projectiles (les projectiles sont simulés par le serveur)
	  Ghosts       avatars des joueurs ayant terminé le trou (intangibles)
	  Course       géométrie jouable du parcours (sol, murs, ponts, obstacles)
	  Props        décor non bloquant (herbes, fleurs, petits cailloux)
	  Default      groupe Roblox par défaut : Terrain et toute géométrie non assignée (traitée comme le parcours)

	Matrice de collision (✔ = collision physique, · = aucune) :

	               Balls  Characters  Vehicles  Projectiles  Ghosts  Course  Props  Default
	  Balls         (1)       ·          ·           ·          ·       ✔       ·       ✔
	  Characters               (2)       ✔           ·          ·       ✔       ·       ✔
	  Vehicles                           ✔           ·          ·       ✔       ·       ✔
	  Projectiles                                    ·          ·       ✔       ·       ✔
	  Ghosts                                                    ·       ✔       ·       ✔
	  Course                                                            ✔       ✔       ✔
	  Props                                                                     ·       ✔

	  (1) balle–balle : réglage d'hôte « interactions entre balles » (SetBallCollisions), Collision.BallBallDefault.
	  (2) avatar–avatar : Collision.CharactersCollide (bousculade Roblox par défaut).
	  - Une balle ne touche JAMAIS physiquement un avatar : les impacts sont des requêtes spatiales serveur
	    (BallService -> CombatService), le serveur reste seul juge du KO et du recul.
	  - Une voiturette (possédée par son conducteur) ne touche jamais une balle : elle ne peut pas y injecter
	    de vitesse arbitraire.
	  - Un fantôme ne touche que le parcours (Course + Default) : il ne gêne plus personne.
	  - Le décor non bloquant ne bloque rien (il repose seulement sur le sol).

	API :
	  CollisionService.SetBallCollisions(enabled)    CollisionService.GetBallCollisions() -> boolean
	  CollisionService.AssignCharacter(character)    (groupe Characters, ou Ghosts si le joueur est fantôme)
	  CollisionService.SetGhost(player, isGhost)     CollisionService.IsGhost(player) -> boolean
	  CollisionService.AssignPart(part, group)       CollisionService.AssignModel(model, group)
	  CollisionService.GetGroups() -> { [clé]: nom }
	Avec Collision.AutoGhostOnHoleFinished, l'attribut joueur HoleFinished rend aussi le joueur fantôme.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Gameplay)
local Log = require(Shared.Util.Log)
local TroveModule = require(Shared.Util.Trove)

type Trove = TroveModule.Trove

type Rule = { a: string, b: string, collide: boolean }

local CollisionService = {}
CollisionService.Priority = 0

local GROUPS = Config.CollisionGroups
local DEFAULT_GROUP = "Default"

-- Matrice explicite (voir l'en-tête). Toute paire absente reste collidable (comportement Roblox).
local RULES: { Rule } = {
	{ a = GROUPS.Balls, b = GROUPS.Characters, collide = false },
	{ a = GROUPS.Balls, b = GROUPS.Vehicles, collide = false },
	{ a = GROUPS.Balls, b = GROUPS.Projectiles, collide = false },
	{ a = GROUPS.Balls, b = GROUPS.Ghosts, collide = false },
	{ a = GROUPS.Balls, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Balls, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Balls, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Characters, b = GROUPS.Vehicles, collide = true },
	{ a = GROUPS.Characters, b = GROUPS.Projectiles, collide = false },
	{ a = GROUPS.Characters, b = GROUPS.Ghosts, collide = false },
	{ a = GROUPS.Characters, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Characters, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Characters, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Vehicles, b = GROUPS.Vehicles, collide = true },
	{ a = GROUPS.Vehicles, b = GROUPS.Projectiles, collide = false },
	{ a = GROUPS.Vehicles, b = GROUPS.Ghosts, collide = false },
	{ a = GROUPS.Vehicles, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Vehicles, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Vehicles, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Projectiles, b = GROUPS.Projectiles, collide = false },
	{ a = GROUPS.Projectiles, b = GROUPS.Ghosts, collide = false },
	{ a = GROUPS.Projectiles, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Projectiles, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Projectiles, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Ghosts, b = GROUPS.Ghosts, collide = false },
	{ a = GROUPS.Ghosts, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Ghosts, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Ghosts, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Course, b = GROUPS.Course, collide = true },
	{ a = GROUPS.Course, b = GROUPS.Props, collide = true },
	{ a = GROUPS.Course, b = DEFAULT_GROUP, collide = true },

	{ a = GROUPS.Props, b = GROUPS.Props, collide = false },
	{ a = GROUPS.Props, b = DEFAULT_GROUP, collide = true },
}

type GhostState = { explicit: boolean, finished: boolean }

local registered = false
local ballCollisions = Config.Collision.BallBallDefault
local ghostStates: { [Player]: GhostState } = {}
local playerTroves: { [Player]: Trove } = {}
local characterTroves: { [Model]: Trove } = {}

local function isGroupName(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	if name == DEFAULT_GROUP then
		return true
	end
	for _, groupName in GROUPS do
		if groupName == name then
			return true
		end
	end
	return false
end

-- Accepte une clé de Config (ex. "Course") ou un nom de groupe ; retourne le nom de groupe ou nil.
local function resolveGroup(group: string): string?
	local byKey = (GROUPS :: any)[group]
	if type(byKey) == "string" then
		return byKey
	end
	if isGroupName(group) then
		return group
	end
	return nil
end

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function setCollidable(a: string, b: string, collide: boolean)
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(a, b, collide)
	end)
	if not ok then
		Log.warn("Collision", "impossible de régler", a, "/", b, ":", err)
	end
end

local function ensureRegistered()
	if registered then
		return
	end
	registered = true
	for _, name in GROUPS do
		register(name)
	end
	for _, rule in RULES do
		setCollidable(rule.a, rule.b, rule.collide)
	end
	setCollidable(GROUPS.Characters, GROUPS.Characters, Config.Collision.CharactersCollide)
	setCollidable(GROUPS.Balls, GROUPS.Balls, ballCollisions)
end

local function isGhostState(state: GhostState?): boolean
	if not state then
		return false
	end
	return state.explicit or (Config.Collision.AutoGhostOnHoleFinished and state.finished)
end

local function groupForCharacter(character: Model): string
	local player = Players:GetPlayerFromCharacter(character)
	if player and isGhostState(ghostStates[player]) then
		return GROUPS.Ghosts
	end
	return GROUPS.Characters
end

local function applyGroupToModel(model: Instance, groupName: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function CollisionService.GetGroups(): { [string]: string }
	local copy: { [string]: string } = {}
	for key, name in GROUPS do
		copy[key] = name
	end
	return copy
end

function CollisionService.SetBallCollisions(enabled: boolean)
	ballCollisions = enabled == true
	if registered then
		setCollidable(GROUPS.Balls, GROUPS.Balls, ballCollisions)
	end
end

function CollisionService.GetBallCollisions(): boolean
	return ballCollisions
end

function CollisionService.AssignPart(part: BasePart, group: string): boolean
	local groupName = resolveGroup(group)
	if not groupName or typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end
	ensureRegistered()
	part.CollisionGroup = groupName
	return true
end

-- Assigne toutes les pièces d'un modèle (et celles ajoutées ensuite si `follow` est vrai).
-- Retourne la connexion de suivi (à nettoyer par l'appelant) quand follow = true.
function CollisionService.AssignModel(model: Instance, group: string, follow: boolean?): RBXScriptConnection?
	local groupName = resolveGroup(group)
	if not groupName or typeof(model) ~= "Instance" then
		return nil
	end
	ensureRegistered()
	if model:IsA("BasePart") then
		model.CollisionGroup = groupName
	end
	applyGroupToModel(model, groupName)
	if follow then
		return model.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = groupName
			end
		end)
	end
	return nil
end

-- Groupe Characters (ou Ghosts) pour tout le personnage, y compris les pièces ajoutées plus tard
-- (cosmétiques, outils). Fonctionne aussi pour un PNJ (aucun joueur associé).
function CollisionService.AssignCharacter(character: Model)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	ensureRegistered()
	local existing = characterTroves[character]
	if existing then
		existing:Clean()
	end
	local trove = TroveModule.new()
	characterTroves[character] = trove
	trove:Add(function()
		if characterTroves[character] == trove then
			characterTroves[character] = nil
		end
	end)

	applyGroupToModel(character, groupForCharacter(character))
	trove:Connect(character.DescendantAdded, function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupForCharacter(character)
		end
	end)
	trove:Connect(character.AncestryChanged, function()
		if not character:IsDescendantOf(game) then
			trove:Clean()
		end
	end)
	trove:Connect(character.Destroying, function()
		trove:Clean()
	end)
end

local function refreshPlayer(player: Player)
	local character = player.Character
	if character and characterTroves[character] then
		applyGroupToModel(character, groupForCharacter(character))
	elseif character then
		CollisionService.AssignCharacter(character)
	end
end

local function getGhostState(player: Player): GhostState
	local state = ghostStates[player]
	if not state then
		state = { explicit = false, finished = false }
		ghostStates[player] = state
	end
	return state
end

-- Fantôme explicite (spectateur du trou, joueur ayant terminé...). Persiste d'un personnage à l'autre
-- jusqu'à SetGhost(player, false).
function CollisionService.SetGhost(player: Player, isGhost: boolean)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local state = getGhostState(player)
	local before = isGhostState(state)
	state.explicit = isGhost == true
	if isGhostState(state) ~= before then
		refreshPlayer(player)
	end
end

function CollisionService.IsGhost(player: Player): boolean
	return isGhostState(ghostStates[player])
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function setupPlayer(player: Player)
	if playerTroves[player] then
		return
	end
	local trove = TroveModule.new()
	playerTroves[player] = trove
	local state = getGhostState(player)
	state.finished = player:GetAttribute("HoleFinished") == true

	trove:Connect(player.CharacterAdded, function(character: Model)
		CollisionService.AssignCharacter(character)
	end)
	trove:Connect(player:GetAttributeChangedSignal("HoleFinished"), function()
		local before = isGhostState(state)
		state.finished = player:GetAttribute("HoleFinished") == true
		if isGhostState(state) ~= before then
			refreshPlayer(player)
		end
	end)
	if player.Character then
		CollisionService.AssignCharacter(player.Character)
	end
end

function CollisionService.Init()
	ensureRegistered()
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local trove = playerTroves[player]
		if trove then
			trove:Destroy()
			playerTroves[player] = nil
		end
		ghostStates[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

function CollisionService.Start() end

return CollisionService

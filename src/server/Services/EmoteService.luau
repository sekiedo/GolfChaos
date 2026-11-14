--!strict
--[[
	EmoteService — lance et arrête les émotes des personnages (docs/ARCHITECTURE.md §6 et §8, priorité 46).

	  EmoteService.Play(player, emoteId) -> (boolean, string?)   raisons : "unknown" | "notOwned" | "busy" | "cooldown" | "dead"
	  EmoteService.Stop(player)
	  EmoteService.IsPlaying(player) -> string?                  identifiant de l'émote en cours
	  Signaux : Played(player, emoteId), Stopped(player, emoteId)

	Le client n'envoie qu'une INTENTION (remotes Emote.Play / Emote.Stop). Le serveur vérifie :
	  - l'émote existe dans le catalogue (emplacement "Emote") et dispose d'une animation procédurale ;
	  - le joueur la possède (liste équipée ou émote par défaut) ;
	  - le personnage est vivant, hors KO, hors visée, hors véhicule, sans autre animation en cours (AnimState vide) ;
	  - le délai minimal entre deux émotes est respecté.
	Il pose ensuite les attributs de personnage Emote (identifiant) et EmoteStartedAt (heure serveur) : chaque
	client joue la même animation au même instant (AnimationController). Aucun avantage de jeu, aucun délai contourné.

	Fin d'émote : demande du joueur (Emote.Stop, par exemple dès qu'il se déplace), fin d'une animation ponctuelle,
	golf / combat / KO (AnimState non vide), visée, véhicule, mort ou nouvelle apparition. Un nouvel appel à Play
	pendant une émote la remplace (après le délai).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Cosmetics = require(Shared.Cosmetics)
local Animations = require(Shared.Animations)

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Emote")

local EmoteService = {}
EmoteService.Priority = 46
EmoteService.Played = Signal.new()
EmoteService.Stopped = Signal.new()

local COOLDOWN = 0.75 -- s entre deux lancements d'un même joueur
local EXPIRY_MARGIN = 0.1 -- s ajoutées à la durée d'une animation ponctuelle avant d'effacer l'attribut

type Active = { id: string, startedAt: number, character: Model, trove: any }

local active: { [Player]: Active } = {}
local lastPlayAt: { [Player]: number } = {}

local function aliveCharacter(player: Player): Model?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return nil
	end
	return character
end

-- Possédée = gratuite par défaut ou présente dans la liste équipée (l'équipement exige la possession).
local function owns(player: Player, def: Cosmetics.CosmeticDef): boolean
	if def.unlock.kind == "Default" then
		return true
	end
	local ok, equipped = services.call("CosmeticService", "GetEquipped", player)
	if ok and type(equipped) == "table" and type(equipped.Emotes) == "table" then
		return table.find(equipped.Emotes, def.id) ~= nil
	end
	return false
end

local function clearAttributes(character: Model)
	character:SetAttribute("Emote", "")
	character:SetAttribute("EmoteStartedAt", 0)
end

function EmoteService.IsPlaying(player: Player): string?
	local entry = active[player]
	return if entry then entry.id else nil
end

function EmoteService.Stop(player: Player)
	local entry = active[player]
	if not entry then
		return
	end
	active[player] = nil
	entry.trove:Destroy()
	if entry.character.Parent then
		clearAttributes(entry.character)
	end
	EmoteService.Stopped:Fire(player, entry.id)
end

local function canPlay(player: Player, character: Model): (boolean, string?)
	for _, name in { "KnockedOut", "Aiming", "InVehicle", "Spectating" } do
		if player:GetAttribute(name) == true then
			return false, "busy"
		end
	end
	local state = character:GetAttribute("AnimState")
	if type(state) == "string" and state ~= "" then
		return false, "busy"
	end
	return true, nil
end

function EmoteService.Play(player: Player, emoteId: string): (boolean, string?)
	if type(emoteId) ~= "string" then
		return false, "unknown"
	end
	local def = Cosmetics.get(emoteId)
	if not def or def.slot ~= "Emote" or type(def.emote) ~= "string" then
		return false, "unknown"
	end
	local animation = Animations.get(def.emote)
	if not animation then
		Log.warn("Emote", "animation absente pour", emoteId)
		return false, "unknown"
	end
	local character = aliveCharacter(player)
	if not character then
		return false, "dead"
	end
	local clock = os.clock()
	local previous = lastPlayAt[player]
	if previous and clock - previous < COOLDOWN then
		return false, "cooldown"
	end
	local free, reason = canPlay(player, character)
	if not free then
		return false, reason
	end
	if not owns(player, def) then
		return false, "notOwned"
	end

	EmoteService.Stop(player)
	lastPlayAt[player] = clock

	local trove = Trove.new()
	local startedAt = Workspace:GetServerTimeNow()
	local entry: Active = { id = emoteId, startedAt = startedAt, character = character, trove = trove }
	active[player] = entry

	-- Tout état concurrent interrompt l'émote (golf, combat, KO, visée, véhicule, mort).
	trove:Connect(character:GetAttributeChangedSignal("AnimState"), function()
		local state = character:GetAttribute("AnimState")
		if type(state) == "string" and state ~= "" then
			EmoteService.Stop(player)
		end
	end)
	for _, name in { "KnockedOut", "Aiming", "InVehicle", "Spectating" } do
		trove:Connect(player:GetAttributeChangedSignal(name), function()
			if player:GetAttribute(name) == true then
				EmoteService.Stop(player)
			end
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		trove:Connect(humanoid.Died, function()
			EmoteService.Stop(player)
		end)
	end
	trove:Connect(character.AncestryChanged, function()
		if not character.Parent then
			EmoteService.Stop(player)
		end
	end)

	-- Animation ponctuelle : l'attribut est effacé à sa fin (sauf si une autre émote l'a remplacée entre-temps).
	if not animation.looped then
		task.delay(animation.duration + animation.blendOut + EXPIRY_MARGIN, function()
			if active[player] == entry then
				EmoteService.Stop(player)
			end
		end)
	end

	character:SetAttribute("EmoteStartedAt", startedAt)
	character:SetAttribute("Emote", emoteId)
	EmoteService.Played:Fire(player, emoteId)
	return true, nil
end

function EmoteService.Init()
	Net.on("Emote.Play", function(player: Player, emoteId: string)
		local ok, reason = EmoteService.Play(player, emoteId)
		if not ok then
			Log.debug("Emote", player.Name, "refusé :", reason)
		end
	end)
	Net.on("Emote.Stop", function(player: Player)
		EmoteService.Stop(player)
	end)
end

function EmoteService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		EmoteService.Stop(player)
		lastPlayAt[player] = nil
	end)
	-- Une nouvelle apparition repart sans émote.
	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			EmoteService.Stop(player)
			clearAttributes(character)
		end)
	end
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
end

return EmoteService

--!strict
--[[
	AnimationController — joue les animations PROCÉDURALES de tous les personnages (docs/ARCHITECTURE.md §6 et §8,
	priorité 70). Aucune animation uploadée : chaque animation est une fonction joints(t) (shared/Animations)
	qui renvoie un décalage CFrame par articulation R15.

	  AnimationController.PlayEmote(emoteId)    intention envoyée au serveur (remote Emote.Play)
	  AnimationController.StopEmote()           intention d'arrêt (remote Emote.Stop)
	  AnimationController.GetCurrent(character) -> string?   identifiant de l'animation dominante (tests / HUD)

	Sources lues, toutes répliquées par le serveur (jamais d'état local décisif) :
	  - attributs du personnage AnimState / ShotType (golf, combat, KO) -> Animations.forState ;
	  - attributs Emote / EmoteStartedAt (EmoteService) -> animation de l'émote ; le temps part de l'heure
	    serveur : tous les clients voient la même danse au même instant.
	AnimState l'emporte sur l'émote. À la fin d'un KO, la transition (Animations.transitionFrom) se joue.

	Application : pendant RunService.PreSimulation (après l'Animator), joint.Transform = décalage * base, où
	« base » est la valeur écrite par l'Animator. Si l'Animator n'a pas touché l'articulation, la base mémorisée
	est réutilisée : le décalage ne s'accumule donc jamais d'une image à l'autre.

	Mélange : une couche par animation (fondu d'entrée / de sortie), triées par priorité croissante ; une couche
	écrase la précédente joint par joint, au prorata de son poids. Mode « effets réduits » : amplitude `calm`,
	pas de particules (fx) ; les personnages loin de la caméra ne sont pas animés.

	Reste à faire (non implémenté) : réorientation du manche de club (champ `club` des animations de golf).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Trove = require(Shared.Util.Trove)
local Cosmetics = require(Shared.Cosmetics)
local Animations = require(Shared.Animations)

local AnimationController = {}
AnimationController.Priority = 70

local MAX_DISTANCE = 220 -- studs : au-delà, le personnage n'est pas animé
local MAX_LAYERS = 3
local STOP_GRACE = 0.35 -- s avant qu'un déplacement du joueur local n'arrête son émote
local MOVE_THRESHOLD = 0.1

type AnimationDef = Animations.AnimationDef

type Layer = {
	id: string,
	def: AnimationDef,
	start: number, -- heure serveur du début
	outAt: number?, -- heure serveur du début du fondu de sortie
}

type Rig = {
	character: Model,
	trove: any, -- Util.Trove (typé any : le type générique exporté par Trove n'est pas égal à lui-même pour l'analyseur)
	joints: { [string]: Motor6D },
	layers: { Layer },
	written: { [string]: CFrame }, -- dernière valeur écrite par nous
	base: { [string]: CFrame }, -- valeur de l'Animator sans notre décalage
	dirty: boolean, -- des Transform modifiés par nous restent à restaurer
	prevState: string,
	stateStart: number,
	transition: { id: string, start: number }?,
	fx: { Instance },
	stopSent: boolean,
}

local rigs: { [Model]: Rig } = {}
local localPlayer = Players.LocalPlayer

-- Utilitaires -------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- EffectsController est chargé à la demande (aucun cycle de require, et son absence est tolérée).
local function effects(): any?
	local sibling = script.Parent:FindFirstChild("EffectsController")
	if not sibling then
		return nil
	end
	local ok, module = pcall(require, sibling)
	if ok and type(module) == "table" then
		return module
	end
	return nil
end

local function isReduced(): boolean
	local module = effects()
	return module ~= nil and type(module.IsReduced) == "function" and module.IsReduced() == true
end

local function playSound(name: string, parent: Instance?)
	local module = effects()
	if module and type(module.PlaySound) == "function" then
		module.PlaySound(name, { parent = parent, maxDuration = 4 })
	end
end

local function collectJoints(character: Model): { [string]: Motor6D }
	local known: { [string]: boolean } = {}
	for _, name in Animations.JOINTS do
		known[name] = true
	end
	local joints: { [string]: Motor6D } = {}
	for _, item in character:GetDescendants() do
		if item:IsA("Motor6D") and known[item.Name] and not joints[item.Name] then
			joints[item.Name] = item
		end
	end
	return joints
end

-- Animation voulue (identifiant, heure de départ) d'après les attributs répliqués.
local function wanted(rig: Rig): (string?, number)
	local character = rig.character
	local state = character:GetAttribute("AnimState")
	if type(state) == "string" and state ~= "" then
		local shotType = character:GetAttribute("ShotType")
		local id = Animations.forState(state, if type(shotType) == "string" then shotType else nil)
		if id and Animations.get(id) then
			return id, rig.stateStart
		end
	end
	local transition = rig.transition
	if transition then
		local def = Animations.get(transition.id)
		if def and serverNow() - transition.start < def.duration + def.blendOut then
			return transition.id, transition.start
		end
		rig.transition = nil
	end
	local emote = character:GetAttribute("Emote")
	if type(emote) == "string" and emote ~= "" then
		local cosmetic = Cosmetics.get(emote)
		local animationId = if cosmetic and cosmetic.emote then cosmetic.emote else emote
		if Animations.get(animationId) then
			local startedAt = character:GetAttribute("EmoteStartedAt")
			return animationId, if type(startedAt) == "number" and startedAt > 0 then startedAt else serverNow()
		end
	end
	return nil, 0
end

local function destroyFx(rig: Rig)
	for _, instance in rig.fx do
		if instance.Parent then
			instance:Destroy()
		end
	end
	table.clear(rig.fx)
end

local function startFx(rig: Rig, def: AnimationDef)
	destroyFx(rig)
	if def.fx and not isReduced() then
		local ok, created = pcall(def.fx, rig.character)
		if ok and type(created) == "table" then
			rig.fx = created
		elseif not ok then
			Log.warn("Animation", "fx", def.id, ":", created)
		end
	end
	if def.tags and table.find(def.tags, "music") then
		playSound("emote_party", rig.character:FindFirstChild("Head"))
	end
end

-- Recalcule la couche dominante quand un attribut change.
local function refresh(rig: Rig)
	local id, start = wanted(rig)
	local now = serverNow()
	local top = rig.layers[#rig.layers]
	local topLive = if top and not top.outAt then top else nil

	if topLive and topLive.id == id and math.abs(topLive.start - start) < 1e-3 then
		return
	end
	if topLive then
		topLive.outAt = now
	end
	if id then
		local def = Animations.get(id)
		if def then
			table.insert(rig.layers, { id = id, def = def, start = start, outAt = nil })
			while #rig.layers > MAX_LAYERS do
				table.remove(rig.layers, 1)
			end
			startFx(rig, def)
			rig.stopSent = false
			return
		end
	end
	destroyFx(rig)
end

-- Heure à laquelle commence le fondu de sortie (nil = la couche est maintenue).
local function outTime(layer: Layer): number?
	if layer.outAt then
		return layer.outAt
	end
	local def = layer.def
	if not def.looped and not def.hold then
		return layer.start + def.duration -- fin naturelle d'une animation ponctuelle
	end
	return nil
end

-- Poids d'une couche à l'instant `now` (0 = à retirer).
local function weightOf(layer: Layer, now: number): number
	local def = layer.def
	local weight = 1
	if def.blendIn > 0 then
		weight = math.clamp((now - layer.start) / def.blendIn, 0, 1)
	end
	local outAt = outTime(layer)
	if outAt and now >= outAt then
		if def.blendOut <= 0 then
			return 0
		end
		weight *= math.clamp(1 - (now - outAt) / def.blendOut, 0, 1)
	end
	return weight
end

local function isFinished(layer: Layer, now: number): boolean
	local outAt = outTime(layer)
	if not outAt or now < outAt then
		return false
	end
	return weightOf(layer, now) <= 0
end

local function timeOf(layer: Layer, now: number): number
	local def = layer.def
	local age = math.max(now - layer.start, 0)
	if def.looped then
		return age % def.duration
	end
	return math.min(age, def.duration)
end

local function restore(rig: Rig)
	if not rig.dirty then
		return
	end
	for name, joint in rig.joints do
		local base = rig.base[name]
		if base and joint.Parent and joint.Transform == rig.written[name] then
			joint.Transform = base
		end
	end
	table.clear(rig.written)
	table.clear(rig.base)
	rig.dirty = false
end

type Sample = { pose: { [string]: CFrame }, weight: number, calm: number }

local function apply(rig: Rig, now: number, reduced: boolean)
	for index = #rig.layers, 1, -1 do
		if isFinished(rig.layers[index], now) then
			table.remove(rig.layers, index)
		end
	end
	if #rig.layers == 0 then
		restore(rig)
		return
	end

	-- Poses échantillonnées une seule fois par couche, triées par priorité croissante.
	local ordered = table.clone(rig.layers)
	table.sort(ordered, function(a, b)
		if a.def.priority ~= b.def.priority then
			return a.def.priority < b.def.priority
		end
		return a.start < b.start
	end)
	local samples: { Sample } = {}
	for _, layer in ordered do
		local weight = weightOf(layer, now)
		if weight > 0 then
			local ok, pose = pcall(layer.def.joints, timeOf(layer, now))
			if ok and type(pose) == "table" then
				table.insert(samples, {
					pose = pose,
					weight = weight,
					calm = if reduced then (layer.def.calm or 1) else 1,
				})
			end
		end
	end

	for name, joint in rig.joints do
		local offset = CFrame.identity
		local touched = false
		for _, sample in samples do
			local cf = sample.pose[name]
			if cf then
				if sample.calm < 1 then
					cf = Animations.Kit.scale(cf, sample.calm)
				end
				offset = offset:Lerp(cf, sample.weight)
				touched = true
			end
		end
		if touched then
			local current = joint.Transform
			local base = if current ~= rig.written[name] then current else (rig.base[name] or current)
			rig.base[name] = base
			local result = offset * base
			rig.written[name] = result
			joint.Transform = result
			rig.dirty = true
		end
	end
end

-- Le joueur local interrompt son émote dès qu'il se déplace (le serveur reste maître de l'arrêt).
local function watchLocalMovement(rig: Rig, now: number)
	if rig.stopSent then
		return
	end
	local emote = rig.character:GetAttribute("Emote")
	if type(emote) ~= "string" or emote == "" then
		return
	end
	local startedAt = rig.character:GetAttribute("EmoteStartedAt")
	if type(startedAt) ~= "number" or now - startedAt < STOP_GRACE then
		return
	end
	local humanoid = rig.character:FindFirstChildOfClass("Humanoid")
	if humanoid and (humanoid.MoveDirection.Magnitude > MOVE_THRESHOLD or humanoid.Jump) then
		rig.stopSent = true
		task.spawn(function()
			Net.send("Emote.Stop")
		end)
	end
end

-- Cycle de vie des personnages -----------------------------------------------------

local function release(character: Model)
	local rig = rigs[character]
	if not rig then
		return
	end
	rigs[character] = nil
	restore(rig)
	destroyFx(rig)
	rig.trove:Destroy()
end

local function track(character: Model)
	if rigs[character] then
		return
	end
	local rig: Rig = {
		character = character,
		trove = Trove.new(),
		joints = collectJoints(character),
		layers = {},
		written = {},
		base = {},
		dirty = false,
		prevState = "",
		stateStart = serverNow(),
		transition = nil,
		fx = {},
		stopSent = false,
	}
	rigs[character] = rig

	local function onState()
		local state = character:GetAttribute("AnimState")
		local value = if type(state) == "string" then state else ""
		if value ~= rig.prevState then
			local transitionId = if value == "" then Animations.transitionFrom(rig.prevState) else nil
			rig.transition = if transitionId then { id = transitionId, start = serverNow() } else nil
			rig.prevState = value
			rig.stateStart = serverNow()
		end
		refresh(rig)
	end

	for _, name in { "AnimState", "ShotType" } do
		rig.trove:Connect(character:GetAttributeChangedSignal(name), onState)
	end
	for _, name in { "Emote", "EmoteStartedAt" } do
		rig.trove:Connect(character:GetAttributeChangedSignal(name), function()
			refresh(rig)
		end)
	end
	-- Les articulations peuvent arriver après le personnage (réplication) ou être recréées.
	rig.trove:Connect(character.DescendantAdded, function(item: Instance)
		if item:IsA("Motor6D") then
			if not rig.joints[item.Name] and table.find(Animations.JOINTS, item.Name) then
				rig.joints[item.Name] = item
			end
		end
	end)
	rig.trove:Connect(character.AncestryChanged, function()
		if not character:IsDescendantOf(Workspace) then
			release(character)
		end
	end)

	onState()
end

local function watchPlayer(player: Player)
	local function onCharacter(character: Model)
		-- Attend le rig (Humanoid) avant de collecter les articulations.
		task.spawn(function()
			character:WaitForChild("Humanoid", 10)
			if character.Parent then
				track(character)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(release)
	if player.Character then
		onCharacter(player.Character)
	end
end

-- API ---------------------------------------------------------------------------------

function AnimationController.PlayEmote(emoteId: string)
	if type(emoteId) ~= "string" or emoteId == "" then
		return
	end
	task.spawn(function()
		Net.send("Emote.Play", emoteId)
	end)
end

function AnimationController.StopEmote()
	task.spawn(function()
		Net.send("Emote.Stop")
	end)
end

function AnimationController.GetCurrent(character: Model): string?
	local rig = rigs[character]
	if not rig then
		return nil
	end
	local top = rig.layers[#rig.layers]
	return if top and not top.outAt then top.id else nil
end

function AnimationController.Init()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

function AnimationController.Start()
	RunService.PreSimulation:Connect(function()
		local now = serverNow()
		local camera = Workspace.CurrentCamera
		local reduced = isReduced()
		for character, rig in rigs do
			local root = character:FindFirstChild("HumanoidRootPart")
			local near = true
			if camera and root and root:IsA("BasePart") then
				near = (root.Position - camera.CFrame.Position).Magnitude <= MAX_DISTANCE
			end
			if near then
				apply(rig, now, reduced)
			else
				restore(rig)
			end
			if localPlayer and character == localPlayer.Character then
				watchLocalMovement(rig, now)
			end
		end
	end)
end

return AnimationController

--!strict
--[[
	ItemService — inventaire, boîtes d'objets, utilisation validée et effets des 17 objets
	(docs/REGISTRE_OBJETS.md, docs/ARCHITECTURE.md §10, priorité 44).

	INTENTIONS CLIENT (Net/Remotes/Items) : Items.Select(case), Items.Use(roundId, case, visée, cibleSuggérée?),
	Items.UseStart(roundId, case) / Items.UseCancel(roundId, case) pour les objets « maintenir ». Le serveur
	revalide tout : objets activés, manche et phase « Playing », participant actif, vivant, ni KO ni gelé ni
	terminé, objet présent dans la case, délai global et par objet, visée finie. Il décide seul de l'effet.

	ATTRIBUTS JOUEUR (lus par le HUD) : Inventory ("horn,,espresso"), SelectedSlot, InventoryCapacity.
	ATTRIBUTS PERSONNAGE posés par les objets : Frozen, Dazzled, Giant, Invisible, Shielded.

	COMPORTEMENTS : un ModuleScript par objet dans Server/Items (contrat de docs/ARCHITECTURE.md §10) :
	  { Id, Use(ctx, player, payload) -> (boolean, feedbackKey?), UseStart?(ctx, player, hold) -> boolean?,
	    UseCancel?(ctx, player, hold) }.   Use ne doit pas attendre longtemps : les annonces et les durées passent par
	ctx.after(trove, secondes, fn). Retourner true consomme une charge ; false n'en consomme aucune.
	payload = { slot, aim (unitaire), target (Player?), held (s), hold (table partagée avec UseStart) }.

	API
	  Grant(player, itemId) -> (boolean, slot?)    GrantRandom(player, boxKind?) -> itemId?    Remove(player, slot)
	  GetInventory(player) -> { string }           HasItem(player, itemId) -> boolean
	  HasEffect(player, effectId) -> boolean       (frozen, dazzled, giant, invisible, shield...)
	  AddEffect(player, nom, secondes, onEnd?) / ClearEffect(player, nom) / ClearEffects(player)
	  ClearRound()                                  appelé par MatchService en fin de manche
	  Signaux : ItemUsed(player, itemId), ItemGained(player, itemId, slot), EffectStarted / EffectEnded(player, nom)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ItemBoxes = require(Shared.Config.ItemBoxes)
local Items = require(Shared.Config.Items)
local Inventory = require(Shared.Logic.Inventory)
local ItemOdds = require(Shared.Logic.ItemOdds)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)

local Services = require(script.Parent.Parent.Util.Services)

type Trove = TroveModule.Trove
type Signal = SignalModule.Signal

local LOG_TAG = "Items"
local services = Services.scope(LOG_TAG)

local ItemService = {}
ItemService.Priority = 44
ItemService.ItemUsed = SignalModule.new() :: Signal -- (player, itemId)
ItemService.ItemGained = SignalModule.new() :: Signal -- (player, itemId, slot)
ItemService.EffectStarted = SignalModule.new() :: Signal -- (player, name)
ItemService.EffectEnded = SignalModule.new() :: Signal -- (player, name)

type Effect = { token: number, endsAt: number, onEnd: (() -> ())? }
type Hold = { slot: number, itemId: string, startedAt: number, data: { [string]: any } }
type PState = {
	inv: Inventory.Inv,
	trove: Trove,
	effects: { [string]: Effect },
	shieldCharges: number,
	lastUse: number,
	cooldowns: { [number]: number },
	charges: { [number]: number },
	hold: Hold?,
	mines: number,
}

type Box = { part: Part, kind: string, readyAt: number, home: Vector3 }

local states: { [Player]: PState } = {}
local registry: { [string]: any } = {}
local roundTrove: Trove = TroveModule.new()
local boxTrove: Trove = TroveModule.new()
local boxes: { Box } = {}
local rng = Random.new()
local effectToken = 0
local ctx: any = {}

local FEEDBACK = {
	disabled = "item.fb.disabled",
	phase = "item.fb.phase",
	empty = "item.fb.empty",
	cooldown = "item.fb.cooldown",
	state = "item.fb.state",
	full = "item.fb.full",
}

local function now(): number
	return os.clock()
end

local function isFiniteVector(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

--------------------------------------------------------------------------------
-- État par joueur
--------------------------------------------------------------------------------

local function getState(player: Player): PState
	local existing = states[player]
	if existing then
		return existing
	end
	local state: PState = {
		inv = Inventory.new(Items.InventoryCapacity),
		trove = TroveModule.new(),
		effects = {},
		shieldCharges = 0,
		lastUse = 0,
		cooldowns = {},
		charges = {},
		hold = nil,
		mines = 0,
	}
	states[player] = state
	return state
end

local function publish(player: Player)
	local state = states[player]
	if not state then
		return
	end
	player:SetAttribute("Inventory", Inventory.serialize(state.inv))
	player:SetAttribute("SelectedSlot", state.inv.selected)
	player:SetAttribute("InventoryCapacity", state.inv.capacity)
end

local function feedback(player: Player, key: string, vars: { [string]: any }?)
	pcall(Net.fire, "Items.Feedback", player, key, vars)
end

local function matchService(): any
	return services.get("MatchService")
end

local function matchSetting(key: string): any
	local match = matchService()
	if match and type(match.GetSettings) == "function" then
		local ok, settings = pcall(match.GetSettings)
		if ok and type(settings) == "table" then
			return (settings :: any)[key]
		end
	end
	return nil
end

local function itemsEnabled(): boolean
	return matchSetting("itemsEnabled") ~= false
end

local function itemFrequency(): string
	local value = matchSetting("itemFrequency")
	return if type(value) == "string" then value else "Normal"
end

--------------------------------------------------------------------------------
-- Effets (états temporaires sur un joueur)
--------------------------------------------------------------------------------

local function endEffect(player: Player, name: string)
	local state = states[player]
	if not state then
		return
	end
	local effect = state.effects[name]
	if not effect then
		return
	end
	state.effects[name] = nil
	if effect.onEnd then
		local ok, err = pcall(effect.onEnd)
		if not ok then
			Log.warn(LOG_TAG, "fin d'effet en erreur :", name, err)
		end
	end
	ItemService.EffectEnded:Fire(player, name)
end

function ItemService.AddEffect(player: Player, name: string, seconds: number, onEnd: (() -> ())?)
	local state = getState(player)
	local existing = state.effects[name]
	effectToken += 1
	local effect: Effect = {
		token = effectToken,
		endsAt = now() + seconds,
		onEnd = onEnd or (if existing then existing.onEnd else nil),
	}
	state.effects[name] = effect
	if not existing then
		ItemService.EffectStarted:Fire(player, name)
	end
	task.delay(seconds, function()
		if states[player] == state and state.effects[name] == effect then
			endEffect(player, name)
		end
	end)
end

function ItemService.ClearEffect(player: Player, name: string)
	endEffect(player, name)
end

function ItemService.ClearEffects(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local names: { string } = {}
	for name in state.effects do
		table.insert(names, name)
	end
	for _, name in names do
		endEffect(player, name)
	end
end

function ItemService.HasEffect(player: Player, effectId: string): boolean
	local state = states[player]
	if not state then
		return false
	end
	local effect = state.effects[effectId]
	return effect ~= nil and effect.endsAt > now()
end

-- Bouclier : charges absorbées par CombatService (voir le gestionnaire plus bas).
local function consumeShield(player: Player): boolean
	local state = states[player]
	if not state or state.shieldCharges <= 0 then
		return false
	end
	state.shieldCharges -= 1
	if state.shieldCharges <= 0 then
		endEffect(player, "shield")
	end
	return true
end

local function shieldHandler(victim: Player, info: any): string?
	local state = states[victim]
	if not state then
		return nil
	end
	if info.major ~= true and ItemService.HasEffect(victim, "giant") then
		return "blocked" -- géant : immunisé contre les frappes mineures (Gameplay.KO.GiantImmuneToMinor)
	end
	if state.shieldCharges > 0 then
		if info.major == true then
			state.shieldCharges = 0
			endEffect(victim, "shield")
			return "broken"
		end
		consumeShield(victim)
		local achievements = services.get("AchievementService")
		if achievements and type(achievements.Increment) == "function" then
			pcall(achievements.Increment, victim, "shieldBlocks", 1)
		end
		return "blocked"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Inventaire
--------------------------------------------------------------------------------

function ItemService.GetInventory(player: Player): { string }
	local state = states[player]
	return if state then table.clone(state.inv.slots) else {}
end

function ItemService.HasItem(player: Player, itemId: string): boolean
	local state = states[player]
	if not state then
		return false
	end
	for index = 1, state.inv.capacity do
		if state.inv.slots[index] == itemId then
			return true
		end
	end
	return false
end

local function chargedItem(def: any): boolean
	return def.cooldown > 0 and def.charges > 1
end

function ItemService.Grant(player: Player, itemId: string): (boolean, number?)
	local def = Items.get(itemId)
	if not def or player.Parent ~= Players then
		return false, nil
	end
	local state = getState(player)
	local slot = Inventory.add(state.inv, itemId)
	if not slot then
		return false, nil
	end
	state.charges[slot] = if chargedItem(def) then def.charges else 1
	state.cooldowns[slot] = nil
	if Inventory.get(state.inv, state.inv.selected) == itemId or Inventory.count(state.inv) == 1 then
		state.inv.selected = slot
	end
	publish(player)
	pcall(Net.fire, "Items.Gained", player, itemId, slot)
	ItemService.ItemGained:Fire(player, itemId, slot)
	return true, slot
end

function ItemService.Remove(player: Player, slot: number)
	local state = states[player]
	if not state then
		return
	end
	Inventory.remove(state.inv, slot)
	state.charges[slot] = nil
	state.cooldowns[slot] = nil
	publish(player)
end

-- Tirage serveur avec rattrapage (Logic/ItemOdds).
function ItemService.GrantRandom(player: Player, boxKind: string?): string?
	local position = ItemBoxes.DefaultNormalizedPosition
	local match = matchService()
	if match and type(match.GetRacePosition) == "function" then
		local ok, rank, total = pcall(match.GetRacePosition, player)
		if ok and type(rank) == "number" and type(total) == "number" then
			position = ItemOdds.normalizedPosition(rank, total)
		end
	end
	local exclude: { [string]: boolean } = {}
	for id in Items.ById do
		if not registry[id] then
			exclude[id] = true -- comportement absent : ne jamais distribuer un objet inutilisable
		end
	end
	local id = ItemOdds.roll(Items.List :: any, rng, position, ItemBoxes.CatchUpStrength, boxKind or "Random", exclude)
	if id and ItemService.Grant(player, id) then
		return id
	end
	return nil
end

--------------------------------------------------------------------------------
-- Boîtes d'objets
--------------------------------------------------------------------------------

local function buildBox(position: Vector3, kind: string): Box
	local info = ItemBoxes.Kinds[kind]
	local size = ItemBoxes.Visual.Size
	local part = Instance.new("Part")
	part.Name = "BoiteObjet_" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(size, size, size)
	part.Material = Enum.Material.Neon
	part.Color = info.color
	part.Transparency = 0.15
	part.CFrame = CFrame.new(position + Vector3.new(0, size, 0))
	part:SetAttribute("BoxKind", kind)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60)
	gui.AlwaysOnTop = true
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = info.glyph
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = part
	return { part = part, kind = kind, readyAt = 0, home = position + Vector3.new(0, size, 0) }
end

local function spawnBoxes(runtime: any)
	boxTrove:Clean()
	boxes = {}
	if not itemsEnabled() or type(runtime) ~= "table" or type(runtime.itemBoxes) ~= "table" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BoitesObjets"
	folder.Parent = Workspace
	boxTrove:Add(folder)
	for index, position in runtime.itemBoxes do
		if typeof(position) == "Vector3" then
			-- Une boîte de mobilité sur quatre (les objets de déplacement restent accessibles à tous).
			local box = buildBox(position, if index % 4 == 0 then "Mobility" else "Random")
			box.part.Parent = folder
			table.insert(boxes, box)
		end
	end
	local spin = ItemBoxes.Visual.SpinSpeed
	local bob = ItemBoxes.Visual.BobAmplitude
	local bobSpeed = ItemBoxes.Visual.BobSpeed
	local nextCheck = 0
	boxTrove:Add(RunService.Heartbeat:Connect(function()
		local time = now()
		for _, box in boxes do
			if box.part.Transparency < 1 then
				box.part.CFrame = CFrame.new(box.home + Vector3.new(0, math.sin(time * bobSpeed) * bob, 0)) * CFrame.Angles(0, time * spin, 0)
			end
		end
		if time < nextCheck then
			return
		end
		nextCheck = time + ItemBoxes.CheckInterval
		for _, box in boxes do
			if time < box.readyAt then
				continue
			end
			for _, player in Players:GetPlayers() do
				local state = states[player]
				local root = ctx.root(player)
				if root and (not state or not Inventory.isFull(state.inv)) and ctx.isPlaying(player) then
					if (root.Position - box.home).Magnitude <= ItemBoxes.PickupRadius then
						local id = ItemService.GrantRandom(player, box.kind)
						if id then
							local respawn = ItemBoxes.Respawn[itemFrequency()] or ItemBoxes.Respawn.Normal
							box.readyAt = time + respawn
							box.part.Transparency = 1
							task.delay(respawn, function()
								if box.part.Parent then
									box.part.Transparency = 0.15
								end
							end)
							break
						end
					end
				end
			end
		end
	end))
end

--------------------------------------------------------------------------------
-- Utilisation
--------------------------------------------------------------------------------

-- Retourne (état, objet, définition, nil) ou (nil, nil, nil, clé de refus).
local function checkUse(player: Player, roundId: number, slot: number): (PState?, string?, any?, string?)
	if not itemsEnabled() then
		return nil, nil, nil, FEEDBACK.disabled
	end
	local match = matchService()
	if not match or match.GetPhase() ~= "Playing" or match.GetRoundId() ~= roundId then
		return nil, nil, nil, FEEDBACK.phase
	end
	if not ctx.isPlaying(player) then
		return nil, nil, nil, FEEDBACK.state
	end
	local state = states[player]
	if not state then
		return nil, nil, nil, FEEDBACK.empty
	end
	local itemId = Inventory.get(state.inv, slot)
	local def = if itemId then Items.get(itemId) else nil
	if not itemId or not def then
		return nil, nil, nil, FEEDBACK.empty
	end
	return state, itemId, def, nil
end

local function breakInvisible(player: Player)
	if ItemService.HasEffect(player, "invisible") then
		endEffect(player, "invisible")
	end
end

local function consume(player: Player, state: PState, slot: number, def: any, itemId: string)
	local remaining = (state.charges[slot] or 1) - 1
	if remaining > 0 and chargedItem(def) then
		state.charges[slot] = remaining
		state.cooldowns[slot] = now() + def.cooldown
	else
		Inventory.remove(state.inv, slot)
		state.charges[slot] = nil
		state.cooldowns[slot] = nil
	end
	publish(player)
	if itemId ~= "ninja_smoke" then
		breakInvisible(player)
	end
	ItemService.ItemUsed:Fire(player, itemId)
end

local function sanitizeAim(player: Player, aim: any): Vector3
	if isFiniteVector(aim) and (aim :: Vector3).Magnitude > 0.01 then
		return (aim :: Vector3).Unit
	end
	return ctx.look(player)
end

local function runUse(player: Player, slot: number, aim: any, targetUserId: any, forced: boolean)
	local state, itemId, def, reason = checkUse(player, ctx.roundId(), slot)
	if not state or not itemId or not def then
		if reason and not forced then
			feedback(player, reason)
		end
		return
	end
	local time = now()
	if time - state.lastUse < Items.GlobalUseCooldown then
		return
	end
	local readyAt = state.cooldowns[slot]
	if readyAt and time < readyAt then
		if not forced then
			feedback(player, FEEDBACK.cooldown)
		end
		return
	end
	local module = registry[itemId]
	if not module then
		feedback(player, "item.fb.unavailable")
		return
	end
	local hold = state.hold
	local held = 0
	local shared: { [string]: any } = {}
	if hold and hold.slot == slot then
		held = time - hold.startedAt
		shared = hold.data
	end
	state.hold = nil
	local target: Player? = nil
	if type(targetUserId) == "number" then
		target = Players:GetPlayerByUserId(targetUserId)
	end
	state.lastUse = time
	local ok, used, key = pcall(module.Use, ctx, player, {
		slot = slot,
		aim = sanitizeAim(player, aim),
		target = target,
		held = held,
		hold = shared,
		forced = forced,
	})
	if not ok then
		Log.warn(LOG_TAG, "objet en erreur :", itemId, used)
		feedback(player, "item.fb.unavailable")
		return
	end
	if used == true then
		consume(player, state, slot, def, itemId)
	elseif type(key) == "string" then
		feedback(player, key)
	end
end

-- Corne Tonitruante : utilisation involontaire de l'objet sélectionné (droit devant).
function ctx.forceUse(player: Player, _reason: string?): boolean
	local state = states[player]
	if not state then
		return false
	end
	local slot = state.inv.selected
	local itemId = Inventory.get(state.inv, slot)
	local def = if itemId then Items.get(itemId) else nil
	if not def or not def.hornSensitive then
		return false
	end
	state.lastUse = 0
	state.cooldowns[slot] = nil
	runUse(player, slot, ctx.look(player), nil, true)
	return true
end

local function onSelect(player: Player, slot: number)
	local state = states[player]
	if state and Inventory.select(state.inv, slot) then
		publish(player)
	end
end

local function onUse(player: Player, roundId: number, slot: number, aim: Vector3, targetUserId: number?)
	local state = states[player]
	if not state then
		return
	end
	local _, _, _, reason = checkUse(player, roundId, slot)
	if reason then
		state.hold = nil
		feedback(player, reason)
		return
	end
	runUse(player, slot, aim, targetUserId, false)
end

local function onUseStart(player: Player, roundId: number, slot: number)
	local state, itemId, def, reason = checkUse(player, roundId, slot)
	if not state or not itemId or not def then
		if reason then
			feedback(player, reason)
		end
		return
	end
	local module = registry[itemId]
	if not module or not def.holdToUse then
		return
	end
	local hold: Hold = { slot = slot, itemId = itemId, startedAt = now(), data = {} }
	if type(module.UseStart) == "function" then
		local ok, accepted = pcall(module.UseStart, ctx, player, hold)
		if not ok or accepted == false then
			return
		end
	end
	state.hold = hold
end

local function cancelHold(player: Player)
	local state = states[player]
	if not state or not state.hold then
		return
	end
	local hold = state.hold
	state.hold = nil
	local module = registry[hold.itemId]
	if module and type(module.UseCancel) == "function" then
		pcall(module.UseCancel, ctx, player, hold)
	end
end

local function onUseCancel(player: Player, _roundId: number, slot: number)
	local state = states[player]
	if state and state.hold and state.hold.slot == slot then
		cancelHold(player)
	end
end

--------------------------------------------------------------------------------
-- Nettoyage
--------------------------------------------------------------------------------

function ItemService.ClearRound()
	boxTrove:Clean()
	boxes = {}
	roundTrove:Clean()
	for player, state in states do
		cancelHold(player)
		ItemService.ClearEffects(player)
		state.trove:Clean()
		Inventory.clear(state.inv)
		state.charges = {}
		state.cooldowns = {}
		state.mines = 0
		state.shieldCharges = 0
		publish(player)
	end
	local folder = Workspace:FindFirstChild("ItemEffects")
	if folder then
		folder:ClearAllChildren()
	end
end

local function onCharacterReset(player: Player)
	-- Aucun état temporaire ne survit à une réapparition (docs/REGISTRE_OBJETS.md, « Nettoyage »).
	cancelHold(player)
	ItemService.ClearEffects(player)
end

local function trackPlayer(player: Player)
	getState(player)
	publish(player)
	player.CharacterRemoving:Connect(function()
		onCharacterReset(player)
	end)
	player.CharacterAdded:Connect(function()
		onCharacterReset(player)
	end)
end

--------------------------------------------------------------------------------
-- Contexte transmis aux comportements
--------------------------------------------------------------------------------

local function buildContext()
	ctx.roundTrove = roundTrove
	ctx.rng = rng
	ctx.def = Items.get
	ctx.service = function(name: string): any
		return services.get(name)
	end
	ctx.now = now
	ctx.roundId = function(): number
		local match = matchService()
		return if match and type(match.GetRoundId) == "function" then match.GetRoundId() else 0
	end
	ctx.root = function(player: Player): BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			return root
		end
		return nil
	end
	ctx.look = function(player: Player): Vector3
		local root = ctx.root(player)
		if not root then
			return Vector3.new(0, 0, -1)
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		return if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
	end
	-- En jeu : participant actif, vivant, ni KO, ni gelé, ni ayant terminé le trou.
	ctx.isPlaying = function(player: Player): boolean
		local character = player.Character
		if not character or not ctx.root(player) then
			return false
		end
		local match = matchService()
		if match and type(match.IsActive) == "function" and not match.IsActive(player) then
			return false
		end
		if player:GetAttribute("HoleFinished") == true or player:GetAttribute("Spectating") == true then
			return false
		end
		if character:GetAttribute("KnockedOut") == true or character:GetAttribute("Frozen") == true then
			return false
		end
		return true
	end
	ctx.playerTrove = function(player: Player): Trove
		return getState(player).trove
	end
	ctx.after = function(trove: Trove, seconds: number, fn: () -> ()): thread
		return trove:Add(task.delay(seconds, function()
			local ok, err = pcall(fn)
			if not ok then
				Log.warn(LOG_TAG, "action différée en erreur :", err)
			end
		end))
	end
	ctx.addEffect = ItemService.AddEffect
	ctx.clearEffect = ItemService.ClearEffect
	ctx.hasEffect = ItemService.HasEffect
	ctx.setShield = function(player: Player, charges: number)
		getState(player).shieldCharges = charges
	end
	ctx.shieldCharges = function(player: Player): number
		local state = states[player]
		return if state then state.shieldCharges else 0
	end
	ctx.consumeShield = consumeShield
	ctx.notify = feedback
	ctx.record = function(player: Player, stat: string, amount: number?)
		local achievements = services.get("AchievementService")
		if achievements and type(achievements.Increment) == "function" then
			pcall(achievements.Increment, player, stat, amount or 1)
		end
	end
	ctx.warn = function(victim: Player, itemId: string, attacker: Player)
		pcall(Net.fire, "Items.Warning", victim, itemId, attacker.UserId)
	end
	ctx.lockState = function(player: Player, targetUserId: number)
		pcall(Net.fire, "Items.LockState", player, targetUserId)
	end
	ctx.mines = function(player: Player, delta: number): number
		local state = getState(player)
		state.mines = math.max(0, state.mines + delta)
		return state.mines
	end
	ctx.breakInvisible = breakInvisible
end

local function loadBehaviours()
	local folder = script.Parent.Parent:FindFirstChild("Items")
	if not folder then
		Log.warn(LOG_TAG, "dossier Server/Items introuvable : aucun objet utilisable")
		return
	end
	for _, module in folder:GetChildren() do
		if not module:IsA("ModuleScript") then
			continue
		end
		local ok, behaviour = pcall(require, module)
		if ok and type(behaviour) == "table" and type(behaviour.Id) == "string" and type(behaviour.Use) == "function" then
			if not Items.get(behaviour.Id) then
				Log.warn(LOG_TAG, "comportement sans définition dans Config.Items :", behaviour.Id)
			elseif registry[behaviour.Id] then
				Log.warn(LOG_TAG, "comportement défini deux fois :", behaviour.Id)
			else
				registry[behaviour.Id] = behaviour
			end
		elseif not ok then
			Log.error(LOG_TAG, "comportement illisible :", module.Name, behaviour)
		end
	end
	for _, def in Items.List do
		if not registry[def.id] then
			Log.warn(LOG_TAG, "objet sans comportement :", def.id)
		end
	end
end

function ItemService.GetBehaviours(): { [string]: any }
	return registry
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function ItemService.Init()
	buildContext()
	loadBehaviours()
	Net.on("Items.Select", onSelect)
	Net.on("Items.Use", onUse)
	Net.on("Items.UseStart", onUseStart)
	Net.on("Items.UseCancel", onUseCancel)
end

function ItemService.Start()
	local combat = services.get("CombatService")
	if combat and type(combat.SetShieldHandler) == "function" then
		combat.SetShieldHandler(shieldHandler)
	else
		Log.warn(LOG_TAG, "CombatService absent : pas de Bulle Magnétique")
	end
	services.connect("MatchService", "HoleStarted", spawnBoxes)
	services.connect("BallService", "Shot", function(player: any)
		if typeof(player) == "Instance" and player:IsA("Player") then
			breakInvisible(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		cancelHold(player)
		ItemService.ClearEffects(player)
		local state = states[player]
		if state then
			state.trove:Clean()
		end
		states[player] = nil
	end)
end

return ItemService

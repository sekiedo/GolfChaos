--!strict
--[[
	CosmeticService — boutique, équipement et apparence (docs/ARCHITECTURE.md §8, SPEC §7).

	  CosmeticService.Purchase(player, cosmeticId) -> (boolean, string?)
	  CosmeticService.Equip(player, slot, cosmeticId?) -> (boolean, string?)   (nil = retirer ; Emote = bascule dans la liste)
	  CosmeticService.SetVariant(player, cosmeticId, index) -> (boolean, string?)
	  CosmeticService.SaveLoadout(player, index) / UseLoadout(player, index) -> (boolean, string?)
	  CosmeticService.GetEquipped(player) -> { Head, Face, Outfit, Shoes, Club, Ball, HoleEffect, Emotes, variants }
	  CosmeticService.ApplyAppearance(player, character)
	  CosmeticService.IsUnlocked(player, def) -> (boolean, string?)

	Profil (src/server/Data/Schema.luau) : owned { [id] = true }, equipped { Head, Face, Outfit, Shoes, Club, Ball,
	HoleEffect, Emotes = { ids } }, variants { [id] = index }, loadouts { [1..3] = { equipped, variants } }.
	Achat : PlayerDataService.Transact(player, "buy:<id>", ...) — idempotent, jamais de double débit ; refusé si le
	profil n'est pas prêt (PlayerDataService refuse alors la transaction : état honnête affiché par le client).

	ÉQUITÉ : les modèles viennent de shared/Cosmetics (Build impose Massless, sans collision, sans requête) ; ce
	service ne touche à aucune statistique, aucune portée et aucune collision. Le skin de balle est purement visuel
	(attribut lu par le client) ; la balle serveur reste la référence de collision.
	Visibilité : les accessoires sont ajoutés par le serveur (répliqués à tous) et réappliqués à chaque apparition.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Cosmetics = require(Shared.Cosmetics)
local Economy = require(Shared.Config.Economy)

type CosmeticDef = Cosmetics.CosmeticDef

local CosmeticService = {}
CosmeticService.Priority = 40
CosmeticService.Purchased = Signal.new()
CosmeticService.EquipmentChanged = Signal.new()

local SLOTS = { "Head", "Face", "Outfit", "Shoes", "Club", "Ball", "HoleEffect" }
local SLOT_SET: { [string]: boolean } = { Emote = true }
for _, slot in SLOTS do
	SLOT_SET[slot] = true
end
local MAX_EMOTES = 8
local LOADOUT_COUNT = 3
local COSMETIC_TAG = "GolfChaosCosmetic"

local Services = require(script.Parent.Parent.Util.Services)
local characterTroves: { [Player]: any } = {}

local getService = Services.get

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function readData(player: Player): any?
	local PlayerDataService = getService("PlayerDataService")
	if not PlayerDataService or type(PlayerDataService.GetProfile) ~= "function" then
		return nil
	end
	local ok, profile = pcall(PlayerDataService.GetProfile, player)
	if not ok or type(profile) ~= "table" then
		return nil
	end
	if type((profile :: any).data) == "table" then
		return (profile :: any).data
	end
	return profile
end

local function ensureTables(data: any)
	if type(data.owned) ~= "table" then
		data.owned = {}
	end
	if type(data.equipped) ~= "table" then
		data.equipped = {}
	end
	if type(data.equipped.Emotes) ~= "table" then
		data.equipped.Emotes = {}
	end
	if type(data.variants) ~= "table" then
		data.variants = {}
	end
	if type(data.loadouts) ~= "table" then
		data.loadouts = {}
	end
end

local function result(player: Player, action: string, ok: boolean, reasonKey: string?, payload: any?)
	Net.fire("Shop.Result", player, action, ok, reasonKey, payload)
end

-- Conditions de déblocage ---------------------------------------------------------------

function CosmeticService.IsUnlocked(player: Player, def: CosmeticDef, data: any?): (boolean, string?)
	local unlock = def.unlock
	if not unlock or unlock.kind == "Default" or unlock.kind == "Price" then
		return true, nil
	end
	local profile = data or readData(player)
	if type(profile) ~= "table" then
		return false, "shop.err.profile"
	end
	local stats = if type(profile.stats) == "table" then profile.stats else {}
	if unlock.kind == "Achievement" then
		local entry = type(profile.achievements) == "table" and profile.achievements[unlock.value] or nil
		if type(entry) == "table" and entry.done == true then
			return true, nil
		end
		return false, "shop.err.locked"
	end
	local needed = if isFiniteNumber(unlock.value) then unlock.value else 1
	local counter = if unlock.kind == "Wins" then stats.matchesWon
		elseif unlock.kind == "HolesInOne" then stats.holesInOne
		elseif unlock.kind == "MatchesPlayed" then stats.matchesPlayed
		else nil
	if isFiniteNumber(counter) and counter >= needed then
		return true, nil
	end
	return false, "shop.err.locked"
end

local function ownsOrDefault(data: any, def: CosmeticDef): boolean
	if def.unlock and def.unlock.kind == "Default" then
		return true
	end
	return type(data.owned) == "table" and data.owned[def.id] == true
end

-- Achat ------------------------------------------------------------------------------------

function CosmeticService.Purchase(player: Player, cosmeticId: string): (boolean, string?)
	local def = Cosmetics.get(cosmeticId)
	if not def then
		return false, "shop.err.unknown"
	end
	local PlayerDataService = getService("PlayerDataService")
	if not PlayerDataService or type(PlayerDataService.Transact) ~= "function" then
		return false, "shop.err.profile"
	end
	local snapshot = readData(player)
	if type(snapshot) == "table" then
		ensureTables(snapshot)
		if ownsOrDefault(snapshot, def) then
			return false, "shop.err.owned"
		end
	end
	local unlocked, lockReason = CosmeticService.IsUnlocked(player, def, snapshot)
	if not unlocked then
		return false, lockReason
	end
	local price = if isFiniteNumber(def.price) then math.max(0, math.floor(def.price)) else 0
	local ok, reason = PlayerDataService.Transact(player, "buy:" .. def.id, function(data: any): (boolean, string?)
		ensureTables(data)
		if data.owned[def.id] == true then
			return false, "shop.err.owned"
		end
		local coins = if isFiniteNumber(data.coins) then math.floor(data.coins) else 0
		if coins < price then
			return false, "shop.err.coins"
		end
		data.coins = math.clamp(coins - price, 0, Economy.MaxCoins)
		data.owned[def.id] = true
		return true, nil
	end)
	if ok then
		Log.info("Shop", player.Name, "achète", def.id, price)
		CosmeticService.Purchased:Fire(player, def.id, price)
		return true, nil
	end
	if reason == "duplicate" then
		return false, "shop.err.owned"
	end
	return false, if type(reason) == "string" and string.sub(reason, 1, 5) == "shop." then reason else "shop.err.profile"
end

-- Équipement ---------------------------------------------------------------------------------

local function update(player: Player, mutate: (data: any) -> (boolean, string?)): (boolean, string?)
	local PlayerDataService = getService("PlayerDataService")
	if not PlayerDataService or type(PlayerDataService.Update) ~= "function" then
		return false, "shop.err.profile"
	end
	local outcome: boolean, outcomeReason: string? = false, "shop.err.profile"
	local ok, err = pcall(PlayerDataService.Update, player, function(data: any)
		ensureTables(data)
		outcome, outcomeReason = mutate(data)
	end)
	if not ok then
		Log.warn("Shop", "mise à jour refusée", player.Name, err)
		return false, "shop.err.profile"
	end
	return outcome, outcomeReason
end

local function refresh(player: Player)
	local character = player.Character
	if character then
		CosmeticService.ApplyAppearance(player, character)
	end
	CosmeticService.EquipmentChanged:Fire(player)
end

function CosmeticService.Equip(player: Player, slot: string, cosmeticId: string?): (boolean, string?)
	if not SLOT_SET[slot] then
		return false, "shop.err.slot"
	end
	local def: CosmeticDef? = nil
	if cosmeticId ~= nil then
		def = Cosmetics.get(cosmeticId)
		if not def or def.slot ~= slot then
			return false, "shop.err.unknown"
		end
	end
	local ok, reason = update(player, function(data: any): (boolean, string?)
		if slot == "Emote" then
			if not def then
				return false, "shop.err.unknown"
			end
			if not ownsOrDefault(data, def) then
				return false, "shop.err.notOwned"
			end
			local list = data.equipped.Emotes
			local index = table.find(list, def.id)
			if index then
				table.remove(list, index)
			elseif #list >= MAX_EMOTES then
				return false, "shop.err.emotesFull"
			else
				table.insert(list, def.id)
			end
			return true, nil
		end
		if def then
			if not ownsOrDefault(data, def) then
				return false, "shop.err.notOwned"
			end
			data.equipped[slot] = def.id
		else
			local fallback = Cosmetics.defaultFor(slot :: any)
			data.equipped[slot] = if fallback then fallback.id else nil
		end
		return true, nil
	end)
	if ok then
		refresh(player)
	end
	return ok, reason
end

function CosmeticService.SetVariant(player: Player, cosmeticId: string, index: number): (boolean, string?)
	local def = Cosmetics.get(cosmeticId)
	if not def then
		return false, "shop.err.unknown"
	end
	local count = if def.variants then #def.variants else 1
	if not isFiniteNumber(index) or index < 1 or index > count or math.floor(index) ~= index then
		return false, "shop.err.variant"
	end
	local ok, reason = update(player, function(data: any): (boolean, string?)
		if not ownsOrDefault(data, def) then
			return false, "shop.err.notOwned"
		end
		data.variants[def.id] = index
		return true, nil
	end)
	if ok then
		refresh(player)
	end
	return ok, reason
end

function CosmeticService.SaveLoadout(player: Player, index: number): (boolean, string?)
	if not isFiniteNumber(index) or index < 1 or index > LOADOUT_COUNT or math.floor(index) ~= index then
		return false, "shop.err.loadout"
	end
	return update(player, function(data: any): (boolean, string?)
		local copy = table.clone(data.equipped)
		copy.Emotes = table.clone(data.equipped.Emotes)
		data.loadouts[index] = { equipped = copy, variants = table.clone(data.variants), savedAt = os.time() }
		return true, nil
	end)
end

function CosmeticService.UseLoadout(player: Player, index: number): (boolean, string?)
	if not isFiniteNumber(index) or index < 1 or index > LOADOUT_COUNT or math.floor(index) ~= index then
		return false, "shop.err.loadout"
	end
	local ok, reason = update(player, function(data: any): (boolean, string?)
		local loadout = data.loadouts[index]
		if type(loadout) ~= "table" or type(loadout.equipped) ~= "table" then
			return false, "shop.err.emptyLoadout"
		end
		for _, slot in SLOTS do
			local id = loadout.equipped[slot]
			local def = if type(id) == "string" then Cosmetics.get(id) else nil
			if def and def.slot == slot and ownsOrDefault(data, def) then
				data.equipped[slot] = def.id
			elseif id == nil then
				local fallback = Cosmetics.defaultFor(slot :: any)
				data.equipped[slot] = if fallback then fallback.id else nil
			end
		end
		local emotes = {}
		if type(loadout.equipped.Emotes) == "table" then
			for _, id in loadout.equipped.Emotes do
				local def = if type(id) == "string" then Cosmetics.get(id) else nil
				if def and def.slot == "Emote" and ownsOrDefault(data, def) and #emotes < MAX_EMOTES then
					table.insert(emotes, def.id)
				end
			end
		end
		data.equipped.Emotes = emotes
		if type(loadout.variants) == "table" then
			for id, value in loadout.variants do
				if type(id) == "string" and isFiniteNumber(value) then
					data.variants[id] = value
				end
			end
		end
		return true, nil
	end)
	if ok then
		refresh(player)
	end
	return ok, reason
end

function CosmeticService.GetEquipped(player: Player): { [string]: any }
	local data = readData(player)
	local equipped: { [string]: any } = {}
	for _, slot in SLOTS do
		local id = if type(data) == "table" and type(data.equipped) == "table" then data.equipped[slot] else nil
		local def = if type(id) == "string" then Cosmetics.get(id) else nil
		if not def then
			def = Cosmetics.defaultFor(slot :: any)
		end
		equipped[slot] = if def then def.id else nil
	end
	equipped.Emotes = if type(data) == "table" and type(data.equipped) == "table" and type(data.equipped.Emotes) == "table"
		then table.clone(data.equipped.Emotes)
		else {}
	equipped.variants = if type(data) == "table" and type(data.variants) == "table" then table.clone(data.variants) else {}
	return equipped
end

-- Apparence -----------------------------------------------------------------------------------

local function variantOf(equipped: { [string]: any }, id: string?): number
	if not id then
		return 1
	end
	local value = equipped.variants and equipped.variants[id]
	return if isFiniteNumber(value) then value else 1
end

local function tagCosmetic(instance: Instance)
	instance:SetAttribute(COSMETIC_TAG, true)
end

local function clearCosmetics(character: Model)
	for _, child in character:GetChildren() do
		if child:GetAttribute(COSMETIC_TAG) == true then
			child:Destroy()
		end
	end
end

local function addAccessory(humanoid: Humanoid, accessory: Instance)
	if accessory:IsA("Accessory") then
		tagCosmetic(accessory)
		humanoid:AddAccessory(accessory)
	end
end

local function attachClub(character: Model, model: Model)
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	local handGrip = hand and hand:FindFirstChild("RightGripAttachment") :: Attachment?
	local handle = model:FindFirstChild("Handle") :: BasePart?
	local grip = handle and handle:FindFirstChild("Grip") :: Attachment?
	if not (hand and handGrip and handle and grip) then
		model:Destroy()
		return
	end
	model.Name = "ClubCosmetique"
	tagCosmetic(model)
	-- Aligne l'attachement "Grip" du club sur la main, puis soude (le club suit la main animée).
	model:PivotTo(handGrip.WorldCFrame * grip.CFrame:Inverse() * handle.CFrame:ToObjectSpace(model:GetPivot()))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end
	-- Soudure réglable (Weld, pas WeldConstraint) : AnimationController modifie C0 côté client pour tenir le manche
	-- dans l'axe des mains pendant les animations de golf ; DefaultC0 = position de repos (club tenu normalement).
	local weld = Instance.new("Weld")
	weld.Name = "ClubGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = hand.CFrame:ToObjectSpace(handle.CFrame)
	weld.C1 = CFrame.identity
	weld:SetAttribute("DefaultC0", weld.C0)
	weld.Parent = handle
	model.Parent = character
end

local function applyBodyColors(character: Model, colors: { [string]: Color3 }?)
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = character
	end
	if not colors then
		return
	end
	for property, color in colors do
		if typeof(color) == "Color3" then
			pcall(function()
				(bodyColors :: any)[property] = color
			end)
		end
	end
end

local function build(def: CosmeticDef, variant: number): Instance?
	if type(def.build) ~= "function" then
		return nil
	end
	local ok, instance = pcall(def.build :: any, variant)
	if not ok or typeof(instance) ~= "Instance" then
		Log.warn("Shop", "construction impossible", def.id, instance)
		return nil
	end
	return instance
end

function CosmeticService.ApplyAppearance(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	clearCosmetics(character)
	local equipped = CosmeticService.GetEquipped(player)

	-- Tenue : couleurs du corps + pièces.
	local outfitDef = if equipped.Outfit then Cosmetics.get(equipped.Outfit) else nil
	applyBodyColors(character, outfitDef and outfitDef.bodyColors or nil)
	for _, slot in { "Outfit", "Shoes", "Head", "Face" } do
		local id = equipped[slot]
		local def = if type(id) == "string" then Cosmetics.get(id) else nil
		if def then
			local instance = build(def, variantOf(equipped, def.id))
			if instance then
				if instance:IsA("Folder") then
					for _, child in instance:GetChildren() do
						addAccessory(humanoid, child)
					end
					instance:Destroy()
				else
					addAccessory(humanoid, instance)
				end
			end
		end
	end

	-- Visage dessiné : masque le visage par défaut pour éviter la superposition.
	local head = character:FindFirstChild("Head")
	local defaultFace = head and head:FindFirstChild("face")
	if defaultFace and defaultFace:IsA("Decal") then
		defaultFace.Transparency = if equipped.Face then 1 else 0
	end

	-- Club en main (même longueur pour tous les skins : portée identique).
	local clubDef = if equipped.Club then Cosmetics.get(equipped.Club) else nil
	if clubDef then
		local model = build(clubDef, variantOf(equipped, clubDef.id))
		if model and model:IsA("Model") then
			attachClub(character, model)
		elseif model then
			model:Destroy()
		end
	end

	-- Données visuelles lues par les clients (balle visuelle, effet d'entrée dans le trou).
	player:SetAttribute("BallSkin", equipped.Ball or "")
	player:SetAttribute("BallSkinVariant", variantOf(equipped, equipped.Ball))
	player:SetAttribute("HoleEffect", equipped.HoleEffect or "")
end

-- Profils : starters gratuits ---------------------------------------------------------------

local function grantDefaults(player: Player)
	update(player, function(data: any): (boolean, string?)
		local changed = false
		for _, def in Cosmetics.all() do
			if def.unlock and def.unlock.kind == "Default" and data.owned[def.id] ~= true then
				data.owned[def.id] = true
				changed = true
			end
		end
		for _, slot in SLOTS do
			if data.equipped[slot] == nil then
				local fallback = Cosmetics.defaultFor(slot :: any)
				if fallback then
					data.equipped[slot] = fallback.id
					changed = true
				end
			end
		end
		return changed, nil
	end)
end

-- Cycle de vie --------------------------------------------------------------------------------

function CosmeticService.Init()
	Net.on("Shop.Buy", function(player: Player, cosmeticId: string)
		local ok, reason = CosmeticService.Purchase(player, cosmeticId)
		result(player, "buy", ok, reason, { id = cosmeticId })
	end)
	Net.on("Shop.Equip", function(player: Player, slot: string, cosmeticId: string?)
		local ok, reason = CosmeticService.Equip(player, slot, cosmeticId)
		result(player, "equip", ok, reason, { slot = slot, id = cosmeticId })
	end)
	Net.on("Shop.SetVariant", function(player: Player, cosmeticId: string, index: number)
		local ok, reason = CosmeticService.SetVariant(player, cosmeticId, index)
		result(player, "variant", ok, reason, { id = cosmeticId, index = index })
	end)
	Net.on("Shop.SaveLoadout", function(player: Player, index: number)
		local ok, reason = CosmeticService.SaveLoadout(player, index)
		result(player, "saveLoadout", ok, reason, { index = index })
	end)
	Net.on("Shop.UseLoadout", function(player: Player, index: number)
		local ok, reason = CosmeticService.UseLoadout(player, index)
		result(player, "useLoadout", ok, reason, { index = index })
	end)
end

local function onCharacter(player: Player, character: Model)
	local previous = characterTroves[player]
	if previous then
		previous:Clean()
	end
	local trove = Trove.new()
	characterTroves[player] = trove
	task.defer(function()
		if character.Parent and player.Character == character then
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and character.Parent then
				CosmeticService.ApplyAppearance(player, character)
			end
		end
	end)
end

function CosmeticService.Start()
	local PlayerDataService = getService("PlayerDataService")
	if PlayerDataService and type(PlayerDataService.ProfileLoaded) == "table" then
		PlayerDataService.ProfileLoaded:Connect(function(player: Player)
			grantDefaults(player)
			refresh(player)
		end)
	end
	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local trove = characterTroves[player]
		if trove then
			trove:Clean()
		end
		characterTroves[player] = nil
	end)
end

return CosmeticService

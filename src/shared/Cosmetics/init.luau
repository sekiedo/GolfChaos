--!strict
--[[
	Cosmetics : registre unique des cosmétiques (partagé client/serveur).

	Les définitions vivent dans Cosmetics/Catalog/*.luau (un fichier par famille), chacun retournant
	un tableau de CosmeticDef. Les modèles sont CONSTRUITS PAR CODE (aucun asset uploadé) :
	le serveur les attache aux personnages, le client les construit pour les aperçus 3D.

	  Cosmetics.all() -> { CosmeticDef }           Cosmetics.get(id) -> CosmeticDef?
	  Cosmetics.bySlot(slot) -> { CosmeticDef }     Cosmetics.counts() -> { [Slot]: number }
	  Cosmetics.defaultFor(slot) -> CosmeticDef?    Cosmetics.validate() -> { string } (erreurs)

	ÉQUITÉ (règle absolue) : un cosmétique ne change QUE l'apparence. Toute pièce construite doit avoir
	Massless = true, CanCollide = false, CanQuery = false, CanTouch = false. Les collisions et portées
	du jeu sont calculées sur le HumanoidRootPart et la balle serveur, jamais sur un cosmétique.

	Ce que retourne chaque fonction de construction selon l'emplacement :
	  Head, Face   build(variant) -> Accessory (Handle + pièces soudées ; Attachment du Handle nommé comme
	               l'attachement R15 visé : HatAttachment, HairAttachment, FaceFrontAttachment, FaceCenterAttachment)
	  Outfit       build(variant) -> Folder d'Accessory (torse, bras, jambes...) ; attribut facultatif du Folder
	               "BodyColors" non utilisé : couleurs du corps via le champ bodyColors de la définition
	  Shoes        build(variant) -> Folder de 2 Accessory (LeftFootAttachment, RightFootAttachment)
	  Club         build(variant) -> Model (PrimaryPart "Handle" contenant un Attachment "Grip" au niveau de la
	               poignée, axe du manche le long de -Y du Grip) ; soudé à RightHand.RightGripAttachment
	  Ball         decorate(visualPart, variant) -> Instance? (habille la balle VISUELLE côté client)
	  HoleEffect   play(position, parent) (effet client joué quand la balle du joueur entre dans le trou)
	  Emote        emote = id d'animation procédurale (shared/Animations)
]]

export type Slot = "Head" | "Face" | "Outfit" | "Shoes" | "Club" | "Ball" | "HoleEffect" | "Emote"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type Unlock = {
	kind: "Default" | "Price" | "Achievement" | "Wins" | "HolesInOne" | "MatchesPlayed",
	value: any?, -- id de succès ou seuil numérique selon kind
}
export type Variant = { nameKey: string?, colors: { Color3 } }

export type CosmeticDef = {
	id: string, -- stable, ex. "head_pirate_hat"
	slot: Slot,
	nameKey: string, -- clé Locale (ex. "cos.head_pirate_hat")
	descKey: string?,
	rarity: Rarity,
	price: number, -- prix en pièces (monnaie du jeu) ; 0 si gratuit / déblocage par condition
	unlock: Unlock,
	variants: { Variant }?, -- variantes de couleurs (la variante 1 est celle par défaut)
	bodyColors: { [string]: Color3 }?, -- Outfit : couleurs des parties du corps (HeadColor3, TorsoColor3...)
	tags: { string }?,
	build: ((variant: number?) -> Instance)?,
	decorate: ((visual: BasePart, variant: number?) -> Instance?)?,
	play: ((position: Vector3, parent: Instance) -> ())?,
	emote: string?,
}

local Cosmetics = {}

local list: { CosmeticDef } = {}
local byId: { [string]: CosmeticDef } = {}
local loadErrors: { string } = {}
local loaded = false

local SLOT_ORDER: { Slot } = { "Head", "Face", "Outfit", "Shoes", "Club", "Ball", "HoleEffect", "Emote" }

local function load()
	if loaded then
		return
	end
	loaded = true
	local catalog = script:FindFirstChild("Catalog")
	if not catalog then
		return
	end
	local modules = catalog:GetChildren()
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)
	for _, module in modules do
		if not module:IsA("ModuleScript") then
			continue
		end
		local ok, defs = pcall(require, module)
		if not ok or type(defs) ~= "table" then
			table.insert(loadErrors, module.Name .. " : " .. tostring(defs))
			continue
		end
		for _, def in defs :: { CosmeticDef } do
			if type(def) ~= "table" or type(def.id) ~= "string" then
				table.insert(loadErrors, module.Name .. " : entrée sans id")
			elseif byId[def.id] then
				table.insert(loadErrors, "id dupliqué : " .. def.id)
			else
				byId[def.id] = def
				table.insert(list, def)
			end
		end
	end
	table.sort(list, function(a, b)
		local ia = table.find(SLOT_ORDER, a.slot) or 99
		local ib = table.find(SLOT_ORDER, b.slot) or 99
		if ia ~= ib then
			return ia < ib
		end
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.id < b.id
	end)
end

function Cosmetics.all(): { CosmeticDef }
	load()
	return table.clone(list)
end

function Cosmetics.get(id: string): CosmeticDef?
	load()
	return byId[id]
end

function Cosmetics.bySlot(slot: Slot): { CosmeticDef }
	load()
	local result = {}
	for _, def in list do
		if def.slot == slot then
			table.insert(result, def)
		end
	end
	return result
end

function Cosmetics.counts(): { [string]: number }
	load()
	local counts: { [string]: number } = {}
	for _, def in list do
		counts[def.slot] = (counts[def.slot] or 0) + 1
	end
	return counts
end

-- Cosmétique gratuit par défaut d'un emplacement (unlock.kind == "Default"), s'il existe.
function Cosmetics.defaultFor(slot: Slot): CosmeticDef?
	load()
	for _, def in list do
		if def.slot == slot and def.unlock.kind == "Default" then
			return def
		end
	end
	return nil
end

-- Vérifications structurelles (utilisées par les tests) : retourne la liste des erreurs.
function Cosmetics.validate(): { string }
	load()
	local errors = table.clone(loadErrors)
	for _, def in list do
		local prefix = def.id .. " : "
		if not table.find(SLOT_ORDER, def.slot) then
			table.insert(errors, prefix .. "emplacement inconnu " .. tostring(def.slot))
		end
		if type(def.nameKey) ~= "string" or def.nameKey == "" then
			table.insert(errors, prefix .. "nameKey manquant")
		end
		if type(def.price) ~= "number" or def.price < 0 or math.floor(def.price) ~= def.price then
			table.insert(errors, prefix .. "prix invalide")
		end
		if type(def.unlock) ~= "table" then
			table.insert(errors, prefix .. "unlock manquant")
		end
		local slot = def.slot
		if (slot == "Head" or slot == "Face" or slot == "Outfit" or slot == "Shoes" or slot == "Club") and type(def.build) ~= "function" then
			table.insert(errors, prefix .. "build manquant")
		elseif slot == "Ball" and type(def.decorate) ~= "function" then
			table.insert(errors, prefix .. "decorate manquant")
		elseif slot == "HoleEffect" and type(def.play) ~= "function" then
			table.insert(errors, prefix .. "play manquant")
		elseif slot == "Emote" and type(def.emote) ~= "string" then
			table.insert(errors, prefix .. "emote manquant")
		end
	end
	return errors
end

return Cosmetics

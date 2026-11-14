--!strict
--[[
	Cosmetics.Status — état d'un cosmétique pour l'interface (pur, partagé client/serveur, aucun effet au require).
	Reprend les règles de CosmeticService (possession, déblocage, achat) pour afficher le bon bouton ; le serveur
	reste seul juge : ce module n'autorise rien, il ne fait qu'expliquer.

	  Status.isOwned(def, snap) -> boolean           par défaut ou acheté
	  Status.isEquipped(def, snap) -> boolean        équipé (Emote : présent dans la liste équipée)
	  Status.unlock(def, snap) -> { unlocked, current, target, textKey, vars }
	  Status.of(def, snap) -> "equipped" | "owned" | "buyable" | "poor" | "locked"
	  Status.variantOf(def, snap) -> indice de variante choisi (1 par défaut)
	  Status.RARITY_ORDER / Status.rarityRank(rarity)

	snap = instantané du profil (Data.Sync) : { coins, owned, equipped, variants, achievements, stats }.
]]

local Status = {}

export type Snapshot = {
	coins: number?,
	owned: { [string]: boolean }?,
	equipped: { [string]: any }?,
	variants: { [string]: number }?,
	achievements: { [string]: { done: boolean? } }?,
	stats: { [string]: number }?,
}

Status.RARITY_ORDER = table.freeze({ "Common", "Rare", "Epic", "Legendary" })

function Status.rarityRank(rarity: string): number
	return table.find(Status.RARITY_ORDER :: any, rarity) or 0
end

local function isDefault(def: any): boolean
	return def.unlock ~= nil and def.unlock.kind == "Default"
end

function Status.isOwned(def: any, snap: Snapshot?): boolean
	if isDefault(def) then
		return true
	end
	return snap ~= nil and snap.owned ~= nil and snap.owned[def.id] == true
end

function Status.isEquipped(def: any, snap: Snapshot?): boolean
	local equipped = snap and snap.equipped
	if not equipped then
		return false
	end
	if def.slot == "Emote" then
		local list = equipped.Emotes
		return type(list) == "table" and table.find(list, def.id) ~= nil
	end
	local id = equipped[def.slot]
	if type(id) == "string" and id ~= "" then
		return id == def.id
	end
	return isDefault(def) -- "" = cosmétique par défaut de l'emplacement
end

function Status.unlock(def: any, snap: Snapshot?): { unlocked: boolean, current: number, target: number, textKey: string, vars: { [string]: any }? }
	local unlock = def.unlock
	local kind = if unlock then unlock.kind else "Default"
	local stats: { [string]: number } = if snap and snap.stats then snap.stats else {}
	if kind == "Default" or kind == "Price" then
		return { unlocked = true, current = 1, target = 1, textKey = "shop.unlock.free", vars = nil }
	end
	if kind == "Achievement" then
		local entry = snap and snap.achievements and snap.achievements[unlock.value]
		local done = type(entry) == "table" and entry.done == true
		return {
			unlocked = done,
			current = if done then 1 else 0,
			target = 1,
			textKey = "shop.unlock.achievement",
			vars = { nameKey = "ach." .. tostring(unlock.value) .. ".name" }, -- clé à traduire par l'appelant
		}
	end
	local target = if type(unlock.value) == "number" then unlock.value else 1
	local counter = if kind == "Wins" then stats.matchesWon
		elseif kind == "HolesInOne" then stats.holesInOne
		elseif kind == "MatchesPlayed" then stats.matchesPlayed
		else nil
	local current = if type(counter) == "number" then counter else 0
	local textKey = if kind == "Wins" then "shop.unlock.wins"
		elseif kind == "HolesInOne" then "shop.unlock.holesInOne"
		else "shop.unlock.matches"
	return { unlocked = current >= target, current = math.min(current, target), target = target, textKey = textKey, vars = { n = target } }
end

function Status.of(def: any, snap: Snapshot?): string
	if Status.isOwned(def, snap) then
		return if Status.isEquipped(def, snap) then "equipped" else "owned"
	end
	if not Status.unlock(def, snap).unlocked then
		return "locked"
	end
	local coins = (snap and snap.coins) or 0
	return if coins >= (def.price or 0) then "buyable" else "poor"
end

function Status.variantOf(def: any, snap: Snapshot?): number
	local index = snap and snap.variants and snap.variants[def.id]
	local count = if def.variants then #def.variants else 1
	if type(index) == "number" and index >= 1 and index <= count then
		return math.floor(index)
	end
	return 1
end

return Status

--!strict
--[[
	Logic.ItemOdds — tirage pur et testable des objets, avec rattrapage selon la position dans la course.

	  ItemOdds.normalizedPosition(rank, total)                -> 0 (meneur) .. 1 (dernier) ; 0.5 si total <= 1
	  ItemOdds.weights(defs, position, strength, boxKind)     -> { { id, weight } } (poids > 0 uniquement)
	  ItemOdds.probabilities(defs, position, strength, kind)  -> { [id] = probabilité } (somme = 1)
	  ItemOdds.roll(defs, rng: Random, position, strength, boxKind, exclude?) -> id?

	Poids d'un objet = lerp(weightLeader, weightLast, position × strength + 0.5 × (1 − strength))
	(strength = 0 : tout le monde tire avec le poids « milieu de course »). Boîte de mobilité : seuls les objets
	dont mobilityBox = true sont éligibles. `exclude` retire des ids (ex. objets désactivés).
]]

local ItemOdds = {}

export type Weighted = { id: string, weight: number }

type MinimalDef = { id: string, weightLeader: number, weightLast: number, mobilityBox: boolean }

function ItemOdds.normalizedPosition(rank: number, total: number): number
	if total <= 1 then
		return 0.5
	end
	return math.clamp((rank - 1) / (total - 1), 0, 1)
end

function ItemOdds.weights(defs: { MinimalDef }, position: number, strength: number, boxKind: string?, exclude: { [string]: boolean }?): { Weighted }
	local s = math.clamp(strength, 0, 1)
	local t = math.clamp(position, 0, 1) * s + 0.5 * (1 - s)
	local result: { Weighted } = {}
	for _, def in defs do
		if exclude and exclude[def.id] then
			continue
		end
		if boxKind == "Mobility" and not def.mobilityBox then
			continue
		end
		local weight = def.weightLeader + (def.weightLast - def.weightLeader) * t
		if weight > 0 then
			table.insert(result, { id = def.id, weight = weight })
		end
	end
	return result
end

function ItemOdds.probabilities(defs: { MinimalDef }, position: number, strength: number, boxKind: string?): { [string]: number }
	local weighted = ItemOdds.weights(defs, position, strength, boxKind)
	local total = 0
	for _, entry in weighted do
		total += entry.weight
	end
	local result: { [string]: number } = {}
	if total <= 0 then
		return result
	end
	for _, entry in weighted do
		result[entry.id] = entry.weight / total
	end
	return result
end

function ItemOdds.roll(defs: { MinimalDef }, rng: Random, position: number, strength: number, boxKind: string?, exclude: { [string]: boolean }?): string?
	local weighted = ItemOdds.weights(defs, position, strength, boxKind, exclude)
	local total = 0
	for _, entry in weighted do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for _, entry in weighted do
		pick -= entry.weight
		if pick <= 0 then
			return entry.id
		end
	end
	return weighted[#weighted].id
end

return ItemOdds

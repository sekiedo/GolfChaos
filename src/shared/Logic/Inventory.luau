--!strict
--[[
	Logic.Inventory — cases d'objets d'un joueur (pur, testable, aucun effet au require).

	  Inventory.new(capacity) -> Inv                       { slots, capacity, selected }
	  Inventory.add(inv, itemId) -> slot?                  première case vide ; nil si plein
	  Inventory.remove(inv, slot) -> itemId?               vide la case et renvoie l'objet
	  Inventory.get(inv, slot) -> itemId?
	  Inventory.select(inv, slot) -> boolean               1..capacité
	  Inventory.selectNext(inv, step)                      cycle parmi les cases (L1 / R1)
	  Inventory.isFull(inv) / Inventory.count(inv)
	  Inventory.setCapacity(inv, capacity)                 réduit : les cases en trop sont perdues
	  Inventory.clear(inv)
	  Inventory.serialize(inv) -> "horn,,espresso"         format de l'attribut joueur Inventory ("" = case vide)
	  Inventory.parse(text, capacity) -> Inv

	Les cases sont numérotées à partir de 1 ; la sélection reste toujours dans 1..capacité.
]]

local Inventory = {}

export type Inv = { slots: { string }, capacity: number, selected: number }

local MAX_CAPACITY = 8

local function clampCapacity(capacity: number): number
	return math.clamp(math.floor(capacity), 1, MAX_CAPACITY)
end

function Inventory.new(capacity: number): Inv
	local size = clampCapacity(capacity)
	local slots: { string } = {}
	for index = 1, size do
		slots[index] = ""
	end
	return { slots = slots, capacity = size, selected = 1 }
end

function Inventory.get(inv: Inv, slot: number): string?
	local id = inv.slots[slot]
	if id == nil or id == "" then
		return nil
	end
	return id
end

function Inventory.add(inv: Inv, itemId: string): number?
	if itemId == "" then
		return nil
	end
	for index = 1, inv.capacity do
		if inv.slots[index] == "" then
			inv.slots[index] = itemId
			return index
		end
	end
	return nil
end

function Inventory.remove(inv: Inv, slot: number): string?
	local id = Inventory.get(inv, slot)
	if id then
		inv.slots[slot] = ""
	end
	return id
end

function Inventory.select(inv: Inv, slot: number): boolean
	if slot ~= slot or slot < 1 or slot > inv.capacity or math.floor(slot) ~= slot then
		return false
	end
	inv.selected = slot
	return true
end

function Inventory.selectNext(inv: Inv, step: number)
	local direction = if step < 0 then -1 else 1
	inv.selected = ((inv.selected - 1 + direction) % inv.capacity) + 1
end

function Inventory.count(inv: Inv): number
	local total = 0
	for index = 1, inv.capacity do
		if inv.slots[index] ~= "" then
			total += 1
		end
	end
	return total
end

function Inventory.isFull(inv: Inv): boolean
	return Inventory.count(inv) >= inv.capacity
end

function Inventory.setCapacity(inv: Inv, capacity: number)
	local size = clampCapacity(capacity)
	for index = 1, size do
		inv.slots[index] = inv.slots[index] or ""
	end
	for index = size + 1, #inv.slots do
		inv.slots[index] = nil :: any
	end
	inv.capacity = size
	inv.selected = math.clamp(inv.selected, 1, size)
end

function Inventory.clear(inv: Inv)
	for index = 1, inv.capacity do
		inv.slots[index] = ""
	end
end

function Inventory.serialize(inv: Inv): string
	local parts: { string } = {}
	for index = 1, inv.capacity do
		parts[index] = inv.slots[index] or ""
	end
	return table.concat(parts, ",")
end

function Inventory.parse(text: string, capacity: number): Inv
	local inv = Inventory.new(capacity)
	if text ~= "" then
		for index, id in string.split(text, ",") do
			if index <= inv.capacity then
				inv.slots[index] = id
			end
		end
	end
	return inv
end

return Inventory

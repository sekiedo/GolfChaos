--!strict
--[[
	Animations : registre des animations PROCÉDURALES (partagé client/serveur, aucun effet de bord).

	Aucune animation n'est uploadée : chaque animation est une fonction joints(t) qui renvoie, pour un instant
	t (secondes depuis le début), une CFrame de décalage par articulation R15. AnimationController (client)
	multiplie ces décalages avec le résultat de l'Animator (joint.Transform = décalage * joint.Transform)
	pendant RunService.PreSimulation, sur chaque client, pour tous les personnages. Voir docs/ANIMATIONS.md.

	  Animations.get(id) -> AnimationDef?         Animations.list() -> { AnimationDef } (triées par id)
	  Animations.sample(id, t) -> Pose?           Animations.forState(animState, shotType?) -> id?
	  Animations.validate() -> { string }         Animations.JOINTS (noms des articulations)

	Bibliothèques : Animations/Library/*.luau (Golf, Combat, Emotes...), chacune retournant { AnimationDef }.
	Library/Kit.luau est la boîte à outils commune (ignorée par le chargement).
]]

local Kit = require(script.Library.Kit)

export type Pose = Kit.Pose

export type AnimationDef = {
	id: string,
	duration: number, -- durée d'un cycle (bouclée) ou de l'animation (ponctuelle), en secondes
	looped: boolean,
	hold: boolean?, -- ponctuelle : garde la dernière pose tant que l'état qui l'a lancée dure
	priority: number, -- la plus haute recouvre les autres (golf/combat > émotes)
	blendIn: number, -- secondes de fondu d'entrée
	blendOut: number, -- secondes de fondu de sortie
	joints: (t: number) -> Pose,
	calm: number?, -- amplitude en mode « effets réduits » (0..1, défaut 1 = inchangée)
	club: boolean?, -- le poignet droit tient le club : AnimationController corrige l'orientation du manche
	fx: ((rig: Model) -> { Instance })?, -- effets client facultatifs (particules), détruits à l'arrêt
	tags: { string }?,
}

local Animations = {}

Animations.JOINTS = Kit.JOINTS
Animations.Kit = Kit

local list: { AnimationDef } = {}
local byId: { [string]: AnimationDef } = {}
local loadErrors: { string } = {}

do
	local library = script:FindFirstChild("Library")
	local modules = if library then library:GetChildren() else {}
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)
	for _, module in modules do
		if not module:IsA("ModuleScript") or module.Name == "Kit" or string.sub(module.Name, 1, 1) == "_" then
			continue
		end
		local ok, defs = pcall(require, module)
		if not ok or type(defs) ~= "table" then
			table.insert(loadErrors, module.Name .. " : " .. tostring(defs))
			continue
		end
		for _, def in defs :: { AnimationDef } do
			if type(def) ~= "table" or type(def.id) ~= "string" then
				table.insert(loadErrors, module.Name .. " : animation sans id")
			elseif byId[def.id] then
				table.insert(loadErrors, "id d'animation dupliqué : " .. def.id)
			else
				byId[def.id] = def
				table.insert(list, def)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
end

function Animations.get(id: string): AnimationDef?
	return byId[id]
end

function Animations.list(): { AnimationDef }
	return table.clone(list)
end

-- Pose d'une animation à l'instant t (aperçus, tests). nil si l'id est inconnu.
function Animations.sample(id: string, t: number): Pose?
	local def = byId[id]
	if not def then
		return nil
	end
	return def.joints(t)
end

-- Animation correspondant à l'attribut de personnage AnimState (docs/ARCHITECTURE.md §6).
-- shotType ("Drive" | "Chip" | "Putt") choisit la variante de golf ; nil = coup plein.
function Animations.forState(state: string, shotType: string?): string?
	if state == "Address" then
		return if shotType == "Putt" then "golf_putt_address" else "golf_address"
	elseif state == "Charging" then
		if shotType == "Putt" then
			return "golf_putt_charge"
		elseif shotType == "Chip" then
			return "golf_chip_charge"
		end
		return "golf_charge"
	elseif state == "Swing" then
		if shotType == "Putt" then
			return "golf_putt"
		elseif shotType == "Chip" then
			return "golf_chip"
		end
		return "golf_swing"
	elseif state == "Dive" then
		return "combat_dive"
	elseif state == "Punch" then
		return "combat_punch"
	elseif state == "KO" then
		return "combat_ko"
	end
	return nil
end

-- Animation jouée en transition quand l'état `from` se termine (ex. se relever après un KO).
function Animations.transitionFrom(from: string): string?
	if from == "KO" then
		return "combat_getup"
	end
	return nil
end

local function isFiniteCFrame(cf: any): boolean
	if typeof(cf) ~= "CFrame" then
		return false
	end
	for _, component in { cf:GetComponents() } do
		if component ~= component or component == math.huge or component == -math.huge then
			return false
		end
	end
	return true
end

-- Vérifications structurelles + échantillonnage (valeurs finies, articulations connues). Utilisé par les tests.
function Animations.validate(): { string }
	local errors = table.clone(loadErrors)
	local known: { [string]: boolean } = {}
	for _, name in Kit.JOINTS do
		known[name] = true
	end
	for _, def in list do
		local prefix = def.id .. " : "
		if type(def.duration) ~= "number" or def.duration <= 0 then
			table.insert(errors, prefix .. "durée invalide")
		end
		if type(def.priority) ~= "number" then
			table.insert(errors, prefix .. "priorité manquante")
		end
		if type(def.blendIn) ~= "number" or def.blendIn < 0 or type(def.blendOut) ~= "number" or def.blendOut < 0 then
			table.insert(errors, prefix .. "fondus invalides")
		end
		if type(def.joints) ~= "function" then
			table.insert(errors, prefix .. "joints manquant")
			continue
		end
		local duration = if type(def.duration) == "number" and def.duration > 0 then def.duration else 1
		for step = 0, 12 do
			local t = duration * step / 10 -- dépasse volontairement la fin (maintien / bouclage)
			local ok, pose = pcall(def.joints, t)
			if not ok then
				table.insert(errors, string.format("%sjoints(%.2f) : %s", prefix, t, tostring(pose)))
				break
			end
			if type(pose) ~= "table" then
				table.insert(errors, prefix .. "joints ne retourne pas de table")
				break
			end
			local bad: string? = nil
			for name, cf in pose :: Pose do
				if not known[name] then
					bad = "articulation inconnue " .. tostring(name)
				elseif not isFiniteCFrame(cf) then
					bad = "valeur non finie pour " .. name
				end
			end
			if bad then
				table.insert(errors, string.format("%st=%.2f : %s", prefix, t, bad))
				break
			end
		end
	end
	return errors
end

return Animations

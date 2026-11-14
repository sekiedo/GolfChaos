--!strict
--[[
	ScreenManager — gestion des écrans d'interface (un ScreenGui par écran), pile de modales, retour (B / Échap)
	et focus manette (GuiService.SelectedObject). Module unique côté client (état au niveau du module).

	  ScreenManager.SetRoot(playerGui)               racine des ScreenGui (UIController, au démarrage)
	  ScreenManager.Register(nom, écran)             enregistre un écran (construit paresseusement)
	  ScreenManager.Show(nom, args?)                 affiche (ou met à jour s'il est déjà visible)
	  ScreenManager.Hide(nom)                        masque (animation de sortie de l'écran respectée)
	  ScreenManager.Toggle(nom, args?)               bascule
	  ScreenManager.HideAll(except?)                 masque tout sauf un nom ou une liste de noms
	  ScreenManager.IsVisible(nom) / GetTopModal() / Get(nom) / GetGui(nom)
	  ScreenManager.Back() -> boolean                ferme la modale du dessus (ou la laisse traiter Retour) ;
	                                                 false si aucune modale (l'appelant laisse passer l'entrée)
	  ScreenManager.FocusTop()                       place la sélection manette sur la modale du dessus
	  ScreenManager.Preload(nom)                     construit l'écran sans l'afficher
	  ScreenManager.Changed : Signal(nom, visible)

	Contrat d'un écran (table ; méthodes appelées avec « : », toutes facultatives sauf Build) :
	  DisplayOrder: number?        couche (Theme.Layers)
	  Modal: boolean?              entre dans la pile de modales (Retour la ferme, focus manette capturé)
	  CaptureFocus: boolean?       prend le focus manette à l'affichage sans être une modale
	  IgnoreGuiInset: boolean?     défaut true (plein écran sous la barre Roblox)
	  Build(self, gui: ScreenGui)  construit l'interface (une seule fois)
	  Show(self, args, déjàVisible)
	  Hide(self) -> number?        durée de l'animation de sortie avant de désactiver le ScreenGui
	  Back(self) -> boolean?       true = Retour traité par l'écran (sous-panneau refermé…), sinon on le masque
	  GetDefaultSelection(self) -> GuiObject?
	  Destroy(self)
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Log = require(Shared.Util.Log)

local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Components.Base)

type Entry = {
	name: string,
	screen: any,
	gui: ScreenGui?,
	built: boolean,
	visible: boolean,
	token: number,
	returnSelection: GuiObject?,
}

local ScreenManager = {}

ScreenManager.Changed = Signal.new()

local entries: { [string]: Entry } = {}
local modalStack: { string } = {}
local root: Instance? = nil

local function call(entry: Entry, method: string, ...: any): (boolean, any)
	local fn = entry.screen[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local results = table.pack(xpcall(fn, debug.traceback, entry.screen, ...))
	if not results[1] then
		Log.warn("UI", string.format("écran %s:%s en erreur : %s", entry.name, method, tostring(results[2])))
		return false, nil
	end
	return true, results[2]
end

-- Vrai si l'objet peut recevoir la sélection manette (visible jusqu'à un ScreenGui activé).
local function isSelectable(object: Instance?): boolean
	if not object or not object:IsA("GuiObject") or not object.Selectable then
		return false
	end
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return current.Enabled and current:IsDescendantOf(game)
		end
		current = current.Parent
	end
	return false
end

-- Premier objet sélectionnable visible d'un ScreenGui (ordre de parcours de l'arbre).
local function firstSelectable(container: Instance): GuiObject?
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiObject") and isSelectable(descendant) then
			return descendant
		end
	end
	return nil
end

local function focusEntry(entry: Entry)
	if not Base.isGamepad() then
		return
	end
	local gui = entry.gui
	if not gui then
		return
	end
	local _, preferred = call(entry, "GetDefaultSelection")
	local target: GuiObject? = nil
	if typeof(preferred) == "Instance" and isSelectable(preferred) then
		target = preferred :: GuiObject
	else
		target = firstSelectable(gui)
	end
	if target then
		GuiService.SelectedObject = target
	end
end

local function ensureBuilt(entry: Entry): ScreenGui?
	if entry.built then
		return entry.gui
	end
	local parent = root
	if not parent then
		Log.warn("UI", "ScreenManager : racine absente, écran non construit :", entry.name)
		return nil
	end
	entry.built = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "GC_" .. entry.name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = entry.screen.IgnoreGuiInset ~= false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = if type(entry.screen.DisplayOrder) == "number" then entry.screen.DisplayOrder else 20
	gui.Enabled = false
	gui.Parent = parent
	entry.gui = gui
	call(entry, "Build", gui)
	return gui
end

local function removeFromStack(name: string)
	local index = table.find(modalStack, name)
	if index then
		table.remove(modalStack, index)
	end
end

function ScreenManager.SetRoot(parent: Instance)
	root = parent
end

function ScreenManager.Register(name: string, screen: any)
	assert(type(screen) == "table", "ScreenManager.Register : écran invalide " .. tostring(name))
	local existing = entries[name]
	if existing then
		Log.warn("UI", "écran remplacé :", name)
		ScreenManager.Hide(name)
		call(existing, "Destroy")
		if existing.gui then
			existing.gui:Destroy()
		end
	end
	entries[name] = {
		name = name,
		screen = screen,
		gui = nil,
		built = false,
		visible = false,
		token = 0,
		returnSelection = nil,
	}
end

function ScreenManager.Preload(name: string)
	local entry = entries[name]
	if entry then
		ensureBuilt(entry)
	end
end

function ScreenManager.Get(name: string): any
	local entry = entries[name]
	return if entry then entry.screen else nil
end

function ScreenManager.GetGui(name: string): ScreenGui?
	local entry = entries[name]
	return if entry then entry.gui else nil
end

function ScreenManager.IsVisible(name: string): boolean
	local entry = entries[name]
	return entry ~= nil and entry.visible
end

function ScreenManager.GetTopModal(): string?
	return modalStack[#modalStack]
end

function ScreenManager.Show(name: string, args: any?)
	local entry = entries[name]
	if not entry then
		Log.warn("UI", "écran inconnu :", name)
		return
	end
	local gui = ensureBuilt(entry)
	if not gui then
		return
	end
	local wasVisible = entry.visible
	entry.token += 1
	entry.visible = true
	local isModal = entry.screen.Modal == true
	if isModal then
		if not wasVisible then
			local current = GuiService.SelectedObject
			entry.returnSelection = if current and not current:IsDescendantOf(gui) then current else nil
		end
		removeFromStack(name)
		table.insert(modalStack, name)
	end
	gui.Enabled = true
	call(entry, "Show", args, wasVisible)
	if not wasVisible and (isModal or entry.screen.CaptureFocus == true) then
		-- Après une image : laisse les mises en page (UIListLayout, tailles automatiques) se calculer.
		task.defer(function()
			if entry.visible then
				focusEntry(entry)
			end
		end)
	end
	if not wasVisible then
		ScreenManager.Changed:Fire(name, true)
	end
end

function ScreenManager.Hide(name: string)
	local entry = entries[name]
	if not entry or not entry.visible then
		return
	end
	entry.visible = false
	entry.token += 1
	local token = entry.token
	removeFromStack(name)
	local gui = entry.gui
	local _, delay = call(entry, "Hide")
	local wait = if type(delay) == "number" and delay > 0 then delay else 0

	-- Focus manette : quitte l'écran masqué vers la modale suivante ou l'objet mémorisé.
	local selected = GuiService.SelectedObject
	if gui and selected and selected:IsDescendantOf(gui) then
		local top = modalStack[#modalStack]
		local returnTo = entry.returnSelection
		if top and entries[top] then
			GuiService.SelectedObject = nil
			focusEntry(entries[top])
		elseif returnTo and isSelectable(returnTo) then
			GuiService.SelectedObject = returnTo
		else
			GuiService.SelectedObject = nil
		end
	end
	entry.returnSelection = nil

	if gui then
		if wait > 0 then
			task.delay(wait, function()
				if entry.token == token and not entry.visible then
					gui.Enabled = false
				end
			end)
		else
			gui.Enabled = false
		end
	end
	ScreenManager.Changed:Fire(name, false)
end

function ScreenManager.Toggle(name: string, args: any?)
	if ScreenManager.IsVisible(name) then
		ScreenManager.Hide(name)
	else
		ScreenManager.Show(name, args)
	end
end

function ScreenManager.HideAll(except: (string | { string })?)
	local keep: { [string]: boolean } = {}
	if type(except) == "string" then
		keep[except] = true
	elseif type(except) == "table" then
		for _, name in except do
			keep[name] = true
		end
	end
	for name, entry in entries do
		if entry.visible and not keep[name] then
			ScreenManager.Hide(name)
		end
	end
end

function ScreenManager.Back(): boolean
	local top = modalStack[#modalStack]
	if not top then
		return false
	end
	local entry = entries[top]
	if not entry then
		removeFromStack(top)
		return false
	end
	local ok, handled = call(entry, "Back")
	if ok and handled == true then
		return true
	end
	Base.playSound("ui_click", 0.7)
	ScreenManager.Hide(top)
	return true
end

function ScreenManager.FocusTop()
	local top = modalStack[#modalStack]
	if top and entries[top] then
		local selected = GuiService.SelectedObject
		local gui = entries[top].gui
		if selected and gui and selected:IsDescendantOf(gui) and isSelectable(selected) then
			return
		end
		focusEntry(entries[top])
	end
end

-- Focus explicite sur un écran visible (CaptureFocus ou appel manuel après reconstruction du contenu).
function ScreenManager.Focus(name: string)
	local entry = entries[name]
	if entry and entry.visible then
		focusEntry(entry)
	end
end

-- Outils partagés par les écrans.
ScreenManager.isSelectable = isSelectable

-- UIScale suivi par l'échelle du thème (grands écrans) ; à poser sur les panneaux centrés d'un écran.
local trackedScales: { [UIScale]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local scaleHooked = false

function ScreenManager.AttachScale(object: GuiObject): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "EchelleTheme"
	scale.Scale = Theme.getScale()
	scale.Parent = object
	trackedScales[scale] = true
	if not scaleHooked then
		scaleHooked = true
		Theme.Changed:Connect(function(what: any)
			if what == "layout" then
				for tracked in trackedScales do
					if tracked.Parent then
						tracked.Scale = Theme.getScale()
					end
				end
			end
		end)
	end
	return scale
end

return ScreenManager

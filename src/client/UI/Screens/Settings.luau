--!strict
--[[
	Settings — écran des réglages du joueur (modale à onglets) :
	  Son           volume général, musique, effets sonores, sons de l'interface
	  Commandes     sensibilité de la caméra, inversion de l'axe vertical, vibrations
	  Affichage     qualité des effets, taille du texte, langue
	  Accessibilité secousses de la caméra, effets réduits, mode sans flash
	Chaque contrôle écrit aussitôt dans SettingsController (application immédiate, enregistrement différé) et
	suit ses changements (instantané Data.Sync reçu pendant que l'écran est ouvert). LB / RB changent d'onglet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Modal = require(UI.Components.Modal)
local Tabs = require(UI.Components.Tabs)
local Grid = require(UI.Components.Grid)
local Toggle = require(UI.Components.Toggle)
local Slider = require(UI.Components.Slider)
local Cycler = require(UI.Components.Cycler)
local Util = require(script.Parent.Util)

local Settings = {}

type ControlApi = { Instance: GuiObject, Set: (value: any, silent: boolean?) -> () }

local TAB_DEFS = {
	{ id = "audio", key = "settings.tab.audio", glyph = "♪" },
	{ id = "controls", key = "settings.tab.controls", glyph = "✥" },
	{ id = "display", key = "settings.tab.display", glyph = "▣" },
	{ id = "access", key = "settings.tab.access", glyph = "♿" },
}

local function percent(value: number): string
	return Locale.t("ui.percent", { n = math.floor(value * 100 + 0.5) })
end

local function multiplier(value: number): string
	return Locale.t("ui.multiplier", { n = string.format("%.2f", value) })
end

function Settings.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Settings, Modal = true }

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local tabs: Tabs.TabsApi
	local pages: { [string]: Grid.GridApi } = {}
	local controls: { [string]: ControlApi } = {}

	local function settingsController(): any
		return Util.controller("SettingsController")
	end

	local function getValue(key: string): any
		local settings = settingsController()
		if settings and type(settings.Get) == "function" then
			local ok, value = pcall(settings.Get, key)
			if ok then
				return value
			end
		end
		return nil
	end

	local function setValue(key: string, value: any)
		local settings = settingsController()
		if settings and type(settings.Set) == "function" then
			pcall(settings.Set, key, value)
		end
	end

	local function specOf(key: string): any
		local settings = settingsController()
		if settings and type(settings.GetSpec) == "function" then
			local ok, spec = pcall(settings.GetSpec, key)
			if ok then
				return spec
			end
		end
		return nil
	end

	-- Ligne : libellé (+ description) à gauche, contrôle à droite.
	local function row(page: Grid.GridApi, key: string, order: number, control: GuiObject, descKey: string?)
		local frame = Instance.new("Frame")
		frame.Name = "Ligne_" .. key
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Theme.Colors.NightRaised
		frame.Size = UDim2.new(1, -10, 0, if descKey then 76 else 60)
		frame.LayoutOrder = order
		Base.corner(frame, "Medium")
		Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		Base.padding(frame, nil, Theme.Spacing.M, 6)
		frame.Parent = page.Instance

		local controlWidth = control.Size.X.Offset
		local texts = Instance.new("Frame")
		texts.Name = "Textes"
		texts.BackgroundTransparency = 1
		texts.Size = UDim2.new(1, -(controlWidth + 12), 1, 0)
		Base.list(texts, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		texts.Parent = frame
		Label.new({
			name = "Libelle",
			key = "settings." .. key,
			style = "Body",
			font = "Heavy",
			layoutOrder = 1,
			parent = texts,
		})
		if descKey then
			Label.new({
				name = "Description",
				key = descKey,
				style = "Caption",
				font = "Bold",
				color = Theme.Colors.PaperDim,
				layoutOrder = 2,
				parent = texts,
			})
		end

		control.AnchorPoint = Vector2.new(1, 0.5)
		control.Position = UDim2.new(1, 0, 0.5, 0)
		control.Parent = frame
	end

	local function addSlider(page: Grid.GridApi, key: string, order: number, format: (number) -> string)
		local spec = specOf(key) or { min = 0, max = 1, step = 0.05 }
		local slider = Slider.new({
			name = "Curseur",
			min = spec.min or 0,
			max = spec.max or 1,
			step = spec.step or 0.05,
			value = tonumber(getValue(key)) or spec.default or 0,
			format = format,
			width = 200,
			onChanged = function(value: number)
				setValue(key, value)
			end,
		})
		controls[key] = slider :: any
		row(page, key, order, slider.Instance)
	end

	local function addToggle(page: Grid.GridApi, key: string, order: number, descKey: string?)
		local toggle = Toggle.new({
			name = "Interrupteur",
			value = getValue(key) == true,
			onChanged = function(value: boolean)
				setValue(key, value)
			end,
		})
		controls[key] = toggle :: any
		row(page, key, order, toggle.Instance, descKey)
	end

	local function addCycler(page: Grid.GridApi, key: string, order: number, values: { string }, prefix: string)
		local options = {}
		for _, value in values do
			table.insert(options, { value = value, key = prefix .. value })
		end
		local cycler = Cycler.new({
			name = "Selecteur",
			options = options,
			value = getValue(key),
			width = 240,
			onChanged = function(value: any)
				setValue(key, value)
			end,
		})
		controls[key] = cycler :: any
		row(page, key, order, cycler.Instance)
	end

	local function newPage(id: string): Grid.GridApi
		local page = Grid.list({
			name = "Page_" .. id,
			gap = Theme.Spacing.S,
			position = UDim2.fromOffset(0, 62),
			size = UDim2.new(1, 0, 1, -62 - 64),
			visible = false,
			parent = modal.Content,
		})
		pages[id] = page
		return page
	end

	local function showPage(id: string)
		for pageId, page in pages do
			page.Instance.Visible = pageId == id
		end
		local page = pages[id]
		if page then
			page.ScrollToTop()
		end
	end

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = "settings.title",
			size = Vector2.new(680, 580),
			scroll = false,
			onClose = function()
				ctx.Manager.Hide("Settings")
			end,
		})

		tabs = Tabs.new({
			name = "Onglets",
			tabs = TAB_DEFS,
			selected = "audio",
			size = UDim2.new(1, 0, 0, 56),
			parent = modal.Content,
			onChanged = function(id: string)
				showPage(id)
			end,
		})

		local audio = newPage("audio")
		addSlider(audio, "masterVolume", 1, percent)
		addSlider(audio, "musicVolume", 2, percent)
		addSlider(audio, "sfxVolume", 3, percent)
		addSlider(audio, "uiVolume", 4, percent)

		local controlsPage = newPage("controls")
		addSlider(controlsPage, "sensitivity", 1, multiplier)
		addToggle(controlsPage, "invertY", 2)
		addToggle(controlsPage, "vibration", 3)

		local display = newPage("display")
		addCycler(display, "quality", 1, { "Auto", "Low", "Medium", "High" }, "settings.quality.")
		addCycler(display, "textSize", 2, { "Normal", "Large", "Larger" }, "settings.textSize.")
		local languages = {}
		for _, code in Locale.getLanguages() do
			if Locale.has("settings.language." .. code, "fr") then
				table.insert(languages, code)
			end
		end
		addCycler(display, "language", 3, languages, "settings.language.")

		local access = newPage("access")
		addSlider(access, "cameraShake", 1, percent)
		addToggle(access, "reducedEffects", 2, "settings.reducedEffects.desc")
		addToggle(access, "noFlash", 3, "settings.noFlash.desc")

		Button.new({
			name = "Defaut",
			key = "settings.reset",
			icon = "↺",
			variant = "Dark",
			size = "Small",
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -4),
			parent = modal.Content,
			onActivated = function()
				local settings = settingsController()
				if settings and type(settings.Reset) == "function" then
					pcall(settings.Reset)
				end
			end,
		})

		showPage("audio")
	end

	local function syncControls()
		for key, control in controls do
			local value = getValue(key)
			if value ~= nil then
				control.Set(value, true)
			end
		end
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		if type(args) == "string" and pages[args] then
			tabs.Select(args, true)
			showPage(args)
		end
		syncControls()
		if wasVisible then
			return
		end
		showTrove:Clean()
		modal.Open()
		local settings = settingsController()
		if settings and settings.Changed and type(settings.Changed.Connect) == "function" then
			showTrove:Add(settings.Changed:Connect(function(key: any, value: any)
				local control = controls[key]
				if control and value ~= nil then
					control.Set(value, true)
				end
			end))
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return modal.Close()
	end

	function screen.GetDefaultSelection(_self: any): GuiObject?
		return tabs.GetButton(tabs.GetSelected())
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return Settings

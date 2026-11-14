--!strict
--[[
	LobbyMenu — menu principal (modale) : Jouer, Entraînement, Boutique, Personnaliser, Défis, Réglages,
	interrupteur « regarder la prochaine partie », solde de pièces.

	  Jouer        Accueil : Lobby.Advance (ouvre la préparation) ; Préparation : ouvre le salon (HostSettings) ;
	               pendant une partie : désactivé.
	  Entraînement sous-panneau Driving Range / Tutoriel -> Lobby.RequestTraining("Range" | "Tutorial").
	  Boutique, Personnaliser, Défis : ShopController / CustomizeController / ChallengesController s'ils existent
	               (Open, Show ou Toggle), sinon un toast « bientôt disponible ».
	  Réglages     écran Settings.
	  Spectateur   Match.SetSpectator(bool).
	Retour (B / Échap) : referme le sous-panneau d'entraînement, sinon le menu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Modal = require(UI.Components.Modal)
local Toggle = require(UI.Components.Toggle)
local Util = require(script.Parent.Util)

local LobbyMenu = {}

local function send(name: string, ...: any)
	if not Net.getDefinitions()[name] then
		Log.warn("UI", "remote absent :", name)
		return
	end
	local ok, err = pcall(Net.send, name, ...)
	if not ok then
		Log.warn("UI", "envoi impossible :", name, err)
	end
end

-- Ouvre l'interface d'un autre contrôleur (Open / Show / Toggle), sinon annonce « bientôt disponible ».
local function openFeature(controllerName: string, labelKey: string): boolean
	local controller = Util.controller(controllerName)
	if controller then
		for _, method in { "Open", "Show", "Toggle" } do
			local fn = controller[method]
			if type(fn) == "function" then
				local ok, err = pcall(fn)
				if ok then
					return true
				end
				Log.warn("UI", controllerName .. "." .. method .. " en erreur :", err)
				break
			end
		end
	end
	Util.notify("ui.comingSoon.named", { name = Locale.t(labelKey) }, "info")
	return false
end

function LobbyMenu.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Menu, Modal = true }

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local mainPage: Frame
	local trainingPage: Frame
	local playButton: Button.ButtonApi
	local trainingButton: Button.ButtonApi
	local rangeButton: Button.ButtonApi
	local spectator: Toggle.ToggleApi
	local coinsLabel: TextLabel
	local hint: Label.LabelApi
	local trainingOpen = false

	local function close()
		ctx.Manager.Hide("LobbyMenu")
	end

	local function setTrainingOpen(open: boolean)
		trainingOpen = open
		mainPage.Visible = not open
		trainingPage.Visible = open
		modal.Panel.SetTitleKey(if open then "menu.training.title" else "menu.title")
		task.defer(function()
			ctx.Manager.Focus("LobbyMenu")
		end)
	end

	local function onPlay()
		local phase = ctx.GetPhase()
		if phase == "Preparing" then
			close()
			ctx.Manager.Show("HostSettings", ctx.GetLobbyState())
		elseif phase == "Lobby" then
			send("Lobby.Advance")
			close()
		end
	end

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = "menu.title",
			size = Vector2.new(560, 560),
			onClose = close,
		})
		local content = modal.Content

		-- Page principale -------------------------------------------------------
		mainPage = Instance.new("Frame")
		mainPage.Name = "Principal"
		mainPage.BackgroundTransparency = 1
		mainPage.AutomaticSize = Enum.AutomaticSize.Y
		mainPage.Size = UDim2.new(1, -6, 0, 0)
		Base.list(mainPage, Enum.FillDirection.Vertical, Theme.Spacing.M, Enum.HorizontalAlignment.Center)
		mainPage.Parent = content

		local top = Instance.new("Frame")
		top.Name = "Haut"
		top.BackgroundTransparency = 1
		top.Size = UDim2.new(1, 0, 0, 36)
		top.LayoutOrder = 1
		top.Parent = mainPage

		Label.new({
			name = "SousTitre",
			key = "menu.subtitle",
			style = "Body",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, -150, 1, 0),
			truncate = true,
			parent = top,
		})

		local coins = Instance.new("Frame")
		coins.Name = "Pieces"
		coins.BorderSizePixel = 0
		coins.BackgroundColor3 = Theme.Colors.Primary
		coins.AnchorPoint = Vector2.new(1, 0.5)
		coins.Position = UDim2.fromScale(1, 0.5)
		coins.AutomaticSize = Enum.AutomaticSize.X
		coins.Size = UDim2.fromOffset(0, 34)
		Base.corner(coins, "Pill")
		Base.stroke(coins, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
		Base.padding(coins, nil, 12, 0)
		coins.Parent = top
		coinsLabel = Base.newText("Solde", "Body", "Heavy", Theme.Colors.Ink)
		coinsLabel.AutomaticSize = Enum.AutomaticSize.X
		coinsLabel.Size = UDim2.fromOffset(0, 34)
		coinsLabel.Parent = coins

		playButton = Button.new({
			name = "Jouer",
			key = "menu.play",
			icon = "▶",
			variant = "Success",
			size = "Large",
			fill = true,
			layoutOrder = 2,
			parent = mainPage,
			onActivated = onPlay,
		})

		local grid = Instance.new("Frame")
		grid.Name = "Grille"
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, 2 * (Theme.Touch.Medium + Theme.Touch.Lip) + Theme.Spacing.M)
		grid.LayoutOrder = 3
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0.5, -Theme.Spacing.M / 2, 0, Theme.Touch.Medium + Theme.Touch.Lip)
		gridLayout.CellPadding = UDim2.fromOffset(Theme.Spacing.M, Theme.Spacing.M)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid
		grid.Parent = mainPage

		trainingButton = Button.new({
			name = "Entrainement",
			key = "menu.training",
			icon = "⛳",
			variant = "Secondary",
			fill = true,
			layoutOrder = 1,
			parent = grid,
			onActivated = function()
				setTrainingOpen(true)
			end,
		})
		Button.new({
			name = "Boutique",
			key = "menu.shop",
			icon = "◎",
			variant = "Primary",
			fill = true,
			layoutOrder = 2,
			parent = grid,
			onActivated = function()
				if openFeature("ShopController", "menu.shop") then
					close()
				end
			end,
		})
		Button.new({
			name = "Personnaliser",
			key = "menu.customize",
			icon = "✎",
			variant = "Accent",
			fill = true,
			layoutOrder = 3,
			parent = grid,
			onActivated = function()
				if openFeature("CustomizeController", "menu.customize") then
					close()
				end
			end,
		})
		Button.new({
			name = "Defis",
			key = "menu.challenges",
			icon = "★",
			variant = "Warning",
			fill = true,
			layoutOrder = 4,
			parent = grid,
			onActivated = function()
				if openFeature("ChallengesController", "menu.challenges") then
					close()
				end
			end,
		})

		local bottom = Instance.new("Frame")
		bottom.Name = "Bas"
		bottom.BackgroundTransparency = 1
		bottom.Size = UDim2.new(1, 0, 0, Theme.Touch.Medium + Theme.Touch.Lip)
		bottom.LayoutOrder = 4
		bottom.Parent = mainPage

		Button.new({
			name = "Reglages",
			key = "menu.settings",
			icon = "⚙",
			variant = "Dark",
			width = 210,
			parent = bottom,
			onActivated = function()
				ctx.Manager.Show("Settings")
			end,
		})

		local spectatorRow = Instance.new("Frame")
		spectatorRow.Name = "Spectateur"
		spectatorRow.BackgroundTransparency = 1
		spectatorRow.AnchorPoint = Vector2.new(1, 0)
		spectatorRow.Position = UDim2.fromScale(1, 0)
		spectatorRow.Size = UDim2.new(1, -224, 1, 0)
		spectatorRow.Parent = bottom
		Label.new({
			name = "Libelle",
			key = "menu.spectator",
			style = "Small",
			font = "Bold",
			wrap = true,
			size = UDim2.new(1, -84, 1, 0),
			parent = spectatorRow,
		})
		spectator = Toggle.new({
			name = "Interrupteur",
			showState = false,
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.new(1, 0, 0.5, 0),
			parent = spectatorRow,
			onChanged = function(value: boolean)
				send("Match.SetSpectator", value)
			end,
		})

		hint = Label.new({
			name = "Aide",
			style = "Caption",
			font = "Bold",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 20),
			layoutOrder = 5,
			parent = mainPage,
		})

		-- Sous-page entraînement -----------------------------------------------
		trainingPage = Instance.new("Frame")
		trainingPage.Name = "Entrainement"
		trainingPage.BackgroundTransparency = 1
		trainingPage.AutomaticSize = Enum.AutomaticSize.Y
		trainingPage.Size = UDim2.new(1, -6, 0, 0)
		trainingPage.Visible = false
		Base.list(trainingPage, Enum.FillDirection.Vertical, Theme.Spacing.M, Enum.HorizontalAlignment.Center)
		trainingPage.Parent = content

		Label.new({
			name = "Choix",
			key = "menu.training.pick",
			style = "Heading",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 32),
			layoutOrder = 1,
			parent = trainingPage,
		})

		local function trainingOption(kind: string, icon: string, variant: string, order: number): Button.ButtonApi
			local box = Instance.new("Frame")
			box.Name = "Option" .. kind
			box.BackgroundTransparency = 1
			box.AutomaticSize = Enum.AutomaticSize.Y
			box.Size = UDim2.new(1, 0, 0, 0)
			box.LayoutOrder = order
			Base.list(box, Enum.FillDirection.Vertical, 4)
			box.Parent = trainingPage
			local button = Button.new({
				name = "Bouton",
				key = "lobby.training." .. kind,
				icon = icon,
				variant = variant,
				size = "Large",
				fill = true,
				layoutOrder = 1,
				parent = box,
				onActivated = function()
					send("Lobby.RequestTraining", kind)
					close()
				end,
			})
			Label.new({
				name = "Description",
				key = "lobby.training." .. kind .. ".desc",
				style = "Small",
				color = Theme.Colors.PaperDim,
				alignX = Enum.TextXAlignment.Center,
				layoutOrder = 2,
				parent = box,
			})
			return button
		end
		rangeButton = trainingOption("Range", "⛳", "Success", 2)
		trainingOption("Tutorial", "?", "Secondary", 3)

		Button.new({
			name = "Retour",
			key = "ui.back",
			icon = "◀",
			variant = "Dark",
			size = "Small",
			layoutOrder = 4,
			parent = trainingPage,
			onActivated = function()
				setTrainingOpen(false)
			end,
		})
	end

	local function refresh()
		local phase = ctx.GetPhase()
		if phase == "Preparing" then
			playButton.SetKey("menu.play.lobby")
			playButton.SetEnabled(true)
		elseif phase == "Lobby" then
			playButton.SetKey("menu.play")
			playButton.SetEnabled(true)
		else
			playButton.SetKey("menu.play.inMatch")
			playButton.SetEnabled(false)
		end
		trainingButton.SetEnabled(phase == "Lobby")

		local coins = Util.localPlayer():GetAttribute("Coins")
		coinsLabel.Text = "◎ " .. Locale.t("menu.coins", { coins = if type(coins) == "number" then math.floor(coins) else 0 })

		local spectating = Util.localPlayer():GetAttribute("Spectating")
		spectator.Set(spectating == true, true)

		hint.SetKey(if Base.isGamepad() then "menu.hint.gamepad" else "menu.hint.keyboard")
	end

	function screen.Show(_self: any, _args: any, wasVisible: boolean)
		refresh()
		if wasVisible then
			return
		end
		showTrove:Clean()
		if trainingOpen then
			setTrainingOpen(false)
		end
		modal.Open()
		local player = Util.localPlayer()
		showTrove:Connect(player:GetAttributeChangedSignal("Coins"), refresh)
		showTrove:Connect(player:GetAttributeChangedSignal("Spectating"), refresh)
		showTrove:Connect(ctx.PhaseChanged, refresh)
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return modal.Close()
	end

	function screen.Back(_self: any): boolean
		if trainingOpen then
			setTrainingOpen(false)
			return true
		end
		return false
	end

	function screen.GetDefaultSelection(_self: any): GuiObject?
		if trainingOpen then
			return rangeButton.Instance
		end
		return if playButton.IsEnabled() then playButton.Instance else trainingButton.Instance
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return LobbyMenu

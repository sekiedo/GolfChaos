--!strict
--[[
	Textes des commandes (français). Clés préfixées "controls.".

	controls.key.<Nom> : libellé d'une touche pour InputController.GetKeyCodeLabel / GetKeyLabel
	(Nom = Enum.KeyCode.Name ou Enum.UserInputType.Name). Uniquement les touches spéciales, la souris et la
	manette : ne JAMAIS ajouter de lettre ni de chiffre, leur libellé suit la disposition réelle du clavier
	(AZERTY, QWERTZ...) via UserInputService:GetStringForKeyCode.

	controls.action.<nom> : libellés courts des boutons tactiles et des indicateurs d'action.
]]
return {
	-- Clavier : touches spéciales
	["controls.key.Space"] = "Espace",
	["controls.key.Return"] = "Entrée",
	["controls.key.KeypadEnter"] = "Entrée",
	["controls.key.Tab"] = "Tab",
	["controls.key.Backspace"] = "Retour arrière",
	["controls.key.Escape"] = "Échap",
	["controls.key.LeftShift"] = "Maj",
	["controls.key.RightShift"] = "Maj droite",
	["controls.key.LeftControl"] = "Ctrl",
	["controls.key.RightControl"] = "Ctrl droit",
	["controls.key.LeftAlt"] = "Alt",
	["controls.key.RightAlt"] = "Alt Gr",
	["controls.key.CapsLock"] = "Verr. Maj",
	["controls.key.Delete"] = "Suppr",
	["controls.key.Insert"] = "Inser",
	["controls.key.Home"] = "Début",
	["controls.key.End"] = "Fin",
	["controls.key.PageUp"] = "Page préc.",
	["controls.key.PageDown"] = "Page suiv.",
	["controls.key.Up"] = "↑",
	["controls.key.Down"] = "↓",
	["controls.key.Left"] = "←",
	["controls.key.Right"] = "→",

	-- Souris
	["controls.key.MouseButton1"] = "Clic gauche",
	["controls.key.MouseButton2"] = "Clic droit",
	["controls.key.MouseButton3"] = "Clic molette",
	["controls.key.MouseWheel"] = "Molette",
	["controls.key.MouseMovement"] = "Souris",

	-- Manette (libellés courts)
	["controls.key.ButtonA"] = "A",
	["controls.key.ButtonB"] = "B",
	["controls.key.ButtonX"] = "X",
	["controls.key.ButtonY"] = "Y",
	["controls.key.ButtonL1"] = "LB",
	["controls.key.ButtonR1"] = "RB",
	["controls.key.ButtonL2"] = "LT",
	["controls.key.ButtonR2"] = "RT",
	["controls.key.ButtonL3"] = "LS",
	["controls.key.ButtonR3"] = "RS",
	["controls.key.ButtonStart"] = "Menu",
	["controls.key.ButtonSelect"] = "Vue",
	["controls.key.DPadUp"] = "Croix ↑",
	["controls.key.DPadDown"] = "Croix ↓",
	["controls.key.DPadLeft"] = "Croix ←",
	["controls.key.DPadRight"] = "Croix →",
	["controls.key.Thumbstick1"] = "Stick gauche",
	["controls.key.Thumbstick2"] = "Stick droit",

	-- Actions (boutons tactiles et indicateurs)
	["controls.action.skip"] = "Passer",
	["controls.action.punch"] = "Poing",
	["controls.action.dive"] = "Plonger",
	["controls.action.aim"] = "Viser",
	["controls.action.swing"] = "Frapper",
	["controls.action.cancel"] = "Annuler",
	["controls.action.shotType"] = "Coup",
	["controls.action.lock"] = "Verrou",
	["controls.action.loftUp"] = "Angle +",
	["controls.action.loftDown"] = "Angle −",
	["controls.action.resetBall"] = "Replacer",
	["controls.action.jump"] = "Sauter",
	["controls.action.move"] = "Se déplacer",
	["controls.action.camera"] = "Caméra",
	["controls.action.useItem"] = "Objet",
	["controls.action.items"] = "Objets",
	["controls.action.scoreboard"] = "Scores",
	["controls.action.follow"] = "Reprendre",
}

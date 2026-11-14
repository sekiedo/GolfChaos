--!strict
--[[
	Control texts (English). Keys prefixed "controls.".

	controls.key.<Name>: key label for InputController.GetKeyCodeLabel / GetKeyLabel
	(Name = Enum.KeyCode.Name or Enum.UserInputType.Name). Special keys, mouse and gamepad only: NEVER add a
	letter or a digit, their label follows the real keyboard layout through UserInputService:GetStringForKeyCode.

	controls.action.<name>: short labels of touch buttons and action indicators.
]]
return {
	-- Keyboard: special keys
	["controls.key.Space"] = "Space",
	["controls.key.Return"] = "Enter",
	["controls.key.KeypadEnter"] = "Enter",
	["controls.key.Tab"] = "Tab",
	["controls.key.Backspace"] = "Backspace",
	["controls.key.Escape"] = "Esc",
	["controls.key.LeftShift"] = "Shift",
	["controls.key.RightShift"] = "Right Shift",
	["controls.key.LeftControl"] = "Ctrl",
	["controls.key.RightControl"] = "Right Ctrl",
	["controls.key.LeftAlt"] = "Alt",
	["controls.key.RightAlt"] = "Alt Gr",
	["controls.key.CapsLock"] = "Caps Lock",
	["controls.key.Delete"] = "Del",
	["controls.key.Insert"] = "Ins",
	["controls.key.Home"] = "Home",
	["controls.key.End"] = "End",
	["controls.key.PageUp"] = "Page Up",
	["controls.key.PageDown"] = "Page Down",
	["controls.key.Up"] = "↑",
	["controls.key.Down"] = "↓",
	["controls.key.Left"] = "←",
	["controls.key.Right"] = "→",

	-- Mouse
	["controls.key.MouseButton1"] = "Left click",
	["controls.key.MouseButton2"] = "Right click",
	["controls.key.MouseButton3"] = "Middle click",
	["controls.key.MouseWheel"] = "Wheel",
	["controls.key.MouseMovement"] = "Mouse",

	-- Gamepad (short labels)
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
	["controls.key.ButtonSelect"] = "View",
	["controls.key.DPadUp"] = "D-pad ↑",
	["controls.key.DPadDown"] = "D-pad ↓",
	["controls.key.DPadLeft"] = "D-pad ←",
	["controls.key.DPadRight"] = "D-pad →",
	["controls.key.Thumbstick1"] = "Left stick",
	["controls.key.Thumbstick2"] = "Right stick",

	-- Actions (touch buttons and indicators)
	["controls.action.skip"] = "Skip",
	["controls.action.punch"] = "Punch",
	["controls.action.dive"] = "Dive",
	["controls.action.aim"] = "Aim",
	["controls.action.swing"] = "Swing",
	["controls.action.cancel"] = "Cancel",
	["controls.action.shotType"] = "Shot",
	["controls.action.lock"] = "Lock",
	["controls.action.loftUp"] = "Loft +",
	["controls.action.loftDown"] = "Loft −",
	["controls.action.resetBall"] = "Reset",
	["controls.action.jump"] = "Jump",
	["controls.action.move"] = "Move",
	["controls.action.camera"] = "Camera",
	["controls.action.useItem"] = "Item",
	["controls.action.items"] = "Items",
	["controls.action.scoreboard"] = "Scores",
	["controls.action.follow"] = "Resume",
}

--!strict
-- Aiming, golf and ball texts (English). Keys prefixed "aim.".
-- Used by GolfAimController, BallVisualController, ActionController and UI/AimPanel.
return {
	-- Shot types (AimPanel:SetShotType receives the type id)
	["aim.shot.Drive"] = "Drive",
	["aim.shot.Chip"] = "Chip",
	["aim.shot.Putt"] = "Putt",
	["aim.shot.Guided"] = "Guided shot",
	["aim.shot.suggested"] = "Putt suggested",

	-- Prompts
	["aim.prompt.enter"] = "{key}: aim",
	["aim.prompt.enterTouch"] = "Tap “{button}” to aim",
	["aim.prompt.resetConfirm"] = "Press {key} again to reset your ball (penalty: +{n})",
	["aim.prompt.resetConfirmFree"] = "Press {key} again to reset your ball",
	["aim.prompt.resetHold"] = "Hold {key} to reset a stuck ball",
	["aim.prompt.resetHolding"] = "Resetting your ball…",
	["aim.prompt.practice"] = "Practice: strokes don't count",
	["aim.prompt.goToBall"] = "Walk to your ball to swing",
	["aim.prompt.following"] = "{key}: take back control",

	-- Contextual help while aiming
	["aim.hint.kbm"] = "{rotate}: turn • {loft}: loft • {shot}: shot type • {lock} (hold): guided shot • {swing}: power meter • {cancel}: cancel • {reset}: reset ball",
	["aim.hint.gamepad"] = "{rotate}: turn • {loft}: loft • {shot}: shot type • {lock} (hold): guided shot • {swing}: power meter • {cancel}: cancel • {reset}: reset ball",
	["aim.hint.touch"] = "Drag to turn • {loftUp} / {loftDown}: loft • swing button: start the power meter",
	["aim.hint.charge"] = "{swing} at the right moment to hit • {cancel}: back to aiming",
	["aim.hint.chargeTouch"] = "Tap the swing button again at the right moment!",
	["aim.hint.rotateMouse"] = "Right-click + drag or {left} {right}",
	["aim.hint.loftKeys"] = "Wheel or {up} {down}",
	["aim.hint.pair"] = "{a} / {b}",
	["aim.hint.aimKbm"] = "{rotate}: turn • {loft}: loft • {shot}: shot type • {swing}: power meter • {cancel}: cancel",
	["aim.hint.aimGamepad"] = "Right stick: turn • {loft}: loft • {shot}: shot type • {swing}: power meter • {cancel}: cancel",
	["aim.hint.aimTouch"] = "Drag to turn • Loft and Shot buttons • Swing: start the power meter",
	["aim.hint.rotateKbm"] = "Right-click + drag / {left} {right}",
	["aim.hint.loftKbm"] = "Wheel / {up} {down}",

	-- Guided shot (lock-on)
	["aim.lock.reticle"] = "◎ {name}",
	["aim.lock.none"] = "No target: aim at an opponent",
	["aim.lock.practice"] = "No guided shots while practising",
	["aim.lock.disabled"] = "Guided shot unavailable",
	["aim.lock.cooldown"] = "Guided shot ready in {n} s",

	-- Putting
	["aim.putt.unavailable"] = "Putting is only allowed on the green or within {n} studs of the hole",

	-- Aim panel (UI/AimPanel)
	["aim.panel.power"] = "POWER",
	["aim.panel.powerValue"] = "{n}%",
	["aim.panel.loft"] = "Loft {n}°",
	["aim.panel.loftTitle"] = "LOFT",
	["aim.panel.distance"] = "≈ {n} studs",
	["aim.panel.distanceUnknown"] = "Distance ?",
	["aim.panel.windTitle"] = "WIND",
	["aim.panel.wind"] = "{n}",
	["aim.panel.windCalm"] = "Calm",
	["aim.panel.shotTitle"] = "SHOT",
	["aim.panel.charging"] = "Hit at the right moment!",
	["aim.panel.sweetSpot"] = "Sweet spot",
	["aim.panel.bandLow"] = "Soft",
	["aim.panel.bandMid"] = "Medium",
	["aim.panel.bandHigh"] = "Strong",
	["aim.panel.bandMax"] = "Max",

	-- Shot feedback
	["aim.shot.accepted"] = "Stroke {n}",
	["aim.shot.acceptedPractice"] = "Practice stroke",
	["aim.shot.forced"] = "Forced swing!",

	-- Aim cancelled by the server (Golf.AimCancelled)
	["aim.cancel.stun"] = "You're knocked out: aim cancelled",
	["aim.cancel.horn"] = "The horn broke your focus!",
	["aim.cancel.too_far"] = "Too far from your ball",
	["aim.cancel.invalid"] = "Shot refused",
	["aim.cancel.unavailable"] = "You can't swing right now",
	["aim.cancel.respawn"] = "Your ball was moved",
	["aim.cancel.phase"] = "Aim cancelled: the hole is over",
	["aim.cancel.no_target"] = "No valid target for the guided shot",
	["aim.cancel.cooldown"] = "Wait a moment before swinging again",
	["aim.cancel.ball_moving"] = "Your ball is still rolling",
	["aim.cancel.ball_frozen"] = "Your ball is frozen!",
	["aim.cancel.finished"] = "You've finished this hole",
	["aim.cancel.vehicle"] = "Leave the cart to swing",
	["aim.cancel.status"] = "You can't aim right now",
	["aim.cancel.blocked"] = "Aiming blocked for a moment",
	["aim.cancel.putt_not_allowed"] = "Putt refused: too far from the green",
	["aim.cancel.guided_cooldown"] = "Guided shot recharging",
	["aim.cancel.knocked"] = "You're knocked out",
	["aim.cancel.default"] = "Aim cancelled",

	-- Ball reset (Golf.BallReset)
	["aim.reset.water"] = "Splash! Ball reset",
	["aim.reset.oob"] = "Out of bounds! Ball reset",
	["aim.reset.lava"] = "Lava! Ball reset",
	["aim.reset.void"] = "Into the void! Ball reset",
	["aim.reset.stuck"] = "Ball reset",
	["aim.reset.generic"] = "Ball reset",
	["aim.reset.penalty"] = "{text} (+{n} stroke)",
	["aim.reset.penaltyMany"] = "{text} (+{n} strokes)",

	-- Balls (BallVisualController)
	["aim.ball.yours"] = "Your ball",
	["aim.ball.offscreen"] = "Your ball · {n} studs",
	["aim.ball.ready"] = "Ready!",
	["aim.ball.distance"] = "{n} studs",

	-- Tags on other players' balls (team marker readable without colour)
	["aim.ballTag.unknown"] = "Ball",
	["aim.ballTag.team"] = "{glyph} {team} team",
	["aim.ballTag.name"] = "{name}",
	["aim.ballTag.teamName"] = "{glyph} {name}",
	["aim.team.Red"] = "Red",
	["aim.team.Blue"] = "Blue",

	-- Combat (ActionController, Combat.Feedback)
	["aim.combat.cooldown"] = "Not so fast!",
	["aim.combat.knocked"] = "You're knocked out",
	["aim.combat.busy"] = "Can't do that now",
	["aim.combat.finished"] = "You've finished the hole",
	["aim.combat.miss"] = "Missed!",
	["aim.combat.shield"] = "Blocked by a shield!",
	["aim.combat.protected"] = "That player is protected",
	["aim.combat.ally"] = "That's a teammate!",
	["aim.combat.phase"] = "No fighting right now",
	["aim.combat.hit"] = "Bam!",
	["aim.combat.default"] = "Action refused",
}

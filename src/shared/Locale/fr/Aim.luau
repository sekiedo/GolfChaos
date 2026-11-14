--!strict
-- Textes de la visée, du golf et des balles (français). Clés préfixées "aim.".
-- Utilisés par GolfAimController, BallVisualController, ActionController et UI/AimPanel.
return {
	-- Types de frappe (AimPanel:SetShotType reçoit l'identifiant du type)
	["aim.shot.Drive"] = "Drive",
	["aim.shot.Chip"] = "Coup lobé",
	["aim.shot.Putt"] = "Putt",
	["aim.shot.Guided"] = "Tir guidé",
	["aim.shot.suggested"] = "Putt conseillé",

	-- Invites
	["aim.prompt.enter"] = "{key} : viser",
	["aim.prompt.enterTouch"] = "Touche « {button} » pour viser",
	["aim.prompt.resetConfirm"] = "Appuie encore sur {key} pour replacer ta balle (pénalité : +{n})",
	["aim.prompt.resetConfirmFree"] = "Appuie encore sur {key} pour replacer ta balle",
	["aim.prompt.resetHold"] = "Maintiens {key} pour replacer ta balle bloquée",
	["aim.prompt.resetHolding"] = "Replacement de la balle…",
	["aim.prompt.practice"] = "Entraînement : coups non comptés",
	["aim.prompt.goToBall"] = "Rejoins ta balle pour frapper",
	["aim.prompt.following"] = "{key} : reprendre la main",

	-- Aides contextuelles pendant la visée
	["aim.hint.kbm"] = "{rotate} : orienter • {loft} : angle • {shot} : type de coup • {lock} (maintenir) : tir guidé • {swing} : jauge • {cancel} : annuler • {reset} : replacer la balle",
	["aim.hint.gamepad"] = "{rotate} : orienter • {loft} : angle • {shot} : type de coup • {lock} (maintenir) : tir guidé • {swing} : jauge • {cancel} : annuler • {reset} : replacer la balle",
	["aim.hint.touch"] = "Glisse pour orienter • {loftUp} / {loftDown} : angle • bouton de frappe : lancer la jauge",
	["aim.hint.charge"] = "{swing} au bon moment pour frapper • {cancel} : revenir à la visée",
	["aim.hint.chargeTouch"] = "Touche encore le bouton de frappe au bon moment !",
	["aim.hint.rotateMouse"] = "Clic droit + glisser ou {left} {right}",
	["aim.hint.loftKeys"] = "Molette ou {up} {down}",
	["aim.hint.pair"] = "{a} / {b}",
	["aim.hint.aimKbm"] = "{rotate} : orienter • {loft} : angle • {shot} : type de coup • {swing} : jauge • {cancel} : annuler",
	["aim.hint.aimGamepad"] = "Stick droit : orienter • {loft} : angle • {shot} : type de coup • {swing} : jauge • {cancel} : annuler",
	["aim.hint.aimTouch"] = "Glisse pour orienter • boutons Angle et Coup • Frapper : lancer la jauge",
	["aim.hint.rotateKbm"] = "Clic droit + glisser / {left} {right}",
	["aim.hint.loftKbm"] = "Molette / {up} {down}",

	-- Tir guidé (verrouillage)
	["aim.lock.reticle"] = "◎ {name}",
	["aim.lock.none"] = "Aucune cible : vise un adversaire",
	["aim.lock.practice"] = "Pas de tir guidé à l'entraînement",
	["aim.lock.disabled"] = "Tir guidé indisponible",
	["aim.lock.cooldown"] = "Tir guidé prêt dans {n} s",

	-- Putt
	["aim.putt.unavailable"] = "Putt possible seulement sur le green ou à moins de {n} studs du trou",

	-- Panneau de visée (UI/AimPanel)
	["aim.panel.power"] = "PUISSANCE",
	["aim.panel.powerValue"] = "{n} %",
	["aim.panel.loft"] = "Angle {n}°",
	["aim.panel.loftTitle"] = "ANGLE",
	["aim.panel.distance"] = "≈ {n} studs",
	["aim.panel.distanceUnknown"] = "Distance ?",
	["aim.panel.windTitle"] = "VENT",
	["aim.panel.wind"] = "{n}",
	["aim.panel.windCalm"] = "Calme",
	["aim.panel.shotTitle"] = "COUP",
	["aim.panel.charging"] = "Frappe au bon moment !",
	["aim.panel.sweetSpot"] = "Zone idéale",
	["aim.panel.bandLow"] = "Doux",
	["aim.panel.bandMid"] = "Moyen",
	["aim.panel.bandHigh"] = "Fort",
	["aim.panel.bandMax"] = "Max",

	-- Retours de frappe
	["aim.shot.accepted"] = "Coup n° {n}",
	["aim.shot.acceptedPractice"] = "Coup d'entraînement",
	["aim.shot.forced"] = "Frappe forcée !",

	-- Visée annulée par le serveur (Golf.AimCancelled)
	["aim.cancel.stun"] = "Tu es KO : visée annulée",
	["aim.cancel.horn"] = "La corne t'a déconcentré !",
	["aim.cancel.too_far"] = "Trop loin de ta balle",
	["aim.cancel.invalid"] = "Frappe refusée",
	["aim.cancel.unavailable"] = "Tu ne peux pas frapper pour le moment",
	["aim.cancel.respawn"] = "Ta balle a été replacée",
	["aim.cancel.phase"] = "Visée annulée : le trou est terminé",
	["aim.cancel.no_target"] = "Aucune cible valide pour le tir guidé",
	["aim.cancel.cooldown"] = "Patiente un instant avant de refrapper",
	["aim.cancel.ball_moving"] = "Ta balle roule encore",
	["aim.cancel.ball_frozen"] = "Ta balle est gelée !",
	["aim.cancel.finished"] = "Tu as terminé ce trou",
	["aim.cancel.vehicle"] = "Descends de la voiturette pour frapper",
	["aim.cancel.status"] = "Impossible de viser dans cet état",
	["aim.cancel.blocked"] = "Visée bloquée un instant",
	["aim.cancel.putt_not_allowed"] = "Putt refusé : trop loin du green",
	["aim.cancel.guided_cooldown"] = "Tir guidé en recharge",
	["aim.cancel.knocked"] = "Tu es KO",
	["aim.cancel.default"] = "Visée annulée",

	-- Balle replacée (Golf.BallReset)
	["aim.reset.water"] = "Plouf ! Balle replacée",
	["aim.reset.oob"] = "Hors limites ! Balle replacée",
	["aim.reset.lava"] = "Lave ! Balle replacée",
	["aim.reset.void"] = "Dans le vide ! Balle replacée",
	["aim.reset.stuck"] = "Balle replacée",
	["aim.reset.generic"] = "Balle replacée",
	["aim.reset.penalty"] = "{text} (+{n} coup)",
	["aim.reset.penaltyMany"] = "{text} (+{n} coups)",

	-- Balles (BallVisualController)
	["aim.ball.yours"] = "Ta balle",
	["aim.ball.offscreen"] = "Ta balle · {n} studs",
	["aim.ball.ready"] = "Prête !",
	["aim.ball.distance"] = "{n} studs",

	-- Étiquettes des balles des autres joueurs (repère d'équipe lisible sans la couleur)
	["aim.ballTag.unknown"] = "Balle",
	["aim.ballTag.team"] = "{glyph} Équipe {team}",
	["aim.ballTag.name"] = "{name}",
	["aim.ballTag.teamName"] = "{glyph} {name}",
	["aim.team.Red"] = "rouge",
	["aim.team.Blue"] = "bleue",

	-- Combat (ActionController, Combat.Feedback)
	["aim.combat.cooldown"] = "Pas si vite !",
	["aim.combat.knocked"] = "Tu es KO",
	["aim.combat.busy"] = "Impossible maintenant",
	["aim.combat.finished"] = "Tu as terminé le trou",
	["aim.combat.miss"] = "Raté !",
	["aim.combat.shield"] = "Bloqué par un bouclier !",
	["aim.combat.protected"] = "Ce joueur est protégé",
	["aim.combat.ally"] = "C'est un coéquipier !",
	["aim.combat.phase"] = "Pas de combat maintenant",
	["aim.combat.hit"] = "Bam !",
	["aim.combat.default"] = "Action refusée",
}

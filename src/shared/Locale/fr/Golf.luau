--!strict
-- Messages envoyés par BallService (français). Clés : golf.aimCancelled.*, golf.reset.*, golf.lipOut, golf.ball.*, golf.penalty.*
return {
	["golf.aimCancelled.stun"] = "Tu es sonné : visée annulée.",
	["golf.aimCancelled.horn"] = "La corne t'a fait tirer !",
	["golf.aimCancelled.too_far"] = "Tu es trop loin de ta balle.",
	["golf.aimCancelled.invalid"] = "Coup impossible, réessaie.",
	["golf.aimCancelled.unavailable"] = "Tu ne peux pas frapper maintenant.",
	["golf.aimCancelled.respawn"] = "Visée annulée : tu as réapparu.",
	["golf.aimCancelled.phase"] = "Ce n'est pas le moment de frapper.",
	["golf.aimCancelled.no_target"] = "Aucune cible pour le tir guidé.",
	["golf.aimCancelled.ball_moving"] = "Ta balle roule encore.",
	["golf.aimCancelled.ball_frozen"] = "Ta balle est gelée !",
	["golf.aimCancelled.finished"] = "Trou terminé !",
	["golf.aimCancelled.vehicle"] = "Impossible de viser depuis le kart.",
	["golf.aimCancelled.status"] = "Un effet t'empêche de viser.",
	["golf.aimCancelled.blocked"] = "Visée bloquée un instant.",
	["golf.aimCancelled.cooldown"] = "Pas si vite !",
	["golf.aimCancelled.putt_not_allowed"] = "Putt impossible ici : rapproche-toi du green.",
	["golf.aimCancelled.guided_cooldown"] = "Tir guidé en recharge.",

	["golf.reset.water"] = "Plouf ! Ta balle est dans l'eau.",
	["golf.reset.oob"] = "Hors limites : balle replacée.",
	["golf.reset.lava"] = "Trop chaud ! Balle replacée.",
	["golf.reset.void"] = "Balle tombée dans le vide : replacée.",
	["golf.reset.stuck"] = "Balle coincée : replacée.",
	["golf.reset.refused"] = "Tu ne peux pas replacer ta balle maintenant.",
	["golf.reset.generic"] = "Balle replacée.",

	["golf.lipOut"] = "Presque ! La balle ressort du trou.",
	["golf.ball.frozen"] = "Balle gelée pendant {n} s",
	["golf.penalty.added"] = "+{n} coup(s) de pénalité",
}

--!strict
-- Textes de l'interface en jeu (français). Clés préfixées "hud.". Utilisés par HUDController et UI/Hud/*.
return {
	-- Carte du trou
	["hud.hole"] = "Trou {n}/{total}",
	["hud.holeSingle"] = "Trou {n}",
	["hud.par"] = "Par {n}",
	["hud.strokes"] = "Coups",
	["hud.strokesValue"] = "{n}",
	["hud.toPar.even"] = "Au par",
	["hud.toPar.under"] = "{n} sous le par",
	["hud.toPar.over"] = "{n} au-dessus du par",
	["hud.holeNameUnknown"] = "Trou mystère",

	-- Chronomètre et phases
	["hud.phase.HoleIntro"] = "Présentation",
	["hud.phase.Countdown"] = "Prêts ?",
	["hud.phase.Playing"] = "Temps restant",
	["hud.phase.HoleEnd"] = "Trou terminé",
	["hud.timer.none"] = "--:--",
	["hud.overtime.title"] = "PROLONGATION !",
	["hud.overtime.body"] = "Termine le trou avant la fin : {time}",

	-- Informations (vent, distance, position)
	["hud.wind.title"] = "VENT",
	["hud.wind.calm"] = "Calme",
	["hud.wind.value"] = "{n}",
	["hud.wind.light"] = "Léger",
	["hud.wind.strong"] = "Fort",
	["hud.distance.title"] = "TROU",
	["hud.distance.value"] = "{n} studs",
	["hud.distance.unknown"] = "—",
	["hud.position.title"] = "PLACE",
	["hud.position.value"] = "{rank} / {total}",
	["hud.position.finished"] = "Arrivé !",

	-- Ordinaux
	["hud.ordinal.1"] = "1er",
	["hud.ordinal.n"] = "{n}e",

	-- Tableau des scores
	["hud.scoreboard.title"] = "JOUEURS",
	["hud.scoreboard.done"] = "✓",
	["hud.scoreboard.playing"] = "•",
	["hud.scoreboard.you"] = "{name} (toi)",
	["hud.scoreboard.more"] = "+{n} autres",
	["hud.scoreboard.strokes"] = "{n}",
	["hud.scoreboard.empty"] = "En attente des joueurs…",

	-- Fil d'événements
	["hud.feed.holed"] = "{name} a réussi en {n} coups",
	["hud.feed.holedOne"] = "{name} a réussi en 1 coup",
	["hud.feed.holeInOne"] = "{name} : TROU EN UN !",
	["hud.feed.finished"] = "{name} termine {order} ({n} coups)",
	["hud.feed.ko"] = "{attacker} a mis {victim} KO",
	["hud.feed.koAlone"] = "{victim} est KO",
	["hud.feed.someone"] = "Quelqu'un",

	-- Barre d'aide des commandes
	["hud.controls.kbm"] = "{move} : bouger • {jump} : sauter • {aim} : viser • {punch} : poing • {dive} : plonger • {reset} (maintenir) : replacer la balle",
	["hud.controls.gamepad"] = "{jump} : sauter • {aim} : viser • {punch} : poing • {dive} : plonger • {reset} (maintenir) : replacer la balle",
	["hud.controls.touch"] = "Approche-toi de ta balle et touche « {aim} » • {punch} / {dive} : combat",
	["hud.controls.move"] = "ZQSD / WASD",

	-- Inventaire
	["hud.inventory.title"] = "OBJETS",
	["hud.inventory.empty"] = "Vide",
	["hud.inventory.slot"] = "{n}",

	-- Entraînement (accueil)
	["hud.practice.title"] = "ENTRAÎNEMENT",
	["hud.practice.body"] = "Frappe librement : les coups ne comptent pas",
	["hud.practice.strokes"] = "Coups d'essai : {n}",
}

--!strict
-- In-game interface texts (English). Keys prefixed "hud.". Used by HUDController and UI/Hud/*.
return {
	-- Hole card
	["hud.hole"] = "Hole {n}/{total}",
	["hud.holeSingle"] = "Hole {n}",
	["hud.par"] = "Par {n}",
	["hud.strokes"] = "Strokes",
	["hud.strokesValue"] = "{n}",
	["hud.toPar.even"] = "Even par",
	["hud.toPar.under"] = "{n} under par",
	["hud.toPar.over"] = "{n} over par",
	["hud.holeNameUnknown"] = "Mystery hole",

	-- Timer and phases
	["hud.phase.HoleIntro"] = "Presenting",
	["hud.phase.Countdown"] = "Ready?",
	["hud.phase.Playing"] = "Time left",
	["hud.phase.HoleEnd"] = "Hole over",
	["hud.timer.none"] = "--:--",
	["hud.overtime.title"] = "OVERTIME!",
	["hud.overtime.body"] = "Finish the hole before time runs out: {time}",

	-- Info (wind, distance, position)
	["hud.wind.title"] = "WIND",
	["hud.wind.calm"] = "Calm",
	["hud.wind.value"] = "{n}",
	["hud.wind.light"] = "Light",
	["hud.wind.strong"] = "Strong",
	["hud.distance.title"] = "HOLE",
	["hud.distance.value"] = "{n} studs",
	["hud.distance.unknown"] = "—",
	["hud.position.title"] = "PLACE",
	["hud.position.value"] = "{rank} / {total}",
	["hud.position.finished"] = "Finished!",

	-- Ordinals
	["hud.ordinal.1"] = "1st",
	["hud.ordinal.2"] = "2nd",
	["hud.ordinal.3"] = "3rd",
	["hud.ordinal.n"] = "{n}th",

	-- Scoreboard
	["hud.scoreboard.title"] = "PLAYERS",
	["hud.scoreboard.done"] = "✓",
	["hud.scoreboard.playing"] = "•",
	["hud.scoreboard.you"] = "{name} (you)",
	["hud.scoreboard.more"] = "+{n} more",
	["hud.scoreboard.strokes"] = "{n}",
	["hud.scoreboard.empty"] = "Waiting for players…",

	-- Event feed
	["hud.feed.holed"] = "{name} holed out in {n} strokes",
	["hud.feed.holedOne"] = "{name} holed out in 1 stroke",
	["hud.feed.holeInOne"] = "{name}: HOLE IN ONE!",
	["hud.feed.finished"] = "{name} finishes {order} ({n} strokes)",
	["hud.feed.ko"] = "{attacker} knocked out {victim}",
	["hud.feed.koAlone"] = "{victim} is knocked out",
	["hud.feed.someone"] = "Someone",

	-- Controls hint bar
	["hud.controls.kbm"] = "{move}: move • {jump}: jump • {aim}: aim • {punch}: punch • {dive}: dive • {reset} (hold): reset ball",
	["hud.controls.gamepad"] = "{jump}: jump • {aim}: aim • {punch}: punch • {dive}: dive • {reset} (hold): reset ball",
	["hud.controls.touch"] = "Walk to your ball and tap “{aim}” • {punch} / {dive}: fight",
	["hud.controls.move"] = "WASD",

	-- Inventory
	["hud.inventory.title"] = "ITEMS",
	["hud.inventory.empty"] = "Empty",
	["hud.inventory.slot"] = "{n}",

	-- Practice (lobby)
	["hud.practice.title"] = "PRACTICE",
	["hud.practice.body"] = "Swing freely: strokes don't count",
	["hud.practice.strokes"] = "Practice strokes: {n}",
}

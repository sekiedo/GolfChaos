--!strict
-- Menus and phase screens: main menu, host lobby, banner, loading, hole intro, countdown. Domain "menu".
return {
	-- Main menu (lobby)
	["menu.title"] = "Golf Chaos",
	["menu.subtitle"] = "The golf game where anything can happen",
	["menu.play"] = "Play",
	["menu.play.lobby"] = "Match lobby",
	["menu.play.inMatch"] = "Match in progress",
	["menu.training"] = "Training",
	["menu.shop"] = "Shop",
	["menu.customize"] = "Customize",
	["menu.challenges"] = "Challenges",
	["menu.settings"] = "Settings",
	["menu.spectator"] = "Watch the next match",
	["menu.resume"] = "Resume",
	["menu.coins"] = "{coins} coins",
	["menu.button"] = "Menu",
	["menu.hint.keyboard"] = "M: menu   ·   Esc: back",
	["menu.hint.gamepad"] = "Start: menu   ·   B: back",
	["menu.training.title"] = "Training",
	["menu.training.pick"] = "Choose your training",

	-- Lobby (preparing)
	["menu.host.sectionGame"] = "Match",
	["menu.host.sectionRules"] = "Rules",
	["menu.host.sectionPlayers"] = "Players",
	["menu.host.readOnly"] = "Only the host can change the settings",
	["menu.host.youTag"] = "YOU",
	["menu.host.hostTag"] = "HOST",
	["menu.host.waitingReady"] = "Waiting for players to be ready…",
	["menu.host.canStart"] = "All set: you can start!",
	["menu.host.syncing"] = "Syncing the lobby…",
	["menu.host.customPlaylist"] = "Selection: {count} hole(s)",
	["menu.host.biomesAll"] = "All biomes",
	["menu.host.teamLocked"] = "Teams are only used in Teams mode",
	["menu.host.reopen"] = "Lobby",

	-- Phase banner
	["menu.banner.lobby"] = "Lobby",
	["menu.banner.preparing"] = "Preparing the match",
	["menu.banner.timer"] = "{time}",
	["menu.banner.host"] = "Host: {name}",
	["menu.banner.noHost"] = "No host",

	-- Loading
	["menu.loading.title"] = "Loading…",
	["menu.loading.tip"] = "Tip",
	["menu.tip.1"] = "Hold the swing longer for a stronger shot: release at the right moment!",
	["menu.tip.2"] = "Wind pushes your ball in flight: check the arrow before you swing.",
	["menu.tip.3"] = "The first players to reach the cup score the most points.",
	["menu.tip.4"] = "A well-placed punch costs an opponent time… but they can hit back!",
	["menu.tip.5"] = "Item boxes give better items to players who are behind.",
	["menu.tip.6"] = "A cart gets you to your ball faster, but watch the corners!",
	["menu.tip.7"] = "Landing in water costs a penalty stroke: aim for the fairway.",
	["menu.tip.8"] = "On the green, hit softly: the ball rolls a long way.",
	["menu.tip.9"] = "A hole in one earns a big points bonus.",
	["menu.tip.10"] = "In Teams mode, help your allies: every finish counts for the team.",
	["menu.tip.11"] = "Sand slows the ball down, ice makes it slide.",
	["menu.tip.12"] = "Accessibility options (reduced effects, no flashes) are in the Settings menu.",

	-- Hole intro
	["menu.intro.biome"] = "Biome: {biome}",
	["menu.intro.mode"] = "{mode}",
	["menu.intro.difficulty"] = "Difficulty",

	-- Countdown
	["menu.countdown.3"] = "3",
	["menu.countdown.2"] = "2",
	["menu.countdown.1"] = "1",
}

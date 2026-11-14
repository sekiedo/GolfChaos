--!strict
--[[
	Logic.MatchStateMachine — machine à états PURE de la partie (docs/ARCHITECTURE.md §7).

	  Lobby → Preparing → Loading → HoleIntro → Countdown → Playing → HoleEnd → HoleResults
	        → (Loading du trou suivant | Podium) → Lobby

	Transitions exceptionnelles (toutes documentées dans Transitions) :
	  - Preparing → Lobby          : l'hôte annule, préparation trop longue, salon vide ;
	  - toute phase de partie → Lobby : partie interrompue (MatchService.Abort : plus aucun participant, erreur) ;
	  - Loading → Podium           : plus aucun trou chargeable alors qu'au moins un trou a été joué.

	API (aucune dépendance moteur, aucun effet de bord) :
	  MatchStateMachine.Phases                       -> { Phase } dans l'ordre du parcours normal
	  MatchStateMachine.isPhase(value)               -> boolean
	  MatchStateMachine.canTransition(from, to)      -> boolean   (table Transitions ; pas de transition vers soi)
	  MatchStateMachine.allowedFrom(phase)           -> { Phase } (triées dans l'ordre de Phases)
	  MatchStateMachine.nextAfterResults(holeIndex, holeCount) -> "Loading" | "Podium"
	  MatchStateMachine.nextPhase(phase, holeIndex?, holeCount?) -> Phase  (parcours normal)
	  MatchStateMachine.isMatchPhase(phase)          -> boolean   (une partie est en cours : Loading..Podium)
	  MatchStateMachine.isHolePhase(phase)           -> boolean   (un trou est chargé : Loading..HoleResults)
	  MatchStateMachine.allowsSettingsChange(phase)  -> boolean   (Lobby, Preparing uniquement)
]]

local Types = require(script.Parent.Parent.Types)

type Phase = Types.Phase

local MatchStateMachine = {}

MatchStateMachine.Phases = {
	"Lobby",
	"Preparing",
	"Loading",
	"HoleIntro",
	"Countdown",
	"Playing",
	"HoleEnd",
	"HoleResults",
	"Podium",
} :: { Phase }

-- Table des transitions autorisées : Transitions[de][vers] = true. Toute autre transition est refusée.
MatchStateMachine.Transitions = {
	Lobby = { Preparing = true },
	Preparing = { Loading = true, Lobby = true },
	Loading = { HoleIntro = true, Podium = true, Lobby = true },
	HoleIntro = { Countdown = true, Lobby = true },
	Countdown = { Playing = true, Lobby = true },
	Playing = { HoleEnd = true, Lobby = true },
	HoleEnd = { HoleResults = true, Lobby = true },
	HoleResults = { Loading = true, Podium = true, Lobby = true },
	Podium = { Lobby = true },
} :: { [string]: { [string]: boolean } }

local PHASE_INDEX: { [string]: number } = {}
for index, phase in MatchStateMachine.Phases do
	PHASE_INDEX[phase] = index
end

local MATCH_PHASES: { [string]: boolean } = {
	Loading = true,
	HoleIntro = true,
	Countdown = true,
	Playing = true,
	HoleEnd = true,
	HoleResults = true,
	Podium = true,
}

local HOLE_PHASES: { [string]: boolean } = {
	Loading = true,
	HoleIntro = true,
	Countdown = true,
	Playing = true,
	HoleEnd = true,
	HoleResults = true,
}

local SETTINGS_PHASES: { [string]: boolean } = {
	Lobby = true,
	Preparing = true,
}

function MatchStateMachine.isPhase(value: any): boolean
	return type(value) == "string" and PHASE_INDEX[value] ~= nil
end

function MatchStateMachine.canTransition(from: any, to: any): boolean
	if not MatchStateMachine.isPhase(from) or not MatchStateMachine.isPhase(to) then
		return false
	end
	if from == to then
		return false
	end
	local allowed = MatchStateMachine.Transitions[from]
	return allowed ~= nil and allowed[to] == true
end

function MatchStateMachine.allowedFrom(phase: any): { Phase }
	local result: { Phase } = {}
	if not MatchStateMachine.isPhase(phase) then
		return result
	end
	for _, candidate in MatchStateMachine.Phases do
		if MatchStateMachine.canTransition(phase, candidate) then
			table.insert(result, candidate)
		end
	end
	return result
end

-- Après le tableau des résultats : trou suivant tant qu'il en reste, sinon podium.
-- Toute valeur invalide (index ou nombre de trous non entiers, nuls, NaN) mène au podium : jamais de boucle infinie.
function MatchStateMachine.nextAfterResults(holeIndex: number, holeCount: number): Phase
	local validIndex = type(holeIndex) == "number" and holeIndex == holeIndex and holeIndex >= 1 and holeIndex < math.huge
	local validCount = type(holeCount) == "number" and holeCount == holeCount and holeCount >= 1 and holeCount < math.huge
	if validIndex and validCount and math.floor(holeIndex) < math.floor(holeCount) then
		return "Loading"
	end
	return "Podium"
end

-- Phase suivante du parcours normal (sans les transitions exceptionnelles).
function MatchStateMachine.nextPhase(phase: Phase, holeIndex: number?, holeCount: number?): Phase
	if phase == "Lobby" then
		return "Preparing"
	elseif phase == "Preparing" then
		return "Loading"
	elseif phase == "Loading" then
		return "HoleIntro"
	elseif phase == "HoleIntro" then
		return "Countdown"
	elseif phase == "Countdown" then
		return "Playing"
	elseif phase == "Playing" then
		return "HoleEnd"
	elseif phase == "HoleEnd" then
		return "HoleResults"
	elseif phase == "HoleResults" then
		return MatchStateMachine.nextAfterResults(holeIndex or 0, holeCount or 0)
	end
	return "Lobby" -- Podium (et toute valeur inattendue) : retour à l'accueil
end

function MatchStateMachine.isMatchPhase(phase: any): boolean
	return type(phase) == "string" and MATCH_PHASES[phase] == true
end

function MatchStateMachine.isHolePhase(phase: any): boolean
	return type(phase) == "string" and HOLE_PHASES[phase] == true
end

function MatchStateMachine.allowsSettingsChange(phase: any): boolean
	return type(phase) == "string" and SETTINGS_PHASES[phase] == true
end

return MatchStateMachine

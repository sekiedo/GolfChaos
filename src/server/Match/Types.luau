--!strict
--[[
Match.Types — types internes de MatchService (extraits du service, sans changement de comportement).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Scoring = require(Shared.Logic.Scoring)
local TroveModule = require(Shared.Util.Trove)

type Trove = TroveModule.Trove
type Team = Types.Team
type Phase = Types.Phase
type Mode = Types.Mode
type MatchSettings = Types.MatchSettings
type HoleResult = Types.HoleResult
type HoleDef = Types.HoleDef
type HoleRuntime = Types.HoleRuntime

export type EntryStatus = "Playing" | "Finished" | "TimeOut" | "Forfeit" | "Disconnected" | "AFK"

export type PlayerRecord = {
	userId: number,
	name: string,
	player: Player?,
	present: boolean,
	team: Team?,
	joinedHole: number, -- index de playlist du premier trou joué
	holesAccounted: number, -- trous joués déjà comptés dans totalStrokes (rattrapage des trous manqués)
	points: number,
	holeWins: number,
	totalStrokes: number,
	birdiesOrBetter: number,
	holesPlayed: number,
	holesFinished: number,
	activeHoles: number,
	parOrBetter: number,
	holeInOnes: number,
	eagles: number,
	birdies: number,
	soloHoles: { Scoring.SoloHole },
	afkFlag: boolean, -- encore marqué AFK : délai réduit au trou suivant
	afkPos: Vector3?,
}

export type HoleEntry = {
	record: PlayerRecord,
	status: EntryStatus,
	reason: string?,
	finishOrder: number?,
	finishTime: number?,
	strokes: number,
	shots: number,
	fromDistance: number?,
	wasPutt: boolean?,
	points: number,
	bonuses: { string },
	category: string?,
	startCFrame: CFrame,
	lastActivityAt: number,
	activityPos: Vector3?,
	heartbeatPos: Vector3?,
	heartbeatLook: Vector3?,
	afkWarned: boolean,
}

export type HoleState = {
	index: number,
	def: Types.HoleDef,
	runtime: Types.HoleRuntime,
	par: number,
	cap: number,
	timeLimit: number,
	referenceTime: number,
	startedAt: number,
	deadline: number,
	overtimeTriggered: boolean,
	entries: { [number]: HoleEntry },
	order: { number },
	finishCount: number,
	lastFinishFrame: number?,
	lastFinishRank: number?,
	teamSizes: { [string]: number },
	frozen: boolean,
	endCheckScheduled: boolean,
	results: { HoleResult }?,
	teamWinner: Team?,
	trove: Trove,
}

export type MatchState = {
	id: string,
	settings: MatchSettings,
	mode: Mode,
	playlist: { string },
	holeIndex: number,
	holesPlayed: number,
	holeCaps: { number }, -- plafond de coups de chaque trou joué (dans l'ordre)
	records: { [number]: PlayerRecord },
	order: { number },
	pendingLate: { [Player]: boolean },
	teamScores: { [string]: number },
	teamInstances: { [string]: Team },
	trove: Trove,
	lastHoleResults: { [string]: any }?,
	podium: { [string]: any }?,
	completed: boolean,
}

return {}

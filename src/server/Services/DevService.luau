--!strict
--[[
	DevService — outils d'intégration et de test, ACTIFS UNIQUEMENT DANS STUDIO.

	Expose ServerStorage.DevBridge (BindableFunction, jamais répliquée aux clients, aucun RemoteEvent) :
	le code de test exécuté côté serveur pendant un Play (outil MCP execute_luau, datamodel "Server")
	appelle :
	    game.ServerStorage.DevBridge:Invoke("state")
	    game.ServerStorage.DevBridge:Invoke("netStats")
	    game.ServerStorage.DevBridge:Invoke("perf", secondes)
	    game.ServerStorage.DevBridge:Invoke("call", "MatchService", "GetPhase")   -- appel d'API publique
	    game.ServerStorage.DevBridge:Invoke("attrs", userId)
	Les modules requis par un contexte de test sont des copies distinctes de ceux du jeu en cours
	(cache de require séparé) : ce pont donne accès aux INSTANCES RÉELLES des services démarrés.

	En dehors de Studio (serveur réel), DevService ne crée rien et ne fait rien.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local Log = require(ReplicatedStorage.Shared.Util.Log)

local DevService = {}
DevService.Priority = 90

local servicesFolder = script.Parent
local commands: { [string]: (...any) -> any } = {}

local function getService(name: string): any?
	local module = servicesFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function serialize(value: any, depth: number?): any
	local level = depth or 0
	local kind = typeof(value)
	if kind == "Instance" then
		return value:GetFullName()
	elseif kind == "Vector3" then
		return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	elseif kind == "CFrame" then
		local p = value.Position
		return string.format("CFrame(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
	elseif kind == "table" then
		if level > 4 then
			return "{…}"
		end
		local out = {}
		for key, item in value do
			out[tostring(key)] = serialize(item, level + 1)
		end
		return out
	elseif kind == "function" or kind == "thread" then
		return "<" .. kind .. ">"
	elseif kind == "EnumItem" or kind == "BrickColor" or kind == "Color3" then
		return tostring(value)
	end
	return value
end

local function playerAttributes(player: Player)
	local attrs = {}
	for key, value in player:GetAttributes() do
		attrs[key] = serialize(value)
	end
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		attrs._position = if root then serialize(root.Position) else nil
		local charAttrs = {}
		for key, value in character:GetAttributes() do
			charAttrs[key] = serialize(value)
		end
		attrs._character = charAttrs
	end
	return attrs
end

commands.ping = function()
	return "pong"
end

commands.state = function()
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	local stateAttrs = {}
	if gameState then
		for key, value in gameState:GetAttributes() do
			stateAttrs[key] = serialize(value)
		end
	end
	local players = {}
	for _, player in Players:GetPlayers() do
		players[player.Name] = playerAttributes(player)
	end
	local balls = {}
	local ballsFolder = workspace:FindFirstChild("Balls")
	if ballsFolder then
		for _, ball in ballsFolder:GetChildren() do
			if ball:IsA("BasePart") then
				balls[ball.Name] = {
					position = serialize(ball.Position),
					velocity = serialize(ball.AssemblyLinearVelocity),
					state = ball:GetAttribute("State"),
					owner = ball:GetAttribute("OwnerUserId"),
				}
			end
		end
	end
	local serverScript = servicesFolder.Parent
	return {
		gameState = stateAttrs,
		players = players,
		balls = balls,
		bootFailures = serverScript:GetAttribute("BootFailures"),
		booted = serverScript:GetAttribute("Booted"),
		logErrors = Log.getErrorCount(),
	}
end

commands.attrs = function(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	return playerAttributes(player)
end

commands.netStats = function()
	local Net = require(ReplicatedStorage.Shared.Net) :: any
	local result: { [string]: any } = { net = Net.getStats() }
	local validation = getService("NetworkValidation")
	if validation and type(validation.GetReport) == "function" then
		result.validation = serialize(validation.GetReport())
	end
	return result
end

-- Résout un chemin pointé dans une table de service ("GetPhase", "Dev.ForceStart").
local function resolvePath(root: any, path: string): any
	local target = root
	for segment in string.gmatch(path, "[^%.]+") do
		if type(target) ~= "table" then
			return nil
		end
		target = target[segment]
	end
	return target
end

-- Appel générique d'une fonction publique d'un service démarré : ("call", "BallService", "GetStrokes", userId, ...)
-- Les noms pointés atteignent les sous-tables (ex. ("call", "MatchService", "Dev.ForceStart")).
-- Les arguments nommés "player:<userId>" sont convertis en objet Player.
commands.call = function(serviceName: string, functionName: string, ...: any)
	local service = getService(serviceName)
	if not service then
		error("service introuvable : " .. tostring(serviceName))
	end
	local fn = resolvePath(service, functionName)
	if type(fn) ~= "function" then
		error(string.format("%s.%s n'existe pas", serviceName, tostring(functionName)))
	end
	local args = table.pack(...)
	for index = 1, args.n do
		local value = args[index]
		if type(value) == "string" then
			local userId = string.match(value, "^player:(%d+)$")
			if userId then
				args[index] = Players:GetPlayerByUserId(tonumber(userId) :: number)
			end
		end
	end
	local results = table.pack(fn(table.unpack(args, 1, args.n)))
	local out = {}
	for index = 1, results.n do
		out[index] = serialize(results[index])
	end
	return out
end

-- Mesures de performance côté serveur sur une durée donnée (défaut 3 s).
commands.perf = function(duration: number?)
	local seconds = math.clamp(duration or 3, 0.5, 20)
	local frames, total, worst = 0, 0, 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		total += dt
		worst = math.max(worst, dt)
	end)
	task.wait(seconds)
	connection:Disconnect()
	local function safe(getter: () -> any): any
		local ok, value = pcall(getter)
		return if ok then value else nil
	end
	return {
		seconds = seconds,
		heartbeatFps = if total > 0 then frames / total else 0,
		worstFrameMs = worst * 1000,
		memoryMb = safe(function()
			return Stats:GetTotalMemoryUsageMb()
		end),
		instanceCount = safe(function()
			return Stats.InstanceCount
		end),
		primitives = safe(function()
			return Stats.PrimitivesCount
		end),
		movingPrimitives = safe(function()
			return Stats.MovingPrimitivesCount
		end),
		contacts = safe(function()
			return Stats.ContactsCount
		end),
		dataSendKbps = safe(function()
			return Stats.DataSendKbps
		end),
		dataReceiveKbps = safe(function()
			return Stats.DataReceiveKbps
		end),
		workspaceDescendants = #workspace:GetDescendants(),
	}
end

-- Derniers avertissements/erreurs du serveur (Log.getRecent) : ("logs", 30) ou ("logs", 30, "error").
commands.logs = function(count: number?, level: string?)
	local wanted: ("warn" | "error")? = if level == "error" then "error" elseif level == "warn" then "warn" else nil
	local out = {}
	for _, entry in Log.getRecent(count, wanted) do
		table.insert(out, string.format("[%s %.1f] %s", entry.level, entry.at, entry.text))
	end
	return out
end

-- Inventaire de ce qui reste dans le monde (détection de résidus entre manches).
commands.residue = function()
	local counts: { [string]: number } = {}
	for _, child in workspace:GetChildren() do
		local key = child.ClassName .. ":" .. child.Name
		counts[key] = #child:GetDescendants() + 1
	end
	return counts
end

--------------------------------------------------------------------------------
-- Scénario automatisé de partie (test d'intégration en Play solo)
--   ("scenario", { holes = 2, hold = 1, timeout = 120, skip = true, settings = {...} })  -> démarre (asynchrone)
--   ("report")                                                                           -> rapport courant/final
-- Le scénario lance une partie par MatchService.Dev.ForceStart, fait « arriver » chaque joueur
-- (MatchService.Dev.FinishPlayer, même chemin que BallService.Holed) `hold` secondes après le début de
-- chaque manche, accélère les phases d'affichage (SkipPhase) et s'arrête au retour à l'accueil.
--------------------------------------------------------------------------------

type ScenarioReport = {
	ok: boolean,
	running: boolean,
	error: string?,
	phases: { string },
	steps: { string },
	errorsBefore: number,
	errorsAfter: number?,
	duration: number?,
	residueBefore: { [string]: number }?,
	residueAfter: { [string]: number }?,
	logs: { string }?,
	gameState: { [string]: any }?,
}

local currentReport: ScenarioReport? = nil
local SKIPPABLE = { HoleIntro = true, Countdown = true, HoleResults = true, Podium = true }

local function readPhase(): string?
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	return if gameState then gameState:GetAttribute("Phase") :: string? else nil
end

local function readRound(): number
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	local value = if gameState then gameState:GetAttribute("RoundId") else nil
	return if type(value) == "number" then value else 0
end

commands.scenario = function(options: any?)
	if currentReport and currentReport.running then
		return { error = "un scénario est déjà en cours" }
	end
	local opts = if type(options) == "table" then options else {}
	local MatchService = getService("MatchService")
	if not MatchService or type(MatchService.Dev) ~= "table" or type(MatchService.Dev.ForceStart) ~= "function" then
		error("MatchService.Dev.ForceStart indisponible")
	end
	local dev = MatchService.Dev
	local startedAt = os.clock()
	local report: ScenarioReport = {
		ok = false,
		running = true,
		phases = {},
		steps = {},
		errorsBefore = Log.getErrorCount(),
	}
	currentReport = report
	local function stamp(): string
		return string.format("%.1f", os.clock() - startedAt)
	end
	local function step(text: string)
		table.insert(report.steps, stamp() .. " " .. text)
	end
	local phaseConnection: any = nil
	if type(MatchService.PhaseChanged) == "table" and type(MatchService.PhaseChanged.Connect) == "function" then
		phaseConnection = MatchService.PhaseChanged:Connect(function(newPhase, oldPhase)
			table.insert(report.phases, string.format("%s %s->%s", stamp(), tostring(oldPhase), tostring(newPhase)))
		end)
	end
	local hold = if type(opts.hold) == "number" then math.clamp(opts.hold, 0, 30) else 1
	local timeout = if type(opts.timeout) == "number" then math.clamp(opts.timeout, 10, 600) else 150
	local allowSkip = opts.skip ~= false

	task.spawn(function()
		local ok, err = pcall(function()
			report.residueBefore = commands.residue()
			dev.ForceStart(opts.settings)
			step("ForceStart")
			local deadline = os.clock() + timeout
			local sawPlaying = false
			local finishedRounds: { [number]: boolean } = {}
			local skippedAt: { [string]: number } = {}
			while os.clock() < deadline do
				local phase = readPhase()
				if phase == "Lobby" and sawPlaying then
					step("retour à l'accueil")
					break
				elseif phase == "Playing" then
					sawPlaying = true
					local round = readRound()
					if not finishedRounds[round] then
						finishedRounds[round] = true
						task.wait(hold)
						if readPhase() == "Playing" and type(dev.FinishPlayer) == "function" then
							for _, player in Players:GetPlayers() do
								local finished, finishErr = pcall(dev.FinishPlayer, player)
								if not finished then
									step("FinishPlayer a échoué : " .. tostring(finishErr))
								end
							end
							step("joueurs arrivés (manche " .. round .. ")")
						end
					end
				elseif phase and allowSkip and SKIPPABLE[phase] and type(dev.SkipPhase) == "function" then
					local key = phase .. ":" .. readRound()
					if not skippedAt[key] then
						skippedAt[key] = os.clock()
						task.wait(hold)
						if readPhase() == phase then
							pcall(dev.SkipPhase)
							step("SkipPhase " .. phase)
						end
					end
				end
				task.wait(0.2)
			end
			if not sawPlaying then
				error("la phase Playing n'a jamais été atteinte")
			end
		end)
		report.residueAfter = commands.residue()
		report.ok = ok and readPhase() == "Lobby"
		report.error = if ok then (if report.ok then nil else "délai dépassé avant le retour à l'accueil") else tostring(err)
		report.errorsAfter = Log.getErrorCount()
		report.duration = os.clock() - startedAt
		local logs = {}
		for _, entry in Log.getRecent(40) do
			table.insert(logs, entry.level .. " " .. entry.text)
		end
		report.logs = logs
		local gameState = ReplicatedStorage:FindFirstChild("GameState")
		if gameState then
			local snapshot = {}
			for key, value in gameState:GetAttributes() do
				snapshot[key] = serialize(value)
			end
			report.gameState = snapshot
		end
		if phaseConnection then
			phaseConnection:Disconnect()
		end
		report.running = false
	end)
	return { started = true, hold = hold, timeout = timeout }
end

commands.report = function()
	return currentReport or { error = "aucun scénario lancé" }
end

function DevService.Init()
	if not RunService:IsStudio() then
		return
	end
	local bridge = ServerStorage:FindFirstChild("DevBridge")
	if bridge then
		bridge:Destroy()
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DevBridge"
	fn.OnInvoke = function(command: string, ...: any)
		local handler = commands[command]
		if not handler then
			return { error = "commande inconnue : " .. tostring(command) }
		end
		local results = table.pack(pcall(handler, ...))
		if not results[1] then
			return { error = tostring(results[2]) }
		end
		return serialize(results[2])
	end
	fn.Parent = ServerStorage
	Log.info("Dev", "DevBridge prêt (Studio uniquement)")
end

-- Permet à d'autres modules de test d'ajouter des commandes (ex. HoleProver).
function DevService.RegisterCommand(name: string, handler: (...any) -> any)
	commands[name] = handler
end

return DevService

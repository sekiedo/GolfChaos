--!strict
-- Machine à états de la partie (Logic.MatchStateMachine) : parcours normal, transitions exceptionnelles,
-- transitions refusées, enchaînement des trous (docs/ARCHITECTURE.md §7, docs/REGLES_SCORE.md §12).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchStateMachine = require(Shared.Logic.MatchStateMachine)

local NORMAL_PATH = { "Lobby", "Preparing", "Loading", "HoleIntro", "Countdown", "Playing", "HoleEnd", "HoleResults" }
local MATCH_PHASES = { "Loading", "HoleIntro", "Countdown", "Playing", "HoleEnd", "HoleResults", "Podium" }

return function(t)
	t.describe("Phases", function()
		t.it("liste les 9 phases dans l'ordre du parcours", function()
			t.expect(MatchStateMachine.Phases).toEqual({
				"Lobby",
				"Preparing",
				"Loading",
				"HoleIntro",
				"Countdown",
				"Playing",
				"HoleEnd",
				"HoleResults",
				"Podium",
			})
		end)

		t.it("reconnaît les phases valides et rejette le reste", function()
			for _, phase in MatchStateMachine.Phases do
				t.expect(MatchStateMachine.isPhase(phase)).toBe(true)
			end
			t.expect(MatchStateMachine.isPhase("Training")).toBe(false)
			t.expect(MatchStateMachine.isPhase("lobby")).toBe(false)
			t.expect(MatchStateMachine.isPhase(nil)).toBe(false)
			t.expect(MatchStateMachine.isPhase(3)).toBe(false)
		end)

		t.it("ne référence que des phases valides dans la table de transitions", function()
			for from, targets in MatchStateMachine.Transitions do
				t.expect(MatchStateMachine.isPhase(from)).toBe(true)
				for to in targets do
					t.expect(MatchStateMachine.isPhase(to)).toBe(true)
				end
			end
		end)
	end)

	t.describe("Transitions autorisées", function()
		t.it("suit le parcours normal d'un trou", function()
			for index = 1, #NORMAL_PATH - 1 do
				t.expect(MatchStateMachine.canTransition(NORMAL_PATH[index], NORMAL_PATH[index + 1])).toBe(true)
			end
		end)

		t.it("enchaîne le trou suivant ou le podium après les résultats", function()
			t.expect(MatchStateMachine.canTransition("HoleResults", "Loading")).toBe(true)
			t.expect(MatchStateMachine.canTransition("HoleResults", "Podium")).toBe(true)
			t.expect(MatchStateMachine.canTransition("Podium", "Lobby")).toBe(true)
		end)

		t.it("permet d'annuler la préparation et d'interrompre toute phase de partie", function()
			t.expect(MatchStateMachine.canTransition("Preparing", "Lobby")).toBe(true)
			for _, phase in MATCH_PHASES do
				t.expect(MatchStateMachine.canTransition(phase, "Lobby")).toBe(true)
			end
		end)

		t.it("permet le podium quand plus aucun trou n'est chargeable", function()
			t.expect(MatchStateMachine.canTransition("Loading", "Podium")).toBe(true)
		end)
	end)

	t.describe("Transitions refusées", function()
		t.it("refuse de sauter des phases", function()
			t.expect(MatchStateMachine.canTransition("Lobby", "Loading")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Lobby", "Playing")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Preparing", "Playing")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Loading", "Playing")).toBe(false)
			t.expect(MatchStateMachine.canTransition("HoleIntro", "Playing")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Playing", "HoleResults")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Countdown", "HoleEnd")).toBe(false)
		end)

		t.it("refuse les retours en arrière", function()
			t.expect(MatchStateMachine.canTransition("Playing", "Countdown")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Playing", "Loading")).toBe(false)
			t.expect(MatchStateMachine.canTransition("HoleEnd", "Playing")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Podium", "Loading")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Podium", "HoleResults")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Preparing", "Preparing")).toBe(false)
		end)

		t.it("refuse toute transition vers soi-même", function()
			for _, phase in MatchStateMachine.Phases do
				t.expect(MatchStateMachine.canTransition(phase, phase)).toBe(false)
			end
		end)

		t.it("refuse les valeurs invalides", function()
			t.expect(MatchStateMachine.canTransition("Lobby", "Nowhere")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Nowhere", "Lobby")).toBe(false)
			t.expect(MatchStateMachine.canTransition(nil, "Lobby")).toBe(false)
			t.expect(MatchStateMachine.canTransition("Lobby", nil)).toBe(false)
		end)

		t.it("n'offre que la préparation depuis l'accueil", function()
			t.expect(MatchStateMachine.allowedFrom("Lobby")).toEqual({ "Preparing" })
			t.expect(MatchStateMachine.allowedFrom("Podium")).toEqual({ "Lobby" })
			t.expect(MatchStateMachine.allowedFrom("HoleResults")).toEqual({ "Lobby", "Loading", "Podium" })
			t.expect(MatchStateMachine.allowedFrom("Inconnu")).toEqual({})
		end)
	end)

	t.describe("Enchaînement des trous", function()
		t.it("passe au trou suivant tant qu'il en reste", function()
			t.expect(MatchStateMachine.nextAfterResults(1, 3)).toBe("Loading")
			t.expect(MatchStateMachine.nextAfterResults(2, 3)).toBe("Loading")
			t.expect(MatchStateMachine.nextAfterResults(3, 3)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(1, 1)).toBe("Podium")
		end)

		t.it("mène au podium pour toute valeur invalide (jamais de boucle infinie)", function()
			t.expect(MatchStateMachine.nextAfterResults(0, 0)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(0 / 0, 3)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(1, 0 / 0)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(math.huge, 3)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(1, math.huge)).toBe("Podium")
			t.expect(MatchStateMachine.nextAfterResults(-1, 3)).toBe("Podium")
		end)

		t.it("déroule une partie complète de 3 trous jusqu'au retour à l'accueil", function()
			local holeCount = 3
			local holeIndex = 0
			local phase = "Lobby"
			local visited: { string } = { phase }
			for _ = 1, 100 do
				if phase == "Loading" then
					holeIndex += 1
				end
				local nextPhase = MatchStateMachine.nextPhase(phase :: any, holeIndex, holeCount)
				t.expect(MatchStateMachine.canTransition(phase, nextPhase)).toBe(true)
				phase = nextPhase
				table.insert(visited, phase)
				if phase == "Lobby" then
					break
				end
			end
			t.expect(phase).toBe("Lobby")
			t.expect(holeIndex).toBe(holeCount)
			local playingCount = 0
			for _, value in visited do
				if value == "Playing" then
					playingCount += 1
				end
			end
			t.expect(playingCount).toBe(holeCount)
			t.expect(visited[#visited - 1]).toBe("Podium")
		end)
	end)

	t.describe("Catégories de phases", function()
		t.it("distingue partie, trou et réglages", function()
			t.expect(MatchStateMachine.isMatchPhase("Lobby")).toBe(false)
			t.expect(MatchStateMachine.isMatchPhase("Preparing")).toBe(false)
			t.expect(MatchStateMachine.isMatchPhase("Podium")).toBe(true)
			t.expect(MatchStateMachine.isMatchPhase("Playing")).toBe(true)
			t.expect(MatchStateMachine.isHolePhase("Podium")).toBe(false)
			t.expect(MatchStateMachine.isHolePhase("Loading")).toBe(true)
			t.expect(MatchStateMachine.isHolePhase("HoleResults")).toBe(true)
			t.expect(MatchStateMachine.allowsSettingsChange("Lobby")).toBe(true)
			t.expect(MatchStateMachine.allowsSettingsChange("Preparing")).toBe(true)
			t.expect(MatchStateMachine.allowsSettingsChange("Playing")).toBe(false)
			t.expect(MatchStateMachine.allowsSettingsChange("Loading")).toBe(false)
		end)
	end)
end

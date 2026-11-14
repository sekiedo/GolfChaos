--!strict
--[[
	Remotes des émotes (EmoteService côté serveur, EmoteController côté client).
	Le client n'envoie que des INTENTIONS : le serveur vérifie l'existence de l'émote (catalogue Cosmetics,
	emplacement "Emote"), sa possession, l'état du personnage (vivant, non KO, hors visée, hors véhicule)
	et le délai, puis pose les attributs de personnage EmoteStartedAt / Emote (docs/ARCHITECTURE.md §6).
	L'animation est jouée par AnimationController sur chaque client ; aucun remote serveur -> client n'est
	nécessaire (l'état passe par les attributs répliqués).
]]
return {
	-- Client -> serveur : jouer une émote possédée. (identifiant du cosmétique "Emote", 40 caractères max)
	["Emote.Play"] = { kind = "Event", dir = "ToServer", args = { "string:40" }, rate = 1, burst = 2 },
	-- Client -> serveur : arrêter l'émote en cours (déplacement local, bouton « Arrêter »).
	["Emote.Stop"] = { kind = "Event", dir = "ToServer", args = {}, rate = 2, burst = 3 },
}

--!strict
--[[
	Remotes des effets visuels et sonores (purement cosmétiques : aucun effet de jeu ne passe par ici).
	Le serveur décide QUAND un effet a lieu ; chaque client le rend selon ses réglages (qualité, effets réduits,
	mode sans flash, volumes).
]]
return {
	-- Serveur -> clients : jouer un effet du registre client/Effects/*. (nomEffet, paramètres)
	["Effects.Play"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> clients : jouer un son de Config/Sounds. (nomSon, position Vector3? (nil = son d'interface), volumeRelatif?)
	["Effects.Sound"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> clients : changer la musique d'ambiance. (nomMusique ou "" pour couper)
	["Effects.Music"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : effets fréquents à faible priorité (traînées, étincelles), perte acceptable.
	["Effects.Burst"] = { kind = "Unreliable", dir = "ToClient" },
}

--!strict
--[[
	Config.Data — réglages de la sauvegarde des profils (PlayerDataService, Data.ProfileStore).
	Aucune donnée de joueur ici : uniquement des durées et des noms.
]]

local Data = {}

Data.StoreName = "PlayerData" -- en Studio, DataStoreAdapter ajoute le suffixe "_Studio"
Data.KeyPrefix = "Player_" -- clé d'un profil : KeyPrefix .. UserId

-- Verrou de session : un seul serveur à la fois possède un profil.
Data.LockExpiry = 300 -- s : un verrou plus ancien est considéré abandonné (serveur planté)
Data.LockRefresh = 120 -- s : un profil chargé est réécrit au moins à ce rythme pour garder son verrou
Data.LoadRetries = 5 -- essais de chargement quand un autre serveur tient encore le verrou
Data.LoadRetryDelay = 4 -- s entre deux essais

-- Sauvegarde.
Data.AutosaveInterval = 60 -- s : enregistrement périodique des profils modifiés
Data.UrgentSaveDelay = 8 -- s : enregistrement rapproché après une transaction (achat, récompense)
Data.MinSaveGap = 7 -- s : écart minimal entre deux écritures d'une même clé
Data.CloseTimeout = 20 -- s : temps maximal accordé aux sauvegardes à la fermeture du serveur

-- Réplication.
Data.SyncDelay = 0.5 -- s : regroupement des instantanés Data.Sync envoyés au propriétaire
Data.ProfileWaitTimeout = 30 -- s : attente par défaut de WaitForProfile

return Data

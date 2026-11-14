# État de reprise — Golf Chaos

> Document tenu à jour par l'intégrateur après chaque étape : décisions, fichiers, tests, problèmes,
> prochaine action. Permet de reprendre le travail sans perte de contexte.

## Environnement constaté (12/11/2026)

- Dossier projet : `C:\Users\gifgr\Downloads\super Battle blox` — contenait 10 scripts Luau d'un prototype
  « étape 1 » (balle serveur, visée, jauge, étourdissement), conservés tels quels dans `legacy/prototype-etape1/`
  (commit `250bc33` sur `main`). Aucun AGENTS.md / CLAUDE.md.
- Git : dépôt créé ; `main` = prototype d'origine ; travail sur `dev/golf-chaos`.
- Outils : git 2.56 ; **aucun** Rojo/Rokit/Wally/Selene/StyLua/Lune/Node/Python installés au départ.
  Rojo 7.7.1 téléchargé (release officielle, SHA-256 vérifié) dans `tools/` (hors Git, script `scripts/install-tools.ps1`).
- Roblox Studio 0.747.0.7471481, serveur MCP intégré activé. Deux fenêtres : la place cloud de l'utilisateur
  « super combat blox » (Baseplate vide, **jamais modifiée**) et la place de test `build/GolfChaos.rbxlx`.
- Machine de référence PC : AMD Ryzen 7 7435HS, NVIDIA RTX 4060 Laptop, 23,7 Go RAM, Windows 11 Famille.
  Aucun appareil mobile physique disponible.
- Bruit de console connu : un plugin cloud installé dans Studio (`cloud_8089767977.Animation`) affiche
  « Please Enable Script Injection » et une erreur d'index ; il ne fait pas partie du projet.

## Décisions

1. Source de vérité = dépôt ; build Rojo → `build/GolfChaos.rbxlx` ouvert dans une fenêtre Studio séparée.
2. Monde entièrement généré par code depuis les données (accueil, trous, décors, UI) : reproductible, inspectable.
3. Balle = Part physique serveur (pas fixe 240 Hz) + balayage Spherecast + capture du trou segment–cercle.
4. `CharacterAutoLoads = false` : `SpawnService` contrôle toutes les apparitions ; `LoadCharacterAppearance = false`
   (proportions identiques pour tous, apparence par cosmétiques du jeu).
5. Animations procédurales (Motor6D.Transform) répliquées par attributs ; aucun upload requis.
6. Sauvegarde : adaptateur DataStore réel en production ; adaptateur mémoire **non persistant** signalé en Studio.
7. (Recherche doc, `docs/notes-techniques-roblox.md`) `StarterPlayer.AvatarJointUpgrade = Disabled` : rigs R15 à Motor6D
   classiques (ragdoll et animations procédurales). `Workspace.SignalBehavior = Deferred` explicite (Default = Immediate).
   `Workspace.TouchesUseCollisionGroups = true`. Vérifié dans le fichier construit (`SignalBehavior2 = 2`,
   `AvatarJointUpgrade_SerializedRollout = 1`, `PhysicsSteppingMethod = 1`).
8. Parties privées : API actuelle `TeleportOptions.ReservedServerId` (GUID serveur) ; `ReserveServer` est déprécié.
   Les téléportations sont testables en Studio (Test / Team Test) via `TeleportAsync`.
9. Tests multi-clients : `StudioTestService:ExecuteMultiplayerTestAsync(1..8, args)` (sécurité plugin) — à essayer via
   le contexte plugin de l'outil MCP pour les tests à 2–8 clients ; 16 joueurs impossible dans cet outil (max 8).
10. Audio : uniquement sons intégrés du moteur et bibliothèque sous licence des comptes officiels ProSoundEffects et
    APMOfficial (provenance vérifiable) ; uploads d'utilisateurs exclus (origine incertaine).
11. Cosmétiques : modèles construits par code (`shared/Cosmetics/Build.luau` impose Massless/sans collision/sans requête).

## Étapes

| Étape | Statut | Preuve |
| --- | --- | --- |
| 1. Environnement, fondations | Fait | build Rojo OK, Studio MCP OK, 10/10 tests unitaires en moteur, boot serveur/client OK (Play solo) |
| 1. Cahier des charges, matrice | En cours | — |
| 2. Boucle complète sur un trou | En cours | — |
| 3–8 | À faire | — |

## Propriété des fichiers (chantiers parallèles)

Voir les prompts de chantier ; fichiers communs réservés à l'intégration : `Types.luau`, `Net/init.luau`,
`Net/Remotes/{Core,Golf,Combat,Match,Lobby,Data}.luau`, `Util/*`, bootstraps, `tests/Runner.luau`, `docs/ARCHITECTURE.md`.

## API ajoutées en cours de route

- `Log.getRecent(n?, niveau?)` : derniers avertissements/erreurs gardés en mémoire (200 max) pour les tests Studio.
- `DevBridge` : commande `logs` (derniers messages du serveur) ; `call` accepte les chemins pointés
  (ex. `("call", "MatchService", "Dev.ForceStart")`).

## Problèmes ouverts

- **Incident Studio (12/11, 13 h 48 et 13 h 51)** : la fenêtre de la place de l'utilisateur « super combat blox » s'est fermée
  (fermetures « propres » d'après les journaux Studio) juste après l'ouverture de fenêtres de test ; cause non établie
  (un test contrôlé montre qu'ouvrir une fenêtre ne ferme pas les autres). Aucune modification de la place n'était en attente
  de notre part. Mesure : `scripts/open-studio.ps1 -CloseOld` ne ferme plus qu'une fenêtre dont le titre est exactement sa
  propre copie de test ; ne jamais fermer une autre fenêtre Studio.
- Limite d'utilisation atteinte à 11 h 5x (reprise 13 h 41) : les ateliers ont été relancés automatiquement ; l'agent audio a été
  repris par message. Fenêtres actuelles : `GolfChaos_check.rbxlx` (vérifications de compilation des chantiers, mode Édition) et
  `GolfChaos_verify.rbxlx` (tests de l'intégrateur).
- **Studio déconnecté (12/11, 18 h 42)** : la connexion automatique de Studio échoue (HTTP 401) et Studio se ferme au
  démarrage. L'utilisateur doit se reconnecter dans Roblox Studio ; tant que ce n'est pas fait, aucun test moteur n'est possible.
  Les ateliers ont été relancés (runs `wf_090fa779-fb5` et `wf_406d82a3-04e`) avec une consigne : vérifier la compilation dans
  la fenêtre « GolfChaos_check.rbxlx » si elle existe, sinon continuer sans bloquer.
- **Règle Studio confirmée (13/11, 21 h 33)** : lancer une nouvelle fenêtre Studio a de nouveau fermé une fenêtre ouverte par
  l'utilisateur (`build/GolfChaos.rbxlx`), journal à l'appui (« About to close app » quelques secondes après le lancement).
  Désormais : ne jamais lancer de fenêtre Studio tant qu'une fenêtre non ouverte par nous est présente ; construire dans
  `build/GolfChaos_src.rbxlx` (jamais sur le fichier que l'utilisateur peut avoir ouvert) ; réutiliser les fenêtres
  `GolfChaos_check.rbxlx` et `GolfChaos_verify.rbxlx`.
- **Reprise (13/11, 21 h 40)** : les brouillons (≈10 000 lignes) se chargent tous en Studio (55 modules, 0 échec) ; tests
  72/77 avant correction des tolérances float32 de `BallMath.spec` (1e-6 → 1e-4). Travail restant relancé en 21 tâches
  courtes (run `wf_a32b601c-e99`, script `golf-chaos-core-v2`) : chaînes trous (données + constructeur → CourseService),
  interface (cadre → HUD + écrans), sauvegarde (schéma → ProfileStore) ; tâches isolées balle, partie, salon, visée,
  animations, documents, 5 lots de cosmétiques. En cas d'interruption : `Workflow({scriptPath, resumeFromRunId})`.
- Leçon : ne jamais envoyer de message aux agents d'un atelier interrompu par une limite (cela les relance hors de
  l'atelier et crée des doublons) ; relancer l'atelier lui-même. Des brouillons partiels d'une exécution interrompue existent
  (Gameplay, BallMath, Collision/Combat/Movement/NetworkValidation, Input/Camera, Animations, cahier des charges) : les
  chantiers relancés les reprennent.
- **Diagnostic des interruptions (14/11, 07 h 30)** : le run `wf_a32b601c-e99` (14 agents simultanés) a été relancé trois
  fois (13/11 21 h 39, 14/11 03 h 22 et 06 h 55) et coupé chaque fois par la limite d'usage au bout d'environ 30 min, sans
  qu'aucun agent ne se termine : chaque reprise repartait de zéro (aucun résultat en cache) et relisait tout le contexte.
  Seule la première exécution a laissé des fichiers (BallService, Schema, DataStoreAdapter, Theme + 3 composants UI, Emotes,
  catalogues Heads/Faces/Shoes, textes Aim/Controls/Lobby/Match, cahier des charges et matrice), sauvegardés dans le commit
  `a535f5a` (non vérifiés au-delà du chargement : 86 modules, 0 échec ; tests 75/77, échecs attendus = cosmétiques manquants).
  Le run `wf_fd84959f-86b` (objets/véhicules) n'a rien produit. Nouvelle méthode : **5 agents simultanés au plus**, lots
  ciblés, consigne d'écrire chaque fichier sur disque dès sa première version complète, intégration et tests par
  l'intégrateur entre deux ateliers.
- **Atelier « boucle jouable » (14/11, 09 h 52)** : run `wf_bfefd55f-7f8` (script `golf-chaos-playable-loop`), 8 lots :
  constructeur de trous + format + données (entraînement, COT-01..06), CourseService + obstacles + accueil,
  MatchService + SpawnService + LobbyService, visée + actions + balle visuelle + HUD, cadre UI + écrans + menus + réglages,
  PlayerDataService + ProfileStore + MemoryAdapter + migrations, animations procédurales + EmoteService, textes boutique et
  cosmétiques. Reprise : `Workflow({scriptPath: ".../golf-chaos-playable-loop-wf_bfefd55f-7f8.js", resumeFromRunId:
  "wf_bfefd55f-7f8"})`.
- Point d'intégration à vérifier : `Schema.sanitize` doit accepter des clés de statistiques numériques arbitraires
  (défis : parOrBetter, longShots, onePutts, chipIns, shieldBlocks, hornForcedShots, dodges, teamWins, cartKOs) et un champ
  `sets` (ensembles : biomesFinished, holesFinished_<Biome>, itemsUsedSet).

## Fait par l'intégrateur pendant les chantiers

- Registre exécutable des 17 objets (`Config/Items`, `Config/ItemBoxes`, `Logic/ItemOdds` testé), textes FR/EN.
- Progression : 38 défis (`Config/Achievements`), économie anti-farm (`Config/Economy`, `Logic/Rewards` testé), textes FR/EN.
- Plan des 81 trous (`docs/PLAN_PARCOURS.md`), registre et matrice d'interactions des objets.
- Couche d'effets/sons client (`EffectsController`, `Effects/Core`, remotes `Effects.*`) ; registre sonore vérifié (51 sons).
- Tests d'intégration : réseau, traductions, cosmétiques, objets, progression → 47/48 en moteur (échec attendu : catalogue
  de cosmétiques en cours d'écriture).

## Prochaine action

À la fin des ateliers « boucle de jeu » et « cosmétiques/animations » : construire, exécuter tous les tests, intégrer en Play
solo (partie complète sur les trous d'entraînement), corriger, puis lancer l'étape suivante (objets, véhicules, 81 trous,
boutique, défis branchés, tutoriel, spectateur).

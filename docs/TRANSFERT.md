# Transfert du projet « Golf Chaos » (dossier `super Battle blox`)

> Document de passation pour reprendre le projet dans un autre environnement (agent Claude connecté à Roblox Studio
> par MCP) **sans rien perdre ni recommencer**. Rédigé le 14/11/2026 sur la branche `dev/golf-chaos`.
> Le paquet de transfert est régénéré à tout moment par `powershell -File scripts/export-transfert.ps1`
> (sortie : `build/transfert/`). Les annexes A à D en fin de fichier sont **générées** à partir des fichiers réels au
> moment de l'export ; le statut de chaque fichier y est indiqué.

## 0. À lire en premier (nouvel agent)

**Nom et cadre.** Le jeu s'appelle **Golf Chaos**. C'est un jeu Roblox **original** de golf multijoueur simultané
(chaos cartoon, objets, voiturettes, 81 trous, cosmétiques, progression), inspiré des *mécaniques générales* d'un
party-golf (le jeu Steam « Super Battle Golf »). Le dossier s'appelle « super Battle blox ». Règle de la demande
d'origine : **ne reprendre ni le nom, ni les assets, ni les personnages, ni les niveaux, ni les collaborations de marque
du jeu Steam**.

**Trois façons d'importer (du plus direct au plus détaillé) :**

1. **Place Studio prête** : ouvrir `GolfChaos_transfert_complet.rbxlx` dans Roblox Studio. Tous les scripts sont déjà
   à leur place (chemins de l'annexe A). Un agent connecté à Studio par MCP peut lire chaque script dans la place
   (outils `script_read` / `script_grep` / `script_search`) sans rien recopier.
   `GolfChaos_transfert_verifie.rbxlx` = même chose mais au **dernier commit** (état vérifié : 86 modules chargés, 0 échec).
2. **Dépôt Git complet** : `git clone golf-chaos.bundle golf-chaos` puis `git checkout dev/golf-chaos`
   (historique complet ; le travail non commité au moment de l'export est dans `golf-chaos-sources.zip`).
   Construction : Rojo **7.7.1** (`rojo build default.project.json -o place.rbxlx`).
3. **Code intégral en Markdown** : fichiers `01_…` à `NN_…` du paquet. Chaque fichier source y figure **en entier**,
   avec son chemin dans le dépôt, son chemin Roblox exact, sa classe (Script / LocalScript / ModuleScript), son nombre
   de lignes et son empreinte SHA-256 (vérifiable dans `SHA256SUMS.txt`).

**Source de vérité.** Le projet est piloté *par les fichiers* (`src/` + `default.project.json`, construits par Rojo) :
Studio n'est qu'une cible. Le monde entier (accueil, trous, décors, interface) est **généré par le code** à partir des
données : il n'y a **aucun objet à placer à la main** dans le Workspace. Si le nouvel environnement travaille
directement dans Studio, il doit garder la même arborescence et les mêmes contrats (sinon les modules ne se trouvent plus).

**Ordre de lecture recommandé :** `docs/ARCHITECTURE.md` (contrat liant tous les modules : arborescence, conventions,
attributs répliqués, API des services, priorités) → `docs/SPEC_DEMANDE.md` (demande d'origine complète) → ce fichier →
`docs/ETAT_REPRISE.md` (journal des décisions, incidents, runs) → `docs/REGLES_SCORE.md` → `docs/PLAN_PARCOURS.md`
(81 trous) → `docs/FORMAT_TROUS.md` (s'il existe à l'export) → `docs/REGISTRE_OBJETS.md` / `MATRICE_INTERACTIONS.md`
→ `docs/MANIFESTE_ASSETS.md` → `docs/CAHIER_DES_CHARGES.md` / `MATRICE_COUVERTURE.md`.

## 1. Arborescence

### 1.1 Correspondance dépôt → Roblox (`default.project.json`, Rojo 7.7.1)

| Dossier du dépôt | Instance Roblox | Contenu |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` (Folder) | Config, données de trous, types, logique pure, Net, Locale, Util, Cosmetics, Animations |
| `src/server` | `ServerScriptService.Server` (**Script**, via `init.server.luau`) | `Services/` (un ModuleScript par service), `Data/`, `Course/` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` (**LocalScript**, via `init.client.luau`) | `Controllers/`, `UI/`, `Effects/` |
| `src/tests` | `ServerStorage.Tests` (Folder) | `Runner` + `Specs/*.spec` (tests unitaires exécutables dans Studio) |

Règles de conversion Rojo : `init.server.luau` → le dossier devient un **Script** ; `init.client.luau` → **LocalScript** ;
`init.luau` → **ModuleScript** portant le nom du dossier (ses fichiers deviennent ses enfants, ex. `Shared.Net` est un
ModuleScript dont l'enfant `Remotes` est un Folder) ; tout autre `X.luau` → ModuleScript `X` ; dossier sans `init` → Folder.

**Seuls deux scripts s'exécutent** : `ServerScriptService.Server` (Script) et
`StarterPlayer.StarterPlayerScripts.Client` (LocalScript). Ils chargent tous les ModuleScripts de `Services/`
(serveur) et `Controllers/` (client), les trient par `Priority` (défaut 100) puis par nom, appellent tous les `Init()`
puis lancent chaque `Start()` dans son thread. Un module qui échoue est isolé et journalisé
(`ServerScriptService.Server:GetAttribute("BootFailures")`, attribut `Booted`).

Propriétés de projet imposées (dans `default.project.json`, à reproduire si l'on recrée une place) :
`Players.CharacterAutoLoads = false` (SpawnService fait apparaître les personnages) ;
`StarterPlayer.LoadCharacterAppearance = false`, `AvatarJointUpgrade = Disabled` (rigs R15 à Motor6D classiques),
`CharacterWalkSpeed 16`, `CharacterJumpPower 50`, `CharacterUseJumpPower true`, `CameraMinZoomDistance 4`,
`CameraMaxZoomDistance 90`, `EnableMouseLockOption false` ;
`Workspace.StreamingEnabled = false`, `PhysicsSteppingMethod = Fixed` (balle à 240 Hz), `SignalBehavior = Deferred`,
`TouchesUseCollisionGroups = true`, `FallenPartsDestroyHeight = -2000`, `Gravity = 196.2` ;
`Lighting.Technology = ShadowMap`, `ClockTime 14`, `Brightness 2.5`, `GlobalShadows true`.

L'arborescence complète, fichier par fichier, est en **annexe A** ; les remotes en **annexe B** ; les priorités réelles
en **annexe C** ; l'index des fichiers (taille, statut, partie du paquet) en **annexe D**.

### 1.2 Instances créées à l'exécution (absentes de la place, c'est normal)

| Instance | Créée par | Rôle |
| --- | --- | --- |
| `ReplicatedStorage.Remotes` (Folder de RemoteEvent / UnreliableRemoteEvent / RemoteFunction nommés `Domaine.Action`) | `Shared.Net` côté serveur, à partir de `Shared.Net.Remotes.*` | seul point de réseau ; arguments client → serveur vérifiés + limites de débit par joueur |
| `ReplicatedStorage.GameState` (Folder à attributs) | `Shared.Util.GameState.get()` côté serveur | état de partie répliqué (phase, manche, trou, vent, scores…) |
| `Workspace.Balls` | `BallService` | une balle (Part serveur) par joueur, attributs `OwnerUserId`, `State`, `Skin` |
| `Workspace.Course` + monde de l'accueil | `CourseService` (+ `Course/LobbyBuilder`, `HoleBuilder`) | accueil permanent à `Config.Course.LobbyOrigin` (0,0,0) ; trou courant à `HoleOrigin` (0,0,5000) |
| Groupes de collision `Balls`, `Characters`, `Vehicles`, `Projectiles`, `Ghosts`, `Course`, `Props` | `CollisionService` | interactions physiques |
| `ServerStorage.DevBridge` (BindableFunction) | `DevService`, **Studio uniquement** | pont de test : `state`, `attrs`, `netStats`, `perf`, `residue`, `logs`, `call`, `scenario`, `report` |
| `Lighting.Atmosphere` | `CourseService.ApplyBiomeLighting` | ambiance par biome |

## 2. État d'avancement (au 14/11/2026)

Légende : **✅ testé** = vérifié dans Roblox Studio avec preuve ; **🟨 écrit** = code complet qui se charge dans Studio
sans erreur mais pas encore éprouvé en partie ; **🟧 en cours** = fichiers en cours d'écriture par l'atelier
`wf_bfefd55f-7f8` au moment de l'export (non vérifiés ; voir le statut de chaque fichier en annexe D) ; **⬜ à faire**.
Aucun système n'est déclaré « 100 % terminé » tant qu'il n'a pas été joué dans Studio.

**Preuves disponibles :** construction Rojo OK ; démarrage serveur + client OK en Play solo (12/11, étape 1) ;
**86 ModuleScripts se chargent sans échec** dans Studio (14/11) ; **75/77 tests unitaires passent** dans Studio
(14/11 ; les 2 échecs sont attendus : catalogues de cosmétiques incomplets et noms traduits manquants).

| Système | Fichiers principaux | État |
| --- | --- | --- |
| Démarrage serveur/client en deux phases | `Server` (init.server), `Client` (init.client) | ✅ testé (Play solo, étape 1) |
| Réseau typé + limites de débit | `Shared.Net` + `Net.Remotes.*` (12 domaines) | ✅ testé (tests unitaires des définitions) |
| Utilitaires (Signal, Trove, Validate, Log, GameState) | `Shared.Util.*` | ✅ testé (tests unitaires) |
| Textes FR/EN | `Shared.Locale` + `fr/*`, `en/*` | ✅ mécanisme testé ; 🟨 contenu par domaine |
| Physique de balle (simulation pure) | `Shared.Logic.BallMath`, `Config.Gameplay` | ✅ tests unitaires (tolérances float32) |
| Service de balle (balle serveur 240 Hz, Spherecast, surfaces, vent, dangers, trou segment–cercle, tirs validés) | `Services.BallService` (~3 000 lignes) | 🟨 écrit, non joué |
| Combat cartoon (KO, recul, protection, frappe, plongeon), déplacements (verrous, plausibilité), collisions, garde-fous réseau | `Services.CombatService`, `MovementService`, `CollisionService`, `NetworkValidation` | 🟨 écrits, non joués |
| Entrées clavier/manette/tactile, caméra | `Controllers.InputController`, `CameraController` | 🟨 écrits |
| Effets visuels et sons (51 sons vérifiés, 10 effets, mode sans flash, effets réduits) | `Controllers.EffectsController`, `Effects.Core`, `Config.Sounds`, `docs/MANIFESTE_ASSETS.md` | 🟨 écrits (identifiants sonores vérifiés dans Studio) |
| Objets : registre des 17 objets, boîtes, probabilités de rattrapage | `Config.Items`, `Config.ItemBoxes`, `Logic.ItemOdds` | ✅ données + tirage testés ; ⬜ comportements (ItemService + 17 modules) |
| Progression : 38 défis internes, économie anti-farm, récompenses | `Config.Achievements`, `Config.Economy`, `Logic.Rewards`, `Services.AchievementService`, `Services.RewardService` | ✅ logique testée ; 🟨 services écrits (dépendent de PlayerDataService et MatchService) |
| Cosmétiques : registre, construction équitable (sans collision ni masse), service boutique/équipement/apparence | `Shared.Cosmetics`, `Cosmetics.Build`, `Services.CosmeticService` | 🟨 écrits |
| Catalogues : 25 têtes, 15 visages (+1 défaut), 10 chaussures (+1) | `Cosmetics.Catalog.Heads/Faces/Shoes` | 🟨 écrits ; noms FR/EN 🟧 en cours |
| Catalogues : 20 tenues, 15 clubs, 10 balles, 5 effets de trou, 8+ émotes cosmétiques | — | ⬜ à faire |
| Sauvegarde : schéma versionné, assainissement, opérations idempotentes, adaptateur DataStore (reprises, budgets, file par clé, isolement « _Studio », verrou de session) | `Server.Data.Schema`, `Data.Adapters.DataStoreAdapter` | 🟨 écrits |
| Sauvegarde : ProfileStore verrouillé, MemoryAdapter (non persistant, signalé), migrations, PlayerDataService | `Data.ProfileStore`, `Data.Adapters.MemoryAdapter`, `Data.Migrations`, `Services.PlayerDataService` | 🟧 en cours |
| Trous : format, validateur, constructeur, décors, accessoires, 3 trous d'entraînement, COT-01..06 | `docs/FORMAT_TROUS.md`, `Logic.HoleValidator`, `Server.Course.HoleBuilder/Props/Biomes.Common`, `Shared.Data.Holes.*`, `Config.Biomes`, `Config.Course` | 🟧 en cours |
| Parcours : CourseService, obstacles animés, accueil (place, départs, practice, podium) | `Services.CourseService`, `Course.Obstacles`, `Course.LobbyBuilder` | 🟧 en cours |
| Partie : machine à états, modes (Chacun pour soi, Équipes, Solo), score, apparitions, salon (hôte, réglages, prêt, équipes, entraînement, parties privées) | `Services.MatchService`, `SpawnService`, `LobbyService`, `Logic.MatchStateMachine/Scoring/Playlist`, `Config.Match/Scoring` | 🟧 en cours (logique pure déjà écrite) |
| Visée, actions, balle visuelle, HUD | `Controllers.GolfAimController`, `ActionController`, `BallVisualController`, `HUDController`, `UI.AimPanel`, `UI.Hud.*` | 🟧 en cours |
| Interface : thème, composants, gestionnaire d'écrans, écrans de phase, menus, réglages, notifications | `UI.Theme`, `UI.Components.*`, `UI.ScreenManager`, `UI.Screens.*`, `Controllers.UIController/MenuController/SettingsController/NotificationController` | 🟧 en cours |
| Animations procédurales (Motor6D) et émotes | `Shared.Animations` + `Library.*`, `Controllers.AnimationController`, `Services.EmoteService` | 🟨 bibliothèques ; 🟧 contrôleur et service en cours |
| 81 trous (Côte 18, Forêt 18, Désert 18, Neige 18, Ville 9) | `docs/PLAN_PARCOURS.md` (81 concepts) | 🟧 6 trous de Côte en cours ; ⬜ 75 à écrire + validation par trou + catalogue avec captures |
| Objets (17 comportements), voiturettes | `Server.Items.*`, `ItemService`, `VehicleService`, contrôleurs client | ⬜ à faire (registre et remotes déjà prêts) |
| Boutique / personnalisation / défis (écrans), spectateur, tutoriel | — | ⬜ à faire |
| Tests multi-clients, latence, performances mesurées, accessibilité vérifiée | — | ⬜ à faire |
| Documents : cahier des charges, matrice de couverture, règles de score, plan des 81 trous, registre et matrice des objets, manifeste des assets, notes techniques Roblox | `docs/*.md` | 🟨 écrits (à mettre à jour après les tests) |

## 3. Code source intégral

Le code est livré **en entier**, sans résumé ni coupure, dans les fichiers `01_…` à `NN_…` du paquet (découpés en
parties de taille raisonnable pour pouvoir être transmis morceau par morceau). L'index de l'annexe D indique pour
chaque fichier la partie qui le contient. L'ordre : projet et outils → serveur → partagé → client → tests →
documents → prototype d'origine (`legacy/prototype-etape1`, conservé pour référence, **non utilisé** par le jeu).

## 4. Liaisons et dépendances

### 4.1 Règles générales

- **Aucun `require` circulaire** : un service obtient un autre service paresseusement
  (`pcall(require, script.Parent.<Nom>)` dans une fonction) ou s'abonne à ses `Signal`. Un service absent est toléré
  (dégradation propre, journal), ce qui permet de livrer les systèmes un par un.
- **Réseau** : seul `Shared.Net` crée des remotes (`Net.on` = un seul gestionnaire serveur par remote ;
  `Net.fire/fireAll/fireList/fireAllExcept` ; client `Net.send/listen/invoke`). Toute intention de jeu transporte le
  `RoundId` courant (`GameState.RoundId`) ; 0 = entraînement à l'accueil.
- **État répliqué** : uniquement par attributs (noms exacts dans `docs/ARCHITECTURE.md` §6) — dossier `GameState`,
  joueurs (`Participant`, `Spectating`, `Team`, `Strokes`, `HoleFinished`, `FinishOrder`, `MatchPoints`, `Ready`,
  `Aiming`, `KnockedOut`, `Protected`, `AFK`, `Coins`, `DataStatus`, `Inventory`, `InventoryCapacity`, `SelectedSlot`,
  `ActiveEffects`, `InVehicle`, `Practice`), balles (`OwnerUserId`, `State`, `Skin`), personnages (`AnimState`, `Emote`,
  `EmoteStartedAt`, `Giant`, `Frozen`, `Invisible`). Seul `MatchService` écrit `GameState.Phase`.
- **Textes** : `Locale.t("domaine.cle", vars)` ; chaque clé existe en `fr` **et** en `en`, dans un seul fichier par langue.
- **Durées de vie** : `Util.Trove` par manche, par joueur, par personnage ; `MatchService` appelle en fin de trou
  `ItemService.ClearRound()`, `VehicleService.ClearAll()`, `BallService.RemoveAll()`, `CourseService.UnloadHole()`.

### 4.2 Qui dépend de qui (serveur)

| Service (priorité) | Utilise | Est utilisé par / signaux consommés |
| --- | --- | --- |
| `CollisionService` (0) | PhysicsService | tous (groupes) |
| `PlayerDataService` (5) | `Data.ProfileStore`, `Data.Schema`, `Data.Migrations`, adaptateurs DataStore / mémoire, `Config.Data` | `CosmeticService`, `AchievementService`, `RewardService` (`Transact` idempotent par `opId`, `Update`, `GetProfile`, signal `ProfileLoaded`) |
| `NetworkValidation` (8) | `Net` | services de gameplay (`Report`) |
| `MovementService` (10) | — | `CombatService`, `SpawnService`, obstacles, objets |
| `CombatService` (15) | `MovementService`, `CollisionService` | `BallService` (KO par la balle), `MatchService`, `AchievementService` (`KnockedOut`), `ItemService` (`SetShieldHandler`) |
| `BallService` (20) | `CombatService`, `CollisionService`, `Logic.BallMath`, `Config.Gameplay` | `MatchService` (`SpawnBall`, `SetCanShoot`, `SetWind`, signaux `Shot`, `Holed`), `CourseService` (`SetCup`), `RewardService` (`Shot`), `AchievementService` (`Holed`), objets |
| `CourseService` (25) | `Course.HoleBuilder`, `Course.Obstacles`, `Course.LobbyBuilder`, `Course.Props`, `Course.Biomes.*`, `Shared.Data.Holes`, `Config.Course`, `Config.Biomes`, `BallService.SetCup` | `MatchService` (`LoadHole`, `GetStartPlacements`, `ApplyBiomeLighting`), `SpawnService` (`GetLobby`, `GetCheckpointFor`) |
| `VehicleService` (30) | — | à faire |
| `ItemService` (35) | `Config.Items`, `Config.ItemBoxes`, `Logic.ItemOdds`, `Server.Items.<Id>` | à faire ; `AchievementService` écoute `ItemUsed` |
| `CosmeticService` (40) | `PlayerDataService`, `Shared.Cosmetics` | `SpawnService` (`ApplyAppearance`), `BallService` (skin), `EmoteService` |
| `AchievementService` (45) | `PlayerDataService`, `Config.Achievements` | écoute `BallService.Holed`, `CombatService.KnockedOut`, `ItemService.ItemUsed`, `PlayerDataService.ProfileLoaded` |
| `EmoteService` (46) | `CosmeticService`, `Animations.Library.Emotes` | clients (attributs `Emote`) |
| `RewardService` (50) | `PlayerDataService`, `Logic.Rewards`, `Config.Economy` | écoute `MatchService.MatchEnded`, `MatchService.PlayerFinishedHole`, `BallService.Shot` |
| `SpawnService` (55) | `CourseService`, `CosmeticService`, `CombatService`, `CollisionService`, `MovementService` | `MatchService` |
| `LobbyService` (60) | `Config.Match`, `Shared.Data.Holes`, `BallService` (balle d'entraînement) | `MatchService` (signaux `PrepareRequested`, `CancelRequested`, `StartRequested`, `HostChanged`, `SettingsChanged`, `ClientReady`) |
| `MatchService` (70) | tous les précédents, `Logic.MatchStateMachine/Scoring/Playlist` | `RewardService`, `AchievementService`, clients (`GameState`, `Match.*`) |
| `DevService` (90) | tous (lecture), **Studio uniquement** | tests via `ServerStorage.DevBridge` |

Côté client : `InputController` (0) → `SettingsController` (5) → `UIController` (10) → `CameraController` (20) →
`GolfAimController` (30) → `ActionController` (35) → `BallVisualController` (36) → `HUDController` (40) →
`MenuController` (50) → `NotificationController` (60) → `AnimationController` (70) ; `EffectsController` sert à tous.
Les contrôleurs ne lisent que les attributs répliqués et les remotes ; ils n'envoient que des intentions.

### 4.3 Objets du Workspace : rien à placer à la main

- **Apparitions (spawns)** : pas de `SpawnLocation`. `SpawnService` fait apparaître les personnages
  (`CharacterAutoLoads = false`) sur les plots de l'accueil (`CourseService.GetLobby().spawns`, construits par
  `LobbyBuilder`) ou aux départs du trou (`CourseService.GetStartPlacements`) ; réapparition au dernier point de
  contrôle (`CourseService.GetCheckpointFor`).
- **Trous** : décrits comme données (`Types.HoleDef` : ligne centrale `path`, `tee`, `cup`, `green`, `hazards`,
  `obstacles`, `props`, `checkpoints`, `itemBoxes`, `mobilityBoxes`, `carts`, `bounds`, `seed`…) dans
  `ReplicatedStorage.Shared.Data.Holes.<Biome>` ; construits par `HoleBuilder` à `Config.Course.HoleOrigin`. Les
  surfaces sont lues par la balle via l'attribut de Part `Surface` ; les dangers portent l'étiquette CollectionService
  `GolfHazard` et l'attribut `Hazard` (`water` | `oob` | `lava` | `void`) ; la capture du trou est calculée par
  `BallService.SetCup(position, rayon)` (pas de pièce « trou » détectée par contact).
- **Caisses mystères (boîtes d'objets et de mobilité)** : positions fournies par chaque trou (`itemBoxes`,
  `mobilityBoxes`) ; types, réapparition et capacité dans `Config.ItemBoxes` ; tirage serveur avec rattrapage selon la
  position dans `Logic.ItemOdds` ; apparition et ramassage par `ItemService` (**à écrire**), inventaire de 3 cases
  répliqué par les attributs `Inventory`/`SelectedSlot`/`InventoryCapacity`.
- **Accueil** : construit au démarrage par `LobbyBuilder` (place centrale, 16 plots, practice de putting, practice de
  drive, panneaux Jouer/Boutique/Personnaliser/Défis/Entraînement, podium à 3 marches).

### 4.4 Construire, lancer, tester

- Outils : Rojo 7.7.1 (`scripts/install-tools.ps1` le télécharge depuis la release officielle et vérifie le SHA-256
  `d4dfa3493a1613a43fc87312d6dac660d7c8bf38e6a99aa5dcd0d26154ba0b82`) ; `scripts/build.ps1 -Output <fichier>` ;
  `scripts/open-studio.ps1 -Rebuild -CloseOld -Instance verify -Place build/GolfChaos_src.rbxlx`.
- Tests unitaires (Studio, mode Édition ou serveur) : `require(game.ServerStorage.Tests.Runner).run()` →
  `{ passed, failed, total, failures }`.
- Pendant un Play (contexte serveur de `execute_luau`) : `game.ServerStorage.DevBridge:Invoke("state")`,
  `("logs", 30)`, `("call", "MatchService", "Dev.ForceStart")`, `("scenario", { holes = 2, hold = 1 })` puis
  `("report")` (partie automatisée complète : phases vues, erreurs, résidus).
- Vérification de compilation sans construire : exécuter dans Studio
  `local function __compileCheck() <contenu du fichier, "export type" remplacé par "type"> end return "COMPILE_OK"`.

## 5. Règles de la demande à respecter (toujours en vigueur)

- Jeu original ; pas d'assets, de personnages, de niveaux ni de marques du jeu Steam.
- **Aucun AssetId inventé** : seulement le contenu intégré `rbxasset://` (polices, sons du moteur) et des ressources
  vérifiées consignées dans `docs/MANIFESTE_ASSETS.md` ; géométrie et interface construites par code.
- Travail local ; **aucun achat, aucune activation de monétisation, aucun message, aucune publication** sans demande
  explicite. Pas de boutique Robux, **pas de pay-to-win** (cosmétiques uniquement, monnaie gagnée en jeu).
- Serveur autoritaire : le client n'envoie que des intentions ; récompenses, achats et scores ne viennent jamais du client.
- Sauvegarde : ne jamais écraser un profil existant par un profil vide si le chargement échoue (lecture seule « Failed ») ;
  verrou de session ; identifiants d'opération idempotents ; données de développement (`_Studio`) séparées des données
  réelles ; l'adaptateur mémoire est signalé « non persistant ».
- Outils et communications natifs de Roblox (chat, amis, serveurs réservés) ; pas de système parallèle qui contourne
  leurs permissions.
- Ne jamais modifier la place cloud de l'utilisateur « super combat blox ». Une synchronisation ne doit pas écraser des
  modifications Studio non exportées.
- Toujours distinguer **implémenté** de **testé dans Studio** ; n'inventer aucune capacité d'édition, d'import ou de test.

## 6. Reste à faire (ordre recommandé)

1. Terminer/intégrer l'atelier « boucle jouable » (voir annexe D, fichiers 🟧) : construire, charger tous les modules,
   tests unitaires, puis **partie complète en Play solo** (`DevBridge` `scenario`), corrections.
2. Captures d'écran (accueil, trous, interface) et catalogue des trous.
3. Objets : `ItemService` (inventaire, boîtes, effets/statuts, projectiles simulés serveur, contexte §10 de
   l'architecture) + les 17 modules `Server.Items.<Id>` + effets client + `InventoryController`.
4. Voiturettes : `VehicleService` + `VehicleController`.
5. Les 75 trous restants (5 biomes, `docs/PLAN_PARCOURS.md` + `docs/FORMAT_TROUS.md`), validation automatique de chaque
   trou (`Logic.HoleValidator` + simulation de tirs `BallService.CreateSimBall/StepSim`), décors par biome
   (`Course.Biomes.<Biome>`).
6. Cosmétiques restants (tenues, clubs, balles, effets de trou, émotes) + écrans Boutique / Personnaliser (aperçu,
   tenues enregistrées) / Défis.
7. Spectateur, tutoriel, parties privées (serveurs réservés, uniquement expérience publiée).
8. Tests multi-clients (`StudioTestService:ExecuteMultiplayerTestAsync`, 2 à 8 clients), latence, mesures de
   performance (`DevBridge perf`), vérifications d'accessibilité ; mise à jour de la matrice de couverture ; rapport final daté.

## 7. Points d'attention connus

- **Fenêtres Studio** : sur cette machine, lancer un nouveau processus Studio a fermé deux fois une fenêtre ouverte par
  l'utilisateur. Ne jamais lancer Studio quand une fenêtre de l'utilisateur est ouverte ; travailler sur des copies
  (`build/GolfChaos_src.rbxlx` → `GolfChaos_verify.rbxlx`).
- **Limite d'usage** : des ateliers de 14 agents simultanés ont été coupés trois fois sans rien livrer ; préférer
  ≤ 5 agents, des lots qui se terminent, et l'écriture des fichiers sur disque dès la première version.
- À vérifier à l'intégration : `PlayerDataService.Transact` ne doit enregistrer l'`opId` que si la fonction renvoie
  `true` (un défi « pas encore atteint » doit pouvoir être versé plus tard) ; `Schema.sanitize` doit garder les
  statistiques numériques arbitraires et les ensembles (`sets`) des défis ; noms de surfaces entre `HoleBuilder` et
  `BallService` ; forme des résumés `MatchEnded` / `PlayerFinishedHole` attendue par `RewardService` ; clés de texte
  `shop.err.*` de `CosmeticService`.
- Bruit de console connu dans le Studio de l'utilisateur : un plugin cloud (`cloud_8089767977.Animation`) affiche
  « Please Enable Script Injection » ; il ne fait pas partie du projet.

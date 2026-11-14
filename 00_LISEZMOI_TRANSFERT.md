# Transfert du projet « Golf Chaos » (dossier `super Battle blox`)

> Document de passation pour reprendre le projet dans un autre environnement (agent Claude connecté à Roblox Studio
> par MCP) **sans rien perdre ni recommencer**. Rédigé le 14/11/2026 sur la branche `dev/golf-chaos`.
> Le paquet de transfert est régénéré à tout moment par `powershell -File scripts/export-transfert.ps1`
> (sortie : `build/transfert/`). Les annexes A à D en fin de fichier sont **générées** à partir des fichiers réels au
> moment de l'export ; le statut de chaque fichier y est indiqué.

## Journal de reprise (Claude Code, à partir du 14/11/2026)

> Section tenue à jour après chaque étape, en même temps que `dashboard.html` (tableau de bord à ouvrir dans un
> navigateur, rechargé toutes les 5 secondes). Objectif de la reprise : améliorer l'existant (Luau plus propre,
> optimisé, modulaire, sans bugs) **sans repartir de zéro**. Les annexes A à E restent celles de l'export d'origine.

| Étape | Date | Contenu | Fichiers du jeu modifiés | Vérification |
| --- | --- | --- | --- | --- |
| 0 | 14/11/2026 | Lecture du document, création de `dashboard.html`, ajout de cette section | aucun | sans objet |
| 1 | 14/11/2026 | Dépôt Git local (branche `dev/reprise`). Outil de vérification `scripts/verifier.sh` (construction Rojo + analyse de types `luau-lsp`, comparée à une référence). Module unique `Server.Util.Services` (`get` / `scope(tag).call` / `.connect`) à la place des 11 copies ; spec `Services.spec` (8 tests) | `Server/Util/Services` (nouveau), `AchievementService`, `BallService`, `CombatService`, `CosmeticService`, `CourseService`, `DevService`, `LobbyService`, `MatchService`, `RewardService`, `SpawnService`, `Course/Obstacles` (−253 lignes, +37) | Construction Rojo OK ; analyse de types : aucun nouveau diagnostic hors bruit `pcall` déjà présent ailleurs. **Non testé dans Studio** (lancer `Runner.run("Services")` puis un Play solo) |
| 2 | 14/11/2026 | Sauvegarde complète : `Config.Data`, `Data.Migrations` (versions, refus d'une version future), `Data.Adapters.MemoryAdapter` (non persistant, signalé), `Data.ProfileStore` (verrou de session, jamais d'écriture après un chargement en échec), `Data.ProfileOps` (transactions tout-ou-rien, `opId` mémorisé seulement si l'opération réussit), `Services.PlayerDataService` (API du §4.2, états `Loading/Ready/Memory/Failed`, sauvegarde périodique, à la sortie et à la fermeture). Correctif : `MatchService` écrit le record Solo dans `data.bestSolo` (champ du schéma) et non plus dans `data.stats.bestSolo`. Banc d'essai local `scripts/essais-locaux.sh` | 6 nouveaux modules + `MatchService` (3 lignes) | Construction Rojo OK ; **20 tests `PlayerData.spec` exécutés et verts en local** (émulation, pas Roblox) ; `PlayerDataService` lui-même (joueurs, remotes, DataStore réel) **non testé dans Studio** |
| 3 | 14/11/2026 | Textes manquants : `Locale/fr|en/Shop` (11 clés `shop.err.*` de `CosmeticService`) et `Locale/fr|en/Cosmetics` (noms, descriptions et variantes des 52 cosmétiques existants : 25 têtes, 16 visages, 11 chaussures — 218 clés par langue). Tests ajoutés (`Locale.spec`, `Cosmetics.spec`). `scripts/verifier.sh` signale désormais toute clé de texte utilisée dans le code mais absente du français | 4 nouveaux fichiers de textes, 2 specs complétées | Tests locaux : le test « a un nom traduit pour chaque cosmétique » (en échec à l'export) passe ; 195 verts sur 198. **Non relu dans Studio** (affichage réel des textes) |
| 4 | 14/11/2026 | Audit du code existant : appels entre services (`callService`, `connect`, accès directs) confrontés aux méthodes et signaux réellement définis ; examen des diagnostics de types qui ressemblaient à des bugs | aucun | Aucune cible inexistante hors `ItemService` / `VehicleService` (pas encore écrits) ; diagnostics examinés = bruit de typage strict |
| 5 | 14/11/2026 | Émotes : `Cosmetics/Catalog/Emotes` (13 émotes, mêmes ids que `Animations.Library.Emotes`), textes `cos.emote_*` (nom + description, fr/en), `Services.EmoteService` (priorité 46 : remotes `Emote.Play` / `Emote.Stop`, vérifie existence, possession, état du personnage et délai de 0,75 s ; pose `Emote` / `EmoteStartedAt` ; s'arrête sur golf, combat, KO, visée, véhicule, mort), `Controllers.AnimationController` (priorité 70 : couches avec fondus, `joint.Transform = décalage * base` en `PreSimulation` sans accumulation, temps basé sur l'heure serveur, mode effets réduits, particules `fx`, jingle `emote_party`, arrêt de l'émote locale au déplacement) | `Locale/fr|en/Cosmetics` (+26 clés), 3 nouveaux fichiers | Tests locaux : 195 verts sur 198 (les 3 échecs = catalogues tenues, clubs, balles, effets pas encore écrits) ; le test des noms traduits et l'effectif d'émotes passent. Analyse de types : aucun diagnostic sur les nouveaux fichiers. **Non testé dans Studio** ; **réorientation du manche de club (`club = true`) non faite** ; aucun écran pour choisir une émote (`PlayEmote` existe côté client) |
| 6 | 14/11/2026 | Catalogues restants : `Catalog/Outfits` (1 par défaut + 20 tenues), `Catalog/Clubs` (1 + 15 ; convention : `Handle` avec `Attachment` « Grip » à l'origine, manche le long de −Y, face vers −Z, longueur < 4,6 studs), `Catalog/Balls` (1 + 10), `Catalog/HoleEffects` (1 + 5, `play(position, parent)`) ; 54 noms + descriptions et 23 couleurs de variantes (`cos.sc.col.*`) en fr/en. **Manche de club réorienté** : `Kit.CLUB_PIVOT`, soudure serveur `ClubGrip` (`Weld`, attribut `DefaultC0`), et `AnimationController` calcule la main dans le repère de l'UpperTorso à partir des articulations épaule/coude/poignet (aucun retard d'une image) pour aligner le manche pivot → mains, face de frappe vers la gauche. `EffectsController` écoute `Golf.Holed` et joue l'effet de trou équipé (ignoré en mode effets réduits et à l'entraînement). Émulation locale étendue (UDim/UDim2, séquences, TweenInfo, `GetBoundingBox`, `Color3:Lerp`) | 4 nouveaux catalogues, `Locale/fr|en/Cosmetics`, `Kit`, `Golf`, `CosmeticService`, `AnimationController`, `EffectsController`, `prelude.luau` | Tests locaux : 197 verts sur 198 (reste `Items.spec` : générateur aléatoire de l'émulation). Diagnostics de types : quelques avertissements d'invariance de tableau (`Variant`) déjà présents sur `Shoes`. **Non testé dans Studio** : décalages des tenues (attachements au centre des faces), orientation du manche, rendu des effets de trou |
| 7 | 14/11/2026 | Écrans de collection : `Cosmetics/Status` (état pur : équipé / possédé / achetable / pas assez de pièces / verrouillé, variante, progression du déblocage), `Controllers/ProfileController` (copie lecture seule du profil via `Data.Sync`, envoi des intentions `Shop.*` / `Emote.*`), écrans `Shop`, `Customize` (via `Screens/CosmeticBrowser` : onglets par emplacement, cartes avec pastilles de couleur, détail, achat / équipement / variante / 3 ensembles), `Challenges` (progression par catégorie via `Achievements.progress`), `Emotes` (choix d'émote, touches 1 à 8), contrôleurs `Shop` (+ toasts de `Shop.Result`), `Customize`, `Challenges` (+ toast de défi réussi), `Emote` (touche V), bouton « Émotes » dans `LobbyMenu`, textes `Locale/fr|en/Collection` (fr + en) | 12 nouveaux fichiers, `UIController`, `LobbyMenu`, `CosmeticStatus.spec` | Tests locaux : 205 verts sur 206 (reste `Items.spec`, aléatoire de l'émulation). **Non testé dans Studio** : mise en page, navigation manette, aucun aperçu 3D (pastilles de couleur à la place) |

**Vérification locale (sans Studio)** : `bash scripts/essais-locaux.sh [filtre]` exécute les specs avec l'interpréteur Luau
officiel et une émulation minimale des API Roblox (`scripts/local/prelude.luau`) : 195 tests verts sur 198 à l'étape 3. Les
3 échecs restants : catalogues de cosmétiques pas encore écrits (tenues, clubs, balles, effets, émotes — attendu), et deux
limites de l'émulation (pas de `UDim2` pour construire les modèles, générateur aléatoire différent de Roblox).
`bash scripts/verifier.sh` construit la place (`build/GolfChaos_src.rbxlx`) et liste
les diagnostics de types **nouveaux** par rapport à `build/analyse_reference.txt` (601 diagnostics d'origine, surtout du
bruit de typage strict). Outils dans `tools/` (non versionnés) : `rojo.exe` (via `scripts/install-tools.ps1`),
`luau-lsp.exe` et `globalTypes.d.luau` (dépôt GitHub `JohnnyMorganz/luau-lsp`). Cela **ne remplace pas** un test en jeu.

**Constats à la lecture (non corrigés à ce stade) :**

- Modules cités « 🟧 en cours » au §2 mais **absents de `src/`** : `Services.PlayerDataService`, `Data.ProfileStore`,
  `Data.Adapters.MemoryAdapter`, `Data.Migrations`, `Controllers.AnimationController`, `Services.EmoteService`.
  `CosmeticService`, `AchievementService` et `RewardService` dépendent de `PlayerDataService`.
- Ce dossier n'est pas un dépôt Git (le dépôt est dans `golf-chaos.bundle`, non présent ici) : pas d'historique local
  pour annuler une modification.

- Les 12 clés `shop.err.*` utilisées par `CosmeticService` (`profile`, `locked`, `unknown`, `owned`, `coins`, `slot`,
  `notOwned`, `emotesFull`, `variant`, `loadout`, `emptyLoadout`…) n'existent dans **aucun** fichier de `Shared.Locale`
  (point d'attention du §7 confirmé).
- La recherche paresseuse d'un service est **recopiée dans 11 fichiers serveur** sous 3 variantes (`getService` sans
  cache, `optionalService` avec cache et nouvel essai après 5 s, `service`) : `AchievementService`, `BallService`,
  `CombatService`, `CosmeticService`, `CourseService`, `DevService`, `LobbyService`, `MatchService`, `RewardService`,
  `SpawnService`, `Course.Obstacles`.
- Formes `PlayerFinishedHole` (`finished`, `strokes`, `par`…) et `MatchEnded` lues par `RewardService` : cohérentes avec
  ce qu'émet `MatchService` à la lecture (non vérifié en jeu).

- Un fichier `rojo.exe` (Rojo 7.4.4, daté d'août 2024) est présent à la racine sans faire partie de l'export ni des
  outils installés par la reprise (`tools/rojo.exe` = 7.7.1) : laissé en place, ignoré par Git.

**Étape en cours :** voir la dernière ligne du tableau ci-dessus et `dashboard.html`.

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
| Catalogues : 25 têtes, 15 visages (+1 défaut), 10 chaussures (+1) | `Cosmetics.Catalog.Heads/Faces/Shoes`, `Locale/*/Cosmetics` | 🟨 écrits ; noms FR/EN écrits à l'étape 3 de la reprise |
| Catalogues : 20 tenues, 15 clubs, 10 balles, 5 effets de trou, 8+ émotes cosmétiques | — | ⬜ à faire |
| Sauvegarde : schéma versionné, assainissement, opérations idempotentes, adaptateur DataStore (reprises, budgets, file par clé, isolement « _Studio », verrou de session) | `Server.Data.Schema`, `Data.Adapters.DataStoreAdapter` | 🟨 écrits |
| Sauvegarde : ProfileStore verrouillé, MemoryAdapter (non persistant, signalé), migrations, transactions, PlayerDataService | `Data.ProfileStore`, `Data.Adapters.MemoryAdapter`, `Data.Migrations`, `Data.ProfileOps`, `Services.PlayerDataService`, `Config.Data` | 🟨 écrits à l'étape 2 de la reprise (tests locaux verts ; non joués dans Studio) |
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
  par `Server.Util.Services` (`Services.get("<Nom>")`, `Services.scope(tag).call/connect` — depuis l'étape 1 de la
  reprise ; ne plus recopier de `pcall(require, …)` local) ou s'abonne à ses `Signal`. Un service absent est toléré
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

---

> Annexes générées automatiquement le 14/11/2026 10:26 (branche `dev/golf-chaos`, dernier commit `eee221a`) par `scripts/export-transfert.ps1`.
> 192 fichiers exportés, dont 84 non commités au moment de l'export (travail en cours, non vérifié).

## Annexe A — Arborescence complète (dépôt → Roblox)

Format : `Nom (Classe)` ; `*` = fichier non commité au moment de l'export (en cours d'écriture, non vérifié).

### ReplicatedStorage.Shared

````text
ReplicatedStorage.Shared (Folder) ← src/shared/
    Animations (ModuleScript)
        Library (Folder)
            Combat (ModuleScript)
            Emotes (ModuleScript)
            Golf (ModuleScript)
            Kit (ModuleScript)
    Config (Folder)
        Achievements (ModuleScript)
        Biomes (ModuleScript) *
        Course (ModuleScript) *
        Economy (ModuleScript)
        Gameplay (ModuleScript)
        ItemBoxes (ModuleScript)
        Items (ModuleScript)
        Match (ModuleScript) *
        Scoring (ModuleScript)
        Sounds (ModuleScript)
    Cosmetics (ModuleScript)
        Catalog (Folder)
            Faces (ModuleScript)
            Heads (ModuleScript)
            Shoes (ModuleScript)
        Build (ModuleScript)
    Data (Folder)
        Holes (ModuleScript)
            Coast (ModuleScript) *
            Training (ModuleScript) *
    Locale (ModuleScript)
        en (Folder)
            Achievements (ModuleScript)
            Aim (ModuleScript) *
            Controls (ModuleScript) *
            Core (ModuleScript)
            Course (ModuleScript) *
            HolesCoast (ModuleScript) *
            HolesTraining (ModuleScript) *
            Hud (ModuleScript) *
            Items (ModuleScript)
            Lobby (ModuleScript)
            Match (ModuleScript) *
            Menu (ModuleScript) *
            Results (ModuleScript) *
            Settings (ModuleScript) *
            UI (ModuleScript) *
        fr (Folder)
            Achievements (ModuleScript)
            Aim (ModuleScript) *
            Controls (ModuleScript) *
            Core (ModuleScript)
            Course (ModuleScript) *
            HolesCoast (ModuleScript) *
            HolesTraining (ModuleScript) *
            Hud (ModuleScript) *
            Items (ModuleScript)
            Lobby (ModuleScript)
            Match (ModuleScript) *
            Menu (ModuleScript) *
            Results (ModuleScript) *
            Settings (ModuleScript) *
            UI (ModuleScript) *
    Logic (Folder)
        BallMath (ModuleScript)
        HoleValidator (ModuleScript) *
        ItemOdds (ModuleScript)
        MatchStateMachine (ModuleScript)
        Playlist (ModuleScript)
        Rewards (ModuleScript)
        Scoring (ModuleScript)
    Net (ModuleScript)
        Remotes (Folder)
            Combat (ModuleScript)
            Core (ModuleScript)
            Data (ModuleScript)
            Effects (ModuleScript)
            Emote (ModuleScript)
            Golf (ModuleScript)
            Items (ModuleScript)
            Lobby (ModuleScript)
            Match (ModuleScript)
            Progress (ModuleScript)
            Shop (ModuleScript)
            Vehicles (ModuleScript)
    Util (Folder)
        GameState (ModuleScript)
        Log (ModuleScript)
        Signal (ModuleScript)
        Trove (ModuleScript)
        Validate (ModuleScript)
    Types (ModuleScript)
````

### ServerScriptService.Server

````text
ServerScriptService.Server (Script) ← src/server/init.server.luau
    Cosmetics (Folder)
    Course (Folder)
        Biomes (Folder)
            Common (ModuleScript) *
        HoleBuilder (ModuleScript) *
        LobbyBuilder (ModuleScript) *
        Obstacles (ModuleScript) *
        Props (ModuleScript) *
    Data (Folder)
        Adapters (Folder)
            DataStoreAdapter (ModuleScript)
        Schema (ModuleScript)
    Items (Folder)
    Services (Folder)
        AchievementService (ModuleScript)
        BallService (ModuleScript)
        CollisionService (ModuleScript)
        CombatService (ModuleScript)
        CosmeticService (ModuleScript)
        CourseService (ModuleScript) *
        DevService (ModuleScript)
        LobbyService (ModuleScript) *
        MatchService (ModuleScript) *
        MovementService (ModuleScript)
        NetworkValidation (ModuleScript)
        RewardService (ModuleScript)
        SpawnService (ModuleScript) *
````

### StarterPlayer.StarterPlayerScripts.Client

````text
StarterPlayer.StarterPlayerScripts.Client (LocalScript) ← src/client/init.client.luau
    Controllers (Folder)
        ActionController (ModuleScript) *
        BallVisualController (ModuleScript) *
        CameraController (ModuleScript)
        EffectsController (ModuleScript)
        GolfAimController (ModuleScript) *
        HUDController (ModuleScript) *
        InputController (ModuleScript)
        MenuController (ModuleScript) *
        NotificationController (ModuleScript) *
        SettingsController (ModuleScript) *
        UIController (ModuleScript) *
    Effects (Folder)
        Core (ModuleScript)
    UI (Folder)
        Components (Folder)
            Base (ModuleScript) *
            Button (ModuleScript)
            Cycler (ModuleScript) *
            Grid (ModuleScript) *
            IconButton (ModuleScript) *
            Label (ModuleScript)
            Modal (ModuleScript) *
            Panel (ModuleScript) *
            ProgressBar (ModuleScript) *
            Slider (ModuleScript) *
            Tabs (ModuleScript) *
            TeamMarker (ModuleScript) *
            Toast (ModuleScript) *
            Toggle (ModuleScript) *
        Hud (Folder)
            ControlsBar (ModuleScript) *
            Feed (ModuleScript) *
            HoleCard (ModuleScript) *
            InfoPanel (ModuleScript) *
            Inventory (ModuleScript) *
            Kit (ModuleScript) *
            PracticePanel (ModuleScript) *
            Scoreboard (ModuleScript) *
            TimerBanner (ModuleScript) *
        Screens (Folder)
            Countdown (ModuleScript) *
            HoleIntro (ModuleScript) *
            HoleResults (ModuleScript) *
            HostSettings (ModuleScript) *
            Loading (ModuleScript) *
            LobbyMenu (ModuleScript) *
            PhaseBanner (ModuleScript) *
            Podium (ModuleScript) *
            Settings (ModuleScript) *
            Util (ModuleScript) *
        AimPanel (ModuleScript) *
        ScreenManager (ModuleScript) *
        Theme (ModuleScript) *
````

### ServerStorage.Tests

````text
ServerStorage.Tests (Folder) ← src/tests/
    Specs (Folder)
        BallMath.spec (ModuleScript)
        Cosmetics.spec (ModuleScript)
        Holes.spec (ModuleScript) *
        Items.spec (ModuleScript)
        Locale.spec (ModuleScript)
        MatchStateMachine.spec (ModuleScript) *
        NetDefinitions.spec (ModuleScript)
        Playlist.spec (ModuleScript) *
        Progression.spec (ModuleScript)
        Scoring.spec (ModuleScript) *
        Util.spec (ModuleScript)
    Runner (ModuleScript)
````

## Annexe B — Remotes (créés à l'exécution dans `ReplicatedStorage.Remotes` par `Shared.Net`)

Définis dans `src/shared/Net/Remotes/*.luau`. `args` = types vérifiés côté serveur avant le gestionnaire (surplus rejeté) ; `rate`/`burst` = seau à jetons par joueur.

| Remote | Fichier | Type | Sens | Arguments (client → serveur) | Débit | Description |
| --- | --- | --- | --- | --- | --- | --- |
| `Combat.Punch` | Combat | Event | ToServer | "integer", "Vector3" | 3/s, rafale 2 | Client -> serveur : frappe de proximité (coup de poing/club) dans la direction regardée. (roundId, direction) |
| `Combat.Dive` | Combat | Event | ToServer | "integer", "Vector3" | 2/s, rafale 1 | Client -> serveur : plongeon / esquive dans une direction. (roundId, direction) |
| `Combat.KO` | Combat | Event | ToClient |  |  | Serveur -> tous : annonce de KO. (victimUserId, attackerUserId (0 si aucun), source : "ball" \| "punch" \| itemId...) |
| `Combat.Feedback` | Combat | Event | ToClient |  |  | Serveur -> client : retour visuel d'une action de combat refusée ou réussie. (action, ok, raison?) |
| `Core.Notify` | Core | Event | ToClient |  |  | Serveur -> client : message court affiché en toast. (texte, type "info" \| "warn" \| "hit" \| "success") |
| `Core.NotifyKey` | Core | Event | ToClient |  |  | Serveur -> client : clé de traduction + variables (préféré à Core.Notify pour les textes du jeu). |
| `Core.ClientReady` | Core | Event | ToServer | (aucun) | 1/s, rafale 2 | Client -> serveur : le client signale qu'il a fini de charger son interface (pour les arrivées tardives). |
| `Data.Sync` | Data | Event | ToClient |  |  | Serveur -> client (propriétaire) : instantané (partiel) du profil. ({ status, persistent, coins, owned, equipped, loadouts, achievements, stats, settings, version }) |
| `Data.SaveSettings` | Data | Event | ToServer | "table" | 1/s, rafale 3 | Client -> serveur : enregistrer les préférences (table clé -> valeur, validée par clé côté serveur). |
| `Data.RequestSync` | Data | Event | ToServer | (aucun) | 0.2/s, rafale 2 | Client -> serveur : demander un nouvel instantané (après reconnexion de l'interface). |
| `Effects.Play` | Effects | Event | ToClient |  |  | Serveur -> clients : jouer un effet du registre client/Effects/*. (nomEffet, paramètres) |
| `Effects.Sound` | Effects | Event | ToClient |  |  | Serveur -> clients : jouer un son de Config/Sounds. (nomSon, position Vector3? (nil = son d'interface), volumeRelatif?) |
| `Effects.Music` | Effects | Event | ToClient |  |  | Serveur -> clients : changer la musique d'ambiance. (nomMusique ou "" pour couper) |
| `Effects.Burst` | Effects | Unreliable | ToClient |  |  | Serveur -> client : effets fréquents à faible priorité (traînées, étincelles), perte acceptable. |
| `Emote.Play` | Emote | Event | ToServer | "string:40" | 1/s, rafale 2 | Client -> serveur : jouer une émote possédée. (identifiant du cosmétique "Emote", 40 caractères max) |
| `Emote.Stop` | Emote | Event | ToServer | (aucun) | 2/s, rafale 3 | Client -> serveur : arrêter l'émote en cours (déplacement local, bouton « Arrêter »). |
| `Golf.AimState` | Golf | Event | ToServer | "integer", "boolean" | 6/s, rafale 6 | Client -> serveur : entrer (true) / quitter (false) le mode visée. (roundId, isAiming) |
| `Golf.SwingStart` | Golf | Event | ToServer | "integer" | 6/s, rafale 4 | Client -> serveur : démarrage de la jauge de puissance (horodaté par le serveur). (roundId) |
| `Golf.Shoot` | Golf | Event | ToServer | "integer", "Vector3", "number", "number?", "string:8?" | 4/s, rafale 3 | Client -> serveur : frappe. (roundId, direction horizontale, loft en degrés, puissance indicative 0..1, type "Drive"\|"Chip"\|"Putt") La puissance est RECALCULÉE par le serveur depuis l'horodatage de Golf.SwingStart (tolérance bornée). |
| `Golf.ResetBall` | Golf | Event | ToServer | "integer" | 0.5/s, rafale 1 | Client -> serveur : balle bloquée -> retour à la dernière position valide (pénalité configurable). (roundId) |
| `Golf.AimCancelled` | Golf | Event | ToClient |  |  | Serveur -> client (tireur) : visée annulée par le serveur. (raison : "stun" \| "horn" \| "too_far" \| "invalid" \| "unavailable" \| "respawn" \| "phase") |
| `Golf.ShotAccepted` | Golf | Event | ToClient |  |  | Serveur -> client (tireur) : frappe acceptée. ({ strokes, power, shotType }) |
| `Golf.Holed` | Golf | Event | ToClient |  |  | Serveur -> tous : une balle est entrée dans le trou. (userId, { strokes, fromDistance, holeInOne, effectId }) |
| `Golf.BallReset` | Golf | Event | ToClient |  |  | Serveur -> client concerné : balle replacée (eau, hors limites, vide, blocage). (raison, pénalité) |
| `Items.Select` | Items | Event | ToServer | "integer" | 8/s, rafale 6 | Client -> serveur : sélectionner une case d'inventaire (1..capacité). |
| `Items.Use` | Items | Event | ToServer | "integer", "integer", "Vector3", "integer?" | 4/s, rafale 3 | Client -> serveur : utiliser l'objet d'une case. (roundId, case, direction de visée, userId de la cible suggérée ou nil) La cible suggérée n'est qu'une indication : le serveur la revalide (ou choisit lui-même selon la règle de l'objet). |
| `Items.UseStart` | Items | Event | ToServer | "integer", "integer" | 4/s, rafale 3 | Client -> serveur : début d'utilisation maintenue (verrouillage de fusée, charge du rail). (roundId, case) |
| `Items.UseCancel` | Items | Event | ToServer | "integer", "integer" | 4/s, rafale 3 | Client -> serveur : annulation d'une utilisation maintenue. (roundId, case) |
| `Items.Gained` | Items | Event | ToClient |  |  | Serveur -> client (propriétaire) : objet obtenu. (itemId, case) |
| `Items.Feedback` | Items | Event | ToClient |  |  | Serveur -> client : retour d'utilisation (refus ou information). (cléLocale, variables?) |
| `Items.Projectile` | Items | Event | ToClient |  |  | Serveur -> tous : un projectile simulé par le serveur apparaît. (id, type, origine, vitesse Vector3, paramètres) |
| `Items.ProjectileUpdate` | Items | Unreliable | ToClient |  |  | Serveur -> tous : correction de trajectoire d'un projectile guidé (perte acceptable). (id, position, vitesse) |
| `Items.ProjectileEnd` | Items | Event | ToClient |  |  | Serveur -> tous : fin d'un projectile. (id, position, raison "hit" \| "expire" \| "deflect" \| "dodge") |
| `Items.LockState` | Items | Event | ToClient |  |  | Serveur -> client : état du verrouillage pour le tireur. (userId de la cible verrouillée, 0 si aucun) |
| `Items.Warning` | Items | Event | ToClient |  |  | Serveur -> client : avertissement à une cible (cercle orbital, viseur laser, nuage). (itemId, attackerUserId) |
| `Lobby.SetSetting` | Lobby | Event | ToServer | "string:24", "any" | 8/s, rafale 8 | Client -> serveur : modifier un réglage de partie (hôte). (clé, valeur) — clés : voir Types.MatchSettings |
| `Lobby.SetCustomPlaylist` | Lobby | Event | ToServer | "table" | 1/s, rafale 2 | Client -> serveur : playlist personnalisée (hôte). (liste d'ids de trous, 1..18 éléments) |
| `Lobby.SetReady` | Lobby | Event | ToServer | "boolean" | 2/s, rafale 3 | Client -> serveur : se déclarer prêt / pas prêt. |
| `Lobby.Advance` | Lobby | Event | ToServer | (aucun) | 0.5/s, rafale 2 | Client -> serveur : ouvrir la préparation (Lobby -> Preparing) ou lancer la partie (Preparing -> Loading) (hôte). |
| `Lobby.Cancel` | Lobby | Event | ToServer | (aucun) | 0.5/s, rafale 2 | Client -> serveur : revenir à l'accueil depuis la préparation (hôte). |
| `Lobby.SetTeam` | Lobby | Event | ToServer | "string:8" | 1/s, rafale 3 | Client -> serveur : choisir son équipe ("Red" \| "Blue" \| "Auto"). |
| `Lobby.BalanceTeams` | Lobby | Event | ToServer | (aucun) | 0.5/s, rafale 1 | Client -> serveur : équilibrer les équipes automatiquement (hôte). |
| `Lobby.CreatePrivate` | Lobby | Event | ToServer | (aucun) | 0.1/s, rafale 1 | Client -> serveur : créer une partie privée entre amis (serveur réservé ; expérience publiée uniquement). |
| `Lobby.RequestTraining` | Lobby | Event | ToServer | "string:12" | 0.5/s, rafale 2 | Client -> serveur : demander une session d'entraînement (Driving Range / tutoriel). (type : "Range" \| "Tutorial") |
| `Lobby.State` | Lobby | Event | ToClient |  |  | Serveur -> tous : instantané du salon. ({ hostUserId, settings, players = { { userId, name, ready, team, spectator } }, canStart }) |
| `Match.PlayerFinished` | Match | Event | ToClient |  |  | Serveur -> tous : un joueur a terminé le trou. ({ userId, name, finishOrder, strokes, par, points, bonuses }) |
| `Match.HoleResults` | Match | Event | ToClient |  |  | Serveur -> tous : résultats du trou. ({ holeId, holeName, par, results = { HoleResult }, teamScores = { Red, Blue }, teamWinner }) |
| `Match.Podium` | Match | Event | ToClient |  |  | Serveur -> tous : fin de partie. ({ matchId, mode, standings = { { userId, name, team, points, strokes, rank } }, teamScores, winner }) |
| `Match.Announce` | Match | Event | ToClient |  |  | Serveur -> tous ou un joueur : annonce localisée. (cléLocale, variables?) |
| `Match.Forfeit` | Match | Event | ToServer | "integer" | 0.5/s, rafale 1 | Client -> serveur : abandonner le trou courant (reste spectateur du trou). (roundId) |
| `Match.SetSpectator` | Match | Event | ToServer | "boolean" | 1/s, rafale 2 | Client -> serveur : préférer être spectateur à la prochaine partie (true) ou participant (false). |
| `Match.Heartbeat` | Match | Event | ToServer | "integer" | 0.5/s, rafale 2 | Client -> serveur : signaler une activité (anti-AFK) quand le joueur bouge la caméra/l'avatar. (roundId) |
| `Progress.AchievementCompleted` | Progress | Event | ToClient |  |  | Serveur -> client : défi réussi. (achievementId, pièces versées) |
| `Progress.MatchReward` | Progress | Event | ToClient |  |  | Serveur -> client : récompense de fin de partie. ({ total, breakdown, eligible, reason? }) |
| `Shop.Buy` | Shop | Event | ToServer | "string:48" | 2/s, rafale 3 | Client -> serveur : acheter un cosmétique avec des pièces. (cosmeticId) |
| `Shop.Equip` | Shop | Event | ToServer | "string:16", "string:48?" | 4/s, rafale 4 | Client -> serveur : équiper (ou retirer si nil) un cosmétique possédé dans un emplacement. (emplacement, cosmeticId?) |
| `Shop.SetVariant` | Shop | Event | ToServer | "string:48", "integer" | 4/s, rafale 4 | Client -> serveur : choisir la variante de couleur d'un cosmétique possédé. (cosmeticId, indice) |
| `Shop.SaveLoadout` | Shop | Event | ToServer | "integer" | 1/s, rafale 2 | Client -> serveur : enregistrer la tenue actuelle dans un ensemble (1..3). |
| `Shop.UseLoadout` | Shop | Event | ToServer | "integer" | 1/s, rafale 2 | Client -> serveur : porter un ensemble enregistré (1..3). |
| `Shop.Result` | Shop | Event | ToClient |  |  | Serveur -> client : résultat d'une action. (action, ok, cléLocale?, données?) |
| `Vehicles.Reset` | Vehicles | Event | ToServer | "integer" | 0.3/s, rafale 1 | Client -> serveur : remettre son kart à l'endroit (conducteur, délai de recharge). (roundId) |
| `Vehicles.Horn` | Vehicles | Event | ToServer | (aucun) | 1/s, rafale 2 | Client -> serveur : klaxon du kart (cosmétique, son pour tous). |
| `Vehicles.State` | Vehicles | Event | ToClient |  |  | Serveur -> client : état du véhicule occupé. ({ cartId, seatIndex, isDriver, structure, expiresAt } ou nil en descendant) |

63 remotes au total.

## Annexe C — Services et contrôleurs (ordre de démarrage réel, lu dans les fichiers)

| Côté | Module | Priority | Chemin Roblox | Statut |
| --- | --- | --- | --- | --- |
| serveur | CollisionService | 0 | `ServerScriptService.Server.Services.CollisionService` | commité |
| serveur | NetworkValidation | 8 | `ServerScriptService.Server.Services.NetworkValidation` | commité |
| serveur | MovementService | 10 | `ServerScriptService.Server.Services.MovementService` | commité |
| serveur | CombatService | 15 | `ServerScriptService.Server.Services.CombatService` | commité |
| serveur | BallService | 20 | `ServerScriptService.Server.Services.BallService` | commité |
| serveur | CourseService | 25 | `ServerScriptService.Server.Services.CourseService` | nouveau, non commité (en cours) |
| serveur | CosmeticService | 40 | `ServerScriptService.Server.Services.CosmeticService` | commité |
| serveur | AchievementService | 45 | `ServerScriptService.Server.Services.AchievementService` | commité |
| serveur | RewardService | 50 | `ServerScriptService.Server.Services.RewardService` | commité |
| serveur | SpawnService | 55 | `ServerScriptService.Server.Services.SpawnService` | nouveau, non commité (en cours) |
| serveur | LobbyService | 60 | `ServerScriptService.Server.Services.LobbyService` | nouveau, non commité (en cours) |
| serveur | MatchService | 70 | `ServerScriptService.Server.Services.MatchService` | nouveau, non commité (en cours) |
| serveur | DevService | 90 | `ServerScriptService.Server.Services.DevService` | commité |
| client | InputController | 0 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController` | commité |
| client | SettingsController | 5 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.SettingsController` | nouveau, non commité (en cours) |
| client | UIController | 10 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.UIController` | nouveau, non commité (en cours) |
| client | CameraController | 20 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController` | commité |
| client | GolfAimController | 30 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.GolfAimController` | nouveau, non commité (en cours) |
| client | ActionController | 35 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ActionController` | nouveau, non commité (en cours) |
| client | BallVisualController | 36 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.BallVisualController` | nouveau, non commité (en cours) |
| client | HUDController | 40 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController` | nouveau, non commité (en cours) |
| client | MenuController | 50 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.MenuController` | nouveau, non commité (en cours) |
| client | NotificationController | 60 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.NotificationController` | nouveau, non commité (en cours) |
| client | EffectsController | 65 | `StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController` | commité |

## Annexe D — Index de tous les fichiers exportés

| Fichier du dépôt | Chemin Roblox | Classe | Lignes | Octets | Statut | Partie |
| --- | --- | --- | ---: | ---: | --- | --- |
| `default.project.json` | — | — | 75 | 1 787 | commité | `01_projet.md` |
| `.gitignore` | — | — | 17 | 290 | commité | `01_projet.md` |
| `.gitattributes` | — | — | 8 | 133 | commité | `01_projet.md` |
| `README.md` | — | — | 83 | 3 924 | commité | `01_projet.md` |
| `scripts/build.ps1` | — | — | 15 | 793 | commité | `01_projet.md` |
| `scripts/export-transfert.ps1` | — | — | 384 | 22 398 | commité | `01_projet.md` |
| `scripts/install-tools.ps1` | — | — | 35 | 1 740 | commité | `01_projet.md` |
| `scripts/open-studio.ps1` | — | — | 47 | 2 506 | commité | `01_projet.md` |
| `src/server/Course/Biomes/Common.luau` | `ServerScriptService.Server.Course.Biomes.Common` | ModuleScript | 558 | 22 593 | nouveau, non commité (en cours) | `02_serveur-1.md` |
| `src/server/Course/HoleBuilder.luau` | `ServerScriptService.Server.Course.HoleBuilder` | ModuleScript | 1 075 | 44 348 | nouveau, non commité (en cours) | `02_serveur-1.md` |
| `src/server/Course/LobbyBuilder.luau` | `ServerScriptService.Server.Course.LobbyBuilder` | ModuleScript | 976 | 51 189 | nouveau, non commité (en cours) | `02_serveur-1.md` |
| `src/server/Course/Obstacles.luau` | `ServerScriptService.Server.Course.Obstacles` | ModuleScript | 1 685 | 74 200 | nouveau, non commité (en cours) | `02_serveur-1.md` |
| `src/server/Course/Props.luau` | `ServerScriptService.Server.Course.Props` | ModuleScript | 664 | 25 509 | nouveau, non commité (en cours) | `02_serveur-1.md` |
| `src/server/Data/Adapters/DataStoreAdapter.luau` | `ServerScriptService.Server.Data.Adapters.DataStoreAdapter` | ModuleScript | 967 | 34 160 | commité | `03_serveur-2.md` |
| `src/server/Data/Schema.luau` | `ServerScriptService.Server.Data.Schema` | ModuleScript | 1 355 | 41 353 | commité | `03_serveur-2.md` |
| `src/server/init.server.luau` | `ServerScriptService.Server` | Script | 86 | 2 840 | commité | `03_serveur-2.md` |
| `src/server/Services/AchievementService.luau` | `ServerScriptService.Server.Services.AchievementService` | ModuleScript | 327 | 11 945 | commité | `03_serveur-2.md` |
| `src/server/Services/BallService.luau` | `ServerScriptService.Server.Services.BallService` | ModuleScript | 3 035 | 102 026 | commité | `03_serveur-2.md` |
| `src/server/Services/CollisionService.luau` | `ServerScriptService.Server.Services.CollisionService` | ModuleScript | 366 | 12 932 | commité | `03_serveur-2.md` |
| `src/server/Services/CombatService.luau` | `ServerScriptService.Server.Services.CombatService` | ModuleScript | 1 186 | 36 869 | commité | `04_serveur-3.md` |
| `src/server/Services/CosmeticService.luau` | `ServerScriptService.Server.Services.CosmeticService` | ModuleScript | 593 | 20 207 | commité | `04_serveur-3.md` |
| `src/server/Services/CourseService.luau` | `ServerScriptService.Server.Services.CourseService` | ModuleScript | 1 850 | 63 277 | nouveau, non commité (en cours) | `04_serveur-3.md` |
| `src/server/Services/DevService.luau` | `ServerScriptService.Server.Services.DevService` | ModuleScript | 432 | 14 293 | commité | `04_serveur-3.md` |
| `src/server/Services/LobbyService.luau` | `ServerScriptService.Server.Services.LobbyService` | ModuleScript | 1 158 | 36 918 | nouveau, non commité (en cours) | `04_serveur-3.md` |
| `src/server/Services/MatchService.luau` | `ServerScriptService.Server.Services.MatchService` | ModuleScript | 2 725 | 83 455 | nouveau, non commité (en cours) | `05_serveur-4.md` |
| `src/server/Services/MovementService.luau` | `ServerScriptService.Server.Services.MovementService` | ModuleScript | 654 | 20 226 | commité | `05_serveur-4.md` |
| `src/server/Services/NetworkValidation.luau` | `ServerScriptService.Server.Services.NetworkValidation` | ModuleScript | 385 | 11 720 | commité | `05_serveur-4.md` |
| `src/server/Services/RewardService.luau` | `ServerScriptService.Server.Services.RewardService` | ModuleScript | 300 | 9 961 | commité | `05_serveur-4.md` |
| `src/server/Services/SpawnService.luau` | `ServerScriptService.Server.Services.SpawnService` | ModuleScript | 786 | 25 726 | nouveau, non commité (en cours) | `05_serveur-4.md` |
| `src/shared/Animations/init.luau` | `ReplicatedStorage.Shared.Animations` | ModuleScript | 194 | 6 491 | commité | `06_partage-1.md` |
| `src/shared/Animations/Library/Combat.luau` | `ReplicatedStorage.Shared.Animations.Library.Combat` | ModuleScript | 244 | 7 418 | commité | `06_partage-1.md` |
| `src/shared/Animations/Library/Emotes.luau` | `ReplicatedStorage.Shared.Animations.Library.Emotes` | ModuleScript | 862 | 30 784 | commité | `06_partage-1.md` |
| `src/shared/Animations/Library/Golf.luau` | `ReplicatedStorage.Shared.Animations.Library.Golf` | ModuleScript | 403 | 13 068 | commité | `06_partage-1.md` |
| `src/shared/Animations/Library/Kit.luau` | `ReplicatedStorage.Shared.Animations.Library.Kit` | ModuleScript | 484 | 16 821 | commité | `06_partage-1.md` |
| `src/shared/Config/Achievements.luau` | `ReplicatedStorage.Shared.Config.Achievements` | ModuleScript | 124 | 5 485 | commité | `06_partage-1.md` |
| `src/shared/Config/Biomes.luau` | `ReplicatedStorage.Shared.Config.Biomes` | ModuleScript | 508 | 20 538 | nouveau, non commité (en cours) | `06_partage-1.md` |
| `src/shared/Config/Course.luau` | `ReplicatedStorage.Shared.Config.Course` | ModuleScript | 433 | 16 172 | modifié depuis le dernier commit (en cours) | `06_partage-1.md` |
| `src/shared/Config/Economy.luau` | `ReplicatedStorage.Shared.Config.Economy` | ModuleScript | 39 | 1 902 | commité | `06_partage-1.md` |
| `src/shared/Config/Gameplay.luau` | `ReplicatedStorage.Shared.Config.Gameplay` | ModuleScript | 528 | 27 044 | commité | `06_partage-1.md` |
| `src/shared/Config/ItemBoxes.luau` | `ReplicatedStorage.Shared.Config.ItemBoxes` | ModuleScript | 29 | 1 206 | commité | `06_partage-1.md` |
| `src/shared/Config/Items.luau` | `ReplicatedStorage.Shared.Config.Items` | ModuleScript | 253 | 14 323 | commité | `06_partage-1.md` |
| `src/shared/Config/Match.luau` | `ReplicatedStorage.Shared.Config.Match` | ModuleScript | 241 | 12 026 | modifié depuis le dernier commit (en cours) | `06_partage-1.md` |
| `src/shared/Config/Scoring.luau` | `ReplicatedStorage.Shared.Config.Scoring` | ModuleScript | 99 | 4 126 | commité | `06_partage-1.md` |
| `src/shared/Config/Sounds.luau` | `ReplicatedStorage.Shared.Config.Sounds` | ModuleScript | 484 | 14 651 | commité | `06_partage-1.md` |
| `src/shared/Cosmetics/Build.luau` | `ReplicatedStorage.Shared.Cosmetics.Build` | ModuleScript | 185 | 7 544 | commité | `06_partage-1.md` |
| `src/shared/Cosmetics/Catalog/Faces.luau` | `ReplicatedStorage.Shared.Cosmetics.Catalog.Faces` | ModuleScript | 912 | 37 839 | commité | `07_partage-2.md` |
| `src/shared/Cosmetics/Catalog/Heads.luau` | `ReplicatedStorage.Shared.Cosmetics.Catalog.Heads` | ModuleScript | 1 047 | 44 227 | commité | `07_partage-2.md` |
| `src/shared/Cosmetics/Catalog/Shoes.luau` | `ReplicatedStorage.Shared.Cosmetics.Catalog.Shoes` | ModuleScript | 347 | 18 122 | commité | `07_partage-2.md` |
| `src/shared/Cosmetics/init.luau` | `ReplicatedStorage.Shared.Cosmetics` | ModuleScript | 183 | 6 693 | commité | `07_partage-2.md` |
| `src/shared/Data/Holes/Coast.luau` | `ReplicatedStorage.Shared.Data.Holes.Coast` | ModuleScript | 308 | 11 760 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Data/Holes/init.luau` | `ReplicatedStorage.Shared.Data.Holes` | ModuleScript | 124 | 3 601 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Data/Holes/Training.luau` | `ReplicatedStorage.Shared.Data.Holes.Training` | ModuleScript | 141 | 5 172 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Achievements.luau` | `ReplicatedStorage.Shared.Locale.en.Achievements` | ModuleScript | 93 | 4 731 | commité | `07_partage-2.md` |
| `src/shared/Locale/en/Aim.luau` | `ReplicatedStorage.Shared.Locale.en.Aim` | ModuleScript | 128 | 5 977 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Controls.luau` | `ReplicatedStorage.Shared.Locale.en.Controls` | ModuleScript | 83 | 3 025 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Core.luau` | `ReplicatedStorage.Shared.Locale.en.Core` | ModuleScript | 16 | 510 | commité | `07_partage-2.md` |
| `src/shared/Locale/en/Course.luau` | `ReplicatedStorage.Shared.Locale.en.Course` | ModuleScript | 70 | 2 669 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/HolesCoast.luau` | `ReplicatedStorage.Shared.Locale.en.HolesCoast` | ModuleScript | 16 | 863 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/HolesTraining.luau` | `ReplicatedStorage.Shared.Locale.en.HolesTraining` | ModuleScript | 12 | 585 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Hud.luau` | `ReplicatedStorage.Shared.Locale.en.Hud` | ModuleScript | 76 | 2 706 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Items.luau` | `ReplicatedStorage.Shared.Locale.en.Items` | ModuleScript | 65 | 4 577 | commité | `07_partage-2.md` |
| `src/shared/Locale/en/Lobby.luau` | `ReplicatedStorage.Shared.Locale.en.Lobby` | ModuleScript | 172 | 9 484 | commité | `07_partage-2.md` |
| `src/shared/Locale/en/Match.luau` | `ReplicatedStorage.Shared.Locale.en.Match` | ModuleScript | 182 | 8 863 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Menu.luau` | `ReplicatedStorage.Shared.Locale.en.Menu` | ModuleScript | 71 | 3 016 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Results.luau` | `ReplicatedStorage.Shared.Locale.en.Results` | ModuleScript | 50 | 2 151 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/Settings.luau` | `ReplicatedStorage.Shared.Locale.en.Settings` | ModuleScript | 38 | 1 516 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/en/UI.luau` | `ReplicatedStorage.Shared.Locale.en.UI` | ModuleScript | 31 | 882 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Achievements.luau` | `ReplicatedStorage.Shared.Locale.fr.Achievements` | ModuleScript | 93 | 4 920 | commité | `07_partage-2.md` |
| `src/shared/Locale/fr/Aim.luau` | `ReplicatedStorage.Shared.Locale.fr.Aim` | ModuleScript | 128 | 6 325 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Controls.luau` | `ReplicatedStorage.Shared.Locale.fr.Controls` | ModuleScript | 84 | 3 197 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Core.luau` | `ReplicatedStorage.Shared.Locale.fr.Core` | ModuleScript | 16 | 560 | commité | `07_partage-2.md` |
| `src/shared/Locale/fr/Course.luau` | `ReplicatedStorage.Shared.Locale.fr.Course` | ModuleScript | 73 | 3 179 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/HolesCoast.luau` | `ReplicatedStorage.Shared.Locale.fr.HolesCoast` | ModuleScript | 17 | 1 106 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/HolesTraining.luau` | `ReplicatedStorage.Shared.Locale.fr.HolesTraining` | ModuleScript | 14 | 835 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Hud.luau` | `ReplicatedStorage.Shared.Locale.fr.Hud` | ModuleScript | 74 | 2 807 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Items.luau` | `ReplicatedStorage.Shared.Locale.fr.Items` | ModuleScript | 65 | 4 929 | commité | `07_partage-2.md` |
| `src/shared/Locale/fr/Lobby.luau` | `ReplicatedStorage.Shared.Locale.fr.Lobby` | ModuleScript | 172 | 10 309 | commité | `07_partage-2.md` |
| `src/shared/Locale/fr/Match.luau` | `ReplicatedStorage.Shared.Locale.fr.Match` | ModuleScript | 182 | 9 446 | modifié depuis le dernier commit (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Menu.luau` | `ReplicatedStorage.Shared.Locale.fr.Menu` | ModuleScript | 72 | 3 371 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Results.luau` | `ReplicatedStorage.Shared.Locale.fr.Results` | ModuleScript | 50 | 2 305 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/Settings.luau` | `ReplicatedStorage.Shared.Locale.fr.Settings` | ModuleScript | 38 | 1 623 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/fr/UI.luau` | `ReplicatedStorage.Shared.Locale.fr.UI` | ModuleScript | 31 | 960 | nouveau, non commité (en cours) | `07_partage-2.md` |
| `src/shared/Locale/init.luau` | `ReplicatedStorage.Shared.Locale` | ModuleScript | 127 | 3 392 | commité | `08_partage-3.md` |
| `src/shared/Logic/BallMath.luau` | `ReplicatedStorage.Shared.Logic.BallMath` | ModuleScript | 648 | 26 597 | commité | `08_partage-3.md` |
| `src/shared/Logic/HoleValidator.luau` | `ReplicatedStorage.Shared.Logic.HoleValidator` | ModuleScript | 724 | 27 065 | nouveau, non commité (en cours) | `08_partage-3.md` |
| `src/shared/Logic/ItemOdds.luau` | `ReplicatedStorage.Shared.Logic.ItemOdds` | ModuleScript | 82 | 2 776 | commité | `08_partage-3.md` |
| `src/shared/Logic/MatchStateMachine.luau` | `ReplicatedStorage.Shared.Logic.MatchStateMachine` | ModuleScript | 158 | 5 577 | commité | `08_partage-3.md` |
| `src/shared/Logic/Playlist.luau` | `ReplicatedStorage.Shared.Logic.Playlist` | ModuleScript | 397 | 13 142 | commité | `08_partage-3.md` |
| `src/shared/Logic/Rewards.luau` | `ReplicatedStorage.Shared.Logic.Rewards` | ModuleScript | 101 | 3 259 | commité | `08_partage-3.md` |
| `src/shared/Logic/Scoring.luau` | `ReplicatedStorage.Shared.Logic.Scoring` | ModuleScript | 632 | 22 406 | commité | `08_partage-3.md` |
| `src/shared/Net/init.luau` | `ReplicatedStorage.Shared.Net` | ModuleScript | 340 | 11 086 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Combat.luau` | `ReplicatedStorage.Shared.Net.Remotes.Combat` | ModuleScript | 14 | 895 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Core.luau` | `ReplicatedStorage.Shared.Net.Remotes.Core` | ModuleScript | 10 | 640 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Data.luau` | `ReplicatedStorage.Shared.Net.Remotes.Data` | ModuleScript | 14 | 867 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Effects.luau` | `ReplicatedStorage.Shared.Net.Remotes.Effects` | ModuleScript | 16 | 925 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Emote.luau` | `ReplicatedStorage.Shared.Net.Remotes.Emote` | ModuleScript | 15 | 989 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Golf.luau` | `ReplicatedStorage.Shared.Net.Remotes.Golf` | ModuleScript | 24 | 1 954 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Items.luau` | `ReplicatedStorage.Shared.Net.Remotes.Items` | ModuleScript | 31 | 2 499 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Lobby.luau` | `ReplicatedStorage.Shared.Net.Remotes.Lobby` | ModuleScript | 27 | 2 156 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Match.luau` | `ReplicatedStorage.Shared.Net.Remotes.Match` | ModuleScript | 21 | 1 579 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Progress.luau` | `ReplicatedStorage.Shared.Net.Remotes.Progress` | ModuleScript | 10 | 444 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Shop.luau` | `ReplicatedStorage.Shared.Net.Remotes.Shop` | ModuleScript | 20 | 1 426 | commité | `08_partage-3.md` |
| `src/shared/Net/Remotes/Vehicles.luau` | `ReplicatedStorage.Shared.Net.Remotes.Vehicles` | ModuleScript | 14 | 851 | commité | `08_partage-3.md` |
| `src/shared/Types.luau` | `ReplicatedStorage.Shared.Types` | ModuleScript | 143 | 6 305 | commité | `08_partage-3.md` |
| `src/shared/Util/GameState.luau` | `ReplicatedStorage.Shared.Util.GameState` | ModuleScript | 63 | 1 949 | commité | `08_partage-3.md` |
| `src/shared/Util/Log.luau` | `ReplicatedStorage.Shared.Util.Log` | ModuleScript | 87 | 2 454 | commité | `08_partage-3.md` |
| `src/shared/Util/Signal.luau` | `ReplicatedStorage.Shared.Util.Signal` | ModuleScript | 106 | 2 895 | commité | `08_partage-3.md` |
| `src/shared/Util/Trove.luau` | `ReplicatedStorage.Shared.Util.Trove` | ModuleScript | 113 | 3 282 | commité | `08_partage-3.md` |
| `src/shared/Util/Validate.luau` | `ReplicatedStorage.Shared.Util.Validate` | ModuleScript | 143 | 4 747 | commité | `08_partage-3.md` |
| `src/client/Controllers/ActionController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ActionController` | ModuleScript | 343 | 11 111 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/BallVisualController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.BallVisualController` | ModuleScript | 758 | 23 919 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/CameraController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController` | ModuleScript | 776 | 25 779 | commité | `09_client-1.md` |
| `src/client/Controllers/EffectsController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController` | ModuleScript | 403 | 12 382 | commité | `09_client-1.md` |
| `src/client/Controllers/GolfAimController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.GolfAimController` | ModuleScript | 1 576 | 50 739 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/HUDController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController` | ModuleScript | 710 | 22 116 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/InputController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController` | ModuleScript | 865 | 28 821 | commité | `09_client-1.md` |
| `src/client/Controllers/MenuController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.MenuController` | ModuleScript | 219 | 6 757 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/NotificationController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.NotificationController` | ModuleScript | 290 | 8 885 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/SettingsController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.SettingsController` | ModuleScript | 277 | 8 668 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Controllers/UIController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.UIController` | ModuleScript | 363 | 11 139 | nouveau, non commité (en cours) | `09_client-1.md` |
| `src/client/Effects/Core.luau` | `StarterPlayer.StarterPlayerScripts.Client.Effects.Core` | ModuleScript | 307 | 10 970 | commité | `09_client-1.md` |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` | LocalScript | 87 | 2 635 | commité | `09_client-1.md` |
| `src/client/UI/AimPanel.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.AimPanel` | ModuleScript | 785 | 27 342 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Base.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Base` | ModuleScript | 437 | 13 804 | modifié depuis le dernier commit (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Button.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Button` | ModuleScript | 277 | 8 724 | commité | `10_client-2.md` |
| `src/client/UI/Components/Cycler.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Cycler` | ModuleScript | 342 | 10 268 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Grid.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Grid` | ModuleScript | 157 | 5 258 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/IconButton.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.IconButton` | ModuleScript | 231 | 6 609 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Label.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Label` | ModuleScript | 231 | 7 154 | commité | `10_client-2.md` |
| `src/client/UI/Components/Modal.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Modal` | ModuleScript | 233 | 7 140 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Panel.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Panel` | ModuleScript | 247 | 8 052 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/ProgressBar.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.ProgressBar` | ModuleScript | 139 | 3 676 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Slider.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Slider` | ModuleScript | 318 | 9 150 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Tabs.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Tabs` | ModuleScript | 262 | 7 225 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/TeamMarker.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.TeamMarker` | ModuleScript | 113 | 3 558 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Toast.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Toast` | ModuleScript | 206 | 6 307 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Components/Toggle.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Components.Toggle` | ModuleScript | 191 | 5 512 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/ControlsBar.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.ControlsBar` | ModuleScript | 64 | 1 794 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/Feed.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.Feed` | ModuleScript | 174 | 5 142 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/HoleCard.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.HoleCard` | ModuleScript | 147 | 4 873 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/InfoPanel.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.InfoPanel` | ModuleScript | 150 | 5 213 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/Inventory.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.Inventory` | ModuleScript | 156 | 5 305 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/Kit.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.Kit` | ModuleScript | 102 | 3 489 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/PracticePanel.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.PracticePanel` | ModuleScript | 74 | 2 185 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/Scoreboard.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.Scoreboard` | ModuleScript | 165 | 5 301 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Hud/TimerBanner.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Hud.TimerBanner` | ModuleScript | 125 | 4 155 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/ScreenManager.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.ScreenManager` | ModuleScript | 375 | 10 931 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Screens/Countdown.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Countdown` | ModuleScript | 206 | 5 908 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Screens/HoleIntro.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.HoleIntro` | ModuleScript | 271 | 8 962 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Screens/HoleResults.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.HoleResults` | ModuleScript | 548 | 19 302 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Screens/HostSettings.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.HostSettings` | ModuleScript | 654 | 21 481 | nouveau, non commité (en cours) | `10_client-2.md` |
| `src/client/UI/Screens/Loading.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Loading` | ModuleScript | 260 | 8 242 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Screens/LobbyMenu.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.LobbyMenu` | ModuleScript | 433 | 12 032 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Screens/PhaseBanner.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.PhaseBanner` | ModuleScript | 227 | 6 737 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Screens/Podium.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Podium` | ModuleScript | 538 | 17 734 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Screens/Settings.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Settings` | ModuleScript | 324 | 9 319 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Screens/Util.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Util` | ModuleScript | 178 | 5 507 | nouveau, non commité (en cours) | `11_client-3.md` |
| `src/client/UI/Theme.luau` | `StarterPlayer.StarterPlayerScripts.Client.UI.Theme` | ModuleScript | 683 | 23 070 | modifié depuis le dernier commit (en cours) | `11_client-3.md` |
| `src/tests/Runner.luau` | `ServerStorage.Tests.Runner` | ModuleScript | 257 | 8 370 | commité | `12_tests.md` |
| `src/tests/Specs/BallMath.spec.luau` | `ServerStorage.Tests.Specs.BallMath.spec` | ModuleScript | 373 | 18 325 | commité | `12_tests.md` |
| `src/tests/Specs/Cosmetics.spec.luau` | `ServerStorage.Tests.Specs.Cosmetics.spec` | ModuleScript | 131 | 4 996 | commité | `12_tests.md` |
| `src/tests/Specs/Holes.spec.luau` | `ServerStorage.Tests.Specs.Holes.spec` | ModuleScript | 242 | 8 853 | nouveau, non commité (en cours) | `12_tests.md` |
| `src/tests/Specs/Items.spec.luau` | `ServerStorage.Tests.Specs.Items.spec` | ModuleScript | 132 | 5 266 | commité | `12_tests.md` |
| `src/tests/Specs/Locale.spec.luau` | `ServerStorage.Tests.Specs.Locale.spec` | ModuleScript | 76 | 2 546 | commité | `12_tests.md` |
| `src/tests/Specs/MatchStateMachine.spec.luau` | `ServerStorage.Tests.Specs.MatchStateMachine.spec` | ModuleScript | 175 | 7 572 | nouveau, non commité (en cours) | `12_tests.md` |
| `src/tests/Specs/NetDefinitions.spec.luau` | `ServerStorage.Tests.Specs.NetDefinitions.spec` | ModuleScript | 95 | 2 895 | commité | `12_tests.md` |
| `src/tests/Specs/Playlist.spec.luau` | `ServerStorage.Tests.Specs.Playlist.spec` | ModuleScript | 242 | 8 882 | nouveau, non commité (en cours) | `12_tests.md` |
| `src/tests/Specs/Progression.spec.luau` | `ServerStorage.Tests.Specs.Progression.spec` | ModuleScript | 130 | 5 474 | commité | `12_tests.md` |
| `src/tests/Specs/Scoring.spec.luau` | `ServerStorage.Tests.Specs.Scoring.spec` | ModuleScript | 378 | 14 264 | nouveau, non commité (en cours) | `12_tests.md` |
| `src/tests/Specs/Util.spec.luau` | `ServerStorage.Tests.Specs.Util.spec` | ModuleScript | 96 | 3 461 | commité | `12_tests.md` |
| `docs/ARCHITECTURE.md` | — | — | 291 | 20 598 | commité | `13_docs-1.md` |
| `docs/CAHIER_DES_CHARGES.md` | — | — | 1 180 | 85 160 | commité | `13_docs-1.md` |
| `docs/ETAT_REPRISE.md` | — | — | 122 | 10 345 | commité | `13_docs-1.md` |
| `docs/MANIFESTE_ASSETS.md` | — | — | 224 | 24 826 | commité | `13_docs-1.md` |
| `docs/MATRICE_COUVERTURE.md` | — | — | 381 | 65 233 | commité | `13_docs-1.md` |
| `docs/MATRICE_INTERACTIONS.md` | — | — | 40 | 5 206 | commité | `13_docs-1.md` |
| `docs/notes-techniques-roblox.md` | — | — | 303 | 56 231 | commité | `14_docs-2.md` |
| `docs/PLAN_PARCOURS.md` | — | — | 117 | 10 118 | commité | `14_docs-2.md` |
| `docs/REGISTRE_OBJETS.md` | — | — | 177 | 15 742 | commité | `14_docs-2.md` |
| `docs/REGLES_SCORE.md` | — | — | 358 | 20 136 | commité | `14_docs-2.md` |
| `docs/SPEC_DEMANDE.md` | — | — | 223 | 21 759 | commité | `14_docs-2.md` |
| `docs/TRANSFERT.md` | — | — | 259 | 25 502 | commité | `14_docs-2.md` |
| `legacy/prototype-etape1/AimController.lua` | — | — | 570 | 17 645 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/BallService.lua` | — | — | 760 | 23 541 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/ClientMain.client.lua` | — | — | 11 | 422 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/CollisionService.lua` | — | — | 59 | 1 901 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/Config.lua` | — | — | 136 | 5 218 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/Main.server.lua` | — | — | 52 | 1 719 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/MovementService.lua` | — | — | 101 | 2 611 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/Net.lua` | — | — | 49 | 1 339 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/PowerMeter.lua` | — | — | 235 | 7 976 | commité | `15_prototype.md` |
| `legacy/prototype-etape1/StunService.lua` | — | — | 256 | 7 427 | commité | `15_prototype.md` |

Total : 192 fichiers, 61 519 lignes, 2 427 856 octets ; dont 162 fichiers Luau du jeu (54 951 lignes).

## Annexe E — Contenu du paquet de transfert

| Fichier | Taille | Rôle |
| --- | ---: | --- |
| `00_LISEZMOI_TRANSFERT.md` | — | ce document (récapitulatif, état, liaisons, annexes) |
| `01_projet.md` | 35 908 octets | code source intégral (voir l'en-tête de la partie) |
| `02_serveur-1.md` | 220 880 octets | code source intégral (voir l'en-tête de la partie) |
| `03_serveur-2.md` | 208 741 octets | code source intégral (voir l'en-tête de la partie) |
| `04_serveur-3.md` | 174 727 octets | code source intégral (voir l'en-tête de la partie) |
| `05_serveur-4.md` | 154 271 octets | code source intégral (voir l'en-tête de la partie) |
| `06_partage-1.md` | 207 505 octets | code source intégral (voir l'en-tête de la partie) |
| `07_partage-2.md` | 252 751 octets | code source intégral (voir l'en-tête de la partie) |
| `08_partage-3.md` | 164 634 octets | code source intégral (voir l'en-tête de la partie) |
| `09_client-1.md` | 231 991 octets | code source intégral (voir l'en-tête de la partie) |
| `10_client-2.md` | 249 919 octets | code source intégral (voir l'en-tête de la partie) |
| `11_client-3.md` | 86 978 octets | code source intégral (voir l'en-tête de la partie) |
| `12_tests.md` | 96 908 octets | code source intégral (voir l'en-tête de la partie) |
| `13_docs-1.md` | 213 714 octets | code source intégral (voir l'en-tête de la partie) |
| `14_docs-2.md` | 151 784 octets | code source intégral (voir l'en-tête de la partie) |
| `15_prototype.md` | 73 910 octets | code source intégral (voir l'en-tête de la partie) |
| `golf-chaos.bundle` | 486 924 octets | dépôt Git complet : git clone golf-chaos.bundle golf-chaos |
| `GolfChaos_transfert_complet.rbxlx` | 2 007 030 octets | place Studio de l'arbre de travail (tout le code, y compris en cours) |
| `GolfChaos_transfert_verifie.rbxlx` | 1 003 498 octets | place Studio du dernier commit |
| `golf-chaos-sources.zip` | 776 772 octets | archive des sources de l'arbre de travail |
| `SHA256SUMS.txt` | 19 189 octets | empreintes SHA-256 des fichiers exportés |

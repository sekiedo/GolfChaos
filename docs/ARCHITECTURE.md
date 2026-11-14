# Golf Chaos — Architecture et contrats

Ce document est le **contrat** entre tous les modules. Toute personne (ou agent) qui écrit du code
le lit en entier avant de commencer, et respecte les noms, signatures et attributs indiqués ici.
En cas de besoin d'une API absente, l'ajouter dans **son propre** module et la documenter dans
`docs/ETAT_REPRISE.md` (section « API ajoutées ») ; ne pas modifier le module d'un autre chantier.

## 1. Flux de travail et source de vérité

- **Source de vérité : le dépôt** (`src/`, `default.project.json`, `docs/`). Studio n'est qu'une cible.
- Construction : `powershell -File scripts/build.ps1` → `build/GolfChaos.rbxlx` (Rojo 7.7.1 dans `tools/`).
- Test : `powershell -File scripts/open-studio.ps1 -Rebuild -CloseOld` ouvre la place construite dans une
  **fenêtre Studio séparée** (PID mémorisé dans `build/studio.pid`). Les tests passent par le serveur MCP
  de Studio (outil `execute_luau`, `start_stop_play`, `screen_capture`...).
- **On n'écrase jamais une place existante de l'utilisateur** (ex. la place cloud « super combat blox »).
  Toute modification faite à la main dans la fenêtre de test est perdue au prochain build : la reporter
  dans `src/` d'abord. La publication se fait plus tard, à la demande, via Studio (Fichier ▸ Publier).
- Le monde (accueil, 81 trous, décors, UI) est **généré par le code** à partir des données de `src/` :
  aucune étape manuelle de construction de niveau.

## 2. Arborescence Rojo

| Dossier | Instance Roblox | Contenu |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` | Config, données de trous, types, logique pure, Net, Locale, Util |
| `src/server` | `ServerScriptService.Server` | `init.server.luau` (seul Script), `Services/`, `Items/`, `Course/`, `Data/`, `Cosmetics/` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | `init.client.luau` (seul LocalScript), `Controllers/`, `UI/`, `Effects/` |
| `src/tests` | `ServerStorage.Tests` | `Runner.luau`, `Specs/*.spec.luau` |

Détail de `src/shared` :
- `Config/` — paramètres de jeu **sans code métier** (un fichier par domaine : `Gameplay`, `Scoring`, `Match`,
  `Items`, `ItemBoxes`, `Vehicles`, `Cosmetics`, `Economy`, `Achievements`, `Biomes`, `Sounds`, `Quality`).
- `Data/Holes/` — `Coast.luau`, `Forest.luau`, `Desert.luau`, `Snow.luau`, `City.luau`, `Training.luau`
  (chacun retourne un tableau de `Types.HoleDef`) ; `Data/Holes/init.luau` les agrège (`Holes.all()`, `Holes.get(id)`).
- `Logic/` — logique **pure** testable sans moteur (score, machine à états, tirages, économie, playlists, validation).
- `Net/` — `init.luau` + `Remotes/<Domaine>.luau` (un fichier de définitions par domaine).
- `Locale/` — `init.luau` + `fr/<Domaine>.luau` + `en/<Domaine>.luau`.
- `Util/` — `Signal`, `Trove`, `Validate`, `Log` (+ ajouts génériques éventuels).
- `Types.luau` — types transverses (phases, réglages, résultats, format des trous).

## 3. Conventions de code

- Tous les fichiers `.luau` commencent par `--!strict` ; commentaires et textes en **français**.
- Un module = une responsabilité. Pas de `_G`/`shared`. `require` explicite ; pas de cycle (passer des callbacks
  ou écouter des `Signal` pour inverser une dépendance).
- API publique des modules en **PascalCase** (`BallService.SpawnBall`) ; cycle de vie `Init()` puis `Start()`.
- Événements inter-modules : `Util/Signal` exposés sur le module (`BallService.Holed:Connect(...)`).
- Tout ce qui a une durée de vie (manche, joueur, effet, véhicule) possède une `Trove` nettoyée explicitement.
- Aucun texte affiché en dur : `Locale.t("domaine.cle", vars)` ; ajouter les clés dans `Locale/fr` **et** `Locale/en`.
- Aucun nombre d'équilibrage en dur : il vit dans `shared/Config/*`.
- **Jamais d'AssetId inventé.** Seuls sont permis : contenu intégré `rbxasset://` (sons/polices du moteur),
  ressources vérifiées consignées dans `docs/MANIFESTE_ASSETS.md`, et géométrie construite par code.
- Journal : `Log.info/warn/error/debug(tag, ...)`. Une erreur attendue (requête invalide) n'est pas une `Log.error`.
- Pas de `wait()`/`spawn()`/`delay()` dépréciés : utiliser `task.*`. Pas de boucle `while true` sans `task.wait`.
- Code compatible avec les signaux différés (`Workspace.SignalBehavior = Deferred`).

## 4. Démarrage

`init.server.luau` charge tous les ModuleScripts de `Services/`, trie par `Priority` (défaut 100) puis par nom,
appelle tous les `Init()` puis lance chaque `Start()` dans son thread. Même principe côté client avec `Controllers/`.

Priorités serveur (à respecter) :

| Priorité | Service | Rôle |
| --- | --- | --- |
| 0 | `CollisionService` | groupes de collision |
| 5 | `PlayerDataService` | profils persistants |
| 8 | `NetworkValidation` | statistiques et garde-fous réseau communs |
| 10 | `MovementService` | verrous de déplacement, modificateurs, plausibilité |
| 15 | `CombatService` | KO, recul, protection, frappe de proximité, plongeon |
| 20 | `BallService` | balles, tirs, physique, trou, pénalités |
| 25 | `CourseService` | construction/nettoyage des trous, accueil, éclairage, checkpoints |
| 30 | `VehicleService` | voiturettes |
| 35 | `ItemService` | inventaires, boîtes, effets, objets |
| 40 | `CosmeticService` | boutique, équipements, apparence |
| 45 | `AchievementService` | défis/succès internes |
| 50 | `RewardService` | récompenses de fin de partie |
| 55 | `SpawnService` | apparition des personnages (accueil, checkpoints) |
| 60 | `LobbyService` | hôte, réglages, équipes, prêt, parties privées |
| 70 | `MatchService` | machine à états, modes, score, résultats |
| 90 | `DevService` | outils de test **Studio uniquement** |

Priorités client : `InputController` 0, `SettingsController` 5, `UIController` 10, `CameraController` 20,
`GolfAimController` 30, `HUDController` 40, `MenuController` 50, autres 60+.

## 5. Réseau et sécurité

- Seul `shared/Net` crée des remotes, à partir des fichiers `Net/Remotes/<Domaine>.luau`. Noms `Domaine.Action`.
- Chaque remote client → serveur déclare `args` (types vérifiés avant le handler, surplus rejeté) et `rate`/`burst`.
- Le client envoie des **intentions** (viser, frapper avec telle direction, utiliser l'objet du slot 2...).
  Le serveur vérifie tout : phase, `RoundId`, participant actif, état (KO, trou terminé, en véhicule), distance,
  délai, équipement, cible plausible, bornes numériques, doublons. Il calcule lui-même les conséquences.
- Toute intention de jeu pendant un trou transporte le **`RoundId`** courant (attribut `GameState.RoundId`) :
  une requête d'une manche précédente est ignorée.
- Les récompenses, achats et scores ne transitent **jamais** du client vers le serveur.
- Rejets : comptés par `Net.getStats()` ; `NetworkValidation` expose `Report(player, reason)` pour les rejets
  métier (statistiques, détection d'abus, jamais d'exclusion automatique sans preuve).

## 6. État répliqué (noms exacts)

`ReplicatedStorage.GameState` (Folder obtenu **uniquement** via `shared/Util/GameState.luau` : `GameState.get()`
le crée côté serveur s'il n'existe pas, l'attend côté client ; n'importe quel service peut l'utiliser dès `Init`), attributs :

| Attribut | Type | Sens |
| --- | --- | --- |
| `Phase` | string | `Types.Phase` |
| `PhaseEndsAt` | number | heure serveur (`workspace:GetServerTimeNow()`) de fin de phase ; 0 si indéfinie |
| `RoundId` | number | incrémenté à chaque chargement de trou |
| `MatchId` | string | identifiant unique de la partie (GUID) |
| `Mode` | string | `Types.Mode` |
| `HoleIndex` / `HoleCount` | number | position dans la playlist (1..n) |
| `HoleId` / `HoleName` / `HoleBiome` | string | trou courant |
| `HolePar` | number | par |
| `CupPosition` | Vector3 | centre du trou (monde) |
| `Wind` | Vector3 | accélération du vent (studs/s², horizontale) |
| `HoleStartedAt` | number | heure serveur du début de `Playing` |
| `OvertimeEndsAt` | number | fin de prolongation (0 si aucune) |
| `HostUserId` | number | hôte du salon (0 si aucun) |
| `SettingsJson` | string | `MatchSettings` encodé JSON (affichage) |
| `TeamScoreRed` / `TeamScoreBlue` | number | points d'équipe |
| `PersistentData` | boolean | false = sauvegarde en mémoire (mode test) |

Attributs **joueur** (posés par le serveur uniquement) : `Participant` (bool), `Spectating` (bool),
`Team` (string, "" si aucune), `Strokes` (number, coups + pénalités du trou), `HoleFinished` (bool),
`FinishOrder` (number, 0 si non arrivé), `MatchPoints` (number), `Ready` (bool), `Aiming` (bool),
`KnockedOut` (bool), `Protected` (bool), `AFK` (bool), `Coins` (number), `DataStatus` (string : "Loading" |
"Ready" | "Memory" | "Failed"), `Inventory` (string : ids séparés par des virgules, "" = case vide),
`InventoryCapacity` (number), `SelectedSlot` (number), `ActiveEffects` (string JSON `{ [effetId] = finServeur }`),
`InVehicle` (bool).

Attributs de la **balle** (Part dans `Workspace.Balls`) : `OwnerUserId` (number), `State` ("Resting" | "Moving" |
"Holed" | "Frozen"), `Skin` (id de cosmétique de balle). Le Part serveur est la **collision de référence**
(taille identique pour tous) ; le client affiche le skin par-dessus (le Part reste neutre).

Attributs du **personnage** : `AnimState` ("" | "Address" | "Charging" | "Swing" | "Dive" | "Punch" | "KO"),
`Emote` (id, "" si aucune), `EmoteStartedAt` (number), `Giant` (bool), `Frozen` (bool), `Invisible` (bool).

Les **événements ponctuels** (KO, trou réussi, résultats, podium) passent par des remotes `ToClient`.

## 7. Machine à états de la partie

`Lobby → Preparing → Loading → HoleIntro → Countdown → Playing → HoleEnd → HoleResults → (Loading du trou suivant | Podium) → Lobby`

- Définie de façon pure dans `shared/Logic/MatchStateMachine.luau` (table des transitions autorisées, testée).
- `MatchService` est le seul à changer `GameState.Phase` ; chaque transition est validée par la table.
- `Preparing` : l'hôte règle la partie ; départ quand l'hôte lance (ou tous prêts) avec ≥ 1 participant.
- `Playing` se termine quand tous les participants actifs ont terminé, abandonné, sont AFK ou déconnectés,
  ou à la fin du chronomètre (prolongation déclenchée par la première arrivée, voir `docs/REGLES_SCORE.md`).
- `HoleEnd` fige les résultats : plus aucune action ne modifie le score ; les joueurs ayant terminé ne peuvent
  ni frapper ni gêner ceux qui jouent encore (ils deviennent intangibles/spectateurs du trou).
- Aucune situation (égalité, départ de l'hôte, déconnexion, AFK, balle bloquée) ne doit bloquer la progression :
  chaque phase a une durée maximale.

## 8. Contrats des services serveur

Signatures minimales ; `Player` = joueur Roblox. Les signaux sont des `Util/Signal`.

**CollisionService** — groupes : `Balls`, `Characters`, `Vehicles`, `Projectiles`, `Ghosts` (joueurs ayant terminé),
`Course`, `Props` (décor non bloquant). `SetBallCollisions(enabled: boolean)`, `AssignCharacter(character)`,
`SetGhost(player, isGhost: boolean)`.

**MovementService** — `Lock(player, reason)`, `Unlock(player, reason)`, `IsLocked(player, reason?)`,
`SetModifier(player, key, speedMult, jumpMult?, duration?)`, `ClearModifiers(player)`,
`AllowDisplacement(player, seconds, reason)` (exempte la vérification de plausibilité : propulsion, téléportation),
`Teleport(player, cframe)` (téléportation serveur autorisée), `Refresh(player)`.

**CombatService** — `Knockout(victim, opts) -> boolean` avec `opts = { attacker: Player?, source: string,
duration: number?, knock: Vector3?, major: boolean? }` (respecte protection, anti-KO répété, bouclier, équipe,
joueurs ayant terminé) ; `Knockback(player, velocity, opts?)` ; `IsKnockedOut(player)` ; `IsProtected(player)` ;
`GrantProtection(player, seconds)` ; `CanAffect(attacker: Player?, victim: Player) -> boolean` ;
`SetShieldHandler(fn(victim, info) -> "blocked" | "broken" | nil)` (fourni par ItemService) ;
signaux `KnockedOut(victim, attacker?, source)`, `Recovered(victim)`. Gère les intentions `Combat.Punch`, `Combat.Dive`.

**BallService** — `SpawnBall(player, position) -> BasePart`, `PlaceBall(player, position)`, `RemoveBall(player)`,
`RemoveAll()`, `GetBall(player)`, `GetState(player)`, `GetStrokes(player)`, `ResetStrokes(player)`,
`AddPenalty(player, count, reason)`, `SetCup(position: Vector3, radius: number)`, `SetWind(v: Vector3)`,
`SetCanShoot(fn(player) -> boolean)`, `CancelAim(player, reason, blockSeconds?)`,
`ForceShot(player, reason) -> boolean` (frappe prématurée : Klaxon), `ApplyBallImpulse(player, velocity, source)`,
`FreezeBall(player, seconds)`, `ResetToLastValid(player, reason, penalty: number)`,
`CreateSimBall(position) -> BasePart` + `StepSim(...)` (balle sans propriétaire pour les outils de validation),
signaux `Shot(player, strokes, power, info)`, `Rested(player, position)`,
`Holed(player, info)` avec `info = { strokes, shotDistance, fromDistance, wasPutt, holeInOne }`,
`Respawned(player, reason)`, `PlayerHit(attacker, victim)`.

**CourseService** — `LoadHole(def: HoleDef) -> HoleRuntime`, `UnloadHole()`, `GetCurrent() -> HoleRuntime?`,
`GetCheckpointFor(position: Vector3) -> CFrame`, `IsOutOfBounds(position) -> boolean`,
`GetStartPlacements(count) -> { CFrame }` (départs équitables), `ApplyBiomeLighting(biome)`,
`BuildPreview(holeId, origin) -> Folder` (inspection en mode Édition), `GetLobby() -> { spawn: CFrame, ... }`,
signaux `HoleLoaded(runtime)`, `HoleUnloaded()`.

**ItemService** — `GiveItem(player, itemId) -> boolean`, `GetInventory(player) -> { string }`,
`ClearPlayer(player)`, `ClearRound()` (supprime **tous** les effets, projectiles, pièges, boîtes de la manche),
`RollItem(player, boxKind) -> string?` (tirage serveur, rattrapage selon la position), `HasEffect(player, id)`,
`AddEffect(player, id, duration, onEnd)`, `RemoveEffect(player, id)`, signaux `ItemUsed(player, itemId)`,
`ItemGained(player, itemId)`. Chaque objet = un module `server/Items/<Id>.luau` (contrat §10).

**VehicleService** — `SpawnCart(cframe, owner: Player?) -> Model`, `DespawnCart(cart)`, `ResetCart(cart)`,
`ClearAll()`, `GetVehicleOf(player) -> Model?`, `EjectPlayer(player)`, signaux `PlayerEntered`, `PlayerExited`.

**PlayerDataService** — `GetProfile(player) -> Profile?`, `WaitForProfile(player, timeout?)`,
`GetStatus(player)`, `IsPersistent() -> boolean`, `Update(player, fn(data))`,
`Transact(player, opId: string, fn(data) -> (boolean, string?)) -> (boolean, string?)` (idempotent par `opId`),
`AddCoins(player, amount, reason, opId)`, `SpendCoins(player, amount, reason, opId) -> boolean`,
signaux `ProfileLoaded(player, data)`, `ProfileChanged(player, keys)`.

**RewardService** — `GrantMatchRewards(summary)` (montants plafonnés, `opId = MatchId..":"..UserId`),
`GrantOnce(player, rewardId, amount) -> boolean`.

**CosmeticService** — `Purchase(player, cosmeticId) -> (boolean, string?)`, `Equip(player, slot, cosmeticId)`,
`GetEquipped(player)`, `ApplyAppearance(player, character)`, `SaveLoadout(player, index)`, `UseLoadout(player, index)`.

**AchievementService** — `Increment(player, statId, amount?)`, `GetProgress(player)` ; écoute les signaux des
autres services (trou réussi, KO, objets, véhicules...).

**SpawnService** — `Spawn(player, where: "Lobby" | "Hole")`, `Respawn(player, reason)`,
`SetSpawnResolver(fn(player) -> CFrame?)`.

**LobbyService** — `GetHost()`, `IsHost(player)`, `GetSettings() -> MatchSettings`, `ApplySetting(player, key, value)`,
`BalanceTeams()`, `GetParticipants() -> { Player }`, signaux `HostChanged`, `SettingsChanged`, `StartRequested(settings)`.

**MatchService** — `GetPhase()`, `GetRoundId()`, `IsParticipant(player)`, `IsActive(player)` (participant en jeu
sur le trou courant, non terminé), `GetTeam(player)`, `AreAllies(a, b)`, `GetSettings()`,
`GetRacePosition(player) -> (rank, total)` (classement par distance au trou), `Abort(reason)`,
signaux `PhaseChanged(new, old)`, `HoleStarted(runtime)`, `HoleEnded(results)`, `MatchEnded(summary)`,
`PlayerFinishedHole(player, result)`.

## 9. Contrats des contrôleurs client

- **InputController** : `GetDevice() -> "KeyboardMouse" | "Touch" | "Gamepad"`, `DeviceChanged` (Signal),
  `Bind(action, callback(state), keys...)`, `Unbind(action)`. Toutes les actions ont un équivalent clavier,
  tactile et manette.
- **UIController** : racine des ScreenGui, `UI/Theme.luau` (couleurs, polices, tailles, contrastes),
  `UI/Components/*` (Button, Panel, Label, IconButton, Modal, Tabs, Grid, Toggle, Slider, ProgressBar, Toast),
  `UI/ScreenManager.luau` (`Register(name, screen)`, `Show(name, args?)`, `Hide(name)`, pile de modales,
  focus manette via `GuiService.SelectedObject`).
- **SettingsController** : préférences locales (+ synchronisées au profil) : volumes, sensibilité, secousses,
  vibrations, effets réduits, **mode sans flash**, langue ; `Get(key)`, `Set(key, value)`, `Changed` (Signal).
- **EffectsController** : `PlaySound(name, opts?)`, `Play(effectName, params)` ; registre `client/Effects/*.luau`
  (chaque fichier retourne `{ [effectName] = function(params) end }`) ; respecte qualité et effets réduits.
- **CameraController**, **GolfAimController**, **HUDController**, **MenuController**, **SpectatorController**,
  **InventoryController**, **ShopController**, **CustomizeController**, **AnimationController** (animations
  procédurales de tous les personnages via les attributs `AnimState`/`Emote`), **VehicleController**,
  **TutorialController**, **NotificationController**.

## 10. Objets (contrat des modules `server/Items/<Id>.luau`)

```lua
return {
	Id = "horn",                          -- identique à Config/Items
	Use = function(ctx, player, payload) -> (boolean, string?)  -- payload validé : { aim: Vector3?, target: Player? }
	OnRoundEnd = function(ctx) end,       -- facultatif : nettoyage de tout état global de l'objet
	OnPlayerRemoving = function(ctx, player) end, -- facultatif
}
```
`ctx` fournit : services (Ball, Combat, Movement, Vehicle, Course, Match), `trove` de manche,
`raycast`, `getPlayersInRadius`, `getTargetInCone`, `spawnProjectile`, `fireEffect(name, params)`.

## 11. Physique et propriété réseau

- **Balle** : Part non ancré, propriété réseau **serveur** (`SetNetworkOwner(nil)`), pas fixe 240 Hz
  (`Workspace.PhysicsSteppingMethod = Fixed`), traînée par surface, vent en vol, vitesse plafonnée,
  **balayage `Spherecast`** entre deux pas serveur contre le passage à travers les obstacles minces,
  détection du trou par test **segment–cercle** côté serveur (pas de point accordé à distance).
  Le client affiche un skin lissé ; le Part serveur reste la référence.
- **Personnages** : propriété client (réactivité) ; le serveur vérifie la plausibilité des déplacements
  (vitesse max selon effets, fenêtres d'exemption après propulsion/téléportation autorisée). Pendant un KO,
  le serveur prend la propriété du personnage puis la rend.
- **Voiturettes** : propriété au conducteur (VehicleSeat), vitesse plafonnée et vérifiée serveur ; les impacts
  sur joueurs sont décidés par le serveur.
- **Projectiles** : simulés par le serveur (pas de Part physique), rendus par les clients à partir des données
  de tir répliquées.

## 12. Nettoyage

- Une `Trove` de **manche** (créée au chargement du trou, nettoyée à `HoleEnd`→`Loading`/`Podium`) détient :
  géométrie du trou, effets, pièges, projectiles, boîtes, voiturettes, états temporaires.
- Une `Trove` par **joueur** (nettoyée à `PlayerRemoving`) ; une par **personnage** (nettoyée à `CharacterRemoving`).
- `ItemService.ClearRound()`, `VehicleService.ClearAll()`, `BallService.RemoveAll()` sont appelés par `MatchService`
  en fin de trou. Les tests vérifient l'absence de résidus entre manches (instances, connexions).

## 13. Tests

- `require(game.ServerStorage.Tests.Runner).run(filtre?)` exécute `src/tests/Specs/*.spec.luau`.
- Les specs ne testent que des modules sans effet de bord au `require` (Config, Logic, Util, Data).
- Catégories de preuve (à distinguer dans les rapports) : analyse statique, test unitaire, simulation,
  test moteur Studio (Play solo), test multi-clients, appareil physique, service Roblox réel.

## 14. Propriété des fichiers

Chaque chantier ne modifie que ses fichiers (liste tenue dans `docs/ETAT_REPRISE.md`). Les fichiers communs
(`Types.luau`, `Net/init.luau`, `Util/*`, bootstraps, `Runner.luau`) ne sont modifiés que par l'intégration.

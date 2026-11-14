# Notes techniques Roblox – Golf Chaos

> Recherche du 2026-11-12 sur la documentation officielle (create.roblox.com, versions `.md`, pages mises à jour les 10–11/11/2026).
> « non confirmé » = absent ou ambigu dans la doc officielle. « DevForum » = source communautaire ou annonce, pas la doc de référence.
> Aucun asset ID inventé : n'utiliser que des IDs vérifiés dans la Toolbox / le Creator Store.

---

## 1. Network ownership

**Faits clés**
- Physique distribuée : chaque assemblage non ancré est simulé par son propriétaire (serveur ou un client). Défaut = serveur, mais le moteur donne automatiquement la propriété à un client selon la proximité de son `Character` et la capacité de son appareil.
- Pièces ancrées : toujours au serveur, propriété non modifiable. Tester avant : `BasePart:CanSetNetworkOwnership(): (boolean, string?)` (false + raison).
- `BasePart:SetNetworkOwner(playerInstance: Player?)` : `nil` = serveur ; s'applique « à cette pièce et à toutes les pièces connectées ». Appel côté serveur.
- `BasePart:SetNetworkOwnershipAuto()`, `BasePart:GetNetworkOwner(): Player?` (`nil` = serveur), `BasePart:GetNetworkOwnershipAuto(): boolean`.
- Mécanisme sans pièce ancrée : régler un assemblage règle tous les assemblages du mécanisme. Ancrer un assemblage isolé → serveur ; au désancrage l'ownership précédent est **perdu** (retour auto). Dans un mécanisme, l'ownership fixé est restauré au désancrage.
- Personnages : possédés par leur client (un exploiteur peut se téléporter, voler, modifier `WalkSpeed` localement sans déclencher d'événement).
- Véhicules : par défaut le premier assis (même un passager sur `Seat`) reçoit l'ownership de tout le véhicule → le conducteur subit plusieurs cycles réseau de retard. Correctif officiel : sur `VehicleSeat.Changed` (propriété `Occupant`), `seat:SetNetworkOwner(player)` ; siège vide → `seat:SetNetworkOwnershipAuto()`. Donner aussi les pièces libres posées sur le véhicule au même client.
- `VehicleSeat` soude le joueur au contact et transmet `Throttle`/`Steer` (-1/0/1, retombent à 0 s'ils ne sont pas réécrits) et `ThrottleFloat` (-1 à 1) aux moteurs. Attribution automatique de l'ownership au conducteur : non documentée (non confirmé).
- `SetNetworkOwner(nil)` : à utiliser « avec parcimonie », peut rendre la physique saccadée côté clients (latence de réplication visible, pas de prédiction locale).

**Exploits / latence**
- Roblox ne vérifie pas la physique d'une pièce possédée par un client : téléportation, traversée de murs, vitesses extrêmes, `Inf`/`NaN` dans CFrame/vitesses (peut perturber des assemblages non possédés → « fling »).
- `Touched` est lié à l'ownership : un client peut déclencher (ou supprimer) des `Touched` sur ses pièces → jamais une vérité serveur.
- Debug Studio : options de visualisation du viewport > « Network owners » (vert = mon client, rouge = zone tampon, blanc/gris = serveur ou autre client, noir = personne → pas de physique) ; une couleur par client en multi-client.

**Option Server Authority**
- `Workspace.AuthorityMode = Enum.AuthorityMode.Server` (sinon `Automatic` = modèle distribué) : serveur seule source de vérité, prédiction client + rollback/resimulation. **En bêta** selon la page sécurité (11/2026).
- Exige (réglés automatiquement par AuthorityMode) : `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`, `SignalBehavior = Deferred`, `UseFixedSimulation`, `StreamingEnabled`. Logique dans `RunService:BindToSimulation(fn)` (module chargé client + serveur), inputs via Input Action System, `time()` synchronisé. Attributs synchronisés : 64 premiers par instance, nom ≤ 50 car., string ≤ 50 car. `Destroy()` interdit dans la simulation ; Tools pas entièrement supportés.

Sources : https://create.roblox.com/docs/physics/network-ownership · https://create.roblox.com/docs/scripting/security/network-ownership · https://create.roblox.com/docs/reference/engine/classes/BasePart · https://create.roblox.com/docs/projects/server-authority · https://create.roblox.com/docs/reference/engine/enums/AuthorityMode · https://create.roblox.com/docs/reference/engine/classes/VehicleSeat

---

## 2. Frontière client-serveur / sécurité

- `RemoteEvent` : unidirectionnel, fiable, ordonné, ne cède pas. `FireServer(...)` → `OnServerEvent(player, ...)` ; `FireClient(player, ...)` / `FireAllClients(...)` → `OnClientEvent(...)`.
- `UnreliableRemoteEvent` : mêmes méthodes, ni livraison ni ordre garantis, pas de renvoi ; payload **> 1000 octets jeté** (log Output en Studio) ; certains types (buffers) compressés → taille difficile à prévoir.
- `RemoteFunction` : `InvokeServer(...)` cède jusqu'au retour de `OnServerInvoke = function(player, ...)` (une seule callback : la dernière définie). `InvokeClient` à éviter : erreur client → erreur serveur, déconnexion → erreur, pas de retour → yield infini.
- Ordre : RemoteEvents ordonnés par connexion et direction, **même entre instances différentes** ; l'ordre porte sur le démarrage des handlers (un handler qui yield peut être doublé). Aucun ordre garanti entre RemoteFunction et RemoteEvent, ni pour Unreliable → numéro de séquence si besoin.
- Sans handler connecté : RemoteEvent/RemoteFunction mis en file (taille limitée, puis erreur « Remote event invocation discarded ») ; Unreliable jeté immédiatement.
- Throttling client→serveur : **~500 requêtes/s par client**, partagé par tous les remotes du même type. Excès : RemoteEvent retardé (ordre conservé), Unreliable jeté.
- Taille max d'un RemoteEvent fiable : non documentée (non confirmé).
- Sérialisation : Instance non visible par le destinataire → `nil` (ServerStorage → client ; pièce créée en LocalScript → serveur) ; fonctions → `nil` ; clés non-string (Instance, userdata) → converties en string ; pas de table mixte (clés numériques + string) ni de trous `nil` ; tables copiées (identité perdue) ; métatables perdues.
- NaN/inf via remotes : sérialisation non documentée (non confirmé). Un exploiteur envoie ce qu'il veut → rejeter tout nombre avec `x ~= x` ou `math.abs(x) == math.huge` (composantes de Vector3/CFrame incluses), vérifier `typeof`, bornes, longueurs de strings.
- Doc sécurité, « Never trust the client » : un exploiteur peut décompiler tout LocalScript/ModuleScript répliqué, prendre l'ownership de son perso et des pièces non ancrées, déclencher Touched/ProximityPrompt à toute distance/fréquence, appeler les remotes à toute fréquence avec des arguments arbitraires (sauf le 1er `Player`), modifier son DataModel local.
- Serveur = source de vérité : recevoir l'input, valider (possible ? permis ? distance ?), exécuter, répliquer. Données/logique sensibles dans ServerScriptService, jamais dans ReplicatedStorage/Workspace.
- Rate limiting : la doc impose le test « que se passe-t-il à 1 000+ appels/s ? » ; seaux à fuite (leaky bucket) recommandés pour la validation de mouvement (moyenne sur la latence, projection XZ, exemptions pour téléportations légitimes).
- Device Trust API (optionnelle) : niveau de confiance de l'appareil à la connexion ; ne remplace pas la validation serveur.

Sources : https://create.roblox.com/docs/scripting/events/remote · https://create.roblox.com/docs/reference/engine/classes/RemoteEvent · https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent · https://create.roblox.com/docs/scripting/security/security-tactics · https://create.roblox.com/docs/scripting/security/network-ownership

---

## 3. Physique

**Pas de simulation**
- `Workspace.PhysicsSteppingMethod` : `Default` (= **Adaptive** actuellement), `Fixed` (tous les assemblages à 240 Hz, stabilité/précision max), `Adaptive` (240/120/60 Hz par assemblage, jusqu'à 2,5× plus performant). **Non scriptable** : à régler dans les Propriétés de Workspace en Studio.
- Base 240 Hz ≈ 4 worldsteps par frame à 60 FPS. Adaptive place les assemblages rapides/accélérés en île 240 Hz ; des îles de fréquences différentes connectées ou en collision passent au taux le plus élevé (surcoût). Doc : Fixed recommandé pour jeux de course, destruction, mécanismes complexes.
- Debug : Studio Settings > Physics > « Are Timesteps Shown » ; MicroProfiler (`worldStep - Adaptive`).
- `Workspace.UseFixedSimulation` (RolloutState) : active `RunService:BindToSimulation()` (fréquence fixe), contrôleur de personnage et transforms de joints à fréquence fixe, `time()` = temps fixe. `Workspace.NextGenerationPhysicsSolver` : nouveau solveur (RolloutState, réglage Studio/plugin).

**Tunneling (petits objets rapides)**
- Aucune détection continue (CCD) documentée dans la doc officielle (non confirmé). DevForum (communautaire) : « Roblox doesn't have [CCD], yet ».
- Atténuations (recommandations, pas doc) : Fixed 240 Hz, colliders épais, vitesse plafonnée, balayage serveur `Spherecast` entre la position précédente et l'actuelle à chaque pas.

**Requêtes spatiales (`WorldRoot` = Workspace / WorldModel)**
- `Raycast(origin: Vector3, direction: Vector3, raycastParams?: RaycastParams): RaycastResult?` — longueur max 15 000 studs.
- `Spherecast(position: Vector3, radius: float, direction: Vector3, params?: RaycastParams): RaycastResult?` — rayon ≤ 256, distance ≤ 1024 studs.
- `Blockcast(cframe: CFrame, size: Vector3, direction: Vector3, params?: RaycastParams): RaycastResult?` — taille ≤ 512, distance ≤ 1024.
- `Shapecast(part: BasePart, direction: Vector3, params?: RaycastParams, cframeOverride?: CFrame?, sizeOverride?: Vector3?): RaycastResult?` — géométrie réelle (pas Terrain) ; la pièce castée est toujours exclue ; distance ≤ 1024.
- PIÈGE : les casts **ne détectent pas** les pièces déjà en intersection au départ ; erreur si rayon/direction/CFrame invalides. `RaycastResult.Distance` = distance parcourue jusqu'au contact.
- Overlap : `GetPartBoundsInBox(cframe, size, overlapParams?)`, `GetPartBoundsInRadius(position, radius, overlapParams?)`, `GetPartsInPart(part, overlapParams?)`.
- `RaycastParams.new()` (mutable, réutilisable) : `ExcludeInstances` / `IncludeInstances` (`{Instance}?`, l'exclusion prime ; `IncludeInstances = {}` n'inclut rien, `nil` inclut tout) **remplacent** `FilterDescendantsInstances` / `FilterType` / `AddToFilter` (supersédés) ; `CollisionGroup` (défaut "Default") ; `RespectCanCollide` ; `IgnoreWater` ; `Margin` (≥ 0, grossit la forme ; `Margin` > 0 sur `Raycast` = spherecast) ; `SizeGradient` (≥ -1) ; `BruteForceAllSlow` (jamais en live).
- `OverlapParams.new()` : mêmes Exclude/Include, `MaxParts` (0 = illimité), `CollisionGroup`, `Tolerance` (0–0,05 stud), `RespectCanCollide`.

**Groupes de collision**
- API sur `WorldRoot` : `workspace:RegisterCollisionGroup(name)`, `workspace:CollisionGroupSetCollidable(name1, name2, collidable)` (erreur si un groupe n'est pas enregistré), `CollisionGroupsAreCollidable`, `IsCollisionGroupRegistered`, `GetRegisteredCollisionGroups`, `UnregisterCollisionGroup`, `RenameCollisionGroup`. Mêmes méthodes sur `PhysicsService` ; `CreateCollisionGroup`, `SetPartCollisionGroup`, `GetCollisionGroupId`, `RemoveCollisionGroup` dépréciés.
- **32 groupes max par monde** (`GetMaxCollisionGroups()`). "Default" non renommable/supprimable. Assignation : `part.CollisionGroup = "Nom"`.
- Création/modification côté serveur uniquement ; coût proportionnel au nombre de BaseParts → tout enregistrer au démarrage, dans **un seul script** (sinon race conditions).
- `Workspace.TouchesUseCollisionGroups` (défaut `false`) : si `true`, les groupes non collidables ignorent aussi `Touched`.
- `Touched`/`TouchEnded` : uniquement via mouvement physique (pas via `CFrame`/`Position`), indépendants de `CanCollide`, coupés par `CanTouch = false`.
- `BasePart:BindToCollisionSummaries(callback): RBXScriptConnection` : 1×/frame après la physique, résumés `{Time, Part0, Part1, Point, Normal (sortant de Part0), RelativeVelocity (avant résolution), Area}` ; vitesse d'impact = `RelativeVelocity:Dot(Normal)`. Produit **uniquement chez le propriétaire réseau**, non répliqué ; rien si `CanCollide = false` ou entre pièces endormies.

**Propriétés physiques / impulsions**
- `PhysicalProperties.new(material)` ; `.new(density, friction, elasticity)` ; `.new(density, friction, elasticity, frictionWeight, elasticityWeight)` ; `+ acousticAbsorption`. Bornes : densité [0,0001 ; 100], friction [0 ; 2], élasticité [0 ; 1], poids [0 ; 100]. Valeur effective entre A et B = `(vA*wA + vB*wB) / (wA + wB)` (friction et élasticité). Via `BasePart.CustomPhysicalProperties`.
- `BasePart.AssemblyLinearVelocity` (studs/s, centre de masse) : affectation directe déconseillée → `VectorForce` ou `ApplyImpulse`.
- `BasePart:ApplyImpulse(impulse: Vector3)` (au centre de masse, Δv = impulse / AssemblyMass), `ApplyImpulseAtPosition(impulse: Vector3, position: Vector3)`, `ApplyAngularImpulse(impulse: Vector3)`.
- PIÈGE : pièce possédée par le serveur → impulsions/vitesses depuis un Script serveur ; appel client **sans effet**. Ownership auto côté client : client ou serveur.

Sources : https://create.roblox.com/docs/physics/adaptive-timestepping · https://create.roblox.com/docs/reference/engine/enums/PhysicsSteppingMethod · https://create.roblox.com/docs/reference/engine/classes/Workspace · https://create.roblox.com/docs/reference/engine/classes/WorldRoot · https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams · https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams · https://create.roblox.com/docs/workspace/collisions · https://create.roblox.com/docs/reference/engine/classes/PhysicsService · https://create.roblox.com/docs/reference/engine/datatypes/PhysicalProperties · DevForum : https://devforum.roblox.com/t/reduced-minimum-part-size-released-everywhere/1394733?page=5

---

## 4. DataStores (+ MemoryStore)

**API (serveur uniquement ; depuis un LocalScript → erreur)**
- `DataStoreService:GetDataStore(name: string, scope?: string, options?: Instance): DataStore` (même nom/scope → même objet ; scopes = legacy, préférer les préfixes de clé).
- `GetAsync(key: string, options?: DataStoreGetOptions): (value, DataStoreKeyInfo)` — cache local **4 s** ; lecture servie par le cache = hors quotas ; `DataStoreGetOptions.UseCache = false` pour forcer le backend ; cache propre à chaque instance de DataStore.
- `SetAsync(key: string, value: Variant, userIds?: Array, options?: DataStoreSetOptions): Variant` (id de version) — écrase sans lire ; budget écriture seulement ; incohérences si deux serveurs écrivent.
- `UpdateAsync(key: string, transformFunction: Function): (value, DataStoreKeyInfo)` — callback `(current, keyInfo) -> (new?, userIds?, metadata?)` ; lit la dernière valeur puis écrit ; **si un autre serveur modifie la clé entre-temps, la callback est rappelée** jusqu'à réussite ; retourner `nil` annule ; la callback **ne doit pas yield** ; budgets lecture ET écriture. Toujours renvoyer `keyInfo:GetUserIds()` / `keyInfo:GetMetadata()`, sinon effacés.
- `IncrementAsync(key, delta?: int = 1, userIds?, options?)` ; `RemoveAsync(key)` (version « tombstone », suppression définitive après 30 jours).
- `GetRequestBudgetForRequestType(requestType: Enum.DataStoreRequestType): int` ; `SetRateLimitForRequestType(requestType, baseLimit: int, perPlayerLimit: int)` (une fois à l'init ; `Standard*` : base [0 ; 10 000], par joueur [0 ; 200] ; `UpdateAsync`/`OnUpdate` non configurables).

**Limites**
- Nom de store, clé, scope : **50 caractères** ; valeur : **4 194 304 caractères** par clé (mesurer via `HttpService:JSONEncode`) ; métadonnées utilisateur : clé 50, valeur 250, total 300 caractères.
- Débit par clé (fenêtre 60 s, tous serveurs) : lecture **25 Mo/min**, écriture **4 Mo/min** ; chaque requête arrondie au Ko supérieur.
- Budget expérience (req/min, partagé avec Open Cloud) : Read `300 + CCU×40`, Write `300 + CCU×20`, List `300 + CCU×2`, Remove `300 + CCU×40`.
- Budget serveur par défaut (req/min) : StandardRead `60 + joueurs×40`, StandardWrite `60 + joueurs×40`, StandardList `5 + joueurs×2`, StandardRemove `60 + joueurs×40` (ordonnés : Read `60 + 40n`, Write/Remove `30 + 5n`, List `5 + 2n`) ; bonus ponctuel au démarrage du serveur.
- Files Set / OrderedSet / Get / OrderedGet : **30 requêtes** chacune ; file pleine → erreurs 301–306 (requête abandonnée).
- Stockage : `500 Mo + 1 Mo × utilisateurs uniques à vie` (taille compressée des dernières versions ; ne pas compresser soi-même).

**Sérialisation** : JSON ; nil, booléens, nombres (**ne pas stocker inf, -inf, nan**), strings (UTF-8 valide sinon échec), tables de types supportés (clés numériques → strings si longueur 0), buffers. Type non supporté → erreur ou stocké en `nil`.

**Versioning** : la 1re écriture d'une clé par heure UTC crée une sauvegarde versionnée ; les écritures suivantes de la même heure l'écrasent ; une version écrasée expire après 30 jours ; la dernière n'expire jamais. `ListVersionsAsync`, `GetVersionAsync`, `GetVersionAtTimeAsync`.

**Erreurs** (toujours `pcall`) : 101/102 clé vide/trop longue · 103/104 valeur interdite/non sérialisable · 105 valeur trop grande · 301–306 file pleine · 401/402 serveur en arrêt · **403 `StudioAccessToApisNotAllowed`** · 501–505 internes · 509 écritures bloquées sur RCC personnel · 511–513 métadonnées · `KeyThrottled` / `DatastoreThrottled` · `Standard*ExperienceThrottled` / `Standard*GameServerThrottled`. Un échec d'écriture ne prouve pas l'absence d'écriture → relire avec `UseCache = false`.

**Session locking / bonnes pratiques**
- Une clé par joueur (`User_{UserId}`) dans peu de stores ; données en mémoire ; sauvegardes : périodique + `PlayerRemoving` + `BindToClose` + checkpoints d'achat.
- Retries : backoff exponentiel + jitter, plafonnés, **traités dans l'ordre par clé** (un vieux retry peut écraser une donnée plus récente).
- Échantillon officiel : toutes les opérations passent par `UpdateAsync` (lecture + écriture atomiques, abandon possible en renvoyant `nil`) ; un `LockId` (GUID) est écrit dans les **métadonnées** de la clé ; une autre session refuse la clé tant que le verrou n'a pas expiré ; verrou rafraîchi par l'autosave (**180 s**, 1re sauvegarde décalée aléatoirement), libéré à la sauvegarde finale. Échec de chargement → données par défaut marquées « errored », jamais sauvegardées, achats bloqués.
- `DataModel:BindToClose(function)` : fonctions appelées en parallèle (paramètre `Enum.CloseReason` optionnel) ; le serveur attend **30 s** max puis s'arrête ; sauvegarder en parallèle ; `RunService:IsStudio()` pour ne pas écrire de données Studio ni bloquer la fin du test ; téléportations désactivées pendant les arrêts de modération.

**Studio / tests**
- Par défaut Studio n'a **pas** accès aux DataStores : File > Experience Settings > Security > « Enable Studio Access to API Services » (jeu publié). Studio lit/écrit les **mêmes** données que la prod → n'activer que sur une expérience de test séparée.
- Place jamais publiée : erreur « You must publish this place to the web to access DataStore » (DevForum, non officiel ; la doc officielle ne décrit que le cas publié).
- Mode Run de Studio : limites statiques séparées, possiblement plus basses → tester les quotas en Team Create.
- Aucun mock officiel de DataStoreService documenté (non confirmé).

**MemoryStoreService (matchmaking inter-serveurs)**
- `GetQueue(name: string, invisibilityTimeout?: int)`, `GetSortedMap(name: string)`, `GetHashMap(name: string)` ; serveur uniquement (`InvalidClientAccess`). Cas d'usage doc : file partagée + serveurs lobby qui matchent périodiquement.
- Quotas (niveau jeu) : mémoire `64 Ko + 1,2 Ko × utilisateurs` (réévaluée à la baisse après 8 jours) ; requêtes `1000 + 120 × CCU` unités/min ; par structure : 1 000 000 éléments, 100 Mo, 100 000 unités/min ; valeur ≤ 32 Ko ; expiration ≤ 3 888 000 s (45 j, défaut 45 j) ; ~30 000 unités/min par partition (une queue ou sorted map = 1 partition) ; hash map ~5 000 écritures / 15 000 lectures par clé et par minute ; `ReadAsync` = éléments lus + 1 unité par 2 s d'attente.
- Studio : données **isolées** de la prod, mêmes quotas (donc minuscules avec 1 utilisateur) ; place non publiée → `UnpublishedPlace` (« You must publish this place to use MemoryStoreService »).

Sources : https://create.roblox.com/docs/cloud-services/data-stores · https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits · https://create.roblox.com/docs/cloud-services/data-stores/best-practices · https://create.roblox.com/docs/cloud-services/data-stores/versioning-listing-and-caching · https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing · https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore · https://create.roblox.com/docs/reference/engine/classes/DataStoreService · https://create.roblox.com/docs/reference/engine/classes/DataModel · https://create.roblox.com/docs/cloud-services/memory-stores · https://create.roblox.com/docs/reference/engine/classes/MemoryStoreService · DevForum : https://devforum.roblox.com/t/is-there-a-way-to-check-if-a-place-has-been-published-using-code/142606

---

## 5. Téléportations / matchs privés

- `TeleportService:TeleportAsync(placeId: int64, players: Instances, teleportOptions?: Instance): Instance` — **serveur uniquement** ; ≤ **50 joueurs** par appel ; groupes dans la même expérience ; retourne un `TeleportAsyncResult` seulement si des options sont passées ; sans routage → serveur public (matchmaking sur le 1er joueur de la liste).
- `TeleportOptions` (un seul champ de routage à la fois, sinon erreur « Incompatible Parameters ») :
  - `ReservedServerId: string` — **méthode actuelle** : GUID généré côté serveur (`HttpService:GenerateGUID(false)`) ; le 1er teleport avec un nouvel ID crée le serveur réservé, réutiliser l'ID y renvoie (persister l'ID en DataStore/MemoryStore pour rejoindre plus tard).
  - `VipServerId: string` — serveur privé acheté par un joueur = son `DataModel.PrivateServerId` ; limité à l'expérience propriétaire ; accès vérifié au moment du teleport (amis autorisés, allowlist, lien).
  - `ServerInstanceId: string` — `JobId` d'un serveur public précis.
  - **Dépréciés** : `ReservedServerAccessCode`, `ShouldReserveServer`, `ReserveServer()`, `ReserveServerAsync()` (ne réserve rien, génère juste un GUID), `TeleportToPrivateServer()`, `Teleport()` client, `TeleportPartyAsync`. Les serveurs existants par code fonctionnent encore.
  - `SetTeleportData(data)` / `GetTeleportData()` : données non sécurisées (visibles client), types valeur uniquement (Instances, fonctions, RaycastParams… retirés avec erreur console). Arrivée : `player:GetJoinData().TeleportData` (serveur) ou `TeleportService:GetLocalPlayerTeleportData()` (client).
- `TeleportAsyncResult.PrivateServerId` = `PrivateServerId` de la destination (`ReservedServerAccessCode` rempli seulement en mode legacy).
- Détection serveur réservé : `game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0` ; `PrivateServerId` constant pour ce serveur réservé, `JobId` change à chaque instance.
- Échecs : `pcall` + retries (surtout serveurs réservés). Un teleport lancé peut échouer au dernier moment sans erreur → `TeleportService.TeleportInitFailed(player: Instance, teleportResult: Enum.TeleportResult, errorMessage: string, placeId: int64, teleportOptions: Instance)` (client et serveur, une fois par joueur d'un groupe ; fournit de nouvelles TeleportOptions pour viser la même destination). Exemple officiel : `Flooded` → attendre 15 s, `Failure` → 1 s puis retenter, autre → erreur.
- Rate limit chiffré des teleports : non documenté (non confirmé) ; seul signal = `Enum.TeleportResult.Flooded`.
- Sécurité : Creator Dashboard > Access Control for Places (Fully open / Limited to same universe / Secure within universe only) ; « Secure » conseillé pour des places à serveurs réservés.
- `GetPlayerPlaceInstanceAsync(userId)` : serveur, ne marche pas en test Studio, JobId inutilisable pour les serveurs réservés.

**Studio** : `TeleportAsync` testable en **Test** et **Team Test** sans publier (la destination s'ouvre comme nouveau serveur de test) ; méthodes dépréciées non supportées. Limites : en Test, `PrivateServerId` et `JobId` toujours vides ; en Team Test tous les serveurs sont privés (`PrivateServerId` jamais vide) et `ReservedServerId` peut différer de `PrivateServerId` ; teleports `VipServerId` échouent (pas de propriétaire) ; uniquement entre places partageant le même `GameId`.

Sources : https://create.roblox.com/docs/projects/teleport · https://create.roblox.com/docs/projects/teleport-private-servers · https://create.roblox.com/docs/reference/engine/classes/TeleportService · https://create.roblox.com/docs/reference/engine/classes/TeleportOptions

---

## 6. Input

- `ContextActionService` (client) : `BindAction(actionName: string, functionToBind: Function, createTouchButton: boolean, inputTypes: Tuple)` ; handler `(actionName, Enum.UserInputState, InputObject)` ; `BindActionAtPriority(actionName, functionToBind, createTouchButton, priorityLevel: int, inputTypes)` (priorité haute d'abord, ignore l'ordre de pile) ; `UnbindAction(name)`. Retourner `Enum.ContextActionResult.Pass` laisse passer, `nil`/`Sink` consomme ; état `Cancel` si une autre action recouvre l'input. Boutons tactiles dans ScreenGui « ContextActionGui » / Frame « ContextButtonFrame » (`GetButton`, `SetTitle`, `SetImage`, `SetPosition`, `SetDescription`), **7 boutons max**. **Doc : BindAction & co. « planned for deprecation »** → Input Action System.
- Input Action System : `InputContext` (`Enabled`, `Priority`, `Sink`) > `InputAction` (`Type` : Bool, Direction1D, Direction2D, Direction3D, ViewportPosition ; événements `Pressed`, `Released`, `StateChanged` ; `GetState()` à lire chaque frame pour l'analogique ; `PreferredBinding`) > `InputBinding` (`KeyCode`, `Up/Down/Left/Right/Forward/Backward`, `UIButton` pour le tactile, `Scale`, `PressedThreshold`/`ReleasedThreshold`, `DisplayName`/`DisplayImage`). Conseillé : contexts dans `ReplicatedStorage/Inputs` et `Workspace.PlayerScriptsUseInputActionSystem = Enabled`. `InputActionLabel` (bêta) affiche la bonne touche selon l'appareil. Réservés : Esc/Start (menu), F9, F11, F12, PrintScreen.
- `UserInputService` (client uniquement) : **`PreferredInput` existe** (`Enum.PreferredInput` : KeyboardAndMouse, Gamepad, Touch, MicroGamepad ; écouter `GetPropertyChangedSignal("PreferredInput")`) ; `GamepadEnabled`, `TouchEnabled`, `GamepadConnected`/`GamepadDisconnected`, `GetConnectedGamepads()`, `IsGamepadButtonDown`, `GetGamepadState`, `GetImageForKeyCode`, `GetStringForKeyCode`, événements `TouchTap/TouchPinch/TouchPan/TouchSwipe/TouchLongPress…`. `ModalEnabled` déprécié → `GuiService.TouchControlsEnabled`.
- Navigation UI manette : `GuiService.SelectedObject` (objet focalisé, peut retomber à `nil` hors écran), `GuiNavigationEnabled`, `AutoSelectGuiEnabled` (Select ou `\` sélectionne automatiquement), `GuiService:Select(selectionParent)` (prend le plus petit `SelectionOrder`), `AddSelectionParent(name, parent)` / `AddSelectionTuple` / `RemoveSelectionGroup`. `GuiObject.Selectable`, `NextSelectionUp/Down/Left/Right` (peuvent pointer vers un objet non sélectionnable → vérifier), `SelectionOrder` (défaut 0, sans effet sur la navigation directionnelle), `SelectionImageObject`. Activer : Enter / ButtonR2.
- Haptique : `HapticService` (`IsVibrationSupported(inputType)`, `IsMotorSupported(inputType, motor)`, `SetMotor(inputType, motor, intensity)`, `GetMotor`) **supersédé par `HapticEffect`** (`effect.Type = Enum.HapticEffectType.GameplayCollision / UIClick / GameplayExplosion…`, `effect:Play()`) ; manettes PlayStation/Xbox et Quest Touch ; intensité modulée par le réglage utilisateur.
- Studio : Controller Emulator (manettes, remotes TV, VR) sans matériel.

Sources : https://create.roblox.com/docs/reference/engine/classes/ContextActionService · https://create.roblox.com/docs/input/input-action-system · https://create.roblox.com/docs/reference/engine/classes/UserInputService · https://create.roblox.com/docs/reference/engine/enums/PreferredInput · https://create.roblox.com/docs/reference/engine/classes/GuiService · https://create.roblox.com/docs/reference/engine/classes/GuiObject · https://create.roblox.com/docs/input/gamepad · https://create.roblox.com/docs/reference/engine/classes/HapticService

---

## 7. Chat texte & voix

- `TextChatService` : si `CreateDefaultTextChannels = true`, crée `RBXGeneral` et `RBXSystem` (canaux à parenter sous TextChatService ; deux canaux de même nom = comportements imprévus). `CreateDefaultCommands`. `TextChannel:SendAsync()` (client), `TextChannel:DisplaySystemMessage()`, `TextChatService:DisplayBubble()` (bulles de PNJ).
- **Filtrage automatique** des messages selon les informations de compte de chaque joueur (remplace `Chat:FilterStringAsync` / `FilterStringForBroadcast`).
- Callbacks (jamais de yield) : `TextChannel.ShouldDeliverCallback` (serveur) ; `TextChatService.OnIncomingMessage`, `TextChannel.OnIncomingMessage`, `OnBubbleAdded`, `OnChatWindowAdded` (client).
- **Platform-integrated chat** (`TextChatService.PlatformIntegratedChat`, modifiable seulement en Studio) : opt-in aujourd'hui, **obligatoire pour tous les jeux à partir de mai 2027**. Une fois actif : Roblox affiche le chat (fenêtre par défaut ou `TextChannelWindow`), le texte des messages devient inaccessible au code (`TextChatMessage.Text`, `PrefixText`… → `""`), `SendAsync` (presets) non supporté → Quick Words, commandes uniquement via `TextChatCommand` (`Player.Chatted`/`OnIncomingMessage` inutilisables).
- Texte saisi par un joueur et montré à d'autres (nom de lobby, nom d'équipe…) : **filtrage obligatoire** par le dev (jeu retiré si non filtré). Serveur : `TextService:FilterStringAsync(stringToFilter: string, fromUserId: int64, textContext?: Enum.TextFilterContext): TextFilterResult` puis `result:GetNonChatStringForBroadcastAsync()` (visible par tous) ou `result:GetNonChatStringForUserAsync(toUserId)`. Une fois par soumission (pas à chaque caractère) ; yield toujours ; **ne pas retenter** (retries internes) ; **erreur si `fromUserId` n'est pas sur ce serveur** ; échec → n'afficher le texte à personne. Texte relu depuis un DataStore : refiltrer à l'affichage. `FilterAndTranslateStringAsync` : plus supporté.
- Règle (FAQ platform-integrated chat) : panneaux/notes/texte in-world **ne doivent pas permettre de communication bidirectionnelle**, exigent un **rate limiting d'au moins 1 minute** et sont modérés → pas de chat parallèle maison.
- Filtrage dans Studio : comportement non documenté (non confirmé).
- Voix : utilisateurs 13+ vérifiés (âge/ID) de certains pays ; places à **≤ 100 joueurs max** ; activée par défaut sur les nouveaux jeux (Experience Settings > Communication) ; `VoiceChatService.EnableDefaultVoice` (désactiver par place), `UseAudioApi` (AudioDeviceInput + Wire + AudioFader pour voix d'équipe/non spatiale ; `AudioDeviceInput:SetUserIdAccessList`, `AccessType`). Statut : `VoiceChatService:IsVoiceEnabledForUserIdAsync(userId)` côté client (pcall).

Sources : https://create.roblox.com/docs/chat/in-experience-text-chat · https://create.roblox.com/docs/chat/platform-integrated-chat · https://create.roblox.com/docs/ui/text-filtering · https://create.roblox.com/docs/reference/engine/classes/TextService · https://create.roblox.com/docs/chat/voice-chat

---

## 8. Tests Studio

- Modes solo (renommés) : **Test** (F5, avatar au SpawnLocation ou vers (0, 100, 0)), **Test Here** (devant la caméra), **Run** (F8, pas d'avatar). Test/Test Here = 2 simulations (client + serveur), bascule Client/Server. Pause/Resume/Step (1/60 s) ne touchent que PreAnimation/PreSimulation/PostSimulation/Stepped (pas PreRender/Heartbeat/RenderStepped) ni les scripts.
- **Server & Clients** (F7) : 1 serveur + **jusqu'à 8 clients** ; End Session ferme tout. Party Simulator pour `PartyId`. Team Test : une seule session à la fois.
- **Tests multi-clients lançables par code : OUI**, via `StudioTestService` (Studio uniquement, inactif en jeu publié) :
  - `ExecuteMultiplayerTestAsync(numPlayers: int, args: Variant): Variant` — 1 serveur + **1 à 8** clients ; yield jusqu'à `EndTest` et renvoie sa valeur ; **PluginSecurity, « can only be called from plugin scripts »** ; erreur si un test tourne déjà ou si appelé depuis un test ; une session multijoueur à la fois par instance de Studio.
  - `ExecutePlayModeAsync(args)` (Test solo) et `ExecuteRunModeAsync(args)` (Run) — PluginSecurity, yield, renvoient la valeur d'`EndTest` ou `nil`.
  - `EndTest(value)` (DataModel serveur seulement, asynchrone, marche même si le test n'a pas été lancé par le service) ; `AddPlayers(numPlayers)` (1–8 par appel, depuis le serveur d'un test actif ; plafond total non précisé) ; `GetTestArgs()` (problème connu depuis un LocalScript client) ; `CanLeaveTest(): boolean` + `LeaveTest()` (DataModel client) ; `EditModeActive` (lecture plugin/barre de commande).
  - Le serveur MCP intégré de Studio (`start_stop_play`) ne lance qu'une session Play Client solo.
  - Autres services Studio-only : `StudioDeviceSimulatorService` (profils d'appareil scriptables) ; `VirtualInput` via `UserInputService:CreateVirtualInput()` (souris/clavier/pointeur simulés, limité à l'UI du jeu).
- Simulation réseau : **Network Simulator** (bêta : File > Beta Features > New Device Simulator) — latence et jitter 0–1000 ms, perte 0–0,50 %, par direction ; presets (4G : entrant 45 ms / 20 ms / 0,40 %, sortant 55 / 30 / 0,50 ; 3G : 150 / 70 / 0,50 et 180 / 90 / 0,50). Par script (plugin) : `NetworkSettings.InboundNetworkMinDelayMs`, `InboundNetworkJitterMs`, `InboundNetworkLossPercent` (plafonné à **0,5 %**) et équivalents `Outbound*` (PluginSecurity) ; `NetworkSettings.IncomingReplicationLag` (secondes, retarde tous les messages entrants ; onglet Network des Studio Settings ; accès via `settings().Network` non confirmé par la page) ; valeurs non conservées après redémarrage de Studio.
- **Device Simulator** (bêta) : dimensions d'écran (≤ 7680×4320), densité (72–10 000 ppi), clavier virtuel, plateforme rapportée ; multi-touch simulé (Alt+glisser = pinch/rotate, Alt+Shift+glisser = pan). Ne simule ni le réseau (→ Network Simulator) ni la manette (→ Controller Emulator) ; mémoire émulée via `NetworkSettings.EmulatedTotalMemoryInMB` ; performances CPU/GPU réelles de l'appareil : non simulées (non confirmé).
- Player Emulator : locale et région (influence `PolicyService:GetPolicyInfoForPlayerAsync`).

Sources : https://create.roblox.com/docs/studio/testing-modes · https://create.roblox.com/docs/reference/engine/classes/StudioTestService · https://create.roblox.com/docs/studio/network-simulator · https://create.roblox.com/docs/reference/engine/classes/NetworkSettings · https://create.roblox.com/docs/studio/device-simulator · https://create.roblox.com/docs/reference/engine/classes/UserInputService

---

## 9. Animations sans upload d'assets

- Réplication (`Animator`) : Animator sous le Humanoid/AnimationController d'un `Player.Character` → animations lancées **par ce client** répliquées au serveur et aux autres. Animator hors personnage → charger/jouer **côté serveur** pour répliquer. L'Animator doit être **créé par le serveur** (créé localement = aucune réplication). `LoadAnimation` exige l'Animator dans Workspace et crée toujours une nouvelle piste → `Animator:GetTrackByAnimationId(id)` pour retrouver une piste.
- `KeyframeSequenceProvider:RegisterKeyframeSequence(keyframeSequence): ContentId` (hash) et `RegisterActiveKeyframeSequence` (`active://`) : IDs temporaires « **cannot be used outside of Studio** » → inutilisables en serveur live. Idem `AnimationClipProvider:RegisterAnimationClip(animationClip)` / `RegisterActiveAnimationClip`. La page AnimationClipProvider présente KeyframeSequenceProvider comme déprécié.
- `CurveAnimation` (AnimationClip à courbes : un Folder par joint, `Position` = Vector3Curve, `Rotation` = EulerRotationCurve/RotationCurve, FloatCurve pour FACS ; correspondance partielle de hiérarchie possible) : **doit être uploadée** avant d'être jouée (ID temporaire = Studio seulement).
- Conclusion : sans asset uploadé, seule l'animation **procédurale** fonctionne en live.
- Procédural : `Motor6D.Transform` (CFrame, recommandé plutôt que C0/C1) est appliqué en lot **après `RunService.PreSimulation`**, juste avant la physique ; l'Animator l'écrase chaque frame **après PreAnimation et avant PreSimulation** → écrire dans un handler `RunService.PreSimulation`, en multipliant (`joint.Transform = offset * joint.Transform`) pour se superposer aux pistes ; sauter si `Animator.EvaluationThrottled` est vrai.
- **AvatarJointUpgrade** (`StarterPlayer.AvatarJointUpgrade`, défaut pour les nouvelles expériences) : les R15 utilisent des **`AnimationConstraint`** au lieu de `Motor6D` → `FindFirstChildOfClass("Motor6D")` ne trouve rien ; chercher `FindFirstChildWhichIsA("AnimationConstraint")` puis repli Motor6D ; `IsA("Motor6D")` faux. `AnimationConstraint.Transform` = même usage que `Motor6D.Transform` ; `C0/C1/Part0/Part1` = alias **lecture seule** ; ne pas modifier `RigAttachment.CFrame` ; `IsKinematic = true` (défaut, comme Motor6D) / `false` = suivi par forces (ragdoll : `MaxForce`, `MaxTorque`, `LinearStrength`, `AngularStrength`, damping).
- Réplication du procédural : ne pas écrire C0 côté serveur ; évaluer côté client et synchroniser l'état via attributs ou `UnreliableRemoteEvent` (doc AnimationConstraint).
- `Animator.PreferLodEnabled` (défaut true) : évaluation réduite pour les persos lointains ; false pour les persos importants.

Sources : https://create.roblox.com/docs/reference/engine/classes/Animator · https://create.roblox.com/docs/reference/engine/classes/KeyframeSequenceProvider · https://create.roblox.com/docs/reference/engine/classes/AnimationClipProvider · https://create.roblox.com/docs/reference/engine/classes/CurveAnimation · https://create.roblox.com/docs/reference/engine/classes/Motor6D · https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint

---

## 10. Personnages PNJ

- `Players:CreateHumanoidModelFromDescriptionAsync(description: HumanoidDescription, rigType: Enum.HumanoidRigType, assetTypeVerification?: Enum.AssetTypeVerification): Model` — **yield** ; R6 ou R15 selon `rigType`. La version sans `Async` est **dépréciée**. `CreateHumanoidModelFromUserIdAsync(userId)` copie l'avatar d'un utilisateur (R6/R15 selon lui). Contexte d'appel (serveur seulement ?) non précisé dans la doc actuelle (non confirmé) → appeler côté serveur pour que le modèle soit répliqué.
- `Humanoid:MoveTo(location: Vector3, part?: Instance)` : règle `WalkToPoint`/`WalkToPart` ; **timeout de 8 s** si le but n'est pas atteint (rappeler `MoveTo` avant l'échéance pour relancer) ; se termine aussi à l'arrivée (~1 stud), si WalkToPoint/WalkToPart change, si un script appelle `Move()`, ou si le CFrame du RootPart est modifié. `Humanoid.MoveToFinished(reached: boolean)`.
- `PathfindingService:CreatePath(params?)` : `AgentRadius` (2), `AgentHeight` (5), `AgentCanJump` (true), `AgentCanClimb` (false ; TrussPart, label "Climb"), `WaypointSpacing` (4 ; `math.huge` = aucun point intermédiaire), `Costs` (noms d'`Enum.Material` ou labels de `PathfindingModifier`/`PathfindingLink` ; `math.huge` = infranchissable).
- `Path:ComputeAsync(start: Vector3, finish: Vector3)` (pcall + vérifier `path.Status == Enum.PathStatus.Success`), `Path:GetWaypoints()` (Position, Action `Enum.PathWaypointAction` ex. Jump, Label), `Path.Blocked(blockedWaypointIndex)` → recalculer si l'index est devant l'agent. Calculer quand l'agent touche le sol.
- Doc : avancer avec `Humanoid:Move()` vers chaque waypoint et détecter l'arrivée (plan + seuil selon la vitesse) plutôt qu'avec `MoveTo`.
- Limites : distance à vol d'oiseau ≤ **3 000 studs** ; budget **20 000 nœuds** ; waypoints hors Y ±65 536 ignorés ; paramètres d'agent incompatibles → échec. Streaming : le serveur voit tout, un client peut viser une zone non streamée.

Sources : https://create.roblox.com/docs/reference/engine/classes/Players · https://create.roblox.com/docs/reference/engine/classes/Humanoid · https://create.roblox.com/docs/characters/pathfinding

---

## 11. Contenu local intégré & audio

- `rbxasset://` pointe vers le **dossier de contenu de Roblox sur l'appareil de l'utilisateur** (Windows : `%LOCALAPPDATA%\Roblox\Versions\<version>\content` ; Mac : `RobloxStudio.app/Contents/Resources/content`), ex. `rbxasset://textures/face.png`. Ce n'est pas un asset cloud (fichier local fourni avec l'application).
- Fonctionne en live pour les fichiers présents dans le client : le moteur utilise lui-même des valeurs par défaut `rbxasset://` (ex. `Sky.SkyboxBk` = `rbxasset://textures/sky/sky512_bk.tex`, soleil `rbxasset://sky/sun.jpg`).
- MAIS la liste des fichiers (`rbxasset://sounds/...`, `rbxasset://textures/...`) **n'est pas documentée** et n'est pas garantie stable entre versions/plateformes (chemins mobile/console non documentés) → non confirmé ; prévoir un repli et tester sur chaque plateforme.
- Page officielle « Pending updates » : correctif d'un bug où les chemins `rbxasset` locaux n'étaient pas assignables dans les propriétés de type `Content` (ex. `TextureContent`), « introduced in version 743 ».
- Autres schémas : `rbxassetid://ID` (asset cloud), `rbxthumb://type=…&id=…&w=…&h=…` (Avatar, AvatarHeadShot, BadgeIcon, GameIcon… tailles fixes), `rbxgameasset://Images/Nom` (Asset Manager, ce jeu seulement), `rbxtemp://` (File), `https` (domaines approuvés uniquement).
- Audio : un audio importé est **privé** par défaut (utilisable par son seul propriétaire), partageable avec des amis/groupes/expériences précis (Creator Dashboard > Permissions ; un accord à un jeu est **irrévocable**). Le Creator Store fournit > 100 000 SFX/musiques gratuits (Roblox + partenaires). Sans permission : l'asset ne se charge pas (inaudible au runtime, erreur cliquable dans l'Output). Le réglage « Asset Privacy » ne concerne que Images/Decals/Meshes, pas l'audio.
- Import audio : droits légaux requis ; mp3/ogg/wav/flac, < 20 Mo, < 7 min, ≤ 48 kHz, mono/stéréo/3.0/5.1 ; 100 imports/30 j (non vérifié) ou 2 000/30 j (ID vérifié) ; modération avant visibilité. La Toolbox insère un `Sound`, la doc note qu'il n'a pas les capacités dynamiques d'`AudioPlayer` (+ `Wire` → `AudioEmitter`/`AudioDeviceOutput`).

Sources : https://create.roblox.com/docs/projects/assets · https://create.roblox.com/docs/reference/engine/classes/Sky · https://create.roblox.com/docs/updates/pending · https://create.roblox.com/docs/projects/assets/privacy · https://create.roblox.com/docs/audio/assets

---

## 12. Réglages Workspace / rendu (manches construites au runtime)

- `Workspace.StreamingEnabled` : **activé par défaut** pour les nouvelles places ; **non scriptable** (Studio seulement, impossible à changer en jeu). Propriétés de streaming toutes non scriptables : `StreamingMinRadius` (défaut 64), `StreamingTargetRadius` (défaut 1024), `StreamOutBehavior` (LowMemory par défaut, Opportunistic recommandé), `StreamingIntegrityMode` (PauseOutsideLoadedArea recommandé), `ModelStreamingBehavior` (Improved recommandé), `PredictiveStreamingMode`.
- Implications : seules les descendances de Workspace streament ; les BaseParts arrivent plus tard côté client (`WaitForChild`, ne jamais supposer leur présence) ; une instance streamée-out est parentée à `nil` (modifs locales perdues) ; les instances créées par le client ne stream-out pas ; les assemblages streament en bloc ; physique client (et prédiction) seulement dans les zones streamées. Outils : `Model.ModelStreamingMode` (Atomic ; Persistent + `Workspace.PersistentLoaded` ; PersistentPerPlayer), `Player.ReplicationFocus`, `Player:AddReplicationFocus()`, `Player:RequestStreamAroundAsync()`. Server Authority exige le streaming.
- `Workspace.SignalBehavior` : `Default` = **Immediate actuellement** (passera à Deferred) ; les places modèles sont réglées sur `Deferred` ; `Deferred` recommandé. Points de reprise : input, PreRender, PreAnimation, PreSimulation, PostSimulation, Heartbeat, `task.*`, BindToClose ; réentrance limitée à 10. Pièges Deferred : le handler n'a pas encore tourné juste après le déclencheur ; `Destroying` s'exécute après destruction ; préférer `:Once()`.
- `Lighting.Technology` : **déprécié**, non scriptable (Studio seulement) ; remplacé par `Lighting.LightingStyle` (`Soft` = stylisé, `Realistic`) et `Lighting.PrioritizeLightingQuality` (bool), tous deux scriptables. Enum : Legacy, Voxel, Compatibility (déprécié), ShadowMap, Future, Unified. `ShadowSoftness` (défaut 0,2) seulement en ShadowMap/Future. `GlobalShadows` = voxels 4×4×4 studs.
- `Atmosphere` (sous Lighting) : `Density`, `Offset`, `Haze`, `Color`, `Glare` (visible seulement si Haze > 0), `Decay` (Haze et Glare > 0). Les propriétés Fog de Lighting sont masquées si une Atmosphere est présente.
- `Sky` (sous Lighting) : `SkyboxBk/Dn/Ft/Lf/Rt/Up` (+ versions `*Content` ; défauts `rbxasset://textures/sky/sky512_*.tex`), `SkyboxOrientation`, `CelestialBodiesShown`, `StarCount`, `SunAngularSize` (défaut 21, [0 ; 60]), `MoonAngularSize`, `SunTextureId`/`MoonTextureId`. Événement `Lighting.LightingChanged(skyChanged)`.

Sources : https://create.roblox.com/docs/workspace/streaming · https://create.roblox.com/docs/reference/engine/classes/Workspace · https://create.roblox.com/docs/scripting/events/deferred · https://create.roblox.com/docs/reference/engine/enums/SignalBehavior · https://create.roblox.com/docs/reference/engine/classes/Lighting · https://create.roblox.com/docs/reference/engine/enums/Technology · https://create.roblox.com/docs/environment/atmosphere · https://create.roblox.com/docs/reference/engine/classes/Sky

---

## 13. Objets aléatoires payants

- `PolicyService:GetPolicyInfoForPlayerAsync(player: Instance): Dictionary` — yield, `pcall` ; côté client seulement pour le LocalPlayer ; erreur si > 100 appels en vol. Champs : `ArePaidRandomItemsRestricted`, `IsPaidItemTradingAllowed`, `AreAdsAllowed`, `IsContentSharingAllowed`, `IsEligibleToPurchaseSubscription`, `IsEligibleToPurchaseCommerceProduct`, `IsSubjectToChinaPolicies`, `IsEndlessContentLoadAllowed`, `IsEndlessContentAutoplayAllowed`, `IsPhotoToAvatarAllowed`, `AllowedExternalLinkReferences` (legacy, toujours vide).
- `ArePaidRandomItemsRestricted = true` : le joueur ne peut utiliser aucun générateur aléatoire **payé en Robux ou en monnaie achetée avec des Robux** (y compris indirect : clés, tickets, rerolls, boosts de chance, pity). Traitements admis : chemin gratuit gagnable, ordre prédéterminé annoncé, vente directe de l'objet (prix ≈ valeur espérée), masquer/retirer, bloquer avec message, téléporter hors de la zone.
- Transparence (Robux ou monnaie achetable en Robux) : afficher toutes les issues et leurs probabilités en % (somme = 100 % ; bouton « Info »/« Details » avec texte, un simple (i) ne suffit pas), mettre à jour si objets uniques, chiffrer l'effet des boosts.
- **Boîtes aléatoires gratuites** ramassées en jeu (ni Robux ni monnaie) : **non concernées** — la doc exempte les récompenses aléatoires obtenues par une action « sans paiement de Robux ou d'autre monnaie du jeu » (pas de cotes obligatoires) ; `ArePaidRandomItemsRestricted` ne vise que le payant.
- Zone grise : boîte payée avec une monnaie **uniquement gagnée en jouant** (non achetable) — l'exemption mentionne « other in-game currency » → obligation d'afficher les cotes ambiguë (non confirmé) ; prudence : les afficher.
- `IsPaidItemTradingAllowed = false` : interdire l'échange des objets payants ou issus d'aléatoire payant. Le questionnaire de classification de contenu demande si le jeu vend des récompenses aléatoires.

Sources : https://create.roblox.com/docs/reference/engine/classes/PolicyService · https://create.roblox.com/docs/production/monetization/paid-random-items · https://create.roblox.com/docs/production/monetization · https://create.roblox.com/docs/production/promotion/content-ratings

---

## 14. Badges

- `BadgeService:AwardBadgeAsync(userId: User, badgeId: int64): boolean` — yield, `pcall`. Conditions : joueur **connecté** à l'expérience ; ne possède pas déjà le badge ; appel depuis un **Script serveur** (RunContext Server/Legacy) ou un module requis par lui ; place appartenant à **l'expérience propriétaire du badge** ; badge activé (`GetBadgeInfoAsync(badgeId).IsEnabled`). Rate limit : **50 + 35 × utilisateurs par minute**.
- `AwardBadge` (sans Async) : déprécié. `UserHasBadgeAsync(userId, badgeId)` (50 + 35 × joueurs/min ; côté client seulement pour soi), `CheckUserBadgesAsync(userId, {≤ 10 ids})` et `GetUserBadgesAsync(userId, {≤ 100 ids})` (10 + 5 × joueurs/min par serveur), `GetBadgeInfoAsync(badgeId)` (Name, Description, IconImageId, IsEnabled, AwardCount, PastDayAwardCount, Rarity ; cache court). `IsDisabled`, `IsLegal`, `UserHasBadge` dépréciés.
- Création : **5 badges gratuits par 24 h (GMT) et par jeu**, puis 100 Robux chacun ; image 512×512 rognée en cercle.
- Publication : un badge doit appartenir à l'expérience → expérience publiée + badges créés sur le Creator Dashboard. Comportement d'`AwardBadgeAsync` en test Studio non documenté (non confirmé) ; la doc du `IsDisabled` déprécié indique qu'en Studio un badge n'est testable que s'il est **désactivé**.

Sources : https://create.roblox.com/docs/reference/engine/classes/BadgeService · https://create.roblox.com/docs/production/publishing/badges

---

## Conséquences pour Golf Chaos

1. **Balle = assemblage serveur** : `ball:SetNetworkOwner(nil)` dès le spawn (et après chaque re-création/désancrage), jamais d'ownership auto. Tir : le client n'envoie que (direction, puissance) via RemoteEvent ; le serveur valide (tour/état, cooldown, bornes, NaN/inf) puis `ball:ApplyImpulse(...)` (un appel client serait sans effet).
2. **`PhysicsSteppingMethod = Fixed`** (240 Hz) réglé dans Studio (non scriptable ; Default = Adaptive) + balayage serveur anti-tunneling à chaque pas : `workspace:Spherecast(prevPos, rayon, curPos - prevPos, params)` (≤ 1024 studs ; ignore les chevauchements initiaux → reculer légèrement l'origine), vitesse plafonnée, bords et trous épais.
3. **Impacts / trou détectés côté serveur** via `ball:BindToCollisionSummaries` (le serveur est propriétaire) + requêtes `GetPartBoundsInRadius` ; ne jamais se fier à `Touched` (lié à l'ownership, non déclenché par CFrame).
4. **Groupes de collision** enregistrés au démarrage dans un seul script serveur via `workspace:RegisterCollisionGroup` (≤ 32) : Balls, Characters, Carts, Items… ; `Carts`↔`Balls` non collidables (un kart possédé par un client pourrait injecter vitesses extrêmes/NaN dans la balle) ; `Workspace.TouchesUseCollisionGroups = true`.
5. **Karts** : `VehicleSeat` ; sur `Occupant` → `seat:SetNetworkOwner(conducteur)`, siège vide → `SetNetworkOwnershipAuto()` ; validation serveur vitesse/position (seau à fuite, projection XZ) ; effets de combat sur karts appliqués par le serveur.
6. **Remotes** : une RemoteEvent par intention, validation systématique (types, `x == x`, bornes, longueurs), rate limit par joueur bien sous ~500/s ; cosmétique haute fréquence (aperçu de visée) en `UnreliableRemoteEvent` < 1000 octets ; aucune `InvokeClient`. Requêtes spatiales avec `ExcludeInstances`/`IncludeInstances` (pas `FilterDescendantsInstances`, supersédé).
7. **Progression DataStore** : clé `User_{UserId}` dans un store `PlayerData` ; session lock via `UpdateAsync` + `LockId` en métadonnées ; autosave 180 s décalée aléatoirement ; sauvegarde sur `PlayerRemoving` + `BindToClose` en parallèle (< 30 s, ignorée en Studio) ; file ordonnée par clé + backoff/jitter ; relecture `UseCache = false` après échec ; jamais de NaN/inf ; strings UTF-8.
8. **Adaptateur DataStore en mémoire** (même interface Get/Set/Update/Remove, mêmes règles de verrou) utilisé automatiquement en Studio non publié ou sans « Studio Access » (erreur 403 / « must publish » au 1er appel) et dans les tests multi-clients ; le vrai DataStore uniquement sur une **expérience de test séparée** (Studio partage les données de prod).
9. **Matchs privés** : le lobby génère `ReservedServerId = HttpService:GenerateGUID(false)` côté serveur ; code de lobby → GUID stocké en MemoryStore HashMap (TTL court) ; `TeleportAsync` (≤ 50 joueurs) en `pcall` + retries ; `TeleportInitFailed` géré (Flooded → 15 s) ; détection `PrivateServerId ~= "" and PrivateServerOwnerId == 0` ; aucun `ReserveServer`/`ReservedServerAccessCode` (dépréciés). Matchs publics : file MemoryStore + même mécanisme. Tester en Test/Team Test en tenant compte des JobId/PrivateServerId vides ou différents (VIP impossible en test).
10. **Texte saisi par les joueurs** (noms de lobby, d'équipe) : `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync` côté serveur, rien d'affiché si échec ; pas de chat parallèle (texte in-world : rate limit ≥ 1 min) ; chat = TextChatService par défaut, prêt pour PlatformIntegratedChat (obligatoire mai 2027) : commandes via `TextChatCommand`.
11. **Inputs** : Input Action System (tir, visée, objets, kart) plutôt que ContextActionService (dépréciation prévue, 7 boutons tactiles max) ; `UserInputService.PreferredInput` pour adapter l'UI ; navigation manette via `GuiService:Select()` / `SelectedObject` / `NextSelection*` ; vibrations via `HapticEffect`.
12. **Animations sans assets** : poses procédurales (swing, célébrations, KO cartoon) écrites dans `Transform` pendant `RunService.PreSimulation` sur chaque client, pilotées par des attributs répliqués ; joints trouvés via `AnimationConstraint` puis repli `Motor6D` (AvatarJointUpgrade) ; `RegisterKeyframeSequence`/`RegisterAnimationClip` exclus (Studio uniquement). PNJ/bots : `CreateHumanoidModelFromDescriptionAsync` côté serveur, `Humanoid:Move` par waypoint (MoveTo expire à 8 s).
13. **Tests automatisés** : plugin de test qui appelle `StudioTestService:ExecuteMultiplayerTestAsync(n ≤ 8, args)` (scénarios lobby → match → départ via `LeaveTest`, arrivées tardives via `AddPlayers`, verdict via `EndTest`) + Network Simulator / `NetworkSettings` (latence, jitter, perte ≤ 0,5 %) pour juger le ressenti de la balle serveur à 100–300 ms.
14. **Réglages Studio (non scriptables)** : `SignalBehavior = Deferred` explicite (Default = Immediate) ; `StreamingEnabled` choisi consciemment (OFF plus simple pour des parcours compacts générés au runtime ; ON obligatoire si l'on adopte Server Authority, qui reste en bêta) ; `LightingStyle = Soft` par script (Technology déprécié).
15. **Monétisation & récompenses** : boîtes d'objets gratuites ramassées en jeu = hors politique « paid random items » ; si un jour vendues en Robux (ou monnaie achetable) → cotes affichées + gating `ArePaidRandomItemsRestricted` côté serveur. Badges via `AwardBadgeAsync` serveur + pcall (badges de cette expérience, 50 + 35×joueurs/min, 5 créations gratuites/jour). Sons : uniquement des IDs vérifiés du Creator Store ou des `rbxasset://` testés, avec repli silencieux.

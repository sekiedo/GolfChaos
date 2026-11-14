# Cahier des charges — Golf Chaos

| Élément | Valeur |
| --- | --- |
| Version | 1.1 — 13/11/2026 (la v1.0 du 12/11/2026 s'arrêtait au §4 ; voir §22) |
| Statut | Référence fonctionnelle et technique du développement. Elle évolue par révision datée (§22) et ne déclare **aucune** fonctionnalité terminée |
| Sources | `docs/SPEC_DEMANDE.md` (demande d'origine, fait foi en cas de doute), `docs/ARCHITECTURE.md` (contrat technique, fait foi pour les noms, signatures et attributs) |
| Spécifications détaillées | `docs/REGLES_SCORE.md` (score, modes, durées), `docs/REGISTRE_OBJETS.md` (17 objets), `docs/MATRICE_INTERACTIONS.md`, `docs/PLAN_PARCOURS.md` (81 trous), `docs/MANIFESTE_ASSETS.md` (provenance), `docs/notes-techniques-roblox.md` (API Roblox) |
| Suivi des preuves | `docs/MATRICE_COUVERTURE.md` (une ligne par exigence, identifiants stables) et `docs/ETAT_REPRISE.md` (journal d'avancement) |

Ce document transforme la demande en exigences vérifiables. L'état réel de chaque exigence, la preuve obtenue et
la limite restante sont consignés dans la matrice de couverture, jamais ici.
Les mots **doit** (obligatoire), **devrait** (recommandé, écart justifié possible) et **peut** (facultatif) ont
leur sens normatif habituel. Les valeurs chiffrées citées sont les **valeurs initiales** : elles vivent dans
`src/shared/Config/*` et la configuration fait foi si elle a évolué depuis cette révision.

## Sommaire

1. Objet, périmètre et non-objectifs
2. Joueurs cibles et supports
3. Glossaire
4. Boucle de jeu et machine à états
5. Modes de jeu
6. Score
7. Golf : commandes et physique
8. Déplacement, combat et KO
9. Les 17 objets
10. Les 81 trous et la création des niveaux
11. Direction artistique, avatar et cosmétiques
12. Progression et sauvegarde
13. Salon, interface, accessibilité et communication
14. Architecture technique
15. Sécurité et autorité serveur
16. Performances
17. Stratégie de validation et catégories de preuve
18. Définitions : « implémenté », « testé », « prêt à publier »
19. Livrables
20. Limites actuelles de l'environnement
21. Exécution par étapes
22. Gestion des révisions

---

## 1. Objet, périmètre et non-objectifs

### 1.1 Objet

« Golf Chaos » (nom de travail) est un jeu Roblox de golf **multijoueur simultané** : chaque joueur possède sa
balle, tout le monde joue en même temps, contrôle son personnage à la troisième personne, frappe sa balle puis la
rejoint à pied ou en véhicule. La course vers le trou est pimentée par des combats cartoon, des objets, des
voiturettes, de nombreux parcours et la personnalisation des personnages, clubs et balles. Les mécaniques
s'inspirent du genre « golf de combat » ; les chiffres retenus sont **notre adaptation** et ne prétendent pas
reproduire les réglages d'un jeu existant.

### 1.2 Périmètre de la livraison finale

La livraison finale **doit** être un jeu complet, utilisable dans Roblox Studio, comprenant :

| Domaine | Contenu exigé |
| --- | --- |
| Boucle de jeu | machine à états complète de l'accueil au podium et retour (§4) |
| Modes | Chacun pour soi, Équipes rouge/bleue, Solo, Entraînement, Spectateur (§5) |
| Golf | visée, loft, puissance chargée, putt, frappe aérienne, physique par surface, vent, eau, anti-traversée (§7) |
| Combat | saut, course, plongeon, frappe de proximité, tir de balle guidé, KO, recul, protections (§8) |
| Objets | 17 objets fonctionnels, inventaire, boîtes, rattrapage, matrice d'interactions (§9) |
| Parcours | 81 trous distincts sur 5 biomes + trous d'entraînement, playlists (§10) |
| Personnalisation | ≥ 100 cosmétiques équipables + ≥ 8 émotes animées, boutique, aperçu 3D, ensembles (§11) |
| Progression | monnaie, récompenses, ≥ 30 défis, sauvegarde persistante sûre (§12) |
| Interface | accueil jouable, menus, HUD complet, résultats, podium, réglages d'accessibilité (§13) |
| Documentation | README, architecture, règles, catalogues, registre, manifeste, matrice, rapport final (§19) |

Une démonstration à trois trous, une interface seule ou un dossier de scripts non intégré **ne remplit pas** la demande.

### 1.3 Non-objectifs (exclusions explicites)

| Exclusion | Conséquence |
| --- | --- |
| Boutique Robux, produits développeur, passes | aucun achat en Robux dans cette livraison ; aucune activation de monétisation |
| Pay-to-win | aucun avantage de jeu achetable ; les cosmétiques ne changent que l'apparence (§11.4) |
| Assets du jeu Steam de référence | aucun modèle, son, image, animation, nom ou niveau repris ; aucune collaboration de marque reproduite |
| AssetId inventés | seuls le contenu intégré `rbxasset://`, les ressources vérifiées consignées dans `docs/MANIFESTE_ASSETS.md` et la géométrie construite par code sont permis |
| Publication publique, envoi de messages, achats | jamais sans demande explicite de l'utilisateur ; on prépare la publication sans la faire |
| Système de communication parallèle | pas de chat maison contournant les permissions Roblox (§13.6) |
| BadgeId réels | non requis : succès internes autonomes, raccordement ultérieur possible (§12.3) |
| Écrasement d'une place de l'utilisateur | aucune place de l'utilisateur n'est modifiée (ex. la place cloud « super combat blox ») ; la construction écrit dans `build/` (sortie par défaut `build/GolfChaos.rbxlx`, ou `build/GolfChaos_src.rbxlx` quand l'utilisateur peut avoir ouvert le premier) ; aucune fenêtre Studio n'est lancée tant qu'une fenêtre non ouverte par l'outillage est présente (§20) |

### 1.4 Originalité

- Le nom, les interfaces, les modèles, les sons, les animations et les niveaux **doivent** être une création originale.
- Les 17 objets portent des **noms originaux** (§9.1) ; la « mécanique de référence » de la demande n'est utilisée
  que comme description interne.
- Les 81 trous ont des **tracés et des noms originaux** (plan : `docs/PLAN_PARCOURS.md`).
- Le monde (accueil, trous, décors, interface, cosmétiques) est **généré par le code** à partir des données de `src/` :
  aucune étape manuelle de construction de niveau.

## 2. Joueurs cibles et supports

### 2.1 Nombre de joueurs

| Exigence | Valeur |
| --- | --- |
| Cible principale | **1 à 8 joueurs** par serveur, tous modes (`Config/Match.MaxParticipants` = 8) |
| Architecture | prévue pour **16 joueurs** (aucune structure limitée à 8 : listes, départs, couleurs, barème jusqu'au 16e rang, UI de classement) |
| Mode 16 joueurs | **expérimental** : réglage `MatchSettings.experimental16`, désactivé par défaut ; reste marqué expérimental tant que sa stabilité n'a pas été mesurée par un test séparé (§17.4) |
| Solo | jouable à 1 sans adversaire obligatoire (mode Solo, Entraînement) |
| Spectateurs | un joueur peut choisir d'être spectateur (`Match.SetSpectator`) sans compter dans les participants |

### 2.2 Supports et commandes

| Support | Exigence |
| --- | --- |
| PC | clavier + souris ; toutes les actions accessibles sans manette |
| Mobile / tablette | commandes tactiles dédiées, boutons de taille confortable (≥ 44 px logiques), interface lisible en paysage, aucune action réservée au clavier |
| Manette | parité complète : chaque action possède une liaison manette, navigation de tous les menus au focus (`GuiService.SelectedObject`) |
| Détection | `InputController.GetDevice()` renvoie `KeyboardMouse`, `Touch` ou `Gamepad` ; l'interface (invites, icônes de touches) s'adapte à chaud via `DeviceChanged` ; les libellés de touches sont lus dynamiquement (positions physiques : un clavier AZERTY affiche ses propres lettres) |

### 2.3 Langues

- Interface **française** par défaut ; **tous** les textes affichés passent par `Locale.t("domaine.cle", vars)`.
- Chaque clé existe en `Locale/fr/<Domaine>.luau` **et** `Locale/en/<Domaine>.luau` (traduction anglaise complète,
  mêmes variables `{x}` ; vérifié par `tests/Specs/Locale.spec.luau`).
- Le choix de langue est une préférence joueur sauvegardée (§12.4).

## 3. Glossaire

| Terme | Définition |
| --- | --- |
| Partie (match) | suite de trous jouée entre `Preparing` et `Podium` ; identifiée par `GameState.MatchId` (GUID) |
| Trou / manche | un trou de la playlist ; chaque chargement incrémente `GameState.RoundId` |
| `RoundId` | numéro de manche transporté par toute intention de jeu ; une intention d'une manche précédente est ignorée |
| Participant | joueur inscrit à la partie (attribut `Participant`) ; un spectateur ne l'est pas |
| Participant actif | participant présent sur le trou courant, non terminé, non abandonné, non AFK (`MatchService.IsActive`) |
| Joueur ayant terminé | balle entrée dans le trou (`HoleFinished`) ; devient intangible (groupe de collision `Ghosts`) |
| Fantôme | joueur ayant terminé, abandonné ou AFK : groupe `Ghosts`, ne peut ni affecter ni être affecté |
| KO | mise hors d'état temporaire (ragdoll) ; pas de points de vie ni d'élimination |
| Frappe majeure / mineure | majeure = KO + fort recul ; mineure = KO court ou simple recul (§8.4) |
| Protection | invulnérabilité brève après réapparition (attribut `Protected`) |
| Checkpoint | point de réapparition le long du parcours (`CourseService.GetCheckpointFor`) |
| Hors limites | zone d'eau, de vide, de lave ou hors des bornes du trou ; la balle revient à sa dernière position valide avec pénalité |
| Boîte d'objet / de mobilité | ramassable en jeu ; le serveur tire le contenu (§9.4) |
| Rattrapage | ajustement des probabilités de tirage selon la position dans la course |
| Hôte | joueur qui règle la partie (`GameState.HostUserId`) ; transféré automatiquement s'il part |
| Trove | conteneur de nettoyage (`Util/Trove`) attaché à une durée de vie : manche, joueur, personnage, effet |
| Balle d'entraînement | balle créée à l'accueil (phases `Lobby`/`Preparing`) : coups jamais comptés, pas de KO, pas de vent |
| Balle de simulation | balle sans propriétaire des outils de validation (`BallService.CreateSimBall` / `StepSim`) |
| Opération idempotente | transaction serveur identifiée par un `opId` : rejouée, elle ne s'applique qu'une fois (`PlayerDataService.Transact`) |
| Adaptateur mémoire | stockage de profil non persistant utilisé quand DataStore est indisponible (`DataStatus = "Memory"`) |
| Catégorie de preuve | nature d'une vérification : analyse statique, test unitaire, simulation, test moteur, multi-clients, appareil physique, service réel (§17.1) |

## 4. Boucle de jeu et machine à états

### 4.1 Phases

La partie suit une machine à états **explicite**, définie de façon pure dans `src/shared/Logic/MatchStateMachine.luau`
(table des transitions autorisées, testée unitairement) et pilotée **uniquement** par `MatchService`, seul module
autorisé à écrire `GameState.Phase` :

```
Lobby → Preparing → Loading → HoleIntro → Countdown → Playing → HoleEnd → HoleResults
      → (Loading du trou suivant | Podium) → Lobby
```

| Phase (`Types.Phase`) | Rôle | Sortie normale | Durée maximale (exigence) |
| --- | --- | --- | --- |
| `Lobby` | accueil jouable : entraînement libre, boutique, personnalisation | l'hôte ouvre la préparation (`Lobby.Advance`) | illimitée (pas de partie en cours) |
| `Preparing` | l'hôte règle la partie, les joueurs se déclarent prêts, équipes | l'hôte lance, ou tous prêts (3 s), avec ≥ 1 participant | 240 s ; retour `Lobby` si l'hôte annule ou si le salon se vide |
| `Loading` | construction du trou, placement des joueurs et des balles, `RoundId` + 1 | trou construit et joueurs placés | 1,5 s minimum, 25 s maximum ; un client lent n'est pas attendu indéfiniment |
| `HoleIntro` | survol caméra, nom, par, particularité | fin de la présentation | 5 s |
| `Countdown` | compte à rebours 3-2-1, frappes bloquées | fin du compte | 3 s |
| `Playing` | jeu simultané | tous les actifs ont terminé / abandonné / AFK / déconnectés, ou fin du chronomètre (prolongation incluse) | durée limite du trou (§6.3) ; sécurité absolue 900 s |
| `HoleEnd` | résultats figés : plus aucune action ne modifie le score | délai court | 3 s |
| `HoleResults` | tableau des résultats du trou | délai | 8 s |
| `Podium` | classement final, récompenses uniques | délai | 12 s, puis `Lobby` |

Transitions exceptionnelles (toutes dans la table) : `Preparing → Lobby` (annulation, salon vide, délai dépassé),
toute phase de partie `→ Lobby` (partie interrompue : plus aucun participant, erreur), `Loading → Podium` (plus aucun
trou chargeable alors qu'au moins un trou a été joué). Chaque transition **doit** être validée par la table ; une
transition refusée est journalisée (`Log.warn`) et ne change pas la phase. `GameState.PhaseEndsAt` publie l'heure
serveur de fin de phase (0 si indéfinie) pour les chronomètres clients.

### 4.2 État répliqué

L'état continu passe **uniquement** par les attributs du dossier `ReplicatedStorage.GameState` (obtenu via
`shared/Util/GameState.luau`) et par les attributs des joueurs, balles et personnages, **avec les noms exacts** de
`docs/ARCHITECTURE.md` §6 (`Phase`, `PhaseEndsAt`, `RoundId`, `MatchId`, `Mode`, `HoleIndex`, `HoleCount`, `HoleId`,
`HoleName`, `HoleBiome`, `HolePar`, `CupPosition`, `Wind`, `HoleStartedAt`, `OvertimeEndsAt`, `HostUserId`,
`SettingsJson`, `TeamScoreRed`, `TeamScoreBlue`, `PersistentData` ; joueurs : `Participant`, `Spectating`, `Team`,
`Strokes`, `HoleFinished`, `FinishOrder`, `MatchPoints`, `Ready`, `Aiming`, `KnockedOut`, `Protected`, `AFK`, `Coins`,
`DataStatus`, `Inventory`, `InventoryCapacity`, `SelectedSlot`, `ActiveEffects`, `InVehicle`). Les événements
ponctuels (arrivée, résultats, podium, annonces, KO) passent par les remotes `ToClient` de `Net/Remotes/Match.luau`,
`Golf.luau` et `Combat.luau`.

### 4.3 Règles de fin de trou

- `HoleEnd` **fige** les résultats : aucune frappe, aucun KO, aucun objet ne modifie plus le score.
- Un joueur qui a terminé **ne peut ni frapper ni gêner** ceux qui jouent encore : il passe dans le groupe de
  collision `Ghosts` (`CollisionService.SetGhost`), ne peut ni affecter ni être affecté (`CombatService.CanAffect`),
  ses pièges et nuages en cours sont retirés ; il peut observer (caméra spectateur du trou).
- `MatchService` appelle en fin de trou `ItemService.ClearRound()`, `VehicleService.ClearAll()`,
  `BallService.RemoveAll()` puis nettoie la `Trove` de manche (§14.4).

### 4.4 Cas limites : aucun ne bloque la progression

| Cas | Traitement exigé |
| --- | --- |
| Égalité de points / d'ordre | départage déterministe (`docs/REGLES_SCORE.md` §5.2 et §5.8) : arrivées traitées pendant la même image serveur = rang partagé (1, 1, 3) ; partie : points, puis trous gagnés, puis coups retenus, puis birdies ou mieux ; égalité parfaite = rang partagé |
| Arrivée tardive | si `lateJoin` : le joueur rejoint au **trou suivant** comme participant (spectateur en attendant) ; sinon spectateur jusqu'à la partie suivante ; jamais d'injection au milieu d'un trou ; jamais en Solo |
| Déconnexion | résultat `Disconnected` pour le trou ; balle, effets, pièges, kart nettoyés ; la condition de fin de `Playing` est réévaluée immédiatement |
| Changement d'hôte | si l'hôte part, `LobbyService` désigne le joueur présent depuis le plus longtemps et émet `HostChanged` ; jamais de salon sans hôte s'il reste un joueur |
| Abandon | `Match.Forfeit(roundId)` : statut `Forfeit`, le joueur devient spectateur intangible du trou |
| AFK | aucune frappe acceptée ni déplacement significatif (≥ 4 studs) pendant 60 s (25 s si le joueur était déjà AFK au trou précédent) ; `Match.Heartbeat` ne compte qu'accompagné d'un mouvement ; attribut `AFK`, exclu de la condition de fin, statut `AFK` |
| Balle bloquée | `Golf.ResetBall(roundId)` : retour à la dernière position valide avec pénalité configurable ; immobilisation forcée après 3 s sans déplacement et arrêt de sécurité après 30 s de mouvement |
| Tous partis | retour `Lobby`, nettoyage complet, aucune récompense |
| Fin du chronomètre | statut `TimeOut` pour les non-arrivés ; prolongation déclenchée par la première arrivée (§6.3) |

Chaque phase a une **durée maximale** ; aucune attente n'est conditionnée à un seul client.

## 5. Modes de jeu

Le mode est un réglage d'hôte (`MatchSettings.mode`, `Types.Mode`) figé au lancement de la partie. Le rôle de
spectateur est disponible dans tous les modes. Règles détaillées et valeurs : `docs/REGLES_SCORE.md`.

### 5.1 Vue d'ensemble

| Mode | `Types.Mode` | Participants | Gagnant | Objets et voiturettes | Pièces |
| --- | --- | --- | --- | --- | --- |
| Chacun pour soi | `FreeForAll` | 1–8 (16 expérimental) | total des points (arrivée + bonus) | selon `itemsEnabled` | oui |
| Équipes rouge / bleue | `Teams` | 1–8 (16 expérimental) ; aucune équipe vide dès 2 participants | total des points d'équipe ; égalité = match nul | oui, jamais contre un allié | oui |
| Solo | `Solo` | 1 (les autres regardent) | coups par rapport au par, puis temps | selon `itemsEnabled` | oui (barème solo) |
| Entraînement | `Training` | 1–8 | aucun classement | oui (essais) | non (seule exception : tutoriel, une fois) |
| Spectateur | rôle (`Spectating`) | — | — | — | — |

### 5.2 Chacun pour soi

- Points du trou = barème d'arrivée + bonus de performance plafonnés (§6.2) ; vainqueur = premier du classement (§6.4).
- KO, objets et tirs guidés permis entre tous les participants ; `friendlyFire` est sans objet.
- L'interface **doit** afficher le classement provisoire après chaque trou et le podium final avec le rang de chacun.

### 5.3 Équipes rouge / bleue

- **Composition** : chaque participant choisit `Red`, `Blue` ou `Auto` (`Lobby.SetTeam`) ; l'hôte peut équilibrer
  (`Lobby.BalanceTeams` : Rouge, Bleu, Rouge… dans l'ordre d'arrivée, remplace les choix) ; au lancement, chaque `Auto`
  rejoint l'équipe la moins nombreuse (Rouge si égalité) ; dès 2 participants aucune équipe n'est vide ; un arrivant
  tardif rejoint l'équipe la moins nombreuse. Équipes déséquilibrées permises.
- **Point d'équipe par trou** : l'équipe au plus fort **ratio d'arrivées** (arrivées / membres présents au départ du
  trou ; un départ en cours de trou ne favorise pas son équipe) marque 1 point ; à ratio égal, le plus d'arrivées
  absolues ; puis la plus basse moyenne de coups des joueurs arrivés ; sinon aucun point.
- **Fin de partie** : le plus grand total gagne ; égalité = match nul (`Draw`).
- **Alliés** : jamais de KO, de recul, d'effet d'objet, de verrouillage ni de piège déclenché entre alliés
  (`MatchService.AreAllies`, `CombatService.CanAffect`) ; `friendlyFire` est ignoré dans ce mode.
- **Lisibilité** : les équipes sont identifiées par la couleur **et** par un nom ou un pictogramme (§13.5).

### 5.4 Solo

- Un seul participant : l'hôte s'il participe, sinon le joueur présent depuis le plus longtemps ; les autres regardent.
- Score = coups totaux par rapport au par total (« +2 », « −1 ») puis temps total ; un trou non terminé compte
  `max(coups, plafond)` et la durée limite du trou. Ni barème d'arrivée ni prolongation.
- Record personnel par trou (`stats.bestSolo[holeId]`), mis à jour seulement pour un trou terminé (moins de coups,
  puis temps plus court).

### 5.5 Entraînement

- **Driving Range** (`ENT-01`, `Lobby.RequestTraining` avec `"Range"`) : essais libres des frappes Drive, Chip et Putt
  avec aperçu de trajectoire, sans vent, sans KO, coups jamais comptés.
- **Tutoriel interactif** (`ENT-02`, `Lobby.RequestTraining` avec `"Tutorial"`) : étapes guidées (se déplacer, viser,
  doser la puissance, putter, sauter et plonger, frappe de proximité, ramasser et utiliser un objet, monter dans un
  kart), chacune validée par une action réelle constatée par le serveur ; récompense unique du défi `ach_tutorial`.
- **Essais des objets et des voiturettes** : à l'accueil, un poste d'essai par objet et un Kart-Caddie, utilisables
  seulement en phase `Lobby` ; et le mode de partie `Training`, qui déroule la boucle complète (essais de trous,
  objets, voiturettes) **sans points ni récompenses** (`RewardService` n'est pas appelé).
- **Anti-farm** : aucune pièce, et aucune progression de défi récompensé, n'est obtenue par une action
  d'entraînement, à la seule exception du tutoriel (une fois).

### 5.6 Spectateur

- On devient spectateur par choix (`Match.SetSpectator(true)`, effectif à la partie suivante), en attendant le trou
  suivant après une arrivée tardive, ou pour le reste du trou après avoir terminé, abandonné ou été déclaré AFK.
- Caméra de suivi (`CameraController.Follow`) d'un participant en jeu ; changement du joueur observé (suivant /
  précédent) au clavier, à la manette et au tactile ; affichage du nom, des coups et du rang du joueur suivi ;
  bascule automatique quand le joueur suivi termine ou part.
- Un spectateur n'a ni balle ni inventaire, ne peut ni affecter ni être affecté et n'entre pas dans la condition de fin.

## 6. Score

La spécification normative est `docs/REGLES_SCORE.md` (v1.1, écrite **avant** l'implémentation). Les valeurs vivent
dans `Config/Scoring.luau` et `Config/Match.luau`, les calculs dans `Logic/Scoring.luau` (fonctions pures), appliqués
par `MatchService`. Résumé des exigences :

### 6.1 Principes

1. Le serveur mesure tout (ordre d'arrivée, coups, distances, temps) et calcule tous les points.
2. La course prime : les bonus golfiques sont cumulables mais plafonnés sous la valeur d'une victoire.
3. Chaque égalité possible a une règle écrite ; une égalité parfaite donne un rang partagé.
4. Rien ne bloque : chronomètre, prolongation, plafond de coups, AFK, abandon et déconnexion terminent toujours le trou.

### 6.2 Points d'un trou (Chacun pour soi)

```
points = barème(rang d'arrivée) + min(catégorie + coup de loin + vitesse, 8)      (0 si le trou n'est pas terminé)
```

| Rang d'arrivée | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 à 16 | non arrivé |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Points | 12 | 9 | 7 | 5 | 4 | 3 | 2 | 1 | 1 | 0 |

| Bonus (cumulables, plafond 8 par trou, trou terminé uniquement) | Condition | Points |
| --- | --- | --- |
| Catégorie (une seule, la meilleure) | trou en un / albatros (par − 3) / eagle (par − 2) / birdie (par − 1) / par | +6 / +5 / +4 / +2 / +1 |
| Coup rentré de loin | coup final parti d'au moins 40 studs du trou (horizontal, mesuré par le serveur), putts exclus | +2 |
| Vitesse | arrivée en au plus 50 % de la durée de référence (`targetTime × timeScale`) | +1 |

### 6.3 Chronomètre, prolongation et plafond de coups

- Durée limite d'un trou : `clamp(targetTime × timeScale × 2, 45 s, 600 s)` (`targetTime` = 90 s si absent).
- **Prolongation** à la première arrivée : le temps restant est ramené dans `[20 s ; 45 s] × timeScale`, une seule fois
  par trou, seulement s'il reste un autre joueur en jeu ; `OvertimeEndsAt` et `PhaseEndsAt` publient l'échéance.
- **Plafond de coups** : `clamp(par + 7, 10, 14)` ; au-delà, le serveur refuse toute frappe ; une balle immobile au
  plafond sans être rentrée entraîne l'abandon automatique (statut `Forfeit`, motif `strokeCap`).

### 6.4 Statuts, égalités et classement

- Statuts de fin de trou : `Finished` (barème + bonus), `TimeOut`, `Forfeit`, `AFK`, `Disconnected` (0 point).
- Arrivées traitées pendant la même image serveur : rang partagé (1, 1, 3) ; chacun reçoit les points du rang partagé.
- Classement de partie : points ↓, trous gagnés ↓ (rang 1 partagé compris), coups retenus ↑ (`max(coups, plafond)` pour
  un trou non terminé ou manqué), birdies ou mieux ↓, puis rang partagé. Un joueur parti est retiré du podium.

### 6.5 Équipes et Solo

Règles d'équipe : §5.3 ; Solo : §5.4 ; Entraînement : aucun score (§5.5).

### 6.6 Configuration et preuves

- Aucun nombre du score n'est écrit en dur : changer un équilibrage = modifier la configuration, mettre à jour
  `docs/REGLES_SCORE.md`, relancer les tests.
- `tests/Specs/Scoring.spec.luau` **doit** couvrir la liste de `docs/REGLES_SCORE.md` §12 (barème 1 à 16, chaque bonus,
  seuil du coup de loin et exclusion du putt, vitesse, plafond, arrivées simultanées, départages, plafond de coups,
  équipes déséquilibrées et chaque niveau de départage d'équipe, composition des équipes, prolongation, solo et record) ;
  `MatchStateMachine.spec.luau` et `Playlist.spec.luau` couvrent les transitions et les playlists. Ce sont des tests
  unitaires ; la mesure serveur des distances et des arrivées simultanées exige en plus des tests moteur.

## 7. Golf : commandes et physique

### 7.1 Commandes de frappe

| Action | Exigence (valeurs : `Config/Gameplay`) |
| --- | --- |
| Entrer / sortir de la visée | automatique à ≤ 9 studs de sa balle, annulée au-delà de 14 studs (tolérance serveur 4 studs) ; `Golf.AimState` |
| Visée horizontale | direction de la caméra, du stick ou du glisser tactile ; envoyée normalisée et revalidée par le serveur (`Validate.flatUnit`) |
| Angle vertical (loft) | réglable par crans de 3°, borné par le type : Drive 8–60°, Chip 48–60°, Putt 0–3°, Guided 2–20° |
| Type de frappe | Drive (longue), Chip (**frappe aérienne** lobée, puissance × 0,6), Putt (sur le green ou à moins de 30 studs du trou), Guided (tir guidé, §8.3) |
| Puissance chargée | jauge triangulaire 0 → 1 → 0 de période 1,6 s ; `Golf.SwingStart` est horodaté par le serveur, puis `Golf.Shoot` ; le serveur recalcule la puissance depuis son horodatage et n'accepte la valeur client qu'à ± 0,2 (écart > 0,45 signalé) ; swing de 0,12 à 12 s ; 0,4 s minimum entre deux frappes |
| Indicateur de trajectoire | `BallMath.predictTrajectory` avec **les mêmes paramètres que le serveur** (gravité de la balle, traînée de l'air, vent courant), horizon 4 s ; le roulement après l'impact n'est pas promis par l'aperçu |
| Frappe refusée | motif renvoyé par `Golf.AimCancelled` (`stun`, `horn`, `too_far`, `invalid`, `unavailable`, `respawn`, `phase`, `no_target`) ; aucun coup n'est compté |

Chaque action possède une liaison clavier/souris, manette et tactile (§2.2) ; une frappe n'est jamais déclenchée par
une animation ou un effet visuel.

### 7.2 Physique de la balle et surfaces

- Balle = Part serveur de Ø 1,2 stud et de densité 0,7, **identique pour tous** ; gravité subie = 0,5 × `Workspace.Gravity`
  (compensation par `VectorForce`) ; vitesse plafonnée à 160 studs/s ; immobilisation sous 1,2 stud/s pendant 0,6 s
  si la pente le permet ; arrêt de sécurité après 30 s de mouvement.
- Surfaces (`Config/Gameplay.Surfaces`, attribut `Surface` ou matériau) : chacune définit freinage proportionnel,
  résistance de roulement, frottement et rebond. Effets exigés :

| Surface | Effet exigé |
| --- | --- |
| Fairway / herbe | référence : roulement moyen |
| Green | roulement long et précis (putt) |
| Rough | freine nettement |
| Sable | freine fortement, rebond quasi nul : pénalisant |
| Glace | glisse (frottement quasi nul) |
| Neige, boue | freinent fortement (boue : la plus pénalisante) |
| Roche, bois, asphalte | rebonds vifs |

- **Pentes** : la balle roule dans le sens de la pente ; elle ne s'immobilise que si `g_balle × sin(pente)` reste sous la
  résistance de roulement × 1,25 (une balle ne « colle » pas à une pente raide).

### 7.3 Dangers, hors limites et balle bloquée

- Dangers `water`, `oob`, `lava`, `void` : volumes tagués `GolfHazard`, eau du Terrain, bornes du trou
  (`CourseService.IsOutOfBounds`) et altitude `killY`. Conséquence : +1 coup (configurable, plafond 10), replacement
  à la dernière position valide (`BallService.ResetToLastValid`), annonce `Golf.BallReset`.
- Hors limites seulement au **contact du sol** (survoler est permis) ; aucune pénalité si la balle a été poussée dans
  le danger par un tiers (objet, plateforme disparue).
- Balle bloquée : immobilisation forcée après 3 s sans déplacement de plus de 0,35 stud ; `Golf.ResetBall` remet la
  balle à sa dernière position valide avec +1 coup (règle « coup et distance »).

### 7.4 Vent

Accélération horizontale appliquée **en vol uniquement** : `Off` 0, `Light` 5, `Strong` 12, `Random` tiré entre 0 et
14 studs/s² (borne de sécurité 40), éventuellement orienté par le `windBias` du trou ; publiée dans `GameState.Wind`
et affichée (direction et force) ; jamais appliquée aux balles d'entraînement.

### 7.5 Anti-traversée et entrée dans le trou

- `Workspace.PhysicsSteppingMethod = Fixed` (240 Hz, réglé dans `default.project.json`) et **balayage `Spherecast`**
  (rayon × 0,8) entre deux pas serveur, confirmé par un rayon central : une balle rapide ne traverse jamais un obstacle
  mince ; elle est replacée devant la surface et réfléchie selon l'élasticité.
- **Capture du trou côté serveur** par test balayé segment–cercle (rayon 1,7 + 0,1) : vitesse horizontale maximale de
  34 studs/s au centre, moitié au bord (au-delà, ressortie déviée de 14° avec 15 % de perte) ; fenêtre verticale
  (+1,25 / −1,5 stud) : une balle en vol passe au-dessus ; une balle en équilibre au bord (≤ 2,3 studs, quasi arrêtée)
  tombe après 0,4 s ; capture uniquement en phase `Playing`. **Aucun point n'est accordé à distance.**
- La distance du coup final (`info.fromDistance`) et le caractère putt sont mesurés par le serveur.

### 7.6 Collision de référence et affichage

Le Part serveur (neutre, blanc) est la **seule** collision de référence. Le client affiche le skin sur une balle
visuelle lissée vers la position serveur (lissage 18/s, recalage au-delà de 12 studs d'écart) ; un skin ne modifie
jamais la taille, la masse ou la collision.

### 7.7 Propriété réseau et latence

| Élément | Simulation | Garde-fous |
| --- | --- | --- |
| Balle | serveur (`SetNetworkOwner(nil)`) | balayage, capture et dangers décidés par le serveur |
| Personnages | client (réactivité) ; serveur pendant un KO | plausibilité des déplacements (§8.7) |
| Kart-Caddie | conducteur (`VehicleSeat`) | vitesse plafonnée et vérifiée ; impacts sur joueurs décidés par le serveur ; karts sans collision avec les balles |
| Projectiles | serveur (sans Part physique) | rendus par les clients (`Items.Projectile`, corrections `Items.ProjectileUpdate` non fiables) |

La stratégie **doit** être testée avec de la latence (Network Simulator ou `NetworkSettings`, 100 à 300 ms avec gigue) :
frappes acceptées, captures, KO et contrôle de plausibilité sans faux positif ; résultats consignés.

### 7.8 Équité et sensations

- Longues frappes cohérentes : même formule partout (Drive 25 → 150 studs/s). Petit putt précis : Putt 2 → 60 studs/s
  avec courbe de puissance 1,5 (résolution fine aux faibles puissances).
- Un avatar ou une balle avec un autre skin n'obtient **aucun** avantage physique : Part identique, proportions R15
  identiques (`LoadCharacterAppearance = false`), cosmétiques sans masse ni collision ; portées et impacts calculés sur
  le `HumanoidRootPart` et la balle serveur.

## 8. Déplacement, combat et KO

Valeurs : `Config/Gameplay` (`Movement`, `Punch`, `Dive`, `Guided`, `BallHit`, `KO`, `Knockback`). Le combat est actif
en phases `Lobby`, `Preparing` et `Playing`.

### 8.1 Déplacements

- **Course** : déplacement à pied (16 studs/s × `gameSpeed` pendant une partie), modifié par les effets (Expresso, flash,
  géant) ; un sprint distinct n'est pas exigé. **Saut** : `JumpPower` 50, modifiable (Bottes Kangourou).
- **Plongeon / esquive** (`Combat.Dive`) : poussée de 52 studs/s pendant 0,22 s, fenêtre d'esquive `Dodging` de 0,35 s
  (projectiles, rayons et balles guidées ratent ; verrou de fusée rompu), recharge 2,5 s ; les zones (Rayon Satellite,
  éclair, mine) ne sont **pas** esquivables par plongeon.
- Verrous et modificateurs de vitesse centralisés par `MovementService` (un verrou par raison, modificateurs sans cumul
  multiplicatif pour une même clé, expiration automatique).

### 8.2 Frappe de proximité

`Combat.Punch` : portée 7 studs, cône de 50°, écart vertical ≤ 5, recharge 0,8 s ; KO court (1,2 s) et recul ; cible
choisie par le serveur (angle et distance) ; neutralise un Champignon Piégé à ≤ 4 studs.

### 8.3 Tir de balle guidé : verrouillage et évitement

- **Verrouillage** vérifié par le serveur au moment de la frappe : adversaire (jamais un allié ni soi) dans le cône de
  25° (+ 8° de tolérance serveur) autour de la visée, entre 4 et 90 studs de la balle, à moins de 40 studs d'altitude,
  en ligne de vue depuis la balle, ni invisible, ni protégé, ni KO, ni en plongeon, ni ayant terminé, ni spectateur ;
  cible = plus petit score `angle × 2 + distance / 90`. Sans cible valide, la frappe est refusée sans compter de coup.
- **En vol** : verrou vérifié toutes les 0,1 s et **rompu** si la ligne de vue est perdue, si la cible devient invisible,
  protégée ou KO, plonge ou termine ; virage limité à 120°/s ; guidage arrêté au premier contact avec le sol ou après
  2,5 s ; balle libérée en trajectoire balistique. La cible est annoncée à tous (attribut de balle `GuidedTargetUserId`).
- Recharge de 6 s par joueur ; tirer met fin à sa propre protection ; jamais avec une balle d'entraînement.
- **Impact d'une balle** sur un joueur : KO si la balle dépasse 38 studs/s (rayon de la balle + 1,4), une fois par balle
  et par victime chaque seconde ; la balle garde 65 % de sa vitesse ; un joueur en plongeon n'est pas touché.

### 8.4 KO, recul, frappes majeures et mineures

- KO = ragdoll temporaire, pas de points de vie ni d'élimination ; durée par défaut 2 s (bornes 0,5–6 s) ; relève
  légèrement au-dessus du sol avec exemption de plausibilité.
- **Frappe mineure** : KO court ou simple recul. **Frappe majeure** : KO + fort recul (vitesse de recul plafonnée à
  140 studs/s). Liste par objet : champ `major` de `Config/Items`.
- Bouclier brisé par une frappe majeure : KO **sans** fort recul (recul × 0,15 : pas de chute dans le vide).
  Personnage géant : immunisé contre les frappes mineures.

### 8.5 Protection et anti-KO répété

- **Protection** de 3 s après chaque apparition ou réapparition (aucun KO, gel, éblouissement ni ciblage) ; attaquer
  y met fin.
- **Anti-KO répété** (configurable) : même attaquant → même victime : 8 s avant un nouveau KO ; immunité de 1,5 s après
  chaque relève ; durées décroissantes (× 1, × 1, × 0,75 puis × 0,5) quand une victime enchaîne les KO dans une
  fenêtre de 20 s.

### 8.6 Réapparition et checkpoints

- Chute ou sortie de zone d'un personnage : réapparition au checkpoint le plus pertinent
  (`CourseService.GetCheckpointFor`), surveillance des chutes toutes les 0,25 s ; à l'accueil, retour au point
  d'apparition (`SpawnService`). La balle n'est pas déplacée par la réapparition du joueur.
- Toute réapparition retire les verrous et effets temporaires du personnage (visée, KO, gel, éblouissement) ; un
  verrou de phase posé par `MatchService` reste en place.

### 8.7 Plausibilité des déplacements

Échantillonnage serveur toutes les 0,5 s ; tolérance × 1,6 de la vitesse autorisée + 8 studs (montées comprises) ;
déplacement flagrant (> 4 × l'autorisé) corrigé aussitôt ; sinon 3 infractions en 10 s avant replacement. **Exemptions**
pour tout déplacement autorisé par le jeu : réapparition (2,5 s), téléportation serveur (1,5 s),
`MovementService.AllowDisplacement` (plongeon, recul, Tromblon, Bottes, Club Propulseur, kart), sols mobiles. Aucune
exclusion automatique d'un joueur (§15.5).

## 9. Les 17 objets

Données exécutées : `Config/Items.luau`, `Config/ItemBoxes.luau` ; spécification de conception :
`docs/REGISTRE_OBJETS.md` (fiches détaillées, à garder synchronisées) ; interactions : `docs/MATRICE_INTERACTIONS.md`.

### 9.1 Liste et noms originaux

| # | ID stable | Nom original | Mécanique de référence | Catégorie | Rareté | Comportement exigé (résumé) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `horn` | Corne Tonitruante | Klaxon | Perturbation | Commun | annonce 0,4 s puis, à 45 studs : frappe prématurée de qui charge, visée annulée 1,5 s pour qui vise, 35 % d'utilisation involontaire d'un objet sensible sélectionné |
| 2 | `espresso` | Expresso Turbo | Café | Mobilité | Commun | vitesse × 1,45 et saut × 1,15 pendant 8 s, sans cumul |
| 3 | `cork_pistol` | Pistolet à Bouchon | Pistolet de duel | Attaque | Commun | 2 tirs instantanés (portée 80, arrêt sur le décor), KO 1,8 s |
| 4 | `blunderbuss` | Tromblon Rebond | Fusil à recul | Attaque / mobilité | Rare | cône 30° sur 25 studs (KO à moins de 12), balles poussées, recul du tireur, propulsion verticale si tir vers le sol |
| 5 | `magnet_shield` | Bulle Magnétique | Bouclier électromagnétique | Défense | Rare | 12 s, absorbe 3 frappes mineures, dévie les projectiles ; frappe majeure = bulle détruite + KO sans fort recul |
| 6 | `caddie_kart` | Kart-Caddie | Voiturette | Véhicule | Rare | kart pilotable 8 places (60 studs/s), percussion, montée/descente fiables, sortie de secours, destruction ou remise à l'endroit contrôlées, 45 s |
| 7 | `shroom_mine` | Champignon Piégé | Mine | Piège | Commun | armement 1,5 s, avertissement 0,6 s, explosion, désamorçage par coup de poing, 2 actifs max, 60 s |
| 8 | `orbital_beam` | Rayon Satellite | Laser orbital | Attaque majeure | Épique | cercle de rayon 7 qui suit la cible 2 s puis se fige 1,2 s avant la frappe ; ciblage explicite (§9.5) |
| 9 | `confetti_rocket` | Lance-Fusées Confettis | Lance-roquettes | Attaque | Rare | verrouillage 0,6 s (cône 20°, 150 studs), fusée guidée 70 studs/s (90°/s), esquivable, explosion |
| 10 | `kangaroo_boots` | Bottes Kangourou | Bottes à ressorts | Mobilité | Commun | 3 bonds géants (saut × 2,6) en 15 s, contrôle aérien normal |
| 11 | `rocket_club` | Club Propulseur | Club à fusée | Attaque / mobilité | Rare | coup suivant × 1,6, sinon frappe majeure de mêlée, sinon propulsion de l'utilisateur (80 studs/s, 0,4 s) |
| 12 | `frost_bomb` | Boule Givrante | Bombe de glace | Perturbation | Rare | lancer en cloche ; gel 3 s (glissade) des adversaires, balles et karts ; plateforme de glace 8 s sur l'eau |
| 13 | `ninja_smoke` | Nuage Ninja | Fumigène | Défense / perturbation | Commun | fumée 6 s, invisibilité 5 s, rupture et blocage des verrouillages ; cesse si l'utilisateur agit |
| 14 | `paparazzi_flash` | Flash Paparazzi | Appareil à flash | Perturbation | Commun | adversaires tournés vers le flash (cône 50°, 30 studs) éblouis 2,5 s : visée impossible, vitesse × 0,6 ; mode sans flash à pénalité identique |
| 15 | `grumpy_cloud` | Nuage Grognon | Orage | Perturbation de zone | Épique | nuage 8 s dérivant vers l'adversaire le plus proche ; éclair annoncé 1 s (anneau) toutes les 2 s, rayon 5 |
| 16 | `rail_slinger` | Rail-Fronde | Railgun | Attaque majeure | Épique | charge 1 s avec viseur visible de tous ; rayon de 140 studs touchant jusqu'à 3 adversaires alignés (§9.5) |
| 17 | `mega_burger` | Méga Burger | Burger géant | Transformation | Épique | géant 8 s (× 2,2), percussion et projection des balles et adversaires, décor `Breakable` brisé, géométrie jouable conservée |

Chaque objet **doit** avoir un comportement réel et distinct, conforme à sa fiche de `docs/REGISTRE_OBJETS.md`, avec
ses télégraphies visuelles et sonores (effets du registre client, sons de `Config/Sounds.luau`).

### 9.2 Données exigées par objet

| Donnée exigée par la demande | Champ de `Config/Items` |
| --- | --- |
| ID stable | `id` (+ `order`) |
| Rareté | `rarity` |
| Chances d'apparition | `weightLeader` / `weightLast` (+ `mobilityBox`) |
| Portée, durée, charges | `range`, `duration`, `charges` |
| Délai | `cooldown`, `windup` (+ `GlobalUseCooldown` = 0,25 s entre deux objets) |
| Catégories de cible | `targets` (`Self`, `Enemy`, `Ball`, `Area`, `Vehicle`, `Water`) |
| Contre-jeu | `counterKey` (texte affiché), `dodgeable`, `shield` (`Absorb`, `Deflect`, `Breaks`, `Ignored`) |
| Effets sur les alliés | `allyEffect` |
| Nettoyage | `cleanup` |
| Compléments | `major`, `hornSensitive`, `holdToUse`, `params`, `nameKey`, `descKey`, `glyph`, `color` |

### 9.3 Inventaire et commandes

- Inventaire **limité** : capacité initiale **3 cases** (`Items.InventoryCapacity`, configurable de 1 à 4), répliquée par
  les attributs `Inventory`, `InventoryCapacity`, `SelectedSlot` ; une boîte n'est pas ramassée si l'inventaire est
  plein (elle reste disponible) ; inventaire **vidé** à chaque chargement de trou.
- Sélection : clavier 1/2/3, manette L1/R1 (cycle), tactile en touchant la case (`Items.Select`). Utilisation : clavier E,
  manette R2, bouton tactile « Utiliser » (`Items.Use(roundId, case, visée, cible suggérée)`) ; objets à maintenir
  (fusée, rail) : `Items.UseStart` / `Items.UseCancel`.
- Le serveur valide phase, `RoundId`, participant actif, état (KO, gel, éblouissement, trou terminé), présence de l'objet
  dans la case, délais, cible et ligne de vue ; la cible suggérée par le client n'est qu'une indication.

### 9.4 Boîtes et tirage avec rattrapage

- **Boîtes aléatoires** (tous objets) et **boîtes de mobilité** (Expresso, Bottes Kangourou, Kart-Caddie, Club
  Propulseur), placées par les données du trou (`itemBoxes`, `mobilityBoxes`) ; ramassage par test de proximité serveur
  (4 studs, toutes les 0,1 s) ; réapparition après 16 / 10 / 6 s selon `itemFrequency` ; désactivées si `itemsEnabled`
  est faux.
- **Tirage serveur** (`Logic/ItemOdds`, `Random` dédié) : position normalisée `p = (rang − 1) / (n − 1)` d'après
  `MatchService.GetRacePosition` (distance restante au trou ; 0,5 si joueur seul) ; poids de chaque objet
  `lerp(weightLeader, weightLast, p × s + 0,5 × (1 − s))` avec `s = ItemBoxes.CatchUpStrength` (0 = aucun rattrapage,
  1 = plein effet) ; une boîte de mobilité ne tire que des objets de mobilité ; liste d'exclusion possible. Le client ne
  choisit jamais l'objet.

### 9.5 Règles explicites exigées

- **Ciblage du Rayon Satellite** : l'adversaire le mieux placé dans la course (distance restante au trou la plus faible),
  hors alliés, joueurs ayant terminé, protégés et invisibles ; si l'utilisateur est lui-même premier, l'adversaire
  suivant ; sans cible valide, l'objet n'est pas consommé. Contre-jeu : sortir du cercle pendant la phase figée.
- **Multi-cibles du Rail-Fronde** : le rayon s'arrête sur le décor et traverse les joueurs ; au plus 3 adversaires
  touchés, triés par distance le long du rayon, recul 100 %, 70 % puis 50 %, chaque touche étant une frappe majeure ;
  le premier adversaire protégé par une bulle arrête le rayon ; les alliés sont traversés sans effet.
- **Bouclier** : absorbe ou dévie les frappes mineures (3 charges) ; toute frappe majeure (Rayon Satellite, Rail-Fronde,
  contact du Méga Burger, mine au contact, kart à plus de 40 studs/s) détruit la bulle et provoque un KO sans fort recul.
- **Flash accessible** : le mode sans flash remplace l'éclair blanc par une vignette sombre et une icône « Ébloui »,
  avec une pénalité de jeu **identique**.
- **Verrouillages** : fusée et tir guidé rompus par le plongeon et par l'invisibilité ; aucun verrouillage d'un
  joueur invisible.

### 9.6 Matrice d'interactions

Les huit paires exigées sont définies dans `docs/MATRICE_INTERACTIONS.md`, implémentées côté serveur et prouvées une à une :

| Paire | Règle exigée |
| --- | --- |
| Gel / voiturette | conducteur gelé : ni direction ni accélération, le kart glisse 3 s puis freine ; kart touché gelé 3 s ; passagers gelés restent assis |
| Bouclier / laser | bulle détruite + KO sans fort recul |
| Bouclier / railgun | le premier adversaire protégé arrête le rayon ; les cibles derrière lui sont épargnées |
| Invisibilité / roquette | aucun verrouillage d'un joueur invisible ; verrou existant rompu, la fusée file droit |
| Géant / obstacles | brise le décor `Breakable` (rétabli au trou suivant), jamais la géométrie jouable qui le bloque normalement |
| Mine / allié | les alliés (et le poseur) ne déclenchent jamais la mine ; l'explosion ne touche que les adversaires du poseur |
| Klaxon / objet | 35 % d'utilisation involontaire d'un objet sensible sélectionné ; frappe prématurée de qui charge |
| Gel / réapparition | toute réapparition retire le gel ; la protection empêche un nouveau gel ; une balle replacée est dégelée |

### 9.7 Nettoyage et durée de vie

Tout effet, piège, projectile, nuage, plateforme, véhicule et changement d'échelle appartient à la `Trove` de manche
**et** à celle du joueur concerné. Aucun état temporaire ne survit à la fin d'une manche (`ItemService.ClearRound`), à
une déconnexion (`ItemService.ClearPlayer`, `OnPlayerRemoving`), à une réapparition (effets sur soi) ni au retour à
l'accueil. Les tests comptent instances et connexions entre manches (§17.6).

### 9.8 Contrat d'implémentation

Un module `server/Items/<Id>.luau` par objet (contrat `docs/ARCHITECTURE.md` §10 : `Id`, `Use(ctx, player, payload)`,
`OnRoundEnd`, `OnPlayerRemoving`), piloté par `ItemService` (inventaires, boîtes, effets, tirage).

## 10. Les 81 trous et la création des niveaux

### 10.1 Répartition

| Biome | Préfixe | Trous | Par total | Éléments exigés |
| --- | --- | --- | --- | --- |
| Côte | `COT` | 18 | 71 | îles, plages, ponts, falaises, passages au-dessus de l'eau |
| Forêt | `FOR` | 18 | 71 | arbres, clairières, reliefs, plateformes |
| Désert | `DES` | 18 | 71 | dunes, canyons, arches, oasis, sable pénalisant |
| Neige | `NEI` | 18 | 71 | glace, pentes, précipices, passages glissants |
| Ville | `VIL` | 9 | 36 | rues, parcs, canaux, ponts, hauteurs, circulation dangereuse |
| **Total** | | **81** | **320** | |

S'y ajoutent, hors des 81, les trous d'entraînement `ENT-01` (Driving Range) et `ENT-02` (tutoriel). Noms, pars,
difficultés et signatures : `docs/PLAN_PARCOURS.md`.

### 10.2 Données de chaque trou

Format `Types.HoleDef` (guide d'écriture à produire : `docs/FORMAT_TROUS.md`), un fichier par biome dans
`src/shared/Data/Holes/` agrégé par `Data/Holes/init.luau` (`Holes.all()`, `Holes.get(id)`).

| Exigence de la demande | Champ |
| --- | --- |
| ID, nom, biome | `id` (`PPP-NN`), `name`, `biome` |
| Par, difficulté | `par` (2..6), `difficulty` (1..5) |
| Départs équitables | `tee` + `CourseService.GetStartPlacements(count)` (même distance au trou, aucun départ avantagé) |
| Position du trou | `cup` (+ `green`) |
| Limites | `bounds` (+ `killY` calculé) |
| Checkpoints, zones de récupération | `checkpoints` (générés le long de `path` par défaut), `hazards` |
| Boîtes d'objets | `itemBoxes`, `mobilityBoxes` |
| Obstacles et décor | `obstacles`, `props`, `decorDensity` |
| Durée cible | `targetTime` |
| Chemins de déplacement praticables | `path` (nœuds avec largeur, surface et nature : sol, pont, trou, glace, tunnel) |
| Raccourcis risqués | `shortcuts` (description + objet requis) |
| Particularité | `feature` (affichée à l'intro et au catalogue) |
| Reproductibilité | `seed` (décor procédural déterministe), `windBias` facultatif |

### 10.3 Distinction des 81 expériences

Chaque trou a une **signature** propre (forme du tracé, obstacle principal, terrain, rythme). Sont interdits : les
copies recolorées, le même tracé avec une autre graine et toute sortie de générateur jamais inspectée. Contrôle :
comparaison automatique des signatures (longueur, virages, dénivelé, types d'obstacles) **et** inspection visuelle de
chaque trou (aperçu en mode Édition et capture).

### 10.4 Praticabilité et raccourcis

- Le **chemin principal** est praticable à pied **sans objet** : pentes ≤ 30°, trous ≤ 6 studs ou franchis par un pont ;
  le trou est réalisable avec des frappes normales sous le plafond de coups.
- Les **raccourcis** risqués peuvent exiger un objet (Bottes Kangourou, Kart-Caddie, Boule Givrante sur l'eau, Club
  Propulseur, Tromblon) et sont documentés dans `shortcuts`.
- Longueurs indicatives : par 3 de 120 à 220 studs, par 4 de 230 à 380, par 5 de 380 à 560. Courbe de difficulté par
  biome : trous 1–6 accessibles, 7–12 intermédiaires, 13–18 exigeants, le dernier est une finale spectaculaire.

### 10.5 Outils de construction et d'inspection

- `server/Course/` (constructeur de trou, accueil, obstacles, décor, biomes) construit **toute** la géométrie par code
  à partir des données ; valeurs dans `Config/Course.luau`.
- `Logic/HoleValidator.luau` (pur, testable) vérifie structure, bornes, chemin, pentes, trous, checkpoints, boîtes,
  trou sur le green et équité des départs.
- `CourseService.BuildPreview(holeId, origin)` construit un trou en **mode Édition** dans `Workspace.CoursePreviews`
  pour l'inspection (jamais sauvegardé dans la place) ; les balles de simulation (`CreateSimBall` / `StepSim`)
  vérifient la faisabilité des frappes.
- Même graine + mêmes données = même trou (génération stable, inspectable et reproductible).

### 10.6 Chargement, nettoyage et playlists

- Un seul trou de partie chargé à la fois (`Workspace.Course`, loin de l'accueil) ; l'accueil (`Workspace.Lobby`)
  reste permanent ; `CourseService.UnloadHole` détruit tout le contenu du trou précédent (Trove de manche) ; budget
  indicatif de 1 500 pièces par trou.
- Playlists (`Logic/Playlist`) : `Quick3`, `Front9`, `Full18`, `Biome:<Biome>`, `Mixed` (mélange de biomes filtré par
  `biomes`), `Custom` (1 à 18 identifiants, `Lobby.SetCustomPlaylist`) ; ordre aléatoire reproductible par graine
  (`shuffle`) ; identifiants inconnus écartés avec repli documenté.

### 10.7 Validation et catalogue

États de validation d'un trou, du moins au plus avancé : **Planifié** (dans le plan) → **Données écrites** →
**Structure validée** (`HoleValidator`) → **Parcours simulé** → **Inspecté** (mode Édition, capture) → **Joué** (Play,
playtest consigné). `docs/CATALOGUE_TROUS.md` liste les 81 trous avec leur particularité, leur état, la date et la
preuve ; il est produit à partir des données et des validations **réellement exécutées**. Un trou non vérifié conserve
son état explicite.

## 11. Direction artistique, avatar et cosmétiques

### 11.1 Direction artistique

- Univers cartoon **low-poly** cohérent : couleurs lisibles, palette par biome, silhouettes expressives, objets
  reconnaissables (pictogramme et couleur propres à chaque objet), effets satisfaisants, interface soignée
  (`UI/Theme.luau`, composants communs).
- De **vrais décors et accessoires** construits par code avec des composants Roblox ; un placeholder temporaire ne vaut
  pas finition.

### 11.2 Avatar

- Avatar R15 aux proportions identiques pour tous (`LoadCharacterAppearance = false`, `AvatarJointUpgrade = Disabled`,
  `CharacterAutoLoads = false` : `SpawnService` contrôle les apparitions), compatible avec les animations procédurales
  et les proportions de collision.
- **Aperçu 3D** de la tenue (`ViewportFrame`) dans la personnalisation et la boutique ; **variantes de couleurs**
  (`variants`, `Shop.SetVariant`) ; **3 ensembles** sauvegardables (`Shop.SaveLoadout` / `Shop.UseLoadout`).

### 11.3 Catalogue minimal

| Emplacement (`Cosmetics.Slot`) | Contenu | Minimum exigé |
| --- | --- | --- |
| `Head` | têtes, chapeaux, masques | 25 |
| `Face` | coiffures, visages, lunettes, accessoires du visage | 15 |
| `Outfit` | tenues | 20 |
| `Shoes` | paires de chaussures | 10 |
| `Club` | apparences de clubs | 15 |
| `Ball` | apparences de balles | 10 |
| `HoleEffect` | effets lorsque la balle entre dans le trou | 5 |
| **Total** | cosmétiques réellement équipables | **100** |
| `Emote` | danses ou émotes avec une animation réelle (procédurale) | 8 |

Les objets gratuits par défaut et les simples recolorations (variantes) ne comptent pas. Chaque cosmétique a un nom
traduit (fr/en), une rareté, un prix en pièces, une condition de déblocage (`Default`, `Price`, `Achievement`, `Wins`,
`HolesInOne`, `MatchesPlayed`) et un modèle construit par code (`shared/Cosmetics/Catalog/*.luau`).

### 11.4 Équité

- Les cosmétiques changent **l'apparence uniquement** : toute pièce construite est sans masse, sans collision, sans
  requête ni contact, sans script (`Cosmetics/Build.luau`) ; même longueur de club pour tous les skins (même portée) ;
  la balle serveur reste neutre.
- Les animations et émotes ne contournent **aucun** délai : délais de frappe, de combat et d'objet sont mesurés par le
  serveur indépendamment des animations ; une action de jeu interrompt l'émote.

### 11.5 Boutique et équipement

- Boutique avec aperçu, filtres (emplacement, rareté, possédé / verrouillé), statut possédé / verrouillé, prix en
  pièces, condition de déblocage affichée et boutons **Acheter** / **Équiper** fonctionnels (`Shop.Buy`, `Shop.Equip`).
- L'achat est une transaction serveur idempotente (§12.5) ; le succès n'est affiché qu'après la confirmation
  `Shop.Result`.
- La sélection est **visible par les autres joueurs** (apparence appliquée par le serveur au personnage) et
  **conservée après reconnexion** (profil sauvegardé).
- Prix de référence par rareté (`Config/Economy.PriceByRarity`) : Commun 200, Rare 500, Épique 1 000, Légendaire 2 000.

### 11.6 Assets et provenance

Aucun AssetId fabriqué. Contenu permis : contenu intégré `rbxasset://`, audio sous licence des comptes
`ProSoundEffects` et `APMOfficial` vérifié et consigné dans `docs/MANIFESTE_ASSETS.md` (registre `Config/Sounds.luau`),
géométrie, interface et animations générées par code. Tout import futur et les permissions nécessaires sont consignés
dans le manifeste ; quand un upload est indisponible, une solution générée localement est fournie et sa limite indiquée.

## 12. Progression et sauvegarde

### 12.1 Monnaie et récompenses

- Monnaie du jeu (pièces) gagnée **uniquement en jouant** : solde initial 250, borne de sécurité 10 000 000.
- Récompenses de fin de partie calculées par `Logic/Rewards.luau` (valeurs `Config/Economy.luau`) et versées par
  `RewardService` (opération idempotente `MatchId..":"..UserId`) : participation 40 (partie complète éligible),
  8 par trou terminé, classement 60 / 40 / 25 / 10 (Chacun pour soi), équipes 50 / 15 / 30 (victoire / défaite / nul),
  solo 30 + 5 par trou au par ou mieux, performance (trou en un 50, eagle 25, birdie 10) plafonnée à 100 ; total
  plafonné à 400 par partie.
- **Anti-farm** : rien en Entraînement (sauf le tutoriel, une fois) ; une partie ne rapporte que si le joueur a été
  actif (au moins une frappe acceptée) sur au moins 3 trous, ou sur tous si la partie en compte moins ; partie
  interrompue = aucune récompense ; montant jamais négatif, jamais décidé par le client.

### 12.2 Défis

Au moins **30 défis variés** ; 38 sont définis dans `Config/Achievements.luau` : Golf 7, Précision 4, Exploration 7,
Objets 5, Survie 5, Équipe 3, Véhicules 4, Victoires 3. Trois natures : compteur cumulé (`Stat`), ensemble d'éléments
distincts (`Set`), événement (`Event`). `AchievementService` écoute les signaux des autres services (trou réussi, KO,
objets, véhicules…) et verse chaque récompense **une seule fois** (`opId = "ach:" .. id`). Les identifiants référencés
par les cosmétiques ne changent jamais.

### 12.3 Succès internes et badges

Les succès fonctionnent sans BadgeId Roblox. Le champ `badgeId` permet de raccorder plus tard un vrai badge de
plateforme (après publication, identifiant réel, attribution serveur `AwardBadgeAsync` en `pcall`) ; aucun identifiant
n'est inventé.

### 12.4 Données sauvegardées

Monnaie, cosmétiques possédés, équipements, variantes, ensembles, succès obtenus, statistiques utiles (compteurs des
défis, ensembles `sets`, records solo `bestSolo`, parties jouées et gagnées) et préférences (volumes, sensibilité,
secousses, vibrations, effets réduits, mode sans flash, langue, qualité). Les statistiques acceptent des clés numériques
arbitraires et le champ `sets` (point d'intégration noté dans `docs/ETAT_REPRISE.md`).

### 12.5 Transactions serveur

Achats et récompenses sont décidés **côté serveur** et appliqués par `PlayerDataService.Transact(player, opId, fn)` :
une opération rejouée (double clic, requête répétée, reconnexion) ne s'applique qu'une fois ; aucune monnaie, aucun
objet possédé et aucune récompense ne transite du client vers le serveur.

### 12.6 Robustesse de la persistance

- Schéma **versionné** avec migrations testées (jamais de perte de champ inconnu) et assainissement des valeurs
  (jamais de NaN ni d'infini, chaînes UTF-8).
- **Accès concurrents** : verrou de session (`UpdateAsync` + identifiant de verrou en métadonnées) ; un second serveur
  n'écrase pas un profil verrouillé.
- **Reprises bornées** (nombre maximal, attente croissante avec gigue) et respect des **limites de requêtes**
  (budget DataStore consulté) ; sauvegarde périodique décalée ; **sauvegarde de fermeture au mieux** (`PlayerRemoving`
  et `BindToClose` en parallèle, moins de 30 s).

### 12.7 Échec de chargement

Si le chargement échoue : statut `DataStatus = "Failed"`, **aucune écriture** qui écraserait le profil existant par un
profil vide, état honnête affiché au joueur et transactions dangereuses (achats, récompenses) bloquées jusqu'à un
chargement réussi.

### 12.8 Environnements de données

Les données de développement et de test sont séparées des données réelles : Studio n'écrit jamais dans le stockage de
production (adaptateur mémoire par défaut ; essais DataStore réels sur une expérience de test séparée ou un stockage
suffixé). L'adaptateur mémoire est **identifié comme non persistant** (`GameState.PersistentData = false`,
`DataStatus = "Memory"`, bandeau à l'écran) ; il ne prouve pas que DataStore fonctionne.

### 12.9 Monétisation

Aucune mécanique pay-to-win, aucune boutique Robux, aucun produit développeur ni passe dans cette livraison.

## 13. Salon, interface, accessibilité et communication

### 13.1 Accueil jouable

L'accueil (`Workspace.Lobby`, construit par code) est un espace jouable où l'on peut se déplacer, frapper des balles
d'entraînement, accéder au Driving Range et au tutoriel, à la boutique, à la personnalisation, aux postes d'essai des
objets, à la sélection du mode et aux parties (préparation du salon).

### 13.2 Parties publiques et privées

- **Parties publiques** : chaque serveur public de l'expérience héberge un salon et ses parties (matchmaking Roblox).
- **Parties privées entre amis** : serveur réservé via `TeleportOptions.ReservedServerId` (GUID généré par le serveur)
  et `TeleportService:TeleportAsync` (au plus 50 joueurs, amis présents inclus), avec reprises et gestion de
  `TeleportInitFailed` (`Lobby.CreatePrivate`, `Config/Match.Private`) ; API dépréciées interdites.
- Ces fonctions exigent une expérience publiée et configurée : elles sont documentées et testées **séparément**
  (service Roblox réel) ; en Studio, elles sont désactivées par défaut (`Private.AllowInStudio = false`).

### 13.3 Réglages de l'hôte

L'hôte règle la partie depuis l'accueil ou la préparation, jamais pendant un trou : `MatchService` fige une copie des
réglages au lancement. Chaque réglage est validé clé par clé côté serveur (`Config/Match.SettingRules`) :

| Réglage | Valeurs | Défaut |
| --- | --- | --- |
| `mode` | `FreeForAll`, `Teams`, `Solo`, `Training` | `FreeForAll` |
| `playlist` | `Quick3`, `Front9`, `Full18`, `Biome:<Biome>`, `Mixed`, `Custom` | `Quick3` |
| `holeCount` / `customHoleIds` | 1 à 18 / liste de 1 à 18 identifiants | 3 / — |
| `biomes`, `shuffle` | sous-ensemble des biomes ; ordre aléatoire | tous ; non |
| `timeScale` (durée) | 0,5 à 2 | 1 |
| `wind` | `Off`, `Light`, `Strong`, `Random` | `Light` |
| `gameSpeed` (vitesse) | 0,75 à 1,5 | 1 |
| `itemsEnabled`, `itemFrequency` (objets) | oui / non ; `Low`, `Normal`, `High` | oui ; `Normal` |
| `ballCollisions` (interactions entre balles) | oui / non | non |
| `friendlyFire` | oui / non (ignoré en Équipes) | non |
| `lateJoin`, `experimental16` | oui / non | oui ; non |

Équipes : choix, équilibrage par l'hôte (§5.3). Transfert automatique des droits d'hôte en cas de départ (§4.4).

### 13.4 Interface de jeu

L'interface **doit** comprendre : menus (accueil, préparation, réglages, boutique, personnalisation, options), visée et
jauge de puissance, angle et type de frappe, aperçu de trajectoire, vent, par, compteur de coups, chronomètre
(échéance et prolongation), inventaire, effets actifs avec temps restant, classement en direct, annonces de KO,
résultats du trou, podium et état des données (bandeau « mémoire » ou « échec »). Les boutons réalisent les actions
annoncées ; aucun faux écran de succès : un succès n'est affiché qu'après confirmation du serveur. Aucun texte en dur.

### 13.5 Accessibilité et réglages

- **Manette** : navigation de tous les menus au focus (`GuiService.SelectedObject`, `NextSelection*`), sans souris.
- **Tactile** : commandes confortables (≥ 44 px logiques, emplacements fixes, masquées dans les menus plein écran),
  aucune action exigeant un clavier.
- **Caméra** non gênante : zoom borné (4 à 90 studs), pas d'obstruction pendant la visée, secousses réglables.
- **Lisibilité** : textes lisibles (taille minimale, contraste suffisant, objectif 4,5:1 pour le texte courant) ;
  indicateurs d'équipe **autres que la couleur** (nom, pictogramme ou motif).
- **Réglages** (`SettingsController`, synchronisés au profil) : volumes (général, effets, musique, interface),
  sensibilité de la caméra et de la visée, vibrations (si l'appareil les prend en charge) et secousses de caméra,
  réduction des effets, **mode sans flash**, langue, qualité graphique.

### 13.6 Communication

Chat textuel natif (`TextChatService`, filtré par Roblox) et chat vocal natif seulement lorsque la plateforme et le
compte l'autorisent ; le jeu reste **entièrement jouable sans vocal**. Aucun système de communication parallèle ;
tout texte saisi par un joueur et montré à d'autres serait filtré côté serveur (`TextService:FilterStringAsync`), rien
n'étant affiché en cas d'échec. Compatibilité avec le chat intégré à la plateforme (obligatoire à partir de mai 2027).

## 14. Architecture technique

Le contrat détaillé est `docs/ARCHITECTURE.md` ; ce chapitre en fixe les exigences.

### 14.1 Flux de travail et source de vérité

- **Source de vérité : le dépôt** (`src/`, `default.project.json`, `docs/`). Studio n'est qu'une cible.
- Construction reproductible : `scripts/install-tools.ps1` (Rojo 7.7.1, empreinte SHA-256 vérifiée) puis
  `scripts/build.ps1` → place `.rbxlx` dans `build/`. Toute modification faite à la main dans une place construite est
  perdue au build suivant : elle est d'abord reportée dans `src/`.
- Aucune place de l'utilisateur n'est écrasée ; la publication se fait plus tard, à la demande (§1.3, §20).

### 14.2 Organisation du code

- Luau typé (`--!strict` en tête de chaque fichier), commentaires en français, un module = une responsabilité, aucun
  `_G` ni `shared`, aucun cycle de `require`, aucune dépendance externe inutile.
- Séparation serveur / client / partagé (`ServerScriptService.Server`, `StarterPlayerScripts.Client`,
  `ReplicatedStorage.Shared`, tests dans `ServerStorage.Tests`) ; un seul Script serveur et un seul LocalScript
  d'amorçage : aucun script monolithique.
- Paramètres de jeu séparés du code (`shared/Config/*`), logique pure testable (`shared/Logic/*`), réseau centralisé
  (`shared/Net`), textes centralisés (`shared/Locale`), utilitaires communs (`shared/Util`).

### 14.3 Services et contrôleurs

| Priorité | Service serveur | Rôle |
| --- | --- | --- |
| 0 | `CollisionService` | groupes de collision |
| 5 | `PlayerDataService` | profils persistants |
| 8 | `NetworkValidation` | statistiques et garde-fous réseau |
| 10 | `MovementService` | verrous, modificateurs, plausibilité |
| 15 | `CombatService` | KO, recul, protection, frappe de proximité, plongeon |
| 20 | `BallService` | balles, tirs, physique, trou, pénalités |
| 25 | `CourseService` | trous, accueil, éclairage, checkpoints |
| 30 | `VehicleService` | voiturettes |
| 35 | `ItemService` | inventaires, boîtes, effets, objets |
| 40 | `CosmeticService` | boutique, équipements, apparence |
| 45 | `AchievementService` | défis et succès internes |
| 50 | `RewardService` | récompenses de fin de partie |
| 55 | `SpawnService` | apparitions |
| 60 | `LobbyService` | hôte, réglages, équipes, parties privées |
| 70 | `MatchService` | machine à états, modes, score, résultats |
| 90 | `DevService` | outils de test, Studio uniquement |

Contrôleurs client : `InputController`, `SettingsController`, `UIController`, `CameraController`, `GolfAimController`,
`HUDController`, `MenuController`, `SpectatorController`, `InventoryController`, `ShopController`,
`CustomizeController`, `AnimationController`, `VehicleController`, `TutorialController`, `NotificationController`,
`EffectsController`.

### 14.4 Cycle de vie et nettoyage

- Démarrage en deux phases (`Init` synchrone par priorité puis `Start` dans un thread par module) ; un module en
  échec est isolé et signalé (attributs `Booted` / `BootFailures`) ; aucun effet de bord au `require`.
- `Trove` de **manche** (géométrie, effets, pièges, projectiles, boîtes, voiturettes, états temporaires), par
  **joueur** (nettoyée à `PlayerRemoving`), par **personnage** (à `CharacterRemoving`) et par **effet**.
  En fin de trou : `ItemService.ClearRound()`, `VehicleService.ClearAll()`, `BallService.RemoveAll()`, puis la Trove de
  manche. Connexions, tâches, contraintes, projectiles et effets sont toujours nettoyés après usage.
- Code compatible avec les signaux différés (`Workspace.SignalBehavior = Deferred`), bibliothèque `task` uniquement,
  aucune boucle sans attente.

### 14.5 Réseau

Seul `shared/Net` crée des remotes, à partir de `Net/Remotes/<Domaine>.luau` (noms `Domaine.Action`) ; chaque remote
client → serveur déclare ses types d'arguments (`args`) et son débit (`rate`, `burst`) ; aucune `RemoteFunction`
serveur → client ; l'état continu passe par des attributs, les événements ponctuels par des remotes `ToClient`, les
effets fréquents par des remotes non fiables.

### 14.6 Configuration

Aucun nombre d'équilibrage en dur : il vit dans `shared/Config/<Domaine>.luau`, lisible par le client (aucun secret) ;
le serveur revalide tout.

## 15. Sécurité et autorité serveur

### 15.1 Principe

Le serveur décide des frappes acceptées, des KO, des entrées dans le trou, des scores, des tirages, des achats et des
récompenses. Le client transmet des **intentions** de jeu, jamais une récompense ou une conséquence à appliquer.

### 15.2 Contrôles obligatoires sur chaque intention

1. Types et nombre d'arguments (spécification `args`, surplus rejeté) ; valeurs **finies** (ni NaN ni infini),
   vecteurs bornés, chaînes de longueur bornée (`Util/Validate`).
2. Phase de partie et `RoundId` courant.
3. Statut du joueur : participant actif, non KO, non gelé, non ébloui, n'ayant pas terminé, en véhicule ou non.
4. Bornes numériques (loft, puissance, case d'inventaire), distance (balle, cible, boîte), ligne de vue.
5. Équipement et possession (objet présent dans la case, cosmétique possédé), permissions (hôte uniquement).
6. Délais propres à l'action (frappe, combat, objet, réinitialisation, demandes de salon).

### 15.3 Débit, doublons et manches périmées

Débit limité par joueur et par remote (seau à jetons `rate` / `burst` de `shared/Net`) ; doublons rejetés (une frappe par
jauge, opérations idempotentes) ; toute requête d'une manche précédente ignorée.

### 15.4 Déplacements

Contrôle de plausibilité serveur (§8.7) sans punir les propulsions, téléportations ou réapparitions autorisées par le jeu.

### 15.5 Suivi des rejets

Rejets techniques comptés par `Net.getStats()` ; rejets métier signalés par `NetworkValidation.Report(player, raison)`.
Jamais d'exclusion automatique d'un joueur sans preuve ; une requête invalide attendue n'est pas une erreur de journal.

### 15.6 Outils de test

`DevService` et son pont `ServerStorage.DevBridge` (jamais répliqué, aucun remote) ne fonctionnent que dans Studio.

## 16. Performances

### 16.1 Objectifs

- **60 FPS** sur le PC de référence documenté (AMD Ryzen 7 7435HS, NVIDIA RTX 4060 Laptop, 23,7 Go de RAM, Windows 11).
- **30 FPS** sur un appareil mobile de référence.
- Ces objectifs ne sont **jamais annoncés comme atteints sans mesure réelle** ; un émulateur d'écran ne prouve pas les
  performances d'un téléphone (§20).

### 16.2 Budgets

Un seul trou chargé à la fois ; environ 1 500 pièces par trou au plus ; projectiles sans pièce physique ; nombre de
balles, karts, pièges, nuages et particules simultanés plafonné ; calculs coûteux à fréquence réduite (contrôles de
dangers toutes les 0,1 s, plausibilité toutes les 0,5 s) ; messages réseau limités (attributs pour l'état continu,
événements non fiables pour les effets fréquents, débits plafonnés).

### 16.3 Qualité graphique

Au moins trois niveaux (`Low`, `Medium`, `High`, `EffectsController.GetQuality`) et le réglage « effets réduits » qui
diminuent particules, décor secondaire et effets.

### 16.4 Mesures

Temps de frame client et serveur, mémoire, nombre d'instances et trafic réseau sont mesurés avec le matériel
disponible (pont `DevBridge` « perf », statistiques et MicroProfiler de Studio) pendant une partie complète, puis
consignés avec la machine, la qualité, le nombre de joueurs et la durée de mesure.

## 17. Stratégie de validation et catégories de preuve

### 17.1 Catégories de preuve

Aucune catégorie ne remplace automatiquement une autre. Les codes sont ceux de la matrice de couverture.

| Code | Catégorie | Ce que c'est | Moyen dans cet environnement | Ce qu'elle ne prouve pas |
| --- | --- | --- | --- | --- |
| AS | Analyse statique | lecture et recherche dans le code et les données, construction Rojo, contrôles `--!strict`, recherche d'AssetId | dépôt, `scripts/build.ps1` | aucun comportement à l'exécution |
| TU | Test unitaire | specs du `Runner` sur des modules purs (Config, Logic, Util, Data) | Studio en mode Édition (outil MCP `execute_luau`) | intégration au moteur, réseau |
| SIM | Simulation | exécution scriptée sans joueur réel : balles de simulation, latence simulée, scénarios serveur | Studio (Network Simulator, `NetworkSettings`) | ressenti réel, appareils réels |
| TM | Test moteur Studio | Play solo (un client + serveur) ou mode Édition avec moteur (aperçus, chargement d'assets) | MCP : `start_stop_play`, console, captures, entrées simulées | interactions entre clients |
| MC | Test multi-clients | un serveur et 2 à 8 clients dans Studio | « Serveur et clients » de Studio ; `StudioTestService:ExecuteMultiplayerTestAsync` (contexte plugin, à essayer) | 16 joueurs, services réels |
| AP | Appareil physique | exécution sur téléphone, tablette ou manette réels | aucun appareil mobile disponible | — |
| SR | Service Roblox réel | place publiée : DataStore, serveurs réservés, chat et vocal, badges, serveurs de production | nécessite publication et accès API (action de l'utilisateur) | — |

### 17.2 Tests unitaires

`require(game.ServerStorage.Tests.Runner).run(filtre?)` exécute `src/tests/Specs/*.spec.luau`. Specs existantes :
`Util`, `Locale`, `NetDefinitions`, `Items`, `Progression`, `BallMath`, `Cosmetics`. Specs exigées en plus : `Scoring`,
`MatchStateMachine`, `Playlist`, `HoleValidator` (dont les données des 81 trous), schéma et migrations de sauvegarde,
transactions idempotentes avec erreurs simulées, animations (validation du registre), règles pures des objets dès
qu'elles sont extraites (ciblage du Rayon Satellite, tri du Rail-Fronde, réaction du bouclier).

### 17.3 Playtests Studio exigés

| Scénario (demande §12) | Catégorie |
| --- | --- |
| Session solo, puis deux clients, puis jusqu'à huit clients | TM, MC |
| Partie entière sur plusieurs trous, résultats, récompense unique, retour à l'accueil | TM, MC |
| Départs simultanés, arrivée tardive, déconnexion, réapparition, changement d'hôte, fin du délai | MC |
| Frappes proches et lointaines, pentes, sable, glace, vent, collisions rapides, entrée dans le trou | TM (+ SIM) |
| Tous les objets et les interactions importantes de leur matrice | TM, MC |
| Achats, équipements, rechargement des données, tentatives de double récompense | TM, SR |
| Erreurs de sauvegarde simulées ; requêtes client invalides, répétées ou trop rapides | TU, TM |
| Chaque trou : validation structurelle et parcours réalisable (§17.5) | TU, SIM, TM |
| Écrans PC et mobile, navigation manette, effets réduits, lisibilité en équipe | TM (+ AP) |
| Plusieurs manches successives : fuites, objets résiduels, dégradation progressive | TM |

### 17.4 Seize joueurs

Studio limite les tests à 8 clients (« Serveur et clients » comme `ExecuteMultiplayerTestAsync`). Une validation à
16 clients ne peut donc **pas** être obtenue dans Studio et ne sera jamais inventée. Test séparé exigé pour lever le
statut expérimental : serveur publié avec 16 comptes réels (SR), mesures de performance et de stabilité consignées.
Réalisable localement en attendant : tests unitaires à 16 entrées (barème, équipes), test à 8 clients, simulation de
charge serveur (16 balles de simulation) — sans conclure sur 16 joueurs.

### 17.5 Validation des trous

Pour chacun des 81 trous : validation structurelle (`HoleValidator`), parcours réalisable sans objet (simulation),
inspection visuelle (aperçu en mode Édition) et playtest ; chaque état réellement atteint est consigné avec sa date dans
`docs/CATALOGUE_TROUS.md` (§10.7).

### 17.6 Endurance et résidus

Au moins cinq trous ou parties successifs dans la même session : nombre d'instances dans `Workspace`, connexions et
éléments de Trove, mémoire, statistiques réseau ; aucune croissance au-delà d'une tolérance documentée, aucun objet
résiduel (effets, pièges, karts, balles, plateformes) après une fin de manche ou une déconnexion.

## 18. Définitions : « implémenté », « testé », « prêt à publier »

| Statut | Définition |
| --- | --- |
| **Implémenté** | le code et ses données existent dans le dépôt, sont intégrés à la boucle de jeu et à leur interface, se chargent sans erreur et se nettoient ; sans preuve de fonctionnement, ce statut ne suffit pas |
| **Testé** | implémenté **et** doté de la (ou des) preuve(s) de la catégorie attendue, consignée(s) avec date, commande ou scénario et résultat dans la matrice |
| **Prêt à publier** | testé, y compris les tests multi-clients et les vérifications sur service Roblox réel exigées (DataStore, serveurs réservés, chat), manifeste des assets à jour, configuration Roblox restante faite, aucune anomalie bloquante ouverte |

Une fonctionnalité est **terminée** si elle fonctionne de bout en bout, possède ses interfaces et assets nécessaires, se
nettoie correctement et dispose d'une preuve adaptée. Une configuration ou une animation seule ne suffit pas. Toute
fonctionnalité ou carte non vérifiée conserve un statut explicite. Le projet n'est pas déclaré « terminé » si des
éléments majeurs manquent ou si le jeu n'a pas pu être vérifié dans Studio.

## 19. Livrables

| Livrable | Emplacement |
| --- | --- |
| Projet source complet, configurations, dépendances reproductibles | `src/`, `default.project.json`, `scripts/`, `tools/` (installé par script, hors Git) |
| Fichier de place réellement généré | `build/GolfChaos.rbxlx` (`scripts/build.ps1`), ou procédure de construction et d'import vérifiée |
| Géométrie, interface et modèles générés de manière reproductible | `src/server/Course/`, `src/client/UI/`, `src/shared/Cosmetics/` |
| README en français (installation, ouverture, synchronisation, lancement, tests, configuration Roblox restante) | `README.md` |
| Architecture | `docs/ARCHITECTURE.md` |
| Règles de gameplay | `docs/REGLES_SCORE.md` et ce cahier (§4 à §9) |
| Catalogue des 81 trous | `docs/CATALOGUE_TROUS.md` (+ `docs/PLAN_PARCOURS.md`, `docs/FORMAT_TROUS.md`) |
| Registre des 17 objets | `docs/REGISTRE_OBJETS.md` (+ `docs/MATRICE_INTERACTIONS.md`) |
| Catalogue des cosmétiques | `docs/CATALOGUE_COSMETIQUES.md` (produit à partir du registre) |
| Manifeste des assets | `docs/MANIFESTE_ASSETS.md` |
| Matrice exigence → fichiers/systèmes → preuve → résultat → limite | `docs/MATRICE_COUVERTURE.md` |
| Rapport final daté (contenu, commandes, résultats, captures, problèmes, démarches avant publication) | `docs/RAPPORT_FINAL.md` |
| État de reprise | `docs/ETAT_REPRISE.md` |

## 20. Limites actuelles de l'environnement

### 20.1 Constats (13/11/2026)

| Constat | Conséquence sur le travail et les preuves |
| --- | --- |
| Roblox Studio 0.747 avec serveur MCP intégré **vérifié** : exécution de Luau en mode Édition, Play solo, console, captures d'écran, entrées simulées | tests unitaires et tests moteur solo possibles et consignés |
| Lancer une nouvelle fenêtre Studio peut **fermer d'autres fenêtres Studio** (incidents des 12/11 et 13/11) | aucune fenêtre lancée tant qu'une fenêtre non ouverte par l'outillage est présente ; réutilisation des fenêtres `GolfChaos_check.rbxlx` (vérifications de compilation, mode Édition) et `GolfChaos_verify.rbxlx` (tests de l'intégrateur) ; construction dans un fichier distinct |
| Multi-clients : l'outil MCP `start_stop_play` ne lance qu'un Play solo ; `StudioTestService:ExecuteMultiplayerTestAsync` (1 à 8 clients, sécurité plugin) est **à essayer** via le contexte plugin ; sinon « Serveur et clients » manuel | aucune preuve MC obtenue à ce jour ; 16 clients impossibles dans Studio (§17.4) |
| DataStore réel : exige une place **publiée** avec « Activer l'accès Studio aux services API » | adaptateur mémoire signalé non persistant ; preuves SR à obtenir après publication (action de l'utilisateur) |
| Aucun upload d'asset (images, maillages, animations, sons) | modèles, décors, interface, icônes et animations **procéduraux**, générés par code |
| Audio : sons intégrés au moteur et bibliothèque sous licence des comptes officiels ProSoundEffects et APMOfficial (51 sons vérifiés, `docs/MANIFESTE_ASSETS.md`) | aucun autre uploader ; disponibilité à revérifier après publication |
| PC de référence : AMD Ryzen 7 7435HS, NVIDIA RTX 4060 Laptop, 23,7 Go de RAM, Windows 11 Famille | objectif 60 FPS mesurable sur cette machine |
| Aucun appareil mobile physique | objectif 30 FPS mobile et confort tactile réel non vérifiables (AP) ; le simulateur d'appareil de Studio n'en est pas une preuve |
| Studio peut perdre sa connexion au compte (HTTP 401 du 12/11) | tests moteur suspendus jusqu'à la reconnexion par l'utilisateur ; travaux indépendants poursuivis |
| Un plugin cloud tiers installé dans Studio écrit des messages d'erreur dans la console | messages à ignorer dans l'analyse des journaux du jeu |
| Parties privées : serveurs réservés réservés aux expériences publiées | testées séparément sur service réel (§13.2) |

### 20.2 Pourquoi les fenêtres Studio de test paraissent vides (13/11/2026)

Les deux fenêtres Studio ouvertes par l'outillage (`GolfChaos_check.rbxlx` et `GolfChaos_verify.rbxlx`) n'affichent
rien dans la vue 3D. C'est **attendu** dans l'état actuel du projet, pour trois raisons :

1. **La place construite ne contient aucune géométrie, par conception.** `default.project.json` ne déclare que des
   réglages pour `Workspace` (aucun Baseplate, aucun SpawnLocation, aucun terrain) : les fichiers de `build/` contiennent
   65 scripts (1 Script, 1 LocalScript, 63 ModuleScripts dont 8 de tests) et **0 pièce**. Le monde (accueil, trous,
   décors, interface) doit être **généré par le code au démarrage d'une partie** (§1.4) ; en mode Édition, la vue est
   donc vide.
2. **Les modules qui construisent le monde et l'interface ne sont pas encore dans le dépôt.** Les 55 modules de jeu
   présents (fondations, configuration, logique pure, collisions, combat, déplacements, caméra, entrées, effets) se
   chargent sans erreur, mais `CourseService` et ses constructeurs, les données des trous, `SpawnService`, l'interface
   (`UIController`, HUD, menus) et `BallService`/`MatchService` sont en cours d'écriture. Comme
   `Players.CharacterAutoLoads = false` (les apparitions sont confiées à `SpawnService`), même un Play n'affiche
   aujourd'hui ni sol, ni avatar, ni interface.
3. **La fenêtre de vérification ne sert qu'à compiler.** Dans `GolfChaos_check.rbxlx`, chaque fichier est vérifié en
   l'enveloppant dans une fonction **jamais appelée** : rien n'est créé, et la règle interdit d'y créer ou d'y modifier
   des instances. `GolfChaos_verify.rbxlx` sert aux tests unitaires (mode Édition) et aux Play de l'intégrateur ; après
   l'arrêt d'un Play, Studio revient au mode Édition vide.

Le contenu deviendra visible quand `CourseService` sera intégré : en Play (accueil construit au démarrage), et en mode
Édition grâce à `CourseService.BuildPreview(holeId, origin)` (aperçu d'inspection dans `Workspace.CoursePreviews`).

### 20.3 Conséquences sur les preuves

Toute exigence dont la preuve dépend d'une limite ci-dessus garde le statut « À faire » ou « En cours » dans la matrice,
avec la limite écrite dans la colonne « Limite restante ». Aucune preuve n'est présumée à partir d'une catégorie plus faible.

## 21. Exécution par étapes

Les étapes suivent la demande (§11) sans réduire le périmètre final ; après chaque étape, ce qui vient de changer est
vérifié puis l'étape suivante est lancée, sans s'arrêter après un plan ou un prototype. L'avancement réel est tenu dans
`docs/ETAT_REPRISE.md` et la matrice (lignes `ETP`).

| Étape | Contenu | Critère de sortie |
| --- | --- | --- |
| 1 | examiner l'environnement, écrire le cahier des charges et la matrice de couverture | environnement consigné ; cahier et matrice complets et relus |
| 2 | partie complète sur un trou : physique fiable, HUD, score, retour à l'accueil | Play solo : accueil → trou → résultats → podium → accueil, sans erreur, preuves TM consignées |
| 3 | multijoueur, états de partie et commandes sur les supports visés | tests MC à 2 puis jusqu'à 8 clients ; cas limites (§4.4) ; clavier, manette et tactile en TM |
| 4 | les 17 objets, les véhicules et les modes | chaque objet, chaque paire de la matrice d'interactions et chaque mode prouvés (TM, MC) |
| 5 | les cinq biomes et les 81 trous | 81 trous au minimum « Structure validée » et « Parcours simulé », catalogue à jour |
| 6 | personnalisation, boutique, progression et sauvegarde | catalogue ≥ 100 + 8 émotes, achats et défis prouvés, sauvegarde testée (TU, TM ; SR après publication) |
| 7 | présentation, animations, audio, accessibilité et optimisation | réglages d'accessibilité, mesures de performance consignées |
| 8 | revue complète, corrections et preuves finales | rapport final daté, matrice à jour, distinction implémenté / testé / prêt à publier |

## 22. Gestion des révisions

| Version | Date | Changements |
| --- | --- | --- |
| 1.0 | 12/11/2026 | rédaction des §1 à §4 (brouillon interrompu) |
| 1.1 | 13/11/2026 | rédaction des §5 à §22 ; départage des égalités aligné sur `docs/REGLES_SCORE.md` v1.1 ; durées de phase et règle AFK précisées ; règle des fenêtres Studio et fichier de construction distinct ; constats d'environnement et explication des fenêtres Studio vides (§20) |

Procédure : toute modification d'exigence ajoute une ligne datée à ce tableau, met à jour les lignes concernées de
`docs/MATRICE_COUVERTURE.md` (sans réutiliser un identifiant) et est signalée dans `docs/ETAT_REPRISE.md`. En cas de
contradiction, `docs/SPEC_DEMANDE.md` prévaut sur ce cahier, et ce cahier prévaut sur les documents de conception
dérivés, à l'exception des noms, signatures et attributs fixés par `docs/ARCHITECTURE.md`.

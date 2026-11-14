# Matrice de couverture — Golf Chaos

| Élément | Valeur |
| --- | --- |
| Version | 1.0 — 13/11/2026 |
| Exigences | `docs/SPEC_DEMANDE.md` §1 à §13, détaillées dans `docs/CAHIER_DES_CHARGES.md` v1.1 (références « CDC §… ») |
| Contenu | 180 exigences granulaires, identifiants stables, regroupées par section de la demande |
| Tenue | par l'intégrateur après chaque preuve obtenue (voir « Comment mettre à jour ») |

Une ligne par exigence vérifiable : exigence → fichiers / systèmes → preuve attendue → résultat → limite restante.
Le résultat « Fait » n'est écrit que lorsque **toutes** les preuves attendues ont été obtenues et consignées ; une preuve
d'une catégorie plus faible n'en remplace jamais une autre (`docs/CAHIER_DES_CHARGES.md` §17).

## Légende

### Résultat

| Valeur | Sens |
| --- | --- |
| **Fait (preuve : …)** | exigence satisfaite et preuve(s) de la catégorie attendue obtenue(s) ; la parenthèse cite le test, le fichier ou le constat, la date et le résultat |
| **En cours** | du code, des données ou un document existent dans le dépôt (brouillon) ou un chantier est lancé, mais la preuve attendue n'est pas obtenue ; les preuves partielles sont décrites dans « Limite restante » |
| **À faire** | rien d'exploitable dans le dépôt pour cette exigence (au mieux un contrat ou une valeur de configuration) |

### Preuve attendue (catégories de `docs/CAHIER_DES_CHARGES.md` §17.1)

| Code | Catégorie | Exemples dans ce projet |
| --- | --- | --- |
| AS | analyse statique | lecture du code et des données, construction Rojo, recherche d'AssetId, contrôle `--!strict` |
| TU | test unitaire | `require(game.ServerStorage.Tests.Runner).run("Nom")` sur des modules purs, Studio en mode Édition |
| SIM | simulation | balles de simulation, latence simulée (Network Simulator, `NetworkSettings`), charge serveur scriptée |
| TM | test moteur Studio | Play solo ou mode Édition avec moteur (aperçus, chargement d'assets), via l'outil MCP de Studio |
| MC | test multi-clients | un serveur et 2 à 8 clients dans Studio |
| AP | appareil physique | téléphone, tablette ou manette réels |
| SR | service Roblox réel | place publiée : DataStore, serveurs réservés, chat et vocal, badges, serveurs de production |

### Colonnes

- **ID** : identifiant stable, jamais réutilisé ni renuméroté ; le préfixe indique le domaine (PER périmètre, ENV
  environnement, BCL boucle, CMD commandes, MOD modes, SCO score, PHY physique, SEC sécurité, OBJ objets, INT
  interactions, TRO trous, ART direction artistique, COS cosmétiques, PRG progression, SAV sauvegarde, SAL salon, IHM
  interface, ACC accessibilité, COM communication, ARC architecture, PRF performances, ETP étapes, VAL validation, LIV
  livrables).
- **Fichiers / systèmes** : chemins relatifs à `src/` sauf mention ; « (à écrire) » = absent du dépôt ; « (en écriture) »
  = confié à un chantier en cours.
- **Preuve attendue** : toutes les catégories listées sont exigées pour écrire « Fait ».

## Synthèse au 13/11/2026

| Section de la demande | Lignes | Fait | En cours | À faire |
| --- | --- | --- | --- | --- |
| §1 Objectif et périmètre | 6 | 1 | 5 | 0 |
| §2 Environnement réel | 7 | 4 | 3 | 0 |
| §3 Boucle de jeu, commandes, modes, score | 26 | 1 | 22 | 3 |
| §4 Physique du golf et autorité serveur | 16 | 1 | 14 | 1 |
| §5 Les 17 objets | 32 | 2 | 1 | 29 |
| §6 Les 81 trous | 14 | 0 | 7 | 7 |
| §7 Direction artistique et personnalisation | 12 | 1 | 8 | 3 |
| §8 Progression et sauvegarde | 13 | 2 | 7 | 4 |
| §9 Salons, interface et accessibilité | 16 | 0 | 13 | 3 |
| §10 Architecture et performances | 10 | 1 | 7 | 2 |
| §11 Exécution par étapes | 6 | 0 | 4 | 2 |
| §12 Validation et critères d'acceptation | 13 | 1 | 3 | 9 |
| §13 Livrables | 9 | 0 | 7 | 2 |
| **Total** | **180** | **14** | **101** | **65** |

Les 14 lignes « Fait » ne couvrent que des fondations (environnement, Git, construction, accès Studio, registres et tests
unitaires, sons vérifiés, chargement des modules). **Aucune fonctionnalité de jeu n'est prouvée de bout en bout.**

### État de référence utilisé pour cette version

- Chargement en Studio (mode Édition) : 55 modules de jeu, 0 échec — 13/11/2026, 21 h 40 (`docs/ETAT_REPRISE.md`).
- Tests unitaires en moteur : série d'intégration du 12/11/2026 (réseau, traductions, cosmétiques, objets, progression)
  à 47/48, seul échec attendu : catalogue de cosmétiques en cours d'écriture ; série du 13/11/2026 à 72/77 **avant**
  correction des tolérances float32 de `BallMath.spec` (1e-6 → 1e-4), à relancer.
- Chantiers en cours (run `wf_a32b601c-e99`) : trous (données → constructeur → `CourseService`), interface (cadre → HUD et
  écrans), sauvegarde (schéma → stockage), balle, partie, salon, visée, animations, documents, 5 lots de cosmétiques.
- Non commencés : comportements des 17 objets, véhicules, boutique, services de défis et de récompenses, tutoriel,
  spectateur, données des 81 trous.
- Les fenêtres Studio de test sont vides : la place construite ne contient aucune géométrie par conception et les modules
  qui construisent le monde ne sont pas encore intégrés (`docs/CAHIER_DES_CHARGES.md` §20.2).

---

## §1 — Objectif et périmètre

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| PER-01 | Golf multijoueur simultané : chaque joueur possède sa balle, tout le monde joue en même temps à la 3e personne, frappe puis rejoint sa balle à pied ou en véhicule (CDC §1.1) | `server/Services/BallService.luau`, `MatchService`, `SpawnService` (en écriture), `client/Controllers/CameraController.luau`, `VehicleService` (à écrire) | TM, MC | En cours | boucle de jeu en écriture ; aucun Play ne montre encore de monde (CDC §20.2) |
| PER-02 | Création originale : nom, interfaces, modèles, sons, animations et niveaux originaux ; aucun asset du jeu Steam ni collaboration de marque ; noms d'objets originaux (CDC §1.4) | `docs/MANIFESTE_ASSETS.md`, `shared/Cosmetics/Build.luau`, `shared/Animations`, `server/Course/` (en écriture), `shared/Config/Items.luau` | AS | En cours | provenance des sons vérifiée et géométrie par code ; revue finale de tout le contenu livré à faire |
| PER-03 | Livraison = jeu complet utilisable dans Studio : 81 trous, 17 objets fonctionnels, progression persistante, interface aboutie ; ni démo à 3 trous, ni interface seule, ni scripts non intégrés (CDC §1.2) | ensemble du projet | TM, MC, SR | En cours | critère global de fin, dépend de toutes les autres lignes |
| PER-04 | 1 à 8 joueurs ; architecture prévue pour 16 ; mode 16 joueurs expérimental et désactivé par défaut tant que sa stabilité n'est pas mesurée (CDC §2.1) | `shared/Config/Match.luau` (`MaxParticipants`, `MaxParticipantsExperimental`), `Types.MatchSettings.experimental16`, `Config/Scoring.luau` (barème jusqu'au 16e) | AS, TU, MC | En cours | paramètres écrits ; aucun test multi-clients ; 16 joueurs : VAL-12 |
| PER-05 | Supports PC, mobile/tablette et manette : toute action accessible sur chaque support (CDC §2.2) | `client/Controllers/InputController.luau` (détection, boutons tactiles), interface (en écriture) | TM, AP | En cours | InputController écrit, non vérifié en Play ; aucun appareil mobile physique |
| PER-06 | Textes centralisés (`Locale.t`), français par défaut, traduction anglaise de chaque clé avec les mêmes variables (CDC §2.3) | `shared/Locale/init.luau`, `Locale/fr/*`, `Locale/en/*`, `tests/Specs/Locale.spec.luau` | TU | Fait (preuve : `Locale.spec` en moteur, mode Édition, série d'intégration du 12/11/2026) | à relancer à chaque ajout de textes ; absence de texte en dur dans l'interface finale : IHM-06 |

## §2 — Environnement réel

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| ENV-01 | Inspection du dossier, de l'état Git, des consignes (AGENTS.md / CLAUDE.md : absents) et des outils installés (CDC §20.1) | `docs/ETAT_REPRISE.md` § Environnement constaté | AS | Fait (preuve : inventaire consigné le 12/11/2026 dans `docs/ETAT_REPRISE.md`) | à compléter si l'environnement change |
| ENV-02 | Travail existant préservé : prototype d'origine conservé, dépôt Git, travail sur une branche dédiée | `legacy/prototype-etape1/` (10 scripts), commit `250bc33` sur `main`, branche `dev/golf-chaos` | AS | Fait (preuve : `git log` montre le commit `250bc33` « Prototype initial (etape 1) » ; 10 fichiers présents dans `legacy/prototype-etape1/`, constaté le 13/11/2026) | — |
| ENV-03 | Accès réel à Roblox Studio et à ses outils MCP vérifié, sans capacité inventée | Studio 0.747, serveur MCP intégré | TM | Fait (preuve : exécution de Luau en mode Édition, Play solo, console, captures et entrées simulées vérifiées, `docs/ETAT_REPRISE.md`, 12–13/11/2026) | Studio peut perdre sa connexion (HTTP 401 du 12/11) ; multi-clients non essayé (VAL-07) |
| ENV-04 | Flux reproductible Luau + Rojo, versions vérifiées avant de figer la configuration ; place `.rbxlx` réellement construite | `scripts/install-tools.ps1` (Rojo 7.7.1, SHA-256), `scripts/build.ps1`, `default.project.json` | AS | Fait (preuve : construction réussie ; `build/GolfChaos.rbxlx` et ses copies contiennent 63 ModuleScripts, 1 Script et 1 LocalScript, constaté le 13/11/2026) | la place finale (LIV-02) dépend du contenu restant |
| ENV-05 | Source de vérité définie (le dépôt) ; une synchronisation n'écrase jamais des modifications Studio non exportées ni une place de l'utilisateur (CDC §1.3, §14.1) | `docs/ARCHITECTURE.md` §1, `README.md`, `scripts/open-studio.ps1` | AS, TM | En cours | règle du 13/11 : lancer Studio peut fermer d'autres fenêtres ; aucune fenêtre lancée tant qu'une fenêtre de l'utilisateur est ouverte ; construire dans `build/GolfChaos_src.rbxlx` |
| ENV-06 | Documentation Roblox actuelle consultée pour les API sensibles : physique, propriété réseau, sauvegardes, téléportations, commandes, communication | `docs/notes-techniques-roblox.md` (sources citées) | AS | En cours | notes rédigées ; à confronter à chaque intégration d'API sensible |
| ENV-07 | Studio inaccessible : travaux indépendants poursuivis, manipulations restantes décrites, aucun lancement prétendu ; questions seulement si bloquantes ; travail local sans publication, achat, monétisation ni message sans demande explicite | `docs/ETAT_REPRISE.md`, `README.md` § Publier | AS | En cours | règle appliquée pendant la déconnexion du 12/11 ; aucune publication à ce jour ; à maintenir jusqu'à la livraison |

## §3 — Boucle de jeu, commandes, modes et score

### Boucle et cas limites

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| BCL-01 | Machine à états explicite et pure (table des transitions, refus journalisés), pilotée par `MatchService` seul ; chaque phase a une durée maximale (CDC §4.1) | `shared/Logic/MatchStateMachine.luau`, `Config/Match.Durations`, `server/Services/MatchService.luau` (en écriture) | TU, TM | En cours | module pur écrit sans spec (`MatchStateMachine.spec`, VAL-01) |
| BCL-02 | Boucle complète : accueil → préparation du salon → chargement → présentation du trou → compte à rebours → partie → fin du trou → résultats → trou suivant → podium → retour à l'accueil (CDC §4.1) | `MatchService`, `LobbyService`, `CourseService`, `SpawnService` (en écriture), HUD (en écriture) | TM, MC | En cours | aucun Play complet possible tant que monde et services manquent (CDC §20.2) |
| BCL-03 | KO temporaires, recul, réapparition aux checkpoints et récupération de la balle hors limites (CDC §7.3, §8.4, §8.6) | `server/Services/CombatService.luau`, `SpawnService`, `CourseService.GetCheckpointFor`, `BallService.ResetToLastValid` (en écriture) | TM | En cours | CombatService écrit (brouillon chargé) ; checkpoints et balle en écriture |
| BCL-04 | Protection brève après réapparition (3 s) et mécanisme configurable contre les KO répétés sur la même personne (CDC §8.5) | `CombatService` (`GrantProtection`, anti-KO répété), `Config/Gameplay.KO` | TU, TM | En cours | brouillon chargé, non vérifié en Play |
| BCL-05 | Fin de trou : les joueurs ayant terminé ne peuvent plus modifier les résultats ni gêner ceux qui jouent encore (CDC §4.3) | `server/Services/CollisionService.luau` (`SetGhost`), `CombatService.CanAffect`, `MatchService` | TM, MC | En cours | groupes et fantômes écrits ; preuve multi-clients à faire |
| BCL-06 | Arrivée tardive (spectateur jusqu'au trou suivant, jamais au milieu d'un trou), déconnexion (statut `Disconnected`, nettoyage, réévaluation de fin) et changement d'hôte (plus ancien présent) sans blocage (CDC §4.4) | `MatchService`, `LobbyService` (en écriture), `Config/Match.LateJoin` | MC | En cours | nettoyage des objets et karts dépend d'`ItemService` et `VehicleService` (à écrire) |
| BCL-07 | Abandon (`Match.Forfeit`), AFK (60 s, 25 s en récidive, battement accompagné d'un mouvement), balle bloquée (`Golf.ResetBall`, arrêt forcé), départ de tous, chargement bloqué et fin du chronomètre ne bloquent jamais la progression (CDC §4.4) | `MatchService`, `BallService` (en écriture), `Config/Match.Afk`, `Config/Gameplay.Stuck`, transitions exceptionnelles de `MatchStateMachine` | TU, TM, MC | En cours | règles chiffrées en configuration ; services en écriture |

### Commandes

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| CMD-01 | Visée horizontale et angle vertical (loft borné par type de frappe), revalidés par le serveur (CDC §7.1) | `GolfAimController` (en écriture), `Golf.Shoot`, `shared/Logic/BallMath.luau`, `Config/Gameplay.ShotTypes` | TU, TM | En cours | `BallMath.spec` à 72/77 avant correction des tolérances (13/11), à relancer |
| CMD-02 | Puissance chargée : jauge horodatée par le serveur (`Golf.SwingStart`), puissance recalculée, valeur client bornée à ± 0,2 (CDC §7.1) | `BallMath.serverPower`, `BallService` (en écriture), `Config/Gameplay.Shot` | TU, TM | En cours | cas couverts par `BallMath.spec` (à relancer) ; application serveur en écriture |
| CMD-03 | Putt précis (green ou moins de 30 studs du trou, courbe 1,5) et frappe aérienne (Chip lobé 48–60°) (CDC §7.1, §7.8) | `Config/Gameplay.ShotTypes`, `BallMath.resolveShotType`, `BallService` | TU, TM | En cours | sensation à valider en Play |
| CMD-04 | Indicateur de trajectoire cohérent avec les règles : même calcul et mêmes paramètres que le serveur (CDC §7.1) | `BallMath.predictTrajectory`, `GolfAimController` (en écriture), `Config/Gameplay.Aim` | TU, TM | En cours | parabole testée par `BallMath.spec` ; affichage à écrire |
| CMD-05 | Saut, course, plongeon/esquive (fenêtre `Dodging` 0,35 s, recharge 2,5 s) et frappe de proximité (`Combat.Punch` : 7 studs, 50°, KO 1,2 s) (CDC §8.1, §8.2) | `server/Services/MovementService.luau`, `CombatService`, `InputController`, `Config/Gameplay` (`Dive`, `Punch`) | TM | En cours | brouillons chargés, non vérifiés en Play |
| CMD-06 | Tir de balle guidé vers un adversaire avec règles explicites de verrouillage, de rupture et d'évitement (CDC §8.3) | `BallMath` (sélection de cible, guidage), `Config/Gameplay.Guided`, `BallService`, `CombatService.BallHit` | TU, TM, MC | En cours | guidage testé dans `BallMath.spec` (à relancer) ; vol guidé serveur en écriture |

### Modes

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| MOD-01 | Chacun pour soi : points selon l'ordre d'arrivée, bonus de performance golfique, gagnant au total des points (CDC §5.2) | `shared/Logic/Scoring.luau`, `MatchService` | TU, MC | En cours | logique écrite sans spec (VAL-01) |
| MOD-02 | Équipes rouge/bleue : point d'équipe au ratio d'arrivées, départages, match nul, équipes déséquilibrées, composition et équilibrage (CDC §5.3) | `Logic/Scoring` (`teamHolePoint`, `assignTeams`, `balanceTeams`), `LobbyService` | TU, MC | En cours | logique écrite sans spec |
| MOD-03 | Équipes : aucun KO, recul ni effet d'objet entre alliés (CDC §5.3) | `CombatService.CanAffect`, `MatchService.AreAllies`, `ItemService` (à écrire) | TM, MC | En cours | règle de combat écrite ; objets à faire |
| MOD-04 | Solo : score coups/par puis temps, sans adversaire obligatoire, record personnel par trou (CDC §5.4) | `Logic/Scoring` (`soloSummary`, `isBetterSoloRecord`), `MatchService`, `PlayerDataService` | TU, TM | En cours | logique écrite sans spec ; sauvegarde du record en écriture |
| MOD-05 | Entraînement : Driving Range et essais libres des frappes, sans score ni pièces (CDC §5.5) | `shared/Data/Holes/Training.luau` (ENT-01), `Lobby.RequestTraining`, `LobbyService`, `CourseService` (en écriture) | TM | En cours | trous d'entraînement dans le chantier « trous » |
| MOD-06 | Entraînement : essais des objets et des voiturettes (postes d'essai à l'accueil, mode `Training` sans points ni récompenses) (CDC §5.5) | `ItemService`, `VehicleService`, postes d'essai de l'accueil (à écrire) | TM | À faire | dépend des objets et véhicules |
| MOD-07 | Tutoriel interactif : chaque étape validée par une action réelle constatée par le serveur ; récompense unique (CDC §5.5) | `TutorialController` (à écrire), `Data/Holes/Training.luau` (ENT-02), défi `ach_tutorial` | TM | À faire | — |
| MOD-08 | Spectateur : caméra de suivi, changement du joueur observé sur chaque support, bascule automatique (CDC §5.6) | `SpectatorController` (à écrire), `CameraController.Follow`, `Match.SetSpectator` | TM, MC | À faire | seul `CameraController.Follow` existe (brouillon) |

### Score

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| SCO-01 | Spécification du score écrite avant l'implémentation ; valeurs initiales équilibrées, centralisées en configuration et testées (CDC §6, §6.6) | `docs/REGLES_SCORE.md` v1.1, `Config/Scoring.luau`, `Config/Match.luau`, `tests/Specs/Scoring.spec.luau` (à écrire) | AS, TU | En cours | spécification et configuration écrites ; tests à écrire (VAL-01) |
| SCO-02 | Barème d'arrivée (12-9-7-5-4-3-2-1 puis 1, 0 si non arrivé) ; bonus par, birdie, eagle, albatros, trou en un, coup rentré de loin (40 studs, hors putt) et vitesse, cumulables et plafonnés à 8 (CDC §6.2) | `Logic/Scoring` (`arrivalPoints`, `computeBonuses`, `scoreHole`) | TU, TM | En cours | mesure serveur de la distance du coup final à prouver en Play |
| SCO-03 | Chronomètre (`clamp(cible × échelle × 2, 45, 600)`), prolongation déclenchée par la première arrivée (20–45 s, une fois), plafond de coups (`clamp(par + 7, 10, 14)`) et statuts de fin de trou (CDC §6.3, §6.4) | `Logic/Scoring` (`holeTimeLimit`, `deadlineAfterFinish`, `strokeCap`), `MatchService` | TU, TM | En cours | — |
| SCO-04 | Égalités : arrivées de la même image serveur à rang partagé (1, 1, 3) ; classement de partie par points, trous gagnés, coups retenus, birdies, puis rang partagé (CDC §6.4) | `Logic/Scoring` (`nextFinishRank`, `competitionRanks`, `matchStandings`), `MatchService` | TU, MC | En cours | arrivées simultanées réelles à prouver en multi-clients |
| SCO-05 | Récompenses économiques non exploitables par la répétition d'actions d'entraînement : rien en entraînement, rien sans 3 trous actifs, plafonds par partie (CDC §5.5, §12.1) | `Config/Economy.luau`, `shared/Logic/Rewards.luau`, `tests/Specs/Progression.spec.luau` | TU | Fait (preuve : `Progression.spec` — « ne donne rien en entraînement », « ne donne rien à un joueur inactif (AFK) », « plafonne les bonus de performance et le total », en moteur, série du 12/11/2026) | versement réel et défis bloqués en entraînement à prouver (PRG-02, PRG-04) |

## §4 — Physique du golf et autorité serveur

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| PHY-01 | Roulement, rebond, frottement et pentes selon la surface : herbe/fairway, green, rough, sable, glace, neige, boue, roche, bois, asphalte (CDC §7.2) | `Config/Gameplay.Surfaces`, `BallMath` (roulement, rebond, arrêt en pente), `BallService` (en écriture) | TU, TM | En cours | cas purs dans `BallMath.spec` (à relancer) ; sensation à valider en Play |
| PHY-02 | Eau, hors limites, lave et vide (pénalité configurable, replacement à la dernière position valide, hors limites au contact du sol) et obstacles statiques ou animés (CDC §7.3, §10.5) | `Config/Gameplay.Hazards`, `BallService`, `CourseService.IsOutOfBounds`, `Config/Course.ObstacleKinds`, `server/Course/` (en écriture) | TM | En cours | — |
| PHY-03 | Vent configurable (Off, Light, Strong, Random), appliqué en vol, publié et affiché (CDC §7.4) | `Config/Gameplay.Wind`, `BallMath`, `GameState.Wind`, HUD (en écriture) | TU, TM | En cours | dérive testée dans `BallMath.spec` (à relancer) |
| PHY-04 | Collisions rapides : aucune balle ne traverse un obstacle mince (pas fixe 240 Hz et balayage `Spherecast`) (CDC §7.5) | `default.project.json` (`PhysicsSteppingMethod = Fixed`), `Config/Gameplay.AntiTunneling`, `BallService` | SIM, TM | En cours | réglage moteur présent dans le fichier construit ; balayage en écriture |
| PHY-05 | Entrée dans le trou robuste (test balayé segment–cercle côté serveur) ; aucun point accordé à distance (CDC §7.5) | `BallMath` (capture), `Config/Gameplay.Cup`, `BallService` | TU, TM | En cours | 8 cas de capture dans `BallMath.spec` (à relancer) |
| PHY-06 | Effets visuels des balles séparés de leur collision de référence (Part serveur neutre, skin client lissé) (CDC §7.6) | `BallService`, balle visuelle client (en écriture), `Cosmetics` (`decorate`) | AS, TM | En cours | — |
| PHY-07 | Stratégie de simulation et de propriété réseau documentée pour balles, véhicules et joueurs (CDC §7.7) | `docs/ARCHITECTURE.md` §11, `docs/notes-techniques-roblox.md` §1 | AS | En cours | documentée ; ses conséquences restent à tester (PHY-08) |
| PHY-08 | Conséquences testées avec latence (100–300 ms, gigue) ; lissage visuel client corrigé vers l'état autorisé (CDC §7.7) | Network Simulator ou `NetworkSettings`, `Config/Gameplay.Aim` (lissage) | SIM, MC | À faire | aucun test de latence réalisé |
| PHY-09 | Longues frappes cohérentes et petit putt précis (CDC §7.8) | `Config/Gameplay.ShotTypes` (Drive 25–150 studs/s, Putt 2–60 studs/s, courbe 1,5), `BallMath` | TU, TM | En cours | bornes testées dans `BallMath.spec` ; ressenti à valider |
| PHY-10 | Aucun avantage physique lié à un skin d'avatar ou de balle : même Part, mêmes proportions, cosmétiques sans masse ni collision (CDC §7.8, §11.4) | `Config/Gameplay.Ball`, `default.project.json` (`LoadCharacterAppearance = false`), `Cosmetics/Build.luau`, `tests/Specs/Cosmetics.spec.luau` | TU, TM | En cours | règles d'équité dans `Cosmetics.spec`, en échec tant que le catalogue est incomplet |
| SEC-01 | Le serveur décide des frappes acceptées, des KO, des entrées dans le trou et des scores ; le client ne transmet que des intentions, jamais une récompense ou une conséquence (CDC §15.1) | `shared/Net/Remotes/*.luau`, `BallService`, `CombatService`, `MatchService` | AS, TM | En cours | aucun remote ne transporte de score ni de récompense ; gestionnaires serveur à relire à l'intégration |
| SEC-02 | Chaque remote client → serveur déclare ses types d'arguments et son débit ; aucune RemoteFunction serveur → client ; nommage `Domaine.Action` (CDC §14.5) | `shared/Net/init.luau`, `Net/Remotes/*.luau`, `tests/Specs/NetDefinitions.spec.luau` | TU | Fait (preuve : `NetDefinitions.spec` en moteur, série d'intégration du 12/11/2026) | à relancer à chaque nouveau remote |
| SEC-03 | Types, valeurs finies, bornes, distance, état du joueur, équipement, délai et permissions validés pour chaque intention (CDC §15.2) | `shared/Util/Validate.luau`, contrôle commun de `Net`, gestionnaires des services | TU, TM | En cours | `Util.spec` couvre Validate ; application par chaque gestionnaire à vérifier |
| SEC-04 | Requêtes limitées (seau à jetons par joueur et par remote), doublons rejetés, requêtes d'une ancienne manche (`RoundId`) ignorées (CDC §15.3) | `shared/Net` (`rate`, `burst`), gestionnaires des services | TU, TM, MC | En cours | limitation codée dans Net, non éprouvée par une rafale réelle (VAL-05) |
| SEC-05 | Déplacements plausibles vérifiés sans punir les propulsions, téléportations ou réapparitions autorisées (CDC §8.7) | `MovementService` (`AllowDisplacement`, `Teleport`), `Config/Gameplay.Movement.Plausibility` | TM, MC | En cours | brouillon chargé ; faux positifs à mesurer avec latence |
| SEC-06 | Rejets comptés et consultables sans exclusion automatique sans preuve ; outils de test actifs uniquement dans Studio (CDC §15.5, §15.6) | `Net.getStats`, `server/Services/NetworkValidation.luau`, `server/Services/DevService.luau` | AS, TM | En cours | brouillons chargés ; pont `DevBridge` à éprouver en Play |

## §5 — Les 17 objets

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| OBJ-01 | Registre commun des 17 objets avec, pour chacun : ID stable, nom original (fr/en), rareté, chances d'apparition, portée, durée, charges, délai, catégories de cible, contre-jeu, effets sur alliés, nettoyage ; capacité d'inventaire initiale documentée et configurable (3, bornes 1–4) (CDC §9.1 à §9.3) | `shared/Config/Items.luau`, `Locale/*/Items.luau`, `docs/REGISTRE_OBJETS.md`, `tests/Specs/Items.spec.luau` | TU | Fait (preuve : `Items.spec` — « exactement les 17 objets attendus », « tous les champs exigés », « textes français et anglais », « capacité initiale dans les bornes », en moteur, série du 12/11/2026) | comportements à implémenter (OBJ-06 à OBJ-22) |
| OBJ-02 | Tirage avec ajustement configurable des probabilités selon la position dans la course ; boîte de mobilité limitée aux objets de mobilité ; tirage reproductible avec une graine (CDC §9.4) | `shared/Logic/ItemOdds.luau`, `Config/ItemBoxes.CatchUpStrength`, `Items.spec` | TU | Fait (preuve : `Items.spec` — probabilités de somme 1, rattrapage favorable aux derniers, aucun rattrapage à force nulle, boîte de mobilité, distribution avec graine, liste d'exclusion ; en moteur, 12/11/2026) | rang de course réel fourni par `MatchService.GetRacePosition` (OBJ-05) |
| OBJ-03 | Inventaire limité fonctionnel : ramassage, cases répliquées, vidage à chaque trou, sélection au clavier, au tactile et à la manette, utilisation simple ou maintenue (CDC §9.3) | `ItemService`, `InventoryController` (à écrire), `Items.Select`, `Items.Use`, `Items.UseStart`, `Items.UseCancel` | TM, AP | À faire | boutons tactiles génériques disponibles dans InputController |
| OBJ-04 | Boîtes d'objets aléatoires et boîtes de mobilité dans les trous : ramassage par proximité serveur, réapparition selon la fréquence, désactivation par réglage (CDC §9.4) | `ItemService` (à écrire), `Config/ItemBoxes.luau`, `HoleDef.itemBoxes`, `HoleDef.mobilityBoxes` | TM | À faire | — |
| OBJ-05 | Tirage réalisé par le serveur à partir de la position réelle dans la course ; le client ne choisit jamais (CDC §9.4) | `ItemService.RollItem` (à écrire), `MatchService.GetRacePosition` | AS, TM | À faire | logique pure prête (OBJ-02) |
| OBJ-06 | Corne Tonitruante : annonce 0,4 s ; frappe prématurée de qui charge, visée annulée 1,5 s, utilisation involontaire (35 %) d'un objet sensible ; alliés et porteurs de bulle non affectés | `server/Items/horn.luau` (à écrire), `BallService.ForceShot` | TM, MC | À faire | — |
| OBJ-07 | Expresso Turbo : vitesse × 1,45 et saut × 1,15 pendant 8 s, réutilisation sans cumul, le gel l'emporte | `server/Items/espresso.luau` (à écrire), `MovementService.SetModifier` | TM | À faire | — |
| OBJ-08 | Pistolet à Bouchon : 2 tirs instantanés (portée 80, arrêt sur le décor), KO 1,8 s, esquivable par plongeon, dévié par la bulle | `server/Items/cork_pistol.luau` (à écrire) | TM, MC | À faire | — |
| OBJ-09 | Tromblon Rebond : cône de 30° sur 25 studs, KO à moins de 12, balles poussées, recul du tireur et propulsion maîtrisée lors d'un tir vers le sol, avec exemption de plausibilité | `server/Items/blunderbuss.luau` (à écrire), `BallService.ApplyBallImpulse`, `MovementService.AllowDisplacement` | TM, MC | À faire | — |
| OBJ-10 | Bulle Magnétique : 12 s, absorbe 3 frappes mineures, dévie les projectiles ; une frappe majeure détruit la bulle et provoque un KO sans fort recul | `server/Items/magnet_shield.luau` (à écrire), `CombatService.SetShieldHandler` | TM, MC | À faire | crochet `SetShieldHandler` prévu dans CombatService |
| OBJ-11 | Kart-Caddie : véhicule pilotable à 8 occupants (60 studs/s, vitesse vérifiée), collisions et percussion décidées par le serveur, montée et descente fiables, sortie de secours, destruction (3 frappes majeures, chute) ou remise à l'endroit contrôlée, disparition après 45 s ou au départ du propriétaire | `server/Services/VehicleService.luau`, `server/Items/caddie_kart.luau`, `VehicleController` (à écrire), `Net/Remotes/Vehicles.luau` | TM, MC | À faire | contrats réseau définis |
| OBJ-12 | Champignon Piégé : armement 1,5 s visible, avertissement 0,6 s, explosion (KO à moins de 6 studs), déclenchement par une balle rapide, désamorçage par coup de poing, 2 actifs au plus, 60 s | `server/Items/shroom_mine.luau` (à écrire) | TM, MC | À faire | — |
| OBJ-13 | Rayon Satellite : règle de ciblage explicite (adversaire le mieux placé, exclusions), cercle qui suit 2 s puis se fige 1,2 s, frappe majeure, objet non consommé sans cible | `server/Items/orbital_beam.luau` (à écrire), `MatchService.GetRacePosition` | TM, MC | À faire | — |
| OBJ-14 | Lance-Fusées Confettis : verrouillage 0,6 s (cône 20°, 150 studs, ligne de vue), fusée à 70 studs/s au virage limité, verrou rompu par plongeon ou fumée, explosion | `server/Items/confetti_rocket.luau` (à écrire), `Items.LockState`, `Items.Projectile`, `Items.ProjectileUpdate`, `Items.ProjectileEnd` | TM, MC | À faire | — |
| OBJ-15 | Bottes Kangourou : 3 bonds géants (saut × 2,6) en 15 s, contrôle aérien normal, exemption de plausibilité | `server/Items/kangaroo_boots.luau` (à écrire) | TM | À faire | — |
| OBJ-16 | Club Propulseur : coup suivant amplifié (× 1,6), sinon frappe majeure de mêlée, sinon propulsion de l'utilisateur | `server/Items/rocket_club.luau` (à écrire), `BallService` (frappe amplifiée) | TM, MC | À faire | — |
| OBJ-17 | Boule Givrante : lancer en cloche, gel 3 s avec glissade (joueurs, balles, karts), plateforme de glace de 8 s sur l'eau | `server/Items/frost_bomb.luau` (à écrire), `BallService.FreezeBall` | TM, MC | À faire | — |
| OBJ-18 | Nuage Ninja : fumée 6 s, invisibilité 5 s (semi-transparence pour les alliés), rupture et blocage des verrouillages, fin dès que l'utilisateur agit | `server/Items/ninja_smoke.luau` (à écrire) | TM, MC | À faire | — |
| OBJ-19 | Flash Paparazzi : éblouissement de 2,5 s des adversaires tournés vers le flash (visée impossible, vitesse × 0,6) ; mode sans flash à pénalité identique | `server/Items/paparazzi_flash.luau` (à écrire), `EffectsController.IsNoFlash` | TM, MC | À faire | mode sans flash pris en charge par EffectsController (brouillon) |
| OBJ-20 | Nuage Grognon : nuage de 8 s qui dérive vers l'adversaire le plus proche, éclairs annoncés 1 s à l'avance toutes les 2 s | `server/Items/grumpy_cloud.luau` (à écrire), effet `Ring` | TM, MC | À faire | — |
| OBJ-21 | Rail-Fronde : charge de 1 s avec viseur visible de tous, rayon de 140 studs touchant jusqu'à 3 adversaires alignés selon la règle explicite, arrêt sur le décor et sur le premier bouclier | `server/Items/rail_slinger.luau` (à écrire), effet `Beam` | TM, MC | À faire | — |
| OBJ-22 | Méga Burger : géant 8 s (× 2,2), percussion et projection des balles et des adversaires, immunité aux frappes mineures, décor `Breakable` brisé | `server/Items/mega_burger.luau` (à écrire), `Config/Course.BreakableProps` | TM, MC | À faire | — |
| OBJ-23 | Matrice d'interactions écrite : 8 paires exigées et autres situations définies (CDC §9.6) | `docs/MATRICE_INTERACTIONS.md` | AS | En cours | rédigée ; chaque règle reste à prouver (INT-01 à INT-08) |
| INT-01 | Gel / voiturette : conducteur gelé sans direction ni accélération, kart qui glisse 3 s ; kart touché gelé ; passagers gelés restent assis | `frost_bomb`, `VehicleService` (à écrire) | TM | À faire | — |
| INT-02 | Bouclier / laser : bulle détruite et KO sans fort recul | `magnet_shield`, `orbital_beam` (à écrire) | TM | À faire | — |
| INT-03 | Bouclier / railgun : le premier adversaire protégé arrête le rayon, les cibles derrière lui sont épargnées | `magnet_shield`, `rail_slinger` (à écrire) | TM, MC | À faire | — |
| INT-04 | Invisibilité / roquette : aucun verrouillage d'un joueur invisible ; verrou existant rompu, la fusée file droit | `ninja_smoke`, `confetti_rocket` (à écrire) | TM, MC | À faire | — |
| INT-05 | Géant / obstacles : décor `Breakable` brisé et rétabli au trou suivant, géométrie jouable jamais traversée | `mega_burger`, `server/Course/` | TM | À faire | — |
| INT-06 | Mine / allié : alliés et poseur ne déclenchent jamais la mine (surlignée en vert pour eux) ; l'explosion ne touche que les adversaires du poseur | `shroom_mine`, `MatchService.AreAllies` | TM, MC | À faire | — |
| INT-07 | Klaxon / objet : utilisation involontaire d'un objet sensible sélectionné ; frappe prématurée de qui charge | `horn`, `ItemService`, `BallService.ForceShot` | TM, MC | À faire | — |
| INT-08 | Gel / réapparition : toute réapparition retire le gel, la protection empêche un nouveau gel, une balle replacée est dégelée | `frost_bomb`, `SpawnService`, `MovementService` (verrous retirés à la réapparition) | TM | À faire | verrou `Frozen` déjà retiré à la réapparition par MovementService (brouillon) |
| OBJ-24 | Aucun état temporaire ne survit à la fin d'une manche ni à une déconnexion : effets, pièges, projectiles, nuages, plateformes, karts, changement d'échelle (CDC §9.7) | `ItemService.ClearRound`, `ItemService.ClearPlayer`, Troves de manche et de joueur | TM, MC | À faire | test de résidus entre manches : VAL-10 |

## §6 — Les 81 trous et la création des niveaux

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| TRO-01 | Plan des 81 trous : tracés et noms originaux, par, difficulté, signature distincte et raccourcis de chaque trou (CDC §10.1, §10.3) | `docs/PLAN_PARCOURS.md` | AS | En cours | plan rédigé ; à confronter aux données et aux inspections |
| TRO-02 | Côte : 18 trous (îles, plages, ponts, falaises, passages au-dessus de l'eau), par 71 | `shared/Data/Holes/Coast.luau` (à écrire) | AS, TU, SIM, TM | À faire | — |
| TRO-03 | Forêt : 18 trous (arbres, clairières, reliefs, plateformes), par 71 | `Data/Holes/Forest.luau` (à écrire) | AS, TU, SIM, TM | À faire | — |
| TRO-04 | Désert : 18 trous (dunes, canyons, arches, oasis, sable pénalisant), par 71 | `Data/Holes/Desert.luau` (à écrire) | AS, TU, SIM, TM | À faire | — |
| TRO-05 | Neige : 18 trous (glace, pentes, précipices, passages glissants), par 71 | `Data/Holes/Snow.luau` (à écrire) | AS, TU, SIM, TM | À faire | — |
| TRO-06 | Ville : 9 trous (rues, parcs, canaux, ponts, hauteurs, circulation dangereuse), par 36 | `Data/Holes/City.luau` (à écrire) | AS, TU, SIM, TM | À faire | — |
| TRO-07 | Trous d'entraînement ENT-01 (Driving Range) et ENT-02 (tutoriel), hors des 81 (CDC §10.1) | `Data/Holes/Training.luau` (en écriture), `Config/Course.Training` | TU, TM | En cours | chantier « trous » en cours |
| TRO-08 | 81 expériences réellement distinctes : ni copies recolorées, ni graines aléatoires jamais inspectées (CDC §10.3) | comparaison des signatures (`HoleValidator`), aperçus `BuildPreview`, `docs/CATALOGUE_TROUS.md` | AS, TM | À faire | — |
| TRO-09 | Données complètes par trou : ID, nom, biome, par, difficulté, départs équitables, position du trou, limites, checkpoints, zones de récupération, boîtes, obstacles, durée cible, chemins praticables (CDC §10.2) | `shared/Types.luau` (`HoleDef`), `Config/Course.luau`, `CourseService.GetStartPlacements`, `docs/FORMAT_TROUS.md` (à écrire) | AS, TU | En cours | format défini dans `Types.HoleDef` ; guide d'écriture à produire |
| TRO-10 | Trajet normal réalisable sans objet aléatoire indispensable (pentes ≤ 30°, trous ≤ 6 studs ou ponts) ; raccourcis risqués documentés (CDC §10.4) | `shared/Logic/HoleValidator.luau` (à écrire), `Config/Course.Validation`, balles de simulation, `HoleDef.shortcuts` | TU, SIM, TM | En cours | règles chiffrées en configuration ; validateur à écrire |
| TRO-11 | Format de données et outils réutilisables d'assemblage ; génération procédurale stable, inspectable, reproductible et validée (CDC §10.5) | `server/Course/*`, `Config/Course.luau`, `CourseService.BuildPreview` (en écriture) | TU, TM | En cours | constructeur dans le chantier « trous » |
| TRO-12 | Chargement du seul contenu nécessaire et nettoyage de l'ancien niveau (CDC §10.6) | `CourseService.LoadHole`, `CourseService.UnloadHole`, Trove de manche, `Config/Course.MaxPartsPerHole` | TM | En cours | — |
| TRO-13 | Sélection de parcours, mélange de biomes, ordre aléatoire reproductible, playlists de 3, 9, 18 trous ou personnalisées (CDC §10.6) | `shared/Logic/Playlist.luau`, `Config/Match.Playlists`, `Lobby.SetCustomPlaylist` | TU | En cours | module pur écrit sans spec (`Playlist.spec`, VAL-01) |
| TRO-14 | Chacun des 81 trous : validation structurelle et parcours réalisable, inspections et playtests réellement effectués, consignés avec leur particularité et leur état dans le catalogue des 81 trous (CDC §10.7, §17.5) | `HoleValidator`, simulation, `BuildPreview`, Play, `docs/CATALOGUE_TROUS.md` (à produire depuis les données et les validations) | AS, TU, SIM, TM | À faire | — |

## §7 — Direction artistique et personnalisation

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| ART-01 | Univers cartoon low-poly cohérent : couleurs lisibles, silhouettes expressives, objets reconnaissables, vrais décors et accessoires originaux construits par code, aucun placeholder en finition (CDC §11.1) | `server/Course/` (décor, biomes), `Config/Course.luau`, `Config/Items.luau` (pictogramme, couleur), `client/UI/Theme.luau` (en écriture) | TM | En cours | aucune capture du monde possible avant l'intégration de CourseService |
| ART-02 | Effets satisfaisants (particules intégrées, télégraphies) respectant qualité et effets réduits (CDC §11.1) | `client/Effects/Core.luau` (10 effets), `client/Controllers/EffectsController.luau` | TM | En cours | effets écrits, non vus en Play |
| ART-03 | Interface soignée : thème, composants communs, gestion des écrans (CDC §11.1, §13.4) | `client/UI/Theme.luau`, `client/UI/Components/*`, `client/UI/ScreenManager.luau` (en écriture) | TM | En cours | chantier « interface » en cours |
| COS-01 | Avatar compatible avec les animations et les proportions de collision choisies, identique pour tous (R15) (CDC §11.2) | `default.project.json` (`LoadCharacterAppearance`, `AvatarJointUpgrade`, `CharacterAutoLoads`), `SpawnService` (en écriture), `shared/Animations` | TM | En cours | réglages présents dans le fichier construit ; apparitions en écriture |
| COS-02 | Aperçu 3D de la tenue, variantes de couleurs et plusieurs ensembles sauvegardables (3) (CDC §11.2) | `CustomizeController` (à écrire), `Cosmetics.Variant`, `Shop.SetVariant`, `Shop.SaveLoadout`, `Shop.UseLoadout`, `CosmeticService` (à écrire) | TM, SR | À faire | champs et remotes définis |
| COS-03 | Catalogue minimal de 100 cosmétiques réellement équipables, hors recolorations et objets par défaut : 25 têtes/chapeaux/masques, 15 coiffures/visages/lunettes, 20 tenues, 10 paires de chaussures, 15 clubs, 10 balles, 5 effets d'entrée dans le trou (CDC §11.3) | `shared/Cosmetics/Catalog/*.luau` (en écriture), `Cosmetics.spec` | TU, TM | En cours | 5 lots en écriture ; `Cosmetics.spec` échoue tant que le catalogue est incomplet |
| COS-04 | Au moins 8 danses ou émotes avec une animation réelle (procédurale) (CDC §11.3) | `shared/Animations` (bibliothèques), `AnimationController` (en écriture) | TU, TM | En cours | chantier « animations » en cours |
| COS-05 | Cosmétiques = apparence uniquement (mêmes statistiques, collision et portée) ; animations sans contournement des délais de frappe (CDC §11.4) | `Cosmetics/Build.luau`, `Cosmetics.spec` (équité, longueur de club), délais serveur de `BallService` | TU, TM | En cours | règles d'équité codées et testées par `Cosmetics.spec` (catalogue incomplet) |
| COS-06 | Boutique : aperçu, filtres, statut possédé/verrouillé, prix en pièces, condition de déblocage, boutons acheter et équiper fonctionnels (CDC §11.5) | `ShopController` (à écrire), `CosmeticService.Purchase`, `CosmeticService.Equip` (à écrire), `Net/Remotes/Shop.luau` | TM | À faire | contrats réseau définis |
| COS-07 | Sélection visible par les autres joueurs et conservée après reconnexion (CDC §11.5) | `CosmeticService.ApplyAppearance`, `PlayerDataService` | MC, SR | À faire | — |
| COS-08 | Registre sonore de provenance vérifiable (sons du moteur, ProSoundEffects et APMOfficial), chargement vérifié dans Studio (CDC §11.6) | `shared/Config/Sounds.luau`, `docs/MANIFESTE_ASSETS.md` | TM | Fait (preuve : 51 sons chargés avec `PreloadAsync` sur des instances temporaires non parentées, créateur et titre contrôlés, Studio en mode Édition, 12/11/2026) | disponibilité à revérifier après publication ; écoute en situation à faire |
| COS-09 | Aucun AssetId fabriqué ; imports et permissions consignés dans le manifeste ; solution générée localement quand l'upload est indisponible, limites indiquées (CDC §11.6) | tout `src/` (recherche de `rbxassetid`), `docs/MANIFESTE_ASSETS.md`, `Cosmetics/Build.luau`, `shared/Animations` | AS | En cours | au 13/11, `rbxassetid://` n'apparaît que dans `Config/Sounds.luau` (sons vérifiés) ; revue à refaire à la livraison |

## §8 — Progression et sauvegarde

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| PRG-01 | Monnaie gagnée en jouant : calcul des récompenses de fin de partie (classement, équipes, solo, trous terminés, performance plafonnée, total plafonné, jamais négatif) (CDC §12.1) | `Config/Economy.luau`, `Logic/Rewards.luau`, `Progression.spec` | TU | Fait (preuve : `Progression.spec` — « récompense le classement », « équipe gagnante plus que la perdante », « plafonne les bonus et le total », « entier positif ou nul même avec des entrées invalides », en moteur, 12/11/2026) | versement serveur : PRG-02 |
| PRG-02 | Récompenses de fin de partie versées une seule fois par le serveur (`opId = MatchId:UserId`), jamais en Entraînement (CDC §12.1, §12.5) | `RewardService` (à écrire), `PlayerDataService.Transact` | TM, SR | À faire | — |
| PRG-03 | Au moins 30 défis variés (golf, précision, exploration, objets, survie, équipe, véhicules), fonctionnant sans BadgeId : 38 définis (CDC §12.2, §12.3) | `Config/Achievements.luau`, `Locale/*/Achievements.luau`, `Progression.spec` | TU | Fait (preuve : `Progression.spec` — « au moins 30, aux ids uniques », « toutes les catégories exigées », « défis référencés par les cosmétiques », « définitions complètes et textes fr/en », « progression des trois types », en moteur, 12/11/2026) | branchement sur le jeu : PRG-04 |
| PRG-04 | Défis branchés sur les événements de jeu, récompense versée une seule fois (`ach:<id>`), aucune progression récompensée en Entraînement sauf le tutoriel (CDC §12.2, §5.5) | `AchievementService` (à écrire) | TM, MC | À faire | le schéma de profil doit accepter des clés de statistiques arbitraires et le champ `sets` |
| PRG-05 | Badges de plateforme raccordés plus tard à de vrais BadgeId (champ `badgeId`, jamais inventé) (CDC §12.3) | `Config/Achievements.luau` (`badgeId`), `AchievementService` | SR | À faire | nécessite une expérience publiée |
| SAV-01 | Sauvegarde de la monnaie, de l'inventaire cosmétique, des équipements, des succès, des statistiques utiles et des préférences (CDC §12.4) | `PlayerDataService`, schéma de profil (en écriture) | TU, TM, SR | En cours | chantier « sauvegarde » en cours |
| SAV-02 | Achats et récompenses décidés côté serveur, non duplicables (identifiants d'opération), reconnexions traitées de façon cohérente (CDC §12.5) | `PlayerDataService.Transact` (en écriture) | TU, TM, SR | En cours | — |
| SAV-03 | Schéma versionné et migrations (CDC §12.6) | schéma de profil (en écriture) | TU | En cours | — |
| SAV-04 | Accès concurrents (verrou de session), reprises bornées, limites de requêtes, sauvegarde de fermeture au mieux (CDC §12.6) | adaptateur DataStore (en écriture) | TU, SR | En cours | comportement réel prouvable seulement sur service Roblox (SAV-07) |
| SAV-05 | Échec de chargement : profil existant jamais écrasé par un profil vide, état honnête affiché, transactions dangereuses bloquées (CDC §12.7) | `PlayerDataService` (en écriture), bandeau d'état (interface) | TU, TM | En cours | erreurs à simuler (VAL-04) |
| SAV-06 | Données de développement et de test séparées des données réelles ; adaptateur mémoire identifié comme non persistant (`PersistentData`, `DataStatus = "Memory"`, bandeau) (CDC §12.8) | `PlayerDataService`, `GameState.PersistentData`, HUD | AS, TM | En cours | — |
| SAV-07 | DataStore réel prouvé : lecture, écriture, verrou et reprise après reconnexion sur une place publiée avec accès API (CDC §12.6) | `PlayerDataService` et service DataStore | SR | À faire | exige publication et « Activer l'accès Studio aux services API » (action de l'utilisateur) |
| SAV-08 | Aucune mécanique pay-to-win ni boutique Robux nécessaire (CDC §12.9) | `Config/Economy.luau`, `Net/Remotes/Shop.luau` | AS | En cours | au 13/11, aucune référence à `MarketplaceService` dans `src/` ; revue finale à faire |

## §9 — Salons, interface et accessibilité

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| SAL-01 | Accueil jouable avec entraînement, boutique, personnalisation, sélection du mode et accès aux parties (CDC §13.1) | `server/Course/` (accueil), `LobbyService`, `MenuController` (en écriture) | TM | En cours | aucun accueil visible aujourd'hui (CDC §20.2) |
| SAL-02 | Parties publiques et parties privées entre amis (serveur réservé, `TeleportAsync`, reprises) documentées et testées séparément (CDC §13.2) | `LobbyService` (`Lobby.CreatePrivate`), `Config/Match.Private`, `README.md` § Configuration restante | AS, SR | À faire | exige une expérience publiée ; désactivé en Studio |
| SAL-03 | L'hôte configure parcours, équipes, durée, vent, vitesse, objets et interactions entre balles ; réglages validés clé par clé et jamais modifiés au milieu d'un trou ; sélection équilibrée des équipes (CDC §13.3) | `Config/Match.SettingRules`, `Lobby.SetSetting`, `LobbyService`, `MatchService` (copie figée), `Logic/Scoring.balanceTeams` | TU, TM, MC | En cours | règles de validation écrites ; services en écriture |
| IHM-01 | Menus : accueil, préparation du salon, réglages, boutique, personnalisation, options (CDC §13.4) | `UIController`, `client/UI/ScreenManager.luau`, `MenuController` (en écriture) | TM | En cours | — |
| IHM-02 | HUD de jeu : visée, jauge de puissance, angle et type de frappe, vent, par, compteur de coups, chronomètre et prolongation (CDC §13.4) | `HUDController`, `GolfAimController` (en écriture) | TM | En cours | — |
| IHM-03 | Inventaire et effets actifs avec temps restant (CDC §13.4) | `InventoryController` (à écrire), attributs `Inventory`, `ActiveEffects` | TM | À faire | dépend d'ItemService |
| IHM-04 | Classement en direct, annonces de KO, résultats du trou et podium (CDC §13.4) | `HUDController`, `NotificationController` (en écriture), `Match.HoleResults`, `Match.Podium`, `Combat.KO` | TM, MC | En cours | — |
| IHM-05 | Les boutons réalisent les actions annoncées ; aucun faux écran de succès (succès affiché après confirmation serveur) ; état des données honnête (CDC §13.4) | interface, `Shop.Result`, `Items.Feedback`, `Data.Sync` | TM | En cours | à vérifier écran par écran |
| IHM-06 | Aucun texte en dur : toute l'interface en français via `Locale`, anglais disponible (CDC §2.3) | `client/UI/*`, `Locale/*` | AS, TU | En cours | contrôle statique des textes de l'interface à faire à son intégration |
| ACC-01 | Navigation manette de tous les menus (focus `GuiService.SelectedObject`) (CDC §13.5) | `client/UI/ScreenManager.luau` (en écriture), `InputController` | TM, AP | En cours | aucune manette physique constatée ; émulateur de manette de Studio possible |
| ACC-02 | Commandes tactiles confortables (au moins 44 px, emplacements fixes, masquées dans les menus) (CDC §13.5) | `InputController` (boutons tactiles), interface | TM, AP | En cours | aucun appareil mobile physique |
| ACC-03 | Caméra non gênante : zoom borné (4–90), pas d'obstruction pendant la visée, secousses réglables (CDC §13.5) | `client/Controllers/CameraController.luau`, `default.project.json` | TM | En cours | brouillon chargé, non vu en Play |
| ACC-04 | Textes lisibles et contrastes suffisants (CDC §13.5) | `client/UI/Theme.luau` (en écriture) | AS, TM | En cours | — |
| ACC-05 | Indicateurs d'équipe autres que la couleur (nom, pictogramme ou motif) (CDC §5.3, §13.5) | HUD, plaques de nom, classement (à écrire) | TM | À faire | — |
| ACC-06 | Réglages sonores, sensibilité, vibrations (si disponibles), secousses de caméra, réduction des effets et mode sans flash conservant une pénalité de jeu équivalente (CDC §9.5, §13.5) | `SettingsController` (à écrire), `EffectsController` (volumes par catégorie, `IsReduced`, `IsNoFlash`), `CameraController.Shake` | TM, AP | En cours | volumes, secousses, effets réduits et sans flash lus par les brouillons ; SettingsController et sensibilité à écrire |
| COM-01 | Communications natives : chat filtré (`TextChatService`) et vocal seulement si la plateforme et le compte l'autorisent ; jeu entièrement jouable sans vocal ; aucun système parallèle (CDC §13.6) | `default.project.json` (`TextChatService`), revue du code | AS, SR | En cours | aucun système de chat maison dans `src/` au 13/11 ; filtrage et vocal à vérifier sur service réel |

## §10 — Architecture et performances

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| ARC-01 | Luau typé (`--!strict` partout), modules aux responsabilités claires, séparation serveur/client/partagé, un seul Script et un seul LocalScript d'amorçage, aucune dépendance inutile (CDC §14.2) | `src/**/*.luau`, `default.project.json`, `server/init.server.luau`, `client/init.client.luau` | AS | En cours | 65 fichiers sur 65 commencent par `--!strict` au 13/11 ; à vérifier à chaque intégration |
| ARC-02 | Services serveur et contrôleurs client prévus par l'architecture (Match, Lobby, Course, Ball, Combat, Items, Vehicles, PlayerData, Rewards, Cosmetics, Achievements, NetworkValidation ; Input, Camera, GolfAim, HUD, Shop, Customize, Effects…) (CDC §14.3) | `server/Services/`, `client/Controllers/` | AS, TM | En cours | écrits : 5 services sur 16 (Collision, Combat, Movement, NetworkValidation, Dev) et 3 contrôleurs (Input, Camera, Effects) |
| ARC-03 | Démarrage en deux phases (`Init` puis `Start`), priorités, isolement des échecs (CDC §14.4) | `server/init.server.luau`, `client/init.client.luau` | TM | En cours | démarrage serveur et client vérifié en Play solo à l'étape 1 ; à refaire avec tous les modules |
| ARC-04 | Tous les modules du dépôt se chargent sans erreur dans Studio | 55 modules de jeu (hors 8 modules de tests) | TM | Fait (preuve : `require` des 55 modules en mode Édition, 0 échec, 13/11/2026 21 h 40, `docs/ETAT_REPRISE.md`) | ne prouve pas le fonctionnement en Play ; à refaire à chaque intégration |
| ARC-05 | Paramètres de gameplay séparés du code ; données et décisions sensibles conservées sur le serveur (CDC §14.6, §15) | `shared/Config/*`, `ServerScriptService`, `ServerStorage` | AS | En cours | — |
| ARC-06 | Connexions, tâches, contraintes, projectiles et effets nettoyés après utilisation (Troves de manche, joueur, personnage, effet) (CDC §14.4) | `shared/Util/Trove.luau`, services | TU, TM | En cours | `Util.spec` couvre Trove ; absence de fuites à mesurer (VAL-10) |
| PRF-01 | Objets physiques, effets simultanés, calculs inutiles et messages réseau limités ; plusieurs niveaux de qualité (`Low`, `Medium`, `High`) et effets réduits (CDC §16.2, §16.3) | `Config/Course.MaxPartsPerHole`, `Net/Remotes` (`Effects.Burst`, `Items.ProjectileUpdate`), `EffectsController.GetQuality`, services | AS, TM | En cours | aucune mesure de partie ; réglage de qualité joueur à écrire |
| PRF-02 | Mesures des temps de frame, de la mémoire, des instances et du réseau avec le matériel disponible (CDC §16.4) | `DevService` (`DevBridge` « perf »), outils de Studio | TM, MC | En cours | outil écrit ; aucune mesure de partie complète |
| PRF-03 | 60 FPS sur le PC de référence (AMD Ryzen 7 7435HS, RTX 4060 Laptop, 23,7 Go, Windows 11), mesuré (CDC §16.1) | client Studio puis client publié | TM, SR | À faire | jamais annoncé sans mesure |
| PRF-04 | 30 FPS sur un appareil mobile de référence, mesuré ; un émulateur d'écran ne prouve pas les performances d'un téléphone (CDC §16.1) | appareil mobile | AP | À faire | aucun appareil mobile physique disponible |

## §11 — Exécution par étapes

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| ETP-01 | Étape 1 : environnement examiné, cahier des charges et matrice de couverture écrits (CDC §21) | `docs/ETAT_REPRISE.md`, `docs/CAHIER_DES_CHARGES.md` v1.1, ce document | AS | En cours | cahier et matrice complétés le 13/11/2026 ; relecture par l'intégrateur |
| ETP-02 | Étape 2 : partie complète avec un trou, physique fiable, HUD, score et retour à l'accueil | chantiers balle, partie, salon, visée, trous, interface (en cours) | TM | En cours | critère de sortie : Play solo complet sans erreur |
| ETP-03 | Étape 3 : multijoueur, états de partie et commandes validés sur les supports visés | — | MC, TM, AP | À faire | — |
| ETP-04 | Étapes 4 à 7 menées sans réduire le périmètre final : objets, véhicules et modes ; biomes et 81 trous ; personnalisation, boutique, progression et sauvegarde ; présentation, animations, audio, accessibilité et optimisation | registres, sons, effets, animations, cosmétiques et sauvegarde amorcés | TM, MC | En cours | objets, véhicules et 81 trous non commencés |
| ETP-05 | Étape 8 : revue complète, correction des défauts et preuves finales | `docs/RAPPORT_FINAL.md` (à écrire) | AS, TM, MC | À faire | — |
| ETP-06 | Vérification après chaque étape, enchaînement sans arrêt après un plan, délégation à des sous-agents avec responsabilités claires et vérification de l'intégration ; état de reprise tenu à jour ; limitations décrites sans être déclarées accomplies | `docs/ETAT_REPRISE.md` (décisions, fichiers, tests, problèmes, prochaine action, propriété des fichiers) | AS | En cours | processus continu |

## §12 — Validation et critères d'acceptation

Les preuves propres à chaque fonctionnalité sont suivies dans leurs sections (physique PHY, objets OBJ et INT, achats et
sauvegarde COS et SAV, validation de chacun des 81 trous TRO-14). Cette section suit la campagne de tests exigée par la
demande.

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| VAL-01 | Tests unitaires du score, des transitions et des playlists (CDC §6.6, §17.2) | `tests/Specs/Scoring.spec.luau`, `MatchStateMachine.spec.luau`, `Playlist.spec.luau` (à écrire) | TU | À faire | modules purs prêts à tester |
| VAL-02 | Tests unitaires des récompenses et des définitions réseau (CDC §17.2) | `tests/Specs/Progression.spec.luau`, `tests/Specs/NetDefinitions.spec.luau` | TU | Fait (preuve : `Progression.spec` et `NetDefinitions.spec` en moteur, série d'intégration du 12/11/2026) | à relancer à chaque modification |
| VAL-03 | Tests des achats : prix, possession, condition de déblocage, double achat, solde insuffisant (CDC §17.2) | spec des transactions de boutique (à écrire), `CosmeticService` | TU, TM | À faire | — |
| VAL-04 | Tests de la sauvegarde : schéma, migrations, idempotence, erreurs de sauvegarde simulées (CDC §17.2) | specs du schéma et des transactions (en écriture) | TU | En cours | chantier « sauvegarde » en cours |
| VAL-05 | Requêtes client invalides, répétées ou trop rapides rejetées en jeu et comptées (CDC §17.3) | `Net`, `NetworkValidation`, `DevBridge` « netStats » | TM, MC | À faire | — |
| VAL-06 | Tests des interactions d'objets (règles pures puis en moteur) (CDC §17.2, §17.3) | specs des règles d'objets (à écrire), scénarios de Play | TU, TM | À faire | — |
| VAL-07 | Sessions solo, puis deux clients, puis jusqu'à huit clients : partie entière sur plusieurs trous, résultats, récompense unique et retour à l'accueil (CDC §17.3) | Play solo (MCP), « Serveur et clients », `StudioTestService:ExecuteMultiplayerTestAsync` | TM, MC | À faire | multi-clients par code à essayer via le contexte plugin |
| VAL-08 | Départs simultanés, arrivée tardive, déconnexion, réapparition, changement d'hôte et fin du délai (CDC §17.3) | scénarios multi-clients | MC | À faire | — |
| VAL-09 | Écrans PC et mobile, navigation manette, effets réduits et lisibilité en équipe (CDC §17.3) | interface | TM, AP | À faire | aucun appareil mobile physique |
| VAL-10 | Plusieurs manches successives : fuites, objets résiduels et dégradation progressive (CDC §17.6) | instances, Troves, mémoire, `DevBridge` | TM | À faire | — |
| VAL-11 | Rapports distinguant analyse statique, test unitaire, simulation, test moteur, multi-clients, appareil physique et service réel ; aucune catégorie n'en remplace une autre (CDC §17.1) | ce document, `docs/ETAT_REPRISE.md`, rapport final | AS | En cours | catégories définies et appliquées dans cette matrice |
| VAL-12 | Test séparé du mode 16 joueurs, réalisable dans l'environnement disponible ; aucune validation à 16 clients inventée dans un outil limité à 8 (CDC §17.4) | serveur publié (16 comptes réels), simulation de charge | SR, SIM | À faire | impossible dans Studio (8 clients au plus) |
| VAL-13 | Définition de « terminé » appliquée ; distinction « implémenté », « testé », « prêt à publier » ; statut explicite pour toute fonctionnalité ou carte non vérifiée (CDC §18) | cette matrice, `docs/CATALOGUE_TROUS.md`, rapport final | AS | En cours | — |

## §13 — Livrables

Le catalogue des 81 trous est suivi en TRO-14.

| ID | Exigence | Fichiers / systèmes | Preuve attendue | Résultat | Limite restante |
| --- | --- | --- | --- | --- | --- |
| LIV-01 | Projet source complet, configurations et dépendances reproductibles ; géométrie, UI et modèles inclus ou générés de manière reproductible, sans étape cachée de construction manuelle des 81 niveaux (CDC §1.4, §19) | `src/`, `default.project.json`, `scripts/`, `tools/` (installé par script), `server/Course/`, `client/UI/`, `shared/Cosmetics/` | AS, TM | En cours | contenu incomplet |
| LIV-02 | Fichier `.rbxlx` final réellement généré, ou procédure précise de construction et d'import vérifiée (CDC §19) | `scripts/build.ps1` → `build/` | AS, TM | En cours | chaîne de construction prouvée (ENV-04) ; place finale à générer |
| LIV-03 | README en français : installation, ouverture, synchronisation, lancement, tests, configuration Roblox restante (CDC §19) | `README.md` | AS | En cours | rédigé ; « Lancer une partie » décrit un comportement pas encore disponible (accueil non construit) |
| LIV-04 | Documents d'architecture et de règles de gameplay (CDC §19) | `docs/ARCHITECTURE.md`, `docs/REGLES_SCORE.md`, `docs/CAHIER_DES_CHARGES.md` | AS | En cours | documents vivants, à aligner sur l'implémentation |
| LIV-05 | Registre des 17 objets (CDC §19) | `docs/REGISTRE_OBJETS.md` (+ `Config/Items.luau`) | AS | En cours | rédigé ; à garder synchronisé avec la configuration |
| LIV-06 | Catalogue des cosmétiques (CDC §19) | `docs/CATALOGUE_COSMETIQUES.md` (à produire depuis le registre) | AS | À faire | — |
| LIV-07 | Manifeste des assets (CDC §11.6, §19) | `docs/MANIFESTE_ASSETS.md` | AS | En cours | sons consignés ; à compléter à chaque import |
| LIV-08 | Matrice exigence → fichiers/systèmes → preuve → résultat → limite restante (CDC §19) | `docs/MATRICE_COUVERTURE.md` | AS | En cours | v1.0 du 13/11/2026, à tenir à jour |
| LIV-09 | Rapport final daté : contenu livré, commandes exécutées, résultats, captures, problèmes restants, démarches avant publication ; distinction « implémenté », « testé », « prêt à publier » (CDC §18, §19) | `docs/RAPPORT_FINAL.md` (à écrire) | AS | À faire | — |

---

## Comment mettre à jour

1. **Après chaque preuve obtenue**, remplacer le résultat par
   `Fait (preuve : <test, scénario ou constat>, <date>, <résultat chiffré>)` **uniquement** si toutes les catégories de
   la colonne « Preuve attendue » sont couvertes. Sinon, laisser « En cours » et décrire la preuve partielle dans
   « Limite restante » (exemple : « TU vert le 20/11 ; TM à faire »).
2. **Passer de « À faire » à « En cours »** dès qu'un brouillon est dans le dépôt ou qu'un chantier est lancé ; indiquer
   dans « Fichiers / systèmes » les chemins réels et retirer les mentions « (à écrire) » devenues fausses.
3. **Régression** (test de nouveau en échec, fonctionnalité cassée) : la ligne repasse à « En cours » avec le motif et la date.
4. **Ne jamais déduire une preuve d'une catégorie plus faible** : un test unitaire ne prouve pas un comportement
   multi-clients ; l'adaptateur mémoire ne prouve pas DataStore ; le simulateur d'appareil ne prouve pas un téléphone ;
   un test à 8 clients ne prouve pas 16 joueurs.
5. **Preuves reproductibles** : citer la commande (ex. `require(game.ServerStorage.Tests.Runner).run("Items")`), le
   scénario de Play, la capture ou le fichier de mesure, avec la date et la version de Studio si elle a changé.
6. **Nouvelle exigence** (révision du cahier des charges) : ajouter une ligne dans la section correspondante avec le
   prochain numéro libre du préfixe ; **ne jamais réutiliser ni renuméroter un identifiant** ; une exigence abandonnée
   est barrée (`~~texte~~`) avec la référence de la révision du cahier.
7. **Recompter la synthèse** après chaque modification (PowerShell, depuis la racine du dépôt) :

   ```powershell
   $rows = Get-Content -Encoding UTF8 docs\MATRICE_COUVERTURE.md | Where-Object { $_ -match '^\| [A-Z]{3}-\d{2} \|' }
   $rows.Count                                                     # lignes
   ($rows | Where-Object { $_ -match '\| Fait \(preuve' }).Count    # Fait
   ($rows | Where-Object { $_ -match '\| En cours \|' }).Count      # En cours
   ($rows | Where-Object { $_ -match '\| À faire \|' }).Count       # À faire
   ```

8. **Mettre à jour l'en-tête** (version, date, nombre de lignes) et signaler les changements dans `docs/ETAT_REPRISE.md`.

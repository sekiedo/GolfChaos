# Règles de score — Golf Chaos

| Élément | Valeur |
| --- | --- |
| Version | 1.1 — 13/11/2026 |
| Exigences | `docs/SPEC_DEMANDE.md` §3 (boucle, modes, score), §9 (salon), §12 (tests) ; `docs/CAHIER_DES_CHARGES.md` §4–6 |
| Valeurs | `src/shared/Config/Scoring.luau` (score) et `src/shared/Config/Match.luau` (durées, AFK, salon, playlists) |
| Calcul | `src/shared/Logic/Scoring.luau` (fonctions pures), appliqué par `src/server/Services/MatchService.luau` |
| Tests | `src/tests/Specs/Scoring.spec.luau` (barème, bonus, plafond, égalités, équipes déséquilibrées, prolongation, solo) |

Cette spécification a été écrite **avant** l'implémentation. Tout nombre cité ici vit dans la configuration :
changer un équilibrage = modifier `Config/Scoring.luau` (ou `Config/Match.luau`), mettre ce document à jour,
puis relancer les tests.

---

## 1. Principes

1. **Le serveur décide de tout.** Ordre d'arrivée, coups, distances, temps et points sont mesurés par le serveur
   (`BallService.Holed`, horloge `workspace:GetServerTimeNow()`). Aucun score, aucune récompense ne vient du client.
2. **La course prime, le golf récompense.** Le barème d'arrivée est la source principale de points ; les bonus de
   performance golfique sont cumulables mais **plafonnés** pour ne jamais dépasser la valeur d'une victoire.
3. **Égalités déterministes.** Chaque égalité possible a une règle écrite ; une égalité parfaite donne un rang partagé.
4. **Rien ne bloque.** Chronomètre, prolongation, plafond de coups, AFK, abandon et déconnexion garantissent qu'un trou
   se termine toujours ; chaque phase a une durée maximale (`Config/Match.Durations`).

---

## 2. Déroulement d'un trou et durées

| Phase | Durée (défaut) | Sécurité | Remarque |
| --- | --- | --- | --- |
| `Preparing` | jusqu'au lancement | 240 s puis retour à l'accueil | départ par l'hôte, ou 3 s après que tous les participants sont prêts |
| `Loading` | ≥ 1,5 s | 25 s | construction du trou, placement équitable, `RoundId` + 1 |
| `HoleIntro` | 5 s | — | nom, par, particularité |
| `Countdown` | 3 s | — | joueurs immobilisés, frappes refusées |
| `Playing` | chronomètre §3 | 900 s | fin anticipée quand plus personne n'est en jeu |
| `HoleEnd` | 3 s | — | résultats figés, objets/véhicules/balles retirés |
| `HoleResults` | 8 s | — | tableau du trou et classement provisoire |
| `Podium` | 12 s | — | classement final, récompenses, puis retour à l'accueil |

---

## 3. Chronomètre du trou et prolongation

### 3.1 Durée limite

```
limite = clamp(targetTime × timeScale × Facteur, Min, Max)
```

| Paramètre | Valeur | Source |
| --- | --- | --- |
| `targetTime` | durée cible du trou pour un joueur moyen (donnée du trou) ; **90 s** si absente ou invalide | `HoleDef.targetTime`, `HoleTime.DefaultTargetTime` |
| `timeScale` | réglage d'hôte, 0,5 à 2 | `MatchSettings.timeScale` |
| Facteur | **2** | `HoleTime.Factor` |
| Min / Max | **45 s / 600 s** | `HoleTime.Min`, `HoleTime.Max` |

Exemples (`timeScale` = 1) : par 3 de 60 s → 120 s ; par 4 de 90 s → 180 s ; par 5 de 130 s → 260 s.
La **durée de référence** d'un trou (bonus de vitesse, §5.5) est `targetTime × timeScale`, sans le facteur.

### 3.2 Prolongation déclenchée par la première arrivée

Dès que **le premier joueur** rentre sa balle, le temps restant est ramené dans une fenêtre de prolongation :

```
restant = clamp(restant, OvertimeMin × timeScale, OvertimeMax × timeScale)      -- par défaut [20 s ; 45 s]
```

- S'il restait plus de 45 s, le trou se termine 45 s après la première arrivée (rythme préservé).
- S'il restait moins de 20 s, le trou est **prolongé** à 20 s (le deuxième joueur a toujours une chance).
- La prolongation n'a lieu **qu'une fois** par trou ; les arrivées suivantes ne la modifient pas.
- Elle ne s'applique que s'il reste au moins un autre joueur en jeu (sinon le trou se termine aussitôt).
- `GameState.OvertimeEndsAt` et `GameState.PhaseEndsAt` publient la nouvelle échéance ; annonce `match.announce.overtime`.
- Mode Solo : sans objet (un seul participant ; le trou se termine à son arrivée).

Exemples (limite 180 s) : première arrivée à 70 s → fin à 115 s ; première arrivée à 170 s → fin à 190 s.

### 3.3 Fin de la phase `Playing`

`Playing` se termine dès que **plus aucun participant n'est en jeu** sur le trou (tous arrivés, ont abandonné,
sont AFK, ont atteint le plafond de coups ou sont déconnectés), ou à l'échéance du chronomètre (prolongation incluse).
La vérification de fin est différée à la fin de l'image serveur : deux arrivées de la même image sont toutes deux
enregistrées. Une sécurité absolue (`Durations.PlayingMax` = 900 s) borne la phase quoi qu'il arrive.

---

## 4. Statuts de fin de trou

| Statut (`HoleResult.status`) | Cause | Points | Bonus | Coups retenus au classement | Trou « actif » (récompenses) |
| --- | --- | --- | --- | --- | --- |
| `Finished` | balle rentrée (décision serveur) | barème d'arrivée | oui | coups réels | oui (au moins un coup accepté) |
| `TimeOut` | chronomètre écoulé avant d'arriver (« DNF ») | 0 | non | max(coups, plafond) | si au moins un coup accepté |
| `Forfeit` | abandon volontaire (`Match.Forfeit`) **ou** plafond de coups atteint (motif `strokeCap`) | 0 | non | max(coups, plafond) | si au moins un coup accepté |
| `AFK` | inactivité prolongée (§9.1) | 0 | non | max(coups, plafond) | si au moins un coup accepté |
| `Disconnected` | joueur parti pendant le trou | 0 | non | max(coups, plafond) | non pertinent (joueur absent) |

« Coups » = coups joués + pénalités (eau, hors limites, balle bloquée), tels que comptés par `BallService`.
Le motif éventuel est transmis dans le champ `reason` du résultat (`"strokeCap"`, `"voluntary"`, `"timeout"`...).

### 4.1 Plafond de coups (abandon automatique)

```
plafond = clamp(par + 7, 10, 14)
```

| Par | 2 | 3 | 4 | 5 | 6 |
| --- | --- | --- | --- | --- | --- |
| Plafond | 10 | 10 | 11 | 12 | 13 |

- Le coup numéro `plafond` est encore autorisé ; au-delà, le serveur refuse toute frappe.
- Si la balle s'immobilise sans être rentrée alors que le compteur a atteint le plafond (pénalités comprises),
  le joueur **abandonne automatiquement** : statut `Forfeit`, motif `strokeCap`, annonce `match.announce.strokeCap`.
  Il devient spectateur intangible du trou comme après un abandon.
- Raison du choix : un débutant ne peut pas bloquer un trou indéfiniment ; environ le double du par.

### 4.2 Coups retenus pour le départage

- Trou terminé : coups réels (au moins 1).
- Trou non terminé : `max(coups, plafond du trou)` — ne pas finir n'est jamais meilleur que finir.
- Trou manqué par un joueur arrivé en cours de partie : plafond du trou (aucun avantage à arriver tard).

---

## 5. Mode Chacun pour soi

### 5.1 Barème d'arrivée

| Rang d'arrivée | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 à 16 | non arrivé |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Points | **12** | **9** | **7** | **5** | **4** | **3** | **2** | **1** | **1** | **0** |

- Écart marqué en tête (gagner un trou vaut 3 points de plus que la 2e place) ; tout joueur qui termine marque au
  moins 1 point (motivation à finir même dernier) ; 9e à 16e : 1 point (architecture 16 joueurs).

### 5.2 Arrivées simultanées

Les arrivées traitées pendant **la même image serveur** (compteur incrémenté à chaque `RunService.PreSimulation`)
**partagent le meilleur rang** ; l'arrivée suivante prend le rang « nombre d'arrivées précédentes + 1 »
(classement 1, 1, 3). Les joueurs à égalité reçoivent tous les points du rang partagé et comptent tous un trou gagné
s'ils partagent le rang 1.

### 5.3 Bonus de performance golfique (par rapport au par)

Une seule catégorie s'applique : la meilleure atteinte.

| Résultat | Condition (coups, pénalités comprises) | Bonus | Identifiant |
| --- | --- | --- | --- |
| Trou en un | 1 coup | **+6** | `holeInOne` |
| Albatros | par − 3 ou mieux (hors trou en un) | **+5** | `albatross` |
| Eagle | par − 2 | **+4** | `eagle` |
| Birdie | par − 1 | **+2** | `birdie` |
| Par | par | **+1** | `par` |
| Bogey ou pire | par + 1 ou plus | 0 | — |

### 5.4 Coup rentré de loin

**+2** (`longShot`) si le coup qui rentre la balle part d'au moins **40 studs** du trou (distance horizontale mesurée
par le serveur, `info.fromDistance` de `BallService.Holed`). Les putts ne comptent pas par défaut
(`LongShot.CountPutts = false`), par cohérence avec le défi « Tir de sniper » (`Config/Achievements`, 40 studs hors putt).

### 5.5 Bonus de vitesse (optionnel, activé par défaut)

**+1** (`speed`) si le joueur termine en au plus **50 %** de la durée de référence (`targetTime × timeScale`).
Désactivable (`Speed.Enabled`). Rare par construction : il récompense la maîtrise sans encourager à bâcler.

### 5.6 Cumul et plafond

- **Cumulables** : catégorie par rapport au par + coup rentré de loin + vitesse.
- **Plafond par trou** : la somme des bonus est limitée à **8** points (`BonusCap`), soit les deux tiers d'une
  victoire : la course reste le critère principal.
- Bonus uniquement pour un trou **terminé** (statut `Finished`).

### 5.7 Points du trou

```
points = barème(rang) + min(catégorie + loin + vitesse, 8)          (0 si le trou n'est pas terminé)
```

| Situation | Arrivée | Catégorie | Loin | Vitesse | Bonus retenu | Total |
| --- | --- | --- | --- | --- | --- | --- |
| 1er, birdie (par 4 en 3), rentré de 12 studs, 50 s (référence 90 s) | 12 | +2 | 0 | 0 | 2 | **14** |
| 2e, par | 9 | +1 | 0 | 0 | 1 | **10** |
| 1er, trou en un (par 3) depuis 120 studs en 20 s (référence 60 s) | 12 | +6 | +2 | +1 | 9 → **8** | **20** |
| 3e, bogey | 7 | 0 | 0 | 0 | 0 | **7** |
| 4e, eagle (par 5 en 3), chip rentré de 45 studs | 5 | +4 | +2 | 0 | 6 | **11** |
| Chronomètre écoulé avant d'arriver | 0 | — | — | — | 0 | **0** |

Maximum théorique par trou : 12 + 8 = 20 points.

### 5.8 Classement de la partie et départage

Classement par :

1. **points totaux** (décroissant) ;
2. **trous gagnés** : nombre de trous terminés au rang 1, rang partagé compris (décroissant) ;
3. **coups totaux retenus** (§4.2) (croissant) ;
4. **birdies ou mieux** : trous terminés à par − 1 ou mieux, trou en un compris (décroissant) ;
5. égalité parfaite : **rang partagé** (1, 1, 3) ; l'ordre d'affichage entre ex æquo (nom puis UserId) n'a aucun effet.

Un joueur qui quitte le serveur pendant la partie est **retiré du classement final** (ses résultats de trous restent
affichés dans les tableaux déjà envoyés) : le podium ne contient que les participants présents.

---

## 6. Mode Équipes rouge / bleue

### 6.1 Composition

- Chaque participant choisit `Red`, `Blue` ou `Auto` (`Lobby.SetTeam`) ; l'hôte peut **équilibrer**
  (`Lobby.BalanceTeams`) : attribution alternée Rouge, Bleu, Rouge… dans l'ordre d'arrivée sur le serveur
  (déterministe), qui remplace les choix existants.
- Au lancement : les choix explicites sont respectés ; chaque `Auto` rejoint l'équipe la moins nombreuse (Rouge en
  cas d'égalité), dans l'ordre d'arrivée ; avec au moins 2 participants, aucune équipe n'est laissée vide : le
  dernier arrivé de l'équipe pleine change d'équipe, en priorité un joueur `Auto`.
- Les équipes **déséquilibrées** sont permises et traitées par le ratio d'arrivées (§6.2).
- Arrivée tardive acceptée : le joueur rejoint l'équipe la moins nombreuse (Rouge en cas d'égalité).
- Instances `Team` « Rouge » et « Bleu » créées dans le service Teams pendant la partie (`AutoAssignable = false`),
  attribut joueur `Team` = `"Red"` / `"Blue"`. L'interface affiche aussi le **nom** de l'équipe (indicateur autre
  que la couleur).

### 6.2 Point d'équipe par trou

`taille` = membres de l'équipe participant au trou **au départ** (un membre déconnecté pendant le trou reste compté :
partir ne peut pas avantager son équipe). `ratio = arrivées / taille` (comparé sans arrondi : produits croisés).

1. L'équipe au **ratio d'arrivées** le plus élevé marque **1 point** d'équipe ;
2. ratios égaux : l'équipe avec le plus d'**arrivées absolues** ;
3. encore égales : la **moyenne de coups des joueurs arrivés** la plus basse ;
4. encore égales (ou aucune arrivée des deux côtés) : **aucun point**.

| Rouge | Bleu | Décision |
| --- | --- | --- |
| 3/4 = 0,75 | 2/4 = 0,50 | Rouge (ratio) |
| 2/3 = 0,67 | 3/5 = 0,60 | Rouge (ratio, malgré moins d'arrivées) |
| 2/4 = 0,50 | 1/2 = 0,50 | Rouge (arrivées absolues 2 > 1) |
| 2/4, coups 3 et 4 (moy. 3,5) | 2/4, coups 4 et 4 (moy. 4) | Rouge (moyenne de coups) |
| 1/2, 4 coups | 1/2, 4 coups | aucun point |
| 0/3 | 0/2 | aucun point |

- Les points individuels (barème §5) sont calculés et affichés (meilleur joueur), mais seul le point d'équipe décide.
- Fin de partie : l'équipe au plus grand total gagne ; totaux égaux = **match nul** (`Draw`).
- **Alliés** : jamais de KO, de recul ni d'effet d'objet entre alliés (`MatchService.AreAllies`) ; le tir ami
  (`friendlyFire`) est ignoré en mode Équipes.

---

## 7. Mode Solo

- **Un seul participant** : l'hôte s'il participe, sinon le participant présent depuis le plus longtemps ; les
  autres joueurs regardent.
- Score = **coups totaux par rapport au par total** (ex. « +2 », « −1 ») et **temps total** (somme des temps d'arrivée).
  Trou non terminé : coups = max(coups, plafond du trou), temps = durée limite du trou.
- Pas de barème d'arrivée ni de prolongation.
- **Record personnel par trou** (`data.stats.bestSolo[holeId] = { strokes, time }`, via `PlayerDataService.Update`) :
  meilleur = moins de coups, puis temps plus court ; mis à jour uniquement pour un trou terminé ; annonce
  `match.announce.soloBest`.

---

## 8. Entraînement

- **Aucun score, aucune pièce.** Les balles d'entraînement de l'accueil (`Lobby.RequestTraining`, Driving Range ou
  tutoriel) ne comptent jamais : frappes autorisées seulement pendant une session d'entraînement en phase `Lobby`,
  balles retirées dès que le salon passe en préparation, compteur de coups remis à zéro à chaque chargement de trou.
- Le mode de partie `Training` déroule la boucle complète (essais de trous, objets, voiturettes) **sans points ni
  récompenses** : `RewardService` n'est pas appelé.
- Seule exception économique : la récompense **unique** du tutoriel (défi `ach_tutorial`, versé une fois par
  `AchievementService`).

---

## 9. Situations particulières

### 9.1 AFK

- Un participant en jeu est déclaré AFK après **60 s** (`Config/Match.Afk.Seconds`) **sans frappe acceptée ni
  déplacement significatif** : au moins **4 studs** horizontaux depuis la dernière activité, échantillonné chaque
  seconde par le serveur. Un joueur KO n'accumule pas d'inactivité.
- `Match.Heartbeat` ne compte comme activité **qu'accompagné d'un mouvement** : petit déplacement (≥ 0,25 stud) ou
  rotation de l'avatar (≥ 8°) depuis le battement précédent. Un client qui envoie seulement des battements n'est pas actif.
- Conséquences : statut `AFK`, attribut joueur `AFK = true`, trou perdu, balle retirée, joueur intangible et spectateur
  du trou. L'attribut repasse à `false` dès qu'il bouge à nouveau.
- Toujours marqué AFK au début du trou suivant : délai réduit à **25 s** (`Afk.RepeatSeconds`).

### 9.2 Abandon

`Match.Forfeit(roundId)` : accepté seulement pendant `Playing`, pour un participant encore en jeu et pour la manche
courante (`RoundId`). Statut `Forfeit` (motif `voluntary`), balle retirée, spectateur intangible du trou.

### 9.3 Déconnexion

Statut `Disconnected` pour le trou en cours ; la condition de fin est réévaluée immédiatement ; si plus aucun
participant n'est présent, la partie est interrompue (sans récompense) et tout le monde revient à l'accueil.

### 9.4 Arrivée tardive

- `MatchSettings.lateJoin = true` : spectateur jusqu'au **trou suivant**, puis participant (0 point, trous manqués
  comptés au plafond pour le départage), dans la limite des places (8, ou 16 en mode expérimental). Jamais en Solo.
- `lateJoin = false` (ou partie pleine) : spectateur jusqu'à la **partie suivante**.
- Jamais d'entrée au milieu d'un trou.

### 9.5 Hôte

L'hôte est le premier joueur présent ; s'il part, le joueur présent depuis le plus longtemps le remplace
(`LobbyService.HostChanged`). Les réglages ne changent qu'à l'accueil ou en préparation, jamais pendant un trou :
`MatchService` fige une copie des réglages au lancement.

---

## 10. Économie et anti-farm

Les pièces sont calculées par `Logic/Rewards.luau` (valeurs `Config/Economy.luau`) à partir du résumé de partie
produit par `MatchService` et versées par `RewardService` (opération idempotente `MatchId..":"..UserId`).

- L'entraînement ne rapporte rien (seule exception : tutoriel, une fois).
- Une partie ne rapporte que si le joueur a été **actif** sur au moins `MinActiveHoles` trous (3, ou tous si la partie
  en compte moins) : un trou est actif s'il contient **au moins une frappe acceptée par le serveur**.
- Les trous **terminés** (balle rentrée) apportent un bonus par trou ; trous en un, eagles et birdies un bonus plafonné.
- Montant par partie plafonné (`MatchCap`), jamais négatif, jamais décidé par le client.
- Partie interrompue (abandon de tous, erreur) ou mode `Training` : aucune récompense.

Champs du résumé transmis à `RewardService.GrantMatchRewards(summary)` : `matchId`, `mode`, `holeCount` (trous
joués), `completed` (partie allée jusqu'au podium), `teamScores`, `winner`, et `players` = un élément par participant
**présent** avec `player`, `userId`, `name`, `team` et les champs de `Rewards.MatchInput` : `mode`, `rank`,
`participants`, `holeCount`, `activeHoles`, `holesFinished`, `parOrBetter`, `holeInOnes`, `eagles` (albatros compris),
`birdies`, `teamResult` (`"Win"` | `"Lose"` | `"Draw"`).

---

## 11. Valeurs initiales et justification

| Valeur | Défaut | Justification |
| --- | --- | --- |
| Barème 12-9-7-5-4-3-2-1, puis 1 | — | victoire nettement récompensée, aucun arrivant à 0 |
| Plafond de bonus | 8 | une performance parfaite vaut 2/3 d'une victoire |
| Catégories +6/+5/+4/+2/+1/0 | — | progression lisible ; le par rapporte un peu, le bogey rien |
| Coup de loin | +2 dès 40 studs | même seuil que le défi « Tir de sniper » |
| Vitesse | +1 sous 50 % de la référence | rare, ne pousse pas à bâcler |
| Facteur de durée | 2 | généreux pour les débutants ; la prolongation garde le rythme |
| Prolongation | 20–45 s (× timeScale) | fin rapide après la première arrivée, chance minimale garantie |
| Plafond de coups | par + 7, borné 10–14 | environ le double du par ; pas de trou interminable |
| AFK | 60 s (25 s si récidive) | laisse le temps de réfléchir ; récidive sanctionnée plus vite |
| Participants | 8 (16 expérimental) | cible de la demande ; 16 reste marqué expérimental |
| Durées de phase | intro 5 s, compte 3 s, fin 3 s, résultats 8 s, podium 12 s | rythme de fête sans temps mort |

---

## 12. Tests (preuves attendues)

`src/tests/Specs/Scoring.spec.luau` : barème complet (1 à 16, non arrivé), chaque catégorie de bonus, coup de loin
(seuil, putt exclu), vitesse, cumul et plafond, arrivées simultanées (rangs 1, 1, 3), départages de partie, rang
partagé, plafond de coups, coups retenus d'un non-arrivant, équipes déséquilibrées et chaque niveau de départage
d'équipe, composition des équipes, résultat final d'équipe, prolongation (réduction, extension, une seule fois,
échelle de temps), durée limite, score solo et record personnel. `MatchStateMachine.spec.luau` et
`Playlist.spec.luau` couvrent les transitions (y compris les transitions refusées) et les playlists (tailles,
reproductibilité, repli). Ces tests sont des **tests unitaires** (catégorie distincte des tests moteur et
multi-clients, `docs/ARCHITECTURE.md` §13).

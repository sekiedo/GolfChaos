# Registre des 17 objets — Golf Chaos

Spécification de conception (valeurs initiales). Les valeurs exécutées vivent dans
`src/shared/Config/Items.luau` et `src/shared/Config/ItemBoxes.luau` ; ce document en est la source et doit
rester synchronisé. Noms originaux ; la colonne « mécanique de référence » renvoie à la demande.

## Règles communes

- **Inventaire** : capacité initiale **3 cases** (`Config.Items.InventoryCapacity`, réglable 1–4). Une boîte
  n'est pas ramassée si l'inventaire est plein (elle reste disponible pour les autres).
- **Sélection** : clavier 1/2/3 ; manette L1/R1 (cycle) ; tactile : toucher la case. **Utilisation** : clavier E,
  manette R2, tactile bouton « Utiliser ». L'utilisation envoie une **intention** `Items.Use(roundId, slot, aim, targetUserId?)` ;
  le serveur valide tout (phase, participant actif, non KO, non gelé, non terminé, objet présent dans la case,
  délai, cible plausible, ligne de vue) et décide de l'effet.
- **Cibles « adversaire »** : jamais un allié (mode Équipes), jamais un joueur ayant terminé le trou, jamais un
  joueur protégé (réapparition), jamais un joueur invisible pour le verrouillage.
- **Dégâts** : il n'y a pas de points de vie ; un coup réussi provoque un **KO temporaire** (ragdoll) et/ou un
  **recul**. « Frappe majeure » = KO + fort recul ; « frappe mineure » = KO court ou simple recul.
- **Bouclier** (Bulle Magnétique) : absorbe/dévie les frappes **mineures** (3 charges) ; une frappe **majeure**
  détruit le bouclier et provoque un **KO sans le fort recul** (pas de chute dans le vide).
- **Esquive** : pendant la fenêtre de plongeon (attribut `Dodging`, 0,35 s) les projectiles et rayons
  esquivables ratent ; le verrouillage d'une roquette est rompu.
- **Nettoyage** : tout effet, piège, projectile, nuage, plateforme, véhicule et modification d'échelle est
  détenu par la `Trove` de manche **et** par celle du joueur concerné ; il disparaît à la fin du trou, à la
  réapparition (effets sur soi), à la déconnexion, au retour à l'accueil. Un objet possédé n'est **pas conservé**
  d'un trou à l'autre (inventaire vidé à chaque chargement de trou).
- **Boîtes** : boîtes aléatoires (tous objets) et **boîtes de mobilité** (Expresso, Bottes Kangourou, Kart-Caddie,
  Club Propulseur). Ramassage par proximité testée côté serveur (rayon 4 studs). Réapparition 10 s (fréquence
  « Élevée » 6 s, « Basse » 16 s). Désactivées si `itemsEnabled = false`.
- **Rattrapage** : le serveur tire l'objet selon un poids interpolé entre `poids meneur` et `poids dernier` selon
  la position normalisée dans la course p = (rang − 1) / (n − 1) (0 = meneur), modulé par
  `Config.ItemBoxes.CatchUpStrength` (0 = désactivé, 1 = plein effet). Le tirage est **serveur** (`Random` dédié).

## Tableau de référence

| # | ID | Nom original | Mécanique de référence | Catégorie | Rareté | Poids meneur / dernier | Portée | Durée | Charges | Délai | Cibles |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `horn` | Corne Tonitruante | Klaxon | Perturbation | Commun | 10 / 8 | rayon 45 | instantané (annonce 0,4 s) | 1 | — | adversaires proches |
| 2 | `espresso` | Expresso Turbo | Café | Mobilité | Commun | 12 / 12 | soi | 8 s | 1 | — | soi |
| 3 | `cork_pistol` | Pistolet à Bouchon | Pistolet de duel | Attaque | Commun | 10 / 9 | 80 (instantané) | — | 2 tirs | 0,8 s entre tirs | adversaire |
| 4 | `blunderbuss` | Tromblon Rebond | Fusil à recul | Attaque / mobilité | Rare | 7 / 8 | cône 30°, 25 | — | 2 | 1,2 s | zone + soi |
| 5 | `magnet_shield` | Bulle Magnétique | Bouclier électromagnétique | Défense | Rare | 7 / 7 | soi | 12 s ou rupture | 3 absorptions | — | soi |
| 6 | `caddie_kart` | Kart-Caddie | Voiturette | Véhicule | Rare | 6 / 9 | apparaît devant | 45 s | 1 | — | véhicule |
| 7 | `shroom_mine` | Champignon Piégé | Mine | Piège | Commun | 9 / 8 | déclenchement 6, explosion 8 | 60 s max | 1 (2 posées max) | armement 1,5 s | zone |
| 8 | `orbital_beam` | Rayon Satellite | Laser orbital | Attaque majeure | Épique | 2 / 7 | cercle 7 sur la cible | annonce 2 s + 1,2 s | 1 | — | meneur adverse |
| 9 | `confetti_rocket` | Lance-Fusées Confettis | Lance-roquettes | Attaque | Rare | 6 / 8 | 150 | 4 s de vol max | 1 | verrouillage 0,6 s | adversaire |
| 10 | `kangaroo_boots` | Bottes Kangourou | Bottes à ressorts | Mobilité | Commun | 10 / 10 | soi | 15 s ou 3 bonds | 3 bonds | — | soi |
| 11 | `rocket_club` | Club Propulseur | Club à fusée | Attaque / mobilité | Rare | 7 / 8 | mêlée 7 / soi | coup suivant ≤ 10 s | 1 | — | balle, adversaire, soi |
| 12 | `frost_bomb` | Boule Givrante | Bombe de glace | Perturbation | Rare | 7 / 8 | lancer 40, rayon 9 | gel 3 s ; plateforme 8 s | 1 | — | zone, balles, eau |
| 13 | `ninja_smoke` | Nuage Ninja | Fumigène | Défense / perturbation | Commun | 8 / 8 | nuage rayon 10 | nuage 6 s, invisibilité 5 s | 1 | — | soi + zone |
| 14 | `paparazzi_flash` | Flash Paparazzi | Appareil à flash | Perturbation | Commun | 9 / 8 | cône 50°, 30 | 2,5 s | 1 | — | adversaires face au flash |
| 15 | `grumpy_cloud` | Nuage Grognon | Orage | Perturbation de zone | Épique | 3 / 7 | suit un adversaire, éclair rayon 5 | 8 s | 1 | éclair toutes 2 s (annonce 1 s) | zone |
| 16 | `rail_slinger` | Rail-Fronde | Railgun | Attaque majeure | Épique | 2 / 6 | 140 | charge 1 s | 1 | — | jusqu'à 3 adversaires alignés |
| 17 | `mega_burger` | Méga Burger | Burger géant | Transformation | Épique | 3 / 7 | soi + contact | 8 s | 1 | — | soi, contact |

## Fiches détaillées

### 1. Corne Tonitruante (`horn`)
- **Effet** : après une annonce sonore de 0,4 s (gonflement visible), tous les adversaires dans un rayon de 45 studs :
  s'ils **chargent** leur frappe → frappe **prématurée** immédiate à la puissance serveur courante (`BallService.ForceShot`) ;
  s'ils **visent** sans charger → visée annulée et bloquée 1,5 s ; s'ils ont en case sélectionnée un objet
  « sensible au klaxon » (Pistolet à Bouchon, Tromblon Rebond, Lance-Fusées Confettis) → 35 % de chance de
  l'**utiliser involontairement** droit devant eux.
- **Contre-jeu** : l'annonce laisse le temps de relâcher/annuler ; s'éloigner ; Bulle Magnétique (aucun effet, charge non consommée).
- **Alliés** : non affectés. **Nettoyage** : aucun état persistant.

### 2. Expresso Turbo (`espresso`)
- **Effet** : vitesse ×1,45 et saut ×1,15 pendant 8 s (`MovementService.SetModifier`). Réutiliser rafraîchit la durée
  sans cumul multiplicatif. Le gel l'emporte (vitesse nulle tant que gelé).
- **Contre-jeu** : KO, gel, flash. **Alliés** : soi uniquement. **Nettoyage** : modificateur retiré en fin de trou,
  réapparition, déconnexion.

### 3. Pistolet à Bouchon (`cork_pistol`)
- **Effet** : 2 tirs instantanés (rayon serveur depuis la position serveur du tireur, direction fournie par le client
  validée et normalisée, portée 80, arrêt sur le décor). Touche = KO court (1,8 s) + léger recul.
- **Contre-jeu** : plongeon (raté), couverture, invisibilité (pas d'assistance de visée), bouclier (bouchon dévié vers le tireur, −1 charge).
- **Alliés** : traversés sans effet. Sensible au klaxon.

### 4. Tromblon Rebond (`blunderbuss`)
- **Effet** : cône de 30° sur 25 studs ; KO à moins de 12 studs, recul dégressif jusqu'à 25 ; les **balles** dans le cône
  sont poussées (`BallService.ApplyBallImpulse`). **Recul du tireur** : poussée arrière 60 studs/s ; si le tir vise le sol
  (inclinaison < −35°), propulsion verticale 70 studs/s (« saut au tromblon », exemption de plausibilité 1,5 s).
- **Contre-jeu** : distance, bouclier (pas de KO, recul réduit de moitié, −1 charge). **Alliés** : aucun effet. Sensible au klaxon.

### 5. Bulle Magnétique (`magnet_shield`)
- **Effet** : 12 s de protection ; absorbe **3** frappes mineures (bouchon, plomb de tromblon, coup de poing, balle,
  éclair, flash, klaxon, explosion de mine en bordure) et **dévie** les projectiles compatibles (bouchon renvoyé,
  fusée détournée qui explose à l'écart). Une frappe **majeure** (Rayon Satellite, Rail-Fronde, charge du Méga Burger,
  explosion de mine au contact, impact de Kart-Caddie > 40 studs/s) détruit la bulle et provoque un **KO sans fort recul**.
- **Contre-jeu** : frappes majeures, attendre l'expiration. **Alliés** : non partageable. **Nettoyage** : fin de trou,
  réapparition, déconnexion.

### 6. Kart-Caddie (`caddie_kart`)
- **Effet** : fait apparaître un kart devant l'utilisateur (zone libre vérifiée ; sinon l'objet est rendu). **8 places**
  (1 conducteur + 7 passagers, alliés ou non). Vitesse max 60 studs/s. Percuter un adversaire à plus de 25 studs/s → KO
  + recul (décision serveur, cooldown par victime). Durée 45 s ; détruit après 3 frappes majeures ou une chute en zone
  dangereuse (éjection propre des occupants). Les karts ne touchent pas les balles (groupes de collision).
- **Montée / descente** : invite de proximité « Monter » (siège libre le plus proche) ; saut = descendre ; **sortie de
  secours** automatique si le kart est retourné ou bloqué plus de 3 s ; remise à l'endroit par le conducteur (délai 5 s).
- **Contre-jeu** : gel (kart glissant sans direction 3 s), frappes majeures, obstacles. **Nettoyage** : disparaît en fin de
  trou ; si le propriétaire part, éjection puis disparition.

### 7. Champignon Piégé (`shroom_mine`)
- **Effet** : posé aux pieds ; **armement 1,5 s** (clignotement lent, visible de tous) ; un adversaire à moins de 6 studs
  déclenche un **avertissement 0,6 s** (clignotement rapide + bip) puis l'explosion : KO à moins de 6 studs, recul jusqu'à 8.
  Une balle rapide qui le touche le fait exploser. 2 champignons actifs max par joueur, 60 s de vie.
- **Désamorçage** : un coup de poing à moins de 4 studs le neutralise sans explosion.
- **Alliés** : ne le déclenchent jamais et le voient surligné en vert. Le poseur ne déclenche jamais son propre champignon.
- **Nettoyage** : fin de trou, déconnexion du poseur.

### 8. Rayon Satellite (`orbital_beam`) — règle de ciblage explicite
- **Cible** : l'adversaire **le mieux placé** dans la course (distance restante au trou la plus faible), hors alliés,
  joueurs ayant terminé, protégés et invisibles. Si l'utilisateur est lui-même premier, c'est l'adversaire suivant.
  Sans cible valide, l'objet n'est pas consommé.
- **Déroulé** : cercle rouge de rayon 7 qui **suit** la cible pendant 2 s, puis se **fige** 1,2 s (charge visible), puis frappe :
  frappe **majeure** pour tout adversaire dans le cercle (les balles présentes sont projetées).
- **Contre-jeu** : sortir du cercle pendant la phase figée ; bouclier (détruit + KO sans fort recul) ; devenir invisible
  avant le lancement (cible suivante choisie). **Alliés** : immunisés.

### 9. Lance-Fusées Confettis (`confetti_rocket`)
- **Verrouillage** : maintenir « Utiliser » ; cible valide dans un cône de 20°, à moins de 150 studs, en ligne de vue,
  visible et adverse ; verrouillage acquis après 0,6 s ; relâcher pour tirer (sans verrou : tir droit).
- **Vol** : 70 studs/s, virage max 90°/s, 4 s de vie. Explosion au contact (cible ou décor) : KO à moins de 5 studs,
  recul jusqu'à 8.
- **Contre-jeu** : plongeon (verrou rompu, la fusée file droit), Nuage Ninja (verrou rompu), bouclier (fusée déviée),
  couverture. Sensible au klaxon.

### 10. Bottes Kangourou (`kangaroo_boots`)
- **Effet** : 3 bonds géants (saut ×2,6) dans les 15 s ; contrôle aérien normal ; exemption de plausibilité pendant l'effet.
- **Contre-jeu** : KO, gel. **Alliés** : soi. **Nettoyage** : comme l'Expresso.

### 11. Club Propulseur (`rocket_club`)
- **Effet selon le contexte** : en **visée** → le prochain coup (≤ 10 s) est amplifié (puissance ×1,6, plafond relevé pour
  ce coup) ; sinon, adversaire dans le cône de mêlée (7 studs) → frappe majeure ; sinon → **propulsion** de l'utilisateur
  vers l'avant (80 studs/s pendant 0,4 s, exemption de plausibilité).
- **Contre-jeu** : plongeon, bouclier (détruit + KO sans fort recul). **Alliés** : non affectés.

### 12. Boule Givrante (`frost_bomb`)
- **Effet** : lancer en cloche simulé par le serveur (≈ 40 studs) ; à l'impact, rayon 9 : adversaires **gelés 3 s**
  (immobiles, visée impossible, **glissade** sur l'élan), balles gelées 3 s ; sur l'eau, **plateforme de glace**
  temporaire (disque rayon 9, 8 s) praticable à pied et par la balle (surface Glace).
- **Contre-jeu** : esquiver la zone, bouclier (−1 charge). **Alliés** : immunisés. **Nettoyage** : gel retiré à la
  réapparition, en fin de trou, à la déconnexion ; la protection de réapparition empêche le gel ; plateformes retirées en fin de trou.

### 13. Nuage Ninja (`ninja_smoke`)
- **Effet** : nuage de fumée (rayon 10, 6 s) à la position de l'utilisateur ; **invisibilité 5 s** (personnage quasi
  transparent pour les autres, nom masqué) ; **rompt tous les verrouillages** visant l'utilisateur (fusées, tir guidé,
  ciblage du Rayon Satellite) et empêche d'en acquérir de nouveaux. L'invisibilité cesse si l'utilisateur attaque,
  utilise un objet ou frappe sa balle.
- **Contre-jeu** : attaques de zone (champignon, nuage grognon). **Alliés** : voient l'utilisateur en semi-transparence.

### 14. Flash Paparazzi (`paparazzi_flash`)
- **Effet** : adversaires dans un cône de 50° sur 30 studs **et tournés vers l'utilisateur** : **éblouis 2,5 s** —
  visée impossible et vitesse ×0,6 (pénalité de jeu) + effet visuel. **Mode accessible sans flash** (réglage) : vignette
  sombre et icône « Ébloui » à la place du flash blanc, **pénalité de jeu identique**.
- **Contre-jeu** : détourner le regard (test d'orientation serveur), bouclier (−1 charge). **Alliés** : non affectés.

### 15. Nuage Grognon (`grumpy_cloud`)
- **Effet** : nuage d'orage au-dessus de l'utilisateur qui dérive vers l'adversaire le plus proche (≤ 80 studs) à
  12 studs/s pendant 8 s ; toutes les 2 s, **annonce** d'un éclair (anneau au sol 1 s) puis frappe rayon 5 : KO 2 s + recul ;
  les balles touchées reçoivent une secousse aléatoire.
- **Contre-jeu** : continuer à bouger (12 < 16 studs/s de marche), sortir de l'anneau, bouclier (−1 charge).
  **Alliés** : immunisés. **Nettoyage** : fin de trou, déconnexion de l'utilisateur.

### 16. Rail-Fronde (`rail_slinger`) — règle multi-cibles explicite
- **Effet** : charge 1 s avec **viseur laser visible de tous**, puis rayon instantané de 140 studs dans la direction visée.
  Le rayon **s'arrête sur le décor** et **traverse les joueurs** : il touche au plus **3 adversaires**, triés par distance le
  long du rayon, avec un recul de 100 %, 70 % puis 50 % ; chaque touche est une frappe majeure.
- **Bouclier** : le premier adversaire protégé arrête le rayon (bulle détruite + KO sans fort recul) ; les cibles
  au-delà ne sont pas touchées. **Plongeon** pendant le tir : raté. **Alliés** : traversés sans effet.

### 17. Méga Burger (`mega_burger`)
- **Effet** : transformation **géante 8 s** (échelle ×2,2) : vitesse ×0,85, immunité aux frappes mineures, le contact
  projette les adversaires (KO 2 s) et les balles ; visée impossible pendant la transformation. Le géant **brise le décor
  marqué « Breakable »** (réapparition au trou suivant) mais reste bloqué par la géométrie du parcours (murs, tunnels).
- **Contre-jeu** : frappes majeures (fin anticipée), fuir. **Alliés** : non projetés.
- **Nettoyage** : échelle restaurée en fin d'effet, réapparition, fin de trou, déconnexion.

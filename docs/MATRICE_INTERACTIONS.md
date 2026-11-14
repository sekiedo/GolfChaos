# Matrice d'interactions des objets — Golf Chaos

Chaque ligne est une règle **implémentée côté serveur** et couverte par un test (unitaire quand la règle est pure,
test moteur sinon). Statut de preuve tenu dans `docs/MATRICE_COUVERTURE.md`.

## Paires exigées par la demande

| Paire | Règle | Raison / contre-jeu |
| --- | --- | --- |
| **Gel / voiturette** | Un conducteur gelé ne peut ni diriger ni accélérer : le kart garde son élan et **glisse** (frottement quasi nul) 3 s, freinage automatique ensuite. Un kart touché directement par la Boule Givrante est gelé 3 s (glissade, pas de direction). Les passagers gelés restent assis. | Le gel reste lisible et n'éjecte pas brutalement ; pas de vitesse infinie. |
| **Bouclier / laser** (Rayon Satellite) | Frappe majeure : la Bulle est **détruite** et la cible est **KO sans fort recul**. | Le bouclier n'annule pas l'ultime ; il évite seulement la chute dans le vide. |
| **Bouclier / railgun** (Rail-Fronde) | Le premier adversaire protégé **arrête** le rayon : Bulle détruite + KO sans fort recul ; les cibles derrière lui sont épargnées. | Le bouclier protège aussi ses voisins alignés. |
| **Invisibilité / roquette** | Un joueur invisible (Nuage Ninja) ne peut pas être verrouillé ; un verrou existant est **rompu** et la fusée continue en ligne droite. | Contre-jeu direct au verrouillage. |
| **Géant / obstacles** | Le Méga Burger brise le décor `Breakable` (réapparaît au trou suivant) mais **pas** la géométrie jouable (murs, ponts, tunnels, obstacles animés) qui le bloque normalement ; les obstacles animés ne le KO pas mais peuvent le pousser. | Le parcours reste praticable et le géant ne peut pas couper à travers les murs. |
| **Mine / allié** | Les alliés du poseur ne déclenchent jamais un Champignon Piégé et le voient surligné en vert ; le poseur ne déclenche jamais le sien. L'explosion (déclenchée par un adversaire ou par une balle rapide) ne touche que les **adversaires** du poseur. | Pas de tir ami ; lisibilité. |
| **Klaxon / objet** | Un adversaire dans le rayon qui a en case sélectionnée un objet sensible (Pistolet à Bouchon, Tromblon Rebond, Lance-Fusées Confettis) a 35 % de chance de l'utiliser involontairement droit devant lui ; un joueur qui charge sa frappe la déclenche prématurément. | Mécanique de la demande ; l'annonce de 0,4 s permet d'annuler. |
| **Gel / réapparition** | Toute réapparition (checkpoint, hors limites, chute) **retire** le gel ; la protection de réapparition (3 s) empêche d'être gelé de nouveau ; une balle gelée replacée après un hors-limites est dégelée. | Aucun état ne survit à une réapparition. |

## Autres interactions définies

| Situation | Règle |
| --- | --- |
| Bouclier / frappes mineures | Absorbe (−1 charge sur 3) ; bouchons renvoyés vers le tireur, fusées déviées (explosion à l'écart). |
| Bouclier / Méga Burger | Le contact du géant est une frappe majeure : Bulle détruite + KO sans fort recul. |
| Bouclier / Klaxon | Aucun effet sur le porteur, charge non consommée. |
| Bouclier / Flash | Absorbé (−1 charge), pas d'éblouissement. |
| Plongeon / projectiles et rayons | Pendant `Dodging` (0,35 s) : bouchon, plomb, fusée, Rail-Fronde ratent ; le verrou d'une fusée est rompu. Les zones (Rayon Satellite, éclair, mine) **ne** sont **pas** esquivables par plongeon. |
| Invisibilité / Rayon Satellite | Un joueur invisible ne peut pas être choisi comme cible ; une cible qui devient invisible **après** le lancement reste dans le cercle (le cercle suit sa dernière position connue). |
| Invisibilité / attaque | L'invisibilité cesse dès que le joueur attaque, utilise un objet ou frappe sa balle. |
| Géant / gel | Le géant gelé est immobile 3 s mais reste géant ; la durée de transformation continue de s'écouler. |
| Géant / KO mineur | Immunisé. KO majeur → fin anticipée de la transformation. |
| Voiturette / balles | Aucune collision (groupes de collision) : un kart ne peut pas injecter de vitesse dans une balle. |
| Voiturette / Rayon Satellite, Rail-Fronde | Frappe majeure sur le kart : −1 sur ses 3 points de structure ; le conducteur touché est éjecté et KO. |
| Mine / balle | Une balle à plus de 30 studs/s qui touche un champignon armé le fait exploser (effet sur les adversaires du poseur seulement). |
| Mine / plongeon | Le plongeon ne protège pas de l'explosion. |
| Joueur ayant terminé | Intangible (groupe Ghosts) : ne peut ni être affecté ni affecter ; ses pièges et nuages en cours sont retirés. |
| Joueur protégé (réapparition) | Ne peut être ni KO, ni gelé, ni ébloui, ni ciblé pendant 3 s ; attaquer met fin à sa protection. |
| Fin de trou | `ItemService.ClearRound()` : inventaires vidés, effets retirés, pièges, nuages, projectiles, plateformes et karts détruits. |
| Déconnexion | Effets, pièges et nuages du joueur retirés ; son kart éjecte ses occupants puis disparaît. |
| KO répété | Même attaquant → même victime : délai de 8 s avant un nouveau KO ; immunité de 1,5 s après chaque relève ; durées décroissantes (×0,75 puis ×0,5) si la victime enchaîne 3 KO en 20 s. |

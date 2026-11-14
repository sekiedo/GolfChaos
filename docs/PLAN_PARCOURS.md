# Plan des 81 trous — Golf Chaos

Plan de conception : chaque trou a une **signature** propre (forme du tracé, obstacle, terrain, rythme) pour que les
81 trous soient 81 expériences distinctes. Les données exécutées vivent dans `src/shared/Data/Holes/<Biome>.luau`
(format : `docs/FORMAT_TROUS.md`) ; le **catalogue** avec l'état de validation de chaque trou est
`docs/CATALOGUE_TROUS.md` (produit à partir des données et des validations réellement exécutées).

Règles communes : le **chemin principal** est toujours praticable à pied sans objet (pentes ≤ 30°, trous ≤ 6 studs
ou ponts) ; les **raccourcis** risqués peuvent exiger un objet (Bottes Kangourou, Kart-Caddie, Boule Givrante sur
l'eau, Club Propulseur, Tromblon). Par 3 : 120–220 studs ; par 4 : 230–380 ; par 5 : 380–560. Courbe : trous 1–6
accessibles, 7–12 intermédiaires, 13–18 exigeants, le 18 est une finale spectaculaire.

## Côte (COT, 18 trous, par 71) — îles, plages, ponts, falaises, passages au-dessus de l'eau

| ID | Nom | Par | Diff. | Signature | Raccourci risqué |
|---|---|---|---|---|---|
| COT-01 | Le Ponton des Mouettes | 3 | 1 | départ sur un ponton, courte traversée d'un lagon peu profond vers un green de plage | — |
| COT-02 | Anse aux Galets | 4 | 1 | dogleg droit le long d'une plage de galets, mares de marée | couper par la mare (eau) |
| COT-03 | L'Île du Phare | 3 | 2 | green en île autour d'un phare, accès à pied par pont de cordes | — |
| COT-04 | Falaise des Cormorans | 4 | 2 | départ en haut de falaise, drive plongeant ; descente à pied en lacets | sauter la falaise (bottes) |
| COT-05 | Le Chapelet d'Îlots | 5 | 2 | quatre îlots reliés par des ponts, une boîte d'objet par îlot | traversée directe par l'eau (gel) |
| COT-06 | Crique des Contrebandiers | 4 | 2 | fairway à travers une grotte marine | passer par le toit de la grotte |
| COT-07 | La Jetée Venteuse | 3 | 2 | green étroit au bout d'une longue jetée, vent latéral dominant, butoirs | — |
| COT-08 | Plage des Parasols | 4 | 2 | forêt de parasols-obstacles sur sable, cabane à glaces | — |
| COT-09 | Le Pont-Levis du Port | 4 | 3 | pont-levis mobile au-dessus du chenal ; contournement par le quai | attendre/forcer le pont baissé |
| COT-10 | Arche de Corail | 3 | 3 | tir à travers une arche rocheuse au-dessus de l'eau | — |
| COT-11 | Les Marches du Géant | 5 | 3 | par 5 **montant** sur des terrasses de falaise avec rampes | rampe latérale abrupte |
| COT-12 | Lagon Turquoise | 4 | 3 | dogleg autour d'un lagon intérieur | survoler le lagon |
| COT-13 | Épave Ensablée | 4 | 3 | épave au milieu du fairway, traversable par la coque | — |
| COT-14 | Récif des Moulins | 3 | 4 | minuscule green sur récif gardé par deux moulins à pales | — |
| COT-15 | Corniche Vertigineuse | 4 | 4 | route de corniche étroite, vide sur l'océan d'un côté | — |
| COT-16 | La Traversée des Bouées | 5 | 4 | longue passerelle flottante ; plateformes qui tanguent | sauter de bouée en bouée |
| COT-17 | Grotte aux Échos | 4 | 4 | grotte fermée à piliers, green sous une ouverture de lumière | — |
| COT-18 | Le Grand Phare | 5 | 5 | finale : spirale autour d'une île-phare, ponts et traversées, green sur la terrasse haute | pont suspendu direct |

## Forêt (FOR, 18 trous, par 71) — arbres, clairières, reliefs, plateformes

| ID | Nom | Par | Diff. | Signature | Raccourci risqué |
|---|---|---|---|---|---|
| FOR-01 | Clairière des Lucioles | 3 | 1 | clairière ouverte cerclée d'arbres, champignons géants | — |
| FOR-02 | Sentier des Écureuils | 4 | 1 | sentier sinueux entre grands pins, dogleg gauche | — |
| FOR-03 | Le Vieux Chêne | 3 | 1 | chêne géant devant le green : contourner ou passer par-dessus | — |
| FOR-04 | Ruisseau Babillard | 4 | 2 | double traversée d'un ruisseau sur rondins | — |
| FOR-05 | Les Champignons Rebondissants | 4 | 2 | champignons-butoirs et tremplins qui relancent la balle | tremplin vers le green |
| FOR-06 | Colline du Hibou | 5 | 2 | montée puis descente d'une colline, green caché | — |
| FOR-07 | Scierie Abandonnée | 4 | 3 | tapis roulants et barres tournantes dans une vieille scierie | — |
| FOR-08 | Passerelles des Cimes | 3 | 3 | passerelles en hauteur dans la canopée, green sur plateforme | — |
| FOR-09 | Marais des Grenouilles | 4 | 3 | îlots de nénuphars, boue, eau stagnante | — |
| FOR-10 | Le Tunnel de Racines | 4 | 3 | tunnel creusé dans des racines ; route aérienne plus longue | — |
| FOR-11 | Cascade Chantante | 5 | 3 | montée le long d'une cascade, bassin au pied | escalier glissant derrière la chute |
| FOR-12 | Labyrinthe de Haies | 4 | 3 | haies formant plusieurs itinéraires | brèche dans la haie |
| FOR-13 | Ravin des Fougères | 3 | 4 | départ et green de part et d'autre d'un ravin ; escaliers à pied | — |
| FOR-14 | Moulin du Bûcheron | 4 | 4 | grande roue à aubes gardant un pont étroit | — |
| FOR-15 | Plateformes Moussues | 5 | 4 | pont de cordes au-dessus d'un gouffre moussu | plateformes à sauter (bottes) |
| FOR-16 | Le Cercle de Pierres | 3 | 4 | green dans un cercle de menhirs aux passages étroits | — |
| FOR-17 | Bois Brumeux | 4 | 4 | brume dense, couloirs entre troncs | — |
| FOR-18 | La Cabane Perchée | 5 | 5 | finale : ascension vers une cabane perchée, ascenseurs et ponts | liane-tremplin |

## Désert (DES, 18 trous, par 71) — dunes, canyons, arches, oasis, sable pénalisant

| ID | Nom | Par | Diff. | Signature | Raccourci risqué |
|---|---|---|---|---|---|
| DES-01 | Porte des Sables | 3 | 1 | arche d'entrée, fairway de terre battue | — |
| DES-02 | Dunes Douces | 4 | 1 | fairway ondulé sur dunes | — |
| DES-03 | L'Oasis Cachée | 3 | 2 | green au bord d'une oasis à palmiers | — |
| DES-04 | Canyon du Coyote | 4 | 2 | fond de canyon entre deux parois | — |
| DES-05 | Les Cactus Farceurs | 4 | 2 | champ de cactus-butoirs | — |
| DES-06 | Route de la Caravane | 5 | 2 | longue piste rectiligne, caravane au repos, fosses de sable | — |
| DES-07 | Arche du Soleil | 3 | 3 | tir à travers une arche de grès | — |
| DES-08 | Le Sablier | 4 | 3 | fairway en sablier, étranglement cerné de sable lourd | — |
| DES-09 | Mesa Suspendue | 4 | 3 | green au sommet d'une mesa, rampe d'accès | — |
| DES-10 | Les Tourbillons | 4 | 3 | courants de sable (tapis) qui poussent balles et joueurs | — |
| DES-11 | Temple Ensablé | 5 | 3 | temple en ruine à colonnes | couloir secret du temple |
| DES-12 | Gorge du Vent | 3 | 3 | gorge étroite au vent fort | — |
| DES-13 | Mine du Prospecteur | 4 | 4 | galeries de mine, wagonnets mobiles | — |
| DES-14 | Les Pyramides Penchées | 4 | 4 | faces de pyramides qui dévient la balle | — |
| DES-15 | Pont de Cordes du Canyon | 5 | 4 | long pont de cordes au-dessus d'un canyon ; détour possible | — |
| DES-16 | Mirage | 3 | 4 | green cerné de fosses de sable, faux lac en décor | — |
| DES-17 | Le Serpent de Grès | 4 | 4 | crête de grès étroite en S | — |
| DES-18 | Couronne du Pharaon | 5 | 5 | finale : ascension d'une ziggourat à étages, butoirs et tremplins | tremplin d'étage |

## Neige (NEI, 18 trous, par 71) — glace, pentes, précipices, passages glissants

| ID | Nom | Par | Diff. | Signature | Raccourci risqué |
|---|---|---|---|---|---|
| NEI-01 | Piste des Débutants | 3 | 1 | douce pente enneigée et fanions | — |
| NEI-02 | Lac Gelé | 4 | 1 | traversée d'un lac gelé (roulement glissant) | — |
| NEI-03 | Bonhommes Gardiens | 3 | 2 | bonshommes de neige autour du green | — |
| NEI-04 | Télésiège | 4 | 2 | fairway montant, plateforme-ascenseur pour monter à pied | — |
| NEI-05 | Igloos du Village | 4 | 2 | village d'igloos, ruelles étroites | — |
| NEI-06 | La Grande Descente | 5 | 2 | longue descente avec plaques de glace | — |
| NEI-07 | Crevasse Bleue | 3 | 3 | traversée d'une crevasse vers un green sur banquise ; pont de glace | — |
| NEI-08 | Patinoire Folle | 4 | 3 | patinoire-flipper avec butoirs | — |
| NEI-09 | Col des Avalanches | 4 | 3 | boules de neige géantes qui dévalent la pente | — |
| NEI-10 | Sapins Givrés | 4 | 3 | slalom entre sapins givrés | — |
| NEI-11 | Tremplin | 5 | 3 | lacets sur le chemin principal | tremplin de saut à ski |
| NEI-12 | Grotte de Glace | 3 | 3 | grotte à stalactites et sol de glace | — |
| NEI-13 | Corniche du Yéti | 4 | 4 | corniche étroite au-dessus du précipice, statue de yéti | — |
| NEI-14 | Bobsleigh | 4 | 4 | couloir de glace relevé en virages | — |
| NEI-15 | Pont de Glace Fragile | 5 | 4 | suite de ponts de glace au-dessus d'un gouffre ; détour | — |
| NEI-16 | Sommet Venteux | 3 | 4 | green au sommet, vent violent | — |
| NEI-17 | Les Glissades | 4 | 4 | dalles de glace inclinées vers le vide | — |
| NEI-18 | Observatoire Polaire | 5 | 5 | finale : montée vers un observatoire, ascenseurs, glace, crevasses | téléphérique |

## Ville (VIL, 9 trous, par 36) — rues, parcs, canaux, ponts, hauteurs, circulation dangereuse

| ID | Nom | Par | Diff. | Signature | Raccourci risqué |
|---|---|---|---|---|---|
| VIL-01 | Square des Pigeons | 3 | 1 | square avec fontaine (eau) et bancs | — |
| VIL-02 | Avenue des Taxis | 4 | 2 | avenue traversée par des taxis (KO au contact), passage piéton | traverser hors du passage |
| VIL-03 | Le Canal | 3 | 2 | canal et ponts en arche, bateaux mobiles | — |
| VIL-04 | Toits de la Ville | 4 | 3 | parcours de toit en toit (passerelles sur le chemin principal) | sauts entre toits |
| VIL-05 | Chantier Fou | 4 | 3 | grues tournantes, poutrelles, cônes | — |
| VIL-06 | Parking à Étages | 5 | 3 | rampes en spirale d'un parking | cage d'escalier |
| VIL-07 | Marché du Port | 4 | 4 | étals, bord de canal, chariots de livraison mobiles | — |
| VIL-08 | Échangeur | 4 | 4 | passerelles au-dessus d'une circulation dense | — |
| VIL-09 | Gratte-Ciel | 5 | 5 | finale : ascension d'un gratte-ciel par ascenseurs extérieurs, green sur l'héliport | nacelle de laveur de vitres |

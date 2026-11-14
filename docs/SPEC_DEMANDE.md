# Demande d'origine (copie de référence)

> Copie fidèle de la demande de l'utilisateur, conservée comme référence unique des exigences.
> Les documents `CAHIER_DES_CHARGES.md` et `MATRICE_COUVERTURE.md` en dérivent.

Tu es le développeur principal de mon jeu Roblox : programmeur Luau, concepteur de gameplay, créateur de niveaux et responsable de la qualité. Développe réellement le projet dans le dossier courant et dans Roblox Studio lorsque les outils disponibles le permettent.

## 1. Objectif et périmètre

Créer un jeu de golf multijoueur simultané inspiré des mécaniques de Super Battle Golf : course vers le trou, coups de golf, combats cartoon, pouvoirs, voiturettes, nombreux parcours et personnalisation des personnages, clubs et balles.

Nom de travail : « Golf Chaos ». Le nom, les interfaces, les modèles, les sons, les animations et les niveaux doivent constituer une création originale. Ne récupère pas les assets du jeu Steam et ne reproduis pas ses collaborations de marque. Les noms d'objets ci-dessous décrivent des mécaniques de référence ; tu peux leur donner des noms originaux dans notre jeu.

La livraison finale doit être un jeu complet utilisable dans Roblox Studio, avec 81 trous, 17 objets fonctionnels, progression persistante et interface aboutie. Une démonstration à trois trous, une interface seule ou un dossier de scripts non intégré ne remplit pas cette demande. Les valeurs et choix chiffrés ci-dessous définissent notre adaptation ; ils ne prétendent pas reproduire exactement les réglages du jeu Steam.

Cible principale : 1 à 8 joueurs, avec architecture permettant 16 joueurs. Le mode 16 joueurs reste expérimental tant que sa stabilité n'a pas été mesurée. Supports : PC, mobile/tablette et manette. Interface française, textes centralisés pour permettre une traduction anglaise.

## 2. Commencer par l'environnement réel

- Inspecte le dossier, l'état Git s'il existe, les consignes AGENTS.md/CLAUDE.md et les outils installés. Préserve le travail existant.
- Vérifie l'accès réel à Roblox Studio et à ses éventuels outils MCP. N'invente aucune capacité d'édition, d'import ou de test.
- Si un projet existe, conserve son flux de travail pertinent. Si tu pars de zéro, choisis un flux reproductible : par exemple Luau + Rojo pour les scripts et les modèles générables. Vérifie les versions compatibles avec Studio avant de figer la configuration.
- Définis une source de vérité pour les scripts et les scènes. Une synchronisation ne doit pas écraser des modifications Studio non exportées.
- Si Studio n'est pas accessible, construis les sources, les assets générables, le build importable et les outils de validation disponibles. Décris précisément les manipulations Studio restantes ; ne prétends pas que le jeu a été lancé.
- Consulte la documentation Roblox actuelle pour les API sensibles : physique, propriété réseau, sauvegardes, téléportations, commandes et communication.
- Fais les choix techniques ordinaires toi-même. Demande uniquement une information réellement bloquante et continue les travaux indépendants.
- Travaille localement et prépare la publication. N'effectue pas d'achat, d'activation de monétisation, d'envoi de message ou de publication publique sans demande explicite.

## 3. Boucle de jeu et modes

Implémente une machine à états explicite : accueil → préparation du salon → chargement → présentation du trou → compte à rebours → partie → fin du trou → résultats → trou suivant → podium → retour à l'accueil.

Chaque joueur possède sa balle. Tout le monde joue simultanément, contrôle son personnage à la troisième personne, frappe sa balle puis la rejoint à pied ou en véhicule.

Fonctionnalités :
- Visée horizontale, angle vertical, puissance chargée, putt et frappe aérienne ; indicateur de trajectoire d'aide cohérent avec les règles.
- Saut, course, plongeon/esquive, frappe de proximité et tir de balle guidé vers un adversaire, avec règles de verrouillage et d'évitement explicites.
- KO temporaires, recul, réapparition aux checkpoints et récupération de balle hors limites.
- Protection brève après réapparition et mécanisme configurable limitant les KO répétés sur la même personne.
- À la fin d'un trou, les joueurs ayant terminé ne peuvent plus modifier les résultats ou gêner ceux qui jouent encore.
- Traitement des égalités, arrivées tardives, déconnexions, changement d'hôte du salon, abandon, joueurs AFK et balle bloquée. Aucun de ces cas ne doit bloquer la progression du match.

Modes :
1. Chacun pour soi : points selon l'ordre d'arrivée, bonus de performance golfique, gagnant au total des points.
2. Équipes rouge/bleue : sur chaque trou, l'équipe avec le plus de joueurs ayant terminé marque un point d'équipe ; pas de KO ni d'élimination entre alliés. Définis le traitement des égalités et équipes déséquilibrées.
3. Solo : parcours au score et au temps, sans adversaire obligatoire.
4. Entraînement : Driving Range, tutoriel interactif, essais des frappes, objets et véhicules.
5. Spectateur : caméra de suivi et changement de joueur observé.

Écris une spécification précise du score avant de l'implémenter : barème d'arrivée, par/birdie/eagle, trou en un, coup rentré de loin, chronomètre, prolongation, égalités et bonus cumulables. Choisis des valeurs initiales équilibrées, centralise-les dans une configuration et teste-les. Les récompenses économiques ne doivent pas être exploitables en répétant indéfiniment une action d'entraînement.

## 4. Physique du golf et autorité serveur

Le golf doit être agréable, lisible et stable, y compris en multijoueur.

- Gérer roulement, rebond, frottement, pente, herbe, sable, glace, eau, obstacles et vent configurable.
- Détecter les collisions rapides et l'entrée dans le trou de manière robuste : pas de balle traversant un obstacle mince ni de point accordé à distance.
- Les effets visuels des balles restent séparés de leur collision de référence.
- Le serveur décide des frappes acceptées, des KO, des entrées dans le trou et des scores. Le client transmet des intentions de jeu, jamais une récompense ou une conséquence à appliquer aveuglément.
- Documenter la stratégie de simulation et de propriété réseau pour balles, véhicules et joueurs ; tester ses conséquences avec de la latence. Lissage ou prédiction visuelle côté client possible, avec correction vers l'état autorisé.
- Valider types, valeurs finies, bornes, distance, état du joueur, équipement, délai et permissions ; limiter les requêtes et rejeter doublons ou requêtes d'une ancienne manche.
- Vérifier les déplacements plausibles sans punir les propulsions, téléportations ou réapparitions autorisées par le jeu.

Les longues frappes doivent rester cohérentes et le petit putt précis. Un avatar ou une balle avec un autre skin ne doit pas obtenir un avantage physique.

## 5. Les 17 objets à développer

Créer un registre commun et un comportement réel distinct pour chacun :

1. Klaxon : provoque une frappe prématurée ou l'utilisation involontaire d'un objet compatible.
2. Café : accélération temporaire.
3. Pistolet de duel : tir précis provoquant un KO.
4. Fusil à recul : tir puissant, recul et possibilité de propulsion maîtrisée.
5. Bouclier électromagnétique : protection et déviation des attaques compatibles ; les frappes majeures détruisent le bouclier et provoquent un KO plutôt qu'une élimination directe.
6. Voiturette : véhicule pilotable, jusqu'à huit occupants, collisions et percussion, montée/descente fiables, sortie de secours et destruction ou remise à zéro contrôlée.
7. Mine : piège réagissant aux mouvements proches, avec armement, avertissement et désamorçage.
8. Laser orbital : frappe télégraphiée depuis le ciel, zone lisible et possibilité de contre-jeu. Définis explicitement sa règle de sélection de cible.
9. Lance-roquettes : projectile guidé, verrouillage, esquive et explosion.
10. Bottes à ressorts : grand bond contrôlable.
11. Club à fusée : frappe amplifiée sur balle ou adversaire, et propulsion de l'utilisateur.
12. Bombe de glace : gel temporaire, glissade et plateforme temporaire sur l'eau.
13. Fumigène : fumée et invisibilité temporaire, avec rupture des verrouillages compatibles.
14. Appareil à flash : gêne visuelle temporaire ; mode accessible sans flash lumineux conservant une pénalité de jeu équivalente.
15. Orage : nuage temporaire et frappes de foudre annoncées.
16. Railgun : rayon puissant, pouvant toucher plusieurs cibles alignées selon une règle explicite.
17. Burger géant : transformation temporaire, percussion et projection des balles ou adversaires.

Pour chaque objet, définir dans les données : ID stable, rareté, chances d'apparition, portée, durée, charges, délai, catégories de cible, contre-jeu, effets sur alliés et nettoyage. Prévoir un inventaire limité, sélectionnable au clavier, au tactile et à la manette. Choisis une capacité initiale documentée et configurable.

Ajouter boîtes d'objets aléatoires, boîtes de mobilité et ajustement configurable des probabilités selon la situation dans la course. Le serveur réalise le tirage.

Écrire une matrice d'interactions : gel/voiturette, bouclier/laser, bouclier/railgun, invisibilité/roquette, géant/obstacles, mine/allié, klaxon/objet, gel/réapparition. Aucun état temporaire ne doit survivre accidentellement à la fin d'une manche ou à une déconnexion.

## 6. Les 81 trous et la création des niveaux

Créer cinq biomes avec cette répartition :
- Côte : 18 trous, îles, plages, ponts, falaises et passages au-dessus de l'eau.
- Forêt : 18 trous, arbres, clairières, reliefs et plateformes.
- Désert : 18 trous, dunes, canyons, arches, oasis et sable pénalisant.
- Neige : 18 trous, glace, pentes, précipices et passages glissants.
- Ville : 9 trous, rues, parcs, canaux, ponts, hauteurs et circulation dangereuse.

Les tracés et noms sont originaux. Les 81 trous doivent correspondre à 81 expériences de parcours distinctes, pas à des copies recolorées ou à des graines aléatoires jamais inspectées.

Chaque trou possède : ID, nom, biome, par, difficulté, départs équitables, position du trou, limites, checkpoints, zones de récupération, boîtes d'objets, obstacles, durée cible et chemins de déplacement praticables. Garantir un trajet normal réalisable sans obtenir un objet aléatoire indispensable. Les raccourcis risqués peuvent exploiter des objets.

Prévoir un format de données et des outils réutilisables pour assembler les niveaux. Une génération procédurale est acceptable si les résultats sont stables, inspectables, reproductibles et validés. Fournir un catalogue des 81 trous avec leur particularité et leur état de validation.

Charger seulement le contenu nécessaire, nettoyer l'ancien niveau et permettre les sélections de parcours, mélange de biomes, ordre aléatoire et playlists de 3, 9, 18 trous ou personnalisées.

## 7. Direction artistique et personnalisation

Créer un univers cartoon low-poly cohérent : couleurs lisibles, silhouettes expressives, objets reconnaissables, effets satisfaisants, interface soignée. Construire de vrais décors et accessoires avec des modèles originaux et des composants Roblox ; les placeholders temporaires ne valent pas finition.

Prévoir un avatar compatible avec les animations et proportions de collision choisies, un aperçu 3D de la tenue, des variantes de couleurs et plusieurs ensembles sauvegardables.

Catalogue minimal de 100 cosmétiques réellement équipables, hors simples recolorations :
- 25 têtes, chapeaux ou masques ;
- 15 coiffures, visages, lunettes ou accessoires du visage ;
- 20 tenues ;
- 10 paires de chaussures ;
- 15 apparences de clubs ;
- 10 apparences de balles ;
- 5 effets lorsque la balle entre dans le trou.

Ajouter au moins huit danses ou émotes avec une animation réelle. Exemples possibles : club poisson, cuillère géante, panneau inventé, baguette, maillet ; balle disco, œil cartoon, pelote, météorite ; chapeaux et costumes originaux humoristiques.

Les cosmétiques changent l'apparence uniquement : mêmes statistiques, même collision utile et même portée. Les animations ne doivent pas contourner les délais de frappe.

Créer boutique, aperçu, filtres, statut possédé/verrouillé, prix en monnaie du jeu, condition de déblocage et boutons acheter/équiper fonctionnels. Une sélection doit être visible pour les autres joueurs et conservée après reconnexion.

Ne fabrique pas d'AssetId. Utilise des assets créés pour le projet ou des ressources autorisées avec provenance vérifiable. Consigne les imports et permissions nécessaires dans un manifeste. Prévois une solution fonctionnelle générable localement lorsque l'upload d'une animation, image ou d'un son est indisponible, et indique les limites réelles.

## 8. Progression et sauvegarde

- Monnaie gagnée en jouant, récompenses de fin de partie, succès internes et achats cosmétiques.
- Prévoir au moins 30 défis variés : golf, précision, exploration, objets, survie, équipe et véhicules.
- Garder les succès internes fonctionnels sans exiger des BadgeId Roblox ; les badges de plateforme peuvent être raccordés ensuite à de vrais identifiants.
- Sauvegarder monnaie, inventaire, équipements, succès, statistiques utiles et préférences.
- Achats et récompenses décidés côté serveur, non duplicables, avec identifiants d'opération et traitement cohérent des reconnexions.
- Schéma versionné, migrations, gestion des accès concurrents, reprises bornées, limites de requêtes et sauvegarde de fermeture au mieux.
- Si le chargement échoue, ne pas écraser le profil existant avec un profil vide. Afficher un état honnête et empêcher les transactions dangereuses.
- Séparer données de développement/test et données réelles. Un adaptateur en mémoire doit être identifié comme non persistant ; il ne prouve pas que DataStore fonctionne.

Pas de mécanique pay-to-win ni de boutique Robux nécessaire à cette livraison.

## 9. Salons, interface et accessibilité

Créer un accueil jouable avec entraînement, boutique, personnalisation, sélection du mode et accès aux parties. Prévoir des parties publiques et privées entre amis selon les API Roblox disponibles ; documenter et tester séparément les fonctions qui nécessitent une expérience configurée ou un serveur réservé.

L'hôte peut configurer parcours, équipes, durée, vent, vitesse, objets et interactions entre balles. Les réglages ne changent pas arbitrairement au milieu d'un trou. Prévoir sélection équilibrée des équipes et transfert des droits d'hôte en cas de départ.

Interface complète : menus, visée, puissance, vent, par, compteur de coups, chronomètre, inventaire, effets actifs, classement, annonces de KO, résultats et podium. Les boutons réalisent les actions annoncées ; pas de faux écran de succès.

Assurer navigation manette, commandes tactiles confortables, caméra non gênante, textes lisibles, contrastes et indicateurs d'équipe autres que la couleur. Ajouter réglages sonores, sensibilité, vibrations/secousses si disponibles, réduction des effets et flashs.

Utiliser les communications et outils natifs Roblox : chat filtré et vocal seulement lorsque la plateforme et le compte l'autorisent. Le jeu doit rester entièrement jouable sans vocal. Ne crée pas de système parallèle contournant ces permissions.

## 10. Architecture et performances

Utiliser Luau typé et des modules aux responsabilités claires, avec séparation serveur/client/partagé. Éviter un script monolithique et les dépendances inutiles.

Services possibles : Match, Lobby, Course, Ball, Combat, Items, Vehicles, PlayerData, Rewards, Cosmetics, Achievements et NetworkValidation. Contrôleurs client : Input, Camera, GolfAim, HUD, Shop, Cosmetics et Effects. Adapter ces noms à l'existant.

Séparer les paramètres de gameplay du code. Conserver sur le serveur les données et décisions sensibles. Nettoyer connexions, tâches, contraintes, projectiles et effets après utilisation.

Limiter objets physiques et effets simultanés, réduire les calculs inutiles et les messages réseau, prévoir plusieurs niveaux de qualité. Mesurer les temps de frame, la mémoire, les instances et le réseau avec le matériel disponible. Viser 60 FPS sur le PC de référence documenté et 30 FPS sur un appareil mobile de référence ; ne pas annoncer ces objectifs comme atteints sans mesure réelle. Un émulateur d'écran ne prouve pas les performances d'un téléphone.

## 11. Exécution par étapes, sans réduire le périmètre final

1. Examiner l'environnement, écrire le cahier des charges et la matrice de couverture.
2. Construire une partie complète avec un trou, physique fiable, HUD, score et retour à l'accueil.
3. Valider le multijoueur, les états de partie et les commandes sur les supports visés.
4. Développer les 17 objets, véhicules et modes.
5. Finaliser les cinq biomes et les 81 trous.
6. Intégrer personnalisation, boutique, progression et sauvegarde.
7. Terminer présentation, animations, audio, accessibilité et optimisation.
8. Effectuer une revue complète, corriger les défauts et produire les preuves finales.

Après chaque étape, vérifie ce qui vient de changer puis poursuis l'étape suivante. Ne t'arrête pas après un plan ou un prototype en demandant si tu dois continuer. Si des sous-agents sont disponibles, délègue les tâches indépendantes avec une responsabilité claire et vérifie leur intégration.

Tiens à jour un état de reprise contenant décisions, fichiers modifiés, tests, problèmes et prochaine action, pour poursuivre sans perdre le contexte. Si une limitation externe empêche une partie du travail, termine les travaux indépendants et décris ce qui manque sans le déclarer accompli.

## 12. Validation et critères d'acceptation

Créer des tests utiles pour score, transitions, récompenses, achats, sauvegarde, validations réseau et interactions d'objets. Compléter avec de vrais playtests Studio :

- Sessions solo, deux clients, puis jusqu'à huit clients lorsque l'environnement le permet.
- Partie entière, plusieurs trous, résultats, récompense unique et retour à l'accueil.
- Départs simultanés, arrivée tardive, déconnexion, respawn, changement d'hôte et fin du délai.
- Frappes proches/lointaines, pentes, sable, glace, vent, collisions rapides et entrée dans le trou.
- Tous les objets et les interactions importantes de leur matrice.
- Tous les achats, équipements, rechargement des données et tentatives de double récompense.
- Erreurs simulées de sauvegarde et requêtes client invalides, répétées ou trop rapides.
- Chaque trou : validation structurelle et parcours réalisable ; consigner les inspections et playtests réellement effectués pour chacun des 81.
- Écrans PC/mobile, navigation manette, effets réduits et lisibilité en équipe.
- Plusieurs manches successives pour détecter fuites, objets résiduels et dégradation progressive.

Distinguer explicitement : analyse statique, test unitaire, simulation, test moteur avec plusieurs clients, test sur appareil physique et test sur service Roblox réel. Aucun ne remplace automatiquement les autres. Pour 16 joueurs, consigner un test séparé réalisable dans l'environnement disponible ; ne pas inventer une validation à 16 clients dans un outil limité à huit.

Une fonctionnalité est terminée si elle fonctionne de bout en bout, possède ses interfaces et assets nécessaires, se nettoie correctement, et dispose d'une preuve adaptée. Une configuration ou une animation seule ne suffit pas. Toute fonctionnalité ou carte non vérifiée conserve un statut explicite.

## 13. Livrables

- Projet source complet, configurations et dépendances reproductibles.
- Fichier .rbxl/.rbxlx réellement généré si l'outillage le permet, ou procédure précise de construction et d'import vérifiée dans les limites disponibles.
- Géométrie, UI et modèles inclus dans le projet ou générés de manière reproductible ; pas d'étape cachée demandant de construire manuellement les 81 niveaux.
- README en français : installation, ouverture, synchronisation, lancement, tests et configuration Roblox restante.
- Documents d'architecture, règles de gameplay, catalogue des 81 trous, registre des 17 objets, catalogue des cosmétiques et manifeste des assets.
- Matrice exigence → fichiers/systèmes → preuve de test → résultat → limite restante.
- Rapport final daté : contenu livré, commandes exécutées, résultats, captures si possibles, problèmes restants et démarches nécessaires avant publication.

Ne conclus pas « terminé » si les éléments majeurs sont absents ou si tu n'as pas pu vérifier le jeu dans Studio. Distingue clairement « implémenté », « testé » et « prêt à publier ».

## Références techniques à consulter

- Documentation Roblox, outils externes : https://create.roblox.com/docs/projects/external-tools
- Sécurité client-serveur : https://create.roblox.com/docs/scripting/security/client-server-boundary
- Propriété réseau : https://create.roblox.com/docs/physics/network-ownership
- Sauvegardes : https://create.roblox.com/docs/cloud-services/data-stores
- Tests Studio : https://create.roblox.com/docs/studio/testing-modes
- Téléportations : https://create.roblox.com/docs/projects/teleport
- Communications natives : https://create.roblox.com/docs/chat/in-experience-text-chat

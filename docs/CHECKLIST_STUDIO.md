# Check-list du test dans Roblox Studio (étape finale)

Tout le code des étapes 1 à 10 est écrit et vérifié **en local seulement** (217 tests sur 218, types sans diagnostic nouveau).
Rien n'a été joué dans Studio. Règles : ne jamais lancer une fenêtre Studio pendant qu'une fenêtre ouverte par l'utilisateur
existe ; ne pas modifier la place du compte (« super combat blox ») ; commits sur `dev/reprise`.

## 0. Démarrage
1. `rojo build` / serveur Rojo, ouvrir une place **vide de test** (pas la place du compte).
2. Sortie : aucun `[Boot] ... (Init|Start|require)` en erreur ; `ServerScriptService.Server:GetAttribute("BootFailures")` vide.
3. `Workspace.ItemEffects` et `Workspace.Karts` apparaissent à la première utilisation (pas avant).

## 1. Boucle de partie (solo, Play)
- Accueil : menu, boutons Boutique / Personnaliser / Défis / Émotes (touche V) ouvrent leurs écrans, Échap les ferme.
- Lancer une partie (menu hôte) sur les trous d'entraînement : intro → compte à rebours → jeu → résultats → podium → accueil.
- Visée / jauge / frappe, trou réussi, danger (eau, hors-limites) avec pénalité, abandon du trou.
- Cosmétiques : manche de club dans la main pendant l'animation, effet de trou joué.

## 2. Objets (touches 1 à 4 = case, E = utiliser ; manette L1/R1/R2)
Pour chacun, vérifier effet, durée, fin garantie (réapparition, fin de trou, déconnexion) et message de refus :
horn · espresso · cork_pistol · blunderbuss · magnet_shield · shroom_mine (désamorçage au poing, balle rapide)
· orbital_beam (cercle suit 2 s, fige 1,2 s) · confetti_rocket (maintenir : verrou 0,6 s, relâcher : tir) · kangaroo_boots
· rocket_club (visée = tir ×1,6 ; sinon mêlée ; sinon élan) · frost_bomb (gel 3 s, plateforme sur l'eau) · ninja_smoke
(transparence restaurée) · paparazzi_flash (voile blanc, « sans flash » atténue) · grumpy_cloud · rail_slinger (maintenir 1 s)
· mega_burger (échelle ×2,2 puis retour, décors cassables) · caddie_kart.
Points à surveiller : transparence de l'invisibilité sur tous les accessoires, `Character:ScaleTo` avec les tenues,
`CombatService.Punched` pour le champignon, bulle qui absorbe 3 coups mineurs / casse sur coup majeur.

## 3. Kart-Caddie
- Invite « Monter » sur le châssis, 8 places, conducteur = place 1 ; attribut joueur `InVehicle` posé/retiré.
- Conduite (W/S/A/D) : vitesse plafonnée à 60, braquage, pente, coincé 3 s → éjection ; R remet à l'endroit (délai 5 s).
- Écrasement > 25 studs/s : KO mineur ; > 40 : KO majeur + 1 point d'usure ; 3 points → explosion ; 45 s de vie.
- KO d'un passager : éjecté ; fin de trou : tous les karts disparaissent.
- Physique : le châssis est un bloc sans roues (LinearVelocity plan horizontal) : vérifier qu'il ne s'accroche pas au décor.

## 4. Multi-clients et finition
- 2 à 4 clients (Test > Local Server) : synchro des projectiles, des effets, du kart, des attributs Frozen / Dazzled / Giant.
- Latence simulée, performances (nombre de pièces d'effet), accessibilité (sans flash, effets réduits).
- Captures d'écran de l'accueil, d'un trou, de l'interface.

## Limites connues (à ne pas confondre avec des bugs)
- Échec de test local : `Items.spec` (tirage aléatoire de l'émulation, pas du jeu).
- 75 trous restants, tutoriel, spectateur complet, parties privées : hors du périmètre des étapes 1 à 10.
- Aperçu 3D des cosmétiques : remplacé par des pastilles de couleur.

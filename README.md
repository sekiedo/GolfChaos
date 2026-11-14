# Golf Chaos

Jeu Roblox de golf multijoueur simultané : course vers le trou, frappes, combats cartoon, objets,
voiturettes, 81 trous répartis sur cinq biomes, personnalisation et progression persistante.
Création originale (nom, interfaces, modèles, animations, niveaux) — voir `docs/CAHIER_DES_CHARGES.md`.

> État d'avancement réel, preuves et limites : `docs/ETAT_REPRISE.md` et `docs/MATRICE_COUVERTURE.md`.
> Ce README décrit les procédures ; il ne déclare pas une fonctionnalité terminée.

## Prérequis

- Windows 10/11, Roblox Studio à jour (testé : 0.747).
- Git (testé : 2.56).
- Rojo **7.7.1** : installé automatiquement dans `tools/` par `scripts/install-tools.ps1`
  (release officielle GitHub `rojo-rbx/rojo`, empreinte SHA-256 vérifiée ; aucune modification du PATH).

## Construire la place

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-tools.ps1   # une seule fois
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

Résultat : `build/GolfChaos.rbxlx`, place autonome ouvrable dans Studio. Tout le contenu (accueil,
trous, décors, interface) est généré par le code au lancement à partir des données de `src/`.

## Ouvrir dans Studio

```powershell
powershell -ExecutionPolicy Bypass -File scripts\open-studio.ps1 -Rebuild -CloseOld
```

Ouvre la place construite dans une **nouvelle fenêtre** Studio (la fenêtre de test précédente ouverte
par ce script est fermée ; aucune autre fenêtre n'est touchée). On peut aussi double-cliquer
`build/GolfChaos.rbxlx`.

## Source de vérité et synchronisation

- Les sources (`src/`, `default.project.json`) font foi. Une modification faite dans Studio sur la place
  construite est **écrasée** au build suivant : la reporter dans `src/`.
- Synchronisation en direct possible avec le plugin Rojo (`tools\rojo.exe serve`, puis « Connect » dans
  le plugin Rojo de Studio, à installer avec `tools\rojo.exe plugin install`). Le flux par défaut du projet
  n'en a pas besoin : build + ouverture.
- Pour publier vers une place existante : ouvrir `build/GolfChaos.rbxlx`, puis Fichier ▸ Publier sur
  Roblox en tant que… et choisir la place. **Non effectué** : la publication est une action volontaire.

## Lancer une partie

Dans Studio : bouton **Play** (ou **Test ▸ Clients et serveurs** pour plusieurs clients). Le joueur apparaît
dans l'accueil ; le premier joueur présent est l'hôte du salon.

## Tests

Tests unitaires (dans Studio, mode Édition, barre de commande ou outil MCP `execute_luau`) :

```lua
require(game.ServerStorage.Tests.Runner).run()            -- tous les tests
require(game.ServerStorage.Tests.Runner).run("Scoring")   -- filtrés par nom de fichier
```

Pendant un Play, le pont de test (Studio uniquement) donne accès aux services réellement démarrés :

```lua
game.ServerStorage.DevBridge:Invoke("state")       -- état de la partie, joueurs, balles
game.ServerStorage.DevBridge:Invoke("netStats")    -- requêtes acceptées / rejetées par remote
game.ServerStorage.DevBridge:Invoke("perf", 5)     -- mesures serveur sur 5 s
```

## Configuration Roblox restante (hors de ce dépôt)

- Sauvegardes réelles : publier la place, puis Paramètres du jeu ▸ Sécurité ▸ « Activer l'accès Studio
  aux services API ». Sans cela, le jeu utilise un adaptateur **en mémoire, non persistant**, signalé à l'écran.
- Parties privées entre amis (serveurs réservés) : nécessitent une expérience publiée ; non testables en Studio.
- Badges de plateforme : à raccorder plus tard à de vrais BadgeId (les succès internes fonctionnent sans).

## Arborescence

Voir `docs/ARCHITECTURE.md` (contrats, conventions, état répliqué, services).

## Prototype d'origine

Les 10 scripts présents au départ sont conservés dans `legacy/prototype-etape1/` (et dans l'historique
Git, branche `main`). Leur logique a été reprise et étendue dans `src/`.

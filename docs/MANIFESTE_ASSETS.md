# Manifeste des assets — Golf Chaos

> Registre de provenance de tout contenu qui n'est pas généré par le code. Il fait foi pour
> `src/shared/Config/Sounds.luau` : un identifiant n'entre dans le code qu'après avoir été consigné ici.
> Dernière vérification : **12/11/2026**, Roblox Studio 0.747, place locale `build/GolfChaos.rbxlx`
> (non publiée), mode Edit.

## Règles

1. **Aucun AssetId inventé.** Un identifiant n'est utilisé qu'après avoir été vu dans un résultat de
   recherche officiel du Creator Store, vérifié dans Studio et consigné dans ce manifeste.
2. **Origines autorisées, et seulement celles-ci :**
   - le **contenu intégré au moteur** (`rbxasset://…`) : polices `rbxasset://fonts/families/*.json`,
     sons `rbxasset://sounds/*` ;
   - l'**audio sous licence** publié par les comptes partenaires officiels de Roblox **ProSoundEffects**
     (descriptions « Courtesy of Pro Sound Effects ») et **APMOfficial** (« Courtesy of APM Music »),
     chacun avec une page Creator Store vérifiable.
3. **Tout autre uploader est refusé**, même gratuit et même avec le filtre « créateurs vérifiés » (ce
   filtre laisse passer d'autres comptes) : provenance invérifiable, fichiers souvent extraits d'autres
   jeux, réimports, sons générés par IA sans licence claire.
4. **Modèles, décors, trous, cosmétiques, interface, icônes et animations sont générés par code**
   (géométrie construite, interface instanciée, animations procédurales `Motor6D.Transform`) : aucun
   mesh, image, décalque ni animation importé.
5. Les sons du moteur ne servent qu'en **repli**, quand aucun asset sous licence ne convient.
6. **Procédure d'ajout d'un son :** recherche par mots-clés (le suffixe « (SFX) » aide à trouver Pro Sound
   Effects) → ne retenir que `creatorName` **exactement** `ProSoundEffects` ou `APMOfficial` → vérifier
   le chargement (point 7) → contrôler créateur, titre et durée (point 8) → consigner ici → seulement
   ensuite référencer l'ID dans `Config/Sounds.luau`.
7. **Vérification du chargement** (Studio, mode Edit, sans effet sur la place) :
   `ContentProvider:PreloadAsync` appliqué à des instances `Sound` temporaires **jamais parentées au
   DataModel**, détruites aussitôt. Attention : `PreloadAsync` appelé avec des **chaînes** d'ID charge
   l'ID comme une image et renvoie `Failure` pour tout audio (81/81 le 12/11/2026, fichiers du moteur
   compris) ; ce résultat n'a aucune valeur.
8. **Contrôle de provenance** (lecture seule) : `MarketplaceService:GetProductInfo` (`Creator.Name`,
   `AssetTypeId = 3` Audio) et `AssetService:GetAudioMetadataAsync` (titre, durée).
9. **Limite connue :** aucune écoute n'a été possible pendant la vérification ; les choix reposent sur les
   titres et descriptions officiels. Une validation à l'oreille reste à faire (voir « Remarques d'usage »).

## Contenu intégré du moteur

### Polices

- Usage autorisé : `Font.new("rbxasset://fonts/families/<Famille>.json", <graisse>, <style>)`.
- Polices effectivement utilisées par l'interface : *à compléter par le chantier UI
  (`client/UI/Theme.luau`)*. Aucune n'est encore référencée dans `src/`.
- Familles présentes dans le client Studio installé (dossier `content/fonts/families`, version
  `version-63eb6055af4e4688`, constaté le 12/11/2026) : AccanthisADFStd, AmaticSC, Arimo, Balthazar,
  Bangers, BuilderExtended, BuilderMono, BuilderSans, ComicNeueAngular, Creepster, DenkOne, Fondamento,
  FredokaOne, GrenzeGotisch, Guru, HighwayGothic, Inconsolata, IndieFlower, JosefinSans, Jura, Kalam,
  LegacyArial, LegacyArimo, LuckiestGuy, Merriweather, Michroma, Montserrat, NotoSansCJKFallback, Nunito,
  Oswald, PatrickHand, PermanentMarker, PressStart2P, Roboto, RobotoCondensed, RobotoMono, RomanAntique,
  Sarpanch, SourceSansPro, SpecialElite, TitilliumWeb, Ubuntu, Zekton.

### Sons

| Nom logique | Chemin | Réglage | Raison du repli | Statut de vérification |
| --- | --- | --- | --- | --- |
| `ui_hover` | `rbxasset://sounds/volume_slider.ogg` | volume 0,25 | Tic très doux certain ; le bouton sous licence le plus proche (« Dvd Player Button 14 (SFX) », en alternative ci-dessous) peut contenir un bruit mécanique | Chargé dans Studio (12/11/2026) |
| `rocket_explode` | `rbxasset://sounds/impact_explosion_03.mp3` | volume 0,85 | Les deux explosions courtes sous licence trouvées servent déjà (`mine_explode`, `blunderbuss_boom`) ; les autres durent 8 à 13 s | Chargé dans Studio (12/11/2026) |
| `spring_boing` | `rbxasset://sounds/action_jump.mp3` | pitch 1,25 | Aucun « boing » publié par ProSoundEffects ou APMOfficial trouvé | Chargé dans Studio (12/11/2026) |
| `giant_stomp` | `rbxasset://sounds/action_jump_land.mp3` | pitch 0,45, volume 1 | Aucun pas de géant ou impact lourd adapté trouvé chez les partenaires | Chargé dans Studio (12/11/2026) |

Autres sons du moteur présents dans le dossier de contenu (non utilisés, non préchargés) :
`action_falling.ogg`, `action_footsteps_plastic.mp3`, `action_get_up.mp3`, `action_swim.mp3`,
`impact_water.mp3`, `oof.ogg`, `ouch.ogg`.

La liste des fichiers `rbxasset://` n'est ni documentée officiellement ni garantie entre versions et
plateformes : tester sur chaque plateforme cible (voir `notes-techniques-roblox.md` §11).

## Audio sous licence (bibliothèque Roblox)

47 assets retenus, tous gratuits, tous de type Audio. Les durées proviennent de la description publiée
(ou des métadonnées `AssetService` quand la description n'en donne pas).

| Nom logique | assetId | Titre exact | Compte créateur | URL Creator Store | Durée | Statut de vérification |
| --- | --- | --- | --- | --- | --- | --- |
| `swing_whoosh` | 9120972321 | Wood Whoosh Slicing Air Quick Swings 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120972321 | 0,8 s | Chargé dans Studio (12/11/2026) |
| `ball_hit_drive` | 9114627278 | Golf Ball Regular Hits Snappy Club Impact 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114627278 | 2,6 s | Chargé dans Studio (12/11/2026) |
| `ball_hit_putt` | 9117373789 | Ping Pong Ball Bouncing On Wood Paddle 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117373789 | 0,4 s | Chargé dans Studio (12/11/2026) |
| `ball_bounce` | 9114626660 | Golf Ball Impact On Concrete Exterior 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114626660 | 0,3 s | Chargé dans Studio (12/11/2026) |
| `ball_cup_drop` | 9117374754 | Ping Pong Ball Bouncing On Wood Table 9 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117374754 | 0,9 s | Chargé dans Studio (12/11/2026) |
| `splash_water` | 9119482207 | Splash Thunking Impact 6 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119482207 | 2,3 s | Chargé dans Studio (12/11/2026) |
| `sand_thud` | 9118767941 | Sand Impacts 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9118767941 | 1,4 s | Chargé dans Studio (12/11/2026) |
| `ko_bonk` | 9125782351 | Pot Clank Hit Metal Pan Some Ring Handle Sto (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125782351 | 2,0 s | Chargé dans Studio (12/11/2026) |
| `punch_swish` | 9120708588 | Whoosh Fast Short Dull Several Versions 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120708588 | 0,7 s | Chargé dans Studio (12/11/2026) |
| `dive_whoosh` | 9120709477 | Whoosh Fast Short Dull Several Versions 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120709477 | 1,4 s | Chargé dans Studio (12/11/2026) |
| `countdown_beep` | 9117060347 | Nasa Transmission Beep 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117060347 | 1,0 s | Chargé dans Studio (12/11/2026) |
| `countdown_go` | 9117261702 | Pealess Whistle Referee Police 5 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117261702 | 0,7 s | Chargé dans Studio (12/11/2026) |
| `hole_in_one_fanfare` | 9045751710 | William Tell Overture (sting b) | APMOfficial | https://create.roblox.com/store/asset/9045751710 | 5 s | Chargé dans Studio (12/11/2026) |
| `birdie_sting` | 9043151108 | Get Up And Go - Tag2 | APMOfficial | https://create.roblox.com/store/asset/9043151108 | 3 s | Chargé dans Studio (12/11/2026) |
| `crowd_cheer` | 9112766176 | Crowd Cheer And Applause 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9112766176 | 41,5 s | Chargé dans Studio (12/11/2026) |
| `crowd_aww` | 9114010280 | Crowd Disappointment 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114010280 | 8,3 s | Chargé dans Studio (12/11/2026) |
| `ui_click` | 9117028855 | Moviola Toggle Switch Single Clicks Sharp 10 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117028855 | 1,1 s | Chargé dans Studio (12/11/2026) |
| `ui_error` | 9114282163 | Electronic Beeps Single Blurty Tone Blats 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114282163 | 1,1 s | Chargé dans Studio (12/11/2026) |
| `coins_reward` | 9113849583 | Coin Throws 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113849583 | 2,4 s | Chargé dans Studio (12/11/2026) |
| `item_box_pickup` | 9116395089 | Magic Glows Soft Clusters Of Chiming Hits 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9116395089 | 2,9 s | Chargé dans Studio (12/11/2026) |
| `horn_blast` | 9113072082 | Air Horn Various Lengths 6 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113072082 | 2,9 s | Chargé dans Studio (12/11/2026) |
| `espresso_slurp` | 9119159142 | Sip Coffee 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119159142 | 3,5 s | Chargé dans Studio (12/11/2026) |
| `cork_pop` | 9113856861 | Comic Expulsions Small Pops Tube Blows Wet 6 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113856861 | 1,4 s | Chargé dans Studio (12/11/2026) |
| `blunderbuss_boom` | 9119236757 | Small Explosion 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119236757 | 3,2 s | Chargé dans Studio (12/11/2026) |
| `shield_hum` | 9119807820 | Synthesized Tones Energy Hum Undulating 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119807820 | 27,0 s | Chargé dans Studio (12/11/2026) |
| `shield_break` | 9114592102 | Glass Breaks 11 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114592102 | 2,2 s | Chargé dans Studio (12/11/2026) |
| `cart_engine_loop` | 9112787518 | Go Kart Engine Constant 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9112787518 | 41,3 s | Chargé dans Studio (12/11/2026) |
| `cart_horn` | 9113438365 | Bike Horn Squeeze 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113438365 | 1,5 s | Chargé dans Studio (12/11/2026) |
| `mine_beep` | 9117060349 | Nasa Transmission Beep 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117060349 | 1,0 s | Chargé dans Studio (12/11/2026) |
| `mine_explode` | 9119236749 | Small Explosion 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119236749 | 2,9 s | Chargé dans Studio (12/11/2026) |
| `orbital_charge` | 9125805094 | Rising Synth Tone Ascending In Pitch Waverin (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125805094 | 4,1 s | Chargé dans Studio (12/11/2026) |
| `orbital_blast` | 9126102254 | Time Warp Big Explosion Blast Boom Tonal Tai (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9126102254 | 5,8 s | Chargé dans Studio (12/11/2026) |
| `rocket_launch` | 9113082843 | Airy Whoosh Blast 18 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113082843 | 5,6 s | Chargé dans Studio (12/11/2026) |
| `rocket_club_whoosh` | 9120709694 | Whoosh Fast Short Dull Several Versions 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120709694 | 1,1 s | Chargé dans Studio (12/11/2026) |
| `ice_freeze` | 9114858588 | Ice Crackle Large Block Cracks 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114858588 | 3,7 s | Chargé dans Studio (12/11/2026) |
| `ice_shatter` | 9125610305 | Ice Break Small Pieces Break Fall To Concret (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125610305 | 2,8 s | Chargé dans Studio (12/11/2026) |
| `smoke_puff` | 9117183939 | Pacifier 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117183939 | 0,6 s | Chargé dans Studio (12/11/2026) |
| `camera_flash` | 9113025799 | 35 Mm Still Camera 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9113025799 | 2,6 s | Chargé dans Studio (12/11/2026) |
| `thunder_crack` | 9126082854 | Synth Thunder Cracks Individual Explosion Bo (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9126082854 | 6,6 s | Chargé dans Studio (12/11/2026) |
| `rail_charge` | 9125805189 | Rising Synth Tone Ascending In Pitch Waverin (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125805189 | 3,5 s | Chargé dans Studio (12/11/2026) |
| `rail_fire` | 9116236630 | Laser Cannon 1702 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9116236630 | 1,4 s | Chargé dans Studio (12/11/2026) |
| `burger_chomp` | 9119056464 | Shark Bite Smaller Teeth Snaps 13 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119056464 | 0,3 s | Chargé dans Studio (12/11/2026) |
| `emote_party` | 9047214582 | Party In The Wild - Tag2 | APMOfficial | https://create.roblox.com/store/asset/9047214582 | 4 s | Chargé dans Studio (12/11/2026) |
| `music_lobby` | 9040475935 | Early Bird - 60, Alt | APMOfficial | https://create.roblox.com/store/asset/9040475935 | 61 s | Chargé dans Studio (12/11/2026) |
| `music_match` | 9047099304 | Game Day Warrior (a) | APMOfficial | https://create.roblox.com/store/asset/9047099304 | 125 s (métadonnées) | Chargé dans Studio (12/11/2026) |
| `music_podium` | 9043213948 | Opening Fanfare | APMOfficial | https://create.roblox.com/store/asset/9043213948 | 25 s | Chargé dans Studio (12/11/2026) |
| `music_tension` | 9041909063 | Wander Waltz (a 60) | APMOfficial | https://create.roblox.com/store/asset/9041909063 | 60 s | Chargé dans Studio (12/11/2026) |

Bibliothèques APM indiquées dans les descriptions : Juice Music (`hole_in_one_fanfare`), Spot On
(`birdie_sting`, `emote_party`, `music_lobby`), Conroy (`music_podium`), Ded Good (`music_tension`).
`music_match` n'a pas de description publiée (artiste selon les métadonnées : Markus Gleissner).

### Remarques d'usage (à valider à l'écoute)

- **Approximations** (aucun son partenaire exact trouvé, le titre décrit un son voisin) :
  `ball_hit_putt` et `ball_cup_drop` (balle de ping-pong jouée plus grave), `smoke_puff` (« pop » de la
  catégorie Cartoon), `burger_chomp` (claquement de dents), `ko_bonk` (coup sur une casserole),
  `rocket_club_whoosh` (whoosh générique joué plus grave).
- **Fichiers longs non bouclés**, à couper ou fondre dans `EffectsController` : `crowd_cheer` (41,5 s,
  ~4 s utiles), `crowd_aww` (8,3 s, ~3 s), `rocket_launch` (5,6 s), `orbital_blast` (5,8 s),
  `thunder_crack` (6,6 s).
- **Contenu à connaître** : `crowd_cheer` contient sifflets et chants (combat de boxe thaï) ;
  `cart_engine_loop` contient des montées en régime ; `cart_horn` enchaîne plusieurs pouets ;
  `countdown_beep` et `mine_beep` sont deux prises du même bip, distinguées par la hauteur (pitch 1,5).
- **Musiques** : `music_lobby`, `music_match` et `music_tension` sont prévues en boucle ; `music_podium`
  (fanfare de 25 s) est jouée une fois.

### Alternatives vérifiées (non utilisées)

Également trouvées chez les partenaires et chargées dans Studio, prêtes pour un remplacement après écoute.

| Usage possible | assetId | Titre exact | Compte créateur | URL Creator Store | Durée | Statut de vérification |
| --- | --- | --- | --- | --- | --- | --- |
| `swing_whoosh` | 9120972444 | Wood Whoosh Slicing Air Quick Swings 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120972444 | 0,8 s | Chargé dans Studio (12/11/2026) |
| `ball_hit_drive` | 9114627292 | Golf Ball Regular Hits Snappy Club Impact 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114627292 | 3,0 s | Chargé dans Studio (12/11/2026) |
| `ball_hit_putt`, `ball_bounce` | 9114626834 | Golf Ball Impact On Concrete Exterior 5 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114626834 | 0,3 s | Chargé dans Studio (12/11/2026) |
| `ball_cup_drop` | 9117374396 | Ping Pong Ball Bouncing On Wood Table 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117374396 | 1,8 s | Chargé dans Studio (12/11/2026) |
| `splash_water` | 9125703162 | Mud Puddle Splash Shallow Water Impacts Hits (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125703162 | 1,1 s | Chargé dans Studio (12/11/2026) |
| `punch_swish` | 9120709480 | Whoosh Fast Short Dull Several Versions 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9120709480 | 0,8 s | Chargé dans Studio (12/11/2026) |
| `countdown_beep`, `mine_beep` | 9117060368 | Nasa Transmission Beep 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117060368 | 1,0 s | Chargé dans Studio (12/11/2026) |
| `countdown_go` | 9117264449 | Pealess Whistle Referee Tornado 635 3 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117264449 | 0,5 s | Chargé dans Studio (12/11/2026) |
| `birdie_sting`, `emote_party` | 9042807094 | What Did You Just Say to Me? (sting) | APMOfficial | https://create.roblox.com/store/asset/9042807094 | 3 s | Chargé dans Studio (12/11/2026) |
| `emote_party` | 9040345493 | Giggle Water Sting | APMOfficial | https://create.roblox.com/store/asset/9040345493 | 3 s | Chargé dans Studio (12/11/2026) |
| `crowd_aww` | 9114010229 | Crowd Disappointment 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114010229 | 6,6 s | Chargé dans Studio (12/11/2026) |
| `ui_hover` | 9114212934 | Dvd Player Button 14 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114212934 | 0,5 s | Chargé dans Studio (12/11/2026) |
| `ui_error` | 9114282006 | Electronic Beeps Single Blurty Tone Blats 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114282006 | 1,1 s | Chargé dans Studio (12/11/2026) |
| `espresso_slurp` | 9114889946 | Juice Box Set Down At Tail 7 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114889946 | 0,9 s | Chargé dans Studio (12/11/2026) |
| `cork_pop`, `smoke_puff` | 9117848644 | Pops Mouth Popping Multiple Versions 7 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117848644 | 0,9 s | Chargé dans Studio (12/11/2026) |
| `shield_hum` | 9112889082 | Transformer Hum 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9112889082 | 36,0 s | Chargé dans Studio (12/11/2026) |
| `shield_break` | 9114591862 | Glass Breaks 10 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9114591862 | 2,1 s | Chargé dans Studio (12/11/2026) |
| `cart_engine_loop` | 9112787694 | Go Kart Exhaust Constant 2 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9112787694 | 73,8 s | Chargé dans Studio (12/11/2026) |
| `emote_party` | 9117241704 | Party Horn 20 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9117241704 | 1,7 s | Chargé dans Studio (12/11/2026) |
| `orbital_charge` | 9125804956 | Rising Synth Tone Ascending In Pitch Waverin (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125804956 | 5,1 s | Chargé dans Studio (12/11/2026) |
| `thunder_crack` | 9119841013 | Synth Thunder Tubular Cracks Rolls 1 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119841013 | 5,1 s | Chargé dans Studio (12/11/2026) |
| `rail_charge` | 9125805105 | Rising Synth Tone Ascending In Pitch Waverin (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9125805105 | 5,5 s | Chargé dans Studio (12/11/2026) |
| `rail_fire` | 9116228051 | Laser Cannon 506 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9116228051 | 2,0 s | Chargé dans Studio (12/11/2026) |
| `burger_chomp` | 9119055161 | Shark Bite Smaller Teeth Snaps 4 (SFX) | ProSoundEffects | https://create.roblox.com/store/asset/9119055161 | 1,0 s | Chargé dans Studio (12/11/2026) |
| `hole_in_one_fanfare` | 9047102381 | Game Day Warrior Sting 1 | APMOfficial | https://create.roblox.com/store/asset/9047102381 | non indiquée | Chargé dans Studio (12/11/2026) |
| `music_match` | 9047101942 | Game Day Warrior (a) 60 | APMOfficial | https://create.roblox.com/store/asset/9047101942 | 60 s (métadonnées) | Chargé dans Studio (12/11/2026) |
| `birdie_sting` | 9038578394 | Good Good Times (sting a) | APMOfficial | https://create.roblox.com/store/asset/9038578394 | 4 s | Chargé dans Studio (12/11/2026) |
| `music_tension` | 9041911669 | Wander Waltz (a 30) | APMOfficial | https://create.roblox.com/store/asset/9041911669 | 30 s | Chargé dans Studio (12/11/2026) |
| `music_podium` | 1836077174 | Triumphant And Ceremonial | APMOfficial | https://create.roblox.com/store/asset/1836077174 | non indiquée | Chargé dans Studio (12/11/2026) |
| `music_lobby` | 9044531189 | Early Birdy [Alternate] | APMOfficial | https://create.roblox.com/store/asset/9044531189 | 107 s | Chargé dans Studio (12/11/2026) |

Pour ces alternatives, le compte créateur est celui affiché par la recherche Creator Store ;
`GetProductInfo` n'a été lancé que sur les 47 assets retenus.

### Candidats écartés

- **Échec de chargement :** aucun. Les 81 contenus testés (47 retenus, 30 alternatives, 4 sons du moteur)
  ont renvoyé `Success` avec la méthode par instances `Sound` du point 7.
- **Écartés pour provenance** (exemples rencontrés pendant la recherche, aucun utilisé) : sons de golf et
  « cartoon bonk » publiés par des comptes individuels, sons annoncés comme extraits de jeux du commerce
  (TF2, Fortnite, Castle Crashers, ULTRAKILL, SCP : Containment Breach…), réimports « asset manager »,
  packs synthétisés publiés par des comptes non partenaires (ex. « Daily Sounds »), sons générés par IA
  (« Generated by Mirelo »), musiques de distributeurs non retenus par les règles (ex. DistrokidOfficial).

## Imports et permissions nécessaires

- **Aucun import et aucune permission à accorder** pour les assets ci-dessus : ce sont des audios publics
  et gratuits du catalogue partenaire de Roblox, référencés directement par leur ID (aucun upload, aucun
  partage d'expérience à configurer dans le Creator Dashboard). Les sons et polices du moteur sont fournis
  par le client Roblox.
- **Ne pas télécharger ni ré-importer ces fichiers** sous un autre compte : l'usage couvert est la
  référence à l'asset publié par le compte partenaire.
- **Re-vérification obligatoire après publication.** La vérification du 12/11/2026 a été faite en mode
  Edit sur une place non publiée. Après chaque publication, relancer la vérification en jeu publié
  (serveur et client ; PC, mobile, console), car Roblox peut modifier la disponibilité d'un audio
  (modération, retrait ou remplacement d'un titre du catalogue partenaire, évolution des licences).
  Un son indisponible doit échouer en silence (`EffectsController`) ; mettre alors à jour le statut et la
  date dans ce manifeste.

## Assets générés localement

Liste provisoire : tout le contenu visuel et animé est créé par code. Chaque chantier complète sa ligne
(module réel, méthode, preuve).

| Domaine | Module (prévu, voir `ARCHITECTURE.md`) | Méthode | Statut |
| --- | --- | --- | --- |
| Trous (81) et parcours | `shared/Data/Holes/*`, `server/Course/*` | Géométrie construite depuis les données de trous | À compléter (chantier parcours) |
| Accueil, décors et biomes | `server/Course/*` | Pièces, terrain et éclairage générés | À compléter |
| Balles et accessoires de golf | `server/Services/BallService` | Parts générées | À compléter |
| Objets (17) et projectiles | `server/Items/*` | Modèles construits par code | À compléter (chantier objets) |
| Véhicules (voiturette) | `server/Services/VehicleService` | Modèles construits par code | À compléter |
| Cosmétiques | `server/Cosmetics/*` | Parts et accessoires générés | À compléter |
| Interface et icônes | `client/UI/*` | Instances UI générées, polices du moteur, aucune image importée | À compléter (chantier UI) |
| Animations des personnages | `client/Controllers/AnimationController` | Procédural (`Motor6D.Transform`, attributs `AnimState`/`Emote`) | À compléter |
| Effets visuels | `client/Effects/*` | Particules, traînées et lumières paramétrées par code | À compléter |

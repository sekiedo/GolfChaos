--!strict
--[[
	Registre audio de Golf Chaos : nom logique -> définition d'un son.

	Règles de provenance (docs/MANIFESTE_ASSETS.md fait foi) :
	- Jamais d'AssetId inventé : chaque identifiant ci-dessous a été vu dans un résultat de recherche du
	  Creator Store, puis vérifié dans Studio le 12/11/2026 (chargement réussi, créateur et titre contrôlés).
	- Deux origines seulement :
	  1. l'audio sous licence publié par les comptes partenaires officiels de Roblox « ProSoundEffects »
	     (Pro Sound Effects) et « APMOfficial » (APM Music), avec une page Creator Store vérifiable ;
	  2. le contenu intégré au moteur (rbxasset://sounds/...), en repli seulement quand aucun asset sous
	     licence ne convient (source = "Moteur").
	- Tout autre uploader est refusé (provenance invérifiable, fichiers souvent extraits d'autres jeux).
	- Ajouter un son : rechercher (créateur exact), vérifier le chargement (PreloadAsync sur une instance
	  Sound temporaire non parentée), consigner l'entrée dans le manifeste, puis seulement l'ajouter ici.
	- Roblox peut changer la disponibilité d'un audio : re-vérifier après chaque publication ; un son qui
	  ne charge pas doit échouer en silence (EffectsController).

	Conventions :
	- volume : valeur relative 0..1, multipliée par le réglage du joueur de la catégorie (Sfx, Music, Ui).
	- pitch : vitesse de lecture (1 si absent) ; pitchVariance : écart aléatoire relatif maximal autour de
	  pitch (0.05 = ±5 %), pour éviter l'effet de répétition.
	- looped : lecture en boucle (ambiances, moteurs, musiques).
	- Les fichiers longs non bouclés (foule, décollage, tonnerre) sont à couper ou fondre par l'appelant.
	- Module de données pur : aucun effet de bord au require (aucune instance créée, aucun service appelé).
]]

export type SoundCategory = "Sfx" | "Music" | "Ui"
export type SoundSource = "ProSoundEffects" | "APMOfficial" | "Moteur"

export type SoundDef = {
	id: string, -- "rbxassetid://<nombre>" (sous licence) ou "rbxasset://sounds/<fichier>" (moteur)
	volume: number,
	pitch: number?,
	pitchVariance: number?,
	looped: boolean?,
	category: SoundCategory,
	source: SoundSource,
}

local Sounds: { [string]: SoundDef } = {
	----------------------------------------------------------------------------
	-- Golf
	----------------------------------------------------------------------------

	-- « Wood Whoosh Slicing Air Quick Swings 4 (SFX) », 0,8 s.
	swing_whoosh = {
		id = "rbxassetid://9120972321",
		volume = 0.6,
		pitchVariance = 0.08,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Golf Ball Regular Hits Snappy Club Impact 1 (SFX) », 2,6 s.
	ball_hit_drive = {
		id = "rbxassetid://9114627278",
		volume = 0.8,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Ping Pong Ball Bouncing On Wood Paddle 4 (SFX) », 0,4 s. Approximation : petit « toc » joué plus grave.
	ball_hit_putt = {
		id = "rbxassetid://9117373789",
		volume = 0.5,
		pitch = 0.8,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Golf Ball Impact On Concrete Exterior 1 (SFX) », 0,3 s.
	ball_bounce = {
		id = "rbxassetid://9114626660",
		volume = 0.45,
		pitchVariance = 0.12,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Ping Pong Ball Bouncing On Wood Table 9 (SFX) », 0,9 s. Approximation : rebonds décroissants joués
	-- plus graves (petit cliquetis de la balle dans le trou).
	ball_cup_drop = {
		id = "rbxassetid://9117374754",
		volume = 0.7,
		pitch = 0.75,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Splash Thunking Impact 6 (SFX) », 2,3 s.
	splash_water = {
		id = "rbxassetid://9119482207",
		volume = 0.7,
		pitchVariance = 0.06,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Sand Impacts 3 (SFX) », 1,4 s.
	sand_thud = {
		id = "rbxassetid://9118767941",
		volume = 0.6,
		pitchVariance = 0.08,
		category = "Sfx",
		source = "ProSoundEffects",
	},

	----------------------------------------------------------------------------
	-- Combat et personnages
	----------------------------------------------------------------------------

	-- « Pot Clank Hit Metal Pan Some Ring Handle Sto (SFX) », 2,0 s : coup de poêle façon cartoon.
	ko_bonk = {
		id = "rbxassetid://9125782351",
		volume = 0.75,
		pitch = 1.1,
		pitchVariance = 0.06,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Whoosh Fast Short Dull Several Versions 1 (SFX) », 0,7 s.
	punch_swish = {
		id = "rbxassetid://9120708588",
		volume = 0.55,
		pitchVariance = 0.1,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Whoosh Fast Short Dull Several Versions 2 (SFX) », 1,4 s.
	dive_whoosh = {
		id = "rbxassetid://9120709477",
		volume = 0.6,
		pitch = 0.9,
		pitchVariance = 0.06,
		category = "Sfx",
		source = "ProSoundEffects",
	},

	----------------------------------------------------------------------------
	-- Déroulement de la partie (compte à rebours, réactions, jingles)
	----------------------------------------------------------------------------

	-- « Nasa Transmission Beep 1 (SFX) », 1,0 s.
	countdown_beep = {
		id = "rbxassetid://9117060347",
		volume = 0.6,
		category = "Ui",
		source = "ProSoundEffects",
	},
	-- « Pealess Whistle Referee Police 5 (SFX) », 0,7 s : coup de sifflet du départ.
	countdown_go = {
		id = "rbxassetid://9117261702",
		volume = 0.7,
		category = "Ui",
		source = "ProSoundEffects",
	},
	-- « William Tell Overture (sting b) », 5 s (APM, bibliothèque Juice Music).
	hole_in_one_fanfare = {
		id = "rbxassetid://9045751710",
		volume = 0.7,
		category = "Music",
		source = "APMOfficial",
	},
	-- « Get Up And Go - Tag2 », 3 s (APM, bibliothèque Spot On).
	birdie_sting = {
		id = "rbxassetid://9043151108",
		volume = 0.6,
		category = "Music",
		source = "APMOfficial",
	},
	-- « Crowd Cheer And Applause 1 (SFX) », 41,5 s : à fondre après ~4 s.
	crowd_cheer = {
		id = "rbxassetid://9112766176",
		volume = 0.55,
		pitchVariance = 0.04,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Crowd Disappointment 1 (SFX) », 8,3 s : à fondre après ~3 s.
	crowd_aww = {
		id = "rbxassetid://9114010280",
		volume = 0.55,
		category = "Sfx",
		source = "ProSoundEffects",
	},

	----------------------------------------------------------------------------
	-- Interface
	----------------------------------------------------------------------------

	-- « Moviola Toggle Switch Single Clicks Sharp 10 (SFX) », 1,1 s.
	ui_click = {
		id = "rbxassetid://9117028855",
		volume = 0.5,
		pitchVariance = 0.03,
		category = "Ui",
		source = "ProSoundEffects",
	},
	-- Repli moteur : petit tic du curseur de volume de Roblox, plus sûr qu'un bouton mécanique sous
	-- licence pour un survol très discret (alternative consignée au manifeste).
	ui_hover = {
		id = "rbxasset://sounds/volume_slider.ogg",
		volume = 0.25,
		pitchVariance = 0.05,
		category = "Ui",
		source = "Moteur",
	},
	-- « Electronic Beeps Single Blurty Tone Blats 3 (SFX) », 1,1 s.
	ui_error = {
		id = "rbxassetid://9114282163",
		volume = 0.45,
		category = "Ui",
		source = "ProSoundEffects",
	},
	-- « Coin Throws 2 (SFX) », 2,4 s.
	coins_reward = {
		id = "rbxassetid://9113849583",
		volume = 0.6,
		pitchVariance = 0.05,
		category = "Ui",
		source = "ProSoundEffects",
	},

	----------------------------------------------------------------------------
	-- Objets
	----------------------------------------------------------------------------

	-- « Magic Glows Soft Clusters Of Chiming Hits 4 (SFX) », 2,9 s.
	item_box_pickup = {
		id = "rbxassetid://9116395089",
		volume = 0.6,
		pitchVariance = 0.04,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Air Horn Various Lengths 6 (SFX) », 2,9 s : Corne Tonitruante.
	horn_blast = {
		id = "rbxassetid://9113072082",
		volume = 0.9,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Sip Coffee 2 (SFX) », 3,5 s.
	espresso_slurp = {
		id = "rbxassetid://9119159142",
		volume = 0.7,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Comic Expulsions Small Pops Tube Blows Wet 6 (SFX) », 1,4 s : tir du pistolet à bouchon.
	cork_pop = {
		id = "rbxassetid://9113856861",
		volume = 0.7,
		pitchVariance = 0.08,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Small Explosion 2 (SFX) », 3,2 s, joué un peu plus aigu.
	blunderbuss_boom = {
		id = "rbxassetid://9119236757",
		volume = 0.85,
		pitch = 1.15,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Synthesized Tones Energy Hum Undulating 1 (SFX) », 27,0 s, en boucle.
	shield_hum = {
		id = "rbxassetid://9119807820",
		volume = 0.35,
		looped = true,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Glass Breaks 11 (SFX) », 2,2 s.
	shield_break = {
		id = "rbxassetid://9114592102",
		volume = 0.7,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Go Kart Engine Constant 2 (SFX) », 41,3 s, en boucle (contient quelques montées en régime).
	cart_engine_loop = {
		id = "rbxassetid://9112787518",
		volume = 0.4,
		looped = true,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Bike Horn Squeeze 2 (SFX) », 1,5 s (plusieurs pouets).
	cart_horn = {
		id = "rbxassetid://9113438365",
		volume = 0.7,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Nasa Transmission Beep 2 (SFX) », 1,0 s, joué plus aigu que le compte à rebours.
	mine_beep = {
		id = "rbxassetid://9117060349",
		volume = 0.5,
		pitch = 1.5,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Small Explosion 1 (SFX) », 2,9 s.
	mine_explode = {
		id = "rbxassetid://9119236749",
		volume = 0.85,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Rising Synth Tone Ascending In Pitch Waverin (SFX) », 4,1 s.
	orbital_charge = {
		id = "rbxassetid://9125805094",
		volume = 0.6,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Time Warp Big Explosion Blast Boom Tonal Tai (SFX) », 5,8 s.
	orbital_blast = {
		id = "rbxassetid://9126102254",
		volume = 0.9,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Airy Whoosh Blast 18 (SFX) », 5,6 s : à fondre après ~2 s si nécessaire.
	rocket_launch = {
		id = "rbxassetid://9113082843",
		volume = 0.7,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- Repli moteur : les deux explosions courtes sous licence trouvées servent déjà (mine, tromblon) et
	-- les autres durent de 8 à 13 s.
	rocket_explode = {
		id = "rbxasset://sounds/impact_explosion_03.mp3",
		volume = 0.85,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "Moteur",
	},
	-- Repli moteur : aucun « boing » sous licence trouvé ; saut du moteur joué plus aigu.
	spring_boing = {
		id = "rbxasset://sounds/action_jump.mp3",
		volume = 0.7,
		pitch = 1.25,
		category = "Sfx",
		source = "Moteur",
	},
	-- « Whoosh Fast Short Dull Several Versions 3 (SFX) », 1,1 s, joué plus grave.
	rocket_club_whoosh = {
		id = "rbxassetid://9120709694",
		volume = 0.7,
		pitch = 0.8,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Ice Crackle Large Block Cracks 3 (SFX) », 3,7 s.
	ice_freeze = {
		id = "rbxassetid://9114858588",
		volume = 0.6,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Ice Break Small Pieces Break Fall To Concret (SFX) », 2,8 s.
	ice_shatter = {
		id = "rbxassetid://9125610305",
		volume = 0.7,
		pitchVariance = 0.05,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Pacifier 4 (SFX) », 0,6 s (catégorie Cartoon). Approximation : « pouf » cartoon.
	smoke_puff = {
		id = "rbxassetid://9117183939",
		volume = 0.6,
		pitch = 0.9,
		pitchVariance = 0.08,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « 35 Mm Still Camera 2 (SFX) », 2,6 s.
	camera_flash = {
		id = "rbxassetid://9113025799",
		volume = 0.6,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Synth Thunder Cracks Individual Explosion Bo (SFX) », 6,6 s.
	thunder_crack = {
		id = "rbxassetid://9126082854",
		volume = 0.8,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Rising Synth Tone Ascending In Pitch Waverin (SFX) », 3,5 s (autre prise que orbital_charge).
	rail_charge = {
		id = "rbxassetid://9125805189",
		volume = 0.55,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Laser Cannon 1702 (SFX) », 1,4 s.
	rail_fire = {
		id = "rbxassetid://9116236630",
		volume = 0.75,
		pitchVariance = 0.04,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- « Shark Bite Smaller Teeth Snaps 13 (SFX) », 0,3 s. Approximation : « croc ! » de dents.
	burger_chomp = {
		id = "rbxassetid://9119056464",
		volume = 0.7,
		pitch = 1.15,
		pitchVariance = 0.08,
		category = "Sfx",
		source = "ProSoundEffects",
	},
	-- Repli moteur : aucun pas de géant sous licence trouvé ; atterrissage du moteur joué très grave.
	giant_stomp = {
		id = "rbxasset://sounds/action_jump_land.mp3",
		volume = 1,
		pitch = 0.45,
		category = "Sfx",
		source = "Moteur",
	},

	----------------------------------------------------------------------------
	-- Emotes
	----------------------------------------------------------------------------

	-- « Party In The Wild - Tag2 », 4 s (APM, bibliothèque Spot On).
	emote_party = {
		id = "rbxassetid://9047214582",
		volume = 0.6,
		category = "Music",
		source = "APMOfficial",
	},

	----------------------------------------------------------------------------
	-- Musiques
	----------------------------------------------------------------------------

	-- « Early Bird - 60, Alt », 61 s (APM, bibliothèque Spot On), en boucle.
	music_lobby = {
		id = "rbxassetid://9040475935",
		volume = 0.35,
		looped = true,
		category = "Music",
		source = "APMOfficial",
	},
	-- « Game Day Warrior (a) », 125 s (APM), en boucle.
	music_match = {
		id = "rbxassetid://9047099304",
		volume = 0.3,
		looped = true,
		category = "Music",
		source = "APMOfficial",
	},
	-- « Opening Fanfare », 25 s (APM, bibliothèque Conroy), jouée une fois.
	music_podium = {
		id = "rbxassetid://9043213948",
		volume = 0.45,
		category = "Music",
		source = "APMOfficial",
	},
	-- « Wander Waltz (a 60) », 60 s (APM, bibliothèque Ded Good), en boucle : suspense léger (prolongation).
	music_tension = {
		id = "rbxassetid://9041909063",
		volume = 0.35,
		looped = true,
		category = "Music",
		source = "APMOfficial",
	},
}

-- Configuration immuable : aucune modification à l'exécution.
for _, def in Sounds do
	table.freeze(def)
end

return table.freeze(Sounds)

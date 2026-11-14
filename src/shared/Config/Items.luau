--!strict
--[[
	Config.Items — registre des 17 objets (données uniquement ; comportements dans server/Items/<Id>.luau).
	Source de conception : docs/REGISTRE_OBJETS.md (à garder synchronisé). Distances en studs, durées en secondes.

	Champs communs :
	  id, order, nameKey/descKey/counterKey (Locale), glyph (pictogramme texte pour l'UI), color
	  category      "Attack" | "Mobility" | "Defense" | "Trap" | "Disrupt" | "Vehicle" | "Transform"
	  rarity        "Common" | "Rare" | "Epic"
	  weightLeader / weightLast : poids de tirage pour le meneur / le dernier (interpolés, voir Logic/ItemOdds)
	  mobilityBox   peut sortir d'une boîte de mobilité
	  range, duration, charges, cooldown (entre deux charges), windup (annonce/charge avant effet)
	  targets       catégories de cible : "Self" | "Enemy" | "Ball" | "Area" | "Vehicle" | "Water"
	  major         frappe majeure (détruit le bouclier + KO sans fort recul)
	  dodgeable     esquivable par plongeon (attribut Dodging)
	  shield        réaction de la Bulle Magnétique : "Absorb" | "Deflect" | "Breaks" | "Ignored"
	  allyEffect    "None" (alliés jamais affectés) | "Self"
	  hornSensitive peut être déclenché involontairement par la Corne Tonitruante
	  holdToUse     l'utilisation se fait en maintenant (verrouillage / charge) puis en relâchant
	  cleanup       ce qui est retiré en fin de manche / à la déconnexion (documentation + tests)
	  params        valeurs propres à l'objet
]]

export type ItemCategory = "Attack" | "Mobility" | "Defense" | "Trap" | "Disrupt" | "Vehicle" | "Transform"
export type ItemRarity = "Common" | "Rare" | "Epic"
export type ShieldReaction = "Absorb" | "Deflect" | "Breaks" | "Ignored"

export type ItemDef = {
	id: string,
	order: number,
	nameKey: string,
	descKey: string,
	counterKey: string,
	glyph: string,
	color: Color3,
	category: ItemCategory,
	rarity: ItemRarity,
	weightLeader: number,
	weightLast: number,
	mobilityBox: boolean,
	range: number,
	duration: number,
	charges: number,
	cooldown: number,
	windup: number,
	targets: { string },
	major: boolean,
	dodgeable: boolean,
	shield: ShieldReaction,
	allyEffect: "None" | "Self",
	hornSensitive: boolean,
	holdToUse: boolean,
	cleanup: { string },
	params: { [string]: any },
}

local Items = {}

-- Inventaire
Items.InventoryCapacity = 3 -- capacité initiale (documentée dans docs/REGISTRE_OBJETS.md)
Items.MinCapacity = 1
Items.MaxCapacity = 4
Items.GlobalUseCooldown = 0.25 -- délai minimal entre deux utilisations d'objets (anti-spam)
Items.MaxActiveMinesPerPlayer = 2

-- Règles transverses
Items.Shield = { MinorHitsAbsorbed = 3 } -- charges de la Bulle Magnétique
Items.Knockout = { MinorDuration = 1.8, MajorDuration = 3.0, MajorKnockback = 85, MinorKnockback = 35 }
Items.DodgeWindow = 0.35 -- durée de l'attribut Dodging (doit correspondre à Config.Gameplay)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { ItemDef } = {
	{
		id = "horn", order = 1, nameKey = "item.horn.name", descKey = "item.horn.desc", counterKey = "item.horn.counter",
		glyph = "📯", color = rgb(255, 196, 61), category = "Disrupt", rarity = "Common",
		weightLeader = 10, weightLast = 8, mobilityBox = false,
		range = 45, duration = 0, charges = 1, cooldown = 0, windup = 0.4,
		targets = { "Enemy" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = {},
		params = { AimBlockSeconds = 1.5, AccidentalUseChance = 0.35 },
	},
	{
		id = "espresso", order = 2, nameKey = "item.espresso.name", descKey = "item.espresso.desc", counterKey = "item.espresso.counter",
		glyph = "☕", color = rgb(146, 92, 52), category = "Mobility", rarity = "Common",
		weightLeader = 12, weightLast = 12, mobilityBox = true,
		range = 0, duration = 8, charges = 1, cooldown = 0, windup = 0,
		targets = { "Self" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "speedModifier" },
		params = { SpeedMultiplier = 1.45, JumpMultiplier = 1.15 },
	},
	{
		id = "cork_pistol", order = 3, nameKey = "item.cork_pistol.name", descKey = "item.cork_pistol.desc", counterKey = "item.cork_pistol.counter",
		glyph = "🍾", color = rgb(222, 184, 135), category = "Attack", rarity = "Common",
		weightLeader = 10, weightLast = 9, mobilityBox = false,
		range = 80, duration = 0, charges = 2, cooldown = 0.8, windup = 0,
		targets = { "Enemy" }, major = false, dodgeable = true, shield = "Deflect", allyEffect = "None",
		hornSensitive = true, holdToUse = false, cleanup = {},
		params = { KnockoutDuration = 1.8, Knockback = 25 },
	},
	{
		id = "blunderbuss", order = 4, nameKey = "item.blunderbuss.name", descKey = "item.blunderbuss.desc", counterKey = "item.blunderbuss.counter",
		glyph = "💥", color = rgb(181, 101, 29), category = "Attack", rarity = "Rare",
		weightLeader = 7, weightLast = 8, mobilityBox = false,
		range = 25, duration = 0, charges = 2, cooldown = 1.2, windup = 0,
		targets = { "Enemy", "Ball", "Self" }, major = false, dodgeable = true, shield = "Absorb", allyEffect = "None",
		hornSensitive = true, holdToUse = false, cleanup = { "displacementAllowance" },
		params = {
			ConeDegrees = 30, KnockoutRange = 12, KnockbackMax = 70, BallImpulse = 70,
			RecoilSpeed = 60, GroundAimPitchDegrees = -35, VerticalRecoilSpeed = 70, ExemptionSeconds = 1.5,
		},
	},
	{
		id = "magnet_shield", order = 5, nameKey = "item.magnet_shield.name", descKey = "item.magnet_shield.desc", counterKey = "item.magnet_shield.counter",
		glyph = "🧲", color = rgb(90, 170, 255), category = "Defense", rarity = "Rare",
		weightLeader = 7, weightLast = 7, mobilityBox = false,
		range = 0, duration = 12, charges = 1, cooldown = 0, windup = 0,
		targets = { "Self" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "shieldEffect" },
		params = { MinorHitsAbsorbed = 3, Radius = 4.5 },
	},
	{
		id = "caddie_kart", order = 6, nameKey = "item.caddie_kart.name", descKey = "item.caddie_kart.desc", counterKey = "item.caddie_kart.counter",
		glyph = "🛺", color = rgb(76, 199, 108), category = "Vehicle", rarity = "Rare",
		weightLeader = 6, weightLast = 9, mobilityBox = true,
		range = 8, duration = 45, charges = 1, cooldown = 0, windup = 0,
		targets = { "Vehicle" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "vehicle", "seats" },
		params = {
			Seats = 8, MaxSpeed = 60, RamMinSpeed = 25, MajorRamSpeed = 40, StructurePoints = 3,
			StuckEjectSeconds = 3, ResetCooldown = 5, SpawnDistance = 8,
		},
	},
	{
		id = "shroom_mine", order = 7, nameKey = "item.shroom_mine.name", descKey = "item.shroom_mine.desc", counterKey = "item.shroom_mine.counter",
		glyph = "🍄", color = rgb(230, 57, 70), category = "Trap", rarity = "Common",
		weightLeader = 9, weightLast = 8, mobilityBox = false,
		range = 6, duration = 60, charges = 1, cooldown = 0, windup = 1.5,
		targets = { "Area", "Enemy" }, major = true, dodgeable = false, shield = "Breaks", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "mine" },
		params = { TriggerRadius = 6, WarningSeconds = 0.6, ExplosionRadius = 8, KnockoutRadius = 6, DisarmPunchRange = 4, BallTriggerSpeed = 30 },
	},
	{
		id = "orbital_beam", order = 8, nameKey = "item.orbital_beam.name", descKey = "item.orbital_beam.desc", counterKey = "item.orbital_beam.counter",
		glyph = "🛰", color = rgb(255, 64, 64), category = "Attack", rarity = "Epic",
		weightLeader = 2, weightLast = 7, mobilityBox = false,
		range = 0, duration = 3.2, charges = 1, cooldown = 0, windup = 3.2,
		targets = { "Area", "Enemy" }, major = true, dodgeable = false, shield = "Breaks", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "telegraph" },
		params = { Radius = 7, FollowSeconds = 2.0, LockSeconds = 1.2, BallImpulse = 90, TargetRule = "BestPlacedOpponent" },
	},
	{
		id = "confetti_rocket", order = 9, nameKey = "item.confetti_rocket.name", descKey = "item.confetti_rocket.desc", counterKey = "item.confetti_rocket.counter",
		glyph = "🎆", color = rgb(255, 105, 180), category = "Attack", rarity = "Rare",
		weightLeader = 6, weightLast = 8, mobilityBox = false,
		range = 150, duration = 4, charges = 1, cooldown = 0, windup = 0.6,
		targets = { "Enemy" }, major = false, dodgeable = true, shield = "Deflect", allyEffect = "None",
		hornSensitive = true, holdToUse = true, cleanup = { "projectile" },
		params = { LockConeDegrees = 20, LockSeconds = 0.6, Speed = 70, TurnRateDegrees = 90, ExplosionRadius = 8, KnockoutRadius = 5 },
	},
	{
		id = "kangaroo_boots", order = 10, nameKey = "item.kangaroo_boots.name", descKey = "item.kangaroo_boots.desc", counterKey = "item.kangaroo_boots.counter",
		glyph = "🦘", color = rgb(255, 159, 67), category = "Mobility", rarity = "Common",
		weightLeader = 10, weightLast = 10, mobilityBox = true,
		range = 0, duration = 15, charges = 3, cooldown = 0, windup = 0,
		targets = { "Self" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "jumpModifier", "displacementAllowance" },
		params = { JumpMultiplier = 2.6, Bounds = 3 },
	},
	{
		id = "rocket_club", order = 11, nameKey = "item.rocket_club.name", descKey = "item.rocket_club.desc", counterKey = "item.rocket_club.counter",
		glyph = "🚀", color = rgb(255, 120, 40), category = "Attack", rarity = "Rare",
		weightLeader = 7, weightLast = 8, mobilityBox = true,
		range = 7, duration = 10, charges = 1, cooldown = 0, windup = 0,
		targets = { "Ball", "Enemy", "Self" }, major = true, dodgeable = true, shield = "Breaks", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "shotBoost", "displacementAllowance" },
		params = { ShotPowerMultiplier = 1.6, MeleeConeDegrees = 60, DashSpeed = 80, DashSeconds = 0.4 },
	},
	{
		id = "frost_bomb", order = 12, nameKey = "item.frost_bomb.name", descKey = "item.frost_bomb.desc", counterKey = "item.frost_bomb.counter",
		glyph = "❄", color = rgb(160, 230, 255), category = "Disrupt", rarity = "Rare",
		weightLeader = 7, weightLast = 8, mobilityBox = false,
		range = 40, duration = 3, charges = 1, cooldown = 0, windup = 0,
		targets = { "Area", "Enemy", "Ball", "Vehicle", "Water" }, major = false, dodgeable = false, shield = "Absorb", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "frozen", "icePlatform", "projectile" },
		params = { Radius = 9, FreezeSeconds = 3, PlatformRadius = 9, PlatformSeconds = 8, ThrowSpeed = 55, ThrowLoftDegrees = 35 },
	},
	{
		id = "ninja_smoke", order = 13, nameKey = "item.ninja_smoke.name", descKey = "item.ninja_smoke.desc", counterKey = "item.ninja_smoke.counter",
		glyph = "💨", color = rgb(120, 120, 140), category = "Defense", rarity = "Common",
		weightLeader = 8, weightLast = 8, mobilityBox = false,
		range = 10, duration = 6, charges = 1, cooldown = 0, windup = 0,
		targets = { "Self", "Area" }, major = false, dodgeable = false, shield = "Ignored", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "smokeCloud", "invisible" },
		params = { CloudRadius = 10, CloudSeconds = 6, InvisibleSeconds = 5, OthersTransparency = 0.92, AlliesTransparency = 0.5 },
	},
	{
		id = "paparazzi_flash", order = 14, nameKey = "item.paparazzi_flash.name", descKey = "item.paparazzi_flash.desc", counterKey = "item.paparazzi_flash.counter",
		glyph = "📸", color = rgb(255, 255, 210), category = "Disrupt", rarity = "Common",
		weightLeader = 9, weightLast = 8, mobilityBox = false,
		range = 30, duration = 2.5, charges = 1, cooldown = 0, windup = 0,
		targets = { "Enemy" }, major = false, dodgeable = false, shield = "Absorb", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "dazzled" },
		params = { ConeDegrees = 50, FacingDotMin = 0.2, SpeedMultiplier = 0.6, DazzleSeconds = 2.5 },
	},
	{
		id = "grumpy_cloud", order = 15, nameKey = "item.grumpy_cloud.name", descKey = "item.grumpy_cloud.desc", counterKey = "item.grumpy_cloud.counter",
		glyph = "⛈", color = rgb(110, 110, 180), category = "Disrupt", rarity = "Epic",
		weightLeader = 3, weightLast = 7, mobilityBox = false,
		range = 80, duration = 8, charges = 1, cooldown = 0, windup = 1,
		targets = { "Area", "Enemy", "Ball" }, major = false, dodgeable = false, shield = "Absorb", allyEffect = "None",
		hornSensitive = false, holdToUse = false, cleanup = { "stormCloud" },
		params = { DriftSpeed = 12, StrikeInterval = 2, StrikeWarning = 1, StrikeRadius = 5, KnockoutDuration = 2, Height = 28 },
	},
	{
		id = "rail_slinger", order = 16, nameKey = "item.rail_slinger.name", descKey = "item.rail_slinger.desc", counterKey = "item.rail_slinger.counter",
		glyph = "⚡", color = rgb(120, 255, 240), category = "Attack", rarity = "Epic",
		weightLeader = 2, weightLast = 6, mobilityBox = false,
		range = 140, duration = 0, charges = 1, cooldown = 0, windup = 1.0,
		targets = { "Enemy" }, major = true, dodgeable = true, shield = "Breaks", allyEffect = "None",
		hornSensitive = false, holdToUse = true, cleanup = { "telegraph" },
		params = { MaxTargets = 3, KnockbackScale = { 1.0, 0.7, 0.5 }, BeamRadius = 1.5 },
	},
	{
		id = "mega_burger", order = 17, nameKey = "item.mega_burger.name", descKey = "item.mega_burger.desc", counterKey = "item.mega_burger.counter",
		glyph = "🍔", color = rgb(222, 141, 47), category = "Transform", rarity = "Epic",
		weightLeader = 3, weightLast = 7, mobilityBox = false,
		range = 0, duration = 8, charges = 1, cooldown = 0, windup = 0,
		targets = { "Self", "Enemy", "Ball" }, major = true, dodgeable = false, shield = "Breaks", allyEffect = "Self",
		hornSensitive = false, holdToUse = false, cleanup = { "scale", "giant" },
		params = { Scale = 2.2, SpeedMultiplier = 0.85, ContactKnockout = 2, ContactKnockback = 90, BallImpulse = 80 },
	},
}

local byId: { [string]: ItemDef } = {}
for _, def in list do
	byId[def.id] = def
end

Items.List = list
Items.ById = byId

function Items.get(id: string): ItemDef?
	return byId[id]
end

function Items.all(): { ItemDef }
	return table.clone(list)
end

return Items

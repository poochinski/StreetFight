extends RefCounted
## Static game data: names, colors and per-enemy tuning in one place.

const FLOOR_NAMES = ["Neon Row", "The Burnt Mile", "Sunset Plaza"]
## Item tiers, lowest to highest. The same neon colors mark an item everywhere:
## name text, slot frames, ground labels and loot beams.
const RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS = [Color("dcd6ea"), Color("5dff8f"), Color("3fb8ff"), Color("c76bff"), Color("ffb438")]
const GOLD = Color("dfb86e")
const CREAM = Color("f0e5cf")
const MUTED = Color("9b9d99")

## Interface palette: dungeon stone and brass crossed with an 80s vaporwave sunset.
const NEON_PINK = Color("ff4fd8")
const NEON_CYAN = Color("3ff0ff")
const NEON_PURPLE = Color("9b5cff")
const SUNSET = Color("ff9a3c")
const SUN_YELLOW = Color("ffe45c")
const CHROME = Color("f6f0ff")
const PANEL = Color("170b29")
const PANEL_DEEP = Color("0c0616")
const PANEL_EDGE = Color("6b3fa0")
const INK = Color("e9e2ff")
const INK_MUTED = Color("9a8fbf")
const AFFIX_BLUE = Color("6fd8ff")
const UPGRADE = Color("5dff8f")
const DOWNGRADE = Color("ff5470")
const HEALTH = Color("ff3d6e")
const MANA = Color("38c8ff")

## Characters are drawn at this size in the world so a person stands well
## under a shop door and buildings read at true scale. Portraits are not scaled.
const CHARACTER_SCALE = 0.8

const ENEMY_NAMES = {"imp":"Ember Imp", "brute":"Ash Brute", "ranged":"Hex Caster", "boss":"The Ash Warden"}

## hp: base health (scaled +55% per floor; the boss is not scaled). speed: tiles/second.
## damage: hit damage before floor scaling. cooldown: seconds between attacks.
## windup: telegraph before a hit lands, so the player can react or dodge.
## reach: distance at which a melee attack starts and still connects.
## radius: body size for walls, separation and how far melee can reach it.
## height: screen height of the body, used for click targeting.
## interruptible: whether a hit cancels the wind-up. Brutes and the boss power through.
const ENEMIES = {
	"imp": {"hp":42.0,"speed":2.0,"damage":11.0,"cooldown":1.0,"windup":0.38,"reach":1.15,"xp":12,"radius":0.22,"height":25.0,"scale":1.0,"interruptible":true},
	"brute": {"hp":70.0,"speed":1.25,"damage":19.0,"cooldown":1.4,"windup":0.55,"reach":1.3,"xp":20,"radius":0.26,"height":32.0,"scale":1.35,"interruptible":false},
	"ranged": {"hp":34.0,"speed":1.35,"damage":13.0,"cooldown":2.3,"windup":0.45,"reach":7.0,"xp":12,"radius":0.22,"height":25.0,"scale":1.0,"interruptible":true},
	"boss": {"hp":1500.0,"speed":1.35,"damage":42.0,"cooldown":2.8,"windup":0.95,"reach":4.2,"xp":140,"radius":0.3,"height":58.0,"scale":2.0,"interruptible":false},
}
const RANGED_KEEP_DISTANCE = 4.5
const BOSS_SLAM_RADIUS = 3.3
const AGGRO_RANGE = 7.0
const LEASH_RANGE = 14.0
const PACK_ALERT_RANGE = 3.5

## Default weapon colors; Items.weapon_look tints these by material and rarity.
const DEFAULT_WEAPON_LOOK = {"style":"sword","blade":Color("b4beba"),"edge":Color("eef4ea"),"glow":Color("e9f4da")}

## Body armor looks by chest piece type: plate, shade, trim and cloak colors on the hero.
const ARMOR_LOOKS = {
	"leather": {"plate":Color("8a6446"),"shade":Color("5e4330"),"trim":Color("c39b60"),"cloak":Color("2f6b77")},
	"mail": {"plate":Color("8794a0"),"shade":Color("596570"),"trim":Color("8fd0e6"),"cloak":Color("27506a")},
	"plate": {"plate":Color("a7aebb"),"shade":Color("6a7180"),"trim":Color("f0cf7a"),"cloak":Color("5a2147")},
	"mantle": {"plate":Color("6c5a92"),"shade":Color("45396a"),"trim":Color("f0cf7a"),"cloak":Color("2c2550")},
	"denim": {"plate":Color("5a7fa8"),"shade":Color("3e5a7c"),"trim":Color("c8ccd4"),"cloak":Color("2a3a52")},
	"track": {"plate":Color("16a0a0"),"shade":Color("0e6e70"),"trim":Color("ff4fa8"),"cloak":Color("1a3a48")},
	"varsity": {"plate":Color("7a1f2e"),"shade":Color("54141f"),"trim":Color("efe8dc"),"cloak":Color("3a1018")},
	"duster": {"plate":Color("7a5634"),"shade":Color("54391f"),"trim":Color("c8a050"),"cloak":Color("5a3e24")},
	"riot": {"plate":Color("2a2a32"),"shade":Color("18181e"),"trim":Color("9aa2aa"),"cloak":Color("202028")},
	"robe": {"plate":Color("5a2a8a"),"shade":Color("3c1a60"),"trim":Color("ff4fd8"),"cloak":Color("2c1648")},
	"oyoroi": {"plate":Color("26262a"),"shade":Color("151517"),"trim":Color("e0b020"),"cloak":Color("5a1a1a")},
	"trench": {"plate":Color("1c1c22"),"shade":Color("0e0e12"),"trim":Color("ff4fd8"),"cloak":Color("141418")},
}

## Per-floor look of the ruined city: ground, building palettes, light and
## neon colors, sign words and the weather drifting over the screen.
## buildings: [front face, side face, roof, trim] per building style
## (brick, pink stucco, teal stucco, concrete, glass tower, warehouse metal).
const FLOOR_THEMES = [
	{"asphalt":[Color("2b2f3d"),Color("292c39"),Color("2e3242")],"asphalt_seam":Color("1d2029"),"lane":Color("d8b84a"),
		"sidewalk":[Color("575c6a"),Color("525665")],"sidewalk_seam":Color("3a3d49"),"curb":Color("8a8f9c"),
		"lot":Color("4a4c55"),"grass":Color("2f4a3a"),"dirt":Color("4a4038"),"rubble":Color("4b4645"),"pavers":Color("5b4f6b"),
		"soot":0.0,"light":Color("ffb35c"),"glow":Color("ff4fd8"),
		"neon":[Color("ff4fd8"),Color("3ff0ff"),Color("ffe45c"),Color("9b5cff"),Color("5dff8f")],
		"buildings":[[Color("6b3a36"),Color("4c2a29"),Color("2d2230"),Color("a8705a")],[Color("b0698a"),Color("7d4a66"),Color("3a2a40"),Color("ffd1e4")],
			[Color("3f8a8a"),Color("2b6266"),Color("223040"),Color("bff5ee")],[Color("6a6c75"),Color("4b4d57"),Color("2a2b35"),Color("9a9caa")],
			[Color("27405e"),Color("1b2e46"),Color("1a2236"),Color("6fd8ff")],[Color("56606a"),Color("3d454e"),Color("262b33"),Color("8a96a0")]],
		"signs":["ARCADE","VIDEO","MOTEL","DINER","DISCO","PIZZA","LAUNDRY","RECORDS","CINEMA","ROLLER RINK","TAPES","OPEN 24H","CLUB 88","TV REPAIR"],
		"weather":"rain","mote":Color(0.7,0.8,1.0)},
	{"asphalt":[Color("2e2a2a"),Color("2b2727"),Color("322c2a")],"asphalt_seam":Color("1c1918"),"lane":Color("c79a3a"),
		"sidewalk":[Color("5a524c"),Color("544c47")],"sidewalk_seam":Color("3b3532"),"curb":Color("857a70"),
		"lot":Color("47403b"),"grass":Color("3d3a28"),"dirt":Color("4d3d30"),"rubble":Color("4d4440"),"pavers":Color("5a4a48"),
		"soot":0.45,"light":Color("ff8a3a"),"glow":Color("ff6a2e"),
		"neon":[Color("ff4f6e"),Color("ff9a3c"),Color("ffe45c"),Color("ff4fd8"),Color("3ff0ff")],
		"buildings":[[Color("5e342c"),Color("43251f"),Color("261b1c"),Color("9a6048")],[Color("94606a"),Color("6a4048"),Color("2e2026"),Color("e6b9b0")],
			[Color("4a6a62"),Color("344c46"),Color("1f2626"),Color("a6d0c0")],[Color("5f5a58"),Color("45403e"),Color("252222"),Color("8e8680")],
			[Color("2e3a4a"),Color("212a36"),Color("1a1e26"),Color("e09a5a")],[Color("5a524a"),Color("403a34"),Color("26221e"),Color("958a7c")]],
		"signs":["LIQUOR","PAWN","GAS","AUTO PARTS","BAR","MOTEL","HOT DOGS","DONUTS","BOWLING","GUNS","CHECKS CASHED","DRIVE IN"],
		"weather":"ash","mote":Color(1.0,0.55,0.3)},
	{"asphalt":[Color("2c2838"),Color("2a2535"),Color("302a3d")],"asphalt_seam":Color("1c1826"),"lane":Color("ff6ad5"),
		"sidewalk":[Color("5e5670"),Color("58506a")],"sidewalk_seam":Color("3c3650"),"curb":Color("a094c0"),
		"lot":Color("4a4458"),"grass":Color("2e3f45"),"dirt":Color("4a3e48"),"rubble":Color("4a4252"),"pavers":Color("5d4a72"),
		"soot":0.15,"light":Color("ff7ad8"),"glow":Color("9b5cff"),
		"neon":[Color("ff4fd8"),Color("3ff0ff"),Color("9b5cff"),Color("ffe45c"),Color("ff9a3c")],
		"buildings":[[Color("7a4a7a"),Color("573558"),Color("2e2240"),Color("ffb0f0")],[Color("c07aa0"),Color("8a5476"),Color("3a2848"),Color("ffe0f4")],
			[Color("4aa0a8"),Color("327078"),Color("223048"),Color("c6fbff")],[Color("6e6a80"),Color("4e4b60"),Color("2a2838"),Color("b0a8d0")],
			[Color("2c3a6a"),Color("1e2a50"),Color("1a1e3a"),Color("ff7ad8")],[Color("5a5a72"),Color("404056"),Color("262636"),Color("a09cc0")]],
		"signs":["SUNSET MALL","FOOD COURT","CINEMA","ARCADE","SYNTHWAVE","VHS","PLAZA","NEON","DREAMS","SURF SHOP","MALL","STARLIGHT"],
		"weather":"glitter","mote":Color(1.0,0.6,0.95)},
]

extends RefCounted
## Items: equipment slots, item bases, rarity tiers, affixes, sockets and gems,
## generated names, the hero stats that gear adds up to, and comparisons.
##
## An item is a plain Dictionary so it saves to JSON as is:
##   slot      weapon, helmet, chest, gloves, boots, belt, ring, amulet or gem
##   base      base type ("Katana", "Helm"); style/look pick its art
##   rarity    0 Common, 1 Uncommon, 2 Rare, 3 Epic, 4 Legendary
##   level     item level, which is also the level needed to equip it
##   min/max/speed (weapons) or armor (armor pieces)
##   affixes   [[stat key, value], ...]; sockets and gems (socketed gem items)

const Data = preload("res://scripts/data.gd")

const EQUIP_SLOTS = ["helmet", "amulet", "chest", "gloves", "belt", "ring1", "ring2", "boots", "weapon"]
const SLOT_LABELS = {"helmet":"Helmet", "amulet":"Amulet", "chest":"Chest", "gloves":"Gloves", "belt":"Belt",
	"ring1":"Ring", "ring2":"Ring", "boots":"Boots", "weapon":"Weapon"}
const BAG_SIZE = 40
const STAT_POINTS_PER_LEVEL = 5
const ATTRIBUTES = ["strength", "dexterity", "focus", "vitality"]
## The average time between combo swings and the combo's average power, for DPS.
const SWING_TIME = 0.293
const COMBO_POWER = 1.1

const RARITY_POWER = [1.0, 1.08, 1.17, 1.28, 1.42]
const AFFIX_COUNT = [[0, 0], [1, 1], [2, 3], [3, 4], [5, 5]]
const SOCKET_SLOTS = ["weapon", "helmet", "chest", "amulet"]
const MATERIALS = ["Rusted", "Iron", "Steel", "Chrome", "Neon"]
const JEWEL_MATERIALS = ["Copper", "Silver", "Gold", "Chrome", "Prism"]
const SLOT_WEIGHTS = {"weapon":3.0, "chest":2.0, "helmet":1.5, "gloves":1.2, "boots":1.2, "belt":1.0, "ring":1.0, "amulet":0.8}

const BASES = {
	"weapon": [
		{"name":"Short Sword", "style":"sword", "min":12, "max":17, "speed":1.0},
		{"name":"Cleaver", "style":"cleaver", "min":14, "max":21, "speed":0.92},
		{"name":"Leafblade", "style":"leaf", "min":11, "max":16, "speed":1.12},
		{"name":"Saber", "style":"saber", "min":11, "max":18, "speed":1.08},
		{"name":"Greatsword", "style":"great", "min":19, "max":28, "speed":0.82},
		{"name":"Axe", "style":"axe", "min":15, "max":21, "speed":0.94},
		{"name":"Mace", "style":"mace", "min":16, "max":19, "speed":0.95},
		{"name":"Katana", "style":"katana", "min":12, "max":19, "speed":1.15},
	],
	"helmet": [{"name":"Coif", "style":"coif", "armor":2}, {"name":"Helm", "style":"helm", "armor":3}, {"name":"Visor", "style":"visor", "armor":3}],
	"chest": [{"name":"Jerkin", "look":"leather", "armor":5}, {"name":"Hauberk", "look":"mail", "armor":7},
		{"name":"Cuirass", "look":"plate", "armor":8}, {"name":"Mantle", "look":"mantle", "armor":6}],
	"gloves": [{"name":"Gloves", "style":"gloves", "armor":1}, {"name":"Gauntlets", "style":"gauntlets", "armor":2}],
	"boots": [{"name":"Boots", "style":"boots", "armor":1}, {"name":"Greaves", "style":"greaves", "armor":2}],
	"belt": [{"name":"Belt", "style":"belt", "armor":1}, {"name":"Sash", "style":"sash", "armor":1}],
	"ring": [{"name":"Ring", "style":"ring"}, {"name":"Band", "style":"band"}],
	"amulet": [{"name":"Amulet", "style":"amulet"}, {"name":"Talisman", "style":"talisman"}],
}

const JEWELRY = ["ring", "amulet"]
const ARMOR_SLOTS = ["helmet", "chest", "gloves", "boots", "belt"]
const ALL_SLOTS = ["weapon", "helmet", "chest", "gloves", "boots", "belt", "ring", "amulet"]

## label: tooltip text. min/max: roll at item level 1. grow: added per item level.
## weight: how much the stat counts when comparing items for the upgrade arrows.
const AFFIXES = {
	"strength": {"label":"+%d Strength", "min":2, "max":5, "grow":0.6, "slots":ALL_SLOTS, "prefix":"Brutal", "suffix":"of the Ox", "weight":1.3},
	"dexterity": {"label":"+%d Dexterity", "min":2, "max":5, "grow":0.6, "slots":ALL_SLOTS, "prefix":"Swift", "suffix":"of the Fox", "weight":1.1},
	"focus": {"label":"+%d Focus", "min":2, "max":5, "grow":0.6, "slots":ALL_SLOTS, "prefix":"Arcane", "suffix":"of the Mind", "weight":0.9},
	"vitality": {"label":"+%d Vitality", "min":2, "max":5, "grow":0.6, "slots":ALL_SLOTS, "prefix":"Stalwart", "suffix":"of the Bear", "weight":1.1},
	"max_hp": {"label":"+%d Maximum Health", "min":8, "max":16, "grow":2.5, "slots":["helmet", "chest", "belt", "boots", "amulet", "ring"], "prefix":"Hale", "suffix":"of Life", "weight":0.3},
	"armor": {"label":"+%d Armor", "min":2, "max":5, "grow":0.8, "slots":["helmet", "chest", "gloves", "boots", "belt", "amulet"], "prefix":"Reinforced", "suffix":"of Warding", "weight":1.4},
	"fire": {"label":"+%d Fire Damage", "min":2, "max":5, "grow":0.9, "slots":["weapon", "gloves", "ring", "amulet"], "prefix":"Scorching", "suffix":"of Embers", "weight":1.0},
	"ice": {"label":"+%d Ice Damage", "min":2, "max":4, "grow":0.8, "slots":["weapon", "gloves", "ring", "amulet"], "prefix":"Frozen", "suffix":"of Frost", "weight":1.1},
	"shock": {"label":"+%d Shock Damage", "min":1, "max":6, "grow":0.9, "slots":["weapon", "gloves", "ring", "amulet"], "prefix":"Voltaic", "suffix":"of Static", "weight":1.0},
	"poison": {"label":"+%d Poison Damage", "min":2, "max":5, "grow":0.9, "slots":["weapon", "gloves", "ring", "amulet"], "prefix":"Venomous", "suffix":"of Blight", "weight":1.0},
	"attack_speed": {"label":"+%d%% Attack Speed", "min":3, "max":7, "grow":0.3, "slots":["weapon", "gloves", "ring", "amulet"], "prefix":"Quick", "suffix":"of Haste", "weight":1.6},
	"crit": {"label":"+%d%% Critical Hit Chance", "min":2, "max":4, "grow":0.2, "slots":["weapon", "helmet", "gloves", "ring", "amulet"], "prefix":"Keen", "suffix":"of Precision", "weight":2.0},
	"crit_damage": {"label":"+%d%% Critical Damage", "min":10, "max":20, "grow":1.2, "slots":["weapon", "helmet", "amulet", "ring"], "prefix":"Cruel", "suffix":"of Slaughter", "weight":0.3},
	"gold_find": {"label":"+%d%% Gold Found", "min":8, "max":18, "grow":1.0, "slots":["helmet", "gloves", "ring", "amulet", "belt"], "prefix":"Lucky", "suffix":"of Fortune", "weight":0.15},
	"life_on_kill": {"label":"+%d Health per Kill", "min":2, "max":5, "grow":0.4, "slots":["weapon", "gloves", "ring", "belt"], "prefix":"Vampiric", "suffix":"of the Leech", "weight":0.8},
	"mana_regen": {"label":"+%d%% Mana Regeneration", "min":10, "max":25, "grow":1.0, "slots":["helmet", "amulet", "ring", "belt"], "prefix":"Humming", "suffix":"of the Synth", "weight":0.12},
	"nova_damage": {"label":"+%d%% Ember Nova Damage", "min":10, "max":22, "grow":1.2, "slots":["weapon", "helmet", "chest", "amulet"], "prefix":"Radiant", "suffix":"of the Sunset", "weight":0.25},
	"move_speed": {"label":"+%d%% Movement Speed", "min":3, "max":7, "grow":0.2, "slots":["boots"], "prefix":"Fleet", "suffix":"of the Wind", "weight":1.0},
}

const ELEMENTS = ["fire", "ice", "shock", "poison"]
const ELEMENT_COLORS = {"fire":Color("ff7a3c"), "ice":Color("6fe3ff"), "shock":Color("ffe45c"), "poison":Color("7dff6a")}

## Gems socket into gear. The same gem gives one bonus in a weapon and another in armor or jewelry.
const GEMS = {
	"ruby": {"name":"Ruby", "color":Color("ff3b5c"), "weapon":["fire", 4], "armor":["strength", 3]},
	"sapphire": {"name":"Sapphire", "color":Color("3f7bff"), "weapon":["ice", 4], "armor":["armor", 4]},
	"emerald": {"name":"Emerald", "color":Color("37f08a"), "weapon":["poison", 4], "armor":["max_hp", 12]},
	"amethyst": {"name":"Amethyst", "color":Color("b45cff"), "weapon":["crit_damage", 12], "armor":["focus", 3]},
	"topaz": {"name":"Topaz", "color":Color("ffd23f"), "weapon":["shock", 4], "armor":["dexterity", 3]},
}
const GEM_TIERS = ["Chipped", "Polished", "Radiant"]
const GEM_POWER = [1.0, 2.0, 3.5]

const EPIC_WORDS = [["Neon", "Vapor", "Laser", "Midnight", "Synth", "Chrome", "Prism", "Static", "Hologram", "Arcade", "Dusk", "Velvet"],
	["Requiem", "Oath", "Pulse", "Dirge", "Halo", "Vow", "Echo", "Fang", "Bloom", "Reverie", "Mirage", "Cascade"]]

## One unique name per slot family, with a line of flavor text.
const LEGENDARIES = {
	"weapon": [{"name":"Outrun Edge", "flavor":"Forged at 88 miles per hour."}, {"name":"Miami Nightfall", "flavor":"The sun sets twice on those it cuts."},
		{"name":"The Last Arcade", "flavor":"Insert coin. Continue? 9... 8..."}, {"name":"Sunset Executioner", "flavor":"Pink sky, red ground."}],
	"helmet": [{"name":"Crown of the Grid", "flavor":"It hums with a neon horizon."}],
	"chest": [{"name":"Chrome Sarcophagus", "flavor":"Polished by a thousand reflections."}],
	"gloves": [{"name":"Hands of the Synth", "flavor":"Every blow lands on the beat."}],
	"boots": [{"name":"Nightdrive Treads", "flavor":"They leave light trails on stone."}],
	"belt": [{"name":"Cassette Girdle", "flavor":"Side B is all battle hymns."}],
	"ring": [{"name":"Loop of Eternal Dusk", "flavor":"The light never quite goes out."}],
	"amulet": [{"name":"Heart of the Dying Mall", "flavor":"A fountain coin that came back."}],
}

# --- Starting gear and lookups ---------------------------------------------------

static func starter_weapon() -> Dictionary:
	return {"slot":"weapon", "base":"Short Sword", "style":"sword", "name":"Wayfarer’s Blade", "rarity":0, "level":1,
		"min":12, "max":17, "speed":1.0, "affixes":[], "sockets":0, "gems":[], "value":4, "flavor":""}

static func starter_chest() -> Dictionary:
	return {"slot":"chest", "base":"Jerkin", "look":"leather", "name":"Worn Leather", "rarity":0, "level":1,
		"armor":3, "affixes":[], "sockets":0, "gems":[], "value":3, "flavor":""}

static func empty_equipment() -> Dictionary:
	var equipment = {}
	for slot in EQUIP_SLOTS: equipment[slot] = null
	return equipment

static func empty_bag() -> Array:
	var bag: Array = []
	bag.resize(BAG_SIZE)
	return bag

## Whether an item can go in an equipment slot (either ring slot takes a ring).
static func fits(item, slot: String) -> bool:
	if item==null: return true
	if item.slot=="ring": return slot in ["ring1", "ring2"]
	return item.slot==slot

static func color(item) -> Color:
	return Data.RARITY_COLORS[clampi(int(item.rarity), 0, 4)]

static func is_gem(item) -> bool:
	return item!=null and item.slot=="gem"

static func type_line(item) -> String:
	if is_gem(item): return "Gem"
	return "%s %s" % [Data.RARITIES[int(item.rarity)], item.base]

static func affix_text(key: String, value: float) -> String:
	return AFFIXES[key].label % int(value)

static func speed_word(speed: float) -> String:
	return "Very Fast" if speed>=1.12 else "Fast" if speed>=1.04 else "Average" if speed>=0.93 else "Slow"

## The flat elemental damage a weapon carries on its own affixes and gems.
static func own_elements(item) -> Dictionary:
	var result = {"fire":0.0, "ice":0.0, "shock":0.0, "poison":0.0}
	for a in item.affixes:
		if a[0] in result: result[a[0]] += a[1]
	for gem in item.gems:
		var effect = gem_effect(gem, item.slot=="weapon")
		if effect[0] in result: result[effect[0]] += effect[1]
	return result

static func dps(item) -> float:
	if item==null or item.slot!="weapon": return 0.0
	var extra = 0.0
	var speed_bonus = 0.0
	var elements = own_elements(item)
	for key in elements: extra += elements[key]
	for a in item.affixes:
		if a[0]=="attack_speed": speed_bonus += a[1]
	return ((item.min+item.max)/2.0+extra)*COMBO_POWER*item.speed*(1+speed_bonus/100.0)/SWING_TIME

## The element that dominates a weapon, which colors its glow, swing trail and hit sparks.
static func main_element(item) -> String:
	if item==null: return ""
	var elements = own_elements(item)
	var best = ""
	var amount = 0.0
	for key in elements:
		if elements[key]>amount:
			amount = elements[key]
			best = key
	return best

static func weapon_look(item) -> Dictionary:
	if item==null: return {"style":"none", "blade":Color.WHITE, "edge":Color.WHITE, "glow":Color.WHITE}
	var tier = clampi((int(item.level)-1)/3, 0, 4)
	var blades = [Color("8f9597"), Color("a3acb0"), Color("bcc7cc"), Color("d6dde6"), Color("a8f4ff")]
	var blade: Color = blades[tier]
	var rarity = int(item.rarity)
	var glow = Data.RARITY_COLORS[rarity] if rarity>=2 else Color("e9f4da")
	var element = main_element(item)
	if element!="": glow = ELEMENT_COLORS[element]
	if rarity==4: blade = Color("ffcf6a").lerp(Data.NEON_PINK, 0.25)
	elif rarity==3: blade = blade.lerp(Color("2d2242"), 0.55)
	if item.get("style", "")=="great" and rarity<3: blade = blade.lerp(Color("3b2d52"), 0.4)
	return {"style":item.get("style", "sword"), "blade":blade, "edge":Color.WHITE.lerp(glow, 0.35), "glow":glow}

static func armor_look(item) -> Dictionary:
	var look: Dictionary = Data.ARMOR_LOOKS.get(item.get("look", "leather") if item else "leather", Data.ARMOR_LOOKS.leather).duplicate()
	if item and int(item.rarity)>=2: look.trim = look.trim.lerp(color(item), 0.65)
	if item and int(item.rarity)>=3: look.cloak = look.cloak.lerp(color(item).darkened(0.45), 0.5)
	return look

## The metal or leather color of an armor piece, brightening with item level.
static func material_color(item, metal: bool) -> Color:
	var tier = clampi((int(item.get("level", 1))-1)/3, 0, 4)
	var steel = [Color("6f6a66"), Color("8d959a"), Color("aab4bb"), Color("d0d8e2"), Color("b8f6ff")]
	var leather = [Color("5e4330"), Color("6b4a32"), Color("7a5a40"), Color("8a6446"), Color("9a7050")]
	return steel[tier] if metal else leather[tier]

# --- Gems ---------------------------------------------------------------------

static func make_gem(kind: String, tier: int) -> Dictionary:
	return {"slot":"gem", "gem":kind, "tier":tier, "base":"Gem", "name":"%s %s" % [GEM_TIERS[tier], GEMS[kind].name],
		"rarity":tier+1, "level":1, "affixes":[], "sockets":0, "gems":[], "value":10*(tier+1)*(tier+1), "flavor":""}

static func gem_effect(gem: Dictionary, in_weapon: bool) -> Array:
	var effect = GEMS[gem.gem]["weapon" if in_weapon else "armor"]
	return [effect[0], roundi(effect[1]*GEM_POWER[int(gem.tier)])]

static func open_sockets(item) -> int:
	if item==null or is_gem(item): return 0
	return int(item.sockets)-item.gems.size()

# --- Generation ---------------------------------------------------------------

## Rolls a rarity. luck multiplies the chance of every tier above Common.
static func roll_rarity(g, luck: float = 1.0) -> int:
	var r = g._random()
	var depth = 1+(g.floor_number-1)*0.35
	var chances = [0.006, 0.035, 0.12, 0.32]
	var total = 0.0
	for i in 4:
		total += chances[i]*luck*depth
		if r<total: return 4-i
	return 0

static func _pick(g, list: Array):
	return list[mini(floori(g._random()*list.size()), list.size()-1)]

static func _pick_slot(g) -> String:
	var total = 0.0
	for key in SLOT_WEIGHTS: total += SLOT_WEIGHTS[key]
	var r = g._random()*total
	for key in SLOT_WEIGHTS:
		r -= SLOT_WEIGHTS[key]
		if r<=0: return key
	return "weapon"

static func generate(g, level: int, rarity: int, slot: String = "") -> Dictionary:
	if slot=="": slot = _pick_slot(g)
	level = maxi(1, level)
	var base: Dictionary = _pick(g, BASES[slot])
	var tier = clampi((level-1)/3, 0, 4)
	var item = {"slot":slot, "base":base.name, "rarity":rarity, "level":level, "affixes":[], "sockets":0, "gems":[], "flavor":""}
	if base.has("style"): item.style = base.style
	if base.has("look"): item.look = base.look
	if slot=="weapon":
		var power = (1+(level-1)*0.1)*RARITY_POWER[rarity]
		item.min = roundi(base.min*power)
		item.max = roundi(base.max*power)
		item.speed = base.speed
	elif base.has("armor"):
		item.armor = roundi(base.armor*(1+(level-1)*0.18)*RARITY_POWER[rarity])
	var range_count: Array = AFFIX_COUNT[rarity]
	var count = range_count[0]+floori(g._random()*(range_count[1]-range_count[0]+1))
	var pool: Array = []
	for key in AFFIXES:
		if slot in AFFIXES[key].slots: pool.append(key)
	for i in mini(count, pool.size()):
		var key = pool[floori(g._random()*pool.size())]
		pool.erase(key)
		var spec = AFFIXES[key]
		var value = lerpf(spec.min, spec.max, g._random())+(level-1)*spec.grow
		item.affixes.append([key, maxi(1, roundi(value*(1+rarity*0.08)))])
	if slot in SOCKET_SLOTS:
		var socket_chance = [0.15, 0.3, 0.55, 0.9, 1.0][rarity]
		if g._random()<socket_chance: item.sockets = 1
		if rarity>=3 and g._random()<0.5: item.sockets = 2
		if rarity==4: item.sockets = 2
	item.name = _name(g, item, base, tier)
	item.value = roundi((6+level*2.5)*(1+rarity*1.5))
	return item

static func _name(g, item: Dictionary, base: Dictionary, tier: int) -> String:
	var rarity = int(item.rarity)
	var materials = JEWEL_MATERIALS if item.slot in JEWELRY else MATERIALS
	if rarity==0 or item.affixes.is_empty(): return "%s %s" % [materials[tier], base.name]
	if rarity==1: return "%s %s" % [AFFIXES[item.affixes[0][0]].prefix, base.name]
	if rarity==2:
		var suffix = AFFIXES[item.affixes[1][0]].suffix if item.affixes.size()>1 else "of the Deep"
		return "%s %s %s" % [AFFIXES[item.affixes[0][0]].prefix, base.name, suffix]
	if rarity==3: return "%s %s" % [_pick(g, EPIC_WORDS[0]), _pick(g, EPIC_WORDS[1])]
	var unique: Dictionary = _pick(g, LEGENDARIES[item.slot])
	item.flavor = unique.flavor
	return unique.name

## A random drop for the current floor: gear near the hero's level, or sometimes a gem.
static func random_drop(g, luck: float = 1.0) -> Dictionary:
	if g._random()<0.14:
		var kind = _pick(g, GEMS.keys())
		var tier = 2 if g._random()<0.08*g.floor_number else 1 if g._random()<0.3*g.floor_number else 0
		return make_gem(kind, tier)
	var level = int(g.player.level)+(g.floor_number-1)+floori(g._random()*3)-1
	return generate(g, level, roll_rarity(g, luck))

# --- Hero stats -------------------------------------------------------------------

static func gear_totals(equipment: Dictionary) -> Dictionary:
	var totals = {"armor_base":0.0}
	for key in AFFIXES: totals[key] = 0.0
	for slot in EQUIP_SLOTS:
		var item = equipment.get(slot)
		if item==null: continue
		if item.has("armor"): totals.armor_base += item.armor
		for a in item.affixes: totals[a[0]] += a[1]
		for gem in item.gems:
			var effect = gem_effect(gem, slot=="weapon")
			totals[effect[0]] += effect[1]
	return totals

## Everything the hero's attributes, level and gear add up to.
static func derive(player: Dictionary) -> Dictionary:
	var totals = gear_totals(player.equipment)
	var d = {}
	for key in ATTRIBUTES:
		d[key+"_base"] = float(player.attributes[key])
		d[key] = float(player.attributes[key])+totals[key]
	var weapon = player.equipment.get("weapon")
	var power = 1+d.strength*0.03
	d.damage_min = (float(weapon.min) if weapon else 3.0)*power
	d.damage_max = (float(weapon.max) if weapon else 5.0)*power
	d.elements = {}
	d.element_total = 0.0
	for key in ELEMENTS:
		d.elements[key] = totals[key]
		d.element_total += totals[key]
	d.attack_speed = (float(weapon.speed) if weapon else 1.1)*(1+totals.attack_speed/100.0)
	d.crit = minf(75, d.dexterity*0.5+totals.crit)
	d.crit_damage = 50+d.strength*1.0+totals.crit_damage
	d.evade = minf(30, d.dexterity*0.3)
	d.armor = totals.armor_base+totals.armor
	d.reduction = minf(0.75, d.armor/(d.armor+60))
	d.max_hp = 80+int(player.level)*20+d.vitality*4+totals.max_hp
	d.max_mana = 40+d.focus*4
	d.mana_regen = (4+d.focus*0.15)*(1+totals.mana_regen/100.0)
	d.nova_power = (1+d.focus*0.04)*(1+totals.nova_damage/100.0)
	d.gold_find = totals.gold_find
	d.life_on_kill = totals.life_on_kill
	d.move_speed = minf(25, totals.move_speed)
	var average = (d.damage_min+d.damage_max)/2+d.element_total
	d.dps = average*(1+d.crit/100*d.crit_damage/100)*COMBO_POWER*d.attack_speed/SWING_TIME
	return d

# --- Comparison ---------------------------------------------------------------

## A single number for how good an item is, used for the upgrade arrows on loot.
static func score(item) -> float:
	if item==null: return 0.0
	var total = dps(item)*0.6+float(item.get("armor", 0))*1.5
	for a in item.affixes: total += a[1]*AFFIXES[a[0]].weight
	for gem in item.gems:
		var effect = gem_effect(gem, item.slot=="weapon")
		total += effect[1]*AFFIXES[effect[0]].weight
	total += open_sockets(item)*3
	return total

## The equipped item a new item would replace: for rings, the empty or weaker one.
static func compared_slot(item, equipment: Dictionary) -> String:
	if item==null or is_gem(item): return ""
	if item.slot=="ring":
		if equipment.ring1==null: return "ring1"
		if equipment.ring2==null: return "ring2"
		return "ring1" if score(equipment.ring1)<=score(equipment.ring2) else "ring2"
	return item.slot

## +3 to -3: how much better (or worse) an item is than what it would replace.
static func upgrade_steps(item, equipment: Dictionary) -> int:
	var slot = compared_slot(item, equipment)
	if slot=="": return 0
	var current = equipment.get(slot)
	var new_score = score(item)
	var old_score = score(current)
	if current==null: return 3
	if absf(new_score-old_score)<0.5: return 0
	var ratio = new_score/maxf(0.1, old_score)
	if ratio>=1.3: return 3
	if ratio>=1.12: return 2
	if ratio>1.0: return 1
	if ratio<=0.75: return -2
	return -1

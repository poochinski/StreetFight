extends RefCounted
## Diablo-style elite packs and knockback.
##
## Champion packs: every member is a blue "champion" sharing one or two traits.
## Rare packs: one gold-named leader with several traits, plus tougher minions.
## Traits change how the enemy fights; elites hit harder, have more health and
## drop better loot. Knockback shoves enemies on heavy hits.

const Data = preload("res://scripts/data.gd")
const Effects = preload("res://scripts/effects.gd")
const Items = preload("res://scripts/items.gd")

const CHAMPION_BLUE = Color("6fa8ff")
const RARE_GOLD = Color("ffd24a")
const MINION_GOLD = Color("e0c890")

## name: shown on the nameplate. text: what it does, for the README and tooltips.
const AFFIXES = {
	"turbo": {"name":"Turbo", "text":"Moves and attacks much faster."},
	"molten": {"name":"Molten", "text":"Its hits set you on fire, and it explodes when it dies."},
	"vampiric": {"name":"Vampiric", "text":"Heals itself when it hits you."},
	"chrome": {"name":"Chrome Plated", "text":"Takes 40% less damage."},
	"overcharged": {"name":"Overcharged", "text":"Hitting it can arc lightning back at you."},
	"juggernaut": {"name":"Juggernaut", "text":"Extra health; can't be knocked back or staggered."},
}
const NAME_FRONT = ["Neon", "Chrome", "Static", "Rust", "Ash", "Volt", "Grim", "Hex", "Toxic", "Laser", "Vinyl", "Cobalt"]
const NAME_BACK = ["jaw", "bone", "skull", "fang", "grin", "spine", "howl", "rib", "claw", "tooth"]
const NAME_TITLE = ["the Unbroken", "the Flickering", "the Hungry", "the Overclocked", "the Wretched", "the Radiant", "the Hollow", "the Rewound"]

## How strongly each enemy type is pushed by knockback.
const KNOCK_RESIST = {"imp":1.0, "ranged":1.0, "brute":0.55, "boss":0.0}
const KNOCK_FRICTION = 24.0

# --- Making elite packs ------------------------------------------------------------

## Chance that a pack on this floor is an elite pack, and what kind.
static func roll_pack(g, number: int) -> String:
	var roll = g._random()
	var rare_chance = 0.04+number*0.03
	var champion_chance = 0.06+number*0.03
	if roll<rare_chance: return "rare"
	if roll<rare_chance+champion_chance: return "champion"
	return ""

## Turns a freshly spawned pack into an elite pack.
static func promote_pack(g, pack: Array, rank: String, number: int) -> void:
	if pack.is_empty(): return
	if rank=="champion":
		var traits = _pick_affixes(g, 1 if number==1 else 2)
		for e in pack: _make_elite(g, e, "champion", traits)
	else:
		var leader = pack[0]
		_make_elite(g, leader, "rare", _pick_affixes(g, 2 if number==1 else 3))
		leader.elite.name = _rare_name(g)
		for k in range(1, pack.size()):
			var minion = pack[k]
			minion.minion = true
			minion.max_hp *= 1.3; minion.hp = minion.max_hp
			minion.damage_mult = 1.1

static func _pick_affixes(g, count: int) -> Array:
	var pool = AFFIXES.keys()
	var picked: Array = []
	while picked.size()<count and not pool.is_empty():
		var i = floori(g._random()*pool.size())
		picked.append(pool[i])
		pool.remove_at(i)
	return picked

static func _rare_name(g) -> String:
	var front: String = NAME_FRONT[floori(g._random()*NAME_FRONT.size())]
	var back: String = NAME_BACK[floori(g._random()*NAME_BACK.size())]
	var title: String = NAME_TITLE[floori(g._random()*NAME_TITLE.size())]
	return "%s%s %s" % [front, back, title]

static func _make_elite(g, e: Dictionary, rank: String, affixes: Array) -> void:
	var rare = rank=="rare"
	e.elite = {"rank":rank, "affixes":affixes.duplicate(), "name":""}
	var hp_mult = 3.4 if rare else 2.2
	if "juggernaut" in affixes: hp_mult *= 1.6
	e.max_hp *= hp_mult; e.hp = e.max_hp
	e.damage_mult = 1.4 if rare else 1.25
	e.size_mult = 1.25 if rare else 1.12
	e.xp_mult = 4.0 if rare else 2.5
	if "turbo" in affixes:
		e.speed_mult = 1.5
		e.cooldown_mult = 0.72

## Nameplate text, e.g. "Voltjaw the Hungry" or "Champion Ash Brute".
static func title(e: Dictionary) -> String:
	if e.has("elite"):
		if e.elite.rank=="rare": return e.elite.name
		return "Champion %s" % Data.ENEMY_NAMES[e.kind]
	if e.get("minion", false): return "%s Minion" % Data.ENEMY_NAMES[e.kind]
	return Data.ENEMY_NAMES[e.kind]

static func traits_text(e: Dictionary) -> String:
	if not e.has("elite"): return ""
	var names: Array = []
	for a in e.elite.affixes: names.append(AFFIXES[a].name)
	return ", ".join(names)

static func color(e: Dictionary) -> Color:
	if e.has("elite"): return RARE_GOLD if e.elite.rank=="rare" else CHAMPION_BLUE
	if e.get("minion", false): return MINION_GOLD
	return Color(1, 1, 1)

static func has_affix(e: Dictionary, affix: String) -> bool:
	return e.has("elite") and affix in e.elite.affixes

# --- Combat hooks --------------------------------------------------------------------

## Damage an elite actually takes.
static func adjust_damage(e: Dictionary, amount: int) -> int:
	if has_affix(e, "chrome"): return maxi(1, roundi(amount*0.6))
	return amount

## Called after an enemy takes a hit.
static func on_damaged(g, e: Dictionary) -> void:
	if e.hp<=0 or not has_affix(e, "overcharged"): return
	if e.pos.distance_to(g.player.pos)>3.0 or g._random()>0.22: return
	Effects.add(g, "arc", {"from":e.pos, "to":g.player.pos, "seed":randi()}, 0.25)
	g._tone(880, 0.08, "saw", 0.015)
	g._hurt(6.0+g.floor_number*3.0)

## Called when an enemy's attack lands on the hero.
static func on_hit_hero(g, e: Dictionary, damage: float) -> void:
	if has_affix(e, "vampiric"):
		var heal = damage*1.5
		e.hp = minf(e.max_hp, e.hp+heal)
		g._float_text(e.pos, "+%d" % roundi(heal), Color("ff5470"))
	if has_affix(e, "molten"):
		g.player.burn = 2.5
		g.player.burn_dps = 3.0+g.floor_number*2.0

## Called when an enemy dies: elite loot and Molten's death blast.
static func on_death(g, e: Dictionary) -> void:
	if has_affix(e, "molten"):
		g.hazards.append({"kind":"molten", "pos":e.pos, "delay":0.9, "max_delay":0.9, "radius":2.2,
			"damage":14.0+g.floor_number*8.0})
	if not e.has("elite"): return
	var rare = e.elite.rank=="rare"
	g._drop_gold(e.pos, floori(g._between(12, 30))*g.floor_number*(2 if rare else 1))
	if rare:
		g._drop_item(e.pos, Items.generate(g, int(g.player.level)+1, 2+(1 if g._random()<0.35 else 0)))
		if g._random()<0.6: g._drop_item(e.pos, Items.random_drop(g, 3.0))
	elif g._random()<0.55:
		g._drop_item(e.pos, Items.random_drop(g, 2.0))

## Hazards left by enemies (Molten's blast). The hero sees a ring before it goes off.
static func update_hazards(g, dt: float) -> void:
	for h in g.hazards:
		h.delay -= dt
		if h.delay<=0 and not h.get("done", false):
			h.done = true
			Effects.shockwave(g, h.pos, h.radius, Color("ff6a2a"), true)
			g._burst(h.pos, Color("ff8a3a"), 24, 4)
			g._tone(80, 0.3, "saw", 0.04)
			g.shake = maxf(g.shake, 3.0)
			if g.player.pos.distance_to(h.pos)<h.radius: g._hurt(h.damage)
	g.hazards = g.hazards.filter(func(h): return not h.get("done", false))

## The hero burning from a Molten hit.
static func update_hero_burn(g, dt: float) -> void:
	if g.player.get("burn", 0.0)<=0: return
	g.player.burn -= dt
	g.player.burn_tick = g.player.get("burn_tick", 0.0)+dt
	if g.player.burn_tick>=0.5:
		g.player.burn_tick = 0.0
		var amount = g.player.burn_dps*0.5
		g.player.hp = maxf(0, g.player.hp-amount)
		g._float_text(g.player.pos, "−%d" % ceili(amount), Color("ff8a3a"))
		if g.player.hp<=0: g._finish(false)

# --- Knockback -----------------------------------------------------------------------

## Shoves an enemy away from a point. strength is the starting speed in cells per second.
static func knock(e: Dictionary, from: Vector2, strength: float) -> void:
	if e.hp<=0 or has_affix(e, "juggernaut"): return
	var resist: float = KNOCK_RESIST.get(e.kind, 1.0)
	if e.has("elite"): resist *= 0.6
	if resist<=0: return
	var dir = e.pos-from
	dir = dir.normalized() if dir.length()>0.01 else Vector2.RIGHT
	e.knock = dir*strength*resist

## Moves a knocked-back enemy. Returns true while the shove still controls it.
static func update_knock(g, e: Dictionary, dt: float) -> bool:
	var k: Vector2 = e.get("knock", Vector2.ZERO)
	if k==Vector2.ZERO: return false
	g._move(e, k*dt, Data.ENEMIES[e.kind].radius)
	k = k.move_toward(Vector2.ZERO, KNOCK_FRICTION*dt)
	e.knock = k
	if k.length()>1.2:
		# A hard shove breaks a light enemy's wind-up.
		if e.windup>0 and Data.ENEMIES[e.kind].interruptible:
			e.windup = 0
			e.attack = maxf(e.attack, 0.4)
		return true
	return false

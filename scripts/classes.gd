extends RefCounted
## Hero classes. Each has its own starting attributes, a basic attack on the left
## mouse button and four skills learned at levels 1, 2, 4 and 6. Skill effects
## that outlive a single frame live in g.shots (projectiles), g.zones (grenades,
## frost fields, meteors, barrages) and player.channel (whirlwind, fan the hammer).

const Data = preload("res://scripts/data.gd")
const Effects = preload("res://scripts/effects.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")

const UNLOCK_LEVELS = [1, 2, 4, 6]
const ORDER = ["samurai", "gunslinger", "synth_mage"]

const CLASSES = {
	"samurai": {"name":"Street Samurai", "role":"Melee fighter", "color":Color("ff9a4a"),
		"text":"A blade for hire who wades into the crowd. Tough, hits hard up close.",
		"attack":"slash", "range":0.0, "attributes":{"strength":7, "dexterity":5, "focus":3, "vitality":5},
		"skills":["nova", "dash", "whirlwind", "slam"]},
	"gunslinger": {"name":"Gunslinger", "role":"Ranged shooter", "color":Color("3ff0ff"),
		"text":"Fast hands and a chrome revolver. Kills from a distance, crits often.",
		"attack":"shot", "range":8.5, "attributes":{"strength":4, "dexterity":8, "focus":4, "vitality":4},
		"skills":["scatter", "grenade", "fan", "barrage"]},
	"synth_mage": {"name":"Synth Mage", "role":"Spellcaster", "color":Color("c86bff"),
		"text":"Bends neon and static into spells. Fragile, but clears whole streets.",
		"attack":"bolt", "range":8.0, "attributes":{"strength":3, "dexterity":4, "focus":9, "vitality":4},
		"skills":["arc", "frost", "nova", "meteor"]},
}

## cost in mana, cooldown in seconds, power as a multiple of a weapon hit.
const SKILLS = {
	"slash": {"name":"Slash", "cost":0, "cooldown":0.0, "power":1.0, "text":"A three-swing combo. The third swing hits 30% harder."},
	"shot": {"name":"Revolver Shot", "cost":0, "cooldown":0.0, "power":1.0, "text":"A fast bullet at the target under the cursor."},
	"bolt": {"name":"Laser Bolt", "cost":0, "cooldown":0.0, "power":0.9, "text":"A bolt of neon that passes through one foe. Scales with Focus."},
	"nova": {"name":"Ember Nova", "cost":25, "cooldown":6.0, "power":2.8, "text":"A ring of fire that burns every foe around you."},
	"dash": {"name":"Dash Strike", "cost":15, "cooldown":4.0, "power":1.6, "text":"Lunge toward the cursor, cutting every foe in your path. You can't be hit mid-dash."},
	"whirlwind": {"name":"Whirlwind", "cost":30, "cooldown":8.0, "power":0.7, "text":"Spin for a moment, hitting everything around you again and again. You can still move."},
	"slam": {"name":"Ground Slam", "cost":40, "cooldown":10.0, "power":3.5, "text":"Crack the street open. Heavy damage around you and stuns foes."},
	"scatter": {"name":"Scattershot", "cost":18, "cooldown":4.0, "power":0.7, "text":"Seven pellets in a wide cone. Brutal up close."},
	"grenade": {"name":"Frag Grenade", "cost":25, "cooldown":6.0, "power":2.6, "text":"Lob a grenade at the cursor. It bursts a moment later."},
	"fan": {"name":"Fan the Hammer", "cost":30, "cooldown":8.0, "power":1.0, "text":"Empty the cylinder: six quick shots at the nearest foes."},
	"barrage": {"name":"Neon Barrage", "cost":45, "cooldown":12.0, "power":1.4, "text":"Call down a rain of tracer fire around the cursor."},
	"arc": {"name":"Arc Lightning", "cost":14, "cooldown":1.5, "power":1.5, "text":"Lightning jumps from the foe nearest the cursor to up to three more."},
	"frost": {"name":"Frost Grid", "cost":25, "cooldown":7.0, "power":0.45, "text":"A field of frozen static at the cursor. Chills and wears down foes inside."},
	"meteor": {"name":"Meteor", "cost":50, "cooldown":12.0, "power":5.0, "text":"A burning satellite falls on the cursor after a short delay."},
}

static func info(g) -> Dictionary:
	return CLASSES[g.player.get("class", "samurai")]

static func skill_ids(g) -> Array:
	return info(g).skills

static func attack_id(g) -> String:
	return info(g).attack

static func ranged(g) -> bool:
	return info(g).range>0

static func unlock_level(index: int) -> int:
	return UNLOCK_LEVELS[index]

static func unlocked(g, index: int) -> bool:
	return int(g.player.level)>=UNLOCK_LEVELS[index]

## Skills learned when the hero reached this level, if any.
static func learned_at(g, level: int) -> Array:
	var out: Array = []
	for i in UNLOCK_LEVELS.size():
		if UNLOCK_LEVELS[i]==level: out.append(SKILLS[skill_ids(g)[i]].name)
	return out

static func cooldown_left(g, id: String) -> float:
	if id=="nova": return g.player.nova
	return float(g.player.cd.get(id, 0.0))

static func cooldown_total(id: String) -> float:
	return SKILLS[id].cooldown

## Damage multiplier for spells: casters scale with Focus.
static func spell_power(g) -> float:
	return g.stats.nova_power if g.player.get("class", "")=="synth_mage" else 1.0

# --- Casting ------------------------------------------------------------------------

static func cast(g, index: int) -> void:
	if g.state!="play" or index<0 or index>=4: return
	var id: String = skill_ids(g)[index]
	if not unlocked(g, index):
		g._notice("%s is learned at level %d." % [SKILLS[id].name, UNLOCK_LEVELS[index]])
		g._tone(140, 0.12, "triangle", 0.02)
		return
	if id=="nova":
		g._nova()
		return
	if cooldown_left(g, id)>0 or g.player.roll>0: return
	var cost: int = SKILLS[id].cost
	if g.player.mana<cost:
		g._notice("Not enough mana for %s." % SKILLS[id].name)
		g._tone(140, 0.12, "triangle", 0.02)
		return
	g.player.mana -= cost
	g.player.cd[id] = SKILLS[id].cooldown
	g.player.cast_at = g.clock
	var target = _cursor_point(g)
	var direction = (target-g.player.pos).normalized()
	if direction==Vector2.ZERO: direction = Vector2.from_angle(g.player.angle)
	g.player.angle = direction.angle()
	g.walk_target = null; g.move_path = PackedVector2Array(); g.chase = {}
	var power: float = SKILLS[id].power
	match id:
		"dash":
			g.swing.clear(); g.player.attack = 0
			g.player.channel = {"kind":"dash", "time":0.22, "dir":direction, "hit":[]}
			g.player.inv = maxf(g.player.inv, 0.26)
			g._tone(320, 0.12, "saw", 0.03)
		"whirlwind":
			g.player.channel = {"kind":"whirlwind", "time":1.4, "tick":0.0}
			g._tone(180, 0.6, "saw", 0.03)
		"slam":
			g.shake = 6
			Effects.shockwave(g, g.player.pos, 3.2, Color("ffcf7a"), true)
			g._burst(g.player.pos, Color("c8b8a0"), 30, 4)
			for e in _enemies_near(g, g.player.pos, 3.2):
				g._strike_enemy(e, power)
				e.stagger = 1.2 if e.kind!="boss" else 0.3
				g._move(e, (e.pos-g.player.pos).normalized()*0.6, Data.ENEMIES[e.kind].radius)
			g._tone(70, 0.4, "saw", 0.06)
			g.hitstop = 0.09
		"scatter":
			for k in 7:
				var spread = direction.rotated((k-3)*0.13+g._between(-0.04, 0.04))
				_fire(g, spread, power, Color("ffe45c"), 15.0, 0.4, 0)
			g.shake = 3
			g._tone(110, 0.15, "saw", 0.05)
		"grenade":
			var reach = minf(g.player.pos.distance_to(target), 7.0)
			var land = g.player.pos+direction*reach
			if not g._clear_path(g.player.pos, land): land = _last_clear(g, g.player.pos, land)
			g.zones.append({"kind":"grenade", "from":g.player.pos, "pos":land, "radius":2.6, "delay":0.65, "max_delay":0.65, "power":power, "life":0.65})
			g._tone(420, 0.1, "triangle", 0.03)
		"fan":
			g.player.channel = {"kind":"fan", "time":0.66, "tick":0.0, "shots":6}
		"barrage":
			g.zones.append({"kind":"barrage", "pos":target, "radius":3.0, "life":1.6, "max_life":1.6, "tick":0.0, "power":power})
			g._tone(240, 0.3, "saw", 0.03)
		"arc":
			_arc(g, target, power)
		"frost":
			g.zones.append({"kind":"frost", "pos":target, "radius":2.4, "life":4.0, "max_life":4.0, "tick":0.0, "power":power})
			g._tone(880, 0.25, "sine", 0.03)
		"meteor":
			g.zones.append({"kind":"meteor", "pos":target, "radius":3.0, "delay":1.0, "max_delay":1.0, "power":power, "life":1.0})
			g._tone(150, 0.9, "saw", 0.04)

# --- Basic attacks ----------------------------------------------------------------

## A gunshot or bolt at whatever the hero is aiming at.
static func shoot(g) -> void:
	var id = attack_id(g)
	var period = (0.34 if id=="shot" else 0.42)/g.stats.attack_speed
	g.attack_period = period
	g.player.attack = period
	g.attack_buffer = 0
	g.attack_serial += 1
	g.player.ranged_attack = {"age":0.0,"duration":period,"fire_at":(0.045 if id=="shot" else 0.075)/g.stats.attack_speed,"angle":g.player.angle,"fired":false,"id":id,"serial":g.attack_serial}

static func _release_shot(g) -> void:
	var id = attack_id(g)
	var direction = Vector2.from_angle(g.player.angle)
	if id=="shot":
		_fire(g, direction, SKILLS.shot.power, Color("ffe9a0"), 18.0, 0.0, 0)
		g._tone(190, 0.08, "saw", 0.035)
		g.player.recoil = 0.12
	else:
		_fire(g, direction, SKILLS.bolt.power, info(g).color, 12.0, 0.0, 1)
		g._tone(520, 0.1, "sine", 0.03)
		g.player.recoil = 0.12

static func _fire(g, direction: Vector2, power: float, color: Color, speed: float, spread_life: float, pierce: int) -> void:
	var start = g.player.pos+direction*0.55
	if not g._clear_path(g.player.pos,start): start=g.player.pos
	var life = (9.0 if spread_life==0 else 4.2)/speed
	g.shots.append({"pos":start, "vel":direction*speed, "power":power, "color":color, "life":life, "pierce":pierce, "hit":[], "spell":attack_id(g)=="bolt"})
	g.player.fired_serial = int(g.player.get("fired_serial",0))+1
	g.player.muzzle_age = 0.0

# --- Simulation -------------------------------------------------------------------

static func update(g, dt: float) -> void:
	g.player.muzzle_age = float(g.player.get("muzzle_age",10.0))+dt
	var attack: Dictionary=g.player.get("ranged_attack",{})
	if not attack.is_empty():
		attack.age+=dt
		if not attack.fired and attack.age>=attack.fire_at:
			attack.fired=true
			g.player.angle=attack.angle
			_release_shot(g)
		if attack.age>=attack.duration: g.player.ranged_attack={}
	for id in g.player.cd.keys():
		g.player.cd[id] = maxf(0.0, g.player.cd[id]-dt)
	g.player.recoil = maxf(0.0, g.player.get("recoil", 0.0)-dt)
	_update_channel(g, dt)
	_update_shots(g, dt)
	_update_zones(g, dt)

static func _update_channel(g, dt: float) -> void:
	var ch: Dictionary = g.player.channel
	if ch.is_empty(): return
	ch.time -= dt
	match ch.kind:
		"dash":
			var before = g.player.pos
			g._move(g.player, ch.dir*18.0*dt)
			for e in _enemies_near(g, g.player.pos, 1.1):
				if not ch.hit.has(e):
					ch.hit.append(e)
					g._strike_enemy(e, SKILLS.dash.power)
					e.stagger = 0.3
					Effects.hit(g, e.pos, ch.dir, Color("ffcf7a"), true)
					g.hitstop = 0.05
			if g.player.pos.distance_to(before)<0.001: ch.time = 0
			g.ghost_timer -= dt
			if g.ghost_timer<=0:
				g.ghost_timer = 0.03
				Effects.ghost(g, g.world_view.characters.hero_state())
		"whirlwind":
			ch.tick -= dt
			g.player.angle += dt*18.0
			if ch.tick<=0:
				ch.tick = 0.2
				var hit_any = false
				for e in _enemies_near(g, g.player.pos, 2.1):
					g._strike_enemy(e, SKILLS.whirlwind.power)
					e.stagger = maxf(e.stagger, 0.12)
					Effects.hit(g, e.pos, (e.pos-g.player.pos).normalized(), Color("ffb35c"), false)
					hit_any = true
				g._tone(160 if hit_any else 220, 0.08, "saw", 0.02)
		"fan":
			ch.tick -= dt
			if ch.tick<=0 and ch.shots>0:
				ch.tick = 0.11
				ch.shots -= 1
				var target = _nearest(g, g.player.pos, 9.0)
				var direction = (target.pos-g.player.pos).normalized() if not target.is_empty() else Vector2.from_angle(g.player.angle)
				g.player.angle = direction.angle()
				_fire(g, direction.rotated(g._between(-0.05, 0.05)), SKILLS.fan.power, Color("ffe9a0"), 20.0, 0.0, 0)
				g.player.recoil = 0.1
				g._tone(200, 0.06, "saw", 0.035)
	if ch.time<=0: g.player.channel = {}

static func _update_shots(g, dt: float) -> void:
	for s in g.shots:
		var steps = maxi(1, ceili(s.vel.length()*dt/0.15))
		for i in steps:
			if s.life<=0: break
			s.pos += s.vel*dt/steps
			if not g._walkable(s.pos):
				s.life = 0
				Effects.hit(g, s.pos-s.vel.normalized()*0.1, -s.vel.normalized(), s.color, false)
				break
			for e in g.enemies:
				if e.hp<=0 or s.hit.has(e): continue
				if e.pos.distance_to(s.pos)<Data.ENEMIES[e.kind].radius+0.22:
					s.hit.append(e)
					g._strike_enemy(e, s.power*(spell_power(g) if s.spell else 1.0))
					e.stagger = maxf(e.stagger, 0.08)
					g._move(e, s.vel.normalized()*(0.04 if e.kind=="boss" else 0.14), Data.ENEMIES[e.kind].radius)
					Effects.hit(g, e.pos, s.vel.normalized(), s.color, false)
					if s.pierce<=0: s.life = 0
					else: s.pierce -= 1
					break
		s.life -= dt
	g.shots = g.shots.filter(func(s): return s.life>0)

static func _update_zones(g, dt: float) -> void:
	for z in g.zones:
		z.life -= dt
		match z.kind:
			"grenade", "meteor":
				z.delay -= dt
				if z.delay<=0 and not z.get("done", false):
					z.done = true
					z.life = 0
					var color = Color("ffb35c") if z.kind=="grenade" else Color("ff5ad2")
					Effects.shockwave(g, z.pos, z.radius, color, true)
					g._burst(z.pos, color, 40, 5)
					g.shake = maxf(g.shake, 5.0 if z.kind=="grenade" else 8.0)
					g._tone(60 if z.kind=="meteor" else 90, 0.4, "saw", 0.06)
					for e in _enemies_near(g, z.pos, z.radius):
						g._strike_enemy(e, z.power*spell_power(g))
						e.stagger = maxf(e.stagger, 0.5)
					g.hitstop = 0.07
			"frost":
				z.tick -= dt
				if z.tick<=0:
					z.tick = 0.5
					for e in _enemies_near(g, z.pos, z.radius):
						e.chill = 1.0
						g._damage_enemy(e, maxi(1, roundi(g._damage()*z.power*spell_power(g))), false, Color("9fe8ff"))
			"barrage":
				z.tick -= dt
				if z.tick<=0:
					z.tick = 0.13
					var spot = z.pos if not z.get("started",false) else z.pos+Vector2.from_angle(g._random()*TAU)*g._random()*z.radius
					z.started=true
					if g._walkable(spot):
						Effects.hit(g, spot, Vector2.UP, Color("3ff0ff"), true)
						Effects.add(g, "tracer", {"pos":spot}, 0.18)
						for e in _enemies_near(g, spot, 0.9):
							g._strike_enemy(e, z.power)
						g._tone(240, 0.04, "saw", 0.02)
	g.zones = g.zones.filter(func(z): return z.life>0)

# --- Helpers ------------------------------------------------------------------------

static func _cursor_point(g) -> Vector2:
	if not g.pointer_active: return g.player.pos+Vector2.from_angle(g.player.angle)*3.0
	var target = g._cursor_target(true)
	if not target.is_empty(): return target.pos
	return g._world(g._pointer_local())

static func _last_clear(g, from: Vector2, to: Vector2) -> Vector2:
	var steps = maxi(1, ceili(from.distance_to(to)/0.2))
	var last = from
	for i in range(1, steps+1):
		var point = from.lerp(to, float(i)/steps)
		if not g._walkable(point): break
		last = point
	return last

static func _enemies_near(g, point: Vector2, radius: float) -> Array:
	var out: Array = []
	for e in g.enemies:
		if e.hp>0 and e.pos.distance_to(point)<radius+Data.ENEMIES[e.kind].radius and g._clear_path(point, e.pos): out.append(e)
	return out

static func _nearest(g, point: Vector2, radius: float) -> Dictionary:
	var best = {}
	var nearest = radius
	for e in g.enemies:
		var d = e.pos.distance_to(point)
		if e.hp>0 and d<nearest and g._clear_path(point, e.pos):
			nearest = d
			best = e
	return best

static func _arc(g, target: Vector2, power: float) -> void:
	var current = _nearest(g, target, 2.5)
	if current.is_empty(): current = _nearest(g, g.player.pos, 7.0)
	var origin = g.player.pos
	var done: Array = []
	if current.is_empty():
		Effects.add(g, "arc", {"from":origin, "to":target, "seed":randi()}, 0.2)
		g._tone(900, 0.1, "saw", 0.02)
		return
	for jump in 4:
		Effects.add(g, "arc", {"from":origin, "to":current.pos, "seed":randi()}, 0.25)
		g._strike_enemy(current, power*spell_power(g)*(1.0-jump*0.15))
		current.stagger = maxf(current.stagger, 0.15)
		done.append(current)
		origin = current.pos
		var next = {}
		var nearest = 3.5
		for e in g.enemies:
			if e.hp<=0 or done.has(e): continue
			var d = e.pos.distance_to(origin)
			if d<nearest and g._clear_path(origin, e.pos):
				nearest = d
				next = e
		if next.is_empty(): break
		current = next
	g._tone(980, 0.15, "saw", 0.03)

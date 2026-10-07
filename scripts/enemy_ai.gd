extends RefCounted
## Enemy behaviour: noticing the hero, walking around walls, telegraphed
## attacks and keeping bodies from stacking on top of each other.

const Data = preload("res://scripts/data.gd")
const Effects = preload("res://scripts/effects.gd")
const Elites = preload("res://scripts/elites.gd")
const REPATH_INTERVAL = 0.35

static func update_all(g, dt: float) -> void:
	for e in g.enemies:
		if e.hp<=0: continue
		var before = e.pos
		# Nobody fights in the food court: enemies lose interest and keep out.
		if g._safe():
			e.alert = false
			e.windup = 0
		_update_enemy(g,e,dt)
		if g.safe_rect.size!=Vector2.ZERO and g.safe_rect.grow(0.8).has_point(e.pos): e.pos = before
		# Walk-cycle bookkeeping for the character art.
		var moved = e.pos.distance_to(before)
		e.step += moved*3.2
		e.moving = lerpf(e.moving,clampf(moved/maxf(dt,0.0001)/Data.ENEMIES[e.kind].speed,0,1),minf(1,dt*10))
		if g.state!="play": return
	_separate(g,dt)

static func alert(g, e: Dictionary) -> void:
	if e.alert: return
	e.alert = true
	# A noticed enemy calls nearby allies that can see it.
	for other in g.enemies:
		if other.hp>0 and not other.alert and other.pos.distance_to(e.pos)<Data.PACK_ALERT_RANGE and g._clear_path(e.pos,other.pos):
			other.alert = true

static func _update_enemy(g, e: Dictionary, dt: float) -> void:
	var stats = Data.ENEMIES[e.kind]
	e.hit = maxf(0,e.hit-dt)
	e.attack -= dt
	if Elites.update_knock(g,e,dt): return
	if Elites.has_affix(e,"juggernaut"): e.stagger = 0
	# Heavy enemies power through hits during a wind-up and must be dodged.
	if e.windup>0 and not stats.interruptible: e.stagger = 0
	if e.stagger>0:
		e.stagger = maxf(0,e.stagger-dt)
		# Light enemies lose their wind-up when hit.
		if e.windup>0:
			e.windup = 0
			e.attack = maxf(e.attack,0.35)
		return
	var d = e.pos.distance_to(g.player.pos)
	var sees = d<Data.LEASH_RANGE and g._clear_path(e.pos,g.player.pos)
	if not e.alert and d<Data.AGGRO_RANGE and sees: alert(g,e)
	if not e.alert or d>Data.LEASH_RANGE: return
	e.phase += dt
	if e.windup>0:
		e.windup -= dt
		if e.windup<=0: _strike(g,e,stats,d)
		return
	if e.kind=="boss":
		if e.attack<=0 and d<stats.reach:
			_begin_windup(g,e,stats)
			g._tone(110,0.5,"triangle",0.02)
		elif d>1.5: _approach(g,e,stats,dt,sees)
	elif e.kind=="ranged":
		if d>Data.RANGED_KEEP_DISTANCE or not sees: _approach(g,e,stats,dt,sees)
		if e.attack<=0 and d<stats.reach and sees:
			_begin_windup(g,e,stats)
	else:
		if e.attack<=0 and d<stats.reach and sees:
			_begin_windup(g,e,stats)
			g._tone(180 if e.kind=="imp" else 120,0.12,"triangle",0.012)
		elif d>stats.reach*0.75: _approach(g,e,stats,dt,sees)

static func _begin_windup(g, e: Dictionary, stats: Dictionary) -> void:
	e.windup = stats.windup
	e.windup_total = stats.windup
	e.aim = (g.player.pos-e.pos).normalized()

static func _strike(g, e: Dictionary, stats: Dictionary, d: float) -> void:
	e.attack = stats.cooldown*e.get("cooldown_mult",1.0)
	var floor_scale = (0.8+g.floor_number*0.2)*e.get("damage_mult",1.0)
	if e.kind=="boss":
		Effects.shockwave(g,e.pos,Data.BOSS_SLAM_RADIUS,Color("ff7752"),true)
		g._burst(e.pos,Color("ff875e"),25,4)
		if d<Data.BOSS_SLAM_RADIUS: g._hurt(stats.damage)
		g.shake = 5
	elif e.kind=="ranged":
		if not g._clear_path(e.pos,g.player.pos): return
		var direction = (g.player.pos-e.pos).normalized()
		Effects.add(g,"impact",{"pos":e.pos+direction*0.3,"color":Color("b8f59a"),"size":0.8,"angle":0.0},0.15)
		g.particles.append({"pos":e.pos,"z":30.0,"velocity":direction*4.5,"vz":0.0,"life":2.0,"color":Color("b8e799"),"size":5.0,"hostile":true,"damage":(stats.damage+g.floor_number*3)*e.get("damage_mult",1.0),"source":e})
		g._tone(520,0.12,"sine",0.012)
	else:
		# The hit lands only if the hero is still in reach when the wind-up ends.
		if d<stats.reach+0.25 and g._clear_path(e.pos,g.player.pos):
			var landed = g.player.inv<=0
			if landed: Effects.hit(g,g.player.pos,e.aim,Color("ff8a6a"),e.kind=="brute")
			var hp_before = g.player.hp
			g._hurt(stats.damage*floor_scale)
			if landed and g.player.hp<hp_before: Elites.on_hit_hero(g,e,hp_before-g.player.hp)
		_lunge(g,e,stats)

static func _lunge(g, e: Dictionary, stats: Dictionary) -> void:
	g._move(e,e.aim*0.18,stats.radius)

static func _approach(g, e: Dictionary, stats: Dictionary, dt: float, sees: bool) -> void:
	var target = g.player.pos
	if sees:
		e.path = PackedVector2Array()
	else:
		e.repath -= dt
		if e.repath<=0 or e.path.is_empty():
			e.repath = REPATH_INTERVAL
			e.path = _find_path(g,e.pos,g.player.pos)
		while not e.path.is_empty() and e.pos.distance_to(e.path[0])<0.3:
			e.path.remove_at(0)
		if e.path.is_empty(): return
		target = e.path[0]
	var direction = (target-e.pos).normalized()
	# Ice damage chills: chilled enemies move at half speed.
	var speed = stats.speed*e.get("speed_mult",1.0)*(0.5 if e.get("chill",0.0)>0 else 1.0)
	g._move(e,direction*speed*dt,stats.radius)

static func _find_path(g, from: Vector2, to: Vector2) -> PackedVector2Array:
	var result = PackedVector2Array()
	if g.nav==null: return result
	var start = Vector2i(floori(from.x),floori(from.y))
	var end = Vector2i(floori(to.x),floori(to.y))
	if not g.nav.is_in_boundsv(start) or not g.nav.is_in_boundsv(end): return result
	if g.nav.is_point_solid(start) or g.nav.is_point_solid(end): return result
	for cell in g.nav.get_id_path(start,end):
		result.append(Vector2(cell)+Vector2.ONE*0.5)
	if not result.is_empty(): result.remove_at(0)
	return result

static func _separate(g, dt: float) -> void:
	var list = g.enemies
	for i in list.size():
		var a = list[i]
		if a.hp<=0: continue
		var ra = Data.ENEMIES[a.kind].radius
		# Enemies cannot stand inside the hero.
		var to_hero = a.pos-g.player.pos
		var hero_gap = ra+0.3
		if to_hero.length()>0.01 and to_hero.length()<hero_gap:
			g._move(a,to_hero.normalized()*(hero_gap-to_hero.length())*minf(1,dt*12),ra)
		for j in range(i+1,list.size()):
			var b = list[j]
			if b.hp<=0: continue
			var rb = Data.ENEMIES[b.kind].radius
			var gap = ra+rb+0.15
			var d = a.pos.distance_to(b.pos)
			if d>0.01 and d<gap:
				var push = (a.pos-b.pos).normalized()*(gap-d)*minf(1,dt*8)*0.5
				g._move(a,push,ra); g._move(b,-push,rb)

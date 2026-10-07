extends RefCounted
## Combat effects: hit sparks and flashes, shockwaves, scorch marks, dodge
## afterimages, enemy deaths and level-up light. Effects live in g.fx.

const Data = preload("res://scripts/data.gd")

var g
var p
var c: CanvasItem
var characters

func _init(game, painter, character_art) -> void:
	g = game
	p = painter
	c = game
	characters = character_art

# --- Spawning ---------------------------------------------------------------

static func add(g, kind: String, data: Dictionary, life: float) -> void:
	data.kind = kind
	data.life = life
	data.max = life
	g.fx.append(data)

## A blade connecting: a bright flash plus sparks thrown away from the hero.
static func hit(g, point: Vector2, direction: Vector2, color: Color, strong: bool) -> void:
	add(g,"impact",{"pos":point,"color":color,"size":1.4 if strong else 1.0,"angle":randf()*TAU},0.16 if strong else 0.12)
	for i in (10 if strong else 6):
		var spread = direction.rotated(randf_range(-0.9,0.9))*randf_range(3,7)
		add(g,"spark",{"pos":point,"z":randf_range(14,30),"vel":spread,"vz":randf_range(20,70),"color":color},randf_range(0.18,0.35))

static func shockwave(g, point: Vector2, radius: float, color: Color, scorch: bool) -> void:
	add(g,"ring",{"pos":point,"radius":radius,"color":color},0.55)
	add(g,"ring",{"pos":point,"radius":radius*0.6,"color":Color(1,1,1,0.8)},0.3)
	add(g,"flash",{"pos":point,"radius":radius,"color":color},0.25)
	if scorch: add(g,"scorch",{"pos":point,"radius":radius*0.55,"seed":randi()},3.0)
	for i in 18:
		var dir = Vector2.from_angle(randf()*TAU)
		add(g,"spark",{"pos":point+dir*0.3,"z":4.0,"vel":dir*randf_range(4,9),"vz":randf_range(30,90),"color":color},randf_range(0.3,0.6))

static func ghost(g, state: Dictionary) -> void:
	add(g,"ghost",{"state":state},0.22)

static func death(g, e: Dictionary) -> void:
	var snapshot = e.duplicate()
	snapshot.hit = 0.0; snapshot.windup = 0.0
	add(g,"death",{"enemy":snapshot},0.55 if e.kind!="boss" else 1.4)
	var color = Color("ffb054") if e.kind=="boss" else Color("7a6a62")
	for i in (40 if e.kind=="boss" else 14):
		var dir = Vector2.from_angle(randf()*TAU)
		add(g,"ash",{"pos":e.pos+dir*randf_range(0,0.4),"z":randf_range(6,40)*Data.ENEMIES[e.kind].scale,"vel":dir*randf_range(0.3,1.2),"vz":randf_range(10,40),"color":color if randf()<0.6 else Color("ff8a4a")},randf_range(0.5,1.1))

static func level_up(g, point: Vector2) -> void:
	add(g,"pillar",{"pos":point},1.2)

static func update(g, dt: float) -> void:
	for f in g.fx:
		f.life -= dt
		if f.kind=="spark" or f.kind=="ash":
			f.pos += f.vel*dt
			f.z = maxf(0,f.z+f.vz*dt)
			f.vz -= (160 if f.kind=="spark" else 30)*dt
	g.fx = g.fx.filter(func(f): return f.life>0)

# --- Drawing ----------------------------------------------------------------

## Ground-level effects drawn under characters.
func draw_ground() -> void:
	for f in g.fx:
		var t = 1-f.life/f.max
		if f.kind=="scorch":
			var s = g._project(f.pos)
			var a = minf(1,f.life/1.2)
			p.ellipse(s,f.radius*45,f.radius*23,Color(0.05,0.03,0.03,0.45*a),32)
			var rng = RandomNumberGenerator.new()
			rng.seed = f.seed
			for i in 8:
				var dir = Vector2.from_angle(rng.randf()*TAU)
				var length = rng.randf_range(0.3,0.6)*f.radius
				var points = PackedVector2Array([s])
				for k in range(1,4):
					var bend = dir.rotated(rng.randf_range(-0.5,0.5))*length*k/3.0
					points.append(s+g._iso(bend))
				c.draw_polyline(points,Color(1,0.45,0.2,0.45*a),1.2,true)
		elif f.kind=="ring":
			var s = g._project(f.pos)
			var eased = 1-pow(1-t,3)
			var r = f.radius*eased
			if g.view3d:
				var ring=PackedVector2Array()
				for i in 49: ring.append(g._project(f.pos+Vector2.from_angle(TAU*i/48.0)*r,1))
				if r>.01:
					c.draw_colored_polygon(ring,Color(f.color,.065*(1-t)))
					c.draw_polyline(ring,Color(f.color,.8*(1-t)),2.8*(1-t)+.7,true)
			else:
				p.ellipse(s,r*45,r*23,Color(f.color,0.12*(1-t)),40)
				p.ellipse_arc(s,r*45,r*23,0,TAU,Color(f.color,(1-t)),4*(1-t)+1)
		elif f.kind=="flash":
			var s = g._project(f.pos)
			p.glow(s-Vector2(0,10),f.radius*60*(0.6+t*0.6),Color(f.color,0.5*(1-t)))

## Effects drawn over characters.
func draw_air(shake_offset: Vector2) -> void:
	for f in g.fx:
		var t = 1-f.life/f.max
		match f.kind:
			"ghost":
				if g.view3d: continue
				p.tint_color = Color("7fe0e8"); p.tint_amount = 0.8
				p.alpha = 0.45*(1-t)
				characters.draw_hero(f.state,shake_offset,true)
				p.tint_amount = 0; p.alpha = 1
			"death":
				if g.view3d: continue
				p.tint_color = Color("2a2024") if f.enemy.kind!="boss" else Color("ff9a4a"); p.tint_amount = 0.4+t*0.5
				characters.draw_enemy(f.enemy,shake_offset,1-t,t*10)
				p.tint_amount = 0
			"impact":
				var s = g._project(f.pos,26)
				var size = f.size*(10+t*16)
				p.glow(s,size*2.4,Color(f.color,0.6*(1-t)))
				for i in 4:
					var dir = Vector2.from_angle(f.angle+i*PI/2)
					p.line(s-dir*size*0.2,s+dir*size*(1.4 if i%2==0 else 0.8),Color(Color.WHITE,1-t),2.2*(1-t)+0.5)
				p.circle(s,size*0.35*(1-t)+1,Color(1,1,1,1-t))
			"spark":
				var s = g._project(f.pos,f.z)
				var tail = s-g._iso(f.vel)*0.035+Vector2(0,f.vz*0.02)
				p.line(tail,s,Color(f.color,1-t),2)
				p.circle(s,1.2,Color(Color.WHITE,1-t))
			"ash":
				var s = g._project(f.pos,f.z)
				p.circle(s,1.6*(1-t)+0.5,Color(f.color,1-t))
			"arc":
				# A jagged shock arc jumping between two enemies.
				var a = g._project(f.from,26)
				var b = g._project(f.to,26)
				var rng = RandomNumberGenerator.new()
				rng.seed = f.seed+int(t*4)
				var points = PackedVector2Array([a])
				for k in range(1,6):
					points.append(a.lerp(b,k/6.0)+Vector2(rng.randf_range(-7,7),rng.randf_range(-7,7)))
				points.append(b)
				c.draw_polyline(points,p.ink(Color(1,0.95,0.5,1-t)),3,true)
				c.draw_polyline(points,p.ink(Color(1,1,1,1-t)),1.2,true)
				p.glow(b,18,Color(1,0.9,0.4,0.6*(1-t)))
			"tracer":
				# A shot streaking down from above in the Neon Barrage.
				var s = g._project(f.pos)
				var top = s-Vector2(-30,160)*(1-t)
				c.draw_line(top,s,p.ink(Color(0.25,0.95,1,1-t)),3,true)
				p.glow(s,16,Color(0.3,1,1,0.6*(1-t)))
			"pillar":
				var s = g._project(f.pos)
				var a = sin(t*PI)
				for i in 6: p.glow(s-Vector2(0,20+i*22),36-i*3,Color(1,0.9,0.6,0.22*a))
				for i in 10:
					var k = fposmod(t*1.6+i*0.1,1.0)
					p.circle(s+Vector2(sin(i*2.3)*14,-k*120),1.6,Color(1,0.95,0.7,a*(1-k)))
				p.ellipse_arc(s,30+t*20,14+t*9,0,TAU,Color(1,0.9,0.6,a*0.8),2)

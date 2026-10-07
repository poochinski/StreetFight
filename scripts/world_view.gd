extends RefCounted
## Draws the ruined city (ground, markings, light pools, buildings and neon via
## city_art.gd), then layers props, characters and effects in depth order.

const Data = preload("res://scripts/data.gd")
const Characters = preload("res://scripts/characters.gd")
const EffectsArt = preload("res://scripts/effects.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const CityArt = preload("res://scripts/city_art.gd")
const CityLayer = preload("res://scripts/city_layer.gd")
const CHUNK = 8

var g
var p
var c: CanvasItem
var characters
var effects
var city
var root: Node2D
var backdrop: Node2D
var markings: Node2D
var grounds = {}
var buildings = {}
var darkness: GradientTexture2D

func _init(game, painter) -> void:
	g = game
	p = painter
	c = game
	characters = Characters.new(game,painter)
	effects = EffectsArt.new(game,painter,characters)
	city = CityArt.new(game,painter)
	darkness = GradientTexture2D.new()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(0,0,0,0),Color(0.01,0.0,0.03,0.0),Color(0.01,0.0,0.03,0.72)])
	gradient.offsets = PackedFloat32Array([0.0,0.22,0.8])
	darkness.gradient = gradient
	darkness.fill = GradientTexture2D.FILL_RADIAL
	darkness.fill_from = Vector2(0.5,0.5)
	darkness.fill_to = Vector2(1.0,0.5)

func _theme() -> Dictionary:
	return g.theme()

## Builds the cached layers behind the game's own drawing: the backdrop, the
## ground of every chunk, the street markings and lights, then the buildings
## of every chunk back to front.
func _build_layers() -> void:
	backdrop = _layer(g,Vector2i.ZERO,"backdrop")
	backdrop.show_behind_parent = true
	root = Node2D.new()
	root.show_behind_parent = true
	g.add_child(root)
	var count = DungeonGenerator.SIZE/CHUNK
	for chunk_y in count:
		for chunk_x in count: grounds[Vector2i(chunk_x,chunk_y)] = _layer(root,Vector2i(chunk_x,chunk_y),"ground")
	markings = _layer(root,Vector2i.ZERO,"markings")
	for total in 2*count-1:
		for chunk_y in range(maxi(0,total-count+1),mini(count-1,total)+1):
			var chunk = Vector2i(total-chunk_y,chunk_y)
			buildings[chunk] = _layer(root,chunk,"buildings")

func _layer(parent: Node, chunk: Vector2i, kind: String) -> Node2D:
	var node = CityLayer.new()
	node.view = self
	node.chunk = chunk
	node.layer = kind
	parent.add_child(node)
	return node

## A newly revealed cell redraws the chunk it sits in.
func reveal(cell: Vector2i) -> void:
	if root==null: return
	var chunk = cell/CHUNK
	if grounds.has(chunk):
		grounds[chunk].queue_redraw()
		buildings[chunk].queue_redraw()

func redraw_all() -> void:
	if root==null: return
	for chunk in grounds:
		grounds[chunk].queue_redraw()
		buildings[chunk].queue_redraw()

## Called by a cached layer during its own draw. The layers draw with the camera
## at zero; the root node is moved by the camera instead.
func draw_layer(node: CanvasItem, chunk: Vector2i, kind: String) -> void:
	if g.player.is_empty(): return
	if kind=="backdrop":
		node.draw_texture_rect(p.background,Rect2(-g.position/g.scale,node.get_viewport_rect().size/g.scale),false)
		return
	var camera = g.camera
	g.camera = Vector2.ZERO
	p.alpha = 1
	p.canvas = node
	city.c = node
	city.shake = Vector2.ZERO
	if kind=="markings":
		city.decals(g.player.pos,_cull_radius())
		city.lights(g.player.pos,_cull_radius())
		city.sign_light()
		for exit in g.exits:
			if g.seen.has(Vector2i(exit.pos)): city.exit(exit)
	else:
		var x0 = chunk.x*CHUNK; var y0 = chunk.y*CHUNK
		for total in 2*CHUNK-1:
			for dy in range(maxi(0,total-CHUNK+1),mini(CHUNK-1,total)+1):
				var cell = Vector2i(x0+total-dy,y0+dy)
				if not g.seen.has(cell): continue
				var s = g._project(Vector2(cell)+Vector2(0.5,0.5))
				if kind=="ground":
					if g.cells.has(cell): city.ground(cell,s)
				elif not g.cells.has(cell) and _beside_open(cell): city.building(cell,s)
	g.camera = camera
	p.canvas = g
	city.c = g

func _cull_radius() -> float:
	return 22.0/minf(1.0,g.scale.x/1.4)

func draw(shake_offset: Vector2) -> void:
	if g.view3d:
		_draw_over_3d(shake_offset)
		return
	if root==null: _build_layers()
	root.position = shake_offset-g.camera
	markings.queue_redraw()
	backdrop.queue_redraw()
	c.draw_set_transform(shake_offset)
	city.shake = shake_offset
	# The dark closes in away from the hero.
	if g.zoom>=1.0:
		var hero = g._project(g.player.pos)
		c.draw_texture_rect(darkness,Rect2(hero-Vector2(850,500),Vector2(1700,1000)),false)
	city.signs(Rect2(-g.position/g.scale,c.get_viewport_rect().size/g.scale).grow(160))
	effects.draw_ground()
	_draw_hazards()
	for z in g.zones: _draw_zone(z)
	if g.state=="play" and g.pointer_active:
		var target = g._cursor_target()
		if not target.is_empty():
			var r = 0.55*Data.ENEMIES[target.kind].scale
			p.ellipse_arc(g._project(target.pos),r*45,r*23,0,TAU,Color("dfb86eaa"),1.6)
	for drop in g.drops:
		if not g.seen.has(Vector2i(drop.pos)): continue
		g.loot_view.draw_drop(drop,shake_offset)
	var objects: Array = []
	var view = Rect2(-g.position/g.scale,c.get_viewport_rect().size/g.scale).grow_individual(140,200,140,60)
	for prop in g.props:
		if g.seen.has(Vector2i(prop.pos)) and view.has_point(g._project(prop.pos)): objects.append({"order":prop.pos.x+prop.pos.y,"kind":"prop","data":prop})
	for e in g.enemies:
		if e.hp>0 and g.seen.has(Vector2i(e.pos)): objects.append({"order":e.pos.x+e.pos.y,"kind":"enemy","data":e})
	objects.append({"order":g.player.pos.x+g.player.pos.y,"kind":"hero"})
	objects.sort_custom(func(a,b): return a.order<b.order)
	for object in objects:
		if object.kind=="prop": city.prop(object.data)
		elif object.kind=="enemy": characters.draw_enemy(object.data,shake_offset)
		else: characters.draw_hero(characters.hero_state(),shake_offset)
	characters.draw_swing_trail(g.swing)
	effects.draw_air(shake_offset)
	_draw_projectiles()
	c.draw_set_transform(Vector2.ZERO)

func _draw_projectiles() -> void:
	for shot in g.shots: _draw_shot(shot)
	for z in g.zones:
		if z.kind=="grenade" or z.kind=="meteor": _draw_falling(z)
	for particle in g.particles:
		if particle.hostile: _draw_bolt(particle)
		else:
			var screen = g._project(particle.pos,maxf(0,particle.z))
			p.alpha = minf(1,particle.life*2)
			if particle.size>2.6: p.glow(screen,particle.size*3,Color(particle.color,0.35))
			p.circle(screen,particle.size*0.8,particle.color)
			p.alpha = 1
	for t in g.texts:
		var screen = g._project(t.pos,48+(1-t.life/t.max)*32)
		var pop = 1.0+maxf(0,(t.life/t.max-0.8))*2.5
		p.alpha = minf(1,t.life*3)
		var size = int((20 if t.get("big",false) else 14)*pop)
		p.center(t.text,screen+Vector2(1,1),size,Color("09121c"))
		p.center(t.text,screen,size,t.color)
		p.alpha = 1
	c.draw_set_transform(Vector2.ZERO)

## In 3D the city, props and characters are models; this draws what stays 2D on
## top of them: target rings, skill areas, loot, effects, shots and damage numbers.
func _draw_over_3d(shake_offset: Vector2) -> void:
	c.draw_set_transform(shake_offset)
	effects.draw_ground()
	_draw_hazards()
	for z in g.zones: _draw_zone(z)
	if g.state=="play" and g.pointer_active:
		var target = g._cursor_target()
		if not target.is_empty():
			var r = 0.55*Data.ENEMIES[target.kind].scale
			p.ellipse_arc(g._project(target.pos),r*45,r*23,0,TAU,Color("dfb86eaa"),1.6)
	for drop in g.drops:
		if not g.seen.has(Vector2i(drop.pos)): continue
		g.loot_view.draw_drop(drop,shake_offset)
	characters.draw_swing_trail(g.swing)
	effects.draw_air(shake_offset)
	_draw_projectiles()
	c.draw_set_transform(Vector2.ZERO)

## Screen-space atmosphere drawn above the world: weather, a sunset haze along
## the top, the vignette and the hurt flash.
func draw_screen_overlays(canvas: CanvasItem) -> void:
	var viewport = canvas.get_viewport_rect()
	var t = city.theme()
	var mote: Color = t.mote
	canvas.draw_texture_rect(p.header_gradient,Rect2(0,0,viewport.size.x,viewport.size.y*0.45),false,Color(t.glow,0.22))
	match t.weather:
		"rain":
			for i in 110:
				var x = fposmod(i*97.3-g.clock*120,viewport.size.x+40)-20
				var y = fposmod(i*61.7+g.clock*(620+(i%5)*40),viewport.size.y+40)-20
				canvas.draw_line(Vector2(x,y),Vector2(x-5,y+16),Color(mote,0.13+(i%3)*0.04),1)
		"ash":
			for i in 70:
				var x = fposmod(i*137.4+sin(g.clock*0.3+i)*40,viewport.size.x)
				var y = fposmod(i*87.9+g.clock*(14+i%6*3),viewport.size.y)
				canvas.draw_rect(Rect2(x,y,2,2),Color(0.8,0.78,0.75,0.25))
			for i in 24:
				var x = fposmod(i*211.3+sin(g.clock*0.8+i)*30,viewport.size.x)
				var y = fposmod(i*53.1-g.clock*(30+i%4*8),viewport.size.y)
				canvas.draw_circle(Vector2(x,y),1.4,Color(mote,0.35+0.3*sin(g.clock*4+i)))
		_:
			for i in 40:
				var x = fposmod(i*137.4+sin(g.clock*0.2+i)*30,viewport.size.x)
				var y = fposmod(i*87.9-g.clock*(6+i%4*2),viewport.size.y)
				var col = mote if i%2==0 else Color(0.5,0.95,1)
				canvas.draw_circle(Vector2(x,y),1.2,Color(col,0.12+(sin(g.clock*2+i)+1)*0.12))
	canvas.draw_texture_rect(p.vignette,viewport,false)
	if g.hurt_flash>0: canvas.draw_texture_rect(p.vignette,viewport,false,Color(1,0.15,0.1,g.hurt_flash*0.9))

func _beside_open(cell: Vector2i) -> bool:
	for dy in [-1,0,1]:
		for dx in [-1,0,1]:
			if g.cells.has(cell+Vector2i(dx,dy)): return true
	return false

# --- Projectiles ------------------------------------------------------------------

## Hero bullets and bolts: a bright streak with a glowing head.
func _draw_shot(shot: Dictionary) -> void:
	var head = g._project(shot.pos,22)
	var tail = g._project(shot.pos-shot.vel.normalized()*(0.9 if shot.spell else 0.6),22)
	p.glow(head,16 if shot.spell else 10,Color(shot.color,0.6))
	c.draw_line(tail,head,p.ink(Color(shot.color,0.55)),4.0 if shot.spell else 3.0,true)
	c.draw_line(tail.lerp(head,0.4),head,p.ink(Color.WHITE),1.6,true)

## Skill areas on the ground: where a grenade or meteor will land, frost fields
## and the barrage zone.
func _draw_zone(z: Dictionary) -> void:
	var s = g._project(z.pos)
	var r: float = z.radius
	match z.kind:
		"grenade", "meteor":
			var t = 1.0-z.delay/z.max_delay
			var color = Color("ffb35c") if z.kind=="grenade" else Color("ff5ad2")
			p.ellipse(s,r*45*t,r*23*t,Color(color,0.12),36)
			p.ellipse_arc(s,r*45,r*23,0,TAU,Color(color,0.75),2)
		"frost":
			var fade = minf(1.0,z.life/0.5)*minf(1.0,(z.max_life-z.life)/0.25)
			p.ellipse(s,r*45,r*23,Color(0.6,0.9,1,0.16*fade),36)
			p.ellipse_arc(s,r*45,r*23,0,TAU,Color(0.7,0.95,1,0.8*fade),2)
			for k in 6:
				var a = k*PI/3+g.clock*0.3
				p.line(s,s+Vector2(cos(a)*r*40,sin(a)*r*20),Color(0.8,0.97,1,0.3*fade),1.2)
		"barrage":
			var fade = minf(1.0,z.life/0.3)
			p.ellipse_arc(s,r*45,r*23,0,TAU,Color(0.25,0.95,1,0.6*fade),2)

## A Molten elite's death blast: a red ring that fills in before it goes off.
func _draw_hazards() -> void:
	for h in g.hazards:
		var s = g._project(h.pos)
		var t = 1.0-clampf(h.delay/h.max_delay, 0, 1)
		var r: float = h.radius
		p.ellipse(s, r*45*t, r*23*t, Color(1, 0.35, 0.1, 0.22), 36)
		p.ellipse_arc(s, r*45, r*23, 0, TAU, Color(1, 0.4, 0.15, 0.6+0.4*sin(g.clock*30)), 2.5)

## A grenade arcing through the air, or a meteor falling from the sky.
func _draw_falling(z: Dictionary) -> void:
	var t = clampf(1.0-z.delay/z.max_delay,0,1)
	if z.kind=="grenade":
		var at = z.from.lerp(z.pos,minf(1.0,t*1.4))
		var height = sin(minf(1.0,t*1.4)*PI)*60+4
		var s = g._project(at,height)
		p.circle(s,4.5,Color("4a5a34"))
		p.circle(s+Vector2(-1,-1),1.6,Color("9aa080"))
		if int(g.clock*12)%2==0: p.glow(s,10,Color(1,0.3,0.2,0.6))
	else:
		var s = g._project(z.pos,(1.0-t)*520)
		p.glow(s,40,Color(1,0.4,0.6,0.7))
		c.draw_line(s,s-Vector2(-50,120)*(1.0-t*0.5),p.ink(Color(1,0.6,0.3,0.6)),8,true)
		p.circle(s,9,Color("ff7a3a"))
		p.circle(s+Vector2(-3,-3),4,Color("ffe45c"))

func _draw_bolt(bolt: Dictionary) -> void:
	var screen = g._project(bolt.pos,maxf(0,bolt.z))
	var back = g._iso(bolt.velocity.normalized())*0.35
	for k in 5:
		p.circle(screen-back*k*1.6,4.5-k*0.8,Color(0.72,0.96,0.6,0.5-k*0.09))
	p.glow(screen,22,Color(0.7,1,0.55,0.5))
	p.circle(screen,3.2,Color("efffe6"))

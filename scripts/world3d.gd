extends Node3D
## The 3D view of the city. The game still runs on its 2D grid (one unit per
## cell, world x/y -> 3D x/z); this node builds lit 3D streets, buildings, neon
## signs and props from the generated level, places 3D models for the hero and
## enemies every frame, and projects between the grid and the screen so the
## HUD, loot plates and 2D effects line up with the 3D scene.

const Data = preload("res://scripts/data.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const Models = preload("res://scripts/models.gd")
const Elites = preload("res://scripts/elites.gd")

## Screen pixels of height in the 2D art per 3D unit (a cell is one unit across).
const PX = 45.0
const CHUNK = 8
## Camera: looks down the iso diagonal like the 2D view, slightly perspective.
const CAMERA_DISTANCE = 15.0
const CAMERA_PITCH = 52.0
const CAMERA_FOV = 34.0

var g
var camera: Camera3D
var environment: WorldEnvironment
var moon: DirectionalLight3D
var hero_light: OmniLight3D
var level: Node3D
var actors: Node3D
var models
var hero
var enemy_nodes = {}
var prop_nodes = {}
var flickers: Array = []
var focus = Vector3.ZERO
var materials = {}

func setup(game) -> void:
	g = game
	models = Models.new()
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.5
	camera.far = 120.0
	add_child(camera)
	camera.current = true
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	add_child(environment)
	moon = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58, 20, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	add_child(moon)
	hero_light = OmniLight3D.new()
	hero_light.omni_range = 7.5
	hero_light.light_energy = 1.4
	hero_light.light_color = Color(1.0, 0.86, 0.7)
	add_child(hero_light)
	level = Node3D.new()
	add_child(level)
	actors = Node3D.new()
	add_child(actors)
	for key in ["ground", "wall", "glow"]:
		var m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85 if key!="glow" else 1.0
		if key=="glow": m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		materials[key] = m

func _theme() -> Dictionary:
	return g.theme()

static func v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)

# --- Projection between the grid, 3D and the screen ---------------------------------

## Screen point (in the game node's local drawing space) of a grid point at
## height z, where z is in the 2D art's pixels.
func project(point: Vector2, z: float) -> Vector2:
	var screen = camera.unproject_position(v3(point, z/PX))
	return (screen-g.position)/g.scale

## The grid point on the ground under a point in the game node's drawing space.
func world(local: Vector2) -> Vector2:
	var screen = g.position+local*g.scale
	var origin = camera.project_ray_origin(screen)
	var direction = camera.project_ray_normal(screen)
	if absf(direction.y)<0.0001: return Vector2(origin.x, origin.z)
	var t = -origin.y/direction.y
	var hit = origin+direction*t
	return Vector2(hit.x, hit.z)

func place_camera(target: Vector2, smooth: float = 1.0) -> void:
	focus = focus.lerp(v3(target), smooth) if smooth<1.0 else v3(target)
	var pitch = deg_to_rad(CAMERA_PITCH)
	var back = Vector3(1, 0, 1).normalized()*cos(pitch)*CAMERA_DISTANCE
	# Zooming out (map previews) pulls the camera back instead of widening it.
	var distance = CAMERA_DISTANCE*g.WORLD_ZOOM/maxf(0.1, g.zoom)
	back *= distance/CAMERA_DISTANCE
	camera.position = focus+back+Vector3(0, sin(pitch)*distance, 0)
	camera.far = maxf(120.0, distance*4.0)
	camera.look_at(focus+Vector3(0, 0.6, 0), Vector3.UP)

# --- Building the level ------------------------------------------------------------

func build() -> void:
	for child in level.get_children(): child.queue_free()
	for child in actors.get_children(): child.queue_free()
	enemy_nodes.clear()
	prop_nodes.clear()
	flickers.clear()
	hero = null
	var t = _theme()
	var env: Environment = environment.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(t.glow).lerp(Color(0.3, 0.34, 0.5), 0.8)
	env.ambient_light_energy = t.get("ambient", 0.32)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(t.glow).darkened(0.7)
	env.fog_density = 0.005
	moon.light_color = Color(0.55, 0.6, 0.95) if t.weather!="ash" else Color(1.0, 0.6, 0.45)
	moon.light_energy = 0.5 if not t.get("indoor", false) else 0.12
	hero_light.omni_range = 7.5 if not t.get("indoor", false) else 9.0
	var count = DungeonGenerator.SIZE/CHUNK
	for cy in count:
		for cx in count: _build_chunk(Vector2i(cx, cy), t)
	_build_markings(t)
	_build_signs(t)
	_build_props(t)
	_build_exits(t)
	if t.get("indoor", false): _build_ceiling_lights(t)
	_build_roofs()
	for id in ["samurai", "gunslinger", "synth_mage"]:
		if not portraits.has(id): _make_portrait(id)
	hero = models.hero(g.player.get("class", "samurai"))
	actors.add_child(hero)
	place_camera(g.player.pos)

func _build_chunk(chunk: Vector2i, t: Dictionary) -> void:
	var ground = SurfaceTool.new()
	ground.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow = SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_ground = false
	var any_wall = false
	var any_glow = false
	for y in range(chunk.y*CHUNK, (chunk.y+1)*CHUNK):
		for x in range(chunk.x*CHUNK, (chunk.x+1)*CHUNK):
			var c = Vector2i(x, y)
			if g.cells.has(c):
				_ground_cell(ground, c, t)
				any_ground = true
			else:
				# Every solid cell is built, so blocks read as solid buildings
				# with roofs instead of hollow shells.
				any_glow = _building_cell(walls, glow, c, t) or any_glow
				any_wall = true
	if any_ground: _mesh(ground, materials.ground)
	if any_wall: _mesh(walls, materials.wall)
	if any_glow: _mesh(glow, materials.glow, false)

func _mesh(st: SurfaceTool, material: Material, shadows: bool = true) -> void:
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(node)

func _beside_open(c: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if g.cells.has(c+Vector2i(dx, dy)): return true
	return false

func _h(a: int, b: int, k: int = 0) -> int:
	return absi((a*73856093) ^ (b*19349663) ^ (k*83492791))%1000

## Adds a quad (counter-clockwise seen from where the normal points).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	st.set_color(color)
	for p in [a, b, c, a, c, d]: st.add_vertex(p)

func _flat(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, color: Color) -> void:
	_quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), color)

## An axis-aligned box without a bottom.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, top: Color, side: Color) -> void:
	_flat(st, lo.x, lo.z, hi.x, hi.z, hi.y, top)
	_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), side)
	_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), side.darkened(0.12))
	_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), side.darkened(0.05))
	_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), side.darkened(0.18))

func _ground_cell(st: SurfaceTool, c: Vector2i, t: Dictionary) -> void:
	# Leave a real opening in the sidewalk for the descending subway steps.
	for e in g.exits:
		if e.kind!="subway": continue
		var size = Vector2(1.5, 1.9) if e.face.y!=0 else Vector2(1.9, 1.5)
		var hole = Rect2(e.pos-size/2, size)
		var tile = Rect2(Vector2(c), Vector2.ONE)
		if not tile.intersects(hole): continue
		var cut = tile.intersection(hole)
		var col: Color = t.sidewalk[0]
		_flat(st, tile.position.x, tile.position.y, cut.position.x, tile.end.y, 0.1, col)
		_flat(st, cut.end.x, tile.position.y, tile.end.x, tile.end.y, 0.1, col)
		_flat(st, cut.position.x, tile.position.y, cut.end.x, cut.position.y, 0.1, col)
		_flat(st, cut.position.x, cut.end.y, cut.end.x, tile.end.y, 0.1, col)
		return
	var kind = g.cells[c]
	var style: String = g.cell_style.get(c, "")
	var hv = _h(c.x, c.y)
	var x0 = float(c.x); var z0 = float(c.y)
	match kind:
		DungeonGenerator.CORRIDOR:
			var col: Color = t.asphalt[hv%3]
			if style=="parking": col = t.lot.darkened(0.15).lerp(col, 0.5)
			_flat(st, x0, z0, x0+1, z0+1, 0.0, col)
		DungeonGenerator.SIDEWALK:
			# Raised slabs with a curb on the street side.
			var col: Color = t.sidewalk[hv%2]
			_box(st, Vector3(x0+0.02, 0, z0+0.02), Vector3(x0+0.98, 0.1, z0+0.98), col, Color(t.curb).darkened(0.2))
			_flat(st, x0, z0, x0+1, z0+1, 0.0, t.sidewalk_seam)
		DungeonGenerator.LOT:
			var col: Color = t.lot
			match style:
				"grass": col = Color(t.grass).lightened(0.04*(hv%3))
				"dirt": col = Color(t.dirt).lightened(0.03*(hv%3))
				"rubble": col = Color(t.rubble).lightened(0.03*(hv%3))
				"pavers": col = t.pavers if (c.x+c.y)%2==0 else Color(t.pavers).lightened(0.07)
				"parking": col = t.lot.darkened(0.15).lerp(t.asphalt[0], 0.5)
				"water":
					_flat(st, x0, z0, x0+1, z0+1, -0.12, Color(t.get("water", Color("1a3a4a"))).lightened(0.03*(hv%3)))
					return
			_flat(st, x0, z0, x1(x0), z0+1, 0.0, col)
		_:
			match style:
				"checker":
					for i in 2:
						for j in 2:
							var col = Color("cfc6b4") if (i+j)%2==0 else Color("1d1a22")
							_flat(st, x0+i*0.5, z0+j*0.5, x0+i*0.5+0.5, z0+j*0.5+0.5, 0.01, col)
				"carpet": _flat(st, x0, z0, x0+1, z0+1, 0.01, Color("1c1430").lightened(0.03*(hv%3)))
				"tile": _flat(st, x0, z0, x0+1, z0+1, 0.01, Color("3d6b6e") if (c.x+c.y)%3!=0 else Color("c87a9a"))
				"threshold": _flat(st, x0, z0, x0+1, z0+1, 0.01, Color("3c3a42"))
				"rail":
					_flat(st, x0, z0, x0+1, z0+1, -0.25, t.floor.rail[hv%2])
					# Sleepers across, two steel rails along the track.
					_flat(st, x0+0.1, z0+0.3, x0+0.9, z0+0.45, -0.24, Color("3a2a20"))
					_flat(st, x0+0.1, z0+0.8, x0+0.9, z0+0.95, -0.24, Color("3a2a20"))
					if c.y%4==0 or c.y%4==2:
						_box(st, Vector3(x0, -0.25, z0+0.6), Vector3(x0+1, -0.17, z0+0.68), Color("b8bcc4"), Color("6a6e78"))
				_:
					var tiles: Dictionary = t.get("floor", {})
					if tiles.has(style): _flat(st, x0, z0, x0+1, z0+1, 0.01, tiles[style][(c.x+c.y)%2])
					else: _flat(st, x0, z0, x0+1, z0+1, 0.01, Color("4a4a52").lightened(0.03*(hv%3)))

func x1(x0: float) -> float:
	return x0+1.0

## One building cell: a block with storefronts, lit windows and a roof. Returns
## true if it added anything glowing.
func _building_cell(st: SurfaceTool, glow: SurfaceTool, c: Vector2i, t: Dictionary) -> bool:
	var h = DungeonGenerator.solid_height(g, c)/PX
	if t.get("indoor", false): return _inner_wall(st, glow, c, h, t)
	var style = _h(c.x/5, c.y/5, g.floor_number)%t.buildings.size()
	var pal: Array = t.buildings[style]
	var x0 = float(c.x); var z0 = float(c.y)
	var tall = h>=DungeonGenerator.FACADE_HEIGHT/PX-0.01
	# Walls cut down so they never hide the street read as dark broken stubs.
	if tall: _box(st, Vector3(x0, 0, z0), Vector3(x0+1, h, z0+1), pal[2], pal[0])
	else: _box(st, Vector3(x0, 0, z0), Vector3(x0+1, h, z0+1), Color(pal[1]).darkened(0.5), Color(pal[1]).darkened(0.3))
	var glowing = false
	if not tall: return false
	# Trim band above the shop floor and a parapet.
	for face in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
		if not g.cells.has(c+face): continue
		var hv = _h(c.x, c.y, face.x*3+face.y)
		var n = Vector3(face.x, 0, face.y)
		var along = Vector3(-face.y, 0, face.x)
		var center = Vector3(x0+0.5, 0, z0+0.5)+n*0.5
		var out = n*0.02
		# Shop front: lit glass, a dark doorway or a shutter.
		var kind = hv%6
		if kind<3:
			var lit = hv%3==0
			var col = Color(t.neon[hv%t.neon.size()]).lerp(Color(1, 0.85, 0.6), 0.5)*(1.0 if lit else 0.0)+Color(0.04, 0.06, 0.1)*(0.0 if lit else 1.0)
			_face(glow, center+out, along, n, 0.36, 0.25, 1.3, col)
			glowing = glowing or lit
		elif kind==3: _face(st, center+out, along, n, 0.16, 0.0, 1.2, Color("120d14"))
		else: _face(st, center+out, along, n, 0.42, 0.0, 1.32, Color("5a5e68"))
		_face(st, center+n*0.06, along, n, 0.5, 1.55, 1.7, Color(pal[3]).darkened(0.25))
		# Upper windows: some lit warm, some flickering TV blue, most dark.
		for side in [-1, 1]:
			var state = _h(c.x*3+side, c.y*5, face.x+face.y*2)%10
			var col = Color(0.05, 0.07, 0.12)
			if state<2: col = Color(1.0, 0.75, 0.42)
			elif state==2: col = Color(0.45, 0.6, 1.0)
			var target = glow if state<3 else st
			_face(target, center+out+along*side*0.24, along, n, 0.14, 1.95, 2.75, col)
			glowing = glowing or state<3
	return glowing

## An inside wall: plain painted block, a coloured band at waist height and
## now and then a lit poster or vent. Returns true if it added anything glowing.
func _inner_wall(st: SurfaceTool, glow: SurfaceTool, c: Vector2i, h: float, t: Dictionary) -> bool:
	var x0 = float(c.x); var z0 = float(c.y)
	var hv0 = _h(c.x, c.y, 5)
	var wall: Color = Color(t.wall).darkened(0.04*(hv0%3))
	_box(st, Vector3(x0, 0, z0), Vector3(x0+1, h, z0+1), t.wall_top, wall)
	var glowing = false
	for face in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
		if not g.cells.has(c+face): continue
		var n = Vector3(face.x, 0, face.y)
		var along = Vector3(-face.y, 0, face.x)
		var center = Vector3(x0+0.5, 0, z0+0.5)+n*0.51
		_face(st, center, along, n, 0.5, 0.0, 0.12, Color(t.wall).darkened(0.5))
		if h>0.6: _face(st, center, along, n, 0.5, 0.42, 0.56, t.band)
		var hv = _h(c.x, c.y, face.x*3+face.y)
		if h>=DungeonGenerator.FACADE_HEIGHT/PX-0.01 and hv%9==0:
			var col: Color = t.neon[hv%t.neon.size()] if t.has("neon") else t.band
			_face(glow, center+n*0.01, along, n, 0.3, 1.0, 1.7, Color(col).lerp(Color.WHITE, 0.2)*0.9)
			glowing = true
	return glowing

## Dim ceiling lights over each room of an indoor area.
func _build_ceiling_lights(t: Dictionary) -> void:
	for z in g.rooms:
		var r: Rect2i = z.rect
		var step = 9
		for y in range(r.position.y+step/2, r.end.y, step):
			for x in range(r.position.x+step/2, r.end.x, step):
				var light = OmniLight3D.new()
				light.light_color = t.light
				light.light_energy = 1.3 if z.role!="safe" else 1.8
				light.omni_range = 8.0
				light.position = Vector3(x+0.5, 2.6, y+0.5)
				level.add_child(light)
				if _h(x, y, 9)%5==0: flickers.append({"node":light, "seed":_h(x, y), "energy":light.light_energy})

## A flat rectangle on a wall face: half-width w along the wall, from height y0 to y1.
func _face(st: SurfaceTool, center: Vector3, along: Vector3, n: Vector3, w: float, y0: float, y1: float, color: Color) -> void:
	var a = center-along*w+Vector3(0, y0, 0)
	var b = center+along*w+Vector3(0, y0, 0)
	var c = center+along*w+Vector3(0, y1, 0)
	var d = center-along*w+Vector3(0, y1, 0)
	# Wind so the quad faces outward along n.
	if along.cross(Vector3.UP).dot(n)>0: _quad(st, a, d, c, b, color)
	else: _quad(st, a, b, c, d, color)

func _build_markings(t: Dictionary) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any = false
	for d in g.decals:
		match d.kind:
			"lane":
				var a: Vector2 = d.a; var b: Vector2 = d.b
				var length = a.distance_to(b)
				var dir = (b-a)/length
				var side = Vector2(-dir.y, dir.x)*0.06
				var at = 0.8
				while at<length-0.8:
					var p0 = a+dir*at; var p1 = a+dir*minf(at+0.9, length-0.8)
					_quad(st, v3(p0-side, 0.012), v3(p0+side, 0.012), v3(p1+side, 0.012), v3(p1-side, 0.012), Color(t.lane).darkened(0.2))
					at += 1.8
					any = true
			"crosswalk":
				var along = Vector2(1, 0) if d.axis=="x" else Vector2(0, 1)
				var across = Vector2(0, 1) if d.axis=="x" else Vector2(1, 0)
				var length: float = d.w if d.axis=="x" else d.h
				var k = -length/2.0+0.3
				while k<length/2.0-0.2:
					var m = d.pos+along*k
					_quad(st, v3(m-across*0.5, 0.012), v3(m+along*0.4-across*0.5, 0.012), v3(m+along*0.4+across*0.5, 0.012), v3(m+across*0.5, 0.012), Color(0.75, 0.75, 0.72))
					k += 0.8
					any = true
			"bays":
				var x0 = d.pos.x-d.w/2.0
				for k in int(d.w/2.0)+1:
					var x = x0+k*2.0
					_flat(st, x-0.04, d.pos.y-1, x+0.04, d.pos.y+1, 0.012, Color(0.8, 0.8, 0.76))
					any = true
			"puddle", "stain", "scorch":
				var col = Color(0.05, 0.08, 0.14) if d.kind=="puddle" else Color(0.03, 0.03, 0.04, 1)
				if d.kind=="scorch": col = Color(0.02, 0.015, 0.015)
				_blob(st, d.pos, d.w*0.45, d.h*0.45, 0.006+(d.get("seed", 0)%5)*0.0005, col, d.get("seed", 0))
				any = true
			"manhole":
				_blob(st, d.pos, 0.34, 0.34, 0.01, Color(0.16, 0.17, 0.2), -1)
				_blob(st, d.pos, 0.26, 0.26, 0.011, Color(0.1, 0.11, 0.13), -1)
				any = true
	if any:
		var m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.4
		st.generate_normals()
		var node = MeshInstance3D.new()
		node.mesh = st.commit()
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(node)

## A flat patch on the ground: a round lid (seed -1) or an irregular stain.
func _blob(st: SurfaceTool, at: Vector2, rx: float, rz: float, y: float, color: Color, seed: int) -> void:
	var steps = 16
	var points: Array = []
	for k in steps:
		var a = k*TAU/steps
		var wobble = 1.0 if seed<0 else 0.78+0.22*sin(a*3.0+seed)+0.1*sin(a*5.0+seed*1.7)
		points.append(Vector3(at.x+cos(a)*rx*wobble, y, at.y+sin(a)*rz*wobble))
	st.set_color(color)
	var center = Vector3(at.x, y, at.y)
	for k in steps:
		st.add_vertex(center)
		st.add_vertex(points[k])
		st.add_vertex(points[(k+1)%steps])

## Water towers and vents on the rooftops, away from the street edge.
func _build_roofs() -> void:
	var top = DungeonGenerator.FACADE_HEIGHT/PX
	for y in DungeonGenerator.SIZE:
		for x in DungeonGenerator.SIZE:
			var c = Vector2i(x, y)
			if g.cells.has(c) or DungeonGenerator.solid_height(g, c)<DungeonGenerator.FACADE_HEIGHT: continue
			var roll = _h(x, y, 77)
			if roll>=30: continue
			var near_street = false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]:
				if g.cells.has(c+d): near_street = true
			if near_street: continue
			var node = models.roof_prop(roll)
			node.position = Vector3(x+0.5, top, y+0.5)
			level.add_child(node)

func _build_signs(t: Dictionary) -> void:
	for s in g.signs:
		var a: Vector2 = s.a; var b: Vector2 = s.b
		var mid = (a+b)/2.0
		var normal = Vector3(0, 0, 1) if absf(a.y-b.y)<0.01 else Vector3(1, 0, 0)
		var color: Color = t.neon[s.color%t.neon.size()]
		var label = Label3D.new()
		label.text = s.text if s.kind=="panel" else "\n".join(s.text.split(""))
		label.font_size = 64 if s.kind=="panel" else 48
		label.pixel_size = 0.006
		label.modulate = color*1.8
		label.outline_modulate = Color(color, 0.6)
		label.outline_size = 10
		label.shaded = false
		label.double_sided = false
		label.position = v3(mid, s.v/PX)+normal*0.08
		if s.kind!="panel": label.position = v3(mid, s.v/PX-0.3)+normal*0.35
		label.rotation.y = 0.0 if normal.z>0 else PI/2
		level.add_child(label)
		var light = OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.6
		light.omni_range = 4.0
		light.position = label.position+normal*0.6
		level.add_child(light)
		if s.flicker: flickers.append({"node":light, "label":label, "seed":s.seed, "energy":1.6})

func _build_props(t: Dictionary) -> void:
	for pr in g.props:
		var node = models.prop(pr, t)
		if node==null: continue
		node.position = v3(pr.pos)
		level.add_child(node)
		prop_nodes[pr] = node
		if node.has_meta("flicker"): flickers.append({"node":node.get_meta("flicker"), "seed":pr.seed, "energy":node.get_meta("flicker").light_energy})

## Subway stairs, doorways into side areas and the ways back out.
func _build_exits(t: Dictionary) -> void:
	for exit in g.exits:
		var node: Node3D
		match exit.kind:
			"subway":
				node = models.subway(t)
				node.position = v3(exit.pos)+Vector3(0, 0.11, 0)
				Models.face(node, exit.face)
			"stairs":
				node = models.subway(t, "EXIT")
				node.position = v3(exit.pos)
				node.rotation.y = 0.0 if exit.face.y>0 else PI
			"door", "gate":
				node = models.doorway(exit, t, exit.kind=="gate" or exit.get("zone", "")=="park")
				# Street doorways sit on the building front; the way out of a
				# side area stands at its edge.
				var at: Vector2 = exit.pos-exit.face*0.5 if exit.has("wall") else exit.pos-exit.face*0.45
				node.position = v3(at)
				Models.face(node, exit.face)
		if node: level.add_child(node)

# --- Hero portraits for the HUD, class cards and character page --------------------

var portraits = {}

## Draws the class's 3D hero standing with its feet at feet, height pixels tall.
func draw_portrait(canvas: CanvasItem, class_id: String, feet: Vector2, height: float) -> void:
	if not portraits.has(class_id): _make_portrait(class_id)
	var p = portraits[class_id]
	if g.player.get("class","")==class_id: Models.CombatAnimator.equip(p.actor,g._weapon())
	p.used = g.clock
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The portrait camera frames the hero's feet at 90% of the image height
	# and its head near the top.
	var size = Vector2(p.viewport.size)
	var scale = height/(size.y*0.7)
	var rect = Rect2(feet-Vector2(size.x*0.5, size.y*0.9)*scale, size*scale)
	canvas.draw_texture_rect(p.viewport.get_texture(), rect, false)

func _make_portrait(class_id: String) -> void:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(240, 300)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var cam = Camera3D.new()
	cam.fov = 30.0
	viewport.add_child(cam)
	cam.position = Vector3(0, 0.95, 2.9)
	cam.look_at(Vector3(0, 0.56, 0), Vector3.UP)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.55, 0.75)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(env)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.92, 0.85)
	viewport.add_child(key)
	var rim = OmniLight3D.new()
	rim.position = Vector3(-0.8, 1.3, -0.9)
	rim.light_color = Color(0.25, 0.95, 1.0)
	rim.light_energy = 2.5
	rim.omni_range = 3.0
	viewport.add_child(rim)
	var rim2 = OmniLight3D.new()
	rim2.position = Vector3(0.9, 0.9, -0.6)
	rim2.light_color = Color(1.0, 0.3, 0.85)
	rim2.light_energy = 2.0
	rim2.omni_range = 3.0
	viewport.add_child(rim2)
	var actor = models.hero(class_id)
	actor.get_meta("model").rotation.y = 0.45
	viewport.add_child(actor)
	models.idle(actor)
	portraits[class_id] = {"viewport":viewport, "actor":actor, "used":g.clock}

# --- Every frame --------------------------------------------------------------------

func sync(dt: float) -> void:
	for id in portraits:
		portraits[id].actor.get_meta("anim").advance(dt)
		if g.clock-portraits[id].used>0.3: portraits[id].viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if hero==null: return
	place_camera(g.player.pos, 1.0-exp(-10*dt) if g.state=="play" else 1.0)
	hero_light.position = v3(g.player.pos, 2.2)
	models.pose_hero(hero, g, dt)
	var alive = {}
	for e in g.enemies:
		if e.hp<=0: continue
		var id = e.get("uid", 0)
		alive[id] = true
		var node = enemy_nodes.get(id)
		if node==null:
			node = models.enemy(e.kind)
			actors.add_child(node)
			if e.has("elite") or e.get("minion", false): models.mark_elite(node, e, Elites.color(e))
			enemy_nodes[id] = node
		models.pose_enemy(node, e, g, dt)
		node.get_meta("anim").advance(g.simulation_delta)
	for id in enemy_nodes.keys():
		if not alive.has(id):
			models.die(enemy_nodes[id])
			enemy_nodes.erase(id)
	for pr in prop_nodes:
		if pr.get("open", false) and not prop_nodes[pr].has_meta("opened"):
			prop_nodes[pr].set_meta("opened", true)
			models.open_prop(prop_nodes[pr], pr)
	for pr in prop_nodes:
		var node: Node3D = prop_nodes[pr]
		if node.has_meta("bob"): node.get_meta("bob").position.y = 1.25+sin(g.clock*3.0+pr.seed)*0.1
		if node.has_meta("blink"): node.get_meta("blink").light_energy = 1.0 if sin(g.clock*3.5)>0 else 0.15
		if node.has_meta("fire"): node.get_meta("fire").light_energy = 2.0+sin(g.clock*17.0+pr.seed)*0.3+sin(g.clock*7.3)*0.25
	for f in flickers:
		var t = g.clock*0.8
		var n = sin(t*13.0+f.seed)*sin(t*7.3+f.seed*2.0)+sin(t*2.1+f.seed*0.7)*0.4
		var on = 0.1 if n<-0.75 else 1.0
		f.node.light_energy = f.energy*on
		if f.has("label"): f.label.modulate.a = 0.3 if on<0.5 else 1.0

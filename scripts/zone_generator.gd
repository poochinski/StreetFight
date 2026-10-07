extends RefCounted
## Builds the side areas off the streets: Starlight Mall (shops off a
## concourse, and the food court, a safe hub with vendors, a stash and a
## transit map), Liberty Park (a grimy 80s city park), Warehouse 13 (storage
## halls, offices and loading bays joined by corridors) and the subway
## stations between streets (platforms either side of the tracks, a stalled
## train, stairs up at both ends).
##
## Uses the same grid as the streets (see dungeon_generator.gd): cells are
## walkable ground, everything else is wall, and blocked cells hold props.
## Each builder fills g.rooms (the entry first), g.exits and g.arrivals.

const DG = preload("res://scripts/dungeon_generator.gd")
const Zones = preload("res://scripts/zones.gd")
const Elites = preload("res://scripts/elites.gd")
const SIZE = DG.SIZE
const ROOM = DG.ROOM
const LOT = DG.LOT

static func generate(g, kind: String, level: int) -> void:
	var reserved = {}
	match kind:
		"mall": _mall(g, level, reserved)
		"park": _park(g, level, reserved)
		"warehouse": _warehouse(g, level, reserved)
		"subway": _subway(g, level, reserved)
	for z in g.rooms: DG._settle(g, z)
	_spawn(g, kind, level)
	DG.build_navigation(g)

## An exit and where the hero stands when arriving through it.
static func _exit(g, kind: String, pos: Vector2, to: Array, label: String, arrive: String, face: Vector2 = Vector2.DOWN) -> void:
	g.exits.append({"kind":kind, "pos":pos, "to":to, "label":label, "face":face})
	g.arrivals[arrive] = pos+face*1.6

static func _room(g, r: Rect2i, type: String, style: String) -> Dictionary:
	DG.carve(g, r.position.x, r.position.y, r.size.x, r.size.y, ROOM)
	DG._style(g, r, style)
	return DG._zone(r, type)

# --- Starlight Mall ------------------------------------------------------------

static func _mall(g, level: int, reserved: Dictionary) -> void:
	# A long concourse running east from the street doors, a cross hall, the
	# food court at the north end of the cross hall, shops off both halls.
	var hall = Rect2i(5, 28, 54, 7)
	var cross = Rect2i(28, 15, 7, 36)
	var court = Rect2i(19, 3, 26, 12)
	var entry = _room(g, Rect2i(5, 28, 9, 7), "atrium", "mall")
	var hall_zone = _room(g, hall, "concourse", "mall")
	var cross_zone = _room(g, cross, "concourse", "mall")
	var food = _room(g, court, "foodcourt", "court")
	food.role = "safe"
	g.safe_rect = Rect2(court.grow(-1))
	var rooms: Array = [entry, food]
	# Shops along the concourse, each with a wide opening onto it.
	var types = ["arcade", "video", "laundromat", "diner", "boutique", "arcade", "boutique", "video"]
	DG._shuffle(g, types)
	var lots = [Rect2i(15, 19, 11, 8), Rect2i(37, 19, 10, 8), Rect2i(15, 36, 11, 9), Rect2i(37, 36, 10, 9), Rect2i(49, 18, 10, 9),
		Rect2i(17, 46, 9, 10), Rect2i(37, 46, 11, 10), Rect2i(49, 36, 10, 14)]
	for i in lots.size():
		var r: Rect2i = lots[i]
		var type: String = types[i%types.size()]
		var shop = _room(g, r, type, {"arcade":"carpet", "diner":"checker", "video":"carpet", "laundromat":"tile", "boutique":"mall"}[type])
		_opening(g, r, hall, cross, reserved)
		rooms.append(shop)
	# The far end of the concourse: a department store, the mall rats' den.
	var store = _room(g, Rect2i(52, 26, 9, 11), "boutique", "mall")
	rooms.append(store)
	g.rooms.append_array(rooms)
	g.rooms.append(cross_zone)
	g.rooms.append(hall_zone)
	var door = Vector2(5.5, 31.5)
	_exit(g, "door", door, ["street", Zones.home_street("mall"), "door:mall"], "Exit to %s" % Zones.street_name(Zones.home_street("mall")), "door", Vector2.RIGHT)
	g.stairs = door
	for c in DG._cells_around(Vector2i(door), 2): reserved[c] = true
	# The food court: vendors along the back wall, tables, a fountain.
	var back = court.position.y+1
	var stalls = [["vendor", court.position.x+4, {"vendor":"pawn"}], ["vendor", court.position.x+10, {"vendor":"juice"}],
		["stash", court.position.x+16, {}], ["transit", court.position.x+21, {}]]
	for s in stalls:
		var r = Rect2i(s[1], back, 2 if s[0]=="vendor" else 1, 1)
		DG._put_block(g, s[0], r, reserved, s[2].merged({"face":Vector2i.DOWN}))
		for c in DG._cells_around(Vector2i(s[1], back+1), 1): reserved[c] = true
	var middle = Vector2i(court.position.x+court.size.x/2, court.position.y+court.size.y/2+1)
	DG._put_block(g, "fountain", Rect2i(middle-Vector2i.ONE, Vector2i(2, 2)), reserved)
	for x in range(court.position.x+2, court.end.x-2, 4):
		for y in [court.end.y-3, court.position.y+5]:
			if absi(x-middle.x)<3: continue
			DG._put_block(g, "table", Rect2i(x, y, 1, 1), reserved, {"color":floori(g._random()*4)})
	for c in [Vector2i(court.position.x+1, court.end.y-2), Vector2i(court.end.x-2, court.end.y-2)]:
		DG._put_block(g, "planter", Rect2i(c, Vector2i.ONE), reserved)
	g.arrivals["foodcourt"] = Vector2(middle)+Vector2(0.5, 2.6)
	# The concourse: planters with palms down the middle, benches, columns.
	for x in range(hall.position.x+10, hall.end.x-3, 6):
		if absi(x-31)<4: continue
		DG._put_block(g, "planter", Rect2i(x, hall.position.y+3, 1, 1), reserved)
		DG._put_loose(g, "bench", Vector2(x+1.6, hall.position.y+3.5), {"axis":"x"})
	for y in range(cross.position.y+3, cross.end.y-2, 7):
		if absi(y-31)<4: continue
		DG._put_block(g, "planter", Rect2i(cross.position.x+3, y, 1, 1), reserved)
	DG._put_loose(g, "neon_floor", Vector2(31.5, 31.5))
	for z in rooms.slice(2):
		if z.type=="boutique": _dress_boutique(g, z, reserved)
		else: DG._dress_interior(g, z, level, reserved)
	_litter(g, rooms)

## Opens a shop onto whichever hall it touches.
static func _opening(g, r: Rect2i, hall: Rect2i, cross: Rect2i, reserved: Dictionary) -> void:
	var cells: Array = []
	if r.end.y==hall.position.y or r.position.y==hall.end.y:
		var y = r.end.y if r.end.y==hall.position.y else r.position.y-1
		var mid = clampi(r.position.x+r.size.x/2, hall.position.x+2, hall.end.x-3)
		for x in range(mid-2, mid+2): cells.append(Vector2i(x, y))
	elif r.end.x==cross.position.x or r.position.x==cross.end.x:
		var x = r.end.x if r.end.x==cross.position.x else r.position.x-1
		var mid = r.position.y+r.size.y/2
		for y in range(mid-2, mid+2): cells.append(Vector2i(x, y))
	else:
		# Not touching a hall: a short passage up or down to the concourse.
		var x = r.position.x+r.size.x/2
		var y0 = mini(r.end.y, hall.end.y)
		var y1 = maxi(r.position.y, hall.position.y)
		for y in range(y0-1, y1+1):
			for dx in 3: cells.append(Vector2i(x-1+dx, y))
	for c in cells:
		g.cells[c] = ROOM
		g.cell_style[c] = "threshold"
		reserved[c] = true

## Clothes racks in rows and mannequins posed along the walls.
static func _dress_boutique(g, z: Dictionary, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	for y in range(r.position.y+2, r.end.y-2, 3):
		for x in range(r.position.x+2, r.end.x-3, 4):
			DG._put_block(g, "rack", Rect2i(x, y, 2, 1), reserved, {"color":floori(g._random()*5)})
	for run in DG._wall_runs(g, r):
		for i in range(1, run.cells.size()-1, 3):
			DG._put_loose(g, "mannequin", DG._against(run.cells[i], run.dir, 0.2), {"face":-run.dir, "color":floori(g._random()*5)})
	for run in DG._wall_runs(g, r):
		if DG._put_loose(g, "chest", DG._against(run.cells[run.cells.size()-1], run.dir, 0.15)): break

# --- Liberty Park --------------------------------------------------------------

static func _park(g, level: int, reserved: Dictionary) -> void:
	# The park fills the grid; the city's buildings stand round its edge.
	var whole = Rect2i(3, 3, SIZE-6, SIZE-6)
	DG.carve(g, whole.position.x, whole.position.y, whole.size.x, whole.size.y, LOT)
	DG._style(g, whole, "grass")
	# A paved promenade round the edge, a loop path and two cross paths.
	var ring = whole.grow(-1)
	for y in range(whole.position.y, whole.end.y):
		for x in range(whole.position.x, whole.end.x):
			var c = Vector2i(x, y)
			if not ring.grow(-1).has_point(c): g.cell_style[c] = "pavers"
	var loop = Rect2i(12, 12, 40, 40)
	for k in range(loop.position.x, loop.end.x):
		for w in 2:
			g.cell_style[Vector2i(k, loop.position.y+w)] = "dirt"
			g.cell_style[Vector2i(k, loop.end.y-1-w)] = "dirt"
			g.cell_style[Vector2i(loop.position.x+w, k)] = "dirt"
			g.cell_style[Vector2i(loop.end.x-1-w, k)] = "dirt"
	for k in range(whole.position.x, whole.end.x):
		for w in 2:
			g.cell_style[Vector2i(k, 31+w)] = "dirt"
			g.cell_style[Vector2i(31+w, k)] = "dirt"
	# The fountain plaza where the paths cross.
	var plaza = Rect2i(27, 27, 10, 10)
	DG._style(g, plaza, "pavers")
	var entry = DG._zone(Rect2i(4, 26, 8, 12), "gate")
	var gate = Vector2(4.5, 32.0)
	_exit(g, "gate", gate, ["street", Zones.home_street("park"), "door:park"], "Exit to %s" % Zones.street_name(Zones.home_street("park")), "door", Vector2.RIGHT)
	g.stairs = gate
	for c in DG._cells_around(Vector2i(gate), 3): reserved[c] = true
	# A pond in the south-west, a camp in the north-west, the bandshell in the
	# north-east (the Hex Kids' turf), a playground in the south-east.
	var pond = Rect2i(15, 39, 10, 7)
	for y in range(pond.position.y, pond.end.y):
		for x in range(pond.position.x, pond.end.x):
			var d = Vector2(x+0.5, y+0.5)-Vector2(pond.get_center())
			if (d.x/5.0)*(d.x/5.0)+(d.y/3.5)*(d.y/3.5)<1.0:
				g.cell_style[Vector2i(x, y)] = "water"
				g.blocked[Vector2i(x, y)] = true
	var zones: Array = [entry]
	var plaza_zone = DG._zone(plaza, "park")
	zones.append(plaza_zone)
	zones.append(DG._zone(Rect2i(14, 36, 14, 14), "pond"))
	var camp = DG._zone(Rect2i(15, 15, 12, 12), "camp")
	DG._style(g, camp.rect.grow(-2), "dirt")
	zones.append(camp)
	var shell = DG._zone(Rect2i(38, 14, 12, 12), "bandshell")
	DG._style(g, shell.rect.grow(-1), "pavers")
	zones.append(shell)
	zones.append(DG._zone(Rect2i(38, 38, 12, 12), "playground"))
	zones.append(DG._zone(Rect2i(40, 52, 16, 6), "lawn"))
	zones.append(DG._zone(Rect2i(52, 6, 6, 18), "lawn"))
	zones.append(DG._zone(Rect2i(6, 50, 16, 8), "lawn"))
	g.rooms.append_array(zones)
	DG._put_block(g, "fountain", Rect2i(31, 31, 2, 2), reserved)
	for o in [Vector2(0, -2.6), Vector2(0, 2.6), Vector2(-2.6, 0), Vector2(2.6, 0)]:
		DG._put_loose(g, "bench", Vector2(32, 32)+o, {"axis":"x" if o.x==0 else "y"})
	DG._put_block(g, "bandshell", Rect2i(41, 15, 6, 3), reserved)
	for k in 3: DG._put_loose(g, "barrel_fire", Vector2(40.5+k*3, 22.5))
	DG._dress_lot(g, camp, level, reserved)
	for x in [40, 44, 48]:
		DG._put_block(g, "swing", Rect2i(x, 41, 2, 1), reserved)
	DG._put_block(g, "slide", Rect2i(42, 45, 1, 2), reserved)
	# Trees: thick round the edge and in the lawns, never on a path.
	for attempt in 420:
		var c = Vector2i(5+floori(g._random()*(SIZE-10)), 5+floori(g._random()*(SIZE-10)))
		if g.cell_style.get(c, "")!="grass": continue
		var near = false
		for z in [plaza_zone, camp, shell] :
			if z.rect.grow(1).has_point(c): near = true
		if near or c.distance_to(Vector2i(gate))<6: continue
		var kind = "tree" if g._random()<0.85 else "palm"
		DG._put_block(g, kind, Rect2i(c, Vector2i.ONE), reserved, {"lean":g._between(-0.3, 0.3), "size":g._between(0.8, 1.25), "color":floori(g._random()*3)})
	# Lamps along the loop path, benches here and there, litter.
	for k in range(loop.position.x+3, loop.end.x-2, 7):
		for c in [Vector2i(k, loop.position.y+2), Vector2i(k, loop.end.y-3), Vector2i(loop.position.x+2, k), Vector2i(loop.end.x-3, k)]:
			if g.cell_style.get(c, "")=="grass": DG._put_block(g, "streetlight_low", Rect2i(c, Vector2i.ONE), reserved)
	for k in 10:
		var c = DG._rand_cell(g, loop, 0)
		if g.cell_style.get(c, "")=="dirt": DG._put_loose(g, "bench", DG._jitter(g, c, 0.1), {"axis":"x" if g._random()<0.5 else "y"})
	for k in 6:
		var c = DG._rand_cell(g, whole, 3)
		if g._walkable(Vector2(c)+Vector2(0.5, 0.5)): DG._put_loose(g, "chest" if k==0 else "trash", DG._jitter(g, c, 0.2))
	for k in 40: DG._put_loose(g, "paper", DG._jitter(g, DG._rand_cell(g, whole, 2), 0.4))
	g.decals.append({"kind":"stain", "pos":Vector2(33, 22), "w":1.4, "h":1.0, "seed":3})

# --- Warehouse 13 --------------------------------------------------------------

static func _warehouse(g, level: int, reserved: Dictionary) -> void:
	# Halls of different sizes scattered over the grid, each joined to its
	# nearest earlier hall by a three-wide corridor.
	var rooms: Array = []
	var entry_rect = Rect2i(4, 26, 9, 10)
	rooms.append(_room(g, entry_rect, "loading", "concrete"))
	var types = ["warehouse", "office", "warehouse", "loading", "warehouse", "office", "warehouse", "cold", "warehouse"]
	var placed = 0
	for attempt in 400:
		if placed>=types.size(): break
		var w = 8+floori(g._random()*7)
		var h = 7+floori(g._random()*6)
		var r = Rect2i(3+floori(g._random()*(SIZE-6-w)), 3+floori(g._random()*(SIZE-6-h)), w, h)
		var clash = false
		for other in rooms:
			if other.rect.grow(3).intersects(r): clash = true
		if clash: continue
		var type: String = types[placed]
		rooms.append(_room(g, r, type, {"warehouse":"concrete", "office":"carpet", "loading":"concrete", "cold":"tile"}[type]))
		placed += 1
	for i in range(1, rooms.size()):
		var nearest = 0
		for j in i:
			if rooms[j].pos.distance_to(rooms[i].pos)<rooms[nearest].pos.distance_to(rooms[i].pos): nearest = j
		_corridor(g, Vector2i(rooms[i].pos), Vector2i(rooms[nearest].pos))
	# A loop or two so it is not one long dead end.
	for k in 2:
		var a = 1+floori(g._random()*(rooms.size()-1))
		var b = 1+floori(g._random()*(rooms.size()-1))
		if a!=b: _corridor(g, Vector2i(rooms[a].pos), Vector2i(rooms[b].pos))
	g.rooms.append_array(rooms)
	var door = Vector2(4.5, 31.0)
	_exit(g, "door", door, ["street", Zones.home_street("warehouse"), "door:warehouse"], "Exit to %s" % Zones.street_name(Zones.home_street("warehouse")), "door", Vector2.RIGHT)
	g.stairs = door
	for c in DG._cells_around(Vector2i(door), 2): reserved[c] = true
	for c in g.cells:
		if g.cells[c]==ROOM and not g.cell_style.has(c): g.cell_style[c] = "concrete"
	for z in rooms:
		match z.type:
			"office": _dress_office(g, z, reserved)
			"loading", "cold": _dress_loading(g, z, reserved)
			_: DG._dress_interior(g, z, level, reserved)
	_litter(g, rooms)

static func _corridor(g, a: Vector2i, b: Vector2i) -> void:
	var corner = Vector2i(b.x, a.y) if g._random()<0.5 else Vector2i(a.x, b.y)
	for leg in [[a, corner], [corner, b]]:
		var from: Vector2i = leg[0]; var to: Vector2i = leg[1]
		var lo = Vector2i(mini(from.x, to.x)-1, mini(from.y, to.y)-1)
		var hi = Vector2i(maxi(from.x, to.x)+1, maxi(from.y, to.y)+1)
		for y in range(lo.y, hi.y+1):
			for x in range(lo.x, hi.x+1):
				var c = Vector2i(x, y)
				if x>0 and y>0 and x<SIZE-1 and y<SIZE-1 and not g.cells.has(c):
					g.cells[c] = ROOM
					g.cell_style[c] = "concrete"

## Desks in rows with a TV on some, filing shelves along the wall.
static func _dress_office(g, z: Dictionary, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	for y in range(r.position.y+2, r.end.y-2, 3):
		for x in range(r.position.x+2, r.end.x-3, 4):
			if DG._put_block(g, "counter", Rect2i(x, y, 2, 1), reserved, {"axis":"x", "length":2, "desk":true}) and g._random()<0.5:
				DG._put_loose(g, "tv_small", Vector2(x+1.0, y+0.4))
	var runs = DG._wall_runs(g, r)
	for run in runs.slice(0, 1):
		for i in range(1, mini(run.cells.size()-1, 5)):
			DG._put_block(g, "shelf", Rect2i(run.cells[i], Vector2i.ONE), reserved, {"axis":"x" if run.dir==Vector2i.UP else "y", "length":1})
	if not runs.is_empty(): DG._put_loose(g, "chest", DG._against(runs[0].cells[runs[0].cells.size()-1], runs[0].dir, 0.15))

## Pallets of crates in rows, drums, a forklift-sized gap down the middle.
static func _dress_loading(g, z: Dictionary, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	for y in range(r.position.y+1, r.end.y-1, 3):
		for x in [r.position.x+1, r.end.x-2]:
			if g._random()<0.7: DG._put_block(g, "pallet", Rect2i(x, y, 1, 1), reserved, {"height":1+floori(g._random()*3)})
	for k in 2: DG._put_block(g, "drums", Rect2i(DG._rand_cell(g, r, 2), Vector2i.ONE), reserved)
	for k in 3: DG._put_loose(g, "crate", DG._jitter(g, DG._rand_cell(g, r, 2), 0.3))
	if z.type=="cold": DG._put_loose(g, "chest", DG._jitter(g, DG._rand_cell(g, r, 2), 0.1))

# --- Subway stations -----------------------------------------------------------

static func _subway(g, level: int, reserved: Dictionary) -> void:
	# Two platforms either side of the tracks, running west to east, with a
	# mezzanine and stairs up at each end.
	var north = Rect2i(6, 22, 52, 6)
	var tracks = Rect2i(6, 28, 52, 4)
	var south = Rect2i(6, 32, 52, 5)
	var west = Rect2i(3, 18, 8, 23)
	var east = Rect2i(53, 18, 8, 23)
	var zones: Array = []
	zones.append(_room(g, west, "mezzanine", "platform"))
	zones.append(_room(g, north, "platform", "platform"))
	_room(g, tracks, "tracks", "rail")
	zones.append(_room(g, south, "platform", "platform"))
	zones.append(_room(g, east, "mezzanine", "platform"))
	# Platform edges are painted yellow.
	for x in range(north.position.x, north.end.x):
		g.cell_style[Vector2i(x, north.end.y-1)] = "edge"
		g.cell_style[Vector2i(x, south.position.y)] = "edge"
	# Side rooms off the mezzanines: a token booth and a maintenance room.
	zones.append(_room(g, Rect2i(13, 11, 9, 8), "warehouse", "concrete"))
	_corridor(g, Vector2i(14, 20), Vector2i(16, 16))
	zones.append(_room(g, Rect2i(42, 40, 10, 8), "warehouse", "concrete"))
	_corridor(g, Vector2i(47, 36), Vector2i(47, 42))
	g.rooms.append_array(zones)
	var up_west = Vector2(7.0, 20.5)
	var up_east = Vector2(57.0, 38.5)
	_exit(g, "stairs", up_west, ["street", level, "subway"], "Stairs up to %s" % Zones.street_name(level), "west", Vector2.DOWN)
	_exit(g, "stairs", up_east, ["street", level+1, "start"], "Stairs up to %s" % Zones.street_name(level+1), "east", Vector2.UP)
	g.stairs = up_east
	for p in [up_west, up_east]:
		for c in DG._cells_around(Vector2i(p), 2): reserved[c] = true
	# Tiled pillars down both platforms, benches between them, a stalled train.
	for x in range(north.position.x+4, north.end.x-2, 6):
		DG._put_block(g, "pillar", Rect2i(x, north.position.y+2, 1, 1), reserved)
		DG._put_block(g, "pillar", Rect2i(x, south.end.y-3, 1, 1), reserved)
		if g._random()<0.6: DG._put_loose(g, "bench", Vector2(x+3.0, north.position.y+1.0), {"axis":"x"})
	var train_x = 16+floori(g._random()*14)
	DG._put_block(g, "train", Rect2i(train_x, tracks.position.y, 16, 3), reserved, {"axis":"x", "length":16})
	DG._put_block(g, "counter", Rect2i(4, 26, 1, 3), reserved, {"axis":"y", "length":3})
	DG._put_block(g, "transit", Rect2i(9, 24, 1, 1), reserved, {"face":Vector2i.DOWN})
	for p in [Vector2(30.5, 23.0), Vector2(44.5, 35.5)]: DG._put_loose(g, "payphone", p, {"face":Vector2i.DOWN})
	for z in g.rooms:
		if z.type=="warehouse": DG._dress_interior(g, z, level, reserved)
	_litter(g, zones)
	for k in 12: DG._put_loose(g, "paper", DG._jitter(g, DG._rand_cell(g, north, 0), 0.4))

# --- Shared ------------------------------------------------------------------

static func _litter(g, rooms: Array) -> void:
	for z in rooms:
		var r: Rect2i = z.rect
		for k in r.size.x*r.size.y/120: DG._put_loose(g, "paper", DG._jitter(g, DG._rand_cell(g, r, 1), 0.4))
		if z.role=="safe": continue
		var walls = DG._wall_cells(g, r)
		DG._shuffle(g, walls)
		for k in mini(walls.size(), r.size.x*r.size.y/150): DG._put_loose(g, "trash", DG._against(walls[k][0], walls[k][1], 0.25))

## Enemy packs in every room but the entry and the safe food court, and the
## side quest's boss in the room farthest from the way in.
static func _spawn(g, kind: String, level: int) -> void:
	DG._spawn_enemies(g, level, false)
	if g.safe_rect.size!=Vector2.ZERO:
		g.enemies = g.enemies.filter(func(e): return not g.safe_rect.grow(3).has_point(e.pos))
	if not Zones.QUESTS.has(kind): return
	var distances = DG._walk_distances(g, Vector2i(g.rooms[0].pos))
	var far = g.rooms[0]
	for z in g.rooms:
		if z.role=="safe": continue
		if distances.get(Vector2i(z.pos), -1)>distances.get(Vector2i(far.pos), -1): far = z
	if kind=="park": far = g.rooms.filter(func(z): return z.type=="bandshell")[0]
	var quest: Dictionary = Zones.QUESTS[kind]
	var done = g.player.get("quests", {}).get(kind, "")=="done"
	g.enemies = g.enemies.filter(func(e): return e.pos.distance_to(far.pos)>4.0)
	var pack: Array = []
	for j in 4:
		var body = quest.kind if j==0 else ("imp" if j%2==1 else "ranged")
		var enemy = g._spawn_enemy(body, DG._spot(g, far, 1.0))
		enemy.attack = g._between(0.5, 1.5)
		pack.append(enemy)
	Elites.promote_pack(g, pack, "rare", level+1)
	if not done:
		var boss: Dictionary = pack[0]
		boss.elite.name = quest.boss
		boss.quest = kind
		boss.max_hp *= 1.5; boss.hp = boss.max_hp
		boss.xp_mult = boss.get("xp_mult", 1.0)*1.5

extends RefCounted
## Builds a floor as a ruined 1980s city district: a grid of wide streets where
## some street segments are closed so blocks merge, open plazas, parking lots,
## survivor camps and collapsed lots, and burned-out shops the hero can walk
## into. The subway entrance sits in the outdoor zone farthest from the start;
## on floor 3 a whole block opens into the Warden's plaza.
##
## cells values are the ground type of walkable cells; anything not in cells is
## a solid building. blocked cells (cars, walls, cabinets) stay in cells for
## drawing but cannot be walked through or seen past.

const Data = preload("res://scripts/data.gd")
const Elites = preload("res://scripts/elites.gd")
const Zones = preload("res://scripts/zones.gd")
const SIZE = 64
const ROOM = 1       # building interior floor
const CORRIDOR = 2   # street asphalt
const SIDEWALK = 3
const LOT = 4        # plazas, parking lots, camps and collapsed lots
## Full height of a building front in screen pixels. Walls closer to open
## ground behind them are cut down so they never hide anyone standing there.
const FACADE_HEIGHT = 144.0
const CUT_HEIGHTS = [36.0, 52.0, 80.0, 108.0, 136.0]
const INTERIORS = ["arcade", "diner", "video", "laundromat", "warehouse"]
const PLAZAS = ["park", "parking", "camp"]

static func carve(g, x: int,y: int,w: int,h: int,value: int = ROOM) -> void:
	for j in range(y,y+h):
		for i in range(x,x+w):
			if i>0 and j>0 and i<SIZE-1 and j<SIZE-1:
				var cell = Vector2i(i,j)
				if value!=CORRIDOR or not g.cells.has(cell): g.cells[cell] = value

static func generate(g, number: int) -> void:
	var vb = _bands(g)
	var hb = _bands(g)
	var nv = vb.size(); var nh = hb.size()
	var reserved = {}
	# Street segments join neighbouring crossings. Closing some merges blocks so
	# every floor has its own shape, while every crossing stays reachable.
	var segments = {}
	for j in nh:
		for i in nv-1: segments["h:%d:%d" % [i,j]] = true
	for j in nh-1:
		for i in nv: segments["v:%d:%d" % [i,j]] = true
	var keys = segments.keys()
	_shuffle(g,keys)
	var closed = 0
	for key in keys:
		if closed>=int(keys.size()*0.3): break
		if g._random()<0.45: continue
		segments[key] = false
		if _crossings_connected(segments,nv,nh): closed += 1
		else: segments[key] = true
	var corner = Vector2i(0 if g._random()<0.5 else nv-1,0 if g._random()<0.5 else nh-1)
	# Floor 3: the block farthest from the start opens into the Warden's plaza.
	var arena_block = Vector2i(-1,-1)
	if number==3:
		arena_block = Vector2i(0 if corner.x==nv-1 else nv-2,0 if corner.y==nh-1 else nh-2)
		for key in _block_sides(arena_block.x,arena_block.y): segments[key] = true
	var zones: Array = []
	for j in nh:
		for i in nv:
			var r = Rect2i(vb[i].x,hb[j].x,vb[i].y,hb[j].y)
			carve(g,r.position.x,r.position.y,r.size.x,r.size.y,CORRIDOR)
			zones.append(_zone(r,"crossing",Vector2i(i,j)))
	for key in segments:
		if not segments[key]: continue
		var r = _segment_rect(key,vb,hb)
		carve(g,r.position.x,r.position.y,r.size.x,r.size.y,CORRIDOR)
		var zone = _zone(r,"street")
		zone["axis"] = "x" if key.begins_with("h") else "y"
		zones.append(zone)
	# Blocks become solid buildings, walk-in ruins, plazas or collapsed lots.
	var blocks: Array = []
	for j in nh-1:
		for i in nv-1:
			var r = Rect2i(vb[i].x+vb[i].y,hb[j].x+hb[j].y,vb[i+1].x-vb[i].x-vb[i].y,hb[j+1].x-hb[j].x-hb[j].y)
			var open_sides: Array = []
			for key in _block_sides(i,j):
				if segments[key]: open_sides.append(key)
			blocks.append({"rect":r,"index":Vector2i(i,j),"open":open_sides})
	_shuffle(g,blocks)
	var interiors = 0
	var plazas = 0
	for b in blocks:
		var r: Rect2i = b.rect
		if b.index==arena_block:
			carve(g,r.position.x,r.position.y,r.size.x,r.size.y,LOT)
			_style(g,r,"pavers")
			var arena_rect = r.grow_individual(vb[b.index.x].y,hb[b.index.y].y,vb[b.index.x+1].y,hb[b.index.y+1].y)
			var zone = _zone(arena_rect,"arena")
			zone.pos = Vector2(r.position)+Vector2(r.size)/2.0
			zones.append(zone)
			continue
		if b.open.is_empty(): continue
		var roll = g._random()
		var kind = "solid"
		if interiors<2 or roll<0.36: kind = "interior"
		elif plazas<1 or roll<0.56: kind = "plaza"
		elif roll<0.78: kind = "collapsed"
		if kind=="interior" and (r.size.x<7 or r.size.y<7): kind = "plaza"
		match kind:
			"interior":
				interiors += 1
				zones.append(_interior(g,b,reserved))
			"plaza":
				plazas += 1
				carve(g,r.position.x,r.position.y,r.size.x,r.size.y,LOT)
				var zone = _zone(r,PLAZAS[floori(g._random()*PLAZAS.size())])
				_style(g,r,{"park":"grass","parking":"parking","camp":"dirt"}[zone.type])
				zones.append(zone)
			"collapsed":
				carve(g,r.position.x,r.position.y,r.size.x,r.size.y,LOT)
				_style(g,r,"rubble")
				# Corner stubs of the old building's walls are left standing.
				for k in 2:
					var cx = r.position.x if g._random()<0.5 else r.end.x-1
					var cy = r.position.y if g._random()<0.5 else r.end.y-1
					var dx = 1 if cx==r.position.x else -1
					var dy = 1 if cy==r.position.y else -1
					for step in 2+floori(g._random()*3):
						g.cells.erase(Vector2i(cx+dx*step,cy))
						g.cells.erase(Vector2i(cx,cy+dy*step))
					g.cells.erase(Vector2i(cx,cy))
				zones.append(_zone(r,"collapsed"))
	_sidewalks(g)
	for z in zones: _settle(g,z)
	# The start is a corner crossing; the exit is the outdoor zone farthest away.
	var start = -1
	for i in zones.size():
		if zones[i].type=="crossing" and zones[i].grid==corner: start = i
	var start_zone = zones[start]
	zones.remove_at(start)
	start_zone.role = "start"
	var distances = _walk_distances(g,Vector2i(start_zone.pos))
	var exit = -1
	var best = -1
	for i in zones.size():
		var z = zones[i]
		if number==3 and z.type!="arena": continue
		if number<3 and not (z.type in ["crossing","street","park","parking","camp","collapsed"]): continue
		var d = distances.get(Vector2i(z.pos),-1)
		if d>best:
			best = d
			exit = i
	var exit_zone = zones[exit]
	zones.remove_at(exit)
	exit_zone.role = "arena" if number==3 else "stairs"
	g.rooms.append(start_zone)
	# Walk-in buildings and plazas come first so previews and tests find them early.
	zones.sort_custom(func(a,b): return _zone_rank(a)<_zone_rank(b))
	g.rooms.append_array(zones)
	g.rooms.append(exit_zone)
	g.stairs = exit_zone.pos
	g.player.pos = start_zone.pos
	for c in _cells_around(Vector2i(g.stairs),2): reserved[c] = true
	for c in _cells_around(Vector2i(start_zone.pos),2 if number>1 else 1): reserved[c] = true
	for z in g.rooms: reserved[Vector2i(z.pos)] = true
	for z in g.rooms: _dress(g,z,number,reserved)
	for z in g.rooms: _settle(g,z)
	# The Warden's plaza floor stays clear of street manholes and potholes.
	for z in g.rooms:
		if z.type=="arena":
			g.decals = g.decals.filter(func(d): return not (d.kind in ["manhole","pothole"] and z.rect.has_point(Vector2i(d.pos))))
	_add_doors(g,number)
	_landmark_entrances(g)
	var forward = _sidewalk_subway(g, g.stairs) if number<Zones.STREETS else {}
	var backward = _sidewalk_subway(g, start_zone.pos) if number>1 else {}
	if not forward.is_empty(): g.stairs = forward.pos
	_add_signs(g,number)
	# No neon sign crowds a doorway's marquee.
	for door in g.exits:
		if door.kind=="door": g.signs = g.signs.filter(func(s): return s.cells.all(func(c): return Vector2(c).distance_to(Vector2(door.wall))>2.5))
	_spawn_enemies(g,number)
	build_navigation(g)
	# The subway entrance leads down to the station toward the next street;
	# past the first street, stairs at the start lead back down to the last one.
	g.arrivals["start"] = start_zone.pos
	if number<Zones.STREETS:
		g.exits.append({"kind":"subway","pos":g.stairs,"to":["subway",number,"west"],"label":"Take the subway to %s" % Zones.street_name(number+1),"face":forward.face})
		g.arrivals["subway"] = _beside(g,g.stairs,2.0)
	if number>1:
		g.exits.append({"kind":"subway","pos":backward.pos,"to":["subway",number-1,"east"],"label":"Subway back to %s" % Zones.street_name(number-1),"face":backward.face})
		g.arrivals["start"] = _beside(g,backward.pos,2.0)
	g.player.pos = g.arrivals["start"]

## Open ground about distance cells from point, for arriving beside an exit.
static func _beside(g, point: Vector2, distance: float) -> Vector2:
	for k in 16:
		var at = point+Vector2.from_angle(PI/2+k*TAU/16)*distance
		if g._free(at,0.35): return at
	return point

## Doorways into the side areas: a doorway in a full-height building front,
## with a sidewalk in front of it, away from the start, the subway and other doors.
static func _add_doors(g, number: int) -> void:
	var kinds: Array = Zones.DOORS.get(number,[])
	if kinds.is_empty(): return
	var candidates: Array = []
	for c in g.cells:
		if g.cells[c]!=SIDEWALK or g.blocked.has(c): continue
		for out in [Vector2i.UP,Vector2i.LEFT]:
			var wall = c+out
			var along = Vector2i(out.y,out.x)
			if g.cells.has(wall) or g.cells.has(wall+out) or solid_height(g,wall)<FACADE_HEIGHT: continue
			if g.cells.has(wall+along) or g.cells.has(wall-along): continue
			if g.cells.get(c+along,0)!=SIDEWALK or g.cells.get(c-along,0)!=SIDEWALK: continue
			if g.blocked.has(c+along) or g.blocked.has(c-along) or g.blocked.has(c-out): continue
			candidates.append([c,out])
	_shuffle(g,candidates)
	var start: Vector2 = g.rooms[0].pos
	for kind in kinds:
		for relax in [1.0,0.6,0.0]:
			var found = false
			for pair in candidates:
				if kind in ["mall", "park"]:
					var back: Vector2i = pair[0]+pair[1]*6
					if back.x<5 or back.y<5 or back.x>SIZE-6 or back.y>SIZE-6: continue
				var pos = Vector2(pair[0])+Vector2(0.5,0.5)
				if pos.distance_to(start)<12*relax or pos.distance_to(g.stairs)<8*relax: continue
				var crowded = false
				for other in g.exits:
					if other.pos.distance_to(pos)<14*relax: crowded = true
				if crowded: continue
				var out: Vector2i = pair[1]
				g.exits.append({"kind":"door","pos":pos,"wall":pair[0]+out,"face":Vector2(-out),"to":[kind,number,"door"],
					"label":"Enter %s" % Zones.PLACES[kind].name,"sign":Zones.PLACES[kind].sign,"zone":kind})
				g.arrivals["door:"+kind] = pos+Vector2(-out)*0.6
				found = true
				break
			if found: break

## Carve a forecourt into the block so entrances have space beyond the sidewalk.
static func _landmark_entrances(g) -> void:
	for e in g.exits:
		if e.get("zone", "") not in ["mall", "park"]: continue
		var origin = Vector2i(e.pos)
		var inward = -Vector2i(e.face)
		var along = Vector2i(inward.y, inward.x)
		var footprint = {}
		for depth in range(0, 6):
			for width in range(-4, 5):
				var cell = origin+inward*depth+along*width
				if cell.x<1 or cell.y<1 or cell.x>=SIZE-1 or cell.y>=SIZE-1: continue
				footprint[cell] = true
				g.cells[cell] = LOT
				g.cell_style[cell] = ("pavers" if absi(width)<=1 or depth>=4 else "parking") if e.zone=="mall" else ("dirt" if absi(width)<=1 else "grass")
				g.blocked.erase(cell)
		g.props = g.props.filter(func(pr): return not footprint.has(Vector2i(pr.pos)))
		g.decals = g.decals.filter(func(pr): return not footprint.has(Vector2i(pr.pos)))
		e.pos = Vector2(origin+inward*(5 if e.zone=="mall" else 2))+Vector2(0.5,0.5)
		e.wall = Vector2i(e.pos)+inward
		e["landmark"] = true
		g.arrivals["door:"+e.zone] = e.pos+e.face*0.6

## A recessed sidewalk bay keeps the stairs out of traffic, with a clear approach.
static func _sidewalk_subway(g, near: Vector2) -> Dictionary:
	var best = {}
	var distance = INF
	for cell in g.cells:
		if g.cells[cell]!=SIDEWALK: continue
		for face in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
			if g.cells.get(cell+face, 0)!=CORRIDOR: continue
			if cell.x<4 or cell.y<4 or cell.x>SIZE-5 or cell.y>SIZE-5: continue
			var pos = Vector2(cell-face)+Vector2(0.5,0.5)
			if g.exits.any(func(e): return e.pos.distance_to(pos)<10): continue
			if pos.distance_to(near)<distance:
				distance = pos.distance_to(near)
				best = {"pos":pos, "face":Vector2(face)}
	if best.is_empty(): return {"pos":near, "face":Vector2.DOWN}
	var center = Vector2i(best.pos)
	var outward = Vector2i(best.face)
	var side = Vector2i(outward.y, outward.x)
	var footprint = {}
	for depth in range(-2, 2):
		for width in range(-2, 3):
			var cell = center+outward*depth+side*width
			footprint[cell] = true
			g.cells[cell] = SIDEWALK
			g.blocked.erase(cell)
			g.cell_style.erase(cell)
	g.props = g.props.filter(func(pr): return not footprint.has(Vector2i(pr.pos)))
	g.decals = g.decals.filter(func(pr): return not footprint.has(Vector2i(pr.pos)))
	return best

static func _zone(r: Rect2i,type: String,grid: Vector2i = Vector2i(-1,-1)) -> Dictionary:
	return {"pos":Vector2(r.position)+Vector2(r.size)/2.0,"w":r.size.x,"h":r.size.y,"rect":r,"role":"plain","type":type,"grid":grid}

## Moves a zone's center onto open ground if a wall or prop covers it.
static func _settle(g, z: Dictionary) -> void:
	if g._free(z.pos,0.3): return
	var r: Rect2i = z.rect
	var best = z.pos
	var best_distance = INF
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			var point = Vector2(x+0.5,y+0.5)
			if g._free(point,0.3) and point.distance_to(z.pos)<best_distance:
				best_distance = point.distance_to(z.pos)
				best = point
	z.pos = best

static func _zone_rank(z: Dictionary) -> int:
	if z.type in INTERIORS: return 0
	if z.type in PLAZAS or z.type=="collapsed": return 1
	if z.type=="street": return 2
	return 3

static func _bands(g) -> Array:
	var bands: Array = []
	var at = 3+floori(g._random()*2)
	while true:
		var width = 6+floori(g._random()*3)
		if at+width>SIZE-3: break
		bands.append(Vector2i(at,width))
		at += width+9+floori(g._random()*4)
	return bands

static func _shuffle(g, list: Array) -> void:
	for i in range(list.size()-1,0,-1):
		var j = floori(g._random()*(i+1))
		var t = list[i]; list[i] = list[j]; list[j] = t

static func _block_sides(i: int,j: int) -> Array:
	return ["h:%d:%d" % [i,j],"h:%d:%d" % [i,j+1],"v:%d:%d" % [i,j],"v:%d:%d" % [i+1,j]]

static func _segment_rect(key: String,vb: Array,hb: Array) -> Rect2i:
	var parts = key.split(":")
	var i = int(parts[1]); var j = int(parts[2])
	if parts[0]=="h": return Rect2i(vb[i].x+vb[i].y,hb[j].x,vb[i+1].x-vb[i].x-vb[i].y,hb[j].y)
	return Rect2i(vb[i].x,hb[j].x+hb[j].y,vb[i].y,hb[j+1].x-hb[j].x-hb[j].y)

static func _crossings_connected(segments: Dictionary,nv: int,nh: int) -> bool:
	var seen = {Vector2i.ZERO:true}
	var queue = [Vector2i.ZERO]
	while not queue.is_empty():
		var n: Vector2i = queue.pop_back()
		var links = []
		if n.x<nv-1 and segments["h:%d:%d" % [n.x,n.y]]: links.append(n+Vector2i.RIGHT)
		if n.x>0 and segments["h:%d:%d" % [n.x-1,n.y]]: links.append(n+Vector2i.LEFT)
		if n.y<nh-1 and segments["v:%d:%d" % [n.x,n.y]]: links.append(n+Vector2i.DOWN)
		if n.y>0 and segments["v:%d:%d" % [n.x,n.y-1]]: links.append(n+Vector2i.UP)
		for next in links:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()==nv*nh

static func _style(g, r: Rect2i, style: String) -> void:
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x): g.cell_style[Vector2i(x,y)] = style

## A burned-out shop: one-cell walls, doors onto its open streets, and
## sometimes an inner wall with a gap splitting it in two.
static func _interior(g, b: Dictionary, reserved: Dictionary) -> Dictionary:
	var r: Rect2i = b.rect
	var inner = r.grow(-1)
	var type = INTERIORS[floori(g._random()*INTERIORS.size())]
	carve(g,inner.position.x,inner.position.y,inner.size.x,inner.size.y,ROOM)
	_style(g,inner,{"arcade":"carpet","diner":"checker","video":"carpet","laundromat":"tile","warehouse":"concrete"}[type])
	var doors = 0
	var sides: Array = b.open.duplicate()
	_shuffle(g,sides)
	for key in sides:
		if doors>0 and g._random()<0.35: continue
		doors += 1
		var wide = 3 if g._random()<0.6 else 5
		var parts = key.split(":")
		var horizontal = parts[0]=="h"
		var span = inner.size.x if horizontal else inner.size.y
		wide = mini(wide,span-2)
		var at = 1+floori(g._random()*maxi(1,span-wide-1))
		for k in wide:
			var cell: Vector2i
			var outside: Vector2i
			if horizontal:
				var top = int(parts[2])==b.index.y
				cell = Vector2i(inner.position.x+at+k,r.position.y if top else r.end.y-1)
				outside = cell+(Vector2i.UP if top else Vector2i.DOWN)
			else:
				var left = int(parts[1])==b.index.x
				cell = Vector2i(r.position.x if left else r.end.x-1,inner.position.y+at+k)
				outside = cell+(Vector2i.LEFT if left else Vector2i.RIGHT)
			g.cells[cell] = ROOM
			g.cell_style[cell] = "threshold"
			for c in [cell,outside,cell*2-outside]: reserved[c] = true
	if inner.size.x>=10 and g._random()<0.6:
		var wx = inner.position.x+inner.size.x/2
		var gap = inner.position.y+1+floori(g._random()*maxi(1,inner.size.y-4))
		for y in range(inner.position.y,inner.end.y):
			if y<gap or y>=gap+3: g.cells.erase(Vector2i(wx,y))
			else:
				for c in [Vector2i(wx-1,y),Vector2i(wx,y),Vector2i(wx+1,y)]: reserved[c] = true
	var zone = _zone(inner,type)
	return zone

## Street cells beside a building become sidewalk with a curb.
static func _sidewalks(g) -> void:
	var walks: Array = []
	for cell in g.cells:
		if g.cells[cell]!=CORRIDOR: continue
		for dy in [-1,0,1]:
			for dx in [-1,0,1]:
				if not g.cells.has(cell+Vector2i(dx,dy)):
					walks.append(cell)
					break
	for cell in walks: g.cells[cell] = SIDEWALK

static func _cells_around(c: Vector2i, radius: int) -> Array:
	var out: Array = []
	for y in range(-radius,radius+1):
		for x in range(-radius,radius+1): out.append(c+Vector2i(x,y))
	return out

static func _walk_distances(g, start: Vector2i) -> Dictionary:
	var distances = {start:0}
	var queue = [start]
	var cursor = 0
	while cursor<queue.size():
		var cell = queue[cursor]
		cursor += 1
		for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+dir
			if g.cells.has(next) and not distances.has(next):
				distances[next] = distances[cell]+1
				queue.append(next)
	return distances

## Height of a solid cell's block in screen pixels. Full building fronts only
## where no walkable ground lies behind them, so a wall never hides anyone.
static func solid_height(g, c: Vector2i) -> float:
	if g.wall_cache.has(c): return g.wall_cache[c]
	var h = FACADE_HEIGHT
	for k in range(1,CUT_HEIGHTS.size()+1):
		if g.cells.has(c-Vector2i(k,k)) or g.cells.has(c+Vector2i(1-k,-k)) or g.cells.has(c+Vector2i(-k,1-k)):
			h = CUT_HEIGHTS[k-1]
			break
	g.wall_cache[c] = h
	return h

# --- Placement ---------------------------------------------------------------

## Blocks a rectangle of ground for a prop. The open ground around it must stay
## one unbroken ring, so a blocker can never cut the floor in two.
static func _try_block(g, r: Rect2i, reserved: Dictionary) -> bool:
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			var c = Vector2i(x,y)
			if not g.cells.has(c) or g.blocked.has(c) or reserved.has(c): return false
	var ring: Array = []
	var o = r.grow(1)
	for x in range(o.position.x,o.end.x): ring.append(Vector2i(x,o.position.y))
	for y in range(o.position.y+1,o.end.y): ring.append(Vector2i(o.end.x-1,y))
	for x in range(o.end.x-2,o.position.x-1,-1): ring.append(Vector2i(x,o.end.y-1))
	for y in range(o.end.y-2,o.position.y,-1): ring.append(Vector2i(o.position.x,y))
	var open: Array = []
	for c in ring: open.append(g.cells.has(c) and not g.blocked.has(c))
	var runs = 0
	for i in open.size():
		if open[i] and not open[i-1]: runs += 1
	if runs>1 or not open.has(true): return false
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x): g.blocked[Vector2i(x,y)] = true
	return true

static func _put(g, kind: String, pos: Vector2, extra: Dictionary = {}) -> Dictionary:
	var prop = {"pos":pos,"kind":kind,"open":false,"seed":floori(g._random()*1000)}
	prop.merge(extra)
	g.props.append(prop)
	return prop

## Places a blocking prop with footprint r. Returns false if the spot is taken.
static func _put_block(g, kind: String, r: Rect2i, reserved: Dictionary, extra: Dictionary = {}) -> bool:
	if not _try_block(g,r,reserved): return false
	_put(g,kind,Vector2(r.position)+Vector2(r.size)/2.0,extra)
	return true

## Places a small prop that does not block, on open ground away from the exit.
static func _put_loose(g, kind: String, pos: Vector2, extra: Dictionary = {}) -> bool:
	if not g._walkable(pos) or pos.distance_to(g.stairs)<2.2: return false
	_put(g,kind,pos,extra)
	return true

static func _rand_cell(g, r: Rect2i, margin: int = 0) -> Vector2i:
	return Vector2i(r.position.x+margin+floori(g._random()*maxi(1,r.size.x-margin*2)),r.position.y+margin+floori(g._random()*maxi(1,r.size.y-margin*2)))

static func _jitter(g, c: Vector2i, amount: float = 0.25) -> Vector2:
	return Vector2(c)+Vector2(0.5+g._between(-amount,amount),0.5+g._between(-amount,amount))

## Open cells of a zone that touch a back wall (for things that stand against
## walls). Props draw in front of buildings, so nothing hugs a wall on the
## camera's side, where it would look stuck on top of the wall.
static func _wall_cells(g, r: Rect2i) -> Array:
	var out: Array = []
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			var c = Vector2i(x,y)
			if not g.cells.has(c) or not _clear_front(g,c): continue
			for d in [Vector2i.UP,Vector2i.LEFT]:
				if not g.cells.has(c+d):
					out.append([c,d])
					break
	return out

## A random open spot in a zone, away from walls, props and the stairway.
static func _spot(g, r: Dictionary, margin: float = 1.2, avoid: Vector2 = Vector2(-99,-99), keep_away: float = 0.0) -> Vector2:
	for attempt in 24:
		var point = r.pos+Vector2(g._between(-r.w/2.0+margin,r.w/2.0-margin),g._between(-r.h/2.0+margin,r.h/2.0-margin))
		if g._free(point,0.35) and point.distance_to(g.stairs)>1.6 and point.distance_to(avoid)>=keep_away: return point
	return r.pos

# --- Set dressing ------------------------------------------------------------

static func _dress(g, z: Dictionary, number: int, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	var indoor = z.type in INTERIORS
	match z.type:
		"street": _dress_street(g,z,number,reserved)
		"crossing": _dress_crossing(g,z,number,reserved)
		"arena": _dress_arena(g,z,reserved)
		"park", "parking", "camp", "collapsed": _dress_lot(g,z,number,reserved)
		_: _dress_interior(g,z,number,reserved)
	if z.role=="start": _put_loose(g,"barrel_fire",z.pos+Vector2(1.6,-1.4))
	# Litter: loose paper anywhere, bags only against walls, puddles and stains
	# only out on the asphalt, and never inside the shops.
	var walls = _wall_cells(g,r)
	_shuffle(g,walls)
	for k in r.size.x*r.size.y/110:
		_put_loose(g,"paper",_jitter(g,_rand_cell(g,r,1),0.4))
	for k in mini(walls.size(),r.size.x*r.size.y/120):
		var pair = walls[k]
		_put_loose(g,"trash",_against(pair[0],pair[1],0.25))
	if indoor: return
	for k in r.size.x*r.size.y/90:
		var c = _rand_cell(g,r,1)
		if g.cells.get(c,0)!=CORRIDOR and g.cells.get(c,0)!=LOT: continue
		var roll = g._random()
		if roll<0.45: g.decals.append({"kind":"puddle","pos":_jitter(g,c),"w":g._between(0.8,1.6),"h":g._between(0.6,1.0),"seed":c.x*7+c.y})
		elif roll<0.7: g.decals.append({"kind":"stain","pos":_jitter(g,c),"w":g._between(0.6,1.2),"h":g._between(0.5,0.9),"seed":c.x*3+c.y})
		elif number==2: g.decals.append({"kind":"scorch","pos":_jitter(g,c),"w":g._between(1.2,2.2),"h":g._between(1.0,1.8),"seed":c.x+c.y})

## The middle of cell c, pushed toward its neighbour in direction d.
static func _against(c: Vector2i, d: Vector2i, amount: float) -> Vector2:
	return Vector2(c)+Vector2(0.5,0.5)+Vector2(d)*amount

## Open cells along each back wall of a zone, as straight runs in order, so things
## that line a wall (machines, cabinets, booths) can be placed in neat rows.
static func _wall_runs(g, r: Rect2i) -> Array:
	var runs: Array = []
	for d in [Vector2i.UP,Vector2i.LEFT]:
		var cells: Array = []
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):
				var c = Vector2i(x,y)
				if g.cells.has(c) and not g.cells.has(c+d) and _clear_front(g,c): cells.append(c)
		var along_x = d.x==0
		cells.sort_custom(func(a,b): return [a.y,a.x]<[b.y,b.x] if along_x else [a.x,a.y]<[b.x,b.y])
		var run: Array = []
		for c in cells:
			if not run.is_empty():
				var last: Vector2i = run[run.size()-1]
				var next = last+(Vector2i.RIGHT if along_x else Vector2i.DOWN)
				if c!=next:
					runs.append({"dir":d,"cells":run})
					run = []
			run.append(c)
		if not run.is_empty(): runs.append({"dir":d,"cells":run})
	return runs

## No wall right in front of cell c on screen, so a prop there is never drawn over one.
static func _clear_front(g, c: Vector2i) -> bool:
	return g.cells.has(c+Vector2i.DOWN) and g.cells.has(c+Vector2i.RIGHT) and g.cells.has(c+Vector2i.ONE)

## Is cell c a sidewalk with a building wall right behind it (direction out)?
static func _shopfront(g, c: Vector2i, out: Vector2i) -> bool:
	return g.cells.get(c,0)==SIDEWALK and not g.cells.has(c+out)

static func _dress_street(g, z: Dictionary, number: int, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	var along_x = z.axis=="x"
	var length = r.size.x if along_x else r.size.y
	var width = r.size.y if along_x else r.size.x
	var start = r.position.x if along_x else r.position.y
	var side_a = r.position.y if along_x else r.position.x
	var side_b = side_a+width-1
	var cell_at = func(a: int, b: int) -> Vector2i: return Vector2i(a,b) if along_x else Vector2i(b,a)
	var cross = func(v: int) -> Vector2i: return Vector2i(0,v) if along_x else Vector2i(v,0)
	var mid = side_a+width/2.0
	# Center line and lane dashes.
	var a = Vector2(start,mid) if along_x else Vector2(mid,start)
	var b = Vector2(start+length,mid) if along_x else Vector2(mid,start+length)
	g.decals.append({"kind":"lane","a":a,"b":b,"pos":(a+b)/2,"w":a.distance_to(b),"h":1.0})
	var last = start+length-1
	for side in [[side_a,-1,0],[side_b,1,2]]:
		var row: int = side[0]
		var out: Vector2i = cross.call(side[1])
		var inward: Vector2i = -out
		var back = side[1]<0
		# Streetlights stand at the curb of building-lined sidewalks, evenly
		# spaced and clear of the corners. Only on the far side of the street:
		# on the near side they would stand in front of the building fronts.
		var at = start+2+side[2]
		while back and at<=last-2:
			var c: Vector2i = cell_at.call(at,row)
			var behind = c+out*2
			if _shopfront(g,c,out) and g.cells.get(behind,0)!=ROOM and _put_block(g,"streetlight",Rect2i(c,Vector2i.ONE),reserved,{"dir":Vector2(inward),"flicker":g._random()<0.2}):
				g.props[g.props.size()-1].pos = _against(c,inward,0.3)
			at += 5
		# Street furniture against the buildings, spaced out, never in a doorway.
		at = start+1
		while back and at<=last-1:
			var c: Vector2i = cell_at.call(at,row)
			var step = 1
			if _shopfront(g,c,out) and not reserved.has(c) and not g.blocked.has(c):
				var roll = g._random()
				var along: Vector2i = cell_at.call(1,0)-cell_at.call(0,0)
				if roll<0.09 and _put_block(g,"dumpster",Rect2i(c,Vector2i.ONE),reserved,{"face":out}):
					_put_loose(g,"trash",_against(c+along,out,0.25))
					if g._random()<0.5: _put_loose(g,"tires",_against(c-along,out,0.2))
					step = 4
				elif roll<0.13 and _put_block(g,"payphone",Rect2i(c,Vector2i.ONE),reserved,{"face":out}): step = 5
				elif roll<0.17 and (at-start<=3 or last-at<=3):
					_put_loose(g,"newsbox",_against(c,out,0.2))
					step = 4
				elif roll<0.2 and number==2 and _put_block(g,"barrel_fire",Rect2i(c,Vector2i.ONE),reserved): step = 4
			at += step
		# A hydrant at the curb near one end of the block.
		if g._random()<0.35:
			var at_end = start+1 if g._random()<0.5 else last-1
			var c: Vector2i = cell_at.call(at_end,row)
			if g.cells.get(c,0)==SIDEWALK: _put_loose(g,"hydrant",_against(c,inward,0.3))
		# Cars parked nose to tail in the curb lane, with gaps between them.
		var lane = row+inward.x+inward.y
		if g.cells.get(cell_at.call(start+length/2,row),0)==SIDEWALK:
			at = start+2+floori(g._random()*3)
			while at+1<=last-2:
				if g._random()<0.4:
					var c: Vector2i = cell_at.call(at,lane)
					var rect = Rect2i(c,Vector2i(2,1) if along_x else Vector2i(1,2))
					if _put_block(g,"car",rect,reserved,{"axis":z.axis,"burned":g._random()<(0.55 if number==2 else 0.2),"color":floori(g._random()*6),"flip":g._random()<0.5}):
						at += 3
						continue
				at += 2
	# Now and then a wreck slewed across the middle of the road.
	if g._random()<0.3 and length>=8:
		var c: Vector2i = cell_at.call(start+3+floori(g._random()*(length-6)),side_a+width/2-1)
		_put_block(g,"car",Rect2i(c,Vector2i(1,2) if along_x else Vector2i(2,1)),reserved,{"axis":"y" if along_x else "x","burned":true,"color":floori(g._random()*6),"flip":g._random()<0.5})
	# A checkpoint barricade near one end of the street, with a gap to pass.
	if g._random()<0.3 and length>=6:
		var at = start+2 if g._random()<0.5 else last-2
		var gap = side_a+2+floori(g._random()*maxi(1,width-4))
		var kind = "barrier" if g._random()<0.6 else "sandbags"
		for lane in range(side_a+1,side_b,2):
			if absi(lane-gap)<=1: continue
			_put_block(g,kind,Rect2i(cell_at.call(at,lane),Vector2i(1,2) if along_x else Vector2i(2,1)),reserved,{"axis":"y" if along_x else "x"})
		for k in 2: _put_loose(g,"cone",_jitter(g,cell_at.call(at+(1 if k==0 else -1),gap),0.15))
	# One manhole on the center line, and maybe a pothole in a lane.
	if g._random()<0.5:
		var at = start+2+floori(g._random()*maxi(1,length-4))+0.5
		g.decals.append({"kind":"manhole","pos":Vector2(at,mid) if along_x else Vector2(mid,at),"w":1.0,"h":1.0,"seed":start})
	if g._random()<0.5:
		var c: Vector2i = cell_at.call(start+1+floori(g._random()*maxi(1,length-2)),side_a+2)
		g.decals.append({"kind":"pothole","pos":Vector2(c)+Vector2(0.5,0.5),"w":1.0,"h":1.0,"seed":start+1})

static func _dress_crossing(g, z: Dictionary, number: int, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	# Zebra crossings on each side that leads somewhere.
	for side in [[Vector2i.UP,"x"],[Vector2i.DOWN,"x"],[Vector2i.LEFT,"y"],[Vector2i.RIGHT,"y"]]:
		var d: Vector2i = side[0]
		var probe = Vector2i(z.pos)+Vector2i(d.x*(r.size.x/2+1),d.y*(r.size.y/2+1))
		if g.cells.get(probe,0)!=CORRIDOR and g.cells.get(probe,0)!=SIDEWALK: continue
		var center = z.pos+Vector2(d.x*(r.size.x/2.0-0.7),d.y*(r.size.y/2.0-0.7))
		g.decals.append({"kind":"crosswalk","pos":center,"axis":side[1],"w":float(r.size.x-2) if side[1]=="x" else 1.1,"h":1.1 if side[1]=="x" else float(r.size.y-2)})
	# Signals on two opposite street corners, a hydrant on another.
	var corners = [[r.position,Vector2i(1,1)],[Vector2i(r.end.x-1,r.position.y),Vector2i(-1,1)],[Vector2i(r.position.x,r.end.y-1),Vector2i(1,-1)],[r.end-Vector2i.ONE,Vector2i(-1,-1)]]
	var first = floori(g._random()*2)
	for k in [first,3-first]:
		var c: Vector2i = corners[k][0]
		if g.cells.get(c,0)==SIDEWALK and _put_block(g,"traffic_light",Rect2i(c,Vector2i.ONE),reserved):
			g.props[g.props.size()-1].pos = Vector2(c)+Vector2(0.5,0.5)+Vector2(corners[k][1])*0.25
	var other: Array = corners[1-first]
	if g.cells.get(other[0],0)==SIDEWALK and g._random()<0.6: _put_loose(g,"hydrant",Vector2(other[0])+Vector2(0.5,0.5)+Vector2(other[1])*0.25)
	if g._random()<0.4: g.decals.append({"kind":"manhole","pos":z.pos+Vector2(0.6,0.4),"w":1.0,"h":1.0,"seed":1})
	if number==2 and g._random()<0.5 and z.role!="start": _put_loose(g,"barrel_fire",_jitter(g,Vector2i(z.pos)+Vector2i(1,1),0.2))

static func _dress_lot(g, z: Dictionary, number: int, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	var inner = r.grow(-1)
	var corners = [inner.position,Vector2i(inner.end.x-1,inner.position.y),Vector2i(inner.position.x,inner.end.y-1),inner.end-Vector2i.ONE]
	match z.type:
		"park":
			# A dry fountain in the middle, palms in a ring along the edge, benches
			# facing the fountain and a lamp in each corner.
			var center = Vector2i(z.pos)
			var fountain = z.role=="plain" and r.size.x>=9 and r.size.y>=9 and _put_block(g,"fountain",Rect2i(center-Vector2i.ONE,Vector2i(2,2)),{})
			if fountain: z.pos = Vector2(center)+Vector2(0.5,2.6)
			var ring: Array = []
			for x in range(inner.position.x,inner.end.x): ring.append(Vector2i(x,inner.position.y))
			for y in range(inner.position.y+1,inner.end.y): ring.append(Vector2i(inner.end.x-1,y))
			for x in range(inner.end.x-2,inner.position.x-1,-1): ring.append(Vector2i(x,inner.end.y-1))
			for y in range(inner.end.y-2,inner.position.y,-1): ring.append(Vector2i(inner.position.x,y))
			for i in range(2,ring.size(),3):
				if not (ring[i] in corners): _put_block(g,"palm",Rect2i(ring[i],Vector2i.ONE),reserved,{"lean":g._between(-0.3,0.3)})
			for c in corners: _put_block(g,"streetlight_low",Rect2i(c,Vector2i.ONE),reserved)
			var hub = Vector2(center)+Vector2(0.0,0.0) if fountain else z.pos
			for o in [Vector2(0,-2.6),Vector2(0,2.6),Vector2(-2.6,0),Vector2(2.6,0)]:
				_put_loose(g,"bench",hub+o,{"axis":"x" if o.x==0 else "y"})
		"parking":
			# Painted bays with wrecks parked in some of them, a lamp on the corners.
			for row in range(r.position.y+1,r.end.y-1,3):
				g.decals.append({"kind":"bays","pos":Vector2(r.position.x+r.size.x/2.0,row+1.0),"w":float(r.size.x-2),"h":2.0})
				for x in range(r.position.x+1,r.end.x-2,2):
					if g._random()<0.45:
						_put_block(g,"car",Rect2i(Vector2i(x,row),Vector2i(1,2)),reserved,{"axis":"y","burned":g._random()<(0.6 if number==2 else 0.3),"color":floori(g._random()*6),"flip":g._random()<0.5})
			for k in [0,3]:
				var c: Vector2i = corners[k]
				if _put_block(g,"streetlight",Rect2i(c,Vector2i.ONE),reserved,{"dir":Vector2(1,0) if k==0 else Vector2(-1,0),"flicker":k==3}): pass
			for k in 2: _put_loose(g,"cart",_jitter(g,_rand_cell(g,inner,1),0.3),{"angle":g._random()*TAU})
		"camp":
			# Survivors camped here: tents in a ring around the fire, bedding by the
			# tents, and their stash piled at the edge.
			var fire = z.pos+Vector2(0.5,0.5)
			_put_loose(g,"campfire",fire)
			for k in 4:
				var angle = TAU*k/4.0+g._between(-0.3,0.3)
				var c = Vector2i(fire+Vector2.from_angle(angle)*3.0)
				if _put_block(g,"tent",Rect2i(c-Vector2i(1,0),Vector2i(2,1)),reserved,{"color":floori(g._random()*4)}):
					_put_loose(g,"mattress",Vector2(c)+Vector2(0.5,0.5)+(fire-Vector2(c)).normalized()*0.9)
			_put_loose(g,"chest",fire+Vector2(1.6,1.2))
			var edge = _wall_cells(g,r)
			_shuffle(g,edge)
			var stash = 0
			for pair in edge:
				if stash>=3: break
				if stash==0 and _put_block(g,"tv_pile",Rect2i(pair[0],Vector2i.ONE),reserved): stash += 1
				elif _put_loose(g,"crate",_against(pair[0],pair[1],0.15)): stash += 1
			for k in [1,2]: _put_block(g,"barrel_fire",Rect2i(corners[k],Vector2i.ONE),reserved)
		"collapsed":
			# Rubble heaped along the old walls, wall stubs and scorch marks.
			var edge = _wall_cells(g,r)
			_shuffle(g,edge)
			var mounds = 0
			for pair in edge:
				if mounds>=3+floori(g._random()*2): break
				var size = Vector2i(1+floori(g._random()*2),1)
				if pair[1].x!=0: size = Vector2i(1,size.x)
				if _put_block(g,"mound",Rect2i(pair[0],size),reserved,{"size":size}): mounds += 1
			for k in 2:
				var c = _rand_cell(g,r,2)
				var axis = "x" if g._random()<0.5 else "y"
				_put_block(g,"ruin_wall",Rect2i(c,Vector2i(2,1) if axis=="x" else Vector2i(1,2)),reserved,{"axis":axis,"height":g._between(30,58)})
			for k in 2: g.decals.append({"kind":"scorch","pos":_jitter(g,_rand_cell(g,r,1),0.4),"w":g._between(1.5,2.6),"h":g._between(1.2,2.2),"seed":k})
			for k in 4:
				var pair = edge[(k*5)%maxi(1,edge.size())] if not edge.is_empty() else [Vector2i(z.pos),Vector2i.ZERO]
				_put_loose(g,"rubble",_against(pair[0],pair[1],0.2))
			_put_loose(g,"bones",_jitter(g,_rand_cell(g,r,2),0.3))
			_put_block(g,"barrel_fire",Rect2i(_rand_cell(g,r,2),Vector2i.ONE),reserved)
			if g._random()<0.6:
				for pair in edge:
					if _put_loose(g,"chest",_against(pair[0],pair[1],0.15)): break

static func _dress_interior(g, z: Dictionary, number: int, reserved: Dictionary) -> void:
	var r: Rect2i = z.rect
	var runs = _wall_runs(g,r)
	if runs.is_empty(): return
	match z.type:
		"arcade":
			# Cabinets shoulder to shoulder along the walls, a short break every few
			# machines, and a back-to-back island in the middle of bigger rooms.
			for run in runs:
				for i in run.cells.size():
					if i%5==4: continue
					_put_block(g,"arcade",Rect2i(run.cells[i],Vector2i.ONE),reserved,{"face":-run.dir,"color":floori(g._random()*5),"broken":g._random()<0.25})
			_island(g,r,"arcade",reserved,func(): return {"color":floori(g._random()*5),"broken":g._random()<0.25})
			_put_loose(g,"neon_floor",z.pos)
		"diner":
			# A counter with stools along the back, booths in pairs down the walls
			# and the jukebox in a corner.
			var row = r.position.y+1
			var counter = Rect2i(r.position.x+2,row,mini(5,r.size.x-4),1)
			if _put_block(g,"counter",counter,reserved,{"axis":"x","length":counter.size.x}):
				for x in range(counter.position.x,counter.end.x): _put_loose(g,"stool",Vector2(x+0.5,row+1.6))
			for run in runs:
				if run.dir!=Vector2i.LEFT: continue
				for i in range(2,run.cells.size()-1):
					if i%3!=0: _put_block(g,"booth",Rect2i(run.cells[i],Vector2i.ONE),reserved,{"face":-run.dir})
			# A row of booths across the front of the room, facing the counter.
			for x in range(r.position.x+2,r.end.x-2,2):
				_put_block(g,"booth",Rect2i(x,r.end.y-3,1,1),reserved,{"face":Vector2i.UP})
			for run in runs:
				if _put_block(g,"jukebox",Rect2i(run.cells[run.cells.size()-1],Vector2i.ONE),reserved,{"face":-run.dir}): break
		"video":
			# Shelves of tapes in rows with aisles between them, more tapes along the walls.
			for x in range(r.position.x+2,r.end.x-2,3):
				_put_block(g,"shelf",Rect2i(x,r.position.y+2,1,mini(3,r.size.y-4)),reserved,{"axis":"y","length":mini(3,r.size.y-4)})
			for k in 3:
				var run = runs[floori(g._random()*runs.size())]
				_put_loose(g,"tapes",_against(run.cells[floori(g._random()*run.cells.size())],run.dir,0.2))
		"laundromat":
			# Washers in rows along the walls and back to back down the middle.
			for run in runs:
				for i in run.cells.size():
					if i%6==5: continue
					_put_block(g,"washer",Rect2i(run.cells[i],Vector2i.ONE),reserved,{"face":-run.dir})
			_island(g,r,"washer",reserved,func(): return {})
		"warehouse":
			# Columns on a grid, crates stacked in pallets against the walls.
			for y in range(r.position.y+2,r.end.y-2,4):
				for x in range(r.position.x+2,r.end.x-2,4):
					_put_block(g,"column",Rect2i(x,y,1,1),reserved)
			_shuffle(g,runs)
			for run in runs.slice(0,3):
				for i in range(1,mini(4,run.cells.size())):
					_put_loose(g,"crate",_against(run.cells[i],run.dir,0.15))
				if run.cells.size()>6: _put_block(g,"drums",Rect2i(run.cells[run.cells.size()-2],Vector2i.ONE),reserved)
	# The footlocker sits tucked into a corner; rubble lies along the walls.
	var placed = false
	for run in runs:
		for c in [run.cells[0],run.cells[run.cells.size()-1]]:
			if placed or reserved.has(c) or g.blocked.has(c): continue
			placed = _put_loose(g,"chest",_against(c,run.dir,0.15))
	for k in 2:
		var run = runs[floori(g._random()*runs.size())]
		_put_loose(g,"rubble",_against(run.cells[floori(g._random()*run.cells.size())],run.dir,0.2))

## A back-to-back double row of machines down the middle of a big room.
static func _island(g, r: Rect2i, kind: String, reserved: Dictionary, extra: Callable) -> void:
	if r.size.x<9 or r.size.y<8: return
	var y = r.position.y+r.size.y/2-1
	for x in range(r.position.x+3,r.end.x-3):
		for k in 2:
			var data: Dictionary = extra.call()
			data["face"] = Vector2i.UP if k==0 else Vector2i.DOWN
			_put_block(g,kind,Rect2i(x,y+k,1,1),reserved,data)

## The Warden's plaza: a giant sunset mosaic ringed by palms and fires.
static func _dress_arena(g, z: Dictionary, reserved: Dictionary) -> void:
	g.decals.append({"kind":"sunset","pos":z.pos,"w":11.0,"h":11.0})
	var count = 10
	for k in count:
		var angle = TAU*k/count+0.3
		var radius = minf(z.w,z.h)/2.0-2.2
		var c = Vector2i(z.pos+Vector2.from_angle(angle)*radius)
		if k%2==0: _put_block(g,"palm",Rect2i(c,Vector2i.ONE),reserved,{"lean":g._between(-0.3,0.3),"neon":true})
		else: _put_block(g,"barrel_fire",Rect2i(c,Vector2i.ONE),reserved)
	for k in 6: _put_loose(g,"rubble",_jitter(g,_rand_cell(g,z.rect,1),0.4))
	for k in 4: _put_loose(g,"bones",_jitter(g,_rand_cell(g,z.rect,2),0.4))

## Neon signs and blade signs on full-height building fronts.
static func _add_signs(g, number: int) -> void:
	var theme = Data.FLOOR_THEMES[number-1]
	var words: Array = theme.signs
	var used = {}
	var tall = func(c: Vector2i, face: Vector2i) -> bool:
		return not g.cells.has(c) and g.cells.has(c+face) and not g.blocked.has(c+face) and solid_height(g,c)>=FACADE_HEIGHT
	for pass_index in 2:
		var face = Vector2i.DOWN if pass_index==0 else Vector2i.RIGHT
		var along = Vector2i.RIGHT if pass_index==0 else Vector2i.DOWN
		for line in SIZE:
			var run: Array = []
			for step in SIZE+1:
				var c = Vector2i(step,line) if pass_index==0 else Vector2i(line,step)
				if step<SIZE and tall.call(c,face): run.append(c)
				else:
					_signs_in_run(g,run,face,along,words,used)
					run = []

static func _signs_in_run(g, run: Array, face: Vector2i, along: Vector2i, words: Array, used: Dictionary) -> void:
	var at = 1+floori(g._random()*3)
	while at<run.size():
		var roll = g._random()
		var text: String = words[floori(g._random()*words.size())]
		var length = clampi(ceili(text.length()*0.42),2,4)
		if roll<0.3 and at+length<=run.size():
			var cells = run.slice(at,at+length)
			var first: Vector2i = cells[0]
			var last: Vector2i = cells[cells.size()-1]
			var a: Vector2; var b: Vector2
			if face==Vector2i.DOWN:
				a = Vector2(first.x,first.y+1); b = Vector2(last.x+1,last.y+1)
			else:
				a = Vector2(last.x+1,last.y+1); b = Vector2(first.x+1,first.y)
			g.signs.append({"kind":"panel","text":text,"a":a,"b":b,"cells":cells,"color":floori(g._random()*5),
				"v":g._between(80,96),"flicker":g._random()<0.3,"dead":floori(g._random()*text.length()) if g._random()<0.35 else -1,"seed":g._random()*100})
			at += length+2+floori(g._random()*4)
		elif roll<0.6:
			var c: Vector2i = run[at]
			var blade: String = ["HOTEL","BAR","EAT","OPEN","CLUB","TAPES","PAWN","GAS"][floori(g._random()*8)]
			var a = Vector2(c.x,c.y+1) if face==Vector2i.DOWN else Vector2(c.x+1,c.y+1)
			var b = Vector2(c.x+1,c.y+1) if face==Vector2i.DOWN else Vector2(c.x+1,c.y)
			g.signs.append({"kind":"blade","text":blade,"a":a,"b":b,"cells":[c],"color":floori(g._random()*5),"face":Vector2(face),
				"v":g._between(70,78),"flicker":g._random()<0.3,"dead":-1,"seed":g._random()*100})
			at += 3+floori(g._random()*3)
		else:
			at += 2+floori(g._random()*3)

static func _spawn_enemies(g, number: int, street: bool = true) -> void:
	var start: Vector2 = g.rooms[0].pos
	var candidates: Array = []
	for i in range(1,g.rooms.size()):
		var z = g.rooms[i]
		if z.role=="arena" or z.role=="safe": continue
		if z.pos.distance_to(start)<12: continue
		candidates.append(z)
	_shuffle(g,candidates)
	var budget = 24+number*4
	for z in candidates:
		if budget<=0: break
		var count = 2+floori(g._random()*2)
		if z.type in INTERIORS or z.type in PLAZAS or z.type=="collapsed": count += 1
		if z.role=="stairs": count += 1
		var rank = Elites.roll_pack(g,number)
		# Elite packs bring an extra body or two.
		if rank=="rare": count += 2
		elif rank=="champion": count = maxi(count,3)
		count = mini(count,maxi(budget,3 if rank!="" else 0))
		budget -= count
		var pack: Array = []
		for j in count:
			var kind = "ranged" if g._random()<0.3 else "brute" if g._random()<0.4 else "imp"
			var enemy = g._spawn_enemy(kind,_spot(g,z,1.0,start,11.5))
			enemy.attack = g._between(0.2,1.5)
			enemy.phase = g._random()*6
			pack.append(enemy)
		if rank!="": Elites.promote_pack(g,pack,rank,number)
	if number==3 and street:
		var arena = g.rooms[g.rooms.size()-1]
		g.enemies = g.enemies.filter(func(e): return e.pos.distance_to(g.stairs)>9)
		for j in 3:
			var enemy = g._spawn_enemy("imp" if j<2 else "ranged",_spot(g,arena,2.0))
			enemy.attack = 1.0
		var boss = g._spawn_enemy("boss",g.stairs+Vector2(0,-1))
		boss.attack = 2.0

## Enemies route through this grid when they cannot see the hero directly.
static func build_navigation(g) -> void:
	var grid = AStarGrid2D.new()
	grid.region = Rect2i(0,0,SIZE,SIZE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in SIZE:
		for x in SIZE:
			var cell = Vector2i(x,y)
			if not g.cells.has(cell) or g.blocked.has(cell): grid.set_point_solid(cell)
	g.nav = grid

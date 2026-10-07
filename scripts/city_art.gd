extends RefCounted
## Art for the ruined 1980s city: street, sidewalk, lot and shop-floor ground,
## building fronts with storefronts, windows, fire escapes and graffiti, neon
## signs, ground markings, light pools, every street prop, and the subway
## entrance that leads to the next floor.

const Data = preload("res://scripts/data.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const CAR_COLORS = [Color("3a8a8a"), Color("7a2a3a"), Color("c8b89a"), Color("c06a90"), Color("2a3a6a"), Color("b08a2a")]
const TARP_COLORS = [Color("2f5f9a"), Color("c8642a"), Color("5a6a3a"), Color("8a2a3a")]
const SCREEN_COLORS = [Color("ff4fd8"), Color("3ff0ff"), Color("ffe45c"), Color("5dff8f"), Color("9b5cff")]

var g
var p
var c: CanvasItem
var neon_font = SystemFont.new()
var shake = Vector2.ZERO

func _init(game, painter) -> void:
	g = game
	p = painter
	c = game
	neon_font.font_names = PackedStringArray(["Bahnschrift", "Arial Rounded MT Bold", "DejaVu Sans", "Arial"])
	neon_font.font_weight = 700

func theme() -> Dictionary:
	return Data.FLOOR_THEMES[clampi(g.floor_number-1,0,Data.FLOOR_THEMES.size()-1)]

# --- Small helpers -------------------------------------------------------------

func _h(a: int, b: int, k: int = 0) -> int:
	return absi((a*73856093) ^ (b*19349663) ^ (k*83492791))%1000

## Screen point of a world position at height z.
func _pt(x: float, y: float, z: float = 0.0) -> Vector2:
	return g._project(Vector2(x,y),z)

## Screen point inside a ground cell centered at s, from cell-local u,v in 0..1.
func _cp(s: Vector2, u: float, v: float) -> Vector2:
	return s+Vector2((u-v)*32.0,(u+v-1.0)*16.0)

## A point on a wall face running from a to b on the ground, at height v.
func _fp(a: Vector2, b: Vector2, u: float, v: float) -> Vector2:
	return a.lerp(b,u)-Vector2(0,v)

func _fq(a: Vector2, b: Vector2, u0: float, u1: float, v0: float, v1: float) -> Array:
	return [_fp(a,b,u0,v0),_fp(a,b,u1,v0),_fp(a,b,u1,v1),_fp(a,b,u0,v1)]

func _diamond(s: Vector2, scale: float = 1.0) -> Array:
	return [s+Vector2(0,-16)*scale,s+Vector2(32,0)*scale,s+Vector2(0,16)*scale,s+Vector2(-32,0)*scale]

## A soft contact shadow the shape of the prop's footprint, nudged away from the light.
func _shadow(pos: Vector2, rx: float, ry: float, alpha: float = 0.45) -> void:
	var o = pos+Vector2(0.05,0.05)
	for k in 2:
		var gx = rx*0.75+(0.1 if k==0 else 0.0)
		var gy = ry*0.75+(0.1 if k==0 else 0.0)
		p.poly([_pt(o.x-gx,o.y-gy),_pt(o.x+gx,o.y-gy),_pt(o.x+gx,o.y+gy),_pt(o.x-gx,o.y+gy)],Color(0,0,0,alpha*(0.25 if k==0 else 0.45)))

## An irregular flat patch on the ground (puddles, stains, soot), never a perfect oval.
func _blob(pos: Vector2, w: float, h: float, seed_value: int, color: Color) -> void:
	var points: Array = []
	for i in 11:
		var a = TAU*i/11.0
		var k = 0.62+((absi(seed_value)*(i+3)*37+i*53)%38)/100.0
		points.append(g._project(pos+Vector2(cos(a)*w*0.5*k,sin(a)*h*0.5*k)))
	p.poly(points,color)

## A flat ellipse on the ground, in world units, as a light pool.
func _pool(pos: Vector2, radius: float, color: Color) -> void:
	var s = g._project(pos)
	c.draw_texture_rect(p.glow_texture,Rect2(s-Vector2(radius,radius*0.5),Vector2(radius*2,radius)),false,p.ink(color))

## An axis-aligned box in world space: top and the two faces the camera sees.
func _box(cx: float, cy: float, hx: float, hy: float, z0: float, z1: float, top: Color, front: Color, side: Color) -> void:
	var x0 = cx-hx; var x1 = cx+hx; var y0 = cy-hy; var y1 = cy+hy
	p.poly([_pt(x0,y1,z0),_pt(x1,y1,z0),_pt(x1,y1,z1),_pt(x0,y1,z1)],front)
	p.poly([_pt(x1,y0,z0),_pt(x1,y1,z0),_pt(x1,y1,z1),_pt(x1,y0,z1)],side)
	p.poly([_pt(x0,y0,z1),_pt(x1,y0,z1),_pt(x1,y1,z1),_pt(x0,y1,z1)],top)

## Front (+y) and side (+x) faces of a box as point lists, for details drawn on them.
func _front_face(cx: float, cy: float, hx: float, hy: float, z0: float, z1: float) -> Array:
	return [_pt(cx-hx,cy+hy,z0),_pt(cx+hx,cy+hy,z0),_pt(cx+hx,cy+hy,z1),_pt(cx-hx,cy+hy,z1)]

func _side_face(cx: float, cy: float, hx: float, hy: float, z0: float, z1: float) -> Array:
	return [_pt(cx+hx,cy-hy,z0),_pt(cx+hx,cy+hy,z0),_pt(cx+hx,cy+hy,z1),_pt(cx+hx,cy-hy,z1)]

## A point inside a quad given as [bottom-left, bottom-right, top-right, top-left].
func _in(q: Array, u: float, v: float) -> Vector2:
	return q[0].lerp(q[1],u).lerp(q[3].lerp(q[2],u),v)

func _sub(q: Array, u0: float, u1: float, v0: float, v1: float) -> Array:
	return [_in(q,u0,v0),_in(q,u1,v0),_in(q,u1,v1),_in(q,u0,v1)]

## An upright cylinder: world radius r, from height z0 to z1.
func _cyl(pos: Vector2, r: float, z0: float, z1: float, body: Color, top: Color) -> void:
	var s = g._project(pos)
	var rx = r*45.0; var ry = r*22.5
	var points: Array = []
	for i in 13:
		var a = PI-PI*i/12.0
		points.append(s+Vector2(cos(a)*rx,sin(a)*ry-z0))
	for i in 13:
		var a = PI*i/12.0
		points.append(s+Vector2(cos(a)*rx,sin(a)*ry-z1))
	p.poly(points,body)
	p.ellipse(s-Vector2(0,z1),rx,ry,top,20)

func _flame(base: Vector2, size: float, seed_value: float) -> void:
	var flicker = sin(g.clock*9+seed_value)*2*size
	var x = base.x; var y = base.y
	p.poly([[x-6*size,y],[x-4*size,y-10*size],[x+flicker,y-23*size],[x+6*size,y-6*size],[x+4*size,y+2]],Color("f6a34f"))
	p.poly([[x-2.5*size,y-1],[x+flicker*0.5,y-14*size],[x+3*size,y-1]],Color("ffefb3"))

func _flicker(seed_value: float, rate: float = 1.0) -> float:
	var t = g.clock*rate
	var n = sin(t*13.0+seed_value)*sin(t*7.3+seed_value*2.0)+sin(t*2.1+seed_value*0.7)*0.4
	return 0.15 if n<-0.75 else 1.0

func _neon_text(text: String, at: Vector2, size: int, color: Color, on: float, dead: int = -1) -> void:
	var x = at.x
	for i in text.length():
		var ch = text[i]
		var lit = on if i!=dead else 0.12
		var core = color.lightened(0.55)
		if lit>0.5:
			c.draw_string_outline(neon_font,Vector2(x,at.y),ch,HORIZONTAL_ALIGNMENT_LEFT,-1,size,7,p.ink(Color(color,0.16)))
			c.draw_string_outline(neon_font,Vector2(x,at.y),ch,HORIZONTAL_ALIGNMENT_LEFT,-1,size,3,p.ink(Color(color,0.55)))
			c.draw_string(neon_font,Vector2(x,at.y),ch,HORIZONTAL_ALIGNMENT_LEFT,-1,size,p.ink(core))
		else:
			c.draw_string(neon_font,Vector2(x,at.y),ch,HORIZONTAL_ALIGNMENT_LEFT,-1,size,p.ink(Color(color.darkened(0.55),0.8)))
		x += neon_font.get_string_size(ch,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x

func _text_width(text: String, size: int) -> float:
	return neon_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x

## Text painted flat onto a wall face (a run from a to b), with its baseline at height v.
func _face_text(a: Vector2, b: Vector2, u: float, v: float, text: String, size: int, color: Color) -> void:
	var slope = (b.y-a.y)/(b.x-a.x)
	var origin = _fp(a,b,u,v)
	c.draw_set_transform_matrix(Transform2D(Vector2(1,slope),Vector2(0,1),origin+shake))
	c.draw_string(neon_font,Vector2.ZERO,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,p.ink(color))
	c.draw_set_transform(shake)

# --- Ground --------------------------------------------------------------------

func ground(cell: Vector2i, s: Vector2) -> void:
	var t = theme()
	var kind = g.cells[cell]
	var style: String = g.cell_style.get(cell,"")
	var hv = _h(cell.x,cell.y)
	var d = _diamond(s)
	if kind==DungeonGenerator.CORRIDOR or style=="parking":
		_asphalt(s,d,hv,t,style=="parking")
	elif kind==DungeonGenerator.SIDEWALK:
		_sidewalk(cell,s,d,hv,t)
	elif kind==DungeonGenerator.LOT:
		match style:
			"grass":
				p.poly(d,t.grass.lightened(0.04*(hv%3)))
				for k in 4:
					var q = _cp(s,0.15+((hv*(k+3))%70)/100.0,0.15+((hv*(k+7))%70)/100.0)
					p.line(q,q+Vector2(-2,-5),t.grass.lightened(0.25),1)
					p.line(q,q+Vector2(2,-4),t.grass.lightened(0.15),1)
				if hv%4==0: _blob(Vector2(cell)+Vector2(0.45,0.55),0.5,0.35,hv,Color(t.dirt,0.6))
			"dirt", "rubble":
				var base: Color = t.dirt if style=="dirt" else t.rubble
				p.poly(d,base.lightened(0.03*(hv%3)))
				for k in 3:
					var q = _cp(s,0.2+((hv*(k+2))%60)/100.0,0.2+((hv*(k+5))%60)/100.0)
					if style=="rubble": p.poly([q,q+Vector2(5,-2),q+Vector2(7,2),q+Vector2(1,3)],base.lightened(0.18))
					else: p.circle(q,1.4,base.lightened(0.2))
			"pavers":
				p.poly(d,t.pavers)
				for i in 2:
					for j in 2:
						if (i+j)%2==0: p.poly([_cp(s,i/2.0,j/2.0),_cp(s,(i+1)/2.0,j/2.0),_cp(s,(i+1)/2.0,(j+1)/2.0),_cp(s,i/2.0,(j+1)/2.0)],t.pavers.lightened(0.07))
				p.poly(d,Color(0,0,0,0),Color(t.pavers.darkened(0.35),0.8))
			_:
				p.poly(d,t.lot,Color(t.lot.darkened(0.3),0.6))
	else:
		_shop_floor(cell,s,d,hv,style)
	# Scorch and soot on the burned district.
	if t.soot>0 and hv%5==0 and kind!=DungeonGenerator.ROOM: _blob(Vector2(cell)+Vector2(0.5,0.5),0.9,0.7,hv,Color(0,0,0,t.soot*0.4))

func _asphalt(s: Vector2, d: Array, hv: int, t: Dictionary, lot: bool) -> void:
	var base: Color = t.asphalt[hv%3]
	if lot: base = t.lot.darkened(0.15).lerp(base,0.5)
	p.poly(d,base)
	p.circle(_cp(s,0.3+(hv%40)/100.0,0.6),1,Color(1,1,1,0.06))
	p.circle(_cp(s,0.7,0.2+(hv%50)/100.0),1,Color(0,0,0,0.2))
	if hv%7==0:
		var a = _cp(s,0.1,0.3+(hv%30)/100.0)
		var m = _cp(s,0.45,0.5)
		var b = _cp(s,0.85,0.4+(hv%40)/100.0)
		p.line(a,m,Color(t.asphalt_seam,0.9),1.2)
		p.line(m,b,Color(t.asphalt_seam,0.9),1.0)
		p.line(m,_cp(s,0.5,0.9),Color(t.asphalt_seam,0.7),1.0)
		if t.weather!="ash" and hv%2==0:
			p.line(m,m+Vector2(-3,-6),Color("4f7a44"),1.2)
			p.line(m,m+Vector2(2,-5),Color("6a9a50"),1.2)
	elif hv%11==3:
		p.poly(_diamond(s,0.6),base.darkened(0.12))
	elif hv%9==4 and t.weather=="rain":
		p.line(_cp(s,0.2,0.4),_cp(s,0.6,0.5),Color(t.glow,0.08),2)

func _sidewalk(cell: Vector2i, s: Vector2, d: Array, hv: int, t: Dictionary) -> void:
	var base: Color = t.sidewalk[hv%2]
	p.poly(d,base,t.sidewalk_seam)
	p.line(d[3]+Vector2(3,0),d[0]+Vector2(0,2),Color(1,1,1,0.07),1)
	if hv%6==0: p.line(_cp(s,0.2,0.3),_cp(s,0.6,0.7),Color(t.sidewalk_seam,0.9),1)
	var curb: Color = t.curb
	for side in [[Vector2i.UP,0,1],[Vector2i.RIGHT,1,2],[Vector2i.DOWN,2,3],[Vector2i.LEFT,3,0]]:
		var n = g.cells.get(cell+side[0],0)
		if n!=DungeonGenerator.CORRIDOR: continue
		var a: Vector2 = d[side[1]]; var b: Vector2 = d[side[2]]
		if side[0]==Vector2i.DOWN or side[0]==Vector2i.RIGHT:
			p.poly([a,b,b+Vector2(0,5),a+Vector2(0,5)],curb.darkened(0.45))
		p.line(a,b,curb,2.5)

func _shop_floor(cell: Vector2i, s: Vector2, d: Array, hv: int, style: String) -> void:
	match style:
		"carpet":
			# The classic dark arcade carpet with neon squiggles.
			p.poly(d,Color("1c1430"))
			var k = hv%4
			var q = _cp(s,0.25+(hv%50)/100.0,0.25+((hv/7)%50)/100.0)
			var color: Color = SCREEN_COLORS[(hv/3)%5]
			match k:
				0: p.poly([q,q+Vector2(6,-5),q+Vector2(9,2)],Color(color,0.55))
				1:
					p.line(q,q+Vector2(4,-4),Color(color,0.6),1.5)
					p.line(q+Vector2(4,-4),q+Vector2(8,0),Color(color,0.6),1.5)
					p.line(q+Vector2(8,0),q+Vector2(12,-4),Color(color,0.6),1.5)
				2: p.poly([q+Vector2(0,-3),q+Vector2(4,0),q+Vector2(0,3),q+Vector2(-4,0)],Color(color,0.55))
				3: p.ellipse_arc(q,6,3,0,PI,Color(color,0.55),1.5)
			var q2 = _cp(s,0.7-(hv%30)/100.0,0.65)
			p.line(q2,q2+Vector2(5,-2),Color(SCREEN_COLORS[(hv/11)%5],0.5),1.5)
		"checker":
			for i in 2:
				for j in 2:
					var col = Color("cfc6b4") if (i+j)%2==0 else Color("1d1a22")
					p.poly([_cp(s,i/2.0,j/2.0),_cp(s,(i+1)/2.0,j/2.0),_cp(s,(i+1)/2.0,(j+1)/2.0),_cp(s,i/2.0,(j+1)/2.0)],col)
			p.poly(d,Color(0.15,0.1,0.08,0.18+(hv%4)*0.06))
		"tile":
			p.poly(d,Color("3d6b6e"),Color("24403f"))
			for i in 2:
				for j in 2:
					if (i+j+hv)%3==0: p.poly([_cp(s,i/2.0,j/2.0),_cp(s,(i+1)/2.0,j/2.0),_cp(s,(i+1)/2.0,(j+1)/2.0),_cp(s,i/2.0,(j+1)/2.0)],Color("c87a9a"),Color("24403f"))
			p.line(_cp(s,0.5,0),_cp(s,0.5,1),Color("24403f"),1)
			p.line(_cp(s,0,0.5),_cp(s,1,0.5),Color("24403f"),1)
		"threshold":
			p.poly(d,Color("3c3a42"))
			p.line(_cp(s,0,0.5),_cp(s,1,0.5),Color("8a8a96"),2)
		_:
			p.poly(d,Color("4a4a52").lightened(0.03*(hv%3)),Color("38383f"))
			if hv%5==0: p.line(_cp(s,0.2,0.5),_cp(s,0.7,0.3),Color(0,0,0,0.3),1)
	if hv%9==0: p.line(_cp(s,0.1,0.6),_cp(s,0.5,0.4),Color(0,0,0,0.25),1)

# --- Buildings -------------------------------------------------------------------

## A solid cell beside open ground: its block, the two faces the camera sees, and
## its roof. Full-height fronts get storefronts, windows and fire escapes.
func building(cell: Vector2i, s: Vector2) -> void:
	var t = theme()
	var h = DungeonGenerator.solid_height(g,cell)
	var style = _h(cell.x/5,cell.y/5,g.floor_number)%t.buildings.size()
	var pal: Array = t.buildings[style]
	var tall = h>=DungeonGenerator.FACADE_HEIGHT
	for side in 2:
		var front = cell+(Vector2i.DOWN if side==0 else Vector2i.RIGHT)
		_facade(cell,s,h,side,pal,style,g.cells.has(front),t)
	# Roof or wall top.
	var roof = Vector2(0,h)
	p.poly([s-roof+Vector2(0,-16),s-roof+Vector2(32,0),s-roof+Vector2(0,16),s-roof+Vector2(-32,0)],pal[2] if tall else pal[0].darkened(0.25))
	p.line(s-roof+Vector2(-32,0),s-roof+Vector2(0,16),pal[3].darkened(0.3) if tall else pal[0].lightened(0.15),1.5)
	p.line(s-roof+Vector2(0,16),s-roof+Vector2(32,0),pal[3].darkened(0.45) if tall else pal[0].lightened(0.05),1.5)
	var hv = _h(cell.x,cell.y,7)
	if tall:
		if hv%13==0: _box_screen(s-roof+Vector2(-4,4),9,12,Color("7a7e88"),Color("5a5e68"),Color("9a9ea8"))
		elif hv%19==3:
			p.line(s-roof,s-roof-Vector2(0,30),Color("7a7e88"),1.5)
			p.line(s-roof-Vector2(6,22),s-roof-Vector2(-6,22),Color("7a7e88"),1)
			p.circle(s-roof-Vector2(0,30),1.6,Color(1,0.25,0.3,0.5+0.5*sin(g.clock*3+hv)))
		elif hv%29==5:
			# A rooftop water tank.
			var top = s-roof
			for k in [-10,0,10]: p.line(top+Vector2(k,4),top+Vector2(k*0.8,-10),Color("3a3236"),2)
			p.poly([top+Vector2(-13,-10),top+Vector2(13,-10),top+Vector2(12,-40),top+Vector2(-12,-40)],Color("6a4a36"))
			p.ellipse(top-Vector2(0,40),12,5,Color("8a6448"),14)
			p.poly([top+Vector2(-12,-40),top+Vector2(0,-56),top+Vector2(12,-40)],Color("4a3a30"))
	else:
		for k in 2:
			var q = s-roof+Vector2(-14+((hv*(k+1))%28),-4+((hv*(k+3))%8))
			p.poly([q,q+Vector2(6,-3),q+Vector2(9,1),q+Vector2(2,3)],pal[0].lightened(0.1))

## A small box drawn in screen space (for rooftop clutter).
func _box_screen(point: Vector2, w: float, h: float, front: Color, side: Color, top: Color) -> void:
	p.block(point,w,h,front,side,top)

func _facade(cell: Vector2i, s: Vector2, h: float, side: int, pal: Array, style: int, open_front: bool, t: Dictionary) -> void:
	var a = s+Vector2(-32,0) if side==0 else s+Vector2(0,16)
	var b = s+Vector2(0,16) if side==0 else s+Vector2(32,0)
	var base: Color = pal[0] if side==0 else pal[1]
	var hv = _h(cell.x,cell.y,side)
	var tall = h>=DungeonGenerator.FACADE_HEIGHT
	if t.soot>0: base = base.darkened(t.soot*0.25*((hv%3)/2.0))
	p.poly(_fq(a,b,0,1,0,h),base)
	var trim: Color = pal[3]
	var n = Vector2(-11,5.5) if side==0 else Vector2(11,5.5)
	if not open_front:
		return
	# Grime along the foot of the wall.
	p.poly(_fq(a,b,0,1,0,6),Color(0,0,0,0.28))
	if not tall:
		_low_wall_details(a,b,h,hv,base,t)
		return
	# Storeys at true scale: a 72 px shop floor (doors stand well above the
	# hero), one upper storey, and a parapet.
	match style:
		0:
			for v in range(8,int(h)-8,7): p.line(_fp(a,b,0,v),_fp(a,b,1,v),Color(base.darkened(0.3),0.45),1)
		4:
			for u in [0.33,0.66]: p.line(_fp(a,b,u,72),_fp(a,b,u,h),Color(trim,0.25),1)
		5:
			for k in 8: p.line(_fp(a,b,k/8.0+0.06,72),_fp(a,b,k/8.0+0.06,h),Color(base.darkened(0.25),0.8),1)
		_:
			if hv%3==0: p.poly(_fq(a,b,0.3,0.5,90+(hv%20),98+(hv%20)),Color(base.lightened(0.15),0.6))
	p.poly(_fq(a,b,0,1,70,76),trim.darkened(0.25))
	p.line(_fp(a,b,0,76),_fp(a,b,1,76),Color(trim,0.6),1)
	p.poly(_fq(a,b,0,1,h-8,h),trim.darkened(0.35))
	p.line(_fp(a,b,0,h-8),_fp(a,b,1,h-8),Color(trim,0.4),1)
	_storefront(a,b,hv,style,n,t,trim)
	# Upper-storey windows.
	if style==4:
		var q = _fq(a,b,0.04,0.96,86,128)
		p.poly(q,Color("0e1a2c"))
		p.poly(_sub(q,0.1,0.35,0,1),Color(t.neon[1],0.12))
		p.line(_in(q,0.5,0),_in(q,0.5,1),Color(trim,0.4),1)
		p.line(_in(q,0,0.5),_in(q,1,0.5),Color(trim,0.3),1)
		if hv%5==0: p.poly(_sub(q,0.55,0.95,0.1,0.45),Color(1,0.85,0.5,0.55*_flicker(hv,0.3)))
	else:
		for wi in 2:
			var u0 = 0.16 if wi==0 else 0.58
			_window(_fq(a,b,u0,u0+0.26,86,124),_h(cell.x*3+wi,cell.y*5,side),trim)
		if style==0 and hv%4==0: _fire_escape(a,b,n)
		elif hv%5==1:
			var q = _fq(a,b,0.2,0.38,78,88)
			p.poly(q,Color("8a8e96"))
			p.poly([q[3],q[2],q[2]+n*0.5,q[3]+n*0.5],Color("a6aab2"))
			p.poly([q[1],q[2],q[2]+n*0.5,q[1]+n*0.5],Color("6a6e76"))
	if t.weather!="ash" and hv%13==3:
		var u = 0.75
		var last = _fp(a,b,u,h)
		for k in range(1,12):
			var next = _fp(a,b,u+sin(k*1.7+hv)*0.05,h-k*9)
			p.line(last,next,Color("3f6a3a"),2)
			p.poly([next,next+Vector2(-3,-2),next+Vector2(-1,2)],Color("4f7f44"))
			last = next

func _storefront(a: Vector2, b: Vector2, hv: int, style: int, n: Vector2, t: Dictionary, trim: Color) -> void:
	var kind = hv%10
	if style==4: kind = 0
	if kind<=2:
		var q = _fq(a,b,0.1,0.9,8,60)
		var lit = hv%3==0
		p.poly(q,Color("0b1020"))
		if lit: p.poly(q,Color(t.neon[hv%t.neon.size()],0.22*_flicker(hv*0.3,0.4)))
		p.line(_in(q,0.2,0.1),_in(q,0.45,0.9),Color(1,1,1,0.13),2)
		p.line(_in(q,0.5,0),_in(q,0.5,1),Color(trim,0.6),1.5)
		p.poly(q,Color(0,0,0,0),trim.darkened(0.2))
		if hv%4==1:
			# Smashed glass.
			var m = _in(q,0.3,0.5)
			for k in 5:
				var e = _in(q,0.3+cos(k*1.3)*0.18,0.5+sin(k*1.3)*0.4)
				p.line(m,e,Color(0.8,0.9,1,0.35),1)
		if hv%2==0:
			# A striped awning, torn on some fronts.
			var strips = 6
			for k in strips:
				var u0 = 0.05+0.9*k/strips; var u1 = 0.05+0.9*(k+1)/strips
				var drop = 0.0 if (hv%5!=2 or k<4) else 6.0
				var col: Color = t.neon[(hv/3)%t.neon.size()].darkened(0.35) if k%2==0 else Color("e9e2d0").darkened(0.2)
				p.poly([_fp(a,b,u0,68),_fp(a,b,u1,68),_fp(a,b,u1,60)+n-Vector2(0,-drop),_fp(a,b,u0,60)+n-Vector2(0,-drop)],col)
			p.line(_fp(a,b,0.05,60)+n,_fp(a,b,0.95,60)+n,Color(0,0,0,0.35),1.5)
	elif kind==3:
		var q = _fq(a,b,0.3,0.7,0,54)
		p.poly(q,Color("120d14"))
		p.poly(q,Color(0,0,0,0),trim)
		p.circle(_in(q,0.8,0.45),1.3,Color("d8c070"))
	elif kind<=5:
		var q = _fq(a,b,0.08,0.92,0,60)
		p.poly(q,Color("6a6e78").darkened(0.1+0.1*(hv%2)))
		for k in 14: p.line(_in(q,0,k/14.0),_in(q,1,k/14.0),Color(0,0,0,0.25),1)
	elif kind==6:
		var q = _fq(a,b,0.15,0.85,10,58)
		p.poly(q,Color("0b0d14"))
		for k in 3: p.poly(_sub(q,0,1,0.1+k*0.3,0.3+k*0.3),Color("6b4a32").darkened(0.1*k))
		p.line(_in(q,0,0.1),_in(q,1,0.9),Color("5a3a26"),3)
	# The rest are plain wall: quieter fronts make the street easier to read.

func _window(q: Array, state: int, trim: Color) -> void:
	p.poly(q,Color("0d1220"))
	match state%20:
		10, 11, 12:
			p.poly(_sub(q,0.08,0.92,0.08,0.92),Color(1,0.78,0.45,0.75))
			p.line(_in(q,0.5,0.08),_in(q,0.5,0.92),Color(0.3,0.2,0.1,0.6),1)
		13: p.poly(_sub(q,0.08,0.92,0.08,0.92),Color(0.4,0.6,1,0.3+0.35*abs(sin(g.clock*9+state))))
		14, 15, 16:
			p.poly([_in(q,0.1,0.95),_in(q,0.55,0.6),_in(q,0.9,0.95)],Color(0.7,0.8,0.95,0.3))
			p.poly([_in(q,0.1,0.05),_in(q,0.35,0.4),_in(q,0.6,0.05)],Color(0.7,0.8,0.95,0.25))
		17, 18, 19:
			p.poly(q,Color("5e4230"))
			p.line(_in(q,0,0.3),_in(q,1,0.4),Color("3e2a1c"),1.5)
			p.line(_in(q,0,0.7),_in(q,1,0.75),Color("3e2a1c"),1.5)
		_: p.line(_in(q,0.15,0.2),_in(q,0.4,0.85),Color(1,1,1,0.08),2)
	p.line(_in(q,-0.08,-0.06),_in(q,1.08,-0.06),Color(trim,0.8),2)

func _fire_escape(a: Vector2, b: Vector2, n: Vector2) -> void:
	var metal = Color("2a2a30")
	for v in [80.0]:
		var q = [_fp(a,b,0.08,v),_fp(a,b,0.92,v),_fp(a,b,0.92,v)+n,_fp(a,b,0.08,v)+n]
		p.poly(q,Color(metal,0.9))
		p.line(q[3]-Vector2(0,10),q[2]-Vector2(0,10),metal,1.5)
		for u in [0.0,0.33,0.66,1.0]:
			var base = q[3].lerp(q[2],u)
			p.line(base,base-Vector2(0,10),metal,1)
	# The drop ladder hangs from the platform.
	p.line(_fp(a,b,0.75,80)+n,_fp(a,b,0.75,48)+n,metal,1.5)
	p.line(_fp(a,b,0.85,80)+n,_fp(a,b,0.85,48)+n,metal,1.5)
	for k in 5: p.line(_fp(a,b,0.75,52+k*6)+n,_fp(a,b,0.85,52+k*6)+n,metal,1)

func _low_wall_details(a: Vector2, b: Vector2, h: float, hv: int, base: Color, t: Dictionary) -> void:
	match hv%6:
		1:
			# Plaster fallen away from the brick underneath.
			var q = _fq(a,b,0.25,0.75,8,minf(30,h-4))
			p.poly(q,Color("6b3a30").darkened(0.15))
			for k in 4: p.line(_in(q,0,k/4.0),_in(q,1,k/4.0),Color(0,0,0,0.3),1)
		2: p.line(_fp(a,b,0.4,h),_fp(a,b,0.55,h*0.4),Color(0,0,0,0.4),1.5)
	# A broken notch in the top edge.
	if hv%3==0:
		p.poly([_fp(a,b,0.35,h),_fp(a,b,0.5,h-8),_fp(a,b,0.62,h)],Color(base.darkened(0.45),1))

# --- Neon signs ------------------------------------------------------------------

func signs(view: Rect2) -> void:
	var t = theme()
	for sign in g.signs:
		var visible = false
		for cell in sign.cells:
			if g.seen.has(cell): visible = true
		if not visible: continue
		var a = g._project(sign.a)
		var b = g._project(sign.b)
		if not view.has_point(a) and not view.has_point(b): continue
		var color: Color = t.neon[sign.color%t.neon.size()]
		var on = _flicker(sign.seed) if sign.flicker else 1.0
		if sign.kind=="panel": _panel_sign(sign,a,b,color,on)
		else: _blade_sign(sign,a,b,color,on)

func _panel_sign(sign: Dictionary, a: Vector2, b: Vector2, color: Color, on: float) -> void:
	var span = b.x-a.x
	var size = 15
	while size>9 and _text_width(sign.text,size)>span-14: size -= 1
	var width = _text_width(sign.text,size)
	var slope = (b.y-a.y)/(b.x-a.x)
	var origin = a-Vector2(0,sign.v)
	c.draw_set_transform_matrix(Transform2D(Vector2(1,slope),Vector2(0,1),origin+shake))
	var left = (span-width)/2.0-6
	c.draw_rect(Rect2(left,-size-8,width+12,size+12),p.ink(Color("120a1ee8")))
	c.draw_rect(Rect2(left,-size-8,width+12,size+12),p.ink(Color(color,0.35*on+0.1)),false,1.5)
	if on>0.5: c.draw_texture_rect(p.glow_texture,Rect2(left-20,-size-30,width+52,size+52),false,p.ink(Color(color,0.18)))
	_neon_text(sign.text,Vector2((span-width)/2.0,-4),size,color,on,sign.dead)
	c.draw_set_transform(shake)

func _blade_sign(sign: Dictionary, a: Vector2, b: Vector2, color: Color, on: float) -> void:
	var out = Vector2(-9,4.5) if sign.face.y>0 else Vector2(9,4.5)
	var anchor = a.lerp(b,0.5)-Vector2(0,sign.v)+out
	var letters: String = sign.text
	var size = 12
	var height = letters.length()*(size+1)+10
	var top = anchor-Vector2(0,height)
	p.line(anchor-out-Vector2(0,height*0.2),top+Vector2(0,6),Color("2a2a30"),2)
	p.line(anchor-out-Vector2(0,height*0.8),top+Vector2(0,height-6),Color("2a2a30"),2)
	c.draw_rect(Rect2(top.x-11,top.y,22,height),p.ink(Color("120a1ef0")))
	c.draw_rect(Rect2(top.x-11,top.y,22,height),p.ink(Color(color,0.45*on+0.1)),false,1.5)
	if on>0.5: p.glow(top+Vector2(0,height/2.0),height*0.8,Color(color,0.22))
	for i in letters.length():
		var ch = letters[i]
		var w = _text_width(ch,size)
		_neon_text(ch,Vector2(top.x-w/2.0,top.y+8+(i+1)*(size+1)-3),size,color,on)

## Colored light that neon signs throw on the street in front of them.
func sign_light() -> void:
	var t = theme()
	for sign in g.signs:
		var mid: Vector2 = (sign.a+sign.b)/2.0
		if not g.seen.has(Vector2i(mid)): continue
		var on = _flicker(sign.seed) if sign.flicker else 1.0
		var out = Vector2(0,1.6) if sign.a.y==sign.b.y else Vector2(1.6,0)
		var color: Color = t.neon[sign.color%t.neon.size()]
		_pool(mid+out,130 if sign.kind=="panel" else 80,Color(color,0.13*on))

# --- Ground markings ---------------------------------------------------------------

func decals(center: Vector2, radius: float) -> void:
	var t = theme()
	for d in g.decals:
		if not g.seen.has(Vector2i(d.pos)): continue
		if d.pos.distance_to(center)>radius+maxf(d.w,d.h): continue
		match d.kind:
			"lane":
				var a: Vector2 = d.a; var b: Vector2 = d.b
				var length = a.distance_to(b)
				var dir = (b-a)/length
				var at = 0.8
				while at<length-0.8:
					if not g.seen.has(Vector2i(a+dir*at)):
						at += 1.8
						continue
					p.line(g._project(a+dir*at),g._project(a+dir*minf(at+0.9,length-0.8)),Color(t.lane,0.55),2.5)
					at += 1.8
			"crosswalk":
				var along = Vector2(1,0) if d.axis=="x" else Vector2(0,1)
				var across = Vector2(0,1) if d.axis=="x" else Vector2(1,0)
				var length: float = d.w if d.axis=="x" else d.h
				var k = -length/2.0+0.3
				while k<length/2.0-0.2:
					var m = d.pos+along*k
					p.poly([g._project(m-across*0.5),g._project(m+along*0.4-across*0.5),g._project(m+along*0.4+across*0.5),g._project(m+across*0.5)],Color(0.88,0.88,0.85,0.42))
					k += 0.8
			"bays":
				var x0 = d.pos.x-d.w/2.0
				for k in int(d.w/2.0)+1:
					var x = x0+k*2.0
					p.line(g._project(Vector2(x,d.pos.y-1)),g._project(Vector2(x,d.pos.y+1)),Color(0.9,0.9,0.85,0.4),2)
			"manhole":
				var s = g._project(d.pos)
				p.ellipse(s,17,8.5,Color("1e2028"),18)
				p.ellipse_arc(s,17,8.5,0,TAU,Color("5a5e6a"),1.5)
				for k in 3: p.line(s+Vector2(-12,-4+k*4),s+Vector2(12,-4+k*4),Color("3a3e48"),1)
				if t.weather=="rain":
					for k in 3:
						var rise = fmod(g.clock*14+k*14+d.pos.x*5,42)
						p.circle(s-Vector2(sin(g.clock+k)*5,rise),6+rise*0.25,Color(0.85,0.85,0.95,0.07*(1-rise/42)))
			"pothole":
				var s = g._project(d.pos)
				p.poly([s+Vector2(-14,-2),s+Vector2(-6,-7),s+Vector2(9,-6),s+Vector2(15,1),s+Vector2(4,6),s+Vector2(-9,5)],Color("15161c"))
			"puddle":
				var s = g._project(d.pos)
				var rx = d.w*22.0; var ry = d.h*11.0
				var seed_value: int = d.get("seed",0)
				_blob(d.pos,d.w,d.h,seed_value,Color("0d1424a0"))
				_blob(d.pos-Vector2(0.1,0.1),d.w*0.55,d.h*0.45,seed_value+5,Color(t.glow,0.1))
				p.line(s+Vector2(-rx*0.5,-ry*0.1),s+Vector2(rx*0.1,-ry*0.4),Color(1,1,1,0.12),1.5)
				if t.weather=="rain":
					var phase = fmod(g.clock*0.9+d.get("seed",0)*0.37,1.0)
					p.ellipse_arc(s+Vector2(rx*0.2,0),2+phase*12,1+phase*6,0,TAU,Color(1,1,1,0.2*(1-phase)),1)
			"stain":
				_blob(d.pos,d.w,d.h,d.get("seed",0),Color(0,0,0,0.22))
			"scorch":
				var s = g._project(d.pos)
				_blob(d.pos,d.w,d.h,d.get("seed",0),Color(0,0,0,0.4))
				_blob(d.pos,d.w*0.55,d.h*0.5,d.get("seed",0)+7,Color(0.05,0.03,0.03,0.45))
				if t.weather=="ash":
					for k in 3: p.circle(s+Vector2(sin(k*2.1+d.get("seed",0))*d.w*12,cos(k*1.7)*d.h*5),1.3,Color(1,0.5,0.2,0.4+0.4*sin(g.clock*3+k)))
			"sunset": _sunset(d)

## The Warden's plaza floor: a vaporwave sun laid out in tiles.
func _sunset(d: Dictionary) -> void:
	var r: float = d.w/2.0
	var e1 = Vector2(0.7071,-0.7071)
	var e2 = Vector2(0.7071,0.7071)
	var rings: Array = []
	for i in 40:
		var a = TAU*i/40.0
		rings.append(g._project(d.pos+e1*cos(a)*(r+0.5)+e2*sin(a)*(r+0.5)))
	p.poly(rings,Color("1a0f2acc"))
	var bands = 12
	for i in bands:
		var w0 = -r+2*r*i/float(bands)
		var w1 = w0+2*r/float(bands)
		if i>=bands/2 and i%2==1: continue
		var pts: Array = []
		var steps = 6
		for k in steps+1:
			var w = lerpf(w0,w1,k/float(steps))
			var half = sqrt(maxf(0.0,r*r-w*w))
			pts.append(g._project(d.pos-e1*half+e2*w))
		for k in range(steps,-1,-1):
			var w = lerpf(w0,w1,k/float(steps))
			var half = sqrt(maxf(0.0,r*r-w*w))
			pts.append(g._project(d.pos+e1*half+e2*w))
		var tint = Color("ffe45c").lerp(Color("ff4fd8"),i/float(bands-1))
		p.poly(pts,Color(tint,0.34))
	var outline: Array = []
	for i in 41:
		var a = TAU*i/40.0
		outline.append(g._project(d.pos+e1*cos(a)*(r+0.5)+e2*sin(a)*(r+0.5)))
	c.draw_polyline(PackedVector2Array(outline),p.ink(Color("3ff0ffb0")),2,true)
	_pool(d.pos,260,Color(1,0.4,0.8,0.06+sin(g.clock*1.5)*0.02))

# --- Light pools -------------------------------------------------------------------

func lights(center: Vector2, radius: float) -> void:
	var t = theme()
	for prop in g.props:
		if not g.seen.has(Vector2i(prop.pos)) or prop.pos.distance_to(center)>radius: continue
		match prop.kind:
			"streetlight":
				var on = _flicker(prop.seed,0.8) if prop.flicker else 1.0
				_pool(prop.pos+prop.dir*1.0,170,Color(t.light,0.17*on))
			"streetlight_low": _pool(prop.pos,110,Color(t.light,0.14))
			"barrel_fire", "campfire": _pool(prop.pos,150,Color(1,0.55,0.25,0.17+sin(g.clock*7+prop.pos.x)*0.02))
			"traffic_light": _pool(prop.pos+Vector2(0.6,0.6),70,Color(1,0.7,0.2,0.12*(1.0 if sin(g.clock*3.5)>0 else 0.2)))
			"arcade":
				if not prop.broken: _pool(prop.pos+Vector2(prop.face)*0.8,70,Color(SCREEN_COLORS[prop.color],0.13))
			"jukebox": _pool(prop.pos+Vector2(prop.face)*0.6,80,Color(1,0.5,0.9,0.14))
			"tv_pile", "tv_small": _pool(prop.pos+Vector2(0.5,0.5),60,Color(0.5,0.7,1,0.08+0.06*abs(sin(g.clock*11+prop.seed))))
			"neon_floor": _pool(prop.pos,260,Color(t.glow,0.09))
			"chest":
				if not prop.open: _pool(prop.pos,120,Color(1,0.85,0.4,0.2))

# --- Props -------------------------------------------------------------------------

func prop(pr: Dictionary) -> void:
	var s = g._project(pr.pos)
	var t = theme()
	var seed_value: int = pr.get("seed",0)
	match pr.kind:
		"crate": _crate(pr,s)
		"chest": _chest(pr,s)
		"streetlight": _streetlight(pr,s,t)
		"streetlight_low":
			_shadow(pr.pos,0.2,0.2)
			p.line(s,s-Vector2(0,58),Color("2c2e36"),3)
			p.ellipse(s,5,2.5,Color("3a3c46"),10)
			p.circle(s-Vector2(0,62),6,Color(t.light.lightened(0.4)))
			p.glow(s-Vector2(0,62),26,Color(t.light,0.45))
		"traffic_light": _traffic_light(pr,s)
		"car": _car(pr)
		"dumpster": _dumpster(pr,s)
		"payphone": _payphone(pr,s,t)
		"barrel_fire": _barrel_fire(pr,s)
		"campfire":
			for k in 7:
				var a = TAU*k/7.0
				p.ellipse(s+Vector2(cos(a)*14,sin(a)*7),4,2.5,Color("6a6460"),8)
			p.limb(s+Vector2(-9,-2),s+Vector2(8,3),4,Color("4a3222"))
			p.limb(s+Vector2(-7,4),s+Vector2(9,-3),4,Color("5a3a26"))
			_flame(s-Vector2(0,2),0.85,pr.pos.x)
			_flame(s-Vector2(5,0),0.55,pr.pos.y+2)
			_embers(s-Vector2(0,10),seed_value)
		"barrier": _barrier(pr)
		"sandbags": _sandbags(pr)
		"trash":
			_shadow(pr.pos,0.4,0.25,0.4)
			for k in 3:
				var q = s+Vector2(-8+k*7,(k%2)*3-2)
				p.ellipse(q-Vector2(0,5),7,6.5,Color("15161c"),14)
				p.ellipse(q-Vector2(2,8),2.5,1.5,Color(1,1,1,0.18),8)
				p.line(q-Vector2(0,11),q-Vector2(-2,14),Color("2a2b33"),1.5)
			p.poly([s+Vector2(6,2),s+Vector2(16,-1),s+Vector2(19,4),s+Vector2(9,7)],Color("cfc8b8"))
		"paper":
			for k in 2:
				var q = s+Vector2(((seed_value*(k+1))%20)-10,((seed_value*(k+3))%8)-4)
				p.poly([q,q+Vector2(7,-3),q+Vector2(11,1),q+Vector2(4,4)],Color(0.85,0.82,0.75,0.75))
				p.line(q+Vector2(2,0),q+Vector2(8,-1),Color(0,0,0,0.25),1)
		"tires":
			for k in 3:
				var q = s-Vector2(0,k*6)
				p.ellipse(q,11,5.5,Color("17171b"),16)
				p.ellipse(q-Vector2(0,1),5,2.5,Color("050507"),12)
				p.ellipse_arc(q,11,5.5,PI,TAU,Color("3a3a42"),1)
		"hydrant":
			_shadow(pr.pos,0.15,0.15)
			_cyl(pr.pos,0.12,0,16,Color("b02a2a"),Color("d04040"))
			p.ellipse(s-Vector2(0,19),5,3,Color("e8c040"),10)
			p.circle(s+Vector2(-6,-10),2.2,Color("8a1e1e"))
			p.circle(s+Vector2(6,-10),2.2,Color("8a1e1e"))
		"newsbox":
			_shadow(pr.pos,0.2,0.18)
			var col: Color = [Color("c03a2a"),Color("2a5aa0"),Color("d0a830")][seed_value%3]
			_box(pr.pos.x,pr.pos.y,0.16,0.14,0,24,col.lightened(0.2),col,col.darkened(0.25))
			var f = _front_face(pr.pos.x,pr.pos.y,0.16,0.14,0,24)
			p.poly(_sub(f,0.15,0.85,0.45,0.85),Color("1a1e28"))
			p.poly(_sub(f,0.25,0.75,0.55,0.75),Color(0.85,0.82,0.75,0.6))
		"cone":
			p.poly([s+Vector2(-7,0),s+Vector2(0,3.5),s+Vector2(7,0),s+Vector2(0,-3.5)],Color("d0581a"))
			p.poly([s+Vector2(-5,-1),s+Vector2(0,-20),s+Vector2(5,-1)],Color("ff7a2a"))
			p.poly([s+Vector2(-3.4,-7),s+Vector2(3.4,-7),s+Vector2(2.4,-11),s+Vector2(-2.4,-11)],Color("f0f0f0"))
		"bench":
			_shadow(pr.pos,0.45,0.2,0.3)
			var hx = 0.45 if pr.axis=="x" else 0.16
			var hy = 0.16 if pr.axis=="x" else 0.45
			for k in [-1,1]:
				var o = Vector2(k*0.35,0) if pr.axis=="x" else Vector2(0,k*0.35)
				p.line(g._project(pr.pos+o),g._project(pr.pos+o,10),Color("2a2a30"),2)
			_box(pr.pos.x,pr.pos.y,hx,hy,10,13,Color("8a5a3a"),Color("6a4430"),Color("5a3a28"))
		"palm": _palm(pr,s,t)
		"fountain": _fountain(pr,s,t)
		"tent": _tent(pr)
		"mattress":
			_box(pr.pos.x,pr.pos.y,0.45,0.3,0,5,Color("cfc4b0"),Color("a89c88"),Color("988c78"))
			var top = [_pt(pr.pos.x-0.45,pr.pos.y-0.3,5),_pt(pr.pos.x+0.45,pr.pos.y-0.3,5),_pt(pr.pos.x+0.45,pr.pos.y+0.3,5),_pt(pr.pos.x-0.45,pr.pos.y+0.3,5)]
			p.ellipse(_in(top,0.4,0.5),9,4,Color(0.5,0.4,0.25,0.35),10)
			for k in 3: p.line(_in(top,0.2+k*0.3,0),_in(top,0.2+k*0.3,1),Color(0.4,0.5,0.7,0.35),1)
		"tv_pile": _tv_pile(pr,s)
		"tv_small": _tv(pr.pos,0,seed_value)
		"cart": _cart(pr,s)
		"arcade": _arcade(pr)
		"counter": _counter(pr)
		"stool":
			p.line(s,s-Vector2(0,14),Color("b0b4c0"),2)
			p.ellipse(s,5,2.5,Color("6a6e78"),10)
			p.ellipse(s-Vector2(0,15),7,3.5,Color("c02a3a"),12)
			p.ellipse(s-Vector2(0,16),5,2.2,Color("e04a5a"),10)
		"booth": _booth(pr)
		"jukebox": _jukebox(pr)
		"shelf": _shelf(pr)
		"tapes":
			for k in 3:
				var q = s+Vector2(-8+k*7,((seed_value+k)%3)*2-2)
				p.poly([q,q+Vector2(8,-4),q+Vector2(12,-2),q+Vector2(4,2)],Color("15151a"))
				p.poly([q+Vector2(2,-1),q+Vector2(7,-3.5),q+Vector2(9,-2.5),q+Vector2(4,0)],SCREEN_COLORS[(seed_value+k)%5].darkened(0.2))
		"washer": _washer(pr)
		"column":
			_shadow(pr.pos,0.4,0.4,0.4)
			var top = 56.0
			_box(pr.pos.x,pr.pos.y,0.28,0.28,0,top,Color("7a7a82"),Color("5e5e66"),Color("4a4a52"))
			var f = _front_face(pr.pos.x,pr.pos.y,0.28,0.28,0,top)
			p.poly(_sub(f,0.15,0.85,0.3,0.55),Color(t.neon[seed_value%t.neon.size()],0.45).darkened(0.3))
			for k in 3: p.line(_pt(pr.pos.x-0.2+k*0.2,pr.pos.y,top),_pt(pr.pos.x-0.2+k*0.2,pr.pos.y,top+8+k*3),Color("8a5a3a"),1.5)
		"drums":
			for k in 2:
				var o = Vector2(-0.18+k*0.36,-0.1+k*0.2)
				var col = Color("2a5aa0") if (seed_value+k)%2==0 else Color("c8a020")
				_cyl(pr.pos+o,0.2,0,26,col,col.lightened(0.2))
				p.line(g._project(pr.pos+o)+Vector2(-9,-9),g._project(pr.pos+o)+Vector2(9,-9),col.darkened(0.35),1.5)
				p.line(g._project(pr.pos+o)+Vector2(-9,-19),g._project(pr.pos+o)+Vector2(9,-19),col.darkened(0.35),1.5)
		"mound": _mound(pr,t)
		"ruin_wall": _ruin_wall(pr,t)
		"rubble":
			for k in 4:
				var offset = Vector2(((seed_value+k*37)%17)-8,((seed_value+k*53)%9)-4)
				var size = 4+((seed_value+k*11)%5)
				p.block(s+offset+Vector2(0,size*0.5),size,size*0.7,Color("6a6870"),Color("4a4850"),Color("8a8890"))
			p.line(s+Vector2(-4,-2),s+Vector2(4,-12),Color("8a5a3a"),1.2)
		"bones":
			var bone = Color("d9cfb4")
			p.limb(s+Vector2(-10,-2),s+Vector2(6,2),2.4,bone)
			p.limb(s+Vector2(-4,4),s+Vector2(10,-3),2.2,bone.darkened(0.1))
			p.circle(s+Vector2(4,-5),5,bone)
			p.circle(s+Vector2(2.5,-5.5),1.3,Color("201a18"))
			p.circle(s+Vector2(5.8,-5.5),1.3,Color("201a18"))
		"neon_floor": pass

func _crate(pr: Dictionary, s: Vector2) -> void:
	var x = s.x; var y = s.y
	if pr.open:
		p.poly([[x-10,y],[x+5,y-5],[x+14,y+2],[x,y+5]],Color("655342"))
		p.line(Vector2(x-6,y-1),Vector2(x+8,y+1),Color("8a6e50"),2)
		return
	# p.block's footprint ends at its point, so shift it down to centre it on s.
	var w = 12.0; var h = 11.0
	var b = s+Vector2(0,w/2)
	_shadow(pr.pos,0.26,0.26,0.5)
	p.block(b,w,h,Color("7c5f41"),Color("554a3b"),Color("a3814f"))
	p.line(b,b+Vector2(w,-h-w/2),Color("c39b60"),1.2)
	p.line(b+Vector2(0,-h),b+Vector2(w,-w/2),Color("c39b60"),1.2)
	p.line(b,b+Vector2(-w,-h-w/2),Color("8a6e50"),1.2)
	p.line(b+Vector2(0,-h),b+Vector2(-w,-w/2),Color("8a6e50"),1.2)

## Loot sits in an army footlocker with a stenciled lid.
func _chest(pr: Dictionary, s: Vector2) -> void:
	var w = 15.0; var h = 7.0
	var b = s+Vector2(0,w/2)
	_shadow(pr.pos,0.32,0.32,0.55)
	if not pr.open: p.glow(b-Vector2(0,16),40,Color("ffe45c28"))
	p.block(b,w,h,Color("4f5a34"),Color("3a4426"),Color("6a7846"))
	for offset in [-9.0,9.0]: c.draw_line(b+Vector2(offset,-4.5),b+Vector2(offset,-h-4.5),p.ink(Color("c8c8b0")),2,true)
	var lid = h+(12.0 if pr.open else 0.0)
	p.block(b-Vector2(0,lid),w+0.5,3,Color("5c6a3c"),Color("46522e"),Color("7a8a52"))
	if pr.open:
		p.glow(b-Vector2(0,20),30,Color(1,0.85,0.4,0.3))
	else:
		var pulse = 0.75+0.25*sin(g.clock*3+pr.pos.x)
		c.draw_texture_rect(p.glow_texture,Rect2(b-Vector2(14,150),Vector2(28,150)),false,p.ink(Color(1,0.85,0.35,0.35*pulse)))
		var mark = b-Vector2(0,44+sin(g.clock*3)*4)
		p.poly([mark+Vector2(-7,-6),mark+Vector2(7,-6),mark+Vector2(0,3)],Color(1,0.85,0.35,0.95))
		p.poly([mark+Vector2(-4,-5),mark+Vector2(4,-5),mark+Vector2(0,0)],Color(1,1,0.85,0.95))
		c.draw_rect(Rect2(b+Vector2(-2,-7),Vector2(4,4)),p.ink(Color("d8d0b0")))
		p.center("88",b+Vector2(7,-lid-w/2-9),7,Color("e8d070"))

func _streetlight(pr: Dictionary, s: Vector2, t: Dictionary) -> void:
	var on = _flicker(pr.seed,0.8) if pr.flicker else 1.0
	var head = g._project(pr.pos+pr.dir*0.9,112)
	var top = s-Vector2(0,118)
	_shadow(pr.pos,0.22,0.22)
	p.ellipse(s,7,3.5,Color("3a3c46"),12)
	p.line(s,top,Color("2c2e36"),4)
	p.line(s+Vector2(1,0),top+Vector2(1,0),Color("4a4e5a"),1)
	p.line(top,top.lerp(head,0.5)-Vector2(0,6),Color("2c2e36"),3)
	p.line(top.lerp(head,0.5)-Vector2(0,6),head,Color("2c2e36"),3)
	var arm = (head-top.lerp(head,0.5)).normalized()
	p.poly([head-arm*10+Vector2(0,-2),head+arm*8+Vector2(0,-3),head+arm*10+Vector2(0,1),head-arm*8+Vector2(0,2)],Color("3a3c46"))
	p.poly([head-arm*7+Vector2(0,1),head+arm*8+Vector2(0,0),head+arm*6+Vector2(0,3),head-arm*6+Vector2(0,3)],Color(t.light.lightened(0.5),0.25+0.75*on))
	if on>0.5:
		p.glow(head+Vector2(0,4),44,Color(t.light,0.5))
		var ground = g._project(pr.pos+pr.dir*0.9)
		p.poly([head+Vector2(-6,2),head+Vector2(6,2),ground+Vector2(40,0),ground+Vector2(-40,0)],Color(t.light,0.045))

func _traffic_light(pr: Dictionary, s: Vector2) -> void:
	_shadow(pr.pos,0.2,0.2)
	var top = s-Vector2(0,96)
	p.line(s,top,Color("2a2c32"),4)
	p.poly([top+Vector2(-7,-2),top+Vector2(7,-2),top+Vector2(7,34),top+Vector2(-7,34)],Color("c8a020"))
	p.poly([top+Vector2(-5,0),top+Vector2(5,0),top+Vector2(5,32),top+Vector2(-5,32)],Color("1a1a1e"))
	var amber = sin(g.clock*3.5)>0
	p.circle(top+Vector2(0,6),3.6,Color("4a1414"))
	p.circle(top+Vector2(0,16),3.6,Color("ffb030") if amber else Color("4a3414"))
	p.circle(top+Vector2(0,26),3.6,Color("143a1a"))
	if amber: p.glow(top+Vector2(0,16),26,Color(1,0.7,0.2,0.5))

func _car(pr: Dictionary) -> void:
	var along_x = pr.axis=="x"
	var cx = pr.pos.x; var cy = pr.pos.y
	var hx = 0.95 if along_x else 0.44
	var hy = 0.44 if along_x else 0.95
	var burned: bool = pr.burned
	var paint: Color = CAR_COLORS[pr.color%CAR_COLORS.size()]
	if burned: paint = Color("2c2624")
	var top = paint.lightened(0.15)
	var front = paint.darkened(0.1)
	var side = paint.darkened(0.3)
	_shadow(pr.pos,(hx+0.08)/0.75,(hy+0.08)/0.75,0.5)
	# Wheels on the two visible sides.
	var wheel = Color("101014")
	for k in [-0.6,0.6]:
		var q = g._project(Vector2(cx+k,cy+hy)) if along_x else g._project(Vector2(cx+hx,cy+k))
		p.ellipse(q-Vector2(0,5),7,6,wheel,12)
		if not burned: p.ellipse(q-Vector2(0,5),3,2.5,Color("6a6e78"),8)
	_box(cx,cy,hx,hy,5,17,top,front,side)
	# Cabin set back from the hood.
	var shift = (0.12 if pr.flip else -0.12)
	var kx = 0.5 if along_x else hx-0.06
	var ky = hy-0.06 if along_x else 0.5
	var ccx = cx+(shift if along_x else 0.0)
	var ccy = cy+(0.0 if along_x else shift)
	var glass = Color("101828") if not burned else Color("0a0808")
	_box(ccx,ccy,kx,ky,17,29,top.darkened(0.05),glass,glass.lightened(0.05))
	var f = _front_face(ccx,ccy,kx,ky,17,29)
	var sd = _side_face(ccx,ccy,kx,ky,17,29)
	if not burned:
		p.line(_in(f,0.15,0.2),_in(f,0.4,0.85),Color(1,1,1,0.12),2)
		p.line(_in(sd,0.2,0.2),_in(sd,0.45,0.85),Color(1,1,1,0.1),2)
		var body = _front_face(cx,cy,hx,hy,5,17)
		p.line(_in(body,0,0.35),_in(body,1,0.35),Color("c8ccd8"),1.2)
		var bs = _side_face(cx,cy,hx,hy,5,17)
		p.line(_in(bs,0,0.35),_in(bs,1,0.35),Color("c8ccd8"),1.2)
		# Lights at the front and back ends.
		var end_face = bs if along_x else body
		p.circle(_in(end_face,0.12,0.6),2,Color("e04040"))
		p.circle(_in(end_face,0.88,0.6),2,Color("e04040"))
	else:
		for k in 4:
			var q = g._project(pr.pos+Vector2(sin(k*2.3+pr.seed)*hx*0.7,cos(k*1.9)*hy*0.7),17)
			p.ellipse(q,6,3,Color("6a3a22"),10)
		if g.floor_number==2 and pr.seed%3==0:
			var roof = g._project(Vector2(ccx,ccy),29)
			_flame(roof+Vector2(-6,2),0.8,pr.seed)
			_flame(roof+Vector2(6,1),0.6,pr.seed+3)
			_embers(roof-Vector2(0,10),pr.seed)

func _dumpster(pr: Dictionary, s: Vector2) -> void:
	_shadow(pr.pos,0.55,0.4)
	var col = Color("2f5a3c") if pr.seed%2==0 else Color("2a4a7a")
	_box(pr.pos.x,pr.pos.y,0.42,0.34,0,22,col.lightened(0.1),col,col.darkened(0.25))
	var lid = [_pt(pr.pos.x-0.44,pr.pos.y-0.36,25),_pt(pr.pos.x+0.44,pr.pos.y-0.36,25),_pt(pr.pos.x+0.44,pr.pos.y+0.36,22),_pt(pr.pos.x-0.44,pr.pos.y+0.36,22)]
	p.poly(lid,Color("1e2228"))
	var f = _front_face(pr.pos.x,pr.pos.y,0.42,0.34,0,22)
	for k in 3: p.line(_in(f,0.25+k*0.25,0.05),_in(f,0.25+k*0.25,0.9),Color(0,0,0,0.25),1.5)
	p.ellipse(_in(lid,0.3,0.4)-Vector2(0,4),8,6,Color("15161c"),12)

func _payphone(pr: Dictionary, s: Vector2, t: Dictionary) -> void:
	_shadow(pr.pos,0.25,0.25)
	p.line(s,s-Vector2(0,30),Color("8a8e98"),3)
	_box(pr.pos.x,pr.pos.y,0.2,0.2,30,58,Color("c0c4d0"),Color("2a4a8a"),Color("1e3a6e"))
	var f = _front_face(pr.pos.x,pr.pos.y,0.2,0.2,30,58)
	p.poly(_sub(f,0.2,0.8,0.2,0.65),Color("15181e"))
	p.circle(_in(f,0.5,0.45),2,Color("8a8e98"))
	p.line(_in(f,0.3,0.3),_in(f,0.3,0.3)+Vector2(-2,14),Color("15181e"),1.5)
	var sign = _sub(f,0.05,0.95,0.78,0.98)
	p.poly(sign,Color(t.neon[1],0.85))
	p.glow(_in(sign,0.5,0.5),18,Color(t.neon[1],0.35))

func _barrel_fire(pr: Dictionary, s: Vector2) -> void:
	_shadow(pr.pos,0.3,0.3)
	_cyl(pr.pos,0.22,0,24,Color("6a3a22"),Color("201410"))
	p.line(s+Vector2(-10,-8),s+Vector2(10,-8),Color("3a2214"),1.5)
	p.line(s+Vector2(-10,-17),s+Vector2(10,-17),Color("3a2214"),1.5)
	p.ellipse(s+Vector2(-4,-12),3,4,Color("8a4a2a"),8)
	p.glow(s-Vector2(0,30),60,Color(1,0.55,0.25,0.3))
	_flame(s-Vector2(3,24),0.8,pr.pos.x)
	_flame(s-Vector2(-4,24),0.6,pr.pos.y+5)
	_embers(s-Vector2(0,34),pr.seed)

func _embers(at: Vector2, seed_value: int) -> void:
	for k in 4:
		var rise = fmod(g.clock*30+k*13+seed_value,52)
		p.circle(at+Vector2(sin(g.clock*2+k*1.7)*7,-rise),1.2,Color(1,0.6,0.25,1-rise/52))

func _barrier(pr: Dictionary) -> void:
	var along_x = pr.axis=="x"
	var hx = 0.92 if along_x else 0.26
	var hy = 0.26 if along_x else 0.92
	_shadow(pr.pos,hx+0.1,hy+0.1,0.35)
	var concrete = Color("9a9aa2")
	_box(pr.pos.x,pr.pos.y,hx,hy,0,8,concrete,concrete.darkened(0.15),concrete.darkened(0.3))
	var tx = hx if along_x else 0.12
	var ty = 0.12 if along_x else hy
	_box(pr.pos.x,pr.pos.y,tx,ty,8,22,concrete.lightened(0.1),concrete.darkened(0.08),concrete.darkened(0.25))
	var face = _front_face(pr.pos.x,pr.pos.y,tx,ty,8,22) if along_x else _side_face(pr.pos.x,pr.pos.y,tx,ty,8,22)
	for k in 4:
		var u = 0.1+k*0.22
		p.poly([_in(face,u,0.15),_in(face,u+0.1,0.15),_in(face,u+0.18,0.85),_in(face,u+0.08,0.85)],Color("e07a2a"))
	p.line(_in(face,0,1),_in(face,1,1),Color(1,1,1,0.15),1)

func _sandbags(pr: Dictionary) -> void:
	var along_x = pr.axis=="x"
	_shadow(pr.pos,0.9 if along_x else 0.35,0.35 if along_x else 0.9,0.35)
	for row in 3:
		for k in 4:
			var o = (k-1.5)*0.45+(0.22 if row==1 else 0.0)
			if absf(o)>0.9: continue
			var q = g._project(pr.pos+(Vector2(o,0) if along_x else Vector2(0,o)),row*7+4)
			p.ellipse(q,11,6,Color("8a7a58").darkened(0.06*((k+row)%3)),12)
			p.ellipse(q-Vector2(2,2),6,2.5,Color(1,1,1,0.08),8)

func _palm(pr: Dictionary, s: Vector2, t: Dictionary) -> void:
	_shadow(pr.pos,0.3,0.3)
	var lean: float = pr.lean
	var height = 124.0
	var last = s
	var crown = s
	for k in range(1,11):
		var f = k/10.0
		var q = s+Vector2(lean*60*f*f,-height*f)
		p.line(last,q,Color("6a5040"),7-f*2)
		p.line(last+Vector2(-2,0),q+Vector2(-2,0),Color("7a6050"),1)
		last = q
		crown = q
	var neon: bool = pr.get("neon",false) or t.weather=="glitter"
	if neon:
		var glow_color: Color = t.neon[0]
		var prev = s
		for k in range(1,11):
			var f = k/10.0
			var q = s+Vector2(lean*60*f*f+3*sin(f*20),-height*f)
			p.line(prev,q,Color(glow_color,0.85),1.5)
			prev = q
		p.glow(s-Vector2(0,height*0.5),60,Color(glow_color,0.12))
	var dead = t.weather=="ash"
	var leaf = Color("6a5a30") if dead else Color("2f6a46")
	var sway = sin(g.clock*0.8+pr.pos.x)*3
	for k in 7:
		var a = -PI/2+(k-3)*0.5
		var tip = crown+Vector2(cos(a)*46+sway,sin(a)*14+30-absf(k-3)*2)
		var mid = crown.lerp(tip,0.5)-Vector2(0,10)
		var n = (tip-crown).normalized().orthogonal()*5
		p.poly([crown,mid+n,tip,mid-n*0.4],leaf.darkened(0.1*(k%2)))
		p.line(crown,mid,leaf.lightened(0.15),1)
		if neon: p.line(mid,tip,Color(t.neon[1],0.5),1)
	for k in 3: p.circle(crown+Vector2(-4+k*4,4),3,Color("4a3422"))

func _fountain(pr: Dictionary, s: Vector2, t: Dictionary) -> void:
	_cyl(pr.pos,0.95,0,14,Color("8a8494"),Color("6a6474"))
	p.ellipse(s-Vector2(0,14),38,19,Color("3a3644"),24)
	p.ellipse(s-Vector2(0,13),30,14,Color("2a4a40") if t.weather!="ash" else Color("2a2422"),20)
	_cyl(pr.pos,0.16,10,44,Color("9a94a4"),Color("aaa4b4"))
	_cyl(pr.pos,0.45,44,50,Color("8a8494"),Color("6a6474"))
	p.line(s+Vector2(-20,-6),s+Vector2(-8,-12),Color(0,0,0,0.35),1)
	# A chrome bust on top, the mall's mascot.
	p.circle(s-Vector2(0,62),9,Color("d0d4e0"))
	p.circle(s-Vector2(3,64),3,Color(1,1,1,0.6))
	p.poly([s-Vector2(9,52),s-Vector2(-9,52),s-Vector2(-6,56),s-Vector2(6,56)],Color("b0b4c0"))

func _tent(pr: Dictionary) -> void:
	var col: Color = TARP_COLORS[pr.get("color",0)%TARP_COLORS.size()]
	var x0 = pr.pos.x-0.95; var x1 = pr.pos.x+0.95
	var y0 = pr.pos.y-0.45; var y1 = pr.pos.y+0.45; var yc = pr.pos.y
	_shadow(pr.pos,1.0,0.5,0.35)
	p.poly([_pt(x0,y0,0),_pt(x1,y0,0),_pt(x1,yc,28),_pt(x0,yc,28)],col.darkened(0.35))
	p.poly([_pt(x0,y1,0),_pt(x1,y1,0),_pt(x1,yc,28),_pt(x0,yc,28)],col)
	p.poly([_pt(x1,y0,0),_pt(x1,y1,0),_pt(x1,yc,28)],col.darkened(0.2))
	p.poly([_pt(x1,yc-0.2,0),_pt(x1,yc+0.2,0),_pt(x1,yc,16)],Color("15121a"))
	p.line(_pt(x0,yc,28),_pt(x1,yc,28),col.lightened(0.25),1.5)
	for k in 3: p.line(_pt(x0+0.4+k*0.55,y1,0),_pt(x0+0.4+k*0.55,yc,28),Color(0,0,0,0.15),1)

func _tv(pos: Vector2, z: float, seed_value: int) -> void:
	_box(pos.x,pos.y,0.22,0.2,z,z+18,Color("5a5048"),Color("3a3430"),Color("2a2622"))
	var f = _front_face(pos.x,pos.y,0.22,0.2,z,z+18)
	var screen = _sub(f,0.12,0.88,0.15,0.85)
	var mode = (seed_value+int(g.clock*0.5))%4
	if mode==0:
		p.poly(screen,Color("2a3aa0"))
		p.poly(_sub(screen,0.3,0.7,0.35,0.75),Color("ff9a3c"))
	else:
		p.poly(screen,Color(0.55,0.6,0.7))
		for k in 4:
			var v = fmod(g.clock*3+k*0.27+seed_value*0.1,1.0)
			p.line(_in(screen,0,v),_in(screen,1,v),Color(0.1,0.1,0.15,0.6),1.5)
	p.glow(_in(screen,0.5,0.5),18,Color(0.6,0.7,1,0.25))

func _tv_pile(pr: Dictionary, s: Vector2) -> void:
	_shadow(pr.pos,0.5,0.45)
	_tv(pr.pos+Vector2(-0.18,0.12),0,pr.seed)
	_tv(pr.pos+Vector2(0.2,-0.1),0,pr.seed+1)
	_tv(pr.pos+Vector2(0.0,0.02),18,pr.seed+2)
	_tv(pr.pos+Vector2(0.05,-0.02),36,pr.seed+3)

func _cart(pr: Dictionary, s: Vector2) -> void:
	var chrome = Color("b8bcc8")
	var a: float = pr.get("angle",0.0)
	var dir = Vector2.from_angle(a)*0.3
	var side = dir.orthogonal()*0.7
	var corners = [pr.pos-dir-side,pr.pos+dir-side,pr.pos+dir+side,pr.pos-dir+side]
	for q in corners: p.circle(g._project(q),2,Color("1a1a1e"))
	var bottom: Array = []
	var top: Array = []
	for q in corners:
		bottom.append(g._project(q,6))
		top.append(g._project(q,22))
	for i in 4:
		p.line(bottom[i],top[i],chrome,1)
		p.line(bottom[i],bottom[(i+1)%4],chrome,1)
		p.line(top[i],top[(i+1)%4],chrome,1.2)
	for k in 3: p.line(top[0].lerp(top[1],(k+1)/4.0),bottom[0].lerp(bottom[1],(k+1)/4.0),Color(chrome,0.5),1)

func _arcade(pr: Dictionary) -> void:
	var face: Vector2i = pr.face
	var col: Color = SCREEN_COLORS[pr.color%SCREEN_COLORS.size()]
	var body = Color("1a1426")
	_shadow(pr.pos,0.4,0.4)
	_box(pr.pos.x,pr.pos.y,0.32,0.3,0,44,body.lightened(0.15),body,body.darkened(0.2))
	var f = _front_face(pr.pos.x,pr.pos.y,0.32,0.3,0,44)
	var sd = _side_face(pr.pos.x,pr.pos.y,0.32,0.3,0,44)
	# Side art on both visible sides.
	p.poly(_sub(f,0.05,0.2,0.1,0.9),Color(col,0.7))
	p.poly(_sub(sd,0.8,0.95,0.1,0.9),Color(col,0.7))
	var screen_face: Array = []
	if face==Vector2i.DOWN: screen_face = f
	elif face==Vector2i.RIGHT: screen_face = sd
	if screen_face.is_empty(): return
	var screen = _sub(screen_face,0.18,0.82,0.55,0.8)
	if pr.broken:
		p.poly(screen,Color("0a0a10"))
		p.line(_in(screen,0.2,0.2),_in(screen,0.7,0.9),Color(0.8,0.9,1,0.35),1)
	else:
		p.poly(screen,col.darkened(0.55))
		var y = fmod(g.clock*0.7+pr.seed*0.01,1.0)
		p.poly(_sub(screen,0.15,0.35,y*0.6+0.1,y*0.6+0.3),col.lightened(0.3))
		p.poly(_sub(screen,0.6,0.85,0.2,0.35),Color("ffe45c"))
		p.glow(_in(screen,0.5,0.5),30,Color(col,0.35))
	var marquee = _sub(screen_face,0.1,0.9,0.86,0.98)
	p.poly(marquee,col.lightened(0.2) if not pr.broken else col.darkened(0.6))
	p.poly(_sub(screen_face,0.12,0.88,0.38,0.46),Color("2a2236"))
	p.circle(_in(screen_face,0.35,0.44),1.6,Color("ff3d6e"))
	p.circle(_in(screen_face,0.6,0.44),1.6,Color("3ff0ff"))

func _counter(pr: Dictionary) -> void:
	var half = pr.length/2.0
	_shadow(pr.pos,half+0.1,0.45,0.35)
	_box(pr.pos.x,pr.pos.y,half,0.4,0,20,Color("d8d4cc"),Color("c86a8a"),Color("9a4a6a"))
	var f = _front_face(pr.pos.x,pr.pos.y,half,0.4,0,20)
	p.line(_in(f,0,0.88),_in(f,1,0.88),Color("e8ecf4"),2)
	for k in int(pr.length): p.line(_in(f,(k+0.5)/pr.length,0.05),_in(f,(k+0.5)/pr.length,0.8),Color(0,0,0,0.15),1)
	for k in int(pr.length):
		var q = _pt(pr.pos.x-half+0.5+k,pr.pos.y-0.1,20)
		if k%2==0: _cyl_screen(q,3,7,Color("e8e4dc"))
		else: p.poly([q+Vector2(-4,0),q+Vector2(4,0),q+Vector2(3,-6),q+Vector2(-3,-6)],Color("d04a4a"))

func _cyl_screen(at: Vector2, r: float, h: float, color: Color) -> void:
	p.poly([at+Vector2(-r,0),at+Vector2(r,0),at+Vector2(r,-h),at+Vector2(-r,-h)],color.darkened(0.15))
	p.ellipse(at-Vector2(0,h),r,r*0.5,color,10)

func _booth(pr: Dictionary) -> void:
	var face: Vector2i = pr.face
	_shadow(pr.pos,0.45,0.45,0.3)
	var red = Color("b02a3a")
	_box(pr.pos.x,pr.pos.y,0.42,0.42,0,10,red.lightened(0.1),red,red.darkened(0.25))
	var back = pr.pos-Vector2(face)*0.32
	var hx = 0.42 if face.x==0 else 0.1
	var hy = 0.1 if face.x==0 else 0.42
	_box(back.x,back.y,hx,hy,10,28,red.lightened(0.15),red.darkened(0.05),red.darkened(0.3))
	var table = pr.pos+Vector2(face)*0.25
	p.line(g._project(table),g._project(table,16),Color("8a8e98"),2)
	p.ellipse(g._project(table,17),14,7,Color("e0dcd4"),14)

func _jukebox(pr: Dictionary) -> void:
	_shadow(pr.pos,0.4,0.35)
	_box(pr.pos.x,pr.pos.y,0.3,0.24,0,34,Color("6a3a2a"),Color("5a2e22"),Color("4a2418"))
	var top = g._project(pr.pos,34)
	for k in 5:
		var col: Color = SCREEN_COLORS[(k+int(g.clock*2))%5]
		p.ellipse_arc(top+Vector2(0,4),18-k*3,14-k*2.5,PI,TAU,col,2)
	p.glow(top,40,Color(1,0.5,0.9,0.3))

func _shelf(pr: Dictionary) -> void:
	var half = pr.length/2.0
	_shadow(pr.pos,0.4,half+0.1,0.35)
	_box(pr.pos.x,pr.pos.y,0.3,half,0,36,Color("5a4a3a"),Color("4a3a2e"),Color("3a2e24"))
	var sd = _side_face(pr.pos.x,pr.pos.y,0.3,half,0,36)
	for row in 3:
		var v0 = 0.1+row*0.3
		p.line(_in(sd,0,v0),_in(sd,1,v0),Color("2a2018"),1.5)
		var count = int(pr.length*6)
		for k in count:
			if (k*7+row*3+pr.seed)%5==0: continue
			var u0 = (k+0.1)/count; var u1 = (k+0.8)/count
			p.poly(_sub(sd,u0,u1,v0+0.02,v0+0.24),SCREEN_COLORS[(k+row+pr.seed)%5].darkened(0.25+0.1*(k%3)))

func _washer(pr: Dictionary) -> void:
	var face: Vector2i = pr.face
	_shadow(pr.pos,0.45,0.45,0.35)
	_box(pr.pos.x,pr.pos.y,0.36,0.36,0,24,Color("c8c8c0"),Color("aeaea6"),Color("909088"))
	var top = [_pt(pr.pos.x-0.36,pr.pos.y-0.36,24),_pt(pr.pos.x+0.36,pr.pos.y-0.36,24),_pt(pr.pos.x+0.36,pr.pos.y+0.36,24),_pt(pr.pos.x-0.36,pr.pos.y+0.36,24)]
	p.poly(_sub(top,0.1,0.9,0.05,0.3),Color("8a8e98"))
	p.circle(_in(top,0.7,0.18),1.5,Color("ff5470"))
	var f: Array = []
	if face==Vector2i.DOWN: f = _front_face(pr.pos.x,pr.pos.y,0.36,0.36,0,24)
	elif face==Vector2i.RIGHT: f = _side_face(pr.pos.x,pr.pos.y,0.36,0.36,0,24)
	if f.is_empty():
		# The back of the machine: a vent grille and a hose.
		var back = _side_face(pr.pos.x,pr.pos.y,0.36,0.36,0,24) if face.x!=0 else _front_face(pr.pos.x,pr.pos.y,0.36,0.36,0,24)
		for k in 4: p.line(_in(back,0.3,0.55+k*0.08),_in(back,0.7,0.55+k*0.08),Color(0,0,0,0.25),1)
		p.line(_in(back,0.2,0.3),_in(back,0.1,0.0),Color("3a3c44"),2)
		p.poly(_sub(back,0,1,0,0.08),Color(0,0,0,0.25))
		return
	var center = _in(f,0.5,0.45)
	p.ellipse(center,11,10,Color("8a8e98"),16)
	p.ellipse(center,8,7.5,Color("2a3a5a"),16)
	p.ellipse(center+Vector2(-2,-2),3,2,Color(1,1,1,0.3),8)
	p.poly(_sub(f,0.1,0.9,0.85,0.95),Color("6a6e78"))

func _mound(pr: Dictionary, t: Dictionary) -> void:
	var size: Vector2i = pr.get("size",Vector2i.ONE)
	_shadow(pr.pos,size.x*0.55,size.y*0.55,0.4)
	var seed_value: int = pr.seed
	for k in 6+size.x*size.y*2:
		var o = Vector2(((seed_value+k*37)%100)/100.0-0.5,((seed_value+k*61)%100)/100.0-0.5)*Vector2(size)*0.8
		var z = (1.0-o.length()/maxf(1,Vector2(size).length()*0.5))*18
		var q = g._project(pr.pos+o,z)
		var sz = 6+((seed_value+k*11)%7)
		p.block(q+Vector2(0,sz*0.5),sz,sz*0.6,t.rubble.lightened(0.15),t.rubble.darkened(0.1),t.rubble.lightened(0.3))
	for k in 2:
		var q = g._project(pr.pos+Vector2(0.1*k,-0.1),16)
		p.line(q,q+Vector2(6+k*4,-18),Color("8a5a3a"),1.5)

func _ruin_wall(pr: Dictionary, t: Dictionary) -> void:
	var along_x = pr.axis=="x"
	var hx = 0.95 if along_x else 0.14
	var hy = 0.14 if along_x else 0.95
	var height: float = pr.height
	_shadow(pr.pos,hx+0.1,hy+0.1,0.35)
	var brick = Color("6b3a30")
	_box(pr.pos.x,pr.pos.y,hx,hy,0,height,brick.lightened(0.15),brick,brick.darkened(0.25))
	var face = _front_face(pr.pos.x,pr.pos.y,hx,hy,0,height) if along_x else _side_face(pr.pos.x,pr.pos.y,hx,hy,0,height)
	for k in int(height/7): p.line(_in(face,0,(k+1)*7/height),_in(face,1,(k+1)*7/height),Color(0,0,0,0.22),1)
	p.poly(_sub(face,0.35,0.6,0.35,0.7),Color("0c0a10"))
	p.poly([_in(face,0.6,1),_in(face,0.75,0.78),_in(face,0.9,1)],Color("0c0a10"))

# --- The subway entrance --------------------------------------------------------------

func exit() -> void:
	var t = theme()
	var center: Vector2 = g.stairs
	var hx = 0.75; var hy = 1.0
	var hole = [_pt(center.x-hx,center.y-hy),_pt(center.x+hx,center.y-hy),_pt(center.x+hx,center.y+hy),_pt(center.x-hx,center.y+hy)]
	p.glow(g._project(center),110,Color(t.neon[1],0.12+sin(g.clock*2)*0.03))
	p.poly(hole,Color("06070c"))
	# Steps going down into the dark.
	for k in 7:
		var f = k/7.0
		var y = center.y-hy+f*2*hy
		var depth = f*34
		p.line(_pt(center.x-hx+0.05,y,-depth),_pt(center.x+hx-0.05,y,-depth),Color(0.5,0.55,0.65,0.5-f*0.45),2)
	p.poly(hole,Color(0,0,0,0),Color("8a8e9a"))
	# Railings on three sides.
	var rail = Color("2f6a4a")
	for side in [[Vector2(-hx,-hy),Vector2(hx,-hy)],[Vector2(-hx,-hy),Vector2(-hx,hy)],[Vector2(hx,-hy),Vector2(hx,hy)]]:
		var a: Vector2 = center+side[0]; var b: Vector2 = center+side[1]
		p.line(g._project(a,22),g._project(b,22),rail.lightened(0.2),2.5)
		p.line(g._project(a,12),g._project(b,12),rail,1.5)
		for k in 5:
			var q = a.lerp(b,k/4.0)
			p.line(g._project(q),g._project(q,22),rail,2)
	# Globe lamps and the neon sign.
	for o in [Vector2(-hx,hy),Vector2(hx,hy)]:
		var base = g._project(center+o)
		p.line(base,base-Vector2(0,54),Color("2a2c32"),3)
		p.circle(base-Vector2(0,58),6,Color("8affd8"))
		p.glow(base-Vector2(0,58),30,Color(0.5,1,0.85,0.5))
	var a = _pt(center.x-hx,center.y+hy,0)
	var b = _pt(center.x+hx,center.y+hy,0)
	var slope = (b.y-a.y)/(b.x-a.x)
	c.draw_set_transform_matrix(Transform2D(Vector2(1,slope),Vector2(0,1),a-Vector2(0,40)+shake))
	var span = b.x-a.x
	c.draw_rect(Rect2(-4,-20,span+8,22),p.ink(Color("0e1a22f0")))
	c.draw_rect(Rect2(-4,-20,span+8,22),p.ink(Color(t.neon[1],0.6)),false,1.5)
	var w = _text_width("SUBWAY",13)
	_neon_text("SUBWAY",Vector2((span-w)/2.0,-4),13,Color("3ff0ff"),_flicker(3.0,0.5))
	c.draw_set_transform(shake)
	for i in 6:
		var angle = g.clock*0.7+i
		p.circle(g._project(center)+Vector2(sin(angle)*18,-10+cos(angle*1.5)*12),1.5,Color("b4fff0"))

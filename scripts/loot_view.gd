extends RefCounted
## Loot on the ground: items pop out of enemies and chests, lie on the floor
## under a beam of light in their rarity color, and carry a readable name plate.
## Plates never overlap; hovering one shows the item's tooltip, clicking it
## sends the hero to pick it up.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")

const POP_TIME = 0.45
const BEAM_HEIGHTS = [0.0, 46.0, 84.0, 130.0, 180.0]
const LABEL_RANGE = 11.0

var g
var p
var art
var hovered_drop = null

func _init(game, painter, item_art) -> void:
	g = game
	p = painter
	art = item_art

## Where a drop is drawn this frame: flying out along an arc, then resting.
func drop_point(d: Dictionary) -> Vector3:
	var t = clampf(d.get("age", 1.0)/POP_TIME, 0, 1)
	var from: Vector2 = d.get("from", d.pos)
	var pos = from.lerp(d.pos, t)
	return Vector3(pos.x, pos.y, sin(t*PI)*30)

# --- In the world (zoomed) ------------------------------------------------------

func draw_drop(d: Dictionary, shake: Vector2) -> void:
	var at = drop_point(d)
	var pos = Vector2(at.x, at.y)
	var ground = g._project(pos)
	var landed = at.z<0.5
	var bob = sin(g.clock*3+d.pos.x)*2 if landed else 0.0
	p.ellipse(ground, 9, 3.5, Color(0, 0, 0, 0.4), 14)
	if d.kind=="gold":
		p.glow(ground-Vector2(0, 6+at.z), 18, Color(Data.GOLD, 0.25))
		art.draw("gold", ground-Vector2(0, 5+at.z+bob*0.5)+shake, 16, shake)
		return
	if d.kind=="potion":
		p.glow(ground-Vector2(0, 8+at.z), 18, Color(Data.HEALTH, 0.3))
		art.draw("potion", ground-Vector2(0, 9+at.z+bob)+shake, 15, shake)
		return
	var item = d.item
	var rarity = int(item.rarity)
	var color = Items.color(item)
	if landed:
		_beam(ground, color, rarity)
	p.glow(ground-Vector2(0, 8), 20+rarity*3, Color(color, 0.2+rarity*0.05))
	art.draw(item, ground-Vector2(0, 10+at.z+bob)+shake, 24, shake)

## A column of light: taller and brighter for rarer items, with a turning ring
## and rising motes for Epic and Legendary.
func _beam(ground: Vector2, color: Color, rarity: int) -> void:
	var height = BEAM_HEIGHTS[rarity]
	if height<=0: return
	var pulse = 0.85+sin(g.clock*4+ground.x)*0.15
	var segments = 8
	for i in segments:
		var t0 = float(i)/segments
		var t1 = float(i+1)/segments
		var w0 = lerpf(9, 3, t0)
		var w1 = lerpf(9, 3, t1)
		var a = (1-t0)*(0.3+rarity*0.06)*pulse
		p.poly([ground+Vector2(-w0, -height*t0), ground+Vector2(w0, -height*t0), ground+Vector2(w1, -height*t1), ground+Vector2(-w1, -height*t1)], Color(color, a))
	p.glow(ground-Vector2(0, height*0.35), height*0.45, Color(color, 0.08+rarity*0.03))
	p.line(ground, ground-Vector2(0, height*0.85), Color(color.lightened(0.5), 0.7*pulse), 1.8)
	p.ellipse(ground, 14, 6, Color(color, 0.18), 18)
	if rarity>=3:
		var spin = g.clock*2
		p.ellipse_arc(ground, 18, 8, spin, spin+PI*1.2, Color(color, 0.8), 1.5)
		p.ellipse_arc(ground, 18, 8, spin+PI, spin+PI*2.2, Color(color.lightened(0.4), 0.5), 1)
		for k in 6:
			var rise = fposmod(g.clock*0.5+k/6.0, 1.0)
			p.circle(ground+Vector2(sin(k*2.4+g.clock)*8, -rise*height*0.8), 1.4, Color(color.lightened(0.5), 1-rise))
	if rarity==4:
		for k in 4:
			var angle = g.clock*0.8+k*PI/2
			p.line(ground+Vector2(cos(angle), sin(angle)*0.5)*10, ground+Vector2(cos(angle), sin(angle)*0.5)*28, Color(color, 0.45), 2)

# --- On screen (name plates) -----------------------------------------------------

func _label(d: Dictionary) -> Dictionary:
	if d.kind=="gold": return {"text":"%d Gold" % int(d.value), "color":Data.GOLD, "size":11, "steps":0}
	if d.kind=="potion": return {"text":"Health Potion", "color":Color("ff8aa0"), "size":11, "steps":0}
	var steps = 0
	if not Items.is_gem(d.item) and int(d.item.level)<=int(g.player.level): steps = Items.upgrade_steps(d.item, g.player.equipment)
	return {"text":d.item.name, "color":Items.color(d.item), "size":13 if int(d.item.rarity)>=2 else 12, "steps":steps}

func draw_labels(ui) -> void:
	hovered_drop = null
	if g.state!="play": return
	var entries: Array = []
	for i in g.drops.size():
		var d = g.drops[i]
		if d.taken or not g.seen.has(Vector2i(d.pos)) or d.pos.distance_to(g.player.pos)>LABEL_RANGE: continue
		if d.get("age", 1.0)<POP_TIME*0.8: continue
		var info = _label(d)
		var font = ui.font_bold
		var text_width = ui.width(info.text, info.size, font)
		var extra = 14.0 if info.steps!=0 else 0.0
		var size = Vector2(text_width+18+extra, info.size+10)
		var anchor = g._to_screen(g._project(d.pos, 22 if d.kind=="item" else 14))
		var r = Rect2(anchor-Vector2(size.x/2, size.y+4), size)
		entries.append({"index":i, "drop":d, "info":info, "rect":r, "anchor":anchor})
	# Nearest plates keep their spot; the rest stack upward out of the way.
	entries.sort_custom(func(a, b): return a.anchor.y>b.anchor.y)
	var placed: Array = []
	for e in entries:
		var r: Rect2 = e.rect
		for attempt in 14:
			var clash = false
			for other in placed:
				if r.grow(1).intersects(other):
					r.position.y = other.position.y-r.size.y-3
					clash = true
			if not clash: break
		e.rect = r
		placed.append(r)
	for e in entries: _draw_plate(ui, e)

func _draw_plate(ui, e: Dictionary) -> void:
	var r: Rect2 = e.rect
	var info = e.info
	var hovered = r.has_point(g.pointer) and g.held==null
	if r.end.y<e.anchor.y-10: ui.line(Vector2(r.get_center().x, r.end.y), e.anchor+Vector2(0, -2), Color(info.color, 0.35), 1)
	ui.rect(r, Color("1a0d30f2") if hovered else Color("0b0616d8"))
	ui.rect(Rect2(r.position, Vector2(3, r.size.y)), info.color)
	ui.rect(r, Color(info.color, 0.9 if hovered else 0.4), false, 1)
	var rarity = int(e.drop.item.rarity) if e.drop.kind=="item" else 0
	if rarity>=3: ui.glow(r.get_center(), r.size.x*0.6, Color(info.color, 0.12))
	ui.text(info.text, Vector2(r.position.x+10, r.position.y+4), info.size, info.color.lightened(0.15) if hovered else info.color, ui.LEFT, ui.font_bold, 3, Color(0, 0, 0, 0.7))
	if info.steps!=0:
		var center = Vector2(r.end.x-10, r.get_center().y)
		var up = info.steps>0
		var d = -1.0 if up else 1.0
		ui.poly(PackedVector2Array([center+Vector2(0, 5*d), center+Vector2(-5, -2*d), center+Vector2(5, -2*d)]), Data.UPGRADE if up else Data.DOWNGRADE)
	if hovered: hovered_drop = e.drop
	g.buttons.append({"id":"loot:%d" % e.index, "rect":r})

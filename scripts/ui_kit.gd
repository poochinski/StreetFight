extends RefCounted
## The interface look shared by the HUD, panels, tooltips and menus: dungeon
## stone and brass crossed with an 80s vaporwave sunset (neon edges, chrome
## lettering, striped suns and perspective grids).

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const LEFT = 0
const CENTER = 1
const RIGHT = 2

var g
var p
var c: CanvasItem
var alpha = 1.0
var font_ui = SystemFont.new()
var font_bold = SystemFont.new()
var font_serif = SystemFont.new()
var font_italic = SystemFont.new()
var panel_fill: GradientTexture2D
var fade_down: GradientTexture2D
var fade_up: GradientTexture2D
var sky: GradientTexture2D

func _init(game, painter, canvas: CanvasItem) -> void:
	g = game
	p = painter
	c = canvas
	font_ui.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Inter", "Arial"])
	font_ui.font_weight = 500
	font_bold.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Inter", "Arial"])
	font_bold.font_weight = 700
	font_serif.font_names = PackedStringArray(["Georgia", "Liberation Serif", "Times New Roman"])
	font_serif.font_weight = 700
	font_italic.font_names = PackedStringArray(["Georgia", "Liberation Serif", "Times New Roman"])
	font_italic.font_italic = true
	panel_fill = p._gradient([Color("26114af4"), Color("140a28f6"), Color("0b0516fa")], false, Vector2.ZERO, Vector2(0, 1), [0.0, 0.55, 1.0])
	fade_down = p._gradient([Color(1, 1, 1, 0), Color.WHITE], false, Vector2.ZERO, Vector2(0, 1))
	fade_up = p._gradient([Color.WHITE, Color(1, 1, 1, 0)], false, Vector2.ZERO, Vector2(0, 1))
	sky = p._gradient([Color("12052a"), Color("3b0f5c"), Color("a1286f"), Color("ff7b54")], false, Vector2.ZERO, Vector2(0, 1), [0.0, 0.45, 0.8, 1.0])

func ink(color: Color) -> Color:
	return Color(color, color.a*alpha)

# --- Text ---------------------------------------------------------------------

func width(value: String, size: int, font: Font = null) -> float:
	if font==null: font = font_ui
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Draws text with its top edge at pos.y. Returns the text width.
func text(value: String, pos: Vector2, size: int, color: Color = Data.INK, align: int = LEFT, font: Font = null, outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.85)) -> float:
	if font==null: font = font_ui
	var w = width(value, size, font)
	var x = pos.x-(w/2 if align==CENTER else w if align==RIGHT else 0.0)
	var base = Vector2(x, pos.y+font.get_ascent(size))
	if outline>0: c.draw_string_outline(font, base, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ink(outline_color))
	c.draw_string(font, base, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink(color))
	return w

## Chrome lettering: a pink drop, a cyan fringe and a pale face, like an 80s logo.
func chrome(value: String, pos: Vector2, size: int, align: int = LEFT, font: Font = null) -> void:
	if font==null: font = font_bold
	var depth = maxf(1.0, size/14.0)
	text(value, pos+Vector2(depth, depth)*1.6, size, Color(Data.NEON_PINK, 0.9), align, font)
	text(value, pos+Vector2(-depth*0.8, 0), size, Color(Data.NEON_CYAN, 0.55), align, font)
	text(value, pos, size, Data.CHROME, align, font, 0)
	# A thin horizon line cuts through the lower letters, like airbrushed chrome.
	var w = width(value, size, font)
	var x = pos.x-(w/2 if align==CENTER else w if align==RIGHT else 0.0)
	var y = pos.y+font.get_ascent(size)*0.72
	c.draw_line(Vector2(x, y), Vector2(x+w, y), ink(Color(Data.NEON_PURPLE, 0.35)), maxf(1, size/18.0))

## Text with a soft neon halo.
func neon(value: String, pos: Vector2, size: int, color: Color, align: int = LEFT, font: Font = null) -> void:
	if font==null: font = font_bold
	text(value, pos, size, color, align, font, maxi(4, size/3), Color(color, 0.22))
	text(value, pos, size, color.lightened(0.25), align, font)

# --- Shapes -------------------------------------------------------------------

func rect(r: Rect2, color: Color, filled: bool = true, line_width: float = 1.0) -> void:
	if filled: c.draw_rect(r, ink(color))
	else: c.draw_rect(r, ink(color), false, line_width)

func line(a: Vector2, b: Vector2, color: Color, line_width: float = 1.0) -> void:
	c.draw_line(a, b, ink(color), line_width, true)

func poly(points: PackedVector2Array, color: Color) -> void:
	c.draw_colored_polygon(points, ink(color))

func circle(center: Vector2, radius: float, color: Color) -> void:
	c.draw_circle(center, radius, ink(color))

func ring(center: Vector2, radius: float, color: Color, line_width: float = 1.0, start: float = 0.0, end: float = TAU) -> void:
	c.draw_arc(center, radius, start, end, maxi(24, int(radius*1.2)), ink(color), line_width, true)

func glow(center: Vector2, radius: float, color: Color) -> void:
	c.draw_texture_rect(p.glow_texture, Rect2(center-Vector2.ONE*radius, Vector2.ONE*radius*2), false, ink(color))

func gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	c.draw_rect(r, ink(top))
	c.draw_texture_rect(fade_down, r, false, ink(bottom))

## Clips a segment to the vertical band left..right, so grid lines stay inside a panel.
func _clip_x(a: Vector2, b: Vector2, left: float, right: float) -> Array:
	var t0 = 0.0
	var t1 = 1.0
	var dx = b.x-a.x
	if absf(dx)<0.0001:
		return [a, b] if a.x>=left and a.x<=right else []
	for edge in [[left, -1.0], [right, 1.0]]:
		var t = (edge[0]-a.x)/dx
		if edge[1]*dx>0: t1 = minf(t1, t)
		else: t0 = maxf(t0, t)
	if t0>t1: return []
	return [a.lerp(b, t0), a.lerp(b, t1)]

## A perspective grid floor receding to a horizon at the top of r.
func grid(r: Rect2, color: Color, scroll: float = 0.0, columns: int = 18) -> void:
	var center = r.position.x+r.size.x/2
	var spread = r.size.x*2.2
	for i in range(-columns, columns+1):
		var top = Vector2(center+i*r.size.x/columns*0.35, r.position.y)
		var bottom = Vector2(center+i*spread/columns, r.end.y)
		var clipped = _clip_x(top, bottom, r.position.x, r.end.x)
		if not clipped.is_empty(): line(clipped[0], clipped[1], color, 1)
	for k in 9:
		var t = fposmod(k/9.0+scroll, 1.0)
		var y = r.position.y+r.size.y*t*t
		line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(color, color.a*(0.3+t)), 1)

## A striped synthwave sun: yellow at the top fading to pink, cut by bands below the middle.
## stripe_from: where the bands start, from -1 (top) to 1 (bottom).
func sun(center: Vector2, radius: float, stripes: bool = true, cut: float = 1.0, stripe_from: float = 0.05) -> void:
	var rows = int(radius*2)
	for i in rows:
		var y = -radius+i+0.5
		if y>radius*cut: break
		if stripes and y>radius*stripe_from:
			var band = (y-radius*stripe_from)/(radius*(1-stripe_from))
			if fposmod(y, radius*0.22)<radius*0.22*(0.12+band*0.55): continue
		var half = sqrt(maxf(0, radius*radius-y*y))
		var t = (y+radius)/(radius*2)
		var color = Data.SUN_YELLOW.lerp(Data.SUNSET, clampf(t*1.6, 0, 1)) if t<0.62 else Data.SUNSET.lerp(Data.NEON_PINK, clampf((t-0.62)/0.38, 0, 1))
		c.draw_line(center+Vector2(-half, y), center+Vector2(half, y), ink(color), 1.15)

# --- Frames -------------------------------------------------------------------

## A panel: deep violet glass, a perspective grid in its lower part, a stone and
## neon frame with brass rivets, and an optional sun crest over the top edge.
func panel(r: Rect2, crest: bool = false) -> void:
	rect(r.grow(8), Color(0, 0, 0, 0.32))
	rect(r.grow(3), Color(0, 0, 0, 0.4))
	c.draw_texture_rect(panel_fill, r, false, ink(Color.WHITE))
	var floor_height = r.size.y*0.3
	grid(Rect2(r.position.x+6, r.end.y-floor_height, r.size.x-12, floor_height-6), Color(Data.NEON_CYAN, 0.06), g.clock*0.04)
	c.draw_texture_rect(fade_up, Rect2(r.position+Vector2(6, 6), Vector2(r.size.x-12, 70)), false, ink(Color(Data.NEON_PURPLE, 0.18)))
	frame(r)
	if crest: sun_crest(Vector2(r.get_center().x, r.position.y+2), 30)

func frame(r: Rect2, accent: Color = Data.NEON_CYAN) -> void:
	rect(r, Color("06030c"), false, 4)
	rect(r.grow(-3), Color(Data.PANEL_EDGE, 0.95), false, 1.5)
	rect(r.grow(-6), Color(Data.NEON_PINK, 0.22), false, 1)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point = r.position+r.size*corner
		var sx = 1.0 if corner.x==0 else -1.0
		var sy = 1.0 if corner.y==0 else -1.0
		line(point+Vector2(sx*1, sy*1), point+Vector2(sx*20, sy*1), accent, 2)
		line(point+Vector2(sx*1, sy*1), point+Vector2(sx*1, sy*20), accent, 2)
		rivet(point+Vector2(sx*11, sy*11))

func rivet(point: Vector2) -> void:
	circle(point, 3, Color("1a1020"))
	circle(point, 2.2, Color("b8925a"))
	circle(point+Vector2(-0.6, -0.6), 0.9, Color("f4dca0"))

## The emblem that sits on a panel's top edge: a brass plate holding a striped sun.
func sun_crest(center: Vector2, radius: float) -> void:
	var plate = PackedVector2Array()
	for i in 13:
		var angle = PI+i*PI/12
		plate.append(center+Vector2(cos(angle)*(radius+10), sin(angle)*(radius+6)))
	plate.append(center+Vector2(radius+22, 8))
	plate.append(center+Vector2(-radius-22, 8))
	poly(plate, Color("1a0e24"))
	for side in [-1, 1]:
		poly(PackedVector2Array([center+Vector2(side*(radius+6), -4), center+Vector2(side*(radius+30), 6), center+Vector2(side*(radius+4), 8)]), Color("8a6a3c"))
	sun(center+Vector2(0, -4), radius-4, true, 0.3)
	ring(center+Vector2(0, -4), radius+2, Color("c79a52"), 2.5, PI, TAU)
	ring(center+Vector2(0, -4), radius+5, Color(Data.NEON_CYAN, 0.7), 1, PI, TAU)
	circle(center+Vector2(0, -radius-6), 3.5, Data.NEON_CYAN)
	circle(center+Vector2(0, -radius-6), 1.5, Color.WHITE)

## An inset title plate with chrome lettering.
func plate(r: Rect2, label: String, size: int = 18) -> void:
	rect(r, Color("0a0514e6"))
	rect(r, Color(Data.PANEL_EDGE, 0.9), false, 1)
	line(r.position+Vector2(8, r.size.y-1), Vector2(r.end.x-8, r.end.y-1), Color(Data.NEON_PINK, 0.6), 1)
	chrome(label, Vector2(r.get_center().x, r.position.y+(r.size.y-size*1.25)/2), size, CENTER)

## An inventory slot framed in its item's rarity color.
func slot(r: Rect2, item, hovered: bool = false, highlight: Color = Color.TRANSPARENT) -> void:
	var rarity = int(item.rarity) if item else -1
	var color: Color = Items.color(item) if item else Color("4b3a6c")
	rect(r, Color("0b0716"))
	if item:
		c.draw_texture_rect(fade_down, r, false, ink(Color(color, 0.32 if rarity>0 else 0.14)))
	rect(r.grow(-2), Color(1, 1, 1, 0.03), false, 1)
	if rarity==4:
		var pulse = 0.5+sin(g.clock*3)*0.5
		glow(r.get_center(), r.size.x*0.9, Color(color, 0.12+pulse*0.12))
	rect(r, Color(color, 0.95 if rarity>0 else 0.55), false, 2.0 if rarity>0 else 1.0)
	if highlight.a>0:
		rect(r.grow(2), highlight, false, 2)
		glow(r.get_center(), r.size.x*0.8, Color(highlight, 0.18))
	if hovered:
		rect(r.grow(1), Color(1, 1, 1, 0.75), false, 1)

## A bar with a glossy fill: health, mana, experience.
func bar(r: Rect2, fraction: float, fill: Color, label: String = "", label_size: int = 11) -> void:
	rect(r, Color("07040d"))
	var inner = r.grow(-2)
	var filled = Rect2(inner.position, Vector2(inner.size.x*clampf(fraction, 0, 1), inner.size.y))
	if filled.size.x>0:
		gradient_rect(filled, fill.lightened(0.25), fill.darkened(0.35))
		rect(Rect2(filled.position, Vector2(filled.size.x, filled.size.y*0.4)), Color(1, 1, 1, 0.16))
		line(Vector2(filled.end.x, filled.position.y), Vector2(filled.end.x, filled.end.y), Color(1, 1, 1, 0.5), 1)
	rect(r, Color(Data.PANEL_EDGE, 0.95), false, 1)
	if label!="": text(label, Vector2(r.get_center().x, r.position.y+(r.size.y-label_size*1.2)/2), label_size, Data.CHROME, CENTER, font_bold, 3)

## A neon button registered for clicks. primary buttons glow pink.
func button(id: String, r: Rect2, label: String, primary: bool = false, size: int = 13) -> void:
	var hovered = r.has_point(g.pointer)
	if primary:
		gradient_rect(r, Data.NEON_PINK.lightened(0.15 if hovered else 0.0), Data.NEON_PURPLE.darkened(0.2))
		rect(r, Color(1, 1, 1, 0.75 if hovered else 0.45), false, 1)
		if hovered: glow(r.get_center(), r.size.x*0.7, Color(Data.NEON_PINK, 0.25))
		text(label, Vector2(r.get_center().x, r.position.y+(r.size.y-size*1.25)/2), size, Color.WHITE, CENTER, font_bold, 3, Color("4a0d3cb0"))
	else:
		rect(r, Color("2a1648") if hovered else Color("120a22e6"))
		rect(r, Data.NEON_CYAN if hovered else Color(Data.NEON_CYAN, 0.35), false, 1)
		text(label, Vector2(r.get_center().x, r.position.y+(r.size.y-size*1.25)/2), size, Data.CHROME if hovered else Data.INK, CENTER, font_bold)
	g.buttons.append({"id":id, "rect":r})

func close_button(id: String, r: Rect2) -> void:
	var hovered = r.has_point(g.pointer)
	gradient_rect(r, Color("ff5a8a") if hovered else Color("d93a6e"), Color("7a1240"))
	rect(r, Color("ffd0e4"), false, 1)
	var m = r.size.x*0.28
	line(r.position+Vector2(m, m), r.end-Vector2(m, m), Color.WHITE, 2.5)
	line(Vector2(r.end.x-m, r.position.y+m), Vector2(r.position.x+m, r.end.y-m), Color.WHITE, 2.5)
	g.buttons.append({"id":id, "rect":r})

## The small round plus button for spending stat points.
func plus_button(id: String, r: Rect2, enabled: bool) -> void:
	var hovered = enabled and r.has_point(g.pointer)
	rect(r, Color("2a1648") if hovered else Color("100820"))
	rect(r, Data.UPGRADE if enabled else Color(Data.INK_MUTED, 0.4), false, 1)
	var color = Data.UPGRADE if enabled else Color(Data.INK_MUTED, 0.4)
	var center = r.get_center()
	line(center-Vector2(5, 0), center+Vector2(5, 0), color, 2)
	line(center-Vector2(0, 5), center+Vector2(0, 5), color, 2)
	if enabled: g.buttons.append({"id":id, "rect":r})

# --- Icons --------------------------------------------------------------------

## Simple line icons for stats and HUD buttons, drawn in a size x size box.
func icon(kind: String, center: Vector2, size: float, color: Color) -> void:
	var s = size/24.0
	match kind:
		"strength":
			line(center+Vector2(-7, 8)*s, center+Vector2(7, -8)*s, color, 3*s)
			line(center+Vector2(-9, 2)*s, center+Vector2(-2, 9)*s, color, 2.5*s)
			poly(PackedVector2Array([center+Vector2(5, -10)*s, center+Vector2(10, -10)*s, center+Vector2(10, -5)*s]), color)
		"dexterity":
			var feather = PackedVector2Array([center+Vector2(-8, 9)*s, center+Vector2(-2, -2)*s, center+Vector2(9, -10)*s, center+Vector2(4, 1)*s])
			poly(feather, Color(color, 0.85))
			line(center+Vector2(-9, 10)*s, center+Vector2(6, -6)*s, Color("1a0e24"), 1.4*s)
		"focus":
			var eye = PackedVector2Array()
			for i in 24:
				var a = i*TAU/24
				eye.append(center+Vector2(cos(a)*10, sin(a)*5.5)*s)
			poly(eye, color)
			circle(center, 4*s, Color("1a0e24"))
			circle(center, 2*s, Data.NEON_CYAN)
		"vitality":
			var shield = PackedVector2Array([center+Vector2(-9, -9)*s, center+Vector2(9, -9)*s, center+Vector2(8, 2)*s, center+Vector2(0, 10)*s, center+Vector2(-8, 2)*s])
			poly(shield, color)
			line(center+Vector2(0, -6)*s, center+Vector2(0, 5)*s, Color("1a0e24"), 3*s)
			line(center+Vector2(-5, -1)*s, center+Vector2(5, -1)*s, Color("1a0e24"), 3*s)
		"character":
			circle(center+Vector2(0, -5)*s, 5*s, color)
			poly(PackedVector2Array([center+Vector2(-9, 10)*s, center+Vector2(-7, 2)*s, center+Vector2(7, 2)*s, center+Vector2(9, 10)*s]), color)
		"inventory":
			poly(PackedVector2Array([center+Vector2(-9, -3)*s, center+Vector2(9, -3)*s, center+Vector2(8, 10)*s, center+Vector2(-8, 10)*s]), color)
			ring(center+Vector2(0, -4)*s, 5*s, color, 2*s, PI, TAU)
			rect(Rect2(center+Vector2(-3, 0)*s, Vector2(6, 3)*s), Color("1a0e24"))
		"map":
			poly(PackedVector2Array([center+Vector2(-10, -7)*s, center+Vector2(-3, -9)*s, center+Vector2(3, -7)*s, center+Vector2(10, -9)*s, center+Vector2(10, 7)*s, center+Vector2(3, 9)*s, center+Vector2(-3, 7)*s, center+Vector2(-10, 9)*s]), color)
			line(center+Vector2(-3, -9)*s, center+Vector2(-3, 7)*s, Color("1a0e24"), 1.5*s)
			line(center+Vector2(3, -7)*s, center+Vector2(3, 9)*s, Color("1a0e24"), 1.5*s)
		"sound":
			poly(PackedVector2Array([center+Vector2(-9, -3)*s, center+Vector2(-4, -3)*s, center+Vector2(2, -9)*s, center+Vector2(2, 9)*s, center+Vector2(-4, 3)*s, center+Vector2(-9, 3)*s]), color)
			if g.synth and g.synth.enabled:
				ring(center+Vector2(2, 0)*s, 6*s, color, 1.6*s, -0.9, 0.9)
				ring(center+Vector2(2, 0)*s, 10*s, color, 1.6*s, -0.9, 0.9)
			else:
				line(center+Vector2(5, -5)*s, center+Vector2(11, 5)*s, Data.DOWNGRADE, 2*s)
				line(center+Vector2(11, -5)*s, center+Vector2(5, 5)*s, Data.DOWNGRADE, 2*s)
		"settings":
			ring(center, 6*s, color, 3*s)
			for i in 8:
				var dir = Vector2.from_angle(i*TAU/8)
				line(center+dir*6*s, center+dir*10*s, color, 3*s)
		"pause":
			rect(Rect2(center+Vector2(-6, -8)*s, Vector2(4, 16)*s), color)
			rect(Rect2(center+Vector2(2, -8)*s, Vector2(4, 16)*s), color)
		"gold":
			for k in 3:
				var o = center+Vector2(-4+k*4, 4-k*3)*s
				c.draw_circle(o, 5*s, ink(Color("8a5a1a")))
				c.draw_circle(o+Vector2(0, -1)*s, 5*s, ink(Color("ffcf4a")))
				c.draw_circle(o+Vector2(-1.5, -2.5)*s, 1.5*s, ink(Color("fff2b0")))

extends RefCounted
## Item icons for bag slots, equipment slots, tooltips and loot on the ground.
## Each icon is drawn in a 40x40 box around its center, then scaled to fit.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")

const STEEL = [Color("6f6a66"), Color("8d959a"), Color("aab4bb"), Color("d0d8e2"), Color("b8f6ff")]
const LEATHER = [Color("5e4330"), Color("6b4a32"), Color("7a5a40"), Color("8a6446"), Color("9a7050")]
const METALS = [Color("c27a45"), Color("c9ced6"), Color("ffcf4a"), Color("e6ecf5"), Color("ff9be8")]

var g
var p
var characters

func _init(game, painter, character_art) -> void:
	g = game
	p = painter
	characters = character_art

func _tier(item) -> int:
	return clampi((int(item.get("level", 1))-1)/3, 0, 4)

## Draws an item (or "potion"/"gold") centered at center, size pixels across.
## restore is the canvas offset to put back afterwards (the world's shake offset).
func draw(item, center: Vector2, size: float, restore: Vector2 = Vector2.ZERO) -> void:
	var canvas = p.canvas
	canvas.draw_set_transform(center, 0, Vector2.ONE*size/40.0)
	if item is String:
		if item=="potion": _potion()
		else: _gold()
	else:
		match item.slot:
			"weapon": _weapon(item)
			"helmet": _helmet(item)
			"chest": _chest(item)
			"gloves": _gloves(item)
			"boots": _boots(item)
			"belt": _belt(item)
			"ring": _ring(item)
			"amulet": _amulet(item)
			"gem": gem(item.gem, int(item.tier), Vector2.ZERO, 1.0)
	canvas.draw_set_transform(restore)

func _weapon(item) -> void:
	var look = Items.weapon_look(item)
	if int(item.rarity)>=2: p.glow(Vector2.ZERO, 22, Color(look.glow, 0.18))
	characters.draw_weapon(Vector2(-9, 9), Vector2(13, -13), look, int(item.rarity), false)

func _trim(item) -> Color:
	return Items.color(item) if int(item.rarity)>=1 else Color("c9a45c")

func _helmet(item) -> void:
	var steel: Color = STEEL[_tier(item)]
	var style = item.get("style", "helm")
	var dome = []
	for i in 13:
		var a = PI+i*PI/12
		dome.append(Vector2(cos(a)*13, sin(a)*15+4))
	if style=="coif":
		dome.append(Vector2(12, 14)); dome.append(Vector2(-12, 14))
		p.poly(dome, steel.darkened(0.15))
		for row in 5:
			for col in 7:
				var point = Vector2(-9+col*3+(row%2)*1.5, -7+row*4)
				if point.length()<13: p.circle(point, 0.9, steel.lightened(0.3))
		p.ellipse(Vector2(0, 5), 6.5, 8, Color("1a1020"), 18)
		p.ellipse(Vector2(0, 5), 4.5, 6, Color("d9ad86"), 18)
	elif style=="visor":
		p.poly(dome, steel.lightened(0.2))
		p.poly([Vector2(-13, 4), Vector2(-13, 0), Vector2(-6, -11), Vector2(-4, -2), Vector2(-6, 4)], steel.darkened(0.2))
		p.poly([Vector2(-12, -1), Vector2(12, -1), Vector2(11, 4), Vector2(-11, 4)], Color("12081e"))
		p.line(Vector2(-10, 1.5), Vector2(10, 1.5), Data.NEON_CYAN, 2)
		p.glow(Vector2(0, 1.5), 14, Color(Data.NEON_CYAN, 0.35))
		p.poly([Vector2(-2, -11), Vector2(2, -11), Vector2(1, -18), Vector2(-1, -18)], _trim(item))
		p.poly([Vector2(-13, 4), Vector2(13, 4), Vector2(11, 10), Vector2(-11, 10)], steel.darkened(0.3))
	else:
		var plume = _trim(item) if int(item.rarity)>=2 else Color("c23b45")
		p.poly([Vector2(-1, -10), Vector2(5, -14), Vector2(-4, -19), Vector2(-15, -14), Vector2(-11, -9)], plume)
		p.poly([Vector2(-1, -10), Vector2(-8, -17), Vector2(-14, -14)], plume.lightened(0.25))
		p.poly(dome, steel)
		p.poly([Vector2(-13, 4), Vector2(-13, -2), Vector2(-7, -10), Vector2(-5, 4)], steel.darkened(0.25))
		p.poly([Vector2(-1.5, -2), Vector2(1.5, -2), Vector2(1, 12), Vector2(-1, 12)], steel.darkened(0.35))
		p.poly([Vector2(-13, 4), Vector2(-5, 4), Vector2(-6, 12), Vector2(-12, 10)], steel.darkened(0.15))
		p.poly([Vector2(13, 4), Vector2(5, 4), Vector2(6, 12), Vector2(12, 10)], steel.darkened(0.1))
		p.line(Vector2(-12, 0), Vector2(12, 0), steel.lightened(0.35), 1.2)
	if int(item.rarity)>=2: p.line(Vector2(-12, 3.5), Vector2(12, 3.5), _trim(item), 1.4)

func _chest(item) -> void:
	var look = Items.armor_look(item)
	var kind = item.get("look", "leather")
	if kind=="mantle":
		p.poly([Vector2(-10, -14), Vector2(10, -14), Vector2(14, 16), Vector2(-14, 16)], look.cloak)
		p.poly([Vector2(-10, -14), Vector2(-3, -14), Vector2(-6, 16), Vector2(-14, 16)], look.cloak.darkened(0.3))
	var body = [Vector2(-15, -11), Vector2(-6, -15), Vector2(6, -15), Vector2(15, -11), Vector2(16, -2), Vector2(11, 0), Vector2(10, 15), Vector2(-10, 15), Vector2(-11, 0), Vector2(-16, -2)]
	p.poly(body, look.plate)
	p.poly([Vector2(-15, -11), Vector2(-6, -15), Vector2(-3, -15), Vector2(-5, 15), Vector2(-10, 15), Vector2(-11, 0), Vector2(-16, -2)], look.shade)
	p.poly([Vector2(-4, -15), Vector2(4, -15), Vector2(0, -8)], Color("1a1020"))
	if kind=="mail":
		for row in 6:
			for col in 6:
				var point = Vector2(-8+col*3.3+(row%2)*1.6, -6+row*3.4)
				p.ellipse_arc(point, 1.6, 1.2, 0, PI, look.plate.lightened(0.3), 0.8)
	elif kind=="plate":
		p.ellipse_arc(Vector2(0, -2), 9, 7, PI*1.1, PI*1.9, look.plate.lightened(0.4), 1.5)
		p.line(Vector2(0, -8), Vector2(0, 9), look.shade.darkened(0.2), 1)
	else:
		for y in [-4, 2, 8]: p.line(Vector2(-9, y), Vector2(9, y), look.shade.darkened(0.2), 0.8)
	p.poly([Vector2(-10, 8), Vector2(10, 8), Vector2(10, 11), Vector2(-10, 11)], Color("3a2618"))
	p.poly([Vector2(-2, 7.5), Vector2(2, 7.5), Vector2(2, 11.5), Vector2(-2, 11.5)], look.trim)
	p.ellipse(Vector2(-13, -9), 5, 4, look.plate.lightened(0.15), 14)
	p.ellipse(Vector2(13, -9), 5, 4, look.plate.lightened(0.15), 14)
	p.ellipse_arc(Vector2(13, -9), 5, 4, PI, TAU, look.trim, 1.2)
	p.ellipse_arc(Vector2(-13, -9), 5, 4, PI, TAU, look.trim, 1.2)

func _gloves(item) -> void:
	var gauntlet = item.get("style", "gloves")=="gauntlets"
	var color: Color = STEEL[_tier(item)] if gauntlet else LEATHER[_tier(item)]
	for i in 4:
		var x = -7+i*4.6
		p.limb(Vector2(x, -2), Vector2(x+0.5, -14+absf(i-1.5)*2), 4, color.lightened(0.08*i))
	p.limb(Vector2(-9, 4), Vector2(-15, -3), 4.4, color.darkened(0.1))
	p.poly([Vector2(-10, -4), Vector2(9, -4), Vector2(9, 8), Vector2(-9, 8)], color)
	if gauntlet:
		for i in 4: p.circle(Vector2(-7+i*4.6, -3), 1.6, color.lightened(0.35))
	p.poly([Vector2(-11, 8), Vector2(11, 8), Vector2(12, 16), Vector2(-12, 16)], color.darkened(0.25))
	p.line(Vector2(-11, 9), Vector2(11, 9), _trim(item), 1.5)

func _boots(item) -> void:
	var greaves = item.get("style", "boots")=="greaves"
	var color: Color = STEEL[_tier(item)] if greaves else LEATHER[_tier(item)]
	p.poly([Vector2(-8, -15), Vector2(4, -15), Vector2(5, 4), Vector2(14, 7), Vector2(15, 13), Vector2(-8, 13)], color)
	p.poly([Vector2(-8, -15), Vector2(-3, -15), Vector2(-3, 13), Vector2(-8, 13)], color.darkened(0.2))
	p.poly([Vector2(-9, 11), Vector2(16, 11), Vector2(16, 15), Vector2(-9, 15)], Color("24160e"))
	p.poly([Vector2(-9, -16), Vector2(5, -16), Vector2(5, -11), Vector2(-9, -11)], color.darkened(0.3))
	p.line(Vector2(-9, -12), Vector2(5, -12), _trim(item), 1.4)
	if greaves:
		p.ellipse(Vector2(-1, -3), 5, 4, color.lightened(0.3), 14)
		p.line(Vector2(-6, 4), Vector2(4, 4), color.lightened(0.4), 1)
	else:
		for y in [-8, -4, 0]: p.line(Vector2(-3, y), Vector2(3, y+1), Color("e8d8b0"), 0.8)

func _belt(item) -> void:
	var color: Color = LEATHER[_tier(item)]
	if item.get("style", "belt")=="sash":
		color = Data.NEON_PURPLE.darkened(0.3).lerp(Items.color(item), 0.3)
		p.poly([Vector2(-17, -5), Vector2(17, -5), Vector2(16, 3), Vector2(-16, 3)], color)
		p.poly([Vector2(2, 0), Vector2(8, 15), Vector2(4, 16), Vector2(0, 2)], color.darkened(0.2))
		p.poly([Vector2(-2, 0), Vector2(-7, 14), Vector2(-3, 15), Vector2(0, 2)], color.darkened(0.1))
		p.circle(Vector2(0, -1), 3.5, color.lightened(0.2))
	else:
		p.poly([Vector2(-18, -6), Vector2(18, -6), Vector2(17, 3), Vector2(-17, 3)], color)
		p.line(Vector2(-17, -4), Vector2(17, -4), color.lightened(0.25), 1)
		p.poly([Vector2(-5, -9), Vector2(5, -9), Vector2(5, 6), Vector2(-5, 6)], Color("b8925a"))
		p.poly([Vector2(-3, -7), Vector2(3, -7), Vector2(3, 4), Vector2(-3, 4)], Color("1a1020"))
		p.circle(Vector2(0, -1.5), 2.2, _trim(item))
		for x in [-12, -8, 8, 12]: p.circle(Vector2(x, -1.5), 1, Color("e8d8b0"))

func _ring(item) -> void:
	var metal: Color = METALS[_tier(item)]
	p.ellipse(Vector2(0, 4), 13, 9, metal.darkened(0.3), 28)
	p.ellipse(Vector2(0, 3), 13, 9, metal, 28)
	p.ellipse(Vector2(0, 5), 8.5, 5.5, Color("0b0716"), 24)
	p.ellipse_arc(Vector2(0, 3), 12, 8, PI*1.1, PI*1.6, Color(1, 1, 1, 0.6), 1.2)
	if item.get("style", "ring")=="band":
		p.ellipse_arc(Vector2(0, 3), 10.5, 7, 0.2, PI-0.2, Items.color(item), 1.4)
		return
	var stone = Items.color(item) if int(item.rarity)>0 else Color("ff3b5c")
	p.poly([Vector2(-6, -6), Vector2(6, -6), Vector2(4, -1), Vector2(-4, -1)], metal.darkened(0.2))
	p.poly([Vector2(-5, -6), Vector2(0, -13), Vector2(5, -6), Vector2(0, -2)], stone)
	p.poly([Vector2(-5, -6), Vector2(0, -13), Vector2(0, -6)], stone.lightened(0.35))
	p.glow(Vector2(0, -7), 10, Color(stone, 0.4))
	p.circle(Vector2(-1.5, -9), 0.9, Color.WHITE)

func _amulet(item) -> void:
	var metal: Color = METALS[_tier(item)]
	for i in 9:
		var t = i/8.0
		p.circle(Vector2(lerpf(-12, 0, t), lerpf(-16, 0, t)), 1.1, metal)
		p.circle(Vector2(lerpf(12, 0, t), lerpf(-16, 0, t)), 1.1, metal)
	var stone = Items.color(item) if int(item.rarity)>0 else Data.NEON_CYAN
	if item.get("style", "amulet")=="talisman":
		p.circle(Vector2(0, 7), 8, metal.darkened(0.2))
		p.circle(Vector2(0, 7), 6.5, Color("1a0e24"))
		# A tiny striped sunset sun.
		for i in 11:
			var y = -5.5+i
			if y>0.5 and i%2==1: continue
			var half = sqrt(maxf(0, 30.25-y*y))
			p.line(Vector2(-half, 7+y), Vector2(half, 7+y), Data.SUN_YELLOW.lerp(Data.NEON_PINK, i/10.0), 1.1)
	else:
		p.poly([Vector2(0, 0), Vector2(7, 7), Vector2(0, 16), Vector2(-7, 7)], metal.darkened(0.25))
		p.poly([Vector2(0, 2), Vector2(5, 7), Vector2(0, 13), Vector2(-5, 7)], stone)
		p.poly([Vector2(0, 2), Vector2(5, 7), Vector2(0, 7)], stone.lightened(0.4))
		p.glow(Vector2(0, 7), 12, Color(stone, 0.4))

## A cut gem; tier makes it bigger and brighter.
func gem(kind: String, tier: int, center: Vector2, scale: float) -> void:
	var color: Color = Items.GEMS[kind].color
	var s = [0.62, 0.8, 1.0][clampi(tier, 0, 2)]*scale
	var outline: Array = []
	match kind:
		"ruby":
			for i in 6: outline.append(center+Vector2.from_angle(i*TAU/6+PI/6)*13*s)
		"sapphire":
			outline = [center+Vector2(0, -15)*s, center+Vector2(10, 2)*s, center+Vector2(0, 14)*s, center+Vector2(-10, 2)*s]
		"emerald":
			outline = [center+Vector2(-7, -13)*s, center+Vector2(7, -13)*s, center+Vector2(11, -8)*s, center+Vector2(11, 8)*s, center+Vector2(7, 13)*s, center+Vector2(-7, 13)*s, center+Vector2(-11, 8)*s, center+Vector2(-11, -8)*s]
		"amethyst":
			outline = [center+Vector2(-12, -5)*s, center+Vector2(-6, -12)*s, center+Vector2(6, -12)*s, center+Vector2(12, -5)*s, center+Vector2(0, 14)*s]
		_:
			for i in 10: outline.append(center+Vector2.from_angle(i*TAU/10)*12*s)
	if tier>=1: p.glow(center, 22*s, Color(color, 0.25+tier*0.12))
	p.poly(outline, color.darkened(0.35))
	var inner: Array = []
	for point in outline: inner.append(center+(point-center)*0.62)
	p.poly(inner, color)
	for i in outline.size():
		p.line(outline[i], inner[i], color.lightened(0.3), 0.8)
	p.poly([inner[0], inner[1], center], color.lightened(0.45))
	p.circle(center+Vector2(-3, -4)*s, 1.4*s, Color.WHITE)
	if tier==2:
		var twinkle = 0.5+sin(g.clock*4)*0.5
		p.line(center+Vector2(5, -12)*s, center+Vector2(5, -4)*s, Color(1, 1, 1, twinkle), 1)
		p.line(center+Vector2(1, -8)*s, center+Vector2(9, -8)*s, Color(1, 1, 1, twinkle), 1)

func _potion() -> void:
	p.circle(Vector2(0, 5), 11, Color("5a0f22"))
	p.circle(Vector2(0, 5), 10, Color("d62a4f"))
	p.ellipse(Vector2(0, 0), 9, 3, Color("ff5a7a"), 16)
	p.poly([Vector2(-4, -12), Vector2(4, -12), Vector2(4, -4), Vector2(-4, -4)], Color("c9d7e6"))
	p.poly([Vector2(-5, -16), Vector2(5, -16), Vector2(4, -12), Vector2(-4, -12)], Color("8a5a2a"))
	p.ellipse(Vector2(-4, 2), 2.5, 4, Color(1, 1, 1, 0.5), 10)

func _gold() -> void:
	for k in 4:
		var o = Vector2(-7+k*5, 6-(k%2)*4)
		p.ellipse(o+Vector2(0, 2), 7, 4, Color("8a5a1a"), 16)
		p.ellipse(o, 7, 4, Color("ffcf4a"), 16)
		p.ellipse_arc(o, 5, 2.6, PI, TAU, Color("fff2b0"), 1)

extends RefCounted
## The character page (C) and the equipment and bag page (I), item tooltips with
## comparisons, and the item held on the cursor. Clicks are registered as
## buttons: "bag:<index>", "equip:<slot>", "stat:<attribute>", "sort" and the closes.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const Classes = preload("res://scripts/classes.gd")

const PANEL_TOP = 64.0
const PANEL_HEIGHT = 600.0
const CHARACTER_WIDTH = 360.0
const INVENTORY_WIDTH = 384.0
const SLOT = 50.0
const BAG_SLOT = 40.0
const BAG_GAP = 4.0
const BAG_COLUMNS = 8
const TOOLTIP_WIDTH = 300.0

const STAT_INFO = {
	"strength": {"label":"STRENGTH", "derived":"WEAPON DAMAGE", "help":["Raises all weapon damage by 3% per point", "and critical hit damage by 1% per point."]},
	"dexterity": {"label":"DEXTERITY", "derived":"CRIT  ·  EVADE", "help":["Each point adds 0.5% critical hit chance", "and 0.3% chance to evade an attack."]},
	"focus": {"label":"FOCUS", "derived":"NOVA DAMAGE", "help":["Raises Ember Nova damage by 4% per point,", "maximum mana by 4 and mana regeneration."]},
	"vitality": {"label":"VITALITY", "derived":"MAX HEALTH", "help":["Each point adds 4 maximum health.", "Health also grows by 20 every level."]},
}
const COMPARE_STATS = [["dps", "Damage per Second", "%.1f"], ["armor", "Armor", "%d"], ["max_hp", "Maximum Health", "%d"],
	["crit", "Critical Chance", "%.1f%%"], ["evade", "Evade Chance", "%.1f%%"], ["max_mana", "Maximum Mana", "%d"],
	["element_total", "Elemental Damage", "%d"], ["attack_speed", "Attack Speed", "%.2f"], ["gold_find", "Gold Found", "%d%%"],
	["life_on_kill", "Health per Kill", "%d"], ["move_speed", "Movement Speed", "%d%%"], ["nova_power", "Nova Power", "%.2f"]]

var g
var p
var ui
var art
var characters
var hovered_item = null
var hovered_source = ""

func _init(game, painter, kit, item_art, character_art) -> void:
	g = game
	p = painter
	ui = kit
	art = item_art
	characters = character_art

func character_rect() -> Rect2:
	return Rect2(14, PANEL_TOP, CHARACTER_WIDTH, PANEL_HEIGHT)

func inventory_rect() -> Rect2:
	return Rect2(ui.c.get_viewport_rect().size.x-14-INVENTORY_WIDTH, PANEL_TOP, INVENTORY_WIDTH, PANEL_HEIGHT)

## Whether a screen point is over an open panel (clicks there never reach the world).
func covers(point: Vector2) -> bool:
	return (g.panels.character and character_rect().grow(4).has_point(point)) or (g.panels.inventory and inventory_rect().grow(4).has_point(point))

func draw() -> void:
	hovered_item = null
	hovered_source = ""
	if g.panels.character: _character_page(character_rect())
	if g.panels.inventory: _inventory_page(inventory_rect())

## Tooltips and the held item draw last, above everything else.
func draw_overlay() -> void:
	if g.held!=null:
		var r = Rect2(g.pointer-Vector2(22, 22), Vector2(44, 44))
		ui.glow(g.pointer, 34, Color(Items.color(g.held), 0.35))
		art.draw(g.held, g.pointer+Vector2(4, 4), 40)
		ui.rect(r, Color(Items.color(g.held), 0.8), false, 1)
		return
	if hovered_item!=null:
		draw_tooltip(hovered_item, g.pointer, hovered_source)
	elif hovered_source.begins_with("stat:"):
		draw_stat_help(hovered_source.substr(5), g.pointer)

# --- Character page -----------------------------------------------------------

func _character_page(r: Rect2) -> void:
	var player = g.player
	var s = g.stats
	ui.panel(r, true)
	var x = r.position.x
	var y = r.position.y
	ui.plate(Rect2(x+22, y+24, r.size.x-84, 34), "THE WAYFARER", 18)
	ui.close_button("close_character", Rect2(r.end.x-52, y+26, 30, 30))
	ui.neon("LEVEL %d" % player.level, Vector2(r.get_center().x, y+64), 15, Data.NEON_PINK, ui.CENTER)
	var need = g._xp_needed()
	ui.bar(Rect2(x+24, y+86, r.size.x-48, 18), float(player.xp)/need, Data.NEON_PURPLE.lerp(Data.NEON_CYAN, 0.35), "%d / %d XP" % [player.xp, need], 10)
	var derived_values = {
		"strength":"%d – %d" % [roundi(s.damage_min), roundi(s.damage_max)],
		"dexterity":"%d%%   %d%%" % [roundi(s.crit), roundi(s.evade)],
		"focus":str(roundi(g._nova_damage())),
		"vitality":str(roundi(s.max_hp)),
	}
	var row_y = y+116
	for key in Items.ATTRIBUTES:
		_stat_row(key, Vector2(x, row_y), r.size.x, derived_values[key])
		row_y += 64
	# Combat details in two columns.
	var top = y+378
	ui.text("C O M B A T   D E T A I L S", Vector2(x+24, top), 10, Data.NEON_CYAN, ui.LEFT, ui.font_bold)
	ui.line(Vector2(x+24, top+16), Vector2(r.end.x-24, top+16), Color(Data.NEON_PINK, 0.35), 1)
	var left = [["Damage per Second", "%.1f" % s.dps], ["Attack Speed", "%.2f / s" % (s.attack_speed/Items.SWING_TIME)],
		["Critical Damage", "+%d%%" % roundi(s.crit_damage)], ["Armor", str(roundi(s.armor))],
		["Damage Reduction", "%d%%" % roundi(s.reduction*100)], ["Mana Regen", "%.1f / s" % s.mana_regen],
		["Movement Speed", "+%d%%" % roundi(s.move_speed)], ["Gold Found", "+%d%%" % roundi(s.gold_find)]]
	var right = [["Fire Damage", s.elements.fire, Items.ELEMENT_COLORS.fire], ["Ice Damage", s.elements.ice, Items.ELEMENT_COLORS.ice],
		["Shock Damage", s.elements.shock, Items.ELEMENT_COLORS.shock], ["Poison Damage", s.elements.poison, Items.ELEMENT_COLORS.poison],
		["Health per Kill", s.life_on_kill, Data.HEALTH], ["Nova Power", s.nova_power*100, Data.SUNSET]]
	for i in left.size():
		var line_y = top+22+i*16
		ui.text(left[i][0], Vector2(x+24, line_y), 11, Data.INK_MUTED)
		ui.text(left[i][1], Vector2(x+178, line_y), 11, Data.INK, ui.RIGHT, ui.font_bold)
	for i in right.size():
		var line_y = top+22+i*16
		var value = right[i][1]
		ui.text(right[i][0], Vector2(x+196, line_y), 11, Color(right[i][2], 0.85) if value>0 else Data.INK_MUTED)
		ui.text(("%d%%" % roundi(value)) if right[i][0]=="Nova Power" else ("+%d" % roundi(value)), Vector2(r.end.x-24, line_y), 11, Data.INK if value>0 else Color(Data.INK_MUTED, 0.6), ui.RIGHT, ui.font_bold)
	# Health, mana and unspent points.
	var bottom = y+PANEL_HEIGHT-64
	_vital_box(Rect2(x+24, bottom, 148, 26), "HP", "%d / %d" % [ceili(player.hp), roundi(s.max_hp)], Data.HEALTH)
	_vital_box(Rect2(r.end.x-172, bottom, 148, 26), "MP", "%d / %d" % [floori(player.mana), roundi(s.max_mana)], Data.MANA)
	var points_rect = Rect2(x+70, bottom+32, r.size.x-140, 22)
	ui.rect(points_rect, Color("0a0514e6"))
	ui.rect(points_rect, Color(Data.UPGRADE if player.points>0 else Data.PANEL_EDGE, 0.8), false, 1)
	ui.text("STAT POINTS", Vector2(points_rect.position.x+14, points_rect.position.y+4), 11, Data.SUN_YELLOW, ui.LEFT, ui.font_bold)
	ui.text(str(player.points), Vector2(points_rect.end.x-14, points_rect.position.y+3), 13, Data.UPGRADE if player.points>0 else Data.INK, ui.RIGHT, ui.font_bold)

func _stat_row(key: String, origin: Vector2, panel_width: float, derived: String) -> void:
	var info = STAT_INFO[key]
	var s = g.stats
	var center = origin+Vector2(46, 30)
	ui.circle(center, 24, Color("0a0514"))
	ui.ring(center, 24, Color("b8925a"), 2.5)
	ui.ring(center, 20, Color(Data.NEON_CYAN, 0.5), 1)
	ui.icon(key, center, 26, Data.CHROME)
	var label_rect = Rect2(origin.x+80, origin.y+4, 86, 16)
	var value_rect = Rect2(origin.x+80, origin.y+21, 86, 30)
	ui.text(info.label, Vector2(label_rect.get_center().x, label_rect.position.y+1), 10, Data.SUN_YELLOW, ui.CENTER, ui.font_bold)
	_value_box(value_rect)
	var total = roundi(s[key])
	var bonus = total-roundi(s[key+"_base"])
	ui.text(str(total), Vector2(value_rect.get_center().x, value_rect.position.y+5), 18, Data.AFFIX_BLUE if bonus>0 else Data.CHROME, ui.CENTER, ui.font_bold)
	# Arrow from the attribute to what it drives.
	var arrow_x = origin.x+178
	var arrow_y = value_rect.get_center().y
	ui.poly(PackedVector2Array([Vector2(arrow_x, arrow_y-6), Vector2(arrow_x+10, arrow_y-6), Vector2(arrow_x+10, arrow_y-11), Vector2(arrow_x+20, arrow_y), Vector2(arrow_x+10, arrow_y+11), Vector2(arrow_x+10, arrow_y+6), Vector2(arrow_x, arrow_y+6)]), Color("c79a52"))
	var derived_label = Rect2(origin.x+206, origin.y+4, panel_width-256, 16)
	var derived_rect = Rect2(origin.x+206, origin.y+21, panel_width-256, 30)
	ui.text(info.derived, Vector2(derived_label.get_center().x, derived_label.position.y+1), 10, Data.SUN_YELLOW, ui.CENTER, ui.font_bold)
	_value_box(derived_rect)
	ui.text(derived, Vector2(derived_rect.get_center().x, derived_rect.position.y+6), 16, Data.CHROME, ui.CENTER, ui.font_bold)
	ui.plus_button("stat:"+key, Rect2(origin.x+panel_width-44, origin.y+24, 26, 26), g.player.points>0)
	var row = Rect2(origin+Vector2(18, 0), Vector2(panel_width-66, 56))
	if row.has_point(g.pointer) and g.held==null:
		hovered_source = "stat:"+key

func _value_box(r: Rect2) -> void:
	ui.rect(r, Color("06030c"))
	ui.rect(r, Color("c79a52"), false, 1.5)
	ui.rect(r.grow(-3), Color(Data.NEON_PURPLE, 0.35), false, 1)

func _vital_box(r: Rect2, badge: String, value: String, color: Color) -> void:
	ui.rect(r, Color("06030c"))
	ui.rect(r, Color(color, 0.7), false, 1)
	var badge_center = Vector2(r.position.x+13, r.get_center().y)
	ui.circle(badge_center, 13, color.darkened(0.3))
	ui.ring(badge_center, 13, Color.WHITE, 1)
	ui.text(badge, Vector2(badge_center.x, badge_center.y-7), 10, Color.WHITE, ui.CENTER, ui.font_bold)
	ui.text(value, Vector2(r.position.x+r.size.x/2+10, r.position.y+5), 13, Data.CHROME, ui.CENTER, ui.font_bold)

# --- Equipment and bag page ---------------------------------------------------

func equip_rect(slot: String) -> Rect2:
	var r = inventory_rect()
	var y = r.position.y+96
	var left = r.position.x+18
	var right = r.end.x-18-SLOT
	match slot:
		"helmet": return Rect2(left, y, SLOT, SLOT)
		"chest": return Rect2(left, y+58, SLOT, SLOT)
		"gloves": return Rect2(left, y+116, SLOT, SLOT)
		"belt": return Rect2(left, y+174, SLOT, SLOT)
		"amulet": return Rect2(right, y, SLOT, SLOT)
		"ring1": return Rect2(right, y+58, SLOT, SLOT)
		"ring2": return Rect2(right, y+116, SLOT, SLOT)
		"boots": return Rect2(right, y+174, SLOT, SLOT)
	return Rect2(r.get_center().x-SLOT/2-36, y+174, SLOT, SLOT)

func bag_rect(index: int) -> Rect2:
	var r = inventory_rect()
	var origin = Vector2(r.position.x+(r.size.x-(BAG_COLUMNS*BAG_SLOT+(BAG_COLUMNS-1)*BAG_GAP))/2, r.position.y+352)
	return Rect2(origin+Vector2(index%BAG_COLUMNS, index/BAG_COLUMNS)*(BAG_SLOT+BAG_GAP), Vector2(BAG_SLOT, BAG_SLOT))

func _inventory_page(r: Rect2) -> void:
	var player = g.player
	var s = g.stats
	ui.panel(r, true)
	var x = r.position.x
	var y = r.position.y
	ui.plate(Rect2(x+22, y+24, r.size.x-84, 34), "EQUIPMENT", 18)
	ui.close_button("close_inventory", Rect2(r.end.x-52, y+26, 30, 30))
	# Summary strip.
	var cells = [["DPS", "%.1f" % s.dps], ["ARMOR", str(roundi(s.armor))], ["HEALTH", str(roundi(s.max_hp))], ["CRIT", "%d%%" % roundi(s.crit)]]
	for i in cells.size():
		var cx = x+48+i*(r.size.x-96)/3.0
		ui.text(cells[i][0], Vector2(cx, y+64), 9, Data.INK_MUTED, ui.CENTER, ui.font_bold)
		ui.text(cells[i][1], Vector2(cx, y+75), 13, Data.CHROME, ui.CENTER, ui.font_bold)
	# Portrait: the hero on a neon disc under a sunset, between the slot columns.
	var stage = Rect2(x+78, y+96, r.size.x-156, 224)
	ui.rect(stage, Color("0a0414"))
	c_sky(stage)
	ui.rect(stage, Color(Data.PANEL_EDGE, 0.7), false, 1)
	_portrait(Vector2(stage.get_center().x+20, stage.end.y-46))
	for slot in Items.EQUIP_SLOTS: _equip_slot(slot)
	# Bag.
	var bag_top = y+330
	ui.text("B A G", Vector2(x+22, bag_top), 10, Data.NEON_CYAN, ui.LEFT, ui.font_bold)
	var used = player.bag.filter(func(i): return i!=null).size()
	ui.text("%d / %d" % [used, Items.BAG_SIZE], Vector2(x+64, bag_top), 10, Data.INK_MUTED)
	ui.button("sort", Rect2(r.end.x-82, bag_top-5, 60, 20), "SORT", false, 10)
	for i in Items.BAG_SIZE: _bag_slot(i)
	# Gold, potions and controls.
	var bottom = y+PANEL_HEIGHT-30
	ui.icon("gold", Vector2(x+34, bottom+8), 20, Data.GOLD)
	ui.text(str(player.gold), Vector2(x+50, bottom), 14, Data.GOLD, ui.LEFT, ui.font_bold)
	art.draw("potion", Vector2(x+124, bottom+8), 20)
	ui.text("× %d" % player.potions, Vector2(x+138, bottom+1), 13, Data.INK, ui.LEFT, ui.font_bold)
	ui.text("Right-click: equip  ·  Shift-click: salvage", Vector2(r.end.x-20, bottom+3), 10, Data.INK_MUTED, ui.RIGHT)

func c_sky(stage: Rect2) -> void:
	ui.c.draw_texture_rect(ui.sky, stage, false, ui.ink(Color(1, 1, 1, 0.55)))
	ui.sun(Vector2(stage.get_center().x, stage.position.y+stage.size.y*0.52), 46, true, 0.55)
	ui.grid(Rect2(stage.position.x+1, stage.position.y+stage.size.y*0.6, stage.size.x-2, stage.size.y*0.4-1), Color(Data.NEON_CYAN, 0.35), g.clock*0.15, 12)
	ui.rect(Rect2(stage.position.x+1, stage.position.y+stage.size.y*0.6-1, stage.size.x-2, 2), Color(Data.NEON_PINK, 0.7))

func _portrait(feet: Vector2) -> void:
	ui.c.draw_set_transform(Vector2.ZERO)
	var state = characters.hero_state()
	state.angle = 0.55+sin(g.clock*0.6)*0.25
	state.walk = 0.0
	state.swing = {}
	state.roll = 0.0
	state.blink = false
	state.lean = 0.0
	if g.view3d:
		g.view3d.draw_portrait(ui.c, g.player.get("class", "samurai"), feet, 140.0)
		return
	var saved = characters.c
	characters.c = ui.c
	characters.draw_hero(state, Vector2.ZERO, false, feet, 2.5)
	characters.c = saved

func _equip_slot(slot: String) -> void:
	var r = equip_rect(slot)
	var item = g.player.equipment[slot]
	var hovered = r.has_point(g.pointer)
	var highlight = Color.TRANSPARENT
	if g.held!=null:
		if Items.is_gem(g.held):
			if item!=null and Items.open_sockets(item)>0: highlight = Data.NEON_CYAN
		elif Items.fits(g.held, slot): highlight = Data.UPGRADE if int(g.held.level)<=int(g.player.level) else Data.DOWNGRADE
	ui.slot(r, item, hovered, highlight)
	if item!=null:
		art.draw(item, r.get_center(), r.size.x*0.82)
		_socket_pips(item, r)
	else:
		ui.text(Items.SLOT_LABELS[slot].to_upper(), Vector2(r.get_center().x, r.get_center().y-6), 8, Color(Data.INK_MUTED, 0.55), ui.CENTER, ui.font_bold)
	if hovered and item!=null and g.held==null:
		hovered_item = item
		hovered_source = "equipped"
	g.buttons.append({"id":"equip:"+slot, "rect":r})

func _bag_slot(index: int) -> void:
	var r = bag_rect(index)
	var item = g.player.bag[index]
	var hovered = r.has_point(g.pointer)
	var highlight = Color.TRANSPARENT
	if g.held!=null and Items.is_gem(g.held) and item!=null and Items.open_sockets(item)>0: highlight = Data.NEON_CYAN
	ui.slot(r, item, hovered, highlight)
	if item!=null:
		art.draw(item, r.get_center(), r.size.x*0.8)
		_socket_pips(item, r)
		if not Items.is_gem(item) and int(item.level)>int(g.player.level):
			ui.rect(r.grow(-2), Color(Data.DOWNGRADE, 0.18))
		var steps = Items.upgrade_steps(item, g.player.equipment)
		if steps>0 and int(item.level)<=int(g.player.level):
			_arrow(r.position+Vector2(r.size.x-8, 9), true)
		if hovered and g.held==null:
			hovered_item = item
			hovered_source = "bag"
	g.buttons.append({"id":"bag:%d" % index, "rect":r})

func _socket_pips(item: Dictionary, r: Rect2) -> void:
	for i in int(item.sockets):
		var center = Vector2(r.position.x+7+i*8, r.end.y-7)
		ui.circle(center, 3.2, Color("06030c"))
		if i<item.gems.size(): ui.circle(center, 2.4, Items.GEMS[item.gems[i].gem].color)
		else: ui.ring(center, 2.4, Color(Data.INK_MUTED, 0.9), 1)

func _arrow(center: Vector2, up: bool) -> void:
	var d = -1.0 if up else 1.0
	ui.poly(PackedVector2Array([center+Vector2(0, 5*d), center+Vector2(-4.5, -2*d), center+Vector2(4.5, -2*d)]), Data.UPGRADE if up else Data.DOWNGRADE)

# --- Tooltips -----------------------------------------------------------------

func _line(lines: Array, text: String, size: int, color: Color, font: Font = null, right: String = "", right_color: Color = Data.INK_MUTED, gap: float = 3.0) -> void:
	lines.append({"text":text, "size":size, "color":color, "font":font if font else ui.font_ui, "right":right, "right_color":right_color, "gap":gap})

func _divider(lines: Array) -> void:
	lines.append({"divider":true, "gap":8.0})

## The lines describing an item. source: "bag", "equipped", "ground" or "".
func tooltip_lines(item: Dictionary, source: String) -> Array:
	var lines: Array = []
	var color = Items.color(item)
	_line(lines, item.name, 18, color, ui.font_serif)
	_line(lines, Items.type_line(item), 12, color.darkened(0.15), ui.font_bold, "" if Items.is_gem(item) else "Item Level %d" % int(item.level), Data.INK_MUTED, 2)
	_divider(lines)
	if Items.is_gem(item):
		var in_weapon = Items.gem_effect(item, true)
		var in_armor = Items.gem_effect(item, false)
		_line(lines, "In a weapon:", 12, Data.INK_MUTED)
		_line(lines, "   "+Items.affix_text(in_weapon[0], in_weapon[1]), 13, Data.AFFIX_BLUE)
		_line(lines, "In armor or jewelry:", 12, Data.INK_MUTED, null, "", Data.INK_MUTED, 6)
		_line(lines, "   "+Items.affix_text(in_armor[0], in_armor[1]), 13, Data.AFFIX_BLUE)
	elif item.slot=="weapon":
		_line(lines, "%.1f  Damage per Second" % Items.dps(item), 17, Data.CHROME, ui.font_bold)
		_line(lines, "Damage", 13, Data.INK_MUTED, null, "%d – %d" % [int(item.min), int(item.max)], Data.INK)
		_line(lines, "Attack Speed", 13, Data.INK_MUTED, null, "%s (%.2f)" % [Items.speed_word(item.speed), item.speed], Data.INK)
	elif item.has("armor"):
		var favored = Items.favored(item)
		var bonus = favored!="" and favored==g.player.get("class", "")
		_line(lines, "%d  Armor" % roundi(Items.armor_for(item, g.player.get("class", ""))), 17, Data.CHROME, ui.font_bold, "+15% favored" if bonus else "", Data.UPGRADE)
		if favored!="":
			_line(lines, "Favored: %s" % Classes.CLASSES[favored].name, 12, Classes.CLASSES[favored].color, ui.font_bold)
	for a in item.get("implicit", []):
		if a is Array and a.size()==2 and Items.AFFIXES.has(a[0]): _line(lines, Items.affix_text(a[0], a[1]), 13, Data.INK)
	if not item.affixes.is_empty():
		_divider(lines)
		for a in item.affixes:
			var tint = Items.ELEMENT_COLORS[a[0]].lerp(Data.AFFIX_BLUE, 0.35) if a[0] in Items.ELEMENTS else Data.AFFIX_BLUE
			_line(lines, Items.affix_text(a[0], a[1]), 13, tint)
	if int(item.get("sockets", 0))>0:
		_divider(lines)
		for i in int(item.sockets):
			if i<item.gems.size():
				var gem = item.gems[i]
				var effect = Items.gem_effect(gem, item.slot=="weapon")
				_line(lines, "◆  %s" % gem.name, 12, Items.GEMS[gem.gem].color, ui.font_bold, Items.affix_text(effect[0], effect[1]), Data.AFFIX_BLUE)
			else:
				_line(lines, "◇  Empty Socket", 12, Data.INK_MUTED)
	if item.get("flavor", "")!="":
		_divider(lines)
		_line(lines, "“%s”" % item.flavor, 12, Data.NEON_PINK.lightened(0.2), ui.font_italic)
	_divider(lines)
	if not Items.is_gem(item):
		var met = int(item.level)<=int(g.player.level)
		_line(lines, "Requires Level %d" % int(item.level), 12, Data.INK if met else Data.DOWNGRADE, ui.font_bold, "Sells for %d gold" % int(item.value), Data.GOLD)
	else:
		_line(lines, "", 4, Data.INK, null, "Sells for %d gold" % int(item.value), Data.GOLD)
	if source!="equipped" and not Items.is_gem(item):
		var changes = stat_changes(item)
		if not changes.is_empty():
			_divider(lines)
			_line(lines, "IF EQUIPPED", 10, Data.NEON_CYAN, ui.font_bold)
			for change in changes:
				_line(lines, change.label, 12, Data.INK_MUTED, null, change.text, Data.UPGRADE if change.better else Data.DOWNGRADE, 2)
	var hint = {"bag":"Click to pick up · Right-click to equip · Shift-click to salvage",
		"equipped":"Click to pick up · Right-click to unequip", "ground":"Click to pick up"}.get(source, "")
	if Items.is_gem(item) and source=="bag": hint = "Click it, then click an item with an empty socket"
	if hint!="": _line(lines, hint, 10, Color(Data.INK_MUTED, 0.85), null, "", Data.INK_MUTED, 8)
	return lines

## How the hero's stats would change if this item replaced what it compares to.
func stat_changes(item: Dictionary) -> Array:
	var slot = Items.compared_slot(item, g.player.equipment)
	if slot=="": return []
	var trial = g.player.duplicate()
	trial.equipment = g.player.equipment.duplicate()
	trial.equipment[slot] = item
	var after = Items.derive(trial)
	var before = g.stats
	var changes: Array = []
	for spec in COMPARE_STATS:
		var delta = float(after[spec[0]])-float(before[spec[0]])
		if absf(delta)<0.05: continue
		var text = ("+" if delta>0 else "−")+(spec[2] % absf(delta))
		changes.append({"label":spec[1], "text":text, "better":delta>0})
		if changes.size()>=6: break
	return changes

func _measure(lines: Array) -> float:
	var height = 12.0
	for l in lines:
		height += l.gap
		if l.has("divider"): continue
		height += l.size*1.25
	return height+10

func _draw_lines(lines: Array, r: Rect2) -> void:
	var y = r.position.y+12
	for l in lines:
		y += l.gap
		if l.has("divider"):
			ui.line(Vector2(r.position.x+14, y-4), Vector2(r.end.x-14, y-4), Color(Data.PANEL_EDGE, 0.8), 1)
			continue
		if l.text!="": ui.text(l.text, Vector2(r.position.x+16, y), l.size, l.color, ui.LEFT, l.font)
		if l.right!="": ui.text(l.right, Vector2(r.end.x-16, y+maxf(0, (l.size-12)*0.6)), 12, l.right_color, ui.RIGHT, ui.font_bold)
		y += l.size*1.25

## Draws an item's tooltip near anchor; beside it, the equipped item it compares to.
func draw_tooltip(item: Dictionary, anchor: Vector2, source: String) -> void:
	var lines = tooltip_lines(item, source)
	var height = _measure(lines)
	var screen = ui.c.get_viewport_rect().size
	var r = Rect2(anchor+Vector2(22, -height*0.5), Vector2(TOOLTIP_WIDTH, height))
	if r.end.x>screen.x-8: r.position.x = anchor.x-22-TOOLTIP_WIDTH
	r.position.y = clampf(r.position.y, 8, screen.y-height-8)
	var compare = null
	if source!="equipped" and not Items.is_gem(item):
		var slot = Items.compared_slot(item, g.player.equipment)
		if slot!="": compare = g.player.equipment.get(slot)
	if compare!=null:
		var other_lines = tooltip_lines(compare, "equipped")
		other_lines.pop_back()
		var other_height = _measure(other_lines)+18
		var other = Rect2(Vector2(r.position.x-TOOLTIP_WIDTH-10, r.position.y), Vector2(TOOLTIP_WIDTH, other_height))
		if other.position.x<8: other.position.x = r.end.x+10
		if other.end.x>screen.x-8:
			# No room on either side: stack the comparison above or below.
			other.position.x = r.position.x
			other.position.y = r.end.y+8 if r.end.y+8+other_height<screen.y else r.position.y-other_height-8
		other.position.y = clampf(other.position.y, 8, screen.y-other_height-8)
		_tooltip_box(other, compare)
		ui.text("EQUIPPED", Vector2(other.get_center().x, other.position.y-1), 10, Data.SUN_YELLOW, ui.CENTER, ui.font_bold, 3)
		_draw_lines(other_lines, Rect2(other.position+Vector2(0, 14), other.size))
	_tooltip_box(r, item)
	_draw_lines(lines, r)

func _tooltip_box(r: Rect2, item: Dictionary) -> void:
	var color = Items.color(item)
	ui.rect(r.grow(5), Color(0, 0, 0, 0.35))
	ui.gradient_rect(r, Color("1b0d30f8"), Color("0a0514fa"))
	ui.c.draw_texture_rect(ui.fade_up, Rect2(r.position, Vector2(r.size.x, 54)), false, ui.ink(Color(color, 0.22)))
	ui.rect(r, Color("06030c"), false, 3)
	ui.rect(r.grow(-2), Color(color, 0.95), false, 1.5)
	if int(item.rarity)>=3:
		ui.line(r.position+Vector2(10, 2), Vector2(r.end.x-10, r.position.y+2), Color.WHITE.lerp(color, 0.4), 2)

## The explanation shown when hovering a stat row on the character page.
func draw_stat_help(key: String, anchor: Vector2) -> void:
	var info = STAT_INFO[key]
	var r = Rect2(anchor+Vector2(20, -10), Vector2(290, 92))
	ui.rect(r.grow(5), Color(0, 0, 0, 0.35))
	ui.gradient_rect(r, Color("1b0d30f8"), Color("0a0514fa"))
	ui.rect(r, Data.SUN_YELLOW, false, 1)
	ui.chrome(info.label.capitalize(), Vector2(r.position.x+14, r.position.y+10), 16)
	ui.text(info.help[0], Vector2(r.position.x+14, r.position.y+38), 12, Data.INK)
	ui.text(info.help[1], Vector2(r.position.x+14, r.position.y+55), 12, Data.INK)
	ui.text("Spend points with +  ·  Shift-click spends 5", Vector2(r.position.x+14, r.position.y+73), 10, Data.INK_MUTED)

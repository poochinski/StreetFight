extends RefCounted
## The screen layer: HUD (portrait, orbs, hotbar, minimap, quest tracker, enemy
## plates), loot name plates, the character and inventory pages, title screen
## and menus. Clickable areas are registered in g.buttons as they are drawn.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const InventoryView = preload("res://scripts/inventory_view.gd")
const Classes = preload("res://scripts/classes.gd")
const Elites = preload("res://scripts/elites.gd")
const Zones = preload("res://scripts/zones.gd")

const ORB_RADIUS = 56.0
const HOTBAR_SLOT = 48.0

var g
var p
var c: CanvasItem
var ui
var art
var inventory_view
var hovered_skill = ""

func _init(game, painter, canvas: CanvasItem, item_art, character_art) -> void:
	g = game
	p = painter
	c = canvas
	art = item_art
	ui = UiKit.new(game, painter, canvas)
	inventory_view = InventoryView.new(game, painter, ui, item_art, character_art)

func draw() -> void:
	ui.alpha = 1
	if g.state=="title":
		_title()
		if g.confirm_new_game: _new_game_confirmation()
		return
	if g.state=="create":
		_create()
		return
	var open = g.panels
	g.loot_view.draw_labels(ui)
	_enemy_bars()
	_enemy_plate()
	_top_left(open.character)
	_top_right(open.inventory)
	_bottom_bar()
	_loot_feed()
	_messages()
	_level_banner()
	inventory_view.draw()
	_utility_panel()
	if g.state in ["paused", "victory", "defeat"]:
		_modal()
		if g.confirm_new_game: _new_game_confirmation()
		_button_tooltip()
		return
	if g.state=="inventory": inventory_view.draw_overlay()
	elif g.state=="play":
		var drop = g.loot_view.hovered_drop
		if drop!=null and drop.kind=="item": inventory_view.draw_tooltip(drop.item, g.pointer, "ground")
		elif hovered_skill!="": _skill_tooltip(hovered_skill)

	_button_tooltip()

func _screen() -> Vector2:
	return c.get_viewport_rect().size

# --- Top left: portrait, health and mana, page buttons ----------------------------

func _top_left(_character_open: bool) -> void:
	var labels = [["character", "Character"], ["quests", "Quests"], ["inventory", "Inventory"], ["companion", "Companion"]]
	for i in labels.size():
		ui.button("toggle_"+labels[i][0], Rect2(16+i*100, 14, 94, 32), labels[i][1], g.panels.get(labels[i][0], false), 12)
	if g.player.points>0:
		ui.text("!", Vector2(101, 15), 13, Data.UPGRADE, ui.CENTER, ui.font_bold)

## Retained portrait and resource-bar layout for the future companion feature.
## Deliberately not drawn until a companion system supplies its own actor data.
func _reserved_companion_portrait() -> void:
	var player = g.player
	var frame = Rect2(16, 14, 66, 66)
	ui.rect(frame.grow(3), Color(0, 0, 0, 0.45))
	c.draw_texture_rect(ui.sky, frame, false, ui.ink(Color.WHITE))
	ui.sun(Vector2(frame.get_center().x, frame.position.y+30), 16, true, 0.6)
	ui.grid(Rect2(frame.position.x+1, frame.position.y+40, frame.size.x-2, 25), Color(Data.NEON_CYAN, 0.45), g.clock*0.2, 8)
	_mini_hero(Vector2(frame.get_center().x+2, frame.end.y-6))
	ui.frame(frame, Data.NEON_PINK)
	var badge = Vector2(frame.position.x+4, frame.end.y-2)
	ui.circle(badge, 13, Color("12081e"))
	ui.ring(badge, 13, Color("c79a52"), 2)
	ui.text(str(player.level), Vector2(badge.x, badge.y-8), 13, Data.CHROME, ui.CENTER, ui.font_bold)
	ui.text("THE WAYFARER", Vector2(94, 14), 11, Data.SUN_YELLOW, ui.LEFT, ui.font_bold, 3)
	ui.bar(Rect2(94, 30, 214, 17), player.hp/player.max_hp, Data.HEALTH, "%d / %d" % [ceili(player.hp), roundi(player.max_hp)], 10)
	ui.bar(Rect2(94, 50, 214, 13), player.mana/maxf(1, player.max_mana), Data.MANA, "%d / %d" % [floori(player.mana), roundi(player.max_mana)], 9)

func _utility_panel() -> void:
	if not g.panels.quests and not g.panels.companion: return
	var r = Rect2(24, 64, 520, 350)
	ui.panel(r)
	var companion: bool = g.panels.companion
	ui.text("COMPANION" if companion else "QUESTS", r.position+Vector2(24, 22), 22, Data.SUN_YELLOW, ui.LEFT, ui.font_bold)
	ui.button("close_shop", Rect2(r.end.x-78, r.position.y+16, 60, 28), "Close")
	if companion:
		ui.text("No companion yet.", r.position+Vector2(24, 86), 16, Data.INK)
		ui.text("Your companion's details will appear here.", r.position+Vector2(24, 118), 13, Data.INK_MUTED)
	else:
		ui.text("The Heart Below", r.position+Vector2(24, 72), 17, Data.NEON_PINK)
		ui.text("Defeat the Ash Warden in Sunset Plaza.", r.position+Vector2(24, 101), 13, Data.INK)
		var y = r.position.y+151
		for kind in Zones.QUESTS:
			if not g.player.get("quests", {}).has(kind): continue
			var quest = Zones.QUESTS[kind]
			var done = g.player.quests[kind]=="done"
			ui.text(quest.title+(" — Complete" if done else " — Active"), Vector2(r.position.x+24, y), 15, Data.UPGRADE if done else Data.SUN_YELLOW)
			ui.text(quest.task, Vector2(r.position.x+24, y+23), 12, Data.INK)
			y += 57

## The 2D hero art as a class would look, for a class card.
func _card_hero(id: String, feet: Vector2) -> void:
	var keep = g.player.get("class", "samurai")
	g.player["class"] = id
	var state = g.world_view.characters.hero_state()
	state.angle = 0.6; state.walk = 0.0; state.swing = {}; state.roll = 0.0; state.blink = false; state.lean = 0.0
	g.world_view.characters.c = c
	g.world_view.characters.draw_hero(state, Vector2.ZERO, false, feet, 2.6)
	g.world_view.characters.c = g
	g.player["class"] = keep

func _mini_hero(feet: Vector2) -> void:
	var characters = inventory_view.characters
	var state = characters.hero_state()
	state.angle = 0.6
	state.walk = 0.0; state.swing = {}; state.roll = 0.0; state.blink = false; state.lean = 0.0
	if g.view3d:
		g.view3d.draw_portrait(c, g.player.get("class", "samurai"), feet, 50.0)
		return
	var saved = characters.c
	characters.c = c
	characters.draw_hero(state, Vector2.ZERO, false, feet, 0.95)
	characters.c = saved

# --- Top right: floor name, minimap, quest tracker ---------------------------------

func _top_right(inventory_open: bool) -> void:
	var w = _screen().x
	var sound = Rect2(w-82, 12, 30, 30)
	var pause = Rect2(w-46, 12, 30, 30)
	for spec in [["sound", sound, "sound"], ["settings", pause, "settings"]]:
		var r: Rect2 = spec[1]
		var hovered = r.has_point(g.pointer)
		ui.rect(r, Color("2a1648") if hovered else Color("100820e6"))
		ui.rect(r, Data.NEON_CYAN if hovered else Color(Data.PANEL_EDGE, 0.9), false, 1)
		ui.icon(spec[2], r.get_center(), 18, Data.CHROME)
		g.buttons.append({"id":spec[0], "rect":r})
	if inventory_open: return
	ui.chrome(Zones.name(g.area.kind, g.floor_number).to_upper(), Vector2(w-96, 12), 15, ui.RIGHT)
	var where = "Safe zone  ·  No fighting" if g._safe() else ("Level %d  ·  %s" % [g.floor_number, "Streets" if g.area.kind=="street" else Zones.street_name(g.floor_number)])
	ui.text(where, Vector2(w-96, 34), 10, Data.UPGRADE if g._safe() else Data.INK_MUTED, ui.RIGHT)
	if g.map_visible: _minimap(Vector2(w-114, 152), 84)
	_quests(Vector2(w-236, 262 if g.map_visible else 70))

func _minimap(center: Vector2, radius: float) -> void:
	ui.circle(center, radius+9, Color("06030c"))
	ui.circle(center, radius, Color("0d0620e8"))
	for k in 5: ui.ring(center, radius*(k+1)/5.0, Color(Data.NEON_PURPLE, 0.12), 1)
	var scale = 3.6
	var origin = g.player.pos
	# Streets, sidewalks, plazas and the floors of walk-in buildings.
	var ground_colors = {1:Color("8a6ad0"), 2:Color("43397a"), 3:Color("6656a4"), 4:Color("574c8e")}
	for cell in g.seen:
		if not g.cells.has(cell): continue
		var rel = Vector2(cell)+Vector2(0.5, 0.5)-origin
		var offset = Vector2((rel.x-rel.y)*scale, (rel.x+rel.y)*scale*0.5)
		if offset.length()>radius-4: continue
		var point = center+offset
		var color: Color = ground_colors.get(g.cells[cell], Color("7a68c4"))
		if g.blocked.has(cell): color = Color("2a1f45")
		ui.poly(PackedVector2Array([point+Vector2(0, -scale*0.5), point+Vector2(scale, 0), point+Vector2(0, scale*0.5), point+Vector2(-scale, 0)]), color)
	var mark = func(world: Vector2, color: Color, size: float):
		var rel = world-origin
		var offset = Vector2((rel.x-rel.y)*scale, (rel.x+rel.y)*scale*0.5)
		if offset.length()<radius-5: ui.circle(center+offset, size, color)
	for prop in g.props:
		if prop.kind=="chest" and not prop.open and g.seen.has(Vector2i(prop.pos)): mark.call(prop.pos, Data.GOLD, 2.2)
	for d in g.drops:
		if d.kind=="item" and g.seen.has(Vector2i(d.pos)): mark.call(d.pos, Items.color(d.item), 2.0)
	for e in g.enemies:
		if e.hp>0 and e.pos.distance_to(g.player.pos)<7: mark.call(e.pos, Data.DOWNGRADE, 2.2 if e.kind!="boss" else 4.0)
	# Exits: cyan for the subway and stairs, pink for doorways, pinned to the rim.
	for exit in g.exits:
		if not g.seen.has(Vector2i(exit.pos)): continue
		var rel = exit.pos-origin
		var offset = Vector2((rel.x-rel.y)*scale, (rel.x+rel.y)*scale*0.5)
		if offset.length()>radius-8: offset = offset.normalized()*(radius-8)
		var s = center+offset
		var pulse = 4+sin(g.clock*4)*1.2
		var color = Data.NEON_CYAN if exit.kind in ["subway", "stairs"] else Data.NEON_PINK
		ui.glow(s, 12, Color(color, 0.5))
		ui.poly(PackedVector2Array([s+Vector2(0, -pulse), s+Vector2(pulse, 0), s+Vector2(0, pulse), s+Vector2(-pulse, 0)]), color)
	for prop in g.props:
		if prop.kind in ["vendor", "stash", "transit"] and g.seen.has(Vector2i(prop.pos)): mark.call(prop.pos, Data.UPGRADE, 2.6)
	var facing = g._iso(Vector2.from_angle(g.display_angle)).normalized()
	var side = facing.orthogonal()
	ui.poly(PackedVector2Array([center+facing*7, center-facing*4+side*4.5, center-facing*2, center-facing*4-side*4.5]), Data.NEON_PINK)
	ui.ring(center, radius+1, Color("c79a52"), 3)
	ui.ring(center, radius+5, Color(Data.NEON_CYAN, 0.75), 1.2)
	ui.ring(center, radius+8, Color("06030c"), 2)
	for k in 8:
		var angle = k*TAU/8
		ui.line(center+Vector2.from_angle(angle)*(radius+2), center+Vector2.from_angle(angle)*(radius+7), Color("c79a52"), 2)
	ui.text("M", center+Vector2(radius-6, radius-14), 9, Data.SUN_YELLOW, ui.LEFT, ui.font_bold, 3)

func _quests(origin: Vector2) -> void:
	var x = origin.x
	var y = origin.y
	ui.text("ACTIVE QUEST", Vector2(x, y), 15, Data.SUN_YELLOW, ui.LEFT, ui.font_bold, 4, Color(0, 0, 0, 0.6))
	ui.line(Vector2(x, y+22), Vector2(x+216, y+22), Color(Data.NEON_PINK, 0.6), 1)
	var title = "Slay the Ash Warden" if g.floor_number==3 else "The Heart Below"
	ui.text(title, Vector2(x, y+30), 13, Data.NEON_PINK.lightened(0.2), ui.LEFT, ui.font_bold, 3, Color(0, 0, 0, 0.6))
	var task = "Defeat the Ash Warden in Sunset Plaza." if g.floor_number==3 else "Take the subway to %s." % Zones.street_name(g.floor_number+1)
	ui.text("–  "+task, Vector2(x, y+50), 11, Data.INK, ui.LEFT, null, 3, Color(0, 0, 0, 0.6))
	y += 67
	# The side quest of this place, and a count of the others still open.
	var quests: Dictionary = g.player.get("quests", {})
	if quests.has(g.area.kind):
		var quest: Dictionary = Zones.QUESTS[g.area.kind]
		var done = quests[g.area.kind]=="done"
		ui.text(quest.title+("  ✓" if done else ""), Vector2(x, y+4), 12, Data.UPGRADE if done else Data.SUN_YELLOW.lightened(0.1), ui.LEFT, ui.font_bold, 3, Color(0, 0, 0, 0.6))
		ui.text("–  "+("Done." if done else quest.task), Vector2(x, y+22), 10, Data.INK, ui.LEFT, null, 3, Color(0, 0, 0, 0.6))
		y += 42
	var others = quests.keys().filter(func(k): return k!=g.area.kind and quests[k]=="active").size()
	if others>0:
		ui.text("–  Side quests open elsewhere: %d" % others, Vector2(x, y), 10, Data.SUN_YELLOW.darkened(0.15), ui.LEFT, null, 3, Color(0, 0, 0, 0.6))
		y += 17
	ui.text("–  Foes slain: %d" % g.kills, Vector2(x, y), 11, Data.INK_MUTED, ui.LEFT, null, 3, Color(0, 0, 0, 0.6))

# --- Enemy plate and boss bar -----------------------------------------------------

## Screen height above an enemy's feet where its health bar floats.
func _enemy_top(e: Dictionary) -> float:
	var h = Data.ENEMIES[e.kind].height*Data.CHARACTER_SCALE*e.get("size_mult", 1.0)
	return h*2.15+10 if g.view3d else h+12

## Small health bars over hurt or fighting enemies; elites also show their
## name and traits in their colour, like Diablo's champions and rares.
func _enemy_bars() -> void:
	if g.state!="play": return
	var view = Rect2(Vector2.ZERO, _screen()).grow(40)
	for e in g.enemies:
		if e.hp<=0 or e.kind=="boss" or not g.seen.has(Vector2i(e.pos)): continue
		var elite = e.has("elite")
		if not (elite or e.alert or e.hp<e.max_hp): continue
		var head = g._to_screen(g._project(e.pos, _enemy_top(e)))
		if not view.has_point(head): continue
		var width = 52.0 if elite else 36.0
		var r = Rect2(head.x-width/2, head.y, width, 5 if elite else 4)
		var tint = Elites.color(e)
		ui.rect(r.grow(1), Color(0, 0, 0, 0.75))
		ui.rect(Rect2(r.position, Vector2(r.size.x*clampf(e.hp/e.max_hp, 0, 1), r.size.y)), Data.HEALTH)
		if elite or e.get("minion", false): ui.rect(r.grow(1), Color(tint, 0.9), false, 1.0)
		if elite and e.pos.distance_to(g.player.pos)<10:
			ui.text(Elites.title(e), Vector2(head.x, head.y-16), 11, tint, ui.CENTER, ui.font_bold, 3)
			ui.text(Elites.traits_text(e), Vector2(head.x, head.y-28), 9, Color(tint, 0.85), ui.CENTER, null, 3)

func _enemy_plate() -> void:
	if g.state!="play": return
	var target = {}
	for e in g.enemies:
		if e.kind=="boss" and e.hp>0 and e.alert: target = e
	if target.is_empty():
		var nearest = 30.0
		for e in g.enemies:
			if e.hp<=0 or not g.seen.has(Vector2i(e.pos)): continue
			var body = g._to_screen(g._project(e.pos, Data.ENEMIES[e.kind].height*0.6*Data.CHARACTER_SCALE))
			var distance = body.distance_to(g.pointer)
			if distance<nearest*g.WORLD_ZOOM:
				nearest = distance/g.WORLD_ZOOM
				target = e
	if target.is_empty(): return
	var cx = _screen().x/2
	var boss = target.kind=="boss"
	var width = 420.0 if boss else 300.0
	var r = Rect2(cx-width/2, 46 if boss else 40, width, 14 if boss else 12)
	if boss: ui.sun_crest(Vector2(cx, r.position.y-24), 16)
	if target.has("elite") or target.get("minion", false):
		ui.text(Elites.title(target).to_upper(), Vector2(cx, r.position.y-10), 14, Elites.color(target), ui.CENTER, ui.font_bold, 3)
		var traits = Elites.traits_text(target)
		if traits!="": ui.text(traits, Vector2(cx, r.position.y+r.size.y+14), 11, Color(Elites.color(target), 0.85), ui.CENTER)
	else: ui.chrome(Data.ENEMY_NAMES[target.kind].to_upper(), Vector2(cx, r.position.y-(24 if boss else 21)), 16 if boss else 13, ui.CENTER)
	ui.bar(r, target.hp/target.max_hp, Data.HEALTH.lerp(Data.SUNSET, 0.3), "%d / %d" % [ceili(target.hp), roundi(target.max_hp)], 9)

# --- Bottom: orbs, hotbar and experience ------------------------------------------

func _bottom_bar() -> void:
	var size = _screen()
	var cx = size.x/2
	var player = g.player
	hovered_skill = ""
	# The bar's plate, with a striped sun rising behind it.
	ui.sun(Vector2(cx, size.y-96), 44, true, 0.4, -0.45)
	var plate = PackedVector2Array([Vector2(cx-196, size.y-82), Vector2(cx+196, size.y-82), Vector2(cx+206, size.y-4), Vector2(cx-206, size.y-4)])
	ui.poly(plate, Color("0b0516f0"))
	ui.line(plate[0], plate[1], Data.NEON_PINK, 2)
	ui.line(plate[0]+Vector2(0, 4), plate[1]+Vector2(0, 4), Color("c79a52"), 1)
	ui.line(plate[1], plate[2], Color(Data.PANEL_EDGE, 0.9), 2)
	ui.line(plate[3], plate[0], Color(Data.PANEL_EDGE, 0.9), 2)
	var need = g._xp_needed()
	var xp_rect = Rect2(cx-176, size.y-14, 352, 8)
	ui.bar(xp_rect, float(player.xp)/need, Data.NEON_PURPLE.lerp(Data.NEON_PINK, 0.4))
	for k in range(1, 10): ui.line(Vector2(xp_rect.position.x+xp_rect.size.x*k/10.0, xp_rect.position.y+2), Vector2(xp_rect.position.x+xp_rect.size.x*k/10.0, xp_rect.end.y-2), Color(0, 0, 0, 0.5), 1)
	if xp_rect.grow(4).has_point(g.pointer): ui.text("%d / %d XP" % [player.xp, need], Vector2(cx, xp_rect.position.y-15), 10, Data.CHROME, ui.CENTER, ui.font_bold, 3)
	var skills = [[Classes.attack_id(g), "LMB", player.attack/maxf(0.01, g.attack_period), 0.0, "slash", 0]]
	var ids = Classes.skill_ids(g)
	for i in 4:
		var left_time = Classes.cooldown_left(g, ids[i])
		var locked = 0 if Classes.unlocked(g, i) else Classes.unlock_level(i)
		skills.append([ids[i], "RMB" if i==0 else str(i+1), left_time/maxf(0.01, Classes.cooldown_total(ids[i])), left_time, "skill:%d" % i, locked])
	skills.append(["dodge", "SPC", player.dodge/g.DODGE_COOLDOWN, player.dodge, "dodge", 0])
	skills.append(["potion", "R", 0.0, 0.0, "potion", 0])
	var gap = 6.0
	var left = cx-(skills.size()*HOTBAR_SLOT+(skills.size()-1)*gap)/2
	for i in skills.size():
		_skill_slot(skills[i], Rect2(left+i*(HOTBAR_SLOT+gap), size.y-70, HOTBAR_SLOT, HOTBAR_SLOT))
	_orb(Vector2(cx-262, size.y-66), player.hp/player.max_hp, Data.HEALTH, Color("6a0a3a"), "HP", "%d / %d" % [ceili(player.hp), roundi(player.max_hp)])
	_orb(Vector2(cx+262, size.y-66), player.mana/maxf(1, player.max_mana), Data.MANA, Color("1a1a8a"), "MP", "%d / %d" % [floori(player.mana), roundi(player.max_mana)])

func _skill_slot(skill: Array, r: Rect2) -> void:
	var id: String = skill[0]
	var hovered = r.has_point(g.pointer)
	ui.rect(r, Color("0a0514"))
	ui.gradient_rect(r.grow(-2), Color("24104a"), Color("0d0620"))
	var center = r.get_center()
	match id:
		"slash":
			for flip in [-1, 1]:
				ui.line(center+Vector2(-14*flip, 14), center+Vector2(13*flip, -13), Data.CHROME, 3)
				ui.line(center+Vector2(-14*flip, 4), center+Vector2(-4*flip, 14), Color("c79a52"), 3)
			ui.glow(center, 22, Color(Data.NEON_CYAN, 0.18))
		"nova":
			ui.glow(center, 26, Color(Data.SUNSET, 0.45))
			var star = PackedVector2Array()
			for k in 16:
				var radius = 19.0 if k%2==0 else 7.0
				star.append(center+Vector2.from_angle(k*TAU/16+g.clock*0.5)*radius)
			ui.poly(star, Data.SUNSET)
			ui.circle(center, 6, Data.SUN_YELLOW)
		"dodge":
			for k in 3:
				ui.ring(center+Vector2(4-k*5, 0), 14-k*2, Color(Data.NEON_CYAN, 0.9-k*0.25), 2.5, -PI*0.85, PI*0.1)
			ui.poly(PackedVector2Array([center+Vector2(10, -14), center+Vector2(18, -6), center+Vector2(8, -4)]), Data.NEON_CYAN)
		"potion":
			art.draw("potion", center, 34)
		_:
			_skill_icon(id, center)
	if skill[5]>0:
		# Not learned yet: a dark slot with the level it unlocks at.
		ui.rect(r.grow(-2), Color(0.02, 0, 0.06, 0.82))
		ui.text("Lv %d" % skill[5], Vector2(center.x, center.y-8), 13, Data.INK_MUTED, ui.CENTER, ui.font_bold, 3)
	elif skill[2]>0:
		# Cooldown: a dark sweep that shrinks clockwise, with the seconds left.
		var points = PackedVector2Array([center])
		var fraction = clampf(skill[2], 0, 1)
		for k in 33:
			var angle = -PI/2+TAU*(1-fraction)+TAU*fraction*k/32.0
			var direction = Vector2.from_angle(angle)
			var edge = maxf(absf(direction.x), absf(direction.y))
			points.append(center+direction/edge*r.size.x*0.5)
		ui.poly(points, Color(0.02, 0, 0.06, 0.72))
		if skill[3]>0.5: ui.text(str(ceili(skill[3])), Vector2(center.x, center.y-11), 18, Data.CHROME, ui.CENTER, ui.font_bold, 4)
	var cost: int = Classes.SKILLS[id].cost if Classes.SKILLS.has(id) else 0
	if cost>0 and skill[5]==0:
		var short = g.player.mana<cost
		if short: ui.rect(r.grow(-2), Color(Data.DOWNGRADE, 0.25))
		ui.text(str(cost), r.end-Vector2(4, 16), 11, Data.DOWNGRADE if short else Data.MANA, ui.RIGHT, ui.font_bold, 3)
	if id=="potion":
		ui.text(str(g.player.potions), r.end-Vector2(4, 18), 14, Data.CHROME if g.player.potions>0 else Data.DOWNGRADE, ui.RIGHT, ui.font_bold, 3)
	ui.rect(r, Data.NEON_CYAN if hovered else Color(Data.PANEL_EDGE, 1), false, 2 if hovered else 1.5)
	var key_rect = Rect2(r.position+Vector2(-3, -7), Vector2(ui.width(skill[1], 9, ui.font_bold)+8, 14))
	ui.rect(key_rect, Color("06030c"))
	ui.rect(key_rect, Color("c79a52"), false, 1)
	ui.text(skill[1], key_rect.position+Vector2(4, 1), 9, Data.SUN_YELLOW, ui.LEFT, ui.font_bold)
	if hovered: hovered_skill = id
	g.buttons.append({"id":skill[4], "rect":r})

## Hotbar icons for the class skills, drawn from simple neon shapes.
func _skill_icon(id: String, center: Vector2) -> void:
	var color: Color = Classes.info(g).color
	match id:
		"slash":
			for flip in [-1, 1]:
				ui.line(center+Vector2(-12*flip, 12), center+Vector2(11*flip, -11), Data.CHROME, 3)
				ui.line(center+Vector2(-12*flip, 3), center+Vector2(-3*flip, 12), Color("c79a52"), 3)
			ui.glow(center, 20, Color(Data.NEON_CYAN, 0.18))
		"nova":
			ui.glow(center, 22, Color(Data.SUNSET, 0.45))
			var star = PackedVector2Array()
			for k in 16:
				var radius = 16.0 if k%2==0 else 6.0
				star.append(center+Vector2.from_angle(k*TAU/16+g.clock*0.5)*radius)
			ui.poly(star, Data.SUNSET)
			ui.circle(center, 5, Data.SUN_YELLOW)
		"shot", "fan":
			ui.rect(Rect2(center+Vector2(-12, -6), Vector2(18, 7)), Color("c8ccd8"))
			ui.rect(Rect2(center+Vector2(-12, 0), Vector2(6, 11)), Color("6a4430"))
			ui.circle(center+Vector2(-3, -2), 4, Color("8a8e98"))
			if id=="fan":
				for k in 3: ui.line(center+Vector2(9, -3), center+Vector2(18, -12+k*9), Color(Data.SUN_YELLOW, 0.9), 2)
			else: ui.glow(center+Vector2(10, -3), 10, Color(Data.SUN_YELLOW, 0.7))
		"bolt":
			ui.glow(center, 20, Color(color, 0.5))
			ui.line(center+Vector2(-14, 10), center+Vector2(14, -10), color, 5)
			ui.line(center+Vector2(-14, 10), center+Vector2(14, -10), Color.WHITE, 2)
		"dash":
			for k in 3: ui.line(center+Vector2(-15+k*4, -8+k*8), center+Vector2(4+k*4, -8+k*8), Color(color, 0.4+k*0.25), 3)
			ui.poly(PackedVector2Array([center+Vector2(8, -12), center+Vector2(18, 0), center+Vector2(8, 12)]), Data.CHROME)
		"whirlwind":
			for k in 3: ui.ring(center, 6+k*5, Color(color, 1-k*0.25), 2.5, g.clock*4+k, g.clock*4+k+PI*1.3)
		"slam":
			ui.poly(PackedVector2Array([center+Vector2(-7, -14), center+Vector2(7, -14), center+Vector2(9, 2), center+Vector2(-9, 2)]), Data.CHROME)
			for k in 5: ui.line(center+Vector2(0, 8), center+Vector2(-16+k*8, 15), Color(color, 0.9), 2)
		"scatter":
			for k in 5: ui.line(center+Vector2(-12, 8), center+Vector2(14, 8).rotated(0)+Vector2(0, -18+k*6)-Vector2(0, 8), Color(Data.SUN_YELLOW, 0.85), 2)
		"grenade":
			ui.circle(center+Vector2(0, 3), 10, Color("4a5a34"))
			ui.rect(Rect2(center+Vector2(-3, -12), Vector2(6, 6)), Color("8a8e98"))
			ui.ring(center+Vector2(7, -11), 4, Data.CHROME, 1.5)
		"barrage":
			for k in 6:
				var x = -14+k*5.6
				ui.line(center+Vector2(x+4, -14), center+Vector2(x, 10), Color(Data.NEON_CYAN, 0.9), 2)
		"arc":
			var bolt = [center+Vector2(-5, -15), center+Vector2(4, -3), center+Vector2(-3, 1), center+Vector2(6, 15)]
			ui.glow(center, 20, Color(Data.SUN_YELLOW, 0.4))
			for k in 3: ui.line(bolt[k], bolt[k+1], Data.SUN_YELLOW, 4)
		"frost":
			for k in 3:
				var d = Vector2.from_angle(k*PI/3)*15
				ui.line(center-d, center+d, Color("9fe8ff"), 2.5)
			ui.glow(center, 18, Color("9fe8ff", 0.35))
		"meteor":
			for k in 3: ui.line(center+Vector2(14-k*3, -14+k*2), center+Vector2(2, 2), Color(Data.NEON_PINK, 0.5+k*0.2), 3)
			ui.circle(center+Vector2(-2, 5), 8, Color("ff7a3a"))
			ui.circle(center+Vector2(-4, 3), 3, Data.SUN_YELLOW)

func _skill_tooltip(id: String) -> void:
	var info: Array
	if id=="dodge": info = ["Dodge Roll", "Space", "Roll out of danger. You cannot be hit mid-roll.", "%.1f second cooldown" % g.DODGE_COOLDOWN]
	elif id=="potion": info = ["Health Potion", "R", "Restores 65% of your health.", "%d left  ·  15 gold each at the subway" % g.player.potions]
	else:
		var skill: Dictionary = Classes.SKILLS[id]
		var index = Classes.skill_ids(g).find(id)
		var key = "Left mouse" if index<0 else "Right mouse or 1" if index==0 else str(index+1)
		var cost = "  ·  %d mana" % skill.cost if skill.cost>0 else ""
		var power = g._nova_damage() if id=="nova" else g._damage()*skill.power*Classes.spell_power(g)
		var detail = "Damage about %d" % roundi(power)
		if skill.cooldown>0: detail += "  ·  %s second cooldown" % str(skill.cooldown)
		if index>=0 and not Classes.unlocked(g, index): detail = "Learned at level %d" % Classes.unlock_level(index)
		info = [skill.name, key+cost, skill.text, detail]
	var r = Rect2(g.pointer+Vector2(-140, -136), Vector2(280, 112))
	r.position.x = clampf(r.position.x, 8, _screen().x-r.size.x-8)
	ui.rect(r.grow(4), Color(0, 0, 0, 0.35))
	ui.gradient_rect(r, Color("1b0d30f8"), Color("0a0514fa"))
	ui.rect(r, Data.NEON_CYAN, false, 1)
	ui.chrome(info[0], r.position+Vector2(12, 8), 16)
	ui.text(info[1], Vector2(r.end.x-12, r.position.y+12), 10, Data.SUN_YELLOW, ui.RIGHT, ui.font_bold)
	var words = info[2]
	var lines = _wrap(words, 11, r.size.x-24)
	for i in lines.size(): ui.text(lines[i], r.position+Vector2(12, 34+i*15), 11, Data.INK)
	ui.text(info[3], r.position+Vector2(12, 40+lines.size()*15), 11, Data.AFFIX_BLUE, ui.LEFT, ui.font_bold)

func _wrap(value: String, size: int, max_width: float) -> Array:
	var lines: Array = []
	var current = ""
	for word in value.split(" "):
		var attempt = word if current=="" else current+" "+word
		if ui.width(attempt, size)>max_width and current!="":
			lines.append(current)
			current = word
		else: current = attempt
	if current!="": lines.append(current)
	return lines

## A glass orb of liquid with a moving surface, a chrome bezel and its value above.
func _orb(center: Vector2, fraction: float, light: Color, dark: Color, badge: String, value: String) -> void:
	var r = ORB_RADIUS
	if badge=="HP" and fraction<0.25 and fraction>0:
		ui.glow(center, r+22, Color(Data.HEALTH,0.12+0.10*(0.5+0.5*sin(g.clock*3))))
		ui.ring(center,r+14,Color(Data.HEALTH,0.4+0.25*sin(g.clock*3)),2)
	ui.circle(center, r+12, Color("06030c"))
	ui.ring(center, r+9, Color("8a6a3c"), 5)
	ui.ring(center, r+6, Color("f0d090"), 1.5)
	ui.ring(center, r+11, Color(light, 0.7), 1.5)
	ui.circle(center, r, Color("0a0414"))
	var top = r-2*r*clampf(fraction, 0, 1)
	for y in range(ceili(top), ceili(r)):
		var half = sqrt(maxf(0, r*r-y*y))
		var wave = sin(g.clock*3+y*0.3)*1.5
		var t = (y+r)/(2*r)
		c.draw_line(center+Vector2(-half, y+wave*0.1), center+Vector2(half, y+wave*0.1), ui.ink(light.lerp(dark, t)), 1.3)
	if fraction>0.02 and fraction<0.98:
		var surface = PackedVector2Array()
		var half_top = sqrt(maxf(0, r*r-top*top))
		for k in 17:
			var x = lerpf(-half_top, half_top, k/16.0)
			surface.append(center+Vector2(x, top+sin(g.clock*3+x*0.15)*1.6))
		c.draw_polyline(surface, ui.ink(light.lightened(0.5)), 1.5, true)
	for k in 4:
		var rise = fposmod(g.clock*0.25+k*0.27, 1.0)
		var y = lerpf(r-6, top+4, rise)
		if y>top+2: ui.circle(center+Vector2(sin(k*1.7+g.clock)*r*0.4, y), 1.6, Color(1, 1, 1, 0.25*(1-rise)))
	# Glass: a soft dome highlight and a rim catch-light.
	# Glass catch-lights, brightest where liquid sits behind them.
	var shine = 0.08+0.14*clampf((fraction-0.5)*2, 0, 1)
	p.ellipse(center+Vector2(-r*0.36, -r*0.5), r*0.24, r*0.12, Color(1, 1, 1, shine), 20)
	p.ellipse(center+Vector2(-r*0.52, -r*0.26), r*0.05, r*0.05, Color(1, 1, 1, shine*1.2), 10)
	ui.ring(center, r-1, Color(1, 1, 1, 0.12), 2, PI*0.15, PI*0.85)
	ui.text(badge, Vector2(center.x, center.y-22), 11, Color.WHITE, ui.CENTER, ui.font_bold, 4, Color(0, 0, 0, 0.6))
	ui.text(value, Vector2(center.x, center.y-6), 15, Color.WHITE, ui.CENTER, ui.font_bold, 5, Color(0, 0, 0, 0.7))

# --- Messages ------------------------------------------------------------------

func _loot_feed() -> void:
	var y = _screen().y-34
	for i in range(g.loot_feed.size()-1, -1, -1):
		var entry = g.loot_feed[i]
		ui.alpha = clampf(entry.life, 0, 1)
		ui.text(entry.text, Vector2(18, y), 12, entry.color, ui.LEFT, ui.font_bold, 4, Color(0, 0, 0, 0.75))
		y -= 19
	ui.alpha = 1

func _messages() -> void:
	var size = _screen()
	if g.save_flash>0 and g.state=="play":
		ui.alpha = minf(1,g.save_flash)
		ui.text("Game saved", Vector2(size.x/2, 64), 12, Data.UPGRADE, ui.CENTER, ui.font_bold)
		ui.alpha = 1
	if g.state=="play" and g.notice_time>0:
		ui.alpha = clampf(g.notice_time*2, 0, 1)
		var width = ui.width(g.notice, 13, ui.font_bold)
		var r = Rect2(size.x/2-width/2-24, 92, width+48, 32)
		ui.rect(r, Color("0d0620e0"))
		ui.rect(Rect2(r.position, Vector2(r.size.x, 2)), Data.NEON_PINK)
		ui.rect(r, Color(Data.PANEL_EDGE, 0.9), false, 1)
		ui.text(g.notice, Vector2(size.x/2, r.position.y+8), 13, Data.CHROME, ui.CENTER, ui.font_bold)
		ui.alpha = 1
	if g.state=="play":
		var interaction = g._interaction()
		if not interaction.is_empty():
			var parts = interaction.split(" · ", true, 1)
			var label = parts[1] if parts.size()>1 else interaction
			var width = ui.width(label, 13, ui.font_bold)+44
			var r = Rect2(size.x/2-width/2, size.y-168, width, 30)
			var entrance = g._near_exit()
			if not entrance.is_empty() and interaction=="E · "+entrance.label:
				var at = g._to_screen(g._project(entrance.pos))
				r.position = Vector2(clampf(at.x-width/2,8,size.x-width-8),clampf(at.y+32,130,size.y-168))
			ui.rect(r, Color("0d0620e0"))
			ui.rect(r, Data.NEON_CYAN, false, 1)
			var key = Rect2(r.position+Vector2(8, 6), Vector2(18, 18))
			ui.rect(key, Data.SUN_YELLOW)
			ui.text("E", key.position+Vector2(9, 1), 12, Color("1a0e24"), ui.CENTER, ui.font_bold)
			ui.text(label, Vector2(r.position.x+34, r.position.y+7), 13, Data.CHROME, ui.LEFT, ui.font_bold)

func _level_banner() -> void:
	if g.level_banner<=0: return
	var size = _screen()
	var age = 3.0-g.level_banner
	ui.alpha = clampf(g.level_banner/0.8, 0, 1)
	var pop = 1.0+maxf(0, 0.25-age)*1.6
	var y = size.y*0.24
	ui.glow(Vector2(size.x/2, y+30), 190, Color(Data.NEON_PINK, 0.18))
	ui.sun(Vector2(size.x/2, y+34), 64*pop, true, 0.2)
	ui.chrome("LEVEL UP!", Vector2(size.x/2, y), int(52*pop), ui.CENTER)
	ui.text("Level %d reached  ·  %d stat points to spend (C)" % [g.player.level, g.player.points], Vector2(size.x/2, y+70), 16, Data.CHROME, ui.CENTER, ui.font_bold, 4, Color("2a0a30cc"))
	var learned = Classes.learned_at(g, int(g.player.level))
	if not learned.is_empty():
		ui.text("New skill: %s" % ", ".join(learned), Vector2(size.x/2, y+96), 18, Data.NEON_CYAN, ui.CENTER, ui.font_bold, 4, Color("0a0420cc"))
	ui.alpha = 1

# --- Title screen ----------------------------------------------------------------

func _title() -> void:
	g.buttons.clear()
	var size = _screen()
	var horizon = size.y*0.63
	c.draw_texture_rect(ui.sky, Rect2(0, 0, size.x, horizon), false)
	for i in 70:
		var star = Vector2(fposmod(i*197.3, size.x), fposmod(i*83.1, horizon*0.7))
		ui.circle(star, 1.0+(i%3)*0.4, Color(1, 1, 1, 0.25+0.35*(0.5+sin(g.clock*2+i)*0.5)))
	var sun_center = Vector2(size.x*0.7, horizon-40)
	ui.glow(sun_center, 330, Color(Data.NEON_PINK, 0.22))
	ui.sun(sun_center, 190, true, 0.21)
	# Distant hills, then the ruined skyline in front of the sun, and the glowing
	# subway entrance at its foot.
	var hills = PackedVector2Array([Vector2(0, horizon)])
	for k in 17:
		hills.append(Vector2(k*size.x/16.0, horizon-70*(0.4+0.6*absf(sin(k*1.7)))))
	hills.append(Vector2(size.x, horizon))
	ui.poly(hills, Color("2a0b40"))
	for k in range(1, hills.size()-2): ui.line(hills[k], hills[k+1], Color(Data.NEON_PINK, 0.35), 1.2)
	var x_at = 0.0
	var index = 0
	while x_at<size.x:
		var width = 46.0+fposmod(index*37.0, 50.0)
		var height = 70.0+fposmod(index*53.0, 150.0)
		if absf(x_at+width/2-size.x*0.7)<60: height = 40.0
		# Keep the left side low so the title and menu stay readable.
		if x_at<size.x*0.4: height = minf(height, 46.0+fposmod(index*29.0, 40.0))
		var top = horizon-height
		var block = PackedVector2Array([Vector2(x_at, horizon), Vector2(x_at, top), Vector2(x_at+width*0.3, top), Vector2(x_at+width*0.42, top+(14.0 if index%3==0 else 0.0)), Vector2(x_at+width*0.55, top), Vector2(x_at+width, top), Vector2(x_at+width, horizon)])
		ui.poly(block, Color("140624") if index%2==0 else Color("1b0830"))
		ui.line(Vector2(x_at, top), Vector2(x_at+width*0.3, top), Color(Data.NEON_PINK, 0.4), 1)
		for row in int((height-20)/16):
			for col in int((width-12)/12):
				var lit = int(index*7+row*3+col*5)%9
				if lit<2:
					var flicker = 0.6+0.4*sin(g.clock*(1.5+lit)+index+row)
					ui.rect(Rect2(x_at+8+col*12, top+12+row*16, 5, 7), Color(Data.SUN_YELLOW if lit==0 else Data.NEON_CYAN, 0.55*flicker))
		if index%5==2 and absf(x_at+width/2-size.x*0.7)>110 and height>90:
			var sign_pos = Vector2(x_at+width/2, top+26)
			ui.glow(sign_pos, 40, Color(Data.NEON_PINK, 0.35))
			ui.text(["MOTEL", "VIDEO", "BAR", "88"][index%4], sign_pos, 12, Data.NEON_PINK, ui.CENTER, ui.font_bold, 3, Color(0, 0, 0, 0.5))
		x_at += width+4
		index += 1
	# A dead palm on the left of the subway.
	var palm = Vector2(size.x*0.7-150, horizon)
	for k in 10:
		ui.line(palm+Vector2(k*1.5, -k*14), palm+Vector2((k+1)*1.5, -(k+1)*14), Color("0c0418"), 6-k*0.3)
	for k in 6:
		var angle = -PI/2+(k-2.5)*0.55
		ui.line(palm+Vector2(15, -140), palm+Vector2(15, -140)+Vector2(cos(angle)*46, sin(angle)*16+26), Color("0c0418"), 4)
	var gate = Vector2(sun_center.x, horizon)
	ui.glow(gate+Vector2(0, -20), 90, Color(Data.NEON_CYAN, 0.35+sin(g.clock*3)*0.06))
	ui.poly(PackedVector2Array([gate+Vector2(-40, 0), gate+Vector2(-40, -26), gate+Vector2(40, -26), gate+Vector2(40, 0)]), Color("0c0418"))
	ui.poly(PackedVector2Array([gate+Vector2(-24, 0), gate+Vector2(-24, -16), gate+Vector2(24, -16), gate+Vector2(24, 0)]), Color("3ff0ff"))
	ui.text("SUBWAY", gate+Vector2(0, -50), 13, Data.NEON_CYAN, ui.CENTER, ui.font_bold, 3, Color(0, 0, 0, 0.6))
	for side in [-1, 1]:
		var lamp = gate+Vector2(side*58, -42)
		ui.rect(Rect2(lamp+Vector2(-2, 0), Vector2(4, 42)), Color("1a0e24"))
		ui.glow(lamp, 24, Color(0.5, 1, 0.85, 0.6))
		ui.circle(lamp, 5, Color("8affd8"))
	ui.rect(Rect2(0, horizon, size.x, size.y-horizon), Color("0b0418"))
	ui.grid(Rect2(0, horizon, size.x, size.y-horizon), Color(Data.NEON_CYAN, 0.55), g.clock*0.25, 22)
	ui.rect(Rect2(0, horizon-1, size.x, 2), Data.NEON_PINK)
	c.draw_texture_rect(p.vignette, c.get_viewport_rect(), false)
	var x = size.x*0.08
	var y = maxf(70, (size.y-620)/2)
	ui.text("A N   A D V E N T U R E   I N   T H E   E M B E R   D E P T H S", Vector2(x, y), 11, Data.NEON_CYAN, ui.LEFT, ui.font_bold, 4, Color(0, 0, 0, 0.5))
	ui.chrome("DUNGEON", Vector2(x, y+26), 88)
	ui.neon("CRAWLER", Vector2(x+6, y+128), 80, Data.NEON_PINK)
	ui.text("Something ancient stirs beneath the dead city.", Vector2(x, y+238), 16, Data.CHROME, ui.LEFT, null, 4, Color("12052acc"))
	ui.text("Take up your blade. Bring back the light.", Vector2(x, y+262), 16, Data.CHROME, ui.LEFT, null, 4, Color("12052acc"))
	ui.button("start", Rect2(x, y+310, 300, 54), "ENTER THE DEPTHS   ▸", true, 16)
	var extra = 0
	if not g.cached_save.is_empty():
		ui.button("continue", Rect2(x, y+374, 300, 38), "CONTINUE YOUR DESCENT", false, 13)
		extra = 48
	ui.text("Click to move and attack  ·  Right click and 1–4 skills  ·  Space dodge  ·  C character  ·  I inventory", Vector2(x, y+384+extra), 11, Data.INK, ui.LEFT, null, 4, Color("12052acc"))
	ui.button("quit", Rect2(size.x-120, size.y-56, 90, 32), "QUIT", false, 12)

# --- Character creation ---------------------------------------------------------

## Pick a class: three cards with the hero, what the class does and the skills
## it learns on the way down.
func _create() -> void:
	_title()
	g.buttons.clear()
	var size = _screen()
	ui.rect(Rect2(Vector2.ZERO, size), Color("07021cd8"))
	ui.text("C R E A T E   Y O U R   H E R O", Vector2(size.x/2, 46), 12, Data.NEON_CYAN, ui.CENTER, ui.font_bold, 3)
	ui.chrome("Choose a Class", Vector2(size.x/2, 66), 40, ui.CENTER)
	var card_w = minf(330.0, (size.x-80)/3.0-16)
	var card_h = minf(470.0, size.y-230)
	var left = size.x/2-(card_w*3+32)/2
	for i in Classes.ORDER.size():
		var id: String = Classes.ORDER[i]
		var info: Dictionary = Classes.CLASSES[id]
		var r = Rect2(left+i*(card_w+16), 130, card_w, card_h)
		var selected = g.chosen_class==id
		var hovered = r.has_point(g.pointer)
		ui.gradient_rect(r, Color("1d0c38f4"), Color("0a0418f8"))
		if selected: ui.glow(r.get_center(), card_w*0.9, Color(info.color, 0.12))
		ui.rect(r, info.color if selected else Color(Data.NEON_CYAN, 0.7) if hovered else Color(Data.PANEL_EDGE, 1), false, 3 if selected else 1.5)
		# The hero, as this class would look.
		var feet = r.position+Vector2(card_w/2, 176)
		ui.glow(feet-Vector2(0, 50), 80, Color(info.color, 0.22))
		if g.view3d:
			g.view3d.draw_portrait(c, id, feet, 150.0)
		else: _card_hero(id, feet)
		c.draw_set_transform(Vector2.ZERO)
		ui.chrome(info.name, Vector2(r.position.x+card_w/2, r.position.y+194), 24, ui.CENTER)
		ui.text(info.role.to_upper(), Vector2(r.position.x+card_w/2, r.position.y+230), 11, info.color, ui.CENTER, ui.font_bold)
		var lines = _wrap(info.text, 12, card_w-36)
		for k in lines.size(): ui.text(lines[k], Vector2(r.position.x+18, r.position.y+254+k*17), 12, Data.INK)
		var y = r.position.y+262+lines.size()*17
		var attrs: Dictionary = info.attributes
		ui.text("STR %d   DEX %d   FOC %d   VIT %d" % [attrs.strength, attrs.dexterity, attrs.focus, attrs.vitality], Vector2(r.position.x+18, y), 11, Data.AFFIX_BLUE, ui.LEFT, ui.font_bold)
		y += 24
		ui.text("Basic attack: %s" % Classes.SKILLS[info.attack].name, Vector2(r.position.x+18, y), 11, Data.CHROME, ui.LEFT, ui.font_bold)
		y += 20
		for k in 4:
			if y>r.end.y-20: break
			var skill = Classes.SKILLS[info.skills[k]]
			ui.text("Lv %d" % Classes.UNLOCK_LEVELS[k], Vector2(r.position.x+18, y), 11, Data.SUN_YELLOW, ui.LEFT, ui.font_bold)
			ui.text(skill.name, Vector2(r.position.x+62, y), 11, Data.CHROME)
			y += 18
		g.buttons.append({"id":"class:"+id, "rect":r})
	var info_selected: Dictionary = Classes.CLASSES[g.chosen_class]
	ui.button("begin", Rect2(size.x/2-160, 130+card_h+24, 320, 50), "BEGIN AS %s   ▸" % info_selected.name.to_upper(), true, 15)
	ui.button("back", Rect2(28, size.y-56, 90, 32), "BACK", false, 12)

# --- Menus ---------------------------------------------------------------------

func _modal() -> void:
	g.buttons.clear()
	var size = _screen()
	var player = g.player
	ui.rect(Rect2(Vector2.ZERO, size), Color("07021099"))
	var rect = Rect2(size/2-Vector2(240, 230), Vector2(480, 460))
	ui.panel(rect, true)
	var o = rect.position+Vector2(40, 44)
	var paused = g.state=="paused"
	if paused:
		_settings(rect, o)
		return
	var won = g.state=="victory"
	ui.text("T A K E   A   B R E A T H" if paused else "T H E   E M B E R S   B U R N   B R I G H T" if won else "T H E   D E P T H S   C L A I M   A N O T H E R", o, 10, Data.NEON_CYAN, ui.LEFT, ui.font_bold)
	ui.chrome("Settings" if paused else "The Warden Has Fallen" if won else "Your Light Fades", o+Vector2(0, 22), 32)
	ui.text("The depths can wait." if paused else "You freed the Ember Depths." if won else "A new adventurer will follow your footsteps.", o+Vector2(0, 74), 13, Data.INK)
	if paused:
		ui.button("resume", Rect2(o+Vector2(0, 112), Vector2(400, 48)), "RETURN TO THE DEPTHS", true, 15)
		ui.button("save_game", Rect2(o+Vector2(0, 168), Vector2(400, 34)), "SAVE GAME", false, 13)
		ui.button("restart", Rect2(o+Vector2(0, 210), Vector2(400, 30)), "NEW ADVENTURE", false, 12)
		ui.text(g.save_status, o+Vector2(200, 247), 12, Data.UPGRADE if g.save_status=="Game saved." else Data.DOWNGRADE, ui.CENTER)
	else:
		ui.text("Level %d  ·  %d foes defeated  ·  %d gold  ·  %dm %ds" % [player.level, g.kills, player.gold, int(g.elapsed)/60, int(g.elapsed)%60], o+Vector2(0, 104), 13, Data.SUN_YELLOW, ui.LEFT, ui.font_bold)
		ui.button("restart", Rect2(o+Vector2(0, 150), Vector2(400, 48)), "NEW ADVENTURE", true, 15)
	var help = ["Autosaves on travel, level-up and confirmed stat changes.", "Click to move and attack  ·  Shift-click attacks in place  ·  WASD also moves", "Right click / 1–4 skills  ·  Space dodge  ·  R potion  ·  E interact",
		"C character page  ·  I inventory  ·  Esc settings"]
	for i in help.size():
		ui.text(help[i], Vector2(size.x/2, o.y+272+i*18), 11, Data.INK_MUTED, ui.CENTER)
	ui.button("quit", Rect2(o+Vector2(0, 356), Vector2(400, 30)), "QUIT TO DESKTOP", false, 11)

func _settings(rect: Rect2, o: Vector2) -> void:
	ui.chrome("Controls" if g.settings_page=="controls" else "Settings", o, 30)
	if g.settings_page=="controls":
		var lines = ["Left click / hold — Move or attack", "Shift + click — Attack in place", "WASD / arrows — Move", "Right click / 1 — First skill; 2–4 — Other skills", "J / hold — Basic attacks", "Space — Dodge     R — Healing potion", "E — Enter / interact     M — Minimap", "C — Character     I / B — Inventory", "Stats: + / − to adjust; Shift adjusts five", "Green check — Confirm     Red X — Cancel", "Escape — Close a panel / open Settings"]
		for i in lines.size(): ui.text(lines[i],o+Vector2(0,54+i*25),13,Data.INK)
		ui.button("settings_back",Rect2(o+Vector2(0,350),Vector2(400,34)),"BACK TO SETTINGS")
		return
	ui.button("resume",Rect2(o+Vector2(0,48),Vector2(400,38)),"RESUME GAME",true)
	ui.button("save_game",Rect2(o+Vector2(0,96),Vector2(400,32)),"SAVE GAME")
	ui.text(g.save_status,o+Vector2(200,134),12,Data.UPGRADE if g.save_status=="Game saved." else Data.DOWNGRADE,ui.CENTER)
	ui.button("sound",Rect2(o+Vector2(0,158),Vector2(400,30)),"ALL SOUND: "+("ON" if g.synth.enabled else "MUTED"))
	ui.button("music",Rect2(o+Vector2(0,196),Vector2(194,30)),"MUSIC: "+("ON" if g.synth.music_enabled else "OFF"))
	ui.button("effects",Rect2(o+Vector2(206,196),Vector2(194,30)),"EFFECTS: "+("ON" if g.synth.effects_enabled else "OFF"))
	ui.button("controls",Rect2(o+Vector2(0,236),Vector2(400,30)),"CONTROLS")
	ui.button("restart",Rect2(o+Vector2(0,276),Vector2(400,30)),"NEW ADVENTURE")
	ui.button("quit",Rect2(o+Vector2(0,350),Vector2(400,30)),"QUIT TO DESKTOP")

func _new_game_confirmation() -> void:
	g.buttons.clear()
	ui.rect(Rect2(Vector2.ZERO,_screen()),Color("070210dd"))
	var r = Rect2(_screen()/2-Vector2(240,115),Vector2(480,230))
	ui.panel(r)
	ui.chrome("Start a new adventure?",r.position+Vector2(24,24),24)
	ui.text("Beginning a new character will replace your saved game.",r.position+Vector2(24,80),13,Data.INK)
	ui.text("Keep your current adventure if you are not ready.",r.position+Vector2(24,108),13,Data.INK_MUTED)
	ui.button("cancel_new_game",Rect2(r.position+Vector2(24,158),Vector2(210,38)),"KEEP CURRENT GAME",true,12)
	ui.button("confirm_new_game",Rect2(r.position+Vector2(246,158),Vector2(210,38)),"NEW ADVENTURE",false,12)

func _button_tooltip() -> void:
	var tips = {"confirm_stats":"Confirm and save these stat points", "cancel_stats":"Discard all pending stat changes", "settings":"Settings: save, sound and controls", "sound":"Mute or unmute all sound", "music":"Toggle music; your preference is remembered", "effects":"Toggle sound effects; your preference is remembered"}
	for i in range(g.buttons.size()-1,-1,-1):
		var button = g.buttons[i]
		if not button.rect.has_point(g.pointer): continue
		if not tips.has(button.id): return
		var text: String = tips[button.id]
		var width = ui.width(text,12)+24
		var r = Rect2(g.pointer+Vector2(12,22),Vector2(width,30))
		r.position.x = clampf(r.position.x,8,_screen().x-width-8)
		r.position.y = clampf(r.position.y,8,_screen().y-38)
		ui.rect(r,Color("100820f5")); ui.rect(r,Data.NEON_CYAN,false,1)
		ui.text(text,r.position+Vector2(12,7),12,Data.INK)
		return

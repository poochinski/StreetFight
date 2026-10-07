extends Node2D
## Native 2D port of the original browser game: art, controls, pacing and UI.
## Everything is drawn by Godot. There is no embedded browser or web runtime.
##
## This script owns game state, input and the hero. Other parts live in:
##   data.gd               names, colors and enemy tuning
##   dungeon_generator.gd  city layout, set dressing, spawns and the pathfinding grid
##   enemy_ai.gd           enemy awareness, movement and attacks
##   classes.gd            hero classes, basic attacks and the skills learned by level
##   world_view.gd         draw order of the city, characters and effects
##   city_art.gd           streets, buildings, neon signs, props and the subway
##   characters.gd         hero, weapon and enemy art and animation
##   effects.gd            sparks, shockwaves, afterimages, deaths
##   items.gd              item bases, rarity tiers, affixes, gems and hero stats
##   inventory.gd          bag and equipment rules
##   hud_view.gd           HUD, minimap, title screen and menus
##   inventory_view.gd     character page, equipment and bag page, tooltips
##   loot_view.gd          loot beams and name plates
##   item_art.gd           item icons
##   ui_kit.gd             the interface look (panels, chrome text, orbs)
##   painter.gd            shared drawing primitives
##   synth.gd              synthesized sound effects and synthwave music
##   save_game.gd          floor checkpoints
##   tests/                --smoke-test and --render-check

const Data = preload("res://scripts/data.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Synth = preload("res://scripts/synth.gd")
const Zones = preload("res://scripts/zones.gd")
const ZoneGenerator = preload("res://scripts/zone_generator.gd")
const Painter = preload("res://scripts/painter.gd")
const WorldView = preload("res://scripts/world_view.gd")
const HudView = preload("res://scripts/hud_view.gd")
const Effects = preload("res://scripts/effects.gd")
const HudCanvas = preload("res://scripts/hud_canvas.gd")
const Items = preload("res://scripts/items.gd")
const Inventory = preload("res://scripts/inventory.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const LootView = preload("res://scripts/loot_view.gd")
const SmokeTest = preload("res://scripts/tests/smoke_test.gd")
const RenderCheck = preload("res://scripts/tests/render_check.gd")
const Classes = preload("res://scripts/classes.gd")
const Elites = preload("res://scripts/elites.gd")
const View3D = preload("res://scripts/world3d.gd")

const RUN_SPEED = 175.0 # Screen pixels/second: all eight directions feel equally fast.
const RUN_ACCEL = 3200.0
const RUN_BRAKE = 4200.0
const ATTACK_BUFFER = 0.17
const CombatTiming = preload("res://scripts/combat_timing.gd")
const COMBO_DELAYS = CombatTiming.PERIODS
const MELEE_REACH = 1.45
const NOVA_RADIUS = 4.2
const NOVA_COOLDOWN = 6.0
const NOVA_COST = 25
const DODGE_DURATION = 0.22
const DODGE_COOLDOWN = 1.2
const HERO_RADIUS = 0.22
## The world is drawn zoomed in around the screen center; the HUD stays at screen scale.
const WORLD_ZOOM = 1.4
const REVEAL_RADIUS = 8 # Cells around the hero that come out of the dark.

var save_file = "user://descent.json"
## The 3D view (world3d.gd). Off for --smoke-test and --2d, which use the 2D art.
var view3d = null
var next_uid = 1
var state = "title"
var seed_value = 71283
var floor_number = 1
## Where the hero is: {"kind": street, mall, park, warehouse or subway, "level"}.
## floor_number is the level, which sets how tough everything is. See zones.gd.
var area = {"kind":"street", "level":1}
## Ways out of this area ({kind, pos, to: [kind, level, arrival], label}) and
## where the hero appears for each arrival point.
var exits: Array = []
var arrivals = {}
## The food court: no enemies come in and nobody fights there.
var safe_rect = Rect2()
## The run's seed builds each place the same way on every visit.
var run_seed = 1
var visited = {}
var stash: Array = []
## Open vendor or kiosk panel: "", "pawn", "juice", "stash" or "travel".
var shop = ""
var stock: Array = []
var theme_cache = {}
var cells = {}
var seen = {}
var rooms: Array = []
var enemies: Array = []
var props: Array = []
var drops: Array = []
var particles: Array = []
var texts: Array = []
var waves: Array = []
var fx: Array = []
var decals: Array = []
var blocked = {}
## Ground style per cell (carpet, checker, grass...), neon signs on building fronts,
## and cached building heights. Filled by the level generator.
var cell_style = {}
var signs: Array = []
var wall_cache = {}
## Enemy hazards waiting to go off (a Molten elite's death blast).
var hazards: Array = []
var hurt_flash = 0.0
var ghost_timer = 0.0
var buttons: Array = []
var nav: AStarGrid2D
var player = {}
var stairs = Vector2(38.5, 38.5)
var camera = Vector2.ZERO
## World zoom; previews zoom out for whole-map overviews.
var zoom = WORLD_ZOOM
var clock = 0.0
var elapsed = 0.0
var kills = 0
var shake = 0.0
var victory_timer = -1.0
var notice = ""
var notice_time = 0.0
var pointer = Vector2.ZERO
var pointer_active = false
var attack_held = false
var keys = {}
var map_visible = true
var testing = false
var cached_save = {}
var screen_velocity = Vector2.ZERO
var display_angle = 0.0
var walk_blend = 0.0
var swing = {}
var combo_index = -1
var combo_window = 0.0
var attack_buffer = 0.0
var buffered_auto_aim = false
var attack_period = COMBO_DELAYS[0]
var synth
var painter
var world_view
var hud_view
var hud_canvas
var item_art
var loot_view
## Derived hero stats (damage, crit, armor...), rebuilt by _recalc when gear or points change.
var stats = {}
var panels = {"character":false, "inventory":false}
## The item on the mouse cursor while the panels are open.
var held = null
var loot_feed: Array = []
var level_banner = 0.0
## A drop the hero is walking to after its name plate was clicked.
var walk_target = null
var walk_time = 0.0
## Hero projectiles and lingering skill effects (see classes.gd).
var shots: Array = []
var zones: Array = []
## A brief freeze when a heavy blow lands, so hits feel solid.
var hitstop = 0.0
var simulation_delta = 0.0
var attack_serial = 0
var combat_target = {}
## Click-to-move: the path being walked, the enemy being chased to attack, and
## whether the button is still held (the hero then keeps following the cursor).
var move_path = PackedVector2Array()
var move_held = false
var move_repath = 0.0
var chase = {}
## The class picked on the character screen.
var chosen_class = "samurai"
func _ready() -> void:
	painter = Painter.new(self)
	world_view = WorldView.new(self,painter)
	var layer = CanvasLayer.new()
	add_child(layer)
	hud_canvas = HudCanvas.new()
	hud_canvas.game = self
	layer.add_child(hud_canvas)
	item_art = ItemArt.new(self,painter,world_view.characters)
	loot_view = LootView.new(self,painter,item_art)
	hud_view = HudView.new(self,painter,hud_canvas,item_art,world_view.characters)
	_apply_zoom()
	synth = Synth.new()
	add_child(synth)
	var args = OS.get_cmdline_user_args()
	testing = "--smoke-test" in args or "--render-check" in args
	if testing: save_file = "user://faithful-port-test.json"
	synth.enabled = not testing
	if not "--smoke-test" in args and not "--2d" in args:
		view3d = View3D.new()
		add_child(view3d)
		view3d.setup(self)
	player = _new_player()
	_generate(1)
	camera += Vector2(-180,20)
	cached_save = _load_save()
	if "--smoke-test" in args: SmokeTest.run.call_deferred(self)
	if "--render-check" in args: RenderCheck.run.call_deferred(self)

# --- Randomness -------------------------------------------------------------

func _random() -> float:
	seed_value = (seed_value * 1664525 + 1013904223) & 0xffffffff
	return float(seed_value) / 4294967296.0

func _between(a: float,b: float) -> float:
	return lerpf(a,b,_random())

# --- Setup, floors and saves ------------------------------------------------

func _new_player(class_id: String = "samurai") -> Dictionary:
	var equipment = Items.empty_equipment()
	equipment.weapon = Items.starter_weapon()
	equipment.chest = Items.starter_chest()
	var hero = {"pos":Vector2(7.5,7.5),"hp":120.0,"max_hp":120.0,"mana":60.0,"max_mana":60.0,"level":1,"xp":0,"gold":0,"potions":3,
		"class":class_id,"attributes":Classes.CLASSES[class_id].attributes.duplicate(),"points":0,
		"equipment":equipment,"bag":Items.empty_bag(),"cd":{},"channel":{},"recoil":0.0,
		"angle":0.0,"attack":0.0,"nova":0.0,"dodge":0.0,"inv":0.0,"roll":0.0,"roll_dir":Vector2.ZERO,"step":0.0}
	stats = Items.derive(hero)
	hero.max_hp = stats.max_hp; hero.hp = stats.max_hp
	hero.max_mana = stats.max_mana; hero.mana = stats.max_mana
	return hero

## Rebuilds the derived stats after gear, attributes or level change.
func _recalc() -> void:
	stats = Items.derive(player)
	player.max_hp = stats.max_hp
	player.max_mana = stats.max_mana
	player.hp = minf(player.hp,player.max_hp)
	player.mana = minf(player.mana,player.max_mana)

func _weapon():
	return player.equipment.weapon

## Each level takes noticeably longer than the last: about level 3 by the end of
## the first floor and level 6 by the Warden.
func _xp_needed() -> int:
	return 90+roundi(80*pow(int(player.level)-1,1.35))

func _spawn_enemy(kind: String,pos: Vector2) -> Dictionary:
	var stats = Data.ENEMIES[kind]
	var hp = stats.hp if kind=="boss" else stats.hp*(1+(floor_number-1)*0.55)
	next_uid += 1
	var enemy = {"uid":next_uid,"pos":pos,"kind":kind,"hp":hp,"max_hp":hp,"attack":0.0,"hit":0.0,"phase":0.0,"alert":false,
		"windup":0.0,"windup_total":0.0,"aim":Vector2.ZERO,"stagger":0.0,"path":PackedVector2Array(),"repath":0.0,
		"step":0.0,"moving":0.0}
	enemies.append(enemy)
	return enemy

func _carve(x: int,y: int,w: int,h: int) -> void:
	DungeonGenerator.carve(self,x,y,w,h)

## The look of this place: its street's theme with the area's overrides.
func theme() -> Dictionary:
	if theme_cache.is_empty():
		theme_cache = Data.FLOOR_THEMES[clampi(floor_number-1,0,Data.FLOOR_THEMES.size()-1)].duplicate()
		theme_cache.merge(Data.ZONE_THEMES.get(area.kind,{}),true)
	return theme_cache

func _generate(number: int, kind: String = "street", arrive: String = "start") -> void:
	floor_number = number
	area = {"kind":kind, "level":number, "arrive":arrive}
	theme_cache = {}
	synth.set_track("boss" if number==3 and kind=="street" else "street")
	cells.clear(); seen.clear(); rooms.clear(); enemies.clear(); props.clear()
	drops.clear(); particles.clear(); texts.clear(); waves.clear()
	fx.clear(); decals.clear(); blocked.clear(); hurt_flash = 0
	cell_style.clear(); signs.clear(); wall_cache.clear()
	walk_target = null
	hazards.clear(); player.burn = 0.0
	exits.clear(); arrivals.clear(); safe_rect = Rect2()
	shots.clear(); zones.clear(); chase = {}; move_path = PackedVector2Array(); move_held = false
	player.channel = {}; player.ranged_attack = {}; combat_target = {}; hitstop = 0
	victory_timer = -1
	screen_velocity = Vector2.ZERO
	walk_blend = 0
	swing.clear()
	combo_index = -1; combo_window = 0; attack_buffer = 0
	display_angle = player.angle
	player.pos = Vector2(7.5,7.5)
	player.inv = 1.0
	for key in ["attack","nova","dodge","roll"]: player[key] = 0.0
	if kind=="street": DungeonGenerator.generate(self,number)
	else: ZoneGenerator.generate(self,kind,number)
	if not arrivals.is_empty(): player.pos = arrivals.get(arrive,arrivals.get("start",arrivals.values()[0]))
	world_view.redraw_all()
	if view3d: view3d.build()
	camera = _iso(player.pos)
	_reveal()
	if state=="play": _save()

func _save() -> void:
	SaveGame.write(save_file,player,floor_number,kills,elapsed,seed_value,
		{"area":area,"run_seed":run_seed,"visited":visited.keys(),"stash":stash,"quests":player.get("quests",{})})

## Goes to a place (see zones.gd for arrival points). Each place is built from
## the run's seed, so it is the same place every visit.
func _travel(kind: String, level: int, arrive: String) -> void:
	visited[Zones.key(kind,level)] = true
	if kind=="mall" and arrive=="foodcourt": visited["foodcourt"] = true
	if kind=="mall": stock.clear()
	var quests: Dictionary = player.get("quests",{})
	player.quests = quests
	var fresh = Zones.QUESTS.has(kind) and not quests.has(kind)
	if fresh: quests[kind] = "active"
	seed_value = Zones.seed_for(run_seed,kind,level)
	_generate(level,kind,arrive)
	seed_value = (run_seed*1103515245+int(elapsed*1000)+next_uid*7919)&0xffffffff
	if kind=="mall": visited["foodcourt"] = true
	if fresh:
		_notice(Zones.QUESTS[kind].intro)
		_feed("New quest: %s" % Zones.QUESTS[kind].title,Data.SUN_YELLOW)
	else: _notice("%s · Progress saved" % Zones.name(kind,level))
	_save()

## Is the hero in the food court, where nobody fights?
func _safe(point: Vector2 = Vector2.INF) -> bool:
	if point==Vector2.INF: point = player.pos
	return safe_rect.size!=Vector2.ZERO and safe_rect.has_point(point)

func _no_fighting() -> bool:
	if not _safe(): return false
	if notice_time<=0: _notice("No fighting in the food court.")
	return true

func _load_save() -> Dictionary:
	return SaveGame.read(save_file)

func _begin(continue_game: bool = false, class_id: String = "") -> void:
	var saved = _load_save() if continue_game else {}
	shop = ""; stock.clear(); visited.clear()
	stash = []
	stash.resize(Zones.STASH_SIZE)
	if class_id=="": class_id = chosen_class
	if not saved.is_empty(): class_id = saved.stats.get("class","samurai")
	if not Classes.CLASSES.has(class_id): class_id = "samurai"
	chosen_class = class_id
	player = _new_player(class_id)
	kills = 0; elapsed = 0
	seed_value = int(Time.get_unix_time_from_system()*1000)&0xffffffff
	var number = 1
	run_seed = seed_value
	var place = {"kind":"street","level":1,"arrive":"start"}
	if not saved.is_empty():
		for key in saved.stats: player[key] = saved.stats[key]
		player.bag.resize(Items.BAG_SIZE)
		number = int(saved.floor)
		kills = int(saved.get("kills",0))
		elapsed = float(saved.get("time",0))
		seed_value = int(saved.get("seed",seed_value))
		var world: Dictionary = saved.get("world",{})
		run_seed = int(world.get("run_seed",seed_value))
		for key in world.get("visited",[]): visited[key] = true
		var kept: Array = world.get("stash",[])
		for i in mini(kept.size(),Zones.STASH_SIZE): stash[i] = kept[i]
		player.quests = world.get("quests",{}).duplicate()
		place = world.get("area",{"kind":"street","level":number,"arrive":"start"})
	state = "play"
	panels.character = false; panels.inventory = false
	held = null; loot_feed.clear(); level_banner = 0
	keys.clear(); attack_held = false; pointer_active = false
	if not player.has("quests"): player.quests = {}
	_recalc()
	_travel(place.kind,int(place.level),place.get("arrive","start"))
	_notice("Your descent continues." if not saved.is_empty() else "Neon Row, 1989. Find the subway entrance.")
	if saved.is_empty(): _feed("%s learned: %s" % [Classes.info(self).name,Classes.SKILLS[Classes.skill_ids(self)[0]].name],Data.SUN_YELLOW)

# --- Coordinates and collision ----------------------------------------------

func _apply_zoom() -> void:
	scale = Vector2.ONE*zoom
	position = get_viewport_rect().size/2*(1-zoom)

## Screen position of a point in the world's drawing space, and the reverse.
func _to_screen(local: Vector2) -> Vector2:
	return position+local*scale

func _pointer_local() -> Vector2:
	return (pointer-position)/scale

func _iso(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32,(point.x+point.y)*16)

func _project(point: Vector2,z: float = 0.0) -> Vector2:
	if view3d: return view3d.project(point,z)
	return _iso(point)-camera+get_viewport_rect().size/2-Vector2(0,z)

func _world(point: Vector2) -> Vector2:
	if view3d: return view3d.world(point)
	var s = point+camera-get_viewport_rect().size/2
	var a = s.x/32
	var b = s.y/16
	return Vector2((a+b)/2,(b-a)/2)

func _walkable(point: Vector2) -> bool:
	var cell = Vector2i(floori(point.x),floori(point.y))
	return cells.has(cell) and not blocked.has(cell)

func _free(point: Vector2,radius: float) -> bool:
	return _walkable(point+Vector2(-radius,-radius)) and _walkable(point+Vector2(radius,-radius)) and _walkable(point+Vector2(-radius,radius)) and _walkable(point+Vector2(radius,radius))

func _move(actor: Dictionary,delta: Vector2,radius: float = HERO_RADIUS) -> void:
	# Short swept steps prevent dodges crossing thin walls and allow wall sliding.
	var steps = maxi(1,ceili(delta.length()/0.1))
	var step = delta/steps
	for i in steps:
		if _free(actor.pos+Vector2(step.x,0),radius): actor.pos.x += step.x
		if _free(actor.pos+Vector2(0,step.y),radius): actor.pos.y += step.y

func _screen_to_world_delta(delta: Vector2) -> Vector2:
	return Vector2(delta.x/64+delta.y/32,delta.y/32-delta.x/64)

func _screen_movement() -> Vector2:
	var sx = int(keys.has(KEY_D) or keys.has(KEY_RIGHT))-int(keys.has(KEY_A) or keys.has(KEY_LEFT))
	var sy = int(keys.has(KEY_S) or keys.has(KEY_DOWN))-int(keys.has(KEY_W) or keys.has(KEY_UP))
	return Vector2(sx,sy).normalized()

func _movement() -> Vector2:
	return _screen_to_world_delta(_screen_movement()).normalized()

func _clear_path(from: Vector2,to: Vector2) -> bool:
	var steps = maxi(1,ceili(from.distance_to(to)/0.12))
	for i in range(1,steps+1):
		if not _walkable(from.lerp(to,float(i)/steps)): return false
	return true

func _reveal() -> void:
	var size = DungeonGenerator.SIZE
	for y in range(floori(player.pos.y)-REVEAL_RADIUS,floori(player.pos.y)+REVEAL_RADIUS+1):
		for x in range(floori(player.pos.x)-REVEAL_RADIUS,floori(player.pos.x)+REVEAL_RADIUS+1):
			if x>=0 and y>=0 and x<size and y<size and Vector2(x+0.5,y+0.5).distance_to(player.pos)<REVEAL_RADIUS+0.5 and not seen.has(Vector2i(x,y)):
				seen[Vector2i(x,y)] = true
				world_view.reveal(Vector2i(x,y))

# --- Hero combat ------------------------------------------------------------

## Melee reaches the edge of an enemy's body, so large enemies can be hit from as far as small ones.
func _in_melee_reach(e: Dictionary,extra: float = 0.0) -> bool:
	return e.pos.distance_to(player.pos)<MELEE_REACH+Data.ENEMIES[e.kind].radius+extra

## Attack range of the hero's basic attack.
func _reach_of(e: Dictionary,extra: float = 0.0) -> bool:
	if Classes.ranged(self): return e.pos.distance_to(player.pos)<Classes.info(self).range+extra
	return _in_melee_reach(e,extra)

## The enemy under the cursor. With any=true it may be out of reach or behind a wall.
func _cursor_target(any: bool = false) -> Dictionary:
	var nearest = 38.0
	var selected = {}
	for e in enemies:
		if e.hp<=0: continue
		if not any and (not _reach_of(e,0.6) or not _clear_path(player.pos,e.pos)): continue
		if any and (e.pos.distance_to(player.pos)>12 or not seen.has(Vector2i(e.pos))): continue
		var distance = _pointer_local().distance_to(_project(e.pos,Data.ENEMIES[e.kind].height*Data.CHARACTER_SCALE))
		# Click the visible body, rather than requiring a click at its feet.
		if distance<nearest:
			nearest = distance
			selected = e
	return selected

func _aim(auto_aim: bool = false) -> void:
	if pointer_active and not auto_aim:
		var target = _cursor_target()
		if not target.is_empty(): player.angle = (target.pos-player.pos).angle()
		else:
			var difference = _world(_pointer_local())-player.pos
			if difference.length()>0.12: player.angle = difference.angle()
	else:
		var nearest = 3.0
		if Classes.ranged(self): nearest = Classes.info(self).range
		for e in enemies:
			var distance = e.pos.distance_to(player.pos)
			if e.hp>0 and distance<nearest and _clear_path(player.pos,e.pos):
				nearest = distance
				player.angle = (e.pos-player.pos).angle()

## Average damage of one ordinary swing, including elemental damage.
func _damage() -> int:
	return roundi((stats.damage_min+stats.damage_max)/2+stats.element_total)

func _nova_damage() -> float:
	return _damage()*2.8*stats.nova_power

func _run_speed() -> float:
	return RUN_SPEED*(1+stats.move_speed/100.0)

func _request_attack(auto_aim: bool = false) -> void:
	if state!="play" or _no_fighting(): return
	attack_buffer = ATTACK_BUFFER
	buffered_auto_aim = auto_aim
	if player.attack<=0 and player.roll<=0: _basic_attack(auto_aim)

## The class's basic attack: a sword combo, a revolver shot or a laser bolt.
func _basic_attack(auto_aim: bool = false) -> void:
	if not player.channel.is_empty() and player.channel.kind!="whirlwind": return
	if Classes.attack_id(self)=="slash":
		_slash(auto_aim)
		return
	if state!="play" or player.attack>0 or player.roll>0: return
	_aim(auto_aim)
	Classes.shoot(self)

func _slash(auto_aim: bool = false) -> void:
	if state!="play" or player.attack>0 or player.roll>0: return
	_aim(auto_aim)
	combo_index = (combo_index+1)%3 if combo_window>0 else 0
	combo_window = 0.85
	attack_period = COMBO_DELAYS[combo_index]/stats.attack_speed
	player.attack = attack_period
	attack_buffer = 0
	attack_serial += 1
	swing = {"age":0.0,"duration":attack_period,"contact":CombatTiming.CONTACTS[combo_index]/stats.attack_speed,"speed":stats.attack_speed,"angle":player.angle,"index":combo_index,"resolved":false,"serial":attack_serial}
	_tone(210 if combo_index==0 else 250 if combo_index==1 else 145,0.1,"saw",0.025)

func _resolve_swing() -> void:
	var connected = false
	for e in enemies:
		var difference = e.pos-player.pos
		var angle = wrapf(difference.angle()-swing.angle,-PI,PI)
		if e.hp>0 and _in_melee_reach(e) and (absf(angle)<1.4 or difference.length()<0.65) and _clear_path(player.pos,e.pos):
			var multiplier = 1.3 if swing.index==2 else 1.0
			_strike_enemy(e,multiplier)
			e.stagger = 0.04 if e.kind=="boss" else 0.18 if swing.index==2 else 0.11
			if swing.index==2: Elites.knock(e,player.pos,7.5)
			else: _move(e,difference.normalized()*(0.06 if e.kind=="boss" else 0.2),Data.ENEMIES[e.kind].radius)
			var look = Items.weapon_look(_weapon())
			if _weapon()!=null and Items.main_element(_weapon())=="" and int(_weapon().rarity)<2: look.glow=Color("c9e4ff")
			Effects.hit(self,e.pos,difference.normalized(),look.glow.lerp(Color("ffc06a"),0.5 if swing.index==2 else 0.0),swing.index==2)
			connected = true
	for p in props:
		if p.kind=="crate" and not p.open and p.pos.distance_to(player.pos)<2 and _clear_path(player.pos,p.pos):
			p.open = true
			_burst(p.pos,Color("be966c"))
			_drop_gold(p.pos,floori(_between(2,7)))
			if _random()<0.08: _drop_item(p.pos,Items.random_drop(self))
	if connected:
		hitstop = maxf(hitstop,0.035 if swing.index==2 else 0.012)
		shake = maxf(shake,2.0 if swing.index==2 else 0.8)
		_tone(95 if swing.index==2 else 135,0.07,"triangle",0.035)

## One weapon hit: rolls damage between the hero's minimum and maximum, may
## crit, adds elemental damage and applies its effects (burn, chill, poison, arcs).
func _strike_enemy(e: Dictionary,multiplier: float) -> void:
	var amount = _between(stats.damage_min,stats.damage_max)*multiplier
	var crit = _random()*100<stats.crit
	var elemental = stats.element_total*multiplier
	if crit:
		amount *= 1+stats.crit_damage/100.0
		elemental *= 1+stats.crit_damage/100.0
	var total = roundi(amount+elemental)
	_damage_enemy(e,total,crit)
	_apply_elements(e)

func _apply_elements(e: Dictionary) -> void:
	if e.hp<=0: return
	var elements = stats.elements
	if elements.fire>0:
		e.burn = 2.5
		e.burn_dps = elements.fire*0.6
	if elements.poison>0:
		e.poison = 3.5
		e.poison_dps = elements.poison*0.5
	if elements.ice>0: e.chill = 1.6
	if elements.shock>0 and _random()<0.3:
		# Shock arcs to the nearest other enemy.
		var best = {}
		var nearest = 3.2
		for other in enemies:
			if other==e or other.hp<=0: continue
			var d = other.pos.distance_to(e.pos)
			if d<nearest and _clear_path(e.pos,other.pos):
				nearest = d
				best = other
		if not best.is_empty():
			Effects.add(self,"arc",{"from":e.pos,"to":best.pos,"seed":randi()},0.22)
			_damage_enemy(best,roundi(elements.shock*2.5),false,Items.ELEMENT_COLORS.shock)

func _nova() -> void:
	if state!="play" or player.nova>0 or _no_fighting(): return
	if player.mana<NOVA_COST:
		_notice("Not enough mana for Ember Nova.")
		_tone(140,0.12,"triangle",0.02)
		return
	player.mana -= NOVA_COST
	player.nova = NOVA_COOLDOWN
	player.cast_at = clock
	_tone(95,0.6,"saw",0.06)
	shake = 4
	Effects.shockwave(self,player.pos,NOVA_RADIUS,Color("ffb35c"),true)
	_burst(player.pos,Color("ffb85e"),30,5)
	for e in enemies:
		# The blast is stopped by walls, like melee.
		if e.hp>0 and e.pos.distance_to(player.pos)<NOVA_RADIUS and _clear_path(player.pos,e.pos):
			_damage_enemy(e,roundi(_nova_damage()*_between(0.94,1.06)))
			Elites.knock(e,player.pos,8.0)

func _dodge() -> void:
	if state!="play" or player.dodge>0: return
	player.roll_dir = _screen_movement()
	if player.roll_dir==Vector2.ZERO: player.roll_dir = _iso(Vector2.from_angle(player.angle)).normalized()
	player.roll = DODGE_DURATION; player.inv = 0.32; player.dodge = DODGE_COOLDOWN
	player.channel = {}; chase = {}; move_path = PackedVector2Array()
	combat_target = {}
	# Dodge cancels even the wind-up of an attack. There are no animation locks.
	swing.clear(); attack_buffer = 0; player.attack = 0
	player.ranged_attack = {}
	hitstop = 0
	screen_velocity = player.roll_dir*_run_speed()
	walk_target = null
	_tone(300,0.12,"triangle",0.02)

func _potion() -> void:
	if state!="play": return
	if player.hp>=player.max_hp:
		_notice("Your health is already full.")
		return
	if player.potions<=0:
		_notice("No potions left. Search footlockers or buy some at the subway.")
		return
	player.potions -= 1
	player.hp = minf(player.max_hp,player.hp+roundi(player.max_hp*0.65))
	_burst(player.pos,Color("93eeb3"),20)
	_tone(620,0.3)
	_notice("Healing potion used.")

func _hurt(amount: float) -> void:
	if player.inv>0 or state!="play" or _safe(): return
	if _random()*100<stats.evade:
		player.inv = 0.25
		_float_text(player.pos,"Evaded",Data.NEON_CYAN)
		_tone(520,0.06,"triangle",0.015)
		return
	var actual = maxi(1,roundi(amount*(1-stats.reduction)))
	player.hp = maxf(0,player.hp-actual)
	player.inv = 0.5; shake = 3; hurt_flash = 1.0
	player.hurt_at = clock
	_float_text(player.pos,"−"+str(actual),Color("ff8986"))
	_burst(player.pos,Color("e57870"),8)
	_tone(70,0.16,"saw",0.035)
	if player.hp<=0: _finish(false)

func _damage_enemy(e: Dictionary,amount: int,crit: bool = false,color: Color = Color("eed49a")) -> void:
	if e.hp<=0: return
	amount = Elites.adjust_damage(e,amount)
	e.hp -= amount; e.hit = 0.15
	EnemyAI.alert(self,e)
	_burst(e.pos,Color("ffb95f") if e.kind=="boss" else Color("b9d182"),7)
	if crit: _float_text(e.pos,"%d!" % amount,Data.NEON_PINK,true)
	else: _float_text(e.pos,str(amount),color)
	Elites.on_damaged(self,e)
	if e.hp<=0:
		kills += 1
		_tone(100,0.18,"saw",0.025)
		_gain_xp(roundi(Data.ENEMIES[e.kind].xp*e.get("xp_mult",1.0)))
		Elites.on_death(self,e)
		if stats.life_on_kill>0: player.hp = minf(player.max_hp,player.hp+stats.life_on_kill)
		_drop_gold(e.pos,floori(_between(4,10))*floor_number)
		if _random()<0.16: _drop(e.pos,{"kind":"potion"})
		var chance = {"imp":0.22,"ranged":0.24,"brute":0.32}.get(e.kind,0.0)
		if _random()<chance: _drop_item(e.pos,Items.random_drop(self))
		if e.kind=="boss":
			_drop_item(e.pos,Items.generate(self,int(player.level)+2,4))
			for i in 3: _drop_item(e.pos,Items.random_drop(self,6.0))
		if e.has("quest"): _finish_quest(e)
		Effects.death(self,e)
		if e.kind=="boss":
			Effects.shockwave(self,e.pos,5.0,Color("ffd782"),false)
			_burst(e.pos,Color("ffd782"),70,5)
			victory_timer = 0.85

## A side quest's boss is down: the quest is done and pays out.
func _finish_quest(e: Dictionary) -> void:
	var quest: Dictionary = Zones.QUESTS[e.quest]
	player.quests[e.quest] = "done"
	_drop_item(e.pos,Items.generate(self,int(player.level)+1,3 if _random()<0.7 else 4))
	_drop_gold(e.pos,60*floor_number)
	_feed("Quest complete: %s" % quest.title,Data.SUN_YELLOW)
	_notice("%s is finished. The streets talk." % quest.boss)
	_tone(1180,0.5,"sine",0.04)
	_save()

# --- Progression and loot ---------------------------------------------------

func _gain_xp(amount: int) -> void:
	player.xp += amount
	while player.xp>=_xp_needed():
		player.xp -= _xp_needed()
		player.level += 1
		player.points += Items.STAT_POINTS_PER_LEVEL
		_recalc()
		player.hp = player.max_hp
		player.mana = player.max_mana
		_burst(player.pos,Color("fbe8a7"),35)
		Effects.level_up(self,player.pos)
		level_banner = 3.0
		_feed("Level %d reached: +%d stat points" % [player.level,Items.STAT_POINTS_PER_LEVEL],Data.SUN_YELLOW)
		for skill in Classes.learned_at(self,int(player.level)):
			_feed("New skill learned: %s" % skill,Data.NEON_CYAN)
			_notice("New skill: %s. Check your hotbar." % skill)
		_tone(800,0.5)

func spend_point(attribute: String,count: int = 1) -> void:
	count = mini(count,int(player.points))
	if count<=0: return
	player.attributes[attribute] = int(player.attributes[attribute])+count
	player.points -= count
	var hp_before = player.max_hp
	_recalc()
	player.hp += player.max_hp-hp_before
	_tone(660,0.08,"triangle",0.02)

# --- Loot ---------------------------------------------------------------------------

## Adds a drop that flies out from origin to a free spot nearby.
func _drop(origin: Vector2,data: Dictionary,manual: bool = false) -> Dictionary:
	var target = origin
	for attempt in 8:
		var angle = _random()*TAU
		var candidate = origin+Vector2.from_angle(angle)*_between(0.45,1.15)
		if _free(candidate,0.2) and _clear_path(origin,candidate):
			target = candidate
			break
	var d = {"pos":target,"from":origin,"age":0.0,"taken":false,"manual":manual}
	d.merge(data)
	drops.append(d)
	return d

func _drop_gold(origin: Vector2,amount: int) -> void:
	_drop(origin,{"kind":"gold","value":maxi(1,roundi(amount*(1+stats.gold_find/100.0)))})

func _drop_item(origin: Vector2,item: Dictionary,manual: bool = false) -> void:
	_drop(origin,{"kind":"item","item":item},manual)
	if int(item.rarity)>=4: _tone(1180,0.5,"sine",0.04)
	elif int(item.rarity)>=3: _tone(990,0.3,"sine",0.03)

func _collect(d: Dictionary) -> void:
	if d.taken: return
	if d.kind=="gold":
		d.taken = true
		player.gold += d.value
		_tone(700,0.07,"sine",0.012)
	elif d.kind=="potion":
		d.taken = true
		player.potions += 1
		_feed("Health Potion",Color("ff8aa0"))
		_tone(620,0.08,"sine",0.015)
	else:
		if not Inventory.store(self,d.item):
			if notice_time<=0 or notice!="Your bag is full.": _notice("Your bag is full.")
			return
		d.taken = true
		var rarity = int(d.item.rarity)
		_feed(d.item.name,Items.color(d.item))
		_tone(560+rarity*120,0.12+rarity*0.04,"triangle",0.025)

func _feed(text: String,color: Color) -> void:
	loot_feed.append({"text":text,"color":color,"life":4.0})
	if loot_feed.size()>6: loot_feed.pop_front()

const SERVICES = {"pawn":"Trade at Ray's Pawn", "juice":"Buy potions at Juice Bar", "stash":"Open your stash", "transit":"Read the transit map"}

func _interaction() -> String:
	for p in props:
		if p.kind=="chest" and not p.open and p.pos.distance_to(player.pos)<1.7: return "E · Open footlocker"
	var service = _near_service()
	if not service.is_empty(): return "E · "+SERVICES[service.get("vendor",service.kind)]
	var exit = _near_exit()
	if not exit.is_empty(): return "E · "+exit.label
	return ""

## The vendor stall, stash or transit map within reach.
func _near_service() -> Dictionary:
	for p in props:
		if p.kind in ["vendor","stash","transit"] and p.pos.distance_to(player.pos)<2.0: return p
	return {}

func _near_exit() -> Dictionary:
	for exit in exits:
		if exit.pos.distance_to(player.pos)<2.0: return exit
	return {}

## Opens a vendor, the stash or the transit map beside the bag.
func _open_shop(kind: String) -> void:
	shop = kind
	panels.character = false
	panels.inventory = kind!="travel"
	if kind=="pawn" and stock.is_empty(): stock = Inventory.make_stock(self)
	state = "inventory"
	keys.clear(); attack_held = false; walk_target = null
	_tone(520,0.08,"triangle",0.02)

func _interact() -> void:
	if state!="play": return
	for p in props:
		if p.kind=="chest" and not p.open and p.pos.distance_to(player.pos)<1.7:
			p.open = true
			_drop_item(p.pos,Items.random_drop(self,2.5))
			if _random()<0.4: _drop_item(p.pos,Items.random_drop(self,2.0))
			_drop_gold(p.pos,20*floor_number)
			_drop(p.pos,{"kind":"potion"})
			_burst(p.pos,Color("ffe39b"),25)
			_tone(900,0.3)
			return
	var service = _near_service()
	if not service.is_empty():
		_open_shop(service.get("vendor","travel" if service.kind=="transit" else service.kind))
		return
	var exit = _near_exit()
	if exit.is_empty(): return
	var to: Array = exit.to
	# Heading on toward the next street: patch up and restock on the way down.
	var onward = to[0]=="subway" and to[2]=="west"
	var bought = 0
	if onward:
		while player.potions<3 and player.gold>=Zones.POTION_PRICE:
			player.potions += 1; player.gold -= Zones.POTION_PRICE; bought += 1
		player.hp = minf(player.max_hp,player.hp+roundi(player.max_hp*0.35))
	_travel(to[0],int(to[1]),to[2])
	if bought: _notice("%s · Bought %d potions" % [Zones.name(to[0],int(to[1])),bought])

# --- Feedback ---------------------------------------------------------------

func _float_text(point: Vector2,text: String,color: Color = Color("eed49a"),big: bool = false) -> void:
	texts.append({"pos":point,"text":text,"color":color,"life":1.1,"max":1.1,"big":big})

func _burst(point: Vector2,color: Color,count: int = 12,power: float = 2) -> void:
	for i in count:
		particles.append({"pos":point,"z":_between(4,22),"velocity":Vector2(_between(-power,power),_between(-power,power)),"vz":_between(12,60),"life":_between(0.3,0.8),"color":color,"size":_between(1.5,4),"hostile":false})

func _notice(text: String) -> void:
	notice = text; notice_time = 3.7

func _tone(frequency: float = 220,duration: float = 0.12,shape: String = "triangle",volume: float = 0.045) -> void:
	synth.play(frequency,duration,shape,volume)

# --- Game states and input --------------------------------------------------

func _pause() -> void:
	if state=="play": state = "paused"
	elif state=="paused": state = "play"
	keys.clear(); attack_held = false
	attack_buffer = 0; screen_velocity = Vector2.ZERO

## Opens or closes one of the two pages. The game pauses while either is open.
func _toggle_panel(name: String) -> void:
	if state!="play" and state!="inventory": return
	panels[name] = not panels[name]
	_panels_changed()

func _close_panels() -> void:
	panels.character = false; panels.inventory = false; shop = ""
	_panels_changed()

func _panels_changed() -> void:
	if not panels.inventory: Inventory.stow_held(self)
	if panels.character or not panels.inventory: shop = ""
	state = "inventory" if panels.character or panels.inventory or shop!="" else "play"
	keys.clear(); attack_held = false
	attack_buffer = 0; screen_velocity = Vector2.ZERO
	walk_target = null
	_tone(380 if state=="inventory" else 300,0.06,"triangle",0.015)

func _inventory() -> void:
	_toggle_panel("inventory")

func _character() -> void:
	_toggle_panel("character")

func _finish(won: bool) -> void:
	panels.character = false; panels.inventory = false; held = null
	state = "victory" if won else "defeat"
	keys.clear(); attack_held = false
	victory_timer = -1
	SaveGame.erase(save_file)
	cached_save = {}

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
		pointer_active = true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		pointer = event.position
		var right = event.button_index==MOUSE_BUTTON_RIGHT
		if not event.pressed:
			if not right:
				attack_held = false
				move_held = false
			return
		# Buttons drawn last sit on top, so they get the click first.
		for i in range(buttons.size()-1,-1,-1):
			if buttons[i].rect.has_point(pointer):
				_activate(buttons[i].id,right,event.shift_pressed)
				return
		if state=="inventory":
			# A held item dropped on the Pawn Shop sells; on the open world it drops.
			if held!=null and not right and shop=="pawn" and hud_view.inventory_view.shop_rect().has_point(pointer): Inventory.sell_held(self)
			elif held!=null and not right and not hud_view.inventory_view.covers(pointer): Inventory.drop_held(self)
			return
		if state=="play" and right:
			pointer_active = true
			Classes.cast(self,0)
			return
		if state=="play":
			pointer_active = true
			walk_target = null
			_mouse_down(event.shift_pressed)
	if event is InputEventKey:
		var key = event.physical_keycode
		if not event.pressed:
			keys.erase(key)
			return
		if event.echo: return
		if key==KEY_ESCAPE:
			if state=="inventory": _close_panels()
			else: _pause()
			return
		if key==KEY_I or key==KEY_B:
			_inventory()
			return
		if key==KEY_C:
			_character()
			return
		if state!="play": return
		keys[key] = true
		match key:
			KEY_J: _request_attack(true)
			KEY_Q: Classes.cast(self,0)
			KEY_1: Classes.cast(self,0)
			KEY_2: Classes.cast(self,1)
			KEY_3: Classes.cast(self,2)
			KEY_4: Classes.cast(self,3)
			KEY_SPACE: _dodge()
			KEY_R: _potion()
			KEY_E: _interact()
			KEY_M: map_visible = not map_visible

func _activate(id: String,right: bool = false,shift: bool = false) -> void:
	var parts = id.split(":")
	match parts[0]:
		"bag":
			var index = int(parts[1])
			if right and shop=="stash": Inventory.to_stash(self,index)
			elif right and shop=="pawn": Inventory.sell(self,index)
			elif right: Inventory.equip_from_bag(self,index)
			else: Inventory.click_bag(self,index,shift)
			return
		"stash":
			var index = int(parts[1])
			if right: Inventory.from_stash(self,index)
			else: Inventory.click_stash(self,index)
			return
		"stock":
			Inventory.buy(self,int(parts[1]))
			return
		"travel":
			var places = Zones.destinations()
			var index = int(parts[1])
			if not right and index<places.size() and visited.has(places[index].key):
				var place: Dictionary = places[index]
				_close_panels()
				_travel(place.kind,place.level,place.arrive)
			return
		"equip":
			if right: Inventory.unequip(self,parts[1])
			else: Inventory.click_equipment(self,parts[1])
			return
		"stat":
			spend_point(parts[1],5 if shift else 1)
			return
		"loot":
			var index = int(parts[1])
			if index<drops.size(): _walk_to_drop(drops[index])
			return
		"skill":
			if not right: Classes.cast(self,int(parts[1]))
			return
		"class":
			if not right:
				chosen_class = parts[1]
				_tone(520,0.08,"triangle",0.02)
			return
	if right: return
	match id:
		"start", "restart":
			state = "create"
			_tone(420,0.08,"triangle",0.02)
		"begin": _begin(false,chosen_class)
		"back": state = "title"
		"continue": _begin(true)
		"pause", "resume": _pause()
		"inventory", "close_inventory", "toggle_inventory": _inventory()
		"close_character", "toggle_character": _character()
		"close_shop": _close_panels()
		"buy_potion": Inventory.buy_potion(self)
		"toggle_map": map_visible = not map_visible
		"sort": Inventory.sort(self)
		"slash": _request_attack(true)
		"nova": _nova()
		"dodge": _dodge()
		"potion": _potion()
		"sound":
			synth.enabled = not synth.enabled
			_tone(440,0.15)
		"quit": get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and not testing:
		keys.clear(); attack_held = false
		if state=="play": _pause()

# --- Simulation -------------------------------------------------------------

func _process(delta: float) -> void:
	clock += delta
	_apply_zoom()
	_advance_game(delta)
	if view3d: view3d.sync(delta)
	queue_redraw()

func _advance_game(delta: float) -> void:
	# Consume frame time in small steps instead of slowing the game below 25 FPS.
	var remaining = minf(delta,0.25)
	simulation_delta = 0.0
	while remaining>0.000001 and state=="play":
		if hitstop>0 and not testing:
			var consumed=minf(hitstop,remaining)
			hitstop-=consumed
			remaining-=consumed
			if remaining<=0.000001: break
		elif testing: hitstop=0
		var step = minf(remaining,1.0/120.0)
		_update(step)
		simulation_delta += step
		remaining -= step

## Left click in the world, Diablo style: on an enemy in reach it attacks; on an
## enemy further away the hero runs over and then attacks; on open ground the
## hero walks there, and keeps following the cursor while the button is held.
## Shift-click attacks in place.
func _mouse_down(in_place: bool = false) -> void:
	chase = {}
	combat_target = {}
	move_path = PackedVector2Array()
	if in_place:
		attack_held = true
		_request_attack()
		return
	var target = _cursor_target(true)
	if not target.is_empty():
		combat_target = target
		attack_held = true
		if _reach_of(target) and _clear_path(player.pos,target.pos): _request_attack()
		else:
			chase = target
			move_repath = 0.0
		return
	attack_held = false
	move_held = true
	_path_to(_world(_pointer_local()))

func _path_to(point: Vector2) -> void:
	if _clear_path(player.pos,point):
		move_path = PackedVector2Array([point])
		return
	move_path = EnemyAI._find_path(self,player.pos,point)
	if not move_path.is_empty() and _walkable(point): move_path.append(point)

## Screen direction toward the next point of the click-to-move path or chase.
func _click_direction(dt: float) -> Vector2:
	if attack_held and not combat_target.is_empty():
		if combat_target.hp<=0: combat_target={}
		elif not _reach_of(combat_target,-0.08): chase=combat_target
	if not chase.is_empty():
		if chase.hp<=0:
			chase = {}
			return Vector2.ZERO
		if _reach_of(chase) and _clear_path(player.pos,chase.pos):
			player.angle = (chase.pos-player.pos).angle()
			chase = {}
			move_path = PackedVector2Array()
			_request_attack()
			return Vector2.ZERO
		move_repath -= dt
		if move_repath<=0 or move_path.is_empty():
			move_repath = 0.25
			_path_to(chase.pos)
	elif move_held and pointer_active:
		move_repath -= dt
		if move_repath<=0:
			move_repath = 0.12
			_path_to(_world(_pointer_local()))
	while not move_path.is_empty() and player.pos.distance_to(move_path[0])<(0.12 if move_path.size()==1 else 0.35):
		move_path.remove_at(0)
	if move_path.is_empty(): return Vector2.ZERO
	return _iso(move_path[0]-player.pos).normalized()

## Clicking a loot plate picks it up, walking over to it first if needed.
func _walk_to_drop(d: Dictionary) -> void:
	if d.taken: return
	if d.pos.distance_to(player.pos)<1.3:
		_collect(d)
		return
	walk_target = d
	walk_time = 0.0

func _update(dt: float) -> void:
	elapsed += dt
	player.mana = minf(player.max_mana,player.mana+stats.mana_regen*dt)
	level_banner = maxf(0,level_banner-dt)
	for entry in loot_feed: entry.life -= dt
	loot_feed = loot_feed.filter(func(entry): return entry.life>0)
	_update_statuses(dt)
	Elites.update_hero_burn(self,dt)
	Elites.update_hazards(self,dt)
	for key in ["attack","nova","dodge","inv","roll"]: player[key] = maxf(0,player[key]-dt)
	combo_window = maxf(0,combo_window-dt)
	attack_buffer = maxf(0,attack_buffer-dt)
	_update_hero(dt)
	Classes.update(self,dt)
	_reveal()
	EnemyAI.update_all(self,dt)
	if state!="play": return
	_update_drops(dt)
	_update_effects(dt)
	camera = camera.lerp(_iso(player.pos)+screen_velocity*0.04,1-exp(-12*dt))
	shake = maxf(0,shake-dt*25)
	if victory_timer>=0 and state=="play":
		victory_timer -= dt
		if victory_timer<=0: _finish(true)

## Burning and poisoned enemies take damage over time; chill wears off.
func _update_statuses(dt: float) -> void:
	for e in enemies:
		if e.hp<=0: continue
		e.chill = maxf(0,e.get("chill",0.0)-dt)
		for kind in ["burn","poison"]:
			if e.get(kind,0.0)<=0: continue
			e[kind] -= dt
			e[kind+"_tick"] = e.get(kind+"_tick",0.0)+dt
			if e[kind+"_tick"]>=0.5:
				e[kind+"_tick"] = 0.0
				var color = Items.ELEMENT_COLORS.fire if kind=="burn" else Items.ELEMENT_COLORS.poison
				_damage_enemy(e,maxi(1,roundi(e[kind+"_dps"]*0.5)),false,color)
				if e.hp>0: Effects.add(self,"spark",{"pos":e.pos,"z":_between(10,30),"vel":Vector2(_between(-1,1),_between(-1,1)),"vz":_between(20,50),"color":color},0.4)

func _update_hero(dt: float) -> void:
	var input_direction = _screen_movement()
	if input_direction!=Vector2.ZERO:
		chase = {}; combat_target = {}; move_path = PackedVector2Array(); move_held = false
	elif walk_target==null:
		input_direction = _click_direction(dt)
	if not player.channel.is_empty() and player.channel.kind=="dash":
		walk_blend = 1.0
		display_angle = player.angle
		return
	if walk_target!=null:
		walk_time += dt
		if input_direction!=Vector2.ZERO or walk_target.taken or walk_time>4.0: walk_target = null
		elif walk_target.pos.distance_to(player.pos)<0.6:
			_collect(walk_target)
			walk_target = null
		else: input_direction = _iso(walk_target.pos-player.pos).normalized()
	var previous_position = player.pos
	if player.roll>0:
		var speed = lerpf(430,720,player.roll/DODGE_DURATION)
		_move(player,_screen_to_world_delta(player.roll_dir*speed*dt))
		ghost_timer -= dt
		if ghost_timer<=0:
			ghost_timer = 0.04
			Effects.ghost(self,world_view.characters.hero_state())
	else:
		var acceleration = RUN_BRAKE if input_direction==Vector2.ZERO else RUN_ACCEL
		screen_velocity = screen_velocity.move_toward(input_direction*_run_speed(),acceleration*dt)
		_move(player,_screen_to_world_delta(screen_velocity*dt))
		var actual_motion = _iso(player.pos-previous_position)
		if dt>0: screen_velocity = actual_motion/dt
		player.step += actual_motion.length()*0.085
		if not swing.is_empty(): player.angle = swing.angle
		elif not player.channel.is_empty(): pass
		elif player.attack>0 and Classes.ranged(self): pass
		elif attack_held and chase.is_empty(): _aim()
		elif input_direction!=Vector2.ZERO: player.angle = _screen_to_world_delta(input_direction).angle()
	walk_blend = lerpf(walk_blend,clampf(screen_velocity.length()/RUN_SPEED,0,1),1-exp(-20*dt))
	display_angle = lerp_angle(display_angle,player.angle,1-exp(-22*dt))
	if not swing.is_empty():
		swing.age += dt
		if not swing.resolved and swing.age>=swing.contact:
			swing.resolved = true
			_resolve_swing()
		if swing.age>=swing.duration: swing.clear()
	if player.roll<=0 and player.attack<=0:
		if attack_buffer>0: _basic_attack(buffered_auto_aim)
		elif (attack_held and chase.is_empty() and move_path.is_empty()) or keys.has(KEY_J): _basic_attack(keys.has(KEY_J))

func _update_drops(dt: float) -> void:
	for d in drops:
		d.age = d.get("age",1.0)+dt
		if d.age<LootView.POP_TIME: continue
		var distance = d.pos.distance_to(player.pos)
		# Gold and potions are picked up on contact. Items too, unless the hero dropped them.
		if d.kind!="item" and distance<1.1: _collect(d)
		elif d.kind=="item" and distance<0.7 and not d.get("manual",false): _collect(d)
		# Gold drifts to the hero only when nothing is in the way.
		elif d.kind=="gold" and distance<2.8 and _clear_path(d.pos,player.pos): d.pos += (player.pos-d.pos)*dt*6
	drops = drops.filter(func(d): return not d.taken)

func _update_effects(dt: float) -> void:
	for p in particles:
		p.life -= dt
		p.pos += p.velocity*dt
		if p.hostile:
			if not _walkable(p.pos): p.life = 0
			if p.pos.distance_to(player.pos)<0.45:
				var hp_before = player.hp
				_hurt(p.get("damage",13+floor_number*3))
				if player.hp<hp_before and p.has("source"): Elites.on_hit_hero(self,p.source,hp_before-player.hp)
				p.life = 0
		else:
			p.z += p.vz*dt
			p.vz -= 100*dt
	particles = particles.filter(func(p): return p.life>0)
	for t in texts: t.life -= dt
	texts = texts.filter(func(t): return t.life>0)
	for w in waves: w.life -= dt
	waves = waves.filter(func(w): return w.life>0)
	Effects.update(self,dt)
	hurt_flash = maxf(0,hurt_flash-dt*3)
	notice_time = maxf(0,notice_time-dt)

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if player.is_empty() or painter==null: return
	painter.alpha = 1
	var shake_offset = Vector2(sin(clock*120),cos(clock*95)*0.6)*shake
	world_view.draw(shake_offset)

## Called by the HUD layer: screen-space overlays, HUD and menus.
func draw_screen_layer(canvas: CanvasItem) -> void:
	if player.is_empty() or painter==null: return
	buttons.clear()
	painter.canvas = canvas
	painter.alpha = 1
	world_view.draw_screen_overlays(canvas)
	hud_view.draw()
	painter.canvas = self

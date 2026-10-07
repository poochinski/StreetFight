extends RefCounted
## godot --headless --path . -- --smoke-test
## Uses a separate test checkpoint and never touches normal game progress.

const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const Synth = preload("res://scripts/synth.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")
const Items = preload("res://scripts/items.gd")
const Inventory = preload("res://scripts/inventory.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Classes = preload("res://scripts/classes.gd")

static func run(g) -> void:
	var failures: Array[String] = []
	var check = func(condition: bool,message: String):
		if not condition:
			failures.append(message)
			push_error(message)
	_dungeons(g,check)
	_movement(g,check)
	_combat(g,check)
	_enemies(g,check)
	_progression(g,check)
	_classes(g,check)
	_click_to_move(g,check)
	g._begin()
	_items(g,check)
	var finished: Array = []
	_inventory(g,check,finished)
	check.call(not finished.is_empty(),"Inventory checks ran to the end")
	for shape in ["triangle","saw","sine"]:
		var audio = Synth.make_tone(440,0.15,shape,0.045)
		check.call(audio.data.size()==6616 and audio.mix_rate==22050,"Synthesized %s sound data" % shape)
	var stream = Synth.make_tone(440,0.15,"triangle",0.045)
	var peak = 0
	for i in range(0,stream.data.size(),2): peak = maxi(peak,absi(stream.data.decode_s16(i)))
	check.call(peak>100 and peak<32767,"Audio has a non-silent bounded waveform")
	if failures.is_empty():
		print("PASS: 60 connected city floors with wide streets, an open subway entrance, a quiet start and props that never wall anything off; equal eight-way speed; 15/30/60/144 FPS motion; braking/reversal; swept collision and sliding; visible-body aim; timed damage; buffered combo/finisher; no double hits; dodge cancellation; enemy line of sight, pathfinding, wind-ups and spacing; walled nova and mana; three classes, their skills and unlock levels; click-to-move and chase; leveling pace; progression; stat points; item generation; equip, swap, sockets, salvage, sort; elemental effects; loot pickup; saves; menus; audio.")
	else: print("FAIL: ",failures)
	g.get_tree().quit(0 if failures.is_empty() else 1)

## Removes randomness from combat: no crits or evades, and a fixed-damage blade.
static func _steady(g) -> void:
	g.player.attributes.dexterity = 0
	g.player.equipment.weapon.min = 15
	g.player.equipment.weapon.max = 15
	g._recalc()

static func _dungeons(g, check: Callable) -> void:
	g._begin()
	var signed_floors = 0
	for sample in 60:
		g.seed_value = sample+1
		g._generate(sample%3+1)
		var start = Vector2i(floori(g.player.pos.x),floori(g.player.pos.y))
		var visited = {start:true}
		var queue = [start]
		var cursor = 0
		while cursor<queue.size():
			var cell = queue[cursor]
			cursor += 1
			for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next = cell+dir
				if g.cells.has(next) and not visited.has(next):
					visited[next] = true
					queue.append(next)
		check.call(visited.size()==g.cells.size(),"Disconnected floor %d" % sample)
		check.call(visited.has(Vector2i(floori(g.stairs.x),floori(g.stairs.y))),"Stairs unreachable")
		check.call(g.rooms.size()>=6,"Floors have at least six rooms")
		check.call(g._free(g.player.pos,0.22),"Hero starts on open floor")
		for e in g.enemies: check.call(g._walkable(e.pos),"Invalid enemy spawn")
		var far = g.enemies[g.enemies.size()-1]
		check.call(not EnemyAI._find_path(g,g.player.pos,far.pos).is_empty(),"Pathfinding reaches every room")
		# City layout: wide streets, an open subway entrance, a quiet start, props that never cut the map.
		for z in g.rooms:
			if z.type=="street": check.call(mini(z.w,z.h)>=6,"Streets are at least six cells wide")
		check.call(g._free(g.stairs,0.3),"Subway entrance is on open ground")
		for e in g.enemies:
			if e.kind!="boss": check.call(e.pos.distance_to(g.player.pos)>=9,"No enemies spawn at the start")
		var open_cells = 0
		for cell in g.cells:
			if not g.blocked.has(cell): open_cells += 1
		check.call(_open_reach(g,start)==open_cells,"Props never wall off part of a floor")
		if not g.signs.is_empty(): signed_floors += 1
	check.call(signed_floors>=50,"Building fronts carry neon signs")

## Open cells reachable from start without walking through props.
static func _open_reach(g, start: Vector2i) -> int:
	var visited = {start:true}
	var queue = [start]
	var cursor = 0
	while cursor<queue.size():
		var cell = queue[cursor]
		cursor += 1
		for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+dir
			if g.cells.has(next) and not g.blocked.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited.size()

static func _movement(g, check: Callable) -> void:
	g._begin()
	# Two rooms split by a one-cell wall: a huge step must not cross it.
	g.cells.clear(); g.blocked.clear(); g._carve(2,2,5,5); g._carve(8,2,5,5)
	g.player.pos = Vector2(4.5,4.5)
	g._move(g.player,Vector2(10,3))
	check.call(g._free(g.player.pos,0.22) and g.player.pos.x<7,"Swept collision cannot tunnel through walls")
	g.enemies.clear()
	# Measure travel in a clear arena, independently of camera and dungeon walls.
	g.cells.clear(); g.blocked.clear(); g._carve(1,1,44,44); g.props.clear()
	var distances: Array = []
	for direction_keys in [[KEY_D],[KEY_A],[KEY_W],[KEY_S],[KEY_W,KEY_D],[KEY_S,KEY_D],[KEY_W,KEY_A],[KEY_S,KEY_A]]:
		g.keys.clear(); g.screen_velocity = Vector2.ZERO; g.player.pos = Vector2(20,20)
		for key_code in direction_keys: g.keys[key_code] = true
		for frame in 60: g._advance_game(1.0/60)
		distances.append(g._iso(g.player.pos-Vector2(20,20)).length())
	for distance in distances:
		check.call(absf(distance-distances[0])<0.02,"Equal visible speed in all eight directions")
	check.call(distances[0]>165 and distances[0]<g.RUN_SPEED,"Quick acceleration to running speed")
	var rates: Array = []
	for fps in [15,30,60,144]:
		g.keys.clear(); g.keys[KEY_D] = true
		g.screen_velocity = Vector2.ZERO; g.player.pos = Vector2(20,20)
		for frame in fps: g._advance_game(1.0/fps)
		rates.append(g._iso(g.player.pos-Vector2(20,20)).length())
	for distance in rates: check.call(absf(distance-rates[0])<0.35,"Consistent motion at 15/30/60/144 FPS")
	var stop_position = g.player.pos
	g.keys.clear()
	g._advance_game(0.1)
	check.call(g.screen_velocity.length()<0.01 and g._iso(g.player.pos-stop_position).length()<4,"Release stops promptly without skating")
	g.keys[KEY_D] = true; g._advance_game(0.1)
	g.keys.clear(); g.keys[KEY_A] = true; g._advance_game(0.12)
	check.call(g.screen_velocity.x < -g.RUN_SPEED*0.9,"Direction reversal stays responsive")
	g.keys.clear(); g.screen_velocity = Vector2.ZERO
	# Slide along a wall without jumping through it.
	g.cells.clear(); g.blocked.clear(); g._carve(3,3,2,12)
	g.player.pos = Vector2(4.7,5)
	g._move(g.player,Vector2(5,2))
	check.call(g.player.pos.x<4.8 and g.player.pos.y>6.8 and g._free(g.player.pos,0.22),"Wall sliding and swept collision")

static func _combat(g, check: Callable) -> void:
	g._begin()
	_steady(g)
	g.enemies.clear(); g.props.clear()
	var original_point = Vector2(12.75,8.5)
	check.call(g._world(g._project(original_point)).distance_to(original_point)<0.00001,"Mouse/world projection round trip")
	g.player.inv = 0
	g._hurt(20)
	check.call(g.player.hp==120-roundi(20*(1-g.stats.reduction)) and g.player.hp<120,"Incoming damage reduced by armor")
	g._potion()
	check.call(g.player.hp==120 and g.player.potions==2,"Healing potion")
	g._gain_xp(g._xp_needed())
	check.call(g.player.level==2 and g.player.max_hp==140 and g.player.points==5,"Leveling grants health and stat points")
	var before_points = g._damage()
	g._activate("stat:strength")
	check.call(g._damage()>before_points and g.player.points==4,"Spending Strength raises damage")
	g._activate("stat:vitality",false,true)
	check.call(g.player.points==0 and g.player.max_hp==140+16 and g.player.hp==g.player.max_hp,"Shift-click spends several points; Vitality raises health")
	var enemy = g._spawn_enemy("imp",g.player.pos+Vector2(1,0))
	enemy.hp = 200.0; enemy.max_hp = 200.0; enemy.attack = 100.0
	g.buttons.clear()
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = g._to_screen(g._project(enemy.pos,32))
	click.pressed = true
	var before_click = g.player.pos
	g._input(click)
	check.call(not g.swing.is_empty() and enemy.hp==200 and g.player.pos==before_click,"Click starts swing immediately without click-to-move")
	check.call(absf(wrapf(g.swing.angle-(enemy.pos-g.player.pos).angle(),-PI,PI))<0.01,"Clicking the visible enemy body aims at that enemy")
	click.pressed = false; g._input(click)
	g._advance_game(g.swing.contact-0.015)
	check.call(enemy.hp==200,"Melee does not land before the blade contact time")
	g._advance_game(0.025)
	check.call(enemy.hp<200 and g.player.pos==before_click,"Damage lands during the visible swing without moving the hero")
	var hp_after = enemy.hp
	g._slash()
	check.call(enemy.hp==hp_after and g.player.attack>0,"Repeated calls cannot bypass recovery")
	click.pressed = false
	g._input(click)
	check.call(not g.attack_held,"Mouse release stops attack")
	g._advance_game(maxf(0,g.player.attack-0.09))
	g._request_attack(true)
	check.call(g.attack_buffer>0,"Early click is buffered")
	g._advance_game(0.10)
	check.call(g.combo_index==1 and not g.swing.is_empty(),"Buffered click chains the second swing")
	g._advance_game(g.swing.contact+0.01)
	var second_damage = hp_after-enemy.hp
	check.call(second_damage>0,"Second swing hits")
	var second_hp = enemy.hp
	g._advance_game(minf(0.06,g.player.attack-0.02))
	check.call(enemy.hp==second_hp,"Each swing damages an enemy only once")
	g._advance_game(maxf(0,g.player.attack-0.09))
	g._request_attack(true)
	g._advance_game(0.10)
	check.call(g.combo_index==2,"Third swing completes the combo")
	g._advance_game(g.swing.contact+0.01)
	check.call(second_hp-enemy.hp>second_damage,"Third strike is a stronger finisher")
	hp_after = enemy.hp
	var mana_before = g.player.mana
	g._nova()
	check.call(enemy.hp<hp_after and g.player.nova==g.NOVA_COOLDOWN and g.player.mana==mana_before-g.NOVA_COST,"Nova damage, mana cost and six-second cooldown")
	g._dodge()
	var health_before = g.player.hp
	g._hurt(999)
	check.call(g.player.hp==health_before and is_equal_approx(g.player.dodge,g.DODGE_COOLDOWN) and g.swing.is_empty(),"Dodge cancels attacks and grants invulnerability")
	# A cancelled wind-up must never inflict a delayed ghost hit.
	g.player.roll = 0; g.player.dodge = 0; g.player.attack = 0
	g._slash(true)
	g._dodge()
	var after_cancel = enemy.hp
	g._advance_game(0.08)
	check.call(enemy.hp==after_cancel and g.swing.is_empty(),"Cancelled attack cannot resolve later")
	# Holding attack should repeat naturally, without generating multiple hits per swing.
	g.player.roll = 0; g.player.attack = 0; g.attack_buffer = 0; g.swing.clear()
	enemy.pos = g.player.pos+Vector2(0.7,0); enemy.hp = 1000; enemy.attack = 100
	g.keys[KEY_J] = true
	for i in 4: g._advance_game(0.25)
	g.keys.clear()
	check.call(enemy.hp<950 and enemy.hp>850,"Holding J chains bounded repeated attacks")
	# Neither assisted aiming nor a wide melee arc should reach through a wall.
	g.player.roll = 0; g.player.attack = 0; g.swing.clear()
	g.cells.clear(); g.blocked.clear(); g._carve(1,1,20,20)
	g.player.pos = Vector2(7.5,7.5); enemy.pos = Vector2(9.1,7.5); enemy.hp = 1000
	g.cells.erase(Vector2i(8,7))
	g.pointer_active = true; g.pointer = g._to_screen(g._project(enemy.pos,28))
	g._slash()
	g._advance_game(0.09)
	check.call(enemy.hp==1000,"Melee and targeting cannot hit through a wall")

## A 20x10 arena split by a wall at x=11 with a gap in the bottom row.
static func _walled_arena(g) -> void:
	g.enemies.clear(); g.props.clear(); g.drops.clear(); g.particles.clear()
	g.cells.clear(); g.blocked.clear()
	g._carve(1,1,20,10)
	for y in range(1,10): g.cells.erase(Vector2i(11,y))
	DungeonGenerator.build_navigation(g)
	g.keys.clear(); g.attack_held = false; g.swing.clear(); g.screen_velocity = Vector2.ZERO
	g.player.roll = 0; g.player.attack = 0; g.player.dodge = 0; g.player.nova = 0

## Every class: its basic attack lands, each skill is locked until its level and
## then hits, and leveling is slow enough to take the whole game to reach level 6.
static func _classes(g, check: Callable) -> void:
	g._begin()
	var total = 0
	for level in range(1,6):
		g.player.level = level
		total += g._xp_needed()
	check.call(total>=1200 and total<=2000,"Reaching level 6 takes most of the game (%d XP)" % total)
	print("Class checks: %d XP to reach level 6" % total)
	for id in Classes.ORDER:
		g._begin(false,id)
		check.call(g.player["class"]==id and g.player.attributes==Classes.CLASSES[id].attributes,"%s starts with its own attributes" % id)
		_steady(g)
		_walled_arena(g)
		g.player.pos = Vector2(4.5,5.5)
		g.player.angle = 0.0
		g.pointer_active = false
		var enemy = g._spawn_enemy("brute",Vector2(6.5,5.5))
		if id=="samurai": enemy.pos=g.player.pos+Vector2(1.25,0)
		enemy.hp = 5000.0; enemy.max_hp = 5000.0; enemy.attack = 100.0
		g._request_attack(true)
		for k in 4: g._advance_game(0.2)
		check.call(enemy.hp<5000,"%s basic attack hits" % id)
		g.player.mana = g.player.max_mana
		var mana = g.player.mana
		Classes.cast(g,1)
		check.call(g.player.mana==mana and Classes.cooldown_left(g,Classes.skill_ids(g)[1])==0,"%s second skill is locked at level 1" % id)
		g.player.level = 6
		g._recalc()
		for i in 4:
			var skill: String = Classes.skill_ids(g)[i]
			enemy.pos = Vector2(6.5,5.5); enemy.hp = 5000.0; enemy.stagger = 0.0
			g.player.pos = Vector2(4.5,5.5); g.player.channel = {}; g.player.attack = 0; g.player.nova = 0; g.player.cd = {}
			g.player.mana = g.player.max_mana
			g.seen[Vector2i(enemy.pos)] = true
			g.pointer = g._to_screen(g._project(enemy.pos,30)); g.pointer_active = true
			Classes.cast(g,i)
			check.call(Classes.cooldown_left(g,skill)>0,"%s goes on cooldown" % skill)
			for k in 9: g._advance_game(0.2)
			check.call(enemy.hp<5000,"%s hits its target" % skill)
		g.enemies.clear(); g.shots.clear(); g.zones.clear(); g.player.channel = {}
		g.pointer_active = false

## Clicking open ground walks there, around walls; clicking a far enemy runs over and attacks.
static func _click_to_move(g, check: Callable) -> void:
	g._begin()
	_steady(g)
	_walled_arena(g)
	g.player.pos = Vector2(3.5,5.5)
	g.pointer_active = true
	g.pointer = g._to_screen(g._project(Vector2(8.5,5.5)))
	g._mouse_down()
	g.move_held = false
	for k in 12: g._advance_game(0.2)
	check.call(g.player.pos.distance_to(Vector2(8.5,5.5))<0.4,"Clicking the ground walks there")
	g.pointer = g._to_screen(g._project(Vector2(15.5,3.5)))
	g._mouse_down()
	g.move_held = false
	for k in 40: g._advance_game(0.2)
	check.call(g.player.pos.distance_to(Vector2(15.5,3.5))<0.5,"Click-to-move finds a way around walls")
	var enemy = g._spawn_enemy("imp",Vector2(15.5,8.5))
	enemy.hp = 500.0; enemy.max_hp = 500.0; enemy.attack = 100.0
	g.player.pos = Vector2(15.5,2.5)
	g.seen[Vector2i(enemy.pos)] = true
	g.pointer = g._to_screen(g._project(enemy.pos,30))
	g._mouse_down()
	for k in 15: g._advance_game(0.2)
	g.attack_held = false
	check.call(enemy.hp<500 and g.player.pos.distance_to(enemy.pos)<3.0,"Clicking a distant enemy runs over and attacks it")
	g.enemies.clear()

static func _enemies(g, check: Callable) -> void:
	g._begin()
	_steady(g)
	_walled_arena(g)
	g.player.pos = Vector2(8.5,5.5); g.player.inv = 999
	var hidden = g._spawn_enemy("imp",Vector2(13.5,5.5))
	hidden.attack = 100
	g._advance_game(0.2)
	check.call(not hidden.alert,"Enemies do not notice the hero through walls")
	hidden.alert = true
	for i in 30: g._advance_game(0.2)
	check.call(hidden.pos.distance_to(g.player.pos)<1.5,"Alerted enemies path around walls to reach the hero")
	check.call(hidden.pos.distance_to(g.player.pos)>0.45,"Enemies keep their bodies out of the hero")
	# Nova is blocked by walls but hits enemies in the open.
	_walled_arena(g)
	g.player.pos = Vector2(9.5,5.5)
	var behind_wall = g._spawn_enemy("brute",Vector2(13.0,5.5))
	var in_open = g._spawn_enemy("brute",Vector2(9.5,8.5))
	behind_wall.attack = 100; in_open.attack = 100
	g._nova()
	check.call(behind_wall.hp==behind_wall.max_hp and in_open.hp<in_open.max_hp,"Ember Nova does not pass through walls")
	# Melee enemies telegraph before hitting; standing still gets hit, stepping away or dodging avoids it.
	for outcome in ["stand","step","dodge"]:
		_walled_arena(g)
		g.player.pos = Vector2(5.5,5.5); g.player.inv = 0; g.player.hp = g.player.max_hp; g.player.nova = 0
		var imp = g._spawn_enemy("imp",Vector2(6.4,5.5))
		imp.alert = true; imp.attack = 0
		g._advance_game(0.05)
		check.call(imp.windup>0 and g.player.hp==g.player.max_hp,"Melee enemies wind up before hitting (%s)" % outcome)
		if outcome=="step": g.player.pos = Vector2(3.0,5.5)
		if outcome=="dodge": g._dodge()
		for i in 3: g._advance_game(0.15)
		if outcome=="stand": check.call(g.player.hp<g.player.max_hp,"A completed wind-up hits a hero in reach")
		else: check.call(g.player.hp==g.player.max_hp,"Leaving reach or dodging avoids a wind-up (%s)" % outcome)
	# Hitting an imp interrupts its wind-up; a brute powers through and must be dodged.
	for kind in ["imp","brute"]:
		_walled_arena(g)
		g.player.pos = Vector2(5.5,5.5); g.player.inv = 0; g.player.hp = g.player.max_hp
		var attacker = g._spawn_enemy(kind,Vector2(6.4,5.5))
		attacker.alert = true; attacker.attack = 0; attacker.hp = 1000.0
		g._advance_game(0.05)
		g.player.angle = 0
		g._slash(true)
		for i in 4: g._advance_game(0.15)
		if kind=="imp": check.call(g.player.hp==g.player.max_hp,"Hitting an imp interrupts its wind-up")
		else: check.call(g.player.hp<g.player.max_hp,"A brute's wind-up cannot be interrupted")
	# Large enemies are hit at the edge of their body.
	_walled_arena(g)
	g.player.pos = Vector2(4.5,5.5); g.player.angle = 0
	var boss = g._spawn_enemy("boss",Vector2(4.5+g.MELEE_REACH+0.2,5.5))
	boss.attack = 100
	g._slash(true)
	g._advance_game(g.swing.contact+0.01)
	check.call(boss.hp<boss.max_hp,"Melee reaches the edge of a large enemy")

static func _progression(g, check: Callable) -> void:
	g._begin()
	g._generate(1)
	var key = InputEventKey.new()
	key.physical_keycode = KEY_I; key.pressed = true
	g._input(key)
	check.call(g.state=="inventory" and g.panels.inventory,"I opens the inventory page")
	g._input(key)
	check.call(g.state=="play","I closes the inventory page")
	key.physical_keycode = KEY_C
	g._input(key)
	key.physical_keycode = KEY_I
	g._input(key)
	check.call(g.panels.character and g.panels.inventory and g.state=="inventory","C and I open both pages together")
	key.physical_keycode = KEY_ESCAPE
	g._input(key)
	check.call(g.state=="play" and not g.panels.character and not g.panels.inventory,"Esc closes the pages before pausing")
	g._pause()
	check.call(g.state=="paused" and g.keys.is_empty() and not g.attack_held,"Pause releases controls")
	g._pause()
	g.props = [{"pos":g.player.pos,"kind":"chest","open":false}]
	g._interact()
	check.call(g.props[0].open and g.drops.any(func(d): return d.kind=="item"),"Chest opens and drops loot")
	g.drops.clear()
	g.player.pos = g.stairs
	g.player.gold = 50; g.player.potions = 0
	var helmet = Items.generate(g,1,2,"helmet")
	g.player.equipment.helmet = helmet
	g.player.bag[3] = Items.make_gem("ruby",1)
	g._recalc()
	g._interact()
	check.call(g.floor_number==2 and g.player.potions==3 and g.player.gold==5,"Stairs progression and restock")
	var saved = g._load_save()
	check.call(not saved.is_empty() and int(saved.floor)==2,"Checkpoint serialization")
	var saved_hp = g.player.hp
	var damage = g._damage()
	g.player.hp = 1
	g._begin(true)
	check.call(g.floor_number==2 and g.player.hp==saved_hp and g._damage()==damage,"Continue restores checkpoint stats")
	check.call(g.player.equipment.helmet!=null and g.player.equipment.helmet.name==helmet.name and g.player.bag[3]!=null and g.player.bag[3].gem=="ruby","Continue restores equipment and bag")
	g._generate(3)
	var boss_found = false
	for boss in g.enemies:
		if boss.kind=="boss":
			boss_found = true
			g._damage_enemy(boss,9999)
	check.call(boss_found and g.drops.any(func(d): return d.kind=="item" and int(d.item.rarity)==4),"The Warden drops a Legendary item")
	g.enemies.clear()
	g._update(0.9)
	check.call(g.state=="victory" and g._load_save().is_empty(),"Boss victory clears checkpoint")
	g._begin()
	g.player.inv = 0
	g.player.attributes.dexterity = 0
	g._recalc()
	g._hurt(9999)
	check.call(g.state=="defeat" and g._load_save().is_empty(),"Defeat clears checkpoint")

static func _items(g, check: Callable) -> void:
	g._begin()
	var counts_ok = true
	var names_ok = true
	var sockets_ok = true
	var colors = {}
	for i in 400:
		var rarity = i%5
		var item = Items.generate(g,1+i%12,rarity)
		var range_count = Items.AFFIX_COUNT[rarity]
		var allowed = 0
		for k in Items.AFFIXES:
			if item.slot in Items.AFFIXES[k].slots: allowed += 1
		if item.affixes.size()<mini(range_count[0],allowed) or item.affixes.size()>range_count[1]: counts_ok = false
		if item.name.strip_edges()=="" : names_ok = false
		if int(item.sockets)>2 or (int(item.sockets)>0 and not item.slot in Items.SOCKET_SLOTS): sockets_ok = false
		if not SaveGame._valid_item(item): counts_ok = false
		colors[Items.color(item)] = true
	check.call(counts_ok,"Affix counts follow rarity and items validate")
	check.call(names_ok,"Every item has a name")
	check.call(sockets_ok,"Sockets only on weapons, helmets, chests and amulets")
	check.call(colors.size()==5,"Five rarity colors")
	var weak = Items.generate(g,1,0,"weapon")
	var strong = Items.generate(g,6,3,"weapon")
	check.call(Items.dps(strong)>Items.dps(weak),"Higher level and rarity weapons hit harder")
	check.call(Items.upgrade_steps(strong,g.player.equipment)>0,"A stronger weapon shows as an upgrade")
	weak.min = 2; weak.max = 3
	check.call(Items.upgrade_steps(weak,g.player.equipment)<0,"A weaker weapon shows as a downgrade")
	var rarities = [0,0,0,0,0]
	for i in 3000: rarities[Items.roll_rarity(g)] += 1
	check.call(rarities[0]>rarities[1] and rarities[1]>rarities[2] and rarities[2]>rarities[3] and rarities[3]>rarities[4] and rarities[4]>0,"Rarer tiers drop less often")
	# Elemental weapons: fire burns, ice chills and slows.
	_walled_arena(g)
	g.player.pos = Vector2(5.5,5.5); g.player.angle = 0
	g.player.attributes.dexterity = 0
	var blade = Items.generate(g,1,1,"weapon")
	blade.affixes = [["fire",6],["ice",4]]
	g.player.equipment.weapon = blade
	g._recalc()
	var target = g._spawn_enemy("brute",Vector2(6.6,5.5))
	target.hp = 1000.0; target.attack = 100; target.alert = true
	g._slash(true)
	g._advance_game(g.swing.contact+0.01)
	check.call(target.get("burn",0.0)>0 and target.get("chill",0.0)>0,"Fire burns and ice chills on hit")
	var burning = target.hp
	g._advance_game(0.25); g._advance_game(0.25); g._advance_game(0.2)
	check.call(target.hp<burning,"Burning deals damage over time")
	g.player.pos = Vector2(2.5,5.5)
	target.chill = 5.0; target.attack = 100
	var start = target.pos
	g._advance_game(0.5)
	var chilled_distance = target.pos.distance_to(start)
	target.chill = 0.0; target.burn = 0.0; target.poison = 0.0
	target.pos = start
	g._advance_game(0.5)
	check.call(chilled_distance<target.pos.distance_to(start)*0.7,"Chilled enemies move slower")
	g.player.mana = 0; g.player.nova = 0
	g._nova()
	check.call(g.player.nova==0,"Nova needs mana")

static func _inventory(g, check: Callable, finished: Array) -> void:
	g._begin()
	g.drops.clear()
	# Items found for an empty slot are worn straight away.
	var ring = Items.generate(g,1,2,"ring")
	g._drop_item(g.player.pos,ring)
	g._advance_game(0.25); g._advance_game(0.25)
	if not g.drops.is_empty(): g.player.pos = g.drops[0].pos
	g._advance_game(0.1)
	check.call(g.player.equipment.ring1==ring and g.drops.is_empty(),"Walking over loot picks it up and fills an empty slot")
	# Others go to the bag; right-click swaps them in.
	var sword = Items.generate(g,1,3,"weapon")
	check.call(Inventory.store(g,sword) and g.player.bag[0]==sword,"Found gear goes in the bag")
	var starter = g.player.equipment.weapon
	g._activate("bag:0",true)
	check.call(g.player.equipment.weapon==sword and g.player.bag[0]==starter,"Right-click equips and swaps")
	g._activate("equip:weapon",true)
	check.call(g.player.equipment.weapon==null and g.player.bag.has(sword),"Right-click unequips into the bag")
	var index = g.player.bag.find(sword)
	g._activate("bag:%d" % index)
	check.call(g.held==sword and g.player.bag[index]==null,"Click picks an item up")
	g._activate("equip:helmet")
	check.call(g.held==sword and g.player.equipment.helmet==null,"An item cannot go in the wrong slot")
	g._activate("equip:weapon")
	check.call(g.held==null and g.player.equipment.weapon==sword,"Clicking a slot equips the held item")
	var heavy = Items.generate(g,9,2,"chest")
	Inventory.store(g,heavy)
	g._activate("bag:%d" % g.player.bag.find(heavy),true)
	check.call(g.player.equipment.chest!=heavy,"Level requirements block equipping")
	# Gems: pick up, click an item with an open socket.
	var amulet = Items.generate(g,1,2,"amulet")
	amulet.sockets = 1
	g.player.equipment.amulet = amulet
	var gem = Items.make_gem("ruby",2)
	Inventory.store(g,gem)
	g._recalc()
	var strength = g.stats.strength
	g._activate("bag:%d" % g.player.bag.find(gem))
	g._activate("equip:amulet")
	check.call(amulet.gems.size()==1 and g.held==null and g.stats.strength==strength+Items.gem_effect(gem,false)[1],"Socketed gems add their bonus")
	# Salvage, sort and drop.
	var gold = g.player.gold
	var junk = Items.generate(g,1,0,"belt")
	var junk_index = Inventory.first_free(g)
	g.player.bag[junk_index] = junk
	g._activate("bag:%d" % junk_index,false,true)
	check.call(g.player.gold==gold+int(junk.value) and g.player.bag[junk_index]==null,"Shift-click salvages for gold")
	g.player.bag[30] = Items.generate(g,1,4,"weapon")
	Inventory.sort(g)
	check.call(g.player.bag[0]!=null and g.player.bag[0].slot=="weapon" and int(g.player.bag[0].rarity)==4,"Sort puts the best weapons first")
	g._toggle_panel("inventory")
	g._activate("bag:0")
	var carried = g.held
	g.pointer = Vector2(640,400)
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = g.pointer
	g.buttons.clear()
	g._input(click)
	check.call(g.held==null and g.drops.any(func(d): return d.get("item")==carried and d.manual),"Clicking the world drops the held item")
	g._close_panels()
	g._advance_game(0.25); g._advance_game(0.25)
	check.call(g.drops.any(func(d): return d.get("item")==carried),"Dropped items are not picked straight back up")
	var dropped = g.drops.filter(func(d): return d.get("item")==carried)[0]
	g._walk_to_drop(dropped)
	check.call(g.player.bag.has(carried),"Clicking a nearby loot plate picks it up")
	while Inventory.first_free(g)>=0:
		g.player.bag[Inventory.first_free(g)] = Items.make_gem("topaz",0)
	var spare = Items.generate(g,1,1,"boots")
	g.player.equipment.boots = Items.generate(g,1,1,"boots")
	check.call(not Inventory.store(g,spare),"A full bag refuses new items")
	finished.append(true)

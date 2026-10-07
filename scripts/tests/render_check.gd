extends RefCounted
## godot --path . -- --render-check
## Renders previews from the actual game into previews/ and exits.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Classes = preload("res://scripts/classes.gd")
const Elites = preload("res://scripts/elites.gd")

static func _capture(g, filename: String) -> void:
	g.queue_redraw()
	await g.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error = g.get_viewport().get_texture().get_image().save_png("res://previews/"+filename)
	if error!=OK: push_error("Preview capture failed: "+filename)

## Stands the hero at a point, lights the area around it and takes a picture.
static func _shot(g, at: Vector2, filename: String, enemies: bool = true) -> void:
	g.player.pos = at
	g.player.inv = 99
	if not enemies: g.enemies = g.enemies.filter(func(e): return e.pos.distance_to(at)>9)
	for k in 3: g._reveal()
	g.camera = g._iso(g.player.pos)
	if g.view3d: g.view3d.place_camera(g.player.pos)
	for frame in 4: await g.get_tree().process_frame
	await _capture(g,filename)

## The side areas, the food court and its panels, and a doorway on the street.
static func _zones(g) -> void:
	g.state = "play"
	g.run_seed = 777
	g.player.level = 4
	g._recalc()
	g._travel("street",1,"start")
	g.enemies.clear()
	var door = g.exits.filter(func(e): return e.to[0]=="mall")[0]
	await _shot(g,door.pos+door.face*2.4,"zone-street-mall-door.png")
	var gate = g.exits.filter(func(e): return e.to[0]=="park")[0]
	await _shot(g,gate.pos+gate.face*2.4,"zone-street-park-gate.png")
	g._travel("mall",1,"door")
	await _shot(g,g.arrivals.door+Vector2(6,0),"zone-mall.png")
	await _shot(g,Vector2(31.5,24.0),"zone-mall-cross.png")
	await _shot(g,g.arrivals.foodcourt,"zone-foodcourt.png")
	var pawn = g.props.filter(func(p): return p.get("vendor","")=="pawn")[0]
	g.player.pos = pawn.pos+Vector2(0,1.5)
	g.player.gold = 640
	g._interact()
	g.pointer = Vector2(-100,-100)
	await _capture(g,"zone-pawn.png")
	g._close_panels()
	var locker = g.props.filter(func(p): return p.kind=="stash")[0]
	g.player.pos = locker.pos+Vector2(0,1.5)
	g._interact()
	for i in 9: g.stash[i*3] = Items.generate(g,3+i%4,i%5)
	await _capture(g,"zone-stash.png")
	g._close_panels()
	var kiosk = g.props.filter(func(p): return p.kind=="transit")[0]
	g.player.pos = kiosk.pos+Vector2(0,1.5)
	g.visited["park:1"] = true
	g._interact()
	await _capture(g,"zone-transit.png")
	g._close_panels()
	g._travel("park",1,"door")
	await _shot(g,Vector2(32.5,36.0),"zone-park.png")
	await _shot(g,Vector2(44.0,22.5),"zone-park-bandshell.png")
	g._travel("warehouse",2,"door")
	await _shot(g,g.rooms[2].pos,"zone-warehouse.png")
	await _shot(g,g.arrivals.door,"zone-warehouse-entry.png")
	g._travel("subway",1,"west")
	await _shot(g,Vector2(22.0,25.0),"zone-subway.png")
	await _shot(g,g.arrivals.west,"zone-subway-stairs.png")

## Loot of every tier on the floor, a hovered loot plate, then both pages open with a tooltip.
static func _loot_and_pages(g) -> void:
	g.enemies.clear()
	g.drops.clear()
	g.player.level = 6
	g._recalc()
	var spots = [Vector2(1.6,-0.4),Vector2(1.2,1.2),Vector2(-0.6,1.7),Vector2(2.4,0.8),Vector2(0.4,2.4),Vector2(-1.5,0.6),Vector2(2.0,2.2),Vector2(-0.2,-1.6)]
	for i in 5:
		var item = Items.generate(g,4+i,i)
		g.drops.append({"pos":g.player.pos+spots[i],"kind":"item","item":item,"age":1.0,"taken":false,"manual":true})
	g.drops.append({"pos":g.player.pos+spots[5],"kind":"item","item":Items.make_gem("amethyst",2),"age":1.0,"taken":false,"manual":true})
	g.drops.append({"pos":g.player.pos+spots[6],"kind":"gold","value":37,"age":1.0,"taken":false})
	g.drops.append({"pos":g.player.pos+spots[7],"kind":"potion","age":1.0,"taken":false})
	for d in g.drops:
		if not g._walkable(d.pos): d.pos = g.player.pos+Vector2(0.9,0.9)
		g.seen[Vector2i(d.pos)] = true
	g.pointer = Vector2(-100,-100)
	await _capture(g,"loot.png")
	for b in g.buttons:
		if b.id.begins_with("loot:") and g.drops[int(b.id.split(":")[1])].kind=="item" and int(g.drops[int(b.id.split(":")[1])].item.rarity)==4:
			g.pointer = b.rect.get_center()
	await _capture(g,"loot-tooltip.png")
	g.drops.clear()
	# Fill the bag and equipment for the pages.
	for slot in ["helmet","gloves","boots","belt","amulet"]: g.player.equipment[slot] = Items.generate(g,5,1+randi()%3,slot)
	g.player.equipment.ring1 = Items.generate(g,5,2,"ring")
	g.player.equipment.weapon = Items.generate(g,6,3,"weapon")
	g.player.equipment.weapon.sockets = 2
	g.player.equipment.weapon.gems = [Items.make_gem("ruby",1)]
	for i in 22:
		var item = Items.make_gem(Items.GEMS.keys()[i%5],i%3) if i%6==5 else Items.generate(g,3+i%5,[0,0,1,1,2,2,3,4][i%8])
		g.player.bag[i] = item
	g.player.bag[0] = Items.generate(g,6,4,"weapon")
	g.player.points = 5
	g.player.gold = 1342
	g._recalc()
	g._toggle_panel("character")
	g._toggle_panel("inventory")
	await _capture(g,"pages.png")
	for b in g.buttons:
		if b.id=="bag:0": g.pointer = b.rect.get_center()
	await _capture(g,"pages-tooltip.png")
	# A stat explanation, the held-item cursor, then a skill tooltip in play.
	g.pointer = Vector2(120,200)
	await _capture(g,"pages-stat.png")
	g._activate("bag:3")
	g.pointer = Vector2(1000,470)
	await _capture(g,"pages-held.png")
	Inventory.stow_held(g)
	g._close_panels()
	for b in g.buttons:
		if b.id=="nova": g.pointer = b.rect.get_center()
	await _capture(g,"skill-tooltip.png")
	g.pointer = Vector2(-100,-100)
	g.player.level = 1
	g.player.points = 0
	g._recalc()

static func run(g) -> void:
	DirAccess.make_dir_recursive_absolute("res://previews")
	await _capture(g,"title.png")
	g.state = "create"
	g.chosen_class = "gunslinger"
	g.pointer = Vector2(-50,-50)
	await _capture(g,"create.png")
	g.chosen_class = "samurai"
	g._begin()
	g.level_banner = 0
	g.seed_value = 71283
	g._generate(1)
	for frame in 35: await g.get_tree().process_frame
	await _capture(g,"gameplay.png")
	if g.view3d:
		# Clicks map back to the ground point under the cursor in the 3D view.
		for offset in [Vector2(1.3,-0.7),Vector2(-3,2),Vector2(4,4)]:
			var point = g.player.pos+offset
			var back = g._world(g._project(point))
			if back.distance_to(point)>0.02:
				push_error("3D projection round trip failed: %s -> %s" % [point,back])
				g.get_tree().quit(1)
				return
		# The hero wears its equipped gear: the starter chest builds 3D parts.
		if g.view3d.hero==null or g.view3d.hero.get_meta("gear_nodes", []).is_empty():
			push_error("The 3D hero is not wearing its equipped gear")
			g.get_tree().quit(1)
			return
	# An elite pack: a rare leader with minions, and a champion.
	var pack: Array = []
	for k in 3: pack.append(g._spawn_enemy("brute" if k==0 else "imp",g.player.pos+Vector2(2.2+k*0.7,-1.6+k*0.8)))
	Elites.promote_pack(g,pack,"rare",2)
	var champion = g._spawn_enemy("ranged",g.player.pos+Vector2(-1.5,2.2))
	Elites._make_elite(g,champion,"champion",["turbo","molten"])
	pack.append(champion)
	for e in pack:
		e.alert = true; e.attack = 100.0; e.hp *= 0.7
	for frame in 8: await g.get_tree().process_frame
	await _capture(g,"elites.png")
	for e in pack: g.enemies.erase(e)
	# The subway entrance that leads down to the next floor.
	var start_pos = g.player.pos
	g.player.pos = g.stairs+Vector2(1.2,2.4)
	g.camera = g._iso(g.player.pos)
	if g.view3d: g.view3d.place_camera(g.player.pos)
	g._reveal()
	var near_enemies = g.enemies
	g.enemies = []
	await _capture(g,"subway.png")
	g.enemies = near_enemies
	g.player.pos = start_pos
	g.camera = g._iso(g.player.pos)
	await _loot_and_pages(g)
	g._pause()
	await _capture(g,"paused.png")
	# Also render a discovered combat room, damage particles, and a nova.
	g._pause()
	g.player.pos = g.rooms[1].pos
	g.camera = g._iso(g.player.pos)
	g._reveal()
	g.player.inv = 5
	g._nova()
	for frame in 5: await g.get_tree().process_frame
	await _capture(g,"combat.png")
	# Verify the health liquid clips to its orb at partial health.
	g.player.hp = g.player.max_hp*0.45
	await _capture(g,"partial-health.png")
	# An imp and a brute mid wind-up, showing the attack tell.
	g.enemies.clear(); g.particles.clear(); g.waves.clear(); g.texts.clear()
	g.player.pos = g.rooms[1].pos
	g.camera = g._iso(g.player.pos)
	for spec in [["imp",Vector2(1.0,0.2)],["brute",Vector2(-0.4,1.1)]]:
		var e = g._spawn_enemy(spec[0],g.player.pos+spec[1])
		e.alert = true
		e.windup_total = Data.ENEMIES[spec[0]].windup
		e.windup = e.windup_total*0.3
	g.state = "preview"
	await _capture(g,"windup.png")
	g.state = "play"
	# The full cast around the hero, then each floor's theme, then effects mid-flight.
	g.enemies.clear()
	g.player.equipment.weapon = Items.generate(g,5,2,"weapon")
	g.player.equipment.chest = Items.generate(g,5,2,"chest")
	g.player.equipment.helmet = Items.generate(g,5,2,"helmet")
	for spec in [["imp",Vector2(1.6,-0.6)],["brute",Vector2(-1.2,1.8)],["ranged",Vector2(2.2,1.4)]]:
		var e = g._spawn_enemy(spec[0],g.player.pos+spec[1])
		e.alert = true
	for frame in 3: await g.get_tree().process_frame
	g.state = "preview"
	await _capture(g,"characters.png")
	g.state = "play"
	for floor_number in [2,3]:
		g.seed_value = 4242+floor_number
		g._generate(floor_number)
		g.player.inv = 99
		if floor_number==3:
			g.player.pos = g.stairs+Vector2(0,3)
			for e in g.enemies:
				if e.kind=="boss":
					e.alert = true
					e.windup_total = Data.ENEMIES.boss.windup
					e.windup = e.windup_total*0.4
		else:
			g.player.pos = g.rooms[2].pos
		g.camera = g._iso(g.player.pos)
		g._reveal()
		for i in 12:
			g._reveal()
			g.player.pos += Vector2(0.05,0.05)
		g.player.equipment.weapon = Items.generate(g,8,4 if floor_number==3 else 3,"weapon")
		g.state = "preview"
		await _capture(g,"floor%d.png" % floor_number)
		g.state = "play"
	g.player.nova = 0
	g._nova()
	g.player.attack = 0
	g._slash(true)
	g._advance_game(0.07)
	g.state = "preview"
	await _capture(g,"effects.png")
	g.state = "play"
	# Exercise the updated gait and actual blade animation in the native renderer.
	g._generate(1)
	g.enemies.clear(); g.props.clear()
	g.keys[KEY_D] = true
	for frame in 8: await g.get_tree().process_frame
	await _capture(g,"movement.png")
	g.keys.clear(); g.screen_velocity = Vector2.ZERO
	g.player.attack = 0; g.pointer_active = false
	g.player.angle = 0
	g._slash()
	g._advance_game(0.065)
	g.state = "preview"
	await _capture(g,"swing.png")
	g.state = "play"
	# The Gunslinger and Synth Mage mid-fight, with their skills in the air.
	for spec in [["gunslinger",["scatter","grenade"]],["synth_mage",["arc","frost","meteor"]]]:
		g._begin(false,spec[0])
		g.level_banner = 0
		g.seed_value = 71283
		g._generate(1)
		g.player.level = 6
		g._recalc()
		g.player.pos = g.rooms[1].pos
		g.camera = g._iso(g.player.pos)
		g._reveal()
		g.enemies.clear()
		for offset in [Vector2(2.6,0.4),Vector2(3.2,-1.0),Vector2(1.8,2.0)]:
			var e = g._spawn_enemy("imp",g.player.pos+offset)
			e.alert = true; e.attack = 100.0
		g.player.inv = 50
		g.pointer = g._to_screen(g._project(g.enemies[0].pos,30)); g.pointer_active = true
		for i in 4:
			g.player.mana = g.player.max_mana
			if Classes.skill_ids(g)[i] in spec[1]: Classes.cast(g,i)
		g.player.angle = (g.enemies[1].pos-g.player.pos).angle()
		g._basic_attack()
		for frame in 12: await g.get_tree().process_frame
		g.state = "preview"
		await _capture(g,"class-%s.png" % spec[0])
		g.state = "play"
	g._begin()
	# A zoomed-out view of each floor's whole district.
	for n in [1,2,3]:
		g.seed_value = 500+n
		g._generate(n)
		for y in 64:
			for x in 64: g.seen[Vector2i(x,y)] = true
		g.enemies.clear()
		g.zoom = 0.4
		g.player.pos = Vector2(32,32)
		g.camera = g._iso(g.player.pos)
		g.state = "preview"
		g.world_view.redraw_all()
		await _capture(g,"district%d.png" % n)
		g.state = "play"
		g.zoom = g.WORLD_ZOOM
	await _zones(g)
	if FileAccess.file_exists(g.save_file): DirAccess.remove_absolute(g.save_file)
	print("PASS: %s renderer; " % ("3D" if g.view3d else "2D")+"menus, gameplay, combat, health, wind-up, gait, sword-swing and zone previews saved.")
	g.get_tree().quit()

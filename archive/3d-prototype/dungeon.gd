extends Node3D
## Original native Godot action RPG. No browser, web view, or external assets.

var save_file = "user://descent.json"
const FLOOR_NAMES = ["The Forgotten Approach", "The Hollow Forge", "The Warden's Sanctum"]
const RARITY_COLORS = [Color("c5c9bb"), Color("8cdbac"), Color("8bbef1"), Color("ddb1f4")]
const WEAPON_NAMES = ["Iron Cleaver", "Verdant Edge", "Frostbite Saber", "Duskbringer"]
const ARMOR_NAMES = ["Riveted Leather", "Mossguard Mantle", "Runeforged Mail", "Astral Carapace"]
var rng = RandomNumberGenerator.new()
var cells = {}
var discovered = {}
var enemies: Array = []
var props: Array = []
var drops: Array = []
var effects: Array = []
var projectiles: Array = []
var materials = {}
var astar = AStarGrid2D.new()
var path = PackedVector2Array()
var floor_number = 1
var state = "title"
var stats = {}
var hero: Node3D
var hero_model: Node3D
var sword: Node3D
var world_root: Node3D
var camera: Camera3D
var stairs = Vector3(38.5, 0, 38.5)
var attack_cd = 0.0
var nova_cd = 0.0
var dodge_cd = 0.0
var invulnerable = 0.0
var roll_time = 0.0
var roll_direction = Vector3.ZERO
var facing = Vector3(1, 0, 0)
var swing_time = 0.0
var clock = 0.0
var play_time = 0.0
var kill_count = 0
var notice_time = 0.0
var pointer_held = false
var target_enemy: Node3D
var ui: Control
var title_overlay: Control
var menu_overlay: Control
var gear_overlay: Control
var title_label: Label
var quest_label: Label
var health_bar: ProgressBar
var xp_bar: ProgressBar
var stats_label: Label
var skill_label: Label
var hint_label: Label
var notice_label: Label
var boss_label: Label
var boss_bar: ProgressBar
var gear_label: RichTextLabel
var menu_heading: Label
var menu_detail: Label
var resume_button: Button
var minimap: Control
var smoke_mode = false

func _ready() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args(): save_file = "user://test-descent.json"
	rng.randomize()
	_build_environment()
	_build_ui()
	_reset_stats()
	_generate_floor(1)
	title_overlay.show()
	menu_overlay.hide()
	gear_overlay.hide()
	if "--smoke-test" in OS.get_cmdline_user_args():
		smoke_mode = true
		call_deferred("_smoke_test")
	if "--render-check" in OS.get_cmdline_user_args():
		call_deferred("_render_check")

func _reset_stats() -> void:
	stats = {"hp": 120.0, "max_hp": 120.0, "level": 1, "xp": 0, "gold": 0, "potions": 3,
		"weapon": {"name": "Wayfarer's Blade", "value": 17, "rarity": 0},
		"armor": {"name": "Worn Leather", "value": 0, "rarity": 0}}
	kill_count = 0
	play_time = 0

func _build_environment() -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("09121d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b1c5d9")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("c6dded")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	camera.far = 150
	add_child(camera)
	camera.current = true

func _material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key = color.to_html() + str(emissive)
	if materials.has(key):
		return materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.8
	materials[key] = mat
	return mat

func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh_node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	mesh_node.mesh = mesh
	mesh_node.material_override = _material(color)
	mesh_node.position = pos
	parent.add_child(mesh_node)
	return mesh_node

func _orb(parent: Node3D, pos: Vector3, radius: float, color: Color, emissive: bool = false) -> MeshInstance3D:
	var mesh_node = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh_node.mesh = mesh
	mesh_node.material_override = _material(color, emissive)
	mesh_node.position = pos
	parent.add_child(mesh_node)
	return mesh_node

func _ring(pos: Vector3, radius: float, color: Color, lifetime: float, growing: bool = true) -> Node3D:
	var node = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.06)
	mesh.outer_radius = radius + 0.06
	mesh.rings = 32
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = _material(color, true)
	node.position = pos + Vector3.UP * 0.08
	world_root.add_child(node)
	effects.append({"node": node, "life": lifetime, "max": lifetime, "grow": growing, "kind": "ring"})
	return node

func _actor(pos: Vector3, kind: String) -> Node3D:
	var root = Node3D.new()
	root.position = pos
	world_root.add_child(root)
	var body = Node3D.new()
	root.add_child(body)
	var color = Color("37899b") if kind == "hero" else Color("8a967b")
	if kind == "ranged": color = Color("755b9b")
	if kind == "brute": color = Color("a88670")
	if kind == "boss": color = Color("6f4b68")
	_box(body, Vector3(-0.14, 0.15, 0), Vector3(0.2, 0.3, 0.28), Color("253442"))
	_box(body, Vector3(0.14, 0.15, 0), Vector3(0.2, 0.3, 0.28), Color("253442"))
	_box(body, Vector3(0, 0.58, 0), Vector3(0.55, 0.62, 0.36), color)
	_box(body, Vector3(0, 0.4, 0), Vector3(0.58, 0.09, 0.39), Color("b79660"))
	_orb(body, Vector3(0, 1.08, 0), 0.24, color)
	_box(body, Vector3(0, 1.07, -0.17), Vector3(0.28, 0.16, 0.14), Color("e1bc8e") if kind == "hero" else Color("31353d"))
	for x in [-0.33, 0.33]:
		_box(body, Vector3(x, 0.76, 0), Vector3(0.22, 0.24, 0.4), Color("ccab72") if kind == "hero" else color.lightened(0.16))
		_box(body, Vector3(x, 0.51, -0.02), Vector3(0.13, 0.3, 0.17), color)
	if kind == "hero":
		hero_model = body
		sword = Node3D.new()
		body.add_child(sword)
		sword.position = Vector3(0.38, 0.6, -0.2)
		_box(sword, Vector3(0, 0, -0.4), Vector3(0.11, 0.07, 0.9), Color("d5e9de"))
		_box(sword, Vector3.ZERO, Vector3(0.35, 0.1, 0.09), Color("efc883"))
		_box(body, Vector3(0, 0.6, 0.25), Vector3(0.49, 0.7, 0.07), Color("284e67"))
	else:
		for x in [-0.09, 0.09]:
			_orb(body, Vector3(x, 1.1, -0.25), 0.035, Color("ffb769"), true)
		if kind == "ranged":
			_box(body, Vector3(0.4, 0.7, -0.2), Vector3(0.07, 1.2, 0.07), Color("b3a180"))
			_orb(body, Vector3(0.4, 1.35, -0.2), 0.11, Color("a9e99b"), true)
		else:
			for x in [-0.2, 0.2]:
				var horn = _box(body, Vector3(x, 1.34, 0), Vector3(0.12, 0.35, 0.12), Color("d7c09b"))
				horn.rotation.z = -x * 2
	if kind == "brute": root.scale = Vector3.ONE * 1.35
	if kind == "boss":
		root.scale = Vector3.ONE * 2.4
		_orb(body, Vector3(0, 0.72, -0.22), 0.13, Color("ff9d4e"), true)
	return root

func _carve(x: int, y: int, width: int, height: int) -> void:
	for j in range(y, y + height):
		for i in range(x, x + width):
			if i > 0 and j > 0 and i < 45 and j < 45:
				cells[Vector2i(i, j)] = true

func _generate_floor(number: int) -> void:
	if is_instance_valid(world_root):
		remove_child(world_root)
		world_root.queue_free()
	world_root = Node3D.new()
	world_root.name = "DungeonFloor"
	add_child(world_root)
	floor_number = number
	cells.clear()
	discovered.clear()
	enemies.clear()
	props.clear()
	drops.clear()
	effects.clear()
	projectiles.clear()
	path.clear()
	target_enemy = null
	pointer_held = false
	var centers = [Vector2i(7,7), Vector2i(19,7), Vector2i(32,9), Vector2i(33,23), Vector2i(20,23), Vector2i(8,25), Vector2i(11,38), Vector2i(26,37), Vector2i(38,37)]
	for index in centers.size():
		var c = centers[index]
		var width = 10 if index == 8 else rng.randi_range(7, 9)
		_carve(c.x - width / 2, c.y - width / 2, width, width)
		if index > 0:
			var previous = centers[index - 1]
			_carve(mini(previous.x, c.x) - 1, previous.y - 1, absi(c.x - previous.x) + 3, 3)
			_carve(c.x - 1, mini(previous.y, c.y) - 1, 3, absi(c.y - previous.y) + 3)
	astar.region = Rect2i(0, 0, 46, 46)
	astar.cell_size = Vector2.ONE
	astar.offset = Vector2.ONE * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in 46:
		for x in 46:
			astar.set_point_solid(Vector2i(x,y), not cells.has(Vector2i(x,y)))
	var walls = {}
	for cell in cells:
		var shade = 0.02 * ((cell.x * 71 + cell.y * 13) % 5)
		_box(world_root, Vector3(cell.x + 0.5, -0.12, cell.y + 0.5), Vector3(0.98, 0.24, 0.98), Color(0.2 + shade, 0.29 + shade, 0.32 + shade))
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var adjacent = cell + direction
			if not cells.has(adjacent): walls[adjacent] = true
	for cell in walls:
		_box(world_root, Vector3(cell.x + 0.5, 0.42, cell.y + 0.5), Vector3(1, 1.1, 1), Color("354955"))
		_box(world_root, Vector3(cell.x + 0.5, 1.01, cell.y + 0.5), Vector3(1.03, 0.13, 1.03), Color("60717a"))
	hero = _actor(Vector3(7.5, 0, 7.5), "hero")
	var lamp = OmniLight3D.new()
	lamp.light_color = Color("9ac9ed")
	lamp.omni_range = 7
	lamp.light_energy = 1.3
	lamp.position.y = 2.2
	hero.add_child(lamp)
	for index in centers.size():
		var c = centers[index]
		var center = Vector3(c.x + 0.5, 0, c.y + 0.5)
		_torch(center + Vector3(-2.5,0,-2.5))
		_torch(center + Vector3(2.5,0,2.5))
		if index > 0 and not (number == 3 and index == 8):
			for j in rng.randi_range(3, 4 + int(number > 1)):
				var kind = "ranged" if rng.randf() < 0.25 else ("brute" if rng.randf() < 0.3 else "imp")
				_spawn_enemy(center + Vector3(rng.randf_range(-2,2),0,rng.randf_range(-2,2)), kind)
		if index % 2 == 1: _prop(center + Vector3(1.5,0,-1), "chest")
		for j in 3: _prop(center + Vector3(rng.randf_range(-2.5,2.5),0,rng.randf_range(-2.5,2.5)), "crate")
	if number == 3:
		_spawn_enemy(Vector3(38.5,0,36), "boss")
	else:
		_portal(stairs)
	attack_cd = 0
	nova_cd = 0
	dodge_cd = 0
	roll_time = 0
	invulnerable = 1
	camera.position = hero.position + Vector3(13, 18, 13)
	camera.look_at(hero.position)
	_reveal()
	_update_hud()
	if state == "play": _save()

func _torch(pos: Vector3) -> void:
	_box(world_root, pos + Vector3.UP * 0.2, Vector3(0.5,0.4,0.5), Color("6a6963"))
	_box(world_root, pos + Vector3.UP * 0.9, Vector3(0.11,1.2,0.11), Color("a17c50"))
	var flame = _orb(world_root, pos + Vector3.UP * 1.6, 0.16, Color("ffc571"), true)
	flame.scale.y = 1.8
	var light = OmniLight3D.new()
	light.position = pos + Vector3.UP * 1.8
	light.light_color = Color("ffc086")
	light.light_energy = 1.7
	light.omni_range = 4.8
	world_root.add_child(light)

func _portal(pos: Vector3) -> void:
	for i in 4:
		_box(world_root, pos + Vector3(0, i * 0.13, -i * 0.15), Vector3(1.8 - i * 0.2, 0.15, 1.5 - i * 0.15), Color("518b8c"))
	for x in [-0.8, 0.8]:
		_box(world_root, pos + Vector3(x,1.1,-0.4), Vector3(0.22,2.2,0.25), Color("85b9b2"))
	_box(world_root, pos + Vector3(0,2.2,-0.4), Vector3(1.8,0.22,0.25), Color("a6d9c9"))
	_orb(world_root, pos + Vector3(0,1.1,-0.4), 0.38, Color("6ce0c8"), true)
	var label = Label3D.new()
	label.text = "DESCEND  [E]"
	label.position = pos + Vector3.UP * 2.7
	label.font_size = 32
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world_root.add_child(label)

func _prop(pos: Vector3, kind: String) -> void:
	var node = Node3D.new()
	node.position = pos
	world_root.add_child(node)
	_box(node, Vector3(0,0.28,0), Vector3(0.65,0.55,0.65), Color("96744d"))
	for x in [-0.23,0.23]:
		_box(node, Vector3(x,0.3,0), Vector3(0.065,0.6,0.68), Color("d0b276"))
	if kind == "chest":
		_box(node, Vector3(0,0.64,0), Vector3(0.74,0.18,0.7), Color("c99c5d"))
		_orb(node, Vector3(0,0.36,-0.35), 0.07, Color("ffe5a0"), true)
	props.append({"node":node, "kind":kind, "open":false})

func _spawn_enemy(pos: Vector3, kind: String) -> void:
	var hp = (75 if kind == "brute" else 36 if kind == "ranged" else 42) * (1 + (floor_number - 1) * 0.4)
	if kind == "boss": hp = 900
	enemies.append({"node":_actor(pos,kind), "kind":kind, "hp":hp, "max_hp":hp, "cooldown":rng.randf_range(0.5,1.5), "alert":false, "windup":0.0})

func _begin(load_checkpoint: bool = false) -> void:
	_reset_stats()
	var number = 1
	if load_checkpoint and FileAccess.file_exists(save_file):
		var data = JSON.parse_string(FileAccess.get_file_as_string(save_file))
		if data is Dictionary and data.get("version") == 1:
			stats = data.stats
			number = int(data.floor)
			kill_count = int(data.get("kills",0))
			play_time = float(data.get("time",0))
	state = "play"
	title_overlay.hide()
	menu_overlay.hide()
	gear_overlay.hide()
	_generate_floor(number)
	_notice("The mountain remembers. Find the stairway.")

func _save() -> void:
	var file = FileAccess.open(save_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"version":1,"floor":floor_number,"stats":stats,"kills":kill_count,"time":play_time}))

func _walkable(pos: Vector3) -> bool:
	for offset in [Vector2(-0.2,-0.2), Vector2(0.2,-0.2), Vector2(-0.2,0.2), Vector2(0.2,0.2)]:
		if not cells.has(Vector2i(floori(pos.x + offset.x),floori(pos.z + offset.y))): return false
	return true

func _move_actor(node: Node3D, motion: Vector3) -> void:
	var candidate = node.position + Vector3(motion.x,0,0)
	if _walkable(candidate): node.position = candidate
	candidate = node.position + Vector3(0,0,motion.z)
	if _walkable(candidate): node.position = candidate

func _reveal() -> void:
	var p = Vector2i(hero.position.x,hero.position.z)
	for y in range(p.y - 6,p.y + 7):
		for x in range(p.x - 6,p.x + 7):
			if Vector2(x,y).distance_to(Vector2(p)) <= 6.5: discovered[Vector2i(x,y)] = true
	minimap.queue_redraw()

func _mouse_world() -> Vector3:
	var mouse = get_viewport().get_mouse_position()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	return point if point != null else hero.position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if state == "inventory": _toggle_inventory()
			elif state == "play" or state == "paused": _pause()
		if event.keycode == KEY_I: _toggle_inventory()
		if state != "play": return
		match event.keycode:
			KEY_Q: _nova()
			KEY_SPACE: _dodge()
			KEY_R: _potion()
			KEY_E: _interact()
			KEY_M: minimap.visible = not minimap.visible
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			pointer_held = event.pressed
			if event.pressed and state == "play": _click_destination()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and state == "play": _nova()
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(12,camera.size - 1)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(26,camera.size + 1)

func _click_destination() -> void:
	var point = _mouse_world()
	target_enemy = null
	for enemy in enemies:
		if enemy.hp > 0 and enemy.node.position.distance_to(point) < 1.1:
			target_enemy = enemy.node
			break
	var destination = Vector2i(floori(point.x),floori(point.z))
	if cells.has(destination):
		path = astar.get_point_path(Vector2i(hero.position.x,hero.position.z),destination)
		if not path.is_empty(): path.remove_at(0)
	if not is_instance_valid(target_enemy): _ring(point,0.22,Color("d6c08e"),0.45,false)

func _keyboard_direction() -> Vector3:
	var x = int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y = int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return Vector3(x+y,0,y-x).normalized()

func _physics_process(delta: float) -> void:
	clock += delta
	if state != "play": return
	play_time += delta
	attack_cd = maxf(0,attack_cd-delta)
	nova_cd = maxf(0,nova_cd-delta)
	dodge_cd = maxf(0,dodge_cd-delta)
	invulnerable = maxf(0,invulnerable-delta)
	roll_time = maxf(0,roll_time-delta)
	swing_time = maxf(0,swing_time-delta)
	var direction = _keyboard_direction()
	if direction != Vector3.ZERO:
		path.clear()
		target_enemy = null
	elif is_instance_valid(target_enemy):
		var difference = target_enemy.position-hero.position
		if difference.length() < 1.8:
			facing = difference.normalized()
			_slash()
			path.clear()
		else:
			var target_cell = Vector2i(target_enemy.position.x,target_enemy.position.z)
			path = astar.get_point_path(Vector2i(hero.position.x,hero.position.z),target_cell)
			if not path.is_empty(): path.remove_at(0)
	if direction == Vector3.ZERO and not path.is_empty():
		var destination = Vector3(path[0].x,0,path[0].y)
		if hero.position.distance_to(destination) < 0.15: path.remove_at(0)
		else: direction = (destination-hero.position).normalized()
	if roll_time > 0:
		_move_actor(hero,roll_direction*delta*12)
	else:
		_move_actor(hero,direction*delta*4)
	if direction != Vector3.ZERO: facing = direction
	if Input.is_physical_key_pressed(KEY_J): _slash(true)
	if Input.is_physical_key_pressed(KEY_SHIFT) and pointer_held:
		path.clear()
		facing = (_mouse_world()-hero.position).normalized()
		_slash()
	hero_model.rotation.y = lerp_angle(hero_model.rotation.y,atan2(-facing.x,-facing.z),delta*14)
	hero_model.position.y = absf(sin(clock*11))*0.07 if direction != Vector3.ZERO else 0
	sword.rotation.y = sin((0.25-swing_time)*18)*1.7 if swing_time > 0 else 0
	for enemy in enemies:
		if enemy.hp <= 0: continue
		var node = enemy.node
		var difference = hero.position-node.position
		var distance = difference.length()
		if distance < 8: enemy.alert = true
		if not enemy.alert or distance > 16: continue
		enemy.cooldown -= delta
		node.rotation.y = atan2(-difference.x,-difference.z)
		if enemy.kind == "boss":
			if enemy.windup > 0:
				enemy.windup -= delta
				if enemy.windup <= 0:
					_ring(node.position,3.4,Color("ff8758"),0.5)
					if distance < 3.4: _hurt(43)
					enemy.cooldown = 2.5
			elif enemy.cooldown <= 0 and distance < 4.4:
				enemy.windup = 1.1
				_ring(node.position,3.4,Color("e85543"),1.1,false)
			elif distance > 1.6: _move_actor(node,difference.normalized()*delta*1.6)
		elif enemy.kind == "ranged":
			if distance > 5: _move_actor(node,difference.normalized()*delta*1.6)
			if enemy.cooldown <= 0 and distance < 8:
				var missile = _orb(world_root,node.position+Vector3.UP*0.65,0.14,Color("b4e993"),true)
				projectiles.append({"node":missile,"velocity":difference.normalized()*5,"life":2.5})
				enemy.cooldown = 2.3
		else:
			if distance > 0.95: _move_actor(node,difference.normalized()*delta*(1.4 if enemy.kind=="brute" else 2.2))
			if distance < 1.3 and enemy.cooldown <= 0:
				_hurt((19 if enemy.kind=="brute" else 11)*(0.8+floor_number*0.2))
				enemy.cooldown = 1.25
		if state != "play": break
	_separate_enemies(delta)
	for missile in projectiles:
		missile.life -= delta
		missile.node.position += missile.velocity*delta
		var flat = missile.node.position*Vector3(1,0,1)
		if flat.distance_to(hero.position) < 0.45:
			_hurt(13+floor_number*3)
			missile.life = 0
		if not cells.has(Vector2i(flat.x,flat.z)): missile.life = 0
	for i in range(projectiles.size()-1,-1,-1):
		if projectiles[i].life <= 0:
			projectiles[i].node.queue_free()
			projectiles.remove_at(i)
	for drop in drops:
		var p = drop.node.position*Vector3(1,0,1)
		drop.node.rotation.y += delta
		if p.distance_to(hero.position) < 1.2: _collect(drop)
	for i in range(drops.size()-1,-1,-1):
		if drops[i].taken:
			drops[i].node.queue_free()
			drops.remove_at(i)
	for effect in effects:
		effect.life -= delta
		if effect.kind == "text": effect.node.position.y += delta*0.5
		elif effect.grow: effect.node.scale = Vector3.ONE*(0.1+0.9*(1-effect.life/effect.max))
	for i in range(effects.size()-1,-1,-1):
		if effects[i].life <= 0:
			effects[i].node.queue_free()
			effects.remove_at(i)
	camera.position = camera.position.lerp(hero.position+Vector3(13,18,13),minf(1,delta*7))
	camera.look_at(camera.position-Vector3(13,18,13))
	_reveal()
	notice_time = maxf(0,notice_time-delta)
	notice_label.visible = notice_time > 0
	_update_hud()

func _separate_enemies(delta: float) -> void:
	for i in enemies.size():
		if enemies[i].hp <= 0 or not enemies[i].alert: continue
		for j in range(i+1,enemies.size()):
			if enemies[j].hp <= 0: continue
			var a = enemies[i].node
			var b = enemies[j].node
			var difference = a.position-b.position
			var distance = difference.length()
			if distance > 0.01 and distance < 0.7:
				var push = difference.normalized()*(0.7-distance)*delta*3
				_move_actor(a,push)
				_move_actor(b,-push)

func _damage() -> int:
	return int(stats.weapon.value) + (int(stats.level)-1)*3

func _slash(auto_aim: bool = false) -> void:
	if state != "play" or attack_cd > 0: return
	if auto_aim:
		var nearest = 3.0
		for enemy in enemies:
			var distance = enemy.node.position.distance_to(hero.position)
			if enemy.hp > 0 and distance < nearest:
				nearest = distance
				facing = (enemy.node.position-hero.position).normalized()
	attack_cd = 0.4
	swing_time = 0.25
	_ring(hero.position+facing*0.7,0.8,Color("e8e6bc"),0.18)
	for enemy in enemies:
		var diff = enemy.node.position-hero.position
		if enemy.hp > 0 and diff.length() < 2.2 and (diff.normalized().dot(facing) > -0.15 or diff.length() < 0.9):
			_damage_enemy(enemy,roundi(_damage()*rng.randf_range(0.88,1.2)))
	for prop in props:
		if prop.kind == "crate" and not prop.open and prop.node.position.distance_to(hero.position) < 2:
			prop.open = true
			prop.node.scale.y = 0.15
			_drop(prop.node.position,"gold",rng.randi_range(2,7))

func _nova() -> void:
	if state != "play" or nova_cd > 0: return
	nova_cd = 6
	_ring(hero.position,4.2,Color("ffc477"),0.6)
	for enemy in enemies:
		if enemy.hp > 0 and enemy.node.position.distance_to(hero.position) < 4.2:
			_damage_enemy(enemy,roundi(_damage()*2.8))

func _dodge() -> void:
	if state != "play" or dodge_cd > 0: return
	roll_direction = _keyboard_direction()
	if roll_direction == Vector3.ZERO: roll_direction = facing
	roll_time = 0.25
	invulnerable = 0.45
	dodge_cd = 1.7
	_ring(hero.position,0.6,Color("8fcbe4"),0.3)

func _potion() -> void:
	if state != "play": return
	if stats.hp >= stats.max_hp: _notice("Your health is already full.")
	elif stats.potions <= 0: _notice("No potions. Search chests or restock at the stairway.")
	else:
		stats.potions -= 1
		stats.hp = minf(stats.max_hp,stats.hp+stats.max_hp*0.65)
		_ring(hero.position,1.1,Color("98e8ac"),0.6)
		_notice("Healing potion used.")

func _hurt(amount: float) -> void:
	if invulnerable > 0 or state != "play": return
	var actual = maxi(2,roundi(amount-float(stats.armor.value)*0.65))
	stats.hp = maxf(0,stats.hp-actual)
	invulnerable = 0.5
	_float_text(hero.position,"-"+str(actual),Color("ff9791"))
	if stats.hp <= 0: _finish(false)

func _damage_enemy(enemy: Dictionary, amount: int) -> void:
	if enemy.hp <= 0: return
	enemy.hp -= amount
	enemy.alert = true
	_float_text(enemy.node.position,str(amount),Color("ffe4a7"))
	if enemy.hp <= 0:
		kill_count += 1
		var pos = enemy.node.position
		enemy.node.hide()
		if target_enemy == enemy.node: target_enemy = null
		_gain_xp(140 if enemy.kind=="boss" else 20 if enemy.kind=="brute" else 12)
		_drop(pos,"gold",rng.randi_range(5,11)*floor_number)
		if rng.randf() < 0.18: _drop(pos+Vector3(0.3,0,0),"potion")
		if rng.randf() < 0.18: _drop(pos+Vector3(-0.3,0,0),"gear")
		if enemy.kind == "boss": _finish(true)

func _gain_xp(amount: int) -> void:
	stats.xp += amount
	while stats.xp >= stats.level*40:
		stats.xp -= stats.level*40
		stats.level += 1
		stats.max_hp += 20
		stats.hp = stats.max_hp
		_notice("LEVEL %d  -  Health restored  -  +3 attack" % stats.level)
		_ring(hero.position,2,Color("ffe7a6"),0.8)

func _drop(pos: Vector3, kind: String, value: int = 0) -> void:
	var rarity = 3 if rng.randf()<0.07 else 2 if rng.randf()<0.3 else 1 if rng.randf()<0.6 else 0
	var slot = "weapon" if rng.randf()<0.55 else "armor"
	var gear = {"name":WEAPON_NAMES[rarity] if slot=="weapon" else ARMOR_NAMES[rarity],"value":17+floor_number*4+rarity*5+rng.randi_range(0,4) if slot=="weapon" else 2+floor_number*2+rarity*3,"rarity":rarity}
	var color = Color("f1c673") if kind=="gold" else Color("d77776") if kind=="potion" else RARITY_COLORS[rarity]
	var node = _orb(world_root,pos+Vector3.UP*0.25,0.13 if kind=="gold" else 0.2,color,true)
	if kind == "gear": _box(node,Vector3.UP*0.6,Vector3(0.035,1.2,0.035),color)
	drops.append({"node":node,"kind":kind,"value":value,"gear":gear,"slot":slot,"taken":false})

func _collect(drop: Dictionary) -> void:
	if drop.taken: return
	drop.taken = true
	if drop.kind == "gold": stats.gold += drop.value
	elif drop.kind == "potion":
		stats.potions += 1
		_float_text(hero.position,"+ Potion",Color("b9efbb"))
	else:
		if drop.gear.value > stats[drop.slot].value:
			stats[drop.slot] = drop.gear
			_notice("Equipped: %s  -  %s %d" % [drop.gear.name,drop.slot,drop.gear.value])
		else:
			stats.gold += 8+drop.gear.rarity*7
			_notice("Spare equipment salvaged for gold.")

func _interact() -> void:
	if state != "play": return
	for prop in props:
		if prop.kind == "chest" and not prop.open and prop.node.position.distance_to(hero.position)<2:
			prop.open = true
			prop.node.scale.y = 0.5
			_drop(prop.node.position,"gear")
			_drop(prop.node.position+Vector3(0.4,0,0),"gold",20*floor_number)
			_drop(prop.node.position+Vector3(-0.4,0,0),"potion")
			_notice("Treasure found. Walk over the loot to collect it.")
			return
	if floor_number < 3 and hero.position.distance_to(stairs)<2:
		while stats.potions < 3 and stats.gold >= 15:
			stats.potions += 1
			stats.gold -= 15
		stats.hp = minf(stats.max_hp,stats.hp+stats.max_hp*0.35)
		_generate_floor(floor_number+1)
		_notice("%s  -  Checkpoint saved" % FLOOR_NAMES[floor_number-1])

func _float_text(pos: Vector3, text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.modulate = color
	label.position = pos + Vector3.UP*1.8
	label.font_size = 44
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	world_root.add_child(label)
	effects.append({"node":label,"life":0.9,"max":0.9,"kind":"text","grow":false})

func _notice(text: String) -> void:
	notice_label.text = text
	notice_label.show()
	notice_time = 4

func _pause() -> void:
	if state == "play":
		state = "paused"
		pointer_held = false
		menu_heading.text = "Game paused"
		menu_detail.text = "The depths can wait."
		resume_button.show()
		menu_overlay.show()
	elif state == "paused":
		state = "play"
		menu_overlay.hide()

func _toggle_inventory() -> void:
	if state == "inventory":
		state = "play"
		gear_overlay.hide()
	elif state == "play":
		state = "inventory"
		pointer_held = false
		gear_label.text = "[color=#dfbb7e]WEAPON[/color]\n[b]%s[/b]\n%d attack\n\n[color=#dfbb7e]ARMOR[/color]\n[b]%s[/b]\n%d defense\n\nLevel %d  /  Total attack %d\n\n[color=#99aeb8]Upgrades equip automatically. Spare equipment becomes gold. Stairways refill potions up to three at 15 gold each.[/color]" % [stats.weapon.name,stats.weapon.value,stats.armor.name,stats.armor.value,stats.level,_damage()]
		gear_overlay.show()

func _finish(won: bool) -> void:
	state = "victory" if won else "defeat"
	pointer_held = false
	gear_overlay.hide()
	menu_heading.text = "The Warden has fallen" if won else "Your light fades"
	menu_detail.text = "%s\n\nLevel %d  /  %d enemies defeated\n%d gold  /  %dm %ds" % ["You freed the Ember Depths." if won else "Another adventurer will follow your footsteps.",stats.level,kill_count,stats.gold,int(play_time)/60,int(play_time)%60]
	resume_button.hide()
	menu_overlay.show()
	if FileAccess.file_exists(save_file): DirAccess.remove_absolute(save_file)

func _panel_style() -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color("10212fee")
	box.border_color = Color("947d525f")
	box.set_border_width_all(1)
	box.set_content_margin_all(20)
	return box

func _label(parent: Node, text: String, font_size: int, color: Color = Color("f0e7d4")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0,42)
	button.add_theme_font_size_override("font_size",14)
	button.add_theme_color_override("font_color",Color("e8c890"))
	var normal = _panel_style()
	button.add_theme_stylebox_override("normal",normal)
	var hover = normal.duplicate()
	hover.bg_color = Color("314b57")
	button.add_theme_stylebox_override("hover",hover)
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _overlay(width: float = 500) -> Array:
	var root = ColorRect.new()
	root.color = Color(0.02,0.035,0.06,0.86)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel",_panel_style())
	center.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation",17)
	panel.add_child(content)
	return [root,content]

func _build_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var brand = _label(ui,"DC  /  DUNGEON CRAWLER",20,Color("e2bd7c"))
	brand.position = Vector2(28,24)
	title_label = _label(ui,"",18)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_label.position = Vector2(420,25)
	title_label.size.x = 450
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause_btn = _button(ui,"PAUSE  [ESC]",_pause)
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(1115,18)
	pause_btn.size.x = 140
	quest_label = _label(ui,"",15,Color("bbcbc9"))
	quest_label.position = Vector2(28,100)
	minimap = Control.new()
	minimap.set_script(load("res://scripts/minimap.gd"))
	minimap.game = self
	minimap.position = Vector2(1060,90)
	minimap.size = Vector2(194,206)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(minimap)
	var map_title = _label(minimap,"CARTOGRAPHY   [M]",11,Color("ddbf88"))
	map_title.position = Vector2(13,8)
	var hud_panel = Panel.new()
	hud_panel.position = Vector2(22,674)
	hud_panel.size = Vector2(1236,106)
	hud_panel.add_theme_stylebox_override("panel",_panel_style())
	ui.add_child(hud_panel)
	stats_label = _label(hud_panel,"",15)
	stats_label.position = Vector2(18,12)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(18,43)
	health_bar.size = Vector2(275,21)
	health_bar.show_percentage = false
	var health_style = StyleBoxFlat.new()
	health_style.bg_color = Color("b85158")
	health_bar.add_theme_stylebox_override("fill",health_style)
	hud_panel.add_child(health_bar)
	xp_bar = ProgressBar.new()
	xp_bar.position = Vector2(18,72)
	xp_bar.size = Vector2(275,6)
	xp_bar.show_percentage = false
	var xp_style = StyleBoxFlat.new()
	xp_style.bg_color = Color("d2ad65")
	xp_bar.add_theme_stylebox_override("fill",xp_style)
	hud_panel.add_child(xp_bar)
	var actions = HBoxContainer.new()
	actions.position = Vector2(323,10)
	actions.add_theme_constant_override("separation",9)
	hud_panel.add_child(actions)
	_button(actions,"SLASH  [J]",func(): _slash(true))
	_button(actions,"NOVA  [Q]",_nova)
	_button(actions,"DODGE  [SPACE]",_dodge)
	_button(actions,"POTION  [R]",_potion)
	_button(actions,"EQUIPMENT  [I]",_toggle_inventory)
	skill_label = _label(hud_panel,"",12,Color("a6bfc7"))
	skill_label.position = Vector2(325,69)
	hint_label = _label(ui,"",16,Color("ecd39f"))
	hint_label.position = Vector2(340,634)
	hint_label.size.x = 600
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label = _label(ui,"",16,Color("f1d397"))
	notice_label.position = Vector2(300,78)
	notice_label.size.x = 680
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label = _label(ui,"ASH WARDEN",14,Color("eeb78d"))
	boss_label.position = Vector2(440,110)
	boss_label.size.x = 400
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(440,137)
	boss_bar.size = Vector2(400,12)
	boss_bar.show_percentage = false
	ui.add_child(boss_bar)
	var title = _overlay(610)
	title_overlay = title[0]
	var content = title[1]
	_label(content,"AN ADVENTURE IN THE EMBER DEPTHS",13,Color("dabb81"))
	_label(content,"DUNGEON\nCRAWLER",58,Color("f2dbab"))
	_label(content,"Something ancient stirs beneath the mountain.\nTake up your blade. Bring back the light.",17,Color("a5bac4"))
	_button(content,"ENTER THE DEPTHS",func(): _begin())
	if FileAccess.file_exists(save_file): _button(content,"CONTINUE DESCENT",func(): _begin(true))
	_label(content,"Click to move / attack  -  WASD to move  -  J to slash\nQ / right-click nova  -  Space dodge  -  R heal  -  E interact\nMouse wheel zoom  -  Shift + click attack in place",12,Color("9aafb9"))
	_label(content,"NATIVE GODOT EDITION  /  PLAYABLE PROTOTYPE",11,Color("bfa476"))
	_button(content,"QUIT",func(): get_tree().quit())
	var menu = _overlay()
	menu_overlay = menu[0]
	menu_heading = _label(menu[1],"Game paused",30)
	menu_detail = _label(menu[1],"The depths can wait.",16,Color("b5c4c9"))
	resume_button = _button(menu[1],"RETURN TO THE DEPTHS",_pause)
	_button(menu[1],"NEW ADVENTURE",func(): _begin())
	_button(menu[1],"QUIT TO DESKTOP",func(): get_tree().quit())
	_label(menu[1],"Checkpoints save when you enter a floor.\nWASD / click move  -  J attack  -  Q nova\nSpace dodge  -  R heal  -  E interact  -  I equipment",12,Color("9aafb9"))
	var equipment = _overlay()
	gear_overlay = equipment[0]
	_label(equipment[1],"Your equipment",30)
	gear_label = RichTextLabel.new()
	gear_label.bbcode_enabled = true
	gear_label.custom_minimum_size = Vector2(450,340)
	gear_label.add_theme_font_size_override("normal_font_size",17)
	equipment[1].add_child(gear_label)
	_button(equipment[1],"BACK TO ADVENTURE",_toggle_inventory)

func _update_hud() -> void:
	title_label.text = FLOOR_NAMES[floor_number-1].to_upper()
	quest_label.text = "YOUR DESCENT\n\nThe heart below\n\n%s\n\nFloor %d of 3\n\nBreak crates. Open chests.\nBetter gear waits in the dark." % ["Defeat the Ash Warden." if floor_number==3 else "Find the stairway.",floor_number]
	health_bar.max_value = stats.max_hp
	health_bar.value = stats.hp
	xp_bar.max_value = stats.level*40
	xp_bar.value = stats.xp
	stats_label.text = "WAYFARER  /  LV %d     %d / %d HP" % [stats.level,stats.hp,stats.max_hp]
	skill_label.text = "Nova: %s  /  Dodge: %s      %d potions      %d gold      Attack %d" % ["READY" if nova_cd<=0 else "%.1fs" % nova_cd,"READY" if dodge_cd<=0 else "%.1fs" % dodge_cd,stats.potions,stats.gold,_damage()]
	hint_label.text = "Click to move / attack  -  E interact  -  Mouse wheel zoom"
	for prop in props:
		if prop.kind=="chest" and not prop.open and prop.node.position.distance_to(hero.position)<2: hint_label.text = "[E]  OPEN TREASURE CHEST"
	if floor_number<3 and hero.position.distance_to(stairs)<2: hint_label.text = "[E]  DESCEND  /  HEAL & RESTOCK POTIONS"
	boss_bar.hide()
	boss_label.hide()
	for enemy in enemies:
		if enemy.kind=="boss" and enemy.hp>0 and enemy.alert:
			boss_bar.show()
			boss_label.show()
			boss_bar.max_value = enemy.max_hp
			boss_bar.value = enemy.hp

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play": _pause()

func _smoke_test() -> void:
	# Exercise actual native scene creation and game systems without external tools.
	_begin()
	for number in [1,2,3]:
		_generate_floor(number)
		assert(not astar.get_point_path(Vector2i(7,7),Vector2i(38,38)).is_empty(),"Disconnected dungeon")
		assert(_walkable(hero.position),"Invalid hero spawn")
		for enemy in enemies: assert(cells.has(Vector2i(enemy.node.position.x,enemy.node.position.z)),"Invalid enemy spawn")
	_generate_floor(1)
	invulnerable = 0
	_hurt(20)
	assert(stats.hp == 100)
	_potion()
	assert(stats.hp == 120 and stats.potions == 2)
	_gain_xp(40)
	assert(stats.level == 2 and stats.max_hp == 140)
	var enemy = enemies[0]
	enemy.node.position = hero.position + Vector3(0.5,0,0)
	var hp_before = enemy.hp
	_slash(true)
	assert(enemy.hp < hp_before)
	var hp_after = enemy.hp
	_slash(true)
	assert(enemy.hp == hp_after)
	_dodge()
	_hurt(999)
	assert(stats.hp == 140)
	_toggle_inventory()
	assert(state == "inventory")
	_toggle_inventory()
	assert(state == "play")
	hero.position = stairs
	_interact()
	assert(floor_number == 2)
	assert(FileAccess.file_exists(save_file))
	_generate_floor(3)
	for boss in enemies:
		if boss.kind == "boss": _damage_enemy(boss,9999)
	assert(state == "victory")
	_begin()
	invulnerable = 0
	_hurt(9999)
	assert(state == "defeat")
	print("PASS: native scene, connected floors, movement, combat, cooldowns, dodge, healing, leveling, equipment menu, progression, checkpoint save, boss victory, and defeat.")
	get_tree().quit()

func _render_check() -> void:
	# Render the actual native scene to a development preview artifact.
	save_file = "user://render-check.json"
	_begin()
	for frame in 45:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result = get_viewport().get_texture().get_image().save_png("res://native-preview.png")
	assert(result == OK, "Could not save native render preview")
	if FileAccess.file_exists(save_file): DirAccess.remove_absolute(save_file)
	print("PASS: native renderer and 45 live frames; preview saved.")
	get_tree().quit()

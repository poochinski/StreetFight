extends RefCounted
## godot --path . --rendering-driver opengl3 -- --gear-gallery [--only=helmet|chest|gloves|boots|belt|worn]
## The gear images: every armor base at each rarity, alone on a dark purple
## grid from a three-quarter angle (previews/gear/<slot>/), one contact sheet
## per slot (previews/gear/sheet-<slot>.png) and each class in full sets, front
## and back (previews/gear/worn/). Chest pieces are shown on a plain form,
## since much of their look is the color they give the body and sleeves.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const Classes = preload("res://scripts/classes.gd")
const Models = preload("res://scripts/models.gd")
const GearModels = preload("res://scripts/gear_models.gd")

const OUT = "res://previews/gear/"
const ITEM_SIZE = 256
const WORN_SIZE = Vector2i(360, 480)
## Rarity n is shown at item level LEVELS[n] (or the base's band), so the row also walks the metal tiers.
const LEVELS = [1, 4, 7, 10, 13]
const BACKDROP = Color(0.03, 0.012, 0.06)
## Full sets per class: name, rarity and helmet, chest, gloves, boots, belt.
const SETS = {
	"samurai": [["plain", 0, []], ["ronin", 3, ["Hardhat Kabuto", "Tire-Tread O-Yoroi", "Kote Sleeves", "Tabi Boots", "Studded Obi"]],
		["demolition", 2, ["Moto Helmet", "Riot Vest", "Welding Gauntlets", "Steel-Toe Work Boots", "Weightlifting Belt"]],
		["hockey-legend", 4, ["Hockey Mask", "Cuirass", "Gauntlets", "Greaves", "Belt"]]],
	"gunslinger": [["plain", 0, []], ["drifter", 3, ["Cowboy Hat", "Duster Coat", "Fingerless Driving Gloves", "Cowboy Boots", "Ammo Bandolier"]],
		["mall-rat", 1, ["Sweatband & Shades", "Track Jacket", "Motocross Gloves", "Roller Skates", "Fanny Pack"]],
		["coif-starter", 0, ["Coif", "Studded Denim Vest", "Gloves", "High-Top Sneakers", "Belt"]]],
	"synth_mage": [["plain", 0, []], ["prophet", 3, ["Holo Visor", "Synthweave Robe", "Wired Gloves", "Neon-Sole Kicks", "Cassette Belt"]],
		["static-legend", 4, ["Walkman Headphones", "Neon Trench", "Insulated Gloves", "Moon Boots", "Sash"]],
		["mantle", 2, ["Gas Mask", "Mantle", "Hand Wraps", "Boots", "Tool Belt"]]],
}

const GRID_SHADER = """
shader_type spatial;
render_mode unshaded;
uniform vec4 base : source_color = vec4(0.08, 0.04, 0.15, 1.0);
uniform vec4 line : source_color = vec4(1.0, 0.31, 0.85, 1.0);
void fragment() {
	vec2 p = UV*48.0;
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p-0.5)-0.5)/w;
	float l = 1.0-min(min(g.x, g.y), 1.0);
	float fade = 1.0-smoothstep(0.05, 0.45, distance(UV, vec2(0.5)));
	ALBEDO = mix(base.rgb, line.rgb*0.55, l*fade);
}
"""

static func sample(slot: String, base: Dictionary, rarity: int) -> Dictionary:
	var level = maxi(int(base.get("level", 1)), LEVELS[rarity])
	var item = {"slot":slot, "base":base.name, "name":base.name, "rarity":rarity, "level":level, "affixes":[], "gems":[],
		"sockets":0, "value":1, "flavor":"", "armor":base.armor}
	for key in ["style", "look"]:
		if base.has(key): item[key] = base[key]
	if slot in Items.SOCKET_SLOTS and rarity>=2:
		item.sockets = 1 if rarity==2 else 2
		if rarity>=3: item.gems = [Items.make_gem(["ruby", "sapphire"][rarity-3], 1)]
	return item

static func _find(name: String) -> Dictionary:
	for slot in Items.ARMOR_SLOTS:
		for base in Items.BASES[slot]:
			if base.name==name: return {"slot":slot, "base":base}
	return {}

static func _studio(parent: Node, size: Vector2i) -> Dictionary:
	var vp = SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(vp)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BACKDROP
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.56, 0.8)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	env.environment.glow_hdr_threshold = 1.0
	vp.add_child(env)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.93, 0.86)
	vp.add_child(key)
	for spec in [[Vector3(-1.6, 2.0, -1.4), Color(0.25, 0.95, 1.0)], [Vector3(1.8, 1.4, -1.0), Color(1.0, 0.3, 0.85)]]:
		var rim = OmniLight3D.new()
		rim.position = spec[0]
		rim.light_color = spec[1]
		rim.light_energy = 2.2
		rim.omni_range = 6.0
		vp.add_child(rim)
	var floor = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor.mesh = plane
	var grid = ShaderMaterial.new()
	grid.shader = Shader.new()
	grid.shader.code = GRID_SHADER
	floor.material_override = grid
	vp.add_child(floor)
	var cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	return {"vp":vp, "cam":cam, "floor":floor, "rims":[]}

static func _bounds(node: Node3D) -> AABB:
	var box = AABB()
	var first = true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		if not m.is_visible_in_tree(): continue
		var b: AABB = m.global_transform*m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

static func _frame(studio: Dictionary, box: AABB, direction: Vector3, fill: float = 1.0) -> void:
	var center = box.get_center()
	var radius = maxf(0.15, box.size.length()*0.5)
	var cam: Camera3D = studio.cam
	cam.position = center+direction.normalized()*radius/sin(deg_to_rad(cam.fov*0.5))*fill
	cam.look_at(center, Vector3.UP)
	studio.floor.position = Vector3(center.x, box.position.y-0.01, center.z)

static func _shot(g, studio: Dictionary) -> Image:
	for k in 2:
		await g.get_tree().process_frame
		await RenderingServer.frame_post_draw
	return studio.vp.get_texture().get_image()

## A plain form under chest pieces: torso and T-pose arms in the piece's colors.
static func _form(gear, root: Node3D, item) -> void:
	var tint = gear.parts(item, "chest").tint
	for bone in gear._groups: gear._groups[bone].free()
	var body = MeshInstance3D.new()
	var torso = CylinderMesh.new()
	torso.top_radius = 0.37; torso.bottom_radius = 0.39; torso.height = 0.9
	body.mesh = torso
	body.position = Vector3(0, 0.83, 0)
	body.scale = Vector3(1, 1, 0.92)
	body.material_override = gear.mat(tint.get("body", Color("8a8490")), 0.8)
	root.add_child(body)
	for side in [-1, 1]:
		var arm = MeshInstance3D.new()
		var tube = CylinderMesh.new()
		tube.top_radius = 0.13; tube.bottom_radius = 0.13; tube.height = 0.86
		arm.mesh = tube
		arm.position = Vector3(side*0.52, 1.11, 0)
		arm.rotation.z = PI/2
		arm.material_override = gear.mat(tint.get("arms", Color("8a8490")), 0.8)
		root.add_child(arm)

static func run(g) -> void:
	var only = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var holder = Node.new()
	g.add_child(holder)
	var gear = GearModels.new()
	var studio = await _items(g, holder, gear, only)
	if only=="" or only=="worn": await _worn(g, holder)
	holder.queue_free()
	await g.get_tree().process_frame
	print("PASS: gear gallery saved to previews/gear/ (%d item images, contact sheets and worn sets)." % studio)
	g.get_tree().quit()

static func _items(g, holder: Node, gear, only: String) -> int:
	var studio = _studio(holder, Vector2i(ITEM_SIZE, ITEM_SIZE))
	var count = 0
	for slot in Items.ARMOR_SLOTS:
		if only!="" and only!=slot: continue
		DirAccess.make_dir_recursive_absolute(OUT+slot)
		var rows: Array = []
		for base in Items.BASES[slot]:
			var row: Array = []
			for rarity in 5:
				var item = sample(slot, base, rarity)
				var root = gear.build(item)
				if slot=="chest": _form(gear, root, item)
				for group in root.get_children():
					var bone = String(group.get_meta("bone", ""))
					# One glove reads better than a T-posed pair far apart.
					if slot=="gloves" and bone.ends_with(".r"):
						root.remove_child(group)
						group.free()
				studio.vp.add_child(root)
				var view = {"gloves":Vector3(0.35, 0.55, 1.0), "chest":Vector3(0.45, 0.4, 1.0)}.get(slot, Vector3(0.75, 0.5, 1.0))
				_frame(studio, _bounds(root), view, 0.95)
				var image: Image = await _shot(g, studio)
				image.save_png(OUT+"%s/%s-%d.png" % [slot, _file(base.name), rarity])
				row.append(image)
				root.free()
				count += 1
			rows.append([base, row])
		await _sheet(g, holder, slot, rows)
	studio.vp.queue_free()
	return count

static func _file(name: String) -> String:
	return name.to_lower().replace(" & ", "-").replace(" ", "-")

## One page per slot: a row per base (name, level band, favored class) and a
## column per rarity.
static func _sheet(g, holder: Node, slot: String, rows: Array) -> void:
	var cell = 168
	var left = 250
	var top = 44
	var vp = SubViewport.new()
	vp.size = Vector2i(left+cell*5+8, top+cell*rows.size()+8)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var bg = ColorRect.new()
	bg.color = Color("0c0616")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	for r in 5:
		_label(vp, Data.RARITIES[r], Vector2(left+r*cell, 10), Vector2(cell, 24), Data.RARITY_COLORS[r], 18, true)
	for i in rows.size():
		var base: Dictionary = rows[i][0]
		var y = top+i*cell
		var fav = base.get("fav", "")
		_label(vp, base.name, Vector2(12, y+cell*0.5-34), Vector2(left-16, 28), Data.INK, 18)
		_label(vp, "Level %d  ·  Armor %d" % [int(base.get("level", 1)), int(base.armor)], Vector2(12, y+cell*0.5-6), Vector2(left-16, 22), Data.INK_MUTED, 14)
		if fav!="": _label(vp, "Favored: %s" % Classes.CLASSES[fav].name, Vector2(12, y+cell*0.5+14), Vector2(left-16, 22), Classes.CLASSES[fav].color, 14)
		for r in 5:
			var picture = TextureRect.new()
			picture.texture = ImageTexture.create_from_image(rows[i][1][r])
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.position = Vector2(left+r*cell+2, y+2)
			picture.size = Vector2(cell-4, cell-4)
			vp.add_child(picture)
	await g.get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OUT+"sheet-%s.png" % slot)
	vp.queue_free()

static func _label(parent: Node, text: String, at: Vector2, size: Vector2, color: Color, font_size: int, center: bool = false) -> void:
	var label = Label.new()
	label.text = text
	label.position = at
	label.size = size
	label.clip_text = true
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if center: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

## Each class in its sets, front three-quarter and back three-quarter side by side.
static func _worn(g, holder: Node) -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"worn")
	var studio = _studio(holder, WORN_SIZE)
	var models = Models.new()
	for class_id in Classes.ORDER:
		for outfit in SETS[class_id]:
			var actor = models.hero(class_id)
			studio.vp.add_child(actor)
			models.idle(actor)
			actor.get_meta("anim").advance(0.35)
			var equipment = Items.empty_equipment()
			equipment.weapon = Items.starter_weapon()
			for name in outfit[2]:
				var found = _find(name)
				if not found.is_empty(): equipment[found.slot] = sample(found.slot, found.base, int(outfit[1]))
			models.gear.dress(actor, equipment)
			models.gear.pulse(actor, 0.0)
			var views: Array = []
			for turn in [0.5, PI+0.6]:
				actor.get_meta("model").rotation.y = turn
				var box = AABB(Vector3(-0.4, -0.02, -0.4), Vector3(0.8, 1.16, 0.8))
				_frame(studio, box, Vector3(0, 0.36, 1.0), 0.86)
				views.append(await _shot(g, studio))
			var sheet = Image.create(WORN_SIZE.x*2, WORN_SIZE.y, false, views[0].get_format())
			for k in 2: sheet.blit_rect(views[k], Rect2i(Vector2i.ZERO, WORN_SIZE), Vector2i(WORN_SIZE.x*k, 0))
			sheet.save_png(OUT+"worn/%s-%s.png" % [class_id, outfit[0]])
			actor.free()
	studio.vp.queue_free()

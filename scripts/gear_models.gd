extends RefCounted
## What you wear is what you see: every armor base built from simple shapes
## (boxes, cylinders, spheres, tori) and hung on the KayKit hero's bones, the way
## combat_weapons.gd builds weapons. Parts are laid out in the skeleton's rest
## space (T-pose, y up, +z forward, model units) and re-based onto their bone
## when worn, so one layout fits the Knight, Rogue and Mage. Paired parts are
## written for the left side (+x) and mirrored. Rarity follows the gear
## catalog (1.3): plain trim, a green stripe, blue neon trim and an extra
## part, violet trim on dark purple chrome and two extra parts, then
## gold-pink chrome with a pulsing glow and a light. Item level picks the
## metal (Rusted to Neon). Meshes and materials are cached; a hero is only
## re-dressed when its equipment changes.

const Items = preload("res://scripts/items.gd")
const Data = preload("res://scripts/data.gd")

const SLOTS = ["helmet", "chest", "gloves", "boots", "belt"]
## Bones that come in pairs: parts for them are written for .l and mirrored to .r.
const PAIRED = ["upperarm", "lowerarm", "hand", "upperleg", "lowerleg", "foot"]
## The plain clothes under the gear: shirt and trousers per class.
const PLAIN = {"samurai":[Color("aaa397"), Color("2b2a33")], "gunslinger":[Color("85838c"), Color("33415c")],
	"synth_mage":[Color("766c90"), Color("2a263c")]}
const SKIN = Color("f2b48a")
## Trim per rarity: plain tan, green paint, then blue, violet and gold neon.
const TRIM = [Color("b8a07a"), Color("5dff8f"), Color("3fb8ff"), Color("c76bff"), Color("ffb438")]
const TRIM_GLOW = [0.0, 0.0, 1.6, 2.2, 3.2]
## Neon is kept soft so the trim keeps its color under the bloom instead of burning white.
const GLOW_SCALE = 0.45
const EPIC_BASE = Color("2d2242")
const GOLD_PINK = Color("ffaf85")
const NEON_PINK = Color("ff4fd8")
## Built-in hats and capes the gear replaces.
const HIDDEN = ["Knight_Helmet", "Mage_Hat"]
## Helmets sit a little lower on the Rogue's and Mage's smaller heads.
const HEAD_FIT = {"samurai":Vector3(0, 0, 0), "gunslinger":Vector3(0, -0.06, 0), "synth_mage":Vector3(0, -0.05, 0)}

## Recolors the hero's body, arm and leg meshes toward plain cloth while the
## atlas cells that hold skin stay as painted.
const TINT_SHADER = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 cloth : source_color = vec4(1.0);
uniform bool extra_skin = true;
uniform bool hood_only = false;
void fragment() {
	vec4 t = texture(tex, UV);
	vec2 cell = floor(fract(UV)*vec2(8.0, 4.0));
	bool skin = cell.x<0.5 && cell.y<0.5;
	if (extra_skin) skin = skin || (cell.x>6.5 && cell.y>1.5 && cell.y<2.5) || (cell.x>5.5 && cell.y>2.5);
	// The hooded Rogue head: only its green hood takes the color.
	if (hood_only) skin = !(t.g>t.r+0.05 && t.g>t.b);
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = skin ? t.rgb : cloth.rgb*clamp(0.72+0.42*lum, 0.62, 1.12);
	ROUGHNESS = 0.82;
}
"""

var meshes = {}
var mats = {}
var pulsing: Array = []
var shader: Shader
var hood_head = null
## Build state for the piece being made.
var _groups = {}
var _sock = Vector3.ZERO
var _tint = {}
var _hood = false

# --- Materials and meshes -------------------------------------------------------

func mat(color: Color, rough: float = 0.75, metal: float = 0.0) -> StandardMaterial3D:
	var key = "m%s/%s/%s" % [color.to_html(), rough, metal]
	if not mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color; m.roughness = rough; m.metallic = metal
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats[key] = m
	return mats[key]

## Emissive neon. Pulsing ones (Legendary) breathe slowly; see pulse().
func glow(color: Color, energy: float = 2.0, pulse: bool = false) -> StandardMaterial3D:
	var key = "g%s/%s/%s" % [color.to_html(), energy, pulse]
	if not mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color; m.emission_enabled = true; m.emission = color
		m.emission_energy_multiplier = energy*GLOW_SCALE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats[key] = m
		if pulse: pulsing.append([m, energy*GLOW_SCALE])
	return mats[key]

## Tinted see-through plastic for lenses and visors.
func glass(color: Color, alpha: float = 0.7, energy: float = 0.0) -> StandardMaterial3D:
	var key = "s%s/%s/%s" % [color.to_html(), alpha, energy]
	if not mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(color, alpha); m.roughness = 0.1; m.metallic = 0.4
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if energy>0: m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = energy*GLOW_SCALE
		mats[key] = m
	return mats[key]

func _mesh(kind: String, size: Vector3) -> Mesh:
	var key = kind+str(size)
	if meshes.has(key): return meshes[key]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new(); mesh.size = size
		"cyl", "tube", "cone", "skirt":
			mesh = CylinderMesh.new(); mesh.bottom_radius = size.x; mesh.height = size.y
			mesh.top_radius = size.z if kind in ["cone", "skirt"] else size.x
			mesh.radial_segments = 16; mesh.rings = 1
			if kind in ["tube", "skirt"]: mesh.cap_top = false; mesh.cap_bottom = false
		"oct":
			mesh = CylinderMesh.new(); mesh.top_radius = size.x; mesh.bottom_radius = size.x; mesh.height = size.y
			mesh.radial_segments = 8; mesh.rings = 1
		"sphere", "hemi":
			mesh = SphereMesh.new(); mesh.radius = size.x; mesh.height = size.x*(1.0 if kind=="hemi" else 2.0)
			mesh.is_hemisphere = kind=="hemi"; mesh.radial_segments = 18; mesh.rings = 9
		"torus":
			mesh = TorusMesh.new(); mesh.inner_radius = size.x; mesh.outer_radius = size.y
			mesh.rings = 24; mesh.ring_segments = 8
		"prism":
			mesh = PrismMesh.new(); mesh.size = size
	meshes[key] = mesh
	return mesh

func _group(bone: String) -> Node3D:
	if not _groups.has(bone):
		var group = Node3D.new()
		group.name = bone.replace(".", "_")
		group.set_meta("bone", bone)
		_groups[bone] = group
	return _groups[bone]

## Adds one shape. Sizes: box size; cyl/tube/oct radius x, height y; cone bottom
## radius x, height y, top radius z; sphere/hemi radius x; torus inner x, outer y;
## prism size. A paired bone ("hand", "foot"...) gets a mirrored copy on the right.
func _add(bone: String, kind: String, size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var sides = [[bone, pos, rot]]
	if bone in PAIRED: sides = [[bone+".l", pos, rot], [bone+".r", Vector3(-pos.x, pos.y, pos.z), Vector3(rot.x, -rot.y, -rot.z)]]
	for side in sides:
		var node = MeshInstance3D.new()
		node.mesh = _mesh(kind, size)
		node.material_override = m
		node.position = side[1]
		node.rotation = side[2]
		node.scale = scl
		_group(side[0]).add_child(node)

## Shapes placed evenly around a vertical ring (belts, hems, stud rows), facing out.
func _ring(bone: String, kind: String, size: Vector3, center: Vector3, radius: Vector2, from: float, to: float, count: int, m: Material, tilt: float = 0.0) -> void:
	for k in count:
		var a = lerpf(from, to, (k+0.5)/count) if count>1 else (from+to)/2
		_add(bone, kind, size, center+Vector3(sin(a)*radius.x, 0, cos(a)*radius.y), m, Vector3(tilt, a, 0))

# --- Look of one item -------------------------------------------------------------

## The palette of an item: base colors darkened or brightened by rarity, the
## metal of its level tier, and the trim, stripe and accent of its rarity.
func _context(item, slot: String) -> Dictionary:
	var base = Items.base_info(item)
	var r = clampi(int(item.get("rarity", 0)), 0, 4)
	var tier = clampi((int(item.get("level", 1))-1)/3, 0, 4)
	var colors: Array = base.get("colors", [Color("6b5a4a"), Color("3a3440")])
	var main: Color = colors[0]
	var second: Color = colors[1]
	var metal: Color = Items.material_color(item, true)
	if r==0: main = main.darkened(0.1)
	main = main.lightened(tier*0.025)
	if r==3:
		main = main.lerp(EPIC_BASE, 0.5); second = second.lerp(EPIC_BASE, 0.25); metal = metal.lerp(Color("4a3a6e"), 0.55)
	elif r==4:
		main = main.lerp(GOLD_PINK, 0.6); second = second.lerp(Color("ffcf6a"), 0.35); metal = Color("ffcf6a")
	var style = base.get("style", item.get("style", item.get("look", "")))
	if style in ["leather", "mail", "plate", "mantle"]: style = {"leather":"jerkin", "mail":"hauberk", "plate":"cuirass", "mantle":"mantle"}[style]
	var c = {"r":r, "tier":tier, "slot":slot, "style":style, "main_color":main, "second_color":second, "rarity_color":Data.RARITY_COLORS[r]}
	c.main = mat(main, 0.3 if r==4 else 0.7, 0.55 if r==4 else 0.0)
	c.second = mat(second, 0.6, 0.0)
	c.metal = mat(metal, 0.35, 0.55)
	c.dark = mat(Color("1b1a20").lerp(EPIC_BASE, 0.5 if r==3 else 0.0), 0.8)
	c.trim = glow(TRIM[r], TRIM_GLOW[r], r==4) if r>=2 else mat(TRIM[r], 0.6)
	c.stripe = [mat(Color("8c8775"), 0.9), mat(TRIM[1], 0.5), c.trim, c.trim, c.trim][r]
	c.accent = glow(NEON_PINK, 2.6, true) if r==4 else c.trim
	c.rarity_glow = glow(Data.RARITY_COLORS[r], 1.4+r*0.4, r==4)
	return c

## Builds an item's parts. Returns {"groups": {bone: Node3D in rest space},
## "tint": body/arm colors for chest pieces, "hood": the Rogue's hood swap}.
func parts(item, slot: String = "") -> Dictionary:
	if slot=="": slot = item.slot
	_groups = {}
	_tint = {}
	_hood = false
	_sock = Vector3.INF
	var c = _context(item, slot)
	var fn = "_%s_%s" % [slot, c.style]
	if not has_method(fn): fn = "_%s_%s" % [slot, {"helmet":"helm", "chest":"jerkin", "gloves":"gloves", "boots":"boots", "belt":"belt"}.get(slot, "belt")]
	call(fn, c)
	# Sockets show as gem studs in the gem's color.
	if _sock!=Vector3.INF:
		var gems: Array = item.get("gems", [])
		for k in int(item.get("sockets", 0)):
			var gem_mat = glow(Items.GEMS[gems[k].gem].color, 1.6) if k<gems.size() and Items.GEMS.has(gems[k].get("gem")) else mat(Color("15121c"), 0.2, 0.5)
			var bone = "head" if slot=="helmet" else "chest"
			_add(bone, "sphere", Vector3(0.05, 0, 0), _sock+Vector3((k-(int(item.sockets)-1)*0.5)*0.13, 0, 0), gem_mat)
			_add(bone, "torus", Vector3(0.045, 0.07, 0), _sock+Vector3((k-(int(item.sockets)-1)*0.5)*0.13, 0, -0.01), c.metal, Vector3(PI/2, 0, 0))
	return {"groups":_groups, "tint":_tint, "hood":_hood}

## One item on its own (for the gallery): every part in rest space, plus the
## Legendary light. The caller frees it.
func build(item, slot: String = "") -> Node3D:
	var root = Node3D.new()
	var built = parts(item, slot)
	for bone in built.groups: root.add_child(built.groups[bone])
	if int(item.get("rarity", 0))==4: _legend_light(root, Vector3(0, 0, 0.4), 1.6)
	return root

func _legend_light(parent: Node3D, at: Vector3, reach: float) -> OmniLight3D:
	var light = OmniLight3D.new()
	light.name = "LegendLight"
	light.light_color = Color("ffc07a")
	light.light_energy = 0.9
	light.omni_range = reach
	light.position = at
	parent.add_child(light)
	return light

## Slow breathing of every Legendary glow (shared materials) and of the hero's light.
func pulse(actor: Node3D, time: float) -> void:
	var wave = 0.78+0.3*sin(time*2.2)
	for entry in pulsing: entry[0].emission_energy_multiplier = entry[1]*wave
	if actor.has_meta("gear_light") and is_instance_valid(actor.get_meta("gear_light")): actor.get_meta("gear_light").light_energy = 0.9*wave

# --- Wearing it ---------------------------------------------------------------------

func _key(actor: Node3D, equipment: Dictionary) -> String:
	var parts_key = [actor.get_meta("class", "")]
	for slot in SLOTS:
		var item = equipment.get(slot)
		if item==null: parts_key.append(null)
		else: parts_key.append([item.get("base", ""), item.get("rarity", 0), clampi((int(item.get("level", 1))-1)/3, 0, 4), item.get("sockets", 0), item.get("gems", []).map(func(gem): return gem.get("gem", ""))])
	return JSON.stringify(parts_key)

## Dresses a hero in its armor: plain clothes underneath, built-in hats and
## capes hidden, each piece on its bones. Does nothing if nothing changed.
func dress(actor: Node3D, equipment: Dictionary) -> void:
	var key = _key(actor, equipment)
	if actor.get_meta("gear_key", "")==key: return
	actor.set_meta("gear_key", key)
	for node in actor.get_meta("gear_nodes", []):
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	var sk: Skeleton3D = actor.find_children("*", "Skeleton3D", true, false)[0]
	var class_id: String = actor.get_meta("class", "samurai")
	var plain: Array = PLAIN.get(class_id, PLAIN.samurai)
	var tint = {"body":plain[0], "arms":plain[0], "legs":plain[1]}
	var nodes: Array = []
	var attach: Dictionary = actor.get_meta("gear_attach", {})
	var hood = false
	var legendary = false
	for slot in SLOTS:
		var item = equipment.get(slot)
		if item==null: continue
		var built = parts(item, slot)
		tint.merge(built.tint, true)
		hood = hood or built.hood
		legendary = legendary or int(item.get("rarity", 0))==4
		for bone in built.groups:
			var group: Node3D = built.groups[bone]
			var index = sk.find_bone(bone)
			if index<0:
				group.free()
				continue
			if not attach.has(bone):
				var a = BoneAttachment3D.new()
				a.bone_name = bone
				sk.add_child(a)
				attach[bone] = a
			var fit = Transform3D(Basis(), HEAD_FIT.get(class_id, Vector3.ZERO) if slot=="helmet" else Vector3.ZERO)
			group.transform = sk.get_bone_global_rest(index).affine_inverse()*fit
			if hood and class_id=="gunslinger":
				for part in group.get_children():
					if part.has_meta("hood"): part.free()
			attach[bone].add_child(group)
			nodes.append(group)
			for m in group.find_children("*", "MeshInstance3D", true, false):
				m.material_overlay = actor.get_meta("flash")
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.set_meta("gear_attach", attach)
	if legendary:
		var light = _legend_light(actor, Vector3(0, 0.55, 0.25), 2.4)
		nodes.append(light)
		actor.set_meta("gear_light", light)
	elif actor.has_meta("gear_light"): actor.remove_meta("gear_light")
	actor.set_meta("gear_nodes", nodes)
	_clothe(actor, tint, hood and class_id=="gunslinger")

## Plain clothes: recolors the skinned body, arm and leg meshes, hides capes and
## built-in hats, and swaps the Rogue's head for the hooded one under a Coif.
func _clothe(actor: Node3D, tint: Dictionary, hooded: bool) -> void:
	if shader==null:
		shader = Shader.new()
		shader.code = TINT_SHADER
	var knight = actor.get_meta("class", "")=="samurai"
	for m in actor.get_meta("meshes", []):
		var name = String(m.name)
		if name.ends_with("_Cape") or name in HIDDEN:
			m.visible = false
			continue
		if not m.get_parent() is Skeleton3D: continue
		if name.begins_with("Rogue_Head"):
			if not m.has_meta("own_mesh"): m.set_meta("own_mesh", [m.mesh, m.skin])
			var head = _hooded_head() if hooded else m.get_meta("own_mesh")
			m.mesh = head[0]; m.skin = head[1]
			var own = head[0].surface_get_material(0)
			m.material_override = _tint_material(own.albedo_texture, tint.hood, true, true) if hooded and tint.has("hood") and own is BaseMaterial3D else null
			continue
		var part = "body" if "Body" in name else "arms" if "Arm" in name else "legs" if "Leg" in name else ""
		if part=="": continue
		if not m.has_meta("own_texture"):
			var own = m.mesh.surface_get_material(0)
			m.set_meta("own_texture", own.albedo_texture if own is BaseMaterial3D else null)
		m.material_override = _tint_material(m.get_meta("own_texture"), tint[part], not knight)

func _tint_material(texture: Texture2D, color: Color, extra_skin: bool, hood_only: bool = false) -> ShaderMaterial:
	var key = "t%s/%s/%s/%s" % [texture.get_rid().get_id() if texture else 0, color.to_html(), extra_skin, hood_only]
	if not mats.has(key):
		var m = ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("tex", texture)
		m.set_shader_parameter("cloth", color)
		m.set_shader_parameter("extra_skin", extra_skin)
		m.set_shader_parameter("hood_only", hood_only)
		mats[key] = m
	return mats[key]

## The hooded Rogue head (mesh and skin), used as the Gunslinger's Coif.
func _hooded_head() -> Array:
	if hood_head==null:
		var scene = load("res://assets/models/characters/Rogue_Hooded.glb").instantiate()
		for m in scene.find_children("*", "MeshInstance3D", true, false):
			if String(m.name)=="Rogue_Head_Hooded": hood_head = [m.mesh, m.skin]
		scene.free()
	return hood_head

# --- Helmets (head bone; the head is about 1.1 wide, top near y 2.3, face at z 0.5) ---

func _helmet_coif(c) -> void:
	_hood = true
	_tint = {"hood":c.main_color}
	_add("head", "sphere", Vector3(0.62, 0, 0), Vector3(0, 1.82, -0.12), c.main, Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
	_add("head", "cone", Vector3(0.2, 0.3, 0.02), Vector3(0, 2.2, -0.55), c.main, Vector3(-1.1, 0, 0))
	_hood_marks()
	_add("head", "cone", Vector3(0.5, 0.14, 0.34), Vector3(0, 1.3, 0.0), c.metal)
	for k in 8: _add("head", "box", Vector3(0.1, 0.03, 0.02), Vector3(sin(k*0.785)*0.43, 1.3, cos(k*0.785)*0.43), mat(c.metal.albedo_color.lightened(0.3), 0.3, 0.6), Vector3(-0.6, k*0.785, 0))
	_add("head", "box", Vector3(0.04, 0.24, 0.3), Vector3(0.6, 1.9, -0.1), c.stripe, Vector3(0, 0, -0.25))
	if c.r>=2:
		for x in [-0.16, 0.16]: _add("head", "cyl", Vector3(0.018, 0.3, 0), Vector3(x, 1.36, 0.5), c.trim)
	if c.r>=3:
		_add("head", "torus", Vector3(0.36, 0.42, 0), Vector3(0, 1.74, 0.42), c.trim, Vector3(PI/2, 0, 0), Vector3(1.05, 1, 1.2))
		_add("head", "sphere", Vector3(0.06, 0, 0), Vector3(0, 2.12, -0.82), c.trim)
	if c.r==4:
		for k in 6: _add("head", "sphere", Vector3(0.035, 0, 0), Vector3(cos(k*1.05)*0.46, 1.3, sin(k*1.05)*0.46), c.accent)
	_sock = Vector3(0, 2.26, 0.4)

## Marks the parts just added to the head as the hood the Rogue model brings itself.
func _hood_marks() -> void:
	for part in _group("head").get_children(): part.set_meta("hood", true)

func _helmet_helm(c) -> void:
	_add("head", "hemi", Vector3(0.64, 0, 0), Vector3(0, 1.86, -0.06), c.main, Vector3.ZERO, Vector3(1.03, 0.98, 1.02))
	_add("head", "torus", Vector3(0.62, 0.69, 0), Vector3(0, 1.87, -0.06), c.dark, Vector3.ZERO, Vector3(1.03, 1.0, 1.02))
	for x in [-1, 1]: _add("head", "box", Vector3(0.1, 0.36, 0.5), Vector3(x*0.62, 1.72, -0.12), c.main)
	var visor = glass(c.trim.albedo_color if c.r>=2 else c.second_color, 0.75, 1.2 if c.r>=2 else 0.0)
	_add("head", "box", Vector3(1.0, 0.36, 0.04), Vector3(0, 2.3, 0.42), visor, Vector3(-0.95, 0, 0))
	_add("head", "hemi", Vector3(0.652, 0, 0), Vector3(0, 1.86, -0.06), c.stripe, Vector3.ZERO, Vector3(0.12, 0.98, 1.02))
	for x in [-1, 1]: _add("head", "box", Vector3(0.04, 0.42, 0.05), Vector3(x*0.56, 1.42, 0.16), c.dark, Vector3(0.35, 0, 0))
	if c.r>=2: _add("head", "cyl", Vector3(0.025, 0.3, 0), Vector3(0.5, 2.38, -0.3), c.trim, Vector3(0, 0, -0.5))
	if c.r>=3: _add("head", "box", Vector3(0.07, 0.2, 0.7), Vector3(0, 2.55, -0.1), c.trim)
	if c.r==4:
		for k in 5: _add("head", "prism", Vector3(0.1, 0.24, 0.12), Vector3(0, 2.62, 0.25-k*0.17), c.accent, Vector3(-0.3, 0, 0))
	_sock = Vector3(0, 2.18, 0.52)

func _helmet_visor(c) -> void:
	_add("head", "tube", Vector3(0.56, 0.1, 0), Vector3(0, 1.94, -0.02), c.dark)
	_add("head", "hemi", Vector3(0.6, 0, 0), Vector3(0, 1.96, -0.02), c.dark, Vector3.ZERO, Vector3(0.12, 0.62, 1))
	_add("head", "box", Vector3(1.04, 0.98, 0.1), Vector3(0, 1.7, 0.62), c.main, Vector3(0.06, 0, 0))
	for x in [-1, 1]: _add("head", "box", Vector3(0.1, 0.9, 0.42), Vector3(x*0.54, 1.7, 0.42), c.main)
	_add("head", "box", Vector3(0.64, 0.17, 0.03), Vector3(0, 1.82, 0.67), glass(Color("101418"), 0.95))
	var slit = glow(c.rarity_color if c.r>=2 else Color("6fd8ff"), 1.2+c.r*0.5, c.r==4) if c.r!=4 else glow(Color("ff9a3c"), 3.0, true)
	_add("head", "box", Vector3(0.54, 0.05, 0.035), Vector3(0, 1.82, 0.675), slit)
	for x in [-1, 1]: _add("head", "cyl", Vector3(0.07, 0.08, 0), Vector3(x*0.6, 1.84, 0.34), c.metal, Vector3(0, 0, PI/2))
	_add("head", "box", Vector3(0.74, 0.06, 0.02), Vector3(0, 1.48, 0.675), c.stripe)
	if c.r>=2: _add("head", "box", Vector3(0.08, 0.3, 0.08), Vector3(0, 2.3, 0.4), c.trim, Vector3(0.4, 0, 0))
	if c.r>=3:
		for x in [-0.28, 0, 0.28]: _add("head", "prism", Vector3(0.14, 0.22, 0.02), Vector3(x, 1.36, 0.68), c.trim)
	if c.r==4: _add("head", "box", Vector3(0.62, 0.15, 0.01), Vector3(0, 1.82, 0.69), glass(NEON_PINK, 0.35, 1.5))
	_sock = Vector3(0, 2.06, 0.68)

func _helmet_shades(c) -> void:
	var band = c.main if c.r!=1 else mat(TRIM[1], 0.8)
	if c.r==3: band = mat(Color("6a3a9a"), 0.8)
	_add("head", "tube", Vector3(0.555, 0.13, 0), Vector3(0, 1.93, 0.0), band)
	for y in [1.87, 1.99]: _add("head", "tube", Vector3(0.558, 0.012, 0), Vector3(0, y, 0.0), mat(band.albedo_color.darkened(0.15), 0.9))
	var lens = glass(c.trim.albedo_color, 0.85, 1.0) if c.r>=2 else glass(c.second_color, 0.92)
	if c.r==4: lens = glass(Color("ff7a5c"), 0.9, 1.6)
	var frame = c.metal if c.r<4 else mat(Color("ffcf6a"), 0.25, 0.9)
	for x in [-1, 1]:
		_add("head", "sphere", Vector3(0.15, 0, 0), Vector3(x*0.21, 1.7, 0.57), lens, Vector3(0, 0, x*0.15), Vector3(1.15, 0.85, 0.25))
		_add("head", "torus", Vector3(0.14, 0.165, 0), Vector3(x*0.21, 1.7, 0.575), frame, Vector3(PI/2, 0, 0), Vector3(1.15, 1, 0.85))
		_add("head", "box", Vector3(0.025, 0.025, 0.5), Vector3(x*0.52, 1.74, 0.33), frame)
	_add("head", "box", Vector3(0.14, 0.025, 0.025), Vector3(0, 1.76, 0.59), frame)
	if c.r>=2:
		for k in 2: _add("head", "box", Vector3(0.08, 0.24, 0.03), Vector3(0.06-k*0.12, 1.78, -0.58), band, Vector3(0.3, 0, 0.3-k*0.6))
	if c.r>=3: _add("head", "prism", Vector3(0.1, 0.12, 0.02), Vector3(0, 1.93, 0.565), c.trim, Vector3(0, 0, 0.4))
	if c.r==4: _add("head", "tube", Vector3(0.562, 0.02, 0), Vector3(0, 1.93, 0.0), c.accent)

func _helmet_hockey(c) -> void:
	_add("head", "sphere", Vector3(0.44, 0, 0), Vector3(0, 1.7, 0.44), c.main, Vector3.ZERO, Vector3(1.0, 1.18, 0.42))
	var holes = mat(Color("121216"), 0.9)
	var eyes = c.trim if c.r>=3 else holes
	if c.r==4: eyes = c.accent
	for x in [-1, 1]:
		_add("head", "sphere", Vector3(0.09, 0, 0), Vector3(x*0.19, 1.74, 0.6), eyes, Vector3(0, 0, x*0.25), Vector3(1.35, 0.8, 0.3))
		for p in [Vector2(0.1, 1.44), Vector2(0.22, 1.52), Vector2(0.3, 1.66), Vector2(0.08, 1.33)]:
			_add("head", "cyl", Vector3(0.028, 0.03, 0), Vector3(x*p.x, p.y, 0.6-p.x*0.18), holes, Vector3(PI/2, 0, 0))
		var chevron = c.second if c.r<2 else c.trim
		_add("head", "box", Vector3(0.2, 0.05, 0.03), Vector3(x*0.1, 2.0, 0.58), chevron, Vector3(0, 0, x*0.45))
		_add("head", "box", Vector3(0.2, 0.05, 0.03), Vector3(x*0.1, 2.1, 0.55), chevron, Vector3(0, 0, x*0.45))
	_add("head", "tube", Vector3(0.56, 0.06, 0), Vector3(0, 1.86, 0.0), c.dark)
	_add("head", "box", Vector3(0.05, 0.16, 0.03), Vector3(0.36, 1.5, 0.56), c.stripe, Vector3(0, 0.6, 0))
	if c.r>=2: _add("head", "box", Vector3(0.06, 0.06, 0.4), Vector3(0, 2.2, 0.32), c.main)
	if c.r>=3:
		_add("head", "box", Vector3(0.02, 0.3, 0.02), Vector3(-0.12, 1.5, 0.62), c.trim, Vector3(0, 0, 0.5))
		_add("head", "box", Vector3(0.02, 0.2, 0.02), Vector3(-0.2, 1.36, 0.6), c.trim, Vector3(0, 0, -0.4))
	if c.r==4: _add("head", "sphere", Vector3(0.62, 0, 0), Vector3(0, 1.86, -0.16), c.second, Vector3.ZERO, Vector3(1, 1, 0.95))

func _helmet_headphones(c) -> void:
	var band = c.second if c.r<3 else c.trim
	for k in 11:
		var a = PI*k/10.0
		_add("head", "box", Vector3(0.2, 0.06, 0.1), Vector3(cos(a)*0.62, 1.72+sin(a)*0.66, -0.04), band, Vector3(0, 0, a+PI/2))
	var pads = c.main if c.r<2 else glow(TRIM[c.r], 1.2, c.r==4)
	for x in [-1, 1]:
		_add("head", "cyl", Vector3(0.21, 0.14, 0), Vector3(x*0.62, 1.7, -0.02), c.second if c.r<4 else c.metal, Vector3(0, 0, PI/2))
		_add("head", "cyl", Vector3(0.19, 0.08, 0), Vector3(x*0.53, 1.7, -0.02), pads, Vector3(0, 0, PI/2))
	_add("head", "box", Vector3(0.02, 0.12, 0.22), Vector3(0.7, 1.7, -0.02), c.stripe)
	if c.r>=2:
		_add("head", "cyl", Vector3(0.016, 0.5, 0), Vector3(0.48, 1.52, 0.3), c.metal, Vector3(0.9, 0, 0.35))
		_add("head", "sphere", Vector3(0.04, 0, 0), Vector3(0.36, 1.38, 0.52), c.dark)
	if c.r>=3:
		for k in 2:
			_add("head", "sphere", Vector3(0.05, 0, 0), Vector3(-0.75+k*0.2, 2.25+k*0.15, 0.2), c.trim, Vector3.ZERO, Vector3(1.2, 0.9, 0.6))
			_add("head", "box", Vector3(0.02, 0.18, 0.02), Vector3(-0.71+k*0.2, 2.34+k*0.15, 0.2), c.trim)
	if c.r==4: _add("head", "torus", Vector3(0.78, 0.82, 0), Vector3(0, 1.72, 0), c.accent, Vector3(0, 0, 0.12))

func _helmet_cowboy(c) -> void:
	var hat = c.main if c.r<4 else mat(Color("f4efe4"), 0.6)
	var band = c.second if c.r<2 else c.trim
	if c.r==4: band = c.accent
	_add("head", "cyl", Vector3(0.98, 0.04, 0), Vector3(0, 2.12, 0.02), hat, Vector3(-0.06, 0, 0), Vector3(1, 1, 0.9))
	for x in [-1, 1]: _add("head", "box", Vector3(0.2, 0.04, 0.7), Vector3(x*0.86, 2.17, 0.02), hat, Vector3(0, 0, x*0.45))
	_add("head", "cone", Vector3(0.5, 0.42, 0.4), Vector3(0, 2.34, 0.0), hat, Vector3(-0.06, 0, 0))
	_add("head", "box", Vector3(0.1, 0.06, 0.5), Vector3(0, 2.56, 0.0), mat(hat.albedo_color.darkened(0.2)))
	_add("head", "cyl", Vector3(0.51, 0.08, 0), Vector3(0, 2.19, 0.0), band, Vector3(-0.06, 0, 0))
	_add("head", "prism", Vector3(0.1, 0.1, 0.03), Vector3(0, 2.2, 0.52), c.metal)
	_add("head", "box", Vector3(0.03, 0.14, 0.2), Vector3(0.47, 2.36, 0.0), c.stripe)
	if c.r>=2: _add("head", "box", Vector3(0.1, 0.07, 0.03), Vector3(-0.35, 2.19, 0.37), c.metal, Vector3(0, -0.75, 0))
	if c.r>=3: _add("head", "cyl", Vector3(0.012, 0.6, 0), Vector3(0.3, 1.62, 0.3), c.trim, Vector3(0.3, 0, 0.3))
	if c.r==4: _add("head", "prism", Vector3(0.08, 0.5, 0.03), Vector3(-0.42, 2.42, -0.1), c.accent, Vector3(0.2, 0, 0.5))
	_sock = Vector3(0, 2.3, 0.46)

func _helmet_gasmask(c) -> void:
	_add("head", "sphere", Vector3(0.4, 0, 0), Vector3(0, 1.56, 0.4), c.main, Vector3.ZERO, Vector3(1.1, 0.95, 0.55))
	_add("head", "box", Vector3(0.66, 0.34, 0.16), Vector3(0, 1.76, 0.5), c.main)
	var lens = glass(c.trim.albedo_color, 0.85, 1.4) if c.r>=2 else glass(Color("22303a"), 0.92)
	if c.r==4: lens = glass(NEON_PINK, 0.85, 1.8)
	for x in [-1, 1]:
		_add("head", "cyl", Vector3(0.12, 0.04, 0), Vector3(x*0.17, 1.76, 0.585), lens, Vector3(PI/2, 0, 0))
		_add("head", "torus", Vector3(0.11, 0.15, 0), Vector3(x*0.17, 1.76, 0.59), c.metal, Vector3(PI/2, 0, 0))
	var can = c.second if c.r<3 else c.trim
	_add("head", "cyl", Vector3(0.09, 0.1, 0), Vector3(0, 1.42, 0.62), c.metal, Vector3(PI/2, 0, 0))
	_add("head", "cyl", Vector3(0.13, 0.2, 0), Vector3(0.3, 1.42, 0.62), can, Vector3(PI/2, 0.6, 0))
	_add("head", "tube", Vector3(0.56, 0.07, 0), Vector3(0, 1.84, -0.02), c.dark)
	_add("head", "tube", Vector3(0.133, 0.04, 0), Vector3(0.36, 1.42, 0.7), c.stripe, Vector3(PI/2, 0.6, 0))
	if c.r>=2: _add("head", "cyl", Vector3(0.05, 0.05, 0), Vector3(-0.2, 1.4, 0.6), c.metal, Vector3(PI/2, -0.4, 0))
	if c.r>=3: _add("head", "cyl", Vector3(0.13, 0.2, 0), Vector3(-0.3, 1.42, 0.62), can, Vector3(PI/2, -0.6, 0))
	if c.r==4: _add("head", "sphere", Vector3(0.14, 0, 0), Vector3(0.42, 1.42, 0.82), glass(NEON_PINK, 0.3, 1.5))

func _helmet_kabuto(c) -> void:
	_add("head", "hemi", Vector3(0.63, 0, 0), Vector3(0, 1.95, -0.02), c.main, Vector3.ZERO, Vector3(1.04, 0.95, 1.06))
	_add("head", "hemi", Vector3(0.636, 0, 0), Vector3(0, 1.95, -0.02), mat(c.main_color.darkened(0.25), 0.6), Vector3.ZERO, Vector3(0.14, 0.96, 1.07))
	_add("head", "cyl", Vector3(0.72, 0.04, 0), Vector3(0, 1.95, 0.04), c.main, Vector3.ZERO, Vector3(1, 1, 1.08))
	# Neck guard: three rubber strips stepping out down the back and sides.
	for k in 3:
		var y = 1.88-k*0.1
		var spread = 0.6+k*0.035
		_add("head", "box", Vector3(1.0+k*0.08, 0.09, 0.05), Vector3(0, y, -spread), c.second, Vector3(0.35, 0, 0))
		for x in [-1, 1]: _add("head", "box", Vector3(0.05, 0.09, 0.5), Vector3(x*spread, y, -0.3), c.second, Vector3(0, 0, -x*0.35))
	var crest = c.metal if c.r<2 else c.trim
	if c.r==4: crest = c.accent
	for x in [-1, 1]: _add("head", "box", Vector3(0.08, 0.62, 0.03), Vector3(x*0.2, 2.32, 0.7), crest, Vector3(0.15, 0, -x*0.5))
	_add("head", "oct", Vector3(0.13, 0.03, 0), Vector3(0, 2.1, 0.72), mat(Color("c0262c"), 0.5), Vector3(PI/2, 0, 0))
	_add("head", "box", Vector3(0.04, 0.24, 0.3), Vector3(0.64, 2.06, 0.0), c.stripe, Vector3(0, 0, -0.5))
	if c.r>=2: _add("head", "cone", Vector3(0.05, 0.2, 0.0), Vector3(0, 2.62, -0.05), c.metal)
	if c.r>=3:
		_add("head", "sphere", Vector3(0.3, 0, 0), Vector3(0, 1.42, 0.42), c.dark, Vector3.ZERO, Vector3(1.25, 0.55, 0.55))
		for x in [-1, 1]: _add("head", "box", Vector3(0.12, 0.012, 0.02), Vector3(x*0.12, 1.42, 0.58), c.trim, Vector3(0, 0, x*0.3))
	if c.r==4: _add("head", "torus", Vector3(0.24, 0.28, 0), Vector3(0, 2.5, 0.62), c.accent, Vector3(PI/2, 0, 0), Vector3(1.4, 1, 1))
	_sock = Vector3(0, 2.1, 0.76)

func _helmet_holo(c) -> void:
	_add("head", "tube", Vector3(0.56, 0.1, 0), Vector3(0, 1.9, 0.0), c.main)
	var visor = glass(c.rarity_color if c.r<4 else NEON_PINK, 0.42, 1.8)
	_add("head", "sphere", Vector3(0.62, 0, 0), Vector3(0, 1.72, 0.14), visor, Vector3.ZERO, Vector3(1.0, 0.27, 0.68))
	for y in [1.67, 1.73, 1.79]: _add("head", "box", Vector3(0.48, 0.012, 0.01), Vector3(0, y, 0.575), glow(c.rarity_color, 2.0, c.r==4))
	for x in [-1, 1]: _add("head", "box", Vector3(0.12, 0.2, 0.26), Vector3(x*0.6, 1.76, 0.06), c.metal)
	_add("head", "box", Vector3(0.02, 0.12, 0.18), Vector3(0.67, 1.76, 0.06), c.stripe)
	if c.r>=2:
		_add("head", "cyl", Vector3(0.015, 0.4, 0), Vector3(0.62, 2.04, 0.0), c.metal)
		_add("head", "sphere", Vector3(0.035, 0, 0), Vector3(0.62, 2.25, 0.0), c.rarity_glow)
	if c.r>=3:
		_add("head", "cyl", Vector3(0.015, 0.3, 0), Vector3(-0.62, 1.98, 0.0), c.metal)
		_add("head", "prism", Vector3(0.12, 0.12, 0.02), Vector3(-0.3, 2.42, 0.3), c.trim)
	if c.r==4:
		for k in 3: _add("head", "prism", Vector3(0.12, 0.12, 0.02), Vector3(cos(k*2.1)*0.75, 2.35, sin(k*2.1)*0.75), c.accent, Vector3(0, k, 0))
		_add("head", "box", Vector3(0.52, 0.01, 0.01), Vector3(0, 1.64, 0.58), glow(Color("3ff0ff"), 2.5, true))
	_sock = Vector3(0, 1.92, 0.6)

func _helmet_moto(c) -> void:
	_add("head", "sphere", Vector3(0.64, 0, 0), Vector3(0, 1.8, 0.0), c.main, Vector3.ZERO, Vector3(1.0, 0.98, 1.02))
	var visor = glass(Color("0e0e14"), 0.92) if c.r<4 else glass(Color("ff8a5a"), 0.9, 1.6)
	_add("head", "box", Vector3(0.7, 0.3, 0.14), Vector3(0, 1.74, 0.62), visor)
	var stripe = mat(Color("eeeae0"), 0.5) if c.r==0 else c.stripe
	_add("head", "sphere", Vector3(0.646, 0, 0), Vector3(0, 1.8, 0.0), stripe, Vector3.ZERO, Vector3(0.14, 0.985, 1.025))
	for x in [-1, 1]: _add("head", "box", Vector3(0.06, 0.04, 0.03), Vector3(x*0.1, 1.42, 0.6), c.dark)
	if c.r>=2: _add("head", "box", Vector3(0.12, 0.08, 0.36), Vector3(0, 2.42, -0.2), c.main)
	if c.r>=3:
		for x in [-1, 1]:
			for k in 3: _add("head", "prism", Vector3(0.1, 0.24, 0.02), Vector3(x*0.63, 1.62+k*0.04, 0.1-k*0.14), c.trim, Vector3(-PI/2+0.4, x*PI/2, 0))
	if c.r==4: _add("head", "box", Vector3(0.05, 0.05, 0.7), Vector3(0, 2.0, -0.95), c.accent, Vector3(0.3, 0, 0))
	_sock = Vector3(0, 2.22, 0.6)

# --- Chest (chest bone; spine for the waist, hips for coat tails; the torso is
# about 0.8 wide and 0.75 deep, its front near z 0.38, the neck at y 1.25) ---------

func _chest_jerkin(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var lapel = mat(c.main_color.darkened(0.25), 0.6)
	for x in [-1, 1]:
		_add("chest", "box", Vector3(0.24, 0.2, 0.06), Vector3(x*0.19, 1.3, 0.27), c.main, Vector3(0.35, x*0.6, x*0.25))
		_add("chest", "box", Vector3(0.17, 0.42, 0.03), Vector3(x*0.17, 1.03, 0.4), lapel, Vector3(0, 0, x*0.22))
		for k in 3: _add("chest", "sphere", Vector3(0.032, 0, 0), Vector3(x*(0.24+k*0.06), 1.27, 0.02), c.metal)
	_add("chest", "box", Vector3(0.62, 0.18, 0.06), Vector3(0, 1.32, -0.3), c.main, Vector3(-0.3, 0, 0))
	_add("chest", "box", Vector3(0.035, 0.78, 0.02), Vector3(0.06, 0.86, 0.41), c.second, Vector3(0, 0, 0.05))
	_add("spine", "tube", Vector3(0.42, 0.09, 0), Vector3(0, 0.46, 0.0), lapel, Vector3.ZERO, Vector3(1, 1, 0.92))
	_add("chest", "box", Vector3(0.13, 0.13, 0.02), Vector3(-0.22, 0.95, 0.405), c.stripe)
	if c.r>=2:
		for x in [-1, 1]: _add("chest", "box", Vector3(0.02, 0.62, 0.02), Vector3(x*0.12, 0.9, 0.415), c.trim, Vector3(0, 0, x*0.18))
	if c.r>=3:
		for x in [-1, 1]: _add("chest", "box", Vector3(0.2, 0.08, 0.02), Vector3(x*0.19, 1.24, 0.3), c.trim, Vector3(0.35, x*0.6, x*0.25))
		for k in 4: _add("spine", "torus", Vector3(0.02, 0.035, 0), Vector3(0.3+k*0.02, 0.38-k*0.04, 0.32), c.metal, Vector3(PI/2, 0, k*0.8))
	if c.r==4:
		for x in [-0.1, 0.1]:
			for y in [0.92, 1.06]: _add("chest", "torus", Vector3(0.035, 0.06, 0), Vector3(x, y, -0.4), c.accent, Vector3(PI/2, 0, 0))
	_sock = Vector3(0.2, 1.12, 0.42)

func _chest_hauberk(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var mail = c.metal
	_add("chest", "cyl", Vector3(0.46, 0.56, 0), Vector3(0, 0.95, 0.0), mail, Vector3.ZERO, Vector3(1, 1, 0.88))
	_add("spine", "tube", Vector3(0.45, 0.2, 0), Vector3(0, 0.6, 0.0), mail, Vector3.ZERO, Vector3(1, 1, 0.88))
	var tab = mat(c.metal.albedo_color.lightened(0.25), 0.25, 0.9) if c.r<2 else c.trim
	if c.r==4: tab = c.accent
	for row in 4:
		for col in 5: _add("chest", "box", Vector3(0.07, 0.035, 0.015), Vector3(-0.24+col*0.12+(row%2)*0.06, 0.78+row*0.11, 0.41), tab)
	_add("chest", "sphere", Vector3(0.32, 0, 0), Vector3(0, 1.3, -0.33), c.main, Vector3.ZERO, Vector3(1.4, 0.55, 0.8))
	_add("chest", "box", Vector3(0.6, 0.05, 0.02), Vector3(0, 0.72, 0.41), c.stripe)
	if c.r>=2: _add("chest", "torus", Vector3(0.24, 0.3, 0), Vector3(0, 1.25, 0.08), c.metal, Vector3(0.15, 0, 0))
	if c.r>=3:
		_add("upperarm", "cyl", Vector3(0.17, 0.16, 0), Vector3(0.3, 1.12, 0), mail, Vector3(0, 0, PI/2))
		_add("chest", "sphere", Vector3(0.34, 0, 0), Vector3(0, 1.36, -0.36), c.trim, Vector3.ZERO, Vector3(1.4, 0.3, 0.6))
	_sock = Vector3(0, 1.08, 0.42)

func _chest_cuirass(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	_add("chest", "sphere", Vector3(0.5, 0, 0), Vector3(0, 0.98, 0.22), c.metal, Vector3.ZERO, Vector3(0.96, 0.74, 0.38))
	_add("chest", "sphere", Vector3(0.5, 0, 0), Vector3(0, 0.98, -0.2), c.metal, Vector3.ZERO, Vector3(0.94, 0.72, 0.36))
	var stripe = c.second if c.r<2 else c.trim
	if c.r==1: stripe = c.stripe
	_add("chest", "box", Vector3(0.1, 0.42, 0.02), Vector3(-0.14, 0.98, 0.405), stripe)
	_add("chest", "box", Vector3(0.18, 0.035, 0.04), Vector3(0.2, 0.86, 0.42), c.dark)
	for x in [-1, 1]: _add("chest", "box", Vector3(0.06, 0.12, 0.46), Vector3(x*0.45, 0.94, 0.0), c.dark)
	for k in 2: _add("spine", "tube", Vector3(0.44+k*0.01, 0.1, 0), Vector3(0, 0.62-k*0.1, 0.0), c.metal, Vector3.ZERO, Vector3(1, 1, 0.9))
	if c.r>=2: _add("chest", "box", Vector3(0.1, 0.42, 0.02), Vector3(0.14, 0.98, 0.405), c.trim)
	if c.r>=3:
		_add("upperarm", "sphere", Vector3(0.2, 0, 0), Vector3(0.3, 1.2, 0), c.metal, Vector3.ZERO, Vector3(1, 0.7, 1.1))
		for x in [-1, 1]: _add("chest", "box", Vector3(0.02, 0.5, 0.03), Vector3(x*0.33, 0.96, 0.36), c.trim, Vector3(0, x*0.5, 0))
	if c.r==4: _add("chest", "prism", Vector3(0.14, 0.2, 0.06), Vector3(0, 1.18, 0.42), c.accent)
	_sock = Vector3(0, 1.06, 0.42)

func _chest_mantle(c) -> void:
	_tint = {"body":c.main_color.darkened(0.35), "arms":c.main_color}
	_add("chest", "cone", Vector3(0.64, 0.52, 0.3), Vector3(0, 1.04, 0.0), c.main, Vector3.ZERO, Vector3(1, 1, 0.9))
	var gold = mat(c.second_color, 0.35, 0.6)
	_add("chest", "torus", Vector3(0.6, 0.67, 0), Vector3(0, 0.79, 0.0), gold, Vector3.ZERO, Vector3(1, 1, 0.9))
	var tassel = gold if c.r<2 else c.trim
	for k in 12:
		var a = k*TAU/12
		_add("chest", "cyl", Vector3(0.02, 0.14, 0), Vector3(sin(a)*0.64, 0.7, cos(a)*0.58), tassel)
	_add("chest", "sphere", Vector3(0.06, 0, 0), Vector3(0, 1.22, 0.34), gold)
	_add("spine", "tube", Vector3(0.43, 0.1, 0), Vector3(0, 0.5, 0.0), mat(c.main_color.darkened(0.4)), Vector3.ZERO, Vector3(1, 1, 0.92))
	_add("chest", "box", Vector3(0.14, 0.04, 0.02), Vector3(0.0, 1.0, 0.56), c.stripe, Vector3(-0.55, 0, 0))
	if c.r>=2: _add("chest", "sphere", Vector3(0.05, 0, 0), Vector3(0, 1.22, 0.4), c.trim)
	if c.r>=3:
		_add("chest", "torus", Vector3(0.62, 0.66, 0), Vector3(0, 0.76, 0.0), c.trim, Vector3.ZERO, Vector3(1, 1, 0.9))
		_add("upperarm", "sphere", Vector3(0.18, 0, 0), Vector3(0.28, 1.24, 0), gold, Vector3.ZERO, Vector3(1, 0.5, 1))
	if c.r==4:
		for k in 6: _add("chest", "box", Vector3(0.012, 0.36, 0.012), Vector3(sin(k*1.05)*0.5, 0.98, cos(k*1.05)*0.46), c.accent, Vector3(0, k*1.05, 0.5))
	_sock = Vector3(0, 1.14, 0.36)

func _chest_denim(c) -> void:
	var denim = c.main_color if c.r<4 else Color("f2f0ea")
	_tint = {"body":denim, "arms":SKIN}
	var vest = c.main if c.r<4 else mat(denim, 0.6)
	_add("chest", "box", Vector3(0.24, 0.74, 0.02), Vector3(0, 0.86, 0.405), c.dark)
	for x in [-1, 1]:
		_add("chest", "box", Vector3(0.22, 0.2, 0.06), Vector3(x*0.2, 1.3, 0.26), vest, Vector3(0.35, x*0.6, x*0.25))
		_add("upperarm", "torus", Vector3(0.14, 0.2, 0), Vector3(0.27, 1.11, 0), vest, Vector3(0, 0, PI/2))
		var stud = c.second if c.r<2 else c.trim
		if c.r==4: stud = mat(Color("ffcf6a"), 0.25, 0.9)
		for k in 5: _add("chest", "sphere", Vector3(0.028, 0, 0), Vector3(x*(0.13+k*0.025), 1.2-k*0.07, 0.41), stud)
	_add("spine", "tube", Vector3(0.42, 0.07, 0), Vector3(0, 0.46, 0.0), vest, Vector3.ZERO, Vector3(1, 1, 0.92))
	var patch = mat(Color("e8e4dc"), 0.7) if c.r<4 else c.accent
	_add("chest", "sphere", Vector3(0.12, 0, 0), Vector3(0, 1.0, -0.39), patch, Vector3.ZERO, Vector3(1, 1.1, 0.2))
	for x in [-1, 1]: _add("chest", "sphere", Vector3(0.03, 0, 0), Vector3(x*0.045, 1.02, -0.41), c.dark)
	_add("chest", "box", Vector3(0.12, 0.1, 0.02), Vector3(-0.22, 0.95, 0.4), c.stripe)
	if c.r>=2:
		for k in 4: _add("spine", "torus", Vector3(0.018, 0.03, 0), Vector3(0.36-k*0.03, 0.4-k*0.03, 0.26), c.metal, Vector3(PI/2, 0, k*0.9))
	if c.r>=3:
		for k in 3: _add("upperarm", "cone", Vector3(0.035, 0.1, 0.0), Vector3(0.26+k*0.06, 1.3, 0), c.trim)
	_sock = Vector3(0.22, 1.1, 0.42)

func _chest_track(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var panel = c.second if c.r<4 else c.accent
	_add("chest", "cyl", Vector3(0.41, 0.2, 0), Vector3(0, 1.16, 0.0), panel, Vector3.ZERO, Vector3(1, 1, 0.9))
	var stripe = mat(Color("f4f4f0"), 0.6) if c.r==0 else c.stripe
	_add("chest", "tube", Vector3(0.415, 0.035, 0), Vector3(0, 1.05, 0.0), stripe, Vector3.ZERO, Vector3(1, 1, 0.9))
	_add("chest", "tube", Vector3(0.28, 0.12, 0), Vector3(0, 1.3, 0.0), panel)
	_add("chest", "box", Vector3(0.025, 0.68, 0.02), Vector3(0, 0.88, 0.405), c.metal)
	for z in [-0.04, 0.04]:
		_add("upperarm", "box", Vector3(0.26, 0.02, 0.025), Vector3(0.34, 1.255, z), stripe)
		_add("lowerarm", "box", Vector3(0.26, 0.02, 0.025), Vector3(0.58, 1.245, z), stripe)
	_add("lowerarm", "tube", Vector3(0.15, 0.06, 0), Vector3(0.69, 1.107, 0), panel, Vector3(0, 0, PI/2))
	_add("spine", "tube", Vector3(0.42, 0.08, 0), Vector3(0, 0.46, 0.0), panel, Vector3.ZERO, Vector3(1, 1, 0.92))
	if c.r>=2: _add("chest", "box", Vector3(0.14, 0.1, 0.02), Vector3(0.2, 0.98, 0.405), c.trim)
	if c.r>=3: _add("chest", "torus", Vector3(0.3, 0.33, 0), Vector3(0, 1.37, 0.0), c.trim)
	_sock = Vector3(-0.2, 0.98, 0.42)

func _chest_varsity(c) -> void:
	var sleeves = c.second_color if c.r<4 else Color("ffcf6a")
	_tint = {"body":c.main_color, "arms":sleeves}
	var white = mat(Color("efe8dc"), 0.7)
	var letter = c.main if c.r<2 else c.trim
	if c.r==4: letter = c.accent
	_add("chest", "box", Vector3(0.22, 0.26, 0.02), Vector3(-0.19, 1.0, 0.405), white)
	for y in [0.92, 1.0, 1.08]: _add("chest", "box", Vector3(0.12, 0.035, 0.01), Vector3(-0.19, y, 0.418), letter)
	_add("chest", "box", Vector3(0.035, 0.08, 0.01), Vector3(-0.23, 1.04, 0.418), letter)
	_add("chest", "box", Vector3(0.035, 0.08, 0.01), Vector3(-0.15, 0.96, 0.418), letter)
	for k in 5: _add("chest", "sphere", Vector3(0.022, 0, 0), Vector3(0.05, 0.62+k*0.14, 0.41), white)
	for k in 2:
		_add("spine", "tube", Vector3(0.425, 0.045, 0), Vector3(0, 0.44+k*0.05, 0.0), white if k==0 else c.main, Vector3.ZERO, Vector3(1, 1, 0.92))
		_add("lowerarm", "tube", Vector3(0.152, 0.035, 0), Vector3(0.66+k*0.04, 1.107, 0), c.main if k==0 else white, Vector3(0, 0, PI/2))
	_add("chest", "tube", Vector3(0.29, 0.1, 0), Vector3(0, 1.3, 0.0), c.main)
	_add("chest", "box", Vector3(0.6, 0.06, 0.02), Vector3(0, 1.18, -0.39), c.stripe)
	if c.r>=2: _add("chest", "prism", Vector3(0.12, 0.12, 0.02), Vector3(0.2, 1.06, 0.41), white)
	if c.r>=3: _add("chest", "box", Vector3(0.36, 0.1, 0.02), Vector3(0, 1.02, -0.39), c.trim)
	_sock = Vector3(0.2, 0.92, 0.42)

func _chest_duster(c) -> void:
	var coat = c.main_color if c.r<4 else Color("f2eee6")
	_tint = {"body":coat, "arms":coat}
	var cloth = c.main if c.r<4 else mat(coat, 0.65)
	var lining = c.second if c.r<2 else c.trim
	_add("chest", "cone", Vector3(0.6, 0.3, 0.3), Vector3(0, 1.16, 0.0), mat(coat.darkened(0.12), 0.75), Vector3.ZERO, Vector3(1, 1, 0.92))
	_coat_tails(c, cloth, lining, 0.34, 0.54)
	for x in [-1, 1]: _add("chest", "box", Vector3(0.22, 0.22, 0.06), Vector3(x*0.2, 1.31, 0.26), cloth, Vector3(0.35, x*0.6, x*0.25))
	var button = c.metal if c.r<4 else mat(Color("ffcf6a"), 0.25, 0.9)
	for k in 4: _add("chest", "sphere", Vector3(0.028, 0, 0), Vector3(0.08, 0.72+k*0.13, 0.41), button)
	_add("hips", "box", Vector3(0.2, 0.04, 0.02), Vector3(-0.3, 0.3, 0.44), c.stripe, Vector3(0.2, -0.6, 0))
	if c.r>=2: _add("chest", "box", Vector3(0.02, 0.24, 0.01), Vector3(-0.2, 1.0, 0.41), c.trim)
	if c.r>=3: _add("hips", "torus", Vector3(0.53, 0.56, 0), Vector3(0, 0.2, 0.0), c.trim, Vector3.ZERO, Vector3(1, 1, 0.92))
	if c.r==4: _add("hips", "torus", Vector3(0.54, 0.57, 0), Vector3(0, 0.19, 0.0), c.accent, Vector3.ZERO, Vector3(1, 1, 0.92))
	_sock = Vector3(-0.2, 1.1, 0.42)

## Long coat tails from the waist: a flared skirt split at the front, the
## split edged in the lining color. length is how far down they hang.
func _coat_tails(c, cloth: Material, lining: Material, length: float, flare: float) -> void:
	var top = 0.58
	_add("hips", "skirt", Vector3(flare, length, 0.44), Vector3(0, top-length/2, 0.0), cloth, Vector3.ZERO, Vector3(1, 1, 0.92))
	var slope = atan((flare-0.44)/length)
	for x in [-1, 1]: _add("hips", "box", Vector3(0.025, length, 0.02), Vector3(x*0.05, top-length/2, 0.42+(flare-0.44)*0.5), lining, Vector3(-slope, 0, 0))
	_add("hips", "box", Vector3(0.07, length*0.98, 0.02), Vector3(0, top-length/2, 0.415+(flare-0.44)*0.5), mat(Color("15121c"), 0.9), Vector3(-slope, 0, 0))

func _chest_riot(c) -> void:
	_tint = {"body":c.main_color, "arms":c.second_color}
	var plate = mat(c.main_color.lightened(0.12), 0.5, 0.2)
	if c.r==2: plate = mat(TRIM[2].darkened(0.3), 0.4, 0.3)
	elif c.r==4: plate = c.metal
	_add("chest", "box", Vector3(0.68, 0.48, 0.12), Vector3(0, 1.0, 0.39), plate)
	_add("chest", "box", Vector3(0.68, 0.52, 0.1), Vector3(0, 1.0, -0.37), plate)
	for x in [-1, 1]: _add("chest", "box", Vector3(0.1, 0.44, 0.52), Vector3(x*0.43, 0.94, 0.0), c.main)
	_add("upperarm", "box", Vector3(0.28, 0.07, 0.34), Vector3(0.31, 1.29, 0), c.main, Vector3(0, 0, -0.22))
	_add("chest", "box", Vector3(0.5, 0.08, 0.02), Vector3(0, 1.1, 0.46), mat(Color("e8e8e0"), 0.6))
	_add("chest", "box", Vector3(0.6, 0.035, 0.02), Vector3(0, 1.1, 0.47), mat(NEON_PINK.darkened(0.1), 0.5) if c.r<4 else c.accent, Vector3(0, 0, 0.3))
	_add("spine", "tube", Vector3(0.43, 0.14, 0), Vector3(0, 0.55, 0.0), c.main, Vector3.ZERO, Vector3(1, 1, 0.92))
	_add("chest", "box", Vector3(0.5, 0.04, 0.02), Vector3(0, 0.84, 0.46), c.stripe)
	if c.r>=2: _add("chest", "tube", Vector3(0.3, 0.12, 0), Vector3(0, 1.3, 0.0), c.main)
	if c.r>=3:
		for k in 3: _add("chest", "box", Vector3(0.06, 0.3, 0.02), Vector3(-0.2+k*0.2, 0.98, 0.46), c.trim, Vector3(0, 0, 0.5))
	if c.r==4: _add("chest", "prism", Vector3(0.14, 0.16, 0.04), Vector3(0.2, 1.2, 0.46), c.accent)
	_sock = Vector3(-0.2, 1.2, 0.46)

func _chest_robe(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var grid = glow(c.second_color, 1.2) if c.r<2 else c.trim
	if c.r==4: grid = mat(Color("1a1020"), 0.6)
	var robe = c.main
	# A skirt from the waist (y 0.56) to the shins (y 0.1), flaring from 0.44 to 0.56.
	_add("hips", "skirt", Vector3(0.56, 0.46, 0.44), Vector3(0, 0.33, 0.0), robe, Vector3.ZERO, Vector3(1, 1, 0.92))
	for y in [0.18, 0.33]:
		var radius = 0.56-(y-0.1)/0.46*0.12
		_add("hips", "torus", Vector3(radius-0.005, radius+0.015, 0), Vector3(0, y, 0.0), grid, Vector3.ZERO, Vector3(1, 1, 0.92))
	for k in 8:
		var a = k*TAU/8+0.39
		_add("hips", "box", Vector3(0.014, 0.46, 0.014), Vector3(sin(a)*0.505, 0.33, cos(a)*0.465), grid, Vector3(-cos(a)*0.25, 0, sin(a)*0.25))
	_add("lowerarm", "cone", Vector3(0.3, 0.32, 0.16), Vector3(0.6, 1.08, 0), robe, Vector3(0, 0, PI/2))
	var collar = mat(Color("ece4f4"), 0.6)
	for x in [-1, 1]: _add("chest", "box", Vector3(0.08, 0.6, 0.03), Vector3(x*0.1, 1.02, 0.405), collar, Vector3(0, 0, x*0.45))
	_add("spine", "tube", Vector3(0.43, 0.15, 0), Vector3(0, 0.62, 0.0), c.dark, Vector3.ZERO, Vector3(1, 1, 0.92))
	_add("spine", "box", Vector3(0.14, 0.05, 0.02), Vector3(0.22, 0.62, 0.4), c.stripe)
	if c.r>=2: _add("spine", "box", Vector3(0.18, 0.16, 0.06), Vector3(0, 0.62, -0.42), c.dark)
	if c.r>=3: _add("lowerarm", "torus", Vector3(0.29, 0.32, 0), Vector3(0.75, 1.08, 0), c.trim, Vector3(0, 0, PI/2))
	if c.r==4: _add("chest", "torus", Vector3(0.3, 0.34, 0), Vector3(0, 1.28, 0.0), c.accent)
	_sock = Vector3(0, 1.16, 0.42)

func _chest_oyoroi(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var tread = mat(c.main_color.lightened(0.08), 0.95)
	var ridge = mat(c.main_color.darkened(0.3), 0.95)
	var lace = c.second if c.r<2 else c.trim
	if c.r==4: lace = c.accent
	for row in 3:
		var y = 0.62+row*0.17
		_add("chest" if row>0 else "spine", "box", Vector3(0.8, 0.14, 0.07), Vector3(0, y, 0.41), tread)
		for k in 5: _add("chest" if row>0 else "spine", "box", Vector3(0.04, 0.12, 0.02), Vector3(-0.3+k*0.15, y, 0.45), ridge, Vector3(0, 0, 0.4))
		for x in [-1, 1]: _add("chest" if row>0 else "spine", "box", Vector3(0.07, 0.14, 0.62), Vector3(x*0.44, y, 0.0), tread)
	for x in [-0.25, 0.0, 0.25]: _add("chest", "cyl", Vector3(0.016, 0.5, 0), Vector3(x, 0.79, 0.455), lace)
	if c.r<4:
		_add("chest", "oct", Vector3(0.2, 0.03, 0), Vector3(0, 1.16, 0.43), mat(Color("c0262c"), 0.5), Vector3(PI/2, 0, 0))
		_add("chest", "oct", Vector3(0.16, 0.032, 0), Vector3(0, 1.16, 0.432), mat(Color("e8e4dc"), 0.6), Vector3(PI/2, 0, 0), Vector3(0.6, 1, 0.12))
	else:
		_add("chest", "cyl", Vector3(0.24, 0.04, 0), Vector3(0, 1.14, 0.44), c.metal, Vector3(PI/2, 0, 0))
		_add("chest", "cyl", Vector3(0.08, 0.06, 0), Vector3(0, 1.14, 0.46), c.accent, Vector3(PI/2, 0, 0))
	for k in 4:
		var a = k*TAU/4
		_add("hips", "box", Vector3(0.36, 0.3, 0.05), Vector3(sin(a)*0.46, 0.26, cos(a)*0.42), tread, Vector3(0.18, a, 0))
	_add("upperarm", "box", Vector3(0.3, 0.06, 0.36), Vector3(0.32, 1.28, 0), tread, Vector3(0, 0, -0.35))
	_add("upperarm", "box", Vector3(0.3, 0.02, 0.36), Vector3(0.32, 1.31, 0), c.stripe, Vector3(0, 0, -0.35), Vector3(0.9, 1, 0.2))
	if c.r>=2:
		for x in [-1, 1]: _add("chest", "cyl", Vector3(0.016, 0.5, 0), Vector3(x*0.45, 0.79, 0.25), lace)
	if c.r>=3:
		for k in 6: _add("chest", "sphere", Vector3(0.028, 0, 0), Vector3(-0.3+k*0.12, 1.0, 0.46), c.trim)
	_sock = Vector3(0, 1.32, 0.38)

func _chest_trench(c) -> void:
	_tint = {"body":c.main_color, "arms":c.main_color}
	var tube = glow(c.rarity_color, 1.6+c.r*0.3, c.r==4) if c.r<4 else c.accent
	var second = glow(Color("3ff0ff"), 2.4, true) if c.r==4 else tube
	_add("chest", "tube", Vector3(0.32, 0.26, 0), Vector3(0, 1.34, -0.02), c.main)
	_add("chest", "torus", Vector3(0.31, 0.34, 0), Vector3(0, 1.47, -0.02), tube)
	_coat_tails(c, c.main, tube, 0.42, 0.56)
	_add("hips", "torus", Vector3(0.55, 0.575, 0), Vector3(0, 0.16, 0.0), second, Vector3.ZERO, Vector3(1, 1, 0.92))
	for x in [-1, 1]:
		_add("chest", "cyl", Vector3(0.016, 0.62, 0), Vector3(x*0.1, 0.94, 0.41), tube)
		_add("lowerarm", "torus", Vector3(0.15, 0.17, 0), Vector3(0.7, 1.107, 0), tube, Vector3(0, 0, PI/2))
	_add("chest", "box", Vector3(0.12, 0.04, 0.02), Vector3(-0.24, 1.08, 0.41), c.stripe)
	if c.r>=2: _add("chest", "box", Vector3(0.14, 0.18, 0.04), Vector3(-0.24, 0.9, 0.42), c.metal)
	if c.r>=3: _add("chest", "box", Vector3(0.62, 0.04, 0.02), Vector3(0, 1.14, -0.4), tube)
	_sock = Vector3(0.24, 1.1, 0.42)

# --- Gloves (hand.l at x 0.79, fingers to x 0.97; forearm from x 0.45 on the lowerarm) ---

## The glove itself: a rounded mitt over the hand, size across its box.
func _mitt(size: Vector3, pos: Vector3, m: Material) -> void:
	_add("hand", "sphere", Vector3(0.5, 0, 0), pos, m, Vector3.ZERO, size*1.12)

func _gloves_gloves(c) -> void:
	_mitt(Vector3(0.22, 0.27, 0.3), Vector3(0.875, 1.1, 0.0), c.main)
	_add("hand", "box", Vector3(0.1, 0.1, 0.1), Vector3(0.83, 1.08, 0.18), c.main)
	_add("lowerarm", "tube", Vector3(0.165, 0.1, 0), Vector3(0.72, 1.107, 0), c.second, Vector3(0, 0, PI/2))
	_add("lowerarm", "tube", Vector3(0.168, 0.03, 0), Vector3(0.72, 1.107, 0), c.stripe, Vector3(0, 0, PI/2))
	if c.r>=2: _add("hand", "box", Vector3(0.16, 0.012, 0.02), Vector3(0.875, 1.24, 0.0), c.trim)
	if c.r>=3: _add("hand", "box", Vector3(0.03, 0.02, 0.28), Vector3(0.95, 1.24, 0.0), c.trim)
	if c.r==4:
		for k in 4: _add("hand", "sphere", Vector3(0.025, 0, 0), Vector3(0.96, 1.25, -0.1+k*0.067), c.accent)

func _gloves_gauntlets(c) -> void:
	_mitt(Vector3(0.24, 0.29, 0.32), Vector3(0.875, 1.1, 0.0), c.metal)
	var plate = mat(c.metal.albedo_color.lightened(0.2), 0.25, 0.9) if c.r<4 else c.accent
	for k in 3: _add("hand", "box", Vector3(0.07, 0.04, 0.32), Vector3(0.8+k*0.075, 1.26, 0.0), plate)
	_add("lowerarm", "cone", Vector3(0.22, 0.22, 0.15), Vector3(0.64, 1.107, 0), c.metal, Vector3(0, 0, -PI/2))
	var band = c.dark if c.r<2 else c.trim
	if c.r==1: band = c.stripe
	_add("lowerarm", "torus", Vector3(0.18, 0.21, 0), Vector3(0.6, 1.107, 0), band, Vector3(0, 0, PI/2))
	if c.r>=2: _add("hand", "box", Vector3(0.12, 0.04, 0.12), Vector3(0.82, 1.1, 0.19), c.metal)
	if c.r>=3:
		for k in 3: _add("hand", "cone", Vector3(0.035, 0.1, 0.0), Vector3(0.95, 1.3, -0.1+k*0.1), c.trim)

func _gloves_driving(c) -> void:
	_mitt(Vector3(0.15, 0.26, 0.29), Vector3(0.84, 1.1, 0.0), c.main)
	for z in [-0.06, 0.06]: _add("hand", "sphere", Vector3(0.028, 0, 0), Vector3(0.85, 1.235, z), mat(SKIN, 0.7), Vector3.ZERO, Vector3(1, 0.3, 1))
	var band = c.second if c.r!=1 else c.stripe
	if c.r==4: band = c.accent
	_add("lowerarm", "tube", Vector3(0.158, 0.06, 0), Vector3(0.74, 1.107, 0), band, Vector3(0, 0, PI/2))
	if c.r>=2: _add("lowerarm", "sphere", Vector3(0.03, 0, 0), Vector3(0.74, 1.27, 0), c.trim)
	if c.r>=3: _add("hand", "box", Vector3(0.12, 0.012, 0.2), Vector3(0.84, 1.238, 0.0), glass(TRIM[3], 0.6, 1.2))
	if c.r==4: _add("hand", "box", Vector3(0.02, 0.02, 0.26), Vector3(0.92, 1.24, 0.0), c.metal)

func _gloves_wraps(c) -> void:
	var tape = c.main if c.r<2 else mat(TRIM[c.r].lerp(Color.WHITE, 0.25), 0.8)
	if c.r==4: tape = mat(Color("ffcf6a"), 0.5, 0.4)
	_mitt(Vector3(0.2, 0.26, 0.29), Vector3(0.87, 1.1, 0.0), tape)
	for x in [0.73, 0.79, 0.86, 0.93]: _add("hand" if x>0.76 else "lowerarm", "tube", Vector3(0.155, 0.04, 0), Vector3(x, 1.107, 0), mat(tape.albedo_color.darkened(0.12), 0.85), Vector3(0, 0, PI/2))
	_add("hand", "box", Vector3(0.025, 0.28, 0.01), Vector3(0.87, 1.1, 0.15), mat(tape.albedo_color.darkened(0.15), 0.85), Vector3(0.5, 0, 0))
	_add("lowerarm", "tube", Vector3(0.157, 0.02, 0), Vector3(0.67, 1.107, 0), c.stripe, Vector3(0, 0, PI/2))
	if c.r>=2: _add("hand", "box", Vector3(0.18, 0.03, 0.03), Vector3(0.88, 1.24, 0.08), tape)
	if c.r>=3:
		for k in 3: _add("hand", "sphere", Vector3(0.015, 0, 0), Vector3(0.95, 1.24, -0.08+k*0.08), c.trim)
	if c.r==4:
		for k in 2: _add("hand", "box", Vector3(0.08, 0.01, 0.015), Vector3(0.84+k*0.06, 1.245, -0.06), c.accent, Vector3(0, k*0.8, 0))

func _gloves_wired(c) -> void:
	_mitt(Vector3(0.2, 0.26, 0.29), Vector3(0.87, 1.1, 0.0), c.main)
	var led = glow(c.rarity_color if c.r>0 else Color("3ff0ff"), 2.2, c.r==4)
	for k in 4: _add("hand", "sphere", Vector3(0.024, 0, 0), Vector3(0.97, 1.2, -0.105+k*0.07), led)
	var cable = c.dark if c.r<4 else c.accent
	for z in [-0.05, 0.05]: _add("lowerarm", "cyl", Vector3(0.014, 0.34, 0), Vector3(0.6, 1.24, z), cable, Vector3(0, 0, PI/2))
	_add("lowerarm", "box", Vector3(0.1, 0.06, 0.14), Vector3(0.52, 1.24, 0), c.metal)
	_add("lowerarm", "box", Vector3(0.06, 0.012, 0.1), Vector3(0.52, 1.272, 0), c.stripe)
	if c.r>=2: _add("hand", "box", Vector3(0.1, 0.02, 0.1), Vector3(0.84, 1.24, 0), c.metal)
	if c.r>=3: _add("lowerarm", "sphere", Vector3(0.03, 0, 0), Vector3(0.52, 1.3, 0), led)

func _gloves_motocross(c) -> void:
	_mitt(Vector3(0.26, 0.32, 0.34), Vector3(0.875, 1.1, 0.0), c.main)
	var guard = c.second if c.r<2 else c.trim
	if c.r==4: guard = c.metal
	_add("hand", "box", Vector3(0.12, 0.08, 0.3), Vector3(0.93, 1.27, 0.0), guard)
	_add("hand", "box", Vector3(0.14, 0.03, 0.12), Vector3(0.82, 1.27, 0.0), guard)
	_add("lowerarm", "tube", Vector3(0.18, 0.12, 0), Vector3(0.73, 1.107, 0), c.second, Vector3(0, 0, PI/2))
	_add("lowerarm", "tube", Vector3(0.183, 0.03, 0), Vector3(0.73, 1.107, 0), c.stripe, Vector3(0, 0, PI/2))
	if c.r>=2: _add("hand", "box", Vector3(0.1, 0.12, 0.08), Vector3(0.83, 1.1, 0.2), guard)
	if c.r>=3: _add("lowerarm", "box", Vector3(0.14, 0.04, 0.16), Vector3(0.6, 1.25, 0), guard)
	if c.r==4: _add("hand", "box", Vector3(0.13, 0.01, 0.31), Vector3(0.93, 1.315, 0.0), c.accent)

func _gloves_insulated(c) -> void:
	var rubber = c.main if c.r!=2 else mat(TRIM[2].darkened(0.25), 0.4)
	_add("lowerarm", "cyl", Vector3(0.17, 0.32, 0), Vector3(0.6, 1.107, 0), rubber, Vector3(0, 0, PI/2))
	_mitt(Vector3(0.24, 0.3, 0.32), Vector3(0.875, 1.1, 0.0), rubber)
	_add("lowerarm", "torus", Vector3(0.17, 0.2, 0), Vector3(0.45, 1.107, 0), mat(rubber.albedo_color.darkened(0.25)), Vector3(0, 0, PI/2))
	_add("lowerarm", "box", Vector3(0.1, 0.012, 0.08), Vector3(0.6, 1.278, 0), c.stripe)
	if c.r>=2: _add("hand", "box", Vector3(0.1, 0.1, 0.1), Vector3(0.83, 1.1, 0.2), rubber)
	if c.r>=3: _add("lowerarm", "prism", Vector3(0.14, 0.1, 0.02), Vector3(0.6, 1.2, 0.17), c.trim, Vector3(0, 0, PI/2))
	if c.r==4:
		for k in 3: _add("hand", "box", Vector3(0.012, 0.012, 0.18), Vector3(0.82+k*0.05, 1.27, 0.0), c.accent, Vector3(0, 0.6*(k-1), 0))

func _gloves_welding(c) -> void:
	_mitt(Vector3(0.28, 0.36, 0.36), Vector3(0.88, 1.1, 0.0), c.main)
	_add("lowerarm", "cone", Vector3(0.25, 0.3, 0.19), Vector3(0.62, 1.107, 0), c.second if c.r!=2 else c.trim, Vector3(0, 0, -PI/2))
	var scorch = mat(Color("2a1e14"), 0.95) if c.r<3 else c.trim
	if c.r==4: scorch = glow(Color("ff7a2a"), 2.6, true)
	for k in 3: _add("hand", "box", Vector3(0.05, 0.012, 0.06), Vector3(0.88+k*0.03, 1.285, -0.1+k*0.09), scorch, Vector3(0, k, 0))
	_add("lowerarm", "tube", Vector3(0.235, 0.05, 0), Vector3(0.7, 1.107, 0), c.stripe, Vector3(0, 0, PI/2))
	if c.r>=2: _add("hand", "box", Vector3(0.12, 0.12, 0.1), Vector3(0.84, 1.1, 0.22), c.main)
	if c.r>=3: _add("lowerarm", "torus", Vector3(0.23, 0.26, 0), Vector3(0.5, 1.107, 0), c.metal, Vector3(0, 0, PI/2))

func _gloves_kote(c) -> void:
	_add("lowerarm", "cyl", Vector3(0.162, 0.32, 0), Vector3(0.6, 1.107, 0), c.main, Vector3(0, 0, PI/2))
	_mitt(Vector3(0.2, 0.26, 0.29), Vector3(0.87, 1.1, 0.0), c.main)
	var plate = c.metal if c.r<2 else mat(TRIM[2].darkened(0.2), 0.3, 0.6)
	if c.r==3: plate = mat(Color("17141f"), 0.25, 0.6)
	for row in 3:
		for col in 2: _add("lowerarm", "box", Vector3(0.08, 0.025, 0.1), Vector3(0.49+row*0.1, 1.27, -0.06+col*0.12), plate)
	_add("hand", "box", Vector3(0.16, 0.03, 0.22), Vector3(0.86, 1.24, 0.0), plate)
	var lace = mat(Color("c0262c"), 0.7) if c.r<3 else c.trim
	if c.r==4: lace = c.accent
	_add("lowerarm", "box", Vector3(0.3, 0.012, 0.012), Vector3(0.59, 1.282, 0.0), lace)
	_add("lowerarm", "tube", Vector3(0.165, 0.03, 0), Vector3(0.75, 1.107, 0), c.stripe, Vector3(0, 0, PI/2))
	if c.r>=2: _add("upperarm", "box", Vector3(0.12, 0.025, 0.14), Vector3(0.4, 1.27, 0), plate)
	if c.r>=3: _add("hand", "box", Vector3(0.012, 0.012, 0.2), Vector3(0.86, 1.258, 0.0), c.trim)

# --- Boots (foot.l at x 0.17; the sole is at y 0, toes reach z 0.3, the heel z -0.13) ---

func _boot_base(c, shoe: Material, sole: Material, height: float = 0.16) -> void:
	_add("foot", "box", Vector3(0.27, height, 0.44), Vector3(0.171, 0.035+height/2, 0.08), shoe)
	_add("foot", "box", Vector3(0.28, 0.04, 0.46), Vector3(0.171, 0.02, 0.08), sole)

func _boots_boots(c) -> void:
	_boot_base(c, c.main, c.second if c.r<3 else c.trim)
	_add("lowerleg", "cyl", Vector3(0.145, 0.16, 0), Vector3(0.171, 0.25, 0.0), c.main)
	_add("lowerleg", "tube", Vector3(0.147, 0.03, 0), Vector3(0.171, 0.32, 0.0), c.stripe)
	if c.r>=2:
		for k in 3: _add("foot", "box", Vector3(0.13, 0.015, 0.02), Vector3(0.171, 0.205, 0.1+k*0.06), c.trim)
	if c.r>=3: _add("foot", "box", Vector3(0.04, 0.06, 0.08), Vector3(0.171, 0.13, -0.16), c.metal)
	if c.r==4: _add("foot", "box", Vector3(0.29, 0.02, 0.47), Vector3(0.171, 0.005, 0.08), c.accent)

func _boots_greaves(c) -> void:
	_boot_base(c, c.main, c.dark)
	_add("lowerleg", "cyl", Vector3(0.14, 0.14, 0), Vector3(0.171, 0.24, 0.0), c.main)
	_add("lowerleg", "box", Vector3(0.24, 0.26, 0.07), Vector3(0.171, 0.26, 0.13), c.metal, Vector3(-0.1, 0, 0))
	var reflector = c.second if c.r<2 else c.trim
	if c.r==1: reflector = c.stripe
	if c.r==4: reflector = c.accent
	for k in 2:
		_add("lowerleg", "box", Vector3(0.18, 0.035, 0.02), Vector3(0.171, 0.22+k*0.08, 0.17), reflector if k==0 else mat(Color("eeeae0"), 0.4), Vector3(-0.1, 0, 0))
	if c.r>=2: _add("lowerleg", "sphere", Vector3(0.08, 0, 0), Vector3(0.171, 0.4, 0.14), c.metal)
	if c.r>=3: _add("foot", "box", Vector3(0.2, 0.05, 0.14), Vector3(0.171, 0.2, 0.2), c.metal)

func _boots_hightops(c) -> void:
	var white = c.main
	_add("foot", "box", Vector3(0.27, 0.15, 0.4), Vector3(0.171, 0.12, 0.05), white)
	_add("foot", "sphere", Vector3(0.14, 0, 0), Vector3(0.171, 0.1, 0.22), white, Vector3.ZERO, Vector3(0.98, 0.55, 0.75))
	_add("foot", "box", Vector3(0.3, 0.06, 0.48), Vector3(0.171, 0.03, 0.08), mat(Color("f8f6f0"), 0.7))
	_add("lowerleg", "cyl", Vector3(0.15, 0.2, 0), Vector3(0.171, 0.28, 0.0), white)
	var stripe = c.second if c.r==0 else c.stripe
	if c.r>=2: stripe = c.rarity_glow
	_add("foot", "box", Vector3(0.02, 0.07, 0.26), Vector3(0.31, 0.12, 0.05), stripe, Vector3(0.3, 0, 0))
	_add("foot", "box", Vector3(0.02, 0.07, 0.26), Vector3(0.03, 0.12, 0.05), stripe, Vector3(0.3, 0, 0))
	_add("lowerleg", "box", Vector3(0.11, 0.14, 0.04), Vector3(0.171, 0.33, 0.15), white, Vector3(-0.3, 0, 0))
	if c.r>=2: _add("lowerleg", "tube", Vector3(0.152, 0.03, 0), Vector3(0.171, 0.36, 0.0), stripe)
	if c.r>=3: _add("foot", "box", Vector3(0.1, 0.06, 0.04), Vector3(0.171, 0.16, -0.16), stripe)
	if c.r==4: _add("foot", "box", Vector3(0.31, 0.02, 0.49), Vector3(0.171, 0.01, 0.08), c.accent)

func _boots_tabi(c) -> void:
	_boot_base(c, c.main, c.dark, 0.14)
	_add("foot", "box", Vector3(0.02, 0.1, 0.12), Vector3(0.12, 0.1, 0.25), mat(Color("050508"), 0.9))
	var wrap = c.second if c.r<2 else mat(TRIM[c.r].lerp(Color.WHITE, 0.2), 0.7)
	if c.r==4: wrap = mat(Color("ffcf6a"), 0.4, 0.5)
	for k in 3: _add("lowerleg", "tube", Vector3(0.138, 0.04, 0), Vector3(0.171, 0.2+k*0.06, 0.0), wrap, Vector3(0.15*(k%2*2-1), 0, 0))
	_add("lowerleg", "cyl", Vector3(0.13, 0.18, 0), Vector3(0.171, 0.26, 0.0), c.main)
	_add("foot", "box", Vector3(0.02, 0.06, 0.2), Vector3(0.307, 0.1, 0.05), c.stripe)
	if c.r>=2: _add("lowerleg", "tube", Vector3(0.14, 0.03, 0), Vector3(0.171, 0.36, 0.0), wrap)
	if c.r>=3: _add("foot", "box", Vector3(0.1, 0.02, 0.06), Vector3(0.171, 0.18, 0.1), c.trim)
	if c.r==4: _add("foot", "sphere", Vector3(0.05, 0, 0), Vector3(0.12, 0.1, 0.3), c.accent)

func _boots_cowboyboots(c) -> void:
	var leather = c.main if c.r<4 else mat(Color("f2eee6"), 0.6)
	_add("foot", "box", Vector3(0.26, 0.15, 0.36), Vector3(0.171, 0.11, 0.04), leather)
	_add("foot", "cone", Vector3(0.13, 0.16, 0.025), Vector3(0.171, 0.09, 0.3), leather, Vector3(PI/2, 0, 0), Vector3(1, 1, 0.6))
	_add("foot", "box", Vector3(0.18, 0.08, 0.12), Vector3(0.171, 0.04, -0.09), c.dark)
	_add("lowerleg", "cyl", Vector3(0.155, 0.24, 0), Vector3(0.171, 0.28, 0.0), leather)
	var stitch = c.second if c.r<2 else c.trim
	if c.r==1: stitch = c.stripe
	for x in [-0.05, 0.05]: _add("lowerleg", "box", Vector3(0.015, 0.18, 0.01), Vector3(0.171+x, 0.29, 0.155), stitch, Vector3(0, 0, x*4))
	var spur = c.metal if c.r<4 else mat(Color("ffcf6a"), 0.25, 0.9)
	_add("foot", "cyl", Vector3(0.012, 0.12, 0), Vector3(0.171, 0.07, -0.18), spur, Vector3(PI/2, 0, 0))
	_add("foot", "cyl", Vector3(0.04, 0.012, 0), Vector3(0.171, 0.07, -0.24), spur, Vector3(0, 0, PI/2))
	if c.r>=2: _add("lowerleg", "tube", Vector3(0.157, 0.03, 0), Vector3(0.171, 0.38, 0.0), stitch)
	if c.r>=3:
		for k in 2: _add("lowerleg", "prism", Vector3(0.08, 0.12, 0.02), Vector3(0.12+k*0.1, 0.2, 0.15), c.trim)
	if c.r==4: _add("foot", "sphere", Vector3(0.03, 0, 0), Vector3(0.171, 0.07, -0.25), c.accent)

func _boots_moon(c) -> void:
	_add("foot", "sphere", Vector3(0.21, 0, 0), Vector3(0.171, 0.12, 0.07), c.main, Vector3.ZERO, Vector3(0.82, 0.6, 1.3))
	_add("lowerleg", "cyl", Vector3(0.185, 0.24, 0), Vector3(0.171, 0.28, 0.0), c.main)
	_add("lowerleg", "torus", Vector3(0.17, 0.21, 0), Vector3(0.171, 0.4, 0.0), c.main)
	_add("foot", "box", Vector3(0.32, 0.06, 0.5), Vector3(0.171, 0.03, 0.08), c.second if c.r<3 else c.trim)
	_add("lowerleg", "box", Vector3(0.02, 0.1, 0.16), Vector3(0.36, 0.28, 0.0), c.stripe)
	if c.r>=2:
		for x in [0.0, 0.342]: _add("lowerleg", "box", Vector3(0.02, 0.16, 0.12), Vector3(x, 0.28, 0.0), c.trim)
	if c.r>=3: _add("foot", "box", Vector3(0.18, 0.04, 0.04), Vector3(0.171, 0.2, 0.2), c.trim)
	if c.r==4: _add("foot", "cyl", Vector3(0.2, 0.01, 0), Vector3(0.171, -0.02, 0.08), glass(NEON_PINK, 0.5, 2.0))

func _boots_worktoe(c) -> void:
	_boot_base(c, c.main, c.second)
	var cap = c.metal if c.r<3 else c.trim
	_add("foot", "sphere", Vector3(0.14, 0, 0), Vector3(0.171, 0.09, 0.22), cap, Vector3.ZERO, Vector3(1.02, 0.7, 0.75))
	_add("lowerleg", "cyl", Vector3(0.15, 0.22, 0), Vector3(0.171, 0.27, 0.0), c.main)
	var lace = mat(Color("2a1e14"), 0.9) if c.r<2 else c.trim
	for k in 4: _add("lowerleg", "box", Vector3(0.12, 0.015, 0.02), Vector3(0.171, 0.18+k*0.05, 0.15), lace)
	_add("lowerleg", "tube", Vector3(0.152, 0.04, 0), Vector3(0.171, 0.37, 0.0), c.stripe)
	if c.r>=2: _add("foot", "box", Vector3(0.06, 0.08, 0.06), Vector3(0.31, 0.12, -0.08), c.metal)
	if c.r>=3: _add("lowerleg", "box", Vector3(0.16, 0.1, 0.04), Vector3(0.171, 0.34, -0.15), c.metal)

func _boots_skates(c) -> void:
	_add("foot", "box", Vector3(0.26, 0.14, 0.4), Vector3(0.171, 0.15, 0.06), c.main)
	_add("lowerleg", "cyl", Vector3(0.15, 0.2, 0), Vector3(0.171, 0.3, 0.0), c.main)
	_add("foot", "box", Vector3(0.12, 0.03, 0.44), Vector3(0.171, 0.075, 0.06), c.metal)
	var wheel = c.second if c.r<2 else c.rarity_glow
	if c.r==1: wheel = mat(TRIM[1], 0.5)
	for z in [-0.08, 0.2]:
		for x in [-0.08, 0.08]: _add("foot", "cyl", Vector3(0.055, 0.06, 0), Vector3(0.171+x, 0.055, z), wheel, Vector3(0, 0, PI/2))
	_add("foot", "cyl", Vector3(0.04, 0.06, 0), Vector3(0.171, 0.05, 0.31), mat(Color("c0262c"), 0.6))
	for k in 3: _add("lowerleg", "box", Vector3(0.12, 0.015, 0.02), Vector3(0.171, 0.22+k*0.06, 0.15), c.stripe)
	if c.r>=2: _add("lowerleg", "tube", Vector3(0.152, 0.04, 0), Vector3(0.171, 0.39, 0.0), wheel)
	if c.r>=3: _add("foot", "box", Vector3(0.04, 0.08, 0.1), Vector3(0.171, 0.2, -0.15), c.trim)
	if c.r==4:
		for x in [-1, 1]: _add("foot", "box", Vector3(0.01, 0.01, 0.3), Vector3(0.171+x*0.12, 0.06, -0.3), glow(Color("3ff0ff") if x>0 else NEON_PINK, 2.5, true))

func _boots_motoboots(c) -> void:
	_boot_base(c, c.main, c.dark)
	_add("lowerleg", "cyl", Vector3(0.155, 0.26, 0), Vector3(0.171, 0.28, 0.0), c.main)
	var plate = c.second if c.r<3 else c.trim
	if c.r==4: plate = c.metal
	_add("lowerleg", "box", Vector3(0.2, 0.22, 0.06), Vector3(0.171, 0.28, 0.16), plate)
	var buckle = c.metal if c.r<2 else c.trim
	for k in 3: _add("lowerleg", "tube", Vector3(0.158, 0.02, 0), Vector3(0.171, 0.19+k*0.08, 0.0), buckle)
	_add("lowerleg", "box", Vector3(0.12, 0.03, 0.02), Vector3(0.171, 0.36, 0.195), c.stripe)
	if c.r>=2: _add("foot", "box", Vector3(0.22, 0.05, 0.1), Vector3(0.171, 0.2, 0.22), plate)
	if c.r>=3: _add("lowerleg", "box", Vector3(0.05, 0.2, 0.12), Vector3(0.33, 0.28, 0.0), plate)
	if c.r==4: _add("lowerleg", "box", Vector3(0.12, 0.08, 0.01), Vector3(0.171, 0.28, 0.195), c.accent)

func _boots_neonkicks(c) -> void:
	_add("foot", "box", Vector3(0.26, 0.13, 0.42), Vector3(0.171, 0.115, 0.07), c.main)
	_add("foot", "sphere", Vector3(0.13, 0, 0), Vector3(0.171, 0.1, 0.22), c.main, Vector3.ZERO, Vector3(1, 0.5, 0.8))
	var sole = glow(c.rarity_color if c.r>0 else c.second_color, 1.6+c.r*0.4, c.r==4)
	_add("foot", "box", Vector3(0.29, 0.05, 0.47), Vector3(0.171, 0.025, 0.08), sole)
	_add("lowerleg", "tube", Vector3(0.14, 0.06, 0), Vector3(0.171, 0.2, 0.0), c.main)
	_add("foot", "box", Vector3(0.02, 0.04, 0.2), Vector3(0.307, 0.12, 0.05), c.stripe, Vector3(0.3, 0, 0))
	if c.r>=2: _add("foot", "box", Vector3(0.1, 0.06, 0.04), Vector3(0.171, 0.14, -0.15), sole)
	if c.r>=3: _add("lowerleg", "tube", Vector3(0.142, 0.02, 0), Vector3(0.171, 0.23, 0.0), sole)
	if c.r==4: _add("foot", "box", Vector3(0.32, 0.005, 0.5), Vector3(0.171, 0.001, 0.08), glass(Color("3ff0ff"), 0.5, 2.0))

# --- Belts (hips bone; a ring round the waist at y 0.5, about 0.42 out) -------------

func _band(c, m: Material, height: float, radius: float = 0.425) -> void:
	_add("hips", "tube", Vector3(radius, height, 0), Vector3(0, 0.5, 0.0), m, Vector3.ZERO, Vector3(1, 1, 0.92))

func _belt_belt(c) -> void:
	_band(c, c.main, 0.09)
	var buckle = mat(c.second_color, 0.3, 0.8) if c.r<2 else c.trim
	if c.r<4:
		_add("hips", "box", Vector3(0.15, 0.12, 0.03), Vector3(0, 0.5, 0.405), buckle)
		_add("hips", "box", Vector3(0.09, 0.06, 0.035), Vector3(0, 0.5, 0.41), c.dark)
	else:
		_add("hips", "box", Vector3(0.24, 0.15, 0.04), Vector3(0, 0.5, 0.41), c.metal)
		for x in [-0.05, 0.05]: _add("hips", "cyl", Vector3(0.03, 0.02, 0), Vector3(x, 0.5, 0.435), c.accent, Vector3(PI/2, 0, 0))
	_add("hips", "box", Vector3(0.05, 0.1, 0.02), Vector3(0.3, 0.5, 0.3), c.stripe, Vector3(0, 0.8, 0))
	if c.r>=2: _add("hips", "box", Vector3(0.12, 0.14, 0.06), Vector3(-0.38, 0.45, 0.16), c.main, Vector3(0, -1.1, 0))
	if c.r>=3: _ring("hips", "sphere", Vector3(0.022, 0, 0), Vector3(0, 0.5, 0), Vector2(0.43, 0.4), -2.6, -0.4, 4, c.trim)

func _belt_sash(c) -> void:
	_band(c, c.main, 0.14)
	_add("hips", "sphere", Vector3(0.08, 0, 0), Vector3(0.32, 0.5, 0.27), c.main)
	var ends = c.main if c.r<2 else c.trim
	if c.r==1: ends = c.stripe
	_add("hips", "box", Vector3(0.08, 0.3, 0.03), Vector3(0.36, 0.34, 0.27), ends, Vector3(0, 0.8, 0.15))
	_add("hips", "box", Vector3(0.08, 0.26, 0.03), Vector3(0.3, 0.36, 0.32), ends, Vector3(0, 0.8, -0.12))
	var fringe = mat(c.second_color, 0.4, 0.6) if c.r<4 else mat(Color("ffcf6a"), 0.3, 0.9)
	for k in 3: _add("hips", "cyl", Vector3(0.01, 0.06, 0), Vector3(0.33+k*0.02, 0.17, 0.27), fringe)
	if c.r>=2: _add("hips", "box", Vector3(0.1, 0.1, 0.02), Vector3(0, 0.5, 0.41), fringe)
	if c.r>=3:
		for y in [0.43, 0.57]: _add("hips", "tube", Vector3(0.428, 0.012, 0), Vector3(0, y, 0.0), c.trim, Vector3.ZERO, Vector3(1, 1, 0.92))

func _belt_obi(c) -> void:
	_band(c, c.main, 0.2)
	var cord = mat(Color("e8e0d0"), 0.7) if c.r<2 else c.trim
	if c.r==4: cord = mat(Color("ffcf6a"), 0.3, 0.8)
	_add("hips", "tube", Vector3(0.43, 0.025, 0), Vector3(0, 0.52, 0.0), cord, Vector3.ZERO, Vector3(1, 1, 0.92))
	var stud = c.second if c.r<3 else c.trim
	_ring("hips", "sphere", Vector3(0.024, 0, 0), Vector3(0, 0.45, 0), Vector2(0.43, 0.4), -0.9, 0.9, 7, stud)
	_add("hips", "torus", Vector3(0.04, 0.065, 0), Vector3(-0.4, 0.42, 0.18), c.dark, Vector3(0, 0, PI/2))
	_add("hips", "box", Vector3(0.12, 0.04, 0.02), Vector3(-0.2, 0.57, 0.39), c.stripe, Vector3(0, -0.45, 0))
	if c.r>=2: _add("hips", "sphere", Vector3(0.06, 0, 0), Vector3(0.0, 0.52, -0.4), cord)
	if c.r>=3: _add("hips", "box", Vector3(0.06, 0.2, 0.03), Vector3(0.05, 0.4, -0.41), cord)
	if c.r==4: _add("hips", "sphere", Vector3(0.05, 0, 0), Vector3(0.0, 0.52, -0.46), c.accent)

func _belt_bandolier(c) -> void:
	_band(c, c.main, 0.1)
	var brass = c.second if c.r<4 else mat(Color("ffcf6a"), 0.25, 0.9)
	var tip = mat(Color("8a6a40"), 0.4, 0.7) if c.r<2 else c.trim
	if c.r==1: tip = c.stripe
	if c.r==4: tip = c.accent
	for k in 11:
		var a = lerpf(-1.25, 1.25, k/10.0)
		_add("hips", "cyl", Vector3(0.024, 0.09, 0), Vector3(sin(a)*0.445, 0.5, cos(a)*0.415), brass)
		_add("hips", "sphere", Vector3(0.023, 0, 0), Vector3(sin(a)*0.445, 0.548, cos(a)*0.415), tip)
	_add("hips", "box", Vector3(0.1, 0.24, 0.18), Vector3(-0.47, 0.36, 0.05), mat(c.main_color.darkened(0.3)))
	_add("hips", "box", Vector3(0.06, 0.1, 0.08), Vector3(-0.47, 0.5, 0.08), c.dark, Vector3(0.3, 0, 0))
	if c.r>=2: _add("hips", "box", Vector3(0.12, 0.1, 0.04), Vector3(0, 0.5, -0.4), brass)
	if c.r>=3: _add("hips", "box", Vector3(0.02, 0.16, 0.12), Vector3(-0.525, 0.38, 0.05), c.trim)

func _belt_fanny(c) -> void:
	_band(c, c.dark, 0.05)
	_add("hips", "sphere", Vector3(0.2, 0, 0), Vector3(0, 0.48, 0.42), c.main, Vector3.ZERO, Vector3(0.95, 0.45, 0.4))
	_add("hips", "box", Vector3(0.3, 0.05, 0.06), Vector3(0, 0.46, 0.49), c.second)
	var zip = c.metal if c.r<2 else c.trim
	if c.r==1: zip = c.stripe
	_add("hips", "box", Vector3(0.3, 0.012, 0.012), Vector3(0, 0.53, 0.49), zip, Vector3(0.4, 0, 0))
	_add("hips", "box", Vector3(0.08, 0.05, 0.03), Vector3(-0.32, 0.5, 0.27), c.dark, Vector3(0, -0.8, 0))
	if c.r>=2: _add("hips", "box", Vector3(0.02, 0.06, 0.02), Vector3(0.1, 0.5, 0.505), zip)
	if c.r>=3: _add("hips", "sphere", Vector3(0.09, 0, 0), Vector3(0.3, 0.46, 0.33), c.main, Vector3.ZERO, Vector3(1, 0.7, 0.6))
	if c.r==4:
		for k in 3: _add("hips", "cyl", Vector3(0.03, 0.01, 0), Vector3(-0.08+k*0.08, 0.36-k*0.03, 0.5), c.accent, Vector3(PI/2, 0, 0))

func _belt_toolbelt(c) -> void:
	_band(c, c.main, 0.1)
	var pouch = mat(c.main_color.darkened(0.2), 0.9)
	for x in [-1, 1]: _add("hips", "box", Vector3(0.15, 0.18, 0.1), Vector3(x*0.3, 0.42, 0.33), pouch, Vector3(0, x*0.7, 0))
	var tool = c.metal if c.r<2 else c.trim
	_add("hips", "cyl", Vector3(0.022, 0.26, 0), Vector3(0.45, 0.34, 0.1), mat(Color("8a5a30"), 0.8))
	_add("hips", "box", Vector3(0.05, 0.06, 0.16), Vector3(0.45, 0.47, 0.1), tool)
	_add("hips", "cyl", Vector3(0.012, 0.14, 0), Vector3(-0.45, 0.32, 0.1), tool)
	_add("hips", "cyl", Vector3(0.03, 0.08, 0), Vector3(-0.45, 0.43, 0.1), mat(Color("e0b020"), 0.6))
	_add("hips", "box", Vector3(0.1, 0.03, 0.02), Vector3(-0.3, 0.48, 0.39), c.stripe, Vector3(0, -0.7, 0))
	if c.r>=2: _add("hips", "box", Vector3(0.12, 0.14, 0.08), Vector3(0, 0.43, -0.42), pouch)
	if c.r>=3: _add("hips", "torus", Vector3(0.04, 0.06, 0), Vector3(0.2, 0.38, 0.4), tool, Vector3(PI/2, 0, 0))

func _belt_cassette(c) -> void:
	_band(c, c.main, 0.08)
	var label = glow(c.rarity_color, 0.8+c.r*0.4, c.r==4) if c.r>=2 else mat(c.rarity_color, 0.6)
	for k in 5:
		var a = lerpf(-1.15, 1.15, k/4.0)
		var at = Vector3(sin(a)*0.45, 0.5, cos(a)*0.42)
		_add("hips", "box", Vector3(0.17, 0.11, 0.03), at, c.second, Vector3(0, a, 0))
		_add("hips", "box", Vector3(0.12, 0.035, 0.01), at+Vector3(sin(a)*0.018, 0.025, cos(a)*0.018), label, Vector3(0, a, 0))
		_add("hips", "box", Vector3(0.1, 0.03, 0.01), at+Vector3(sin(a)*0.018, -0.02, cos(a)*0.018), c.dark, Vector3(0, a, 0))
	_add("hips", "box", Vector3(0.08, 0.16, 0.13), Vector3(0.47, 0.46, -0.1), c.metal)
	if c.r>=2: _add("hips", "cyl", Vector3(0.012, 0.16, 0), Vector3(0.47, 0.6, -0.1), c.dark)
	if c.r>=3: _add("hips", "box", Vector3(0.17, 0.11, 0.03), Vector3(0, 0.5, -0.41), c.second)

func _belt_lifting(c) -> void:
	_band(c, c.main, 0.2, 0.43)
	var buckle = c.metal if c.r<2 else c.trim
	if c.r==4: buckle = mat(Color("ffcf6a"), 0.25, 0.9)
	_add("hips", "box", Vector3(0.18, 0.16, 0.035), Vector3(0, 0.5, 0.405), buckle)
	_add("hips", "box", Vector3(0.12, 0.1, 0.04), Vector3(0, 0.5, 0.41), c.main)
	for y in [0.47, 0.53]: _add("hips", "box", Vector3(0.16, 0.012, 0.02), Vector3(0.0, y, 0.43), buckle)
	var logo = mat(Color("e8e4dc"), 0.6) if c.r<4 else c.accent
	_add("hips", "box", Vector3(0.24, 0.08, 0.02), Vector3(0, 0.5, -0.4), logo)
	_add("hips", "box", Vector3(0.08, 0.15, 0.02), Vector3(0.3, 0.5, 0.29), c.stripe, Vector3(0, 0.8, 0))
	if c.r>=2: _add("hips", "tube", Vector3(0.435, 0.02, 0), Vector3(0, 0.6, 0.0), c.trim, Vector3.ZERO, Vector3(1, 1, 0.92))
	if c.r>=3: _add("hips", "tube", Vector3(0.435, 0.02, 0), Vector3(0, 0.4, 0.0), c.trim, Vector3.ZERO, Vector3(1, 1, 0.92))

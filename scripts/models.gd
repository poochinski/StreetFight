extends RefCounted
## 3D models for the 3D view: the KayKit heroes and skeletons (CC0, see
## assets/models/CREDITS.txt) with their animations, KayKit city props, and
## props built from simple shapes where no model fits. world3d.gd places them;
## the pose_* functions pick the animation from the game state every frame.

const ROOT = "res://assets/models/"
const CombatAnimator=preload("res://scripts/combat_animator.gd")
## KayKit characters stand about 2.2 units tall; a grid cell is one unit and a
## shop door is 1.2 units high.
const HERO_SCALE = 0.46
## KayKit city bits are modelled small: a car is 0.94 long and fills two cells here.
const CITY_SCALE = 2.2

## Each class: model, the hand items to keep (all other weapons and shields in
## the model are hidden) and its animations.
const HEROES = {
	"samurai": {"model":"Knight", "keep":["2H_Sword"], "idle":"2H_Melee_Idle",
		"attacks":["2H_Melee_Attack_Slice", "2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin"],
		"shoot":"2H_Melee_Attack_Slice", "cast":"2H_Melee_Attack_Spin", "channel":"2H_Melee_Attack_Spinning"},
	"gunslinger": {"model":"Rogue_Hooded", "keep":["1H_Crossbow"], "idle":"1H_Ranged_Aiming",
		"attacks":["1H_Ranged_Shoot"], "shoot":"1H_Ranged_Shoot", "cast":"Throw", "channel":"1H_Ranged_Shooting"},
	"synth_mage": {"model":"Mage", "keep":["2H_Staff"], "idle":"Idle",
		"attacks":["Spellcast_Shoot"], "shoot":"Spellcast_Shoot", "cast":"Spellcast_Long", "channel":"Spellcasting"},
}
## Each enemy: model, weapons attached to the hands, size, attack animation and
## the moment (seconds into it) the blow lands, lined up with the wind-up.
const ENEMIES = {
	"imp": {"model":"Skeleton_Minion", "weapon":"Skeleton_Blade", "scale":0.42, "attack":"1H_Melee_Attack_Chop", "impact":0.45, "run":"Running_C"},
	"brute": {"model":"Skeleton_Warrior", "weapon":"Skeleton_Axe", "offhand":"Skeleton_Shield_Small_A", "scale":0.56, "attack":"2H_Melee_Attack_Chop", "impact":0.5, "run":"Walking_D_Skeletons"},
	"ranged": {"model":"Skeleton_Mage", "weapon":"Skeleton_Staff", "scale":0.44, "attack":"Spellcast_Shoot", "impact":0.45, "run":"Running_A"},
	"boss": {"model":"Skeleton_Warrior", "weapon":"Skeleton_Axe", "scale":0.95, "attack":"1H_Melee_Attack_Jump_Chop", "impact":0.9, "run":"Walking_D_Skeletons"},
}
const LOOPING = ["Idle", "Idle_B", "Idle_Combat", "2H_Melee_Idle", "1H_Ranged_Aiming", "Running_A", "Running_B", "Running_C",
	"Walking_A", "Walking_B", "Walking_C", "Walking_D_Skeletons", "2H_Melee_Attack_Spinning", "1H_Ranged_Shooting", "Spellcasting"]
const CARS = ["car_sedan", "car_taxi", "car_hatchback", "car_stationwagon", "car_police", "car_sedan"]
const SCREEN_COLORS = [Color("3ff0ff"), Color("ff4fd8"), Color("5dff8f"), Color("ffe45c"), Color("9b5cff")]

var scenes = {}
var materials = {}

func _scene(path: String) -> Node3D:
	if not scenes.has(path):
		scenes[path] = load(ROOT+path)
		var probe = scenes[path].instantiate()
		for player in probe.find_children("*", "AnimationPlayer", true, false):
			for name in LOOPING:
				if player.has_animation(name): player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		probe.free()
	return scenes[path].instantiate()

static func v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)

## Turns a node so its front (+z) faces a grid direction.
static func face(node: Node3D, dir: Vector2) -> void:
	if dir.length_squared()>0.0001: node.rotation.y = atan2(dir.x, dir.y)

# --- Characters ------------------------------------------------------------------

## An actor is a holder node at the character's feet; the model inside turns to
## face where the character looks. Meta: model, anim (AnimationPlayer), meshes,
## flash (overlay material for hit flashes), lock (clock time a one-shot
## animation holds until).
func _actor(path: String, scale: float) -> Node3D:
	var actor = Node3D.new()
	var model = _scene(path)
	model.scale = Vector3.ONE*scale
	actor.add_child(model)
	actor.set_meta("model", model)
	actor.set_meta("anim", model.find_children("*", "AnimationPlayer", true, false)[0])
	actor.get_meta("anim").callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var flash = StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.albedo_color = Color(1, 1, 1, 0)
	actor.set_meta("flash", flash)
	var meshes = model.find_children("*", "MeshInstance3D", true, false)
	for m in meshes: m.material_overlay = flash
	actor.set_meta("meshes", meshes)
	actor.set_meta("lock", 0.0)
	actor.set_meta("playing", "")
	return actor

func _play(actor: Node3D, name: String, blend: float = 0.12, speed: float = 1.0, restart: bool = false) -> void:
	var player: AnimationPlayer = actor.get_meta("anim")
	if not player.has_animation(name): return
	if actor.get_meta("playing")==name and not restart:
		player.speed_scale = speed
		return
	player.play(name, blend)
	player.speed_scale = speed
	if restart: player.seek(0.0, true)
	actor.set_meta("playing", name)

func _hold(actor: Node3D, g, name: String, seconds: float, speed: float = 1.0) -> void:
	_play(actor, name, 0.08, speed, true)
	actor.set_meta("lock", g.elapsed+seconds)

func _locked(actor: Node3D, g) -> bool:
	return g.elapsed<actor.get_meta("lock")

func hero(class_id: String) -> Node3D:
	var info = HEROES.get(class_id, HEROES.samurai)
	var actor = _actor("characters/%s.glb" % info.model, HERO_SCALE)
	for attachment in actor.find_children("*", "BoneAttachment3D", true, false):
		for item in attachment.get_children():
			var name = String(item.name)
			var hand_item = name.begins_with("1H_") or name.begins_with("2H_") or "Shield" in name or "Knife" in name \
				or name in ["Throwable", "Spellbook", "Spellbook_open", "Mug"]
			if hand_item: item.visible = false
	actor.set_meta("class", class_id)
	CombatAnimator.setup(actor)
	CombatAnimator.equip(actor,preload("res://scripts/items.gd").starter_weapon())
	return actor

## Starts the idle loop; call once the actor is in the scene tree.
func idle(actor: Node3D) -> void:
	actor.set_meta("playing", "")
	var info = HEROES.get(actor.get_meta("class", ""), {"idle":"Idle"})
	_play(actor, info.idle, 0.0)
	actor.get_meta("anim").seek(0.0, true)

func enemy(kind: String) -> Node3D:
	var info = ENEMIES.get(kind, ENEMIES.imp)
	var actor = _actor("characters/%s.glb" % info.model, info.scale)
	var skeleton: Skeleton3D = actor.find_children("*", "Skeleton3D", true, false)[0]
	for slot in [["weapon", "handslot.r"], ["offhand", "handslot.l"]]:
		if not info.has(slot[0]): continue
		var attach = BoneAttachment3D.new()
		attach.bone_name = slot[1]
		skeleton.add_child(attach)
		var item = _scene("weapons/%s.gltf" % info[slot[0]])
		attach.add_child(item)
		for m in item.find_children("*", "MeshInstance3D", true, false): m.material_overlay = actor.get_meta("flash")
	if kind=="boss":
		# The Warden: a giant with burning eyes and an ember glow.
		var glow = OmniLight3D.new()
		glow.light_color = Color(1.0, 0.35, 0.15)
		glow.light_energy = 2.0
		glow.omni_range = 3.5
		glow.position = Vector3(0, 1.6, 0.3)
		actor.add_child(glow)
		for m in actor.get_meta("meshes"):
			if "Eyes" in String(m.name): m.material_override = _glow_material(Color(1.0, 0.3, 0.1), 4.0)
	elif kind=="ranged":
		for m in actor.get_meta("meshes"):
			if "Eyes" in String(m.name): m.material_override = _glow_material(Color(0.6, 1.0, 0.4), 3.0)
	actor.set_meta("kind", kind)
	actor.set_meta("hit", 0.0)
	actor.set_meta("windup", 0.0)
	actor.set_meta("last", Vector2.ZERO)
	return actor

func pose_hero(actor: Node3D, g, dt: float) -> void:
	if actor.has_meta("combat_skeleton"):
		CombatAnimator.pose(actor,g,dt,self)
		return
	var p = g.player
	var info = HEROES.get(actor.get_meta("class"), HEROES.samurai)
	actor.position = v3(p.pos)
	var model: Node3D = actor.get_meta("model")
	var dir = Vector2.from_angle(g.display_angle)
	if not p.channel.is_empty() and p.channel.has("dir"): dir = p.channel.dir
	model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.y), 1.0-exp(-28*dt))
	var flash: StandardMaterial3D = actor.get_meta("flash")
	var hurt = g.clock-p.get("hurt_at", -9.0)
	flash.albedo_color = Color(1, 0.25, 0.2, maxf(0.0, 0.5-hurt*2.5))
	if g.state=="defeat":
		if actor.get_meta("playing")!="Death_A": _play(actor, "Death_A", 0.1)
		return
	# Actions, most important first. One-shot animations hold for a moment so
	# a quick tap still reads, but moving or a new action cuts them short.
	var cast_age = g.clock-p.get("cast_at", -9.0)
	if p.roll>0:
		if actor.get_meta("playing")!="Dodge_Forward": _hold(actor, g, "Dodge_Forward", g.DODGE_DURATION+0.05, 2.6)
		return
	if not p.channel.is_empty():
		match p.channel.kind:
			"dash": _play(actor, "Dodge_Forward", 0.05, 2.2)
			_: _play(actor, info.channel, 0.08, 1.6)
		actor.set_meta("lock", g.clock+0.1)
		return
	if cast_age<0.02 and actor.get_meta("cast_seen", -1.0)!=p.cast_at:
		actor.set_meta("cast_seen", p.cast_at)
		_hold(actor, g, info.cast, 0.55, 1.8)
		return
	if not g.swing.is_empty():
		var age: float = g.swing.age
		if age<actor.get_meta("swing_age", 99.0):
			var attacks: Array = info.attacks
			var name: String = attacks[clampi(int(g.swing.index), 0, attacks.size()-1)]
			_hold(actor, g, name, g.swing.duration*2.0+0.1, clampf(0.48/maxf(0.05, g.swing.duration), 1.4, 3.2))
		actor.set_meta("swing_age", age)
	else: actor.set_meta("swing_age", 99.0)
	var recoil = p.get("recoil", 0.0)
	if recoil>actor.get_meta("recoil", 0.0)+0.01: _hold(actor, g, info.shoot, 0.3, 2.4)
	actor.set_meta("recoil", recoil)
	var moving = g.walk_blend>0.25
	if _locked(actor, g) and not (moving and g.swing.is_empty() and recoil<=0): return
	if moving: _play(actor, "Running_A", 0.15, lerpf(0.8, 1.25, clampf(g.walk_blend, 0, 1)))
	else: _play(actor, info.idle, 0.2)

func pose_enemy(actor: Node3D, e: Dictionary, g, dt: float) -> void:
	var info = ENEMIES.get(e.kind, ENEMIES.imp)
	actor.visible = g.seen.has(Vector2i(e.pos))
	var model: Node3D = actor.get_meta("model")
	var last: Vector2 = actor.get_meta("last")
	var step = e.pos-last
	actor.position = v3(e.pos)
	actor.set_meta("last", e.pos)
	var dir = step if step.length_squared()>0.00001 else Vector2.ZERO
	if e.alert or e.windup>0: dir = g.player.pos-e.pos
	if e.windup>0 and e.aim!=Vector2.ZERO: dir = e.aim-e.pos if e.kind=="ranged" else dir
	if dir!=Vector2.ZERO: model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.y), 1.0-exp(-14*dt))
	var flash: StandardMaterial3D = actor.get_meta("flash")
	var hit_glow = clampf(e.hit/0.15, 0.0, 1.0)*0.55
	var tint: Color = actor.get_meta("tint", Color(1, 1, 1, 0))
	flash.albedo_color = Color(1, 0.9, 0.8, hit_glow) if hit_glow>tint.a else tint
	# Wind-up: start the attack so the blow lands when the wind-up ends.
	if e.windup>0 and actor.get_meta("windup")<=0:
		var total = maxf(0.1, e.windup_total)
		_hold(actor, g, info.attack, e.windup+0.45, clampf(info.impact/total, 0.4, 3.0))
	actor.set_meta("windup", e.windup)
	if e.hit>actor.get_meta("hit")+0.01 and e.windup<=0 and e.kind!="boss":
		_hold(actor, g, "Hit_A", 0.3, 1.6)
	actor.set_meta("hit", e.hit)
	if _locked(actor, g): return
	if e.get("moving", 0.0)>0.2: _play(actor, info.run, 0.15, 1.0 if e.kind!="imp" else 1.15)
	elif e.alert: _play(actor, "Idle_Combat", 0.2)
	else: _play(actor, "Idle", 0.2)

## Champions glow blue and rare leaders gold: a bigger body, a coloured
## sheen, a ring of light at their feet and a light that follows them.
func mark_elite(actor: Node3D, e: Dictionary, color: Color) -> void:
	var model: Node3D = actor.get_meta("model")
	model.scale *= e.get("size_mult", 1.0)
	actor.set_meta("tint", Color(color, 0.16 if e.has("elite") else 0.08))
	var ring = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	var radius = 0.42*e.get("size_mult", 1.0)
	disc.top_radius = radius; disc.bottom_radius = radius; disc.height = 0.01; disc.radial_segments = 24
	ring.mesh = disc
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color, 0.35 if e.has("elite") else 0.18)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.03, 0)
	actor.add_child(ring)
	if e.has("elite"):
		var light = OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.3
		light.omni_range = 2.4
		light.position = Vector3(0, 1.0, 0)
		actor.add_child(light)

## Plays the death fall, then sinks the body into the ground and removes it.
func die(actor: Node3D) -> void:
	if not is_instance_valid(actor): return
	actor.get_meta("anim").callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	actor.set_meta("lock", INF)
	_play(actor, "Death_A", 0.05, 1.3, true)
	var flash: StandardMaterial3D = actor.get_meta("flash")
	flash.albedo_color = Color(1, 0.6, 0.3, 0.5)
	var tween = actor.create_tween()
	tween.tween_property(flash, "albedo_color:a", 0.0, 0.3)
	tween.tween_interval(1.6)
	tween.tween_property(actor, "position:y", -0.8, 1.2)
	tween.tween_callback(actor.queue_free)

# --- Materials --------------------------------------------------------------------

func _material(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key = "%s/%s/%s" % [color.to_html(), rough, metal]
	if not materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		materials[key] = m
	return materials[key]

func _glow_material(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key = "glow/%s/%s" % [color.to_html(), energy]
	if not materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		materials[key] = m
	return materials[key]

func _beam_material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m

## Adds a shape to a prop. kind: box, cyl (radius in size.x, height in size.y),
## cone (top radius in size.z), sphere (radius in size.x).
func _part(parent: Node3D, kind: String, size: Vector3, at: Vector3, material: Material, shadows: bool = true) -> MeshInstance3D:
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new(); mesh.size = size
		"cyl":
			mesh = CylinderMesh.new(); mesh.top_radius = size.x; mesh.bottom_radius = size.x; mesh.height = size.y
			mesh.radial_segments = 14; mesh.rings = 1
		"cone":
			mesh = CylinderMesh.new(); mesh.top_radius = size.z; mesh.bottom_radius = size.x; mesh.height = size.y
			mesh.radial_segments = 14; mesh.rings = 1
		"sphere":
			mesh = SphereMesh.new(); mesh.radius = size.x; mesh.height = size.x*2
			mesh.radial_segments = 12; mesh.rings = 6
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _light(parent: Node3D, color: Color, energy: float, reach: float, at: Vector3, shadows: bool = false) -> OmniLight3D:
	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.position = at
	light.shadow_enabled = shadows
	parent.add_child(light)
	return light

func _kit(parent: Node3D, name: String, scale: float = CITY_SCALE) -> Node3D:
	var node = _scene("city/%s.gltf" % name)
	node.scale = Vector3.ONE*scale
	parent.add_child(node)
	return node

# --- Props --------------------------------------------------------------------------

## The 3D version of a level prop, or null for props that are only ground marks.
func prop(pr: Dictionary, t: Dictionary) -> Node3D:
	var root = Node3D.new()
	var seed: int = pr.get("seed", 0)
	var rust = _material(Color("5a3a2c"), 0.9, 0.3)
	var metal = _material(Color("4a4e58"), 0.5, 0.6)
	var dark = _material(Color("24222a"), 0.9)
	match pr.kind:
		"car":
			var car = _kit(root, CARS[int(pr.get("color", 0))%CARS.size()])
			car.rotation.y = (PI/2 if pr.get("axis", "y")=="x" else 0.0)+(PI if pr.get("flip", false) else 0.0)
			if pr.get("burned", false):
				var soot = _beam_material(Color(0, 0, 0, 1))
				soot.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
				soot.albedo_color = Color(0.05, 0.04, 0.04, 0.72)
				for m in car.find_children("*", "MeshInstance3D", true, false): m.material_overlay = soot
		"streetlight":
			var lamp = _kit(root, "streetlight")
			# The arm reaches along -x in the model; turn it out over the street.
			var dir: Vector2 = pr.get("dir", Vector2.RIGHT)
			lamp.rotation.y = atan2(dir.y, -dir.x)
			var tip = v3(dir*0.53, 2.0)
			var light = _light(root, t.light, 2.4, 6.0, tip+Vector3(0, -0.15, 0), false)
			if pr.get("flicker", false): root.set_meta("flicker", light)
		"streetlight_low":
			_part(root, "cyl", Vector3(0.04, 1.4, 0), Vector3(0, 0.7, 0), metal)
			_part(root, "sphere", Vector3(0.12, 0, 0), Vector3(0, 1.45, 0), _glow_material(Color(t.light).lightened(0.3), 3.0), false)
			_light(root, t.light, 1.4, 4.0, Vector3(0, 1.3, 0))
		"traffic_light":
			var pole = _kit(root, "trafficlight_B")
			pole.rotation.y = PI*0.75
			var amber = _light(root, Color(1, 0.65, 0.2), 1.0, 2.5, Vector3(0.3, 1.8, 0.3))
			root.set_meta("blink", amber)
		"hydrant": _kit(root, "firehydrant")
		"dumpster":
			var bin = _kit(root, "dumpster")
			bin.rotation.y = (seed%4)*PI/2
		"bench":
			var b = _kit(root, "bench")
			b.rotation.y = (seed%2)*PI/2
		"trash": _kit(root, "trash_A" if seed%2==0 else "trash_B", 3.0)
		"crate":
			var box = _kit(root, "box_A" if seed%2==0 else "box_B", 3.2)
			box.rotation.y = (seed%7)*0.3
		"chest": _footlocker(root)
		"barrel_fire", "drums":
			var count = 1 if pr.kind=="barrel_fire" else 3
			for k in count:
				var at = Vector3(0, 0.36, 0) if count==1 else Vector3((k-1)*0.34, 0.36, (k%2)*0.2-0.1)
				_part(root, "cyl", Vector3(0.18, 0.72, 0), at, rust)
				_part(root, "cyl", Vector3(0.185, 0.04, 0), at+Vector3(0, 0.2, 0), dark)
			if pr.kind=="barrel_fire":
				_fire(root, Vector3(0, 0.78, 0), 0.7)
		"campfire":
			for k in 6:
				var a = k*TAU/6
				_part(root, "sphere", Vector3(0.09, 0, 0), Vector3(cos(a)*0.32, 0.05, sin(a)*0.32), _material(Color("4a4642")))
			_fire(root, Vector3(0, 0.12, 0), 1.0)
		"palm": _palm(root, pr)
		"tires":
			for k in 3:
				var tire = _part(root, "cyl", Vector3(0.22, 0.12, 0), Vector3(0, 0.06+k*0.12, 0), _material(Color("161618"), 0.95))
				tire.rotation.y = k
		"cone":
			_part(root, "cone", Vector3(0.12, 0.4, 0.02), Vector3(0, 0.2, 0), _material(Color("ff6a1a"), 0.6))
		"newsbox":
			_part(root, "box", Vector3(0.36, 0.7, 0.32), Vector3(0, 0.35, 0), _material(Color(["2a5fb0", "c0392b", "e0b020"][seed%3]), 0.6, 0.3))
		"payphone":
			_part(root, "box", Vector3(0.08, 1.5, 0.08), Vector3(0, 0.75, 0), metal)
			_part(root, "box", Vector3(0.42, 0.6, 0.3), Vector3(0, 1.15, 0), _material(Color("8a8f9c"), 0.4, 0.6))
			_part(root, "box", Vector3(0.44, 0.08, 0.34), Vector3(0, 1.5, 0), _glow_material(Color("3ff0ff"), 1.5), false)
		"rubble", "mound":
			for k in 7:
				var r = 0.12+((seed+k*37)%10)*0.02
				var at = Vector3(((seed*3+k*53)%9-4)*0.09, r*0.5, ((seed*7+k*29)%9-4)*0.09)
				var chunk = _part(root, "box", Vector3(r*2, r, r*1.6), at, _material(Color("5a5450").darkened(((seed+k)%3)*0.12)))
				chunk.rotation = Vector3(k*0.4, k*1.3, k*0.2)
		"ruin_wall":
			var length = 2.0
			var height = pr.get("height", 44.0)/45.0
			var along_x = pr.get("axis", "x")=="x"
			var size = Vector3(length*0.95, height, 0.3) if along_x else Vector3(0.3, height, length*0.95)
			var brick = _material(Color("6b3a36").darkened(0.15))
			_part(root, "box", size, Vector3(0, height/2, 0), brick)
			# Broken top: a few uneven blocks.
			for k in 3:
				var off = (k-1)*0.55
				var h = 0.15+((seed+k*13)%5)*0.06
				_part(root, "box", Vector3(0.5, h, 0.3) if along_x else Vector3(0.3, h, 0.5), Vector3(off if along_x else 0.0, height+h/2, 0.0 if along_x else off), brick)
		"bones":
			for k in 4:
				var bone = _part(root, "cyl", Vector3(0.025, 0.3, 0), Vector3((k-1.5)*0.1, 0.03, (k%2)*0.1), _material(Color("d8d0b8")))
				bone.rotation = Vector3(PI/2, k*0.8, 0)
			_part(root, "sphere", Vector3(0.08, 0, 0), Vector3(0.15, 0.07, -0.05), _material(Color("d8d0b8")))
		"paper", "tapes":
			for k in 4:
				_part(root, "box", Vector3(0.18, 0.01 if pr.kind=="paper" else 0.05, 0.12), Vector3((k-1.5)*0.15, 0.02, ((seed+k)%3-1)*0.12), _material(Color("d8d4c8") if pr.kind=="paper" else Color("1a1a1e")), false).rotation.y = k*0.7
		"mattress":
			_part(root, "box", Vector3(0.9, 0.14, 0.55), Vector3(0, 0.07, 0), _material(Color("8a8070"), 0.95)).rotation.y = (seed%5)*0.3
		"tent":
			var cloth = _material(Color(["3a5a3a", "5a3a5a", "3a4a6a", "6a5a3a"][int(pr.get("color", 0))%4]), 0.95)
			var tent = _part(root, "cone", Vector3(0.8, 1.0, 0.0), Vector3(0, 0.5, 0), cloth)
			tent.scale = Vector3(1.2, 1, 0.7)
		"fountain":
			_part(root, "cyl", Vector3(0.95, 0.4, 0), Vector3(0, 0.2, 0), _material(Color("8a8494"), 0.6))
			_part(root, "cyl", Vector3(0.82, 0.05, 0), Vector3(0, 0.38, 0), _material(Color("2a6a8a"), 0.1, 0.2))
			_part(root, "cyl", Vector3(0.12, 0.9, 0), Vector3(0, 0.75, 0), _material(Color("8a8494"), 0.6))
			_light(root, Color(t.glow), 1.0, 3.0, Vector3(0, 0.7, 0))
		"neon_floor":
			_light(root, Color(t.glow), 1.2, 5.0, Vector3(0, 1.2, 0))
		"tv_pile":
			for k in 3:
				var tv = Node3D.new()
				tv.position = Vector3((k-1)*0.36 if k<2 else -0.18, 0.18 if k<2 else 0.54, 0)
				tv.rotation.y = (seed+k)%3*0.2-0.2
				root.add_child(tv)
				_part(tv, "box", Vector3(0.34, 0.34, 0.3), Vector3.ZERO, _material(Color("3a3530"), 0.7))
				_part(tv, "box", Vector3(0.26, 0.22, 0.02), Vector3(0, 0.02, 0.15), _glow_material(Color(0.45, 0.6, 1.0), 1.4), false)
			var tv_light = _light(root, Color(0.5, 0.65, 1.0), 0.8, 2.5, Vector3(0, 0.5, 0.5))
			root.set_meta("flicker", tv_light)
		_:
			_indoor(root, pr, t)
	if root.get_child_count()==0:
		root.free()
		return null
	return root

## Shop and home furniture that faces into the room.
func _indoor(root: Node3D, pr: Dictionary, t: Dictionary) -> void:
	var front: Vector2 = Vector2(pr.get("face", Vector2i.DOWN))
	var seed: int = pr.get("seed", 0)
	var body = Node3D.new()
	face(body, front)
	root.add_child(body)
	match pr.kind:
		"arcade":
			var color: Color = SCREEN_COLORS[int(pr.get("color", 0))%SCREEN_COLORS.size()]
			var broken = pr.get("broken", false)
			_part(body, "box", Vector3(0.62, 1.15, 0.6), Vector3(0, 0.575, -0.05), _material(Color("231a33"), 0.5))
			_part(body, "box", Vector3(0.64, 0.12, 0.62), Vector3(0, 1.2, -0.05), _glow_material(color, 1.6), false)
			var screen = _part(body, "box", Vector3(0.46, 0.36, 0.04), Vector3(0, 0.85, 0.26), _glow_material(color.lerp(Color.WHITE, 0.3), 2.0) if not broken else _material(Color("101014"), 0.2), false)
			screen.rotation.x = -0.25
			_part(body, "box", Vector3(0.56, 0.08, 0.2), Vector3(0, 0.6, 0.32), _material(Color("15121c")))
			if not broken: _light(body, color, 0.9, 2.2, Vector3(0, 0.9, 0.7))
		"washer":
			_part(body, "box", Vector3(0.6, 0.6, 0.58), Vector3(0, 0.3, 0), _material(Color("d8dce4"), 0.3, 0.2))
			_part(body, "cyl", Vector3(0.18, 0.03, 0), Vector3(0, 0.32, 0.3), _material(Color("6a7c90"), 0.1, 0.4)).rotation.x = PI/2
		"jukebox":
			_part(body, "box", Vector3(0.6, 0.7, 0.4), Vector3(0, 0.35, 0), _material(Color("5a2a3a"), 0.4, 0.3))
			_part(body, "cyl", Vector3(0.3, 0.4, 0), Vector3(0, 0.7, 0), _glow_material(Color("c03aa0"), 0.8), false).rotation.x = PI/2
			_light(body, Color(1, 0.5, 0.9), 0.8, 2.4, Vector3(0, 0.8, 0.5))
		"booth":
			var seat = _material(Color("b03a4a"), 0.5)
			_part(body, "box", Vector3(0.9, 0.42, 0.42), Vector3(0, 0.21, -0.25), seat)
			_part(body, "box", Vector3(0.9, 0.5, 0.12), Vector3(0, 0.6, -0.42), seat)
			_part(body, "box", Vector3(0.7, 0.05, 0.4), Vector3(0, 0.7, 0.22), _material(Color("d8d0c0"), 0.3))
			_part(body, "cyl", Vector3(0.04, 0.68, 0), Vector3(0, 0.34, 0.22), _material(Color("9aa0a8"), 0.3, 0.7))
		"counter", "shelf":
			var length: float = pr.get("length", 2)
			var along_x = pr.get("axis", "x")=="x"
			body.rotation.y = 0.0 if along_x else PI/2
			if pr.kind=="counter":
				_part(body, "box", Vector3(length*0.98, 0.75, 0.5), Vector3(0, 0.375, 0), _material(Color("5a4a66"), 0.35, 0.4))
				_part(body, "box", Vector3(length*0.98, 0.05, 0.6), Vector3(0, 0.77, 0), _material(Color("c8c4d0"), 0.2, 0.6))
				_part(body, "box", Vector3(length*0.98, 0.04, 0.02), Vector3(0, 0.6, 0.26), _glow_material(Color("ff4fd8"), 1.5), false)
			else:
				_part(body, "box", Vector3(length*0.95, 1.4, 0.5), Vector3(0, 0.7, 0), _material(Color("3a3440"), 0.8))
				for k in 3:
					_part(body, "box", Vector3(length*0.9, 0.22, 0.42), Vector3(0, 0.3+k*0.42, 0.02), _material(Color(["7a3a8a", "2a6a8a", "8a6a2a"][k]), 0.6))
		"stool":
			_part(body, "cyl", Vector3(0.03, 0.55, 0), Vector3(0, 0.27, 0), _material(Color("9aa0a8"), 0.3, 0.7))
			_part(body, "cyl", Vector3(0.17, 0.08, 0), Vector3(0, 0.58, 0), _material(Color("b03a4a"), 0.5))
		"column":
			# A broken support pillar, kept low so it never hides the fight.
			_part(body, "box", Vector3(0.45, 1.1, 0.45), Vector3(0, 0.55, 0), _material(Color("6a6c75"), 0.8))
			_part(body, "box", Vector3(0.3, 0.25, 0.3), Vector3(0.05, 1.2, -0.03), _material(Color("6a6c75"), 0.8)).rotation = Vector3(0.3, 0.5, 0.2)
		"cart":
			_part(body, "box", Vector3(0.5, 0.35, 0.7), Vector3(0, 0.55, 0), _material(Color("9aa0a8"), 0.3, 0.7))
			for k in 4: _part(body, "cyl", Vector3(0.05, 0.04, 0), Vector3((k%2-0.5)*0.4, 0.06, (k/2-0.5)*0.55), dark_material()).rotation.z = PI/2
		"vendor":
			# A food court stall: counter, striped awning, neon name and the
			# shopkeeper behind the counter.
			var juice = pr.get("vendor", "")=="juice"
			var color = Color("5dff8f") if juice else Color("ffb438")
			_part(body, "box", Vector3(1.9, 0.8, 0.5), Vector3(0, 0.4, 0.25), _material(Color("3a2a4a"), 0.4, 0.3))
			_part(body, "box", Vector3(1.95, 0.05, 0.6), Vector3(0, 0.82, 0.25), _material(Color("e8e0f0"), 0.2, 0.5))
			_part(body, "box", Vector3(1.9, 0.04, 0.02), Vector3(0, 0.62, 0.51), _glow_material(color, 1.8), false)
			for k in 6:
				_part(body, "box", Vector3(0.33, 0.04, 0.7), Vector3(-0.83+k*0.33, 2.0, 0.1), _material(color if k%2==0 else Color("f0e8f0"), 0.6)).rotation.x = 0.35
			_part(body, "box", Vector3(1.9, 1.9, 0.08), Vector3(0, 1.0, -0.45), _material(Color("231a33"), 0.7))
			var shelf = Color("ff8aa0") if juice else Color("9aa0a8")
			for k in 5: _part(body, "box", Vector3(0.18, 0.26, 0.14), Vector3(-0.7+k*0.35, 1.25, -0.35), _glow_material(shelf, 0.6) if juice else _material(shelf, 0.4, 0.6))
			_sign(body, "JUICE BAR" if juice else "RAY'S PAWN", Vector3(0, 2.35, 0.3), color, 64)
			var keeper = npc("Mage" if juice else "Knight", Vector2.DOWN)
			keeper.position = Vector3(0, 0, -0.15)
			body.add_child(keeper)
			_light(body, color, 1.6, 4.0, Vector3(0, 1.6, 0.9))
		"stash":
			# A wall of lockers with one standing open, the hero's own.
			for k in 3:
				var locker = _part(body, "box", Vector3(0.3, 1.5, 0.45), Vector3(-0.31+k*0.31, 0.75, -0.1), _material(Color(["3a6a8a", "2a5a7a", "3a6a8a"][k]), 0.5, 0.4))
				_part(body, "box", Vector3(0.18, 0.03, 0.01), Vector3(-0.31+k*0.31, 1.3, 0.13), dark_material())
			_part(body, "box", Vector3(0.96, 0.06, 0.5), Vector3(0, 1.53, -0.1), _glow_material(Color("3ff0ff"), 1.5), false)
			_sign(body, "STASH", Vector3(0, 1.9, 0.0), Color("3ff0ff"), 56)
			_light(body, Color("3ff0ff"), 1.2, 3.0, Vector3(0, 1.2, 0.7))
		"transit":
			# A lit transit map on a post: fast travel to places you have been.
			_part(body, "box", Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0), _material(Color("2a2c32"), 0.5, 0.6))
			_part(body, "box", Vector3(0.9, 0.7, 0.08), Vector3(0, 1.35, 0), _material(Color("1a1e28"), 0.4, 0.4))
			_part(body, "box", Vector3(0.82, 0.62, 0.02), Vector3(0, 1.35, 0.05), _glow_material(Color("e8f0ff"), 0.9), false)
			for k in 4:
				var line = _part(body, "box", Vector3(0.7, 0.025, 0.01), Vector3(0, 1.17+k*0.12, 0.065), _glow_material(SCREEN_COLORS[k], 2.0), false)
				line.rotation.z = (k-1.5)*0.12
			_sign(body, "TRANSIT", Vector3(0, 1.95, 0.0), Color("5dff8f"), 48)
			_light(body, Color(0.7, 1.0, 0.85), 1.2, 3.0, Vector3(0, 1.4, 0.6))
		"table":
			var top = _material(Color(["e8e0f0", "ff9ad8", "9ae8ff", "ffe89a"][int(pr.get("color", 0))%4]), 0.4, 0.2)
			_part(body, "cyl", Vector3(0.38, 0.05, 0), Vector3(0, 0.7, 0), top)
			_part(body, "cyl", Vector3(0.04, 0.68, 0), Vector3(0, 0.34, 0), _material(Color("9aa0a8"), 0.3, 0.7))
			for k in 3:
				var a = k*TAU/3+0.4
				_part(body, "cyl", Vector3(0.15, 0.05, 0), Vector3(cos(a)*0.6, 0.42, sin(a)*0.6), _material(Color("b03a4a"), 0.5))
				_part(body, "cyl", Vector3(0.025, 0.4, 0), Vector3(cos(a)*0.6, 0.2, sin(a)*0.6), _material(Color("9aa0a8"), 0.3, 0.7))
		"planter":
			_part(body, "box", Vector3(0.9, 0.45, 0.9), Vector3(0, 0.225, 0), _material(Color("c8b8d0"), 0.4))
			_part(body, "box", Vector3(0.8, 0.04, 0.8), Vector3(0, 0.46, 0), _material(Color("3a2a20"), 1.0))
			var palm = Node3D.new()
			palm.position.y = 0.45
			palm.scale = Vector3.ONE*0.75
			body.add_child(palm)
			_palm(palm, {"lean":0.1})
		"rack":
			var color: Color = SCREEN_COLORS[int(pr.get("color", 0))%SCREEN_COLORS.size()]
			_part(body, "box", Vector3(1.8, 0.04, 0.04), Vector3(0, 1.2, 0), _material(Color("c8ccd4"), 0.2, 0.8))
			for x in [-0.88, 0.88]: _part(body, "cyl", Vector3(0.025, 1.2, 0), Vector3(x, 0.6, 0), _material(Color("c8ccd4"), 0.2, 0.8))
			for k in 7:
				var shirt = _part(body, "box", Vector3(0.18, 0.62, 0.36), Vector3(-0.72+k*0.24, 0.86, 0), _material(color.lerp(Color("2a2238"), (k%3)*0.25), 0.8))
				shirt.rotation.y = 0.15*(k%2)
		"mannequin":
			var skin = _material(Color("e8e0d8"), 0.3)
			var outfit = _material(SCREEN_COLORS[int(pr.get("color", 0))%SCREEN_COLORS.size()].darkened(0.2), 0.7)
			_part(body, "cyl", Vector3(0.2, 0.04, 0), Vector3(0, 0.02, 0), dark_material())
			_part(body, "cyl", Vector3(0.025, 0.5, 0), Vector3(0, 0.27, 0), skin)
			_part(body, "box", Vector3(0.36, 0.55, 0.2), Vector3(0, 0.82, 0), outfit)
			_part(body, "sphere", Vector3(0.11, 0, 0), Vector3(0, 1.22, 0), skin)
			for x in [-1, 1]: _part(body, "box", Vector3(0.08, 0.5, 0.08), Vector3(x*0.23, 0.8, 0), outfit).rotation.z = x*0.15
		"pillar":
			# A tiled station column with a strip light, floor to ceiling.
			_part(body, "box", Vector3(0.6, 3.0, 0.6), Vector3(0, 1.5, 0), _material(Color(t.get("wall", Color("d8d8cc"))), 0.3))
			_part(body, "box", Vector3(0.62, 0.14, 0.62), Vector3(0, 0.5, 0), _material(Color(t.get("band", Color("2a8a5a"))), 0.4))
			_part(body, "box", Vector3(0.64, 0.05, 0.64), Vector3(0, 2.3, 0), _glow_material(Color(t.light), 1.5), false)
		"pallet":
			_part(body, "box", Vector3(0.9, 0.12, 0.9), Vector3(0, 0.06, 0), _material(Color("8a6a44"), 0.9))
			for k in int(pr.get("height", 1)):
				var crate = _part(body, "box", Vector3(0.8, 0.5, 0.8), Vector3(0.03*(k%2), 0.37+k*0.5, 0), _material(Color(["9a7a4a", "7a6a5a", "5a6a4a"][(seed+k)%3]), 0.9))
				crate.rotation.y = 0.1*((seed+k)%3-1)
		"tv_small":
			_part(body, "box", Vector3(0.36, 0.3, 0.3), Vector3(0, 0.95, 0), _material(Color("2a2830"), 0.6))
			_part(body, "box", Vector3(0.28, 0.22, 0.01), Vector3(0, 0.95, 0.155), _glow_material(SCREEN_COLORS[seed%SCREEN_COLORS.size()].lerp(Color.WHITE, 0.4), 1.2), false)
		"swing":
			var frame = _material(Color("c84a3a"), 0.5, 0.4)
			for x in [-0.9, 0.9]:
				for z in [-0.35, 0.35]: _part(body, "cyl", Vector3(0.04, 1.8, 0), Vector3(x, 0.85, z*0.6), frame).rotation.x = z*0.4
			_part(body, "cyl", Vector3(0.04, 1.85, 0), Vector3(0, 1.72, 0), frame).rotation.z = PI/2
			for x in [-0.45, 0.45]:
				_part(body, "box", Vector3(0.01, 1.25, 0.01), Vector3(x, 1.1, 0), dark_material())
				_part(body, "box", Vector3(0.3, 0.04, 0.16), Vector3(x, 0.45, 0), _material(Color("2a2a30")))
		"slide":
			_part(body, "box", Vector3(0.5, 1.2, 0.5), Vector3(0, 0.6, -0.6), _material(Color("3a6aaa"), 0.5, 0.3))
			var chute = _part(body, "box", Vector3(0.45, 0.06, 1.5), Vector3(0, 0.62, 0.35), _material(Color("e0c030"), 0.3, 0.4))
			chute.rotation.x = 0.62
		"bandshell":
			# A half dome stage with lights along its rim: the Hex Kids' turf.
			_part(body, "box", Vector3(5.8, 0.45, 2.8), Vector3(0, 0.22, 0), _material(Color("6a6670"), 0.8))
			var shell = _part(body, "sphere", Vector3(2.8, 0, 0), Vector3(0, 0.45, -0.2), _material(Color("d8d0c8"), 0.6))
			shell.scale = Vector3(1.0, 0.85, 0.55)
			for k in 7:
				var a = PI*(k+0.5)/7.0
				_part(body, "sphere", Vector3(0.09, 0, 0), Vector3(cos(a)*2.75, 0.45+sin(a)*2.3, 1.2), _glow_material(SCREEN_COLORS[k%SCREEN_COLORS.size()], 2.5), false)
			_light(body, Color(0.9, 0.5, 1.0), 2.2, 6.0, Vector3(0, 1.6, 1.6))
		"train":
			# A stalled subway car, graffiti-free steel with a lit window strip.
			var length: float = pr.get("length", 12)
			body.rotation.y = PI/2
			_part(body, "box", Vector3(2.5, 2.0, length-0.2), Vector3(0, 0.85, 0), _material(Color("a8acb4"), 0.3, 0.7))
			_part(body, "box", Vector3(2.52, 0.12, length-0.2), Vector3(0, 0.5, 0), _material(Color("c03a3a"), 0.4))
			for side in [-1, 1]:
				_part(body, "box", Vector3(0.02, 0.5, length-1.0), Vector3(side*1.26, 1.25, 0), _glow_material(Color("fff2c8"), 0.7), false)
				for k in int(length/4.0):
					_part(body, "box", Vector3(0.03, 1.2, 0.7), Vector3(side*1.26, 0.85, -length/2.0+2.0+k*4.0), _material(Color("6a6e78"), 0.4, 0.6))
			_light(body, Color("fff2c8"), 1.2, 5.0, Vector3(0, 2.0, 0))
		"tree":
			# A city park tree: a dark trunk and a lumpy round crown.
			var size: float = pr.get("size", 1.0)
			var trunk = _material(Color("4a3a2c"), 0.9)
			_part(body, "cone", Vector3(0.13*size, 1.4*size, 0.09*size), Vector3(0, 0.7*size, 0), trunk)
			var leaf = _material(Color(["2f5a34", "3a6a3a", "4a5a2a"][int(pr.get("color", 0))%3]), 0.8)
			for k in 4:
				var a = k*TAU/4+seed
				_part(body, "sphere", Vector3((0.55+0.1*(k%2))*size, 0, 0), Vector3(cos(a)*0.3*size, (1.75+0.2*(k%2))*size, sin(a)*0.3*size), leaf)
		_:
			_part(body, "box", Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), _material(Color("4a4652")))

## A neon word floating over a stall.
func _sign(parent: Node3D, text: String, at: Vector3, color: Color, size: int) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.modulate = color*1.7
	label.outline_size = 10
	label.outline_modulate = Color(color, 0.6)
	label.shaded = false
	label.position = at
	parent.add_child(label)

## A townsperson standing still and breathing: shopkeepers and such.
func npc(model: String, facing: Vector2) -> Node3D:
	var actor = _actor("characters/%s.glb" % model, HERO_SCALE)
	for attachment in actor.find_children("*", "BoneAttachment3D", true, false):
		for item in attachment.get_children():
			var name = String(item.name)
			if name.begins_with("1H_") or name.begins_with("2H_") or "Shield" in name or "Spellbook" in name or "Knife" in name or name=="Throwable":
				item.visible = false
	var player: AnimationPlayer = actor.get_meta("anim")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if player.has_animation("Idle"): player.play("Idle")
	face(actor.get_meta("model"), facing)
	return actor

## A doorway into a side area, set into a building front: a dark opening in a
## lit frame with the place's name over it. Gates (the park) are an iron arch.
func doorway(exit: Dictionary, t: Dictionary, gate: bool) -> Node3D:
	if exit.get("zone", "")=="mall": return mall_entrance(exit)
	var root = Node3D.new()
	var text: String = exit.get("sign", "EXIT")
	var color = Color("5dff8f") if gate else Color("ff4fd8")
	if exit.has("zone") and exit.zone=="warehouse": color = Color("ffb438")
	if gate:
		var iron = _material(Color("1c1c22"), 0.5, 0.7)
		# Open promenade: fence wings and trees frame a broad, unobstructed path.
		for x in [-2.1, 2.1]:
			_part(root, "box", Vector3(0.32, 1.65, 0.32), Vector3(x, 0.825, 0), _material(Color("807365"), 0.9))
			_part(root, "sphere", Vector3(0.14, 0, 0), Vector3(x, 1.8, 0), _glow_material(Color("ffe8a0"), 2), false)
			for k in 6:
				var fx = x+signf(x)*k*0.3
				_part(root, "box", Vector3(0.045, 1.1, 0.045), Vector3(fx, 0.55, 0), iron)
			for height in [0.35, 1.0]:
				_part(root, "box", Vector3(1.8, 0.06, 0.06), Vector3(x+signf(x)*0.8, height, 0), iron)
			for z in [-1.6, -3.2]:
				_part(root, "cyl", Vector3(0.14, 1.2, 0), Vector3(x*1.3, 0.6, z), _material(Color("67503c"), 0.9))
				_part(root, "sphere", Vector3(0.85, 0, 0), Vector3(x*1.3, 1.7, z), _material(Color("315e42"), 0.9))

	else:
		var frame = _material(Color("2a2834"), 0.4, 0.6)
		_part(root, "box", Vector3(1.3, 1.75, 0.04), Vector3(0, 0.875, 0.02), _material(Color("050507"), 1.0), false)
		for x in [-0.7, 0.7]: _part(root, "box", Vector3(0.12, 1.9, 0.14), Vector3(x, 0.95, 0.05), frame)
		_part(root, "box", Vector3(1.55, 0.14, 0.16), Vector3(0, 1.9, 0.06), frame)
		_part(root, "box", Vector3(1.5, 0.03, 0.03), Vector3(0, 1.78, 0.14), _glow_material(color, 2.0), false)
		# A doormat of light spilling out.
		_part(root, "box", Vector3(1.1, 0.01, 0.6), Vector3(0, 0.015, 0.4), _beam_material(Color(color, 0.12)), false)
	var label = Label3D.new()
	label.text = text
	label.font_size = 80
	label.pixel_size = 0.0055
	label.modulate = color*1.8
	label.outline_size = 12
	label.outline_modulate = Color(color, 0.6)
	label.shaded = false
	label.position = Vector3(0, 2.6 if not gate else 2.95, 0.12)
	root.add_child(label)
	_light(root, color, 2.0, 5.0, Vector3(0, 2.0, 0.9))
	return root

func mall_entrance(exit: Dictionary) -> Node3D:
	var root = Node3D.new()
	var stone = _material(Color("b0a7b8"), 0.7)
	var chrome = _material(Color("74869b"), 0.3, 0.7)
	var glass = _material(Color("24556c"), 0.25, 0.4)
	# Broad glazed frontage, double doors and a projecting illuminated canopy.
	_part(root, "box", Vector3(8.0, 3.4, 0.25), Vector3(0, 1.7, -0.18), stone)
	for x in [-3.0, -1.8, -0.6, 0.6, 1.8, 3.0]:
		_part(root, "box", Vector3(1.08, 2.4, 0.12), Vector3(x, 1.25, 0.02), glass)
		_part(root, "box", Vector3(0.06, 2.5, 0.2), Vector3(x-0.57, 1.25, 0.1), chrome)
	for x in [-0.2, 0.2]:
		_part(root, "box", Vector3(0.055, 0.55, 0.12), Vector3(x, 1.0, 0.2), chrome)
	_part(root, "box", Vector3(8.4, 0.25, 1.7), Vector3(0, 2.7, 0.6), stone)
	_part(root, "box", Vector3(8.1, 0.055, 0.08), Vector3(0, 2.64, 1.46), _glow_material(Color("ff4fd8"), 2), false)
	var label = Label3D.new()
	label.text = exit.get("sign", "STARLIGHT MALL")
	label.font_size = 90; label.pixel_size = 0.006
	label.position = Vector3(0, 3.22, 0.18)
	label.modulate = Color("ffd3f4"); label.outline_size = 10; label.shaded = false
	root.add_child(label)
	# Marked parking bays flank the pedestrian approach.
	for side in [-1, 1]:
		for z in [2.3, 4.0]:
			_part(root, "box", Vector3(2.1, 0.015, 0.06), Vector3(side*2.8, 0.025, z), _material(Color("d5cfac"), 1), false)
		_part(root, "box", Vector3(0.07, 0.015, 3.4), Vector3(side*1.65, 0.025, 3.1), _material(Color("d5cfac"), 1), false)
	_light(root, Color("ff9edb"), 2, 6, Vector3(0, 2.4, 1.5))
	return root

func dark_material() -> StandardMaterial3D:
	return _material(Color("161618"), 0.9)

## A footlocker full of loot: olive steel with brass corners, lit by a gold
## column of light and a bobbing marker so it reads from across the street.
func _footlocker(root: Node3D) -> void:
	var olive = _material(Color("4e5a34"), 0.6, 0.3)
	var brass = _material(Color("d8a840"), 0.3, 0.8)
	_part(root, "box", Vector3(0.72, 0.34, 0.42), Vector3(0, 0.17, 0), olive)
	var hinge = Node3D.new()
	hinge.position = Vector3(0, 0.34, -0.21)
	root.add_child(hinge)
	_part(hinge, "box", Vector3(0.74, 0.1, 0.44), Vector3(0, 0.05, 0.21), olive)
	_part(hinge, "box", Vector3(0.12, 0.08, 0.04), Vector3(0, 0.0, 0.43), brass)
	for x in [-1, 1]:
		_part(root, "box", Vector3(0.06, 0.36, 0.44), Vector3(x*0.34, 0.18, 0), brass)
	root.set_meta("lid", hinge)
	var beam = _part(root, "cone", Vector3(0.42, 3.0, 0.2), Vector3(0, 1.5, 0), _beam_material(Color(1.0, 0.8, 0.3, 0.08)), false)
	var marker = _part(root, "cone", Vector3(0.0, 0.26, 0.14), Vector3(0, 1.25, 0), _glow_material(Color(1.0, 0.82, 0.3), 2.5), false)
	var light = _light(root, Color(1.0, 0.8, 0.4), 1.8, 3.0, Vector3(0, 0.8, 0))
	root.set_meta("beam", beam)
	root.set_meta("bob", marker)
	root.set_meta("glow", light)

func _fire(root: Node3D, at: Vector3, size: float) -> void:
	var fire = _beam_material(Color(1.0, 0.55, 0.15, 0.9))
	_part(root, "cone", Vector3(0.14*size, 0.36*size, 0.0), at+Vector3(0, 0.18*size, 0), fire, false)
	_part(root, "cone", Vector3(0.08*size, 0.5*size, 0.0), at+Vector3(0.03, 0.25*size, 0.02), _beam_material(Color(1.0, 0.85, 0.35, 0.9)), false)
	var light = _light(root, Color(1.0, 0.55, 0.22), 2.2*size, 4.5*size, at+Vector3(0, 0.4, 0), false)
	root.set_meta("fire", light)

func _palm(root: Node3D, pr: Dictionary) -> void:
	var lean: float = pr.get("lean", 0.0)
	var trunk = Node3D.new()
	trunk.rotation.z = lean*0.4
	root.add_child(trunk)
	var bark = _material(Color("6a5038"), 0.9)
	for k in 7:
		_part(trunk, "cone", Vector3(0.13-k*0.008, 0.42, 0.11-k*0.008), Vector3(0, 0.21+k*0.4, 0), bark)
	var crown = Vector3(0, 2.85, 0)
	var leaf = _material(Color("2f6a3a") if not pr.get("neon", false) else Color("2a8a6a"), 0.7)
	for k in 7:
		var frond = _part(trunk, "box", Vector3(0.18, 0.03, 1.1), crown, leaf)
		frond.rotation = Vector3(0.45, k*TAU/7, 0)
		frond.translate_object_local(Vector3(0, 0, 0.5))
	if pr.get("neon", false):
		_part(trunk, "cyl", Vector3(0.14, 0.05, 0), Vector3(0, 1.2, 0), _glow_material(Color("ff4fd8"), 2.0), false)

## Rooftop clutter: a water tower or a boxy air conditioner.
func roof_prop(roll: int) -> Node3D:
	var root = Node3D.new()
	if roll<8:
		var tower = _kit(root, "watertower", 2.4)
		tower.rotation.y = roll*0.7
	else:
		_part(root, "box", Vector3(0.6, 0.4, 0.5), Vector3(0, 0.2, 0), _material(Color("7a7e88"), 0.5, 0.5))
		_part(root, "cyl", Vector3(0.18, 0.03, 0), Vector3(0, 0.41, 0), _material(Color("2a2c32"), 0.6))
	return root

## Swings a footlocker open once it has been looted.
func open_prop(node: Node3D, pr: Dictionary) -> void:
	if node.has_meta("lid"):
		var tween = node.create_tween()
		tween.tween_property(node.get_meta("lid"), "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK)
		for key in ["beam", "bob"]:
			if node.has_meta(key): node.get_meta(key).visible = false
		if node.has_meta("glow"): tween.parallel().tween_property(node.get_meta("glow"), "light_energy", 0.0, 0.8)
		node.remove_meta("bob")

## The subway entrance down to the next floor: a stairwell with railings, a
## lit globe and a sign.
func subway(t: Dictionary, text: String = "SUBWAY") -> Node3D:
	var root = Node3D.new()
	var rail = _material(Color("2e6a4a"), 0.4, 0.6)
	_part(root, "box", Vector3(1.5, 0.02, 1.9), Vector3(0, -1.0, 0), _material(Color("050507"), 1.0), false)
	for k in 5:
		_part(root, "box", Vector3(1.5, 0.17, 0.34), Vector3(0, -0.93+k*0.17, -0.75+k*0.34), _material(Color("2a2a30").lightened(0.08*(4-k)), 0.9), false)
	for x in [-0.78, 0.78]:
		_part(root, "box", Vector3(0.06, 1.0, 2.0), Vector3(x, -0.5, 0), _material(Color("30343a"), 0.9))
		_part(root, "box", Vector3(0.06, 0.9, 2.0), Vector3(x, 0.45, 0), rail)
	_part(root, "box", Vector3(1.6, 0.9, 0.06), Vector3(0, 0.45, -1.0), rail)
	for x in [-0.78, 0.78]:
		_part(root, "cyl", Vector3(0.05, 2.2, 0), Vector3(x, 1.1, 1.0), rail)
		_part(root, "sphere", Vector3(0.16, 0, 0), Vector3(x, 2.3, 1.0), _glow_material(Color("5dff8f"), 2.5), false)
	var sign = Label3D.new()
	sign.text = text
	sign.font_size = 72
	sign.pixel_size = 0.005
	sign.modulate = Color(0.75, 1.0, 0.85)*1.6
	sign.outline_size = 10
	sign.outline_modulate = Color(0.1, 0.5, 0.3, 0.8)
	sign.shaded = false
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(0, 2.0, 1.0)
	root.add_child(sign)
	_light(root, Color(0.4, 1.0, 0.6), 2.0, 5.0, Vector3(0, 1.8, 1.3))
	return root

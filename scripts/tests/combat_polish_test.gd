extends SceneTree
const Timing=preload("res://scripts/combat_timing.gd")
const Models=preload("res://scripts/models.gd")
const Classes=preload("res://scripts/classes.gd")
var g
var failures=[]

func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _initialize() -> void: run.call_deferred()

func arena(class_id: String="samurai") -> void:
	g.testing=true
	g._begin(false,class_id)
	g.enemies.clear(); g.props.clear(); g.drops.clear(); g.shots.clear(); g.fx.clear()
	g.cells.clear(); g.blocked.clear(); g._carve(1,1,24,24)
	g.player.pos=Vector2(12,12); g.player.angle=0; g.display_angle=0
	g.player.inv=100; g.player.attack=0; g.player.roll=0
	g.keys.clear(); g.attack_held=false; g.pointer_active=false
	g.screen_velocity=Vector2.ZERO; g.walk_blend=0
	g.combo_window=0; g.combo_index=-1; g.swing.clear()
	g.stats.crit=0; g.stats.damage_min=15; g.stats.damage_max=15
	g.state="play"

func target() -> Dictionary:
	var e=g._spawn_enemy("brute",g.player.pos+Vector2(1,0))
	e.hp=100000.0; e.max_hp=e.hp; e.attack=100; e.stagger=100
	return e

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate(); root.add_child(g)
	await process_frame
	g.set_process(false); g.save_file="user://combat-polish-test.json"
	for speed in [.8,1.0,2.5]:
		for index in 3:
			arena(); var e=target(); g.stats.attack_speed=speed
			g.combo_index=index-1; g.combo_window=1 if index>0 else 0
			g._slash(true)
			g._advance_game(g.swing.contact-.012)
			check(e.hp==100000,"No early damage at speed %s combo %s"%[speed,index])
			g._advance_game(.021)
			check(e.hp<100000,"Contact deals damage at speed %s combo %s"%[speed,index])
			var hp=e.hp; g._advance_game(.05)
			check(e.hp==hp,"One damage event per swing")
	# Live hitstop must consume only its duration, rather than discard a frame.
	arena(); g.testing=false; g.hitstop=.035
	var elapsed=g.elapsed; g._advance_game(.1)
	check(absf(g.elapsed-elapsed-.065)<.0001,"A 35ms hit pause preserves the remaining 65ms of a 100ms frame")
	var counts=[]
	for fps in [15,30,60,144]:
		arena(); var e=target(); g.testing=false
		var first=g.attack_serial; g.keys[KEY_J]=true
		for frame in fps*3:
			e.pos=g.player.pos+Vector2(1,0); e.stagger=100
			g._advance_game(1.0/fps)
		counts.append(g.attack_serial-first)
	check(counts.max()-counts.min()<=1,"Held combos stay consistent at 15/30/60/144 FPS: %s"%str(counts))
	for class_id in ["gunslinger","synth_mage"]:
		arena(class_id); var ranged_target=target(); ranged_target.pos=g.player.pos+Vector2(4,0)
		g._basic_attack(true)
		check(g.shots.is_empty(),"Ranged attack has a visible windup")
		g._advance_game(.015)
		g._dodge(); g._advance_game(.10)
		check(g.shots.is_empty(),"Dodge cancels an unreleased "+class_id+" shot")
		g.player.roll=0; g.player.attack=0
		g._basic_attack(true)
		g._advance_game(g.player.ranged_attack.fire_at+.012)
		check(g.shots.size()==1,"Exactly one shot at the release frame")
	# Validate the actual imported pose, not only the timing helper.
	arena(); target(); g._slash(true)
	g.swing.age=g.swing.contact; g.simulation_delta=0
	var actor=g.view3d.hero
	g.view3d.models.pose_hero(actor,g,0)
	check(absf(actor.get_meta("anim").current_animation_position-.445)<.002,"Blade reaches measured contact pose at damage time")
	check(actor.get_meta("combat_legs").size()>=6,"Moving attacks have leg animation tracks")
	var frozen=actor.get_meta("anim").current_animation_position
	g.view3d.models.pose_hero(actor,g,.1)
	check(is_equal_approx(frozen,actor.get_meta("anim").current_animation_position),"Hitstop holds the blade pose")
	arena("gunslinger"); g._basic_attack(true)
	g.player.ranged_attack.age=g.player.ranged_attack.fire_at
	g.view3d.models.pose_hero(g.view3d.hero,g,0)
	var points=Models.CombatAnimator._points(g.view3d.hero)
	check((points[1]-points[0]).normalized().dot(Vector3.RIGHT)>.9,"Revolver barrel faces the firing direction")
	# A target pushed out of reach should be pursued while the button stays held.
	arena(); var e=target(); g.combat_target=e; g.attack_held=true
	e.pos=g.player.pos+Vector2(3,0)
	g._click_direction(.016)
	check(not g.chase.is_empty(),"Hold attack pursues a target pushed outside melee reach")
	g.keys[KEY_D]=true; g._update_hero(.016)
	check(g.chase.is_empty() and g.combat_target.is_empty(),"Keyboard movement overrides pursuit")
	if FileAccess.file_exists(g.save_file): DirAccess.remove_absolute(g.save_file)
	if failures.is_empty(): print("PASS: contact at 0.8x/1x/2.5x speed; single hits; exact hitstop budget; combos at 15/30/60/144 FPS ",counts,"; gun/mage release and dodge cancellation; imported contact pose; frozen animation; firing direction; target pursuit and movement override.")
	g.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

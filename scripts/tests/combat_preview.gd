extends SceneTree
const Models=preload("res://scripts/models.gd")
const Timing=preload("res://scripts/combat_timing.gd")
const Items=preload("res://scripts/items.gd")
var g

func _initialize() -> void: run.call_deferred()

func capture(name: String) -> void:
	g.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/combat-polish/"+name+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://previews/combat-polish")
	g=load("res://scenes/main.tscn").instantiate(); root.add_child(g)
	await process_frame
	g.testing=true; g.save_file="user://combat-preview-test.json"
	g._begin(); g.seed_value=71283; g._generate(1)
	g.enemies.clear(); g.level_banner=0; g.player.inv=100
	# Let the normal renderer warm up before measuring actual presentation.
	for i in 45: await process_frame
	var start=Time.get_ticks_msec()
	for i in 90: await process_frame
	print("Presentation sample: ",snapped(90000.0/(Time.get_ticks_msec()-start),.1)," FPS; draw calls ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	g.set_process(false)
	g.state="play"; g.zoom=2.2; g._apply_zoom()
	var target=g._spawn_enemy("brute",g.player.pos+Vector2(1.25,0)); target.hp=10000; target.attack=100; target.stagger=100
	g.player.angle=0; g.display_angle=0; g.pointer_active=false
	g.player.equipment.weapon.style="katana"; g._recalc()
	g._slash(true)
	for age in [.035,.085,.12,.21]:
		while g.swing.age<age: g._advance_game(minf(.008,age-g.swing.age)); g.view3d.sync(.008)
		await capture("slash-%03d"%roundi(age*1000))
	g.player.roll=0; g.player.attack=0; g.swing.clear(); g.combo_index=1; g.combo_window=1
	g._slash(true)
	while g.swing.age<.135: g._advance_game(.008); g.view3d.sync(.008)
	await capture("finisher")
	g._dodge(); g._advance_game(.055); g.view3d.sync(.055)
	await capture("dodge-cancel")
	# Close-up firing frames, after exactly one projectile release.
	for class_id in ["gunslinger","synth_mage"]:
		g._begin(false,class_id); g.seed_value=71283; g._generate(1)
		g.enemies.clear(); g.player.inv=100; g.player.angle=0; g.display_angle=0
		g.zoom=2.2; g._apply_zoom(); g.pointer_active=false; g.level_banner=0
		g._basic_attack()
		g._advance_game(g.player.ranged_attack.fire_at+.005); g.view3d.sync(.05)
		await capture(class_id+"-release")
	# Weapon designs displayed in native 3D with their equipped color treatments.
	g._begin(); g.enemies.clear(); g.level_banner=0
	g.player.equipment.weapon.style="axe"; g._recalc(); g.view3d.sync(.016)
	g._toggle_panel("inventory")
	await capture("equipped-axe")
	if FileAccess.file_exists(g.save_file): DirAccess.remove_absolute(g.save_file)
	print("PASS: close-up contact, finisher, dodge, gun/mage release and equipped-weapon previews.")
	g.queue_free(); await process_frame; quit()

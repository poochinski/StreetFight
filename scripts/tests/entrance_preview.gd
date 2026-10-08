extends SceneTree
var g
func _initialize() -> void: run.call_deferred()
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	g.testing=true
	DirAccess.make_dir_recursive_absolute("res://previews")
	g.save_file="res://previews/entrance-test-save.json"
	if "--smoke-test" in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute("res://previews/entrances")
	g._begin(); g.run_seed=777; g._travel("street",1,"start")
	g.enemies.clear(); g.set_process(false); g.state="play"
	for e in g.exits:
		await shot(e.pos+e.face*2.4, e.get("zone", "subway"))
	g._travel("park",1,"door"); g.enemies.clear(); g.state="play"
	await shot(g.arrivals.door+Vector2(2,0), "park-return")
	g._toggle_panel("quests"); await capture("quests")
	g._toggle_panel("companion"); await capture("companion")
	g._close_panels()
	g._gain_xp(g._xp_needed()); g.level_banner=0
	g._character(); g.spend_point("strength",2); g.spend_point("vitality",3)
	await capture("pending-stats")
	g._activate("settings"); g._activate("save_game")
	await capture("settings-save")
	g._activate("controls"); await capture("controls")
	g._activate("settings_back"); g._activate("restart"); await capture("new-adventure-confirmation")
	g._activate("cancel_new_game"); g._activate("resume")
	g.player.hp = g.player.max_hp*0.2
	g.save_flash = 2.5
	g.notice_time = 0; g.level_banner = 0
	await capture("low-health-save")
	quit()
func shot(at: Vector2, name: String) -> void:
	g.notice_time=0; g.loot_feed.clear()
	g.player.pos=at
	g._reveal(); g.view3d.place_camera(at); g.view3d.sync(0)
	for i in 8: await process_frame
	await capture(name)
func capture(name: String) -> void:
	g.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/entrances/"+name+".png")

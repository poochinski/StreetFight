extends SceneTree
const Models=preload("res://scripts/models.gd")
func _initialize(): call_deferred("run")
func run():
	var models=Models.new()
	for id in ["samurai","gunslinger","synth_mage"]:
		var actor=models.hero(id); root.add_child(actor)
		var clip="2H_Melee_Attack_Slice" if id=="samurai" else "1H_Ranged_Shoot" if id=="gunslinger" else "Spellcast_Shoot"
		Models.CombatAnimator._sample(actor,clip,.445 if id=="samurai" else .30)
		var points=Models.CombatAnimator._points(actor)
		print(id," points=",points," legs=",actor.get_meta("combat_legs"))
		var sk=actor.get_meta("combat_skeleton")
		print("bones: ",PackedStringArray(range(sk.get_bone_count()).map(func(i): return sk.get_bone_name(i))))
		actor.queue_free()
	quit()

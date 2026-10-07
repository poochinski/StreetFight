extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	for model in ["Knight","Rogue_Hooded","Mage"]:
		var n=load("res://assets/models/characters/%s.glb"%model).instantiate()
		root.add_child(n)
		var ap=n.find_children("*","AnimationPlayer",true,false)[0]
		ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		print("MODEL ",model)
		for clip in ap.get_animation_list():
			if "Attack" in clip or "Shoot" in clip or "Spellcast" in clip or "Ranged_Aim" in clip: print(clip," ",ap.get_animation(clip).length)
		for attachment in n.find_children("*","BoneAttachment3D",true,false):
			print("SLOT ",attachment.name," bone=",attachment.bone_name)
			for item in attachment.get_children(): print("  ",item.name," ",item.transform)
		var sk=n.find_children("*","Skeleton3D",true,false)[0]
		var bone=sk.find_bone("handslot.r")
		for clip in (["2H_Melee_Attack_Slice","2H_Melee_Attack_Chop","2H_Melee_Attack_Spin"] if model=="Knight" else ["1H_Ranged_Shoot"] if model=="Rogue_Hooded" else ["Spellcast_Shoot"]):
			ap.play(clip)
			for k in 13:
				var t=ap.get_animation(clip).length*k/12.0
				ap.seek(t,true)
				sk.force_update_all_bone_transforms()
				var x=sk.get_bone_global_pose(bone)
				print("POSE ",clip," t=",snapped(t,.001)," grip=",x.origin," tip=",x*Vector3(0,1,0))
		n.queue_free()
	quit()

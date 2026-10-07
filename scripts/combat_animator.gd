extends RefCounted
const Timing=preload("res://scripts/combat_timing.gd")
const Weapons=preload("res://scripts/combat_weapons.gd")
const Items=preload("res://scripts/items.gd")

static func setup(actor: Node3D) -> void:
	var sk: Skeleton3D=actor.find_children("*","Skeleton3D",true,false)[0]
	actor.set_meta("combat_skeleton",sk)
	actor.get_meta("anim").callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var legs=[]
	for i in sk.get_bone_count():
		var name=sk.get_bone_name(i).to_lower()
		if "upperleg" in name or "lowerleg" in name or "foot" in name or "toe" in name: legs.append(i)
	actor.set_meta("combat_legs",legs)
	actor.set_meta("trail_points",[])
	var trail=MeshInstance3D.new(); trail.name="BladeRibbon"; trail.mesh=ImmediateMesh.new()
	var mat=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.vertex_color_use_as_albedo=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED; mat.no_depth_test=false
	trail.material_override=mat; trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.add_child(trail); actor.set_meta("combat_trail",trail)
	var flash=MeshInstance3D.new(); flash.name="MuzzlePulse"
	var mesh=SphereMesh.new(); mesh.radius=.09; mesh.height=.18; mesh.radial_segments=8; mesh.rings=4; flash.mesh=mesh
	var fm=Weapons.material(Color("ffe7a0"),0,true); fm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override=fm; flash.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; flash.visible=false
	actor.add_child(flash); actor.set_meta("muzzle_flash",flash)
	var socket=BoneAttachment3D.new(); socket.bone_name="handslot.r"; sk.add_child(socket)
	actor.set_meta("combat_socket",socket)

static func equip(actor: Node3D, item) -> void:
	var key=JSON.stringify(item)
	if actor.get_meta("weapon_key","?")==key: return
	actor.set_meta("weapon_key",key)
	var socket: Node3D=actor.get_meta("combat_socket")
	for child in socket.get_children(): socket.remove_child(child); child.queue_free()
	if item==null:
		actor.set_meta("combat_weapon",null)
		return
	var weapon=Weapons.build(actor.get_meta("class"),item)
	weapon.position.y=.0333
	if actor.get_meta("class")=="gunslinger": weapon.rotation.y=PI/2
	elif actor.get_meta("class")=="samurai": weapon.scale=Vector3.ONE*1.35
	socket.add_child(weapon); actor.set_meta("combat_weapon",weapon)

static func _sample(actor: Node3D, clip: String, time: float) -> void:
	var ap: AnimationPlayer=actor.get_meta("anim")
	if ap.current_animation!=clip: ap.play(clip,0.0)
	ap.seek(clampf(time,0,ap.get_animation(clip).length),true)
	actor.set_meta("playing",clip)

static func _points(actor: Node3D) -> Array:
	var weapon=actor.get_meta("combat_weapon",null)
	if not is_instance_valid(weapon): return []
	var sk: Skeleton3D=actor.get_meta("combat_skeleton")
	sk.force_update_all_bone_transforms()
	var transform=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("handslot.r"))*weapon.transform
	return [transform*weapon.get_node("TrailBase").position,transform*weapon.get_node("Tip").position]

static func _moving_legs(actor: Node3D,g) -> void:
	if g.walk_blend<.05: return
	var sk: Skeleton3D=actor.get_meta("combat_skeleton")
	var poses=[]
	for i in sk.get_bone_count(): poses.append(sk.get_bone_pose(i))
	var ap: AnimationPlayer=actor.get_meta("anim")
	var run=ap.get_animation("Running_A")
	var direction=1.0
	if g.screen_velocity.dot(g._iso(Vector2.from_angle(g.display_angle)))<0: direction=-1.0
	_sample(actor,"Running_A",fposmod(g.player.step*.035*direction,run.length))
	var leg_ids: Array=actor.get_meta("combat_legs")
	for i in sk.get_bone_count():
		var pose: Transform3D=poses[i]
		if i in leg_ids: pose=pose.interpolate_with(sk.get_bone_pose(i),clampf(g.walk_blend,0,1))
		sk.set_bone_pose(i,pose)
	sk.force_update_all_bone_transforms()

static func _ribbon(actor: Node3D, dt: float, color: Color) -> void:
	var points: Array=actor.get_meta("trail_points")
	while not points.is_empty() and points[0].life<=0: points.pop_front()
	while points.size()>20: points.pop_front()
	var mesh: ImmediateMesh=actor.get_meta("combat_trail").mesh
	mesh.clear_surfaces()
	if points.size()<2: return
	var inverse=actor.global_transform.affine_inverse()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,points.size()):
		var a=points[i-1]; var b=points[i]
		for pair in [[a,0],[a,1],[b,1],[a,0],[b,1],[b,0]]:
			var point=pair[0]; var edge=int(pair[1])
			mesh.surface_set_color(Color(color,(.015 if edge==0 else .40)*clampf(point.life/.085,0,1)))
			mesh.surface_add_vertex(inverse*point.points[edge])
	mesh.surface_end()

static func pose(actor: Node3D,g,dt: float,models) -> void:
	equip(actor,g._weapon())
	var p=g.player
	var sk: Skeleton3D=actor.get_meta("combat_skeleton")
	var ap: AnimationPlayer=actor.get_meta("anim")
	var model: Node3D=actor.get_meta("model")
	actor.position=Vector3(p.pos.x,0,p.pos.y)
	var angle=float(p.angle) if not g.swing.is_empty() or not p.get("ranged_attack",{}).is_empty() else float(g.display_angle)
	# Contact faces the same direction as the damage cone, not a second slow aim.
	model.rotation.y=PI/2-angle
	var sim=float(g.simulation_delta) if g.state=="play" else dt if g.state in ["title","create"] else 0.0
	var hurt=g.clock-p.get("hurt_at",-9.0)
	actor.get_meta("flash").albedo_color=Color(1,.25,.2,maxf(0,.5-hurt*2.5))
	var trail: Array=actor.get_meta("trail_points")
	for point in trail: point.life-=sim
	if g.state=="defeat":
		models._play(actor,"Death_A",.08); ap.advance(dt)
	elif p.roll>0:
		trail.clear()
		_sample(actor,"Dodge_Forward",ap.get_animation("Dodge_Forward").length*(1-p.roll/g.DODGE_DURATION))
	elif not p.channel.is_empty():
		trail.clear()
		var clip="Dodge_Forward" if p.channel.kind=="dash" else "2H_Melee_Attack_Spinning" if p.channel.kind=="whirlwind" else "1H_Ranged_Shooting"
		models._play(actor,clip,.06,1.5); ap.advance(sim)
	elif not g.swing.is_empty():
		var s: Dictionary=g.swing
		var serial=int(s.serial)
		if actor.get_meta("swing_serial",-1)!=serial:
			actor.set_meta("swing_serial",serial); actor.set_meta("sample_age",0.0); trail.clear()
			var previous=[]
			for i in sk.get_bone_count(): previous.append(sk.get_bone_pose(i))
			actor.set_meta("attack_blend",previous)
		var last=float(actor.get_meta("sample_age",0.0))
		# Intermediate samples preserve a curved ribbon even at 15 FPS.
		var samples=maxi(1,ceili((s.age-last)/.008))
		for i in range(1,samples+1):
			var age=lerpf(last,s.age,float(i)/samples)
			_sample(actor,Timing.CLIPS[int(s.index)],Timing.clip_time(s,age))
			if s.age>last and Timing.trail_active(s,age):
				var pair=_points(actor)
				if not pair.is_empty():
					pair[0]=pair[0].lerp(pair[1],.35)
					trail.append({"points":pair,"life":maxf(.001,.085-(s.age-age))})
		actor.set_meta("sample_age",s.age)
		var weight=clampf(s.age/.035,0,1)
		if weight<1:
			var previous: Array=actor.get_meta("attack_blend")
			for i in sk.get_bone_count(): sk.set_bone_pose(i,previous[i].interpolate_with(sk.get_bone_pose(i),weight))
		_moving_legs(actor,g)
	elif not p.get("ranged_attack",{}).is_empty():
		var r: Dictionary=p.ranged_attack
		var contact=.30 if r.id=="shot" else .31
		var end=.73 if r.id=="shot" else .90
		var time=lerpf(.18 if r.id=="shot" else .12,contact,clampf(r.age/r.fire_at,0,1)) if r.age<r.fire_at else lerpf(contact,end,clampf((r.age-r.fire_at)/(r.duration-r.fire_at),0,1))
		_sample(actor,"1H_Ranged_Shoot" if r.id=="shot" else "Spellcast_Shoot",time)
		_moving_legs(actor,g)
	else:
		var info=models.HEROES[actor.get_meta("class")]
		if g.clock-p.get("cast_at",-9.0)<.5:
			models._play(actor,info.cast,.06,2.4)
		else: models._play(actor,"Running_A" if g.walk_blend>.15 else info.idle,.09,1.15 if g.walk_blend>.15 else 1.0)
		ap.advance(sim)
	var trail_color=Items.weapon_look(g._weapon()).glow
	if g._weapon()!=null and Items.main_element(g._weapon())=="" and int(g._weapon().rarity)<2: trail_color=Color("c9e4ff")
	if not g.swing.is_empty() and g.swing.index==2: trail_color=trail_color.lerp(Color("ffd59c"),.5)
	_ribbon(actor,sim,trail_color)
	var fired=int(p.get("fired_serial",0))
	var flash_time=maxf(0,float(actor.get_meta("flash_time",0.0))-sim)
	if fired!=actor.get_meta("seen_fire",0): flash_time=.045; actor.set_meta("seen_fire",fired)
	actor.set_meta("flash_time",flash_time)
	var pulse: MeshInstance3D=actor.get_meta("muzzle_flash")
	pulse.visible=flash_time>0 and p.roll<=0
	if pulse.visible:
		var points=_points(actor)
		if not points.is_empty(): pulse.global_position=points[1]
		pulse.scale=Vector3.ONE*(.35+flash_time/.045)
		pulse.material_override.albedo_color=Color("c894ff") if p.get("class","")=="synth_mage" else Color("ffe7a0")

extends RefCounted
## Chunky, readable weapons fitted to the existing KayKit hands. Generated in
## Godot; no modular-character assets are used by this combat branch.
const Items=preload("res://scripts/items.gd")

static func material(color: Color, metal: float=0.0, glow: bool=false) -> StandardMaterial3D:
	var m=StandardMaterial3D.new()
	m.albedo_color=color; m.metallic=metal; m.roughness=.35 if metal>0 else .8
	if glow: m.emission_enabled=true; m.emission=color; m.emission_energy_multiplier=.7
	return m

static func part(parent: Node3D, size: Vector3, at: Vector3, mat: Material, round: bool=false) -> MeshInstance3D:
	var node=MeshInstance3D.new()
	if round:
		var mesh=CylinderMesh.new(); mesh.top_radius=size.x; mesh.bottom_radius=size.x; mesh.height=size.y; mesh.radial_segments=10; node.mesh=mesh
	else:
		var mesh=BoxMesh.new(); mesh.size=size; node.mesh=mesh
	node.position=at; node.material_override=mat; parent.add_child(node)
	return node

static func blade(parent: Node3D, outline: Array, face: Color, edge: Color) -> void:
	var st=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center=Vector2.ZERO
	for v in outline: center+=v
	center/=outline.size()
	for side in [-1.0,1.0]:
		for i in outline.size():
			var a: Vector2=outline[i]; var b: Vector2=outline[(i+1)%outline.size()]
			var points=[Vector3(center.x,center.y,.065*side),Vector3(a.x,a.y,0),Vector3(b.x,b.y,0)]
			if side<0: points.reverse()
			for k in 3: st.set_color(face if k==0 else edge); st.add_vertex(points[k])
	st.generate_normals()
	var mesh=MeshInstance3D.new(); mesh.mesh=st.commit()
	var mat=material(Color.WHITE,.45); mat.vertex_color_use_as_albedo=true; mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material_override=mat; parent.add_child(mesh)

static func build(class_id: String, item) -> Node3D:
	var root=Node3D.new(); root.name="EquippedWeapon"
	var look=Items.weapon_look(item)
	var steel=material(look.blade,.65); var dark=material(Color("202b38"),.35)
	var wrap=material(Color("593c37")); var trim=material(Color("c9a45f"),.65)
	var glow=material(look.glow,0.0,true)
	var tip=Marker3D.new(); tip.name="Tip"
	var base=Marker3D.new(); base.name="TrailBase"
	root.add_child(tip); root.add_child(base)
	if class_id=="gunslinger":
		# Barrel points +Z in the native hand-slot coordinates.
		part(root,Vector3(.16,.28,.15),Vector3(0,-.10,0),wrap)
		part(root,Vector3(.24,.17,.38),Vector3(0,.08,.10),dark)
		var barrel=part(root,Vector3(.068,.43,0),Vector3(0,.11,.37),steel,true); barrel.rotation.x=PI/2
		var cylinder=part(root,Vector3(.12,.19,0),Vector3(0,.075,.07),steel,true); cylinder.rotation.x=PI/2
		part(root,Vector3(.055,.035,.27),Vector3(0,.182,.33),dark)
		part(root,Vector3(.034,.045,.035),Vector3(0,.21,.53),trim)
		part(root,Vector3(.02,.055,.14),Vector3(.125,.08,.1),glow)
		var bore=part(root,Vector3(.043,.01,0),Vector3(0,.11,.591),dark,true); bore.rotation.x=PI/2
		tip.position=Vector3(0,.11,.60); base.position=Vector3(0,.11,.15)
	elif class_id=="synth_mage":
		part(root,Vector3(.047,1.7,0),Vector3(0,.10,0),dark,true)
		for y in [-.65,-.14,.1,.70]: part(root,Vector3(.069,.07,0),Vector3(0,y,0),trim,true)
		for side in [-1,1]:
			var prong=part(root,Vector3(.06,.40,.08),Vector3(side*.12,.90,0),steel); prong.rotation.z=side*-.32
		var crystal=part(root,Vector3(.14,.25,.14),Vector3(0,1.01,0),glow); crystal.rotation.z=PI/4
		tip.position=Vector3(0,1.17,0); base.position=Vector3(0,.3,0)
	else:
		var style=look.style
		part(root,Vector3(.055,.32,0),Vector3(0,-.09,0),wrap,true)
		for y in [-.22,-.15,-.08,-.01]: part(root,Vector3(.059,.021,0),Vector3(0,y,0),dark,true)
		part(root,Vector3(.09,.075,0),Vector3(0,-.27,0),trim,true)
		part(root,Vector3(.32,.058,.115),Vector3(0,.10,0),dark)
		part(root,Vector3(.085,.036,.12),Vector3(0,.115,0),glow)
		var outlines={
			"sword":[Vector2(-.075,.14),Vector2(-.075,.84),Vector2(0,1.04),Vector2(.075,.84),Vector2(.075,.14)],
			"great":[Vector2(-.12,.14),Vector2(-.15,1.04),Vector2(0,1.27),Vector2(.15,1.04),Vector2(.12,.14)],
			"katana":[Vector2(-.04,.14),Vector2(-.015,.80),Vector2(.065,1.10),Vector2(.13,1.15),Vector2(.066,.78),Vector2(.045,.14)],
			"saber":[Vector2(-.055,.14),Vector2(-.045,.60),Vector2(.10,1.03),Vector2(.19,1.09),Vector2(.078,.56),Vector2(.06,.14)],
			"cleaver":[Vector2(-.06,.14),Vector2(-.10,.83),Vector2(.19,.97),Vector2(.22,.82),Vector2(.18,.16)],
			"leaf":[Vector2(-.04,.14),Vector2(-.16,.61),Vector2(0,1.06),Vector2(.16,.61),Vector2(.04,.14)]}
		if outlines.has(style):
			blade(root,outlines[style],look.blade,look.edge)
			tip.position=Vector3(0,1.27 if style=="great" else 1.12 if style=="katana" else 1.04,0)
		elif style=="axe":
			part(root,Vector3(.037,.88,0),Vector3(0,.48,0),wrap,true)
			blade(root,[Vector2(-.025,.68),Vector2(-.025,.92),Vector2(.26,1.04),Vector2(.36,.93),Vector2(.33,.60),Vector2(.21,.58)],look.blade,look.edge)
			tip.position=Vector3(.33,.88,0)
		else:
			part(root,Vector3(.044,.65,0),Vector3(0,.44,0),dark,true)
			part(root,Vector3(.17,.30,0),Vector3(0,.80,0),steel,true)
			for i in 4:
				var flange=part(root,Vector3(.40,.23,.045),Vector3(0,.80,0),steel); flange.rotation.y=i*PI/4
			part(root,Vector3(.052,.34,0),Vector3(0,.80,0),glow,true)
			tip.position=Vector3(0,1.0,0)
		base.position=Vector3(0,.24,0)
	return root

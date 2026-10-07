extends RefCounted
## Character art: the hero, its weapons, and every enemy, drawn from layered
## shapes with walk cycles, attack poses and hit/wind-up tints.

const Data = preload("res://scripts/data.gd")
const Items = preload("res://scripts/items.gd")
const SKIN = Color("d9ad86")
const SKIN_SHADE = Color("b98c68")
const LEATHER = Color("4a3426")
const STEEL = Color("9aa5a4")
const STEEL_DARK = Color("5f6a6c")
const STEEL_LIGHT = Color("d8e2df")

var g
var p
var c: CanvasItem
## The equipment of the hero being drawn (helmet, gloves, boots, belt shape the art).
var gear = {}

func _init(game, painter) -> void:
	g = game
	p = painter
	c = game

# --- Hero -------------------------------------------------------------------

## A snapshot of everything needed to draw the hero, so dodge afterimages can redraw it later.
func hero_state() -> Dictionary:
	var player = g.player
	return {"pos":player.pos,"step":player.step,"walk":g.walk_blend,"angle":g.display_angle,
		"roll":1-player.roll/g.DODGE_DURATION if player.roll>0 else 0.0,"lean":g.screen_velocity.x/g.RUN_SPEED,
		"swing":g.swing.duplicate(),"weapon":player.equipment.weapon,"chest":player.equipment.chest,"helmet":player.equipment.helmet,
		"gloves":player.equipment.gloves,"boots":player.equipment.boots,"belt":player.equipment.belt,
		"blink":player.inv>0 and player.roll<=0 and int(g.clock*20)%2==0,
		"class":player.get("class","samurai"),"recoil":player.get("recoil",0.0)}

func swing_visual_angle(swing: Dictionary) -> float:
	var duration = 0.16 if swing.index==2 else 0.12
	var t = clampf(swing.age/duration,0,1)
	var eased = t*t*(3-2*t)
	var side = -1 if swing.index==1 else 1
	return swing.angle+lerpf(-1.25,1.25,eased)*side

## at and zoom draw the hero somewhere else on screen at another size (portraits).
func draw_hero(state: Dictionary,shake_offset: Vector2,ghost: bool = false,at = null,zoom: float = 1.0) -> void:
	var s = at if at!=null else g._project(state.pos)
	if at==null: zoom *= Data.CHARACTER_SCALE
	gear = state
	var look = Items.armor_look(state.chest)
	var facing = g._iso(Vector2.from_angle(state.angle))
	var mirror = -1.0 if facing.x < -0.1 else 1.0
	var facing_back = facing.y < -6
	var walk = state.walk
	var phase = state.step
	var bob = -absf(sin(phase))*2.2*walk
	var breath = sin(g.clock*2.2)*0.6*(1-walk)
	if not ghost:
		p.ellipse(s,16*zoom,6.5*zoom,Color("00000080"),24)
	if state.blink: p.alpha = 0.5
	# The weapon arm is drawn in unmirrored screen space so the blade points where the hero aims.
	var swinging = not state.swing.is_empty()
	var blade_angle = swing_visual_angle(state.swing) if swinging else state.angle-0.35
	var direction = Vector2.from_angle(blade_angle)
	var look_w = Items.weapon_look(state.weapon)
	var rarity = int(state.weapon.rarity) if state.weapon else 0
	var reach = (1.6 if swinging else 1.05)*(1.15 if look_w.style=="great" else 1.0)
	# Gunslingers hold a revolver and Synth Mages a glowing wand, aimed where they look.
	var hero_class: String = state.get("class","samurai")
	if hero_class!="samurai":
		look_w = look_w.duplicate()
		look_w.style = "pistol" if hero_class=="gunslinger" else "wand"
		direction = Vector2.from_angle(state.angle)
		reach = 0.5 if hero_class=="gunslinger" else 0.62
	var grip = g._iso(direction*0.42)-Vector2(0,24)
	var tip = grip+g._iso(direction*reach)*0.82-Vector2(0,4 if swinging else 10)
	if hero_class!="samurai":
		grip = g._iso(direction*0.38)-Vector2(0,26)
		tip = grip+g._iso(direction*reach)*0.82
		var kick = state.get("recoil",0.0)*25
		grip -= g._iso(direction)*0.004*kick*10; tip -= g._iso(direction)*0.01*kick*10-Vector2(0,kick*0.6)
	var behind = (tip-grip).y < -4 and not swinging or facing_back
	var origin = s+shake_offset+Vector2(0,bob)
	if state.roll>0:
		# Dodge roll: the body tucks and tumbles around its middle; the blade is tucked away.
		var pivot = Vector2(0,-20)
		var spin = state.roll*TAU*0.85*mirror
		c.draw_set_transform_matrix(Transform2D(spin,Vector2(mirror,0.85)*zoom,0,origin+pivot*zoom)*Transform2D(0,Vector2.ONE,0,-pivot))
		_hero_body(look,facing_back,phase,walk,breath,true)
		c.draw_set_transform(shake_offset)
		p.alpha = 1
		return
	if behind:
		c.draw_set_transform(origin,0,Vector2.ONE*zoom)
		_hero_weapon_arm(grip,tip,mirror,look,look_w,rarity,swinging)
	c.draw_set_transform(origin,state.lean*0.05,Vector2(mirror,1)*zoom)
	_hero_body(look,facing_back,phase,walk,breath,false)
	if not behind:
		c.draw_set_transform(origin,0,Vector2.ONE*zoom)
		_hero_weapon_arm(grip,tip,mirror,look,look_w,rarity,swinging)
	c.draw_set_transform(shake_offset)
	p.alpha = 1

func _hero_leg(hip: Vector2,swing: float,lift: float,look: Dictionary,front: bool) -> void:
	var knee = hip+Vector2(sin(swing),cos(swing))*9
	var shin = swing-lift
	var foot = knee+Vector2(sin(shin),cos(shin))*9
	var pants = Color("3a4656") if front else Color("2a3340")
	p.limb(hip,knee,5.5,pants,4.8)
	p.limb(knee,foot,4.8,look.shade.darkened(0.25) if front else look.shade.darkened(0.45),4.2)
	var boots = gear.get("boots")
	var boot = Color("5a3d28")
	if boots: boot = Items.material_color(boots,boots.get("style","")=="greaves")
	if not front: boot = boot.darkened(0.35)
	p.poly([foot+Vector2(-3,-3),foot+Vector2(4,-3),foot+Vector2(6.5,0.5),foot+Vector2(-3.5,1)],boot)
	p.line(foot+Vector2(-3,-1),foot+Vector2(5,-1),boot.lightened(0.2),1)
	if boots and int(boots.rarity)>=2: p.line(foot+Vector2(-3,-3),foot+Vector2(4,-3),Items.color(boots),1)

func _hero_body(look: Dictionary,facing_back: bool,phase: float,walk: float,breath: float,tucked: bool) -> void:
	var swing = sin(phase)*0.62*walk
	var lift_front = maxf(0,cos(phase))*0.9*walk
	var lift_back = maxf(0,-cos(phase))*0.9*walk
	var sway = sin(g.clock*3.1)*0.8+walk*4.0
	var cloak = look.cloak
	# Cloak behind the body; it trails further back while running.
	if not facing_back:
		p.poly([[-8,-38],[5,-39],[2,-28],[-3-sway*0.3,-7],[-15-sway,-5+absf(sin(phase))*2],[-13-sway*0.6,-24]],cloak.darkened(0.35))
	# Back leg and back arm.
	if not tucked: _hero_leg(Vector2(-3,-20),-swing,lift_back,look,false)
	else: p.limb(Vector2(-3,-20),Vector2(4,-12),5,Color("1f2731"))
	var back_hand = Vector2(-7,-36)+Vector2(sin(-swing*0.9)*5-2,12)
	p.limb(Vector2(-7,-36),back_hand,4.5,look.shade.darkened(0.2),4)
	p.circle(back_hand,2.4,_hand_color())
	# Torso: plate, shaded flank, highlight and tabard.
	var chest = -breath
	p.poly([[-8,-38+chest],[7,-39+chest],[9,-30],[8,-21],[-8,-21],[-9,-30]],look.plate)
	p.poly([[-8,-38+chest],[-3,-38+chest],[-4,-21],[-8,-21],[-9,-30]],look.shade)
	p.line(Vector2(5,-37+chest),Vector2(7.5,-27),look.plate.lightened(0.35),1.2)
	if not facing_back:
		p.poly([[-1.5,-37+chest],[3.5,-37+chest],[4.5,-19],[1,-15],[-2.5,-19]],cloak)
		p.line(Vector2(-1.5,-37+chest),Vector2(-2.5,-19),look.trim,1)
		p.line(Vector2(3.5,-37+chest),Vector2(4.5,-19),look.trim,1)
		p.poly([[1,-31],[2.5,-29],[1,-27],[-0.5,-29]],look.trim)
	# Belt with buckle, then segmented tassets.
	p.poly([[-9,-23],[9,-23],[9,-20],[-9,-20]],LEATHER)
	var belt = gear.get("belt")
	p.poly([[-1,-23.5],[2.5,-23.5],[2.5,-19.5],[-1,-19.5]],Items.color(belt) if belt and int(belt.rarity)>0 else look.trim)
	if belt and belt.get("style","")=="sash": p.poly([[2,-21],[5,-13],[3,-12.5],[1,-20]],Data.NEON_PURPLE.darkened(0.2))
	p.poly([[-9.5,-20],[9.5,-20],[10.5,-14],[-10.5,-14]],look.shade)
	for x in [-5,0,5]: p.line(Vector2(x,-20),Vector2(x*1.08,-14),look.shade.darkened(0.35),1)
	# Front leg.
	if not tucked: _hero_leg(Vector2(3,-20),swing,lift_front,look,true)
	else: p.limb(Vector2(3,-20),Vector2(9,-14),5.5,Color("2a3340"))
	# Pauldrons.
	p.ellipse(Vector2(-7,-36+chest),5,4,look.shade.lightened(0.05),16)
	p.ellipse(Vector2(6.5,-36.5+chest),5.5,4.2,look.plate.lightened(0.12),16)
	p.ellipse_arc(Vector2(6.5,-36.5+chest),5.5,4.2,PI*1.05,PI*1.9,look.trim,1)
	# Head: bare with a headband, or the equipped helmet.
	var head = Vector2(1,-46+chest)
	p.limb(Vector2(0.5,-40+chest),head+Vector2(0,3),4,SKIN_SHADE)
	_hero_head(head,facing_back,walk)
	if facing_back:
		# Seen from behind, the cloak covers the back.
		p.poly([[-9,-38],[8,-39],[9,-30],[6-sway*0.2,-8],[-11-sway,-6],[-11,-24]],cloak)
		p.poly([[-9,-38],[8,-39],[7,-34],[-8,-33]],cloak.lightened(0.15))
		p.line(Vector2(6-sway*0.2,-8),Vector2(-11-sway,-6),look.trim,1.2)

func _hand_color() -> Color:
	var gloves = gear.get("gloves")
	if gloves==null: return SKIN_SHADE
	return Items.material_color(gloves,gloves.get("style","")=="gauntlets")

func _hero_head(head: Vector2,facing_back: bool,walk: float) -> void:
	var helmet = gear.get("helmet")
	var style = helmet.get("style","helm") if helmet else "none"
	var steel = Items.material_color(helmet,true) if helmet else STEEL
	var trim = Items.color(helmet) if helmet and int(helmet.rarity)>=2 else Color("c9a45c")
	var wave = sin(g.clock*5)*1.2+walk*2.5
	if style=="none":
		var hair = Color("3a2418")
		if facing_back:
			p.circle(head,6,hair)
		else:
			p.circle(head+Vector2(0.5,0.5),5.6,SKIN)
			p.poly([head+Vector2(-6.5,1),head+Vector2(-6,-5),head+Vector2(-1,-8.5),head+Vector2(5,-7.5),head+Vector2(7,-3),head+Vector2(3,-4.5),head+Vector2(-2,-3.5),head+Vector2(-4,2)],hair)
			p.circle(head+Vector2(3,0.5),0.9,Color("232628"))
		# A neon headband with tails that stream behind while running.
		p.line(head+Vector2(-6.2,-3.5),head+Vector2(6.4,-3.5),Data.NEON_PINK,1.8)
		p.poly([head+Vector2(-6,-4.5),head+Vector2(-11-wave,-5+wave*0.4),head+Vector2(-10-wave,-2.5+wave*0.6),head+Vector2(-6,-2.5)],Data.NEON_PINK.darkened(0.15))
		return
	if style=="coif":
		p.circle(head+Vector2(0,1),7,steel.darkened(0.15))
		p.poly([head+Vector2(-7,1),head+Vector2(7,1),head+Vector2(8,7),head+Vector2(-8,7)],steel.darkened(0.25))
		for k in 5: p.circle(head+Vector2(-5+k*2.5,-3+(k%2)),0.6,steel.lightened(0.3))
		if not facing_back:
			p.ellipse(head+Vector2(1.5,1.5),3.8,4.4,SKIN,14)
			p.circle(head+Vector2(3,1),0.8,Color("232628"))
		return
	if style=="visor":
		p.circle(head,6.4,steel.lightened(0.2))
		p.poly([head+Vector2(-1.2,-6),head+Vector2(1.2,-6),head+Vector2(0.5,-11),head+Vector2(-0.5,-11)],trim)
		if not facing_back:
			p.poly([head+Vector2(-5.5,-1.5),head+Vector2(7,-1.5),head+Vector2(6.5,1.8),head+Vector2(-5,1.8)],Color("12081e"))
			p.line(head+Vector2(-4.5,0.2),head+Vector2(6,0.2),Data.NEON_CYAN,1.4)
			p.glow(head+Vector2(1,0),9,Color(Data.NEON_CYAN,0.35))
		p.ellipse_arc(head,6.4,6.4,PI*1.1,PI*1.6,Color(1,1,1,0.6),1)
		return
	# A steel helm with nose guard and a plume (rarity colored on better helms).
	var plume = trim if helmet and int(helmet.rarity)>=2 else Color("b23b35")
	if facing_back:
		p.circle(head,6.2,steel.darkened(0.3))
		p.poly([head+Vector2(-6,-1),head+Vector2(-5,-7),head+Vector2(1,-10),head+Vector2(7,-7),head+Vector2(6.5,1),head+Vector2(0,4)],steel)
		p.line(head+Vector2(-5,-2),head+Vector2(6,-2),steel.darkened(0.3),1.4)
	else:
		p.circle(head+Vector2(0.5,0.5),5.6,SKIN)
		p.poly([head+Vector2(-6.5,0),head+Vector2(-5.5,-6.5),head+Vector2(1,-10),head+Vector2(7.5,-6.5),head+Vector2(7.5,-1),head+Vector2(-1,-2.5)],steel)
		p.poly([head+Vector2(-6.5,0),head+Vector2(-5.5,-6.5),head+Vector2(-2,-8.5),head+Vector2(-3,-1.5)],steel.darkened(0.3))
		p.line(head+Vector2(-6,-1.5),head+Vector2(7.5,-1.5),steel.lightened(0.35),1)
		p.poly([head+Vector2(4,-2),head+Vector2(5.5,-2),head+Vector2(5,4),head+Vector2(4,4)],steel.darkened(0.3))
		p.circle(head+Vector2(3,1),0.9,Color("232628"))
		p.poly([head+Vector2(-6.5,0),head+Vector2(-3,-1),head+Vector2(-3.5,5),head+Vector2(-6,4)],steel.darkened(0.3))
	var top = head+Vector2(0,2.5)
	p.poly([top+Vector2(-1,-9.5),top+Vector2(3,-11),top+Vector2(-4-wave,-12),top+Vector2(-12-wave*1.6,-7),top+Vector2(-9-wave,-5),top+Vector2(-4,-7.5)],plume)
	p.poly([top+Vector2(-1,-9.5),top+Vector2(-6-wave,-10.5),top+Vector2(-11-wave*1.6,-7)],plume.lightened(0.2))

func _hero_weapon_arm(grip: Vector2,tip: Vector2,mirror: float,look: Dictionary,look_w: Dictionary,rarity: int,swinging: bool) -> void:
	var shoulder = Vector2(6*mirror,-36)
	var elbow = shoulder.lerp(grip,0.5)+Vector2(0,4)
	p.limb(shoulder,elbow,4.6,look.plate)
	p.limb(elbow,grip,4.2,look.shade)
	if look_w.style=="pistol": _revolver(grip,tip,look_w,rarity)
	elif look_w.style=="wand": _wand(grip,tip,rarity)
	elif look_w.style!="none": draw_weapon(grip,tip,look_w,rarity,swinging)
	var hand = _hand_color()
	p.circle(grip,2.8,hand)
	p.circle(grip+Vector2(-0.6,-0.6),1.2,hand.lightened(0.25))

func draw_weapon(grip: Vector2,tip: Vector2,look: Dictionary,rarity: int,swinging: bool) -> void:
	var span = tip-grip
	var length = span.length()
	if length<2: return
	var u = span/length
	var n = u.orthogonal()
	var base = grip+u*3
	# Handle and pommel.
	p.limb(grip-u*7,grip+u*2,3,Color("5a3b26"))
	for i in 3: p.line(grip-u*(5-i*2.5)+n*1.5,grip-u*(5-i*2.5)-n*1.5,Color("8a6440"),0.8)
	p.circle(grip-u*8,2.3,Color("c9a45c"))
	if rarity>=1: p.glow(grip.lerp(tip,0.6),14+rarity*4,Color(look.glow,0.18+rarity*0.05))
	match look.style:
		"axe":
			p.limb(base-u*2,tip+u*1,2.6,Color("5a3b26"))
			var head_at = base.lerp(tip,0.8)
			p.poly([head_at-u*4+n*1.5,head_at+u*4+n*1.5,head_at+u*7+n*9,head_at+n*11,head_at-u*7+n*9],look.blade)
			p.ellipse_arc(head_at+n*6,7.5,7.5,n.angle()-1.0,n.angle()+1.0,look.edge,1.3)
			p.poly([head_at-u*2-n*1.5,head_at+u*2-n*1.5,head_at-n*5],look.blade.darkened(0.3))
			p.circle(head_at,1.6,Color("c9a45c"))
		"mace":
			p.limb(base-u*2,tip-u*5,2.8,Color("5a3b26"))
			var ball = tip-u*3
			for k in 6:
				var spike = Vector2.from_angle(k*TAU/6+u.angle())
				p.poly([ball+spike.orthogonal()*2.2,ball+spike*8.5,ball-spike.orthogonal()*2.2],look.edge)
			p.circle(ball,5.2,look.blade)
			p.circle(ball+(n-u)*1.5,1.8,look.blade.lightened(0.35))
			p.line(base.lerp(tip,0.35)+n*1.6,base.lerp(tip,0.35)-n*1.6,Color("c9a45c"),1.5)
		"katana":
			p.ellipse(base,3.4,3.4,Color("2a2235"),12)
			p.ellipse_arc(base,3.4,3.4,0,TAU,Color("c9a45c"),1)
			var spine = PackedVector2Array()
			var cutting = PackedVector2Array()
			for i in 9:
				var t = i/8.0
				var center = base.lerp(tip+u*3,t)+n*sin(t*PI*0.5)*2.6
				var width = lerpf(1.7,0.2,t*t)
				spine.append(center+n*width); cutting.append(center-n*width)
			var outline: Array = []
			for v in spine: outline.append(v)
			for i in range(cutting.size()-1,-1,-1): outline.append(cutting[i])
			p.poly(outline,look.blade)
			for i in range(1,cutting.size()): p.line(cutting[i-1],cutting[i],look.edge,0.9)
			p.line(base.lerp(tip,0.15),base.lerp(tip,0.7),Color(look.glow,0.6),0.8)
		"cleaver":
			p.limb(base-n*5,base+n*5,2.6,Color("4b5154"))
			p.poly([base-n*1.5,tip-n*1.5,tip+n*3,tip-u*3+n*8,base+u*5+n*7.5,base+n*2],look.blade)
			p.line(base-n*1.5,tip-n*1.5,look.blade.darkened(0.35),1.6)
			p.line(base+u*5+n*7.5,tip-u*3+n*8,look.edge,1.2)
			p.circle(base+u*7+n*3,1.2,Color("4b5154"))
		"leaf":
			p.limb(base-n*6,base+n*6,2.4,Color("b9a34e"))
			p.circle(base-n*6,1.8,Color("6fbf63")); p.circle(base+n*6,1.8,Color("6fbf63"))
			var mid = base.lerp(tip,0.5)
			p.poly([base+n*1.8,mid+n*4.6,tip,mid-n*4.6,base-n*1.8],look.blade)
			p.poly([base+n*1.8,mid+n*4.6,tip,mid],look.blade.lightened(0.12))
			p.line(base,tip-u*2,look.edge,1)
			for i in 3:
				var vein = base.lerp(tip,0.3+i*0.18)
				p.line(vein,vein+(u+n)*2.5,look.edge,0.7)
		"saber":
			p.limb(base-n*4,base+n*5,2.2,Color("cfe8f5"))
			p.ellipse_arc(base,5,5,PI*0.2,PI*1.1,Color("cfe8f5"),1.2)
			var upper = PackedVector2Array()
			var lower = PackedVector2Array()
			for i in 9:
				var t = i/8.0
				var center = base.lerp(tip,t)-n*sin(t*PI)*4.5*(1 if t<1 else 0)
				var width = lerpf(2.6,0.3,t)
				upper.append(center+n*width); lower.append(center-n*width)
			var outline: Array = []
			for v in upper: outline.append(v)
			for i in range(lower.size()-1,-1,-1): outline.append(lower[i])
			p.poly(outline,look.blade)
			for i in range(1,upper.size()): p.line(upper[i-1],upper[i],look.edge,1)
			var sparkle = base.lerp(tip,fposmod(g.clock*0.9,1.0))
			p.circle(sparkle,1.1,Color(1,1,1,0.9))
		"great":
			var far = tip+u*4
			p.limb(base-n*8,base+n*8,3.2,Color("2a2235"))
			p.poly([base-n*8,base-n*11+u*2,base-n*7+u*1],Color("2a2235"))
			p.poly([base+n*8,base+n*11+u*2,base+n*7+u*1],Color("2a2235"))
			p.poly([base+n*3.6,far-u*7+n*3.4,far,far-u*7-n*3.4,base-n*3.6],look.blade)
			p.line(base+n*3.6,far-u*7+n*3.4,look.edge,1.3)
			p.line(base-n*3.6,far-u*7-n*3.4,look.edge,1.3)
			for i in 3:
				var rune = base.lerp(far,0.25+i*0.2)
				p.circle(rune,1.1+sin(g.clock*6+i)*0.3,look.edge)
			p.glow(base.lerp(far,0.5),22,Color(look.glow,0.25))
		_:
			p.limb(base-n*7,base+n*7,2.6,Color("c9a45c"))
			p.circle(base-n*7,1.6,Color("e3c27a")); p.circle(base+n*7,1.6,Color("e3c27a"))
			p.poly([base+n*2.3,tip-u*6+n*2,tip,tip-u*6-n*2,base-n*2.3],look.blade)
			p.poly([base+n*2.3,tip-u*6+n*2,tip,base],look.blade.lightened(0.15))
			p.line(base+u*2,base.lerp(tip,0.62),look.blade.darkened(0.3),1)
			p.line(base+n*0.9,tip,look.edge,0.9)
	if swinging: p.glow(tip,10,Color(look.glow,0.35))

func _revolver(grip: Vector2,tip: Vector2,look: Dictionary,rarity: int) -> void:
	var span = tip-grip
	if span.length()<2: return
	var u = span.normalized()
	var n = u.orthogonal()
	if n.y>0: n = -n
	# Grip, cylinder, barrel and a little muzzle flash right after a shot.
	p.poly([grip-n*1.5-u*1,grip-n*1.5+u*3,grip-n*8+u*1,grip-n*8-u*3],Color("6a4430"))
	p.limb(grip+u*1,tip,3.2,Color("b8bcc8"),2.6)
	p.line(grip+u*2+n*1.2,tip+n*1.2,Color("e8ecf4"),1)
	p.circle(grip+u*3.5,3.4,Color("8a8e98"))
	if rarity>=1: p.glow(grip.lerp(tip,0.5),10+rarity*3,Color(Data.RARITY_COLORS[rarity],0.2))
	if g.player.get("recoil",0.0)>0.07:
		p.glow(tip+u*4,16,Color(1,0.85,0.4,0.8))
		p.poly([tip,tip+u*9+n*3,tip+u*12,tip+u*9-n*3],Color("fff0b0"))

func _wand(grip: Vector2,tip: Vector2,rarity: int) -> void:
	var color: Color = Color("c86bff")
	p.limb(grip-(tip-grip)*0.3,tip,2.2,Color("2a2236"))
	p.line(grip,tip,Color("8a8e98"),0.8)
	var pulse = 0.7+0.3*sin(g.clock*6)
	p.glow(tip,18+rarity*4,Color(color,0.55*pulse))
	p.circle(tip,3.6,color.lightened(0.3))
	p.circle(tip,1.6,Color.WHITE)

## The arc of light left by a swing, tinted by the equipped weapon.
func draw_swing_trail(swing: Dictionary) -> void:
	if g.view3d: return
	if swing.is_empty(): return
	var t = swing.age/swing.duration
	if t<0.03 or t>0.95: return
	var look = Items.weapon_look(g._weapon())
	if look.style=="none": look.glow = Color("e9f4da")
	var current = swing_visual_angle(swing)
	var side = -1 if swing.index==1 else 1
	var origin = g._project(g.player.pos,24)
	var finisher = swing.index==2
	var color = look.glow.lerp(Color("ffb35c"),0.55) if finisher else look.glow
	var outer = 1.85 if finisher else 1.7
	var inner = 0.95
	var arc = 1.25 if finisher else 1.0
	var fade = sin(clampf(t,0,1)*PI)
	var steps = 14
	for i in steps:
		var a0 = current-side*arc*(i/float(steps))
		var a1 = current-side*arc*((i+1)/float(steps))
		var k = 1-i/float(steps)
		var quad = PackedVector2Array([origin+g._iso(Vector2.from_angle(a0)*outer),origin+g._iso(Vector2.from_angle(a1)*outer),
			origin+g._iso(Vector2.from_angle(a1)*lerpf(outer,inner,k)),origin+g._iso(Vector2.from_angle(a0)*lerpf(outer,inner,k))])
		c.draw_colored_polygon(quad,Color(color,0.42*k*fade))
	var edge = PackedVector2Array()
	for i in steps+1: edge.append(origin+g._iso(Vector2.from_angle(current-side*arc*(i/float(steps)))*outer))
	c.draw_polyline(edge,Color(Color.WHITE,0.75*fade),2.0,true)
	p.glow(origin+g._iso(Vector2.from_angle(current)*outer),18,Color(color,0.5*fade))

# --- Enemies ----------------------------------------------------------------

func draw_enemy(e: Dictionary,shake_offset: Vector2,fade: float = 1.0,sink: float = 0.0) -> void:
	var s = g._project(e.pos)
	var stats = Data.ENEMIES[e.kind]
	var size = Data.CHARACTER_SCALE
	var to_hero = g._iso(g.player.pos-e.pos)
	var mirror = -1.0 if to_hero.x<0 else 1.0
	var charge = 0.0
	if e.windup>0 and e.windup_total>0: charge = 1-e.windup/e.windup_total
	var moving = e.get("moving",0.0)
	var step = e.get("step",0.0)
	var bob = sin(g.clock*4+e.phase)*1.2*(1-moving)+sink
	if fade>=1.0: p.ellipse(s,15*stats.scale*size,6*stats.scale*size,Color("00000077"),24)
	if e.kind=="ranged" and charge>0: _rune_circle(s,charge)
	if e.kind=="boss" and e.windup>0: _slam_warning(s,charge)
	elif e.kind!="ranged" and e.kind!="boss" and charge>0:
		var reach = stats.reach+0.25
		p.ellipse_arc(s,reach*45,reach*23,0,TAU,Color(1,0.42,0.3,0.2+charge*0.5),1.5+charge*1.5)
	p.alpha = fade
	if e.hit>0:
		p.tint_color = Color("fff1d6"); p.tint_amount = clampf(e.hit/0.15,0,1)*0.85
	elif charge>0 and e.kind!="boss":
		p.tint_color = Color("ff5a3c"); p.tint_amount = charge*0.35
	elif e.get("chill",0.0)>0:
		p.tint_color = Items.ELEMENT_COLORS.ice; p.tint_amount = 0.4
	elif e.get("poison",0.0)>0:
		p.tint_color = Items.ELEMENT_COLORS.poison; p.tint_amount = 0.25
	c.draw_set_transform(s+shake_offset+Vector2(0,bob),0,Vector2(mirror,1)*size)
	match e.kind:
		"imp": _imp(step,moving,charge)
		"brute": _brute(step,moving,charge)
		"ranged": _caster(step,moving,charge)
		_: _warden(step,moving,charge)
	c.draw_set_transform(shake_offset)
	p.tint_amount = 0
	p.alpha = 1
	if fade<1.0: return
	var bar_y = {"imp":-40.0,"brute":-74.0,"ranged":-64.0}.get(e.kind,0.0)*size
	if e.hp<e.max_hp and e.kind!="boss":
		c.draw_rect(Rect2(s+Vector2(-17,bar_y),Vector2(34,4)),Color("06121bd0"))
		c.draw_rect(Rect2(s+Vector2(-16,bar_y+1),Vector2(32*e.hp/e.max_hp,2)),Color("d6735c"))

func _imp(step: float,moving: float,charge: float) -> void:
	var skin = Color("9b4a3a")
	var dark = Color("6a2c24")
	var belly = Color("c8775a")
	var crouch = charge*3
	var stride = sin(step*1.6)*0.8*moving
	# Tail whips behind.
	var tail: Array = [Vector2(-5,-11+crouch)]
	for i in 4: tail.append(tail[i]+Vector2(-3.5,sin(g.clock*6+i*1.3)*2.2-1.2))
	for i in 4: p.limb(tail[i],tail[i+1],2.6-i*0.45,dark)
	var tip = tail[4]
	p.poly([tip+Vector2(0,-3),tip+Vector2(-4,0),tip+Vector2(0,3),tip+Vector2(1,0)],dark)
	# Digitigrade legs.
	for side in [-1,1]:
		var hip = Vector2(side*2.5,-10+crouch)
		var swing = stride*side
		var knee = hip+Vector2(3+sin(swing)*3,4)
		var ankle = knee+Vector2(-3+sin(swing)*2,4.5-crouch*0.3)
		var color = dark if side<0 else skin
		p.limb(hip,knee,3.2,color,2.6)
		p.limb(knee,ankle,2.6,color,2)
		p.poly([ankle+Vector2(-1,-1),ankle+Vector2(4,0),ankle+Vector2(3.5,1.5),ankle+Vector2(-1,1.5)],dark.darkened(0.2))
	# Hunched body.
	p.poly([[-6,-12+crouch],[-5,-20+crouch],[1,-24+crouch],[7,-19+crouch],[6,-11+crouch],[0,-9+crouch]],skin)
	p.poly([[1,-20+crouch],[6,-18+crouch],[5,-12+crouch],[1,-11+crouch]],belly)
	for i in 3: p.line(Vector2(-4+i*1.5,-21+crouch+i),Vector2(-1+i*1.5,-22+crouch+i),dark,0.8)
	# Arms: claws drawn back during a wind-up.
	var hand = Vector2(10,-13+crouch).lerp(Vector2(-3,-28),charge)
	p.limb(Vector2(4,-19+crouch),hand,2.6,skin,2.1)
	for k in 3: p.line(hand,hand+Vector2(3,-1.5+k*1.5).rotated(-charge*1.8),Color("eadcc0"),0.9)
	# Head with horns, ears and glowing eyes.
	var head = Vector2(5,-26+crouch*1.2)
	p.poly([head+Vector2(-3,-2),head+Vector2(-11,-6),head+Vector2(-4,1)],dark)
	p.circle(head,5.6,skin)
	p.poly([head+Vector2(-1,-4),head+Vector2(-2,-10),head+Vector2(1.5,-5)],Color("e7d3a8"))
	p.poly([head+Vector2(3,-4.5),head+Vector2(5,-10.5),head+Vector2(5,-4)],Color("e7d3a8"))
	p.glow(head+Vector2(3,-0.5),7,Color("ffd54a55"))
	p.circle(head+Vector2(2,-0.5),1.1,Color("ffe27a"))
	p.circle(head+Vector2(4.6,-0.8),1.1,Color("ffe27a"))
	p.line(head+Vector2(1,2.8),head+Vector2(5.5,2.2),Color("2a0f0b"),1)
	p.line(head+Vector2(2.5,2.6),head+Vector2(2.8,3.6),Color.WHITE,0.7)
	p.line(head+Vector2(4.2,2.4),head+Vector2(4.4,3.4),Color.WHITE,0.7)

func _brute(step: float,moving: float,charge: float) -> void:
	var skin = Color("7c8a64")
	var shade = Color("56623f")
	var iron = Color("4a4f55")
	var stride = sin(step)*0.42*moving
	for side in [-1,1]:
		var hip = Vector2(side*6,-22)
		var knee = hip+Vector2(sin(stride*side)*10,10)
		var foot = knee+Vector2(sin(stride*side)*4,10)
		var color = shade if side<0 else skin
		p.limb(hip,knee,8,color,7)
		p.limb(knee,foot,7,Color("4d3b2c") if side>0 else Color("3a2c21"),6.5)
		p.poly([foot+Vector2(-5,-3),foot+Vector2(7,-3),foot+Vector2(8,1.5),foot+Vector2(-5,1.5)],Color("2e231b"))
	# Back arm.
	p.limb(Vector2(-12,-46),Vector2(-16,-26),7,shade,6)
	p.circle(Vector2(-16,-25),4,shade)
	# Loincloth and torso.
	p.poly([[-10,-24],[10,-24],[7,-11],[-6,-12]],Color("6b4a32"))
	p.poly([[-14,-48],[14,-50],[17,-32],[11,-21],[-11,-21],[-16,-33]],skin)
	p.poly([[-14,-48],[-6,-49],[-7,-21],[-11,-21],[-16,-33]],shade)
	p.poly([[2,-37],[12,-38],[11,-25],[3,-24]],skin.lightened(0.1))
	p.line(Vector2(-2,-44),Vector2(4,-38),Color("4a3a2e"),1.2)
	p.line(Vector2(6,-42),Vector2(10,-45),Color("4a3a2e"),1.2)
	p.limb(Vector2(-13,-46),Vector2(13,-24),2.4,Color("3a3a3e"))
	# Iron pauldron with spikes on the back shoulder.
	p.poly([[-19,-46],[-13,-54],[-4,-52],[-5,-43],[-15,-40]],iron)
	p.line(Vector2(-17,-45),Vector2(-6,-46),iron.lightened(0.3),1)
	for x in [-15,-9]: p.poly([[x,-51],[x+2,-60],[x+4,-52]],Color("8a8f94"))
	# Small head with tusks and red eyes.
	var head = Vector2(5,-55)
	p.circle(head,7,skin)
	p.poly([head+Vector2(-6,-2),head+Vector2(7,-4),head+Vector2(7,-1),head+Vector2(-6,1)],shade)
	p.glow(head+Vector2(4,-1),7,Color("ff4a3a55"))
	p.circle(head+Vector2(3,-1.5),1.1,Color("ff6a4a"))
	p.circle(head+Vector2(6,-1.8),1.0,Color("ff6a4a"))
	p.poly([head+Vector2(2,3),head+Vector2(3,-1),head+Vector2(4,3.5)],Color("f1e6c8"))
	p.poly([head+Vector2(6,3),head+Vector2(7.5,-0.5),head+Vector2(7.6,3.6)],Color("f1e6c8"))
	# Front arm and spiked club: raised overhead through the wind-up.
	var angle = lerpf(1.25,-2.35,charge*charge*(3-2*charge))
	var shoulder = Vector2(11,-45)
	var dir = Vector2.from_angle(angle)
	var hand = shoulder+dir*17
	p.limb(shoulder,shoulder+dir*9+Vector2(0,2),7.5,skin,6.5)
	p.limb(shoulder+dir*9+Vector2(0,2),hand,6.5,skin,5.5)
	var club_tip = hand+dir*28
	p.limb(hand-dir*3,club_tip,4.5,Color("6b4a2f"),10)
	p.limb(hand+dir*12,hand+dir*13.5,7.5,iron)
	for i in 3:
		var stud = hand+dir*(17+i*4)+dir.orthogonal()*(4 if i%2==0 else -4)
		p.poly([stud,stud+dir.orthogonal()*(3 if i%2==0 else -3)+dir*1,stud+dir*2],Color("a8adb2"))
	p.circle(hand,4,skin.darkened(0.1))

func _caster(step: float,moving: float,charge: float) -> void:
	var robe = Color("3d3352")
	var robe_dark = Color("2a2340")
	var trim = Color("c9a45c")
	var float_y = sin(g.clock*2.4)*1.5-2
	# Staff behind the far hand.
	var staff_base = Vector2(13,-1+float_y)
	var staff_top = Vector2(14,-54+float_y)
	p.limb(staff_base,staff_top,2.6,Color("5b4a35"))
	p.poly([staff_top+Vector2(-3,2),staff_top+Vector2(-4,-6),staff_top+Vector2(0,-2)],Color("8a7a5a"))
	p.poly([staff_top+Vector2(3,2),staff_top+Vector2(4,-6),staff_top+Vector2(0,-2)],Color("8a7a5a"))
	var orb = staff_top+Vector2(0,-4)
	p.glow(orb,14+charge*24,Color(0.72,0.96,0.6,0.35+charge*0.4))
	p.circle(orb,3.6+charge*2.4,Color("b8f59a"))
	p.circle(orb+Vector2(-1,-1),1.4+charge,Color("efffe6"))
	# Robe with a rippling hem.
	var hem: Array = []
	for i in 7:
		var x = lerpf(13,-13,i/6.0)
		hem.append(Vector2(x,-1+float_y+sin(g.clock*4+i*1.1)*1.4+sin(step+i)*moving))
	var body: Array = [Vector2(-4,-41+float_y),Vector2(5,-41+float_y)]
	body.append_array(hem)
	p.poly(body,robe)
	p.poly([Vector2(-4,-41+float_y),Vector2(0,-41+float_y),hem[5],hem[6]],robe_dark)
	for i in range(1,hem.size()): p.line(hem[i-1]+Vector2(0,-1.5),hem[i]+Vector2(0,-1.5),trim,1.2)
	p.line(Vector2(1,-38+float_y),Vector2(2,-2+float_y),trim,1)
	p.poly([Vector2(-1,-30+float_y),Vector2(2.5,-27+float_y),Vector2(-1,-24+float_y),Vector2(-4,-27+float_y)],Color("7fd06a"))
	# Sleeve reaching to the staff.
	p.limb(Vector2(4,-35+float_y),Vector2(12,-31+float_y),5,robe,6)
	p.circle(Vector2(13,-31+float_y),2.2,Color("8e8aa0"))
	# Peaked hood with a shadowed face and green eyes.
	var hood = Vector2(2,-45+float_y)
	p.poly([hood+Vector2(-8,6),hood+Vector2(-6,-6),hood+Vector2(-2,-12),hood+Vector2(4,-10),hood+Vector2(8,-2),hood+Vector2(7,6)],robe_dark)
	p.ellipse(hood+Vector2(2.5,0.5),4.2,4.8,Color("0d0a12"),16)
	p.glow(hood+Vector2(3,0),6+charge*4,Color(0.6,1,0.5,0.45))
	p.circle(hood+Vector2(1.5,0),0.9,Color("b8f59a"))
	p.circle(hood+Vector2(4.2,0),0.9,Color("b8f59a"))

func _warden(step: float,moving: float,charge: float) -> void:
	var plate = Color("2b2428")
	var plate_light = Color("4a3d42")
	var lava = Color("ff7a3a")
	var pulse = 0.55+sin(g.clock*3)*0.25+charge*0.4
	var stride = sin(step*0.8)*0.3*moving
	for side in [-1,1]:
		var hip = Vector2(side*12,-40)
		var knee = hip+Vector2(sin(stride*side)*14,19)
		var foot = knee+Vector2(sin(stride*side)*4,20)
		p.limb(hip,knee,15,plate if side>0 else plate.darkened(0.3),13)
		p.limb(knee,foot,13,plate_light if side>0 else plate,12)
		p.circle(knee,7,plate_light)
		p.poly([foot+Vector2(-9,-5),foot+Vector2(12,-5),foot+Vector2(14,2),foot+Vector2(-9,2)],Color("1d181b"))
		p.line(hip+Vector2(0,4),knee,Color(lava,pulse*0.6),1.5)
	# Back arm.
	p.limb(Vector2(-26,-88),Vector2(-32,-56),13,plate.darkened(0.3),11)
	p.circle(Vector2(-32,-54),8,plate.darkened(0.2))
	# Torso plates with glowing seams and an ember core.
	p.poly([[-28,-92],[26,-95],[33,-64],[21,-40],[-21,-40],[-31,-64]],plate)
	p.poly([[-28,-92],[-10,-94],[-12,-40],[-21,-40],[-31,-64]],plate.darkened(0.35))
	p.poly([[-2,-88],[22,-90],[26,-66],[2,-62]],plate_light)
	for seam in [[Vector2(-20,-80),Vector2(-6,-60),Vector2(-14,-44)],[Vector2(12,-60),Vector2(18,-48),Vector2(8,-42)],[Vector2(-2,-88),Vector2(2,-62)]]:
		for i in range(1,seam.size()): p.line(seam[i-1],seam[i],Color(lava,pulse),2)
	p.glow(Vector2(4,-70),28+charge*20,Color(1,0.6,0.25,0.4+charge*0.3))
	p.circle(Vector2(4,-70),7+charge*2,Color("ffb054"))
	p.circle(Vector2(4,-70),3.5,Color("fff0c0"))
	# Huge pauldrons with spikes.
	p.poly([[-38,-90],[-26,-104],[-10,-100],[-12,-84],[-32,-78]],plate_light)
	p.poly([[14,-100],[32,-104],[40,-88],[32,-80],[14,-84]],plate_light)
	for spike in [Vector2(-30,-100),Vector2(-20,-102),Vector2(24,-102),Vector2(34,-98)]:
		p.poly([spike+Vector2(-3,2),spike+Vector2(0,-12),spike+Vector2(3,2)],Color("d9c9a8"))
	# Horned helm with a burning visor.
	var head = Vector2(6,-108)
	p.poly([head+Vector2(-11,6),head+Vector2(-10,-8),head+Vector2(0,-14),head+Vector2(12,-9),head+Vector2(13,6),head+Vector2(0,10)],plate)
	p.poly([head+Vector2(-9,-6),head+Vector2(-24,-20),head+Vector2(-20,-28),head+Vector2(-14,-12)],Color("d9c9a8"))
	p.poly([head+Vector2(9,-8),head+Vector2(16,-18),head+Vector2(21,-31),head+Vector2(19,-15),head+Vector2(14,-10)],Color("e8dcc0"))
	p.glow(head+Vector2(3,-1),16,Color(1,0.5,0.2,0.5*pulse))
	p.poly([head+Vector2(-6,-2),head+Vector2(12,-3),head+Vector2(11,0),head+Vector2(-6,1)],Color("ffcf7a"))
	# Hammer arm: raised overhead during the slam wind-up.
	var angle = lerpf(1.45,-2.55,charge*charge*(3-2*charge))
	var shoulder = Vector2(26,-88)
	var dir = Vector2.from_angle(angle)
	var hand = shoulder+dir*30
	p.limb(shoulder,shoulder+dir*16,13,plate,12)
	p.limb(shoulder+dir*16,hand,12,plate_light,11)
	var haft_end = hand+dir*44
	p.limb(hand-dir*10,haft_end,5,Color("2a2226"))
	var n = dir.orthogonal()
	var head_center = haft_end
	p.poly([head_center+n*14-dir*9,head_center+n*14+dir*9,head_center-n*14+dir*9,head_center-n*14-dir*9],Color("3a3035"))
	p.poly([head_center+n*14-dir*9,head_center+n*14+dir*9,head_center+n*4+dir*9,head_center+n*4-dir*9],Color("54474d"))
	p.line(head_center-n*10,head_center+n*10,Color(lava,pulse),2)
	p.glow(head_center,18,Color(1,0.5,0.2,0.25*pulse))
	p.circle(hand,7,plate_light)
	# Embers drifting off the armor.
	for i in 6:
		var t = fposmod(g.clock*0.6+i*0.17,1.0)
		var ember = Vector2(-20+i*8+sin(g.clock+i)*4,-50-t*60)
		p.circle(ember,1.4*(1-t)+0.4,Color(1,0.6+0.3*(1-t),0.3,1-t))

func _rune_circle(s: Vector2,charge: float) -> void:
	var color = Color(0.7,1,0.55,0.25+charge*0.6)
	p.ellipse_arc(s,22,11,0,TAU,color,1.6)
	p.ellipse_arc(s,16,8,0,TAU,Color(color,color.a*0.6),1)
	for i in 6:
		var a = g.clock*1.8+i*TAU/6
		p.circle(s+Vector2(cos(a)*19,sin(a)*9.5),1.4,color)

func _slam_warning(s: Vector2,charge: float) -> void:
	var r = Data.BOSS_SLAM_RADIUS
	var flicker = 0.5+sin(g.clock*16)*0.2
	p.ellipse(s,r*45,r*23,Color(1,0.3,0.15,0.06+charge*0.12),48)
	p.ellipse_arc(s,r*45,r*23,0,TAU,Color(1,0.45,0.29,flicker),3)
	p.ellipse_arc(s,r*45*charge,r*23*charge,0,TAU,Color(1,0.7,0.4,0.6),2)
	p.glow(s,90,Color("ff643c35"))

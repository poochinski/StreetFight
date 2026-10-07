extends RefCounted
## One simulation timeline for input, damage, animation contact and blade trails.
const PERIODS = [0.30,0.28,0.38]
const CONTACTS = [0.085,0.075,0.12]
const ACTIVE_END = [0.15,0.14,0.21]
const CLIPS = ["2H_Melee_Attack_Slice","2H_Melee_Attack_Slice","2H_Melee_Attack_Chop"]
const POSES = [[0.28,0.445,0.68,1.10],[0.68,0.445,0.28,0.0],[0.55,0.82,1.03,1.6333]]

static func clip_time(swing: Dictionary, age: float = -1.0) -> float:
	var i=int(swing.index)
	var t=(swing.age if age<0 else age)*swing.get("speed",1.0)
	var points=POSES[i]
	if t<CONTACTS[i]: return lerpf(points[0],points[1],clampf(t/CONTACTS[i],0,1))
	if t<ACTIVE_END[i]: return lerpf(points[1],points[2],(t-CONTACTS[i])/(ACTIVE_END[i]-CONTACTS[i]))
	return lerpf(points[2],points[3],clampf((t-ACTIVE_END[i])/(PERIODS[i]-ACTIVE_END[i]),0,1))

static func trail_active(swing: Dictionary, age: float) -> bool:
	var t=age*swing.get("speed",1.0)
	return t>=CONTACTS[int(swing.index)]*.60 and t<=ACTIVE_END[int(swing.index)]

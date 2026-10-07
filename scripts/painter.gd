extends RefCounted
## Drawing primitives shared by the world and HUD views. Calls are made on the
## game's CanvasItem during its _draw().

const Data = preload("res://scripts/data.gd")

var canvas: CanvasItem
var alpha = 1.0
## Everything drawn while tint_amount > 0 is blended toward tint_color (hit flashes, wind-up glow, ghosts).
var tint_color = Color.WHITE
var tint_amount = 0.0
var serif = SystemFont.new()
var sans = SystemFont.new()
var background: GradientTexture2D
var glow_texture: GradientTexture2D
var vignette: GradientTexture2D
var footer_gradient: GradientTexture2D
var header_gradient: GradientTexture2D
var title_gradient: GradientTexture2D

func _init(target: CanvasItem) -> void:
	canvas = target
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	sans.font_names = PackedStringArray(["Segoe UI", "Arial"])
	background = _gradient([Color("1c1430"),Color("07060e")],true,Vector2(0.55,0.4),Vector2(1.1,1))
	glow_texture = _gradient([Color.WHITE,Color(1,1,1,0)],true)
	vignette = _gradient([Color(0,0,0,0),Color("04090cb0")],true,Vector2(0.5,0.5),Vector2(1.2,1.2),[0.38,1.0])
	footer_gradient = _gradient([Color("080e1600"),Color("080e16f5")],false,Vector2.ZERO,Vector2(0,1),[0.0,0.6])
	header_gradient = _gradient([Color("080e16dc"),Color("080e1600")],false,Vector2.ZERO,Vector2(0,1))
	title_gradient = _gradient([Color("07111aee"),Color("0a1421c9"),Color("0a162532")],false,Vector2.ZERO,Vector2.RIGHT,[0.0,0.4,1.0])

func _gradient(colors: Array, radial: bool, start: Vector2 = Vector2(0.5,0.5), end: Vector2 = Vector2(1,0.5), offsets: Array = []) -> GradientTexture2D:
	var texture = GradientTexture2D.new()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray(colors)
	if not offsets.is_empty(): gradient.offsets = PackedFloat32Array(offsets)
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	texture.fill_from = start
	texture.fill_to = end
	return texture

func ink(color: Color) -> Color:
	var result = color
	if tint_amount>0: result = Color(color.r,color.g,color.b).lerp(tint_color,tint_amount)
	return Color(result,color.a*alpha)

func poly(points: Array,color: Color,outline: Color = Color.TRANSPARENT) -> void:
	var vertices = PackedVector2Array()
	for point in points:
		vertices.append(point if point is Vector2 else Vector2(point[0],point[1]))
	canvas.draw_colored_polygon(vertices,ink(color))
	if outline.a>0:
		vertices.append(vertices[0])
		canvas.draw_polyline(vertices,ink(outline),1,true)

func ellipse(point: Vector2,rx: float,ry: float,color: Color,segments: int = 48) -> void:
	var vertices = PackedVector2Array()
	for i in segments: vertices.append(point+Vector2(cos(i*TAU/segments)*rx,sin(i*TAU/segments)*ry))
	canvas.draw_colored_polygon(vertices,ink(color))

func circle(point: Vector2,radius: float,color: Color) -> void:
	ellipse(point,radius,radius,color,maxi(10,int(radius*2.5)))

## A rounded limb segment: a quad with circular caps, used for arms, legs and tails.
func limb(a: Vector2,b: Vector2,width_a: float,color: Color,width_b: float = -1.0) -> void:
	if width_b<0: width_b = width_a
	var direction = b-a
	if direction.length()<0.01: direction = Vector2.DOWN*0.01
	var n = direction.normalized().orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([a+n*width_a/2,b+n*width_b/2,b-n*width_b/2,a-n*width_a/2]),ink(color))
	circle(a,width_a/2,color)
	circle(b,width_b/2,color)

func line(a: Vector2,b: Vector2,color: Color,width: float = 1.0) -> void:
	canvas.draw_line(a,b,ink(color),width,true)

func ellipse_arc(point: Vector2,rx: float,ry: float,start: float,end: float,color: Color,width: float = 2) -> void:
	var vertices = PackedVector2Array()
	for i in 49:
		var angle = lerpf(start,end,i/48.0)
		vertices.append(point+Vector2(cos(angle)*rx,sin(angle)*ry))
	canvas.draw_polyline(vertices,ink(color),width,true)

func glow(point: Vector2,radius: float,color: Color) -> void:
	canvas.draw_texture_rect(glow_texture,Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2),false,ink(color))

func block(point: Vector2,width: float,height: float,color: Color,side: Color = Color("24313b"),top: Color = Color("475960")) -> void:
	var x = point.x; var y = point.y; var w = width; var h = height
	poly([[x,y-h],[x+w,y-h-w/2],[x,y-h-w],[x-w,y-h-w/2]],top)
	poly([[x-w,y-h-w/2],[x,y-h],[x,y],[x-w,y-w/2]],side)
	poly([[x,y-h],[x+w,y-h-w/2],[x+w,y-w/2],[x,y]],color)

func text(value: String,point: Vector2,size: int = 12,color: Color = Data.CREAM,heading: bool = false) -> void:
	var font = serif if heading else sans
	canvas.draw_string(font,point+Vector2(0,font.get_ascent(size)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,ink(color))

func center(value: String,point: Vector2,size: int = 12,color: Color = Data.CREAM,heading: bool = false) -> void:
	var font = serif if heading else sans
	text(value,point-Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/2,0),size,color,heading)

func right(value: String,point: Vector2,size: int = 12,color: Color = Data.CREAM) -> void:
	text(value,point-Vector2(sans.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x,0),size,color)

func text_width(value: String,size: int) -> float:
	return sans.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x

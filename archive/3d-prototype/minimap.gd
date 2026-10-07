extends Control

var game: Node

func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	if not is_instance_valid(game) or game.cells.is_empty():
		return
	var unit = 3.5
	var origin = Vector2(16, 24)
	for cell in game.discovered:
		if game.cells.has(cell):
			draw_rect(Rect2(origin + Vector2(cell) * unit, Vector2.ONE * 3), Color("526b73"))
	if game.discovered.has(Vector2i(game.stairs.x, game.stairs.z)):
		draw_circle(origin + Vector2(game.stairs.x, game.stairs.z) * unit, 3, Color("7bd7c6"))
	for enemy in game.enemies:
		if enemy.hp > 0 and enemy.node.position.distance_to(game.hero.position) < 7:
			draw_circle(origin + Vector2(enemy.node.position.x, enemy.node.position.z) * unit, 1.8, Color("db8864"))
	var p = game.hero.position
	draw_circle(origin + Vector2(p.x, p.z) * unit, 3, Color("ffe3a2"))

func _background() -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.035, 0.065, 0.09, 0.88)
	box.border_color = Color("756b5055")
	box.set_border_width_all(1)
	return box

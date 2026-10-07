extends Node2D
## Screen-space layer for the HUD and menus, drawn above the zoomed world.

var game

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game: game.draw_screen_layer(self)

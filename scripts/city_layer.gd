extends Node2D
## One cached piece of the city drawing: the ground or the buildings of an
## 8x8-cell chunk, the street markings and light pools, or the backdrop.
## Godot keeps what it drew until queue_redraw, so a chunk is only redrawn
## when part of it is newly revealed.

var view
var chunk = Vector2i.ZERO
var layer = ""

func _draw() -> void:
	if view: view.draw_layer(self,chunk,layer)

class_name ArenaTerrain
extends Node2D

## Canvas commands survive across frames. Only changed terrain redraws.
var walls: Dictionary = {}
var obstacles: Dictionary = {}
var dimensions := Vector2i.ZERO

func sync(w: WorldSnapshot) -> void:
	if walls != w.walls or obstacles != w.obstacles or dimensions != Vector2i(w.width, w.height):
		dimensions = Vector2i(w.width, w.height)
		walls = w.walls.duplicate()
		obstacles = w.obstacles.duplicate()
		queue_redraw()

func _draw() -> void:
	var cs := float(GridConfig.CELL)
	var field := Vector2(dimensions) * cs
	draw_rect(Rect2(Vector2.ZERO, field), Color(0.60, 0.60, 0.60))
	for y in dimensions.y:
		for x in dimensions.x:
			if (x + y) % 2 == 0:
				draw_rect(Rect2(Vector2(x, y) * cs, Vector2(cs, cs)), Color(0.65, 0.65, 0.65))
	draw_rect(Rect2(Vector2(3, 3), field - Vector2(6, 6)), Color(0.18, 0.18, 0.18), false, 5.0)
	for cell: Vector2i in walls:
		draw_rect(Rect2(Vector2(cell) * cs + Vector2.ONE * 2, Vector2.ONE * (cs - 4)), Color(0.25, 0.26, 0.28))
	for cell: Vector2i in obstacles:
		var rect := Rect2(Vector2(cell) * cs + Vector2.ONE * 2, Vector2.ONE * (cs - 4))
		draw_rect(rect, Color(0.34, 0.39, 0.43))
		draw_line(rect.position, rect.end, Color(0.60, 0.65, 0.68), 2.0)

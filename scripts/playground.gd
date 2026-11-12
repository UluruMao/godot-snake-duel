class_name Playground
extends Node2D

var bean_cell := Vector2i(-1, -1)
var beans: Dictionary = {}
var walls: Dictionary = {}
var items: Dictionary = {}
var mines: Dictionary = {}
var moving_pickups: Dictionary = {}
var obstacles: Dictionary = {}
var enemy_previews: Dictionary = {} # Remains empty: snake entrances have no spatial warning.
var tick := 0
var alpha := 1.0
var dimensions := Vector2i(GridConfig.W, GridConfig.H)

var _pulse := 0.0
var _terrain: ArenaTerrain

func _ready() -> void:
	_terrain = ArenaTerrain.new()
	_terrain.show_behind_parent = true
	add_child(_terrain)


func sync(world: WorldSnapshot, fraction := 1.0) -> void:
	bean_cell = world.food
	dimensions = Vector2i(world.width, world.height)
	beans = world.beans
	walls = world.walls
	items = world.items
	mines = world.mines
	moving_pickups = world.moving_pickups
	obstacles = world.obstacles
	tick = world.tick
	alpha = fraction
	_terrain.sync(world)


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var cs := float(GridConfig.CELL)
	for cell: Vector2i in items:
		_draw_item(cell, items[cell], cs)
	for mine: MineState in mines.values():
		var center := mine.previous.lerp(mine.position, alpha) * cs
		if tick < mine.activation_tick:
			var brightness := 0.35 + 0.55 * absf(sin(tick * 0.3))
			draw_rect(Rect2(center - Vector2.ONE * cs, Vector2.ONE * cs * 2), Color(1.0, 0.45, 0.15, brightness), false, 2.5)
			draw_line(center - Vector2(7, 0), center + Vector2(7, 0), Color(0.5, 0.1, 0.1), 2)
		else:
			_draw_mine(center, cs)
	for item: MovingPickup in moving_pickups.values():
		var center := item.previous.lerp(item.position, alpha) * cs
		var half := item.half_size() * cs
		draw_rect(Rect2(center - Vector2.ONE * half, Vector2.ONE * half * 2), Color(0.2, 0.2, 0.2, 0.12), false, 1.0)
		if item.kind == PickupRules.DIAMOND:
			var points := PackedVector2Array([center + Vector2(0, -half), center + Vector2(half, 0), center + Vector2(0, half), center + Vector2(-half, 0)])
			draw_colored_polygon(points, Color(0.1, 0.85, 0.72))
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0.04, 0.3, 0.35), 2.0, true)
			draw_line(points[0], points[2], Color(0.7, 1, 1), 1.5)
		else:
			draw_circle(center, cs * 0.74, Color(0.28, 0.12, 0.4))
			draw_circle(center + Vector2(-7, -8), cs * 0.2, Color(0.72, 0.44, 0.9))
			draw_polyline(PackedVector2Array([center + Vector2(10, -23), center + Vector2(18, -32), center + Vector2(27, -25)]), Color(0.5, 0.4, 0.12), 4.0, true)
			draw_circle(center + Vector2(27, -25), 4, Color(1, 0.65, 0.1))
	for cell: Vector2i in beans:
		var center := Vector2(cell) * cs + Vector2(cs, cs) * 0.5
		var r := cs * (0.30 + 0.05 * sin(_pulse * 6.0))
		var pts := PackedVector2Array([
			center + Vector2(0, -r), center + Vector2(r, 0),
			center + Vector2(0, r), center + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0.93, 0.93, 0.93))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(0.2, 0.2, 0.2), 2.0, true)

func _draw_item(cell: Vector2i, kind: String, cs: float) -> void:
	var size := PickupRules.item_size(kind)
	var center := Vector2(cell) * cs + Vector2.ONE * cs * size * 0.5
	if kind == ItemRules.STAR:
		draw_rect(Rect2(Vector2(cell) * cs, Vector2.ONE * cs * size), Color(1, 0.75, 0.1, 0.2), false, 1.5)
		var points := PackedVector2Array()
		for i in 10:
			var angle := -PI / 2.0 + i * PI / 5.0
			points.append(center + Vector2.from_angle(angle) * (cs * 0.9 if i % 2 == 0 else cs * 0.4))
		draw_colored_polygon(points, Color(1.0, 0.82, 0.12))
		points.append(points[0])
		draw_polyline(points, Color(0.45, 0.26, 0.02), 1.8, true)
	else:
		var up := kind == ItemRules.SPEED_UP
		var color := Color(0.12, 0.72, 0.30) if up else Color(0.85, 0.18, 0.16)
		draw_rect(Rect2(center - Vector2.ONE * 13, Vector2.ONE * 26), color)
		draw_rect(Rect2(center - Vector2.ONE * 13, Vector2.ONE * 26), Color(0.2, 0.2, 0.2), false, 2)
		var sign_y := -1.0 if up else 1.0
		for offset in [-3.0, 5.0]:
			draw_polyline(PackedVector2Array([center + Vector2(-7, -sign_y * 3 + offset), center + Vector2(0, sign_y * 4 + offset), center + Vector2(7, -sign_y * 3 + offset)]), Color(0.97, 1.0, 0.94), 2.5, true)

func _draw_mine(center: Vector2, cs: float) -> void:
	draw_rect(Rect2(center - Vector2.ONE * cs, Vector2.ONE * cs * 2), Color(0.7, 0.1, 0.2, 0.14), false, 1.5)
	for i in 8:
		var arm := Vector2.from_angle(i * TAU / 8.0 + tick * 0.03)
		draw_line(center + arm * cs * 0.65, center + arm * cs * MineRules.RADIUS, Color(0.30, 0.08, 0.12), 5, true)
	draw_circle(center, cs * 0.72, Color(0.64, 0.15, 0.24))
	draw_circle(center, 3, Color(1.0, 0.62, 0.48))

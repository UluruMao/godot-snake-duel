class_name SnakePlayer
extends Node2D

## Input and presentation only. SnakeSimulation owns all gameplay movement.
var controlled := false
var body_color := Color(0.13, 0.13, 0.13)
var model: SnakeState
var _previous: Array[Vector2i] = []
var _turn_queue: Array[Vector2i] = []
var _fraction := 1.0
var _known_moves := -1
var _star := false
var _combat := false

static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * GridConfig.CELL + Vector2.ONE * GridConfig.CELL * 0.5

func reset() -> void:
	model = null
	_previous.clear()
	_turn_queue.clear()
	_known_moves = -1
	_star = false
	_combat = false
	modulate.a = 1.0

func sync(s: SnakeState, alpha: float, frozen := false, star := false, combat := false) -> void:
	_star = star
	_combat = combat
	if s.moves != _known_moves:
		_previous.assign(model.cells if model != null else s.cells)
		_known_moves = s.moves
	model = s
	_fraction = clampf((s.period - s.remaining + alpha) / s.period, 0.0, 1.0)
	if frozen or s.chance_ticks > 0 or s.moves == 0:
		_previous.assign(s.cells)
		_fraction = 1.0
	if s.chance_ticks > 0:
		modulate.a = 0.45 + 0.55 * absf(sin(s.chance_ticks * 0.36))
	else:
		modulate.a = 1.0
	queue_redraw()

func clear_turns() -> void:
	_turn_queue.clear()

func _input(event: InputEvent) -> void:
	if not controlled or model == null or not model.alive or not is_visible_in_tree():
		return
	if GameControls.is_plain_press(event):
		var direction := Vector2i.ZERO
		match event.keycode:
			KEY_UP, KEY_W: direction = Vector2i.UP
			KEY_DOWN, KEY_S: direction = Vector2i.DOWN
			KEY_LEFT, KEY_A: direction = Vector2i.LEFT
			KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
		var last: Vector2i = _turn_queue[-1] if not _turn_queue.is_empty() else model.direction
		if direction != Vector2i.ZERO and direction != last and direction != -last and _turn_queue.size() < 2:
			_turn_queue.append(direction)

func take_turn() -> Vector2i:
	if not _turn_queue.is_empty():
		return _turn_queue.pop_front()
	return model.direction

func _draw() -> void:
	if model == null or model.cells.is_empty():
		return
	var cs := float(GridConfig.CELL)
	if _previous.is_empty() or _previous[0] == model.cells[0]:
		for cell in model.cells:
			draw_rect(Rect2(Vector2(cell) * cs, Vector2.ONE * cs), body_color)
	else:
		for i in _previous.size():
			var top_left := Vector2(_previous[i]) * cs
			if i == _previous.size() - 1 and model.cells.size() == _previous.size() and _previous.size() > 1:
				_partial(top_left, Vector2(_previous[i] - _previous[i - 1]), 1.0 - _fraction)
			else:
				draw_rect(Rect2(top_left, Vector2.ONE * cs), body_color)
		_partial(Vector2(model.cells[0]) * cs, Vector2(model.direction), _fraction)
	var head := cell_center(_previous[0]).lerp(cell_center(model.cells[0]), _fraction)
	var forward := Vector2(model.direction)
	var side := Vector2(-forward.y, forward.x)
	if model.is_player and model.boosting:
		draw_arc(head, cs * 0.38, 0, TAU, 24, Color(0.2, 0.75, 1.0), 2.5, true)
	if _star:
		for cell in model.cells:
			draw_rect(Rect2(Vector2(cell) * cs + Vector2.ONE * 2, Vector2.ONE * (cs - 4)), Color(1.0, 0.82, 0.12, 0.8), false, 3.0)
	if _combat:
		draw_arc(head, cs * 0.43, 0, TAU, 24, Color(1.0, 0.32, 0.08), 3.0, true)
	for sign_value in [-1, 1]:
		draw_circle(head + forward * 7.0 + side * 7.0 * sign_value, 2.3, Color(0.95, 0.95, 0.95))

func _partial(top_left: Vector2, grow_dir: Vector2, fraction: float) -> void:
	var cs := float(GridConfig.CELL)
	var rect := Rect2(top_left, Vector2.ONE * cs)
	if grow_dir.x != 0:
		rect.size.x *= fraction
		if grow_dir.x < 0:
			rect.position.x += cs * (1.0 - fraction)
	else:
		rect.size.y *= fraction
		if grow_dir.y < 0:
			rect.position.y += cs * (1.0 - fraction)
	draw_rect(rect, body_color)

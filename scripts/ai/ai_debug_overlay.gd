class_name AIDebugOverlay
extends Node2D

signal enemy_chosen(id: String)
signal planner_chosen(value: int)
signal action_requested(key: int)

var world: WorldSnapshot
var decision: AIDecision
var selected := "purple"
var _label: Label
var _scroll: ScrollContainer
var _details: Label
var _legend: Label
var _details_scroll: ScrollContainer
var _enemy_picker: OptionButton
var _planner_picker: OptionButton
var _mine_button: Button
var _diamond_button: Button
var _text_due := 0
var _text_decision: AIDecision
var _text_selected := ""
var _roster_key := ""

static func board_scale(w: WorldSnapshot) -> float:
	return UILayout.board_rect(w, true).size.x / (w.width * GridConfig.CELL)

func _ready() -> void:
	z_index = 20
	var panel := PanelContainer.new()
	panel.position = UILayout.INSPECTOR.position
	panel.size = UILayout.INSPECTOR.size
	panel.theme = UIStyle.theme()
	panel.add_theme_stylebox_override("panel", UIStyle.box())
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(UIStyle.pixel_label("AI INSPECTOR", 2, UIStyle.ACCENT))
	_enemy_picker = OptionButton.new()
	_enemy_picker.focus_mode = Control.FOCUS_NONE
	_enemy_picker.custom_minimum_size.y = 42
	_enemy_picker.item_selected.connect(func(index: int): enemy_chosen.emit(String(_enemy_picker.get_item_metadata(index))))
	column.add_child(_enemy_picker)
	_planner_picker = OptionButton.new()
	_planner_picker.focus_mode = Control.FOCUS_NONE
	_planner_picker.custom_minimum_size.y = 40
	for name in ["BFS baseline", "Safety collector", "Purple planning", "Red tactics", "Golden evasion"]: _planner_picker.add_item(name)
	_planner_picker.item_selected.connect(func(index: int): planner_chosen.emit(index))
	column.add_child(_planner_picker)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_label = UIStyle.label("", 17)
	_label.custom_minimum_size.x = 330
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll.add_child(_label)
	var policies := HBoxContainer.new()
	policies.add_theme_constant_override("separation", 8)
	column.add_child(policies)
	_mine_button = UIStyle.button("Mine forecast", true)
	_mine_button.pressed.connect(func(): action_requested.emit(KEY_F9))
	policies.add_child(_mine_button)
	_diamond_button = UIStyle.button("Diamond plans", true)
	_diamond_button.pressed.connect(func(): action_requested.emit(KEY_F10))
	policies.add_child(_diamond_button)
	var more := UIStyle.button("More diagnostics", true)
	more.toggle_mode = true
	more.toggled.connect(func(value: bool): _details_scroll.visible = value)
	column.add_child(more)
	_details_scroll = ScrollContainer.new()
	_details_scroll.custom_minimum_size.y = 132
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details_scroll.visible = false
	column.add_child(_details_scroll)
	_details = UIStyle.label("", 15, UIStyle.MUTED)
	_details.custom_minimum_size.x = 330
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_scroll.add_child(_details)
	_legend = UIStyle.label("Yellow: route   Blue: reachable\nCyan: opponent forecasts", 13, UIStyle.MUTED)
	column.add_child(_legend)

func refresh(w: WorldSnapshot, d: AIDecision, id: String, _caption: String, active_profile: EnemyProfile = null) -> void:
	world = w
	decision = d if w.snakes.has(id) and w.snakes[id].alive else null
	selected = id
	queue_redraw()
	var now := Time.get_ticks_msec()
	if now < _text_due and d == _text_decision and id == _text_selected: return
	_text_due = now + 100
	_text_decision = d
	_text_selected = id
	var ids: Array[String] = []
	for actor: SnakeState in w.snakes.values():
		if not actor.is_player: ids.append(actor.id)
	var roster_key := str(ids)
	if roster_key != _roster_key:
		_roster_key = roster_key
		_enemy_picker.clear()
		for actor_id in ids:
			_enemy_picker.add_item(actor_id.capitalize().replace("_", " "))
			_enemy_picker.set_item_metadata(_enemy_picker.item_count - 1, actor_id)
		if ids.is_empty():
			_enemy_picker.add_item("Awaiting enemy")
			_enemy_picker.set_item_metadata(0, "player")
	if ids.has(id): _enemy_picker.select(ids.find(id))
	_enemy_picker.disabled = ids.is_empty()
	_planner_picker.disabled = active_profile == null or not w.snakes.has(id) or not w.snakes[id].alive
	if active_profile != null: _planner_picker.select(active_profile.planner)
	_mine_button.visible = active_profile != null and not w.mines.is_empty()
	_diamond_button.visible = active_profile != null and w.snakes.has(id) and EnemySpawnRules.kind(w.snakes[id]) == "purple" and not w.moving_pickups.is_empty()
	if active_profile != null:
		_mine_button.text = "Forecast: " + ("On" if active_profile.mine_prediction else "Off")
		_diamond_button.text = "Diamonds: " + ("On" if active_profile.diamond_planning else "Off")
	var lines := ""
	if w.snakes.has(id):
		var s: SnakeState = w.snakes[id]
		lines = "Length %d  ·  %.2f cells/s" % [s.cells.size(), 50.0 / s.period]
		if s.entry_remaining > 0: lines += "\nEntering: %d / %d segments inside" % [s.cells.size() - s.entry_remaining, s.cells.size()]
	if decision != null:
		var reason := decision.reason.get_slice(" (rival reaction", 0).get_slice(" (search budget", 0)
		lines += "\n\n" + decision.behavior.replace("_", " ") + "\n" + reason + "\n"
		var area := decision.reachable.size()
		lines += "\nTarget %s   ·   Reach %d" % [str(decision.target), area]
		lines += "\n\nMOVE OPTIONS"
		for c in decision.candidates:
			lines += "\n" + _direction_name(c.direction)
			if not c.legal: lines += "  blocked · " + String(c.rejection)
			elif not c.get("evaluated", true): lines += "  not evaluated · plan already safe"
			elif String(c.rejection).begins_with("food rejected"): lines += "  %d cells · food unsafe" % c.area
			else: lines += "  %d cells · risk %.2f" % [c.area, c.threat]
		if decision.exhausted: lines += "\n\nBudget reached · survival fallback"
		_label.tooltip_text = decision.reason
	elif w.snakes.has(id) and not w.snakes[id].alive:
		lines += "\n\nELIMINATED: " + w.snakes[id].death_reason
	else:
		lines += "\n\nWaiting for a movement decision"
	_label.text = lines
	_legend.text = "Yellow: route   Blue: %s\nCyan: opponent forecasts" % ("plan area" if decision != null and decision.planning_status == "early plan validated" else "checked space")
	var detail := "Tick %d · %.2fs\nBeans %d · Mines %d · Obstacles %d\nQueued drops %d" % [w.tick, w.tick * 0.02, w.beans.size(), w.mines.size(), w.obstacles.size(), w.pending_drops.size()]
	if decision != null:
		detail += "\nPlanning: %s\nSource %d · validated %d\nSafety %d · strategy %d nodes" % [decision.planning_status, decision.planning_source_tick, decision.validated_tick, decision.safety_expansions, decision.strategic_expansions]
		if decision.validated_tick >= 0: detail += "\nSafety %.2f ms · strategy %.2f ms%s" % [decision.duration_usec / 1000.0, decision.strategic_duration_usec / 1000.0, " (truncated)" if decision.strategy_exhausted else ""]
		detail += "\n%d expansions / 8192 · %.2f ms\nReaction %.2fs · Mine forecast %s" % [decision.expansions, decision.duration_usec / 1000.0, decision.opponent_reaction_ticks * 0.02, "on" if decision.mine_prediction else "off"]
		for c in decision.candidates:
			detail += "\n%s: exits %d, utility %.2f" % [_direction_name(c.direction), c.continuations, c.utility]
			if c.rejection != "": detail += "\n" + String(c.rejection)
	if active_profile != null: detail += "\nBounty Base ×%d" % active_profile.reward_multiplier
	_details.text = detail

static func _direction_name(d: Vector2i) -> String:
	if d == Vector2i.UP: return "↑ UP"
	if d == Vector2i.DOWN: return "↓ DOWN"
	if d == Vector2i.LEFT: return "← LEFT"
	return "→ RIGHT"

func _draw() -> void:
	if world == null:
		return
	var board := UILayout.board_rect(world, true)
	draw_set_transform(board.position, 0.0, Vector2.ONE * board_scale(world))
	for mine: MineState in world.mines.values():
		draw_rect(Rect2((mine.position - Vector2.ONE * MineRules.RADIUS) * GridConfig.CELL, Vector2.ONE * MineRules.RADIUS * 2 * GridConfig.CELL), Color(1, 0.35, 0.4, 0.8), false, 1.5)
	for actor: SnakeState in world.snakes.values():
		if actor.alive:
			draw_circle(MineRules.center(actor.cells[0]) * GridConfig.CELL, MineRules.HEAD_RADIUS * GridConfig.CELL, Color(0.2, 0.8, 1, 0.8), false, 1.5, true)
	if decision != null:
		for trace: Dictionary in decision.mine_traces:
			var previous := Vector2.ZERO
			for i in trace.points.size():
				var point: Dictionary = trace.points[i]
				var position: Vector2 = point.position * GridConfig.CELL
				if i > 0:
					draw_line(previous, position, Color(0.9, 0.2, 0.6, 0.8), 2.0, true)
					draw_circle(position, 3, Color(0.9, 0.2, 0.6))
					if i == 1 or i == trace.points.size() - 1:
						var label_position: Vector2 = Vector2(trace.points[0].position) * GridConfig.CELL + Vector2(36, -38 if i == 1 else 14)
						draw_line(position, label_position + Vector2(-3, -4), Color(0.7, 0.15, 0.45, 0.7), 1.0, true)
						draw_string(ThemeDB.fallback_font, label_position, "#%d +%.1fs" % [trace.id, (int(point.tick) - decision.snapshot_tick) * 0.02], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.05, 0.3))
				previous = position
		for cell in decision.reachable:
			draw_rect(Rect2(Vector2(cell) * GridConfig.CELL + Vector2.ONE * 3, Vector2.ONE * (GridConfig.CELL - 6)), Color(0.4, 0.65, 1.0, 0.10))
		for path: Array in decision.predicted_paths:
			for i in range(1, path.size()):
				var start := SnakePlayer.cell_center(path[i - 1])
				var end := SnakePlayer.cell_center(path[i])
				for dash in 3:
					draw_line(start.lerp(end, dash / 3.0), start.lerp(end, dash / 3.0 + 0.16), Color(0.05, 0.65, 0.95, 0.9), 2.5, true)
		if decision.path.size() > 1:
			var points := PackedVector2Array()
			for cell in decision.path:
				points.append(SnakePlayer.cell_center(cell))
			draw_polyline(points, Color(0.9, 0.85, 0.25, 0.85), 3.0, true)
		if world.snakes.has(selected):
			var head := decision.origin
			for c in decision.candidates:
				if not c.legal or (c.get("evaluated", true) and c.tier < 2):
					var center := SnakePlayer.cell_center(head + Vector2i(c.direction))
					draw_line(center - Vector2(7, 7), center + Vector2(7, 7), Color(1, 0.25, 0.2), 3)
					draw_line(center + Vector2(-7, 7), center + Vector2(7, -7), Color(1, 0.25, 0.2), 3)
	draw_set_transform(Vector2.ZERO)

class_name SnakeGame
extends Node2D

enum State { HOME, PLAYING, DYING, OVER }
const MAX_CATCHUP_TICKS := 4
const MAX_BACKLOG_SECONDS := MAX_CATCHUP_TICKS * SnakeSimulation.TICK_SECONDS
@export var enemy_spawning: EnemySpawnConfig = preload("res://resources/enemy_spawning.tres")
@export var drops: DropConfig = preload("res://resources/drops.tres")

var state: State = State.HOME
var score: int:
	get:
		return world.score if world != null else 0
var elapsed := 0.0

var _bg: ColorRect
var _playground: Playground
var _player: SnakePlayer
var _hud: HudManager
var _audio: AudioFx
var _home_layer: CanvasLayer
var _over_layer: CanvasLayer
var _over_score_label: PixelLabel
var _over_detail: Label
var _home_btn: Button
var _home_mode: OptionButton
var _home_scenario: OptionButton
var _over_btn: Button
var _crt_material: ShaderMaterial
var world: WorldSnapshot
var paused := false
var _accumulator := 0.0
var _views: Dictionary = {}
var _profiles: Dictionary = {}
var _decisions: Dictionary = {}
var _debug: AIDebugOverlay
var _status: Label
var _debug_visible := false
var _selected := "purple"
var _scenario_index := 0
var _seed_value := 1
var _session_serial := 0
var _arena_root: Control
var performance_stats := {"dropped_seconds": 0.0, "ticks_this_frame": 0, "tick_usec": 0, "ai_usec": 0, "due_actors": 0, "budget_exhaustions": 0}
var _performance_visible := false
var _performance_label: Label
var _performance_due := 0
var threaded_planning := true
var early_planning_enabled := true
var _ahead := PlanningAhead.new()
var _planning_version := 0
var _pending: PlanningBatch
var _retired: Array[PlanningBatch] = []
var _controls: Control
var _scenario_picker: OptionButton
var _pause_button: Button
var _mode_picker: OptionButton
var _lab_hint: Label
var _help_panel: PanelContainer
var _scenario_menu_open := false
var _lab_tools: Array[Button] = []


func _ready() -> void:
	add_to_group("snake_game")
	_bg = ColorRect.new()
	_bg.color = UIStyle.BACKGROUND
	_bg.size = Vector2(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	add_child(_bg)

	_arena_root = Control.new()
	_arena_root.clip_contents = true
	_arena_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arena_root)
	_playground = Playground.new()
	_playground.visible = false
	_arena_root.add_child(_playground)

	_player = SnakePlayer.new()
	_player.body_color = Color(0.13, 0.13, 0.13)
	_player.controlled = true
	_player.visible = false
	_arena_root.add_child(_player)
	_views.player = _player

	_hud = HudManager.new()
	_hud.visible = false
	add_child(_hud)

	_audio = AudioFx.new()
	add_child(_audio)

	_build_home()
	_build_over()

	var debug_layer := CanvasLayer.new()
	debug_layer.layer = 8
	add_child(debug_layer)
	_debug = AIDebugOverlay.new()
	_debug.enemy_chosen.connect(func(id: String): _selected = id; _sync_views())
	_debug.planner_chosen.connect(_set_planner)
	_debug.action_requested.connect(_ui_key)
	_debug.visible = false
	debug_layer.add_child(_debug)
	_status = Label.new()
	_status.position = Vector2(44, UILayout.FOOTER_Y)
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", UIStyle.MUTED)
	debug_layer.add_child(_status)
	_performance_label = Label.new()
	_performance_label.position = Vector2(44, UILayout.FOOTER_Y)
	_performance_label.add_theme_font_size_override("font_size", 14)
	_performance_label.add_theme_color_override("font_color", UIStyle.MUTED)
	_performance_label.visible = false
	debug_layer.add_child(_performance_label)
	_build_controls(debug_layer)

	var host := get_tree().get_first_node_in_group("crt_host")
	if host:
		_crt_material = host.material as ShaderMaterial


func _process(delta: float) -> void:
	_poll_retired()
	performance_stats.ticks_this_frame = 0
	if _pending != null:
		_pending.poll() # Release completed task resources even while paused.
		if not _pending.matches(world, _planning_version): _cancel_planning()
	if state == State.PLAYING:
		if not paused and not _scenario_menu_open and not _help_panel.visible:
			if threaded_planning and early_planning_enabled: _ahead.schedule(world, _profiles)
			var backlog := _accumulator + maxf(0, delta)
			performance_stats.dropped_seconds += maxf(0, backlog - MAX_BACKLOG_SECONDS)
			_accumulator = minf(backlog, MAX_BACKLOG_SECONDS)
			if _pending != null and _pending.poll():
				_complete_planning()
				performance_stats.ticks_this_frame += 1
			while _pending == null and _accumulator + 0.0000001 >= SnakeSimulation.TICK_SECONDS and state == State.PLAYING and not paused and performance_stats.ticks_this_frame < MAX_CATCHUP_TICKS:
				_accumulator = maxf(0, _accumulator - SnakeSimulation.TICK_SECONDS)
				if threaded_planning:
					if early_planning_enabled: _realtime_tick()
					else:
						_begin_planning()
						if _pending != null: break
				else:
					_simulation_tick()
				performance_stats.ticks_this_frame += 1
		elapsed = world.tick * SnakeSimulation.TICK_SECONDS
		_hud.set_time(elapsed)
		_sync_views()

func _begin_planning() -> void:
	_pending = PlanningBatch.new(world, _profiles, _planning_version, Input.is_action_pressed("boost"))
	var actors: Dictionary = _pending.prepared.world.snakes
	if actors.has("player") and actors.player.alive and (SpeedRules.due(actors.player) or actors.player.chance_ticks > 0):
		_pending.player_queued = not _player._turn_queue.is_empty()
		_pending.intents.player = _player._turn_queue[0] if _pending.player_queued else actors.player.direction
	if _pending.jobs.is_empty(): _complete_planning()

func _complete_planning() -> void:
	var batch := _pending
	_pending = null
	performance_stats.ai_usec = 0
	performance_stats.due_actors = batch.jobs.size()
	for job in batch.jobs:
		_decisions[job.actor_id] = job.decision
		batch.intents[job.actor_id] = job.decision.direction
		performance_stats.ai_usec += job.decision.duration_usec
		performance_stats.budget_exhaustions += int(job.decision.exhausted)
	if batch.player_queued: _player.take_turn()
	_apply_tick(SnakeSimulation.finish_tick(batch.prepared.world, batch.intents, batch.prepared.events))
	performance_stats.tick_usec = Time.get_ticks_usec() - batch.started

func _cancel_planning() -> void:
	_planning_version += 1
	_ahead.invalidate()
	if _pending != null:
		_retired.append(_pending)
		_pending = null

func _poll_retired() -> void:
	_ahead.poll()
	for i in range(_retired.size() - 1, -1, -1):
		if _retired[i].poll(): _retired.remove_at(i)

func _exit_tree() -> void:
	_ahead.drain()
	if _pending != null: _pending.drain()
	for batch in _retired: batch.drain()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if state != State.PLAYING and state != State.OVER:
		return
	if state == State.OVER:
		if event.keycode == KEY_R: start_game()
		elif event.keycode == KEY_F3: _select_scenario(1); _scenario_picker.show_popup()
		return
	match event.keycode:
		KEY_F1:
			_set_play_mode(not _debug_visible)
		KEY_F11:
			_performance_visible = not _performance_visible
		KEY_F2:
			var ids: Array = []
			for id in _profiles:
				if world.snakes.has(id):
					ids.append(id)
			if not ids.is_empty():
				_selected = ids[(ids.find(_selected) + 1) % ids.size()]
		KEY_F3:
			_scenario_picker.show_popup()
		KEY_H:
			_help_panel.visible = not _help_panel.visible
		KEY_F4:
			_cancel_planning()
			if _profiles.has(_selected):
				var p: EnemyProfile = _profiles[_selected]
				p.planner = (p.planner + 1) % EnemyProfile.PLANNER_NAMES.size()
				_decisions[_selected] = SnakeAI.choose_move(world, _selected, p)
		KEY_F9:
			if _debug_visible and _profiles.has(_selected):
				_cancel_planning()
				_profiles[_selected].mine_prediction = not _profiles[_selected].mine_prediction
				_decisions[_selected] = SnakeAI.choose_move(world, _selected, _profiles[_selected])
		KEY_F10:
			if _debug_visible and _profiles.has(_selected):
				_cancel_planning()
				_profiles[_selected].diamond_planning = not _profiles[_selected].diamond_planning
				_decisions[_selected] = SnakeAI.choose_move(world, _selected, _profiles[_selected])
		KEY_F6:
			_seed_value += 1
			start_game()
		KEY_F5, KEY_F7, KEY_F8:
			if _debug_visible and state == State.PLAYING and world.snakes.has("player"):
				_cancel_planning()
				var kind := ItemRules.STAR if event.keycode == KEY_F5 else (ItemRules.SPEED_UP if event.keycode == KEY_F7 else ItemRules.SLOW_DOWN)
				world = world.copy()
				var actor: SnakeState = world.snakes.player
				if actor.has_effect(kind, world.tick):
					actor.effects.erase(kind)
					ItemRules.reconcile_speed(actor, world.tick, actor.boosting)
				else:
					ItemRules.apply_effect(world, actor, kind)
				for id in _profiles:
					if world.snakes.has(id) and world.snakes[id].alive:
						_decisions[id] = SnakeAI.choose_move(world, id, _profiles[id])
		KEY_R:
			start_game()
		KEY_P, KEY_ESCAPE:
			paused = not paused
			_accumulator = 0.0
		KEY_N:
			if state == State.PLAYING:
				paused = true
				_accumulator = 0.0
				_simulation_tick()
	_sync_views()

func _ui_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_input(event)

func _select_scenario(index: int) -> void:
	_scenario_index = index
	_scenario_menu_open = false
	start_game()

func _set_play_mode(developer: bool) -> void:
	_debug_visible = developer
	if world != null: _sync_views()

func _set_planner(value: int) -> void:
	if not _profiles.has(_selected) or not world.snakes[_selected].alive: return
	_cancel_planning()
	_profiles[_selected].planner = value
	_decisions[_selected] = SnakeAI.choose_move(world, _selected, _profiles[_selected])
	_sync_views()

func _build_controls(layer: CanvasLayer) -> void:
	_controls = Control.new()
	_controls.size = Vector2(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.theme = UIStyle.theme()
	_controls.z_index = 30
	_controls.visible = false
	layer.add_child(_controls)
	_scenario_picker = OptionButton.new()
	_scenario_picker.focus_mode = Control.FOCUS_NONE
	_scenario_picker.position = Vector2(280, 34)
	_scenario_picker.size = Vector2(410, 44)
	_scenario_picker.add_theme_font_size_override("font_size", 19)
	_scenario_picker.tooltip_text = "F3 · Choose a scenario"
	var picker_title := UIStyle.label("SCENARIOS [F3]", 11, UIStyle.MUTED)
	picker_title.position = Vector2(282, 20)
	_controls.add_child(picker_title)
	for index in AIScenarios.NAMES.size():
		_scenario_picker.add_item(AIScenarios.GROUPS[index] + "  /  " + AIScenarios.NAMES[index])
		_scenario_picker.get_popup().set_item_tooltip(index, AIScenarios.DESCRIPTIONS[index])
	_scenario_picker.item_selected.connect(_select_scenario)
	_scenario_picker.get_popup().about_to_popup.connect(func(): _scenario_menu_open = true)
	_scenario_picker.get_popup().popup_hide.connect(func(): _scenario_menu_open = false)
	_controls.add_child(_scenario_picker)
	var mode_title := UIStyle.label("PLAY MODE [F1]", 11, UIStyle.MUTED)
	mode_title.position = Vector2(1246, 20)
	_controls.add_child(mode_title)
	_mode_picker = OptionButton.new()
	_mode_picker.focus_mode = Control.FOCUS_NONE
	_mode_picker.position = Vector2(1244, 34)
	_mode_picker.size = Vector2(148, 44)
	_mode_picker.add_theme_font_size_override("font_size", 16)
	_mode_picker.add_item("Normal")
	_mode_picker.add_item("Developer")
	_mode_picker.item_selected.connect(func(index: int): _set_play_mode(index == 1))
	_mode_picker.get_popup().about_to_popup.connect(func(): _scenario_menu_open = true)
	_mode_picker.get_popup().popup_hide.connect(func(): _scenario_menu_open = false)
	_controls.add_child(_mode_picker)
	var tools := HBoxContainer.new()
	tools.position = Vector2(40, 98)
	tools.add_theme_constant_override("separation", 8)
	_controls.add_child(tools)
	_pause_button = UIStyle.button("Pause [P]", true)
	_pause_button.pressed.connect(func(): _ui_key(KEY_P))
	tools.add_child(_pause_button)
	for spec in [["Step [N]", KEY_N], ["Reset [R]", KEY_R], ["Seed [F6]", KEY_F6]]:
		var button := UIStyle.button(spec[0], true)
		button.pressed.connect(_ui_key.bind(int(spec[1])))
		_lab_tools.append(button)
		tools.add_child(button)
	_lab_hint = UIStyle.label("", 16, UIStyle.MUTED)
	_lab_hint.position = Vector2(44, 824)
	_lab_hint.size = Vector2(950, 24)
	_lab_hint.clip_text = true
	_controls.add_child(_lab_hint)
	var help := UIStyle.button("Controls [H]", true)
	help.position = Vector2(1250, 846)
	help.size = Vector2(142, 36)
	help.pressed.connect(func(): _ui_key(KEY_H))
	_controls.add_child(help)
	_help_panel = PanelContainer.new()
	_help_panel.position = Vector2(400, 170)
	_help_panel.size = Vector2(640, 560)
	_help_panel.add_theme_stylebox_override("panel", UIStyle.box())
	_help_panel.visible = false
	_controls.add_child(_help_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_help_panel.add_child(column)
	column.add_child(UIStyle.label("CONTROLS", 28))
	column.add_child(UIStyle.label("WASD / Arrows   Move\nSpace   Hold to boost\nP / Esc   Pause\nF12 / Alt+Enter   Fullscreen\n\nF1   AI inspector       F3   Scenario picker\nF2   Select enemy       F4   Cycle planner\nN   Step one tick        R   Reset seed\nF6   New seed\nF5   Star   ·   F7   Speed Up   ·   F8   Slow Down\nF9   Mine prediction   ·   F10   Diamond planning\nF11   Performance details", 19, UIStyle.MUTED))
	var close := UIStyle.button("Close [H]", true)
	close.pressed.connect(func(): _help_panel.visible = false)
	column.add_child(close)


func _realtime_tick() -> void:
	var started := Time.get_ticks_usec()
	var prepared := SnakeSimulation.begin_tick(world, Input.is_action_pressed("boost"))
	var staged: WorldSnapshot = prepared.world
	staged.begin_runtime_validation()
	var intents := {}
	performance_stats.ai_usec = 0
	performance_stats.due_actors = 0
	for actor: SnakeState in staged.snakes.values():
		if not actor.alive: continue
		if actor.is_player and (SpeedRules.due(actor) or actor.chance_ticks > 0):
			intents[actor.id] = _player.take_turn()
		elif not actor.is_player and SpeedRules.due(actor):
			var plan := _ahead.take(staged, actor.id)
			var decision := SnakeAI.choose_current(staged, actor.id, _profiles[actor.id], plan)
			_decisions[actor.id] = decision
			intents[actor.id] = decision.direction
			performance_stats.ai_usec += decision.duration_usec
			performance_stats.due_actors += 1
			performance_stats.budget_exhaustions += int(decision.exhausted)
	_apply_tick(SnakeSimulation.finish_tick(staged, intents, prepared.events))
	_ahead.schedule(world, _profiles)
	performance_stats.tick_usec = Time.get_ticks_usec() - started

func _simulation_tick() -> void:
	_cancel_planning() # Manual stepping and tests resolve immediately.
	var started := Time.get_ticks_usec()
	performance_stats.ai_usec = 0
	performance_stats.due_actors = 0
	var boosting := Input.is_action_pressed("boost")
	# Phase changes must be visible before collecting due intents and before
	# AI forecasts. The simulator repeats this idempotently for direct callers.
	var prepared := SnakeSimulation.begin_tick(world, boosting)
	world = prepared.world
	var intents: Dictionary = {}
	for id in world.snakes:
		var s: SnakeState = world.snakes[id]
		if not s.alive:
			continue
		if s.is_player and (SpeedRules.due(s) or s.chance_ticks > 0):
			intents[id] = _player.take_turn()
		elif not s.is_player and SpeedRules.due(s):
			var decision := SnakeAI.choose_move(world, id, _profiles[id])
			_decisions[id] = decision
			performance_stats.ai_usec += decision.duration_usec
			performance_stats.due_actors += 1
			performance_stats.budget_exhaustions += int(decision.exhausted)
			intents[id] = decision.direction
	var result := SnakeSimulation.finish_tick(world, intents, prepared.events)
	_apply_tick(result)
	performance_stats.tick_usec = Time.get_ticks_usec() - started

func _apply_tick(result: Dictionary) -> void:
	world = result.world
	_sync_roster()
	for event in result.events:
		match event.type:
			"second_chance":
				_player.clear_turns()
				_on_second_chance_started()
			"food":
				if event.id == "player":
					_on_food_eaten(event.cell, event.score)
			"pickup":
				_hud.set_score(score)
				_audio.beep()
				_popup("+%d " % int(event.score) + ("REFRESH " if event.refreshed else "") + String(event.kind).replace("_", " ").to_upper(), event.cell)
			"mine_cleared":
				_popup("MINE CLEARED", event.cell)
			"diamond":
				if event.id == "player":
					_hud.set_score(score)
					_popup("+%d DIAMOND" % int(event.score), event.cell)
					_audio.beep()
			"obstacle_eaten":
				_popup("OBSTACLE EATEN", event.cell)
			"combat_started":
				_audio.thud()
			"died":
				if event.id == "player":
					_on_player_died()
				elif int(event.get("reward", 0)) > 0:
					_award_elimination(event)
	if not world.snakes.has("player"):
		var any_alive := false
		for s: SnakeState in world.snakes.values():
			any_alive = any_alive or s.alive
		if not any_alive:
			paused = true


func _sync_views() -> void:
	if world == null:
		return
	_sync_roster()
	_player.controlled = state == State.PLAYING and not _scenario_menu_open and not _help_panel.visible
	var fraction := clampf(_accumulator / SnakeSimulation.TICK_SECONDS, 0, 1)
	_playground.sync(world, 1.0 if paused else fraction)
	for id in _views:
		var view: SnakePlayer = _views[id]
		view.visible = world.snakes.has(id) and (world.snakes[id].alive or (id == "player" and state == State.DYING)) and state in [State.PLAYING, State.DYING]
		if world.snakes.has(id):
			view.sync(world.snakes[id], fraction, paused, world.snakes[id].has_effect(ItemRules.STAR, world.tick), world.in_combat(id))
	_debug.visible = _debug_visible and state == State.PLAYING
	_arena_root.size = Vector2(world.width, world.height) * GridConfig.CELL
	var board := UILayout.board_rect(world, _debug.visible)
	_arena_root.scale = Vector2.ONE * (board.size.x / _arena_root.size.x)
	_arena_root.position = board.position
	if _debug.visible:
		var mode: int = _profiles[_selected].planner if _profiles.has(_selected) else 0
		var planner_name: String = EnemyProfile.PLANNER_NAMES[mode] if _profiles.has(_selected) else "Awaiting enemy"
		var comparison := " | F10 diamonds " + ("ON" if _profiles[_selected].diamond_planning else "OFF") if _profiles.has(_selected) and world.snakes.has(_selected) and EnemySpawnRules.kind(world.snakes[_selected]) == "purple" else ""
		_debug.refresh(world, _decisions.get(_selected), _selected, "%s | seed %d | tick %d | %s | %s%s" % [AIScenarios.NAMES[_scenario_index], _seed_value, world.tick, "PAUSED" if paused else "RUNNING", planner_name, comparison], _profiles.get(_selected))
	_hud.set_boost_state(world.snakes.has("player") and world.snakes.player.boosting, world.snakes.has("player"), 50.0 / world.snakes.player.period if world.snakes.has("player") else SpeedRules.NORMAL_SPEED)
	_hud.set_effects(world)
	_controls.visible = state == State.PLAYING
	_hud.visible = state == State.PLAYING
	_scenario_picker.select(_scenario_index)
	_pause_button.text = "Resume [P]" if paused else "Pause [P]"
	for button in _lab_tools: button.visible = _debug_visible or _scenario_index != 0
	_mode_picker.select(int(_debug_visible))
	_lab_hint.visible = _scenario_index != 0
	_lab_hint.text = AIScenarios.DESCRIPTIONS[_scenario_index]
	_status.visible = state == State.PLAYING and not _performance_visible
	_status.text = "F2 Select enemy   ·   F4 Planner   ·   F5 / F7 / F8 Effects" if _debug_visible else "WASD / Arrows  Move   ·   Space  Boost   ·   Esc  Pause   ·   F12  Fullscreen"
	_performance_label.visible = _performance_visible and state == State.PLAYING
	if _performance_label.visible and Time.get_ticks_msec() >= _performance_due:
		_performance_due = Time.get_ticks_msec() + 100
		_performance_label.text = "F11 performance | tick %.1fms | AI %.1fms / %d due | backlog %.0fms\nslowdown %.2fs | budget limits %d | mines %d | movers %d | %s" % [performance_stats.tick_usec / 1000.0, performance_stats.ai_usec / 1000.0, performance_stats.due_actors, _accumulator * 1000, performance_stats.dropped_seconds, performance_stats.budget_exhaustions, world.mines.size(), world.moving_pickups.size(), "PLANNING" if _pending != null else "READY"]
		if early_planning_enabled:
			_performance_label.text = "Tick %.1fms · safety %.1fms · early plans %d ready / %d late\nSlowdown %.2fs · work limits %d · F11 hide" % [performance_stats.tick_usec / 1000.0, performance_stats.ai_usec / 1000.0, _ahead.stats.ready, _ahead.stats.late, performance_stats.dropped_seconds, performance_stats.budget_exhaustions]

func _sync_roster() -> void:
	for id in _profiles.keys():
		if not world.snakes.has(id):
			_profiles.erase(id)
			_decisions.erase(id)
	for id in _views.keys():
		if id != "player" and not world.snakes.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for id in world.snakes:
		var actor: SnakeState = world.snakes[id]
		if actor.is_player: continue
		if not _profiles.has(id): _profiles[id] = EnemySpawnRules.profile_for(world, actor)
		if not _views.has(id):
			var view := SnakePlayer.new()
			view.body_color = _profiles[id].display_color
			_views[id] = view
			_arena_root.add_child(view)
	if not world.snakes.has(_selected) or (_selected == "player" and not _profiles.is_empty()):
		_selected = ""
		for id in _profiles:
			if world.snakes[id].alive:
				_selected = id
				break


func start_game() -> void:
	_cancel_planning()
	_session_serial += 1
	_stop_idle_glitch()
	_set_glitch(0.0)
	elapsed = 0.0
	_scenario_index = clampi(_scenario_index, 0, AIScenarios.NAMES.size() - 1)
	_hud.set_score(0)
	_hud.set_time(0.0)
	_home_layer.visible = false
	_over_layer.visible = false
	_playground.visible = true
	_hud.visible = true
	_controls.visible = true
	_help_panel.visible = false
	_arena_root.visible = true
	_arena_root.modulate = Color.WHITE
	world = AIScenarios.make_arena(_seed_value, enemy_spawning, drops) if _scenario_index == 0 else AIScenarios.make(_scenario_index, _seed_value)
	_hud.set_score(world.score)
	_profiles = EnemyProfile.roster()
	_sync_roster()
	if not world.snakes.has(_selected):
		_selected = "player" if world.snakes.has("player") else ""
		for id in _profiles:
			if world.snakes.has(id):
				_selected = id
				break
	_decisions.clear()
	_accumulator = 0.0
	performance_stats = {"dropped_seconds": 0.0, "ticks_this_frame": 0, "tick_usec": 0, "ai_usec": 0, "due_actors": 0, "budget_exhaustions": 0}
	_ahead.stats = {"started": 0, "ready": 0, "late": 0, "invalidated": 0, "worker_usec": 0, "completed": 0}
	paused = _scenario_index != 0
	# Scenario choice and presentation mode are independent; F1 never resets a lab.
	for view: SnakePlayer in _views.values():
		view.reset()
	for id in world.snakes:
		if id != "player":
			_decisions[id] = SnakeAI.choose_move(world, id, _profiles[id])
	state = State.PLAYING
	_sync_views()


func _go_home() -> void:
	_cancel_planning()
	_stop_idle_glitch()
	_set_glitch(0.0)
	state = State.HOME
	_status.visible = false
	_controls.visible = false
	_arena_root.visible = false
	_debug.visible = false
	_performance_label.visible = false
	for view: SnakePlayer in _views.values():
		view.visible = false
	_over_layer.visible = false
	_playground.visible = false
	_hud.visible = false
	_home_layer.visible = true
	_home_mode.select(int(_debug_visible))
	_home_scenario.select(_scenario_index)
	_home_btn.grab_focus()


func _on_food_eaten(cell: Vector2i, points: int) -> void:
	_hud.set_score(score)
	_audio.beep()
	_popup("+%d" % points, cell)


func _on_second_chance_started() -> void:
	_audio.thud()


func _award_elimination(event: Dictionary) -> void:
	_hud.set_score(score)
	_popup("+%d" % int(event.reward), world.snakes[event.id].cells[0])
	_audio.beep()


func _on_player_died() -> void:
	if state != State.PLAYING: return
	state = State.DYING
	_cancel_planning()
	_stop_idle_glitch()
	_set_glitch(0)
	_sync_views()
	_audio.crash()
	var ended_world := world
	await get_tree().create_timer(0.25).timeout
	if world != ended_world or state != State.DYING: return
	_player.visible = false
	_over_score_label.text = "FINAL SCORE: %06d" % score
	var seconds := int(world.tick * 0.02)
	_over_detail.text = "Survived %02d:%02d   ·   Length %d\n%s" % [seconds / 60, seconds % 60, world.snakes.player.cells.size(), _death_caption(world.snakes.player.death_reason)]
	_over_layer.visible = true
	_arena_root.modulate = Color(1, 1, 1, 0.25)
	_over_btn.grab_focus()
	state = State.OVER
	_sync_views()

func _popup(text: String, cell: Vector2i) -> void:
	var p := PixelLabel.new()
	p.text = text
	p.pixel = 2
	p.color = Color(0.95, 0.95, 0.95)
	p.position = SnakePlayer.cell_center(cell) + Vector2(-12, -34)
	_arena_root.add_child(p)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y - 26.0, 0.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(p.queue_free)


func _build_home() -> void:
	_home_layer = CanvasLayer.new()
	_home_layer.layer = 10
	add_child(_home_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(160, 80)
	panel.size = Vector2(1120, 740)
	panel.theme = UIStyle.theme()
	# A full-size arcade title screen, rather than a small dashboard card.
	var blank := StyleBoxEmpty.new()
	blank.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", blank)
	_home_layer.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 32)
	panel.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_child(UIStyle.pixel_label("SNAKE", 20, UIStyle.ACCENT))
	column.add_child(title_row)
	var subtitle := UIStyle.label("PINK / PURPLE / RED / GOLDEN", 26, UIStyle.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	var selectors := HBoxContainer.new()
	selectors.alignment = BoxContainer.ALIGNMENT_CENTER
	selectors.add_theme_constant_override("separation", 24)
	column.add_child(selectors)
	var mode_column := VBoxContainer.new()
	mode_column.add_theme_constant_override("separation", 12)
	selectors.add_child(mode_column)
	mode_column.add_child(UIStyle.label("PLAY MODE", 20))
	_home_mode = OptionButton.new()
	_home_mode.custom_minimum_size = Vector2(300, 64)
	_home_mode.add_theme_font_size_override("font_size", 26)
	_home_mode.add_item("Normal")
	_home_mode.add_item("Developer")
	mode_column.add_child(_home_mode)
	var scenario_column := VBoxContainer.new()
	scenario_column.add_theme_constant_override("separation", 12)
	selectors.add_child(scenario_column)
	scenario_column.add_child(UIStyle.label("SCENARIO", 20))
	_home_scenario = OptionButton.new()
	_home_scenario.custom_minimum_size = Vector2(580, 64)
	_home_scenario.add_theme_font_size_override("font_size", 24)
	for index in AIScenarios.NAMES.size():
		_home_scenario.add_item(AIScenarios.GROUPS[index] + "  /  " + AIScenarios.NAMES[index])
		_home_scenario.get_popup().set_item_tooltip(index, AIScenarios.DESCRIPTIONS[index])
	scenario_column.add_child(_home_scenario)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	column.add_child(buttons)
	_home_btn = _make_button("Start game")
	_home_btn.custom_minimum_size = Vector2(360, 76)
	_home_btn.add_theme_font_size_override("font_size", 30)
	_home_btn.pressed.connect(_on_start_pressed)
	buttons.add_child(_home_btn)
	var labs := _make_button("Scenario lab")
	labs.custom_minimum_size = Vector2(300, 76)
	labs.add_theme_font_size_override("font_size", 28)
	labs.pressed.connect(func(): _home_mode.select(1); _home_scenario.select(1); _on_start_pressed(); _scenario_picker.show_popup())
	buttons.add_child(labs)
	var hints := UIStyle.label("WASD / Arrows  Move   ·   Space  Boost\nF1  Switch mode   ·   F3  Choose scenario   ·   F12  Fullscreen", 22, UIStyle.MUTED)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hints)
	_home_btn.grab_focus.call_deferred()


func _build_over() -> void:
	_over_layer = CanvasLayer.new()
	_over_layer.layer = 11
	_over_layer.visible = false
	add_child(_over_layer)
	var shade := ColorRect.new()
	shade.size = Vector2(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	shade.color = Color(0.72, 0.72, 0.72, 0.90)
	_over_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(300, 190)
	panel.size = Vector2(840, 520)
	panel.add_theme_stylebox_override("panel", UIStyle.box())
	_over_layer.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 30)
	panel.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_child(UIStyle.pixel_label("GAME OVER", 9, UIStyle.ACCENT))
	column.add_child(title_row)
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_over_score_label = UIStyle.pixel_label("FINAL SCORE: 000000", 4, UIStyle.MUTED)
	score_row.add_child(_over_score_label)
	column.add_child(score_row)
	_over_detail = UIStyle.label("", 22, UIStyle.MUTED)
	_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_over_detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_over_btn = _make_button("Try again [R]")
	_over_btn.pressed.connect(start_game)
	row.add_child(_over_btn)
	var back := _make_button("Main menu")
	back.pressed.connect(_on_back_pressed)
	row.add_child(back)


func _make_button(text: String) -> Button:
	var result := UIStyle.button(text)
	result.custom_minimum_size = Vector2(220, 54)
	result.focus_mode = Control.FOCUS_ALL
	return result

func _on_start_pressed() -> void:
	_audio.click()
	_debug_visible = _home_mode.selected == 1
	_scenario_index = _home_scenario.selected
	start_game()


func _on_back_pressed() -> void:
	_audio.click()
	_go_home()


func _set_glitch(v: float) -> void:
	if _crt_material:
		_crt_material.set_shader_parameter("glitch_amount", v)
		_crt_material.set_shader_parameter("rgb_shift", 0.005 * v)


func _stop_idle_glitch() -> void:
	_set_glitch(0)

func _death_caption(reason: String) -> String:
	match reason:
		"mine": return "A mine caught you."
		"self": return "You hit your own body."
		"consumed": return "You lost the head duel."
		"second_chance_timeout": return "You could not escape in time."
		_: return "The arena got the better of you."

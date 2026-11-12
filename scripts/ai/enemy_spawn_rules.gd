class_name EnemySpawnRules
extends RefCounted

## Called only after completed real ticks. Predictions never generate rivals.
static func configure(w: WorldSnapshot, rules: Dictionary, seed_value: int) -> void:
	w.enemy_rules = rules.duplicate(true)
	w.auto_enemies = bool(rules.enabled)
	w.enemy_rng_state = maxi(1, seed_value % 2147483647)
	w.next_enemy_serial = 1
	w.pending_enemy_spawns = {}
	w.enemy_type_ready = {}
	w.enemy_block_until = 0
	w.next_enemy_spawn_tick = w.tick + int(rules.first)

static func kind(s: SnakeState) -> String:
	return s.archetype if s.archetype != "" else s.id

static func profile_for(w: WorldSnapshot, s: SnakeState) -> EnemyProfile:
	var p := EnemyProfile.for_kind(kind(s))
	if w.enemy_rules.get("types", {}).has(kind(s)):
		for key in w.enemy_rules.types[kind(s)].profile:
			p.set(key, w.enemy_rules.types[kind(s)].profile[key])
	return p

static func make_actor(w: WorldSnapshot, id: String, archetype: String, cells: Array, direction: Vector2i) -> SnakeState:
	var p := EnemyProfile.for_kind(archetype)
	if w.enemy_rules.get("types", {}).has(archetype):
		for key in w.enemy_rules.types[archetype].profile: p.set(key, w.enemy_rules.types[archetype].profile[key])
	var actor := SnakeState.create(id, cells, direction, p.interval_ticks)
	actor.archetype = archetype
	actor.collects_food = p.collects_food
	actor.reward_multiplier = p.reward_multiplier
	actor.refresh_entry(w.width, w.height)
	return actor

static func count(w: WorldSnapshot, archetype := "") -> int:
	var total := 0
	for s: SnakeState in w.snakes.values():
		if s.alive and not s.is_player and (archetype == "" or kind(s) == archetype): total += 1
	for preview: Dictionary in w.pending_enemy_spawns.values():
		if archetype == "" or preview.kind == archetype: total += 1
	return total

static func reserved_cells(w: WorldSnapshot, except_id := "") -> Dictionary:
	var result: Dictionary = {}
	for id in w.pending_enemy_spawns:
		if id != except_id:
			for cell in w.pending_enemy_spawns[id].cells:
				if w.in_bounds(cell): result[cell] = true
	return result

static func random(w: WorldSnapshot) -> int:
	w.enemy_rng_state = (w.enemy_rng_state * 48271) % 2147483647
	return w.enemy_rng_state

static func eligible(w: WorldSnapshot) -> Array[String]:
	var result: Array[String] = []
	for archetype in w.enemy_rules.get("types", {}):
		var rule: Dictionary = w.enemy_rules.types[archetype]
		if rule.enabled and rule.weight > 0 and w.score >= int(rule.unlock_score) and count(w, archetype) < int(rule.max_alive) and w.tick >= int(w.enemy_type_ready.get(archetype, 0)):
			result.append(archetype)
	return result

static func next_active_tick(w: WorldSnapshot) -> int:
	if not w.auto_enemies: return -1
	if not w.pending_enemy_spawns.is_empty():
		return int(w.pending_enemy_spawns.values()[0].activation)
	if count(w) >= int(w.enemy_rules.cap): return -1
	var next := 9223372036854775807
	for archetype in w.enemy_rules.types:
		var rule: Dictionary = w.enemy_rules.types[archetype]
		if not rule.enabled or rule.weight <= 0 or w.score < int(rule.unlock_score) or count(w, archetype) >= int(rule.max_alive): continue
		next = mini(next, maxi(w.next_enemy_spawn_tick, maxi(w.enemy_block_until, int(w.enemy_type_ready.get(archetype, 0))) + int(w.enemy_rules.warning)))
	return -1 if next == 9223372036854775807 else next

static func _activate(w: WorldSnapshot, preview: Dictionary, actor: SnakeState, events: Array[Dictionary]) -> void:
	w.snakes[actor.id] = actor
	w.pending_enemy_spawns.erase(actor.id)
	w.next_enemy_spawn_tick = maxi(w.next_enemy_spawn_tick, w.tick + int(w.enemy_rules.interval))
	events.append({"type": "enemy_spawned", "id": actor.id, "kind": preview.kind, "cell": actor.cells[0]})

static func choose_type(w: WorldSnapshot, choices: Array[String]) -> String:
	var total := 0.0
	for archetype in choices: total += float(w.enemy_rules.types[archetype].weight)
	var selection := float(random(w)) / 2147483647.0 * total
	for archetype in choices:
		selection -= float(w.enemy_rules.types[archetype].weight)
		if selection < 0: return archetype
	return choices[-1]

static func _blocked(w: WorldSnapshot, except_id := "") -> Dictionary:
	var blocked := w.occupied()
	blocked.merge(PickupRules.occupied_items(w))
	blocked.merge(reserved_cells(w, except_id))
	blocked.merge(w.beans)
	for mine: MineState in w.mines.values():
		var lower := Vector2i((mine.position - Vector2.ONE).floor())
		var upper := Vector2i((mine.position + Vector2.ONE).ceil())
		for y in range(lower.y, upper.y):
			for x in range(lower.x, upper.x): blocked[Vector2i(x, y)] = true
	return blocked

## Use the runtime fractional clock, including its due-move epsilon.
static func first_move_offset(actor: SnakeState, budget: GridSearch = null) -> int:
	var clock := actor.copy()
	for offset in range(1, ceili(maxf(actor.remaining, actor.period)) + 2):
		if budget != null and not budget.spend(): return -1
		if SpeedRules.advance_phase(clock): return offset
	return -1

## Only entered cells occupy the arena. Unentered tail segments are real body
## length outside the boundary, following the same movement/growth resolver.
static func safe(w: WorldSnapshot, actor: SnakeState, blocked: Dictionary, budget: GridSearch = null, waiting := -1) -> bool:
	if actor.cells.is_empty() or not w.in_bounds(actor.cells[0]): return false
	if actor.entry_remaining > 0:
		if not boundary_heading(w, actor.cells[0], actor.direction): return false
		for i in actor.cells.size():
			if actor.cells[i] != actor.cells[0] - actor.direction * i: return false
	for cell in actor.cells:
		if budget != null and not budget.spend(): return false
		if not w.in_bounds(cell) and actor.entry_remaining == 0: return false
		if w.in_bounds(cell) and blocked.has(cell): return false
	if waiting < 0: waiting = first_move_offset(actor, budget)
	if waiting < 0: return false
	for other: SnakeState in w.snakes.values():
		if not other.alive: continue
		var reach := maxi(int(w.enemy_rules.head_distance), ceili(waiting / maxf(1, other.period)) + 2)
		if other.is_player: reach = maxi(reach, int(w.enemy_rules.get("player_distance", 12)))
		for cell in actor.cells:
			if not w.in_bounds(cell): continue
			if budget != null and not budget.spend(): return false
			if absi(cell.x - other.cells[0].x) + absi(cell.y - other.cells[0].y) < reach: return false
	var fork := w.copy(actor.id, false, false)
	fork.snakes[actor.id] = actor
	var from := MineRules.center(actor.cells[0])
	for direction in SnakeSimulation.candidates(actor):
		if SnakeSimulation.collision_reason(fork, actor, direction, false) != "": continue
		var destination := from + Vector2(direction)
		var clear := true
		for source: MineState in w.mines.values():
			var mine := source.copy()
			for offset in range(1, waiting + 1):
				if budget != null and not budget.spend(): return false
				var segments := MineRules.advance(mine, w.width, w.height, w.tick + offset)
				if MineRules.contact(from, destination if offset == waiting else from, segments) < INF:
					clear = false
					break
			if not clear: break
		if clear: return true
	return false

static func boundary_heading(w: WorldSnapshot, cell: Vector2i, direction: Vector2i) -> bool:
	return (cell.x == 0 and direction == Vector2i.RIGHT) or (cell.x == w.width - 1 and direction == Vector2i.LEFT) or (cell.y == 0 and direction == Vector2i.DOWN) or (cell.y == w.height - 1 and direction == Vector2i.UP)

static func find_placement(w: WorldSnapshot, id: String, archetype: String, budget: GridSearch = null) -> Dictionary:
	var blocked := _blocked(w)
	var length: int = w.enemy_rules.types[archetype].profile.initial_length
	var sites: Array[Dictionary] = []
	for x in w.width:
		sites.append({"cell": Vector2i(x, 0), "direction": Vector2i.DOWN})
		sites.append({"cell": Vector2i(x, w.height - 1), "direction": Vector2i.UP})
	for y in w.height:
		sites.append({"cell": Vector2i(0, y), "direction": Vector2i.RIGHT})
		sites.append({"cell": Vector2i(w.width - 1, y), "direction": Vector2i.LEFT})
	# Shuffle the boundary once; bounded attempts now cover dispersed entries,
	# rather than a short run of neighboring cells in the interior.
	for i in range(sites.size() - 1, 0, -1):
		var index := random(w) % (i + 1)
		var swap := sites[i]
		sites[i] = sites[index]
		sites[index] = swap
	var waiting := -1
	for offset in mini(int(w.enemy_rules.attempts), sites.size()):
		if budget != null and budget.exhausted: break
		var direction: Vector2i = sites[offset].direction
		var head: Vector2i = sites[offset].cell
		var cells: Array[Vector2i] = []
		for i in length: cells.append(head - direction * i)
		var actor := make_actor(w, id, archetype, cells, direction)
		if waiting < 0: waiting = first_move_offset(actor, budget)
		if waiting < 0: break
		if safe(w, actor, blocked, budget, waiting): return {"id": id, "kind": archetype, "cells": cells, "direction": direction, "activation": 0}
	return {}

static func advance(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	if not w.auto_enemies: return
	var deaths: Dictionary = {}
	var bomb := false
	for event in events:
		if event.type == "pickup" and event.kind == PickupRules.BOMB: bomb = true
		if event.type == "died" and w.snakes.has(event.id) and not w.snakes[event.id].is_player:
			deaths[event.id] = true
			var archetype := kind(w.snakes[event.id])
			var cooldown: int = w.enemy_rules.types.get(archetype, {}).get("cooldown", 0)
			w.enemy_type_ready[archetype] = w.tick + cooldown
			w.next_enemy_spawn_tick = maxi(w.next_enemy_spawn_tick, w.tick + int(w.enemy_rules.interval))
	# Keep this tick's corpses until its UI events are consumed, then retire.
	# This bounds snapshot/profile/view growth across an endless session.
	for id in w.snakes.keys():
		if not w.snakes[id].alive and not w.snakes[id].is_player and not deaths.has(id): w.snakes.erase(id)
	if bomb:
		w.pending_enemy_spawns = {}
		w.enemy_block_until = w.tick + int(w.enemy_rules.bomb_grace)
		w.next_enemy_spawn_tick = w.enemy_block_until + int(w.enemy_rules.warning)
	if not w.snakes.has("player") or not w.snakes.player.alive or w.tick < w.enemy_block_until: return
	var budget := GridSearch.new()
	budget.limit = int(w.enemy_rules.checks)
	for id in w.pending_enemy_spawns.keys():
		var preview: Dictionary = w.pending_enemy_spawns[id]
		if w.tick < int(preview.activation): continue
		var actor := make_actor(w, id, preview.kind, preview.cells, preview.direction)
		if safe(w, actor, _blocked(w, id), budget):
			_activate(w, preview, actor, events)
		else:
			w.pending_enemy_spawns.erase(id)
			var replacement := find_placement(w, id, preview.kind, budget)
			if not replacement.is_empty():
				replacement.activation = w.tick
				events.append({"type": "enemy_entry_relocated", "id": id, "from": preview.cells[0], "cell": replacement.cells[0]})
				_activate(w, replacement, make_actor(w, id, preview.kind, replacement.cells, replacement.direction), events)
			else:
				preview.activation = w.tick + int(w.enemy_rules.retry)
				preview.blocked_reason = "No distant safe boundary entrance within the placement budget"
				w.pending_enemy_spawns[id] = preview
	if count(w) >= int(w.enemy_rules.cap) or not w.pending_enemy_spawns.is_empty(): return
	if w.tick < w.next_enemy_spawn_tick - int(w.enemy_rules.warning): return
	var choices := eligible(w)
	if choices.is_empty(): return
	var archetype := choose_type(w, choices)
	var id := "%s_%04d" % [archetype, w.next_enemy_serial]
	while w.snakes.has(id) or w.pending_enemy_spawns.has(id):
		w.next_enemy_serial += 1
		id = "%s_%04d" % [archetype, w.next_enemy_serial]
	var preview := find_placement(w, id, archetype, budget)
	if preview.is_empty():
		w.next_enemy_spawn_tick = w.tick + int(w.enemy_rules.retry) + int(w.enemy_rules.warning)
		return
	w.next_enemy_serial += 1
	preview.activation = maxi(w.next_enemy_spawn_tick, w.tick + int(w.enemy_rules.warning))
	w.pending_enemy_spawns[id] = preview
	w.next_enemy_spawn_tick = int(preview.activation) + int(w.enemy_rules.interval)
	if int(w.enemy_rules.warning) > 0:
		events.append({"type": "enemy_warning", "id": id, "kind": archetype, "cell": preview.cells[0]})
	if int(preview.activation) <= w.tick:
		_activate(w, preview, make_actor(w, id, archetype, preview.cells, preview.direction), events)

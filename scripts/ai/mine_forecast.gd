class_name MineForecast
extends RefCounted

## A decision-local cache. Other actors never clear a forecast mine; only the
## actor whose route is being simulated may clear one with its own Star head.
var source: WorldSnapshot
var search: GridSearch
var predictive := true
var base_tick := 0
var last_tick := 0
var projected: Dictionary = {}
var frames: Dictionary = {}
var poses: Dictionary = {}
var motion: TrajectoryCache

func _init(w: WorldSnapshot, budget: GridSearch = null, predict := true) -> void:
	source = w
	search = budget
	predictive = predict
	base_tick = w.tick - int(w.prepared)
	last_tick = base_tick
	motion = w.trajectories(predict)
	projected = w.mines.duplicate()
	poses[base_tick] = projected

func spend() -> bool:
	return search == null or search.spend()

func spend_many(count: int) -> bool:
	return search == null or search.spend_many(count)

func ensure(tick: int) -> bool:
	while last_tick < tick:
		if not spend_many(projected.size()): return false
		last_tick += 1
		motion.ensure(last_tick)
		frames[last_tick] = motion.frames[last_tick]
		poses[last_tick] = motion.poses[last_tick]
	return true

## Advance only this actor, retaining other bodies as conservative obstacles.
## Check each motion tick AND all waiting ticks before its following decision.
## The exact same mine trajectories/contact primitive are used by gameplay.
func step(w: WorldSnapshot, id: String, direction: Vector2i, measure_clearance := true) -> Dictionary:
	var actor: SnakeState = w.snakes[id]
	var schedule := SnakeSimulation.movement_schedule(w, id, 2)
	var offsets: Array[int] = schedule.offsets
	var failure := {"valid": false, "world": w, "contact_tick": -1, "clearance": INF, "truncated": false}
	if offsets.size() < 2:
		return failure
	if actor.is_player and not w.items.is_empty():
		return _live_step(w, id, direction)
	if not w.moving_pickups.is_empty():
		# Cheap conservative distance bound: a reward farther from the entire
		# head sweep than its maximum travel cannot be collected this interval.
		# Keep the exact per-tick resolver for all possibly interacting rewards.
		var near := actor.is_player
		var nearby: Dictionary = {}
		for item: MovingPickup in w.moving_pickups.values():
			if not spend():
				failure.truncated = true
				return failure
			if item.kind != PickupRules.DIAMOND: continue
			var from := MineRules.center(actor.cells[0]) - item.position
			var to := MineRules.center(actor.cells[0] + direction) - item.position
			var travel := item.velocity.length() * (offsets[1] - 1) * SnakeSimulation.TICK_SECONDS
			if ItemGeometry.square_clearance(from, to, item.half_size()) <= travel + ItemGeometry.EPS:
				near = true
				nearby[item.id] = true
		if near: return _live_step(w, id, direction, nearby if not actor.is_player else {})
	var start_tick := w.tick - int(w.prepared)
	var move_tick := start_tick + offsets[0]
	var end_tick := start_tick + offsets[1] - 1
	if not spend():
		failure.truncated = true
		return failure
	var timed := w.copy(id, false, false)
	timed.tick = move_tick
	timed.prepared = false
	# Distant movers cannot affect this actor before its next decision.
	# Move them once to the ending pose after resolving bodies and hazards.
	timed.moving_pickups.clear()
	if SnakeSimulation.collision_reason(timed, actor, direction, false) != "":
		return failure
	var body_result := SnakeSimulation.resolve_moves(timed, {id: direction}, false, false, false, "", true, id)
	var next: WorldSnapshot = body_result.world
	for event in body_result.events:
		if event.type == "died":
			next.score -= int(event.reward) # Other deaths are not assumed by a forecast.
	next.restore_prediction_actors(w, id)
	var moved: SnakeState = next.snakes[id]
	if not moved.alive:
		return failure
	var from := MineRules.center(actor.cells[0])
	var to := MineRules.center(moved.cells[0])
	var ignored: Dictionary = {}
	for mine_id in source.mines:
		if not w.mines.has(mine_id):
			ignored[mine_id] = true
	var clearance := INF
	for tick in range(start_tick + 1, end_tick + 1):
		if not ensure(tick):
			failure.truncated = true
			return failure
		var head_from := from if tick <= move_tick else to
		var head_to := to if tick >= move_tick else from
		for mine_id in frames[tick]:
			if ignored.has(mine_id):
				continue
			if not spend():
				failure.truncated = true
				return failure
			# Route validity needs exact contact, not a distance score. Only the
			# mandatory immediate candidates expose clearance in the debug UI.
			if measure_clearance:
				clearance = minf(clearance, motion.mine_clearance(tick, mine_id, head_from, head_to))
			if motion.mine_contact(tick, mine_id, head_from, head_to) == INF:
				continue
			# Pickups happen after the movement's contact test, never retroactively.
			var protected: bool = actor.is_player and (actor.has_effect(ItemRules.STAR, tick) if tick <= move_tick else moved.has_effect(ItemRules.STAR, tick))
			if protected:
				ignored[mine_id] = true
			else:
				failure.contact_tick = tick
				failure.clearance = clearance
				return failure
	next.tick = end_tick
	next.prepared = false
	for item: MovingPickup in w.moving_pickups.values():
		if not spend():
			failure.truncated = true
			return failure
		next.moving_pickups[item.id] = motion.pickup_projection(item, end_tick).item
	ItemRules.expire(next, [])
	moved.period = schedule.wait_period
	moved.remaining = schedule.wait_remaining
	ItemRules.reconcile_speed(moved, end_tick, actor.boosting)
	next.mines.clear()
	for mine_id in poses[end_tick]:
		if not ignored.has(mine_id):
			next.mines[mine_id] = poses[end_tick][mine_id]
	return {"valid": true, "world": next, "contact_tick": -1, "clearance": clearance, "truncated": false}

func _live_step(w: WorldSnapshot, id: String, direction: Vector2i, nearby: Dictionary = {}) -> Dictionary:
	var state := w.copy(id, not predictive, false)
	var deferred: Dictionary = {}
	if not nearby.is_empty():
		for item_id in w.moving_pickups:
			if not nearby.has(item_id):
				deferred[item_id] = w.moving_pickups[item_id]
				state.moving_pickups.erase(item_id)
	var failure := {"valid": false, "world": w, "contact_tick": -1, "clearance": INF, "truncated": false}
	var count := 0
	var moved := false
	while count < 2 * ceili(maxf(state.snakes[id].base_period / (1.0 - SpeedRules.DOWN_PENALTY), ItemRules.SLOW_TICKS)) + 2:
		if not spend():
			failure.truncated = true
			return failure
		count += 1
		if not state.prepared: state.tick += 1
		state.prepared = false
		# Retain the physical forecast cache for the debug trajectories even
		# when rewards require the full resolver. This work shares the budget.
		if not ensure(state.tick):
			failure.truncated = true
			return failure
		ItemRules.expire(state, [])
		var actor: SnakeState = state.mutable_snake(id)
		ItemRules.reconcile_speed(actor, state.tick, actor.boosting)
		var intents: Dictionary = {}
		if SpeedRules.advance_phase(actor):
			if SnakeSimulation.collision_reason(state, actor, direction, false) != "": return failure
			intents[id] = direction
			moved = true
		if not spend_many(state.mines.size()):
			failure.truncated = true
			return failure
		if not predictive:
			for mine_id in state.mines:
				state.mines[mine_id].activation_tick = 0 if source.tick >= source.mines[mine_id].activation_tick else 2147483647
		# Preserve the same logical budget and truncation boundary even though
		# distant rewards cannot interact and skip these resolver invocations.
		if not spend_many(state.moving_pickups.size() + deferred.size()):
			failure.truncated = true
			return failure
		var result := SnakeSimulation.resolve_moves(state, intents, predictive, true, true, id, true, id, motion if predictive else null)
		var next: WorldSnapshot = result.world
		for event in result.events:
			if event.type == "died": next.score -= int(event.reward)
		next.restore_prediction_actors(state, id)
		state = next
		if not state.snakes[id].alive:
			failure.contact_tick = state.tick if state.snakes[id].death_reason == "mine" else -1
			return failure
		if moved:
			var preview: SnakeState = state.snakes[id].copy()
			ItemRules.reconcile_speed(preview, state.tick + 1, preview.boosting)
			if SpeedRules.due(preview):
				if not deferred.is_empty():
					var restored: Dictionary = {}
					for item_id in w.moving_pickups:
						if deferred.has(item_id):
							restored[item_id] = motion.pickup_projection_tickwise(deferred[item_id], w.tick + int(not w.prepared), state.tick)
						elif state.moving_pickups.has(item_id): restored[item_id] = state.moving_pickups[item_id]
					state.moving_pickups = restored
				return {"valid": true, "world": state, "contact_tick": -1, "clearance": INF, "truncated": false}
	return failure

## Depth-first bounded existence check. A successful branch is evidence for
## this horizon, not a guarantee. Straight/left/right order stays deterministic.
func escape(w: WorldSnapshot, id: String, moves: int) -> Dictionary:
	var head: Vector2i = w.snakes[id].cells[0]
	if moves <= 0:
		return {"valid": true, "path": [head], "truncated": false, "contact_tick": -1}
	var earliest := -1
	for direction in SnakeSimulation.candidates(w.snakes[id]):
		var result := step(w, id, direction, false)
		if result.truncated:
			return {"valid": false, "path": [head], "truncated": true, "contact_tick": earliest}
		if not result.valid:
			if result.contact_tick >= 0:
				earliest = result.contact_tick if earliest < 0 else mini(earliest, result.contact_tick)
			continue
		var continuation := escape(result.world, id, moves - 1)
		if continuation.valid:
			continuation.path.push_front(head)
			return continuation
		if continuation.truncated:
			return continuation
	return {"valid": false, "path": [head], "truncated": false, "contact_tick": earliest}

func traces(ticks := 50) -> Array:
	var result: Array = []
	# Display uses already-computed poses only; never hides unbudgeted forecast
	# work in rendering or increments a reported decision's search afterwards.
	for mine_id in source.mines:
		var points: Array = [{"position": source.mines[mine_id].position, "tick": base_tick}]
		for tick in range(base_tick + 1, mini(last_tick, base_tick + ticks) + 1):
			if predictive and (tick - base_tick) % 10 == 0 and poses.has(tick):
				points.append({"position": poses[tick][mine_id].position, "tick": tick})
		result.append({"id": mine_id, "points": points})
	return result

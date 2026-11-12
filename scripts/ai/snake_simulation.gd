class_name SnakeSimulation
extends RefCounted

const TICK_SECONDS := 0.02
const CHANCE_TICKS := 20
const BOOST_TICKS := SpeedRules.NORMAL_TICKS / (1.0 + SpeedRules.BOOST_BONUS)
const BITE_TICKS := 10 # Initial tuning: one tail segment / 0.20s, independent of boost.
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func candidates(s: SnakeState) -> Array[Vector2i]:
	return [s.direction, Vector2i(s.direction.y, -s.direction.x), Vector2i(-s.direction.y, s.direction.x)]

## Geometry is shared by runtime, AI and fixtures. Star can clear enemies/mines;
## walls and self stay blocked even while protected.
static func collision_reason(w: WorldSnapshot, s: SnakeState, direction: Vector2i, include_mines := true) -> String:
	if not direction in DIRECTIONS or direction == -s.direction:
		return "reversal"
	var cell := s.cells[0] + direction
	if not w.in_bounds(cell) or w.walls.has(cell):
		return "wall"
	var star := s.is_player and s.has_effect(ItemRules.STAR, w.tick)
	if w.obstacles.has(cell) and not star:
		return "wall"
	var count := s.cells.size() if s.pending_growth > 0 else s.cells.size() - 1
	for i in count:
		if s.cells[i] == cell:
			return "self"
	if include_mines and not star and MineRules.static_contact(w, MineRules.center(s.cells[0]), MineRules.center(cell)):
		return "mine"
	for other: SnakeState in w.snakes.values():
		if other.id != s.id and other.alive and cell in other.cells and not star:
			return "head_contact" if cell == other.cells[0] else "body"
	return ""

static func _kill(w: WorldSnapshot, id: String, reason: String, killer: String, events: Array[Dictionary]) -> void:
	var s: SnakeState = w.snakes[id]
	if not s.alive:
		return
	s = w.mutable_snake(id)
	s.alive = false
	s.boosting = false
	s.chance_ticks = 0
	s.death_reason = reason
	events.append({"type": "died", "id": id, "reason": reason, "killer": killer, "reward": 0, "body": s.cells.duplicate()})

static func _damage(w: WorldSnapshot, id: String, killer: String, protected: bool, events: Array[Dictionary]) -> void:
	var s: SnakeState = w.snakes[id]
	if not s.alive:
		return
	if s.cells.size() <= ScoreRules.MIN_LENGTH:
		if not protected:
			_kill(w, id, "consumed", killer, events)
		return
	s = w.mutable_snake(id)
	s.cells.pop_back()
	if s.entry_remaining > 0: s.refresh_entry(w.width, w.height)
	s.pending_growth = maxi(0, s.pending_growth - 1)
	events.append({"type": "segment_lost", "id": id, "length": s.cells.size(), "protected": protected})

static func _pair(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

static func _turns_out(w: WorldSnapshot, s: SnakeState, entry: Dictionary, intents: Dictionary) -> bool:
	if not intents.has(s.id):
		return false
	var direction: Vector2i = intents[s.id]
	var locked: Vector2i = entry.ad if entry.a == s.id else entry.bd
	return direction != locked and collision_reason(w, s, direction, false) == ""

## Pure joint resolver: all contacts are derived before anyone moves.
static func resolve_moves(snapshot: WorldSnapshot, intents: Dictionary, move_mines := false, check_mines := true, move_pickups := false, only_actor := "", collect_rewards := true, prediction_actor := "", motion: TrajectoryCache = null) -> Dictionary:
	var w := snapshot.copy(prediction_actor, check_mines and motion == null, move_pickups and motion == null, not move_mines)
	var events: Array[Dictionary] = []
	var ids: Array = w.snakes.keys()
	ids.sort()
	# With no intents and no duel, no body can move, start contact or shed a
	# segment. Keep exact swept hazards, pickups and scoring, without running
	# the unchanged body-pair phases. Public runtime stays on the general path.
	if prediction_actor != "" and intents.is_empty() and snapshot.duels.is_empty():
		if check_mines: _resolve_mines(w, snapshot, ids, {}, {}, {}, move_mines, only_actor, motion, events)
		_collect_rewards(w, snapshot, ids, collect_rewards, move_pickups, only_actor, motion, events)
		ScoreRules.award_events(w, events)
		return {"world": w, "events": events}
	var destinations: Dictionary = {}
	for id in ids:
		var s: SnakeState = w.snakes[id]
		if s.alive and intents.has(id):
			destinations[id] = s.cells[0] + Vector2i(intents[id])

	# Star contact works in both directions: the player's moving head hits a
	# rival, OR a rival's head touches any player segment. Attribution is once.
	for player: SnakeState in snapshot.snakes.values():
		if not player.alive or not player.is_player or not player.has_effect(ItemRules.STAR, w.tick):
			continue
		var player_can_move: bool = destinations.has(player.id) and collision_reason(snapshot, player, intents[player.id], false) == ""
		for id in ids:
			var enemy: SnakeState = snapshot.snakes[id]
			if enemy.is_player or not enemy.alive:
				continue
			var touched: bool = player_can_move and destinations[player.id] in enemy.cells
			if snapshot.duels.has(_pair(player.id, id)):
				touched = true
			if destinations.has(id):
				var reason := collision_reason(snapshot, enemy, intents[id], false)
				if not reason in ["wall", "self", "reversal", "mine"]:
					touched = touched or destinations[id] in player.cells
					touched = touched or (player_can_move and destinations[id] == destinations[player.id])
			if touched:
				_kill(w, id, "star_contact", player.id, events)

	# This snapshot includes Star eliminations, but not later moving bodies.
	# The original is already immutable and identical unless Star removed a
	# rival. Reuse it in the common case instead of copying every BFS prediction
	# twice; never alias the mutable result while resolving bodies.
	var collision_world: WorldSnapshot = snapshot if events.is_empty() else w.copy(prediction_actor, false, false)
	var reasons: Dictionary = {}
	for id in destinations:
		reasons[id] = collision_reason(collision_world, collision_world.snakes[id], intents[id], false)
	var contacts: Dictionary = {}
	var duels: Dictionary = {}
	# Existing contact remains until a participant makes a legal turn away.
	for key: String in snapshot.duels:
		var entry: Dictionary = snapshot.duels[key]
		var a: SnakeState = w.snakes[entry.a]
		var b: SnakeState = w.snakes[entry.b]
		if reasons.get(a.id, "") in ["wall", "self", "reversal", "mine"] or reasons.get(b.id, "") in ["wall", "self", "reversal", "mine"]:
			continue # A duel never grants immunity to an unrelated fatal move.
		if not a.alive or not b.alive or _turns_out(collision_world, a, entry, intents) or _turns_out(collision_world, b, entry, intents):
			continue
		duels[key] = entry.duplicate()
		contacts[a.id] = true
		contacts[b.id] = true
	for i in ids.size():
		var a: SnakeState = w.snakes[ids[i]]
		if not a.alive or reasons.get(a.id, "") in ["wall", "self", "reversal", "mine"]:
			continue
		for j in range(i + 1, ids.size()):
			var b: SnakeState = w.snakes[ids[j]]
			if not b.alive or reasons.get(b.id, "") in ["wall", "self", "reversal", "mine"] or (not destinations.has(a.id) and not destinations.has(b.id)):
				continue
			var da: Vector2i = destinations.get(a.id, a.cells[0])
			var db: Vector2i = destinations.get(b.id, b.cells[0])
			if da != db and not (da == b.cells[0] and db == a.cells[0]):
				continue
			# A Star participant never starts a length contest.
			if (a.is_player and a.has_effect(ItemRules.STAR, w.tick)) or (b.is_player and b.has_effect(ItemRules.STAR, w.tick)):
				continue
			var key := _pair(a.id, b.id)
			if not duels.has(key):
				duels[key] = {"a": a.id, "b": b.id, "ad": intents.get(a.id, a.direction), "bd": intents.get(b.id, b.direction), "next_bite": w.tick}
				events.append({"type": "combat_started", "a": a.id, "b": b.id})
			contacts[a.id] = true
			contacts[b.id] = true
	# Resolve swept hazards after deriving held heads, before ordinary damage.
	if check_mines: _resolve_mines(w, snapshot, ids, destinations, contacts, reasons, move_mines, only_actor, motion, events)
	# Derive every bite before applying damage, including equal-length deaths.
	# Multi-head pileups cost one segment per actor per bite, not pair-order damage.
	var damage: Dictionary = {}
	for entry: Dictionary in duels.values():
		if w.tick < int(entry.next_bite):
			continue
		entry.next_bite = w.tick + BITE_TICKS
		for pair_ids: Array in [[entry.a, entry.b], [entry.b, entry.a]]:
			var victim: String = pair_ids[0]
			var killer: String = pair_ids[1]
			if not damage.has(victim) or w.snakes[killer].is_player:
				damage[victim] = killer
	for id in ids:
		if damage.has(id):
			_damage(w, id, damage[id], false, events)

	for id in ids:
		var s: SnakeState = w.snakes[id]
		if not s.alive:
			continue
		if contacts.has(id):
			s = w.mutable_snake(id)
			s.chance_ticks = 0 # A real duel replaces body-contact grace.
			if intents.has(id):
				s.direction = intents[id]
			continue # Heads stay at last valid cells while tails are consumed.
		if not destinations.has(id):
			continue
		s = w.mutable_snake(id)
		var reason: String = reasons[id]
		if reason == "head_contact":
			reason = "body" # The leading head departed; its trailing body is solid.
		if reason != "":
			if s.is_player and s.has_effect(ItemRules.STAR, w.tick) and reason in ["wall", "self"]:
				s.star_blocked = true
				s.direction = intents[id]
				if w.tick >= s.next_shrink_tick:
					s.next_shrink_tick = w.tick + BITE_TICKS
					_damage(w, id, "", true, events)
			elif s.is_player and reason in ["wall", "body"]:
				if s.chance_ticks == 0:
					s.chance_ticks = CHANCE_TICKS
					events.append({"type": "second_chance", "id": id})
			else:
				var killer := ""
				if reason == "body":
					for other: SnakeState in collision_world.snakes.values():
						if other.id != id and other.alive and destinations[id] in other.cells:
							killer = other.id
							break
				_kill(w, id, reason, killer, events)
			continue
		_move_body(w, s, intents[id], destinations[id], collect_rewards, events)
	_collect_rewards(w, snapshot, ids, collect_rewards, move_pickups, only_actor, motion, events)
	w.duels.clear()
	for key: String in duels:
		var entry: Dictionary = duels[key]
		if w.snakes[entry.a].alive and w.snakes[entry.b].alive:
			w.duels[key] = entry
	ScoreRules.award_events(w, events)
	return {"world": w, "events": events}

## Shared by the joint resolver and certified event-free focal predictions.
static func _move_body(w: WorldSnapshot, s: SnakeState, direction: Vector2i, destination: Vector2i, collect_rewards: bool, events: Array[Dictionary]) -> void:
	s.direction = direction
	s.star_blocked = false
	s.cells.push_front(destination)
	if s.pending_growth > 0: s.pending_growth -= 1
	else: s.cells.pop_back()
	s.moves += 1
	if s.entry_remaining > 0: s.refresh_entry(w.width, w.height)
	events.append({"type": "moved", "id": s.id})
	if s.is_player and s.has_effect(ItemRules.STAR, w.tick) and w.obstacles.has(s.cells[0]):
		w.remove_obstacle(s.cells[0])
		events.append({"type": "obstacle_eaten", "id": s.id, "cell": s.cells[0]})
	if collect_rewards and s.collects_food and w.consume_bean(s.cells[0]):
		s.pending_growth += 1
		s.food_eaten += 1
		events.append({"type": "food", "id": s.id, "cell": s.cells[0]})

## Shared hazard and reward phases are also used by event-free waiting ticks.
static func _resolve_mines(w: WorldSnapshot, snapshot: WorldSnapshot, ids: Array, destinations: Dictionary, contacts: Dictionary, reasons: Dictionary, move_mines: bool, only_actor: String, motion: TrajectoryCache, events: Array[Dictionary]) -> void:
	var hazard_contacts: Array[Dictionary] = []
	var checked_ids: Array = [only_actor] if only_actor != "" else ids
	for m: MineState in w.mines.values():
		var segments: Array[Dictionary]
		if motion != null:
			motion.ensure(w.tick)
			segments = motion.frames[w.tick][m.id]
			w.mines[m.id] = motion.poses[w.tick][m.id]
		else:
			segments = MineRules.advance(m, w.width, w.height, w.tick, move_mines)
		for id in checked_ids:
			var s: SnakeState = w.snakes[id]
			if not s.alive:
				continue
			var from := MineRules.center(s.cells[0])
			var to := from
			if destinations.has(id) and not contacts.has(id) and reasons[id] == "":
				to = MineRules.center(destinations[id])
			var contact_time := motion.mine_contact(w.tick, m.id, from, to) if motion != null else MineRules.contact(from, to, segments)
			if contact_time < INF:
				hazard_contacts.append({"time": roundi(contact_time * 100000000), "mine": m.id, "snake": id,
					"star": s.is_player and s.has_effect(ItemRules.STAR, w.tick)})
	hazard_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time != b.time: return a.time < b.time
		if a.star != b.star: return a.star
		if a.mine != b.mine: return a.mine < b.mine
		return a.snake < b.snake)
	for hit in hazard_contacts:
		if not w.mines.has(hit.mine) or not w.snakes[hit.snake].alive:
			continue
		if hit.star:
			var point: Vector2 = w.mines[hit.mine].position
			w.mines.erase(hit.mine)
			events.append({"type": "mine_cleared", "id": hit.snake, "mine": hit.mine, "cell": Vector2i(point.floor())})
		else:
			_kill(w, hit.snake, "mine", "", events)

static func _collect_rewards(w: WorldSnapshot, snapshot: WorldSnapshot, ids: Array, collect_rewards: bool, move_pickups: bool, only_actor: String, motion: TrajectoryCache, events: Array[Dictionary]) -> void:
	if not collect_rewards or (w.items.is_empty() and w.moving_pickups.is_empty()): return
	var heads: Dictionary = {}
	for id in ids:
		if only_actor != "" and only_actor != id: continue
		var actor: SnakeState = w.snakes[id]
		if actor.alive:
			if collect_rewards and (only_actor == "" or only_actor == id):
				if actor.is_player and not w.items.is_empty(): actor = w.mutable_snake(id)
				ItemRules.collect(w, actor, events)
			heads[id] = {"from": MineRules.center(snapshot.snakes[id].cells[0]), "to": MineRules.center(actor.cells[0])}
	if collect_rewards: PickupRules.resolve(w, heads, events, move_pickups, only_actor, motion)

## One clock phase for gameplay and AI: expiration and speed changes happen
## BEFORE collecting simultaneous intents. Direct callers use advance_world.
static func begin_tick(snapshot: WorldSnapshot, boost_requested := false) -> Dictionary:
	var staged := snapshot.copy("", true, true, false)
	if staged.snake_observations.is_empty(): SnakePerception.record(staged)
	staged.tick += 1
	staged.bomb_this_tick = false
	staged.prepared = true
	var events: Array[Dictionary] = []
	ItemRules.expire(staged, events)
	for s: SnakeState in staged.snakes.values():
		ItemRules.reconcile_speed(s, staged.tick, boost_requested)
		if s.has_effect(ItemRules.STAR, staged.tick):
			s.chance_ticks = 0
	return {"world": staged, "events": events}

static func finish_tick(staged: WorldSnapshot, intents: Dictionary, tick_events: Array[Dictionary]) -> Dictionary:
	var moves: Dictionary = {}
	var grace_expired: Array[String] = []
	var events: Array[Dictionary] = tick_events.duplicate()
	for s: SnakeState in staged.snakes.values():
		if not s.alive:
			continue
		if s.chance_ticks > 0:
			var turn: Vector2i = intents.get(s.id, s.direction)
			if turn != s.direction and collision_reason(staged, s, turn) == "":
				s.chance_ticks = 0
				s.direction = turn
				s.remaining = s.period
				events.append({"type": "escaped", "id": s.id})
			else:
				s.chance_ticks -= 1
				if s.chance_ticks == 0:
					grace_expired.append(s.id)
			continue
		if SpeedRules.advance_phase(s):
			moves[s.id] = intents.get(s.id, s.direction)
	var resolved := resolve_moves(staged, moves, true, true, true)
	events.append_array(resolved.events)
	var w: WorldSnapshot = resolved.world
	for id in grace_expired:
		_kill(w, id, "second_chance_timeout", "", events)
	# A timeout on this same tick also disqualifies a player from bounties.
	for event in events:
		if event.type == "died" and int(event.reward) > 0 and not w.snakes[event.killer].alive:
			w.score -= int(event.reward)
			event.reward = 0
	w.prepared = false
	# A protected blocked head keeps shedding on the combat clock, even on
	# ticks when it is not due to move. Legal turns above cancel the contact.
	for s: SnakeState in w.snakes.values():
		if not s.star_blocked:
			continue
		if not s.alive or not s.has_effect(ItemRules.STAR, w.tick) or not collision_reason(w, s, s.direction) in ["wall", "self"]:
			s.star_blocked = false
		elif w.tick >= s.next_shrink_tick:
			s.next_shrink_tick = w.tick + BITE_TICKS
			_damage(w, s.id, "", true, events)
	DropRules.resolve(w, events)
	if w.beans.is_empty():
		spawn_food(w)
	ItemRules.spawn_due(w, events)
	MineRules.spawn_due(w, events)
	EnemySpawnRules.advance(w, events)
	SnakePerception.record(w)
	return {"world": w, "events": events}

static func advance_world(snapshot: WorldSnapshot, intents: Dictionary, boost_requested := false) -> Dictionary:
	var prepared := begin_tick(snapshot, boost_requested)
	return finish_tick(prepared.world, intents, prepared.events)

static func with_player_boost(snapshot: WorldSnapshot, requested: bool) -> WorldSnapshot:
	var staged := snapshot.copy()
	for s: SnakeState in staged.snakes.values():
		ItemRules.reconcile_speed(s, staged.tick, requested)
	return staged

static func predict_move(w: WorldSnapshot, id: String, direction: Vector2i, check_mines := true, collect_rewards := true) -> WorldSnapshot:
	return resolve_moves(w, {id: direction}, false, check_mines, false, "", collect_rewards).world

## Internal read-only-context fork. Mutations go through the same resolver;
## public copy()/predict_move() retain their fully independent snapshots.
static func plan_move(w: WorldSnapshot, id: String, direction: Vector2i, check_mines := true, collect_rewards := true) -> WorldSnapshot:
	# A legal AI move with no global contact/reward phases cannot affect any
	# other actor. Avoid constructing joint contact maps for each route cell.
	# All body/growth/bean rules still use the gameplay movement primitive.
	if not w.snakes[id].is_player and w.duels.is_empty() and (not check_mines or w.mines.is_empty()) and (not collect_rewards or w.moving_pickups.is_empty()):
		var protected_player := false
		var passive_pickup := false
		for actor: SnakeState in w.snakes.values():
			protected_player = protected_player or (actor.alive and actor.is_player and actor.has_effect(ItemRules.STAR, w.tick))
			if collect_rewards and actor.alive and actor.is_player:
				for anchor: Vector2i in w.items:
					passive_pickup = passive_pickup or ItemRules.covers_cell(anchor, w.items[anchor], actor.cells[0])
		if not protected_player and not passive_pickup and w.snakes[id].alive and collision_reason(w, w.snakes[id], direction, false) == "":
			var projected := w.copy(id, false, false)
			var events: Array[Dictionary] = []
			_move_body(projected, projected.snakes[id], direction, w.snakes[id].cells[0] + direction, collect_rewards, events)
			ScoreRules.award_events(projected, events)
			return projected
	return resolve_moves(w, {id: direction}, false, check_mines, false, "", collect_rewards, id).world

## Bounded clock-only forecast uses the actual period/phase functions, including
## effect expiration and held boost. Does not guess future pickups or inputs.
static func movement_offsets(w: WorldSnapshot, id: String, count := 4, horizon := -1) -> Array[int]:
	return movement_schedule(w, id, count, horizon).offsets

static func movement_schedule(w: WorldSnapshot, id: String, count := 4, horizon := -1) -> Dictionary:
	var s: SnakeState = w.snakes[id].copy()
	var offsets: Array[int] = []
	var result := {"offsets": offsets, "wait_remaining": s.remaining, "wait_period": s.period}
	if not s.alive or s.chance_ticks > 0:
		return result
	var cap := horizon if horizon >= 0 else count * ceili(maxf(s.base_period / (1.0 - SpeedRules.DOWN_PENALTY), ItemRules.SLOW_TICKS)) + 2
	for offset in range(1, cap + 1):
		var before_remaining := s.remaining
		var before_period := s.period
		ItemRules.reconcile_speed(s, w.tick + offset - int(w.prepared), s.boosting)
		if SpeedRules.advance_phase(s):
			offsets.append(offset)
			result.wait_remaining = before_remaining
			result.wait_period = before_period
			if offsets.size() >= count:
				break
	return result

static func spawn_food(w: WorldSnapshot) -> void:
	if not w.beans.is_empty(): return
	var blocked := w.occupied()
	if not w.pending_enemy_spawns.is_empty(): blocked.merge(EnemySpawnRules.reserved_cells(w))
	blocked.merge(PickupRules.occupied_items(w))
	var free: Array[Vector2i] = []
	for y in w.height:
		for x in w.width:
			var cell := Vector2i(x, y)
			if not blocked.has(cell) and not w.items.has(cell) and not MineRules.covered(w, cell):
				free.append(cell)
	if free.is_empty():
		w.food = Vector2i(-1, -1)
		return
	w.rng_state = (w.rng_state * 48271) % 2147483647
	w.add_bean(free[w.rng_state % free.size()])
	PickupRules.maybe_diamond(w)

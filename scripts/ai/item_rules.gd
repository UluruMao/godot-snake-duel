class_name ItemRules
extends RefCounted

const STAR := "star"
const SPEED_UP := "speed_up"
const SLOW_DOWN := "slow_down"
const DURATION_TICKS := 500 # 10 seconds of simulation time, never wall-clock time.
const SPEED_TICKS := SpeedRules.NORMAL_TICKS / (1.0 + SpeedRules.UP_BONUS)
const SLOW_TICKS := SpeedRules.NORMAL_TICKS / (1.0 - SpeedRules.DOWN_PENALTY)
const SPAWN_INTERVAL := 150
const PICKUPS := [STAR, SPEED_UP, SLOW_DOWN]
const SPEED_PICKUPS := [SPEED_UP, SLOW_DOWN]

static func apply_effect(w: WorldSnapshot, s: SnakeState, kind: String, duration := DURATION_TICKS) -> void:
	if not s.is_player or not kind in PICKUPS:
		return
	s.effects[kind] = w.tick + duration
	reconcile_speed(s, w.tick, s.boosting)

static func period_at(s: SnakeState, tick: int, boost: bool) -> float:
	return SpeedRules.period(s, tick, boost)

static func reconcile_speed(s: SnakeState, tick: int, boost: bool) -> void:
	var desired := period_at(s, tick, boost)
	if not is_equal_approx(s.period, desired):
		s.remaining *= desired / s.period
		s.period = desired
	s.boosting = s.is_player and boost and s.alive

static func expire(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	for s: SnakeState in w.snakes.values():
		for kind: String in s.effects.keys():
			if not s.has_effect(kind, w.tick):
				s = w.mutable_snake(s.id)
				s.effects.erase(kind)
				events.append({"type": "effect_expired", "id": s.id, "kind": kind})

static func collect(w: WorldSnapshot, s: SnakeState, events: Array[Dictionary]) -> void:
	var cell: Vector2i = s.cells[0]
	if not s.is_player: return
	var anchors: Array = w.items.keys()
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	for anchor: Vector2i in anchors:
		var kind: String = w.items[anchor]
		if not covers_cell(anchor, kind, cell): continue
		var refreshed := s.has_effect(kind, w.tick)
		apply_effect(w, s, kind)
		w.items.erase(anchor)
		events.append({"type": "pickup", "id": s.id, "kind": kind, "cell": cell,
			"refreshed": refreshed})

static func covers_cell(anchor: Vector2i, kind: String, cell: Vector2i) -> bool:
	return Rect2i(anchor, Vector2i.ONE * PickupRules.item_size(kind)).has_point(cell)

static func spawn_due(w: WorldSnapshot, events: Array[Dictionary] = []) -> void:
	PickupRules.spawn_due(w, events)
	if not w.auto_items or w.tick < w.next_item_tick:
		return
	w.next_item_tick = w.tick + SPAWN_INTERVAL
	var kind: String = SPEED_PICKUPS[w.item_sequence % SPEED_PICKUPS.size()]
	w.item_sequence += 1
	if kind in w.items.values():
		return # At most one of each kind in the normal arena.
	var free := PickupRules.free_anchors(w, 1)
	if free.is_empty():
		return
	w.rng_state = (w.rng_state * 48271) % 2147483647
	w.items[free[w.rng_state % free.size()]] = kind

static func effect_text(s: SnakeState, tick: int) -> String:
	var parts: Array[String] = []
	for kind: String in PICKUPS:
		if s.has_effect(kind, tick):
			parts.append("%s %.1fs" % [kind.replace("_", " ").to_upper(), (int(s.effects[kind]) - tick) * 0.02])
	return " | ".join(parts) if not parts.is_empty() else "No active effects"

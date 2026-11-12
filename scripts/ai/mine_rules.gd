class_name MineRules
extends RefCounted

const RADIUS := 1.0 # A moving 2x2 square footprint, not a larger sprite only.
const HEAD_RADIUS := 0.35
const SPEED := 1.25
const WARNING_TICKS := 50
const SCORE_STEP := 50000
const CAP := 8
const RETRY_TICKS := 25
const EPS := 0.0000001
const HEADINGS := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP,
	Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]

static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2.ONE * 0.5

static func advance(m: MineState, width: int, height: int, tick: int, moving := true) -> Array[Dictionary]:
	m.previous = m.position
	if tick < m.activation_tick:
		return []
	if not moving:
		return [{"from": m.position, "to": m.position, "t0": 0.0, "t1": 1.0}]
	var result := ItemGeometry.motion(m.position, m.velocity, RADIUS, Vector2(width, height), SnakeSimulation.TICK_SECONDS)
	m.position = result.position
	m.velocity = result.velocity
	return result.segments

static func contact(head_from: Vector2, head_to: Vector2, segments: Array[Dictionary]) -> float:
	return ItemGeometry.square_contact(head_from, head_to, segments, RADIUS, HEAD_RADIUS)

static func static_contact(w: WorldSnapshot, from: Vector2, to: Vector2) -> bool:
	for m: MineState in w.mines.values():
		if w.tick >= m.activation_tick and contact(from, to, [{"from": m.position, "to": m.position, "t0": 0.0, "t1": 1.0}]) < INF:
			return true
	return false

static func covered(w: WorldSnapshot, cell: Vector2i, include_warnings := true) -> bool:
	for m: MineState in w.mines.values():
		if (include_warnings or w.tick >= m.activation_tick) and ItemGeometry.covers(m.position, RADIUS, cell):
			return true
	return false

static func spawn_due(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	if not w.auto_mines:
		return
	if w.score >= w.next_mine_score:
		var crossed := floori(float(w.score - w.next_mine_score) / SCORE_STEP) + 1
		w.next_mine_score += crossed * SCORE_STEP
		w.pending_mines += mini(crossed, maxi(0, CAP - w.mines.size() - w.pending_mines))
	if w.pending_mines == 0 or w.tick < w.next_mine_retry:
		return
	while w.pending_mines > 0:
		var free := PickupRules.free_anchors(w, 2, true)
		if free.is_empty():
			w.next_mine_retry = w.tick + RETRY_TICKS
			return
		w.mine_rng_state = (w.mine_rng_state * 48271) % 2147483647
		var anchor: Vector2i = free[w.mine_rng_state % free.size()]
		w.mine_rng_state = (w.mine_rng_state * 48271) % 2147483647
		var mine := MineState.create(w.next_mine_id, Vector2(anchor) + Vector2.ONE, HEADINGS[w.mine_rng_state % HEADINGS.size()], w.tick + WARNING_TICKS)
		w.mines[mine.id] = mine
		w.next_mine_id += 1
		w.pending_mines -= 1
		events.append({"type": "mine_spawned", "id": mine.id, "cell": anchor})
	w.next_mine_retry = w.tick

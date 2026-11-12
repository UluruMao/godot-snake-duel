class_name TrajectoryCache
extends RefCounted

## Immutable motion results, scoped to one physical snapshot/mode. No World
## reference is retained, so memoization cannot create a reference cycle.
var width: int
var height: int
var base_tick: int
var observed_tick: int
var predictive: bool
var last_tick: int
var frames: Dictionary = {}
var poses: Dictionary = {}
var _projected: Dictionary
var _pickups: Dictionary = {}
var _signature: Array
var _contacts: Dictionary = {}
var _clearances: Dictionary = {}
var _stepped_pickups: Dictionary = {}

static func signature(w: WorldSnapshot) -> Array:
	var result: Array = [w.width, w.height, w.tick, w.prepared, w.mines.size(), w.moving_pickups.size()]
	for id in w.mines:
		var m: MineState = w.mines[id]
		result.append_array([id, m.position, m.previous, m.velocity, m.activation_tick])
	for id in w.moving_pickups:
		var p: MovingPickup = w.moving_pickups[id]
		result.append_array([id, p.kind, p.position, p.previous, p.velocity, p.tick])
	return result

func matches(w: WorldSnapshot) -> bool:
	return _signature == signature(w)

func _init(w: WorldSnapshot, predict := true) -> void:
	width = w.width
	height = w.height
	base_tick = w.tick - int(w.prepared)
	observed_tick = w.tick
	predictive = predict
	_signature = signature(w)
	last_tick = base_tick
	_projected = w.mines.duplicate()
	poses[base_tick] = _projected

func ensure(tick: int) -> void:
	while last_tick < tick:
		var frame: Dictionary = {}
		var states: Dictionary = {}
		for id in _projected:
			var mine: MineState = _projected[id].copy()
			frame[id] = MineRules.advance(mine, width, height, last_tick + 1 if predictive else observed_tick, predictive)
			states[id] = mine
		last_tick += 1
		frames[last_tick] = frame
		poses[last_tick] = states
		_projected = states

func pickup_projection(item: MovingPickup, target_tick: int) -> Dictionary:
	# Full-precision input pose is part of the key. Different branch stepping
	# can accumulate different float rounding; never merge those trajectories.
	var time_key := Vector3i(item.id, item.tick, target_tick)
	var pose_key := Vector4(item.position.x, item.position.y, item.velocity.x, item.velocity.y)
	if not _pickups.has(time_key): _pickups[time_key] = {}
	var values: Dictionary = _pickups[time_key]
	if not values.has(pose_key):
		var future := item.copy()
		var segments := future.advance(width, height, target_tick)
		values[pose_key] = {"item": future, "segments": segments}
	return values[pose_key]

func mine_contact(tick: int, id: int, from: Vector2, to: Vector2) -> float:
	var key := Vector2i(tick, id)
	var sweep := Vector4(from.x, from.y, to.x, to.y)
	if not _contacts.has(key): _contacts[key] = {}
	var values: Dictionary = _contacts[key]
	if not values.has(sweep): values[sweep] = MineRules.contact(from, to, frames[tick][id])
	return values[sweep]

## Deferred non-interacting rewards must reproduce per-tick rounding, not a
## single larger motion jump. Only immutable pickup data enters this cache.
func pickup_projection_tickwise(item: MovingPickup, first_tick: int, end_tick: int) -> MovingPickup:
	var time_key := Vector4i(item.id, item.tick, first_tick, end_tick)
	var pose_key := Vector4(item.position.x, item.position.y, item.velocity.x, item.velocity.y)
	if not _stepped_pickups.has(time_key): _stepped_pickups[time_key] = {}
	var values: Dictionary = _stepped_pickups[time_key]
	if not values.has(pose_key):
		var future := item.copy()
		for tick in range(first_tick, end_tick + 1): future.advance(width, height, tick)
		values[pose_key] = future
	return values[pose_key]

func mine_clearance(tick: int, id: int, from: Vector2, to: Vector2) -> float:
	var key := Vector2i(tick, id)
	var sweep := Vector4(from.x, from.y, to.x, to.y)
	if not _clearances.has(key): _clearances[key] = {}
	var values: Dictionary = _clearances[key]
	if not values.has(sweep):
		var minimum := INF
		for segment in frames[tick][id]:
			var delta: Vector2 = from.lerp(to, segment.t0) - Vector2(segment.from)
			var relative: Vector2 = (to - from) * (segment.t1 - segment.t0) - (Vector2(segment.to) - Vector2(segment.from))
			minimum = minf(minimum, ItemGeometry.square_clearance(delta, delta + relative, MineRules.RADIUS, MineRules.HEAD_RADIUS))
		values[sweep] = minimum
	return values[sweep]

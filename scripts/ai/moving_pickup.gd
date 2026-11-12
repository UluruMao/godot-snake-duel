class_name MovingPickup
extends RefCounted

var id := 0
var kind := "diamond"
var position := Vector2.ZERO
var previous := Vector2.ZERO
var velocity := Vector2.ZERO
var tick := 0

static func create(key: int, type: String, point: Vector2, heading := Vector2.RIGHT, at_tick := 0) -> MovingPickup:
	var item := MovingPickup.new()
	item.id = key
	item.kind = type
	item.position = point
	item.previous = point
	item.velocity = heading.normalized() * MineRules.SPEED
	item.tick = at_tick
	return item

func half_size() -> float:
	return 1.0 if kind == "bomb" else 0.5

func copy() -> MovingPickup:
	var item := MovingPickup.new()
	item.id = id
	item.kind = kind
	item.position = position
	item.previous = previous
	item.velocity = velocity
	item.tick = tick
	return item

func advance(width: int, height: int, target_tick: int) -> Array[Dictionary]:
	previous = position
	var seconds := maxf(0, target_tick - tick) * SnakeSimulation.TICK_SECONDS
	var result := ItemGeometry.motion(position, velocity, half_size(), Vector2(width, height), seconds)
	position = result.position
	velocity = result.velocity
	tick = target_tick
	return result.segments

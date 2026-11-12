class_name MineState
extends RefCounted

var id := 0
var position := Vector2.ZERO # Grid units; cell centres are (x + .5, y + .5).
var previous := Vector2.ZERO
var velocity := Vector2.ZERO # Grid units per second.
var activation_tick := 0

static func create(key: int, point: Vector2, heading := Vector2.ZERO, active_at := 0) -> MineState:
	var m := MineState.new()
	m.id = key
	m.position = point
	m.previous = point
	m.velocity = heading.normalized() * MineRules.SPEED
	m.activation_tick = active_at
	return m

func copy() -> MineState:
	var m := MineState.new()
	m.id = id
	m.position = position
	m.previous = previous
	m.velocity = velocity
	m.activation_tick = activation_tick
	return m

class_name SnakeState
extends RefCounted

var id: String
var archetype := "" # Independent of unique lifetime ID for duplicate enemies.
var cells: Array[Vector2i] = [] # Head first; never shared between snapshots.
var direction := Vector2i.RIGHT
var pending_growth := 0
var period := SpeedRules.NORMAL_TICKS
var base_period := SpeedRules.NORMAL_TICKS
var boosting := false
var collects_food := true
var reward_multiplier := 0
var remaining := SpeedRules.NORMAL_TICKS
var is_player := false
var alive := true
var chance_ticks := 0
var death_reason := ""
var death_drops_queued := false
var entry_remaining := 0 # Real tail segments still outside the arena.
var moves := 0
var food_eaten := 0
var diamonds_eaten := 0
var effects: Dictionary = {} # kind -> absolute expiration tick (exclusive).
var next_shrink_tick := 0
var star_blocked := false

static func create(key: String, body: Array, heading: Vector2i, ticks: float, player := false) -> SnakeState:
	var s := SnakeState.new()
	s.id = key
	s.archetype = key if key in ["pink", "purple", "red", "golden"] else ""
	s.cells.assign(body)
	s.direction = heading
	s.period = ticks
	s.base_period = ticks
	s.remaining = ticks
	s.is_player = player
	return s

func copy() -> SnakeState:
	var s := SnakeState.create(id, cells, direction, period, is_player)
	s.archetype = archetype
	s.remaining = remaining
	s.base_period = base_period
	s.boosting = boosting
	s.collects_food = collects_food
	s.reward_multiplier = reward_multiplier
	s.pending_growth = pending_growth
	s.alive = alive
	s.chance_ticks = chance_ticks
	s.death_reason = death_reason
	s.death_drops_queued = death_drops_queued
	s.entry_remaining = entry_remaining
	s.moves = moves
	s.food_eaten = food_eaten
	s.diamonds_eaten = diamonds_eaten
	s.effects = effects.duplicate()
	s.next_shrink_tick = next_shrink_tick
	s.star_blocked = star_blocked
	return s

func has_effect(kind: String, tick: int) -> bool:
	return int(effects.get(kind, 0)) > tick

func refresh_entry(width: int, height: int) -> void:
	entry_remaining = 0
	for cell in cells:
		entry_remaining += int(cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height)

class_name WorldSnapshot
extends RefCounted

var width := GridConfig.W
var height := GridConfig.H
var tick := 0
var prepared := false # True only between begin_tick and finish_tick.
var snakes: Dictionary = {}
var walls: Dictionary = {}
var beans: Dictionary = {} # Cell -> true. Natural and dropped beans share rules.
## Single-food fixture compatibility. Assigning replaces the entire bean set.
var food: Vector2i:
	get: return beans.keys()[0] if not beans.is_empty() else Vector2i(-1, -1)
	set(value): beans = {value: true} if value.x >= 0 else {}
var drop_rules: Dictionary = {}
var drop_rng_state := 1
var pending_drops: Array[Dictionary] = []
var next_drop_retry := 0
var rng_state: int = 1
var items: Dictionary = {} # Top-left anchor -> player-only pickup kind.
var moving_pickups: Dictionary = {} # ID -> MovingPickup (diamond/bomb).
var obstacles: Dictionary = {} # Edible generated cells; walls remain fixed lab terrain.
var next_pickup_id := 1
var pickup_rng_state := 1
var auto_diamonds := false
var auto_obstacles := false
var next_star_tick := 3000
var next_bomb_tick := 3000
var next_obstacle_tick := -1
var bomb_this_tick := false
var mines: Dictionary = {} # stable integer ID -> MineState.
var score := 0
var auto_mines := false
var next_mine_score := 50000
var pending_mines := 0
var next_mine_retry := 0
var next_mine_id := 1
var mine_rng_state := 1
var duels: Dictionary = {} # canonical pair -> participants, headings and next bite tick.
var auto_items := false
var next_item_tick := 150
var item_sequence := 0
var note := ""
var auto_enemies := false
var enemy_rules: Dictionary = {}
var pending_enemy_spawns: Dictionary = {}
var enemy_type_ready: Dictionary = {}
var enemy_rng_state := 1
var next_enemy_serial := 1
var next_enemy_spawn_tick := 150
var enemy_block_until := 0
var snake_observations: Dictionary = {} # ID -> immutable completed poses (reaction delay).
var _borrowed_snakes: Dictionary = {} # Internal prediction forks detach before writes.
var _borrowed_obstacles := false
var _borrowed_beans := false
var _trajectory_caches: Dictionary = {}
var _runtime_head_cache: Dictionary = {}
var _cache_runtime_heads := false

## Only the main thread's immutable prepared tick enables this cache. Copies
## and worker snapshots start disabled; a new validation context clears it.
func begin_runtime_validation() -> void:
	_runtime_head_cache.clear()
	_cache_runtime_heads = true

func trajectories(predictive := true) -> TrajectoryCache:
	if not _trajectory_caches.has(predictive) or not _trajectory_caches[predictive].matches(self):
		_trajectory_caches[predictive] = TrajectoryCache.new(self, predictive)
	return _trajectory_caches[predictive]

func copy(prediction_actor := "", copy_mines := true, copy_pickups := true, copy_observations := true) -> WorldSnapshot:
	var w := WorldSnapshot.new()
	w.width = width
	w.height = height
	w.tick = tick
	w.prepared = prepared
	w.beans = beans.duplicate() if prediction_actor == "" else beans
	w._borrowed_beans = prediction_actor != ""
	w.drop_rules = drop_rules.duplicate(true) if prediction_actor == "" else drop_rules
	w.drop_rng_state = drop_rng_state
	w.pending_drops.assign(pending_drops.duplicate(true) if prediction_actor == "" else pending_drops)
	w.next_drop_retry = next_drop_retry
	w.rng_state = rng_state
	w.walls = walls.duplicate() if prediction_actor == "" else walls
	w.items = items.duplicate()
	w.obstacles = obstacles.duplicate() if prediction_actor == "" else obstacles
	w._borrowed_obstacles = prediction_actor != ""
	w.next_pickup_id = next_pickup_id
	w.pickup_rng_state = pickup_rng_state
	w.auto_diamonds = auto_diamonds
	w.auto_obstacles = auto_obstacles
	w.next_star_tick = next_star_tick
	w.next_bomb_tick = next_bomb_tick
	w.next_obstacle_tick = next_obstacle_tick
	w.bomb_this_tick = bomb_this_tick
	for id in moving_pickups:
		w.moving_pickups[id] = moving_pickups[id].copy() if prediction_actor == "" or copy_pickups else moving_pickups[id]
	w.score = score
	w.auto_mines = auto_mines
	w.next_mine_score = next_mine_score
	w.pending_mines = pending_mines
	w.next_mine_retry = next_mine_retry
	w.next_mine_id = next_mine_id
	w.mine_rng_state = mine_rng_state
	for id in mines:
		w.mines[id] = (mines[id] as MineState).copy() if prediction_actor == "" or copy_mines else mines[id]
	w.duels = duels.duplicate(true)
	w.auto_items = auto_items
	w.next_item_tick = next_item_tick
	w.item_sequence = item_sequence
	w.note = note
	w.auto_enemies = auto_enemies
	w.enemy_rules = enemy_rules.duplicate(true) if prediction_actor == "" else enemy_rules
	w.pending_enemy_spawns = pending_enemy_spawns.duplicate(true) if prediction_actor == "" else pending_enemy_spawns
	w.enemy_type_ready = enemy_type_ready.duplicate() if prediction_actor == "" else enemy_type_ready
	w.enemy_rng_state = enemy_rng_state
	w.next_enemy_serial = next_enemy_serial
	w.next_enemy_spawn_tick = next_enemy_spawn_tick
	w.enemy_block_until = enemy_block_until
	w.snake_observations = snake_observations.duplicate(true) if prediction_actor == "" and copy_observations else snake_observations
	for id in snakes:
		if prediction_actor == "" or id == prediction_actor:
			w.snakes[id] = (snakes[id] as SnakeState).copy()
		else:
			w.snakes[id] = snakes[id]
			w._borrowed_snakes[id] = true
	return w

func mutable_snake(id: String) -> SnakeState:
	if _borrowed_snakes.has(id):
		snakes[id] = snakes[id].copy()
		_borrowed_snakes.erase(id)
	return snakes[id]

func remove_obstacle(cell: Vector2i) -> void:
	if _borrowed_obstacles:
		obstacles = obstacles.duplicate()
		_borrowed_obstacles = false
	obstacles.erase(cell)

func add_bean(cell: Vector2i) -> void:
	if _borrowed_beans:
		beans = beans.duplicate()
		_borrowed_beans = false
	beans[cell] = true

func consume_bean(cell: Vector2i) -> bool:
	if not beans.has(cell): return false
	if _borrowed_beans:
		beans = beans.duplicate()
		_borrowed_beans = false
	beans.erase(cell)
	return true

func restore_prediction_actors(source: WorldSnapshot, focal_id: String) -> void:
	for id in source.snakes:
		if id != focal_id:
			snakes[id] = source.snakes[id]
			_borrowed_snakes[id] = true

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func occupied(except_id := "") -> Dictionary:
	var result := walls.duplicate()
	result.merge(obstacles)
	for id in snakes:
		var s: SnakeState = snakes[id]
		if not s.alive or id == except_id:
			continue
		for cell in s.cells:
			if in_bounds(cell): result[cell] = true
	return result

func in_combat(id: String) -> bool:
	for duel: Dictionary in duels.values():
		if id == duel.a or id == duel.b:
			return true
	return false

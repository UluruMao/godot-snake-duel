class_name AIScenarios
extends RefCounted

## Curated playable demonstrations; low-level edge cases live in tests/fixtures.
const NAMES := ["Live arena", "Food safety", "Crossing routes", "Moving tail", "Pink reaction", "Red interception", "Golden escape", "Head duel", "Star decisions", "Mixed speeds", "Mine prediction", "Diamond interception", "Star and obstacles", "Bomb and loot", "Enemy arrivals", "Bean replenishment"]
const DESCRIPTIONS := ["Survive, collect and outmaneuver four enemy archetypes.", "Compare a tempting short route with a validated escape.", "A moving rival can invalidate the shortest food route.", "Follow a vacating tail through a closed loop.", "Down + one step, then Right; advance to tick 15 to cut off Pink.", "Inspect Red's interception and surrounding decisions.", "Golden preserves exits without pursuing food or attacking.", "Heads consume length over time. Turn to escape.", "1 toggles Star: Red retreats and Golden creates distance.", "2 / 3 toggle speed effects; hold Space to combine boost.", "M compares current-position and arrival-time mine avoidance.", "B compares bean collection with a moving diamond intercept.", "Star lets the player eat obstacles. Step toward the rocks.", "One step collects a bomb, clears rivals and generates loot.", "Four independent Purple snakes enter from distant boundaries.", "Eat both beans: only the last triggers natural replenishment."]
const GROUPS := ["PLAY", "AI", "AI", "AI", "AI", "AI", "AI", "COMBAT", "COMBAT", "COMBAT", "WORLD", "WORLD", "WORLD", "WORLD", "WORLD", "WORLD"]

static func _world(seed_value: int) -> WorldSnapshot:
	var w := WorldSnapshot.new()
	w.rng_state = maxi(1, seed_value % 2147483647)
	w.mine_rng_state = w.rng_state
	w.pickup_rng_state = w.rng_state
	return w

static func make_arena(seed_value: int, config: EnemySpawnConfig, drop_config: DropConfig = null) -> WorldSnapshot:
	var w := _world(seed_value)
	w.auto_items = true
	w.auto_mines = true
	w.auto_diamonds = true
	w.auto_obstacles = true
	w.snakes.player = SnakeState.create("player", _line(Vector2i(w.width / 3, w.height * 2 / 3), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
	if config != null: EnemySpawnRules.configure(w, config.to_rules(), seed_value)
	DropRules.configure(w, drop_config if drop_config != null else preload("res://resources/drops.tres"), seed_value)
	SnakeSimulation.spawn_food(w)
	return w

static func make(index: int, seed_value := 1) -> WorldSnapshot:
	if index == 0: return make_arena(seed_value, preload("res://resources/enemy_spawning.tres"))
	var w := _world(seed_value)
	w.food = Vector2i(14, 8)
	match index:
		1, 2, 3:
			w.snakes.purple = SnakeState.create("purple", _line(Vector2i(10, 8), 8), Vector2i.RIGHT, EnemyProfile.purple().interval_ticks)
			if index == 1:
				for x in range(12, 17):
					w.walls[Vector2i(x, 7)] = true
					w.walls[Vector2i(x, 9)] = true
				w.walls[Vector2i(16, 8)] = true
			elif index == 2:
				w.snakes.pink = SnakeState.create("pink", [Vector2i(11, 7), Vector2i(11, 6), Vector2i(11, 5)], Vector2i.DOWN, EnemyProfile.pink().interval_ticks)
				w.snakes.pink.remaining = 1
			else:
				w.snakes.purple = SnakeState.create("purple", [Vector2i(10, 8), Vector2i(10, 9), Vector2i(11, 9), Vector2i(11, 8)], Vector2i.UP, EnemyProfile.purple().interval_ticks)
				for y in w.height:
					for x in w.width:
						if not Vector2i(x, y) in w.snakes.purple.cells: w.walls[Vector2i(x, y)] = true
				w.food = Vector2i(-1, -1)
		4:
			w.food = Vector2i(24, 8)
			w.snakes.player = SnakeState.create("player", _line(Vector2i(11, 7), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.player.remaining = 1
			w.snakes.pink = enemy("pink", Vector2i(10, 8))
		5, 8:
			w.snakes.player = SnakeState.create("player", _line(Vector2i(14, 9), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.red = enemy("red", Vector2i(18, 7))
			w.food = Vector2i(25, 4)
			if index == 8:
				w.snakes.golden = enemy("golden", Vector2i(22, 13), Vector2i.UP)
				ItemRules.apply_effect(w, w.snakes.player, ItemRules.STAR, 100)
		6:
			w.snakes.player = SnakeState.create("player", _line(Vector2i(19, 10), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.golden = enemy("golden", Vector2i(23, 10), Vector2i.UP)
			for x in range(22, 29):
				w.walls[Vector2i(x, 6)] = true
				w.walls[Vector2i(x, 14)] = true
			for y in range(6, 15):
				w.walls[Vector2i(28, y)] = true
				if y != 10: w.walls[Vector2i(22, y)] = true
			for y in range(9, 14): w.walls[Vector2i(25, y)] = true
		7:
			w.food = Vector2i(27, 3)
			w.snakes.player = SnakeState.create("player", _line(Vector2i(10, 8), 8), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.red = SnakeState.create("red", _line(Vector2i(12, 8), 6, Vector2i.LEFT), Vector2i.LEFT, EnemyProfile.red().interval_ticks)
			w.snakes.player.remaining = 1
			w.snakes.red.remaining = 1
			w = SnakeSimulation.resolve_moves(w, {"player": Vector2i.RIGHT, "red": Vector2i.LEFT}).world
		9:
			w.snakes.player = SnakeState.create("player", _line(Vector2i(10, 12), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.pink = enemy("pink", Vector2i(6, 4))
			w.snakes.purple = enemy("purple", Vector2i(23, 6))
			w.snakes.red = enemy("red", Vector2i(14, 2))
			w.snakes.golden = enemy("golden", Vector2i(27, 14), Vector2i.LEFT)
		10:
			w.snakes.purple = enemy("purple", Vector2i(10, 8))
			w.snakes.purple.remaining = 1
			w.mines[1] = MineState.create(1, Vector2(11.5, 9.95), Vector2.UP)
			w.walls[Vector2i(9, 7)] = true
		11:
			w.snakes.purple = enemy("purple", Vector2i(10, 8))
			w.snakes.purple.remaining = 1
			w.food = Vector2i(11, 4)
			w.moving_pickups[1] = MovingPickup.create(1, PickupRules.DIAMOND, Vector2(14, 7.55), Vector2.LEFT)
		12:
			w.food = Vector2i(22, 4)
			w.snakes.player = SnakeState.create("player", _line(Vector2i(10, 8), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			for x in range(11, 16): w.obstacles[Vector2i(x, 8)] = true
			ItemRules.apply_effect(w, w.snakes.player, ItemRules.STAR)
		13:
			w.snakes.player = SnakeState.create("player", _line(Vector2i(16, 12), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.pink = enemy("pink", Vector2i(6, 4))
			w.snakes.purple = enemy("purple", Vector2i(23, 6))
			w.snakes.red = enemy("red", Vector2i(14, 2))
			w.snakes.golden = enemy("golden", Vector2i(27, 14), Vector2i.LEFT)
			w.moving_pickups[1] = MovingPickup.create(1, PickupRules.BOMB, MineRules.center(w.snakes.player.cells[0]), Vector2.ZERO)
			w.next_pickup_id = 2
			DropRules.configure(w, DropConfig.new(), seed_value)
		14:
			var config: EnemySpawnConfig = preload("res://resources/enemy_spawning.tres").duplicate(true)
			config.first_spawn_delay = 0.04
			config.spawn_interval = 0.08
			config.minimum_head_distance = 3
			for type in config.types:
				type.max_alive = 4 if type.archetype == "purple" else 0
				if type.archetype == "purple": type.unlock_score = 0
			w = make_arena(seed_value, config)
			w.auto_items = false
			w.auto_mines = false
			w.auto_diamonds = false
			w.auto_obstacles = false
			w.moving_pickups.clear()
		15:
			w.snakes.player = SnakeState.create("player", _line(Vector2i(6, 8), 5), Vector2i.RIGHT, SpeedRules.NORMAL_TICKS, true)
			w.snakes.player.remaining = 1
			w.snakes.purple = enemy("purple", Vector2i(23, 6))
			w.food = Vector2i(7, 8)
			w.add_bean(Vector2i(8, 8))
	for s: SnakeState in w.snakes.values():
		if not s.is_player:
			var p := EnemyProfile.for_kind(EnemySpawnRules.kind(s))
			s.reward_multiplier = p.reward_multiplier
			s.collects_food = p.collects_food
	w.note = DESCRIPTIONS[index]
	return w

static func enemy(kind: String, head: Vector2i, heading := Vector2i.RIGHT) -> SnakeState:
	var p := EnemyProfile.for_kind(kind)
	var s := SnakeState.create(kind, _line(head, p.initial_length, heading), heading, p.interval_ticks)
	s.reward_multiplier = p.reward_multiplier
	s.collects_food = p.collects_food
	return s

static func _line(head: Vector2i, length: int, direction := Vector2i.RIGHT) -> Array[Vector2i]:
	var body: Array[Vector2i] = []
	for i in length: body.append(head - direction * i)
	return body

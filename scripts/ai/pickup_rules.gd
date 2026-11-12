class_name PickupRules
extends RefCounted

const DIAMOND := "diamond"
const BOMB := "bomb"
const SPECIAL_INTERVAL := 3000 # Both Star and bomb: 60 simulation seconds.
const OBSTACLE_INTERVAL := 500
const OBSTACLE_SCORE := 200000

static func random(w: WorldSnapshot) -> int:
	w.pickup_rng_state = (w.pickup_rng_state * 48271) % 2147483647
	return w.pickup_rng_state

static func item_size(kind: String) -> int:
	return 2 if kind in [ItemRules.STAR, BOMB] else 1

static func occupied_items(w: WorldSnapshot) -> Dictionary:
	var result: Dictionary = {}
	for anchor: Vector2i in w.items:
		var size := item_size(w.items[anchor])
		for y in size:
			for x in size:
				result[anchor + Vector2i(x, y)] = true
	for item: MovingPickup in w.moving_pickups.values():
		var half := item.half_size()
		var lower := Vector2i((item.position - Vector2.ONE * half).floor())
		var upper := Vector2i((item.position + Vector2.ONE * half).ceil())
		for y in range(lower.y, upper.y):
			for x in range(lower.x, upper.x):
				if ItemGeometry.covers(item.position, half, Vector2i(x, y)):
					result[Vector2i(x, y)] = true
	return result

static func free_anchors(w: WorldSnapshot, size: int, keep_head_distance := false) -> Array[Vector2i]:
	var blocked := w.occupied()
	if not w.pending_enemy_spawns.is_empty(): blocked.merge(EnemySpawnRules.reserved_cells(w))
	blocked.merge(occupied_items(w))
	blocked.merge(w.beans)
	# Rasterise a moving footprint once, rather than scanning every mine for
	# every cell in the candidate placement loops.
	for mine: MineState in w.mines.values():
		var lower := Vector2i((mine.position - Vector2.ONE).floor())
		var upper := Vector2i((mine.position + Vector2.ONE).ceil())
		for y in range(lower.y, upper.y):
			for x in range(lower.x, upper.x):
				blocked[Vector2i(x, y)] = true
	var free: Array[Vector2i] = []
	for y in maxi(0, w.height - size + 1):
		for x in maxi(0, w.width - size + 1):
			var anchor := Vector2i(x, y)
			var valid := true
			for dy in size:
				for dx in size:
					var cell := anchor + Vector2i(dx, dy)
					if blocked.has(cell):
						valid = false
						break
					if keep_head_distance:
						for s: SnakeState in w.snakes.values():
							if s.alive and absi(cell.x - s.cells[0].x) + absi(cell.y - s.cells[0].y) < 3:
								valid = false
				if not valid: break
			if valid: free.append(anchor)
	return free

static func moving_count(w: WorldSnapshot, kind: String) -> int:
	var count := 0
	for item: MovingPickup in w.moving_pickups.values():
		count += int(item.kind == kind)
	return count

static func spawn_moving(w: WorldSnapshot, kind: String, safe := false) -> bool:
	var size := item_size(kind)
	var free := free_anchors(w, size, safe)
	if free.is_empty(): return false
	var anchor := free[random(w) % free.size()]
	var heading: Vector2 = MineRules.HEADINGS[random(w) % (4 if kind == DIAMOND else 8)]
	var item := MovingPickup.create(w.next_pickup_id, kind, Vector2(anchor) + Vector2.ONE * size * 0.5, heading, w.tick)
	w.moving_pickups[item.id] = item
	w.next_pickup_id += 1
	return true

static func maybe_diamond(w: WorldSnapshot) -> void:
	if not w.auto_diamonds: return
	var chance := float(w.drop_rules.get("natural_diamond_chance", 0.1))
	var hit := random(w) % 10 == 0 if w.drop_rules.is_empty() else float(random(w)) / 2147483647.0 < chance
	if hit:
		spawn_moving(w, DIAMOND)

static func spawn_obstacles(w: WorldSnapshot, amount: int) -> int:
	var remaining := maxi(0, floori(w.width * w.height / 3.0) - w.obstacles.size())
	var free := free_anchors(w, 1, true)
	var spawned := 0
	for i in mini(amount, mini(remaining, free.size())):
		var index := random(w) % free.size()
		var cell := free[index]
		free.remove_at(index)
		w.obstacles[cell] = true
		spawned += 1
	return spawned

static func spawn_due(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	if w.auto_obstacles and w.score >= OBSTACLE_SCORE:
		if w.next_obstacle_tick < 0:
			w.next_obstacle_tick = w.tick + OBSTACLE_INTERVAL
		elif w.tick >= w.next_obstacle_tick:
			w.next_obstacle_tick = w.tick + OBSTACLE_INTERVAL
			if not w.bomb_this_tick:
				var count := spawn_obstacles(w, 1)
				if count > 0: events.append({"type": "obstacles_spawned", "count": count})
	if not w.auto_items: return
	if w.tick >= w.next_star_tick:
		w.next_star_tick = w.tick + SPECIAL_INTERVAL
		if not ItemRules.STAR in w.items.values():
			var free := free_anchors(w, 2, true)
			if not free.is_empty(): w.items[free[random(w) % free.size()]] = ItemRules.STAR
	if w.tick >= w.next_bomb_tick:
		w.next_bomb_tick = w.tick + SPECIAL_INTERVAL
		if moving_count(w, BOMB) == 0 and spawn_moving(w, BOMB, true):
			events.append({"type": "bomb_spawned"})
			if w.score >= OBSTACLE_SCORE and not w.bomb_this_tick:
				var count := spawn_obstacles(w, 9 + random(w) % 4)
				events.append({"type": "obstacles_spawned", "count": count})

## Collect moving rewards after ordinary collision resolution. Head paths
## come from resolved movement; bodies never pick up diamonds or bombs.
static func resolve(w: WorldSnapshot, heads: Dictionary, events: Array[Dictionary], moving: bool, only_actor := "", motion: TrajectoryCache = null) -> void:
	var contacts: Array[Dictionary] = []
	for item: MovingPickup in w.moving_pickups.values():
		var segments: Array[Dictionary] = []
		if moving:
			if motion != null:
				var projection := motion.pickup_projection(item, w.tick)
				segments = projection.segments
				w.moving_pickups[item.id] = projection.item
			else:
				segments = item.advance(w.width, w.height, w.tick)
		else:
			segments.append({"from": item.position, "to": item.position, "t0": 0.0, "t1": 1.0})
		for id in heads:
			var s: SnakeState = w.snakes[id]
			if not s.alive or (only_actor != "" and only_actor != id) or (item.kind == BOMB and not s.is_player): continue
			var time := ItemGeometry.square_contact(heads[id].from, heads[id].to, segments, item.half_size())
			if time < INF:
				contacts.append({"time": roundi(time * 100000000), "item": item.id, "snake": id})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time != b.time: return a.time < b.time
		if a.item != b.item: return a.item < b.item
		return a.snake < b.snake)
	for contact in contacts:
		if not w.moving_pickups.has(contact.item) or not w.snakes[contact.snake].alive: continue
		var item: MovingPickup = w.moving_pickups[contact.item]
		var actor: SnakeState = w.mutable_snake(contact.snake)
		w.moving_pickups.erase(contact.item)
		var cell := actor.cells[0]
		if item.kind == DIAMOND:
			actor.pending_growth += 3
			actor.diamonds_eaten += 1
			events.append({"type": "diamond", "id": actor.id, "item": item.id, "cell": cell})
		else:
			w.obstacles = {}
			w.mines.clear()
			w.pending_mines = 0
			w.pending_enemy_spawns = {}
			w.next_mine_retry = w.tick
			w.duels.clear()
			w.bomb_this_tick = true
			events.append({"type": "pickup", "kind": BOMB, "id": actor.id, "cell": cell, "refreshed": false})
			for enemy: SnakeState in w.snakes.values():
				if enemy.alive and not enemy.is_player:
					SnakeSimulation._kill(w, enemy.id, "bomb", actor.id, events)

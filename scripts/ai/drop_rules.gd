class_name DropRules
extends RefCounted

static func configure(w: WorldSnapshot, config: DropConfig, seed_value: int) -> void:
	w.drop_rules = config.to_rules()
	w.drop_rng_state = maxi(1, seed_value % 2147483647)
	w.pending_drops.clear()
	w.next_drop_retry = w.tick

static func random(w: WorldSnapshot) -> int:
	w.drop_rng_state = (w.drop_rng_state * 48271) % 2147483647
	return w.drop_rng_state

static func roll(w: WorldSnapshot, chance: float) -> bool:
	return float(random(w)) / 2147483647.0 < clampf(chance, 0, 1)

static func difficulty(w: WorldSnapshot, actor: SnakeState) -> int:
	return int(w.drop_rules.player_difficulty) if actor.is_player else EnemySpawnRules.profile_for(w, actor).difficulty

static func segment_probability(w: WorldSnapshot, stars: int) -> float:
	return clampf(float(w.drop_rules.segment_chance) + max(0, stars - 1) * float(w.drop_rules.difficulty_bonus), 0, 1)

## Returns rolled segment positions. The floor is applied BEFORE conversion.
static func roll_cells(w: WorldSnapshot, cells: Array, stars: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var skipped: Array[Vector2i] = []
	var chance := segment_probability(w, stars)
	for cell: Vector2i in cells:
		if roll(w, chance): result.append(cell)
		else: skipped.append(cell)
	var minimum := mini(cells.size(), int(w.drop_rules.minimum))
	while result.size() < minimum and not skipped.is_empty():
		var index := random(w) % skipped.size()
		result.append(skipped[index])
		skipped.remove_at(index)
	return result

## Called only at the end of completed REAL ticks. Forecasts never roll loot.
static func resolve(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	if w.drop_rules.is_empty() or not bool(w.drop_rules.enabled): return
	var added := false
	for event: Dictionary in events.duplicate():
		if event.type != "died" or not w.snakes.has(event.id): continue
		var actor: SnakeState = w.snakes[event.id]
		if actor.death_drops_queued or (actor.is_player and not bool(w.drop_rules.player_drops)): continue
		actor = w.mutable_snake(actor.id)
		actor.death_drops_queued = true
		var cells: Array = event.get("body", actor.cells)
		var rolled := roll_cells(w, cells, difficulty(w, actor))
		var diamonds := 0
		for cell in rolled:
			var kind := PickupRules.DIAMOND if roll(w, float(w.drop_rules.diamond_chance)) else "bean"
			diamonds += int(kind == PickupRules.DIAMOND)
			w.pending_drops.append({"source": actor.id, "cell": cell, "kind": kind})
		added = added or not rolled.is_empty()
		events.append({"type": "drops_rolled", "id": actor.id, "count": rolled.size(), "diamonds": diamonds})
	if w.pending_drops.is_empty() or (not added and w.tick < w.next_drop_retry): return
	# Build free placement once per death/retry batch. Beans occupy cells for
	# spawning, but remain traversable and collectable for every snake.
	var free: Dictionary = {}
	for cell in PickupRules.free_anchors(w, 1): free[cell] = true
	var waiting: Array[Dictionary] = []
	for drop in w.pending_drops:
		if free.is_empty():
			waiting.append(drop)
			continue
		var cell: Vector2i = drop.cell
		if not free.has(cell):
			var nearest: Array[Vector2i] = []
			var distance := 2147483647
			for available: Vector2i in free:
				var d := absi(available.x - cell.x) + absi(available.y - cell.y)
				if d < distance:
					distance = d
					nearest.assign([available])
				elif d == distance: nearest.append(available)
			cell = nearest[random(w) % nearest.size()]
		free.erase(cell)
		if drop.kind == "bean": w.add_bean(cell)
		else:
			var heading: Vector2 = MineRules.HEADINGS[random(w) % 4]
			var item := MovingPickup.create(w.next_pickup_id, PickupRules.DIAMOND, MineRules.center(cell), heading, w.tick)
			w.moving_pickups[item.id] = item
			w.next_pickup_id += 1
		events.append({"type": "drop_spawned", "id": drop.source, "kind": drop.kind, "cell": cell})
	w.pending_drops = waiting
	w.next_drop_retry = w.tick + int(w.drop_rules.retry)

class_name SnakeAI
extends RefCounted

static func choose_move(w: WorldSnapshot, id: String, profile: EnemyProfile) -> AIDecision:
	var started := Time.get_ticks_usec()
	var reaction_ticks := clampi(profile.opponent_reaction_ticks, 0, SnakePerception.MAX_DELAY_TICKS)
	var observation_tick := SnakePerception.observed_tick(w, reaction_ticks)
	w = SnakePerception.view(w, id, reaction_ticks)
	var s: SnakeState = w.snakes[id]
	var decision := AIDecision.new()
	decision.direction = s.direction
	decision.target = w.food
	decision.snapshot_tick = w.tick
	decision.opponent_reaction_ticks = reaction_ticks
	decision.opponent_observation_tick = observation_tick
	decision.origin = s.cells[0]
	var search := GridSearch.new()
	search.limit = profile.search_budget
	decision.mine_prediction = profile.mine_prediction
	var mines: MineForecast = null
	if not w.mines.is_empty() or not w.moving_pickups.is_empty():
		mines = MineForecast.new(w, search, profile.mine_prediction)
		decision.mine_forecast = mines
	var blocked := w.occupied()
	blocked.erase(s.cells[0])
	if s.pending_growth == 0:
		blocked.erase(s.cells[-1])
	if profile.planner == EnemyProfile.Planner.BFS_ONLY:
		for m: MineState in w.mines.values():
			if w.tick >= m.activation_tick:
				blocked[Vector2i(m.position.floor())] = true
		var scan := search.scan(w, s.cells[0], blocked, w.food if w.beans.size() <= 1 else Vector2i(-1, -1))
		var goals := _bean_targets(w, scan, search)
		decision.target = goals[0] if not goals.is_empty() else w.food
		decision.path = GridSearch.path(scan, decision.target)
		if decision.path.size() > 1:
			decision.direction = decision.path[1] - decision.path[0]
		decision.behavior = "BFS ONLY"
		decision.reason = "Shortest route; no space, growth or head prediction"
		return _finish(decision, search, started)
	var tactical := profile.planner in [EnemyProfile.Planner.RED, EnemyProfile.Planner.GOLDEN]
	var advanced := profile.planner in [EnemyProfile.Planner.PURPLE, EnemyProfile.Planner.RED, EnemyProfile.Planner.GOLDEN]

	# Establish every collision-free fallback BEFORE spending the search budget.
	for direction in SnakeSimulation.candidates(s):
		var rejection := SnakeSimulation.collision_reason(w, s, direction, false)
		decision.candidates.append({"direction": direction, "legal": rejection == "",
			"rejection": rejection, "tier": 0, "area": 0, "continuations": 0,
			"threat": 1.0, "distance": 1000000, "utility": 0.0,
			"path": [], "reachable": [], "tail_path": [], "food_valid": false, "viable_continuations": 0,
			"scan": {}, "tactical_path": [], "target": Vector2i(-1, -1), "tactic": "RETREAT", "tactical_score": -INF,
			"mine_contact_tick": -1, "mine_clearance": INF, "mine_truncated": false, "mine_plan": [], "mine_next": null,
			"food_target": w.food, "reward_kind": "bean", "reward_multiplier": 1.0, "required": 0})
	# Mandatory bounded safety checks run before spending graph-search budget.
	if mines != null:
		var immediate := MineForecast.new(w, search if profile.budget_mandatory else null, profile.mine_prediction)
		for c in decision.candidates:
			if not c.legal:
				continue
			var checked := immediate.step(w, id, c.direction)
			c.mine_contact_tick = checked.contact_tick
			c.mine_clearance = checked.clearance
			c.mine_next = checked.world
			if not checked.valid:
				c.legal = false
				c.rejection = "mine" if checked.contact_tick >= 0 else "no safe timed movement"
	var threats := _threats(w, id, search, reaction_ticks == 0)
	var star_active := false
	for actor: SnakeState in w.snakes.values():
		star_active = star_active or (actor.alive and actor.is_player and actor.has_effect(ItemRules.STAR, w.tick))
	decision.observed_star = star_active
	var required := s.cells.size() + s.pending_growth + maxi(profile.margin_min, ceili(s.cells.size() * profile.margin_ratio))
	for c in decision.candidates:
		if not c.legal:
			continue
		var next: WorldSnapshot = c.mine_next if mines != null else SnakeSimulation.plan_move(w, id, c.direction)
		var moved: SnakeState = next.snakes[id]
		var candidate_required := moved.cells.size() + moved.pending_growth + maxi(profile.margin_min, ceili(moved.cells.size() * profile.margin_ratio))
		c.required = candidate_required
		c.continuations = _continuations(next, moved)
		c.threat = _exposure(next, moved, threats)
		var body_threat: bool = star_active and c.threat >= 1.0
		c.tier = 1
		c.rejection = "escape only: insufficient space or head threat"
		if search.exhausted:
			continue
		var occupied := next.occupied()
		occupied.erase(moved.cells[0])
		var scan := search.scan(next, moved.cells[0], occupied)
		c.scan = scan
		c.area = scan.cells.size()
		c.reachable = scan.cells
		var bean_targets: Array[Vector2i] = []
		if profile.planner != EnemyProfile.Planner.GOLDEN: bean_targets = _bean_targets(w, scan, search)
		c.food_target = bean_targets[0] if not bean_targets.is_empty() else w.food
		c.distance = GridSearch.distance(scan, c.food_target)
		c.path = GridSearch.path(scan, c.food_target)
		c.path.push_front(s.cells[0])
		if scan.complete and c.area >= candidate_required and c.continuations > 0 and not threats.has(moved.cells[0]) and not body_threat:
			c.tier = 2
			c.rejection = ""
		c.food_valid = c.tier == 2 and c.distance < 1000000 and profile.planner != EnemyProfile.Planner.GOLDEN
		if mines != null:
			var horizon := mines.escape(next, id, maxi(0, profile.mine_lookahead_moves - 1))
			c.mine_truncated = horizon.truncated
			if horizon.contact_tick >= 0:
				c.mine_contact_tick = horizon.contact_tick
			if horizon.valid:
				c.mine_plan = [s.cells[0]] + horizon.path
			else:
				c.tier = 1
				c.food_valid = false
				c.rejection = "mine forecast truncated" if horizon.truncated else "no mine-safe continuation in horizon"
		if profile.planner == EnemyProfile.Planner.PURPLE and c.food_valid:
			c.food_valid = false
			for target_index in mini(bean_targets.size(), profile.bean_route_checks):
				var target: Vector2i = bean_targets[target_index]
				var route := GridSearch.path(scan, target)
				route.push_front(s.cells[0])
				var validation := _validate_food(w, id, route, search, mines)
				if validation.valid:
					c.food_valid = true
					c.food_target = target
					c.distance = GridSearch.distance(scan, target)
					c.path = route
					break
				if search.exhausted: break
			if not c.food_valid:
				c.rejection = "food rejected: growth or future mine blocks escape"
		if profile.planner == EnemyProfile.Planner.PURPLE and profile.diamond_planning and c.tier == 2 and not search.exhausted:
			var plans := _diamond_plans(w, id, c.scan, search, profile)
			var checked_plans := 0
			for plan: Dictionary in plans:
				var current_access: float = c.reward_multiplier / (1.0 + c.distance) if c.food_valid else 0.0
				if plan.access <= current_access or checked_plans >= profile.diamond_route_checks: break
				checked_plans += 1
				var validation := _validate_food(w, id, plan.path, search, mines, plan.id)
				if validation.valid:
					c.path = validation.path
					c.distance = c.path.size() - 1
					c.food_target = validation.target
					c.reward_kind = "diamond"
					c.reward_multiplier = 3.0
					c.food_valid = true
					c.rejection = ""
		if advanced:
			c.viable_continuations = _viable_continuations(next, moved, candidate_required, search)
		# Static area may be small in a safe moving-tail loop. Keep a validated
		# tail route as survival evidence, never as permission to chase unsafe food.
		if c.tier == 1 and c.continuations > 0 and not search.exhausted:
			c.tail_path = _tail_route(next, id, search, mines)
			if not c.tail_path.is_empty() and not threats.has(moved.cells[0]) and not body_threat and (mines == null or not c.mine_plan.is_empty()):
				c.tier = 2
				c.rejection = "moving-tail escape"
		var food_access: float = minf(1.0, c.reward_multiplier / (1.0 + c.distance)) if c.food_valid else 0.0
		var space := clampf(float(c.area) / (2.0 * candidate_required), 0.0, 1.0)
		var escapes := float(c.viable_continuations if advanced else c.continuations) / 3.0
		c.utility = profile.food_weight * food_access + profile.space_weight * space + profile.escape_weight * escapes - profile.threat_weight * c.threat
	if tactical:
		return _tactical_choice(w, id, profile, decision, search, required, started)
	var best: Dictionary = {}
	var best_tier := 0
	for c in decision.candidates:
		if c.legal:
			best_tier = maxi(best_tier, c.tier)
	var food_options := false
	for c in decision.candidates:
		if c.legal and c.tier == best_tier and c.food_valid:
			food_options = true
	for c in decision.candidates:
		if not c.legal or c.tier != best_tier:
			continue
		if food_options and not c.food_valid:
			continue
		if best.is_empty() or _better(c, best, food_options, profile):
			best = c
	if not best.is_empty():
		decision.direction = best.direction
		decision.reachable.assign(best.reachable)
		decision.behavior = "FORAGE" if food_options else "ESCAPE"
		if food_options:
			decision.target = best.food_target
			if best.reward_kind == "diamond": decision.behavior = "DIAMOND INTERCEPT"
		decision.path.assign(best.path if food_options else best.tail_path)
		if mines != null and not best.mine_plan.is_empty() and not (food_options and profile.planner == EnemyProfile.Planner.PURPLE):
			decision.path.assign(best.mine_plan)
		if decision.path.is_empty():
			decision.path.assign([s.cells[0], s.cells[0] + best.direction])
		decision.reason = "Food ignored; preserve continuation and open space"
		if food_options:
			decision.reason = "Food route and tail escape validated" if profile.planner == EnemyProfile.Planner.PURPLE else "Safe next step toward the bean"
			if best.reward_kind == "diamond": decision.reason = "Intercept moving diamond; +3 growth and timed tail escape validated"
		if best_tier == 1:
			decision.reason = "Emergency: no move meets all safety checks"
	return _finish(decision, search, started)

## Runtime-only first-step validation. Strategic workers never authorize a
## move against an older body/hazard state. Manual labs retain choose_move().
static func choose_current(w: WorldSnapshot, id: String, profile: EnemyProfile, planned: AIDecision = null) -> AIDecision:
	if profile.planner == EnemyProfile.Planner.BFS_ONLY: return choose_move(w, id, profile)
	var started := Time.get_ticks_usec()
	var d := AIDecision.new()
	d.snapshot_tick = w.tick
	d.validated_tick = w.tick
	d.opponent_reaction_ticks = profile.opponent_reaction_ticks
	d.opponent_observation_tick = SnakePerception.observed_tick(w, profile.opponent_reaction_ticks)
	var perceived := SnakePerception.view(w, id, profile.opponent_reaction_ticks)
	var own: SnakeState = perceived.snakes[id]
	d.origin = own.cells[0]
	d.direction = own.direction
	d.planning_status = "survival fallback"
	d.mine_prediction = profile.mine_prediction
	var reserve := clampi(profile.safety_reserve, 0, profile.search_budget / 2)
	var star_threat := false
	for actor: SnakeState in perceived.snakes.values():
		star_threat = star_threat or (actor.alive and actor.is_player and actor.has_effect(ItemRules.STAR, perceived.tick))
	d.observed_star = star_threat
	var eligible := _runtime_preference(w, profile, planned, star_threat, reserve)
	var dynamic := not perceived.mines.is_empty() or not perceived.moving_pickups.is_empty()
	var hazard_quota := reserve / 4 if dynamic else 0
	var graph_quota := reserve - hazard_quota * 3
	var threat_search := GridSearch.new()
	threat_search.limit = mini(128, graph_quota / 4)
	var threats := _threats(perceived, id, threat_search, profile.opponent_reaction_ticks == 0)
	d.safety_expansions = threat_search.expansions
	d.exhausted = threat_search.exhausted
	var area_quota := maxi(0, (graph_quota - threat_search.limit) / 3)
	var best: Dictionary = {}
	var preferred: Dictionary = {}
	for direction in SnakeSimulation.candidates(own):
		var rejection := SnakeSimulation.collision_reason(perceived, own, direction, false)
		var c := {"direction": direction, "legal": rejection == "", "rejection": rejection, "tier": 0,
			"area": 0, "continuations": 0, "viable_continuations": 0, "threat": 1.0, "utility": 0.0,
			"distance": 1000000, "food_valid": false, "reachable": [], "tail_path": [],
			"mine_contact_tick": -1, "mine_truncated": false, "mine_traces": [], "clearance": 0.0, "evaluated": false}
		d.candidates.append(c)
	var order := d.candidates.duplicate()
	if eligible:
		for candidate in d.candidates:
			if candidate.direction == planned.direction:
				order.erase(candidate)
				order.push_front(candidate)
				break
	for c: Dictionary in order:
		c.evaluated = true
		if not c.legal: continue
		var direction: Vector2i = c.direction
		var next: WorldSnapshot
		var forecast: MineForecast
		var hazard_search := GridSearch.new()
		hazard_search.limit = hazard_quota
		if dynamic:
			forecast = MineForecast.new(perceived, hazard_search, profile.mine_prediction)
			var checked := forecast.step(perceived, id, direction, false)
			c.mine_contact_tick = checked.contact_tick
			c.mine_truncated = checked.truncated
			if not checked.valid:
				d.safety_expansions += hazard_search.expansions
				d.exhausted = d.exhausted or hazard_search.exhausted
				c.legal = checked.truncated # Unknown is an emergency, never a validated plan.
				c.rejection = "timed safety budget reached" if checked.truncated else "mine or blocked timed movement"
				continue
			next = checked.world
		else:
			next = SnakeSimulation.plan_move(perceived, id, direction, false)
		var moved: SnakeState = next.snakes[id]
		if not moved.alive:
			c.legal = false
			c.rejection = moved.death_reason
			continue
		c.tier = 1
		c.continuations = _continuations(next, moved)
		c.threat = _exposure(next, moved, threats)
		c.clearance = _head_clearance(next, id, moved.cells[0])
		var area_search := GridSearch.new()
		area_search.limit = area_quota
		var blocked := next.occupied()
		blocked.erase(moved.cells[0])
		var required := moved.cells.size() + moved.pending_growth + maxi(profile.margin_min, ceili(moved.cells.size() * profile.margin_ratio))
		var spacious := area_search.area_at_least(next, moved.cells[0], blocked, required)
		c.area = area_search.last_area
		c.reachable = area_search.area_cells(next)
		if not spacious and c.continuations > 0 and not area_search.exhausted and not hazard_search.exhausted:
			c.tail_path = _tail_route(next, id, area_search, forecast)
			spacious = not c.tail_path.is_empty()
		c.viable_continuations = c.continuations if spacious else 0
		d.safety_expansions += area_search.expansions + hazard_search.expansions
		d.exhausted = d.exhausted or area_search.exhausted or hazard_search.exhausted
		if forecast != null:
			c.mine_traces = forecast.traces()
			c.mine_truncated = hazard_search.exhausted
		if spacious and c.continuations > 0 and not threats.has(moved.cells[0]) and c.threat < 1.0:
			c.tier = 2
			c.rejection = ""
		else: c.rejection = "escape only: current space or rival threat"
		if eligible and direction == planned.direction and c.tier == 2:
			preferred = c
			break # No alternative can outrank the maximum safety tier.
	for c: Dictionary in d.candidates:
		if not c.evaluated or not c.legal: continue
		var better := best.is_empty()
		if not best.is_empty():
			better = c.tier > best.tier
			if c.tier == best.tier:
				var evade := profile.planner == EnemyProfile.Planner.GOLDEN or (star_threat and profile.planner == EnemyProfile.Planner.RED)
				if evade and c.continuations == best.continuations and is_equal_approx(c.threat, best.threat) and not is_equal_approx(c.clearance, best.clearance): better = c.clearance > best.clearance
				else: better = _better(c, best, false, profile)
		if better: best = c
	if planned != null:
		d.planning_source_tick = planned.snapshot_tick
		d.strategic_expansions = planned.expansions
		d.strategic_duration_usec = planned.duration_usec
		d.strategy_exhausted = planned.exhausted
	var accepted := not preferred.is_empty()
	if accepted:
		best = preferred
		d.target = planned.target
		d.path.assign(planned.path)
		d.predicted_paths = planned.predicted_paths
		d.behavior = planned.behavior
		d.reason = planned.reason + "; current first step revalidated"
		d.planning_status = "early plan validated"
		d.planning_source_tick = planned.snapshot_tick
	else:
		d.behavior = "EVADE" if profile.planner == EnemyProfile.Planner.GOLDEN else ("RETREAT STAR" if star_threat and profile.planner == EnemyProfile.Planner.RED else "ESCAPE")
		d.reason = "Fresh survival fallback; strategic plan unavailable or unsafe"
	if not best.is_empty():
		d.direction = best.direction
		d.reachable.assign(best.reachable)
		if accepted: d.reachable.assign(planned.reachable) # Display the worker's full plan area.
		d.mine_traces = best.mine_traces
		if not accepted: d.path.assign(best.tail_path)
	if d.path.is_empty(): d.path.assign([own.cells[0], own.cells[0] + d.direction])
	d.expansions = d.safety_expansions + d.strategic_expansions
	d.exhausted = d.exhausted or d.strategy_exhausted
	d.mine_truncated = false
	for candidate in d.candidates: d.mine_truncated = d.mine_truncated or candidate.mine_truncated
	d.duration_usec = Time.get_ticks_usec() - started
	return d

static func _runtime_preference(w: WorldSnapshot, profile: EnemyProfile, planned: AIDecision, star: bool, reserve: int) -> bool:
	if planned == null or planned.expansions > profile.search_budget - reserve: return false
	if not planned.candidates.any(func(candidate: Dictionary): return candidate.legal and candidate.direction == planned.direction): return false
	if profile.planner in [EnemyProfile.Planner.RED, EnemyProfile.Planner.GOLDEN] and planned.observed_star != star: return false
	if profile.planner == EnemyProfile.Planner.RED and star and not planned.behavior.begins_with("RETREAT"): return false
	if planned.behavior == "FORAGE" and not w.beans.has(planned.target): return false
	if planned.behavior == "DIAMOND INTERCEPT" and PickupRules.moving_count(w, PickupRules.DIAMOND) == 0: return false
	return true

## Reuse a distance map across all beans, rather than BFS once per bean.
static func _bean_targets(w: WorldSnapshot, scan: Dictionary, search: GridSearch) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for cell: Vector2i in w.beans:
		if w.beans.size() > 1 and not search.spend(): break
		if GridSearch.contains(scan, cell): targets.append(cell)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := GridSearch.distance(scan, a)
		var db := GridSearch.distance(scan, b)
		if da != db: return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return targets

static func _better(a: Dictionary, b: Dictionary, food: bool, p: EnemyProfile) -> bool:
	if food:
		if p.planner == EnemyProfile.Planner.PURPLE and not is_equal_approx(a.utility, b.utility):
			return a.utility > b.utility
		if a.distance != b.distance:
			return a.distance < b.distance
	else:
		if p.planner in [EnemyProfile.Planner.PURPLE, EnemyProfile.Planner.RED, EnemyProfile.Planner.GOLDEN] and a.viable_continuations != b.viable_continuations:
			return a.viable_continuations > b.viable_continuations
		if a.continuations != b.continuations:
			return a.continuations > b.continuations
		if not is_equal_approx(a.threat, b.threat):
			return a.threat < b.threat
	if a.area != b.area:
		return a.area > b.area
	return false # Straight, left, right insertion order is the final tie-break.

## Visible-state forecasts: straight/left/right branches, then continue or turn
## around an obstruction. These are possibilities, never the player's inputs.
static func _player_forecast(w: WorldSnapshot, player: SnakeState, search: GridSearch) -> Array:
	var paths: Array = []
	var offsets := SnakeSimulation.movement_offsets(w, player.id, 4)
	for initial in SnakeSimulation.candidates(player):
		var projected := w
		var path: Array[Vector2i] = [player.cells[0]]
		for step in 4:
			if not search.spend() or step >= offsets.size():
				break
			projected = projected.copy(player.id, false, false)
			projected.tick = w.tick + offsets[step] - int(w.prepared)
			var actor: SnakeState = projected.snakes[player.id]
			var d: Vector2i = initial if step == 0 else actor.direction
			if SnakeSimulation.collision_reason(projected, actor, d, false) != "":
				if step == 0:
					break
				var found := false
				for turn in SnakeSimulation.candidates(actor):
					if SnakeSimulation.collision_reason(projected, actor, turn, false) == "":
						d = turn
						found = true
						break
				if not found:
					break
			projected = SnakeSimulation.plan_move(projected, player.id, d, false, false)
			path.append(projected.snakes[player.id].cells[0])
		if path.size() > 1:
			paths.append(path)
	return paths

static func _tactical_choice(w: WorldSnapshot, id: String, p: EnemyProfile, d: AIDecision, search: GridSearch, required: int, started: int) -> AIDecision:
	var own: SnakeState = w.snakes[id]
	var player: SnakeState = null
	for actor: SnakeState in w.snakes.values():
		if actor.is_player and actor.alive:
			player = actor
			break
	if player != null:
		d.predicted_paths = _player_forecast(w, player, search)
	var star_threat := player != null and player.has_effect(ItemRules.STAR, w.tick)
	var disengage := star_threat or w.in_combat(id)
	var best_tier := 0
	for c in d.candidates:
		if c.legal:
			best_tier = maxi(best_tier, c.tier)
	var base_player_area := 0
	if p.planner == EnemyProfile.Planner.RED and not disengage and player != null and own.cells[0].distance_to(player.cells[0]) < 11 and not search.exhausted:
		base_player_area = _player_area(w, player.id, search)
	var best: Dictionary = {}
	for c in d.candidates:
		if not c.legal or c.tier != best_tier:
			continue
		# An emergency never receives an attack reward. Preserve the shared
		# continuation/threat/space fallback even when all graph work is exhausted.
		if best_tier < 2 or c.scan.is_empty() or not c.scan.complete or search.exhausted:
			if best.is_empty() or _better(c, best, false, p):
				best = c
			continue
		var next := SnakeSimulation.plan_move(w, id, c.direction)
		var moved: SnakeState = next.snakes[id]
		var mobility := float(c.viable_continuations) / 3.0
		var space := clampf(float(c.area) / (2.0 * required), 0.0, 1.0)
		if p.planner == EnemyProfile.Planner.GOLDEN or disengage:
			# No food, player-blocking, length contest or kill term exists here.
			var clearance := _head_clearance(next, id, moved.cells[0])
			var clearance_weight := maxf(p.clearance_weight, p.star_clearance_weight if star_threat else p.retreat_clearance_weight)
			c.tactical_score = maxf(p.escape_weight, p.retreat_escape_weight) * mobility + maxf(p.space_weight, p.retreat_space_weight) * space + clearance_weight * clearance - maxf(p.threat_weight, p.retreat_threat_weight) * c.threat
			c.tactic = "EVADE" if clearance < 1.0 else "ROAM"
			if p.planner == EnemyProfile.Planner.RED:
				c.tactic = "RETREAT STAR" if star_threat else "RETREAT DUEL"
			c.target = _escape_waypoint(next, id, c.scan, search)
			c.tactical_path = GridSearch.path(c.scan, c.target)
		else:
			var interception := _interception(w, own, player, c, d.predicted_paths, search)
			var restriction := 0.0
			if base_player_area > 0 and not search.exhausted:
				var after_area := _player_area(next, player.id, search)
				if not search.exhausted:
					restriction = clampf(1.0 - float(after_area) / base_player_area, 0.0, 1.0)
			c.tactical_score = p.intercept_weight * interception.value + p.block_weight * restriction + p.escape_weight * mobility + p.space_weight * space - p.threat_weight * c.threat
			c.target = interception.target
			c.tactic = "BLOCK" if restriction > 0.1 else interception.tactic
			c.tactical_path = GridSearch.path(c.scan, c.target)
		c.utility = c.tactical_score
		if best.is_empty() or c.tactical_score > float(best.tactical_score):
			best = c
	if not best.is_empty():
		d.direction = best.direction
		d.reachable.assign(best.reachable)
		d.behavior = best.tactic
		d.target = best.target
		d.path.assign(best.tactical_path)
		if d.mine_forecast != null and not best.mine_plan.is_empty():
			d.path.assign(best.mine_plan)
		elif not d.path.is_empty():
			d.path.push_front(own.cells[0])
			# The displayed route is a short receding-horizon plan, not a full
			# commitment to a distant waypoint through moving rivals.
			if d.path.size() > 9:
				d.path.resize(9)
		else:
			d.path.assign([own.cells[0], own.cells[0] + best.direction])
		if p.planner == EnemyProfile.Planner.GOLDEN:
			d.reason = "Preserve exits; food is not targeted but can be eaten incidentally"
		else:
			d.reason = "Arrive early, leave a body barrier, and retain escape routes"
		if disengage:
			d.reason = "Player has Star: increase separation and abandon attacks" if star_threat else "Leave head contact through a validated escape; do not trade survival"
		if best_tier < 2 or best.tactic == "RETREAT":
			d.behavior = "EVADE" if p.planner == EnemyProfile.Planner.GOLDEN else "RETREAT"
			d.reason = "Survival overrides the objective; choose an escape"
	return _finish(d, search, started)

static func _player_area(w: WorldSnapshot, id: String, search: GridSearch) -> int:
	var blocked := w.occupied()
	var head: Vector2i = w.snakes[id].cells[0]
	blocked.erase(head)
	return search.scan(w, head, blocked).cells.size()

static func _interception(w: WorldSnapshot, own: SnakeState, player: SnakeState, c: Dictionary, paths: Array, search: GridSearch) -> Dictionary:
	var result := {"value": 0.0, "target": Vector2i(-1, -1), "tactic": "CIRCLE"}
	var scan: Dictionary = c.scan
	if player != null:
		var player_times := SnakeSimulation.movement_offsets(w, player.id, 4)
		var own_times := SnakeSimulation.movement_offsets(w, own.id, 36)
		for path: Array in paths:
			for i in range(2, path.size()):
				if not search.spend():
					return result
				var point: Vector2i = path[i]
				if not GridSearch.contains(scan, point):
					continue
				var move_index := GridSearch.distance(scan, point)
				if move_index >= own_times.size() or i - 1 >= player_times.size():
					continue
				var arrival: int = own_times[move_index]
				var player_arrival: int = player_times[i - 1]
				var lead := player_arrival - arrival
				# A full move to depart before the player arrives; the long body
				# must still cover the intercept cell afterwards. Never ram heads.
				if lead < own.period or lead >= (own.cells.size() - 1) * own.period:
					continue
				var value := 1.0 + 1.0 / (1.0 + float(GridSearch.distance(scan, point)))
				if path[1] - path[0] == player.direction:
					value += 0.25
				if value > float(result.value):
					result = {"value": value, "target": point, "tactic": "INTERCEPT"}
		if result.value == 0.0:
			var offset := own.cells[0] - player.cells[0]
			var radial := Vector2i.RIGHT if abs(offset.x) >= abs(offset.y) else Vector2i.DOWN
			if (radial == Vector2i.RIGHT and offset.x < 0) or (radial == Vector2i.DOWN and offset.y < 0):
				radial = -radial
			var clockwise := Vector2i(-radial.y, radial.x)
			var orbit := player.cells[0] + clockwise * 3
			if GridSearch.contains(scan, orbit):
				result.target = orbit
				result.value = 0.5 / (1.0 + float(GridSearch.distance(scan, orbit)))
	else:
		result.tactic = "FORAGE"
		if c.food_valid:
			result.target = c.food_target
			result.value = 1.0 / (1.0 + float(c.distance))
	return result

static func _head_clearance(w: WorldSnapshot, id: String, cell: Vector2i) -> float:
	var nearest := 8
	for other: SnakeState in w.snakes.values():
		if other.id != id and other.alive:
			nearest = mini(nearest, absi(cell.x - other.cells[0].x) + absi(cell.y - other.cells[0].y))
	return clampf(nearest / 8.0, 0.0, 1.0)

static func _escape_waypoint(w: WorldSnapshot, id: String, scan: Dictionary, search: GridSearch) -> Vector2i:
	var head: Vector2i = w.snakes[id].cells[0]
	var best := head
	var best_score := -INF
	for cell: Vector2i in scan.cells:
		if not search.spend():
			break
		var distance: int = GridSearch.distance(scan, cell)
		if distance < 2 or distance > 8:
			continue
		var exits := 0
		for direction in SnakeSimulation.DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if GridSearch.contains(scan, neighbor):
				exits += 1
		var score := 4.0 * _head_clearance(w, id, cell) + float(exits) + distance * 0.02
		if score > best_score:
			best_score = score
			best = cell
	return best

static func _continuations(w: WorldSnapshot, s: SnakeState) -> int:
	var count := 0
	for d in SnakeSimulation.candidates(s):
		if SnakeSimulation.collision_reason(w, s, d) == "":
			count += 1
	return count

## A cheap bounded second step distinguishes an open junction from the mouth
## of a trap. Stop flood fill as soon as the required space is established.
static func _viable_continuations(w: WorldSnapshot, s: SnakeState, required: int, search: GridSearch) -> int:
	var count := 0
	for d in SnakeSimulation.candidates(s):
		if SnakeSimulation.collision_reason(w, s, d) != "":
			continue
		var next := SnakeSimulation.plan_move(w, s.id, d)
		var head: Vector2i = next.snakes[s.id].cells[0]
		var blocked := next.occupied()
		blocked.erase(head)
		if search.area_at_least(next, head, blocked, required):
			count += 1
		elif search.exhausted:
			return count
	return count

static func _exposure(w: WorldSnapshot, s: SnakeState, threats: Dictionary) -> float:
	for other: SnakeState in w.snakes.values():
		if other.alive and other.is_player and other.has_effect(ItemRules.STAR, w.tick):
			for cell in s.cells:
				if threats.has(cell):
					return 1.0 # Star can destroy a rival by touching its body, too.
	if threats.has(s.cells[0]):
		return 1.0
	var count := 0.0
	var threatened := 0.0
	for d in SnakeSimulation.candidates(s):
		if SnakeSimulation.collision_reason(w, s, d) == "":
			count += 1.0
			if threats.has(s.cells[0] + d):
				threatened += 1.0
	return threatened / maxf(1.0, count)

static func _threats(w: WorldSnapshot, id: String, search: GridSearch, anticipate_turns := true) -> Dictionary:
	var result: Dictionary = {}
	var own: SnakeState = w.snakes[id]
	for other_id in w.snakes:
		var other: SnakeState = w.snakes[other_id]
		if other_id == id or not other.alive:
			continue
		result[other.cells[0]] = true
		if not anticipate_turns: continue
		var offsets := SnakeSimulation.movement_offsets(w, other_id, ceili(own.period), ceili(own.period))
		var envelope := _opponent_head_envelope(w, other, offsets, search)
		result.merge(envelope.points)
		if not envelope.complete:
			for possible in SnakeSimulation.candidates(own): result[own.cells[0] + possible] = true
			return result
	return result

static func _opponent_head_envelope(w: WorldSnapshot, other: SnakeState, offsets: Array[int], search: GridSearch) -> Dictionary:
	var key := other.id + ":" + str(offsets)
	if w._cache_runtime_heads and w._runtime_head_cache.has(key):
		var cached: Dictionary = w._runtime_head_cache[key]
		if cached.spent <= search.limit - search.expansions:
			search.spend_many(cached.spent) # Preserve each caller's independent budget.
			return cached
	var before := search.expansions
	var points := {}
	var complete := true
	if offsets.size() > 2:
		complete = _long_head_envelope(w, other, offsets.size(), search, points)
	else:
		var frontier: Array = [w]
		for depth in offsets.size():
			var next_frontier: Array = []
			for state: WorldSnapshot in frontier:
				var timed := state.copy(other.id, false, false)
				timed.tick = w.tick + offsets[depth] - int(w.prepared)
				var actor: SnakeState = timed.snakes[other.id]
				for direction in SnakeSimulation.candidates(actor):
					if not search.spend(): return {"points": points, "complete": false}
					if SnakeSimulation.collision_reason(timed, actor, direction, false) == "":
						var projected := SnakeSimulation.plan_move(timed, other.id, direction, false, false)
						points[projected.snakes[other.id].cells[0]] = true
						next_frontier.append(projected)
			frontier = next_frontier
	var result := {"points": points, "complete": complete, "spent": search.expansions - before}
	if complete and w._cache_runtime_heads: w._runtime_head_cache[key] = result
	return result

static func _long_head_envelope(w: WorldSnapshot, other: SnakeState, steps: int, search: GridSearch, result: Dictionary) -> bool:
	var blocked := w.occupied(other.id)
	if other.is_player and other.has_effect(ItemRules.STAR, w.tick):
		# Keep an overestimate if Star expires within this short horizon.
		for cell: Vector2i in blocked.keys():
			if not w.walls.has(cell):
				blocked.erase(cell)
	var releases: Dictionary = {}
	for i in other.cells.size():
		releases[other.cells[i]] = other.cells.size() - i + other.pending_growth
	var heading := SnakeSimulation.DIRECTIONS.find(other.direction)
	var frontier: Array[Vector3i] = [Vector3i(other.cells[0].x, other.cells[0].y, heading)]
	for step in range(1, steps + 1):
		var next_frontier: Array[Vector3i] = []
		var visited: Dictionary = {}
		for node in frontier:
			var cell := Vector2i(node.x, node.y)
			for dir_index in 4:
				var direction: Vector2i = SnakeSimulation.DIRECTIONS[dir_index]
				if direction == -SnakeSimulation.DIRECTIONS[node.z]:
					continue
				if not search.spend():
					return false
				var destination := cell + direction
				if not w.in_bounds(destination) or blocked.has(destination) or int(releases.get(destination, 0)) > step:
					continue
				var key := Vector3i(destination.x, destination.y, dir_index)
				if visited.has(key):
					continue
				visited[key] = true
				result[destination] = true
				next_frontier.append(key)
		frontier = next_frontier
	# Future trail and incidental food growth are ignored here: both only
	# remove real possibilities, so this intentionally overestimates threats.
	return true

static func _tail_route(w: WorldSnapshot, id: String, search: GridSearch, mines: MineForecast = null) -> Array[Vector2i]:
	var s: SnakeState = w.snakes[id]
	if not w.in_bounds(s.cells[-1]): return [] # Entering tails have no grid route yet.
	var blocked := w.occupied()
	blocked.erase(s.cells[0])
	blocked.erase(s.cells[-1])
	var scan := search.scan(w, s.cells[0], blocked, s.cells[-1])
	var path := GridSearch.path(scan, s.cells[-1])
	if not scan.complete or path.size() < 2:
		return []
	var projected := w
	for i in range(1, path.size()):
		if not search.spend():
			return []
		var d := path[i] - path[i - 1]
		if SnakeSimulation.collision_reason(projected, projected.snakes[id], d, mines == null) != "":
			return []
		if mines != null:
			var timed := mines.step(projected, id, d, false)
			if not timed.valid:
				return []
			projected = timed.world
		else:
			projected = SnakeSimulation.plan_move(projected, id, d)
	return path if _continuations(projected, projected.snakes[id]) > 0 else []

static func _validate_food(w: WorldSnapshot, id: String, path: Array, search: GridSearch, mines: MineForecast = null, diamond_id := -1) -> Dictionary:
	var projected := w
	var travelled: Array = [w.snakes[id].cells[0]]
	for i in range(1, path.size()):
		if not search.spend():
			return {"valid": false}
		var d: Vector2i = path[i] - path[i - 1]
		if SnakeSimulation.collision_reason(projected, projected.snakes[id], d, mines == null) != "":
			return {"valid": false}
		if mines != null:
			var timed := mines.step(projected, id, d, false)
			if not timed.valid:
				return {"valid": false}
			projected = timed.world
		else:
			projected = SnakeSimulation.plan_move(projected, id, d)
		travelled.append(projected.snakes[id].cells[0])
		if diamond_id >= 0 and not projected.moving_pickups.has(diamond_id): break
	var actor: SnakeState = projected.snakes[id]
	var collected: bool = actor.food_eaten > w.snakes[id].food_eaten if diamond_id < 0 else (not projected.moving_pickups.has(diamond_id) and actor.diamonds_eaten > w.snakes[id].diamonds_eaten)
	return {"valid": collected and _continuations(projected, actor) > 0 and not _tail_route(projected, id, search, mines).is_empty(), "path": travelled, "target": actor.cells[0]}

static func _diamond_plans(w: WorldSnapshot, id: String, scan: Dictionary, search: GridSearch, profile: EnemyProfile) -> Array:
	var items: Array[MovingPickup] = []
	for item: MovingPickup in w.moving_pickups.values():
		if not search.spend(): return []
		if item.kind == PickupRules.DIAMOND: items.append(item)
	var head := MineRules.center(w.snakes[id].cells[0])
	items.sort_custom(func(a: MovingPickup, b: MovingPickup) -> bool:
		var da := head.distance_squared_to(a.position)
		var db := head.distance_squared_to(b.position)
		return a.id < b.id if is_equal_approx(da, db) else da < db)
	var offsets := SnakeSimulation.movement_offsets(w, id, profile.diamond_horizon_moves)
	var plans: Array = []
	var seen: Dictionary = {}
	var motion := w.trajectories()
	for index in mini(items.size(), profile.diamond_candidates):
		var item := items[index]
		for move_index in offsets.size():
			if not search.spend(): return plans
			var future: MovingPickup = motion.pickup_projection(item, w.tick + offsets[move_index] - int(w.prepared)).item
			var cell := Vector2i(future.position.floor())
			var key := str(item.id) + ":" + str(cell)
			if seen.has(key) or not GridSearch.contains(scan, cell): continue
			var path := GridSearch.path(scan, cell)
			path.push_front(w.snakes[id].cells[0])
			var moves := path.size() - 1
			# A pose is useful only at the route's arrival time. Otherwise a
			# distant future pose can crowd real interceptions out of the budget.
			if moves != move_index + 1 or moves > profile.diamond_horizon_moves: continue
			seen[key] = true
			plans.append({"id": item.id, "path": path, "access": minf(1.0, 3.0 / (1.0 + moves))})
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.access, b.access): return a.access > b.access
		return a.id < b.id)
	return plans

static func _finish(d: AIDecision, search: GridSearch, start: int) -> AIDecision:
	if d.mine_forecast != null:
		d.mine_truncated = search.exhausted
		d.mine_traces = d.mine_forecast.traces()
		for candidate in d.candidates:
			d.mine_truncated = d.mine_truncated or candidate.mine_truncated
			candidate.erase("mine_next")
		d.mine_forecast = null
	for candidate in d.candidates:
		candidate.erase("scan")
	d.expansions = search.expansions
	d.exhausted = search.exhausted
	d.duration_usec = Time.get_ticks_usec() - start
	if d.opponent_reaction_ticks > 0:
		d.reason += " (rival reaction %.2fs; no turn anticipation)" % (d.opponent_reaction_ticks * SnakeSimulation.TICK_SECONDS)
	if d.exhausted:
		d.reason += " (search budget reached)"
	return d

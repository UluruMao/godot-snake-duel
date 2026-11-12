class_name PlanningAhead
extends RefCounted

## One in-flight job per actor, including obsolete work. Nothing waits on an
## unfinished worker in the frame loop. Completed plans are only preferences.
var jobs: Dictionary = {}
var retired: Array[PlanningJob] = []
var stats := {"started": 0, "ready": 0, "late": 0, "invalidated": 0, "worker_usec": 0, "completed": 0}

static func pose(s: SnakeState) -> Array:
	return [s.cells.duplicate(), s.direction, s.pending_growth, s.alive, s.entry_remaining, s.period, s.effects.duplicate()]

func poll() -> void:
	for i in range(retired.size() - 1, -1, -1):
		if retired[i].poll(): retired.remove_at(i)
	for entry: Dictionary in jobs.values():
		if not entry.counted and entry.job.poll():
			stats.worker_usec += entry.job.decision.duration_usec
			stats.completed += 1
			entry.counted = true

func schedule(w: WorldSnapshot, profiles: Dictionary) -> void:
	poll()
	for id in jobs.keys():
		var entry: Dictionary = jobs[id]
		if not w.snakes.has(id) or not w.snakes[id].alive or entry.pose != pose(w.snakes[id]):
			entry.obsolete = true
		if entry.obsolete and entry.job.poll(): jobs.erase(id)
	for id in profiles:
		if jobs.has(id) or not w.snakes.has(id): continue
		var actor: SnakeState = w.snakes[id]
		if not actor.alive or actor.is_player or SpeedRules.due(actor): continue
		# Never stack a new job on a cancelled still-running job for this actor.
		var busy := false
		for old in retired: busy = busy or (old.actor_id == id and not old.poll())
		if busy: continue
		var profile: EnemyProfile = profiles[id].copy()
		if profile.planner == EnemyProfile.Planner.BFS_ONLY: continue
		profile.search_budget = maxi(0, profile.search_budget - clampi(profile.safety_reserve, 0, profile.search_budget / 2))
		profile.budget_mandatory = true
		var job := PlanningJob.new(w, id, profile)
		jobs[id] = {"job": job, "pose": pose(actor), "obsolete": false, "counted": false}
		job.start()
		stats.started += 1

func take(w: WorldSnapshot, id: String) -> AIDecision:
	poll()
	if not jobs.has(id):
		stats.late += 1
		return null
	var entry: Dictionary = jobs[id]
	if not entry.job.poll():
		entry.obsolete = true
		stats.late += 1
		return null
	jobs.erase(id)
	if entry.obsolete or entry.pose != pose(w.snakes[id]):
		stats.invalidated += 1
		return null
	stats.ready += 1
	return entry.job.decision

func invalidate() -> void:
	for entry: Dictionary in jobs.values(): retired.append(entry.job)
	jobs.clear()
	poll()

func drain() -> void:
	for entry: Dictionary in jobs.values(): entry.job.drain()
	for job in retired: job.drain()
	jobs.clear()
	retired.clear()

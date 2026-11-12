class_name SnakePerception
extends RefCounted

## Completed, immutable poses only; no queued input or future AI intent.
## Keep one older anchor plus the last two seconds of changed poses.
const MAX_DELAY_TICKS := 100
const POSE_FIELDS := ["cells", "direction", "alive", "pending_growth", "period", "base_period", "boosting", "chance_ticks", "effects", "entry_remaining"]

static func record(w: WorldSnapshot) -> void:
	var history := w.snake_observations.duplicate()
	for id in history.keys():
		if not w.snakes.has(id): history.erase(id)
	for id in w.snakes:
		var s: SnakeState = w.snakes[id]
		var poses: Array = history.get(id, [])
		var changed := poses.is_empty()
		if not changed:
			for field: String in POSE_FIELDS:
				if poses[-1][field] != s.get(field):
					changed = true
					break
		var prune := poses.size() > 1 and int(poses[1].tick) <= w.tick - MAX_DELAY_TICKS
		if not changed and not prune: continue
		poses = poses.duplicate()
		if changed:
			var pose := {"tick": w.tick, "remaining": s.remaining}
			for field: String in POSE_FIELDS:
				var value = s.get(field)
				pose[field] = value.duplicate() if value is Array or value is Dictionary else value
			poses.append(pose)
		while poses.size() > 1 and int(poses[1].tick) <= w.tick - MAX_DELAY_TICKS:
			poses.pop_front()
		history[id] = poses
	# Replace, never mutate any nested container borrowed by a prediction.
	w.snake_observations = history

static func observed_tick(w: WorldSnapshot, delay: int) -> int:
	return w.tick - int(w.prepared) - clampi(delay, 0, MAX_DELAY_TICKS)

static func view(w: WorldSnapshot, id: String, delay: int) -> WorldSnapshot:
	if delay <= 0: return w
	var cutoff := observed_tick(w, delay)
	var result := w.copy(id, false, false)
	for other_id in w.snakes:
		if other_id == id: continue
		var poses: Array = w.snake_observations.get(other_id, [])
		if poses.is_empty(): continue # A fresh fixture starts with known geometry.
		var pose: Dictionary = poses[0] # Newborns are visible at their spawn pose.
		for candidate: Dictionary in poses:
			if int(candidate.tick) > cutoff: break
			pose = candidate
		var actor := result.mutable_snake(other_id)
		for field: String in POSE_FIELDS:
			var value = pose[field]
			actor.set(field, value.duplicate() if value is Array or value is Dictionary else value)
		# Rebase the observed clock without advancing or guessing its body.
		var elapsed := maxi(0, w.tick - int(w.prepared) - int(pose.tick))
		actor.remaining = fposmod(float(pose.remaining) - elapsed, actor.period)
		if actor.remaining <= SpeedRules.EPS: actor.remaining = actor.period
	return result

class_name ScoreRules
extends RefCounted

const INITIAL_PLAYER_LENGTH := 5
const MIN_LENGTH := 1
const BEAN_MULTIPLIER := 1
const POWER_UP_MULTIPLIER := 10

static func base_score(length: int) -> int:
	return 100 * maxi(MIN_LENGTH, length) + 500

static func reward(actor: SnakeState, multiplier: int) -> int:
	return base_score(actor.cells.size()) * multiplier

## Score the fully resolved body state, before newly queued growth is added.
## Every event carries the awarded value so the UI and forecasts never guess it.
static func award_events(w: WorldSnapshot, events: Array[Dictionary]) -> void:
	for event in events:
		var actor: SnakeState = null
		var multiplier := 0
		var field := "score"
		if event.type == "died":
			field = "reward"
			if event.killer != "":
				actor = w.snakes[event.killer]
				multiplier = w.snakes[event.id].reward_multiplier
		elif event.type in ["food", "pickup", "diamond"]:
			actor = w.snakes[event.id]
			multiplier = BEAN_MULTIPLIER if event.type == "food" else POWER_UP_MULTIPLIER
		else:
			continue
		event[field] = 0
		if actor == null or not actor.is_player or not actor.alive:
			continue
		event.score_length = maxi(MIN_LENGTH, actor.cells.size())
		event.score_base = base_score(event.score_length)
		event.score_multiplier = multiplier
		event[field] = int(event.score_base) * multiplier
		w.score += int(event[field])

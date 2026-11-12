class_name AIDecision
extends RefCounted

var direction := Vector2i.RIGHT
var target := Vector2i(-1, -1)
var path: Array[Vector2i] = []
var reachable: Array[Vector2i] = []
var behavior := "ESCAPE"
var reason := "No legal move; momentum resolves the collision"
var candidates: Array[Dictionary] = []
var expansions := 0
var exhausted := false
var duration_usec := 0
var snapshot_tick := 0
var opponent_reaction_ticks := 0
var opponent_observation_tick := 0
var origin := Vector2i.ZERO
var predicted_paths: Array = []
var mine_forecast: MineForecast
var mine_prediction := true
var mine_traces: Array = []
var mine_truncated := false
var planning_status := "synchronous"
var planning_source_tick := -1
var validated_tick := -1
var safety_expansions := 0
var strategic_expansions := 0
var strategic_duration_usec := 0
var strategy_exhausted := false
var observed_star := false

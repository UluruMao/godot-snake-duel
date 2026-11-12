class_name PlanningBatch
extends RefCounted

## The world stays at its last completed tick until all simultaneous intents
## are ready. Thus slow workers never apply an old plan to a newer world.
var source: WorldSnapshot
var prepared: Dictionary
var intents: Dictionary = {}
var jobs: Array[PlanningJob] = []
var version: int
var started: int
var player_queued := false

func _init(w: WorldSnapshot, profiles: Dictionary, serial: int, boost := false) -> void:
	source = w
	version = serial
	started = Time.get_ticks_usec()
	prepared = SnakeSimulation.begin_tick(w, boost)
	for id in prepared.world.snakes:
		var actor: SnakeState = prepared.world.snakes[id]
		if actor.alive and not actor.is_player and SpeedRules.due(actor):
			jobs.append(PlanningJob.new(prepared.world, id, profiles[id]))
	for job in jobs: job.start()

func poll() -> bool:
	var ready := true
	for job in jobs:
		if not job.poll(): ready = false
	return ready

func matches(w: WorldSnapshot, serial: int) -> bool:
	return source == w and version == serial

func drain() -> void:
	for job in jobs: job.drain()

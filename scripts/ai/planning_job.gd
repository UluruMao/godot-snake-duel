class_name PlanningJob
extends RefCounted

## One worker owns all mutable search, profile and snapshot data. It never
## accesses nodes, input, rendering or a concurrently used trajectory cache.
var snapshot: WorldSnapshot
var profile: EnemyProfile
var actor_id: String
var decision: AIDecision
var task_id := -1
var joined := false

func _init(w: WorldSnapshot, id: String, p: EnemyProfile) -> void:
	snapshot = w.copy()
	profile = p.copy()
	actor_id = id

func start() -> void:
	task_id = WorkerThreadPool.add_task(_run, false, "Snake AI " + actor_id)

func _run() -> void:
	decision = SnakeAI.choose_move(snapshot, actor_id, profile)
	snapshot = null

func poll() -> bool:
	if not joined and WorkerThreadPool.is_task_completed(task_id):
		WorkerThreadPool.wait_for_task_completion(task_id)
		joined = true
	return joined

func drain() -> void:
	if not joined:
		WorkerThreadPool.wait_for_task_completion(task_id)
		joined = true

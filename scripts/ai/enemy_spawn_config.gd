class_name EnemySpawnConfig
extends Resource

@export var enabled := true
## Living snakes share this limit, including partially entered bodies.
@export_range(0, 16, 1) var max_enemies := 4
## First active head. Entrances have no warning or preview stage.
@export_range(0.0, 60.0, 0.1, "suffix:s") var first_spawn_delay := 3.0
@export_range(0.02, 60.0, 0.1, "suffix:s") var spawn_interval := 6.0
@export_range(0.0, 60.0, 0.1, "suffix:s") var bomb_grace := 8.0
@export_range(0.02, 10.0, 0.02, "suffix:s") var blocked_retry := 0.5
@export_range(0, 16, 1) var minimum_head_distance := 6
## Measured against the player's current head when the enemy enters.
@export_range(0, 60, 1) var minimum_player_distance := 12
@export_range(1, 2304, 1) var max_placement_attempts := 128 # Covers all 110 boundary/headings on 30x25.
@export_range(128, 8192, 128) var max_safety_checks := 4096
@export var types: Array[EnemySpawnType] = []

func to_rules() -> Dictionary:
	var entries: Dictionary = {}
	for entry in types:
		if entry != null: entries[entry.archetype] = entry.to_rule()
	var warning := 0 # Legacy snapshot field; current sessions never announce entries.
	return {"enabled": enabled, "cap": clampi(max_enemies, 0, 16), "first": maxi(warning, ceili(first_spawn_delay * 50)), "interval": maxi(1, ceili(spawn_interval * 50)), "warning": warning, "bomb_grace": maxi(0, ceili(bomb_grace * 50)), "retry": maxi(1, ceili(blocked_retry * 50)), "head_distance": maxi(0, minimum_head_distance), "player_distance": maxi(0, minimum_player_distance), "attempts": clampi(max_placement_attempts, 1, 2304), "checks": clampi(max_safety_checks, 128, 8192), "types": entries}

class_name EnemySpawnType
extends Resource

## Editor tuning only. Running worlds store primitive copies, never Resources.
@export_enum("pink", "purple", "red", "golden") var archetype := "pink"
@export var enabled := true
@export_range(0, 10000000, 1000, "or_greater") var unlock_score := 0
@export_range(0, 16, 1) var max_alive := 4
@export_range(0.0, 20.0, 0.05) var selection_weight := 1.0
## Earliest this type can begin another preview after any of its deaths.
## Shared across this type; spacing, capacity and safety can delay it further.
@export_range(0.0, 300.0, 0.5, "suffix:s") var respawn_cooldown := 0.0

@export_group("Snake")
@export_range(1, 32, 1) var initial_length := 3
## Below the player's slowest boost (10 cells/s).
@export_range(0.25, 9.5, 0.05, "suffix:cells/s") var speed := 3.5
@export_range(0, 1000, 1) var reward_multiplier := 5
@export_range(1, 5, 1) var difficulty := 1
@export var display_color := Color(0.91, 0.24, 0.52)

@export_group("Planning")
## Delay before noticing changed rival bodies/headings. Positive values also
## disable speculative rival-turn prediction; terrain, self and mines stay live.
@export_range(0.0, 2.0, 0.02, "suffix:s") var opponent_reaction_delay := 0.0
@export_range(128, 8192, 128) var search_budget := 8192
## Reserved from the total for current-state checks at the movement deadline.
@export_range(128, 4096, 128) var safety_reserve := 2048
@export_range(1, 12, 1) var mine_lookahead_moves := 2
@export_range(0, 10, 1) var safety_margin_min := 2
@export_range(0.0, 1.0, 0.05) var safety_margin_ratio := 0.25
@export_range(0.0, 20.0, 0.1) var food_weight := 3.0
@export_range(0.0, 20.0, 0.1) var space_weight := 4.0
@export_range(0.0, 20.0, 0.1) var escape_weight := 3.0
@export_range(0.0, 20.0, 0.1) var threat_weight := 3.0

func to_rule() -> Dictionary:
	var p := EnemyProfile.for_kind(archetype)
	p.interval_ticks = 50.0 / clampf(speed, 0.25, 9.5)
	p.initial_length = clampi(initial_length, 1, 32)
	p.reward_multiplier = maxi(0, reward_multiplier)
	p.difficulty = clampi(difficulty, 1, 5)
	p.display_color = display_color
	p.search_budget = clampi(search_budget, 128, 8192)
	p.safety_reserve = clampi(safety_reserve, 0, p.search_budget / 2)
	p.opponent_reaction_ticks = clampi(ceili(maxf(0, opponent_reaction_delay) * 50), 0, SnakePerception.MAX_DELAY_TICKS)
	p.mine_lookahead_moves = clampi(mine_lookahead_moves, 1, 12)
	p.margin_min = maxi(0, safety_margin_min)
	p.margin_ratio = clampf(safety_margin_ratio, 0, 1)
	p.food_weight = food_weight
	p.space_weight = space_weight
	p.escape_weight = escape_weight
	p.threat_weight = threat_weight
	var data: Dictionary = {}
	for property in p.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: data[property.name] = p.get(property.name)
	return {"kind": archetype, "enabled": enabled, "unlock_score": maxi(0, unlock_score), "max_alive": maxi(0, max_alive), "weight": maxf(0, selection_weight), "cooldown": ceili(maxf(0, respawn_cooldown) * 50), "profile": data}

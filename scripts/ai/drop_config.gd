class_name DropConfig
extends Resource

@export var enabled := true
@export var player_drops := true
## Independent Bernoulli trials, one per actual body segment at death.
@export_range(0.0, 1.0, 0.01) var segment_chance := 0.25
@export_range(0.0, 1.0, 0.01) var difficulty_bonus := 0.05
@export_range(1, 32, 1) var minimum_drops := 1
@export_range(1, 5, 1) var player_difficulty := 1
## Replaces a rolled drop; it does not add an extra item.
@export_range(0.0, 1.0, 0.01) var diamond_replacement_chance := 0.05
## Existing natural-bean bonus rule, separate from death-drop conversion.
@export_range(0.0, 1.0, 0.01) var natural_extra_diamond_chance := 0.10
@export_range(0.02, 10.0, 0.02, "suffix:s") var blocked_retry := 0.5

func to_rules() -> Dictionary:
	return {"enabled": enabled, "player_drops": player_drops,
		"segment_chance": clampf(segment_chance, 0, 1), "difficulty_bonus": clampf(difficulty_bonus, 0, 1),
		"minimum": maxi(1, minimum_drops), "player_difficulty": clampi(player_difficulty, 1, 5),
		"diamond_chance": clampf(diamond_replacement_chance, 0, 1),
		"natural_diamond_chance": clampf(natural_extra_diamond_chance, 0, 1),
		"retry": maxi(1, ceili(blocked_retry * 50))}

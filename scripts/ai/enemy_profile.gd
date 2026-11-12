class_name EnemyProfile
extends RefCounted

enum Planner { BFS_ONLY, SAFETY, PURPLE, RED, GOLDEN }
const PLANNER_NAMES := ["BFS", "SAFETY", "PURPLE", "RED", "GOLDEN"]
var planner := Planner.SAFETY
var interval_ticks := SpeedRules.TICKS_PER_SECOND / (SpeedRules.NORMAL_SPEED * SpeedRules.PINK_RATIO)
var initial_length := 3
var reward_multiplier := 5
var difficulty := 1
var collects_food := true
var display_color := Color(0.91, 0.24, 0.52)
var margin_min := 2
var margin_ratio := 0.25
var search_budget := 8192
var safety_reserve := 2048 # Runtime validation; optional worker gets the remainder.
var budget_mandatory := false # Legacy synchronous comparisons retain their old counters.
var food_weight := 3.0
var space_weight := 4.0
var escape_weight := 3.0
var threat_weight := 3.0
var intercept_weight := 7.0
var block_weight := 8.0
var clearance_weight := 0.0
var retreat_escape_weight := 9.0
var retreat_space_weight := 4.0
var retreat_threat_weight := 14.0
var retreat_clearance_weight := 6.0
var star_clearance_weight := 12.0
var mine_prediction := true # False is the current-position comparison policy.
var mine_lookahead_moves := 2
var opponent_reaction_ticks := 15 # Pink: 0.30 s delayed rival poses, no turn anticipation.
var diamond_planning := true # Purple only; independently switchable for comparisons.
var diamond_candidates := 4
var diamond_route_checks := 2
var diamond_horizon_moves := 24
var bean_route_checks := 4 # Purple: bounded alternate bean plans, same budget.

func copy() -> EnemyProfile:
	var result := EnemyProfile.new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, get(property.name))
	return result

static func pink() -> EnemyProfile:
	return EnemyProfile.new()

static func purple() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.planner = Planner.PURPLE
	p.opponent_reaction_ticks = 0
	p.mine_lookahead_moves = 6
	p.interval_ticks = SpeedRules.TICKS_PER_SECOND / (SpeedRules.NORMAL_SPEED * SpeedRules.PURPLE_RATIO)
	p.initial_length = 5
	p.reward_multiplier = 20
	p.difficulty = 4
	p.display_color = Color(0.5, 0.23, 0.85)
	return p

static func red() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.planner = Planner.RED
	p.opponent_reaction_ticks = 0
	p.mine_lookahead_moves = 6
	p.interval_ticks = SpeedRules.TICKS_PER_SECOND / (SpeedRules.NORMAL_SPEED * SpeedRules.RED_RATIO)
	p.initial_length = 12
	p.reward_multiplier = 50
	p.difficulty = 5
	p.display_color = Color(0.93, 0.12, 0.12)
	p.space_weight = 1.0
	p.threat_weight = 8.0
	return p

static func golden() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.planner = Planner.GOLDEN
	p.opponent_reaction_ticks = 0
	p.mine_lookahead_moves = 6
	p.interval_ticks = SpeedRules.TICKS_PER_SECOND / (SpeedRules.NORMAL_SPEED * SpeedRules.GOLDEN_RATIO)
	p.initial_length = 3
	p.reward_multiplier = 200
	p.difficulty = 4
	p.collects_food = true # Incidental beans grow Golden; its planner never seeks food.
	p.display_color = Color(1.0, 0.72, 0.08)
	p.food_weight = 0.0
	p.escape_weight = 9.0
	p.threat_weight = 14.0
	p.clearance_weight = 6.0
	return p

static func roster() -> Dictionary:
	return {"pink": pink(), "purple": purple(), "red": red(), "golden": golden()}

static func for_kind(kind: String) -> EnemyProfile:
	match kind:
		"purple": return purple()
		"red": return red()
		"golden": return golden()
		_: return pink()

static func baseline() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.planner = Planner.BFS_ONLY
	p.opponent_reaction_ticks = 0
	return p

class_name SpeedRules
extends RefCounted

## Ratios approximated from speed.mp4; the user chose 5 cells/s as the anchor.
const TICKS_PER_SECOND := 50.0
const NORMAL_SPEED := 5.0
const NORMAL_TICKS := TICKS_PER_SECOND / NORMAL_SPEED
const UP_BONUS := 0.5
const DOWN_PENALTY := 0.25
const BOOST_BONUS := 1.25
const PINK_RATIO := 0.7
const PURPLE_RATIO := 0.9
const RED_RATIO := 4.0 / 3.0
const GOLDEN_RATIO := 1.25
const EPS := 0.000000001

static func player_multiplier(s: SnakeState, tick: int, boost: bool) -> float:
	return 1.0 + (UP_BONUS if s.has_effect("speed_up", tick) else 0.0) - (DOWN_PENALTY if s.has_effect("slow_down", tick) else 0.0) + (BOOST_BONUS if boost and s.alive else 0.0)

static func period(s: SnakeState, tick: int, boost: bool) -> float:
	return s.base_period / player_multiplier(s, tick, boost) if s.is_player else s.base_period

static func due(s: SnakeState) -> bool:
	return s.remaining <= 1.0 + EPS

static func advance_phase(s: SnakeState) -> bool:
	s.remaining -= 1.0
	if s.remaining > EPS: return false
	# Preserve overshoot: rounding/resetting a fractional interval loses speed.
	s.remaining += s.period
	return true

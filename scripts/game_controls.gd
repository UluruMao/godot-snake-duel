class_name GameControls
extends RefCounted

## Keep function keys available to Godot's editor and embedded-game debugger.
## Buttons and keyboard input share these bindings; modified presses are separate.
const INSPECTOR := KEY_I
const SELECT_ENEMY := KEY_Q
const SCENARIOS := KEY_L
const PLANNER := KEY_V
const NEW_SEED := KEY_G
const STAR := KEY_1
const SPEED_UP := KEY_2
const SLOW_DOWN := KEY_3
const MINE_POLICY := KEY_M
const DIAMOND_POLICY := KEY_B
const PERFORMANCE := KEY_T

static func is_plain_press(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.get_modifiers_mask() == 0

static func is_fullscreen_press(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and event.get_modifiers_mask() == KEY_MASK_ALT

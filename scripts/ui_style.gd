class_name UIStyle
extends RefCounted

## Original monochrome arcade palette; layout and controls are shared in both modes.
const BACKGROUND := Color(0.72, 0.72, 0.72)
const PANEL := Color(0.70, 0.70, 0.70)
const BORDER := Color(0.28, 0.28, 0.28)
const TEXT := Color(0.13, 0.13, 0.13)
const MUTED := Color(0.28, 0.28, 0.28)
const ACCENT := Color(0.20, 0.20, 0.20)
const DANGER := Color(0.55, 0.10, 0.12)
const BUTTON_TEXT := Color(0.95, 0.95, 0.95)
const BUTTON_BORDER := Color(0.90, 0.90, 0.90)

static func box(color := PANEL, radius := 4, border := BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

static func label(text := "", size := 18, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func pixel_label(text: String, pixel := 3, color := TEXT) -> PixelLabel:
	var node := PixelLabel.new()
	node.text = text
	node.pixel = pixel
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func button_box(shade := 0.22) -> StyleBoxFlat:
	var style := box(Color(shade, shade, shade), 4, BUTTON_BORDER)
	style.set_border_width_all(2)
	return style

static func button(text: String, small := false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 34 if small else 48
	node.add_theme_font_size_override("font_size", 16 if small else 19)
	node.add_theme_color_override("font_color", BUTTON_TEXT)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_pressed_color", Color.WHITE)
	node.add_theme_stylebox_override("normal", button_box())
	node.add_theme_stylebox_override("hover", button_box(0.32))
	node.add_theme_stylebox_override("pressed", button_box(0.12))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 4, Color.WHITE))
	if small:
		for state in ["normal", "hover", "pressed", "focus"]:
			var style: StyleBoxFlat = node.get_theme_stylebox(state).duplicate()
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			node.add_theme_stylebox_override(state, style)
	node.focus_mode = Control.FOCUS_NONE
	return node

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 19
	result.set_color("font_color", "Label", TEXT)
	for type in ["Button", "OptionButton", "PopupMenu", "CheckButton"]:
		result.set_color("font_color", type, BUTTON_TEXT)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, Color(0.68, 0.68, 0.68))
	result.set_stylebox("panel", "PopupMenu", button_box(0.22))
	result.set_stylebox("hover", "PopupMenu", button_box(0.36))
	result.set_stylebox("normal", "OptionButton", button_box())
	result.set_stylebox("hover", "OptionButton", button_box(0.32))
	result.set_stylebox("pressed", "OptionButton", button_box(0.12))
	result.set_stylebox("disabled", "OptionButton", button_box(0.28))
	result.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 4, Color.WHITE))
	result.set_constant("v_separation", "PopupMenu", 12)
	return result

class_name UILayout
extends RefCounted

const INSPECTOR := Rect2(1024, 144, 384, 676)
const FOOTER_Y := 852.0

static func board_rect(w: WorldSnapshot, debug := false) -> Rect2:
	var available := Rect2(32, 144, 960 if debug else 1376, 676)
	var pixels := Vector2(w.width, w.height) * GridConfig.CELL
	var factor := minf(available.size.x / pixels.x, available.size.y / pixels.y)
	var size := pixels * factor
	return Rect2(available.position + (available.size - size) * 0.5, size)

static func fit_canvas(window_size: Vector2) -> Rect2:
	var canvas := Vector2(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	var factor := minf(window_size.x / canvas.x, window_size.y / canvas.y)
	return Rect2((window_size - canvas * factor) * 0.5, canvas * factor)

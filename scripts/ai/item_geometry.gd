class_name ItemGeometry
extends RefCounted

const EPS := 0.0000001

## Shared reflected motion for squares of any footprint. Positions are centres
## in grid units. Piecewise times make swept tests exact across bounces.
static func motion(position: Vector2, velocity: Vector2, half: float, dimensions: Vector2, seconds: float) -> Dictionary:
	var lower := Vector2.ONE * half
	var upper := dimensions - lower
	var point := position.clamp(lower, upper)
	var delta := velocity * seconds
	for axis in 2:
		if upper[axis] - lower[axis] <= EPS:
			delta[axis] = 0
	var segments: Array[Dictionary] = []
	var time := 0.0
	if delta.is_zero_approx():
		segments.append({"from": point, "to": point, "t0": 0.0, "t1": 1.0})
	while time < 1.0 - EPS and not delta.is_zero_approx():
		var tx := INF
		var ty := INF
		if absf(delta.x) > EPS:
			tx = ((upper.x if delta.x > 0 else lower.x) - point.x) / delta.x
		if absf(delta.y) > EPS:
			ty = ((upper.y if delta.y > 0 else lower.y) - point.y) / delta.y
		var duration := maxf(0.0, minf(1.0 - time, minf(tx, ty)))
		var destination := point + delta * duration
		if duration > EPS:
			segments.append({"from": point, "to": destination, "t0": time, "t1": time + duration})
		point = destination
		time += duration
		if tx <= duration + EPS: delta.x = -delta.x
		if ty <= duration + EPS: delta.y = -delta.y
		if duration <= EPS and tx > EPS and ty > EPS: break
	return {"position": point.clamp(lower, upper), "velocity": delta / seconds if seconds > 0 else velocity, "segments": segments}

static func box_entry(from: Vector2, to: Vector2, half: Vector2) -> float:
	var lower := 0.0
	var upper := 1.0
	var delta := to - from
	for axis in 2:
		if absf(delta[axis]) <= EPS:
			if absf(from[axis]) > half[axis] + EPS: return INF
		else:
			var a := (-half[axis] - from[axis]) / delta[axis]
			var b := (half[axis] - from[axis]) / delta[axis]
			lower = maxf(lower, minf(a, b))
			upper = minf(upper, maxf(a, b))
			if lower > upper + EPS: return INF
	return clampf(lower, 0.0, 1.0) if upper >= -EPS and lower <= 1.0 + EPS else INF

static func circle_entry(from: Vector2, to: Vector2, radius: float) -> float:
	var delta := to - from
	var c := from.length_squared() - radius * radius
	if c <= EPS: return 0.0
	var a := delta.length_squared()
	if a <= EPS: return INF
	var b := 2.0 * from.dot(delta)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < -EPS: return INF
	var u := (-b - sqrt(maxf(0.0, discriminant))) / (2.0 * a)
	return clampf(u, 0.0, 1.0) if u >= -EPS and u <= 1.0 + EPS else INF

## Relative circle-head versus a square item: two bands and four rounded
## corners are the exact Minkowski sum, after a cheap expanded-box rejection.
static func square_contact(head_from: Vector2, head_to: Vector2, segments: Array[Dictionary], half: float, radius := 0.35) -> float:
	for segment in segments:
		var start: Vector2 = head_from.lerp(head_to, segment.t0) - Vector2(segment.from)
		var finish: Vector2 = head_from.lerp(head_to, segment.t1) - Vector2(segment.to)
		if box_entry(start, finish, Vector2.ONE * (half + radius)) == INF: continue
		var entry := minf(box_entry(start, finish, Vector2(half + radius, half)), box_entry(start, finish, Vector2(half, half + radius)))
		for x in [-1, 1]:
			for y in [-1, 1]:
				var corner := Vector2(x, y) * half
				entry = minf(entry, circle_entry(start - corner, finish - corner, radius))
		if entry < INF:
			return float(segment.t0) + entry * (float(segment.t1) - float(segment.t0))
	return INF

static func covers(center: Vector2, half: float, cell: Vector2i) -> bool:
	# Positive area overlap; edge-only touching does not occupy a neighbouring cell.
	var rect := Rect2(center - Vector2.ONE * half, Vector2.ONE * half * 2.0)
	return rect.intersects(Rect2(Vector2(cell) + Vector2.ONE * 0.00001, Vector2.ONE * 0.99998))

static func square_clearance(from: Vector2, to: Vector2, half: float, radius := 0.35) -> float:
	if box_entry(from, to, Vector2.ONE * half) < INF: return -radius
	var minimum := minf((from.abs() - Vector2.ONE * half).max(Vector2.ZERO).length(), (to.abs() - Vector2.ONE * half).max(Vector2.ZERO).length())
	var delta := to - from
	# In one outside half-plane the nearest face/corner is known. Most mine
	# forecasts are short, distant sweeps; avoid testing the other corners.
	var side_x := 1 if minf(from.x, to.x) >= half else (-1 if maxf(from.x, to.x) <= -half else 0)
	var side_y := 1 if minf(from.y, to.y) >= half else (-1 if maxf(from.y, to.y) <= -half else 0)
	if side_x != 0 and side_y != 0:
		var corner := Vector2(side_x, side_y) * half
		var u := clampf((corner - from).dot(delta) / maxf(delta.length_squared(), EPS), 0.0, 1.0)
		return minf(minimum, corner.distance_to(from + delta * u)) - radius
	if (side_x != 0 and minf(from.y, to.y) >= -half and maxf(from.y, to.y) <= half) or (side_y != 0 and minf(from.x, to.x) >= -half and maxf(from.x, to.x) <= half):
		return minimum - radius
	for x in [-1, 1]:
		for y in [-1, 1]:
			var corner := Vector2(x, y) * half
			var u := clampf((corner - from).dot(delta) / maxf(delta.length_squared(), EPS), 0.0, 1.0)
			minimum = minf(minimum, corner.distance_to(from + delta * u))
	return minimum - radius

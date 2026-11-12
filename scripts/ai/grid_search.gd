class_name GridSearch
extends RefCounted

## A decision owns one budget across ALL BFS, flood fills, and threat searches.
var limit := 8192
var expansions := 0
var exhausted := false
var last_area := 0
var _queue := PackedInt32Array()
var _seen := PackedInt32Array()
var _blocked := PackedByteArray()
var _generation := 0

func _prepare(w: WorldSnapshot, blocked: Dictionary) -> void:
	var size := w.width * w.height
	if _queue.size() != size:
		_queue.resize(size)
		_seen.resize(size)
		_seen.fill(0)
		_blocked.resize(size)
	_generation += 1
	_blocked.fill(0)
	for cell: Vector2i in blocked:
		if w.in_bounds(cell): _blocked[cell.y * w.width + cell.x] = 1

static func _neighbor(index: int, direction: int, width: int, size: int) -> int:
	match direction:
		0: return index - width if index >= width else -1
		1: return index + 1 if index % width < width - 1 else -1
		2: return index + width if index + width < size else -1
		_: return index - 1 if index % width > 0 else -1

func spend() -> bool:
	if expansions >= limit:
		exhausted = true
		return false
	expansions += 1
	return true

## Equivalent to repeated spend(), including the failed attempt at the cap.
func spend_many(count: int) -> bool:
	if count > limit - expansions:
		expansions = limit
		exhausted = true
		return false
	expansions += count
	return true

## Iterative BFS doubles as flood fill and a distance map. Fixed neighbor order.
func scan(w: WorldSnapshot, start: Vector2i, blocked: Dictionary, goal := Vector2i(-1, -1)) -> Dictionary:
	_prepare(w, blocked)
	var size := w.width * w.height
	var origin := start.y * w.width + start.x
	var parents := PackedInt32Array()
	var distances := PackedInt32Array()
	parents.resize(size)
	distances.resize(size)
	distances.fill(-1)
	parents[origin] = origin
	distances[origin] = 0
	_queue[0] = origin
	_seen[origin] = _generation
	var cells: Array[Vector2i] = [start]
	var tail := 1
	var cursor := 0
	var complete := true
	while cursor < tail:
		if not spend():
			complete = false
			break
		var index := _queue[cursor]
		cursor += 1
		if cells[cursor - 1] == goal: break
		for direction in 4:
			var next := _neighbor(index, direction, w.width, size)
			if next < 0 or _blocked[next] or _seen[next] == _generation:
				continue
			_seen[next] = _generation
			parents[next] = index
			distances[next] = distances[index] + 1
			_queue[tail] = next
			tail += 1
			cells.append(Vector2i(next % w.width, next / w.width))
	return {"cells": cells, "parents": parents, "distances": distances, "width": w.width, "height": w.height, "complete": complete}

func area_at_least(w: WorldSnapshot, start: Vector2i, blocked: Dictionary, required: int) -> bool:
	_prepare(w, blocked)
	var size := w.width * w.height
	var origin := start.y * w.width + start.x
	_queue[0] = origin
	_seen[origin] = _generation
	var tail := 1
	var cursor := 0
	last_area = 1
	while cursor < tail and tail < required:
		if not spend():
			last_area = tail
			return false
		var index := _queue[cursor]
		cursor += 1
		for direction in 4:
			var next := _neighbor(index, direction, w.width, size)
			if next < 0 or _blocked[next] or _seen[next] == _generation: continue
			_seen[next] = _generation
			_queue[tail] = next
			tail += 1
	last_area = tail
	return tail >= required

func area_cells(w: WorldSnapshot) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in last_area: cells.append(Vector2i(_queue[i] % w.width, _queue[i] / w.width))
	return cells

static func distance(scan_result: Dictionary, cell: Vector2i, fallback := 1000000) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= scan_result.width or cell.y >= scan_result.height: return fallback
	var value: int = scan_result.distances[cell.y * int(scan_result.width) + cell.x]
	return value if value >= 0 else fallback

static func contains(scan_result: Dictionary, cell: Vector2i) -> bool:
	return distance(scan_result, cell, -1) >= 0

static func path(scan_result: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not contains(scan_result, goal):
		return result
	var parents: PackedInt32Array = scan_result.parents
	var width: int = scan_result.width
	var index := goal.y * width + goal.x
	while parents[index] != index:
		result.append(Vector2i(index % width, index / width))
		index = parents[index]
	result.append(Vector2i(index % width, index / width))
	result.reverse()
	return result

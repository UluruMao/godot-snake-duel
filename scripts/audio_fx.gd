class_name AudioFx
extends Node

const MIX := 22050.0


func beep() -> void:
	var dur := 0.09
	var n := int(MIX * dur)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := 660.0 + 440.0 * t / dur
		var s := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		var env := 1.0 - float(i) / n
		frames[i] = Vector2(s, s) * 0.22 * env
	_play(frames)


func click() -> void:
	var dur := 0.05
	var n := int(MIX * dur)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / MIX
		var s := 1.0 if sin(TAU * 440.0 * t) > 0.0 else -1.0
		var env := 1.0 - float(i) / n
		frames[i] = Vector2(s, s) * 0.15 * env
	_play(frames)


func zap() -> void:
	var dur := 0.12
	var n := int(MIX * dur)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var s := randf_range(-1.0, 1.0)
		var env := 1.0 - float(i) / n
		frames[i] = Vector2(s, s) * 0.18 * env
	_play(frames)


func thud() -> void:
	var dur := 0.1
	var n := int(MIX * dur)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := 140.0 - 60.0 * t / dur
		var s := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		var env := pow(1.0 - float(i) / n, 1.3)
		frames[i] = Vector2(s, s) * 0.3 * env
	_play(frames)


func crash() -> void:
	var dur := 0.6
	var n := int(MIX * dur)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env := pow(1.0 - float(i) / n, 1.5)
		var noise := randf_range(-1.0, 1.0)
		var f := 200.0 - 160.0 * t / dur
		var tone := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		var s := noise * 0.6 + tone * 0.4
		frames[i] = Vector2(s, s) * 0.3 * env
	_play(frames)


func _play(frames: PackedVector2Array) -> void:
	var p := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX
	gen.buffer_length = 0.8
	p.stream = gen
	add_child(p)
	p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb != null:
		pb.push_buffer(frames)
	var dur := frames.size() / MIX
	get_tree().create_timer(dur + 0.2).timeout.connect(p.queue_free)

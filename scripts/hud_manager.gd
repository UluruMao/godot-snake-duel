class_name HudManager
extends CanvasLayer

var _score_value: PixelLabel
var _time_value: PixelLabel
var _length_value: PixelLabel
var _boost_label: Label
var _effect_label: Label
var _mine_label: Label # Hidden diagnostic summary, never part of the play HUD.
var _captions: Dictionary = {}

func _ready() -> void:
	layer = 5
	var header := Panel.new()
	header.position = Vector2(24, 20)
	header.size = Vector2(1392, 72)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", UIStyle.box())
	add_child(header)
	var brand := UIStyle.pixel_label("SNAKE DUEL", 3)
	brand.position = Vector2(44, 34)
	add_child(brand)
	var subtitle := UIStyle.label("SURVIVAL / TACTICS", 12, UIStyle.ACCENT)
	subtitle.position = Vector2(46, 58)
	add_child(subtitle)
	_score_value = _stat("SCORE", Vector2(740, 26), 200)
	_time_value = _stat("TIME", Vector2(970, 26), 120)
	_length_value = _stat("LENGTH", Vector2(1120, 26), 100)
	var status := HBoxContainer.new()
	status.position = Vector2(680, 102)
	status.size = Vector2(728, 28)
	status.alignment = BoxContainer.ALIGNMENT_END
	status.add_theme_constant_override("separation", 20)
	add_child(status)
	_boost_label = UIStyle.label("", 17, UIStyle.ACCENT)
	status.add_child(_boost_label)
	_effect_label = UIStyle.label("", 17, UIStyle.MUTED)
	status.add_child(_effect_label)
	_mine_label = Label.new()
	_mine_label.visible = false
	add_child(_mine_label)
	set_score(0)
	set_time(0)
	set_boost_state(false)

func _stat(caption: String, position: Vector2, width: float) -> PixelLabel:
	var title := UIStyle.pixel_label(caption, 2, UIStyle.MUTED)
	title.position = position
	_captions[caption] = title
	add_child(title)
	var value := UIStyle.pixel_label("0", 4)
	value.position = position + Vector2(0, 22)
	value.set_meta("stat_width", width)
	add_child(value)
	return value

func set_score(value: int) -> void:
	_score_value.text = str(value)
	_fit_stat(_score_value)

func set_time(seconds: float) -> void:
	var elapsed := int(seconds)
	_time_value.text = "%02d:%02d" % [elapsed / 60, elapsed % 60]
	_fit_stat(_time_value)

func _fit_stat(value: PixelLabel) -> void:
	var width := float(value.get_meta("stat_width"))
	value.pixel = clampi(floori(width / maxf(1, value.text.length() * 6 - 1)), 1, 4)

func set_boost_state(active: bool, available := true, speed := SpeedRules.NORMAL_SPEED) -> void:
	_boost_label.visible = active and available
	_boost_label.text = "BOOST %.2f/s" % speed

func set_effects(w: WorldSnapshot) -> void:
	_mine_label.text = "MINES %d / %d | BEANS %d | DIAMONDS %d | OBSTACLES %d" % [w.mines.size(), MineRules.CAP, w.beans.size(), PickupRules.moving_count(w, PickupRules.DIAMOND), w.obstacles.size()]
	var has_player := w.snakes.has("player")
	_captions.SCORE.text = "SCORE" if has_player else "TICK"
	_captions.LENGTH.text = "LENGTH" if has_player else "AGENTS"
	_score_value.text = str(w.score) if has_player else str(w.tick)
	_fit_stat(_score_value)
	var agents := 0
	for actor: SnakeState in w.snakes.values(): agents += int(actor.alive and not actor.is_player)
	_length_value.text = str(w.snakes.player.cells.size()) if has_player else str(agents)
	_fit_stat(_length_value)
	var effects: Array[String] = []
	if w.snakes.has("player"):
		var player: SnakeState = w.snakes.player
		for kind: String in ItemRules.PICKUPS:
			if player.has_effect(kind, w.tick): effects.append("%s %.1fs" % [kind.replace("_", " ").to_upper(), (int(player.effects[kind]) - w.tick) * 0.02])
		if w.in_combat("player"): effects.assign(["HEAD DUEL · turn to escape"])
		elif player.chance_ticks > 0: effects.assign(["SECOND CHANCE · turn now"])
	_effect_label.text = "   ".join(effects)
	_effect_label.visible = not effects.is_empty()

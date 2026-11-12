extends Node2D

## Select Main in the editor, expand Enemy Spawning and its per-type entries.
@export var enemy_spawning: EnemySpawnConfig = preload("res://resources/enemy_spawning.tres")
@export var drops: DropConfig = preload("res://resources/drops.tres")
@export_group("AI Scheduling")
@export var early_planning_enabled := true


func _ready() -> void:
	Engine.max_fps = 60
	get_window().content_scale_size = Vector2i(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

	var container := SubViewportContainer.new()
	container.stretch = false # Fixed render canvas; root Window uniformly fits it.
	container.position = Vector2.ZERO
	container.size = Vector2(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	container.add_to_group("crt_host")
	var crt_shader := load("res://shaders/crt.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = crt_shader
	container.material = mat
	add_child(container)

	var vp := SubViewport.new()
	vp.size = Vector2i(GridConfig.VIEWPORT_W, GridConfig.VIEWPORT_H)
	vp.handle_input_locally = true
	vp.gui_embed_subwindows = true
	container.add_child(vp)

	var game := Node2D.new()
	game.set_script(load("res://scripts/game.gd"))
	game.set("enemy_spawning", enemy_spawning)
	game.set("drops", drops)
	game.set("early_planning_enabled", early_planning_enabled)
	vp.add_child(game)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F12 or (event.alt_pressed and event.keycode == KEY_ENTER)):
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()

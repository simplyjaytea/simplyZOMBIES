extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://presentation/main.tscn") as PackedScene
	if packed_scene == null:
		_fail("Cannot load the main scene")
		return
	var main := packed_scene.instantiate()
	if main.get_script() == null:
		_fail("The main scene script did not compile")
		return
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		_fail("The main scene did not construct its simulation world")
		return
	print("GODOT_PROJECT_SMOKE_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

const ContentValidator = preload("res://platform/content_validator.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var issues: Array = ContentValidator.validate_tree("res://content")
	if issues.is_empty():
		print("GODOT_CONTENT_OK")
		quit(0)
	else:
		for msg in issues:
			push_error(String(msg))
		print("GODOT_CONTENT_FAIL %d issue(s)" % issues.size())
		quit(1)

class_name ContentLoader
extends RefCounted


static func load_tree(root: String = "res://content") -> Dictionary:
	var paths: Array[String] = []
	_collect_json(root, paths)
	paths.sort()

	var loaded: Dictionary = {}
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "Cannot open content file: %s" % path)
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		assert(error == OK, "Invalid JSON in %s at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		loaded[path.trim_prefix(root + "/")] = parser.data
	return loaded


static func _collect_json(directory_path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	assert(directory != null, "Cannot open content directory: %s" % directory_path)

	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() == "json":
			paths.append(directory_path.path_join(file_name))
	for child_name in directory.get_directories():
		_collect_json(directory_path.path_join(child_name), paths)

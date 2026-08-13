extends SceneTree

const Content = preload("res://platform/content_loader.gd")
const World = preload("res://sim/world.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := Content.load_tree()
	if not content.has("zombies/base.json") or not content.has("schemas/item.schema.json"):
		push_error("Godot did not load the canonical content tree")
		quit(2)
		return
	var options := _options(OS.get_cmdline_user_args())
	var fixture := _read_json(String(options.get("fixture", "")))
	var expected := _read_json(String(options.get("expected", "")))
	if fixture.is_empty() or expected.is_empty():
		quit(2)
		return

	var world := World.new(fixture)
	var actual: Dictionary = world.run_fixture(fixture)
	var difference := _difference(expected, actual, "$")
	if not difference.is_empty():
		push_error("R1 parity failed: %s" % difference)
		print("R1_PARITY_ACTUAL %s" % JSON.stringify(actual, "", true, true))
		quit(1)
		return

	print("R1_PARITY_OK %s" % JSON.stringify(actual, "", true, true))
	quit(0)


func _options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index := 0
	while index < arguments.size():
		var argument := arguments[index]
		if argument.begins_with("--") and index + 1 < arguments.size():
			result[argument.trim_prefix("--")] = arguments[index + 1]
			index += 2
		else:
			index += 1
	return result


func _read_json(path: String) -> Dictionary:
	if path.is_empty():
		push_error("Missing parity file path")
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open parity file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Parity file is not a JSON object: %s" % path)
		return {}
	return parsed


func _difference(expected: Variant, actual: Variant, path: String) -> String:
	if (expected is int or expected is float) and (actual is int or actual is float):
		if abs(float(expected) - float(actual)) > 0.000000000001:
			return "%s expected %s, got %s" % [path, expected, actual]
		return ""
	if typeof(expected) != typeof(actual):
		return "%s type differs: expected %s, got %s" % [path, type_string(typeof(expected)), type_string(typeof(actual))]
	if expected is Dictionary:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		if expected_dictionary.size() != actual_dictionary.size():
			return "%s key count differs" % path
		for key: Variant in expected_dictionary.keys():
			if not actual_dictionary.has(key):
				return "%s missing key %s" % [path, key]
			var nested := _difference(expected_dictionary[key], actual_dictionary[key], "%s.%s" % [path, key])
			if not nested.is_empty():
				return nested
		return ""
	if expected is Array:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size():
			return "%s length differs" % path
		for index in expected_array.size():
			var nested := _difference(expected_array[index], actual_array[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return ""
	return "" if expected == actual else "%s expected %s, got %s" % [path, expected, actual]

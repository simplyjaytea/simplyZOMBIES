class_name ContentReload
extends RefCounted
# R5 — dev content reload: validate into throwaway, then reload world on success.
# Never puts Resources into sim state. Invalid edits do not reload; HUD shows error.

static func try_reload_world(world: Variant) -> Dictionary:
	# Returns {ok: bool, issues: Array[String]}. On ok, world.content + seed-stable state updated.
	var validator: GDScript = load("res://platform/content_validator.gd") as GDScript
	var issues: Array = validator.call("validate_tree", "res://content") as Array
	if not issues.is_empty():
		var msgs: Array[String] = []
		for it in issues:
			msgs.append(String(it))
		return {"ok": false, "issues": msgs}
	# valid — reload tree onto world (no Node/Resource in state, just Dictionary)
	var loader: GDScript = load("res://platform/content_loader.gd") as GDScript
	var tree: Dictionary = loader.call("load_tree", "res://content") as Dictionary
	world.content = tree
	return {"ok": true, "issues": []}

# Change detection for the poll in main.gd. A fingerprint of the tree -- every JSON path with its
# modified time and length, folded into one integer -- costs a directory walk and no file opens,
# where the poll it replaces validated and parsed every file three times over, twice a second,
# whether or not anything had changed (docs/23's defect list, fixed 2026-09-13; the RELOAD-COST
# lane in check_hud.gd). The presentation caches the last value and reloads only when it moves.
#
# Modified time alone is not enough: its granularity is one second on some filesystems, and an
# edit made while balancing is exactly a same-second edit, so the length goes into the fold too.

static func content_fingerprint(root: String = "res://content") -> int:
	var paths: Array[String] = []
	_collect_json_paths(root, paths)
	paths.sort()
	var entries: Array = []
	for path in paths:
		var length: int = -1
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			length = int(f.get_length())
			f = null
		entries.append([path, int(FileAccess.get_modified_time(path)), length])
	return fold_fingerprint(entries)


# The fold, on its own so a gate can prove it tells a moved mtime from an unmoved one on a
# fabricated list without touching the shipped tree. Each entry is [path, mtime, length].
static func fold_fingerprint(entries: Array) -> int:
	var acc: int = 17
	for e in entries:
		var row: Array = e as Array
		acc = hash([acc, String(row[0]), int(row[1]), int(row[2])])
	return acc


static func _collect_json_paths(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() == "json":
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect_json_paths(dir.path_join(sub), out)

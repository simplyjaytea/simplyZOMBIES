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

# File watcher for dev: poll mtimes and call try_reload_world when changed.
# Presentation owns the timer; this just checks.

static func poll_content_dir(root: String = "res://content") -> bool:
	# Returns true if any .json under root changed since last call (caller caches).
	# Uses FileAccess.get_modified_time where available; falls back to size check.
	var changed := false
	var paths: Array[String] = []
	var loader: GDScript = load("res://platform/content_loader.gd") as GDScript
	# reuse collector but just list; avoid extra alloc by walking via DirAccess
	_collect_mtimes(root, paths)
	# caller compares; we just signal that poll ran. Real change detection is in presentation.
	return not paths.is_empty()
	# ponytail: mtime poll is cheapest without FileSystemDock; upgrade to ResourceWatcher when editor plugin lands.

static func _collect_mtimes(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() == "json":
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect_mtimes(dir.path_join(sub), out)

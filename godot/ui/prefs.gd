extends RefCounted
# Presentation preferences, persisted to user://. Sim never reads these -- they are how the
# screen looks, not what the world is, so they live beside the UI and not in the save file
# (a save carries the run; how transparent your panels are survives the run's death).
#
# There used to be a `windows` table here keyed by a container's *label*, remembering where each
# bag window had been dragged and whether it was pinned. The 2026-09-08 overhaul gave the sheet
# one fixed layout, so there is no window to place and nothing to remember: the whole table went
# with the windows, and with it the label-collision shortcut ("two identical bags share a slot")
# that had been written down here as a known compromise.

const PATH: String = "user://ui_prefs.json"

const DEFAULTS: Dictionary = {
	"inventory_opacity": 0.95,
}

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = DEFAULTS.duplicate(true)
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in (parsed as Dictionary).keys():
			_cache[String(k)] = (parsed as Dictionary)[k]


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_cache))


static func opacity(key: String) -> float:
	_ensure()
	return clampf(float(_cache.get(key, DEFAULTS.get(key, 1.0))), 0.15, 1.0)


static func set_opacity(key: String, value: float) -> void:
	_ensure()
	_cache[key] = clampf(value, 0.15, 1.0)
	_save()


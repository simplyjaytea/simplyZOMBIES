extends RefCounted
# Presentation preferences, persisted to user://. Sim never reads these -- they are how the
# screen looks, not what the world is, so they live beside the UI and not in the save file
# (a save carries the run; how transparent your bags are survives the run's death).
#
# Window positions and pins are keyed by the container's *label* ("pockets", "Hiking Pack").
# Two identical bags would share a slot; acceptable until a stable per-item identity exists
# across saves, and named here so the shortcut is a decision rather than an accident.

const PATH: String = "user://ui_prefs.json"

const DEFAULTS: Dictionary = {
	"inventory_opacity": 0.95,
	"pinned_opacity": 0.85,
	"windows": {}, # label -> {"x": float, "y": float, "pinned": bool}
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


static func _window(label: String) -> Dictionary:
	_ensure()
	var wins: Dictionary = _cache.get("windows", {}) as Dictionary
	return wins.get(label, {}) as Dictionary


static func window_pos(label: String) -> Variant:
	var w: Dictionary = _window(label)
	if w.has("x") and w.has("y"):
		return Vector2(float(w["x"]), float(w["y"]))
	return null


static func window_pinned(label: String) -> bool:
	return bool(_window(label).get("pinned", false))


static func set_window(label: String, pos: Vector2, pinned: bool) -> void:
	_ensure()
	if not (_cache.get("windows") is Dictionary):
		_cache["windows"] = {}
	(_cache["windows"] as Dictionary)[label] = {"x": pos.x, "y": pos.y, "pinned": pinned}
	_save()

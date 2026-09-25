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
	# Has the player put the key list away for good? False on a fresh machine, so a first run
	# opens on the legend; set by the three explicit dismissals (F1 off, Escape, Enter) and by
	# nothing else. `main.gd`'s `_enter_state` is the one reader: the keys are raised on the first
	# entry to PLAYING and never over the title, which is where they were raised before the shell.
	"legend_dismissed": false,
	# The master volume, nought to one, read by `presentation/sfx.gd` and pushed at the audio bus
	# there -- the first thing in this tree ever to reach `AudioServer` (docs/30, "The alpha
	# shell", 2026-09-16). A preference and not save state, for the same reason the opacity is.
	"volume": 1.0,
	# Stand every UI animation still on the frame the kit names for it (`ui/motion.gd`). Off on a
	# fresh machine -- the owner's decision of 2026-09-25 (docs/30, "The UI Field Kit, live") -- and
	# a preference, not a difficulty or accessibility flag the sim reads. The settings sheet's toggle
	# row is the one writer.
	"reduced_motion": false,
}

# The floor each slider clamps to. Opacity has one, because a panel at nought alpha is a panel
# you cannot find again; **volume does not**, because nought is mute and mute is the whole point
# of the row. There was one shared 0.15 clamp here until the volume row landed, and leaving it
# shared would have made the leftmost notch a game you can still hear.
const FLOORS: Dictionary = {
	"inventory_opacity": 0.15,
	"volume": 0.0,
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


# Every slider in `ui/settings_panel.gd` goes through these two, with its floor read off FLOORS
# rather than written into the call -- one clamp, so a row cannot be stored outside the range the
# panel will draw it in.
static func level(key: String) -> float:
	_ensure()
	var floor_at: float = float(FLOORS.get(key, 0.0))
	return clampf(float(_cache.get(key, DEFAULTS.get(key, 1.0))), floor_at, 1.0)


static func set_level(key: String, value: float) -> void:
	_ensure()
	_cache[key] = clampf(value, float(FLOORS.get(key, 0.0)), 1.0)
	_save()


# The opacity pair, kept as the name three panels already call: a forward to `level`, not a
# second clamp beside it.
static func opacity(key: String) -> float:
	return level(key)


static func set_opacity(key: String, value: float) -> void:
	set_level(key, value)


# What `presentation/sfx.gd` reads on every change and at boot. Nought is mute and is stored as
# nought -- see FLOORS.
static func volume() -> float:
	return level("volume")


static func set_volume(value: float) -> void:
	set_level("volume", value)


# The boolean half. A pref file written by an older build has no row for a flag added since, so
# the default answers rather than `false` answering for everything -- the same fallback the
# opacity getter uses, and the reason DEFAULTS carries the flag at all.
static func flag(key: String) -> bool:
	_ensure()
	return bool(_cache.get(key, DEFAULTS.get(key, false)))


static func set_flag(key: String, value: bool) -> void:
	_ensure()
	_cache[key] = value
	_save()

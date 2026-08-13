class_name SimSave
extends RefCounted

const SimSerialize = preload("res://sim/kernel/serialize.gd")

# Matches src/sim/kernel/save.ts — snapshot + meta, canonical text, version/corrupt guards.

static func create_save(world: Variant) -> Dictionary:
	return {
		"snapshot": (world as RefCounted).call("snapshot"),
		"meta": {"savedAtTick": int(world.tick), "seed": int(world.seed)},
	}

static func encode_save(save: Dictionary) -> String:
	return SimSerialize.canonicalize(save)

# Returns Dictionary on success. On failure pushes error and returns empty dict with "__error".
# Callers that need throw semantics can check "__error" or use decode_save_or_throw.
static func decode_save(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		# JSON.parse_string returns null on failure; try explicit parser for message
		var p := JSON.new()
		var err := p.parse(text)
		var msg: String = p.get_error_message() if err != OK else "parse failed"
		push_error("Save file is unreadable: %s" % msg)
		return {"__error": "CorruptSaveError", "__reason": msg}
	if not parsed is Dictionary:
		push_error("Save file is unreadable: expected an object")
		return {"__error": "CorruptSaveError", "__reason": "expected an object"}
	var raw: Dictionary = parsed as Dictionary
	if not raw.has("snapshot"):
		push_error("Save file is unreadable: missing snapshot")
		return {"__error": "CorruptSaveError", "__reason": "missing snapshot"}
	var snap: Variant = raw["snapshot"]
	if not snap is Dictionary:
		push_error("Save file is unreadable: missing snapshot")
		return {"__error": "CorruptSaveError", "__reason": "missing snapshot"}
	var snapd: Dictionary = snap as Dictionary
	if not snapd.has("version"):
		push_error("Save file is unreadable: missing version stamp")
		return {"__error": "CorruptSaveError", "__reason": "missing version stamp"}
	var ver: Variant = snapd["version"]
	if not ver is int and not ver is float:
		push_error("Save file is unreadable: missing version stamp")
		return {"__error": "CorruptSaveError", "__reason": "missing version stamp"}
	if int(ver) != int(SimSerialize.SAVE_VERSION):
		push_error("This save was written by an incompatible version (save format %d, this build reads %d). Saves may break before 1.0 and are not migrated -- start a new run." % [int(ver), int(SimSerialize.SAVE_VERSION)])
		return {"__error": "StaleSaveError", "__found": int(ver), "__expected": int(SimSerialize.SAVE_VERSION)}
	return raw

static func decode_save_or_throw(text: String) -> Dictionary:
	var r: Dictionary = decode_save(text)
	if r.has("__error"):
		var kind: String = String(r["__error"])
		if kind == "StaleSaveError":
			assert(false, "StaleSaveError: save format %s reads %s" % [r.get("__found"), r.get("__expected")])
		else:
			assert(false, "CorruptSaveError: %s" % r.get("__reason", "corrupt"))
	return r

static func apply_save(world: Variant, save: Dictionary) -> void:
	var snap: Dictionary = save["snapshot"] as Dictionary
	(world as RefCounted).call("restore", snap)

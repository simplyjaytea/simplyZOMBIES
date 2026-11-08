class_name FirstPersonSaveSlot
extends RefCounted
# The first-person scene's save slot. It uses the same storage adapter the top-down game writes
# through (`platform/storage.gd`, atomic on desktop, double-buffered on web), under its own key, so
# the two scenes never overwrite each other's save. The top-down slot is `simplyzombies.save`; this
# one is `simplyzombies.first_person`, which on desktop is `user://simplyzombies.first_person.json`.
#
# Presentation only: the sim's `SimSave` makes and reads the text; this file only says where it goes.

const PlatformStorage = preload("res://platform/storage.gd")

const DEFAULT_KEY: String = "simplyzombies.first_person"

# The key the slot reads and writes. The gate points it at a throwaway key and deletes that key
# afterwards, so no lane ever touches a real player's save.
static var slot_key: String = DEFAULT_KEY

# Set by the default title's continue just before the scene change, read and cleared by the
# first-person scene's _ready, which then loads the slot before its first frame (docs/30, 2026-11-07).
# One-shot: a plain boot, or a later boot, starts a fresh run.
static var load_on_boot: bool = false


# Is there a slot to offer as continue? The default title asks this; it does not decode the slot,
# so a slot that will not load still gets its row and says why when chosen (main.gd's continue_refusal).
static func has_save() -> bool:
	return not read().is_empty()


static func write(text: String) -> bool:
	if OS.has_feature("web"):
		return PlatformStorage.write_web_double_buffered(slot_key, text)
	return PlatformStorage.write_file_atomic(slot_key, text)


static func read() -> String:
	if OS.has_feature("web"):
		var v: String = PlatformStorage.read_web(slot_key)
		if v != "":
			return v
	return PlatformStorage.read_file(slot_key)


static func remove() -> void:
	if OS.has_feature("web"):
		PlatformStorage.remove_web(slot_key)
	PlatformStorage.remove_file(slot_key)

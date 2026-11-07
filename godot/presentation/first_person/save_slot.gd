class_name FirstPersonSaveSlot
extends RefCounted
# The first-person scene's save slot. It uses the same storage adapter the top-down game writes
# through (`platform/storage.gd`, atomic on desktop, double-buffered on web), under its own key, so
# the two scenes never overwrite each other's save. The top-down slot is `simplyzombies.save`; this
# one is `simplyzombies.first_person`, which on desktop is `user://simplyzombies.first_person.json`.
#
# Presentation only: the sim's `SimSave` makes and reads the text; this file only says where it goes.
#
# The Reports page's read mark is presentation state too, and it lives beside the slot under a sibling
# key (`<slot>.reads`), not inside the sim's save text: the save format and SAVE_VERSION do not move. A slot
# with no sibling key (an older save) reads as mark 0, which is what the page did before the mark was kept.

const PlatformStorage = preload("res://platform/storage.gd")

const DEFAULT_KEY: String = "simplyzombies.first_person"
const READS_SUFFIX: String = ".reads"

# The key the slot reads and writes. The gate points it at a throwaway key and deletes that key
# afterwards, so no lane ever touches a real player's save.
static var slot_key: String = DEFAULT_KEY


static func write(text: String) -> bool:
	return _write(slot_key, text)


static func read() -> String:
	return _read(slot_key)


static func remove() -> void:
	_remove(slot_key)
	_remove(reads_key())


## The key the read mark sits under: the slot's key with a suffix, so it moves with a swapped slot key.
static func reads_key() -> String:
	return slot_key + READS_SUFFIX


## Stores the Reports page's read mark beside the slot.
static func write_reads(mark: int) -> bool:
	return _write(reads_key(), str(maxi(0, mark)))


## The stored read mark, or 0 when there is none (an older save, or the mark was removed).
static func read_reads() -> int:
	var text: String = _read(reads_key()).strip_edges()
	if text.is_empty() or not text.is_valid_int():
		return 0
	return maxi(0, int(text))


## Removes the stored read mark only, so the next load reads mark 0. The gate uses it to test an older save.
static func remove_reads() -> void:
	_remove(reads_key())


static func _write(key: String, text: String) -> bool:
	if OS.has_feature("web"):
		return PlatformStorage.write_web_double_buffered(key, text)
	return PlatformStorage.write_file_atomic(key, text)


static func _read(key: String) -> String:
	if OS.has_feature("web"):
		var v: String = PlatformStorage.read_web(key)
		if v != "":
			return v
	return PlatformStorage.read_file(key)


static func _remove(key: String) -> void:
	if OS.has_feature("web"):
		PlatformStorage.remove_web(key)
	PlatformStorage.remove_file(key)

class_name PlatformStorage
extends RefCounted
# R5 platform — persistence adapters with atomic-or-equivalent guarantee.
# Desktop: temp + flush + rename in same dir (rename atomic on one FS).
# Web: double-buffered slots + pointer flip (localStorage has no rename).
# Mirrors src/platform/storage.ts without touching sim state (Resources/Nodes never stored).

const SAVE_KEY: String = "simplyzombies.save"

# — desktop (user:// — same FS, atomic rename) —

static func _file_for(key: String) -> String:
	return "user://%s.json" % key

static func read_file(key: String) -> String:
	var path: String = _file_for(key)
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

# Write to a temp file beside the target, then rename it over the target. The rename is the
# whole guarantee (docs/22 "Save performance", docs/19's save model): at no instant is there no
# save on disk. This used to delete the existing save *before* the rename, "so the rename would
# not fail" -- and that delete was the window the name promised there was not (docs/23's defect
# list, fixed 2026-09-13; check_m2_save.gd's ATOMIC lane reads this body for the delete).
#
# What the engine gives us, honestly: on Unix `DirAccess.rename` is POSIX rename(2), which
# replaces an existing target atomically on one filesystem, and user:// is one filesystem. On
# Windows the engine's own DirAccessWindows::rename removes and then renames internally, so the
# window shrinks to the engine's and cannot be closed from GDScript. Godot 4 exposes no fsync, so
# the oracle's `fsyncSync` (src/platform/storage.ts) has no twin here: `flush` empties Godot's
# buffer, not the OS page cache.
static func write_file_atomic(key: String, value: String) -> void:
	var target: String = _file_for(key)
	var tmp: String = target + ".tmp"
	var da := DirAccess.open("user://")
	assert(da != null)
	# A crashed earlier write may have left its temp file behind; it is never read, only replaced.
	if da.file_exists(tmp.get_file()):
		da.remove(tmp.get_file())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	assert(f != null, "storage: cannot open %s for write" % tmp)
	f.store_string(value)
	f.flush()
	f = null
	var err := da.rename(tmp.get_file(), target.get_file())
	assert(err == OK, "storage: atomic rename failed %s -> %s (%d)" % [tmp, target, err])

static func remove_file(key: String) -> void:
	var path: String = _file_for(key)
	if FileAccess.file_exists(path):
		var da := DirAccess.open("user://")
		if da != null:
			da.remove(path.get_file())

# — web double-buffer (uses same file API but emulates localStorage semantics) —
# In Godot Web, user:// is IndexedDB-backed anyway; double-buffer here is for
# explicit crash semantics tests. Two slots + pointer.

static func _slot_key(key: String, slot: int) -> String:
	return "user://%s.slot%d.json" % [key, slot]

static func _pointer_key(key: String) -> String:
	return "user://%s.live" % key

static func _live_slot(key: String) -> int:
	var p := _pointer_key(key)
	if not FileAccess.file_exists(p):
		return 0
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	return 1 if f.get_as_text().strip_edges() == "1" else 0

static func read_web(key: String) -> String:
	var slot: int = _live_slot(key)
	var path: String = _slot_key(key, slot)
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()

static func write_web_double_buffered(key: String, value: String) -> void:
	var live: int = _live_slot(key)
	var nxt: int = 1 if live == 0 else 0
	var slot_path: String = _slot_key(key, nxt)
	var f := FileAccess.open(slot_path, FileAccess.WRITE)
	assert(f != null, "storage: cannot open slot %s" % slot_path)
	f.store_string(value)
	f.flush()
	f = null
	# pointer flip — single small write, smallest crash window
	var pf := FileAccess.open(_pointer_key(key), FileAccess.WRITE)
	assert(pf != null)
	pf.store_string(String.num_int64(nxt))
	pf.flush()

static func remove_web(key: String) -> void:
	var da := DirAccess.open("user://")
	if da == null:
		return
	for s in [0, 1]:
		var p: String = _slot_key(key, s)
		if FileAccess.file_exists(p):
			da.remove(p.get_file())
	var live_p: String = _pointer_key(key)
	if FileAccess.file_exists(live_p):
		da.remove(live_p.get_file())

# — unified: auto-select by platform —

static func read_save() -> String:
	if OS.has_feature("web"):
		var v: String = read_web(SAVE_KEY)
		if v != "":
			return v
		# fallback to single-file if web slot not yet used
		return read_file(SAVE_KEY)
	return read_file(SAVE_KEY)

static func write_save(value: String) -> void:
	if OS.has_feature("web"):
		write_web_double_buffered(SAVE_KEY, value)
	else:
		write_file_atomic(SAVE_KEY, value)

static func remove_save() -> void:
	if OS.has_feature("web"):
		remove_web(SAVE_KEY)
	remove_file(SAVE_KEY)

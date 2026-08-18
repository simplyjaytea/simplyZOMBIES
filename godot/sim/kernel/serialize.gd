class_name SimSerialize
extends RefCounted

# 13: the survivor body schema changed shape -- "arms"/"hands"/"legs"/"feet" split into
# independent left/right parts (docs/30-decisions.md). A v12 save's body dict has the old
# keys and would silently mismatch every part lookup rather than fail loudly, so this is a
# version bump rather than a migration. save.gd already rejects a version mismatch with
# "start a new run" -- saves are not migrated before 1.0.
# 14: two more component shapes changed. "posture" gained "target"/"ticks_left" (it used to
# be `{"current": n}` alone -- SimStances.make_posture builds the full shape now) and
# "stamina.current" became a float instead of an int (it had to, to regenerate at all: see
# health.gd's health.recover). A v13 save's posture dict is missing keys request_stance reads
# unconditionally, and its stamina.current would silently truncate every regen tick again.
# 15: Slice 2 Part A -- wounds that bleed. "injuries" gained "bloodLoss" (float, the
# blood-loss accumulator) and every wound entry in "wounds" gained four keys: "severity"
# (int), "bleeding" (bool), "bandage" (String -- a tier word once Part B's treatment.gd could
# write one), "clotsAtTick" (int). A v14 save's wound entries are missing keys wounds.bleed
# reads unconditionally (severity, bleeding, clotsAtTick), and its injuries dict has no
# bloodLoss to accumulate into -- same class of silent-mismatch-not-migration as 13 and 14.
# Part B did **not** need a bump on top of this: it changed no existing component's shape.
# Its "treatment"/"treated" components are new and transient, and component_store.save() is
# generic, so a v15 save from before Part B loads into a v15 world with no channel running --
# which is exactly what a save taken between two acts of first aid should mean.
# 16: Slice 3 -- recovery. Every wound entry gained "healedTicks" (int, the *earned* recovery
# time: it only advances on ticks the survivor was fed and not exerting). wounds.recover reads
# and increments it unconditionally, so a v15 wound entry would start from a missing key. The
# same slice made part integrity climb again, which is a value change rather than a shape one
# and would not have needed a bump on its own.
const SAVE_VERSION: int = 16


static func canonicalize(value: Variant, path: String = "$") -> String:
	if value == null:
		return "null"
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			var f: float = float(value)
			if is_nan(f):
				push_error("serialize: NaN at %s" % path)
				return "null"
			if is_inf(f):
				push_error("serialize: Inf at %s" % path)
				return "null"
			if is_zero_approx(f) and str(value) == "-0" or (f == 0.0 and signf(f) < 0):
				push_error("serialize: negative zero at %s" % path)
			# TS has no int/float distinction: 4 and 4.0 must serialize identically.
			# JSON round-trip via Godot turns ints into floats (4 -> 4.0); normalize
			# integral floats to int string so fingerprint is stable across save/load.
			if f == float(int(f)) and f >= -9007199254740992.0 and f <= 9007199254740992.0:
				return JSON.stringify(int(f))
			return JSON.stringify(f)
		TYPE_STRING, TYPE_BOOL:
			return JSON.stringify(value)
		TYPE_VECTOR2I:
			var v2i: Vector2i = value as Vector2i
			return '{"x":%s,"y":%s}' % [canonicalize(v2i.x, path + ".x"), canonicalize(v2i.y, path + ".y")]
		TYPE_VECTOR2:
			var v2: Vector2 = value as Vector2
			return '{"x":%s,"y":%s}' % [canonicalize(v2.x, path + ".x"), canonicalize(v2.y, path + ".y")]
		TYPE_NIL:
			return '"__undefined__"'
		TYPE_ARRAY:
			var arr: Array = value as Array
			var parts: Array[String] = []
			for i in arr.size():
				parts.append(canonicalize(arr[i], "%s[%d]" % [path, i]))
			return "[%s]" % ",".join(parts)
		TYPE_DICTIONARY:
			var d: Dictionary = value as Dictionary
			var keys: Array = d.keys()
			keys.sort()
			var kparts: Array[String] = []
			for k in keys:
				kparts.append("%s:%s" % [JSON.stringify(String(k)), canonicalize(d[k], "%s.%s" % [path, String(k)])])
			return "{%s}" % ",".join(kparts)
		_:
			push_error("serialize: cannot serialize %s at %s" % [type_string(typeof(value)), path])
			return "null"


static func fingerprint(canonical: String) -> String:
	var h1: int = 0xdeadbeef
	var h2: int = 0x41c6ce57
	for i in canonical.length():
		var ch: int = canonical.unicode_at(i)
		h1 = _imul32(h1 ^ ch, 2654435761)
		h2 = _imul32(h2 ^ ch, 1597334677)
	h1 = _imul32(h1 ^ (h1 >> 16), 2246822507) ^ _imul32(h2 ^ (h2 >> 13), 3266489909)
	h2 = _imul32(h2 ^ (h2 >> 16), 2246822507) ^ _imul32(h1 ^ (h1 >> 13), 3266489909)
	return "%08x%08x" % [(h2 & 0xffffffff), (h1 & 0xffffffff)]


static func _imul32(a: int, b: int) -> int:
	var a_low: int = a & 0xffff
	var a_high: int = (a >> 16) & 0xffff
	var b_low: int = b & 0xffff
	var b_high: int = (b >> 16) & 0xffff
	return (a_low * b_low + ((a_high * b_low + a_low * b_high) << 16)) & 0xffffffff

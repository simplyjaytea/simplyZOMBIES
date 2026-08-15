class_name SimSerialize
extends RefCounted

const SAVE_VERSION: int = 11


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

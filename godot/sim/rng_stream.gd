class_name SimRngStream
extends RefCounted

const U32_MASK: int = 0xffffffff
const U32_RANGE: float = 4294967296.0

var _state: int


func _init(seed: int) -> void:
	_state = seed & U32_MASK


static func derive_seed(master_seed: int, stream_name: String) -> int:
	var hash: int = (0x811c9dc5 ^ (master_seed & U32_MASK)) & U32_MASK
	for index: int in stream_name.length():
		hash = hash ^ stream_name.unicode_at(index)
		hash = _imul32(hash, 0x01000193)
	return 0x9e3779b9 if hash == 0 else hash


func next() -> float:
	_state = (_state + 0x6d2b79f5) & U32_MASK
	var value: int = _state
	value = _imul32(value ^ (value >> 15), value | 1)
	value = value ^ ((value + _imul32(value ^ (value >> 7), value | 61)) & U32_MASK)
	return float((value ^ (value >> 14)) & U32_MASK) / U32_RANGE


func int_range(min_inclusive: int, max_inclusive: int) -> int:
	return min_inclusive + int(floor(next() * float(max_inclusive - min_inclusive + 1)))


func float_range(min_inclusive: float, max_exclusive: float) -> float:
	return min_inclusive + next() * (max_exclusive - min_inclusive)


func bool_chance(chance_true: float = 0.5) -> bool:
	return next() < chance_true


func pick(items: Array) -> Variant:
	assert(not items.is_empty(), "rng.pick: empty array")
	return items[int_range(0, items.size() - 1)]


func save() -> int:
	return _state


func restore(state: int) -> void:
	_state = state & U32_MASK


static func _imul32(a: int, b: int) -> int:
	var a_low: int = a & 0xffff
	var a_high: int = (a >> 16) & 0xffff
	var b_low: int = b & 0xffff
	var b_high: int = (b >> 16) & 0xffff
	return (a_low * b_low + ((a_high * b_low + a_low * b_high) << 16)) & U32_MASK

class_name SimRngRegistry
extends RefCounted

const RngStream = preload("res://sim/rng_stream.gd")

var master_seed: int
var _streams: Dictionary = {}


func _init(p_seed: int) -> void:
	master_seed = p_seed & int(0xffffffff)


func stream(name: String) -> Variant:
	if _streams.has(name):
		return _streams[name]
	var s: Variant = RngStream.new(RngStream.derive_seed(master_seed, name))
	_streams[name] = s
	return s


var names: Array[String]:
	get:
		var out: Array[String] = []
		for k in _streams.keys():
			out.append(String(k))
		out.sort()
		return out


func save() -> Dictionary:
	var out: Dictionary = {}
	for k in names:
		out[k] = (_streams[k] as RefCounted).call("save")
	return out


func restore(saved: Dictionary) -> void:
	for k in saved.keys():
		var name: String = String(k)
		var state: int = int(saved[name])
		var s: Variant = stream(name)
		(s as RefCounted).call("restore", state)
	for k in _streams.keys():
		var name2: String = String(k)
		if not saved.has(name2):
			var s2: Variant = _streams[name2]
			(s2 as RefCounted).call("restore", RngStream.derive_seed(master_seed, name2))

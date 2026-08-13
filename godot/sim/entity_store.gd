class_name SimEntityStore
extends RefCounted

const INDEX_BITS: int = 20
const INDEX_MASK: int = (1 << INDEX_BITS) - 1
const GENERATION_MASK: int = 0xfff
const MAX_ENTITIES: int = INDEX_MASK


static func entity_index(id: int) -> int:
	return id & INDEX_MASK


static func entity_generation(id: int) -> int:
	return (id >> INDEX_BITS) & GENERATION_MASK


static func _pack(index: int, generation: int) -> int:
	return ((generation & GENERATION_MASK) << INDEX_BITS) | (index & INDEX_MASK)

var _generations: Array[int] = []
var _alive: Array[bool] = []
var _free: Array[int] = []
var _next: int = 0


var count: int:
	get:
		return _next - _free.size()


func spawn() -> int:
	return create()


func create() -> int:
	if not _free.is_empty():
		var recycled: int = _free.pop_back()
		_alive[recycled] = true
		return _pack(recycled, _generations[recycled])
	if _next >= MAX_ENTITIES:
		push_error("SimEntityStore: exhausted %d entity slots" % MAX_ENTITIES)
		return -1
	var index: int = _next
	_next += 1
	# Ensure arrays sized
	if _generations.size() <= index:
		_generations.resize(index + 1)
		_alive.resize(index + 1)
	_generations[index] = 0
	_alive[index] = true
	return _pack(index, 0)


func is_alive(entity: int) -> bool:
	var index: int = entity_index(entity)
	if index >= _next:
		return false
	if _alive[index] != true:
		return false
	return _generations[index] == entity_generation(entity)


func isAlive(entity: int) -> bool:
	return is_alive(entity)


func alive_ids() -> Array[int]:
	return all()


func all() -> Array[int]:
	var out: Array[int] = []
	for index in _next:
		if _alive[index] != true:
			continue
		out.append(_pack(index, _generations[index]))
	return out


func destroy(entity: int) -> bool:
	if not is_alive(entity):
		return false
	var index: int = entity_index(entity)
	_generations[index] = (_generations[index] + 1) & GENERATION_MASK
	_alive[index] = false
	_free.append(index)
	return true


func despawn(entity: int) -> bool:
	return destroy(entity)


func save() -> Dictionary:
	return {
		"generations": _generations.duplicate(),
		"alive": _alive.duplicate(),
		"free": _free.duplicate(),
		"next": _next,
	}


func restore(saved: Dictionary) -> void:
	var raw_gens: Array = saved["generations"] as Array
	var gens: Array[int] = []
	for v in raw_gens:
		gens.append(int(v))
	_generations = gens
	var alv: Array[bool] = []
	for v in (saved["alive"] as Array):
		alv.append(bool(v))
	_alive = alv
	var fr: Array[int] = []
	for v in (saved["free"] as Array):
		fr.append(int(v))
	_free = fr
	_next = int(saved["next"])

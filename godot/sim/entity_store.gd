class_name SimEntityStore
extends RefCounted

var _next_id: int = 0
var _alive: Dictionary = {}


func spawn() -> int:
	var entity := _next_id
	_next_id += 1
	_alive[entity] = true
	return entity


func is_alive(entity: int) -> bool:
	return _alive.has(entity)


func alive_ids() -> Array[int]:
	var ids: Array[int] = []
	for value: Variant in _alive.keys():
		ids.append(int(value))
	ids.sort()
	return ids

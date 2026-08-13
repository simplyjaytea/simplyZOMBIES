class_name SimComponentStore
extends RefCounted

var _tables: Dictionary = {}


func set_component(entity: int, component: String, value: Variant) -> void:
	if not _tables.has(component):
		_tables[component] = {}
	var table: Dictionary = _tables[component] as Dictionary
	table[entity] = value


func set_val(entity: int, component: String, value: Variant) -> void:
	set_component(entity, component, value)


func get_component(entity: int, component: String) -> Variant:
	var table_value: Variant = _tables.get(component)
	if table_value == null:
		return null
	var table: Dictionary = table_value as Dictionary
	return table.get(entity)


func get_val(entity: int, component: String) -> Variant:
	return get_component(entity, component)


func get_or_throw(entity: int, component: String) -> Variant:
	var v: Variant = get_component(entity, component)
	if v == null:
		push_error("Entity %d has no component \"%s\"" % [entity, component])
		return null
	return v


func has_component(entity: int, component: String) -> bool:
	var tv: Variant = _tables.get(component)
	if tv == null:
		return false
	return (tv as Dictionary).has(entity)


func has(entity: int, component: String) -> bool:
	return has_component(entity, component)


func remove(entity: int, component: String) -> bool:
	var tv: Variant = _tables.get(component)
	if tv == null:
		return false
	return (tv as Dictionary).erase(entity)


func remove_component(entity: int, component: String) -> bool:
	return remove(entity, component)


func removeAll(entity: int) -> void:
	for key in _tables.keys():
		var t: Dictionary = _tables[key] as Dictionary
		t.erase(entity)


func remove_all(entity: int) -> void:
	removeAll(entity)


func count(component: String) -> int:
	var tv: Variant = _tables.get(component)
	if tv == null:
		return 0
	return (tv as Dictionary).size()


func for_each_with(component: String, visitor: Callable) -> void:
	var tv: Variant = _tables.get(component)
	if tv == null:
		return
	var table: Dictionary = tv as Dictionary
	for entity in table.keys():
		visitor.call(int(entity), table[entity])


func query(required: Array) -> Array[int]:
	var ids: Array[int] = []
	if required.is_empty():
		return ids
	# Find smallest store
	var smallest_key: String = String(required[0])
	var smallest: Variant = _tables.get(smallest_key)
	if smallest == null:
		return ids
	for i in range(1, required.size()):
		var k: String = String(required[i])
		var s: Variant = _tables.get(k)
		if s == null:
			return ids
		if (s as Dictionary).size() < (smallest as Dictionary).size():
			smallest = s
			smallest_key = k
	var smallest_dict: Dictionary = smallest as Dictionary
	for entity_value in smallest_dict.keys():
		var entity: int = int(entity_value)
		var present: bool = true
		for k in required:
			var sk: String = String(k)
			if sk == smallest_key:
				continue
			var tv2: Variant = _tables.get(sk)
			if tv2 == null or not (tv2 as Dictionary).has(entity):
				present = false
				break
		if present:
			ids.append(entity)
	ids.sort()
	return ids


func save() -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = _tables.keys()
	keys.sort()
	for type_id in keys:
		var k: String = String(type_id)
		var table: Dictionary = _tables[k] as Dictionary
		var entries: Array = []
		for e in table.keys():
			entries.append([int(e), table[e]])
		entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		out[k] = entries
	return out


func restore(saved: Dictionary) -> void:
	_tables.clear()
	for type_id in saved.keys():
		var k: String = String(type_id)
		var entries: Array = saved[k] as Array
		var m: Dictionary = {}
		for entry in entries:
			var arr: Array = entry as Array
			m[int(arr[0])] = arr[1]
		_tables[k] = m

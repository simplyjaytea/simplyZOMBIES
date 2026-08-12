class_name SimComponentStore
extends RefCounted

var _tables: Dictionary = {}


func set_component(entity: int, component: String, value: Variant) -> void:
	if not _tables.has(component):
		_tables[component] = {}
	var table: Dictionary = _tables[component]
	table[entity] = value


func get_component(entity: int, component: String) -> Variant:
	var table_value: Variant = _tables.get(component)
	if table_value == null:
		return null
	var table: Dictionary = table_value
	return table.get(entity)


func query(required: Array) -> Array[int]:
	var ids: Array[int] = []
	if required.is_empty():
		return ids
	var first_value: Variant = _tables.get(String(required[0]))
	if first_value == null:
		return ids
	var first: Dictionary = first_value
	for entity_value: Variant in first.keys():
		var entity := int(entity_value)
		var present := true
		for index in range(1, required.size()):
			var table_value: Variant = _tables.get(String(required[index]))
			if table_value == null or not (table_value as Dictionary).has(entity):
				present = false
				break
		if present:
			ids.append(entity)
	ids.sort()
	return ids

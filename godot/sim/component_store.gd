class_name SimComponentStore
extends RefCounted

var _tables: Dictionary = {}

# `query` answers from a memo while no table it names has gained or lost a member (A3's fifth
# slice: a hundred queries a tick, 2.3 ms, nearly all asking what they asked last tick). `_members`
# counts each table's membership changes -- an entity added or removed, never a value replaced --
# and a memo row stands only while every count it was built against still holds. A `restore`
# drops every row. `check_m2_tick.gd` QUERY holds the memo to a fresh intersection through every
# way the store changes, and `query_fresh` is that intersection.
var _members: Dictionary = {}
var _memo: Dictionary = {}
var memo_hits: int = 0


func _member_changed(component: String) -> void:
	_members[component] = int(_members.get(component, 0)) + 1


func set_component(entity: int, component: String, value: Variant) -> void:
	if not _tables.has(component):
		_tables[component] = {}
	var table: Dictionary = _tables[component] as Dictionary
	if not table.has(entity):
		_member_changed(component)
	table[entity] = value


func set_val(entity: int, component: String, value: Variant) -> void:
	set_component(entity, component, value)


func get_component(entity: int, component: String) -> Variant:
	var table_value: Variant = _tables.get(component)
	if table_value == null:
		return null
	var table: Dictionary = table_value as Dictionary
	return table.get(entity)


## The live table behind `get_component` and `has_component` for one component, for a loop that
## reads it per body: `table(c).get(e)` is `get_component(e, c)` and `table(c).has(e)` is
## `has_component(e, c)`, without the two calls through an untyped world each read costs (about four
## thousand a tick, A3's tenth slice). Read-only by convention -- every write still goes through
## `set_component` and `remove`, which keep the query memo honest. A component with no table yet
## answers an empty Dictionary that is not stored, so a caller holding one across a pass that
## *creates* that table would miss the new rows: hold it only where the pass does not add the
## component's first member. `restore` replaces every table, so never hold one across a load.
## `check_m2_tick.gd` TABLE holds both readings equal.
func table(component: String) -> Dictionary:
	var tv: Variant = _tables.get(component)
	if tv == null:
		return {}
	return tv as Dictionary


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
	if not (tv as Dictionary).erase(entity):
		return false
	_member_changed(component)
	return true


func remove_component(entity: int, component: String) -> bool:
	return remove(entity, component)


func removeAll(entity: int) -> void:
	for key in _tables.keys():
		var t: Dictionary = _tables[key] as Dictionary
		if t.erase(entity):
			_member_changed(String(key))


func remove_all(entity: int) -> void:
	removeAll(entity)


## How many times `component`'s table has gained or lost a member, the count the query memo keys
## on. It never goes down, so a reader that saw the same number twice saw no entity gain or lose
## the component in between (a value replaced in place does not move it). `SimNeeds.stockpile_items`
## keys its memo on it.
func changes(component: String) -> int:
	return int(_members.get(component, 0))


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


# Sorted ids carrying every component in `required`. A copy every time: a caller that sorts or
# appends to what it was handed must not reach the memo.
func query(required: Array) -> Array[int]:
	var key: String = ",".join(PackedStringArray(required))
	var row: Variant = _memo.get(key)
	if row != null:
		var counts: Array = (row as Array)[1] as Array
		var stands: bool = true
		for i in required.size():
			if int(_members.get(String(required[i]), 0)) != int(counts[i]):
				stands = false
				break
		if stands:
			memo_hits += 1
			return ((row as Array)[0] as Array[int]).duplicate()
	var now: Array = []
	for k in required:
		now.append(int(_members.get(String(k), 0)))
	var ids: Array[int] = query_fresh(required)
	_memo[key] = [ids.duplicate(), now]
	return ids


func query_fresh(required: Array) -> Array[int]:
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
	_memo.clear()
	for type_id in saved.keys():
		var k: String = String(type_id)
		var entries: Array = saved[k] as Array
		var m: Dictionary = {}
		for entry in entries:
			var arr: Array = entry as Array
			m[int(arr[0])] = arr[1]
		_tables[k] = m

class_name SimModifiers
extends RefCounted

const GLOBAL: String = "global"

var _stats: Variant
var _entries: Dictionary = {}
var _cache: Dictionary = {}
var _seq: int = 0

func _init(stats: Variant) -> void:
	_stats = stats

func _scope_key(scope: Variant) -> String:
	if scope == null:
		return GLOBAL
	var s: String = str(scope)
	if s == GLOBAL:
		return GLOBAL
	return s

func _cache_key(scope: Variant, stat: String) -> String:
	return _scope_key(scope) + "|" + stat

func _invalidate(scope: Variant, stat: String) -> void:
	if _scope_key(scope) == GLOBAL:
		var to_del: Array = []
		for k in _cache.keys():
			if str(k).ends_with("|" + stat):
				to_del.append(k)
		for k in to_del:
			_cache.erase(k)
		return
	_cache.erase(_cache_key(scope, stat))

func _list_for(scope: Variant) -> Array:
	var k: String = _scope_key(scope)
	if not _entries.has(k):
		_entries[k] = []
	return _entries[k] as Array

static func _by_source_then_seq(a: Dictionary, b: Dictionary) -> bool:
	var sa: String = str((a["modifier"] as Dictionary)["source"])
	var sb: String = str((b["modifier"] as Dictionary)["source"])
	if sa != sb:
		return sa < sb
	return int(a["seq"]) < int(b["seq"])

func add(mod: Dictionary, scope: Variant = null) -> void:
	var sk: String = _scope_key(scope if scope != null else GLOBAL)
	var stat: String = str(mod["stat"])
	assert(_stats.has(stat), "Unknown stat: " + stat)
	assert(str(mod["source"]) != "", "Empty source for " + stat)
	assert(is_finite(float(mod["value"])), "Non-finite value for " + stat)
	_list_for(scope if scope != null else GLOBAL).append({"modifier": mod, "seq": _seq})
	_seq += 1
	_invalidate(scope if scope != null else GLOBAL, stat)

func add_all(mods: Array, scope: Variant = null) -> void:
	for m in mods:
		add(m as Dictionary, scope)

func remove_by_source(source: String, scope: Variant = null) -> int:
	var removed: int = 0
	var scopes: Array = []
	if scope != null:
		scopes = [_scope_key(scope)]
	else:
		scopes = _entries.keys()
	for key in scopes:
		var sk: String = str(key)
		var list: Variant = _entries.get(sk)
		if list == null:
			continue
		var arr: Array = list as Array
		var kept: Array = []
		var touched: Dictionary = {}
		for e in arr:
			var ed: Dictionary = e as Dictionary
			if str((ed["modifier"] as Dictionary)["source"]) != source:
				kept.append(e)
			else:
				touched[str((ed["modifier"] as Dictionary)["stat"])] = true
				removed += 1
		_entries[sk] = kept
		for stat in touched.keys():
			var st: String = str(stat)
			if sk == GLOBAL:
				_invalidate(GLOBAL, st)
			else:
				# sk is numeric string for entity id
				var ent: int = int(sk) if sk != GLOBAL else 0
				_invalidate(ent, st)
	return removed

func remove_scope(scope: Variant) -> void:
	var sk: String = _scope_key(scope)
	var list: Variant = _entries.get(sk)
	if list == null:
		return
	for e in list as Array:
		var ed: Dictionary = e as Dictionary
		_invalidate(scope, str((ed["modifier"] as Dictionary)["stat"]))
	_entries.erase(sk)

func _applicable(scope: Variant, stat: String) -> Array:
	var out: Array = []
	for e in (_entries.get(GLOBAL, []) as Array):
		if str(((e as Dictionary)["modifier"] as Dictionary)["stat"]) == stat:
			out.append(e)
	if scope != null and _scope_key(scope) != GLOBAL:
		for e in (_entries.get(_scope_key(scope), []) as Array):
			if str(((e as Dictionary)["modifier"] as Dictionary)["stat"]) == stat:
				out.append(e)
	out.sort_custom(_by_source_then_seq)
	return out

func resolve(stat: String, scope: Variant = null) -> float:
	var key: String = _cache_key(scope if scope != null else GLOBAL, stat)
	if _cache.has(key):
		return float(_cache[key])
	var v: float = _compute(stat, scope)["final"] as float
	_cache[key] = v
	return v

func explain(stat: String, scope: Variant = null) -> Dictionary:
	return _compute(stat, scope)

func _compute(stat: String, scope: Variant) -> Dictionary:
	var def: Dictionary = _stats.get_or_throw(stat)
	var entries: Array = _applicable(scope if scope != null else GLOBAL, stat)
	var contribs: Array = []
	var value: float = float(def["base"])
	var sets: Array = []
	for e in entries:
		if str(((e as Dictionary)["modifier"] as Dictionary)["op"]) == "set":
			sets.append(e)
	var winner: Variant = null
	if not sets.is_empty():
		winner = sets[sets.size() - 1]
		for e in sets:
			if e == winner:
				continue
			var ed: Dictionary = e as Dictionary
			contribs.append({"op": "set", "value": float((ed["modifier"] as Dictionary)["value"]), "source": str((ed["modifier"] as Dictionary)["source"]), "running": value, "shadowedBy": str(((winner as Dictionary)["modifier"] as Dictionary)["source"])})
		var wd: Dictionary = winner as Dictionary
		value = float((wd["modifier"] as Dictionary)["value"])
		contribs.append({"op": "set", "value": value, "source": str((wd["modifier"] as Dictionary)["source"]), "running": value})
	for e in entries:
		if str(((e as Dictionary)["modifier"] as Dictionary)["op"]) != "add":
			continue
		var ed: Dictionary = e as Dictionary
		value += float((ed["modifier"] as Dictionary)["value"])
		contribs.append({"op": "add", "value": float((ed["modifier"] as Dictionary)["value"]), "source": str((ed["modifier"] as Dictionary)["source"]), "running": value})
	for e in entries:
		if str(((e as Dictionary)["modifier"] as Dictionary)["op"]) != "mul":
			continue
		var ed: Dictionary = e as Dictionary
		value *= float((ed["modifier"] as Dictionary)["value"])
		contribs.append({"op": "mul", "value": float((ed["modifier"] as Dictionary)["value"]), "source": str((ed["modifier"] as Dictionary)["source"]), "running": value})
	for e in entries:
		if str(((e as Dictionary)["modifier"] as Dictionary)["op"]) != "min":
			continue
		var ed: Dictionary = e as Dictionary
		var mv: float = float((ed["modifier"] as Dictionary)["value"])
		if value < mv:
			value = mv
		contribs.append({"op": "min", "value": mv, "source": str((ed["modifier"] as Dictionary)["source"]), "running": value})
	for e in entries:
		if str(((e as Dictionary)["modifier"] as Dictionary)["op"]) != "max":
			continue
		var ed: Dictionary = e as Dictionary
		var mv: float = float((ed["modifier"] as Dictionary)["value"])
		if value > mv:
			value = mv
		contribs.append({"op": "max", "value": mv, "source": str((ed["modifier"] as Dictionary)["source"]), "running": value})
	if def.has("min") and value < float(def["min"]):
		value = float(def["min"])
	if def.has("max") and value > float(def["max"]):
		value = float(def["max"])
	if is_zero_approx(value) and signf(value) < 0:
		value = 0.0
	return {"stat": stat, "scope": _scope_key(scope if scope != null else GLOBAL), "base": float(def["base"]), "contributions": contribs, "final": value}

func sources() -> Array[String]:
	var out: Dictionary = {}
	for list in _entries.values():
		for e in list as Array:
			out[str(((e as Dictionary)["modifier"] as Dictionary)["source"])] = true
	var arr: Array[String] = []
	for k in out.keys():
		arr.append(str(k))
	arr.sort()
	return arr

func size() -> int:
	var n: int = 0
	for list in _entries.values():
		n += (list as Array).size()
	return n

func save() -> Dictionary:
	var global: Array = []
	for e in (_entries.get(GLOBAL, []) as Array):
		global.append((e as Dictionary)["modifier"])
	global.sort_custom(func(a, b): return str(a["source"]) < str(b["source"]) if str(a["source"]) != str(b["source"]) else false)
	var entities: Array = []
	var keys: Array = _entries.keys()
	keys.sort()
	for k in keys:
		var sk: String = str(k)
		if sk == GLOBAL:
			continue
		var list: Array = []
		for e in (_entries[sk] as Array):
			list.append((e as Dictionary)["modifier"])
		if not list.is_empty():
			entities.append([int(sk), list])
	return {"global": global, "entities": entities}

func restore(saved: Dictionary) -> void:
	_entries.clear()
	_cache.clear()
	_seq = 0
	for m in saved.get("global", []) as Array:
		add(m as Dictionary, GLOBAL)
	for pair in saved.get("entities", []) as Array:
		var p: Array = pair as Array
		for m in p[1] as Array:
			add(m as Dictionary, int(p[0]))

static func is_finite(v: float) -> bool:
	return not is_nan(v) and not is_inf(v)

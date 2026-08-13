class_name SimEventBus
extends RefCounted

const MAX_CASCADE_PASSES: int = 16

var _subs: Dictionary = {}
var _queue: Array[Dictionary] = []
var _record: Array[Dictionary] = []


func subscribe(sub: Dictionary) -> void:
	var type: String = String(sub["type"])
	var id: String = String(sub["id"])
	var list: Array = _subs.get(type, []) as Array
	for s in list:
		assert(String((s as Dictionary)["id"]) != id, "EventBus: duplicate subscription id \"%s\" for \"%s\"" % [id, type])
	list.append(sub)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa: int = int(a.get("order", 0))
		var ob: int = int(b.get("order", 0))
		if oa != ob:
			return oa < ob
		return String(a["id"]) < String(b["id"])
	)
	_subs[type] = list


func unsubscribe(id: String) -> bool:
	for type in _subs.keys():
		var list: Array = _subs[type] as Array
		for i in list.size():
			if String((list[i] as Dictionary)["id"]) == id:
				list.remove_at(i)
				return true
	return false


func publish(event: Dictionary) -> void:
	_queue.append(event)


func drain() -> void:
	var passes: int = 0
	while not _queue.is_empty():
		passes += 1
		if passes > MAX_CASCADE_PASSES:
			var types: Array[String] = []
			var seen: Dictionary = {}
			for e in _queue:
				var t: String = String(e["type"])
				if not seen.has(t):
					seen[t] = true
					types.append(t)
			push_error("EventBus: cascade exceeded %d passes; likely cycle involving: %s" % [MAX_CASCADE_PASSES, ", ".join(types)])
			_queue.clear()
			return
		var batch: Array[Dictionary] = _queue.duplicate()
		_queue.clear()
		for event in batch:
			_record.append(event)
			var type: String = String(event["type"])
			var list: Variant = _subs.get(type)
			if list == null:
				continue
			for sub in (list as Array):
				var handler: Callable = (sub as Dictionary)["handler"] as Callable
				handler.call(event)


var drained: Array[Dictionary]:
	get:
		return _record


var pending: int:
	get:
		return _queue.size()


func clear_record() -> void:
	_record.clear()

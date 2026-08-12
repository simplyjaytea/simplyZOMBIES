class_name SimCommandQueue
extends RefCounted

var _pending: Array[Dictionary] = []
var current: Array[Dictionary] = []
var recorded: Array[Dictionary] = []


func push(command: Dictionary) -> void:
	_pending.append(command.duplicate(true))


func take(tick: int) -> Array[Dictionary]:
	current = _pending
	_pending = []
	for command in current:
		recorded.append({"tick": tick, "command": command.duplicate(true)})
	return current

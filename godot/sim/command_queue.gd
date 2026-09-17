class_name SimCommandQueue
extends RefCounted

# `recorded` is opt-in. A played session steps for the life of the run and never reads it back
# (nothing subscribes to it outside a parity or replay path), so an unconditional append here was
# an unbounded leak: every movement command of every tick, kept forever. Off by default; a caller
# that actually replays or diffs a run (R1 parity's `run_fixture`, the R6 soak's input-loss lane)
# sets `record = true` on its own queue before stepping.
var record: bool = false
var _pending: Array[Dictionary] = []
var current: Array[Dictionary] = []
var recorded: Array[Dictionary] = []


func push(command: Dictionary) -> void:
	_pending.append(command.duplicate(true))


func take(tick: int) -> Array[Dictionary]:
	current = _pending
	_pending = []
	if record:
		for command in current:
			recorded.append({"tick": tick, "command": command.duplicate(true)})
	return current

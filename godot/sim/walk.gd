class_name SimWalk
extends RefCounted

# One grid-A* stepper for everybody in the district who walks somewhere on purpose and is not
# running a colony job.
#
# It was `SimRaiders._walk`, private, and the stranger slice needed exactly it: plan a path,
# re-plan when the map moves under it, open the door in the way, and spend a velocity towards the
# next tile. Copying it would have been the cheaper edit and the wrong one -- two walkers that
# start identical drift the first time either learns something (a surface cost, a crowd, a door
# that is locked rather than merely shut), and then a raider and a stranger disagree about what a
# wall is. So the body moved here and both callers reach it.
#
# **The record is the caller's.** `rec` is whatever Dictionary the caller already saves --
# `raider` for a band, `stranger` for somebody in a house -- and this writes `path` and `pathGen`
# into it and nothing else. `path` is an Array of `{x, y}` records, never a PackedVector2Array and
# never a Dictionary keyed by anything: components round-trip through JSON, and CLAUDE.md's trap
# list has both halves of why (a packed array mutated through a Dictionary appends to a copy; a
# dict keyed by an id comes back with String keys).
#
# `speed` is a parameter rather than something read off the record, because the two callers answer
# it differently and both answers move per tick: a raider's comes off its archetype through
# `move_speed` modifiers, a stranger's is one constant. Writing it into the record instead would
# put a derived number in the save.
#
# `jobs.gd`'s `_walk` is deliberately *not* folded in here. It carries job bookkeeping -- the
# reservation, the arrival test the job's own state machine reads, the stance and the encumbrance
# -- and pulling that apart is a refactor of the scheduler rather than a shared helper.

const SimPathRes = preload("res://sim/path.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")


## One tick of walking towards `goal`, at `speed` metres per second.
##
## Re-plans when `path` is empty or when `world.mapGeneration` has moved since the plan was made.
## Leaves the caller's `rec["path"]` empty once the goal is reached or when there is no route, so
## a caller can ask "am I there?" by looking at the path it owns rather than by being told.
static func step(world: Variant, ent: int, rec: Dictionary, goal: Vector2i, speed: float) -> void:
	var pos: Variant = world.components.get_component(ent, "position")
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (pos is Dictionary) or not (vel is Dictionary):
		return
	var p: Dictionary = pos as Dictionary
	var v: Dictionary = vel as Dictionary
	var here := Vector2i(floori(float(p["x"])), floori(float(p["y"])))
	var gen: int = int(world.mapGeneration)
	var path: Array = rec.get("path", []) as Array
	if int(rec.get("pathGen", -1)) != gen or path.is_empty():
		var found: Array[Vector2i] = SimPathRes.find(world, here, goal)
		path.clear()
		for s in found:
			path.append({"x": s.x, "y": s.y})
		rec["path"] = path
		rec["pathGen"] = gen
	if path.is_empty():
		# Arrived, or nowhere to go from here. What that means is the caller's business: a band
		# stands its ground, a stranger stands in front of the colonist who found them.
		halt(v)
		return
	var next: Variant = path[0]
	if not (next is Dictionary):
		path.remove_at(0)
		halt(v)
		return
	var tx: float = float(int((next as Dictionary).get("x", 0))) + 0.5
	var ty: float = float(int((next as Dictionary).get("y", 0))) + 0.5
	# Whoever is walking opens the door they are walking through, the way a colonist does
	# (SimJobs._walk). `load`, not a preload: fortify.gd reaches this file's callers through
	# vehicles, and a preload here would close the ring.
	var step_tx: int = int((next as Dictionary).get("x", 0))
	var step_ty: int = int((next as Dictionary).get("y", 0))
	if world.tilemap != null and SimTileMapRes.tile_at(world.tilemap, step_tx, step_ty) == SimTileMapRes.Tile.Door and world.is_blocked_tile(step_tx, step_ty):
		var Fortify: GDScript = load("res://sim/modules/fortify.gd") as GDScript
		Fortify.call("open_door", world, step_tx, step_ty)
	var dx: float = tx - float(p["x"])
	var dy: float = ty - float(p["y"])
	if dx * dx + dy * dy < 0.04:
		path.remove_at(0)
		rec["path"] = path
		if path.is_empty():
			halt(v)
		return
	var length: float = sqrt(dx * dx + dy * dy)
	# `dx`/`dy`, never `x`/`y`: a velocity written with position's key names adds a pair of keys
	# nothing reads and raises nothing (CLAUDE.md's `vel["x"]` trap).
	v["dx"] = dx / length * speed
	v["dy"] = dy / length * speed


## Stand still. One spelling of it, so a halt and a step cannot disagree about the key names.
static func halt(vel: Dictionary) -> void:
	vel["dx"] = 0.0
	vel["dy"] = 0.0

class_name FirstPersonHitMarks
extends Node3D
# Hit feedback for the first-person fight (docs/30, 2026-11-09). Three reads of the tick's drained events, the same
# read anim_clock.gd and fx_look.gd make (`world.events.drained`, never a subscription to the bus):
#   weapon.fired with no body hit and a contact inside reach  -> an impact mark on the surface the round met,
#   attack.connected on a zombie                              -> a blood puff at the body part's height,
#   entity.staggered on a zombie                              -> a flinch of its view back along the shot.
# Presentation only. Nothing here writes the sim, draws on the RNG, or is saved; every shape is a fixed function of
# the events, so the same events give the same transforms.
#
# Time is counted in sim ticks, one `tick_once` per step, so a mark lasts MARK_TICKS ticks whatever the frame rate.

const MARK_TICKS: int = 400
const MARK_CAP: int = 64
const PUFF_TICKS: int = 8
const PUFF_QUADS: int = 8
const PUFF_RING_M: float = 0.12
const PUFF_SIZE_M: float = 0.07
const MARK_SIZE_M: float = 0.10
const MARK_NORMAL_OFFSET_M: float = 0.02
const CONTACT_EPSILON_M: float = 0.01
const FLINCH_M: float = 0.15
const HEAD_HEIGHT_M: float = 1.6
const TORSO_HEIGHT_M: float = 1.2
const LEGS_HEIGHT_M: float = 0.5
const MARK_COLOUR: Color = Color(0.08, 0.07, 0.06, 0.85)
const PUFF_COLOUR: Color = Color(0.52, 0.06, 0.05, 0.9)

# entity -> Vector3 offset, read by body_view.gd. Shared by reference with the body view; an entry is erased when its
# flinch ends, so a body with no entry is drawn where the sim put it.
var kick: Dictionary = {}

var _tick: int = 0
var _marks: Array = []   # [{"node": MeshInstance3D, "born": int}], oldest first
var _puffs: Array = []   # [{"nodes": Array[MeshInstance3D], "born": int}], oldest first
var _flinch: Dictionary = {}     # entity -> {"dir": Vector2, "left": int, "total": int}
var _shot_dir: Dictionary = {}   # entity -> Vector2, set by attack.connected in the same drain, read by its stagger
var _quad: QuadMesh = null
var _mark_material: StandardMaterial3D = null
var _puff_material: StandardMaterial3D = null


func _ready() -> void:
	_mark_material = _unshaded(MARK_COLOUR)
	_puff_material = _unshaded(PUFF_COLOUR)


# Once per sim tick, before the tick's events are read: ages the marks and puffs and steps every flinch one tick.
func tick_once() -> void:
	_tick += 1
	_age_puffs()
	_age_marks()
	for entity in _flinch.keys():
		var f: Dictionary = _flinch[entity] as Dictionary
		f["left"] = int(f["left"]) - 1
		if int(f["left"]) <= 0:
			_flinch.erase(entity)
			kick.erase(entity)
		else:
			kick[entity] = _kick_for(f)


# Reads one tick's drained events. Call after the tick's step and before the bodies are drawn.
func from_events(world: Variant, drained: Array) -> void:
	if world == null:
		return
	for e in drained:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e as Dictionary
		match String(ev.get("type", "")):
			"weapon.fired":
				_impact(ev)
			"attack.connected":
				_blood(world, ev)
			"entity.staggered":
				_flinch_on(world, ev)
	_shot_dir.clear()


func mark_count() -> int:
	return _marks.size()


func puff_count() -> int:
	return _puffs.size()


# World positions of every live puff quad, for the gate and for a reader that wants to place something on them.
func puff_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _puffs:
		for node in (p as Dictionary)["nodes"] as Array:
			out.append((node as Node3D).global_position)
	return out


# The impact marks' nodes, oldest first.
func mark_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for m in _marks:
		out.append((m as Dictionary)["node"] as Node3D)
	return out


func _impact(ev: Dictionary) -> void:
	if int(ev.get("hit", -1)) >= 0:
		return
	# Without the contact keys (the ray path, docs/40) there is no surface to mark.
	if not (ev.has("ex") and ev.has("ey") and ev.has("ez") and ev.has("oz")):
		return
	var shooter: Vector3 = Vector3(float(ev.get("x", 0.0)), float(int(ev["oz"])) / 1000.0, float(ev.get("y", 0.0)))
	var contact: Vector3 = Vector3(float(ev["ex"]), float(int(ev["ez"])) / 1000.0, float(ev["ey"]))
	# A ray that met nothing ends at reach, so its length from the shooter is the reach (to a millimetre).
	if shooter.distance_to(contact) >= float(ev.get("reach", 0.0)) - CONTACT_EPSILON_M:
		return
	var normal: Vector3 = (shooter - contact).normalized()
	var node: MeshInstance3D = _quad_node(contact + normal * MARK_NORMAL_OFFSET_M, shooter, MARK_SIZE_M, _mark_material)
	_marks.append({"node": node, "born": _tick})
	while _marks.size() > MARK_CAP:
		var oldest: Dictionary = _marks.pop_front() as Dictionary
		_free(oldest["node"] as Node3D)


func _blood(world: Variant, ev: Dictionary) -> void:
	var target: int = int(ev.get("target", -1))
	var attacker: int = int(ev.get("attacker", -1))
	var there: Variant = world.components.get_component(target, "position")
	if not (there is Dictionary):
		return
	var tx: float = float((there as Dictionary)["x"])
	var ty: float = float((there as Dictionary)["y"])
	var from: Variant = world.components.get_component(attacker, "position")
	if from is Dictionary:
		var d: Vector2 = Vector2(tx - float((from as Dictionary)["x"]), ty - float((from as Dictionary)["y"]))
		if d.length() > 0.0001:
			_shot_dir[target] = d.normalized()
	if not world.components.has_component(target, "zombieType"):
		return
	var part: String = String(ev.get("bodyPart", "torso"))
	var height: float = TORSO_HEIGHT_M
	if part == "head":
		height = HEAD_HEIGHT_M
	elif part == "legs":
		height = LEGS_HEIGHT_M
	var centre: Vector3 = Vector3(tx, height, ty)
	var nodes: Array = []
	for i in range(PUFF_QUADS):
		var angle: float = TAU * float(i) / float(PUFF_QUADS)
		var at: Vector3 = centre + Vector3(cos(angle) * PUFF_RING_M, 0.0, sin(angle) * PUFF_RING_M)
		nodes.append(_quad_node(at, at + Vector3(0.0, 0.0, 1.0), PUFF_SIZE_M, _puff_material))
	_puffs.append({"nodes": nodes, "born": _tick})


func _flinch_on(world: Variant, ev: Dictionary) -> void:
	var who: int = int(ev.get("entity", -1))
	if not world.components.has_component(who, "zombieType"):
		return
	var dir: Variant = _shot_dir.get(who)
	if dir == null:
		return
	var ticks: int = maxi(1, int(ev.get("ticks", 8)))
	var f: Dictionary = {"dir": dir as Vector2, "left": ticks, "total": ticks}
	_flinch[who] = f
	kick[who] = _kick_for(f)


func _kick_for(f: Dictionary) -> Vector3:
	var dir: Vector2 = f["dir"] as Vector2
	var share: float = float(int(f["left"])) / float(int(f["total"]))
	return Vector3(dir.x, 0.0, dir.y) * (FLINCH_M * share)


func _quad_node(at: Vector3, look_toward: Vector3, size: float, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	node.mesh = quad
	add_child(node)
	node.position = at
	# The quad's front is +Z. Point +Z at `look_toward`: look_at aims -Z away from the mirror point.
	node.look_at(at * 2.0 - look_toward, Vector3.UP)
	return node


func _age_marks() -> void:
	while not _marks.is_empty() and _tick - int((_marks[0] as Dictionary)["born"]) >= MARK_TICKS:
		_free((_marks.pop_front() as Dictionary)["node"] as Node3D)


func _age_puffs() -> void:
	while not _puffs.is_empty() and _tick - int((_puffs[0] as Dictionary)["born"]) >= PUFF_TICKS:
		for node in (_puffs.pop_front() as Dictionary)["nodes"] as Array:
			_free(node as Node3D)


func _free(node: Node3D) -> void:
	if node == null:
		return
	remove_child(node)
	node.queue_free()


func _unshaded(colour: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

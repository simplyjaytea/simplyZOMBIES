extends Node3D
# The loose items: what the sim has lying on the ground, drawn with their models. One node per sim entity
# that has `position` and `itemBase` and no `stored` (a stored item sits in a container and is the
# inventory panel's business). Presentation only -- this file reads the components and writes none.
#
# The model is the one `models.gd` resolves for the item's id, else its class. An item with no model gets
# no node: it keeps whatever placeholder the scene already draws, which is nothing for loose items today.
# The model stands on the floor: its lowest point is lifted to y = 0. Its turn is a fixed yaw seeded by
# the entity, so the same item lies the same way every run, and nothing here draws from the sim's RNG.

const Appearance = preload("res://presentation/appearance.gd")
const Models = preload("res://presentation/first_person/models.gd")

var _nodes: Dictionary = {}
# Entities whose item has no model. Resolved once, so a refresh does not look the item up again.
var _modelless: Dictionary = {}
# The sim tick the nodes were last brought in line with. Loose items only move on a tick, so a frame between
# ticks has nothing to do; a load, which restores an older tick, calls `invalidate`.
var _synced_tick: int = -1


## Brings the nodes in line with the sim's loose items: one added for each new item with a model, moved to
## each item's position, and freed for each item that is gone or has been stored.
func refresh(world: Variant) -> void:
	if world == null or int(world.tick) == _synced_tick:
		return
	_synced_tick = int(world.tick)
	var present: Dictionary = {}
	for entity in world.components.query(["position", "itemBase"]):
		var ent: int = int(entity)
		if world.components.has_component(ent, "stored"):
			continue
		var pos: Variant = world.components.get_component(ent, "position")
		var base: Variant = world.components.get_component(ent, "itemBase")
		if not (pos is Dictionary) or not (base is Dictionary):
			continue
		present[ent] = true
		if _modelless.has(ent):
			continue
		var node: Node3D = _nodes.get(ent) as Node3D
		if node == null:
			node = _node_for(world, ent, String((base as Dictionary).get("baseId", "")))
			if node == null:
				_modelless[ent] = true
				continue
			_nodes[ent] = node
			add_child(node)
		node.position = Vector3(float((pos as Dictionary)["x"]), 0.0, float((pos as Dictionary)["y"]))
	for ent in _nodes.keys():
		if not present.has(ent):
			var gone: Node3D = _nodes[ent] as Node3D
			_nodes.erase(ent)
			if gone.get_parent() == self:
				remove_child(gone)
			gone.queue_free()
	for ent in _modelless.keys():
		if not present.has(ent):
			_modelless.erase(ent)


## Forces the next `refresh` to read the sim, whatever tick it is on.
func invalidate() -> void:
	_synced_tick = -1


func count() -> int:
	return _nodes.size()


func node_for(entity: int) -> Node3D:
	return _nodes.get(entity) as Node3D


func entities() -> Array[int]:
	var out: Array[int] = []
	for ent in _nodes.keys():
		out.append(int(ent))
	out.sort()
	return out


# A node holding the item's model, turned by the entity's seeded yaw and lifted onto the floor. Null when the
# item has no model.
func _node_for(world: Variant, entity: int, base_id: String) -> Node3D:
	var entry: Dictionary = Appearance.entry_of(world, "item", base_id)
	var model: Node3D = Models.model_for(base_id, String(entry.get("class", "")))
	if model == null:
		return null
	var holder: Node3D = Node3D.new()
	holder.name = "Loose%d" % entity
	holder.rotation.y = _yaw_of(entity)
	model.position.y = -Models.bounds(model).position.y
	holder.add_child(model)
	return holder


# A fixed turn for each entity: a generator seeded by the entity id, so the answer is the same on every run.
static func _yaw_of(entity: int) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = entity * 7919 + 104729
	return rng.randf() * TAU

class_name SimRaiders
extends RefCounted

# A hostile band of *people*, walking in from the edge of the district towards your gate.
#
# The point of the slice is that almost none of this file is new mechanism. A raider is a human
# body with a weapon in its hand and `allegiance.faction = "raiders"` on it, and everything that
# then happens to them is the machinery the colony already had:
#
#   * `melee.gd` / `ranged.gd` resolve against whatever body is in the cone and have never asked
#     who it belongs to, so a raider swinging at a colonist and a colonist swinging at a raider
#     are the same code path that was already there.
#   * `npc_combat.gd` is the intake for both sides. It picks a target through
#     `SimAllegiance.enemies_of` now instead of a hardcoded shambler query, which is the only
#     change hostility actually required.
#   * `wounds.gd`, `health.gd` and `treatment.gd` apply because a raider carries the same
#     `body` + `injuries` a survivor does -- they bleed, they can be bandaged, they die.
#   * `shambler.gd` chases them because `SimAllegiance.is_person` says a raider is prey, and the
#     attention field already carries them because they emit the same noise and scent a
#     colonist does.
#
# What *is* new is exactly two things: an archetype declared as content, and a walk towards the
# gate. Deliberately nothing else -- no looting AI, no dialogue, no faction standing. docs/18's
# factions are Milestone 3 and this must not pre-empt them.
#
# What a raider is kept out of, on purpose, and how: no `needs` component, so needs.gd never
# ticks them, `jobs.gd` never routes them (it queries `jobPriorities` + `identity`, and they
# have neither), the stockpile never counts them, `recruits.gd` never converts them, and -- the
# one that would have been silent and wrong -- `check_m2_balance.gd`'s `_survivors_alive` counts
# `needs` + `body`, so a raid could otherwise have *raised* the colony's survivor count.

const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimPathRes = preload("res://sim/path.gd")
const SimSightingsRes = preload("res://sim/modules/sightings.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimVisibilityRes = preload("res://sim/vision/visibility.gd")

# Content lives in `godot/content/raiders/`, one entry per file, against
# `content/schemas/raider.schema.json`. Its own directory rather than a tagged survivor entry,
# for three reasons that each cost something otherwise: the survivor schema forbids unknown
# top-level keys and the validator enforces `aptitudes` summing to 15 on that type; the frozen
# TypeScript oracle reads a *fixed* list of content directories (`CONTENT_TYPES`), so a new
# directory is invisible to it and a new key under `survivors/` would not be; and
# `SimSurvivors.list_uniques` boots everything under `survivors/` whose id starts with
# `survivor.unique.`, which is not a list a raider belongs on. `content/loot/` is the precedent
# for a Godot-only content type, down to registering the id in `content_validator.gd`.
const CONTENT_TYPE: String = "raider"

# How fast a raider walks in, in metres per second, when their entry declares nothing. Between a
# shambler's 0.8 and a colonist hurrying to a job (jobs.gd's 2.1): a band on its way somewhere,
# not a charge.
const DEFAULT_SPEED: float = 1.5

# How close an enemy comes before a raider stops walking and starts fighting. A swing has a
# wind-up, so a raider who kept walking would cross a defender's reach and be past them before
# the blow landed -- measured as "0 connects" the first time this ran without it. Just outside
# the longest melee reach in the content tree (the spear's 2.4 m) so a raider carrying anything
# halts at a distance its own weapon can work at, and `npc_combat.gd` -- which never sets a
# velocity, by design -- does the rest.
const HALT_METRES: float = 2.6

# What the approach walks at. Read off the map rather than computed: `gate_a` is where a colony
# is entered from, and the annex centre is the honest fallback for a district nobody stamped.
const ARRIVE_METRES: float = 1.2


static func content_entry(world: Variant, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", CONTENT_TYPE, id)
	if not (c is Dictionary):
		return null
	for path in (c as Dictionary).keys():
		if not String(path).begins_with("raiders/"):
			continue
		var raw: Variant = (c as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
				return entry
	return null


# Every archetype in the tree, sorted by id so a band's composition is a function of the seed
# rather than of directory iteration order.
static func types(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.content == null or not (world.content is Dictionary):
		return out
	for path in (world.content as Dictionary).keys():
		if not String(path).begins_with("raiders/"):
			continue
		var raw: Variant = (world.content as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")).begins_with("raider."):
				out.append(entry as Dictionary)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	return out


# One weighted draw from the archetype pool. Same shape as `SimRoster.pick_type`: weights are
# relative and a type that declares none counts as 1, so adding an archetype is a JSON file.
static func pick_type(world: Variant, rng: Variant) -> String:
	var pool: Array[Dictionary] = types(world)
	if pool.is_empty():
		return ""
	var total: int = 0
	for entry in pool:
		total += maxi(1, int(entry.get("weight", 1)))
	var roll: int = int(rng.call("int_range", 0, total - 1))
	for entry in pool:
		roll -= maxi(1, int(entry.get("weight", 1)))
		if roll < 0:
			return String(entry.get("id", ""))
	return String(pool[pool.size() - 1].get("id", ""))


static func is_raider(world: Variant, entity: int) -> bool:
	return world.components.has_component(entity, "raider")


# How many raiders are standing in the district. Counted off the component rather than off a
# tally the director keeps, because a tally has to be decremented and `entity.killed` fires more
# than once for the same individual (CLAUDE.md's standing trap) -- so a tally would drift down.
# `world.despawn` removes every component, which is what makes this honest; see `handle_death`
# in recruits.gd, where a dead raider goes.
static func live_count(world: Variant) -> int:
	return world.components.count("raider")


static func spawn(world: Variant, x: float, y: float, type_id: String) -> int:
	var entry: Variant = content_entry(world, type_id)
	if not (entry is Dictionary):
		return -1
	var e: Dictionary = entry as Dictionary
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	# A plain Array for the path and dictionary steps inside it, not Vector2i: components round
	# trip through JSON on every save and JSON has neither. jobs.gd's `_walk` is the precedent
	# and this mirrors it deliberately rather than inventing a second path representation.
	world.components.set_component(ent, "raider", {
		"id": String(e.get("id", type_id)),
		"path": [],
		"pathGen": -1,
		"goalX": -1,
		"goalY": -1,
	})
	# The declared allegiance, not a constant: this field is what `SimAllegiance.hostile` reads,
	# and the gate proves it by flipping it to "colony" and watching the colony stop shooting.
	SimAllegianceRes.attach(world, ent, String(e.get("allegiance", SimAllegianceRes.RAIDERS)))
	SimHealthRes.make_survivor_body(world, ent)
	SimHealthRes.make_stamina(world, ent)
	SimInventoryRes.make_inventory(world, ent)
	# The same emitter a colonist has, which is the whole of "zombies treat raiders as prey" on
	# the attention side: footsteps into the noise field, body scent into the scent field, both
	# read by the shambler gradient with nothing about raiders in it.
	SimAttentionRes.make_emitter(world, ent)
	SimAptitudesRes.apply(world, ent, e.get("aptitudes", {}))
	# Eyes, so `SimRanged.can_target` refuses a raider a shot through a wall the same way it
	# refuses a colonist one -- without an observer that check returns true and a raider would
	# be the one body in the district that could shoot through masonry.
	if not world.components.has_component(ent, "observer"):
		world.components.set_component(ent, "observer", SimVisibilityRes.daylight_eyes())
	SimSightingsRes.attach(world, ent)
	# `lootKit` is what `recruits._drop_kit` looks for: it is why a dead raider leaves their
	# weapon on the ground instead of taking it out of the world.
	world.components.set_component(ent, "lootKit", {})
	var kit: Variant = e.get("kit", [])
	if kit is Array:
		for row in kit as Array:
			# A kit row is a bare id, or `{item, count}` where the quantity matters. Ammunition
			# forced the second form: `spawn_item` defaults a stack to one, so a gunhand declared
			# as a bare "item.ammo.9mm" arrived with a single round and spent the raid reloading.
			var item_id: String = ""
			var count: int = 1
			if row is Dictionary:
				item_id = String((row as Dictionary).get("item", ""))
				count = maxi(1, int((row as Dictionary).get("count", 1)))
			else:
				item_id = String(row)
			if item_id.is_empty():
				continue
			var item: int = SimItemsRes.spawn_item(world, item_id, {"tier": "scavenged", "count": count})
			if _hold_it(world, ent, item):
				continue
			if not SimInventoryRes.stow(world, ent, item):
				world.components.set_component(item, "position", {"x": x, "y": y})
	world.events.publish({"type": "raider.arrived", "entity": ent, "id": String(e.get("id", type_id)), "x": x, "y": y})
	return ent


# Kit into the hand it belongs to rather than the pack. `SimSurvivors._hold_it`'s rule and its
# reasoning: a weapon in a satchel raises no `meleeWeapon`, so a raider carrying a machete in
# their bag would arrive unable to fight and the whole raid would be a walk.
static func _hold_it(world: Variant, ent: int, item: int) -> bool:
	var slot: Variant = SimInventoryRes.equip_slot_for(world, item)
	if slot == null:
		return false
	var eq: Variant = world.components.get_component(ent, "equipment")
	if eq is Dictionary and ((eq as Dictionary).get("slots", {}) as Dictionary).has(String(slot)):
		return false
	return SimInventoryRes.equip(world, ent, item)


static func register_module(world: Variant) -> void:
	# "ai"/0, beside `jobs.ai` and `shambler.think`: this decides a velocity, and
	# `movement.integrate` (movement/0) spends it on the same tick.
	world.systems.register("raiders.approach", "ai", 0, func(w: Variant) -> void:
		if bool(w.runOver) if "runOver" in w else false:
			return
		for ent in w.components.query(["raider", "position", "velocity"]):
			_approach(w, int(ent))
	)


static func _approach(world: Variant, ent: int) -> void:
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (vel is Dictionary):
		return
	var body: Variant = world.components.get_component(ent, "body")
	if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
		_still(vel as Dictionary)
		return
	# Stand and fight. `npc_combat.gd` never sets a velocity -- engaging is something you do from
	# where you are standing -- so the halt has to come from here, and it is the difference
	# between a band that fights the colony and a band that walks through it.
	if _enemy_within(world, ent, HALT_METRES):
		_still(vel as Dictionary)
		return
	var raider: Variant = world.components.get_component(ent, "raider")
	if not (raider is Dictionary):
		return
	var r: Dictionary = raider as Dictionary
	var goal: Vector2i = _objective(world, r)
	if goal.x < 0 or goal.y < 0:
		_still(vel as Dictionary)
		return
	_walk(world, ent, r, goal)


# Where the band is going. The gate, because that is how a colony is entered; the annex centre
# when a district carries no gate anchor; nothing at all when it carries no annex either, which
# is what an unstamped fixture map honestly is. Cached on the component so the anchors are read
# once per raider rather than once per tick.
static func _objective(world: Variant, r: Dictionary) -> Vector2i:
	var cached := Vector2i(int(r.get("goalX", -1)), int(r.get("goalY", -1)))
	if cached.x >= 0 and cached.y >= 0:
		return cached
	var map: Variant = world.tilemap
	if map == null:
		return Vector2i(-1, -1)
	var goal: Vector2i = SimTileMapRes.gate_a(map)
	if goal.x < 0 or goal.y < 0:
		var annex: Rect2i = SimTileMapRes.annex_rect(map)
		if annex.size.x <= 0 or annex.size.y <= 0:
			return Vector2i(-1, -1)
		goal = annex.position + annex.size / 2
	r["goalX"] = goal.x
	r["goalY"] = goal.y
	return goal


# The nearest enemy body inside `metres`, asked of `SimAllegiance.enemies_of` so the halt and
# `npc_combat._nearest_threat` cannot disagree about who counts as one.
static func _enemy_within(world: Variant, ent: int, metres: float) -> bool:
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return false
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	for other in SimAllegianceRes.enemies_of(world, ent):
		var body: Variant = world.components.get_component(int(other), "body")
		if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not (there is Dictionary):
			continue
		var dx: float = float((there as Dictionary)["x"]) - hx
		var dy: float = float((there as Dictionary)["y"]) - hy
		if dx * dx + dy * dy <= limit_sq:
			return true
	return false


# Grid A* towards the goal, re-planned when the map generation moves under it. jobs.gd's `_walk`,
# minus the job bookkeeping: raiders are the second thing in the district that walks somewhere on
# purpose, and giving them a second pathfinder would be two answers to one question.
static func _walk(world: Variant, ent: int, r: Dictionary, goal: Vector2i) -> void:
	var pos: Variant = world.components.get_component(ent, "position")
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (pos is Dictionary) or not (vel is Dictionary):
		return
	var p: Dictionary = pos as Dictionary
	var v: Dictionary = vel as Dictionary
	var here := Vector2i(floori(float(p["x"])), floori(float(p["y"])))
	var gen: int = int(world.mapGeneration)
	var path: Array = r.get("path", []) as Array
	if int(r.get("pathGen", -1)) != gen or path.is_empty():
		var found: Array[Vector2i] = SimPathRes.find(world, here, goal)
		path.clear()
		for s in found:
			path.append({"x": s.x, "y": s.y})
		r["path"] = path
		r["pathGen"] = gen
	if path.is_empty():
		# Arrived, or nowhere to go from here. A first-cut band stands its ground at the gate --
		# there is no looting AI and no withdrawal, and inventing one here would be scope the
		# slice deliberately does not take.
		_still(v)
		return
	var step: Variant = path[0]
	if not (step is Dictionary):
		path.remove_at(0)
		_still(v)
		return
	var tx: float = float(int((step as Dictionary).get("x", 0))) + 0.5
	var ty: float = float(int((step as Dictionary).get("y", 0))) + 0.5
	var dx: float = tx - float(p["x"])
	var dy: float = ty - float(p["y"])
	if dx * dx + dy * dy < 0.04:
		path.remove_at(0)
		r["path"] = path
		if path.is_empty():
			_still(v)
		return
	var length: float = sqrt(dx * dx + dy * dy)
	var speed: float = _speed_of(world, ent, r)
	# `dx`/`dy`, never `x`/`y`: a velocity written with position's key names adds a pair of keys
	# nothing reads and raises nothing (CLAUDE.md's `vel["x"]` trap).
	v["dx"] = dx / length * speed
	v["dy"] = dy / length * speed


static func _speed_of(world: Variant, ent: int, r: Dictionary) -> float:
	var entry: Variant = content_entry(world, String(r.get("id", "")))
	var base: float = DEFAULT_SPEED
	if entry is Dictionary:
		base = float((entry as Dictionary).get("speed", DEFAULT_SPEED))
	if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
		base *= float(world.modifiers.call("resolve", "move_speed", ent))
	return maxf(base, 0.1)


static func _still(vel: Dictionary) -> void:
	vel["dx"] = 0.0
	vel["dy"] = 0.0

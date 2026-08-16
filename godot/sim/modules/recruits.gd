class_name SimRecruits
extends RefCounted

# Gate beats, generator, Inspect hook, corpse / turn / leave (0004, 0009, 0010).
# ponytail: world.recruits bookkeeping sits next to director; no third blob.

const Clock = preload("res://sim/time/clock.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimAptitudes = preload("res://sim/modules/aptitudes.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimPath = preload("res://sim/path.gd")

const BEATS: Array[int] = [8, 12, 16]
const TRANSMIT_P: float = 0.15
const CAP: int = 3
const LEAVE_TICKS: int = 2400
const CORPSE_SCENT: float = 8.0
const CORPSE_SCENT_OLD: float = 25.0
const STREAM: String = "recruits"


static func default_state() -> Dictionary:
	return {"accepted": 0, "spawned": []}


static func register_module(world: Variant) -> void:
	if not "recruits" in world or not world.recruits is Dictionary:
		world.recruits = default_state()
	world.systems.register("recruits.beats", "director", 10, func(w: Variant) -> void:
		_tick_beats(w)
		_tick_dawn_leave(w)
		_tick_leave(w)
		_tick_corpse(w)
	)
	world.events.subscribe({"id": "recruits.mood-leave", "type": "mood.threshold", "handler": func(e: Dictionary) -> void:
		begin_leave(world, int(e.get("entity", -1)))
	})
	world.systems.register("recruits.intake", "input", 6, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			match String(c.get("type", "")):
				"recruit.accept":
					accept(w, int(c.get("entity", -1)))
				"recruit.ignore":
					ignore(w, int(c.get("entity", -1)))
	)


static func _tick_beats(world: Variant) -> void:
	var day: int = Clock.day_number(int(world.tick))
	if not BEATS.has(day):
		return
	var st: Dictionary = world.recruits as Dictionary
	var spawned: Array = st.get("spawned", []) as Array
	if spawned.has(day):
		return
	if int(st.get("accepted", 0)) >= CAP:
		return
	if not world.components.query(["recruit"]).is_empty():
		return
	spawned.append(day)
	st["spawned"] = spawned
	var rng: Variant = world.rng.stream(STREAM)
	var rolled: Dictionary = roll(world, rng)
	var gx: float = float(SimFortify.GATE_A.x) + 0.5
	var gy: float = float(SimFortify.GATE_A.y) + 1.5
	var ent: int = spawn_generated(world, rolled, gx, gy)
	world.components.set_component(ent, "recruit", {"waiting": true, "beatDay": day})
	world.events.publish({"type": "recruit.arrived", "entity": ent, "day": day})


static func _tick_dawn_leave(world: Variant) -> void:
	var phase: int = Clock.phase_of(int(world.tick))
	if phase != Clock.Phase.Dawn or Clock.phase_of(int(world.tick) - 1) == Clock.Phase.Dawn:
		return
	for e in world.components.query(["recruit"]):
		var r: Variant = world.components.get_component(int(e), "recruit")
		if r is Dictionary and bool((r as Dictionary).get("waiting", false)):
			world.events.publish({"type": "recruit.left", "entity": int(e), "reason": "dawn"})
			world.despawn(int(e))


static func _tick_leave(world: Variant) -> void:
	for e in world.components.query(["leaving", "position"]):
		var lv: Variant = world.components.get_component(int(e), "leaving")
		if not lv is Dictionary:
			continue
		(lv as Dictionary)["ticksLeft"] = int((lv as Dictionary).get("ticksLeft", 0)) - 1
		var dest := SimFortify.GATE_A
		var pos: Variant = world.components.get_component(int(e), "position")
		if pos is Dictionary:
			var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
			var job: Dictionary = {"path": (lv as Dictionary).get("path", []), "pathGen": int((lv as Dictionary).get("pathGen", -1))}
			SimJobs._walk(world, int(e), job, dest)
			(lv as Dictionary)["path"] = job.get("path", [])
			(lv as Dictionary)["pathGen"] = job.get("pathGen", -1)
			if here == dest or int((lv as Dictionary)["ticksLeft"]) <= 0:
				world.events.publish({"type": "recruit.left", "entity": int(e), "reason": "mood"})
				world.despawn(int(e))


static func _tick_corpse(world: Variant) -> void:
	for e in world.components.query(["corpse", "attention_emitter"]):
		var c: Variant = world.components.get_component(int(e), "corpse")
		if not c is Dictionary:
			continue
		if int(world.tick) - int((c as Dictionary).get("sinceTick", 0)) >= Clock.DAY_TICKS:
			var em: Variant = world.components.get_component(int(e), "attention_emitter")
			if em is Dictionary:
				(em as Dictionary)["scent"] = CORPSE_SCENT_OLD


static func roll(world: Variant, rng: Variant) -> Dictionary:
	var pool: Dictionary = _pool(world)
	var given: Array = pool.get("given", ["Sam"]) as Array
	var surnames: Array = pool.get("surnames", ["Doe"]) as Array
	var traits: Array = pool.get("traits", ["optimist"]) as Array
	var stories: Array = pool.get("backstories", [{"id": "cyclist", "label": "cyclist", "kit": []}]) as Array
	var features: Array = pool.get("features", ["tired eyes"]) as Array
	var g: String = String(given[int(rng.call("int_range", 0, given.size() - 1))])
	var s: String = String(surnames[int(rng.call("int_range", 0, surnames.size() - 1))])
	var story: Dictionary = stories[int(rng.call("int_range", 0, stories.size() - 1))] as Dictionary
	var picked: Array = []
	var bag: Array = traits.duplicate()
	var bias: String = String(story.get("bias", ""))
	if bias != "" and bag.has(bias):
		picked.append(bias)
		bag.erase(bias)
	var want: int = int(rng.call("int_range", 2, 3))
	while picked.size() < want and not bag.is_empty():
		var i: int = int(rng.call("int_range", 0, bag.size() - 1))
		picked.append(String(bag[i]))
		bag.remove_at(i)
	var apt: Dictionary = {"str": 5, "dex": 5, "con": 5}
	var comps: Array[Dictionary] = SimAptitudes.compositions()
	apt = comps[int(rng.call("int_range", 0, comps.size() - 1))]
	var nudge: Variant = story.get("nudge", {})
	if nudge is Dictionary:
		for k in (nudge as Dictionary).keys():
			apt[k] = clampi(int(apt.get(k, 5)) + int((nudge as Dictionary)[k]), 3, 8)
	var sum: int = int(apt["str"]) + int(apt["dex"]) + int(apt["con"])
	while sum != 15:
		var k2: String = "con"
		if sum > 15:
			if int(apt["str"]) >= int(apt["dex"]) and int(apt["str"]) >= int(apt["con"]):
				k2 = "str"
			elif int(apt["dex"]) >= int(apt["con"]):
				k2 = "dex"
			apt[k2] = maxi(3, int(apt[k2]) - 1)
		else:
			if int(apt["str"]) <= int(apt["dex"]) and int(apt["str"]) <= int(apt["con"]):
				k2 = "str"
			elif int(apt["dex"]) <= int(apt["con"]):
				k2 = "dex"
			apt[k2] = mini(8, int(apt[k2]) + 1)
		sum = int(apt["str"]) + int(apt["dex"]) + int(apt["con"])
	var look: Array = []
	var fbag: Array = features.duplicate()
	var fn: int = int(rng.call("int_range", 2, 3))
	while look.size() < fn and not fbag.is_empty():
		var fi: int = int(rng.call("int_range", 0, fbag.size() - 1))
		look.append(String(fbag[fi]))
		fbag.remove_at(fi)
	return {
		"name": g + " " + s,
		"backstory": String(story.get("label", "")),
		"traits": picked,
		"aptitudes": apt,
		"kit": (story.get("kit", []) as Array).duplicate(),
		"appearance": look,
	}


static func spawn_generated(world: Variant, rolled: Dictionary, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "posture", {"current": 2})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "identity", {
		"id": "survivor.gen." + String(rolled.get("name", "x")).to_lower().replace(" ", "_"),
		"name": String(rolled.get("name", "Someone")),
		"unique": false,
		"traits": (rolled.get("traits", []) as Array).duplicate(),
		"backstory": String(rolled.get("backstory", "")),
	})
	SimHealth.make_survivor_body(world, ent)
	SimHealth.make_stamina(world, ent)
	SimInventory.make_inventory(world, ent)
	SimAttention.make_emitter(world, ent)
	SimAptitudes.apply(world, ent, rolled.get("aptitudes", {}))
	SimNeeds.attach(world, ent, {"hunger": 50.0, "thirst": 50.0, "rest": 50.0})
	SimJobs.attach(world, ent, "Auto")
	for item_id in rolled.get("kit", []) as Array:
		var item: int = SimItems.spawn_item(world, String(item_id), {"tier": "scavenged"})
		if String(item_id).begins_with("item.food."):
			SimNeeds.mark_spoilage(world, item, String(item_id))
		if not SimInventory.stow(world, ent, item):
			world.components.set_component(item, "position", {"x": x, "y": y})
	return ent


static func accept(world: Variant, entity: int) -> bool:
	var r: Variant = world.components.get_component(entity, "recruit")
	if not r is Dictionary or not bool((r as Dictionary).get("waiting", false)):
		return false
	var st: Dictionary = world.recruits as Dictionary
	if int(st.get("accepted", 0)) >= CAP:
		return false
	(r as Dictionary)["waiting"] = false
	st["accepted"] = int(st.get("accepted", 0)) + 1
	var rng: Variant = world.rng.stream(STREAM)
	if float(rng.call("next")) < TRANSMIT_P:
		world.components.set_component(entity, "zombieInfection", {
			"exposures": [{
				"source": -1,
				"bodyPart": "torso",
				"exposedAtTick": int(world.tick),
				"transmitted": true,
				"stage": SimInfection.Stage.Latent,
				"stageEnteredAtTick": int(world.tick),
				"cauterized": false,
				"amputated": false,
				"vector": "hidden-bite",
			}],
		})
	var n: Dictionary = SimNeeds.of(world, entity)
	n["hunger"] = 50.0
	n["thirst"] = 50.0
	n["rest"] = 50.0
	world.components.remove(entity, "recruit")
	world.events.publish({"type": "survivor.joined", "entity": entity, "id": "recruit"})
	return true


static func ignore(world: Variant, entity: int) -> bool:
	var r: Variant = world.components.get_component(entity, "recruit")
	if not r is Dictionary or not bool((r as Dictionary).get("waiting", false)):
		return false
	world.events.publish({"type": "recruit.left", "entity": entity, "reason": "ignore"})
	world.despawn(entity)
	return true


static func begin_leave(world: Variant, entity: int) -> void:
	if entity < 0 or world.components.has_component(entity, "controlled"):
		return
	if int(entity) == int(world.player):
		return
	if world.components.has_component(entity, "leaving"):
		return
	world.components.set_component(entity, "leaving", {"ticksLeft": LEAVE_TICKS, "path": [], "pathGen": -1})
	world.components.remove(entity, "job")


static func waiting_in_reach(world: Variant, actor: int) -> int:
	for e in world.components.query(["recruit", "position"]):
		var r: Variant = world.components.get_component(int(e), "recruit")
		if not r is Dictionary or not bool((r as Dictionary).get("waiting", false)):
			continue
		if SimFortify._entity_in_reach(world, actor, int(e)):
			return int(e)
	return -1


static func handle_death(world: Variant, entity: int) -> bool:
	if entity < 0:
		return false
	if int(entity) == int(world.player) or world.components.has_component(entity, "controlled"):
		world.runOver = true
		world.events.publish({"type": "run.over", "entity": entity})
		if _is_transmitted(world, entity):
			_turn_with_kit(world, entity)
			return true
		world.despawn(entity)
		return true
	if world.components.has_component(entity, "shambler"):
		_drop_kit(world, entity)
		world.despawn(entity)
		return true
	if _is_transmitted(world, entity):
		_turn_with_kit(world, entity)
		return true
	if world.components.has_component(entity, "needs") or world.components.has_component(entity, "identity"):
		_make_corpse(world, entity)
		return true
	world.despawn(entity)
	return true


static func _is_transmitted(world: Variant, entity: int) -> bool:
	var st: Variant = world.components.get_component(entity, "zombieInfection")
	if not st is Dictionary:
		return false
	for e in (st as Dictionary).get("exposures", []) as Array:
		if bool((e as Dictionary).get("transmitted", false)):
			return true
	return false


static func _make_corpse(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "corpse", {"sinceTick": int(world.tick)})
	world.components.remove(entity, "needs")
	world.components.remove(entity, "job")
	world.components.remove(entity, "jobPriorities")
	world.components.remove(entity, "sleeping")
	world.components.remove(entity, "velocity")
	var em: Variant = world.components.get_component(entity, "attention_emitter")
	if em is Dictionary:
		(em as Dictionary)["scent"] = CORPSE_SCENT
		(em as Dictionary)["ambient"] = 0.0
	else:
		var e2: Dictionary = SimAttention.PERSON_EMITTER.duplicate(true)
		e2["scent"] = CORPSE_SCENT
		e2["walking"] = 0.0
		e2["sprinting"] = 0.0
		SimAttention.make_emitter(world, entity, e2)
	world.events.publish({"type": "corpse.formed", "entity": entity})


static func _turn_with_kit(world: Variant, entity: int) -> void:
	var pos: Variant = world.components.get_component(entity, "position")
	var px: float = float((pos as Dictionary).get("x", 0.0)) if pos is Dictionary else 0.0
	var py: float = float((pos as Dictionary).get("y", 0.0)) if pos is Dictionary else 0.0
	var items: Array[int] = SimInventory.carried_items(world, entity)
	for item in items:
		SimInventory.remove_from_container(world, item)
		SimInventory.unequip_item(world, item)
	world.despawn(entity)
	var shambler: int = int(world.entities.spawn())
	world.components.set_component(shambler, "position", {"x": px, "y": py})
	world.components.set_component(shambler, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(shambler, "body", SimCombat.ZOMBIE_BODY.duplicate())
	var rng: Variant = world.rng.stream("shambler")
	SimShambler.make_shambler(world, shambler, rng)
	SimInventory.make_inventory(world, shambler)
	for item2 in items:
		if not SimInventory.stow(world, shambler, item2):
			world.components.set_component(item2, "position", {"x": px, "y": py})
	world.components.set_component(shambler, "turnedFrom", {"entity": entity})
	world.components.set_component(shambler, "lootKit", {})


static func _drop_kit(world: Variant, entity: int) -> void:
	if not world.components.has_component(entity, "lootKit") and not world.components.has_component(entity, "turnedFrom"):
		return
	var pos: Variant = world.components.get_component(entity, "position")
	var px: float = float((pos as Dictionary).get("x", 0.0)) if pos is Dictionary else 0.0
	var py: float = float((pos as Dictionary).get("y", 0.0)) if pos is Dictionary else 0.0
	for item in SimInventory.carried_items(world, entity):
		SimInventory.remove_from_container(world, item)
		SimInventory.unequip_item(world, item)
		world.components.set_component(item, "position", {"x": px, "y": py})


static func _pool(world: Variant) -> Dictionary:
	if world == null or world.content == null:
		return {}
	var c: Variant = world.content
	if c is Dictionary:
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == "colony.generator.survivors":
				return v as Dictionary
	return {}

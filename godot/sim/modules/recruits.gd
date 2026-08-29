class_name SimRecruits
extends RefCounted

# Gate beats, generator, Inspect hook, corpse / turn / leave (0004, 0009, 0010).
# ponytail: world.recruits bookkeeping sits next to director; no third blob.

const Clock = preload("res://sim/time/clock.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimAptitudes = preload("res://sim/modules/aptitudes.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimPath = preload("res://sim/path.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")

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
	# A stranger arrives at the gate, and where the gate is comes off the map. A district with no
	# gate anchor has nowhere for one to turn up, so the beat does not fire -- checked before the
	# day is marked spawned and before the roll, so neither the beat nor the RNG stream is spent.
	var gate: Vector2i = SimTileMap.gate_a(world.tilemap)
	if gate.x < 0 or gate.y < 0:
		return
	spawned.append(day)
	st["spawned"] = spawned
	var rng: Variant = world.rng.stream(STREAM)
	var rolled: Dictionary = roll(world, rng)
	var gx: float = float(gate.x) + 0.5
	var gy: float = float(gate.y) + 1.5
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
		# They leave by the gate the map names. With no gate anchor there is nothing to walk to,
		# so they simply run their clock down and go -- rather than pathing at (-1, -1).
		var dest: Vector2i = SimTileMap.gate_a(world.tilemap)
		var pos: Variant = world.components.get_component(int(e), "position")
		if pos is Dictionary:
			var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
			var arrived: bool = false
			if dest.x >= 0 and dest.y >= 0:
				var job: Dictionary = {"path": (lv as Dictionary).get("path", []), "pathGen": int((lv as Dictionary).get("pathGen", -1))}
				SimJobs._walk(world, int(e), job, dest)
				(lv as Dictionary)["path"] = job.get("path", [])
				(lv as Dictionary)["pathGen"] = job.get("pathGen", -1)
				arrived = here == dest
			if arrived or int((lv as Dictionary)["ticksLeft"]) <= 0:
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


# Removes every id conflicting with `picked_id` from `bag`, per `traitConflicts` -- content, not
# a GDScript constant (docs/30). `bag` is a plain Array (a reference type in GDScript, unlike a
# PackedStringArray -- CLAUDE.md's packed-array trap), so the erase is visible to the caller's
# copy of the same array; `Array.erase` matches Strings by value, which is exactly what a trait id
# needs (the by-value/by-reference trap only bites Dictionaries and other composite elements).
# Called both after the backstory `bias` pre-pick (before the loop starts) and after every loop
# pick -- the bias case is the one a naive implementation misses, since it runs before `bag` is
# ever touched by the loop.
static func _erase_conflicts_of(bag: Array, picked_id: String, conflicts: Array) -> void:
	for pair in conflicts:
		var p: Array = pair as Array
		if p.size() != 2:
			continue
		var a: String = String(p[0])
		var b: String = String(p[1])
		if a == picked_id:
			bag.erase(b)
		elif b == picked_id:
			bag.erase(a)


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
	var conflicts: Array = pool.get("traitConflicts", []) as Array
	var picked: Array = []
	var bag: Array = traits.duplicate()
	var bias: String = String(story.get("bias", ""))
	if bias != "" and bag.has(bias):
		picked.append(bias)
		bag.erase(bias)
		_erase_conflicts_of(bag, bias, conflicts)
	var want: int = int(rng.call("int_range", 2, 3))
	while picked.size() < want and not bag.is_empty():
		var i: int = int(rng.call("int_range", 0, bag.size() - 1))
		var picked_id: String = String(bag[i])
		picked.append(picked_id)
		bag.remove_at(i)
		_erase_conflicts_of(bag, picked_id, conflicts)
	var apt: Dictionary = {"str": 5, "dex": 5, "con": 5}
	var comps: Array[Dictionary] = SimAptitudes.compositions()
	apt = comps[int(rng.call("int_range", 0, comps.size() - 1))]
	var feat: Array = []
	var fbag: Array = features.duplicate()
	var fn: int = int(rng.call("int_range", 2, 3))
	while feat.size() < fn and not fbag.is_empty():
		var fi: int = int(rng.call("int_range", 0, fbag.size() - 1))
		feat.append(String(fbag[fi]))
		fbag.remove_at(fi)
	# Age and visual look draw from their own stream, `recruitLook` -- never from `rng` above.
	# `rng` is the `recruits` stream, and its draw order (name, surname, story, traits,
	# composition, features) is measured by the balance harness; a new draw threaded into it
	# would land every later call, including `accept`'s 15% transmit roll, on a different byte
	# of the stream. A second named stream costs nothing and perturbs nothing (docs/23,
	# CLAUDE.md's "new randomness gets its own stream").
	var look_rng: Variant = world.rng.stream("recruitLook")
	var bands: Array = pool.get("ageBands", [{"id": "adult", "min": 25, "max": 44, "prose": "", "nudge": {}}]) as Array
	var band: Dictionary = bands[int(look_rng.call("int_range", 0, bands.size() - 1))] as Dictionary
	var age: int = int(look_rng.call("int_range", int(band.get("min", 18)), int(band.get("max", 60))))
	var looks: Array = pool.get("looks", []) as Array
	var look_id: String = ""
	if not looks.is_empty():
		look_id = String(looks[int(look_rng.call("int_range", 0, looks.size() - 1))])
	# Both nudges feed the one clamp-and-rebalance-to-15 loop below, applied before it runs
	# rather than each getting its own pass, so a backstory and an age band pulling the same
	# stat land as one combined push, not a push-then-push that could overshoot and silently
	# clamp twice.
	for nudge in [story.get("nudge", {}), band.get("nudge", {})]:
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
	return {
		"name": g + " " + s,
		"backstory": String(story.get("label", "")),
		"backstoryId": String(story.get("id", "")),
		"traits": picked,
		"aptitudes": apt,
		"kit": (story.get("kit", []) as Array).duplicate(),
		"features": feat,
		"age": age,
		"look": look_id,
	}


static func spawn_generated(world: Variant, rolled: Dictionary, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "identity", {
		"id": "survivor.gen." + String(rolled.get("name", "x")).to_lower().replace(" ", "_"),
		"name": String(rolled.get("name", "Someone")),
		"unique": false,
		"traits": (rolled.get("traits", []) as Array).duplicate(),
		"backstory": String(rolled.get("backstory", "")),
		"backstoryId": String(rolled.get("backstoryId", "")),
		"age": int(rolled.get("age", 0)),
		"look": String(rolled.get("look", "")),
		"features": (rolled.get("features", []) as Array).duplicate(),
	})
	# Same as `SimSurvivors.spawn_unique`: the colony says which side it is on, so a raider band
	# can find it. `faction_of` already reads COLONY by default, so this changes nothing about
	# existing behaviour -- it is what puts a generated colonist in `SimAllegiance.enemies_of`.
	SimAllegiance.attach(world, ent, SimAllegiance.COLONY)
	SimHealth.make_survivor_body(world, ent)
	SimHealth.make_stamina(world, ent)
	SimInventory.make_inventory(world, ent)
	SimAttention.make_emitter(world, ent)
	SimAptitudes.apply(world, ent, rolled.get("aptitudes", {}))
	SimNeeds.attach(world, ent, {"hunger": 50.0, "thirst": 50.0, "rest": 50.0})
	SimJobs.attach(world, ent, "Auto")
	SimSkills.attach(world, ent)
	SimSurvivors.give_eyes(world, ent)
	SimSurvivors.equip_kit(world, ent, rolled.get("kit", []) as Array, x, y)
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
		var next: int = _succession_pick(world, entity)
		if next >= 0:
			# Gear stays on the corpse; camera hands over (ADR 0013 / docs/01).
			if _turns_on_death(world, entity):
				_turn_with_kit(world, entity)
			else:
				_make_corpse(world, entity)
			_handoff(world, entity, next)
			return true
		world.runOver = true
		world.events.publish({"type": "run.over", "entity": entity})
		if _turns_on_death(world, entity):
			_turn_with_kit(world, entity)
			return true
		world.despawn(entity)
		return true
	if world.components.has_component(entity, "shambler"):
		_drop_kit(world, entity)
		world.despawn(entity)
		return true
	if _turns_on_death(world, entity):
		_turn_with_kit(world, entity)
		return true
	# A dead raider drops what they were carrying and leaves the world. The kit falling is the
	# point -- it is the only thing a raid leaves behind, since nothing loots for the colony --
	# and `lootKit` on the body is what makes `_drop_kit` fire for them.
	#
	# Removed rather than left as a corpse, and that is a decision rather than laziness: the
	# `raider` component is what the raid cap counts, and `components.query` does not check alive
	# (CLAUDE.md's despawn trap), so a raider corpse would sit in the district's raider budget
	# forever and every raid after the second would be refused for a cap full of dead men.
	# `world.despawn` removes every component, which is what keeps that count honest.
	if world.components.has_component(entity, "raider"):
		# Announced before the body goes, because afterwards nothing can tell what it was: the
		# despawn takes every component with it, so an observer reading `entity.killed` off the
		# bus would find an id with nothing attached and book a raider as a colonist. That is
		# exactly what the balance harness did on its first run with raids live.
		var rd: Variant = world.components.get_component(entity, "raider")
		world.events.publish({
			"type": "raider.killed",
			"entity": entity,
			"id": String((rd as Dictionary).get("id", "")) if rd is Dictionary else "",
		})
		_drop_kit(world, entity)
		world.despawn(entity)
		return true
	if world.components.has_component(entity, "needs") or world.components.has_component(entity, "identity"):
		_make_corpse(world, entity)
		return true
	world.despawn(entity)
	return true


static func _succession_pick(world: Variant, dead: int) -> int:
	var best: int = -1
	var best_d: float = 1e12
	var mara: int = -1
	var dead_pos: Variant = world.components.get_component(dead, "position")
	var dx0: float = float((dead_pos as Dictionary).get("x", 0.0)) if dead_pos is Dictionary else 0.0
	var dy0: float = float((dead_pos as Dictionary).get("y", 0.0)) if dead_pos is Dictionary else 0.0
	for e in world.components.query(["position"]):
		var ent: int = int(e)
		if ent == dead:
			continue
		if world.components.has_component(ent, "corpse") or world.components.has_component(ent, "shambler"):
			continue
		if not world.components.has_component(ent, "needs") and not world.components.has_component(ent, "identity"):
			continue
		if world.components.has_component(ent, "controlled") and ent != dead:
			# Another controlled body — still eligible if we are transferring.
			pass
		var ident: Variant = world.components.get_component(ent, "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			mara = ent
		var p: Variant = world.components.get_component(ent, "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - dx0
		var dy: float = float((p as Dictionary)["y"]) - dy0
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = ent
	if mara >= 0:
		return mara
	return best


static func _handoff(world: Variant, dead: int, next: int) -> void:
	if world.components.has_component(dead, "controlled"):
		world.components.remove(dead, "controlled")
	if world.components.has_component(dead, "observer"):
		world.components.remove(dead, "observer")
	world.player = next
	world.components.set_component(next, "controlled", {})
	SimSurvivors.give_eyes(world, next)
	if world.components.has_component(next, "job"):
		world.components.remove(next, "job")
	world.runOver = false
	world.events.publish({"type": "player.succeeded", "from": dead, "to": next})


# Does this body get up again? Transmission decides it everywhere except one place: a body the
# colony **put down** stays down. docs/06 response #5 sells exactly one product -- "certainty,
# immediately, cheaply" -- and a put-down that let the body turn anyway would deliver the outcome
# the verb exists to buy your way out of. The marker is the same `putDown` component the grief
# handler reads to charge the put-down's higher price, set by SimInfection.put_down before it
# reaps, so both halves of response #5 read one fact.
static func _turns_on_death(world: Variant, entity: int) -> bool:
	if world.components.has_component(entity, "putDown"):
		return false
	return _is_transmitted(world, entity)


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
	# Through _wake rather than by stripping `sleeping` here: the bed's `occupiedBy` is cleared in
	# exactly one place, and dropping the component behind its back left a survivor who died in bed
	# holding it for the rest of the run -- `nearest_bed`'s free-only scan (jobs.gd's Rest) would
	# never offer it to anybody again. _wake reads the `sleeping` component and the bed, neither of
	# which the removals above touch, so it is safe here at the end of them.
	SimNeeds.wake(world, entity)
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
	# The other door into the same hole `_make_corpse` had: `world.despawn` takes the sleeper's
	# components with it and leaves the *bed* pointing at a dead id, which reads as occupied
	# forever. Turning in your sleep must hand the bed back too.
	SimNeeds.wake(world, entity)
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

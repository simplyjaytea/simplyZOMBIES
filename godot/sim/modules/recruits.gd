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
const SimPeople = preload("res://sim/modules/people.gd")

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
	# A recruit already waiting blocks the beat -- the colony deals with one person at a time --
	# but a **stranger** is not at the gate and is not waiting on this decision. Narrowed by the
	# strangers slice: before it, somebody hiding in a house on day 5 silently cancelled the day-8
	# gate beat and the colony never learned why. `check_m2_strangers.gd`'s GATE BEAT lane holds
	# both halves -- a hidden stranger does not block day 8, a waiting gate recruit still does.
	if not _waiting_at_the_gate(world).is_empty():
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
	# Every waiting recruit **at the gate** goes at dawn. A stranger in a building is not waiting
	# at the gate and keeps their own clock (`SimStrangers.STRANGER_DAYS`); despawning them here
	# would have killed every one of them on the first dawn after they were placed, which is the
	# second regression this narrowing exists to prevent.
	for e in _waiting_at_the_gate(world):
		world.events.publish({"type": "recruit.left", "entity": int(e), "reason": "dawn"})
		world.despawn(int(e))


# The recruits standing at the gate waiting to be spoken to: `recruit {waiting: true}` without
# `stranger`. One predicate for both the beat and the dawn leave, so the two cannot come to
# disagree about what a stranger is.
static func _waiting_at_the_gate(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for e in world.components.query(["recruit"]):
		var r: Variant = world.components.get_component(int(e), "recruit")
		if not (r is Dictionary):
			continue
		if bool((r as Dictionary).get("stranger", false)):
			continue
		if bool((r as Dictionary).get("waiting", false)):
			out.append(int(e))
	return out


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
				# Whatever put them on the road says why. "mood" for a colonist who walked out,
				# which is every caller that came before the strangers slice and so is the
				# default; "stranger" for somebody who gave up on a colony that never came to
				# find them, which the chronicle deliberately says nothing about (see
				# `SimStrangers._give_up`).
				world.events.publish({"type": "recruit.left", "entity": int(e), "reason": String((lv as Dictionary).get("reason", "mood"))})
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


# The roll lives in `people.gd` now (docs/30, "The pause lifted", 2026-09-14): one shape for a
# recruit at the gate, a stranger in a building, a raider with a name and a settler at a camp.
# This is the recruit's call of it -- the `recruits` stream for the identity, `recruitLook` for
# the age and the look -- and `check_m2_people.gd` pins the canonical seed's first two rolls so
# the move is byte-identical rather than said to be.
static func roll(world: Variant, rng: Variant) -> Dictionary:
	return SimPeople.roll(rng, world.rng.stream("recruitLook"), _pool(world))


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
	# What a colonist has and this body may not have had. A recruit at the gate and a stranger in a
	# house are both `spawn_generated` bodies and carry all four already, so every line here is a
	# no-op for them; a **settler** is not, and the camp's whole design is that they are not. Their
	# module withholds `needs` and `jobPriorities` on purpose -- those two are what the colony's
	# ledger and its scheduler are keyed on -- and they carry the settlers faction, so joining is
	# the moment all three change. Without this, accepting one produced a colonist the harness
	# could not count, `jobs.gd` would never schedule, `needs.gd` would never drain, and whose
	# hunger the three lines below wrote into a Dictionary nothing owned (`SimNeeds.of` answers a
	# missing component with a detached `blank()`).
	if not world.components.has_component(entity, "needs"):
		SimNeeds.attach(world, entity, {"hunger": 50.0, "thirst": 50.0, "rest": 50.0})
	if not world.components.has_component(entity, "jobPriorities"):
		SimJobs.attach(world, entity, "Auto")
	# And the web, for the same reason and with the same guard: a colonist with no `skillWeb` is
	# one whose Focus pays into nothing and whose web screen is empty -- a half-colonist that
	# nothing reports, which is the shape this milestone keeps finding.
	if not world.components.has_component(entity, "skillWeb"):
		SimSkills.attach(world, entity)
	if not SimAllegiance.is_colony(world, entity):
		SimAllegiance.attach(world, entity, SimAllegiance.COLONY)
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
		var person: Variant = (rd as Dictionary).get("person", {}) if rd is Dictionary else {}
		world.events.publish({
			"type": "raider.killed",
			"entity": entity,
			"id": String((rd as Dictionary).get("id", "")) if rd is Dictionary else "",
			# Who they were, carried on the event rather than looked up by the handler: the
			# despawn below takes `raider` with it and handlers run at `drain()`, at the end of
			# the step, so a chronicle that read the component would find nothing every time.
			# This is what the colony learns off the body -- `chronicle.gd`'s raider line.
			"person": (person as Dictionary).duplicate(true) if person is Dictionary else {},
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
		# An heir is one of *yours*. The guard above asks whether this body is a person, which was
		# the same question right up until a third side existed: a settler carries an `identity`
		# and would have passed it, so the player dying at a settlers' fence would have woken up
		# in a stranger's body. `is_colony` is the seam that separates the two questions -- being
		# a person is what makes a zombie chase you, being the colony is what makes you an heir --
		# and a raider is now refused here twice over rather than by the accident of carrying no
		# identity. check_m2_allegiance.gd's NO-HEIR lane and check_m2_raiders.gd's NO-IDENTITY
		# lane hold both halves of that.
		if not SimAllegiance.is_colony(world, ent):
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
	return SimPeople.pool(world, SimPeople.SURVIVORS_POOL_ID)

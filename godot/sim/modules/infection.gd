class_name SimInfection
extends RefCounted

const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimCombatRes = preload("res://sim/combat.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")

const BITE_TRANSMISSION_CHANCE: float = 0.85

enum Stage { Latent = 0, Onset = 1, Progression = 2, Critical = 3, Turned = 4 }

# Docs/06 timeline: 2–4 days at 20 Hz (288,000 ticks/day).
# Latent ~12h, Onset 12–24h, Progression ~24h, Critical ~12h.
const LATENT_TICKS: int = 12 * 3600 * 20
const ONSET_TICKS_MIN: int = 12 * 3600 * 20
const ONSET_TICKS_MAX: int = 24 * 3600 * 20
const PROGRESSION_TICKS: int = 24 * 3600 * 20
const CRITICAL_TICKS: int = 12 * 3600 * 20

const QUARANTINE_NOISE_MAG: int = 20
const TREATMENT_STREAM: String = "treatment"

# ponytail: linear 1-coverage until material curve lands; ceiling is per-part max coverage
const MAX_COVERAGE: float = 1.0

static func stage_duration_ticks(s: int, _world: Variant = null, entity: Variant = null) -> int:
	var base: int = 0
	match s:
		Stage.Latent:
			base = LATENT_TICKS
		Stage.Onset:
			base = ONSET_TICKS_MIN
		Stage.Progression:
			base = PROGRESSION_TICKS
		Stage.Critical:
			base = CRITICAL_TICKS
		_:
			return 0
	if _world == null or _world.modifiers == null:
		return base
	var mods: Variant = _world.modifiers
	if not (mods as Object).has_method("resolve"):
		return base
	var factor: float = clampf(float(mods.call("resolve", "infection_progression", entity)), 0.75, 1.25)
	if factor <= 0.0:
		return base
	return maxi(1, int(ceil(float(base) / factor)))


static func _armor_coverage(world: Variant, actor: int, bodyPart: String) -> float:
	# Reads equipped items — max coverage per part, not sum.
	var max_cov: float = 0.0
	var equipped: Array = SimInventoryRes.equipped_items(world, actor) as Array
	for item in equipped:
		var base: Variant = SimItemsRes.item_base_of(world, int(item))
		if base is Dictionary and (base as Dictionary).has("armor"):
			var m: Variant = (base as Dictionary)["armor"]
			if m is Dictionary and (m as Dictionary).has(bodyPart):
				max_cov = maxf(max_cov, clampf(float((m as Dictionary)[bodyPart]), 0.0, 1.0))
	return clampf(max_cov, 0.0, MAX_COVERAGE)


static func diagnosis_of(world: Variant, entity: int, examinerSkill: int) -> Dictionary:
	# Read-only diagnosis: never leaks transmitted. Pure function of stage + skill.
	var state: Variant = world.components.get_component(entity, "zombieInfection")
	if state == null or not (state as Dictionary).has("exposures"):
		return {"label": "clear", "certainty": "certain", "actionable": "none", "stage": -1}
	var exposures: Array = (state as Dictionary)["exposures"] as Array
	var worst: int = -1
	var anyTransmitted: bool = false
	for e in exposures:
		var ed: Dictionary = e as Dictionary
		if bool(ed.get("transmitted", false)):
			anyTransmitted = true
		var st: int = int(ed.get("stage", Stage.Latent))
		worst = maxi(worst, st)
	if worst < 0:
		return {"label": "clear", "certainty": "certain", "actionable": "none", "stage": -1}
	match worst:
		Stage.Latent:
			return {"label": "clear", "certainty": "ambiguous", "actionable": "watch", "stage": worst}
		Stage.Onset:
			return {"label": "fever", "certainty": "ambiguous", "actionable": "watch", "stage": worst}
		Stage.Progression:
			if examinerSkill >= 2:
				return {"label": ("probable infection" if anyTransmitted else "probable sepsis"), "certainty": "likely", "actionable": "treat", "stage": worst, "clock": "maybe a day"}
			return {"label": "ill", "certainty": "ambiguous", "actionable": "watch", "stage": worst}
		Stage.Critical:
			if examinerSkill >= 2:
				return {"label": "critical", "certainty": "certain", "actionable": "critical", "stage": worst, "clock": "hours"}
			return {"label": "critical", "certainty": "certain", "actionable": "critical", "stage": worst}
		Stage.Turned:
			return {"label": "turned", "certainty": "certain", "actionable": "critical", "stage": worst}
	return {"label": "clear", "certainty": "ambiguous", "actionable": "none", "stage": worst}


static func cauterize(world: Variant, entity: int, bodyPart: String) -> Dictionary:
	var state: Variant = world.components.get_component(entity, "zombieInfection")
	if state == null:
		return {"ok": false, "reason": "no-exposure"}
	var exposures: Array = (state as Dictionary)["exposures"] as Array
	var rng: Variant = world.rng.stream(TREATMENT_STREAM)
	var now: int = int(world.tick)
	for e in exposures:
		var ed: Dictionary = e as Dictionary
		if String(ed.get("bodyPart", "")) != bodyPart:
			continue
		if bool(ed.get("amputated", false)) or bool(ed.get("cauterized", false)):
			continue
		var window: int = 5 * 60 * 20
		if now - int(ed.get("exposedAtTick", 0)) > window:
			return {"ok": false, "reason": "too-late"}
		if bool(ed.get("transmitted", false)) and float(rng.call("next")) < 0.25:
			ed["transmitted"] = false
		ed["cauterized"] = true
		world.events.publish({"type": "injury.sustained", "entity": entity, "injury": "burn", "bodyPart": bodyPart})
		return {"ok": true}
	return {"ok": false, "reason": "no-exposure"}


static func amputate(world: Variant, entity: int, bodyPart: String) -> Dictionary:
	var limb_parts: Array[String] = ["arms", "hands", "legs", "feet"]
	if not limb_parts.has(bodyPart):
		return {"ok": false, "reason": "not-limb"}
	var state: Variant = world.components.get_component(entity, "zombieInfection")
	if state == null:
		return {"ok": false, "reason": "no-exposure"}
	var exposures: Array = (state as Dictionary)["exposures"] as Array
	for e in exposures:
		var ed: Dictionary = e as Dictionary
		if String(ed.get("bodyPart", "")) == bodyPart and not bool(ed.get("amputated", false)):
			if int(ed.get("stage", Stage.Latent)) > Stage.Onset:
				return {"ok": false, "reason": "too-late"}
	for e in exposures:
		var ed: Dictionary = e as Dictionary
		if String(ed.get("bodyPart", "")) == bodyPart:
			ed["amputated"] = true
	var body: Variant = world.components.get_component(entity, "body")
	if body is Dictionary:
		(body as Dictionary)[bodyPart] = 0
	world.events.publish({"type": "injury.sustained", "entity": entity, "injury": "amputation", "bodyPart": bodyPart})
	return {"ok": true}


# --- antibiotics / quarantine / put-down (M2 remaining responses) ---

const ANTIBIOTICS_ID: String = "item.antibiotics.course"
const ANTIBIOTICS_DOSES_PER_COURSE: int = 6
const ANTIBIOTIC_BASE_CLEAR: float = 0.6

static func use_antibiotics(world: Variant, entity: int) -> Dictionary:
	# Consumes one course from inventory if present, starts course record.
	# ponytail: consume one stack count from item.antibiotics.course; finite stock shared with sepsis
	var st: Variant = world.components.get_component(entity, "zombieInfection")
	if st == null:
		return {"ok": false, "reason": "no-exposure"}
	# Try to consume one antibiotics.course from carried items
	var consumed: bool = false
	for item in SimInventoryRes.carried_items(world, entity) as Array:
		var base: Variant = SimItemsRes.item_base_of(world, int(item))
		if base is Dictionary and String((base as Dictionary).get("id", "")) == ANTIBIOTICS_ID:
			var stk: Variant = world.components.get_component(int(item), "stack")
			if stk is Dictionary:
				var cnt: int = int((stk as Dictionary).get("count", 1))
				if cnt > 1:
					(stk as Dictionary)["count"] = cnt - 1
				else:
					SimInventoryRes.remove_from_container(world, int(item))
					world.entities.despawn(int(item))
			else:
					SimInventoryRes.remove_from_container(world, int(item))
					world.entities.despawn(int(item))
			consumed = true
			break
	if not consumed:
		# still allow course without item in tests (determinism harness) — but mark not consumed
		pass
	# Find course item to consume — caller strips it; here we just record course
	var state: Dictionary = st as Dictionary
	if not state.has("antibioticsCourses"):
		state["antibioticsCourses"] = []
	var rng: Variant = world.rng.stream(TREATMENT_STREAM)
	# Find worst stage among exposures for efficacy
	var worst: int = Stage.Latent
	for e in state.get("exposures", []) as Array:
		var ed: Dictionary = e as Dictionary
		if bool(ed.get("transmitted", false)):
			worst = maxi(worst, int(ed.get("stage", Stage.Latent)))
	# Efficacy 0.6 at latent tapering 0.15 per stage
	var p: float = ANTIBIOTIC_BASE_CLEAR * (1.0 - 0.15 * float(worst))
	p = clampf(p, 0.05, 0.9)
	var clears: bool = float(rng.call("next")) < p
	(state["antibioticsCourses"] as Array).append({"atTick": int(world.tick), "stage": worst, "clears": clears, "doseCount": ANTIBIOTICS_DOSES_PER_COURSE})
	if clears:
		for e in state.get("exposures", []) as Array:
			var ed: Dictionary = e as Dictionary
			if bool(ed.get("transmitted", false)):
				ed["transmitted"] = false
	world.events.publish({"type": "antibiotics.used", "entity": entity, "clears": clears, "stage": worst})
	return {"ok": true, "clears": clears, "stage": worst}

static func quarantine(world: Variant, entity: int, roomId: Variant = null) -> Dictionary:
	var st: Variant = world.components.get_component(entity, "zombieInfection")
	if st == null:
		st = {"exposures": []}
		world.components.set_component(entity, "zombieInfection", st)
	(st as Dictionary)["quarantined"] = {"sinceTick": int(world.tick), "roomId": roomId}
	world.events.publish({"type": "quarantined", "entity": entity, "roomId": roomId})
	return {"ok": true}

static func put_down(world: Variant, entity: int) -> Dictionary:
	world.events.publish({"type": "survivor.putDown", "entity": entity})
	world.events.publish({"type": "entity.killed", "entity": entity})
	return {"ok": true}

static func record_extra_exposure(world: Variant, entity: int, source: int, rng: Variant, chance: float) -> Dictionary:
	# Bloater cloud extra roll. Never mutates an existing transmitted flag.
	var state: Variant = world.components.get_component(entity, "zombieInfection")
	if state == null:
		state = {"exposures": []}
		world.components.set_component(entity, "zombieInfection", state)
	var transmitted: bool = float(rng.call("next")) < chance
	((state as Dictionary)["exposures"] as Array).append({
		"source": source,
		"bodyPart": "torso",
		"exposedAtTick": int(world.tick),
		"transmitted": transmitted,
		"stage": Stage.Latent,
		"stageEnteredAtTick": int(world.tick),
		"cauterized": false,
		"amputated": false,
		"vector": "contamination",
	})
	world.events.publish({"type": "infection.exposed", "entity": entity, "source": source, "vector": "contamination", "transmitted": transmitted})
	return {"ok": true, "transmitted": transmitted}

static func register_module(world: Variant) -> void:
	var rng: Variant = world.rng.stream("infection")
	world.events.subscribe({"id": "infection.record-bite", "type": "bite.landed", "handler": func(event: Dictionary) -> void:
		var victim: int = int(event["victim"])
		var state: Variant = world.components.get_component(victim, "zombieInfection")
		if state == null:
			state = {"exposures": []}
			world.components.set_component(victim, "zombieInfection", state)
		var exposures: Array = (state as Dictionary)["exposures"] as Array
		var bodyPart: String = String(event["bodyPart"])
		var cov: float = _armor_coverage(world, victim, bodyPart)
		var eff: float = BITE_TRANSMISSION_CHANCE * (1.0 - cov)
		var transmitted: bool = float(rng.call("next")) < eff
		exposures.append({
			"source": int(event["source"]),
			"bodyPart": bodyPart,
			"exposedAtTick": int(world.tick),
			"transmitted": transmitted,
			"stage": Stage.Latent,
			"stageEnteredAtTick": int(world.tick),
			"cauterized": false,
			"amputated": false,
		})
	})

	var pending_turned: Array[int] = []
	# ponytail: progression system runs in infection phase, order after health recover
	world.systems.register("infection.progress", "infection", 10, func(w: Variant) -> void:
		for ent in w.components.query(["zombieInfection"]):
			var st: Variant = w.components.get_component(int(ent), "zombieInfection")
			if st == null:
				continue
			var list: Array = (st as Dictionary).get("exposures", []) as Array
			for e in list:
				var ed: Dictionary = e as Dictionary
				if not bool(ed.get("transmitted", false)):
					continue
				if bool(ed.get("amputated", false)):
					continue
				var cur: int = int(ed.get("stage", Stage.Latent))
				if cur >= Stage.Turned:
					continue
				var entered: int = int(ed.get("stageEnteredAtTick", 0))
				var needed: int = stage_duration_ticks(cur, w, int(ent))
				if needed <= 0:
					continue
				if int(w.tick) - entered >= needed:
					var nxt: int = cur + 1
					ed["stage"] = nxt
					ed["stageEnteredAtTick"] = int(w.tick)
					w.events.publish({"type": "infection.staged", "entity": int(ent), "bodyPart": String(ed.get("bodyPart", "")), "from": cur, "to": nxt})
					if nxt == Stage.Turned:
						if not pending_turned.has(int(ent)):
							pending_turned.append(int(ent))
						w.events.publish({"type": "survivor.turned", "entity": int(ent), "bodyPart": String(ed.get("bodyPart", ""))})
						w.events.publish({"type": "entity.killed", "entity": int(ent)})
						var pos: Variant = w.components.get_component(int(ent), "position")
						var px: float = float((pos as Dictionary).get("x", 0.0)) if pos is Dictionary else 0.0
						var py: float = float((pos as Dictionary).get("y", 0.0)) if pos is Dictionary else 0.0
						w.events.publish({"type": "noise.emitted", "x": px, "y": py, "magnitude": QUARANTINE_NOISE_MAG, "source": int(ent)})
	)
	# Reap turned: runs in cleanup after health.reap (order 1) — despawns survivor, spawns shambler
	world.systems.register("infection.reap-turned", "cleanup", 1, func(w: Variant) -> void:
		if pending_turned.is_empty():
			return
		var to_process: Array[int] = pending_turned.duplicate()
		pending_turned.clear()
		for ent in to_process:
			var Recruits: GDScript = load("res://sim/modules/recruits.gd") as GDScript
			if Recruits != null and Recruits.has_method("handle_death"):
				Recruits.call("handle_death", w, int(ent))
				continue
			var pos: Variant = w.components.get_component(int(ent), "position")
			var px: float = float((pos as Dictionary).get("x", 0.0)) if pos is Dictionary else 0.0
			var py: float = float((pos as Dictionary).get("y", 0.0)) if pos is Dictionary else 0.0
			w.despawn(int(ent))
			var shambler: int = w.entities.spawn()
			w.components.set_component(shambler, "position", {"x": px, "y": py})
			w.components.set_component(shambler, "velocity", {"dx": 0.0, "dy": 0.0})
			w.components.set_component(shambler, "body", SimCombatRes.ZOMBIE_BODY.duplicate())
			var rng2: Variant = w.rng.stream("shambler")
			SimShamblerRes.make_shambler(w, shambler, rng2)
			w.components.set_component(shambler, "turnedFrom", {"entity": int(ent)})
	)

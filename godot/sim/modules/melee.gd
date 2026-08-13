class_name SimMelee
extends RefCounted

const SimCombat = preload("res://sim/combat.gd")
const SimHealth = preload("res://sim/modules/health.gd")

enum SwingState { Idle = 0, WindUp = 1, Recover = 2 }

const MELEE_REACH_FUDGE: float = 0.35


static func make_melee_armed(world: Variant, entity: int, weapon: Dictionary = {}) -> void:
	var profile: Dictionary = weapon if not weapon.is_empty() else SimCombat.ZOMBIE_BODY
	# Default to bat if no profile given
	if not weapon.has("reachMetres"):
		profile = {"reachMetres": 1.4, "weight": 1.2, "damage": 11, "staggerTicks": 16, "speed": 1.0, "recovery": 1.0, "stamina": 1.0}
	else:
		if not profile.has("speed"):
			profile["speed"] = 1.0
		if not profile.has("recovery"):
			profile["recovery"] = 1.0
		if not profile.has("stamina"):
			profile["stamina"] = 1.0
	world.components.set_component(entity, "meleeWeapon", profile)
	world.components.set_component(entity, "swing", {"state": SwingState.Idle, "ticksLeft": 0})

static func _roll_body_part(rng: Variant, body: Variant) -> String:
	var roll: float = float(rng.call("next"))
	var is_survivor: bool = body != null and (body as Dictionary).has("arms")
	var parts: Array[String] = SimCombat.SURVIVOR_BODY_PARTS if is_survivor else SimCombat.BODY_PARTS
	var weights: Dictionary = SimCombat.SURVIVOR_HIT_LOCATION_WEIGHTS if is_survivor else SimCombat.HIT_LOCATION_WEIGHTS
	var cumulative: float = 0.0
	for part in parts:
		cumulative += float(weights.get(String(part), 0))
		if roll < cumulative:
			return String(part)
	return String(parts[parts.size() - 1])

static func register_module(world: Variant) -> void:
	var rng: Variant = world.rng.stream("melee")
	var candidates: Array[int] = []

	world.systems.register("melee.intake", "input", 10, func(w: Variant) -> void:
		var has_swing: bool = false
		for c in w.commands.current:
			if String((c as Dictionary).get("type", "")) == "swing":
				has_swing = true
				break
		if not has_swing:
			return
		for entity in w.components.query(["swing", "meleeWeapon", "controlled"]):
			if w.components.has_component(int(entity), "grabbed"):
				continue
			var swing: Variant = w.components.get_component(int(entity), "swing")
			if swing == null:
				continue
			var s: Dictionary = swing as Dictionary
			if int(s["state"]) != SwingState.Idle:
				continue
			if not _capable_of(w, int(entity), "canSwing"):
				continue
			var weapon: Variant = w.components.get_component(int(entity), "meleeWeapon")
			if weapon == null:
				continue
			var we: Dictionary = weapon as Dictionary
			var cost: int = SimCombat.swing_stamina(float(we.get("weight", 1.0)), float(we.get("stamina", 1.0)))
			var stamina: Variant = w.components.get_component(int(entity), "stamina")
			if stamina != null and int((stamina as Dictionary)["current"]) < cost:
				continue
			s["state"] = SwingState.WindUp
			s["ticksLeft"] = SimCombat.windup_ticks(float(we.get("weight", 1.0)), float(we.get("speed", 1.0)))
			w.events.publish({"type": "stamina.spent", "entity": int(entity), "amount": cost})
	)

	world.systems.register("melee.resolve", "combat", 0, func(w: Variant) -> void:
		for entity in w.components.query(["swing", "meleeWeapon", "position", "facing"]):
			var swing: Variant = w.components.get_component(int(entity), "swing")
			if swing == null:
				continue
			var s: Dictionary = swing as Dictionary
			if int(s["state"]) == SwingState.Idle:
				continue
			if int(s["state"]) == SwingState.WindUp and not _capable_of(w, int(entity), "canAim"):
				s["state"] = SwingState.Idle
				s["ticksLeft"] = 0
				continue
			s["ticksLeft"] = int(s["ticksLeft"]) - 1
			if int(s["ticksLeft"]) > 0:
				continue
			var weapon: Variant = w.components.get_component(int(entity), "meleeWeapon")
			if weapon == null:
				continue
			var we: Dictionary = weapon as Dictionary
			if int(s["state"]) == SwingState.Recover:
				s["state"] = SwingState.Idle
				s["ticksLeft"] = 0
				continue
			_resolve_strike(w, int(entity), we, rng, candidates)
			s["state"] = SwingState.Recover
			s["ticksLeft"] = SimCombat.recover_ticks(float(we.get("weight", 1.0)), float(we.get("recovery", 1.0)))
	)

	world.events.subscribe({"id": "melee.stagger-interrupts", "type": "entity.staggered", "handler": func(event: Dictionary) -> void:
		var swing: Variant = world.components.get_component(int(event["entity"]), "swing")
		if swing == null or int((swing as Dictionary)["state"]) != SwingState.WindUp:
			return
		(swing as Dictionary)["state"] = SwingState.Idle
		(swing as Dictionary)["ticksLeft"] = 0
	})

	world.events.subscribe({"id": "melee.grab-interrupts", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		var swing: Variant = world.components.get_component(int(event["victim"]), "swing")
		if swing == null or int((swing as Dictionary)["state"]) != SwingState.WindUp:
			return
		(swing as Dictionary)["state"] = SwingState.Idle
		(swing as Dictionary)["ticksLeft"] = 0
	})


static func _capable_of(world: Variant, entity: int, cap: String) -> bool:
	# Stance ladder gate — if no posture, allow
	var posture: Variant = world.components.get_component(entity, "posture")
	if posture == null:
		return true
	var stance: int = int((posture as Dictionary).get("current", 2))
	# crawl (0) cannot swing/aim, crouch (1) can, rest can
	if cap == "canSwing" or cap == "canAim":
		return stance != 0
	return true

static func _resolve_strike(world: Variant, attacker: int, weapon: Dictionary, rng: Variant, candidates: Array[int]) -> void:
	var from: Variant = world.components.get_component(attacker, "position")
	var facing_v: Variant = world.components.get_component(attacker, "facing")
	if from == null or facing_v == null:
		return
	var fx: float = float((from as Dictionary)["x"])
	var fy: float = float((from as Dictionary)["y"])
	var facing: float = float((facing_v as Dictionary).get("radians", 0.0))
	var facing_x: float = cos(facing)
	var facing_y: float = sin(facing)
	var reach: float = float(weapon.get("reachMetres", 1.4)) + MELEE_REACH_FUDGE
	var limit_sq: float = reach * reach

	# Walk all bodies — candidates via spatial would be faster but we scan for correctness
	var best: Variant = null
	var best_dist: float = 1e9
	var best_pos: Variant = null
	for entity in world.components.query(["body", "position"]):
		if int(entity) == attacker:
			continue
		var body: Variant = world.components.get_component(int(entity), "body")
		if body == null or not SimHealth.is_alive(body as Dictionary):
			continue
		var there: Variant = world.components.get_component(int(entity), "position")
		if there == null:
			continue
		var dx: float = float((there as Dictionary)["x"]) - fx
		var dy: float = float((there as Dictionary)["y"]) - fy
		var dist_sq: float = dx * dx + dy * dy
		if dist_sq > limit_sq:
			continue
		if dist_sq > 0:
			var cosine: float = (dx * facing_x + dy * facing_y) / sqrt(dist_sq)
			if cosine < float(SimCombat.COS_SWING_HALF_ANGLE):
				continue
		if dist_sq < best_dist:
			best_dist = dist_sq
			best = int(entity)
			best_pos = there

	if best == null:
		return

	var target: int = int(best)
	var body_part: String = _roll_body_part(rng, world.components.get_component(target, "body"))
	var damage: float = float(weapon.get("damage", 11)) * (3.0 if body_part == "head" else 1.0)

	world.events.publish({"type": "noise.emitted", "x": fx, "y": fy, "magnitude": int(SimCombat.MELEE_CONNECT_NOISE), "source": attacker})
	world.events.publish({"type": "attack.connected", "attacker": attacker, "target": target, "bodyPart": body_part, "damage": damage})
	world.events.publish({"type": "entity.staggered", "entity": target, "ticks": int(weapon.get("staggerTicks", 8))})

class_name SimHealth
extends RefCounted

const SimCombat = preload("res://sim/combat.gd")

const BITE_PRESENTS_AS_SCRATCH_CHANCE: float = 0.3

const CRIPPLED_SOURCE: String = "injury.crippled"
const HURT_BELOW: float = 1.0
const BADLY_HURT_BELOW: float = 0.5

enum PartState { Unhurt = 0, Hurt = 1, BadlyHurt = 2, Unusable = 3 }

static func max_of(body: Dictionary, part: String) -> Variant:
	for table in [SimCombat.SURVIVOR_BODY, SimCombat.ZOMBIE_BODY]:
		var t: Dictionary = table as Dictionary
		var matches: bool = true
		for k in t.keys():
			if not body.has(k):
				matches = false
				break
		if matches:
			if t.has(part):
				return int(t[part])
			return null
	return null

static func part_state(body: Dictionary, part: String) -> Variant:
	if not body.has(part):
		return null
	var current: Variant = body[part]
	if current == null:
		return null
	var cur: float = float(current)
	if cur <= 0.0:
		return PartState.Unusable
	var maxv: Variant = max_of(body, part)
	if maxv == null or int(maxv) <= 0:
		return null
	var fraction: float = cur / float(int(maxv))
	if fraction < BADLY_HURT_BELOW:
		return PartState.BadlyHurt
	if fraction < HURT_BELOW:
		return PartState.Hurt
	return PartState.Unhurt

static func is_alive(body: Dictionary) -> bool:
	return int(body.get("head", 0)) > 0

# The one sentinel for "is this a survivor body (sided limbs) or a zombie body (aggregate
# legs, no arms)". melee.gd and the bite handler below used to each spell out
# `body.has("arms")` themselves; one helper means the survivor schema only has one place
# left to update if it changes again.
static func is_survivor_body(body: Variant) -> bool:
	return body is Dictionary and (body as Dictionary).has("arm_left")

static func is_crawling(body: Dictionary) -> bool:
	if body.has("legs"):
		return int(body["legs"]) <= 0
	# A survivor limps on one ruined leg -- that is the permanent-limp consequence docs/05
	# describes -- and only crawls once neither leg still works.
	if body.has("leg_left") and body.has("leg_right"):
		return int(body["leg_left"]) <= 0 and int(body["leg_right"]) <= 0
	return false

static func make_body(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "body", SimCombat.ZOMBIE_BODY.duplicate())

static func make_survivor_body(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "body", SimCombat.SURVIVOR_BODY.duplicate())
	world.components.set_component(entity, "injuries", {"wounds": [], "bloodLoss": 0.0})

static func make_stamina(world: Variant, entity: int, maxv: int = 100) -> void:
	# "current" is a float. It used to be an int, and health.recover's per-tick regen
	# (SimCombat.STAMINA_PER_TICK = 0.6) truncated to zero against an int pool every tick --
	# `int(94 + 0.6) == 94` -- so stamina never actually regenerated. "max" stays an int; it
	# is always a whole number and every reader already casts it on the way in.
	world.components.set_component(entity, "stamina", {"current": float(maxv), "max": maxv, "ticksUntilRecovery": 0})

static func register_module(world: Variant) -> void:
	var killed: Array[int] = []
	var injury_rng: Variant = world.rng.stream("injury")
	# wounds.gd preloads this file for max_of/finish_death, so this side loads it
	# dynamically -- the same cyclic-preload workaround finish_death below already uses for
	# recruits.gd.
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	var damage_part: Callable = func(target: int, source: int, named_part: String, amount: float) -> Variant:
		var body: Variant = world.components.get_component(target, "body")
		if body == null or not is_alive(body as Dictionary):
			return null
		var b: Dictionary = body as Dictionary
		if not b.has(named_part):
			return null
		var before: float = float(b[named_part])
		if before <= 0.0:
			return null
		var taken: float = amount
		if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
			taken *= float(world.modifiers.call("resolve", "damage_taken", target))
		b[named_part] = maxf(0.0, before - taken)
		if named_part == "head" and int(b["head"]) <= 0:
			killed.append(target)
			var pos: Variant = world.components.get_component(target, "position")
			var zt: Variant = world.components.get_component(target, "zombieType")
			world.events.publish({
				"type": "entity.killed",
				"entity": target,
				"killer": source,
				"x": float((pos as Dictionary)["x"]) if pos is Dictionary else 0.0,
				"y": float((pos as Dictionary)["y"]) if pos is Dictionary else 0.0,
				"zombieType": String((zt as Dictionary).get("id", "")) if zt is Dictionary else "",
			})
		return {"body": b, "part": named_part, "before": before, "after": float(b[named_part])}

	world.events.subscribe({"id": "health.take-damage", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		var result: Variant = damage_part.call(int(event["target"]), int(event["attacker"]), String(event["bodyPart"]), float(event["damage"]))
		if result == null:
			return
		var r: Dictionary = result as Dictionary
		if not is_alive(r["body"] as Dictionary):
			return
		# "legs" (zombie) or "leg_left"/"leg_right" (survivor) -- either way, only worth an
		# event once is_crawling says the survivor actually can no longer stand. A survivor
		# who lost one leg limps; that is the permanent-limp consequence, not this one.
		var hit_part: String = String(r["part"])
		if (hit_part == "legs" or hit_part.begins_with("leg_")) and is_crawling(r["body"] as Dictionary):
			world.events.publish({"type": "injury.sustained", "entity": int(event["target"]), "injury": "crippled", "bodyPart": hit_part})
		# A hit that removed no integrity records no wound -- a zero-damage (or fully
		# absorbed) hit still returns a non-null result above, since "before" was positive.
		if is_survivor_body(r["body"]) and float(r["after"]) != float(r["before"]) and Wounds != null:
			Wounds.call("append_wound", world, int(event["target"]), "cut", hit_part, int(event["attacker"]), float(event["damage"]))
	})

	world.events.subscribe({"id": "health.take-bite", "type": "bite.landed", "handler": func(event: Dictionary) -> void:
		var result: Variant = damage_part.call(int(event["victim"]), int(event["source"]), String(event["bodyPart"]), float(event["damage"]))
		if result == null:
			return
		var r: Dictionary = result as Dictionary
		if not is_survivor_body(r["body"]):
			return
		if float(r["after"]) == float(r["before"]) or Wounds == null:
			return
		var presentation: String = "bite" if float(injury_rng.call("next")) >= BITE_PRESENTS_AS_SCRATCH_CHANCE else "scratch"
		Wounds.call("append_wound", world, int(event["victim"]), "bite", String(r["part"]), int(event["source"]), float(event["damage"]), presentation)
		world.events.publish({"type": "injury.sustained", "entity": int(event["victim"]), "injury": "bite", "bodyPart": String(r["part"])})
	})

	world.events.subscribe({"id": "health.spend-stamina", "type": "stamina.spent", "handler": func(event: Dictionary) -> void:
		var s: Variant = world.components.get_component(int(event["entity"]), "stamina")
		if s == null:
			return
		var st: Dictionary = s as Dictionary
		st["current"] = maxf(0.0, float(st["current"]) - float(event["amount"]))
		st["ticksUntilRecovery"] = int(SimCombat.STAMINA_RECOVERY_DELAY_TICKS)
	})

	world.systems.register("health.recover", "health", 0, func(w: Variant) -> void:
		for entity in w.components.query(["stamina"]):
			var s: Variant = w.components.get_component(int(entity), "stamina")
			if s == null:
				continue
			var st: Dictionary = s as Dictionary
			if int(st["ticksUntilRecovery"]) > 0:
				st["ticksUntilRecovery"] = int(st["ticksUntilRecovery"]) - 1
				continue
			if float(st["current"]) < float(st["max"]):
				# stamina_recovery is the modifier inventory.gd:512 writes from encumbrance --
				# it used to resolve to nothing here, the same class of dead modifier HANDOFF
				# already records for move_speed. Guarded the way every other resolve() call
				# in this file is guarded, for a world built without a modifiers object.
				var regen: float = float(SimCombat.STAMINA_PER_TICK)
				if w.modifiers != null and (w.modifiers as Object).has_method("resolve"):
					regen *= float(w.modifiers.call("resolve", "stamina_recovery", int(entity)))
				st["current"] = minf(float(st["max"]), float(st["current"]) + regen)
	)

	world.systems.register("health.reap", "cleanup", 0, func(w: Variant) -> void:
		if killed.is_empty():
			return
		for entity in killed:
			finish_death(w, int(entity))
		killed.clear()
	)


static func finish_death(world: Variant, entity: int) -> void:
	var Recruits: GDScript = load("res://sim/modules/recruits.gd") as GDScript
	if Recruits != null:
		Recruits.call("handle_death", world, entity)
		return
	world.despawn(entity)

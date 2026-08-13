class_name SimHealth
extends RefCounted

const SimCombat = preload("res://sim/combat.gd")

const BodyParts: Array[String] = ["head", "torso", "legs"]
const SurvivorBodyParts: Array[String] = ["head", "torso", "arms", "hands", "legs", "feet"]

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

static func is_crawling(body: Dictionary) -> bool:
	return body.has("legs") and int(body["legs"]) <= 0

static func make_body(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "body", SimCombat.ZOMBIE_BODY.duplicate())

static func make_survivor_body(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "body", SimCombat.SURVIVOR_BODY.duplicate())
	world.components.set_component(entity, "injuries", {"wounds": []})

static func make_stamina(world: Variant, entity: int, maxv: int = 100) -> void:
	world.components.set_component(entity, "stamina", {"current": maxv, "max": maxv, "ticksUntilRecovery": 0})

static func register_module(world: Variant) -> void:
	var killed: Array[int] = []
	var injury_rng: Variant = world.rng.stream("injury")
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
		b[named_part] = maxf(0.0, before - amount)
		if named_part == "head" and int(b["head"]) <= 0:
			killed.append(target)
			world.events.publish({"type": "entity.killed", "entity": target, "killer": source})
		return {"body": b, "part": named_part, "before": before}

	world.events.subscribe({"id": "health.take-damage", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		var result: Variant = damage_part.call(int(event["target"]), int(event["attacker"]), String(event["bodyPart"]), float(event["damage"]))
		if result == null:
			return
		var r: Dictionary = result as Dictionary
		if not is_alive(r["body"] as Dictionary):
			return
		if String(r["part"]) == "legs" and is_crawling(r["body"] as Dictionary):
			world.events.publish({"type": "injury.sustained", "entity": int(event["target"]), "injury": "crippled", "bodyPart": "legs"})
	})

	world.events.subscribe({"id": "health.take-bite", "type": "bite.landed", "handler": func(event: Dictionary) -> void:
		var result: Variant = damage_part.call(int(event["victim"]), int(event["source"]), String(event["bodyPart"]), float(event["damage"]))
		if result == null:
			return
		var r: Dictionary = result as Dictionary
		if not (r["body"] as Dictionary).has("arms"):
			return
		var inj: Variant = world.components.get_component(int(event["victim"]), "injuries")
		if inj == null:
			inj = {"wounds": []}
			world.components.set_component(int(event["victim"]), "injuries", inj)
		var wounds: Array = (inj as Dictionary)["wounds"] as Array
		var presentation: String = "bite" if float(injury_rng.call("next")) >= BITE_PRESENTS_AS_SCRATCH_CHANCE else "scratch"
		wounds.append({"kind": "bite", "presentation": presentation, "bodyPart": String(r["part"]), "source": int(event["source"]), "sustainedAtTick": int(world.tick)})
		world.events.publish({"type": "injury.sustained", "entity": int(event["victim"]), "injury": "bite", "bodyPart": String(r["part"])})
	})

	world.events.subscribe({"id": "health.spend-stamina", "type": "stamina.spent", "handler": func(event: Dictionary) -> void:
		var s: Variant = world.components.get_component(int(event["entity"]), "stamina")
		if s == null:
			return
		var st: Dictionary = s as Dictionary
		st["current"] = maxi(0, int(st["current"]) - int(event["amount"]))
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
			if int(st["current"]) < int(st["max"]):
				var nxt: float = float(st["current"]) + float(SimCombat.STAMINA_PER_TICK)
				st["current"] = mini(int(st["max"]), int(nxt))
	)

	world.systems.register("health.reap", "cleanup", 0, func(w: Variant) -> void:
		if killed.is_empty():
			return
		for entity in killed:
			w.despawn(int(entity))
		killed.clear()
	)

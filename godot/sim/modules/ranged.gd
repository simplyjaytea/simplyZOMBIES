class_name SimRanged
extends RefCounted

# raise → steady → fire → recover → reload. Interruptible like melee windup. Ticket 04.
# Cone is the hit test — no displayed chance. No aim assist.

const SimCombat = preload("res://sim/combat.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimLightMod = preload("res://sim/modules/light.gd")

enum FireState { Idle = 0, Raise = 1, Steady = 2, Recover = 3, Reload = 4 }

const RAISE_TICKS: int = 8
const STEADY_TICKS: int = 4
const RECOVER_TICKS: int = 8
const FLASH_TICKS: int = 4
const WIDE_HALF: float = 0.55
const TIGHT_HALF: float = 0.18
const STREAM: String = "ranged"


static func make_ranged_armed(world: Variant, entity: int, profile: Dictionary) -> void:
	var p: Dictionary = profile.duplicate()
	if not p.has("mag"):
		p["mag"] = int(p.get("magSize", 0))
	p["state"] = FireState.Idle
	p["ticksLeft"] = 0
	p["flashTicks"] = 0
	world.components.set_component(entity, "rangedWeapon", p)


static func register_module(world: Variant) -> void:
	var rng: Variant = world.rng.stream(STREAM)

	world.events.subscribe({"id": "ranged.equip-weapon", "type": "item.equipped", "handler": func(event: Dictionary) -> void:
		var profile: Variant = SimItemsRes.ranged_profile_of(world, int(event["item"]))
		if profile == null:
			return
		make_ranged_armed(world, int(event["entity"]), profile as Dictionary)
	})
	world.events.subscribe({"id": "ranged.unequip-weapon", "type": "item.unequipped", "handler": func(event: Dictionary) -> void:
		if SimItemsRes.ranged_profile_of(world, int(event["item"])) == null:
			return
		world.components.remove(int(event["entity"]), "rangedWeapon")
	})
	world.events.subscribe({"id": "ranged.stagger-interrupts", "type": "entity.staggered", "handler": func(event: Dictionary) -> void:
		_abandon_aim(world, int(event["entity"]))
	})
	world.events.subscribe({"id": "ranged.grab-interrupts", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		_abandon_aim(world, int(event["victim"]))
	})

	world.systems.register("ranged.intake", "input", 11, func(w: Variant) -> void:
		var fire: bool = false
		var reload: bool = false
		for c in w.commands.current:
			var t: String = String((c as Dictionary).get("type", ""))
			if t == "fire":
				fire = true
			elif t == "reload":
				reload = true
		if not fire and not reload:
			return
		for entity in w.components.query(["rangedWeapon", "controlled"]):
			if w.components.has_component(int(entity), "grabbed"):
				continue
			var rw: Variant = w.components.get_component(int(entity), "rangedWeapon")
			if rw == null:
				continue
			var r: Dictionary = rw as Dictionary
			if int(r["state"]) != FireState.Idle:
				continue
			if not _capable_of(w, int(entity)):
				continue
			if reload or (fire and int(r.get("magSize", 0)) > 0 and int(r.get("mag", 0)) <= 0):
				if not _begin_reload(w, int(entity), r):
					continue
				continue
			if not fire:
				continue
			if String(r.get("ammo", "")) != "" and not _has_ammo(w, int(entity), String(r["ammo"])):
				continue
			r["state"] = FireState.Raise
			r["ticksLeft"] = RAISE_TICKS
	)

	world.systems.register("ranged.resolve", "combat", 1, func(w: Variant) -> void:
		for entity in w.components.query(["rangedWeapon", "position", "facing"]):
			var rw: Variant = w.components.get_component(int(entity), "rangedWeapon")
			if rw == null:
				continue
			var r: Dictionary = rw as Dictionary
			if int(r.get("flashTicks", 0)) > 0:
				r["flashTicks"] = int(r["flashTicks"]) - 1
				if int(r["flashTicks"]) <= 0 and float(r.get("flash", 0)) > 0.0:
					var src: Variant = w.components.get_component(int(entity), "light_source")
					if src is Dictionary and is_equal_approx(float((src as Dictionary).get("magnitude", 0)), float(r["flash"])):
						w.components.remove(int(entity), "light_source")
			if int(r["state"]) == FireState.Idle:
				continue
			if (int(r["state"]) == FireState.Raise or int(r["state"]) == FireState.Steady) and not _capable_of(w, int(entity)):
				r["state"] = FireState.Idle
				r["ticksLeft"] = 0
				continue
			r["ticksLeft"] = int(r["ticksLeft"]) - 1
			if int(r["ticksLeft"]) > 0:
				continue
			match int(r["state"]):
				FireState.Raise:
					r["state"] = FireState.Steady
					r["ticksLeft"] = STEADY_TICKS
				FireState.Steady:
					_fire_shot(w, int(entity), r, rng)
					r["state"] = FireState.Recover
					r["ticksLeft"] = RECOVER_TICKS
				FireState.Recover:
					if int(r.get("magSize", 0)) > 0 and int(r.get("mag", 0)) <= 0:
						if _begin_reload(w, int(entity), r):
							pass
						else:
							r["state"] = FireState.Idle
							r["ticksLeft"] = 0
					elif int(r.get("magSize", 0)) <= 0:
						# Bow: nock is the reload window after every shot.
						if _begin_reload(w, int(entity), r):
							pass
						else:
							r["state"] = FireState.Idle
							r["ticksLeft"] = 0
					else:
						r["state"] = FireState.Idle
						r["ticksLeft"] = 0
				FireState.Reload:
					if int(r.get("magSize", 0)) > 0:
						r["mag"] = int(r["magSize"])
					r["state"] = FireState.Idle
					r["ticksLeft"] = 0
	)


static func _begin_reload(world: Variant, entity: int, r: Dictionary) -> bool:
	if String(r.get("ammo", "")) != "" and int(r.get("magSize", 0)) > 0:
		if not _has_ammo(world, entity, String(r["ammo"])):
			return false
	r["state"] = FireState.Reload
	r["ticksLeft"] = maxi(1, int(r.get("reloadTicks", 24)))
	return true


static func _capable_of(world: Variant, entity: int) -> bool:
	var posture: Variant = world.components.get_component(entity, "posture")
	if posture == null:
		return true
	return int((posture as Dictionary).get("current", 2)) != 0


static func _abandon_aim(world: Variant, entity: int) -> void:
	var rw: Variant = world.components.get_component(entity, "rangedWeapon")
	if rw == null:
		return
	var s: int = int((rw as Dictionary)["state"])
	if s == FireState.Raise or s == FireState.Steady:
		(rw as Dictionary)["state"] = FireState.Idle
		(rw as Dictionary)["ticksLeft"] = 0


static func _has_ammo(world: Variant, actor: int, ammo_id: String) -> bool:
	for item in SimInventoryRes.carried_items(world, actor) as Array:
		var base: Variant = SimItemsRes.item_base_of(world, int(item))
		if base is Dictionary and String((base as Dictionary).get("id", "")) == ammo_id:
			return true
	return false


static func _consume_ammo(world: Variant, actor: int, ammo_id: String) -> bool:
	for item in SimInventoryRes.carried_items(world, actor) as Array:
		var base: Variant = SimItemsRes.item_base_of(world, int(item))
		if not (base is Dictionary and String((base as Dictionary).get("id", "")) == ammo_id):
			continue
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
		return true
	return false


static func _fire_shot(world: Variant, attacker: int, weapon: Dictionary, rng: Variant) -> void:
	if String(weapon.get("ammo", "")) != "":
		if not _consume_ammo(world, attacker, String(weapon["ammo"])):
			return
	if int(weapon.get("magSize", 0)) > 0:
		weapon["mag"] = maxi(0, int(weapon.get("mag", 0)) - 1)
	var from: Variant = world.components.get_component(attacker, "position")
	var facing_v: Variant = world.components.get_component(attacker, "facing")
	if from == null or facing_v == null:
		return
	var fx: float = float((from as Dictionary)["x"])
	var fy: float = float((from as Dictionary)["y"])
	var facing: float = float((facing_v as Dictionary).get("radians", 0.0))
	var facing_x: float = cos(facing)
	var facing_y: float = sin(facing)
	var half: float = TIGHT_HALF
	var vel: Variant = world.components.get_component(attacker, "velocity")
	if vel is Dictionary:
		var spd: float = sqrt(float((vel as Dictionary)["dx"]) ** 2.0 + float((vel as Dictionary)["dy"]) ** 2.0)
		if spd > 0.2:
			half = WIDE_HALF
	var cos_half: float = cos(half)
	var reach: float = float(weapon.get("rangeMetres", 30))
	var limit_sq: float = reach * reach
	var best: Variant = null
	var best_dist: float = 1e9
	var impact_x: float = fx + facing_x * reach
	var impact_y: float = fy + facing_y * reach
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
		if dist_sq > limit_sq or dist_sq <= 0.0:
			continue
		var cosine: float = (dx * facing_x + dy * facing_y) / sqrt(dist_sq)
		if cosine < cos_half:
			continue
		if dist_sq < best_dist:
			best_dist = dist_sq
			best = int(entity)
			impact_x = float((there as Dictionary)["x"])
			impact_y = float((there as Dictionary)["y"])
	var mag: float = float(weapon.get("noise", 4))
	world.events.publish({"type": "noise.emitted", "x": fx, "y": fy, "magnitude": mag, "source": attacker})
	if float(weapon.get("flash", 0)) > 0.0:
		weapon["flashTicks"] = FLASH_TICKS
		SimLightMod.make_light_source(world, attacker, float(weapon["flash"]))
	if best != null:
		var target: int = int(best)
		var body_part: String = "torso"
		var roll: float = float(rng.call("next"))
		if roll < 0.2:
			body_part = "head"
		var damage: float = float(weapon.get("damage", 12)) * (3.0 if body_part == "head" else 1.0)
		world.events.publish({"type": "attack.connected", "attacker": attacker, "target": target, "bodyPart": body_part, "damage": damage})
		world.events.publish({"type": "entity.staggered", "entity": target, "ticks": 8})
	if float(weapon.get("recoverable", 0.0)) > 0.0 and float(rng.call("next")) < float(weapon["recoverable"]):
		var arrow: int = SimItemsRes.spawn_item(world, String(weapon.get("ammo", "item.ammo.arrow")), {"tier": "scavenged", "count": 1})
		world.components.set_component(arrow, "position", {"x": impact_x, "y": impact_y})

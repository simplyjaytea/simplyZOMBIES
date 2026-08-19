class_name SimRanged
extends RefCounted

# raise → steady → fire → recover → reload. Interruptible like melee windup. Ticket 04.
# Cone is the hit test — no displayed chance. No aim assist.

const SimCombat = preload("res://sim/combat.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimLightMod = preload("res://sim/modules/light.gd")

enum FireState { Idle = 0, Raise = 1, Steady = 2, Recover = 3, Reload = 4, Clearing = 5 }

# docs/09: "Degraded firearms jam, and clearing a jam takes longer than a reload." Expressed as a
# multiple of the weapon's own reloadTicks rather than a flat number, so "longer than a reload"
# stays true when a weapon's reload time is retuned -- a constant would silently stop being longer
# the first time somebody gave a firearm a 90-tick reload.
const CLEAR_JAM_MULTIPLIER: float = 2.0
const MIN_CLEAR_TICKS: int = 30

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
	p["coneHalf"] = WIDE_HALF
	world.components.set_component(entity, "rangedWeapon", p)


# Felt cone half-angle (radians). Presentation draws sway from this — never a hit %.
static func cone_half(world: Variant, entity: int) -> float:
	var rw: Variant = world.components.get_component(entity, "rangedWeapon")
	if rw is Dictionary and (rw as Dictionary).has("coneHalf"):
		return float((rw as Dictionary)["coneHalf"])
	return WIDE_HALF


static func _refresh_cone(world: Variant, entity: int, r: Dictionary) -> void:
	var half: float = WIDE_HALF
	var st: int = int(r.get("state", FireState.Idle))
	if st == FireState.Raise:
		half = lerpf(WIDE_HALF, (WIDE_HALF + TIGHT_HALF) * 0.5, 1.0 - float(r.get("ticksLeft", 0)) / float(RAISE_TICKS))
	elif st == FireState.Steady:
		half = lerpf((WIDE_HALF + TIGHT_HALF) * 0.5, TIGHT_HALF, 1.0 - float(r.get("ticksLeft", 0)) / float(STEADY_TICKS))
	elif st == FireState.Idle:
		half = WIDE_HALF
	var vel: Variant = world.components.get_component(entity, "velocity")
	if vel is Dictionary:
		var spd: float = sqrt(float((vel as Dictionary)["dx"]) ** 2.0 + float((vel as Dictionary)["dy"]) ** 2.0)
		if spd > 0.2:
			half = maxf(half, WIDE_HALF)
	var stam: Variant = world.components.get_component(entity, "stamina")
	if stam is Dictionary:
		var cur: float = float((stam as Dictionary).get("current", 100))
		var mx: float = maxf(1.0, float((stam as Dictionary).get("max", 100)))
		if cur / mx < 0.35:
			half = minf(WIDE_HALF, half + 0.12)
	var body: Variant = world.components.get_component(entity, "body")
	if body is Dictionary:
		var b: Dictionary = body as Dictionary
		# The worse arm sets your steadiness -- an aim penalty is a per-limb effect, not an
		# average, so one ruined arm costs you the same as it would have before the split.
		var worst_arm: float = minf(float(b.get("arm_left", 40.0)), float(b.get("arm_right", 40.0)))
		if worst_arm < 25.0:
			half = minf(WIDE_HALF, half + 0.15)
	if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
		var acc: float = float(world.modifiers.call("resolve", "ranged_accuracy", entity))
		if acc > 0.0:
			half = clampf(half / acc, TIGHT_HALF * 0.75, WIDE_HALF)
	r["coneHalf"] = half


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
			if reload:
				try_begin_reload(w, int(entity))
			elif fire:
				try_begin_fire(w, int(entity))
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
				_refresh_cone(w, int(entity), r)
				continue
			if (int(r["state"]) == FireState.Raise or int(r["state"]) == FireState.Steady) and not _capable_of(w, int(entity)):
				r["state"] = FireState.Idle
				r["ticksLeft"] = 0
				_refresh_cone(w, int(entity), r)
				continue
			_refresh_cone(w, int(entity), r)
			r["ticksLeft"] = int(r["ticksLeft"]) - 1
			if int(r["ticksLeft"]) > 0:
				continue
			match int(r["state"]):
				FireState.Raise:
					r["state"] = FireState.Steady
					r["ticksLeft"] = STEADY_TICKS
					_refresh_cone(w, int(entity), r)
				FireState.Steady:
					# A jam is decided at the trigger, before the round is spent: the cost of a
					# jam is time and tempo, which is exactly and only what docs/09 specifies.
					# The round stays in the magazine -- it is stuck, not fired -- and comes out
					# during the clear. Spending it too would be a second cost the document does
					# not ask for, on top of an interruption that already costs more than a
					# reload.
					if _jammed(w, r, rng):
						w.events.publish({"type": "weapon.jammed", "entity": int(entity), "ticks": _clear_ticks(r)})
						r["state"] = FireState.Clearing
						r["ticksLeft"] = _clear_ticks(r)
					else:
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
				FireState.Clearing:
					# Cleared, and nothing else changed: the magazine is what it was, because the
					# stuck round was never spent. Back to Idle rather than straight to Raise, so
					# clearing a jam costs the shot you were taking and the player or the NPC has
					# to decide again -- a jam that auto-resumed would be a pause, not a jam.
					r["state"] = FireState.Idle
					r["ticksLeft"] = 0
					w.events.publish({"type": "weapon.cleared", "entity": int(entity)})
	)


# How long this weapon takes to clear, always longer than its own reload. See
# CLEAR_JAM_MULTIPLIER for why it is a multiple rather than a number.
static func _clear_ticks(weapon: Dictionary) -> int:
	return maxi(MIN_CLEAR_TICKS, int(round(float(int(weapon.get("reloadTicks", 24))) * CLEAR_JAM_MULTIPLIER)))


# Whether this trigger pull jams. Draws only when the weapon can jam at all *and* has a non-zero
# chance, so a sound firearm and a bow both cost the RNG stream nothing -- a draw taken on every
# shot regardless would make the whole ranged sequence depend on how worn the weapon happened to
# be, which is a determinism trap rather than a balance one.
static func _jammed(world: Variant, weapon: Dictionary, rng: Variant) -> bool:
	if not bool(weapon.get("jams", false)):
		return false
	var chance: float = float(weapon.get("jamChance", 0.0))
	if chance <= 0.0:
		return false
	return float(rng.call("float_range", 0.0, 1.0)) < chance


# Every precondition a shot has to pass, in one place — see the note on SimMelee.try_begin_swing.
# An empty magazine turns a fire into a reload, which is the behaviour the key press already had
# and is now the behaviour an NPC inherits rather than reimplements.
static func try_begin_fire(world: Variant, entity: int) -> bool:
	var rw: Variant = _idle_weapon(world, entity)
	if not rw is Dictionary:
		return false
	var r: Dictionary = rw as Dictionary
	if int(r.get("magSize", 0)) > 0 and int(r.get("mag", 0)) <= 0:
		return _begin_reload(world, entity, r)
	if String(r.get("ammo", "")) != "" and not _has_ammo(world, entity, String(r["ammo"])):
		return false
	r["state"] = FireState.Raise
	r["ticksLeft"] = RAISE_TICKS
	return true


static func try_begin_reload(world: Variant, entity: int) -> bool:
	var rw: Variant = _idle_weapon(world, entity)
	if not rw is Dictionary:
		return false
	return _begin_reload(world, entity, rw as Dictionary)


# Armed, idle, ungrabbed, untreated and capable — the gate a fire and a reload share.
static func _idle_weapon(world: Variant, entity: int) -> Variant:
	if world.components.has_component(entity, "grabbed"):
		return null
	# Same reason melee.try_begin_swing refuses: holding a dressing, or being held still for
	# one, is not a posture you can shoot from.
	if world.components.has_component(entity, "treatment") or world.components.has_component(entity, "treated"):
		return null
	var rw: Variant = world.components.get_component(entity, "rangedWeapon")
	if not rw is Dictionary:
		return null
	if int((rw as Dictionary)["state"]) != FireState.Idle:
		return null
	if not _capable_of(world, entity):
		return null
	return rw


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
	_refresh_cone(world, attacker, weapon)
	var half: float = float(weapon.get("coneHalf", TIGHT_HALF))
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

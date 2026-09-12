class_name SimHealth
extends RefCounted

const SimCombat = preload("res://sim/combat.gd")

const BITE_PRESENTS_AS_SCRATCH_CHANCE: float = 0.3

const HURT_BELOW: float = 1.0
const BADLY_HURT_BELOW: float = 0.5

# Body damage slows and staggers the dead (docs/14's damage model; the owner's decision 7).
# The chance a torso hit on a zombie knocks it down, by the torso's *resulting* state --
# Unhurt / Hurt / BadlyHurt / Unusable -- rolled on its own stream so the roll moves no other
# draw, and published as `entity.staggered` for TORSO_STAGGER_TICKS, which `shambler.stagger`
# takes as the max with the weapon's own. The head stays the only kill. The speed half lives
# in `SimShambler._speed_of` (`_torso_factor`). `check_m2_lethality.gd` TORSO-STAGGER,
# TORSO-SLOW, HEAD-ONLY.
const TORSO_STAGGER_CHANCE: Array[float] = [0.0, 0.35, 0.6, 1.0]
const TORSO_STAGGER_TICKS: int = 20
const TORSO_STAGGER_STREAM: String = "bodyStagger"

# Armour stops blows -- the owner's decision of 2026-09-12. Until it, an `armor` block reduced
# bite *transmission* (infection.gd) and how far a wound escalated (wounds.gd) and took nothing
# whatever off the hit itself: a riot vest made you less likely to be **infected** and did nothing
# about being **hit**.
#
# **The curve is not a new number.** `SimWounds.severity_for` has softened escalation by exactly
# `1 - 0.5 * coverage` since wounds landed. This promotes that same curve one step upstream, onto
# the integrity, and `severity_for` drops its own copy -- so the damage that reaches the body and
# the wound it opens are now one piece of arithmetic applied once instead of two applied to
# different numbers, and no shipped severity band moves. Full coverage stops half a blow; nothing
# shipped declares full coverage, so a plate is a reason to live rather than a reason to stop
# being afraid, which is docs/01 clause 4 spent as balance rather than as a rule.
#
# Nothing about this is visible as a figure. The player learns it the way they learn everything
# else in this game -- by being hit and still standing -- and `sim/condition.gd` says only
# `armored: true`, which is a boolean and stays one.
const ARMOR_STOPS_AT_FULL_COVERAGE: float = 0.5

enum PartState { Unhurt = 0, Hurt = 1, BadlyHurt = 2, Unusable = 3 }


# Loaded on demand rather than preloaded: infection.gd preloads shambler.gd, which reaches back
# here, and a preload cycle is a parse error. The same workaround `register_module` already uses
# for wounds.gd, and `light.gd`'s `_Attachments()` for this file's opposite number.
static func _Infection() -> GDScript:
	return load("res://sim/modules/infection.gd") as GDScript


## What fraction of a blow to this part gets through what the target is wearing: 1.0 for a bare
## part, 0.5 for a fully covered one. Read in exactly one place -- `damage_part` below, which is
## the one function that moves integrity -- and asserted as a pure predicate by
## check_m2_armor.gd's FACTOR lane.
static func armor_damage_factor(world: Variant, target: int, part: String) -> float:
	var cov: float = clampf(float(_Infection().call("armor_coverage_of", world, target, part)), 0.0, 1.0)
	return 1.0 - ARMOR_STOPS_AT_FULL_COVERAGE * cov

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

# `part_state` against the body's *own* maxima where the entity carries them. `max_of` matches
# a body to one of two shared tables by key set, so every zombie type's torso was judged
# against the shambler's 60 -- the screamer's authored 40 read Hurt from the moment it spawned.
# `SimRoster.spawn_zombie` stores the type's body as `bodyMax`; a body without one (a fixture,
# a survivor) falls back to the table. The torso slice's reader.
static func part_state_of(world: Variant, entity: int, part: String) -> Variant:
	var body: Variant = world.components.get_component(entity, "body")
	if not body is Dictionary:
		return null
	var maxima: Variant = world.components.get_component(entity, "bodyMax")
	if maxima is Dictionary and (maxima as Dictionary).has(part):
		var b: Dictionary = body as Dictionary
		if not b.has(part) or b[part] == null:
			return null
		var cur: float = float(b[part])
		if cur <= 0.0:
			return PartState.Unusable
		var maxv: float = float((maxima as Dictionary)[part])
		if maxv <= 0.0:
			return null
		var fraction: float = cur / maxv
		if fraction < BADLY_HURT_BELOW:
			return PartState.BadlyHurt
		if fraction < HURT_BELOW:
			return PartState.Hurt
		return PartState.Unhurt
	return part_state(body as Dictionary, part)


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
		# **The one place armour stops damage.** Every path that hurts a body -- a survivor's
		# swing (melee.gd), a shot (ranged.gd), a shambler's swipe and its bite (shambler.gd) --
		# arrives at this closure through `attack.connected` or `bite.landed`, so mitigation
		# applied at each publisher would be the same rule written four times and forgotten in
		# the fifth. It sits beside the `damage_taken` modifier because they answer the same
		# question about the same number, and multiplication does not care which goes first.
		taken *= armor_damage_factor(world, target, named_part)
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
		# `taken` rather than `before - after`, which is the same number until the part runs out
		# and then silently is not: a blow that destroys a hand is a deep wound whatever was left
		# of the hand to remove. Both wound paths band off this.
		return {"body": b, "part": named_part, "before": before, "after": float(b[named_part]), "taken": taken}

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
		# A torso hit on one of the dead may put it down for a moment, by how much torso is left.
		if hit_part == "torso" and world.components.has_component(int(event["target"]), "shambler"):
			var state: Variant = part_state_of(world, int(event["target"]), "torso")
			if state != null:
				var chance: float = float(TORSO_STAGGER_CHANCE[int(state)])
				if chance > 0.0 and float(world.rng.stream(TORSO_STAGGER_STREAM).call("next")) < chance:
					world.events.publish({"type": "entity.staggered", "entity": int(event["target"]), "ticks": TORSO_STAGGER_TICKS})
		# A hit that removed no integrity records no wound -- a zero-damage (or fully
		# absorbed) hit still returns a non-null result above, since "before" was positive.
		#
		# `r["taken"]`, not the event's own damage: what opens a wound is what got through the
		# vest, not what was swung. Before mitigation those were the same number and
		# `severity_for` carried its own armour term to make up the difference; it does not any
		# more, so passing the raw figure here would quietly un-armour every wound in the game.
		if is_survivor_body(r["body"]) and float(r["after"]) != float(r["before"]) and Wounds != null:
			var cut: Variant = Wounds.call("append_wound", world, int(event["target"]), "cut", hit_part, int(event["attacker"]), float(r["taken"]))
			# docs/05's "heavy hits" and "head impact": a hit hard enough to be a deep wound may
			# also break the bone under it or rattle the skull. The severity band is the gate, so
			# an ordinary scratch never rolls for either.
			if cut is Dictionary:
				Wounds.call("roll_impact_injury", world, int(event["target"]), hit_part, int((cut as Dictionary).get("severity", 0)), int(event["attacker"]))
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
		# The same `r["taken"]` as the cut path, for the same reason: a bite that had to get
		# through a leather jacket first opens the wound the jacket left it room to open.
		Wounds.call("append_wound", world, int(event["victim"]), "bite", String(r["part"]), int(event["source"]), float(r["taken"]), presentation)
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
			# A held body breathes. The recovery delay is there so that exertion has a cost you
			# feel -- swing, and you cannot immediately swing again -- and inside a grapple it did
			# something else entirely: every escape attempt re-armed the delay, so a survivor who
			# had spent their tank on failed escapes could never afford another one, and a hold
			# became a hold with no exit. Measured on the balance harness with grabs forced on,
			# the colonies that died spent 38-49% of their held ticks below STRUGGLE_STAMINA.
			#
			# So while `grabbed`, the delay still counts down -- it is not skipped, and it still
			# governs what happens the moment they are free -- but it no longer suppresses regen.
			# The pacing that replaces it is the refusal itself: SimShambler._arm_struggle charges
			# nothing when the tank is short, so a spent survivor waits out 25 ticks of regen
			# before the next attempt rather than never getting one.
			var held: bool = w.components.has_component(int(entity), "grabbed")
			if int(st["ticksUntilRecovery"]) > 0:
				st["ticksUntilRecovery"] = int(st["ticksUntilRecovery"]) - 1
				if not held:
					continue
			if float(st["current"]) < float(st["max"]):
				# stamina_recovery is the modifier inventory.gd:512 writes from encumbrance --
				# it used to resolve to nothing here, the same class of dead modifier already
				# on record for move_speed. Guarded the way every other resolve() call
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

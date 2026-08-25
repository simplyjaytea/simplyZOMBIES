class_name SimNeeds
extends RefCounted

# Six Needs (0001–0002, 0005–0006, 0008). One file; each Need is its own system id.
# ponytail: drain every tick; swap to 1 s if a 20-survivor bench shows up in the 8 ms tick.

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimHealth = preload("res://sim/modules/health.gd")

const HUNGER_EMPTY_DAYS: float = 2.0
const THIRST_EMPTY_DAYS: float = 1.0
const SEEK_START: float = 40.0
const SEEK_STOP: float = 80.0
const SEEK_NEVER_ABOVE: float = 50.0
const SOFT: float = 30.0
const HARD: float = 0.0
const STARVE_DAYS: float = 1.0
const DEHYDRATE_DAYS: float = 0.25
const CAMPFIRE_HEAT_M: float = 4.0
const CAMPFIRE_LIGHT_M: float = 20.0
const CAMPFIRE_SCENT: float = 5.0
const CAMPFIRE_COOK_SCENT: float = 15.0
const RAW_SPOIL_DAYS: float = 2.0
const COOKED_SPOIL_DAYS: float = 1.0
const NEED_SOURCES: Array[String] = ["need.hunger", "need.thirst", "need.rest", "need.temperature", "need.hygiene"]

# --- mood consequences (docs/04) -----------------------------------------------------------
#
# "Low mood does not produce a rage meltdown. It produces: slower work, more mistakes, more
# injuries; refusing assigned jobs; arguments -- which damage other survivors' mood, so misery
# spreads; ... at the extreme: leaving." Only the extreme was wired: mood <= LEAVE_AT publishes
# mood.threshold and recruits.gd walks the survivor out. Everything between "fine" and "gone" did
# nothing at all, which is the opposite of the document's own summary -- "a slow, sour decline
# where the colony stops functioning ... more frightening and more recoverable than a dramatic
# break". A cliff at -80 is a dramatic break.
#
# So there are bands rather than a threshold, and each one adds a consequence to the one below it.
# The numbers sit between the existing mood sources (a filthy survivor is already -20, three needs
# below SOFT another -30) and LEAVE_AT, so the bands are reachable by ordinary neglect rather than
# only by contrivance.
const MOOD_LOW: float = -20.0
const MOOD_MISERABLE: float = -50.0
const LEAVE_AT: float = -80.0

# What each band is called. Ordered worst-first, and the strings are the vocabulary every
# consequence and every gate uses -- jobs.gd matches on these rather than re-deriving thresholds,
# so a band boundary moves in one place.
const MOOD_BANDS: Array[String] = ["breaking", "miserable", "low", "content"]

# Arguments. A miserable survivor within ARGUMENT_METRES of another takes it out on them every
# ARGUMENT_TICKS, and the damage accumulates on the *victim* toward a cap.
#
# The cap is the whole design of this: an unbounded source would let two miserable survivors drive
# each other past LEAVE_AT in a few minutes and empty the colony, which is the "rage meltdown"
# docs/04 explicitly rules out. Capped and decaying, arguments are a drag that makes a bad mood
# spread and stick without becoming a spiral that cannot be pulled out of -- feed and rest people
# and it drains away.
const ARGUMENT_METRES: float = 4.0
const ARGUMENT_TICKS: int = 600
const ARGUMENT_PER: float = 6.0
const ARGUMENT_CAP: float = 24.0
# Recovered per mood tick (every 20 ticks) once nobody is arguing at you. At 0.05 a survivor at the
# cap is clear in about two in-game hours of peace.
const ARGUMENT_DECAY: float = 0.05
const ARGUMENT_SOURCE: String = "mood.argument"

# Grief. docs/04 lists "grief" and "witnessing a death" as two of the negative mood sources, and
# docs/23's death-and-succession item asks for "the colony morale hit on a death". This is that,
# and deliberately not the relationship system: docs/07 scales grief by closeness through pairwise
# opinions, which are Milestone 3A. What is here is the part that does not need them -- somebody
# the colony lived with is dead, and everybody feels it, more if they watched it happen.
#
# **Witnessing is a real distinction now and could not have been made before this milestone.**
# Until every survivor got eyes, `world.vision` answered for the player alone, so "did anybody see
# this" had no answer for a colonist. It does now, through the same `line_of_sight` a shot is
# refused by.
#
# The cap is the argument cap's argument, for the same reason: three deaths in a bad night must
# not empty the colony through LEAVE_AT in one stroke. Grief is heavy, it stacks, and it stops.
const GRIEF_WITNESSED: float = 18.0
const GRIEF_HEARD: float = 7.0
# docs/06's response #5 -- putting somebody down yourself -- is supposed to have a price, and
# docs/07 says relationships are "what gives response #5 its price". Without relationships this is
# the part of that price that can be paid: it is worse for everyone when the colony did it.
const GRIEF_PUT_DOWN_MUL: float = 1.6
# docs/07's Optimist: "slower mood decay, less grief transmission".
const GRIEF_OPTIMIST_MUL: float = 0.5
const GRIEF_CAP: float = 40.0
# Per mood tick (every 20 ticks). At 0.005 a survivor at the cap is clear after about thirteen
# in-game hours -- grief lasts most of a day and then it does not.
const GRIEF_DECAY: float = 0.005
const GRIEF_SOURCE: String = "mood.grief"

const TEMP_ORDER: Array[String] = [
	"extremely_cold", "very_cold", "a_little_cold", "comfortable", "a_little_hot", "very_hot", "extremely_hot",
]
const HYG_ORDER: Array[String] = ["clean", "a_little_dirty", "dirty", "filthy"]
# --- food is content (docs/12) ----------------------------------------------------------------
#
# docs/12's content-shape section: "Resources, location loot tables, and spoilage rules are JSON."
# The loot tables moved out a slice ago; this is the spoilage half. What a food restores, what it
# does to mood, how long it keeps and how likely it is to make you ill are a `food` block on the
# item base now, so rebalancing the diet -- or adding a food -- is a data edit.
#
# The table below is gone, not merely bypassed. It read:
#
#   item.food.canned  {hunger: 40, mood:  0, spoilDays: 0}
#   item.food.raw     {hunger: 25, mood: -8, spoilDays: 2}
#   item.food.cooked  {hunger: 60, mood:  8, spoilDays: 1}
#
# and those numbers are now in content/items/supplies.json unchanged, so this slice moves where
# they live without moving what they say.

# What a food does, read from content. Returns null for anything that is not food, which is how
# every caller here asks "is this edible" as well as "what does it do".
static func food_spec(world: Variant, base_id: String) -> Variant:
	var base: Variant = SimItems.content_entry(world, "item", base_id)
	if not (base is Dictionary):
		return null
	var spec: Variant = (base as Dictionary).get("food")
	return spec if spec is Dictionary else null


static func is_food(world: Variant, base_id: String) -> bool:
	return food_spec(world, base_id) != null


# --- foodborne illness (docs/04) --------------------------------------------------------------
#
# docs/04: "Quality matters, not just quantity: raw and spoiled food fills the bar but damages mood
# and carries illness risk". The mood half shipped; the illness half did not, so raw food was a
# mood tax and nothing else and there was never a reason to cook anything you were not enjoying.
#
# Kept deliberately distinct from both zombie infection and sepsis, per docs/23's own line that
# bacterial infection stays separate from zombie infection. This is neither: it is a bounded,
# self-limiting bout of food poisoning that costs mood and work and then passes. Nobody dies of it
# in Milestone 2, which is why it lives here in needs.gd rather than growing a module.
const ILLNESS_TICKS: int = 3600
const ILLNESS_MOOD: float = -14.0
const ILLNESS_WORK_MUL: float = 0.6
const ILLNESS_SOURCE: String = "need.illness"
const ILLNESS_STREAM: String = "illness"

# What a completely empty stamina pool costs work speed. docs/04 lists work speed among the four
# things exhaustion degrades; melee.gd's _apply_exhaustion owns the other three, which are
# modifiers. This one is not, so it lives with work_mul.
const EXHAUSTION_WORK_PENALTY: float = 0.35

# What eating something that has gone off does to mood, regardless of what the base declares --
# spoiled is spoiled. Lifted out of the eat path as a constant so the one magic number in this
# area has a name.
const SPOILED_MOOD: float = -16.0

# Spoiled food is worse than merely raw, whatever the base declares. A multiplier rather than a
# second authored number, so a content edit to illnessChance moves both together.
const SPOILED_ILLNESS_MUL: float = 2.5


# Whether this meal makes them ill. `iron_stomach` is immunity here rather than a reduction: the
# trait already zeroes the mood penalty, and a trait that half-protects from two things is harder
# to reason about than one that fully protects from both.
static func _rolls_ill(world: Variant, entity: int, spec: Dictionary, spoiled: bool) -> bool:
	if has_trait(world, entity, "iron_stomach"):
		return false
	var chance: float = float(spec.get("illnessChance", 0.0))
	if spoiled:
		chance *= SPOILED_ILLNESS_MUL
	if chance <= 0.0:
		return false
	return float(world.rng.stream(ILLNESS_STREAM).call("float_range", 0.0, 1.0)) < clampf(chance, 0.0, 1.0)


# A bout of food poisoning: bounded, self-limiting, and refreshed rather than stacked by a second
# bad meal. Nobody dies of it in Milestone 2 -- it costs mood and work and then passes, which is
# what makes cooking worth the fuel without making one bad tin a death sentence.
static func _fall_ill(world: Variant, entity: int) -> void:
	var n: Dictionary = of(world, entity)
	n["illUntilTick"] = int(world.tick) + ILLNESS_TICKS
	if world.modifiers != null:
		world.modifiers.call("remove_by_source", ILLNESS_SOURCE, entity)
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": ILLNESS_MOOD, "source": ILLNESS_SOURCE}, entity)
	world.events.publish({"type": "illness.contracted", "entity": entity, "ticks": ILLNESS_TICKS})


static func is_ill(world: Variant, entity: int) -> bool:
	return int(world.tick) < int(of(world, entity).get("illUntilTick", -1))


# Clears the modifier once the bout has run its course. Driven from the mood tick rather than its
# own system: it is one comparison per survivor and does not need a phase slot of its own.
static func _tick_illness(world: Variant) -> void:
	if world.modifiers == null:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var until: int = int(n.get("illUntilTick", -1))
		if until < 0 or int(world.tick) < until:
			continue
		n["illUntilTick"] = -1
		world.modifiers.call("remove_by_source", ILLNESS_SOURCE, int(ent))
		world.events.publish({"type": "illness.passed", "entity": int(ent)})


static func blank() -> Dictionary:
	return {
		"hunger": 100.0,
		"thirst": 100.0,
		"rest": 100.0,
		"temperature": "comfortable",
		"hygiene": "clean",
		"crisis": "none",
		"starvingSinceTick": -1,
		"dehydratingSinceTick": -1,
		"slept": "up",
		"wakeJob": "",
		"dirtyWake": false,
	}


static func attach(world: Variant, entity: int, pools: Dictionary = {}) -> void:
	var n: Dictionary = blank()
	for k in pools.keys():
		n[k] = pools[k]
	world.components.set_component(entity, "needs", n)


static func of(world: Variant, entity: int) -> Dictionary:
	var raw: Variant = world.components.get_component(entity, "needs")
	return raw as Dictionary if raw is Dictionary else blank()


static func hold_max(world: Variant) -> bool:
	return bool(world.needsHoldMax) if world != null and "needsHoldMax" in world else false


static func drain_hunger() -> float:
	return 100.0 / (HUNGER_EMPTY_DAYS * float(Clock.DAY_TICKS))


static func drain_thirst() -> float:
	return 100.0 / (THIRST_EMPTY_DAYS * float(Clock.DAY_TICKS))


static func drain_rest() -> float:
	# Wake = dawn+day+dusk = 0.75 of a day.
	return 100.0 / (0.75 * float(Clock.DAY_TICKS))


static func pressure(pool: float) -> String:
	if pool <= HARD:
		return "hard"
	if pool < SOFT:
		return "soft"
	if pool <= SEEK_START:
		return "seek"
	return "ok"


static func band_pressure(kind: String, band: String) -> String:
	if kind == "temperature":
		if band == "extremely_cold" or band == "extremely_hot":
			return "hard"
		if band == "very_cold" or band == "very_hot":
			return "soft"
		if band.begins_with("a_little_"):
			return "seek"
		return "ok"
	if band == "filthy":
		return "hard"
	if band == "dirty":
		return "soft"
	if band == "a_little_dirty":
		return "seek"
	return "ok"


static func sepsis_mul(band: String) -> float:
	match band:
		"a_little_dirty":
			return 1.25
		"dirty":
			return 1.75
		"filthy":
			return 2.5
		_:
			return 1.0


static func work_mul(world: Variant, entity: int) -> float:
	var n: Dictionary = of(world, entity)
	if String(n.get("crisis", "none")) != "none":
		return 0.0
	var m: float = 1.0
	for k in ["hunger", "thirst", "rest"]:
		if float(n.get(k, 100.0)) < SOFT:
			m = minf(m, 0.85)
	var t: String = String(n.get("temperature", "comfortable"))
	var h: String = String(n.get("hygiene", "clean"))
	if t == "very_cold" or t == "very_hot" or h == "dirty" or h == "filthy":
		m = minf(m, 0.85)
	# Food poisoning is the one need-adjacent state that is worse than being merely uncomfortable,
	# so it multiplies rather than joining the 0.85 floor the others share.
	if is_ill(world, entity):
		m *= ILLNESS_WORK_MUL
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	if Wounds != null and bool(Wounds.call("is_septic", world, entity)):
		m *= float(Wounds.get("SEPSIS_WORK_MUL"))
	# docs/05: pain "degrades everything -- accuracy, work speed, mood". Accuracy and mood are
	# modifiers and live in wounds.gd; work speed is this multiplier, which is not a modifier, so
	# it is applied here. Scaled by the pain actually felt, so a dose of painkillers speeds
	# somebody up without healing them -- which is the tactical option, and the trap.
	if Wounds != null:
		var pain: float = float(Wounds.call("pain_of", world, entity))
		if pain > 0.0:
			m *= 1.0 - float(Wounds.get("PAIN_WORK_PENALTY")) * pain
	# docs/04 lists work speed among what exhaustion degrades. Read off stamina directly rather
	# than through a modifier, because this multiplier is not one.
	var stamina: Variant = world.components.get_component(entity, "stamina")
	if stamina is Dictionary:
		var maxv: float = maxf(1.0, float((stamina as Dictionary).get("max", 100)))
		var emptiness: float = clampf(1.0 - float((stamina as Dictionary).get("current", maxv)) / maxv, 0.0, 1.0)
		m *= 1.0 - EXHAUSTION_WORK_PENALTY * emptiness
	return maxf(0.0, m)


static func accuracy_mul(world: Variant, entity: int) -> float:
	return work_mul(world, entity) if work_mul(world, entity) > 0.0 else 0.85


static func has_trait(world: Variant, entity: int, trait_id: String) -> bool:
	var ident: Variant = world.components.get_component(entity, "identity")
	if not ident is Dictionary:
		return false
	var traits: Variant = (ident as Dictionary).get("traits", [])
	return traits is Array and (traits as Array).has(trait_id)


static func wearing_wrap(world: Variant, entity: int) -> bool:
	for item in SimInventory.equipped_items(world, entity):
		var base: Variant = world.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == "item.wrap.cloth":
			return true
	return false


static func register_module(world: Variant) -> void:
	if not "needsHoldMax" in world:
		world.needsHoldMax = false
	world.systems.register("need.hunger", "needs", 10, func(w: Variant) -> void:
		_tick_pools(w, "hunger", drain_hunger(), "starving", STARVE_DAYS)
	)
	world.systems.register("need.thirst", "needs", 11, func(w: Variant) -> void:
		_tick_pools(w, "thirst", drain_thirst(), "dehydrating", DEHYDRATE_DAYS)
	)
	world.systems.register("need.rest", "needs", 12, func(w: Variant) -> void:
		_tick_rest(w)
	)
	world.systems.register("need.illness", "needs", 11, func(w: Variant) -> void:
		_tick_illness(w)
	)
	world.systems.register("need.arguments", "needs", 12, func(w: Variant) -> void:
		_tick_arguments(w)
	)
	world.systems.register("need.grief", "needs", 12, func(w: Variant) -> void:
		_tick_grief(w)
	)

	# Marked on the body rather than remembered in a module-level set: a static would be shared
	# between the two worlds a gate boots, and it would not survive a save. `putDown` is read by
	# the grief handler below and by nothing else.
	world.events.subscribe({"id": "needs.mark-put-down", "type": "survivor.putDown", "handler": func(event: Dictionary) -> void:
		# Handlers run at drain, by which point the put-down has already been reaped, and a
		# reap that ended in a despawn leaves nothing to mark. `set_component` on a dead id
		# would happily create a component nothing can ever reach or remove -- `components`
		# is keyed by id and does not consult `entities` -- so it would sit in every save
		# from then on. SimInfection.put_down sets the marker before it reaps for exactly
		# this reason; this stays the marker for a put-down published by anything else.
		if not bool(world.entities.call("is_alive", int(event["entity"]))):
			return
		world.components.set_component(int(event["entity"]), "putDown", {})
	})
	world.events.subscribe({"id": "needs.grieve", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		_grieve_for(world, event)
	})
	world.systems.register("need.mood", "needs", 13, func(w: Variant) -> void:
		_tick_mood(w)
	)
	world.systems.register("need.temperature", "needs", 14, func(w: Variant) -> void:
		_tick_temperature(w)
	)
	world.systems.register("need.hygiene", "needs", 15, func(w: Variant) -> void:
		_tick_hygiene(w)
	)
	world.systems.register("need.spoilage", "needs", 16, func(w: Variant) -> void:
		_tick_spoilage(w)
	)
	world.systems.register("need.intake", "input", 12, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			if kind == "item.use" or kind == "item.wash":
				for actor in w.components.query(["controlled", "needs"]):
					use_item(w, int(actor), int(c.get("item", -1)), kind == "item.wash" or bool(c.get("wash", false)))
	)
	world.events.subscribe({"id": "need.wake-alarm", "type": "alarm.tripped", "handler": func(_e: Dictionary) -> void:
		_wake_all(world)
	})
	world.events.subscribe({"id": "need.wake-grab", "type": "grab.started", "handler": func(e: Dictionary) -> void:
		_wake(world, int(e.get("victim", -1)))
	})
	world.events.subscribe({"id": "need.wake-hit", "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		_wake(world, int(e.get("target", -1)))
	})


static func _survivors(world: Variant) -> Array[int]:
	return world.components.query(["needs"])


static func _tick_pools(world: Variant, key: String, rate: float, crisis: String, death_days: float) -> void:
	var hold: bool = hold_max(world)
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			_hold_one(world, ent, n)
			continue
		if world.components.has_component(ent, "sleeping") and key != "hunger" and key != "thirst":
			continue
		var before: float = float(n.get(key, 100.0))
		var after: float = maxf(0.0, before - rate)
		n[key] = after
		_cross(world, ent, n, key, before, after)
		if after <= HARD:
			if String(n.get("crisis", "none")) == "none" or String(n.get("crisis", "none")) == "passed_out":
				n["crisis"] = crisis
				var since_key: String = "starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick"
				if int(n.get(since_key, -1)) < 0:
					n[since_key] = int(world.tick)
			var since: int = int(n.get("starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick", -1))
			if since >= 0 and int(world.tick) - since >= int(death_days * float(Clock.DAY_TICKS)):
				world.events.publish({"type": "entity.killed", "entity": ent, "need": key})
				var Health: GDScript = load("res://sim/modules/health.gd") as GDScript
				Health.call("finish_death", world, ent)
		else:
			if String(n.get("crisis", "")) == crisis:
				n["crisis"] = "none"
				n["starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick"] = -1


static func _tick_rest(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var phase: int = Clock.phase_of(int(world.tick))
	var prev: int = Clock.phase_of(int(world.tick) - 1)
	var dawn: bool = phase == Clock.Phase.Dawn and prev != Clock.Phase.Dawn
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			_hold_one(world, ent, n)
			continue
		var sleeping: bool = world.components.has_component(ent, "sleeping")
		if sleeping:
			_refill_sleep(world, ent, n)
		elif phase != Clock.Phase.Night:
			var before: float = float(n.get("rest", 100.0))
			var after: float = maxf(0.0, before - drain_rest())
			n["rest"] = after
			_cross(world, ent, n, "rest", before, after)
			if after <= HARD:
				n["crisis"] = "passed_out"
				_start_sleep(world, ent, -1)
		if dawn:
			n["wakeJob"] = ""
			n["dirtyWake"] = false
		if String(n.get("crisis", "")) == "passed_out" and float(n.get("rest", 0.0)) >= 20.0:
			n["crisis"] = "none"
			_wake(world, ent)


static func _refill_sleep(world: Variant, ent: int, n: Dictionary) -> void:
	# Full night in bed = 100; rough = 50. Spread across night ticks.
	var sl: Variant = world.components.get_component(ent, "sleeping")
	var on_bed: bool = sl is Dictionary and int((sl as Dictionary).get("bed", -1)) >= 0
	var night_ticks: float = 0.25 * float(Clock.DAY_TICKS)
	var full: float = 100.0 if on_bed else 50.0
	if has_trait(world, ent, "light_sleeper"):
		full *= 0.5
	n["rest"] = minf(100.0, float(n.get("rest", 0.0)) + full / night_ticks)
	n["slept"] = "bed" if on_bed else "rough"
	if float(n.get("rest", 0.0)) >= 100.0 and String(n.get("crisis", "")) == "passed_out":
		n["crisis"] = "none"


static func _tick_mood(world: Variant) -> void:
	if hold_max(world):
		for ent in _survivors(world):
			_strip_need_mood(world, ent)
		return
	if int(world.tick) % 20 != 0:
		return
	for ent in _survivors(world):
		if world.components.has_component(ent, "controlled"):
			continue
		if world.modifiers == null:
			continue
		var mood: float = float(world.modifiers.call("resolve", "mood", ent))
		if mood <= LEAVE_AT:
			world.events.publish({"type": "mood.threshold", "entity": ent, "mood": mood})


# The one canonical mood-band read. Every consequence matches on the string this returns rather
# than comparing against a threshold of its own, so a boundary moves in one place.
static func mood_band(world: Variant, entity: int) -> String:
	if world.modifiers == null:
		return "content"
	var mood: float = float(world.modifiers.call("resolve", "mood", entity))
	if mood <= LEAVE_AT:
		return "breaking"
	if mood <= MOOD_MISERABLE:
		return "miserable"
	if mood <= MOOD_LOW:
		return "low"
	return "content"


# docs/04: "arguments -- which damage other survivors' mood, so misery spreads". A miserable
# survivor argues with the nearest other survivor in earshot; the damage lands on the *other* one,
# accumulates toward ARGUMENT_CAP, and drains away once nobody is arguing at them.
#
# Deliberately not symmetric: the arguer does not also lose mood. They are already miserable --
# that is the precondition -- and charging both sides would make any two unhappy people a spiral,
# which is the meltdown docs/04 rules out.
static func _tick_arguments(world: Variant) -> void:
	if int(world.tick) % 20 != 0:
		return
	var everyone: Array = _survivors(world)
	# Decay first, and for everybody, so a survivor nobody has argued with this cycle recovers on
	# the same tick the arguing happens rather than a cycle later.
	for ent in everyone:
		_decay_argument(world, int(ent))
	if hold_max(world):
		return
	if int(world.tick) % ARGUMENT_TICKS != 0:
		return
	for ent in everyone:
		if mood_band(world, int(ent)) != "miserable" and mood_band(world, int(ent)) != "breaking":
			continue
		if world.components.has_component(int(ent), "sleeping"):
			continue
		var victim: int = _nearest_other_survivor(world, int(ent), everyone)
		if victim < 0:
			continue
		_argue(world, int(ent), victim)


static func _nearest_other_survivor(world: Variant, ent: int, everyone: Array) -> int:
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return -1
	var best: int = -1
	var best_sq: float = ARGUMENT_METRES * ARGUMENT_METRES
	for other in everyone:
		if int(other) == ent:
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not (there is Dictionary):
			continue
		var dx: float = float((there as Dictionary)["x"]) - float((here as Dictionary)["x"])
		var dy: float = float((there as Dictionary)["y"]) - float((here as Dictionary)["y"])
		var sq: float = dx * dx + dy * dy
		if sq <= best_sq:
			best_sq = sq
			best = int(other)
	return best


static func _argue(world: Variant, arguer: int, victim: int) -> void:
	var n: Dictionary = of(world, victim)
	var before: float = float(n.get("argued", 0.0))
	if before >= ARGUMENT_CAP:
		# Already as sour as arguing can make them. Still worth publishing -- the colony is having
		# the argument either way, and a listener that wants to say so should hear it.
		world.events.publish({"type": "mood.argument", "entity": arguer, "victim": victim, "capped": true})
		return
	n["argued"] = minf(ARGUMENT_CAP, before + ARGUMENT_PER)
	_apply_argument(world, victim, float(n["argued"]))
	world.events.publish({"type": "mood.argument", "entity": arguer, "victim": victim, "capped": false})


static func _decay_argument(world: Variant, ent: int) -> void:
	var n: Dictionary = of(world, ent)
	var carried: float = float(n.get("argued", 0.0))
	if carried <= 0.0:
		return
	n["argued"] = maxf(0.0, carried - ARGUMENT_DECAY)
	_apply_argument(world, ent, float(n["argued"]))


# --- grief ------------------------------------------------------------------------------------

# A survivor died. Everybody else takes it, more if they saw it.
#
# **Deduplicated on the body.** CLAUDE.md is explicit that `entity.killed` fires more than once for
# the same individual -- health.gd on a destroyed head, infection.gd on a put-down and again on
# turning -- so counting the event would charge the colony two or three times for one funeral. The
# `mourned` component is set the first time and checked every time.
static func _grieve_for(world: Variant, event: Dictionary) -> void:
	var dead: int = int(event.get("entity", -1))
	if dead < 0:
		return
	# Only people. A shambler going down is not a bereavement, and the same event carries both.
	if not world.components.has_component(dead, "needs"):
		return
	if world.components.has_component(dead, "mourned"):
		return
	world.components.set_component(dead, "mourned", {"tick": int(world.tick)})

	var at: Dictionary = _death_place(world, dead, event)
	var put_down: bool = world.components.has_component(dead, "putDown")
	var witnesses: int = 0
	for ent in _survivors(world):
		var mourner: int = int(ent)
		if mourner == dead or not _alive(world, mourner):
			continue
		var saw: bool = _saw(world, mourner, at)
		if saw:
			witnesses += 1
		var amount: float = GRIEF_WITNESSED if saw else GRIEF_HEARD
		if put_down:
			amount *= GRIEF_PUT_DOWN_MUL
		if has_trait(world, mourner, "optimist"):
			amount *= GRIEF_OPTIMIST_MUL
		var n: Dictionary = of(world, mourner)
		n["grief"] = minf(GRIEF_CAP, float(n.get("grief", 0.0)) + amount)
		_apply_grief(world, mourner, float(n["grief"]))
	world.events.publish({"type": "colony.bereaved", "entity": dead, "witnesses": witnesses, "putDown": put_down})


# Where it happened. health.gd's event carries the position; infection.gd's put-down does not, so
# the body's own position is the fallback rather than a silent (0, 0) that everybody can see.
static func _death_place(world: Variant, dead: int, event: Dictionary) -> Dictionary:
	if event.has("x") and event.has("y"):
		return {"x": float(event["x"]), "y": float(event["y"]), "known": true}
	var pos: Variant = world.components.get_component(dead, "position")
	if pos is Dictionary:
		return {"x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]), "known": true}
	return {"x": 0.0, "y": 0.0, "known": false}


# Geometry and range, through the same primitive that decides whether a shot connects. A survivor
# with no eyes -- every pre-sightlines fixture -- witnesses nothing and grieves the lighter amount,
# which is the honest reading of "we have no idea whether they saw it".
static func _saw(world: Variant, mourner: int, at: Dictionary) -> bool:
	if not bool(at.get("known", false)):
		return false
	if world.vision == null:
		return false
	if world.vision.call("tiles_for", mourner) == null:
		return false
	return bool(world.vision.call("line_of_sight", mourner, float(at["x"]), float(at["y"])))


static func _alive(world: Variant, ent: int) -> bool:
	if world.components.has_component(ent, "corpse"):
		return false
	var body: Variant = world.components.get_component(ent, "body")
	return body is Dictionary and SimHealth.is_alive(body as Dictionary)


static func grief_of(world: Variant, entity: int) -> float:
	return float(of(world, entity).get("grief", 0.0))


# Drains on the mood tick, exactly as an argument does. Same shape, same reason: one modifier from
# one source, replaced rather than stacked.
static func _tick_grief(world: Variant) -> void:
	if world.modifiers == null or int(world.tick) % 20 != 0:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var g: float = float(n.get("grief", 0.0))
		if g <= 0.0:
			continue
		g = maxf(0.0, g - GRIEF_DECAY)
		n["grief"] = g
		_apply_grief(world, int(ent), g)


static func _apply_grief(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", GRIEF_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": GRIEF_SOURCE}, ent)


# One modifier from one source, replaced rather than stacked. Adding a second modifier per
# argument would accumulate without bound behind the cap this module thinks it is enforcing.
static func _apply_argument(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", ARGUMENT_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": ARGUMENT_SOURCE}, ent)


static func _tick_temperature(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var night: bool = Clock.phase_of(int(world.tick)) == Clock.Phase.Night
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			n["temperature"] = "comfortable"
			continue
		var pos: Variant = world.components.get_component(ent, "position")
		if not pos is Dictionary:
			continue
		var tx: int = floori(float((pos as Dictionary)["x"]))
		var ty: int = floori(float((pos as Dictionary)["y"]))
		var indoors: bool = world.tilemap != null and SimTileMap.is_indoors(world.tilemap, tx, ty)
		var fire: bool = lit_campfire_near(world, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), CAMPFIRE_HEAT_M)
		var before: String = String(n.get("temperature", "comfortable"))
		var band: String = "comfortable"
		if night:
			if fire:
				band = "comfortable"
			elif not indoors:
				band = "very_cold"
			else:
				band = "a_little_cold"
		if wearing_wrap(world, ent):
			band = _shift_temp(band, 1)
		n["temperature"] = band
		if band != before:
			_apply_muls(world, ent, n)


static func _shift_temp(band: String, toward_comfy: int) -> String:
	var i: int = TEMP_ORDER.find(band)
	if i < 0:
		return "comfortable"
	var c: int = TEMP_ORDER.find("comfortable")
	if i < c:
		return TEMP_ORDER[mini(c, i + toward_comfy)]
	if i > c:
		return TEMP_ORDER[maxi(c, i - toward_comfy)]
	return "comfortable"


static func _tick_hygiene(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var dusk: bool = Clock.phase_of(int(world.tick)) == Clock.Phase.Dusk and Clock.phase_of(int(world.tick) - 1) != Clock.Phase.Dusk
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			n["hygiene"] = "clean"
			_scent_mul(world, ent, "clean")
			continue
		if dusk and bool(n.get("dirtyWake", false)):
			_dirt(world, ent, 1)
		_scent_mul(world, ent, String(n.get("hygiene", "clean")))
		if dusk:
			_daily_sepsis(world, ent, n)


static func _daily_sepsis(world: Variant, ent: int, n: Dictionary) -> void:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not inj is Dictionary:
		return
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return
	var mul: float = sepsis_mul(String(n.get("hygiene", "clean")))
	world.events.publish({"type": "sepsis.checked", "entity": ent, "mul": mul, "kind": "wound"})
	# The socket, finally connected. This published its multiplier every dusk and nothing
	# subscribed, so `sepsis_mul` was gated, correct, and reached no wound. wounds.gd owns the
	# wound record and the recovery clock sepsis has to block, so the roll lives there; hygiene
	# lives here, so the multiplier is computed here and handed over rather than re-derived.
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	if Wounds != null and Wounds.has_method("roll_sepsis"):
		var SkillsRes: GDScript = load("res://sim/modules/skills.gd") as GDScript
		var medicine: int = int(SkillsRes.call("points", world, ent, "Medicine")) if SkillsRes != null else 0
		Wounds.call("roll_sepsis", world, ent, mul, medicine)


static func treat_sepsis_mul(world: Variant, treater: int) -> float:
	return sepsis_mul(String(of(world, treater).get("hygiene", "clean")))


static func _tick_spoilage(world: Variant) -> void:
	for item in world.components.query(["spoilage"]):
		var sp: Variant = world.components.get_component(int(item), "spoilage")
		if not sp is Dictionary:
			continue
		var s: Dictionary = sp as Dictionary
		if bool(s.get("spoiled", false)):
			continue
		var born: int = int(s.get("bornTick", 0))
		var need: int = int(s.get("spoilTicks", 0))
		if need <= 0:
			continue
		if int(world.tick) - born >= need:
			s["spoiled"] = true


static func mark_spoilage(world: Variant, item: int, base_id: String) -> void:
	var spec: Variant = food_spec(world, base_id)
	if spec == null:
		return
	var days: float = float((spec as Dictionary).get("spoilDays", 0.0))
	if days <= 0.0:
		return
	world.components.set_component(item, "spoilage", {
		"bornTick": int(world.tick),
		"spoilTicks": int(days * float(Clock.DAY_TICKS)),
		"spoiled": false,
	})


static func _hold_one(world: Variant, ent: int, n: Dictionary) -> void:
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	n["crisis"] = "none"
	n["starvingSinceTick"] = -1
	n["dehydratingSinceTick"] = -1
	_strip_need_mood(world, ent)


static func _strip_need_mood(world: Variant, ent: int) -> void:
	if world.modifiers == null:
		return
	for src in NEED_SOURCES:
		world.modifiers.call("remove_by_source", src, ent)


static func _cross(world: Variant, ent: int, n: Dictionary, key: String, before: float, after: float) -> void:
	var marks: Array[float] = [SEEK_STOP, SEEK_NEVER_ABOVE, SEEK_START, SOFT, HARD]
	var hit: bool = false
	for m in marks:
		if (before > m and after <= m) or (before <= m and after > m):
			hit = true
			break
	if hit:
		_apply_muls(world, ent, n)
		world.events.publish({"type": "need.crossed", "entity": ent, "need": key, "value": after})


static func _apply_muls(world: Variant, ent: int, n: Dictionary) -> void:
	if world.modifiers == null:
		return
	_strip_need_mood(world, ent)
	if hold_max(world):
		return
	var work: float = work_mul(world, ent)
	var acc: float = accuracy_mul(world, ent)
	if work != 1.0 and work > 0.0:
		world.modifiers.call("add", {"stat": "ranged_accuracy", "op": "mul", "value": acc, "source": "need.hunger"}, ent)
	var mood_v: float = 0.0
	for k in ["hunger", "thirst", "rest"]:
		if float(n.get(k, 100.0)) < SOFT:
			mood_v -= 10.0
	var t: String = String(n.get("temperature", "comfortable"))
	var h: String = String(n.get("hygiene", "clean"))
	if t.begins_with("a_little_") or h == "a_little_dirty":
		mood_v -= 4.0
	if t == "very_cold" or t == "very_hot" or h == "dirty":
		mood_v -= 10.0
	if h == "filthy":
		mood_v -= 20.0
	if mood_v != 0.0:
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": mood_v, "source": "need.hunger"}, ent)


static func _scent_mul(world: Variant, ent: int, band: String) -> void:
	var em: Variant = world.components.get_component(ent, "attention_emitter")
	if not em is Dictionary:
		return
	var base: float = 1.0
	if band == "dirty":
		base = 2.0
	elif band == "filthy":
		base = 3.0
	(em as Dictionary)["scent"] = base


static func dirt(world: Variant, entity: int, bands: int = 1) -> void:
	_dirt(world, entity, bands)


static func _dirt(world: Variant, entity: int, bands: int) -> void:
	var n: Dictionary = of(world, entity)
	var i: int = HYG_ORDER.find(String(n.get("hygiene", "clean")))
	if i < 0:
		i = 0
	n["hygiene"] = HYG_ORDER[clampi(i + bands, 0, HYG_ORDER.size() - 1)]
	_apply_muls(world, entity, n)
	_scent_mul(world, entity, String(n["hygiene"]))


static func wash(world: Variant, entity: int) -> bool:
	if not _consume_base(world, entity, "item.water.bottle"):
		return false
	return wash_at_source(world, entity)


static func wash_at_source(world: Variant, entity: int) -> bool:
	var n: Dictionary = of(world, entity)
	n["hygiene"] = "clean"
	_apply_muls(world, entity, n)
	_scent_mul(world, entity, "clean")
	return true


static func drink(world: Variant, entity: int) -> bool:
	if not _consume_base(world, entity, "item.water.bottle"):
		return false
	var n: Dictionary = of(world, entity)
	n["thirst"] = minf(100.0, float(n.get("thirst", 0.0)) + 50.0)
	if String(n.get("crisis", "")) == "dehydrating" and float(n["thirst"]) > 0.0:
		n["crisis"] = "none"
		n["dehydratingSinceTick"] = -1
	_apply_muls(world, entity, n)
	return true


static func eat(world: Variant, entity: int, item: int) -> bool:
	var base: Variant = world.components.get_component(item, "itemBase")
	if not base is Dictionary:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	var spec_v: Variant = food_spec(world, bid)
	if spec_v == null:
		return false
	var spec: Dictionary = spec_v as Dictionary
	var hunger: float = float(spec.get("hunger", 0.0))
	var mood: float = float(spec.get("mood", 0.0))
	var spoiled: bool = false
	var sp: Variant = world.components.get_component(item, "spoilage")
	if sp is Dictionary:
		spoiled = bool((sp as Dictionary).get("spoiled", false))
	if spoiled:
		mood = SPOILED_MOOD
	# docs/04: raw and spoiled food "carries illness risk". Rolled before the item is consumed but
	# applied after, so a refused consume cannot leave somebody ill from a meal they did not eat.
	var ill: bool = _rolls_ill(world, entity, spec, spoiled)
	var iron: bool = has_trait(world, entity, "iron_stomach")
	if iron and mood < 0.0:
		mood = 0.0
	if not _consume_item(world, entity, item):
		return false
	var n: Dictionary = of(world, entity)
	n["hunger"] = minf(100.0, float(n.get("hunger", 0.0)) + hunger)
	if String(n.get("crisis", "")) == "starving" and float(n["hunger"]) > 0.0:
		n["crisis"] = "none"
		n["starvingSinceTick"] = -1
	if mood != 0.0 and world.modifiers != null:
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": mood, "source": "need.food"}, entity)
	if ill:
		_fall_ill(world, entity)
	_apply_muls(world, entity, n)
	return true


static func use_item(world: Variant, entity: int, item: int, as_wash: bool = false) -> bool:
	if item < 0 or not SimInventory.owns(world, entity, item):
		return false
	var base: Variant = world.components.get_component(item, "itemBase")
	if not base is Dictionary:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	if bid == "item.water.bottle":
		if as_wash:
			return wash(world, entity)
		var n: Dictionary = of(world, entity)
		if String(n.get("hygiene", "clean")) == "filthy" and String(n.get("crisis", "none")) != "dehydrating":
			return wash(world, entity)
		return drink(world, entity)
	if is_food(world, bid):
		return eat(world, entity, item)
	return false


static func _consume_base(world: Variant, actor: int, base_id: String) -> bool:
	for item in SimInventory.carried_items(world, actor):
		var base: Variant = world.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == base_id:
			return _consume_item(world, actor, item)
	return false


static func consume_base(world: Variant, actor: int, base_id: String) -> bool:
	return _consume_base(world, actor, base_id)


static func _consume_item(_world: Variant, _actor: int, item: int) -> bool:
	var stack: Variant = _world.components.get_component(item, "stack")
	if stack is Dictionary and int((stack as Dictionary).get("count", 1)) > 1:
		(stack as Dictionary)["count"] = int((stack as Dictionary)["count"]) - 1
		return true
	SimInventory.remove_from_container(_world, item)
	_world.despawn(item)
	return true


static func start_sleep(world: Variant, entity: int, bed: int) -> void:
	_start_sleep(world, entity, bed)


static func wake(world: Variant, entity: int) -> void:
	_wake(world, entity)


static func _start_sleep(world: Variant, entity: int, bed: int) -> void:
	world.components.set_component(entity, "sleeping", {"bed": bed, "since": int(world.tick)})
	if bed >= 0:
		var b: Variant = world.components.get_component(bed, "bed")
		if b is Dictionary:
			(b as Dictionary)["occupiedBy"] = entity
	var vel: Variant = world.components.get_component(entity, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


static func _wake(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	var sl: Variant = world.components.get_component(entity, "sleeping")
	if sl is Dictionary:
		var bed: int = int((sl as Dictionary).get("bed", -1))
		if bed >= 0:
			var b: Variant = world.components.get_component(bed, "bed")
			if b is Dictionary and int((b as Dictionary).get("occupiedBy", -1)) == entity:
				(b as Dictionary)["occupiedBy"] = -1
	world.components.remove(entity, "sleeping")


static func _wake_all(world: Variant) -> void:
	for ent in world.components.query(["sleeping"]):
		_wake(world, int(ent))


static func make_campfire(world: Variant, x: float, y: float, lit: bool = false) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "campfire", {"lit": lit, "cooking": false})
	var em: Dictionary = SimAttention.PERSON_EMITTER.duplicate(true)
	em["walking"] = 0.0
	em["sprinting"] = 0.0
	em["ambient"] = 0.0
	em["scent"] = 0.0
	SimAttention.make_emitter(world, ent, em)
	if lit:
		set_lit(world, ent, true)
	return ent


static func make_bed(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "bed", {"occupiedBy": -1})
	return ent


static func make_water_source(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "water_source", {})
	return ent


static func nearest_water_source(world: Variant, x: float, y: float) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["water_source", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func set_lit(world: Variant, fire: int, lit: bool, cooking: bool = false) -> void:
	var cf: Variant = world.components.get_component(fire, "campfire")
	if not cf is Dictionary:
		return
	(cf as Dictionary)["lit"] = lit
	(cf as Dictionary)["cooking"] = cooking
	var em: Variant = world.components.get_component(fire, "attention_emitter")
	if em is Dictionary:
		(em as Dictionary)["scent"] = (CAMPFIRE_COOK_SCENT if cooking else CAMPFIRE_SCENT) if lit else 0.0
		(em as Dictionary)["ambient"] = 0.0
	if lit:
		SimLightMod.make_light_source(world, fire, CAMPFIRE_LIGHT_M)
	elif world.components.has_component(fire, "light_source"):
		world.components.remove(fire, "light_source")
		world.events.publish({"type": "light.changed", "entity": fire, "magnitude": 0.0})


static func toggle_fire(world: Variant, fire: int) -> void:
	var cf: Variant = world.components.get_component(fire, "campfire")
	if cf is Dictionary:
		set_lit(world, fire, not bool((cf as Dictionary).get("lit", false)))


static func lit_campfire_near(world: Variant, x: float, y: float, metres: float) -> bool:
	var r2: float = metres * metres
	for e in world.components.query(["campfire", "position"]):
		var cf: Variant = world.components.get_component(int(e), "campfire")
		if not cf is Dictionary or not bool((cf as Dictionary).get("lit", false)):
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		if dx * dx + dy * dy <= r2:
			return true
	return false


static func nearest_campfire(world: Variant, x: float, y: float, lit_only: bool = false) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["campfire", "position"]):
		var cf: Variant = world.components.get_component(int(e), "campfire")
		if lit_only and (not cf is Dictionary or not bool((cf as Dictionary).get("lit", false))):
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func nearest_bed(world: Variant, x: float, y: float, free_only: bool = true) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["bed", "position"]):
		var b: Variant = world.components.get_component(int(e), "bed")
		if free_only and b is Dictionary and int((b as Dictionary).get("occupiedBy", -1)) >= 0:
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func is_stockpile_tile(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	if not SimTileMap.is_indoors(world.tilemap, tx, ty):
		return false
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Floor:
		return false
	# The stockpile is the annex's indoor floor, and where the annex is comes off the map now
	# rather than out of `SimDirector.ANNEX`. An unstamped district reports the empty rect, which
	# has no points -- so it has no stockpile, rather than one at somebody else's coordinates.
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return false
	return annex.has_point(Vector2i(tx, ty))


static func stockpile_items(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for item in SimInventory.ground_items(world):
		var p: Variant = world.components.get_component(item, "position")
		if not p is Dictionary:
			continue
		if is_stockpile_tile(world, floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"]))):
			out.append(item)
	return out


static func seek_kind(world: Variant, entity: int) -> String:
	if hold_max(world) or world.components.has_component(entity, "controlled"):
		return ""
	var n: Dictionary = of(world, entity)
	var best: String = ""
	var best_rank: int = 99
	var order: Array[String] = ["thirst", "hunger", "rest", "temperature", "hygiene"]
	for i in order.size():
		var k: String = order[i]
		var p: String = ""
		if k == "temperature" or k == "hygiene":
			p = band_pressure(k, String(n.get(k, "comfortable" if k == "temperature" else "clean")))
		else:
			p = pressure(float(n.get(k, 100.0)))
			if p == "seek" and float(n.get(k, 100.0)) > SEEK_NEVER_ABOVE:
				p = "ok"
		var rank: int = 99
		if p == "hard":
			rank = i
		elif p == "soft":
			rank = 10 + i
		elif p == "seek":
			rank = 20 + i
		if rank < best_rank:
			best_rank = rank
			best = k
	if best_rank >= 99:
		return ""
	# already recovering: stop seek at 80
	if best == "thirst" or best == "hunger" or best == "rest":
		if float(n.get(best, 0.0)) >= SEEK_STOP and best_rank >= 20:
			return ""
	return best


static func hud_clause(world: Variant, entity: int, panel: bool = false) -> String:
	var n: Dictionary = of(world, entity)
	var first: bool = world.components.has_component(entity, "controlled")
	var name: String = "You"
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		name = String((ident as Dictionary).get("name", "They"))
	var picks: Array[Dictionary] = []
	_hud_pool(picks, "thirst", float(n.get("thirst", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_pool(picks, "hunger", float(n.get("hunger", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_pool(picks, "rest", float(n.get("rest", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_band(picks, "temperature", String(n.get("temperature", "comfortable")), panel)
	_hud_band(picks, "hygiene", String(n.get("hygiene", "clean")), panel)
	if world.modifiers != null:
		var mood: float = float(world.modifiers.call("resolve", "mood", entity))
		if float(n.get("grief", 0.0)) >= GRIEF_HEARD and mood > -80.0:
			# Phrased as "You're <adjective>" so the third-person rewrite below reads as a
			# glimpse of somebody else rather than a report about them.
			picks.append({"rank": 45, "hud": "You're shaken.", "panel": "You're shaken."})
		if mood <= -80.0 and not first:
			picks.append({"rank": -1, "hud": "They're going to leave.", "panel": "They're going to leave."})
		elif mood <= -25.0:
			picks.append({"rank": 50, "hud": "Mood is turning.", "panel": "Mood is turning."})
	if picks.is_empty():
		return ""
	picks.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	var line: String = String(picks[0]["panel" if panel else "hud"])
	if first:
		return line
	if line.begins_with("You're "):
		return name + " looks " + line.substr(7)
	if line.begins_with("They’re") or line.begins_with("They're"):
		return line
	return name + " — " + line


static func hud_panel(world: Variant, entity: int) -> PackedStringArray:
	# Full panel: every non-fine Need. HUD glimpse is worst only.
	var out: PackedStringArray = []
	var clause: String = hud_clause(world, entity, true)
	if not clause.is_empty():
		out.append(clause)
	return out


static func _hud_pool(picks: Array[Dictionary], key: String, v: float, crisis: String, _panel: bool) -> void:
	if key == "hunger":
		if crisis == "starving" or v <= 0.0:
			picks.append({"rank": 2, "hud": "You're starving.", "panel": "You're starving. You can't work."})
		elif v < SOFT:
			picks.append({"rank": 12, "hud": "You're hungry.", "panel": "You're hungry — work and aim are off."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 22, "hud": "You're peckish.", "panel": "You're peckish."})
	elif key == "thirst":
		if crisis == "dehydrating" or v <= 0.0:
			picks.append({"rank": 1, "hud": "You're drying out.", "panel": "You're drying out."})
		elif v < SOFT:
			picks.append({"rank": 11, "hud": "You're thirsty.", "panel": "You're thirsty — work and aim are off."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 21, "hud": "You're thirsty.", "panel": "You're thirsty."})
	elif key == "rest":
		if crisis == "passed_out" or v <= 0.0:
			picks.append({"rank": 3, "hud": "", "panel": "Collapsed. Sleeping where they fell."})
		elif v < SOFT:
			picks.append({"rank": 13, "hud": "You're exhausted.", "panel": "You're exhausted."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 23, "hud": "You're tired.", "panel": "You're tired."})


static func _hud_band(picks: Array[Dictionary], key: String, band: String, _panel: bool) -> void:
	if key == "temperature":
		match band:
			"a_little_cold":
				picks.append({"rank": 24, "hud": "You're uncomfortable — cold.", "panel": "You're uncomfortable — cold."})
			"very_cold":
				picks.append({"rank": 14, "hud": "You're very cold.", "panel": "You're very cold."})
			"extremely_cold":
				picks.append({"rank": 4, "hud": "You're very cold.", "panel": "You're very cold."})
	elif key == "hygiene":
		match band:
			"a_little_dirty":
				picks.append({"rank": 25, "hud": "You're uncomfortable — unwashed.", "panel": "You're uncomfortable — unwashed."})
			"dirty":
				picks.append({"rank": 15, "hud": "You need a wash.", "panel": "You need a wash."})
			"filthy":
				picks.append({"rank": 5, "hud": "You're filthy.", "panel": "You're filthy. Don't cook. Don't treat."})

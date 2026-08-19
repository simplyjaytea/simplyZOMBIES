extends RefCounted
# Modification: the currency-grade consumables from docs/11.
#
# "There is no 'craft a Field-Tested Fire Axe' recipe. You find a Fire Axe and work on it, and the
# things you work on it with are the scarce consumables." Milestone 2's slice scope is two of the
# seven that document lists -- Duct Tape (reroll one existing affix, chosen at random) and Scrap
# Kit (add one affix to an item with a free slot) -- plus the two things that make them a gamble
# rather than a button: skill- and trait-weighted outcomes, and failure that consumes the
# consumable and damages the item.
#
# The other five (Whetstone, Gun Oil, Solvent, Machinist's Gauge, Salvage Rights) are deliberately
# not here. They are not blocked on anything in this file: docs/11 says "adding a consumable is a
# data entry, provided the operation it names already exists", and OPERATIONS below is that
# registry. A Solvent is one content entry plus one `strip` operation.
#
# --- what is content and what is code ----------------------------------------------------
#
# Which operation a consumable performs, and against which item classes, is **content**: an item
# base carries a `modification: {operation, appliesTo}` block, exactly as docs/11's content-shape
# section describes. What an operation *does* is code, because it is behaviour rather than data,
# and OPERATIONS is the registry that document points at.
#
# The `modification` block is a top-level item key, so both validators reach it -- and they reach
# it to different depths, which is worth saying out loud because it has already cost a red CI
# once: content_validator.gd checks the top-level type and rejects unexpected top-level keys, and
# the frozen TypeScript oracle's Ajv pass recurses into `operation` and `appliesTo`. check_mods.gd
# is what asserts the things neither can: that every declared operation exists in OPERATIONS, and
# that `appliesTo` names item classes that items actually have.
#
# --- the gamble ---------------------------------------------------------------------------
#
# docs/11: "Modification is random, and that's the point. Using Duct Tape on a Field-Tested item
# with five good affixes might reroll the one you loved." So a reroll is unconditional -- it does
# not keep the better of the two rolls, and there is no confirmation step in the sim. The affix it
# lands on is drawn uniformly from what the item already has.
#
# Craft skill and injured hands both move the odds, and they move *different* odds, which is the
# distinction docs/11 draws and this preserves:
#
#   - Craft **weights rolls toward higher affix tiers** -- CRAFT_TIER_BIAS_PER_POINT shifts the
#     weighted draw in _biased_affix_tier, so a developed crafter gets better affixes rather than
#     more of them.
#   - Craft **reduces the failure chance**, per "Craft skill reduces both odds substantially".
#   - Injured hands make outcomes **worse**: "a wounded crafter should not be at the bench". Read
#     off SimHealth.part_state for both hands rather than raw integrity, because a hand's maximum
#     is 10 where a torso's is 40 and comparing raw numbers across parts is the trap CLAUDE.md
#     names. Unusable hands refuse outright; a hurt hand raises failure and cancels the Craft
#     tier bias, so a good crafter working injured is merely an ordinary one, never a worse-than-
#     nothing one.
#
# Traits are not in Milestone 2 (docs/23 lists survivor attributes and traits as explicitly out of
# the slice), so "Steady hands" has no hook to read yet. TRAIT_FAILURE_SHIFT is the seam it will
# use, and it is named here rather than left to be invented later.
#
# --- failure -------------------------------------------------------------------------------
#
# "Every modification has a small chance to fail. Failure consumes the consumable and damages the
# item's condition; a critical failure on a badly degraded item can break it outright."
#
# Three outcomes, and the consumable is spent in all three -- that is what makes it a gamble and
# not a retry loop. A failure takes FAILURE_CONDITION_LOSS off the item. A failure on an item
# already below CRITICAL_BELOW breaks it outright: condition to zero, and the ceiling with it, so
# repair cannot bring it back. Breaking is reachable only from a degraded item, so a fresh find is
# never one bad roll from scrap.

const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimSkills = preload("res://sim/modules/skills.gd")

# The operation registry docs/11's content-shape section points at. A consumable's content block
# names one of these; adding a new one is an entry here plus its implementation in _perform.
const OPERATIONS: Array[String] = ["reroll", "add"]

# The RNG stream every modification draw comes from. Its own stream, not `loot`: a bench roll must
# not shift the tier sequence for everything spawned afterwards.
const STREAM: String = "modification"

# Base chance a modification fails outright, before skill and hands move it.
const BASE_FAILURE: float = 0.20
# Each Craft point buys this much off the failure chance, floored at MIN_FAILURE -- "Craft skill
# reduces both odds substantially", but never to zero, because a bench that cannot fail is not a
# gamble and docs/11's whole argument is that it is one.
const CRAFT_FAILURE_RELIEF: float = 0.02
const MIN_FAILURE: float = 0.05
# A hurt (not destroyed) hand. Additive, and it also cancels the Craft tier bias -- see _outcome.
const HURT_HANDS_FAILURE: float = 0.15
# The seam "Steady hands" will use when traits ship in Milestone 3A. Read by _failure_chance and
# currently always zero, because nothing writes a trait yet.
const TRAIT_FAILURE_SHIFT: float = 0.0

# How much each Craft point shifts a weighted affix-tier draw toward the higher tiers. Applied as
# a multiplier on the *later* entries of the tier array, which is ordered best-last.
const CRAFT_TIER_BIAS_PER_POINT: float = 0.15
const MAX_TIER_BIAS: float = 2.5

# What a failure costs, and the band below which a failure breaks the item instead.
const FAILURE_CONDITION_LOSS: float = 0.25
const CRITICAL_BELOW: float = 0.2


static func register_module(world: Variant) -> void:
	world.systems.register("modification.intake", "input", 10, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) != "item.modify":
				continue
			for actor in w.components.query(["controlled", "position"]):
				var res: Dictionary = apply(w, int(actor), int(c.get("item", -1)), int(c.get("consumable", -1)))
				if not bool(res.get("ok", false)):
					w.events.publish({"type": "modification.refused", "entity": int(actor), "reason": String(res.get("reason", "unknown"))})
	)


# The one entry point. Returns {ok, reason} in the shape treatment.gd and SimInfection's responses
# already use, plus `outcome` on success so a caller can say what happened without re-deriving it.
static func apply(world: Variant, actor: int, item: int, consumable: int) -> Dictionary:
	var spec: Variant = spec_of(world, consumable)
	if not (spec is Dictionary):
		return {"ok": false, "reason": "not-a-consumable"}
	var operation: String = String((spec as Dictionary).get("operation", ""))
	if not OPERATIONS.has(operation):
		return {"ok": false, "reason": "unknown-operation"}

	var base: Variant = SimItems.item_base_of(world, item)
	if not (base is Dictionary):
		return {"ok": false, "reason": "no-such-item"}
	var item_class: String = SimItems.base_class(base as Dictionary)
	var applies: Variant = (spec as Dictionary).get("appliesTo")
	if applies is Array and not (applies as Array).is_empty() and not (applies as Array).has(item_class):
		return {"ok": false, "reason": "wrong-item-class"}

	var hands: int = _hand_state(world, actor)
	if hands == SimHealth.PartState.Unusable:
		# docs/11: "a wounded crafter should not be at the bench". Two ruined hands is not a
		# penalty, it is a refusal.
		return {"ok": false, "reason": "hands-unusable"}

	# Whether the operation *can* do anything is checked before the consumable is spent, so a
	# Scrap Kit is never burned on an item with no free slot. A failed roll still spends it; being
	# refused up front does not.
	var ready: Dictionary = _can_perform(world, item, operation)
	if not bool(ready.get("ok", false)):
		return ready

	# Spent by base id through needs.gd's one consume path, which already handles a stack of
	# three duct tapes becoming a stack of two. Consumables of one base are fungible, so which
	# entity in the stack goes is not a decision this module should be making.
	var consumable_base: Dictionary = SimItems.item_base_of(world, consumable) as Dictionary
	if not SimNeeds.consume_base(world, actor, String(consumable_base.get("id", ""))):
		return {"ok": false, "reason": "no-consumable"}

	var rng: Variant = world.rng.stream(STREAM)
	var craft: int = SimSkills.points(world, actor, "Craft")
	var outcome: String = _outcome(world, rng, craft, hands)
	if outcome != "success":
		var broke: bool = _damage(world, item)
		world.events.publish({
			"type": "modification.failed", "entity": actor, "item": item,
			"operation": operation, "broke": broke,
		})
		return {"ok": true, "reason": "", "outcome": "broken" if broke else "failed"}

	# Injured hands cancel the Craft tier bias rather than inverting it: a good crafter working
	# hurt is an ordinary one, never worse than a novice.
	var bias: float = 0.0 if hands != SimHealth.PartState.Unhurt else _tier_bias(craft)
	var changed: Dictionary = _perform(world, item, item_class, operation, rng, bias)
	SimItems.reapply_affix_modifiers(world, item)
	world.events.publish({
		"type": "modification.applied", "entity": actor, "item": item,
		"operation": operation, "affix": String(changed.get("affix", "")),
	})
	return {"ok": true, "reason": "", "outcome": "success", "affix": String(changed.get("affix", ""))}


# The `modification` block on a consumable's item base, or null if it has none.
static func spec_of(world: Variant, consumable: int) -> Variant:
	var base: Variant = SimItems.item_base_of(world, consumable)
	if not (base is Dictionary):
		return null
	var spec: Variant = (base as Dictionary).get("modification")
	return spec if spec is Dictionary else null


# --- operations -----------------------------------------------------------------------------

# Whether the operation has anything to work with, checked before the consumable is spent.
static func _can_perform(world: Variant, item: int, operation: String) -> Dictionary:
	var aff: Variant = world.components.get_component(item, "affixes")
	if not (aff is Dictionary):
		return {"ok": false, "reason": "no-affix-block"}
	var rolled: Array = _all_rolled(aff as Dictionary)
	match operation:
		"reroll":
			if rolled.is_empty():
				return {"ok": false, "reason": "no-affixes"}
		"add":
			if _free_slots(world, item, aff as Dictionary) <= 0:
				return {"ok": false, "reason": "no-free-slot"}
	return {"ok": true, "reason": ""}


static func _perform(world: Variant, item: int, item_class: String, operation: String, rng: Variant, bias: float) -> Dictionary:
	var aff: Dictionary = world.components.get_component(item, "affixes") as Dictionary
	match operation:
		"reroll":
			return _reroll(world, aff, item_class, rng, bias)
		"add":
			return _add(world, aff, item_class, rng, bias)
	return {}


# Duct Tape. One existing affix, chosen at random, rerolled: a new tier drawn for the same affix
# id. Unconditional -- it does not keep the better of the two, because docs/11 is explicit that
# rerolling the one you loved is the risk you are taking.
static func _reroll(world: Variant, aff: Dictionary, item_class: String, rng: Variant, bias: float) -> Dictionary:
	var slots: Array = []
	for slot in ["prefixes", "suffixes"]:
		for entry in aff.get(slot, []) as Array:
			slots.append({"slot": slot, "entry": entry})
	if slots.is_empty():
		return {}
	var pick: Dictionary = slots[int(rng.call("int_range", 0, slots.size() - 1))] as Dictionary
	var rolled: Dictionary = pick["entry"] as Dictionary
	var affix: Variant = SimItems.content_entry(world, "affix", String(rolled["id"]))
	if not (affix is Dictionary):
		return {}
	rolled["tier"] = _biased_affix_tier(affix as Dictionary, rng, bias)
	return {"affix": String(rolled["id"])}


# Scrap Kit. One affix added to a free slot, drawn from the pool for this item's class and never
# duplicating one the item already carries -- a second copy of the same affix would stack two
# modifiers from one source, which is not what "add one affix" means.
static func _add(world: Variant, aff: Dictionary, item_class: String, rng: Variant, bias: float) -> Dictionary:
	var have: Dictionary = {}
	for entry in _all_rolled(aff):
		have[String((entry as Dictionary)["id"])] = true
	# Prefixes first when the split allows it, matching roll_affixes' own ceil/floor split.
	for slot in ["prefix", "suffix"]:
		var bag: Array = []
		for candidate in SimItems.affix_pool(world, item_class, slot):
			if not have.has(String((candidate as Dictionary)["id"])):
				bag.append(candidate)
		if bag.is_empty():
			continue
		var affix: Dictionary = bag[int(rng.call("int_range", 0, bag.size() - 1))] as Dictionary
		var rolled: Dictionary = {"id": String(affix["id"]), "tier": _biased_affix_tier(affix, rng, bias)}
		(aff[("prefixes" if slot == "prefix" else "suffixes")] as Array).append(rolled)
		return {"affix": String(affix["id"])}
	return {}


# How many more affixes this item's tier allows. Reads the same TIERS table generation does, so a
# Scrap Kit can never take an item past what its tier would have rolled naturally.
static func _free_slots(world: Variant, item: int, aff: Dictionary) -> int:
	return SimItems.affix_capacity(world, item) - _all_rolled(aff).size()


static func _all_rolled(aff: Dictionary) -> Array:
	var out: Array = []
	out.append_array(aff.get("prefixes", []) as Array)
	out.append_array(aff.get("suffixes", []) as Array)
	return out


# --- the odds --------------------------------------------------------------------------------

# SimItems._roll_affix_tier's weighted draw, with the later (better) entries scaled up by `bias`.
# The tier array is ordered best-last by convention -- see any entry in content/affixes -- so
# biasing toward the tail is biasing toward quality, which is what docs/11 asks Craft to do.
static func _biased_affix_tier(affix: Dictionary, rng: Variant, bias: float) -> int:
	var tiers: Variant = affix.get("tiers")
	if not (tiers is Array) or (tiers as Array).is_empty():
		return 0
	var arr: Array = tiers as Array
	var weights: Array = []
	var total: float = 0.0
	for i in arr.size():
		var step: float = 0.0 if arr.size() <= 1 else float(i) / float(arr.size() - 1)
		var w: float = float((arr[i] as Dictionary).get("weight", 0)) * (1.0 + bias * step)
		weights.append(w)
		total += w
	if total <= 0.0:
		return 0
	var roll: float = float(rng.call("float_range", 0.0, total))
	for i in weights.size():
		roll -= float(weights[i])
		if roll < 0.0:
			return i
	return arr.size() - 1


static func _tier_bias(craft: int) -> float:
	return minf(MAX_TIER_BIAS, float(maxi(0, craft)) * CRAFT_TIER_BIAS_PER_POINT)


static func failure_chance(craft: int, hands: int) -> float:
	var chance: float = BASE_FAILURE - float(maxi(0, craft)) * CRAFT_FAILURE_RELIEF + TRAIT_FAILURE_SHIFT
	if hands != SimHealth.PartState.Unhurt:
		chance += HURT_HANDS_FAILURE
	return maxf(MIN_FAILURE, chance)


static func _outcome(world: Variant, rng: Variant, craft: int, hands: int) -> String:
	return "failed" if float(rng.call("float_range", 0.0, 1.0)) < failure_chance(craft, hands) else "success"


# The worse of the two hands, as a PartState. Compared as states rather than raw integrity: a hand
# maxes at 10 and a torso at 40, so `body[part] < 15` means "critically injured" on one and
# "perfectly fine" on the other. SimHealth.part_state is the one place that normalises.
static func _hand_state(world: Variant, actor: int) -> int:
	var body: Variant = world.components.get_component(actor, "body")
	if not (body is Dictionary):
		return SimHealth.PartState.Unhurt
	var worst: int = SimHealth.PartState.Unhurt
	var usable: int = 0
	var counted: int = 0
	for part in ["hand_left", "hand_right"]:
		var state: Variant = SimHealth.part_state(body as Dictionary, part)
		if state == null:
			continue
		counted += 1
		if int(state) != SimHealth.PartState.Unusable:
			usable += 1
		worst = maxi(worst, int(state))
	# One working hand is still a hand. Only a crafter with neither is refused outright, so the
	# worst state is downgraded to BadlyHurt while any hand still works.
	if counted > 0 and usable > 0 and worst == SimHealth.PartState.Unusable:
		return SimHealth.PartState.BadlyHurt
	return worst


# Failure damages; failure on an already-degraded item breaks it. Returns whether it broke.
static func _damage(world: Variant, item: int) -> bool:
	var c: Variant = world.components.get_component(item, "condition")
	if not (c is Dictionary):
		return false
	var cond: Dictionary = c as Dictionary
	var before: float = float(cond.get("current", SimItems.FULL_CONDITION))
	if before < CRITICAL_BELOW:
		# Broken outright, ceiling included, so repair cannot bring it back -- docs/10's "then it
		# is scrap forever", arrived at by one bad roll on something already failing rather than
		# by attrition. Reachable only from a degraded item, so a fresh find is never one roll
		# from scrap.
		cond["current"] = 0.0
		cond["ceiling"] = 0.0
		return true
	cond["current"] = maxf(0.0, before - FAILURE_CONDITION_LOSS)
	return false

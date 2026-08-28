extends SceneTree
# Modification: all seven currency-grade consumables docs/11 names, plus the two things that make
# them a gamble rather than a button -- skill- and trait-weighted outcomes, and failure that
# consumes and damages.
#
# What this gate is really holding down:
#
#  1. **The consumable is spent whatever happens, and the item changes.** docs/11's whole argument
#     is that modification is a gamble; a reroll that quietly kept the better outcome, or a
#     failure that refunded the tape, would make it a button. Measured on the affix block and the
#     stack count, never on the function having returned "ok".
#  2. **A Scrap Kit cannot exceed the tier's own capacity.** The tier is what decides how many
#     affixes an item may carry, at the bench exactly as at generation.
#  3. **The odds move in the directions docs/11 says.** Craft down on failure and up on affix
#     tier; injured hands up on failure; two ruined hands refuse outright.
#  4. **Every declared operation exists.** No schema can assert that a content string names an
#     entry in a GDScript registry, so this does.
#  5. **Whetstone, Gun Oil, Solvent, Machinist's Gauge and Salvage Rights each resolve, apply only
#     to their declared classes, refuse everything else, and are findable in a loot table** -- the
#     same dead-socket shape `check_m2_attach.gd` catches for attachments.
#
# Every assertion carries a true negative. A gate that cannot fail is worse than no gate.

const World = preload("res://sim/world.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimMods = preload("res://sim/modules/modification.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const WEAPON: String = "item.axe.fire"
const TAPE: String = "item.tape.duct"
const KIT: String = "item.kit.scrap"
const WHETSTONE: String = "item.whetstone"
const GUN_OIL: String = "item.oil.gun"
const SOLVENT: String = "item.solvent"
const GAUGE: String = "item.gauge.machinist"
const SALVAGE_RIGHTS: String = "item.rights.salvage"
# Enough draws that a rate is a rate. Modification is random by design, so every odds assertion
# here is a distribution rather than a single roll.
const ROLLS: int = 3000

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _every_declared_operation_exists() and ok
	ok = _duct_tape_rerolls_one_affix_and_is_spent() and ok
	ok = _a_scrap_kit_adds_one_and_never_exceeds_the_tier() and ok
	ok = _craft_moves_both_odds_and_hurt_hands_move_one_back() and ok
	ok = _failure_damages_and_a_degraded_item_breaks() and ok
	ok = _a_refusal_costs_nothing() and ok
	ok = _five_more_consumables_resolve_apply_and_refuse_and_are_findable() and ok
	if ok:
		print("MODS_OK operations resolve, tape rerolls, a kit adds inside the tier, craft and hands move the odds, failure damages")
		quit(0)
	else:
		push_error("MODS_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = 5150) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 24, "height": 24, "walls": []},
		"player": {"id": 0, "x": 12.5, "y": 12.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimInventory.make_inventory(w, w.player)
	SimSkills.attach(w, w.player)
	return w


# A weapon at a named tier, so affix capacity is a known quantity rather than whatever the tier
# roll happened to give.
func _weapon(w: Variant, tier: String) -> int:
	return SimItems.spawn_item(w, WEAPON, {"tier": tier})


func _give(w: Variant, base_id: String, count: int = 3) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		push_error("could not stow %s" % base_id)
	return item


func _stack(w: Variant, item: int) -> int:
	var s: Variant = w.components.get_component(item, "stack")
	return int((s as Dictionary).get("count", 1)) if s is Dictionary else 1


func _affixes(w: Variant, item: int) -> Array:
	var aff: Variant = w.components.get_component(item, "affixes")
	if not (aff is Dictionary):
		return []
	var out: Array = []
	out.append_array((aff as Dictionary).get("prefixes", []) as Array)
	out.append_array((aff as Dictionary).get("suffixes", []) as Array)
	return out


# A stable fingerprint of the affix block: which affixes at which tiers.
func _fingerprint(w: Variant, item: int) -> String:
	var parts: Array = []
	for a in _affixes(w, item):
		parts.append("%s@%d" % [String((a as Dictionary)["id"]), int((a as Dictionary)["tier"])])
	parts.sort()
	return ",".join(PackedStringArray(parts))


func _condition(w: Variant, item: int) -> float:
	var c: Variant = w.components.get_component(item, "condition")
	return float((c as Dictionary).get("current", 1.0)) if c is Dictionary else -1.0


func _set_hands(w: Variant, state: String) -> void:
	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	for part in ["hand_left", "hand_right"]:
		match state:
			"hurt":
				# Below BADLY_HURT_BELOW of a hand's max of 10, but not destroyed.
				body[part] = 1.0
			"gone":
				body[part] = 0.0
			_:
				body[part] = float(int(SimHealth.max_of(body, part)))


# --- assertions ---------------------------------------------------------------------------

# No schema can assert that a content string names an entry in a GDScript registry, and docs/11's
# content-shape section makes that string load-bearing: "adding a consumable is a data entry,
# provided the operation it names already exists."
func _every_declared_operation_exists() -> bool:
	var declared: Dictionary = {}
	var classes: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = tree[path]
		if not (value is Array):
			continue
		for entry in value as Array:
			var e: Dictionary = entry as Dictionary
			classes[String(e.get("class", ""))] = true
			var block: Variant = e.get("modification")
			if not (block is Dictionary):
				continue
			declared[String(e.get("id", ""))] = block as Dictionary
	if declared.is_empty():
		push_error("no item declares a `modification` block, so this gate is asserting nothing")
		return false

	for id in declared.keys():
		var block: Dictionary = declared[id] as Dictionary
		var operation: String = String(block.get("operation", ""))
		if not SimMods.OPERATIONS.has(operation):
			push_error("%s declares operation \"%s\", which is not in SimModification.OPERATIONS %s" % [id, operation, str(SimMods.OPERATIONS)])
			return false
		var applies: Variant = block.get("appliesTo")
		if not (applies is Array) or (applies as Array).is_empty():
			push_error("%s declares no appliesTo" % id)
			return false
		for cls in applies as Array:
			if not classes.has(String(cls)):
				push_error("%s applies to class \"%s\", which no item base has" % [id, String(cls)])
				return false

	# Both slice-scope consumables must actually exist, or the assertions below are testing a
	# fixture rather than the shipped game.
	for required in [TAPE, KIT]:
		if not declared.has(required):
			push_error("%s ships no `modification` block, but docs/23's slice scope names it" % required)
			return false
	# The true negative: the registry must reject something nobody implemented.
	if SimMods.OPERATIONS.has("transmute"):
		push_error("the operation registry answered for an operation nobody wrote")
		return false
	print("OPERATIONS OK %d consumables declared (%s), every operation in the registry and every class real" % [declared.size(), str(declared.keys())])
	return true


# Duct Tape: one existing affix rerolled, chosen at random, and the tape gone. Measured on the
# affix block changing and the stack dropping, not on the call returning ok.
func _duct_tape_rerolls_one_affix_and_is_spent() -> bool:
	var changed: int = 0
	var same_set: int = 0
	var spent: int = 0
	var attempts: int = 0
	for seed_val in range(6000, 6060):
		var w: Variant = _world(seed_val)
		var axe: int = _weapon(w, "field_tested")
		if _affixes(w, axe).size() < 2:
			continue
		attempts += 1
		var tape: int = _give(w, TAPE, 3)
		var before_ids: Array = []
		for a in _affixes(w, axe):
			before_ids.append(String((a as Dictionary)["id"]))
		before_ids.sort()
		var before: String = _fingerprint(w, axe)
		var before_stack: int = _stack(w, tape)

		var res: Dictionary = SimMods.apply(w, w.player, axe, tape)
		if not bool(res.get("ok", false)):
			push_error("duct tape on a field-tested axe was refused: %s" % str(res))
			return false
		if _stack(w, tape) == before_stack:
			push_error("a modification did not spend the tape: stack stayed at %d" % before_stack)
			return false
		spent += 1
		if String(res.get("outcome", "")) != "success":
			continue
		var after_ids: Array = []
		for a in _affixes(w, axe):
			after_ids.append(String((a as Dictionary)["id"]))
		after_ids.sort()
		# A reroll changes a tier, never the set of affixes -- that is what separates it from a
		# Scrap Kit and from a Solvent.
		if after_ids != before_ids:
			push_error("a reroll changed which affixes the item has: %s -> %s" % [str(before_ids), str(after_ids)])
			return false
		same_set += 1
		if _fingerprint(w, axe) != before:
			changed += 1

	if attempts < 20:
		push_error("SKIP-WORTHY: only %d field-tested axes carried two affixes, too few to measure a reroll" % attempts)
		return false
	if spent != attempts:
		push_error("%d of %d modifications spent the consumable -- it must go whatever happens" % [spent, attempts])
		return false
	if changed == 0:
		push_error("%d successful rerolls and not one landed on a different tier" % same_set)
		return false
	# The true negative: a scavenged axe carries no affixes, so there is nothing to reroll and the
	# tape must be refused rather than wasted.
	var bare: Variant = _world(6100)
	var plain: int = _weapon(bare, "scavenged")
	var plain_tape: int = _give(bare, TAPE, 3)
	var refused: Dictionary = SimMods.apply(bare, bare.player, plain, plain_tape)
	if bool(refused.get("ok", false)) or String(refused.get("reason", "")) != "no-affixes":
		push_error("duct tape on an affix-less axe returned %s, expected a no-affixes refusal" % str(refused))
		return false
	print("TAPE OK %d rerolls, all spent the tape, the affix set never changed, %d landed on a different tier; an affix-less item refuses" % [attempts, changed])
	return true


# Scrap Kit: one affix added, and never past what the item's tier allows.
func _a_scrap_kit_adds_one_and_never_exceeds_the_tier() -> bool:
	var w: Variant = _world(6200)
	var axe: int = _weapon(w, "modified")
	var capacity: int = SimItems.affix_capacity(w, axe)
	if capacity <= 0:
		push_error("a modified item has affix capacity %d, so there is no free slot to fill" % capacity)
		return false

	# Strip it back to nothing so there are slots to fill, the way a Solvent eventually will.
	var aff: Dictionary = w.components.get_component(axe, "affixes") as Dictionary
	aff["prefixes"] = []
	aff["suffixes"] = []
	SimItems.reapply_affix_modifiers(w, axe)

	var added: int = 0
	for _i in capacity + 3:
		var kit: int = _give(w, KIT, 1)
		var res: Dictionary = SimMods.apply(w, w.player, axe, kit)
		if not bool(res.get("ok", false)):
			if String(res.get("reason", "")) == "no-free-slot":
				break
			push_error("a scrap kit was refused for %s" % str(res.get("reason", "")))
			return false
		if String(res.get("outcome", "")) == "success":
			added += 1
	var carried: int = _affixes(w, axe).size()
	if carried > capacity:
		push_error("an item at capacity %d carries %d affixes -- a kit went past the tier" % [capacity, carried])
		return false
	if added == 0:
		push_error("no scrap kit ever succeeded over %d attempts" % (capacity + 3))
		return false
	# Never a duplicate: two copies of one affix would stack two modifiers from one source, which
	# is not what "add one affix" means.
	var seen: Dictionary = {}
	for a in _affixes(w, axe):
		var id: String = String((a as Dictionary)["id"])
		if seen.has(id):
			push_error("a scrap kit added a second copy of %s" % id)
			return false
		seen[id] = true

	# The true negative: a full item refuses, and refusing costs nothing.
	var full: Variant = _world(6300)
	var loaded: int = _weapon(full, "modified")
	while _affixes(full, loaded).size() < SimItems.affix_capacity(full, loaded):
		# Fill by hand rather than by rolling, so the refusal below is about capacity alone.
		var pool: Array = SimItems.affix_pool(full, "weapon.melee", "prefix")
		if pool.is_empty():
			break
		var block: Dictionary = full.components.get_component(loaded, "affixes") as Dictionary
		(block["prefixes"] as Array).append({"id": String((pool[0] as Dictionary)["id"]), "tier": 0})
	var full_kit: int = _give(full, KIT, 2)
	var before_stack: int = _stack(full, full_kit)
	var denied: Dictionary = SimMods.apply(full, full.player, loaded, full_kit)
	if bool(denied.get("ok", false)) or String(denied.get("reason", "")) != "no-free-slot":
		push_error("a scrap kit on a full item returned %s, expected no-free-slot" % str(denied))
		return false
	if _stack(full, full_kit) != before_stack:
		push_error("a refused scrap kit was spent anyway")
		return false
	print("KIT OK filled to the tier's capacity of %d (%d added, no duplicates); a full item refuses and keeps the kit" % [capacity, added])
	return true


# docs/11: Craft weights rolls toward higher affix tiers and reduces failure; injured hands make
# outcomes worse; two ruined hands are a refusal, not a penalty.
func _craft_moves_both_odds_and_hurt_hands_move_one_back() -> bool:
	var novice: float = SimMods.failure_chance(0, SimHealth.PartState.Unhurt)
	var expert: float = SimMods.failure_chance(6, SimHealth.PartState.Unhurt)
	var hurt: float = SimMods.failure_chance(6, SimHealth.PartState.BadlyHurt)
	if expert >= novice:
		push_error("six Craft points did not reduce the failure chance: %.3f against %.3f" % [expert, novice])
		return false
	if hurt <= expert:
		push_error("injured hands did not raise an expert's failure chance: %.3f against %.3f" % [hurt, expert])
		return false
	if SimMods.failure_chance(999, SimHealth.PartState.Unhurt) < SimMods.MIN_FAILURE:
		push_error("an arbitrarily good crafter drove the failure chance below MIN_FAILURE -- a bench that cannot fail is not a gamble")
		return false

	# The tier bias, measured on rolls rather than on the constant. Mean affix tier over many
	# draws must rise with Craft, using one affix so the comparison is like for like.
	var w: Variant = _world(6400)
	var pool: Array = SimItems.affix_pool(w, "weapon.melee", "prefix")
	if pool.is_empty():
		push_error("SKIP-WORTHY: no melee prefix affixes in content, so there is no tier to bias")
		return false
	var affix: Dictionary = pool[0] as Dictionary
	var tiers: Variant = affix.get("tiers")
	if not (tiers is Array) or (tiers as Array).size() < 2:
		push_error("SKIP-WORTHY: %s declares fewer than two tiers, so a bias cannot show" % String(affix["id"]))
		return false

	var rng: Variant = w.rng.stream(SimMods.STREAM)
	var flat: float = _mean_tier(affix, rng, 0.0)
	var biased: float = _mean_tier(affix, rng, SimMods.MAX_TIER_BIAS)
	if biased <= flat:
		push_error("the craft bias did not raise the mean affix tier: %.3f against %.3f over %d rolls each" % [biased, flat, ROLLS])
		return false

	# Two ruined hands refuse outright rather than merely rolling badly, and the control is the
	# identical actor with hands intact.
	var refuse: Variant = _world(6500)
	var axe: int = _weapon(refuse, "field_tested")
	var tape: int = _give(refuse, TAPE, 3)
	_set_hands(refuse, "gone")
	var denied: Dictionary = SimMods.apply(refuse, refuse.player, axe, tape)
	if bool(denied.get("ok", false)) or String(denied.get("reason", "")) != "hands-unusable":
		push_error("a crafter with two destroyed hands returned %s, expected hands-unusable" % str(denied))
		return false
	if _stack(refuse, tape) != 3:
		push_error("a refusal for ruined hands spent the tape anyway")
		return false
	_set_hands(refuse, "whole")
	if not bool(SimMods.apply(refuse, refuse.player, axe, tape).get("ok", false)):
		push_error("the same actor with hands intact was still refused, so the refusal is not about the hands")
		return false
	print("ODDS OK failure %.3f novice -> %.3f expert -> %.3f expert with hurt hands (floor %.2f); mean affix tier %.3f -> %.3f under bias; ruined hands refuse and keep the tape" % [
		novice, expert, hurt, SimMods.MIN_FAILURE, flat, biased,
	])
	return true


func _mean_tier(affix: Dictionary, rng: Variant, bias: float) -> float:
	var total: int = 0
	for _i in ROLLS:
		total += SimMods._biased_affix_tier(affix, rng, bias)
	return float(total) / float(ROLLS)


# "Failure consumes the consumable and damages the item's condition; a critical failure on a badly
# degraded item can break it outright."
func _failure_damages_and_a_degraded_item_breaks() -> bool:
	# Sound item: a failure costs condition and nothing else.
	var w: Variant = _world(6600)
	var axe: int = _weapon(w, "field_tested")
	var before: float = _condition(w, axe)
	var broke_sound: bool = SimMods._damage(w, axe)
	if broke_sound:
		push_error("a failure broke a sound item outright -- a fresh find must never be one roll from scrap")
		return false
	if _condition(w, axe) >= before:
		push_error("a failure on a sound item cost no condition: %.3f -> %.3f" % [before, _condition(w, axe)])
		return false
	if absf((before - _condition(w, axe)) - SimMods.FAILURE_CONDITION_LOSS) > 0.001:
		push_error("a failure cost %.3f condition, expected FAILURE_CONDITION_LOSS %.3f" % [before - _condition(w, axe), SimMods.FAILURE_CONDITION_LOSS])
		return false

	# Degraded item: the same failure breaks it, ceiling included, so repair cannot bring it back.
	var cond: Dictionary = w.components.get_component(axe, "condition") as Dictionary
	cond["current"] = SimMods.CRITICAL_BELOW - 0.01
	if not SimMods._damage(w, axe):
		push_error("a failure below CRITICAL_BELOW %.2f did not break the item" % SimMods.CRITICAL_BELOW)
		return false
	if _condition(w, axe) != 0.0 or float(cond.get("ceiling", 1.0)) != 0.0:
		push_error("a broken item kept condition %.3f / ceiling %.3f" % [_condition(w, axe), float(cond.get("ceiling", 1.0))])
		return false

	# And the true negative for the boundary: just above it, the same call damages rather than
	# breaks, so CRITICAL_BELOW is a threshold and not a coin toss.
	var edge: Variant = _world(6700)
	var other: int = _weapon(edge, "field_tested")
	var edge_cond: Dictionary = edge.components.get_component(other, "condition") as Dictionary
	edge_cond["current"] = SimMods.CRITICAL_BELOW + 0.01
	if SimMods._damage(edge, other):
		push_error("an item just above CRITICAL_BELOW broke, so the threshold is not where it says")
		return false
	print("FAILURE OK a sound item loses %.2f condition and survives; below %.2f the same failure breaks it, ceiling included; just above it does not" % [
		SimMods.FAILURE_CONDITION_LOSS, SimMods.CRITICAL_BELOW,
	])
	return true


# Every refusal path must leave the consumable and the item exactly as it found them. A gamble you
# were not allowed to take must not cost anything.
func _a_refusal_costs_nothing() -> bool:
	var cases: Array = [
		{"reason": "not-a-consumable", "consumable": "item.food.canned", "item": WEAPON},
		{"reason": "wrong-item-class", "consumable": KIT, "item": "item.food.canned"},
	]
	for case in cases:
		var c: Dictionary = case as Dictionary
		var w: Variant = _world(6800)
		var target: int = SimItems.spawn_item(w, String(c["item"]), {"tier": "field_tested"})
		var tool: int = _give(w, String(c["consumable"]), 2)
		var before_stack: int = _stack(w, tool)
		var before_affixes: String = _fingerprint(w, target)
		var before_condition: float = _condition(w, target)
		var res: Dictionary = SimMods.apply(w, w.player, target, tool)
		if bool(res.get("ok", false)) or String(res.get("reason", "")) != String(c["reason"]):
			push_error("expected refusal %s, got %s" % [String(c["reason"]), str(res)])
			return false
		if _stack(w, tool) != before_stack:
			push_error("refusal %s spent the consumable" % String(c["reason"]))
			return false
		if _fingerprint(w, target) != before_affixes or _condition(w, target) != before_condition:
			push_error("refusal %s changed the item" % String(c["reason"]))
			return false
	print("REFUSALS OK %d refusal paths each cost nothing -- consumable, affixes and condition all untouched" % cases.size())
	return true


# A field-tested axe carrying at least one rolled affix, or {} after 200 seeds found none -- the
# same defensive search TAPE OK above runs over 60 seeds, just returning the first hit instead of
# counting a rate.
func _axe_with_affix(seed_base: int) -> Dictionary:
	for seed_val in range(seed_base, seed_base + 200):
		var w: Variant = _world(seed_val)
		var axe: int = _weapon(w, "field_tested")
		if not _affixes(w, axe).is_empty():
			return {"world": w, "axe": axe}
	return {}


# Whetstone, Gun Oil, Solvent, Machinist's Gauge, Salvage Rights: each resolves, applies only to
# the classes it declares, refuses everything else, and can actually be found. Findability is the
# dead-socket check `check_m2_attach.gd` runs for attachments, done the same way here: read the
# loot tree by path rather than assume a shape only items and affixes have.
func _five_more_consumables_resolve_apply_and_refuse_and_are_findable() -> bool:
	var droppable: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for table_v in value as Array:
			for entry_v in (table_v as Dictionary).get("entries", []) as Array:
				droppable[String((entry_v as Dictionary).get("item", ""))] = true
	for cid in [WHETSTONE, GUN_OIL, SOLVENT, GAUGE, SALVAGE_RIGHTS]:
		if not droppable.has(cid):
			push_error("%s is in no loot table, so it cannot be found" % cid)
			return false

	# Whetstone: melee only.
	var found1: Dictionary = _axe_with_affix(7000)
	if found1.is_empty():
		push_error("SKIP-WORTHY: no field-tested axe over 200 seeds carried an affix for whetstone to reroll")
		return false
	var w1: Variant = found1["world"]
	var axe1: int = int(found1["axe"])
	var stone: int = _give(w1, WHETSTONE, 3)
	var res1: Dictionary = SimMods.apply(w1, w1.player, axe1, stone)
	if not bool(res1.get("ok", false)):
		push_error("whetstone on a field-tested axe carrying an affix was refused: %s" % str(res1))
		return false
	var pistol1: int = SimItems.spawn_item(w1, "item.pistol.service", {"tier": "field_tested"})
	var stone2: int = _give(w1, WHETSTONE, 3)
	var res1b: Dictionary = SimMods.apply(w1, w1.player, pistol1, stone2)
	if bool(res1b.get("ok", false)) or String(res1b.get("reason", "")) != "wrong-item-class":
		push_error("whetstone on a pistol returned %s, expected wrong-item-class" % str(res1b))
		return false

	# Gun Oil: firearms only, restores condition toward the ceiling, refuses at the ceiling.
	var w2: Variant = _world(7100)
	var pistol2: int = SimItems.spawn_item(w2, "item.pistol.service", {"tier": "scavenged"})
	var cond2: Dictionary = w2.components.get_component(pistol2, "condition") as Dictionary
	cond2["current"] = 0.5
	var oil: int = _give(w2, GUN_OIL, 3)
	var before2: float = _condition(w2, pistol2)
	var res2: Dictionary = SimMods.apply(w2, w2.player, pistol2, oil)
	if not bool(res2.get("ok", false)):
		push_error("gun oil on a damaged pistol was refused: %s" % str(res2))
		return false
	if String(res2.get("outcome", "")) == "success" and _condition(w2, pistol2) <= before2:
		push_error("a successful gun oil application did not raise condition: %.3f -> %.3f" % [before2, _condition(w2, pistol2)])
		return false
	var axe2: int = _weapon(w2, "field_tested")
	var oil2: int = _give(w2, GUN_OIL, 3)
	var res2b: Dictionary = SimMods.apply(w2, w2.player, axe2, oil2)
	if bool(res2b.get("ok", false)) or String(res2b.get("reason", "")) != "wrong-item-class":
		push_error("gun oil on an axe returned %s, expected wrong-item-class" % str(res2b))
		return false
	var pistol3: int = SimItems.spawn_item(w2, "item.pistol.service", {"tier": "scavenged"})
	var oil3: int = _give(w2, GUN_OIL, 3)
	var res2c: Dictionary = SimMods.apply(w2, w2.player, pistol3, oil3)
	if bool(res2c.get("ok", false)) or String(res2c.get("reason", "")) != "already-at-ceiling":
		push_error("gun oil on a fresh pistol already at the ceiling returned %s, expected already-at-ceiling" % str(res2c))
		return false

	# Solvent: strips every affix and resets the tier, applies to affix-bearing classes only.
	var found3: Dictionary = _axe_with_affix(7200)
	if found3.is_empty():
		push_error("SKIP-WORTHY: no field-tested axe over 200 seeds carried an affix for solvent to strip")
		return false
	var w3: Variant = found3["world"]
	var axe3: int = int(found3["axe"])
	var solv: int = _give(w3, SOLVENT, 2)
	var res3: Dictionary = SimMods.apply(w3, w3.player, axe3, solv)
	if not bool(res3.get("ok", false)):
		push_error("solvent on a field-tested axe carrying an affix was refused: %s" % str(res3))
		return false
	if String(res3.get("outcome", "")) == "success":
		if not _affixes(w3, axe3).is_empty():
			push_error("a successful solvent left affixes behind: %s" % str(_affixes(w3, axe3)))
			return false
		if SimItems.tier_of(w3, axe3) != "scavenged":
			push_error("a successful solvent left the tier at %s, expected scavenged" % SimItems.tier_of(w3, axe3))
			return false
	var food3: int = SimItems.spawn_item(w3, "item.food.canned", {"tier": "scavenged"})
	var solv2: int = _give(w3, SOLVENT, 2)
	var res3b: Dictionary = SimMods.apply(w3, w3.player, food3, solv2)
	if bool(res3b.get("ok", false)) or String(res3b.get("reason", "")) != "wrong-item-class":
		push_error("solvent on canned food returned %s, expected wrong-item-class" % str(res3b))
		return false

	# Machinist's Gauge: reroll_chosen targets the named affix, not one drawn at random.
	var found4: Dictionary = _axe_with_affix(7300)
	if found4.is_empty():
		push_error("SKIP-WORTHY: no field-tested axe over 200 seeds carried an affix for the gauge to target")
		return false
	var w4: Variant = found4["world"]
	var axe4: int = int(found4["axe"])
	var target_id: String = String((_affixes(w4, axe4)[0] as Dictionary)["id"])
	var gauge: int = _give(w4, GAUGE, 1)
	var res4: Dictionary = SimMods.apply(w4, w4.player, axe4, gauge, target_id)
	if not bool(res4.get("ok", false)):
		push_error("machinist's gauge naming a carried affix was refused: %s" % str(res4))
		return false
	var gauge2: int = _give(w4, GAUGE, 1)
	var res4b: Dictionary = SimMods.apply(w4, w4.player, axe4, gauge2)
	if bool(res4b.get("ok", false)) or String(res4b.get("reason", "")) != "no-target-affix":
		push_error("machinist's gauge with no target returned %s, expected no-target-affix" % str(res4b))
		return false
	var gauge3: int = _give(w4, GAUGE, 1)
	var res4c: Dictionary = SimMods.apply(w4, w4.player, axe4, gauge3, "affix.nope.not-real")
	if bool(res4c.get("ok", false)) or String(res4c.get("reason", "")) != "no-such-affix":
		push_error("machinist's gauge naming an affix not carried returned %s, expected no-such-affix" % str(res4c))
		return false
	var food4: int = SimItems.spawn_item(w4, "item.food.canned", {"tier": "scavenged"})
	var gauge4: int = _give(w4, GAUGE, 1)
	var res4d: Dictionary = SimMods.apply(w4, w4.player, food4, gauge4, target_id)
	if bool(res4d.get("ok", false)) or String(res4d.get("reason", "")) != "wrong-item-class":
		push_error("machinist's gauge on canned food returned %s, expected wrong-item-class" % str(res4d))
		return false

	# Salvage Rights: one tier up, rerolling everything, and refuses at the top of the ladder.
	var w5: Variant = _world(7400)
	var axe5: int = _weapon(w5, "modified")
	var rights: int = _give(w5, SALVAGE_RIGHTS, 1)
	var res5: Dictionary = SimMods.apply(w5, w5.player, axe5, rights)
	if not bool(res5.get("ok", false)):
		push_error("salvage rights on a modified axe was refused: %s" % str(res5))
		return false
	if String(res5.get("outcome", "")) == "success" and SimItems.tier_of(w5, axe5) != "field_tested":
		push_error("a successful salvage rights left the tier at %s, expected field_tested" % SimItems.tier_of(w5, axe5))
		return false
	var axe_top: int = _weapon(w5, "field_tested")
	var rights2: int = _give(w5, SALVAGE_RIGHTS, 1)
	var res5b: Dictionary = SimMods.apply(w5, w5.player, axe_top, rights2)
	if bool(res5b.get("ok", false)) or String(res5b.get("reason", "")) != "already-max-tier":
		push_error("salvage rights on a field-tested axe returned %s, expected already-max-tier" % str(res5b))
		return false
	var food5: int = SimItems.spawn_item(w5, "item.food.canned", {"tier": "scavenged"})
	var rights3: int = _give(w5, SALVAGE_RIGHTS, 1)
	var res5c: Dictionary = SimMods.apply(w5, w5.player, food5, rights3)
	if bool(res5c.get("ok", false)) or String(res5c.get("reason", "")) != "wrong-item-class":
		push_error("salvage rights on canned food returned %s, expected wrong-item-class" % str(res5c))
		return false

	print("FIVE MORE OK whetstone, gun oil, solvent, machinist's gauge and salvage rights each resolve, apply only to their classes, refuse others, and are all findable")
	return true

extends SceneTree
# The health-bar ban, made mechanical. Port of test/unit/paperdoll.test.ts, which was the
# only thing enforcing this and which left with the TypeScript oracle.
#
# docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable and
# docs/05-health-injury.md#the-condition-view: the screen gets a state and a sentence per
# part and no integrity value, no maximum, and no fraction -- so a fill is not discouraged,
# it is *not computable* from what the screen has.
#
# If this fails because a numeric field was added to the view, that is the moment to
# re-read clause 4, not the moment to widen the assertion.

const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _no_numbers_cross_the_boundary() and ok
	ok = _parts_carry_only_the_allowed_keys() and ok
	ok = _every_part_is_present_and_ordered() and ok
	ok = _damage_changes_state_not_magnitude() and ok
	ok = _sidedness_is_independent() and ok
	ok = _wound_infection_armor_are_true_words_not_numbers() and ok
	ok = _a_body_less_entity_has_no_view() and ok
	if ok:
		print("BAN_HEALTH_BAR_OK no integrity, no maximum, no fraction")
		quit(0)
	else:
		push_error("BAN_HEALTH_BAR_FAIL")
		quit(1)

func _fixture() -> Dictionary:
	return {"seed": 909, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

func _hurt_world() -> Variant:
	# A body damaged unevenly, so every part state is represented and every maximum is a
	# number that *could* leak if the view carried one.
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	var body: Variant = w.components.get_component(w.player, "body")
	var b: Dictionary = body as Dictionary
	var fractions: Dictionary = {
		"head": 1.0, "torso": 0.8,
		"arm_left": 0.5, "arm_right": 0.5,
		"hand_left": 0.2, "hand_right": 0.2,
		"leg_left": 0.05, "leg_right": 0.05,
		"foot_left": 0.0, "foot_right": 0.0,
	}
	for part in fractions.keys():
		if b.has(part):
			b[String(part)] = float(b[String(part)]) * float(fractions[part])
	return w

# The assertion the oracle called "the ban, made mechanical": serialise the whole view and
# assert that no integrity value, no maximum, and no fraction survives into it.
func _no_numbers_cross_the_boundary() -> bool:
	var w: Variant = _hurt_world()
	var view: Dictionary = SimCondition.view(w, w.player)
	if view.is_empty():
		push_error("no view for a survivor with a body")
		return false
	var json: String = JSON.stringify(view)

	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	for part in SimCondition.PART_ORDER:
		if not body.has(part):
			continue
		# The maximum is the number a fill would divide by. The oracle checked this and the
		# fraction below, and deliberately did not substring-search for the integrity
		# itself: a damaged part's integrity is a small number that collides with the state
		# enum beside it, so such a check reports the state as a leak. The key allowlist in
		# _parts_carry_only_the_allowed_keys is the robust half of this gate; these two
		# catch a value smuggled into a string field.
		var maximum: Variant = SimHealth.max_of(body, part)
		if maximum != null and json.contains(":%s" % maximum):
			push_error("%s's maximum (%s) leaked into the view: %s" % [part, maximum, json])
			return false

	# A fraction is the other shape a fill arrives in.
	var fraction := RegEx.new()
	fraction.compile("0\\.\\d+")
	if fraction.search(json) != null:
		push_error("a fraction leaked into the view: %s" % json)
		return false
	print("NO NUMBERS OK")
	return true

# Key allowlist. This is what actually fails when someone adds `integrity` to the view.
func _parts_carry_only_the_allowed_keys() -> bool:
	var w: Variant = _hurt_world()
	var view: Dictionary = SimCondition.view(w, w.player)
	for entry in view["parts"] as Array:
		var d: Dictionary = entry as Dictionary
		for key in d.keys():
			if not SimCondition.PART_KEYS.has(String(key)):
				push_error("part carries a disallowed key '%s'; allowed: %s" % [key, SimCondition.PART_KEYS])
				return false
		for required in SimCondition.PART_KEYS:
			if not d.has(required):
				push_error("part is missing required key '%s'" % required)
				return false
	var top: Array[String] = ["parts", "stance", "worst"]
	for key in view.keys():
		if not top.has(String(key)):
			push_error("view carries a disallowed top-level key '%s'" % key)
			return false
	print("KEYS OK")
	return true

func _every_part_is_present_and_ordered() -> bool:
	var w: Variant = _hurt_world()
	var view: Dictionary = SimCondition.view(w, w.player)
	var seen: Array[String] = []
	for entry in view["parts"] as Array:
		seen.append(String((entry as Dictionary)["part"]))
	if seen != SimCondition.PART_ORDER:
		push_error("parts out of survivor order: %s != %s" % [seen, SimCondition.PART_ORDER])
		return false
	print("ORDER OK")
	return true

# The view must still be *useful*: worse damage has to move the state, or the ban would be
# satisfied by a view that says nothing at all.
func _damage_changes_state_not_magnitude() -> bool:
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	var b: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	var intact: int = int(SimCondition.view(w, w.player)["worst"])
	if intact != 0:
		push_error("an undamaged body should be unhurt, got worst=%d" % intact)
		return false
	for part in SimCondition.PART_ORDER:
		if b.has(part):
			b[part] = 0.0
	var ruined: int = int(SimCondition.view(w, w.player)["worst"])
	if ruined <= intact:
		push_error("a ruined body should report a worse state, got %d after %d" % [ruined, intact])
		return false
	print("STATE OK")
	return true

# The one thing the sided-limb split exists to make possible: docs/05's permanent
# consequences promise "a one-armed survivor," and that promise is only true if damaging
# arm_left leaves arm_right's own view entry alone. Also checks label_of distinguishes the
# two -- "left arm" leaking as "arm_left" would be the same class of leak as a raw number,
# just spelled with letters instead of digits.
func _sidedness_is_independent() -> bool:
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	var b: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	b["arm_left"] = 0.0
	var view: Dictionary = SimCondition.view(w, w.player)
	var by_part: Dictionary = {}
	for entry in view["parts"] as Array:
		var d: Dictionary = entry as Dictionary
		by_part[String(d["part"])] = d
	var left: Dictionary = by_part.get("arm_left", {}) as Dictionary
	var right: Dictionary = by_part.get("arm_right", {}) as Dictionary
	if int(left.get("state", -1)) == int(right.get("state", -1)):
		push_error("arm_left and arm_right reported the same state after only arm_left was ruined")
		return false
	if String(left.get("prose", "")) == String(right.get("prose", "")):
		push_error("left and right arm prose are identical: '%s'" % left.get("prose", ""))
		return false
	print("SIDEDNESS OK left=%s right=%s" % [left.get("prose", ""), right.get("prose", "")])
	return true

# wounded/infected/armored joined the view this session. Same ban, new shapes: a bool and a
# word, checked against real Dictionary/String types (not just "did a number leak" the way
# _no_numbers_cross_the_boundary already checks) and checked for a true positive as well as
# a true negative, since a field that is always false would pass every leak check and still
# be useless.
func _wound_infection_armor_are_true_words_not_numbers() -> bool:
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	w.components.set_component(w.player, "injuries", {"wounds": [
		{"kind": "bite", "presentation": "scratch", "bodyPart": "arm_left", "source": -1, "sustainedAtTick": 0},
	]})
	w.components.set_component(w.player, "zombieInfection", {"exposures": [
		{"source": -1, "bodyPart": "leg_left", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Onset, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false},
	]})
	var vest: int = SimItems.spawn_item(w, "item.vest.scrap", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, vest, "vest"):
		push_error("could not equip item.vest.scrap for the wound/infection/armor check")
		return false

	var by_part: Dictionary = {}
	for entry in SimCondition.view(w, w.player)["parts"] as Array:
		var d: Dictionary = entry as Dictionary
		by_part[String(d["part"])] = d

	for part in SimCondition.PART_ORDER:
		var d: Dictionary = by_part.get(part, {}) as Dictionary
		if not (d.get("wounded") is bool):
			push_error("%s.wounded is not a bool: %s" % [part, d.get("wounded")])
			return false
		if not (d.get("infected") is String):
			push_error("%s.infected is not a String: %s" % [part, d.get("infected")])
			return false
		if not (d.get("armored") is bool):
			push_error("%s.armored is not a bool: %s" % [part, d.get("armored")])
			return false

	# True positives, so this cannot be satisfied by fields that are simply always false.
	if not bool(by_part["arm_left"].get("wounded", false)):
		push_error("arm_left has a recorded wound but wounded=false")
		return false
	if String(by_part["leg_left"].get("infected", "none")) == "none":
		push_error("leg_left has an active exposure but infected='none'")
		return false
	if not bool(by_part["torso"].get("armored", false)):
		push_error("torso is covered by an equipped vest but armored=false")
		return false
	# And a true negative on a part none of this touched.
	var clean: Dictionary = by_part["foot_right"] as Dictionary
	if bool(clean.get("wounded", true)) or String(clean.get("infected", "x")) != "none" or bool(clean.get("armored", true)):
		push_error("foot_right should be untouched, got %s" % str(clean))
		return false
	print("WOUND/INFECTION/ARMOR OK arm_left wounded, leg_left infected, torso armored, foot_right clean")
	return true

func _a_body_less_entity_has_no_view() -> bool:
	var w: Variant = World.new(_fixture())
	var nobody: int = w.entities.call("create") if w.entities.has_method("create") else 9999
	if not SimCondition.view(w, nobody).is_empty():
		push_error("an entity with no body should have no condition view")
		return false
	print("NO BODY OK")
	return true

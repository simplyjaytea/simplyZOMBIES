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

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _no_numbers_cross_the_boundary() and ok
	ok = _parts_carry_only_the_allowed_keys() and ok
	ok = _every_part_is_present_and_ordered() and ok
	ok = _damage_changes_state_not_magnitude() and ok
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
	var fractions: Dictionary = {"head": 1.0, "torso": 0.8, "arms": 0.5, "hands": 0.2, "legs": 0.05, "feet": 0.0}
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

func _a_body_less_entity_has_no_view() -> bool:
	var w: Variant = World.new(_fixture())
	var nobody: int = w.entities.call("create") if w.entities.has_method("create") else 9999
	if not SimCondition.view(w, nobody).is_empty():
		push_error("an entity with no body should have no condition view")
		return false
	print("NO BODY OK")
	return true

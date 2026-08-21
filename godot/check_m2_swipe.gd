extends SceneTree
# The swipe -- the one way a zombie hurts anybody while SimShambler.GRABS_ENABLED is false, and
# therefore the assertion that basic combat is *reachable in ordinary play*: nothing here touches
# the flag for the positive cases, so if a refactor ever routes zombie offense back behind it,
# the cadence assertion below is what goes red.
#
# What is pinned, and why:
#   - the first swipe lands exactly SWIPE_FIRST_TICKS after reach and repeats exactly every
#     SWIPE_RECOVER_TICKS -- the clock is the player's window to step back out, so it is exact,
#     the way the bite cadence is pinned in check_m2_contact.gd;
#   - each swipe records one located "cut" wound (the melee pipeline, not a parallel one);
#   - a swipe is chip damage by construction: never a DeepWound, and never a bite -- no
#     bite.landed, no infection -- because the infection loop stays behind the grab flag and its
#     recorded balance questions must not gain a back door. The infection half carries its own
#     live-channel control (a synthetic bite must still infect this victim) so the absence is a
#     refusal, not a dead subscription;
#   - reach and walls refuse it, the same geometry that refuses a grab;
#   - a holder does not swipe and a held body is not swiped -- inside a grapple the mouth is the
#     threat, and piling swipes onto a hold would change the flip's lethality question unmeasured.

const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCombat = preload("res://sim/combat.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _a_swipe_lands_on_cadence_and_each_leaves_a_wound() and ok
	ok = _reach_and_walls_both_refuse_it() and ok
	ok = _a_swipe_is_chip_damage_never_a_bite() and ok
	ok = _a_grapple_takes_both_bodies_off_the_swipe_menu() and ok
	if ok:
		print("M2_SWIPE_OK a shambler in reach swipes on cadence, wounds land shallow and clean, walls and grapples refuse it")
		quit(0)
	else:
		push_error("M2_SWIPE_FAIL")
		quit(1)


# The check_m2_contact.gd bare-fixture builder: World._init gives movement and a field, and the
# two registered modules are the whole loop under test.
func _world(seed_val: int, walls: Array = []) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": walls},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimShambler.register_module(w, null)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	return w


func _spawn_shambler(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
	SimShambler.make_shambler(w, ent, w.rng.stream("shambler"))
	return ent


# Landed zombie swipes, observed off the bus. A record (Array, not captured ints -- the
# lambda-capture trap) of {tick, target, part} for every attack.connected whose attacker
# carries a shambler component.
func _watch_swipes(w: Variant) -> Array:
	var seen: Array = []
	w.events.subscribe({"id": "gate.watch-swipes", "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		if w.components.has_component(int(e["attacker"]), "shambler"):
			seen.append({"tick": int(w.tick), "target": int(e["target"]), "part": String(e["bodyPart"]), "damage": float(e["damage"])})
	})
	return seen


func _wounds_of(w: Variant, entity: int) -> Array:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return []
	return (inj as Dictionary).get("wounds", []) as Array


func _a_swipe_lands_on_cadence_and_each_leaves_a_wound() -> bool:
	var w: Variant = _world(11)
	SimWounds.register_module(w)
	_spawn_shambler(w, 15.6, 16.5)
	var seen: Array = _watch_swipes(w)
	for i in 200:
		w.step()
	if seen.size() < 3:
		push_error("CADENCE: %d swipes in 200 ticks of standing in reach -- expected at least 3" % seen.size())
		return false
	var first_at: int = int((seen[0] as Dictionary)["tick"])
	if first_at != SimShambler.SWIPE_FIRST_TICKS:
		push_error("CADENCE: first swipe at tick %d, not SWIPE_FIRST_TICKS %d" % [first_at, SimShambler.SWIPE_FIRST_TICKS])
		return false
	for i in range(1, seen.size()):
		var gap: int = int((seen[i] as Dictionary)["tick"]) - int((seen[i - 1] as Dictionary)["tick"])
		if gap != SimShambler.SWIPE_RECOVER_TICKS:
			push_error("CADENCE: gap of %d between swipes, not SWIPE_RECOVER_TICKS %d" % [gap, SimShambler.SWIPE_RECOVER_TICKS])
			return false
	# The swipe scales to the part it lands on, the bite_damage_for shape: every observed hit
	# must carry exactly swipe_damage_for's number, and the ordering hand < head < torso must
	# hold on the static table so a flat number cannot quietly return.
	var body: Variant = w.components.get_component(w.player, "body")
	for hit in seen:
		var hd: Dictionary = hit as Dictionary
		var want: float = SimShambler.swipe_damage_for(body, String(hd["part"]))
		if absf(float(hd["damage"]) - want) > 0.0001:
			push_error("SCALE: a swipe on %s carried %.2f, swipe_damage_for says %.2f" % [String(hd["part"]), float(hd["damage"]), want])
			return false
	var on_hand: float = SimShambler.swipe_damage_for(body, "hand_left")
	var on_head: float = SimShambler.swipe_damage_for(body, "head")
	var on_torso: float = SimShambler.swipe_damage_for(body, "torso")
	if not (on_hand < on_head and on_head < on_torso):
		push_error("SCALE: hand %.2f < head %.2f < torso %.2f does not hold -- the swipe has gone flat" % [on_hand, on_head, on_torso])
		return false
	if on_hand < SimShambler.SWIPE_DAMAGE_MIN or on_torso > SimShambler.SWIPE_DAMAGE:
		push_error("SCALE: the floor or the ceiling is not holding (%.2f .. %.2f)" % [on_hand, on_torso])
		return false
	var wounds: Array = _wounds_of(w, w.player)
	if wounds.size() != seen.size():
		push_error("WOUND: %d swipes left %d wounds -- one each, through the melee pipeline" % [seen.size(), wounds.size()])
		return false
	for wound in wounds:
		var wd: Dictionary = wound as Dictionary
		if String(wd.get("kind", "")) != "cut":
			push_error("WOUND: a swipe recorded kind \"%s\", not \"cut\"" % String(wd.get("kind", "")))
			return false
		if not SimCombat.SURVIVOR_BODY_PARTS.has(String(wd.get("bodyPart", wd.get("part", "")))):
			push_error("WOUND: a swipe wound is not located on a survivor part: %s" % str(wd))
			return false
	print("  SWIPE-CADENCE first at %d then every %d, %d wounds for %d swipes" % [first_at, SimShambler.SWIPE_RECOVER_TICKS, wounds.size(), seen.size()])
	return true


func _reach_and_walls_both_refuse_it() -> bool:
	# Reach: a shambler that cannot close -- every speed zeroed -- Pursuing from 1.4 m, inside
	# CONTACT_METRES so the state is Pursue, outside SWIPE_METRES so the claw never reaches.
	var w: Variant = _world(12)
	var z: int = _spawn_shambler(w, 15.1, 16.5)
	var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
	sd["seekSpeed"] = 0.0
	sd["wanderSpeed"] = 0.0
	sd["millSpeed"] = 0.0
	var seen: Array = _watch_swipes(w)
	for i in 120:
		w.step()
	if int(sd["state"]) != SimShambler.ShamblerState["Pursue"]:
		push_error("REACH: the shambler is not even Pursuing -- this negative is measuring nothing")
		return false
	if not seen.is_empty():
		push_error("REACH: a swipe landed from 1.4 m, past SWIPE_METRES")
		return false
	# Wall: adjacent through masonry, wall tile (16,16) between the two bodies -- the same
	# _clear_contact that refuses a grab through it.
	#
	# The geometry is the assertion. This used to place the player at 17.5 against a shambler at
	# 15.9, which is **1.6 m** apart against SWIPE_METRES 1.1: the swipe was refused by reach and
	# the row passed identically with the wall deleted, while its comment claimed "Distance 1.0 m,
	# well in reach". 17.05 and 15.98 is 1.07 m -- inside the claw -- with both bodies clear of
	# tile 16 and the masonry squarely on the line. `_reach_refuses` above is the row that owns
	# the out-of-range case; this row owns the wall, and now it can only pass for that reason.
	# The distance is asserted rather than assumed, so a later nudge to either coordinate cannot
	# quietly return this to measuring reach again.
	var w2: Variant = _world(13, [{"x": 16, "y": 16}])
	var pos: Dictionary = w2.components.get_component(w2.player, "position") as Dictionary
	pos["x"] = 17.05
	var z2: int = _spawn_shambler(w2, 15.98, 16.5)
	var gap: float = absf(float(pos["x"]) - 15.98)
	if gap > SimShambler.SWIPE_METRES:
		push_error("WALL: the bodies are %.3f m apart, past SWIPE_METRES %.3f -- this row is measuring reach, not the wall" % [gap, SimShambler.SWIPE_METRES])
		return false
	var sd2: Dictionary = w2.components.get_component(z2, "shambler") as Dictionary
	sd2["seekSpeed"] = 0.0
	sd2["wanderSpeed"] = 0.0
	sd2["millSpeed"] = 0.0
	sd2["state"] = SimShambler.ShamblerState["Pursue"]
	var seen2: Array = _watch_swipes(w2)
	for i in 120:
		w2.step()
	if not seen2.is_empty():
		push_error("WALL: a swipe landed through a wall")
		return false
	# And the control the wall row needs: the identical placement with no wall in the map must
	# land swipes. Without it "no swipe" is satisfied by any reason at all, which is exactly how
	# the old geometry hid.
	var w3: Variant = _world(13)
	var pos3: Dictionary = w3.components.get_component(w3.player, "position") as Dictionary
	pos3["x"] = 17.05
	var z3: int = _spawn_shambler(w3, 15.98, 16.5)
	var sd3: Dictionary = w3.components.get_component(z3, "shambler") as Dictionary
	sd3["seekSpeed"] = 0.0
	sd3["wanderSpeed"] = 0.0
	sd3["millSpeed"] = 0.0
	sd3["state"] = SimShambler.ShamblerState["Pursue"]
	var seen3: Array = _watch_swipes(w3)
	for i in 120:
		w3.step()
	if seen3.is_empty():
		push_error("WALL: the same placement without a wall landed no swipes either, so the wall proved nothing")
		return false
	print("  SWIPE-REFUSED out of reach (%d) and through a wall (%d), %d swipes at the same range unwalled" % [seen.size(), seen2.size(), seen3.size()])
	return true


func _a_swipe_is_chip_damage_never_a_bite() -> bool:
	var w: Variant = _world(14)
	SimWounds.register_module(w)
	SimInfection.register_module(w)
	var z: int = _spawn_shambler(w, 15.6, 16.5)
	var bites: Array = []
	w.events.subscribe({"id": "gate.watch-bites", "type": "bite.landed", "handler": func(_e: Dictionary) -> void:
		bites.append(1)
	})
	var seen: Array = _watch_swipes(w)
	for i in 400:
		w.step()
	if seen.size() < 6:
		push_error("CHIP: only %d swipes in 400 ticks -- the sample is too thin to claim anything" % seen.size())
		return false
	for wound in _wounds_of(w, w.player):
		if int((wound as Dictionary).get("severity", 0)) >= SimWounds.Severity.DeepWound:
			push_error("CHIP: a swipe cut a DeepWound -- SWIPE_DAMAGE against the smallest part has crossed the 0.40 band")
			return false
	if not bites.is_empty():
		push_error("CHIP: a swipe published bite.landed")
		return false
	if w.components.has_component(w.player, "zombieInfection"):
		push_error("CHIP: %d swipes recorded an infection exposure -- the infection loop has grown a back door around the grab flag" % seen.size())
		return false
	# Live-channel control: the same victim, the same world, a real bite -- an exposure must
	# still be recorded and transmission must still take, or the absence above was a dead
	# subscription rather than a refusal. BITE_TRANSMISSION_CHANCE is 0.85, so a handful of
	# attempts settles the transmitted flag deterministically.
	for i in 10:
		if _transmitted(w, int(w.player)):
			break
		w.events.publish({"type": "bite.landed", "victim": int(w.player), "source": z, "bodyPart": "arm_left", "damage": 4.0})
		w.step()
	if not _transmitted(w, int(w.player)):
		push_error("CHIP: the control bites never transmitted -- this assertion cannot tell a refusal from a dead channel")
		return false
	print("  SWIPE-CHIP %d swipes: no deep wound, no bite, no infection; the control bite still infects" % seen.size())
	return true


func _transmitted(w: Variant, entity: int) -> bool:
	var st: Variant = w.components.get_component(entity, "zombieInfection")
	if not (st is Dictionary):
		return false
	for e in (st as Dictionary).get("exposures", []) as Array:
		if bool((e as Dictionary).get("transmitted", false)):
			return true
	return false


func _a_grapple_takes_both_bodies_off_the_swipe_menu() -> bool:
	SimShambler.GRABS_ENABLED = true
	var ok: bool = true
	var w: Variant = _world(15)
	SimWounds.register_module(w)
	# The holder, in reach and holding: its grab lands on the first tick, its bite clock is then
	# pinned far away so every attack.connected observed below would have to be a swipe.
	var holder: int = _spawn_shambler(w, 15.7, 16.5)
	(w.components.get_component(holder, "shambler") as Dictionary)["grabStrength"] = 999.0
	# The bystander, also in reach of the held victim.
	var bystander: int = _spawn_shambler(w, 17.3, 16.5)
	var seen: Array = _watch_swipes(w)
	w.step()
	var hold: Variant = w.components.get_component(holder, "grabState")
	if not (hold is Dictionary):
		push_error("GRAPPLE: the hold never formed -- this assertion is measuring an empty scene")
		ok = false
	else:
		(hold as Dictionary)["ticksUntilBite"] = 1000000
		# Instinct would tear a 999-grip hold free eventually by luck; silence the struggle
		# intake so the grapple stands for the whole window (the check_m2_contact.gd idiom).
		if not w.systems.unregister("shambler.struggle-intake"):
			push_error("GRAPPLE: shambler.struggle-intake was not registered -- silencing nothing")
			ok = false
		for i in 150:
			w.step()
		if not seen.is_empty():
			push_error("GRAPPLE: %d swipe(s) landed during the grapple -- holder or bystander, neither may, and a held body is off the menu" % seen.size())
			ok = false
	SimShambler.GRABS_ENABLED = false
	if ok:
		print("  SWIPE-GRAPPLE 150 held ticks, holder and bystander both kept their claws down")
	return ok

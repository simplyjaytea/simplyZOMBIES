extends SceneTree
# Armoured and heavy: gear on the dead.
#
# Two kinds, and only one of them needed a line of sim. The **armoured** one is the interesting
# half, because what it closes is a defect docs/23 has carried since the armour slice: "armour on
# anything that is not a survivor". `SimInfection.armor_coverage_of` reads the target's
# `equipment` and has never asked whose body it is, and `SimHealth.armor_damage_factor` multiplies
# by it inside `damage_part` -- the one closure in the sim that moves integrity. The only thing
# missing was that a zombie had no `equipment` component at all, so an armoured kind could not
# exist. A `worn: [item ids]` list on the type, an inventory, the gear equipped and a `lootKit` so
# the existing `_drop_kit` puts it on the floor, and the whole mechanism is *already written*.
# That is the claim, and WORN is the lane that refuses to take it on trust.
#
# The **heavy** is docs/14's second-wave wall: a big, slow body. Its `breach: {factor}` half did
# **not** ship, deliberately -- see BREACH below, which says so and skips rather than passing
# quietly, and holds the two facts that keep the skip honest.
#
# Four lanes, each with a true positive and a true negative, each run red on purpose before it
# was trusted (the sabotage that did it is named on each):
#
#   WORN    every id any kind's `worn` list names exists in the item registry (TN: a fabricated
#           id is refused by the same predicate); a spawned body is actually wearing them, in the
#           slots their own bases declare; an unhurt armoured torso's `armor_damage_factor` reads
#           below a bare shambler's exact 1.0; and then the *outcome* -- one real blow each on the
#           real bus, integrity actually removed, the armoured body losing less. Its second TN is
#           the one that would catch the worst bug here, a mitigation that ignored `bodyPart`: the
#           same armoured body's **legs**, which neither vest nor helmet covers, must take the
#           whole blow. Sampled on fresh bodies only, because `damage_part` clamps at zero and a
#           hurt part measures the clamp rather than the armour -- which is why the armour slice's
#           own gate had to be rewritten. Red by dropping the `_wear_the_kit` call from
#           `spawn_zombie`, which took the factor to 1.0000 with the JSON unchanged.
#   DROP    kill one and the gear is on the floor: every piece carries a `position` at the body's
#           tile and is in nobody's equipment. TN: a bare shambler killed the same way leaves
#           nothing, so the lane is not counting items that were already lying about. Red by
#           dropping the `lootKit` line, which left the vest on a despawned id forever.
#   BREACH  **did not ship, and the lane says so and skips.** Two assertions keep that honest:
#           nothing anywhere declares a `breach` key (a key with no reader is the dead socket this
#           project has paid for eleven times), and the *reason*, measured rather than asserted --
#           a heavy and a shambler pressing the same board breach it on the identical tick, while
#           two bodies breach it faster than one. Board damage is a function of the crowd at a
#           tile (`SimFortify._presses` counts bodies, `pressure_of` takes an int), so a
#           per-attacker factor has nowhere to be read. Red by writing a `breach` key into the
#           heavy's JSON, which is exactly the mistake the lane exists to refuse.
#   HEAVY   the big body, asserted on behaviour twice over: it takes strictly more blows to the
#           head to put down than a shambler born on the same seed, and it covers the ratio of
#           ground its content `locomotion.speed` asks for. Both TNs are the same measurement run
#           shambler-against-shambler, which must come back equal and 1.000. Red by copying the
#           shambler's `body` and `speed` into `heavy.json`, which took both to parity.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")

# The two ids this slice added, named here and not under `godot/sim/` -- the stalker-and-runner
# slice's rule, and it still holds for the armoured one even though this slice did cost code:
# what the code reads is a `worn` key, never an id. Nothing in the sim knows either of these
# words.
const ARMORED: String = "zombie.armored"
const HEAVY: String = "zombie.heavy"
const BARE: String = SimRoster.TYPE_SHAMBLER

# A zombie body is head/torso/legs. The vest covers the torso and the helmet the head, so the legs
# are the part nothing this kind wears touches -- WORN's part-awareness negative.
const TORSO: String = "torso"
const HEAD: String = "head"
const LEGS: String = "legs"

# Small enough that no part it lands on runs out (the smallest torso on the table is a screamer's
# 40, and variance can shrink it by 15%), large enough that half of it is not floating-point
# noise.
const BLOW: float = 6.0
# What a head takes at a time in HEAVY's put-down count. Small enough that the difference between
# a 25-point head and a 40-point one is several blows rather than one.
const HEAD_BLOW: float = 5.0
# Bodies per side in HEAVY's put-down count. Variance scales every body by up to +/-15%, so one
# pair would be a statement about two rolls; eight pairs on eight seeds is a statement about the
# authored numbers.
const PAIRS: int = 8
const RUN_TICKS: int = 20


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _worn() and ok
	ok = _drop() and ok
	ok = _breach() and ok
	ok = _heavy() and ok
	if ok:
		print("M2_ARMORED_OK")
		quit(0)
	else:
		push_error("M2_ARMORED_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

func _fixture(seed_val: int) -> Dictionary:
	return {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}


# A world with just enough registered to hurt a body and move one: health, inventory (so an
# equipped item's encumbrance pass has a home), and the shambler brain with no field --
# check_m2_variance.gd's fixture, which is check_m2_contact.gd's before that.
func _world(seed_val: int) -> Variant:
	var w: Variant = World.new(_fixture(seed_val))
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimShambler.register_module(w, null)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	return w


func _spawn(w: Variant, kind: String, x: float, y: float) -> int:
	return SimRoster.spawn_zombie(w, x, y, kind, w.rng.stream("shambler"))


func _integrity(w: Variant, ent: int, part: String) -> float:
	var b: Variant = w.components.get_component(ent, "body")
	return float((b as Dictionary).get(part, 0.0)) if b is Dictionary else -1.0


# One blow on the bus, drained. `events.publish()` only queues -- handlers run at `drain()`, at
# the end of `world.step()` -- so a fixture that publishes and then reads without stepping sees
# nothing at all (CLAUDE.md's trap, and check_m2_armor.gd's `_strike` is the precedent).
func _strike(w: Variant, ent: int, part: String, damage: float) -> float:
	var before: float = _integrity(w, ent, part)
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": ent, "bodyPart": part, "damage": damage})
	w.step()
	return before - _integrity(w, ent, part)


# Every zombie entry in the shipped tree that declares a `worn` list, as {id: [item ids]}.
func _worn_lists(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for entry in SimRoster.types(w):
		var id: String = String(entry.get("id", ""))
		var worn: Array[String] = SimRoster.worn_of(w, id)
		if not worn.is_empty():
			out[id] = worn
	return out


# Every item base id the content tree knows. The registry the `worn` ids have to be in.
func _item_ids(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for entry in SimItems.content_entries(w, "item"):
		if entry is Dictionary:
			out[String((entry as Dictionary).get("id", ""))] = true
	return out


# --- WORN -------------------------------------------------------------------------------------

func _worn() -> bool:
	var lane: String = "WORN"
	var w: Variant = _world(7101)
	var lists: Dictionary = _worn_lists(w)
	if lists.is_empty():
		# Say so and skip, never pass quietly: with no kind declaring a `worn` list there is
		# nothing here to judge, and every assertion below would be vacuously true.
		print("%s SKIP no zombie kind declares a `worn` list, so there is no gear on any dead body to judge" % lane)
		return true

	# The registry half. An id that names nothing would spawn a body wearing an item with no base,
	# which `item_base_of` push_errors about at the first blow rather than at spawn.
	var registry: Dictionary = _item_ids(w)
	if registry.is_empty():
		push_error("%s: the item registry came back empty, so 'this id exists' cannot be asked" % lane)
		return false
	for kind in lists.keys():
		for item_id in lists[kind] as Array:
			if not registry.has(String(item_id)):
				push_error("%s: %s wears %s, which no item base in the tree declares" % [lane, String(kind), String(item_id)])
				return false
	# TN for the predicate above: it has to be able to say no.
	if registry.has("item.vest.unobtanium"):
		push_error("%s: the registry claims to know a fabricated id, so 'this id exists' proves nothing" % lane)
		return false

	# The equipping half, on the armoured kind itself.
	if not lists.has(ARMORED):
		push_error("%s: %s declares no `worn` list, and it is the kind this slice is about" % [lane, ARMORED])
		return false
	var declared: Array = lists[ARMORED] as Array
	var zed: int = _spawn(w, ARMORED, 8.5, 8.5)
	var eq: Variant = w.components.get_component(zed, "equipment")
	if not eq is Dictionary:
		push_error("%s: a body of %s spawned with no `equipment` component at all -- which is the defect this slice exists to close" % [lane, ARMORED])
		return false
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	var worn_bases: Dictionary = {}
	for item in SimInventory.equipped_items(w, zed):
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary:
			worn_bases[String((base as Dictionary).get("id", ""))] = true
	for item_id in declared:
		if not worn_bases.has(String(item_id)):
			push_error("%s: %s declares %s and the spawned body is not wearing it (slots %s)" % [lane, ARMORED, String(item_id), str(slots.keys())])
			return false

	# The factor half, against a bare body of the kind 80 draws in 100 are. Both bodies are fresh,
	# so both are unhurt: `damage_part` clamps integrity at zero, and a hurt part measures the
	# clamp rather than the armour.
	var naked: int = _spawn(w, BARE, 9.5, 8.5)
	var bare_factor: float = SimHealth.armor_damage_factor(w, naked, TORSO)
	if not is_equal_approx(bare_factor, 1.0):
		push_error("%s: a bare shambler's torso let through %.4f of a blow, and a bare torso is bare" % [lane, bare_factor])
		return false
	var torso_factor: float = SimHealth.armor_damage_factor(w, zed, TORSO)
	var head_factor: float = SimHealth.armor_damage_factor(w, zed, HEAD)
	if torso_factor >= 1.0:
		push_error("%s: an armoured torso let through %.4f -- the coverage reader does not reach a zombie's equipment" % [lane, torso_factor])
		return false
	var cov: float = SimInfection.armor_coverage_of(w, zed, TORSO)
	if cov <= 0.0:
		push_error("%s: a worn vest covers an armoured torso %.4f, so there is no coverage for the factor to read" % [lane, cov])
		return false

	# The outcome half. A factor is a number; this is integrity actually removed from a body by a
	# real event on the real bus, which is the only form of the claim worth anything.
	var hit_armoured: float = _strike(w, zed, TORSO, BLOW)
	var hit_bare: float = _strike(w, naked, TORSO, BLOW)
	if hit_armoured >= hit_bare:
		push_error("%s: an armoured torso lost %.3f of %.1f and a bare one %.3f -- the vest stopped nothing" % [lane, hit_armoured, BLOW, hit_bare])
		return false
	if not is_equal_approx(hit_bare, BLOW):
		push_error("%s: a bare torso lost %.3f of a %.1f blow, so the control is not a control" % [lane, hit_bare, BLOW])
		return false

	# The TN that would catch the worst bug available here -- a mitigation that ignored
	# `bodyPart` and softened everything a zombie in gear was hit with. Neither the vest nor the
	# helmet covers a leg.
	var legs_factor: float = SimHealth.armor_damage_factor(w, zed, LEGS)
	if not is_equal_approx(legs_factor, 1.0):
		push_error("%s: nothing this kind wears covers a leg and the leg let through %.4f -- the mitigation is not reading the part" % [lane, legs_factor])
		return false
	var hit_legs: float = _strike(w, zed, LEGS, BLOW)
	if not is_equal_approx(hit_legs, BLOW):
		push_error("%s: an armoured body's uncovered legs lost %.3f of a %.1f blow" % [lane, hit_legs, BLOW])
		return false

	print("%s OK %d kind(s) wear gear; %s wears %s in slots %s; torso coverage %.2f lets through %.4f against a bare 1.0000, and one %.1f blow removes %.3f against the bare body's %.3f while its uncovered legs take all %.3f; head %.4f" % [
		lane, lists.size(), ARMORED, str(declared), str(slots.keys()), cov, torso_factor, BLOW, hit_armoured, hit_bare, hit_legs, head_factor,
	])
	return true


# --- DROP -------------------------------------------------------------------------------------
#
# The gear has to come back off the body, or an armoured kind is a wall the colony can never take
# anything from. `SimRecruits._drop_kit` already does exactly this for a dead raider and for a
# colonist who turned; the `lootKit` component is what makes it fire, and `handle_death`'s
# shambler arm already calls it. So this lane is the socket question: does the mechanism that
# exists actually get reached from a zombie's death?
func _drop() -> bool:
	var lane: String = "DROP"
	var w: Variant = _world(7202)
	var zed: int = _spawn(w, ARMORED, 11.5, 11.5)
	var carried: Array[int] = []
	for item in SimInventory.equipped_items(w, zed):
		carried.append(int(item))
	if carried.is_empty():
		print("%s SKIP a body of %s spawned wearing nothing, so there is no gear to look for on the floor" % [lane, ARMORED])
		return true
	var ground_before: int = _items_on_the_ground(w, carried).size()
	if ground_before != 0:
		push_error("%s: %d of the worn pieces were already lying on the ground before anything died" % [lane, ground_before])
		return false

	_put_down(w, zed)
	var dropped: Array[int] = _items_on_the_ground(w, carried)
	if dropped.size() != carried.size():
		push_error("%s: %d of %d worn pieces reached the floor when the body went down" % [lane, dropped.size(), carried.size()])
		return false
	for item in dropped:
		var pos: Dictionary = w.components.get_component(int(item), "position") as Dictionary
		if absf(float(pos["x"]) - 11.5) > 1.01 or absf(float(pos["y"]) - 11.5) > 1.01:
			push_error("%s: a dropped piece landed at %.2f,%.2f and the body fell at 11.50,11.50" % [lane, float(pos["x"]), float(pos["y"])])
			return false
		if _worn_by_anybody(w, int(item)):
			push_error("%s: a piece is on the floor and still in somebody's equipment slots" % lane)
			return false

	# TN: the same death, on a kind that wears nothing, leaves nothing behind. Without this the
	# lane would pass against code that dropped every item in the world at every death -- and,
	# more plausibly, against a `lootKit` written onto every zombie rather than onto the ones
	# carrying something.
	var w2: Variant = _world(7203)
	var naked: int = _spawn(w2, BARE, 11.5, 11.5)
	if w2.components.has_component(naked, "lootKit"):
		push_error("%s: a bare shambler carries a `lootKit`, so the kit component is not about the gear" % lane)
		return false
	var loose_before: int = _loose_items(w2)
	_put_down(w2, naked)
	var loose_after: int = _loose_items(w2)
	if loose_after != loose_before:
		push_error("%s: a bare shambler's death put %d item(s) on the ground" % [lane, loose_after - loose_before])
		return false

	print("%s OK %d worn piece(s) on the floor at the body's tile and in nobody's slots; a bare shambler's death leaves %d" % [lane, dropped.size(), loose_after - loose_before])
	return true


# Destroy the head and let the reaper run. `health.reap` is a **cleanup**-phase system and the
# kill is appended at `drain()`, at the end of the step -- so the death is booked on one tick and
# the body handed to `SimRecruits.handle_death` on the next. Stepping once would read the world
# before anything had been dropped at all.
func _put_down(w: Variant, ent: int) -> void:
	for _i in 12:
		if _integrity(w, ent, HEAD) <= 0.0:
			break
		_strike(w, ent, HEAD, 999.0)
	for _i in 3:
		w.step()


func _items_on_the_ground(w: Variant, items: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for item in items:
		if w.components.get_component(int(item), "position") is Dictionary:
			out.append(int(item))
	return out


func _loose_items(w: Variant) -> int:
	return w.components.query(["itemBase", "position"]).size()


func _worn_by_anybody(w: Variant, item: int) -> bool:
	for actor in w.components.query(["equipment"]):
		var eq: Variant = w.components.get_component(int(actor), "equipment")
		if not eq is Dictionary:
			continue
		for slot in ((eq as Dictionary).get("slots", {}) as Dictionary).keys():
			if int(((eq as Dictionary)["slots"] as Dictionary)[slot]) == item:
				return true
	return false


# --- BREACH -----------------------------------------------------------------------------------
#
# **This half did not ship.** The plan proposed `breach: {factor}` on the heavy, read wherever
# `fortify.breached` damage is dealt. It is not read anywhere, because there is nowhere to read
# it: a barrier's damage is a function of the **crowd at its tile**, not of the bodies in it.
# `SimFortify._presses` walks every pressing body and returns a count per tile; `_press` spends
# `pressure_of(n)` -- an `int` in, a float out, superlinear in the count so that three bodies are
# worth six. No entity ever reaches that arithmetic, so a per-attacker factor has no reader, and
# a key with no reader is the dead socket this milestone has paid for eleven times. Making one
# would mean rewriting pressure as a weighted sum, which moves every shipped fortify number and
# every balance figure that depends on them -- a slice of its own, not a line in this one.
#
# So the lane says so and skips. Two assertions keep the skip honest rather than decorative:
#
#   1. Nothing declares a `breach` key -- not the heavy, not any kind, not the schema. The day
#      somebody adds one without a reader, this lane goes red instead of shrugging.
#   2. The reason, measured rather than asserted. A heavy and a shambler pressing the same board
#      breach it on the identical tick, while two bodies breach it sooner than one -- so the
#      measurement can see pressure change, and what it cannot see is which body is applying it.
func _breach() -> bool:
	var lane: String = "BREACH"
	var w: Variant = _world(7304)
	for entry in SimRoster.types(w):
		if (entry as Dictionary).has("breach"):
			push_error("%s: %s declares a `breach` block and nothing in the sim reads one -- see this lane's note" % [lane, String(entry.get("id", ""))])
			return false
	var schema: String = FileAccess.get_file_as_string("res://content/schemas/zombie.schema.json")
	if schema.is_empty():
		push_error("%s: the zombie schema would not open, so 'no breach key' cannot be asked of it" % lane)
		return false
	if schema.contains("\"breach\""):
		push_error("%s: zombie.schema.json declares a `breach` property and no reader exists for it" % lane)
		return false

	var one_heavy: int = _ticks_to_breach(HEAVY, 1)
	var one_bare: int = _ticks_to_breach(BARE, 1)
	var two_bare: int = _ticks_to_breach(BARE, 2)
	if one_heavy < 0 or one_bare < 0 or two_bare < 0:
		push_error("%s: a board survived the press window, so the measurement says nothing (heavy %d, shambler %d, two %d)" % [lane, one_heavy, one_bare, two_bare])
		return false
	if two_bare >= one_bare:
		push_error("%s: two bodies broke the board in %d ticks and one in %d -- this measurement cannot see pressure at all, so its answer about the heavy is worthless" % [lane, two_bare, one_bare])
		return false
	if one_heavy != one_bare:
		push_error("%s: a heavy broke the board in %d ticks and a shambler in %d. Board damage IS per-attacker after all -- go and give `breach` a reader" % [lane, one_heavy, one_bare])
		return false

	print("%s SKIP the breach factor did not ship: board damage is not per-attacker. One heavy and one shambler each break a board on tick %d (two shamblers on %d), because SimFortify._presses counts bodies per tile and pressure_of takes an int -- no entity reaches the arithmetic, so a `breach` key would have no reader. Nothing declares one." % [
		lane, one_heavy, two_bare,
	])
	return true


# `n` bodies of `kind` leaning on one board, and the tick it gives way on -- or -1. The board is
# a component rather than a built barricade: `SimFortify._tick_contact` queries `windowBoard` and
# reads the crowd out of `velocity.pressX/pressY`, which is what the movement kernel writes when
# a body pushes into something solid. check_m2_fortify.gd's PRESS lane drives the same fields.
func _ticks_to_breach(kind: String, n: int) -> int:
	var w: Variant = World.new(_fixture(7305))
	var map: Variant = SimTileMap.blank_map(32, 32)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimFortify.register_module(w)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var board: int = int(w.entities.spawn())
	w.components.set_component(board, "windowBoard", {"tx": 10, "ty": 12, "stage": 0, "contactTicks": 0.0})
	var zeds: Array[int] = []
	for i in n:
		zeds.append(SimRoster.spawn_zombie(w, 10.5 + float(i) * 0.05, 11.5, kind, w.rng.stream("shambler")))
	var breached: Array = []
	w.events.subscribe({"id": "check.armored-press", "type": "fortify.breached", "handler": func(e: Dictionary) -> void:
		breached.append(String(e.get("kind", "")))
	})
	for t in 1200:
		for z in zeds:
			var vel: Dictionary = w.components.get_component(int(z), "velocity") as Dictionary
			vel["pressX"] = 10
			vel["pressY"] = 12
		w.step()
		if not breached.is_empty():
			return t + 1
	return -1


# --- HEAVY ------------------------------------------------------------------------------------
#
# docs/14's second wave: slow, enormous. Both halves are asserted on behaviour rather than on the
# JSON -- a lane that read `body.head` back out of content would be a dictionary comparing itself
# to itself, which is the failure `check_m2_armor.gd`'s header names.
func _heavy() -> bool:
	var lane: String = "HEAVY"

	# Tougher. Eight matched pairs on eight seeds, because `variance.body` scales every body by up
	# to +/-15% and one pair would be a statement about two rolls.
	var heavier: int = 0
	var blows_heavy: int = 0
	var blows_bare: int = 0
	for i in PAIRS:
		var h: int = _blows_to_put_down(HEAVY, 8300 + i)
		var b: int = _blows_to_put_down(BARE, 8300 + i)
		if h < 0 or b < 0:
			push_error("%s: a body survived the put-down window (heavy %d blows, shambler %d)" % [lane, h, b])
			return false
		blows_heavy += h
		blows_bare += b
		if h > b:
			heavier += 1
	if heavier != PAIRS:
		push_error("%s: a heavy took more blows to the head than a shambler in only %d of %d pairs (%d blows against %d in total)" % [lane, heavier, PAIRS, blows_heavy, blows_bare])
		return false
	# TN: the same measurement, shambler against shambler on the same seeds, must come back level.
	# Without it "more blows" could be an artefact of the count rather than of the body.
	for i in PAIRS:
		var a: int = _blows_to_put_down(BARE, 8300 + i)
		var b2: int = _blows_to_put_down(BARE, 8300 + i)
		if a != b2:
			push_error("%s: two shamblers on seed %d took %d and %d blows -- the count is not a function of the body" % [lane, 8300 + i, a, b2])
			return false

	# Slower, measured on ground covered. The expectation comes from the two kinds' own
	# `locomotion.speed`, so retuning either moves the assertion with it rather than leaving a
	# number here to be chased.
	var heavy_ground: float = _ground_covered(HEAVY, 8400)
	var bare_ground: float = _ground_covered(BARE, 8400)
	if bare_ground <= 0.001:
		push_error("%s: the shambler control never moved, so there is no speed to compare against" % lane)
		return false
	if heavy_ground <= 0.001:
		push_error("%s: a heavy stood still -- it is slow, not parked" % lane)
		return false
	var ratio: float = heavy_ground / bare_ground
	var want: float = _speed_of(HEAVY) / _speed_of(BARE)
	if want >= 1.0:
		push_error("%s: %s declares speed %.2f against the shambler's %.2f, and a heavy is the slow one" % [lane, HEAVY, _speed_of(HEAVY), _speed_of(BARE)])
		return false
	if absf(ratio - want) > 0.06:
		push_error("%s: a heavy covered %.3f of the shambler's ground over %d ticks and its content asks for %.3f" % [lane, ratio, RUN_TICKS, want])
		return false
	# TN: shambler against shambler on the same seed is exactly 1.000, so the ratio is about the
	# kind and not about which of two worlds was walked first.
	var control: float = _ground_covered(BARE, 8400)
	if absf(control / bare_ground - 1.0) > 0.001:
		push_error("%s: two shamblers on one seed covered %.4f and %.4f -- the measurement is not repeatable" % [lane, control, bare_ground])
		return false

	print("%s OK over %d matched pairs a heavy took %d blows to the head against a shambler's %d, every pair heavier; and it covered %.3f m against %.3f m over %d ticks, a ratio of %.3f against the %.3f its content asks for" % [
		lane, PAIRS, blows_heavy, blows_bare, heavy_ground, bare_ground, RUN_TICKS, ratio, want,
	])
	return true


func _speed_of(kind: String) -> float:
	var entry: Variant = SimRoster.content_entry(World.new(_fixture(1)), kind)
	if entry is Dictionary and (entry as Dictionary).get("locomotion") is Dictionary:
		return float(((entry as Dictionary)["locomotion"] as Dictionary).get("speed", SimShambler.DEFAULT_LOCOMOTION["speed"]))
	return float(SimShambler.DEFAULT_LOCOMOTION["speed"])


# How many `HEAD_BLOW` blows to the head it takes, or -1 if it outlasts the window.
func _blows_to_put_down(kind: String, seed_val: int) -> int:
	var w: Variant = _world(seed_val)
	var zed: int = _spawn(w, kind, 8.5, 8.5)
	for n in 60:
		if _integrity(w, zed, HEAD) <= 0.0:
			return n
		_strike(w, zed, HEAD, HEAD_BLOW)
	return -1


# Metres covered in `RUN_TICKS` of Pursue. check_m2_variance.gd's CRAWLER lane's measurement:
# the state is pinned explicitly and grabbing is off, because a hold would pin both bodies and
# measure the grab instead of the speed.
func _ground_covered(kind: String, seed_val: int) -> float:
	var w: Variant = _world(seed_val)
	var zed: int = _spawn(w, kind, 19.5, 16.5)
	var sd: Dictionary = w.components.get_component(zed, "shambler") as Dictionary
	sd["state"] = SimShambler.ShamblerState["Pursue"]
	sd["canGrab"] = false
	var from: Dictionary = (w.components.get_component(zed, "position") as Dictionary).duplicate()
	for _i in RUN_TICKS:
		w.step()
	var now: Dictionary = w.components.get_component(zed, "position") as Dictionary
	return sqrt(pow(float(now["x"]) - float(from["x"]), 2.0) + pow(float(now["y"]) - float(from["y"]), 2.0))

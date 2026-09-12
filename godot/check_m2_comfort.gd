extends SceneTree
# Comfort that is not food -- docs/04-survival-needs.md's mood clause.
#
# What this slice fixed. Mood is a real modifier stat with seven sources by the end of this
# milestone -- shame, an argument, grief, a bad night, a bout of illness, a filthy body, an empty
# pool -- and every single one of them is something that happens *to* a survivor. The only thing a
# player could ever do back was cook, because `SimNeeds.use_item` refused any item that was neither
# edible nor drinkable, so a colony's whole morale policy was the dinner menu.
#
# `comfort` is the other half. A smoke, a hand of cards, a photograph, a tune. And the shape is
# copied rather than invented, because needs.gd already had the right one in four places:
#
#   * one modifier from one source, **replaced** rather than stacked (`_apply_grief`),
#   * accumulating to a **cap**, so two of a thing are not worth two of a thing (GRIEF_CAP,
#     ARGUMENT_CAP, SOIL_CAP, SLEEP_MOOD_CAP),
#   * expiring on a **clock** kept as a plain int on the needs component (`mealMoodUntilTick`).
#
# The lane that matters most is PINNED, for check_m2_transform's and check_m2_materials' reason:
# mood is the stat this milestone's whole late game turns on, and a slice that quietly moved one of
# its seven existing numbers while adding an eighth would be a rebalance wearing a content slice's
# clothes. Every shipped magnitude and every band boundary is pinned here by name, and the pinning
# is not only off the constants -- a cooked meal is eaten through the real verb and must still be
# worth exactly what it was worth before this file existed.
#
# CAP is the lane the design lives in, and it carries the true negative that matters: a single
# comfort under the cap must read as *itself* and not as the cap, or "two do not stack" would pass
# on an implementation that simply pinned everybody to fifteen forever.
#
# CLOCK is tick-exact on purpose. A lane that jumps the clock and finds the lift gone proves only
# that it went at some point; this one asserts the modifier is still whole on the tick before and
# gone on the tick itself, which is the difference between a clock and a guess.

const SimBoot = preload("res://sim/boot.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")

# --- what shipped before this slice, and must still ship ----------------------------------------
#
# The seven mood sources as they stood, straight out of git. A change to any of these is a
# rebalance of the colony's morale and this is where it is caught.
const PINNED_CONSTANTS: Array[Dictionary] = [
	{"what": "MOOD_LOW", "is": -20.0},
	{"what": "MOOD_MISERABLE", "is": -50.0},
	{"what": "LEAVE_AT", "is": -80.0},
	{"what": "SOIL_MOOD", "is": 12.0},
	{"what": "SOIL_CAP", "is": 24.0},
	{"what": "ARGUMENT_PER", "is": 6.0},
	{"what": "ARGUMENT_CAP", "is": 24.0},
	{"what": "GRIEF_WITNESSED", "is": 18.0},
	{"what": "GRIEF_HEARD", "is": 7.0},
	{"what": "GRIEF_CAP", "is": 40.0},
	{"what": "SLEEP_MOOD", "is": 16.0},
	{"what": "SLEEP_MOOD_CAP", "is": 16.0},
	{"what": "ILLNESS_MOOD", "is": -14.0},
	{"what": "SPOILED_MOOD", "is": -16.0},
]
# And the mood a plate is worth, which lives in content rather than in the file.
const PINNED_FOOD: Array[Dictionary] = [
	{"id": "item.food.cooked", "mood": 8.0},
	{"id": "item.food.raw", "mood": -8.0},
	{"id": "item.food.canned", "mood": 0.0},
]
const PINNED_MEAL_TICKS: int = 36000

# The fixtures the lanes below put in a pocket. Chosen for what they are worth rather than for what
# they are: PAPERBACK is under the cap alone and PAPERBACK + CHESS is over it, which is the whole
# CAP lane, and HARMONICA is the kept item whose clock CLOCK waits out.
const PAPERBACK: String = "item.paperback.dogeared"
const CHESS: String = "item.chess.travel"
const HARMONICA: String = "item.harmonica.brass"
const CIGARETTES: String = "item.cigarettes.pack"
# Something with no comfort, no food, no drink and no illness grade, for every true negative that
# needs a thing the router must refuse.
const PLANK: String = "item.plank.sawn"

# Where the key is read, and the call the reader is reached by. A textual assertion has to be able
# to find its needle after a refactor, so each of these is a *call* named where the call is made --
# the lesson check_respond and check_weather each paid for when a helper moved.
const READERS: Array[Dictionary] = [
	{"what": "the block is parsed", "file": "res://sim/modules/needs.gd", "needle": "get(\"comfort\")"},
	{"what": "the intake spends it", "file": "res://sim/modules/needs.gd", "needle": "take_comfort(world, entity, item)"},
	{"what": "the word menu asks the same predicate", "file": "res://sim/modules/inventory.gd", "needle": "_Needs().call(\"can_use\""},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_shipped_mood_numbers_have_not_moved() and ok
	ok = _two_comforts_are_not_the_sum_of_two_comforts() and ok
	ok = _a_comfort_lifts_on_the_tick_its_clock_named() and ok
	ok = _every_comfort_is_findable_and_the_key_is_read() and ok
	ok = _the_menu_and_the_intake_are_one_function() and ok
	ok = _a_half_block_is_refused_rather_than_taken_for_free() and ok
	if ok:
		print("M2_COMFORT_OK pinned cap clock reach menu block")
		quit(0)
	else:
		push_error("M2_COMFORT_FAIL")
		quit(1)


# --- fixtures -----------------------------------------------------------------------------------


func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]


# Mood with every *need* source zeroed out, so what is left is the plate and the pocket and nothing
# else -- check_m2_needs' `_mood_without_the_pools`, verbatim and for its stated reason: eating and
# resting move pools, and the pools carry mood of their own through `_apply_muls`.
func _mood_less_pools(w: Variant, ent: int) -> float:
	var n: Dictionary = SimNeeds.of(w, ent)
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	n["relief"] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	SimNeeds._apply_muls(w, ent, n)
	return float(w.modifiers.call("resolve", "mood", ent))


# Strict about the stow rather than falling back to a bare `stored` component: `can_use` asks
# `SimInventory.owns` first, so an item that only *looks* stowed would be refused by the router for
# a reason that has nothing to do with the lane doing the asking.
func _give(w: Variant, ent: int, base_id: String) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged"})
	if item < 0:
		return -1
	if not SimInventory.stow(w, ent, item):
		w.despawn(item)
		return -1
	return item


# Put the pocket back the way it was found. The MENU lane walks every comforting base in the
# roster and a survivor's pack is not twelve cells deep, so a kept item that is never taken back
# out fills it and the lane goes red on the first thing that will not fit -- which reads as "the
# menu refused a comfort" and blames code that is correct.
func _take_back(w: Variant, item: int) -> void:
	if item < 0 or not w.entities.call("is_alive", item):
		return
	SimInventory.remove_from_container(w, item)
	w.despawn(item)


# A base that is not in any shipped file, pushed into the world's own content tree. `_content_get`
# walks the tree live rather than off an index, so a file added here is a base from the next call
# onward -- which is what lets the BLOCK lane put a genuinely malformed block in front of the real
# reader instead of in front of a copy of it.
func _inject(w: Variant, entries: Array) -> void:
	w.content["items/gate_comfort.json"] = entries


func _fabricate(id: String, comfort: Variant) -> Dictionary:
	var e: Dictionary = {
		"id": id,
		"name": "Gate Fixture",
		"class": "tool",
		"size": {"w": 1, "h": 1},
		"massKg": 0.1,
	}
	if comfort != null:
		e["comfort"] = comfort
	return e


func _eat_cooked(w: Variant, ent: int) -> bool:
	var meal: int = _give(w, ent, "item.food.cooked")
	if meal < 0:
		return false
	SimNeeds.of(w, ent)["hunger"] = 10.0
	return SimNeeds.eat(w, ent, meal)


# --- PINNED ---------------------------------------------------------------------------------
#
# The slice is additive or it is a silent rebalance. Two halves, because a constant that still
# reads 8.0 in a file nothing consults would pass the first half on its own: every shipped mood
# number is checked by name, and then a cooked meal is *eaten* through the real verb and must still
# be worth exactly the eight it was worth before `comfort` existed -- with no comfort standing,
# because eating is not comforting and a router that fell through into the new arm would show up
# here as a meal worth more than the plate says.
func _the_shipped_mood_numbers_have_not_moved() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var live: Dictionary = {
		"MOOD_LOW": SimNeeds.MOOD_LOW,
		"MOOD_MISERABLE": SimNeeds.MOOD_MISERABLE,
		"LEAVE_AT": SimNeeds.LEAVE_AT,
		"SOIL_MOOD": SimNeeds.SOIL_MOOD,
		"SOIL_CAP": SimNeeds.SOIL_CAP,
		"ARGUMENT_PER": SimNeeds.ARGUMENT_PER,
		"ARGUMENT_CAP": SimNeeds.ARGUMENT_CAP,
		"GRIEF_WITNESSED": SimNeeds.GRIEF_WITNESSED,
		"GRIEF_HEARD": SimNeeds.GRIEF_HEARD,
		"GRIEF_CAP": SimNeeds.GRIEF_CAP,
		"SLEEP_MOOD": SimNeeds.SLEEP_MOOD,
		"SLEEP_MOOD_CAP": SimNeeds.SLEEP_MOOD_CAP,
		"ILLNESS_MOOD": SimNeeds.ILLNESS_MOOD,
		"SPOILED_MOOD": SimNeeds.SPOILED_MOOD,
	}
	for row in PINNED_CONSTANTS:
		var what: String = String(row["what"])
		var want: float = float(row["is"])
		if absf(float(live[what]) - want) > 0.0001:
			push_error("PINNED: %s is %.4f and shipped as %.4f -- this slice is a rebalance" % [what, float(live[what]), want])
			return false
	if SimNeeds.MEAL_MOOD_TICKS != PINNED_MEAL_TICKS:
		push_error("PINNED: a meal's mood now runs %d ticks against the shipped %d" % [SimNeeds.MEAL_MOOD_TICKS, PINNED_MEAL_TICKS])
		return false
	for row2 in PINNED_FOOD:
		var id: String = String(row2["id"])
		var spec: Variant = SimNeeds.food_spec(w, id)
		if not (spec is Dictionary):
			push_error("PINNED: %s declares no food block at all" % id)
			return false
		var got: float = float((spec as Dictionary).get("mood", 0.0))
		if absf(got - float(row2["mood"])) > 0.0001:
			push_error("PINNED: %s is worth %.2f mood and shipped at %.2f" % [id, got, float(row2["mood"])])
			return false

	# And the measured half, through the verb rather than off the table.
	var baseline: float = _mood_less_pools(w, ent)
	if not _eat_cooked(w, ent):
		push_error("PINNED: the survivor refused a cooked meal, so the shipped number cannot be measured")
		return false
	var moved: float = _mood_less_pools(w, ent) - baseline
	if absf(moved - 8.0) > 0.001:
		push_error("PINNED: a cooked meal moved mood %.3f against the shipped 8.00" % moved)
		return false
	if absf(SimNeeds.comfort_of(w, ent)) > 0.0001:
		push_error("PINNED: eating left %.3f of comfort standing -- the router fell through into the comfort arm" % SimNeeds.comfort_of(w, ent))
		return false
	print("PINNED: %d mood constants, a meal's %d-tick clock and %d food moods are exactly what they shipped as; a cooked meal still moves mood %.2f through the real verb and leaves no comfort behind" % [
		PINNED_CONSTANTS.size(), PINNED_MEAL_TICKS, PINNED_FOOD.size(), moved,
	])
	return true


# --- CAP ------------------------------------------------------------------------------------
#
# needs.gd's own rule, applied rather than routed around: mood sources do not stack unboundedly.
# Three assertions, and the middle one is the true negative that makes the other two mean anything.
#
#   1. One comfort under the cap is worth exactly itself -- not the cap. Without this the lane
#      would pass on an implementation that pinned everybody to fifteen and called it clamping.
#   2. Two comforts whose declared moods sum past the cap are worth **the cap**, and the lane
#      asserts the number rather than an inequality: ten plus eleven is fifteen here.
#   3. A third one on top adds nothing at all, which is what "does not stack" has to mean once the
#      cap is reached rather than merely approached.
func _two_comforts_are_not_the_sum_of_two_comforts() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var a: Variant = SimNeeds.comfort_spec(w, PAPERBACK)
	var b: Variant = SimNeeds.comfort_spec(w, CHESS)
	if not (a is Dictionary) or not (b is Dictionary):
		push_error("CAP: the two fixtures declare no comfort block, so this lane has nothing to judge")
		return false
	var worth_a: float = float((a as Dictionary)["mood"])
	var worth_b: float = float((b as Dictionary)["mood"])
	if worth_a >= SimNeeds.COMFORT_CAP:
		push_error("CAP: %s alone is worth %.2f against a cap of %.2f -- the single-item half of this lane cannot fail" % [PAPERBACK, worth_a, SimNeeds.COMFORT_CAP])
		return false
	if worth_a + worth_b <= SimNeeds.COMFORT_CAP:
		push_error("CAP: the two fixtures sum to %.2f, under the %.2f cap -- the stacking half of this lane cannot fail" % [worth_a + worth_b, SimNeeds.COMFORT_CAP])
		return false

	var baseline: float = _mood_less_pools(w, ent)
	var one: int = _give(w, ent, PAPERBACK)
	if one < 0 or not SimNeeds.use_item(w, ent, one):
		push_error("CAP: the survivor would not read the paperback")
		return false
	var after_one: float = _mood_less_pools(w, ent) - baseline
	if absf(after_one - worth_a) > 0.001:
		push_error("CAP: one comfort worth %.2f moved mood %.3f -- a single item under the cap must read as itself" % [worth_a, after_one])
		return false

	var two: int = _give(w, ent, CHESS)
	if two < 0 or not SimNeeds.use_item(w, ent, two):
		push_error("CAP: the survivor would not play the chess set")
		return false
	var after_two: float = _mood_less_pools(w, ent) - baseline
	if absf(after_two - SimNeeds.COMFORT_CAP) > 0.001:
		push_error("CAP: two comforts carry %.3f of mood, not the %.2f cap" % [after_two, SimNeeds.COMFORT_CAP])
		return false
	if absf(after_two - (worth_a + worth_b)) < 0.001:
		push_error("CAP: two comforts are worth exactly their sum (%.2f) -- they stack" % after_two)
		return false

	var three: int = _give(w, ent, HARMONICA)
	if three < 0 or not SimNeeds.use_item(w, ent, three):
		push_error("CAP: the survivor would not play the harmonica")
		return false
	var after_three: float = _mood_less_pools(w, ent) - baseline
	if absf(after_three - after_two) > 0.001:
		push_error("CAP: a third comfort added %.3f on top of the cap" % (after_three - after_two))
		return false
	# One modifier from one source, and the only way to know it is one is to count them: an
	# implementation that added a second `add` per item would read correctly here through `resolve`
	# only until the first `remove_by_source` took one of them off.
	w.modifiers.call("remove_by_source", SimNeeds.COMFORT_SOURCE, ent)
	var stripped: float = _mood_less_pools(w, ent) - baseline
	if absf(stripped) > 0.001:
		push_error("CAP: %.3f of comfort survived a remove_by_source -- three uses left more than one modifier behind" % stripped)
		return false

	print("CAP: one comfort reads %.2f, two read %.2f rather than their %.2f sum, a third adds %.2f, and the whole of it is one modifier from one source" % [
		after_one, after_two, worth_a + worth_b, after_three - after_two,
	])
	return true


# --- CLOCK ----------------------------------------------------------------------------------
#
# It wears off, and it wears off on the tick its clock named. Tick-exact rather than jumped-and-
# checked: the tick before, the comfort is whole and nothing has been published; the tick itself,
# the modifier is gone, the stored comfort is zero and `mood.comfortFaded` has fired exactly once.
#
# The jump is to `until - 2` and then two `step()`s, because `World.step` increments the tick
# *before* it runs the systems -- so the first step is the tick before and the second is the tick.
func _a_comfort_lifts_on_the_tick_its_clock_named() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var spec: Variant = SimNeeds.comfort_spec(w, HARMONICA)
	if not (spec is Dictionary):
		push_error("CLOCK: the harmonica declares no comfort block, so there is no clock to wait out")
		return false
	var worth: float = float((spec as Dictionary)["mood"])
	var baseline: float = _mood_less_pools(w, ent)
	# Land the clock on a tick that is deliberately **not** a multiple of twenty, and the reason is
	# a sabotage this lane failed to catch before the offset existed. The mood tick runs every
	# twentieth tick, and `_tick_comfort` gated on that same cadence -- the obvious wrong
	# implementation, and the one every neighbouring drain in needs.gd actually uses -- still
	# expires a clock that happens to land on a multiple of twenty. The shipped harmonica runs
	# 24000 ticks off a world booted at tick 36000, so it landed on 60000 and the whole lane passed
	# green while the tick-exactness it claims to prove was gone.
	while (int(w.tick) + int((spec as Dictionary)["ticks"])) % 20 == 0:
		w.tick = int(w.tick) + 1
	var item: int = _give(w, ent, HARMONICA)
	if item < 0 or not SimNeeds.use_item(w, ent, item):
		push_error("CLOCK: the survivor would not play the harmonica")
		return false
	var until: int = int(SimNeeds.of(w, ent).get("comfortUntilTick", -1))
	if until != int(w.tick) + int((spec as Dictionary)["ticks"]):
		push_error("CLOCK: the clock was set to %d against a start of %d and a duration of %d" % [until, int(w.tick), int((spec as Dictionary)["ticks"])])
		return false
	if until % 20 == 0:
		push_error("CLOCK: the clock landed on tick %d, a multiple of the mood cadence -- the offset above stopped working and this lane would pass a tick that is not exact" % until)
		return false

	# The handler accumulates into an Array, never into a captured int: a GDScript lambda captures
	# a primitive by value, which is the trap that made a jam gate blame correct code.
	var faded: Array = []
	w.events.subscribe({"type": "mood.comfortFaded", "id": "gate.comfort", "handler": func(e: Dictionary) -> void:
		faded.append(int(e.get("entity", -1)))
	})

	w.tick = until - 2
	w.step()
	if int(w.tick) != until - 1:
		push_error("CLOCK: the jump landed on tick %d, one short of the tick before %d" % [int(w.tick), until])
		return false
	var before: float = _mood_less_pools(w, ent) - baseline
	if absf(before - worth) > 0.001:
		push_error("CLOCK: on the tick before its clock the comfort read %.3f, not the %.2f it was worth" % [before, worth])
		return false
	if faded.has(ent):
		push_error("CLOCK: mood.comfortFaded fired on the tick *before* the clock ran out")
		return false
	if absf(SimNeeds.comfort_of(w, ent) - worth) > 0.001:
		push_error("CLOCK: the stored comfort was already %.3f on the tick before" % SimNeeds.comfort_of(w, ent))
		return false

	w.step()
	if not faded.has(ent):
		push_error("CLOCK: the clock ran out on tick %d and nothing published mood.comfortFaded" % int(w.tick))
		return false
	if faded.count(ent) != 1:
		push_error("CLOCK: mood.comfortFaded fired %d times for one comfort" % faded.count(ent))
		return false
	var after: float = _mood_less_pools(w, ent) - baseline
	if absf(after) > 0.001:
		push_error("CLOCK: %.3f of comfort survived its own clock" % after)
		return false
	if absf(SimNeeds.comfort_of(w, ent)) > 0.0001 or int(SimNeeds.of(w, ent).get("comfortUntilTick", -1)) >= 0:
		push_error("CLOCK: the clock ran out but the needs component still carries %.3f until tick %d" % [SimNeeds.comfort_of(w, ent), int(SimNeeds.of(w, ent).get("comfortUntilTick", -1))])
		return false

	# And a second clock does not shorten a longer one already running. Take the harmonica (long)
	# and then the cigarettes (short): the end stays the harmonica's.
	var w2: Variant = _world()
	var ent2: int = int(w2.player)
	var long_item: int = _give(w2, ent2, HARMONICA)
	if long_item < 0 or not SimNeeds.use_item(w2, ent2, long_item):
		push_error("CLOCK: the second fixture would not play the harmonica")
		return false
	var long_until: int = int(SimNeeds.of(w2, ent2).get("comfortUntilTick", -1))
	var short_item: int = _give(w2, ent2, CIGARETTES)
	if short_item < 0 or not SimNeeds.use_item(w2, ent2, short_item):
		push_error("CLOCK: the survivor would not take a cigarette")
		return false
	var now_until: int = int(SimNeeds.of(w2, ent2).get("comfortUntilTick", -1))
	if now_until != long_until:
		push_error("CLOCK: a shorter comfort moved the end from tick %d to %d" % [long_until, now_until])
		return false

	print("CLOCK: %s is worth %.2f and holds it whole through tick %d, is gone on tick %d with one mood.comfortFaded, and a shorter comfort taken on top does not cut the longer one short" % [
		HARMONICA, worth, until - 1, until,
	])
	return true


# --- REACH ----------------------------------------------------------------------------------
#
# The dead-socket lane, and this milestone has paid for its absence eleven times. Three questions,
# because the key can be dead in three different places:
#
#   1. Every base declaring `comfort` is rolled by some loot table. A perfect block on an item
#      nobody can find is `item.filter.pump` again, which is exactly how the transform slice's own
#      REACH lane earned its keep on its first run.
#   2. Something *reads* the key, and the reader is named where the call is made rather than
#      matched on a base id -- check_respond and check_weather both went red for needles that could
#      not follow a helper into its new home.
#   3. `check_m2_gear.gd`'s READ_KEYS carries "comfort", which is what makes question 1 automatic
#      for every base added after this one rather than a fact this file happens to assert today.
func _every_comfort_is_findable_and_the_key_is_read() -> bool:
	var w: Variant = _world()
	var findable: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for t_v in file_v as Array:
			if t_v is Dictionary and String((t_v as Dictionary).get("id", "")).begins_with("loot."):
				for row_v in (t_v as Dictionary).get("entries", []) as Array:
					findable[String((row_v as Dictionary).get("item", ""))] = true
	if findable.is_empty():
		push_error("REACH: the loot scan found no rows at all, so it has nothing to judge")
		return false
	if findable.has("item.gate.nowhere"):
		push_error("REACH: the loot scan found an id that does not exist")
		return false

	var declared: Array[String] = []
	var unreachable: Array[String] = []
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not e.has("comfort"):
			continue
		var id: String = String(e.get("id", ""))
		declared.append(id)
		if SimNeeds.comfort_spec(w, id) == null:
			push_error("REACH: %s declares a comfort block the reader refuses -- it is content that does nothing" % id)
			return false
		if not findable.has(id):
			unreachable.append(id)
	if declared.is_empty():
		push_error("REACH: no shipped base declares a comfort block, so this lane has nothing to judge")
		return false
	if not unreachable.is_empty():
		push_error("REACH: %s are comforting and in no loot table -- complete, correct, and unfindable" % str(unreachable))
		return false

	for row in READERS:
		var path: String = String(row["file"])
		var code: String = FileAccess.get_file_as_string(path)
		if code.is_empty():
			push_error("REACH: %s could not be read, so the reader scan cannot judge it" % path)
			return false
		if not code.contains(String(row["needle"])):
			push_error("REACH: %s -- %s does not contain `%s`, so the key is read by nothing the gate can find" % [String(row["what"]), path, String(row["needle"])])
			return false
		# The true negative for the scanner itself: shown a needle that is not there, it says no.
		if code.contains("get(\"comfortableness\")"):
			push_error("REACH: the reader scan matched a needle that is not in %s" % path)
			return false

	# The gear gate's catalogue has to know the key exists, and that is a *membership* question
	# rather than a substring one. The needle used to be the tail of the list, `"noise", "comfort"]`,
	# because the bare word appears in that file's prose too and a needle a comment can satisfy
	# cannot fail. That reasoning was right and the needle was still wrong: the books slice appended
	# `"teaches"` after `"comfort"` and the lane went red against a gear gate that was correct --
	# CLAUDE.md's own "follow the call a link further, never drop the needle". So the line is
	# isolated first and the key looked for inside it, which no comment can satisfy and no later
	# key can displace. check_m2_teach.gd does the same thing and is the precedent.
	var gear: String = FileAccess.get_file_as_string("res://check_m2_gear.gd")
	var read_keys: String = ""
	for line in gear.split("\n"):
		if String(line).begins_with("const READ_KEYS"):
			read_keys = String(line)
	if read_keys.is_empty():
		push_error("REACH: check_m2_gear.gd has no READ_KEYS line, so this assertion is reading the wrong file")
		return false
	if read_keys.contains("\"notakey\""):
		push_error("REACH: the READ_KEYS scan matched a key that is not in the list")
		return false
	if not read_keys.contains("\"comfort\""):
		push_error("REACH: check_m2_gear.gd's READ_KEYS does not list 'comfort', so its catalogue cannot see a comforting item at all")
		return false

	# And the live half, which is the only one that proves a *survivor* can reach it: a shipped
	# comfort actually moves the stat, through the router the word menu calls.
	var ent: int = int(w.player)
	var baseline: float = _mood_less_pools(w, ent)
	var item: int = _give(w, ent, declared[0])
	if item < 0 or not SimNeeds.use_item(w, ent, item):
		push_error("REACH: %s is comforting on paper and the router refused it" % declared[0])
		return false
	var moved: float = _mood_less_pools(w, ent) - baseline
	if moved <= 0.0:
		push_error("REACH: using %s moved mood %.3f -- the key is parsed and read by nothing" % [declared[0], moved])
		return false

	print("REACH: %d bases declare comfort and every one is rolled by a table; %d named readers each contain their call; using %s moves mood %.2f through the router the menu asks" % [
		declared.size(), READERS.size(), declared[0], moved,
	])
	return true


# --- MENU -----------------------------------------------------------------------------------
#
# One function, asked twice. The word menu offers "use" when `can_use` says yes and the intake runs
# the same predicate, so a screen cannot offer a verb the sim then silently drops -- the rule the
# illness cure, the drinks and the noise devices already keep. The true negative is a plank: the
# menu must not offer it and the intake must refuse it, and both for the same reason.
func _the_menu_and_the_intake_are_one_function() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var judged: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not e.has("comfort"):
			continue
		var id: String = String(e.get("id", ""))
		var item: int = _give(w, ent, id)
		if item < 0:
			push_error("MENU: %s would not spawn into a pocket" % id)
			return false
		if not SimNeeds.can_use(w, ent, item):
			push_error("MENU: the menu would not offer `use` for %s, which is comforting" % id)
			return false
		if not SimNeeds.use_item(w, ent, item):
			push_error("MENU: the menu offers `use` for %s and the intake refused it" % id)
			return false
		_take_back(w, item)
		judged += 1

	var plank: int = _give(w, ent, PLANK)
	if plank < 0:
		push_error("MENU: the plank fixture would not spawn, so the true negative has nothing to judge")
		return false
	if SimNeeds.can_use(w, ent, plank):
		push_error("MENU: the menu offers `use` for a sawn plank")
		return false
	if SimNeeds.use_item(w, ent, plank):
		push_error("MENU: the intake took a sawn plank as a comfort")
		return false
	if SimNeeds.take_comfort(w, ent, plank):
		push_error("MENU: take_comfort took a sawn plank when called directly -- it trusts can_use rather than refusing on its own account")
		return false

	print("MENU: all %d comforting bases are offered by the menu and taken by the intake; a sawn plank is refused by both, and by take_comfort called directly" % judged)
	return true


# --- BLOCK ----------------------------------------------------------------------------------
#
# The content validator is shallow -- it checks top-level property types and does not recurse -- so
# a `comfort` block with a lift and no clock behind it would pass `godot:validate` and be a
# permanent free mood that nothing would ever report. `drink_spec` refuses a half stimulant for
# exactly this reason and `comfort_spec` copies it: the block is judged whole, and a malformed one
# makes an item that does nothing rather than one that does something wrong.
#
# Every case is put in front of the *real* reader by injecting a file into the world's own content
# tree, because a gate that re-implements the predicate it is testing tests its own copy.
func _a_half_block_is_refused_rather_than_taken_for_free() -> bool:
	var w: Variant = _world()
	var cases: Array[Dictionary] = [
		{"why": "a lift with no clock", "block": {"mood": 9}},
		{"why": "a clock with no lift", "block": {"ticks": 12000}},
		{"why": "a zero lift", "block": {"mood": 0, "ticks": 12000}},
		{"why": "a negative lift", "block": {"mood": -9, "ticks": 12000}},
		{"why": "a clock of no ticks", "block": {"mood": 9, "ticks": 0}},
		{"why": "a block that is not a block", "block": 9},
		{"why": "no block at all", "block": null},
	]
	var fabricated: Array = []
	for i in cases.size():
		fabricated.append(_fabricate("item.gate.comfort%d" % i, (cases[i] as Dictionary)["block"]))
	# The control: an identical fabricated base with a whole block, so a lane where *every* case is
	# refused because injection silently did nothing cannot pass.
	fabricated.append(_fabricate("item.gate.comfortok", {"mood": 9, "ticks": 12000}))
	_inject(w, fabricated)

	var ent: int = int(w.player)
	if SimNeeds.comfort_spec(w, "item.gate.comfortok") == null:
		push_error("BLOCK: the injected control is not readable, so every refusal below proves nothing about the predicate")
		return false
	var baseline: float = _mood_less_pools(w, ent)
	var control: int = _give(w, ent, "item.gate.comfortok")
	if control < 0 or not SimNeeds.use_item(w, ent, control):
		push_error("BLOCK: the injected control would not be used")
		return false
	if absf(_mood_less_pools(w, ent) - baseline - 9.0) > 0.001:
		push_error("BLOCK: the injected control moved mood %.3f rather than its declared 9.00" % (_mood_less_pools(w, ent) - baseline))
		return false

	for i2 in cases.size():
		var id: String = "item.gate.comfort%d" % i2
		var why: String = String((cases[i2] as Dictionary)["why"])
		if SimNeeds.comfort_spec(w, id) != null:
			push_error("BLOCK: %s was read as a whole comfort block" % why)
			return false
		if SimNeeds.is_comfort(w, id):
			push_error("BLOCK: %s answers is_comfort" % why)
			return false
		var w2: Variant = _world()
		_inject(w2, fabricated)
		var ent2: int = int(w2.player)
		var base2: float = _mood_less_pools(w2, ent2)
		var bad: int = _give(w2, ent2, id)
		if bad < 0:
			push_error("BLOCK: %s would not spawn, so the refusal below has nothing to judge" % why)
			return false
		if SimNeeds.can_use(w2, ent2, bad):
			push_error("BLOCK: the menu offers `use` for %s" % why)
			return false
		if SimNeeds.take_comfort(w2, ent2, bad):
			push_error("BLOCK: %s was taken as a comfort anyway" % why)
			return false
		if absf(_mood_less_pools(w2, ent2) - base2) > 0.0001:
			push_error("BLOCK: %s moved mood without being a comfort" % why)
			return false

	print("BLOCK: %d malformed comfort blocks are each refused outright by the real reader, while an otherwise identical whole one on the same injected file is worth its declared 9.00" % cases.size())
	return true

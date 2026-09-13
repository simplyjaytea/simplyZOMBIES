extends SceneTree
# Drain, bands, player eat/drink/wash/sleep/fire, HUD prose, Need hold.

const SimBoot = preload("res://sim/boot.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _drain() and ok
	ok = _bands() and ok
	ok = _verbs() and ok
	ok = _hud() and ok
	ok = _hold() and ok
	ok = _sepsis() and ok
	ok = _mood_bands_are_a_decline_not_a_cliff() and ok
	ok = _low_mood_slows_work_and_miserable_mood_refuses_it() and ok
	ok = _arguments_spread_misery_and_stop_short_of_a_spiral() and ok
	ok = _food_is_content_and_says_the_same_thing_the_table_did() and ok
	ok = _raw_and_spoiled_food_carry_illness_risk() and ok
	ok = _a_death_costs_the_living() and ok
	ok = _grief_is_charged_once_and_drains_away() and ok
	ok = _the_bathroom_need_drains_and_is_answered_at_a_latrine() and ok
	ok = _nowhere_to_go_costs_hygiene_and_pride() and ok
	ok = _an_npc_takes_itself_to_the_latrine() and ok
	ok = _a_meals_mood_is_bounded_and_wears_off() and ok
	ok = _a_survivor_who_dies_in_bed_gives_the_bed_back() and ok
	ok = _the_deep_cold_is_reachable_and_interrupts_work() and ok
	ok = _a_good_nights_sleep_beats_a_bad_one_and_it_shows_the_next_morning() and ok
	ok = _each_sleep_factor_moves_the_quality_alone() and ok
	ok = _pain_degrades_sleep_and_painkillers_buy_a_night() and ok
	ok = _a_rough_night_costs_mood_then_stops_costing_it() and ok
	ok = _drink_is_content_and_the_bottle_leaves_an_empty() and ok
	ok = _a_stimulant_lifts_rest_now_and_crashes_later() and ok
	ok = _a_careful_pantry_slows_spoilage() and ok
	ok = _untreated_water_carries_illness_and_a_fire_boils_it() and ok
	ok = _a_lit_fire_burns_down() and ok
	ok = _bedding_moves_the_night_and_bare_boards_move_nothing() and ok
	ok = _soap_buys_a_wash_that_lasts() and ok
	if ok:
		print("M2_NEEDS_OK drain bands verbs hud hold, low mood has consequences, food is content and can make you ill, a death costs the living, everybody has to go, a meal's mood wears off, the dead give back the bed, the deep cold is reachable, sleep has a quality, what you sleep on moves it and bare boards do not, soap buys a wash that lasts, drinks are content and leave their empties, a stimulant is a loan, a careful pantry keeps, the well's water wants a fire, and a lit fire burns down")
		quit(0)
	else:
		push_error("M2_NEEDS_FAIL")
		quit(1)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

func _drain() -> bool:
	var w: Variant = _world()
	var n: Dictionary = SimNeeds.of(w, w.player)
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	for _i in 2000:
		w.step()
	n = SimNeeds.of(w, w.player)
	var dh: float = 100.0 - float(n["hunger"])
	var dt: float = 100.0 - float(n["thirst"])
	var want_h: float = SimNeeds.drain_hunger() * 2000.0
	var want_t: float = SimNeeds.drain_thirst() * 2000.0
	if absf(dh - want_h) > 0.05 or absf(dt - want_t) > 0.05:
		push_error("drain h=%s want %s t=%s want %s" % [str(dh), str(want_h), str(dt), str(want_t)])
		return false
	if dh * 1.8 > dt:
		push_error("thirst should drain faster than hunger")
		return false
	print("DRAIN OK hunger %.4f thirst %.4f" % [dh, dt])
	return true

func _bands() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, 0.8)
	w.step()
	var n: Dictionary = SimNeeds.of(w, w.player)
	var t: String = String(n.get("temperature", ""))
	if t != "a_little_cold" and t != "very_cold" and t != "comfortable":
		push_error("night band %s" % t)
		return false
	var fires: Array[int] = w.components.query(["campfire"])
	if fires.is_empty():
		push_error("no campfire")
		return false
	var fp: Variant = w.components.get_component(fires[0], "position")
	w.components.set_component(w.player, "position", {"x": float((fp as Dictionary)["x"]), "y": float((fp as Dictionary)["y"])})
	SimNeeds.set_lit(w, fires[0], true)
	w.step()
	n = SimNeeds.of(w, w.player)
	if String(n.get("temperature", "")) != "comfortable":
		push_error("heat failed %s" % str(n.get("temperature")))
		return false
	print("BANDS OK night then fire")
	return true

func _verbs() -> bool:
	var w: Variant = _world()
	# Nothing cookable on the pile before the first step. This lane is about what E does, and one
	# of its claims is that a second E douses the fire the first one lit -- but a colonist cooking
	# is `SimJobs._do_cook` calling `set_lit(fire, true, true)` every tick it works, so a cook
	# assigned anywhere in the district holds that fire open and the douse silently loses. Since
	# the transform slice it is *content* that decides what can be cooked, so which loot the
	# district rolls onto its stockpile decides whether this lane has a second actor in it. It is
	# cleared rather than relied on: a lane that passes because the seed happened to roll a mask
	# instead of a sack of potatoes is a lane one loot edit away from red, and the cook keeping its
	# own fire lit is correct behaviour that belongs to check_m2_jobs.
	for item in SimNeeds.stockpile_items(w):
		if not SimJobs.cooks_into(w, int(item)).is_empty():
			w.components.remove(int(item), "position")
	var food: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, food):
		push_error("stow food")
		return false
	var n: Dictionary = SimNeeds.of(w, w.player)
	n["hunger"] = 20.0
	w.commands.push({"type": "item.use", "item": food})
	w.step()
	n = SimNeeds.of(w, w.player)
	if float(n["hunger"]) < 55.0:
		push_error("eat %s" % str(n["hunger"]))
		return false
	var water: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, water):
		push_error("stow water")
		return false
	n["thirst"] = 10.0
	w.commands.push({"type": "item.use", "item": water})
	w.step()
	n = SimNeeds.of(w, w.player)
	if float(n["thirst"]) < 55.0:
		push_error("drink %s" % str(n["thirst"]))
		return false
	var water2: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	SimInventory.stow(w, w.player, water2)
	n["hygiene"] = "filthy"
	w.commands.push({"type": "item.wash", "item": water2})
	w.step()
	n = SimNeeds.of(w, w.player)
	if String(n["hygiene"]) != "clean":
		push_error("wash %s" % str(n["hygiene"]))
		return false
	var beds: Array[int] = w.components.query(["bed"])
	if beds.is_empty():
		push_error("no bed")
		return false
	var bp: Variant = w.components.get_component(beds[0], "position")
	w.components.set_component(w.player, "position", {"x": float((bp as Dictionary)["x"]), "y": float((bp as Dictionary)["y"])})
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	# E picks up first — clear reach so sleep/fire can fire.
	for g in SimInventory.ground_items(w):
		var gp: Variant = w.components.get_component(g, "position")
		if not gp is Dictionary:
			continue
		var dx: float = float((gp as Dictionary)["x"]) - float((bp as Dictionary)["x"])
		var dy: float = float((gp as Dictionary)["y"]) - float((bp as Dictionary)["y"])
		if dx * dx + dy * dy <= 2.25:
			w.components.remove(g, "position")
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "sleeping"):
		push_error("sleep E failed")
		return false
	w.components.remove(w.player, "sleeping")
	var fires: Array[int] = w.components.query(["campfire"])
	var fp: Variant = w.components.get_component(fires[0], "position")
	w.components.set_component(w.player, "position", {"x": float((fp as Dictionary)["x"]), "y": float((fp as Dictionary)["y"])})
	for g2 in SimInventory.ground_items(w):
		var gp2: Variant = w.components.get_component(g2, "position")
		if not gp2 is Dictionary:
			continue
		var dx2: float = float((gp2 as Dictionary)["x"]) - float((fp as Dictionary)["x"])
		var dy2: float = float((gp2 as Dictionary)["y"]) - float((fp as Dictionary)["y"])
		if dx2 * dx2 + dy2 * dy2 <= 2.25:
			w.components.remove(g2, "position")
	w.commands.push({"type": "use.context"})
	w.step()
	var cf: Variant = w.components.get_component(fires[0], "campfire")
	if not cf is Dictionary or not bool((cf as Dictionary).get("lit", false)):
		push_error("light E failed")
		return false
	w.commands.push({"type": "use.context"})
	w.step()
	cf = w.components.get_component(fires[0], "campfire")
	if bool((cf as Dictionary).get("lit", true)):
		push_error("douse E failed")
		return false
	print("VERBS OK eat drink wash sleep fire")
	return true

func _hud() -> bool:
	var w: Variant = _world()
	var n: Dictionary = SimNeeds.of(w, w.player)
	n["hunger"] = 50.0
	n["thirst"] = 90.0
	n["rest"] = 90.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	var line: String = SimNeeds.hud_clause(w, w.player, false)
	if line != "You're peckish.":
		push_error("hud %s" % line)
		return false
	n["thirst"] = 20.0
	line = SimNeeds.hud_clause(w, w.player, false)
	if line != "You're thirsty.":
		push_error("hud thirst %s" % line)
		return false
	print("HUD OK peckish then thirsty")
	return true

func _hold() -> bool:
	var w: Variant = _world()
	w.needsHoldMax = true
	var n: Dictionary = SimNeeds.of(w, w.player)
	n["hunger"] = 10.0
	w.step()
	n = SimNeeds.of(w, w.player)
	if absf(float(n["hunger"]) - 100.0) > 0.01 or String(n["crisis"]) != "none":
		push_error("hold %s" % str(n))
		return false
	print("HOLD OK")
	return true

func _sepsis() -> bool:
	if absf(SimNeeds.sepsis_mul("clean") - 1.0) > 0.01:
		return false
	if absf(SimNeeds.sepsis_mul("a_little_dirty") - 1.25) > 0.01:
		return false
	if absf(SimNeeds.sepsis_mul("dirty") - 1.75) > 0.01:
		return false
	if absf(SimNeeds.sepsis_mul("filthy") - 2.5) > 0.01:
		return false
	print("SEPSIS OK muls")
	return true


# --- mood consequences (docs/04) -------------------------------------------------------------
#
# "Low mood does not produce a rage meltdown. It produces: slower work, more mistakes ... refusing
# assigned jobs; arguments -- which damage other survivors' mood, so misery spreads; ... at the
# extreme: leaving." Only the extreme was wired: mood <= -80 walked the survivor out and
# everything between "fine" and "gone" did nothing. A cliff at -80 is the dramatic break that
# document explicitly rules out.

# Drives an entity's mood to a chosen value with a modifier of the gate's own, so a band can be
# reached without starving somebody for three days first. Its own source, so it composes with the
# real ones rather than fighting them.
func _set_mood(w: Variant, ent: int, value: float) -> void:
	w.modifiers.call("remove_by_source", "test.mood", ent)
	var now: float = float(w.modifiers.call("resolve", "mood", ent))
	w.modifiers.call("add", {"stat": "mood", "op": "add", "value": value - now, "source": "test.mood"}, ent)


func _mood_bands_are_a_decline_not_a_cliff() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var want: Array = [
		{"mood": 0.0, "band": "content"},
		{"mood": SimNeeds.MOOD_LOW - 1.0, "band": "low"},
		{"mood": SimNeeds.MOOD_MISERABLE - 1.0, "band": "miserable"},
		{"mood": SimNeeds.LEAVE_AT - 1.0, "band": "breaking"},
	]
	for case in want:
		var c: Dictionary = case as Dictionary
		_set_mood(w, ent, float(c["mood"]))
		var got: String = SimNeeds.mood_band(w, ent)
		if got != String(c["band"]):
			push_error("mood %.1f read as band %s, expected %s" % [float(c["mood"]), got, String(c["band"])])
			return false

	# The boundaries are inclusive on the worse side, and asserted rather than assumed: a band that
	# was off by one would still pass the four cases above.
	_set_mood(w, ent, SimNeeds.MOOD_LOW)
	if SimNeeds.mood_band(w, ent) != "low":
		push_error("exactly MOOD_LOW did not read as low")
		return false
	_set_mood(w, ent, SimNeeds.MOOD_LOW + 0.01)
	if SimNeeds.mood_band(w, ent) != "content":
		push_error("just above MOOD_LOW did not read as content -- the band has no upper edge")
		return false
	_set_mood(w, ent, 0.0)
	print("MOOD BANDS OK content / low (%.0f) / miserable (%.0f) / breaking (%.0f), boundaries inclusive on the worse side" % [
		SimNeeds.MOOD_LOW, SimNeeds.MOOD_MISERABLE, SimNeeds.LEAVE_AT,
	])
	return true


# Slower work and refusing jobs, measured on a job's own countdown and on what gets picked.
func _low_mood_slows_work_and_miserable_mood_refuses_it() -> bool:
	const WINDOW: int = 200
	var advanced: Dictionary = {}
	var mistakes: Dictionary = {}
	for case in [{"band": "content", "mood": 0.0}, {"band": "low", "mood": SimNeeds.MOOD_LOW - 1.0}, {"band": "miserable", "mood": SimNeeds.MOOD_MISERABLE - 1.0}]:
		var c: Dictionary = case as Dictionary
		var w: Variant = _world()
		var ent: int = int(w.player)
		var slips: Array = []
		w.events.subscribe({"type": "job.mistake", "id": "gate.mistake", "handler": func(_e: Dictionary) -> void:
			slips.append(1)
		})
		_set_mood(w, ent, float(c["mood"]))
		# A job with a long countdown, advanced by hand: this measures _progress, not the job AI's
		# choice of what to do, and mixing the two would make a refusal look like slow work.
		var job: Dictionary = {"kind": "Construct", "ticksLeft": 100000, "path": [], "pathGen": -1}
		var before: int = int(job["ticksLeft"])
		for _i in WINDOW:
			SimJobs._progress(w, ent, job)
			w.tick = int(w.tick) + 1
		# job.mistake is published, and publish() only queues -- handlers run at drain, at the end
		# of world.step(). This loop never steps, so drain by hand or the counter reads zero
		# whatever happened.
		w.events.drain()
		advanced[String(c["band"])] = before - int(job["ticksLeft"])
		mistakes[String(c["band"])] = slips.size()

	var content: int = int(advanced["content"])
	var low: int = int(advanced["low"])
	var miserable: int = int(advanced["miserable"])
	if content != WINDOW:
		push_error("a content worker advanced %d of %d ticks -- something is slowing them already" % [content, WINDOW])
		return false
	if low >= content:
		push_error("a low-mood worker advanced %d against a content worker's %d" % [low, content])
		return false
	if miserable >= low:
		push_error("a miserable worker advanced %d, no worse than a low-mood worker's %d" % [miserable, low])
		return false

	# Slowdown and mistakes are separate consequences and are asserted separately, because the
	# tick count above cannot tell them apart. The expected slowdown alone is WINDOW / the skip
	# rate; anything further behind that is mistakes, and they must be zero for a content worker.
	if int(mistakes["content"]) != 0:
		push_error("a content worker made %d mistakes" % int(mistakes["content"]))
		return false
	if int(mistakes["low"]) != 0:
		push_error("a low-mood worker made %d mistakes -- mistakes belong to miserable and worse" % int(mistakes["low"]))
		return false
	if int(mistakes["miserable"]) == 0:
		push_error("a miserable worker made no mistakes over %d ticks" % WINDOW)
		return false
	var slowdown_only: int = WINDOW - (WINDOW / SimJobs.MISERABLE_SLOW_EVERY)
	if miserable >= slowdown_only:
		push_error("a miserable worker advanced %d, which is the slowdown alone (%d) -- the mistakes cost nothing" % [miserable, slowdown_only])
		return false

	# Refusal: a miserable survivor declines the jobs they ranked below REFUSE_PRIORITY_ABOVE and
	# keeps the ones above it. The control is the identical colony at content mood, which must
	# refuse nothing at all.
	var refusals: Dictionary = {}
	for case2 in [{"band": "miserable", "mood": SimNeeds.MOOD_MISERABLE - 1.0}, {"band": "content", "mood": 0.0}]:
		var c2: Dictionary = case2 as Dictionary
		var w2: Variant = _world()
		var seen: Array = []
		w2.events.subscribe({"type": "job.refused", "id": "gate.refused", "handler": func(e: Dictionary) -> void:
			seen.append(int(e.get("entity", -1)))
		})
		for ent2 in w2.components.query(["needs", "position"]):
			_set_mood(w2, int(ent2), float(c2["mood"]))
		for _i in 400:
			w2.step()
			for ent3 in w2.components.query(["needs", "position"]):
				_set_mood(w2, int(ent3), float(c2["mood"]))
		refusals[String(c2["band"])] = seen.size()

	if int(refusals["miserable"]) == 0:
		push_error("no miserable survivor refused a single job over 400 ticks")
		return false
	if int(refusals["content"]) != 0:
		push_error("a content colony refused %d jobs -- the refusal is not about mood" % int(refusals["content"]))
		return false
	print("MOOD WORK OK %d/%d/%d ticks advanced over %d at content/low/miserable (slowdown alone would be %d); %d mistakes while miserable, 0 below; %d sulks while miserable and 0 while content" % [
		content, low, miserable, WINDOW, slowdown_only, int(mistakes["miserable"]), int(refusals["miserable"]),
	])
	return true


# Every shambler out of the world, components and modifiers with it. Called each tick by the
# arguments lane: what it measures is two survivors standing together, and a pack in the annex is
# a death, not an argument.
func _clear_shamblers(w: Variant) -> void:
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))


# "Arguments -- which damage other survivors' mood, so misery spreads." And the half that keeps it
# from being the meltdown docs/04 rules out: the damage is capped and it drains away.
#
# The colony is emptied of shamblers for the measurement. The roads slice's widened suburb brought
# a pack into the annex on this very seed around tick 37,500 of the 4,800-tick hold -- measured
# with a driver: Mara grabbed by one, Ellis by another and a corpse by 38,400, three arguments in --
# and a lane about arguing was reading a corpse's rebuilt needs and reporting "the victim carries
# none of it". Pinning the grab loop off (the latrine walk's precedent) was not enough: a held,
# miserable player standing still in a pack is swiped to death instead. So the pack goes, through
# `world.despawn` (components and modifiers with it -- `entities.despawn` leaves both behind), and
# goes again every tick in case the director sends more; the contact loop has its own gates. The
# lane also says out loud if either party dies mid-hold, so the next layout change that reaches
# the annex fails by name rather than by a number that reads zero.
func _arguments_spread_misery_and_stop_short_of_a_spiral() -> bool:
	var w: Variant = _world()
	_clear_shamblers(w)
	var others: Array = []
	for ent in w.components.query(["needs", "position"]):
		others.append(int(ent))
	if others.size() < 2:
		push_error("SKIP-WORTHY: the booted colony has %d survivors, so nobody has anybody to argue with" % others.size())
		return false

	var arguer: int = int(others[0])
	var victim: int = int(others[1])
	# Stand them together and make one of them miserable. The other stays where their mood was.
	var at: Dictionary = w.components.get_component(arguer, "position") as Dictionary
	var there: Dictionary = w.components.get_component(victim, "position") as Dictionary
	there["x"] = float(at["x"]) + 1.0
	there["y"] = float(at["y"])
	_set_mood(w, arguer, SimNeeds.MOOD_MISERABLE - 5.0)

	var heard: Array = []
	w.events.subscribe({"type": "mood.argument", "id": "gate.argument", "handler": func(e: Dictionary) -> void:
		heard.append(e)
	})

	# Long enough for the cap to be reached several times over, which is the point: the assertion
	# is that it stops.
	var runs: int = SimNeeds.ARGUMENT_TICKS * 8
	for _i in runs:
		_clear_shamblers(w)
		w.step()
		# Hold both in place and the arguer miserable, so this measures arguing rather than the
		# job AI walking one of them out of earshot.
		there["x"] = float(at["x"]) + 1.0
		there["y"] = float(at["y"])
		_set_mood(w, arguer, SimNeeds.MOOD_MISERABLE - 5.0)

	if heard.is_empty():
		push_error("no argument in %d ticks with a miserable survivor standing next to somebody" % runs)
		return false
	for party in [arguer, victim]:
		if w.components.has_component(int(party), "corpse") or not w.components.has_component(int(party), "needs"):
			push_error("survivor %d died during the %d-tick hold (a shambler reached the annex); this lane measured a death, not an argument" % [int(party), runs])
			return false
	var carried: float = float(SimNeeds.of(w, victim).get("argued", 0.0))
	if carried <= 0.0:
		push_error("%d arguments landed and the victim carries none of it" % heard.size())
		return false
	if carried > SimNeeds.ARGUMENT_CAP + 0.001:
		push_error("the victim carries %.2f of argument, past the cap of %.2f -- misery has no ceiling" % [carried, SimNeeds.ARGUMENT_CAP])
		return false

	# It drains. Make the arguer content and the victim must recover on their own.
	_set_mood(w, arguer, 0.0)
	var before_decay: float = carried
	for _i in 2000:
		w.step()
		_set_mood(w, arguer, 0.0)
	var after: float = float(SimNeeds.of(w, victim).get("argued", 0.0))
	if after >= before_decay:
		push_error("argument damage did not drain with nobody arguing: %.3f -> %.3f over 2000 ticks" % [before_decay, after])
		return false

	# The true negative: the same colony with nobody miserable has no arguments at all, so this is
	# measuring mood rather than proximity.
	var calm: Variant = _world()
	_clear_shamblers(calm)
	var quiet: Array = []
	calm.events.subscribe({"type": "mood.argument", "id": "gate.calm", "handler": func(_e: Dictionary) -> void:
		quiet.append(1)
	})
	for ent4 in calm.components.query(["needs", "position"]):
		_set_mood(calm, int(ent4), 0.0)
	for _i in runs:
		_clear_shamblers(calm)
		calm.step()
		for ent5 in calm.components.query(["needs", "position"]):
			_set_mood(calm, int(ent5), 0.0)
	if not quiet.is_empty():
		push_error("a content colony had %d arguments" % quiet.size())
		return false

	print("ARGUMENTS OK %d arguments landed, the victim carried %.1f capped at %.1f and drained to %.1f; a content colony had none" % [
		heard.size(), before_decay, SimNeeds.ARGUMENT_CAP, after,
	])
	return true


# --- food is content, and bad food makes you ill (docs/12, docs/04) --------------------------

# docs/12: "Resources, location loot tables, and spoilage rules are JSON." The loot tables moved a
# slice ago; this is the spoilage half. The retired `SimNeeds.FOOD` table is pinned here by value,
# so the move is provably a change of *where* the numbers live and not of what they say -- if a
# content edit ever changes the diet, this fails and makes that deliberate rather than incidental.
const RETIRED_FOOD_TABLE: Dictionary = {
	"item.food.canned": {"hunger": 40.0, "mood": 0.0, "spoilDays": 0.0},
	"item.food.raw": {"hunger": 25.0, "mood": -8.0, "spoilDays": 2.0},
	"item.food.cooked": {"hunger": 60.0, "mood": 8.0, "spoilDays": 1.0},
}

func _food_is_content_and_says_the_same_thing_the_table_did() -> bool:
	var w: Variant = _world()
	for base_id in RETIRED_FOOD_TABLE.keys():
		var want: Dictionary = RETIRED_FOOD_TABLE[base_id] as Dictionary
		var got_v: Variant = SimNeeds.food_spec(w, String(base_id))
		if not (got_v is Dictionary):
			push_error("%s declares no `food` block, so it is no longer edible" % String(base_id))
			return false
		var got: Dictionary = got_v as Dictionary
		for key in want.keys():
			if absf(float(got.get(key, -999.0)) - float(want[key])) > 0.001:
				push_error("%s.%s is %s in content, was %s in the retired table" % [
					String(base_id), String(key), str(got.get(key)), str(want[key]),
				])
				return false

	# The true negative and the thing that makes `food` load-bearing: is_food asks nothing but the
	# presence of the block, so something that is obviously not edible must not be.
	for not_food in ["item.scrap.metal", "item.bandage.cloth", "item.pistol.service"]:
		if SimNeeds.is_food(w, not_food):
			push_error("%s reads as food" % not_food)
			return false
	if SimNeeds.is_food(w, "item.not.a.real.base"):
		push_error("a base that does not exist reads as food")
		return false

	# And the spoil clock is driven by the content number rather than a remembered one: canned
	# declares 0 days and must never gain a spoilage component at all.
	var canned: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	var raw: int = SimItems.spawn_item(w, "item.food.raw", {"tier": "scavenged"})
	if w.components.has_component(canned, "spoilage"):
		push_error("canned food, which declares spoilDays 0, was given a spoil clock")
		return false
	var sp: Variant = w.components.get_component(raw, "spoilage")
	if not (sp is Dictionary):
		push_error("raw food, which declares spoilDays 2, was given no spoil clock")
		return false
	var want_ticks: int = int(2.0 * float(Clock.DAY_TICKS))
	if int((sp as Dictionary).get("spoilTicks", -1)) != want_ticks:
		push_error("raw food's clock is %d ticks, expected %d from spoilDays 2" % [int((sp as Dictionary).get("spoilTicks", -1)), want_ticks])
		return false

	# And the clock is read off the block for *any* base, not off a remembered pair of ids:
	# spawn_item used to name raw and cooked by hand, so a third perishable food spawned with no
	# clock and never went off. Two fabricated bases prove the reader is generic both ways.
	_inject_fixture(w)
	var perishable: int = SimItems.spawn_item(w, "item.gate.perishable", {"tier": "scavenged"})
	var keeps: int = SimItems.spawn_item(w, "item.gate.keeps", {"tier": "scavenged"})
	var psp: Variant = w.components.get_component(perishable, "spoilage")
	if not (psp is Dictionary) or int((psp as Dictionary).get("spoilTicks", -1)) != int(float(Clock.DAY_TICKS)):
		push_error("a fabricated food with spoilDays 1 outside the old id pair got clock %s" % str(psp))
		return false
	if w.components.has_component(keeps, "spoilage"):
		push_error("a fabricated food with spoilDays 0 was given a spoil clock")
		return false
	print("FOOD CONTENT OK %d foods read from content with the retired table's numbers; canned has no clock, raw has %d ticks; three non-foods and a missing base all refuse; a fabricated perishable outside the old id pair gets a clock and a fabricated keeper does not" % [
		RETIRED_FOOD_TABLE.size(), want_ticks,
	])
	return true


# docs/04: "raw and spoiled food fills the bar but damages mood and carries illness risk". The mood
# half shipped; the illness half did not, so raw food was a mood tax and nothing else and there was
# never a mechanical reason to cook anything you were not enjoying.
func _raw_and_spoiled_food_carry_illness_risk() -> bool:
	const MEALS: int = 400
	var rates: Dictionary = {}
	for case in [{"id": "item.food.raw", "spoil": false}, {"id": "item.food.cooked", "spoil": false}, {"id": "item.food.raw", "spoil": true}]:
		var c: Dictionary = case as Dictionary
		var key: String = String(c["id"]) + ("/spoiled" if bool(c["spoil"]) else "")
		var w: Variant = _world()
		var ill: Array = []
		w.events.subscribe({"type": "illness.contracted", "id": "gate.ill", "handler": func(_e: Dictionary) -> void:
			ill.append(1)
		})
		for _m in MEALS:
			var meal: int = SimItems.spawn_item(w, String(c["id"]), {"tier": "scavenged"})
			if not SimInventory.stow(w, w.player, meal):
				w.components.set_component(meal, "stored", {"container": w.player})
			if bool(c["spoil"]):
				var sp: Variant = w.components.get_component(meal, "spoilage")
				if sp is Dictionary:
					(sp as Dictionary)["spoiled"] = true
			# Room to eat: a full survivor is not refused, but keeping hunger low keeps this about
			# the food rather than about the need.
			SimNeeds.of(w, w.player)["hunger"] = 10.0
			SimNeeds.eat(w, w.player, meal)
			w.events.drain()
		rates[key] = float(ill.size()) / float(MEALS)

	var raw: float = float(rates["item.food.raw"])
	var cooked: float = float(rates["item.food.cooked"])
	var spoiled: float = float(rates["item.food.raw/spoiled"])
	if cooked != 0.0:
		push_error("cooked food made somebody ill at %.3f -- it declares illnessChance 0" % cooked)
		return false
	if raw <= 0.0:
		push_error("raw food never made anybody ill over %d meals" % MEALS)
		return false
	if spoiled <= raw:
		push_error("spoiled food (%.3f) is no worse than merely raw (%.3f)" % [spoiled, raw])
		return false

	# The bout itself: it costs mood and work while it runs, and it passes on its own. Both halves
	# matter -- an illness that never ended would be a death sentence dressed as a debuff.
	var w2: Variant = _world()
	var ent: int = int(w2.player)
	# The bout is measured on a survivor nothing else touches. This half used to ride on the
	# booted district's twenty shamblers happening not to reach the idle player inside 3,640
	# ticks; the day the boot colony started working by day (Guard as the night post, 2026-09-06)
	# the deterministic trajectory changed, a shambler reached the player at tick 39082, the
	# instinct defence swung, a grab followed, and the pain of the wound read as "work was still
	# 0.912 after recovery". `world.despawn`, so the components go with the bodies.
	for z in w2.components.query(["shambler"]):
		w2.despawn(int(z))
	var well_work: float = SimNeeds.work_mul(w2, ent)
	var before_mood: float = float(w2.modifiers.call("resolve", "mood", ent))
	SimNeeds._fall_ill(w2, ent)
	if not SimNeeds.is_ill(w2, ent):
		push_error("a survivor who just fell ill does not read as ill")
		return false
	if SimNeeds.work_mul(w2, ent) >= well_work:
		push_error("illness did not slow work: %.3f against %.3f" % [SimNeeds.work_mul(w2, ent), well_work])
		return false
	if float(w2.modifiers.call("resolve", "mood", ent)) >= before_mood:
		push_error("illness cost no mood")
		return false

	var passed: Array = []
	w2.events.subscribe({"type": "illness.passed", "id": "gate.passed", "handler": func(_e: Dictionary) -> void:
		passed.append(1)
	})
	for _i in SimNeeds.ILLNESS_TICKS + 40:
		w2.step()
	if SimNeeds.is_ill(w2, ent):
		push_error("the bout never ended over %d ticks" % (SimNeeds.ILLNESS_TICKS + 40))
		return false
	if passed.is_empty():
		push_error("the bout ended silently -- nothing published illness.passed")
		return false
	if absf(SimNeeds.work_mul(w2, ent) - well_work) > 0.001:
		push_error("work was still %.3f after recovery, expected %.3f" % [SimNeeds.work_mul(w2, ent), well_work])
		return false

	print("ILLNESS OK raw %.3f, spoiled %.3f, cooked %.3f over %d meals each; the bout slows work and costs mood, then passes and restores both" % [
		raw, spoiled, cooked, MEALS,
	])
	return true


# --- grief (docs/04, docs/23's death-and-succession item) ---------------------------------------
#
# "The colony morale hit on a death." Two magnitudes, because docs/04 lists "grief" and
# "witnessing a death" separately, and witnessing only became answerable for a colonist when every
# survivor got eyes.

func _mara(w: Variant) -> int:
	for ent in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(ent), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(ent)
	return -1


# Kills through the ordinary damage path so health.gd publishes the real event, position and all.
func _kill(w: Variant, victim: int) -> void:
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": victim, "bodyPart": "head", "damage": 999.0})
	w.step()
	w.step()


func _a_death_costs_the_living() -> bool:
	var seen: Variant = _world()
	var mara: int = _mara(seen)
	if mara < 0:
		push_error("GRIEF: no Mara to lose")
		return false
	# Standing next to the player, in daylight, in plain view.
	var here: Dictionary = seen.components.get_component(seen.player, "position") as Dictionary
	seen.components.set_component(mara, "position", {"x": float(here["x"]) + 1.5, "y": float(here["y"])})
	seen.step()
	var before: float = float(seen.modifiers.call("resolve", "mood", seen.player))
	if SimNeeds.grief_of(seen, seen.player) != 0.0:
		push_error("GRIEF: the player was already grieving before anybody died")
		return false
	_kill(seen, mara)
	var witnessed: float = SimNeeds.grief_of(seen, seen.player)
	var after: float = float(seen.modifiers.call("resolve", "mood", seen.player))

	# The same death, out of sight. 48 m is the daylight eye; the far corner of a 64 m map is not
	# somewhere the player can see.
	var unseen: Variant = _world()
	var mara2: int = _mara(unseen)
	unseen.components.set_component(mara2, "position", {"x": 3.5, "y": 3.5})
	unseen.step()
	_kill(unseen, mara2)
	var heard: float = SimNeeds.grief_of(unseen, unseen.player)

	# A shambler dying is not a bereavement. Without this the whole thing would pass for a handler
	# that grieved every `entity.killed` in the district, which is most of them.
	var zeds: Variant = _world()
	var zed: int = -1
	for ent in zeds.components.query(["shambler", "body"]):
		zed = int(ent)
		break
	if zed < 0:
		push_error("GRIEF: no shambler in the district to not mourn")
		return false
	_kill(zeds, zed)
	if SimNeeds.grief_of(zeds, zeds.player) != 0.0:
		push_error("GRIEF: the colony mourned a shambler")
		return false

	if witnessed <= 0.0 or heard <= 0.0:
		push_error("GRIEF: a death cost nothing (witnessed %.2f, heard %.2f)" % [witnessed, heard])
		return false
	if witnessed <= heard:
		push_error("GRIEF: watching it happen is no worse than hearing about it (%.2f vs %.2f)" % [witnessed, heard])
		return false
	if after >= before:
		push_error("GRIEF: mood did not fall (%.2f -> %.2f)" % [before, after])
		return false

	# A put-down costs more than the same death otherwise -- docs/06's response #5 having a price.
	var ours: Variant = _world()
	var mara3: int = _mara(ours)
	ours.components.set_component(mara3, "position", {"x": 3.5, "y": 3.5})
	ours.step()
	ours.events.publish({"type": "survivor.putDown", "entity": mara3})
	ours.step()
	_kill(ours, mara3)
	var by_us: float = SimNeeds.grief_of(ours, ours.player)
	if by_us <= heard:
		push_error("GRIEF: doing it ourselves cost no more than it happening (%.2f vs %.2f)" % [by_us, heard])
		return false

	# The cap. The preload stands in for the deaths that came before this one; what is under test
	# is that the clamp holds when the next one lands.
	var many: Variant = _world()
	var mara4: int = _mara(many)
	var n: Dictionary = SimNeeds.of(many, many.player)
	n["grief"] = SimNeeds.GRIEF_CAP - 1.0
	many.components.set_component(mara4, "position", {"x": float(here["x"]) + 1.5, "y": float(here["y"])})
	many.step()
	_kill(many, mara4)
	var capped: float = SimNeeds.grief_of(many, many.player)
	if capped > SimNeeds.GRIEF_CAP + 0.001:
		push_error("GRIEF: grief ran past the cap (%.2f > %.2f)" % [capped, SimNeeds.GRIEF_CAP])
		return false
	if capped <= SimNeeds.GRIEF_CAP - 1.0:
		push_error("GRIEF: the capped case did not accumulate at all (%.2f)" % capped)
		return false

	var clause: String = SimNeeds.hud_clause(seen, seen.player)
	if not clause.contains("shaken"):
		push_error("GRIEF: the HUD says nothing about it ('%s')" % clause)
		return false
	print("GRIEF OK witnessed %.2f, heard %.2f, put down %.2f, capped %.2f, mood %.1f -> %.1f, hud '%s'" % [witnessed, heard, by_us, capped, before, after, clause])
	return true


func _grief_is_charged_once_and_drains_away() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var here: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	w.components.set_component(mara, "position", {"x": float(here["x"]) + 1.5, "y": float(here["y"])})
	w.step()
	_kill(w, mara)
	var once: float = SimNeeds.grief_of(w, w.player)

	# CLAUDE.md: `entity.killed` fires more than once for the same individual -- health.gd on a
	# destroyed head, infection.gd on a put-down and again on turning. Republishing it is exactly
	# what the sim does, and charging the colony twice for one funeral is the bug this asserts
	# against.
	for _i in 2:
		w.events.publish({"type": "entity.killed", "entity": mara, "x": float(here["x"]) + 1.5, "y": float(here["y"])})
		w.step()
	var twice: float = SimNeeds.grief_of(w, w.player)
	if twice > once + 0.001:
		push_error("ONCE: three killed events charged more than one death (%.2f -> %.2f)" % [once, twice])
		return false

	# And it drains. Long enough to be unambiguous, short enough that the gate stays a gate: the
	# decay is per mood tick, so this is the arithmetic rather than a wait for the full thirteen
	# in-game hours a full load takes to clear.
	var start: float = SimNeeds.grief_of(w, w.player)
	for _i in 400:
		w.step()
	var later: float = SimNeeds.grief_of(w, w.player)
	if later >= start:
		push_error("DECAY: grief did not drain (%.4f -> %.4f)" % [start, later])
		return false
	var expected: float = start - SimNeeds.GRIEF_DECAY * 20.0
	if absf(later - expected) > 0.01:
		push_error("DECAY: grief drained %.4f over 400 ticks, expected %.4f" % [start - later, start - expected])
		return false

	# All the way to nothing, and the modifier goes with it.
	var n: Dictionary = SimNeeds.of(w, w.player)
	n["grief"] = SimNeeds.GRIEF_DECAY * 2.0
	for _i in 80:
		w.step()
	if SimNeeds.grief_of(w, w.player) != 0.0:
		push_error("CLEARED: grief stopped short of zero (%.4f)" % SimNeeds.grief_of(w, w.player))
		return false
	print("ONCE OK one funeral charged once (%.2f), decays %.4f -> %.4f and clears" % [once, start, later])
	return true


# --- the bathroom need (docs/04) ---------------------------------------------------------------
#
# docs/04's cut list said latrines were scenery and nobody tracked a bladder. The owner reversed
# that. Three lanes: the pool and the verb, the consequence of having nowhere to go, and the one
# that keeps it from being a mechanism only the player can reach.

# The colony's latrine, or -1. Every lane below says so out loud rather than passing quietly when
# the district it booted has nowhere to go -- an assertion with no data to judge is not a pass.
func _latrine(w: Variant) -> int:
	var found: Array = w.components.query(["latrine", "position"])
	return int(found[0]) if not found.is_empty() else -1


# Stand somebody on a tile, and clear anything loose within reach of it: `use.context` picks up a
# ground item before it does anything else, so a stray tin would eat the keypress.
func _stand_at(w: Variant, ent: int, at: Dictionary) -> void:
	w.components.set_component(ent, "position", {"x": float(at["x"]), "y": float(at["y"])})
	for g in SimInventory.ground_items(w):
		var gp: Variant = w.components.get_component(g, "position")
		if not gp is Dictionary:
			continue
		var dx: float = float((gp as Dictionary)["x"]) - float(at["x"])
		var dy: float = float((gp as Dictionary)["y"]) - float(at["y"])
		if dx * dx + dy * dy <= 4.0:
			w.components.remove(g, "position")


func _the_bathroom_need_drains_and_is_answered_at_a_latrine() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)

	# Drains on a clock of its own, at the rate the constant declares.
	var n: Dictionary = SimNeeds.of(w, ent)
	n["relief"] = 100.0
	for _i in 2000:
		w.step()
	n = SimNeeds.of(w, ent)
	var fell: float = 100.0 - float(n["relief"])
	var want: float = SimNeeds.drain_relief() * 2000.0
	if absf(fell - want) > 0.05:
		push_error("relief fell %.4f over 2000 ticks, expected %.4f" % [fell, want])
		return false
	# Faster than hunger and slower than nothing: the pressure this need creates is that it comes
	# back sooner than the others, and a rate that matched hunger's would make it a duplicate.
	if want <= SimNeeds.drain_hunger() * 2000.0:
		push_error("relief drains no faster than hunger, so it is hunger with a different name")
		return false

	# Intake feeds it -- what goes in comes out, on a named amount rather than a fraction of what
	# the food restores.
	n["relief"] = 100.0
	var meal: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	SimInventory.stow(w, ent, meal)
	n["hunger"] = 10.0
	SimNeeds.eat(w, ent, meal)
	var after_meal: float = float(SimNeeds.of(w, ent)["relief"])
	if absf(100.0 - after_meal - SimNeeds.RELIEF_PER_MEAL) > 0.001:
		push_error("a meal moved the clock %.2f, expected %.2f" % [100.0 - after_meal, SimNeeds.RELIEF_PER_MEAL])
		return false
	var bottle: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	SimInventory.stow(w, ent, bottle)
	SimNeeds.of(w, ent)["thirst"] = 10.0
	SimNeeds.drink(w, ent)
	var after_drink: float = float(SimNeeds.of(w, ent)["relief"])
	if absf(after_meal - after_drink - SimNeeds.RELIEF_PER_DRINK) > 0.001:
		push_error("a drink moved the clock %.2f, expected %.2f" % [after_meal - after_drink, SimNeeds.RELIEF_PER_DRINK])
		return false

	# The verb, through the player's own key rather than through the leaf it calls: `use.context`
	# is what E does, and a lane that called `relieve_at` directly would pass for a latrine the
	# player can never actually use.
	var latrine: int = _latrine(w)
	if latrine < 0:
		push_error("the booted district sited no latrine, so every assertion below has nothing to judge")
		return false
	var lp: Dictionary = w.components.get_component(latrine, "position") as Dictionary

	# Refuses at a distance. Standing across the colony from the only latrine, the verb does
	# nothing at all -- there is no relieving yourself from over there.
	SimNeeds.of(w, ent)["relief"] = 30.0
	w.components.set_component(ent, "position", {"x": float(lp["x"]) + 12.0, "y": float(lp["y"]) + 12.0})
	if SimNeeds.relieve(w, ent):
		push_error("relief was granted 17 m from the only latrine")
		return false
	if absf(float(SimNeeds.of(w, ent)["relief"]) - 30.0) > 0.001:
		push_error("a refused relief moved the pool anyway")
		return false

	# And in reach, it works.
	_stand_at(w, ent, lp)
	var relieved: Array = []
	w.events.subscribe({"type": "need.relieved", "id": "gate.relieved", "handler": func(e: Dictionary) -> void:
		relieved.append(int(e.get("entity", -1)))
	})
	w.commands.push({"type": "use.context"})
	w.step()
	if float(SimNeeds.of(w, ent)["relief"]) < 99.0:
		push_error("E at the latrine left the pool at %.2f" % float(SimNeeds.of(w, ent)["relief"]))
		return false
	if relieved.is_empty():
		push_error("the pool refilled and nothing published need.relieved")
		return false

	# And a colony with no latrine refuses the same verb standing in the same place -- so this is
	# about the station, not about the position.
	var bare: Variant = _world()
	for e in bare.components.query(["latrine"]):
		bare.components.remove(int(e), "latrine")
	SimNeeds.of(bare, bare.player)["relief"] = 30.0
	bare.components.set_component(bare.player, "position", {"x": float(lp["x"]), "y": float(lp["y"])})
	if SimNeeds.relieve(bare, bare.player):
		push_error("a colony with no latrine relieved somebody anyway")
		return false

	# The prose, at the band and not before. Every other need pinned at fine, so the line under
	# test is the only one that can be picked.
	var m: Dictionary = SimNeeds.of(w, ent)
	m["hunger"] = 100.0
	m["thirst"] = 100.0
	m["rest"] = 100.0
	m["temperature"] = "comfortable"
	m["hygiene"] = "clean"
	m["soiled"] = 0.0
	w.modifiers.call("remove_by_source", SimNeeds.SOIL_SOURCE, ent)
	m["relief"] = 90.0
	if SimNeeds.hud_clause(w, ent, false) != "":
		push_error("a survivor at 90 relief is already being told to go: '%s'" % SimNeeds.hud_clause(w, ent, false))
		return false
	m["relief"] = 50.0
	if SimNeeds.hud_clause(w, ent, false) != "You need to go.":
		push_error("relief 50 said '%s'" % SimNeeds.hud_clause(w, ent, false))
		return false
	m["relief"] = 20.0
	if SimNeeds.hud_clause(w, ent, false) != "You badly need to go.":
		push_error("relief 20 said '%s'" % SimNeeds.hud_clause(w, ent, false))
		return false
	# No digits, ever -- godot:check:hud reads the HUD, this reads the sentence.
	for line in ["You need to go.", "You badly need to go."]:
		for c in line:
			if String(c).is_valid_int():
				push_error("the relief clause carries a digit: '%s'" % line)
				return false

	print("RELIEF OK drains %.4f per 2000 ticks (hunger %.4f), a meal costs %.0f and a drink %.0f, E at the latrine refills it and 17 m away does not, no latrine refuses; prose at 80 and 30, silent at 90" % [
		fell, SimNeeds.drain_hunger() * 2000.0, SimNeeds.RELIEF_PER_MEAL, SimNeeds.RELIEF_PER_DRINK,
	])
	return true


# Nowhere to go. The consequence is a hygiene band and shame -- never damage.
func _nowhere_to_go_costs_hygiene_and_pride() -> bool:
	# True positive: a survivor with an empty pool and no latrine has an accident.
	var w: Variant = _world()
	var ent: int = int(w.player)
	for e in w.components.query(["latrine"]):
		w.components.remove(int(e), "latrine")
	var n: Dictionary = SimNeeds.of(w, ent)
	n["hygiene"] = "clean"
	n["relief"] = SimNeeds.drain_relief() * 3.0
	var before_mood: float = float(w.modifiers.call("resolve", "mood", ent))
	var accidents: Array = []
	w.events.subscribe({"type": "need.soiled", "id": "gate.soiled", "handler": func(e: Dictionary) -> void:
		accidents.append(int(e.get("entity", -1)))
	})
	for _i in 10:
		w.step()
	if accidents.is_empty():
		push_error("a survivor ran the pool dry with nowhere to go and nothing happened")
		return false
	var soiled: float = SimNeeds.soiled_of(w, ent)
	if soiled <= 0.0:
		push_error("the accident cost no pride")
		return false
	if String(SimNeeds.of(w, ent).get("hygiene", "")) != "a_little_dirty":
		push_error("the accident left hygiene at %s, expected one band worse than clean" % str(SimNeeds.of(w, ent).get("hygiene")))
		return false
	if float(w.modifiers.call("resolve", "mood", ent)) >= before_mood:
		push_error("the accident cost no mood (%.2f -> %.2f)" % [before_mood, float(w.modifiers.call("resolve", "mood", ent))])
		return false
	# Never damage. docs/04 has no bodily-harm clause for this, and the easiest wrong version of
	# this feature is the one that starts injuring people.
	var body: Variant = w.components.get_component(ent, "body")
	if body is Dictionary:
		for part in (body as Dictionary).keys():
			var maxv: Variant = null
			if (body as Dictionary)[part] is Dictionary:
				maxv = ((body as Dictionary)[part] as Dictionary).get("max")
			if maxv != null and float(((body as Dictionary)[part] as Dictionary).get("current", 0.0)) < float(maxv):
				push_error("the accident injured %s -- this need must never do damage" % str(part))
				return false
	# The pool resets: the body has been relieved, whatever the dignity of it. Compared loosely
	# because the clock keeps running -- the ticks between the accident and this line drain it
	# again, which is the correct behaviour and not something to null out with a fudge inside the
	# sim.
	if float(SimNeeds.of(w, ent)["relief"]) < 99.0:
		push_error("after the accident the pool sat at %.2f" % float(SimNeeds.of(w, ent)["relief"]))
		return false
	var clause: String = SimNeeds.hud_clause(w, ent, false)
	if not clause.contains("humiliated"):
		push_error("the HUD said nothing about it: '%s'" % clause)
		return false

	# It drains away, and it is capped -- the argument rule, because an unbounded shame source
	# would walk a survivor out of the colony over a bad week.
	var loaded: Dictionary = SimNeeds.of(w, ent)
	loaded["soiled"] = SimNeeds.SOIL_CAP - 1.0
	loaded["relief"] = SimNeeds.drain_relief() * 2.0
	for _i in 10:
		w.step()
	if SimNeeds.soiled_of(w, ent) > SimNeeds.SOIL_CAP + 0.001:
		push_error("shame ran past the cap (%.2f)" % SimNeeds.soiled_of(w, ent))
		return false
	var start: float = SimNeeds.soiled_of(w, ent)
	SimNeeds.of(w, ent)["relief"] = 100.0
	for _i in 400:
		w.step()
		SimNeeds.of(w, ent)["relief"] = 100.0
	var ended: float = SimNeeds.soiled_of(w, ent)
	if ended >= start:
		push_error("shame did not drain over 400 quiet ticks (%.3f -> %.3f)" % [start, ended])
		return false

	# True negative: the identical survivor, on the identical clock, relieved in time. Same world
	# seed, same window, same pool -- the only difference is that they went.
	var kept: Variant = _world()
	var ent2: int = int(kept.player)
	var latrine: int = _latrine(kept)
	if latrine < 0:
		push_error("no latrine to be in time for")
		return false
	var quiet: Array = []
	kept.events.subscribe({"type": "need.soiled", "id": "gate.quiet", "handler": func(_e: Dictionary) -> void:
		quiet.append(1)
	})
	var lp: Dictionary = kept.components.get_component(latrine, "position") as Dictionary
	_stand_at(kept, ent2, lp)
	SimNeeds.of(kept, ent2)["relief"] = SimNeeds.drain_relief() * 3.0
	kept.commands.push({"type": "use.context"})
	for _i in 10:
		kept.step()
	if not quiet.is_empty():
		push_error("a survivor who went to the latrine soiled themselves anyway")
		return false
	if SimNeeds.soiled_of(kept, ent2) != 0.0:
		push_error("a survivor who went in time carries shame")
		return false

	print("ACCIDENT OK an empty pool with nowhere to go costs a hygiene band and %.1f of pride, no damage, mood %.1f -> %.1f, hud '%s'; capped at %.1f and drains %.3f -> %.3f; the same survivor relieved in time has none" % [
		soiled, before_mood, float(w.modifiers.call("resolve", "mood", ent)), clause, SimNeeds.SOIL_CAP, start, ended,
	])
	return true


# The dead-socket lane. A need only the player can answer is a mechanism nine colonists out of ten
# never reach -- this milestone has already paid for that pattern nine times. So: no commands, no
# hands on the NPC, and the assertion is that the colony's own AI walks somebody to the latrine.
#
# The walk is what this lane measures, so the grab loop is pinned off for it: with GRABS_ENABLED
# shipping true (docs/23's flag record), a shambler took hold of Mara mid-walk on this very seed
# -- measured with a driver, grabbed from tick ~1200 of the 4000 -- and a lane about the seek
# ladder was timing a struggle instead. Restore-to-previous, because the flag is a static shared
# by every world this gate process boots; the grab loop has its own gate (check_m2_contact.gd).
func _an_npc_takes_itself_to_the_latrine() -> bool:
	var flag_was: bool = SimShambler.GRABS_ENABLED
	SimShambler.GRABS_ENABLED = false
	var ok: bool = _npc_latrine_walk()
	SimShambler.GRABS_ENABLED = flag_was
	return ok


func _npc_latrine_walk() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	if mara < 0:
		push_error("no NPC in the colony to send")
		return false
	var latrine: int = _latrine(w)
	if latrine < 0:
		push_error("the booted district sited no latrine for an NPC to find")
		return false
	# Soft pressure on relief and nothing else pressing, so what is measured is this need winning
	# the seek ladder rather than an NPC wandering into a latrine on other business.
	var n: Dictionary = SimNeeds.of(w, mara)
	n["relief"] = 20.0
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	if SimNeeds.seek_kind(w, mara) != "relief":
		push_error("an NPC at 20 relief seeks '%s' instead" % SimNeeds.seek_kind(w, mara))
		return false
	var went: Array = []
	w.events.subscribe({"type": "need.relieved", "id": "gate.npc", "handler": func(e: Dictionary) -> void:
		went.append(int(e.get("entity", -1)))
	})
	var ticks: int = 0
	for _i in 4000:
		ticks += 1
		w.step()
		if went.has(mara):
			break
	if not went.has(mara):
		push_error("an NPC needing to go never reached the latrine in 4000 ticks")
		return false
	if float(SimNeeds.of(w, mara)["relief"]) < 99.0:
		push_error("the NPC relieved itself and the pool reads %.2f" % float(SimNeeds.of(w, mara)["relief"]))
		return false

	# True negative: the same NPC, the same pressure, in a colony with no latrine. Nobody publishes
	# anything, so the lane above is measuring the walk rather than the timer.
	var bare: Variant = _world()
	var mara2: int = _mara(bare)
	for e in bare.components.query(["latrine"]):
		bare.components.remove(int(e), "latrine")
	var m: Dictionary = SimNeeds.of(bare, mara2)
	m["relief"] = 20.0
	m["hunger"] = 100.0
	m["thirst"] = 100.0
	m["rest"] = 100.0
	var nothing: Array = []
	bare.events.subscribe({"type": "need.relieved", "id": "gate.npc.bare", "handler": func(_e: Dictionary) -> void:
		nothing.append(1)
	})
	for _i in ticks:
		bare.step()
	if not nothing.is_empty():
		push_error("an NPC relieved itself in a colony with no latrine")
		return false

	print("NPC RELIEF OK an NPC at 20 relief walked itself to the latrine in %d ticks with no player input; the same NPC with no latrine to walk to relieved nothing" % ticks)
	return true


# --- the three needs defects the review sweep found (docs/23) -----------------------------------

# Eat one, of a named base, from the survivor's own hands. Mirrors the illness lane's setup: stow
# it, spoil it if asked, and leave room in the pool so the meal is not refused for a full stomach.
func _eat_one(w: Variant, ent: int, base_id: String, spoil: bool) -> bool:
	var meal: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged"})
	if not SimInventory.stow(w, ent, meal):
		w.components.set_component(meal, "stored", {"container": ent})
	if spoil:
		var sp: Variant = w.components.get_component(meal, "spoilage")
		if sp is Dictionary:
			(sp as Dictionary)["spoiled"] = true
		else:
			w.components.set_component(meal, "spoilage", {"bornTick": 0, "spoilTicks": 1, "spoiled": true})
	SimNeeds.of(w, ent)["hunger"] = 10.0
	return SimNeeds.eat(w, ent, meal)


# Mood with every *need* source zeroed out, so what is left is the meal and nothing else. Eating
# moves hunger and relief, and both of those carry mood of their own through `_apply_muls`; without
# this the measurement below would be reading the pools rather than the plate.
func _mood_without_the_pools(w: Variant, ent: int) -> float:
	var n: Dictionary = SimNeeds.of(w, ent)
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	n["relief"] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	SimNeeds._apply_muls(w, ent, n)
	return float(w.modifiers.call("resolve", "mood", ent))


# `SimNeeds.eat` added a mood modifier with the fixed source `need.food` and nothing ever removed
# one, while every other mood source in that file -- shame, grief, arguments, illness -- pairs its
# `add` with a `remove_by_source`. Thirty meals over a ten-day campaign were thirty entries, all
# summing and none expiring.
func _a_meals_mood_is_bounded_and_wears_off() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var spec_v: Variant = SimNeeds.food_spec(w, "item.food.cooked")
	if not (spec_v is Dictionary):
		push_error("MEAL MOOD: cooked food declares no `food` block, so there is no meal mood to bound")
		return false
	var per_meal: float = float((spec_v as Dictionary).get("mood", 0.0))
	if per_meal <= 0.0:
		push_error("MEAL MOOD: cooked food is worth %.2f mood, so this lane has nothing to judge" % per_meal)
		return false

	# True positive, first half: one meal is worth exactly what content says it is. Without this the
	# whole lane would pass for a meal that did nothing at all.
	var baseline: float = _mood_without_the_pools(w, ent)
	if not _eat_one(w, ent, "item.food.cooked", false):
		push_error("MEAL MOOD: the survivor refused a cooked meal")
		return false
	var one: float = _mood_without_the_pools(w, ent) - baseline
	if absf(one - per_meal) > 0.001:
		push_error("MEAL MOOD: one cooked meal moved mood %.2f, content says %.2f" % [one, per_meal])
		return false

	# True positive, second half: thirty of them are worth one of them.
	for _i in 29:
		if not _eat_one(w, ent, "item.food.cooked", false):
			push_error("MEAL MOOD: a meal was refused partway through the run of thirty")
			return false
	var thirty: float = _mood_without_the_pools(w, ent) - baseline
	if absf(thirty - per_meal) > 0.001:
		push_error("MEAL MOOD: thirty meals carry %.2f of mood against one meal's %.2f -- they stack" % [thirty, per_meal])
		return false
	if int(SimNeeds.of(w, ent).get("mealMoodUntilTick", -1)) < 0:
		push_error("MEAL MOOD: thirty meals left no clock running, so the lift above is permanent")
		return false

	# And it expires. The clock is three in-game hours, which is 36000 ticks -- skipped rather than
	# stepped, because a gate that waits out the whole bout is a gate nobody runs.
	var faded: Array = []
	w.events.subscribe({"type": "mood.mealFaded", "id": "gate.meal", "handler": func(e: Dictionary) -> void:
		faded.append(int(e.get("entity", -1)))
	})
	w.tick = int(w.tick) + SimNeeds.MEAL_MOOD_TICKS
	w.step()
	if not faded.has(ent):
		push_error("MEAL MOOD: the clock ran out and nothing published mood.mealFaded")
		return false
	var after: float = _mood_without_the_pools(w, ent) - baseline
	if absf(after) > 0.001:
		push_error("MEAL MOOD: %.2f of meal mood survived its own clock" % after)
		return false

	# The dead-socket half: something *reads* it. Mood is read through `mood_band`, which is what
	# every consequence in jobs.gd matches on, so a bad meal must be able to move the band -- and
	# the band must come back when the meal wears off. Spoiled *cooked* food, deliberately: it
	# declares illnessChance 0, so this measures the meal rather than a bout of food poisoning.
	var w2: Variant = _world()
	var ent2: int = int(w2.player)
	_mood_without_the_pools(w2, ent2)
	_set_mood(w2, ent2, SimNeeds.MOOD_LOW + 5.0)
	if SimNeeds.mood_band(w2, ent2) != "content":
		push_error("MEAL MOOD: the survivor was already past `content` before the bad meal")
		return false
	if not _eat_one(w2, ent2, "item.food.cooked", true):
		push_error("MEAL MOOD: the survivor refused a spoiled meal")
		return false
	if SimNeeds.is_ill(w2, ent2):
		push_error("MEAL MOOD: spoiled cooked food made somebody ill, so the band below is not the meal")
		return false
	var sour: float = _mood_without_the_pools(w2, ent2)
	if SimNeeds.mood_band(w2, ent2) != "low":
		push_error("MEAL MOOD: a %.0f-mood meal did not move the band off `content` (mood %.2f)" % [SimNeeds.SPOILED_MOOD, sour])
		return false
	w2.tick = int(w2.tick) + SimNeeds.MEAL_MOOD_TICKS
	w2.step()
	_mood_without_the_pools(w2, ent2)
	if SimNeeds.mood_band(w2, ent2) != "content":
		push_error("MEAL MOOD: the band never came back after the bad meal wore off")
		return false

	print("MEAL MOOD OK one meal %.1f, thirty meals %.1f, gone after %d ticks; a spoiled one drops the band to `low` and the band returns when it fades" % [
		one, thirty, SimNeeds.MEAL_MOOD_TICKS,
	])
	return true


# `SimRecruits._make_corpse` stripped the `sleeping` component directly instead of going through
# `SimNeeds._wake`, which is the only thing that clears the bed's `occupiedBy` -- so a survivor who
# died in bed held it for the rest of the run and `nearest_bed`'s free-only scan, which is what
# jobs.gd's Rest asks, never offered it to anybody again.
func _a_survivor_who_dies_in_bed_gives_the_bed_back() -> bool:
	for case in [{"how": "corpse"}, {"how": "turned"}]:
		var c: Dictionary = case as Dictionary
		var w: Variant = _world()
		var sleeper: int = _mara(w)
		if sleeper < 0:
			push_error("BED: no NPC in the colony to put to bed")
			return false
		var beds: Array[int] = w.components.query(["bed", "position"])
		if beds.is_empty():
			push_error("BED: the booted district sited no bed, so this lane has nothing to judge")
			return false
		var bed: int = int(beds[0])
		var bp: Dictionary = w.components.get_component(bed, "position") as Dictionary
		SimNeeds.start_sleep(w, sleeper, bed)
		var b: Dictionary = w.components.get_component(bed, "bed") as Dictionary
		if int(b.get("occupiedBy", -1)) != sleeper:
			push_error("BED: going to bed did not claim it (%s)" % str(b))
			return false
		# The true negative, and the thing that makes the assertion below mean something: while it is
		# claimed, the free-only scan refuses this bed.
		if SimNeeds.nearest_bed(w, float(bp["x"]), float(bp["y"]), true) == bed:
			push_error("BED: an occupied bed was offered to the next sleeper anyway")
			return false

		# Killed where they lie, through the funnel every death in the sim goes through --
		# `entity.killed` then `finish_death`, which is exactly what starvation does in `_tick_pools`.
		# No `attack.connected`, deliberately: that publishes into `need.wake-hit`, which would wake
		# them and free the bed for reasons that have nothing to do with the fix.
		if String(c["how"]) == "corpse":
			w.events.publish({"type": "entity.killed", "entity": sleeper, "need": "hunger"})
			SimHealth.finish_death(w, sleeper)
			if not w.components.has_component(sleeper, "corpse"):
				push_error("BED: the death left no corpse to check")
				return false
			if w.components.has_component(sleeper, "sleeping"):
				push_error("BED: the corpse is still asleep")
				return false
		else:
			# The other door into the same hole: a survivor who turns in their sleep is despawned,
			# and a despawn takes the sleeper's components with it while leaving the *bed* pointing
			# at a dead id.
			SimRecruits._turn_with_kit(w, sleeper)

		if int(b.get("occupiedBy", -1)) != -1:
			push_error("BED: the dead (%s) still hold the bed, occupiedBy %d" % [String(c["how"]), int(b.get("occupiedBy", -1))])
			return false
		# And the read: the scan jobs.gd's Rest uses offers it again.
		if SimNeeds.nearest_bed(w, float(bp["x"]), float(bp["y"]), true) != bed:
			push_error("BED: the bed is free and the free-only scan still refuses it (%s)" % String(c["how"]))
			return false

	print("BED OK a survivor who dies in bed -- as a corpse or by turning in their sleep -- gives it back, and the free-only scan offers it again")
	return true


# A tile outdoors, and a tile indoors, on the booted district's own map. Returned as (-1, -1) when
# the map has none, so the lane says so rather than measuring a position it invented.
func _tile_where(w: Variant, indoors: bool) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_indoors(w.tilemap, x, y) == indoors:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# `_tick_temperature` could write `comfortable`, `very_cold` and `a_little_cold` and nothing else,
# so `extremely_cold` -- the only band `band_pressure` calls "hard", with its own HUD line and its
# own branch in jobs.gd -- was unreachable and every one of those branches was dead code.
func _the_deep_cold_is_reachable_and_interrupts_work() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var out: Vector2i = _tile_where(w, false)
	var inside: Vector2i = _tile_where(w, true)
	if out.x < 0 or inside.x < 0:
		push_error("COLD: the booted district has no outdoor tile or no indoor one, so this lane has nothing to judge")
		return false
	# Every fire out, so the only warmth in question is the roof. Any garment would shift the band
	# toward comfortable -- that is clothing working, and `godot:m2:warmth` owns it -- but it is
	# not what is under test here, so the body is stripped of anything declaring a `warmth` block
	# and the assertion is that it scores nothing rather than that one base id is absent.
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = SimItems.item_base_of(w, item)
		if base is Dictionary and (base as Dictionary).get("warmth") is Dictionary:
			SimInventory.unequip_item(w, item)
	if SimNeeds.warmth_points(w, ent) != 0:
		push_error("COLD: the survivor is still dressed for the weather (%d points), so the band under test is shifted" % SimNeeds.warmth_points(w, ent))
		return false

	# Deep night, outdoors, no fire.
	w.tick = Clock.tick_on_day(2, 0.8)
	w.components.set_component(ent, "position", {"x": float(out.x) + 0.5, "y": float(out.y) + 0.5})
	w.step()
	var n: Dictionary = SimNeeds.of(w, ent)
	if String(n.get("temperature", "")) != "very_cold":
		push_error("COLD: a night outdoors with no fire read %s" % str(n.get("temperature")))
		return false
	if int(n.get("coldSinceTick", -1)) < 0:
		push_error("COLD: nothing started the exposure clock")
		return false

	# The dose, not the switch: it is not deep yet, and it becomes deep when the clock runs out.
	var started: int = int(n.get("coldSinceTick", -1))
	w.tick = started + SimNeeds.EXPOSURE_TICKS - 2
	w.components.set_component(ent, "position", {"x": float(out.x) + 0.5, "y": float(out.y) + 0.5})
	w.step()
	if String(SimNeeds.of(w, ent).get("temperature", "")) != "very_cold":
		push_error("COLD: the band deepened before the exposure clock ran out")
		return false
	w.tick = started + SimNeeds.EXPOSURE_TICKS
	w.components.set_component(ent, "position", {"x": float(out.x) + 0.5, "y": float(out.y) + 0.5})
	w.step()
	if String(SimNeeds.of(w, ent).get("temperature", "")) != "extremely_cold":
		push_error("COLD: %d ticks outdoors at night still read %s" % [SimNeeds.EXPOSURE_TICKS, str(SimNeeds.of(w, ent).get("temperature"))])
		return false
	if SimNeeds.band_pressure("temperature", "extremely_cold") != "hard":
		push_error("COLD: the deep band is not the hard one")
		return false
	# The prose, with every other need pinned fine so the line under test is the one that is picked.
	var m: Dictionary = SimNeeds.of(w, ent)
	m["hunger"] = 100.0
	m["thirst"] = 100.0
	m["rest"] = 100.0
	m["relief"] = 100.0
	m["hygiene"] = "clean"
	m["soiled"] = 0.0
	m["grief"] = 0.0
	var clause: String = SimNeeds.hud_clause(w, ent, false)
	if clause != "You're freezing.":
		push_error("COLD: the deep band says '%s', which is the `very_cold` line or worse" % clause)
		return false
	for ch in clause:
		if String(ch).is_valid_int():
			push_error("COLD: the deep-cold clause carries a digit: '%s'" % clause)
			return false

	# True negative one: the same night, the same span, under a roof. Never deepens past a_little.
	var roofed: Variant = _world()
	var ent2: int = int(roofed.player)
	for fire2 in roofed.components.query(["campfire"]):
		SimNeeds.set_lit(roofed, int(fire2), false)
	roofed.tick = Clock.tick_on_day(2, 0.8)
	roofed.components.set_component(ent2, "position", {"x": float(inside.x) + 0.5, "y": float(inside.y) + 0.5})
	roofed.step()
	var indoor_band: String = String(SimNeeds.of(roofed, ent2).get("temperature", ""))
	roofed.tick = int(roofed.tick) + SimNeeds.EXPOSURE_TICKS * 2
	roofed.components.set_component(ent2, "position", {"x": float(inside.x) + 0.5, "y": float(inside.y) + 0.5})
	roofed.step()
	if String(SimNeeds.of(roofed, ent2).get("temperature", "")) == "extremely_cold":
		push_error("COLD: a survivor indoors all night froze anyway")
		return false
	if int(SimNeeds.of(roofed, ent2).get("coldSinceTick", -1)) >= 0:
		push_error("COLD: a survivor indoors is carrying an exposure clock")
		return false

	# True negative two: warmth clears the clock. Back outside after a step by the fire, the same
	# survivor starts again at `very_cold` rather than picking up where they left off.
	var thawed: Variant = _world()
	var ent3: int = int(thawed.player)
	for item3 in SimInventory.equipped_items(thawed, ent3):
		var base3: Variant = SimItems.item_base_of(thawed, item3)
		if base3 is Dictionary and (base3 as Dictionary).get("warmth") is Dictionary:
			SimInventory.unequip_item(thawed, item3)
	thawed.tick = Clock.tick_on_day(2, 0.8)
	thawed.components.set_component(ent3, "position", {"x": float(out.x) + 0.5, "y": float(out.y) + 0.5})
	thawed.step()
	var began: int = int(SimNeeds.of(thawed, ent3).get("coldSinceTick", -1))
	if began < 0:
		push_error("COLD: the exposure clock never started in the thaw lane")
		return false
	# Indoors for one tick, most of the way through the exposure window.
	thawed.tick = began + SimNeeds.EXPOSURE_TICKS - 4
	thawed.components.set_component(ent3, "position", {"x": float(inside.x) + 0.5, "y": float(inside.y) + 0.5})
	thawed.step()
	if int(SimNeeds.of(thawed, ent3).get("coldSinceTick", -1)) >= 0:
		push_error("COLD: stepping under a roof did not clear the exposure clock")
		return false
	thawed.tick = int(thawed.tick) + 1
	thawed.components.set_component(ent3, "position", {"x": float(out.x) + 0.5, "y": float(out.y) + 0.5})
	thawed.step()
	if String(SimNeeds.of(thawed, ent3).get("temperature", "")) != "very_cold":
		push_error("COLD: a survivor who warmed up came back out at %s" % str(SimNeeds.of(thawed, ent3).get("temperature")))
		return false

	# The dead-socket half: something reads the band. jobs.gd's `_tick_one` treats `extremely_cold`
	# as hard, which is what lets a need interrupt a job mid-action; `very_cold` waits for the job
	# to finish. Same NPC, same job, same pinned needs -- only the band differs.
	var kept: Dictionary = {}
	for band in ["very_cold", "extremely_cold"]:
		var w4: Variant = _world()
		var npc: int = _mara(w4)
		if npc < 0:
			push_error("COLD: no NPC to hold a job")
			return false
		var nn: Dictionary = SimNeeds.of(w4, npc)
		nn["hunger"] = 100.0
		nn["thirst"] = 100.0
		nn["rest"] = 100.0
		nn["relief"] = 100.0
		nn["hygiene"] = "clean"
		nn["temperature"] = String(band)
		if SimNeeds.seek_kind(w4, npc) != "temperature":
			push_error("COLD: an NPC at %s seeks '%s' instead of temperature" % [String(band), SimNeeds.seek_kind(w4, npc)])
			return false
		# `Patient` is a job with somewhere to be and nothing to do, so what happens to it is the
		# interrupt and not the work.
		w4.components.set_component(npc, "job", {"kind": "Patient", "ticksLeft": 100, "path": [], "pathGen": -1})
		SimJobs._tick_one(w4, npc)
		var job: Variant = w4.components.get_component(npc, "job")
		kept[String(band)] = job is Dictionary and String((job as Dictionary).get("kind", "")) == "Patient"
	if not bool(kept["very_cold"]):
		push_error("COLD: a `very_cold` NPC dropped its job mid-action, so the interrupt is not about the deep band")
		return false
	if bool(kept["extremely_cold"]):
		push_error("COLD: an `extremely_cold` NPC worked on regardless -- nothing reads the hard band")
		return false

	print("COLD OK a night outdoors reads very_cold, deepens to extremely_cold after %d ticks of exposure and no sooner, says '%s'; a roof and a thaw both clear the clock; the deep band interrupts a job mid-action and very_cold does not" % [
		SimNeeds.EXPOSURE_TICKS, clause,
	])
	return true


# --- sleep quality (docs/04, docs/05) -----------------------------------------------------------
#
# docs/23's Medicine group: "Blocked on itself: docs/05 lists sleep among what pain degrades, and
# there is no sleep-quality value to degrade yet." `SimNeeds.sleep_quality` is that value now,
# derived every sleeping tick from the same discipline `SimWounds.pain_of` already keeps -- never
# stored as truth, so it cannot drift from the state it reads.

# One night's worth of ticks. Named once so a rebalance of the night length moves every lane here
# together rather than four copies of the same arithmetic quietly disagreeing.
func _night_ticks() -> int:
	return int(0.25 * float(Clock.DAY_TICKS))


func _first_bed(w: Variant) -> int:
	var beds: Array[int] = w.components.query(["bed", "position"])
	return int(beds[0]) if not beds.is_empty() else -1


# A full night, direct: `_refill_sleep` called once per tick rather than `world.step()`, the same
# way `_apply_muls` is called directly elsewhere in this file -- it isolates the mechanism under
# test from everything else a tick would otherwise touch (time of day, other survivors' AI, the
# attention field's own decay), which is what lets a "bed, comfortable, unwounded, quiet" scenario
# mean exactly that and nothing else.
func _sleep_a_night(w: Variant, ent: int, n: Dictionary) -> void:
	for _i in _night_ticks():
		SimNeeds._refill_sleep(w, ent, n)


# The calibration constraint docs/23 names: a good night is materially better than a bad one, a
# bad night is never a dead one, and the difference reads on the HUD and in tomorrow's work speed
# -- the dead-socket half, without which `sleep_quality` would be gated and correct and reach no
# survivor's morning.
func _a_good_nights_sleep_beats_a_bad_one_and_it_shows_the_next_morning() -> bool:
	# The good night: in bed, comfortable, unwounded, quiet. This is the calibration constraint
	# itself -- it must land on exactly today's 100/night, or an ordinary night just got worse.
	var wg: Variant = _world()
	var eg: int = int(wg.player)
	var bed: int = _first_bed(wg)
	if bed < 0:
		push_error("SLEEP: the booted district sited no bed, so this lane has nothing to judge")
		return false
	SimNeeds.start_sleep(wg, eg, bed)
	var ng: Dictionary = SimNeeds.of(wg, eg)
	ng["rest"] = 0.0
	ng["hunger"] = 100.0
	ng["thirst"] = 100.0
	ng["relief"] = 100.0
	ng["temperature"] = "comfortable"
	ng["hygiene"] = "clean"
	_sleep_a_night(wg, eg, ng)
	var good_gain: float = float(ng["rest"])
	if absf(good_gain - SimNeeds.SLEEP_FULL_NIGHT) > 0.5:
		push_error("SLEEP: a good night restored %.2f, not the calibrated %.1f -- an ordinary night moved" % [good_gain, SimNeeds.SLEEP_FULL_NIGHT])
		return false
	if String(ng.get("slept", "")) != "rested":
		push_error("SLEEP: a perfect night did not read as `rested` (%s)" % String(ng.get("slept", "")))
		return false

	# Two identical good nights restore the same amount -- there is no hidden roll in here.
	var wg2: Variant = _world()
	var eg2: int = int(wg2.player)
	SimNeeds.start_sleep(wg2, eg2, _first_bed(wg2))
	var ng2: Dictionary = SimNeeds.of(wg2, eg2)
	ng2["rest"] = 0.0
	ng2["hunger"] = 100.0
	ng2["thirst"] = 100.0
	ng2["relief"] = 100.0
	ng2["temperature"] = "comfortable"
	ng2["hygiene"] = "clean"
	_sleep_a_night(wg2, eg2, ng2)
	if absf(float(ng2["rest"]) - good_gain) > 0.001:
		push_error("SLEEP: two identical good nights restored %.4f and %.4f" % [good_gain, float(ng2["rest"])])
		return false

	# The bad night: rough (no bed), the hard cold band, and a noise source sitting right beside
	# the sleeper -- deliberately no wound, so the rest-pool comparison below is not entangled
	# with pain's own contribution to `work_mul`.
	var wb: Variant = _world()
	var eb: int = int(wb.player)
	SimNeeds.start_sleep(wb, eb, -1)
	var nb: Dictionary = SimNeeds.of(wb, eb)
	nb["rest"] = 0.0
	nb["hunger"] = 100.0
	nb["thirst"] = 100.0
	nb["relief"] = 100.0
	nb["temperature"] = "extremely_cold"
	nb["hygiene"] = "clean"
	if wb.field == null:
		push_error("SLEEP: the booted district has no attention field, so the quiet factor has nothing to judge")
		return false
	var pos: Dictionary = wb.components.get_component(eb, "position") as Dictionary
	wb.field.emit_noise(float(pos["x"]), float(pos["y"]), 150.0)
	_sleep_a_night(wb, eb, nb)
	var bad_gain: float = float(nb["rest"])
	if bad_gain <= 0.0:
		push_error("SLEEP: a bad night restored nothing -- a night is bad, never dead")
		return false
	if bad_gain >= good_gain:
		push_error("SLEEP: a bad night (%.2f) restored as much as a good one (%.2f)" % [bad_gain, good_gain])
		return false
	if absf(bad_gain - SimNeeds.SLEEP_FULL_NIGHT * SimNeeds.SLEEP_QUALITY_FLOOR) > 0.5:
		push_error("SLEEP: the worst night restored %.2f, not the floored %.2f" % [bad_gain, SimNeeds.SLEEP_FULL_NIGHT * SimNeeds.SLEEP_QUALITY_FLOOR])
		return false
	if String(nb.get("slept", "")) != "barely_slept":
		push_error("SLEEP: the worst night did not read as `barely_slept` (%s)" % String(nb.get("slept", "")))
		return false

	# work_mul first, on the rest pool exactly as the bad night left it (temperature cleared, so
	# the deep-cold band -- which also clamps work_mul -- cannot be doing this instead of rest).
	nb["temperature"] = "comfortable"
	var work_good: float = SimNeeds.work_mul(wg, eg)
	var work_bad: float = SimNeeds.work_mul(wb, eb)
	if work_bad >= work_good:
		push_error("SLEEP: the smaller rest pool after a bad night did not change work_mul (%.3f vs %.3f)" % [work_bad, work_good])
		return false

	# The HUD read, isolated from the rest pool's own "You're exhausted" line by handing rest back
	# a healthy number -- what is left standing is the sleep-quality word alone, `barely_slept`
	# from a night that stayed bad even though the sleeper is not short on hours. Without this the
	# assertion below could pass on the strength of a line this slice did not add.
	nb["rest"] = 90.0
	var clause_good: String = SimNeeds.hud_clause(wg, eg)
	var clause_bad: String = SimNeeds.hud_clause(wb, eb)
	if clause_bad == clause_good:
		push_error("SLEEP: hud_clause said the same thing after a good night and a barely-slept one ('%s')" % clause_bad)
		return false
	if not clause_bad.contains("reeling"):
		push_error("SLEEP: with rest healthy again, hud_clause read '%s' instead of the sleep-quality line" % clause_bad)
		return false
	var digit := RegEx.new()
	digit.compile("[0-9]")
	if digit.search(clause_bad) != null or digit.search(clause_good) != null:
		push_error("SLEEP: a sleep-quality HUD line carried a digit -- good '%s' bad '%s'" % [clause_good, clause_bad])
		return false

	print("SLEEP OK a good night restores %.1f (twice, identically), a rough/cold/loud one restores %.1f (floored, never zero); work_mul drops from %.3f to %.3f on the rest pool alone, and the HUD reads '%s' once rest is no longer also the story" % [
		good_gain, bad_gain, work_good, work_bad, clause_bad,
	])
	return true


# Each of docs/04's tractable factors moves the number alone -- the true positive for each, one at
# a time, a control that changes nothing, and a `world.field == null` world that still sleeps
# rather than crashing reaching for a field it does not have.
func _each_sleep_factor_moves_the_quality_alone() -> bool:
	var wc: Variant = _world()
	var ec: int = int(wc.player)
	var bed: int = _first_bed(wc)
	if bed < 0:
		push_error("SLEEP FACTORS: the booted district sited no bed, so this lane has nothing to judge")
		return false
	SimNeeds.start_sleep(wc, ec, bed)
	var nc: Dictionary = SimNeeds.of(wc, ec)
	nc["temperature"] = "comfortable"
	var baseline: float = SimNeeds.sleep_quality(wc, ec)
	if absf(baseline - 1.0) > 0.001:
		push_error("SLEEP FACTORS: the baseline scenario is not a perfect night (%.4f)" % baseline)
		return false

	# The control: an identical second world, changing nothing, reduces nothing.
	var w0: Variant = _world()
	var e0: int = int(w0.player)
	SimNeeds.start_sleep(w0, e0, _first_bed(w0))
	var n0: Dictionary = SimNeeds.of(w0, e0)
	n0["temperature"] = "comfortable"
	var control: float = SimNeeds.sleep_quality(w0, e0)
	if absf(control - baseline) > 0.001:
		push_error("SLEEP FACTORS: an unchanged control scenario read %.4f against baseline %.4f" % [control, baseline])
		return false

	# bed -> rough.
	var w1: Variant = _world()
	var e1: int = int(w1.player)
	SimNeeds.start_sleep(w1, e1, -1)
	var n1: Dictionary = SimNeeds.of(w1, e1)
	n1["temperature"] = "comfortable"
	var q_rough: float = SimNeeds.sleep_quality(w1, e1)
	if q_rough >= baseline:
		push_error("SLEEP FACTORS: a rough bed alone did not reduce quality (%.4f vs %.4f)" % [q_rough, baseline])
		return false

	# comfortable -> very_cold.
	var w2: Variant = _world()
	var e2: int = int(w2.player)
	SimNeeds.start_sleep(w2, e2, _first_bed(w2))
	var n2: Dictionary = SimNeeds.of(w2, e2)
	n2["temperature"] = "very_cold"
	var q_cold: float = SimNeeds.sleep_quality(w2, e2)
	if q_cold >= baseline:
		push_error("SLEEP FACTORS: `very_cold` alone did not reduce quality (%.4f vs %.4f)" % [q_cold, baseline])
		return false

	# unwounded -> a deep wound.
	var w3: Variant = _world()
	var e3: int = int(w3.player)
	SimNeeds.start_sleep(w3, e3, _first_bed(w3))
	var n3: Dictionary = SimNeeds.of(w3, e3)
	n3["temperature"] = "comfortable"
	SimWounds.append_wound(w3, e3, "cut", "torso", -1, 40.0, "", SimWounds.Severity.DeepWound)
	var q_hurt: float = SimNeeds.sleep_quality(w3, e3)
	if q_hurt >= baseline:
		push_error("SLEEP FACTORS: a deep wound alone did not reduce quality (%.4f vs %.4f)" % [q_hurt, baseline])
		return false

	# quiet -> a noise source beside the sleeper.
	var w4: Variant = _world()
	var e4: int = int(w4.player)
	SimNeeds.start_sleep(w4, e4, _first_bed(w4))
	var n4: Dictionary = SimNeeds.of(w4, e4)
	n4["temperature"] = "comfortable"
	if w4.field == null:
		push_error("SLEEP FACTORS: the booted district has no attention field, so the quiet factor has nothing to judge")
		return false
	var p4: Dictionary = w4.components.get_component(e4, "position") as Dictionary
	w4.field.emit_noise(float(p4["x"]), float(p4["y"]), 150.0)
	var q_loud: float = SimNeeds.sleep_quality(w4, e4)
	if q_loud >= baseline:
		push_error("SLEEP FACTORS: noise beside the sleeper alone did not reduce quality (%.4f vs %.4f)" % [q_loud, baseline])
		return false

	# A world with no attention field at all still sleeps rather than crashing reaching for one --
	# the guard sim/attention_read.gd:69 already uses for the same field, on the same reasoning.
	var w5: Variant = _world()
	var e5: int = int(w5.player)
	SimNeeds.start_sleep(w5, e5, _first_bed(w5))
	var n5: Dictionary = SimNeeds.of(w5, e5)
	n5["temperature"] = "comfortable"
	w5.field = null
	var q_no_field: float = SimNeeds.sleep_quality(w5, e5)
	if absf(q_no_field - baseline) > 0.001:
		push_error("SLEEP FACTORS: a world with no attention field read %.4f against baseline %.4f" % [q_no_field, baseline])
		return false

	print("SLEEP FACTORS OK baseline %.4f; bed %.4f, cold %.4f, wound %.4f, noise %.4f each strictly worse; a control read the same and a fieldless world did not crash" % [
		baseline, q_rough, q_cold, q_hurt, q_loud,
	])
	return true


# docs/05: "Pain ... Degrades everything -- accuracy, work speed, mood, sleep quality. Painkillers
# suppress it without healing anything." `pain_of` already applies suppression, so this is the
# read that makes that sentence true for sleep specifically: a dose buys a night back.
func _pain_degrades_sleep_and_painkillers_buy_a_night() -> bool:
	var wc: Variant = _world()
	var ec: int = int(wc.player)
	SimNeeds.start_sleep(wc, ec, _first_bed(wc))
	var nc: Dictionary = SimNeeds.of(wc, ec)
	nc["temperature"] = "comfortable"
	var control: float = SimNeeds.sleep_quality(wc, ec)

	var wu: Variant = _world()
	var eu: int = int(wu.player)
	SimNeeds.start_sleep(wu, eu, _first_bed(wu))
	var nu: Dictionary = SimNeeds.of(wu, eu)
	nu["temperature"] = "comfortable"
	SimWounds.append_wound(wu, eu, "cut", "arm", -1, 3.0, "", SimWounds.Severity.Scratch)
	var undosed: float = SimNeeds.sleep_quality(wu, eu)
	if undosed >= control:
		push_error("PAIN SLEEP: an untreated wound did not cost any sleep quality (%.4f vs unwounded %.4f)" % [undosed, control])
		return false

	var wd: Variant = _world()
	var ed: int = int(wd.player)
	SimNeeds.start_sleep(wd, ed, _first_bed(wd))
	var nd: Dictionary = SimNeeds.of(wd, ed)
	nd["temperature"] = "comfortable"
	SimWounds.append_wound(wd, ed, "cut", "arm", -1, 3.0, "", SimWounds.Severity.Scratch)
	var pk: int = SimItems.spawn_item(wd, "item.painkillers.blister", {"tier": "scavenged"})
	if not SimInventory.stow(wd, ed, pk):
		wd.components.set_component(pk, "stored", {"container": ed})
	var dosed_res: Dictionary = SimWounds.take_painkillers(wd, ed)
	if not bool(dosed_res.get("ok", false)):
		push_error("PAIN SLEEP: the survivor refused their own painkillers (%s)" % String(dosed_res.get("reason", "")))
		return false
	var dosed: float = SimNeeds.sleep_quality(wd, ed)
	if dosed <= undosed:
		push_error("PAIN SLEEP: dosed (%.4f) did not sleep better than undosed (%.4f)" % [dosed, undosed])
		return false
	if absf(dosed - control) > 0.01:
		push_error("PAIN SLEEP: dosed quality %.4f did not reach the unwounded ceiling %.4f" % [dosed, control])
		return false

	print("PAIN SLEEP OK unwounded %.4f, undosed %.4f, dosed %.4f -- painkillers buy back the unwounded ceiling" % [
		control, undosed, dosed,
	])
	return true


# A bad night costs mood at `_wake`, the same shape `_apply_grief` uses, and stops costing it once
# decay has run -- so a run of rough nights is a drag, never a spiral no bandage or bed can answer.
func _a_rough_night_costs_mood_then_stops_costing_it() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var baseline_mood: float = float(w.modifiers.call("resolve", "mood", ent))

	# The true negative first: a good night's sleep charges nothing.
	SimNeeds.start_sleep(w, ent, _first_bed(w))
	var ngood: Dictionary = SimNeeds.of(w, ent)
	ngood["temperature"] = "comfortable"
	_sleep_a_night(w, ent, ngood)
	SimNeeds._wake(w, ent)
	if absf(float(w.modifiers.call("resolve", "mood", ent)) - baseline_mood) > 0.001:
		push_error("SLEEP MOOD: a perfect night charged mood anyway")
		return false

	# One rough night: mood drops, and `explain` names the source, so this is not a modifier
	# nobody can point at.
	SimNeeds.start_sleep(w, ent, -1)
	var n: Dictionary = SimNeeds.of(w, ent)
	n["temperature"] = "comfortable"
	_sleep_a_night(w, ent, n)
	SimNeeds._wake(w, ent)
	var after_one: float = float(w.modifiers.call("resolve", "mood", ent))
	if after_one >= baseline_mood:
		push_error("SLEEP MOOD: a rough night did not cost any mood (%.3f vs baseline %.3f)" % [after_one, baseline_mood])
		return false
	var ex: Dictionary = w.modifiers.call("explain", "mood", ent)
	var named: bool = false
	for c in ex.get("contributions", []) as Array:
		if String((c as Dictionary).get("source", "")) == SimNeeds.SLEEP_SOURCE:
			named = true
			break
	if not named:
		push_error("SLEEP MOOD: mood dropped after a rough night and `explain` names nothing at `mood.sleep`")
		return false

	# Two more rough nights: the accumulator caps, and it is still exactly one modifier -- not
	# three summed ones, which is the meltdown docs/04 already rules out for grief and arguments.
	for _i in 2:
		SimNeeds.start_sleep(w, ent, -1)
		var n2: Dictionary = SimNeeds.of(w, ent)
		n2["temperature"] = "comfortable"
		_sleep_a_night(w, ent, n2)
		SimNeeds._wake(w, ent)
	var capped: float = float(SimNeeds.of(w, ent).get("sleptMood", 0.0))
	if absf(capped - SimNeeds.SLEEP_MOOD_CAP) > 0.01:
		push_error("SLEEP MOOD: three rough nights carry %.2f, not the cap of %.2f" % [capped, SimNeeds.SLEEP_MOOD_CAP])
		return false
	var ex3: Dictionary = w.modifiers.call("explain", "mood", ent)
	var sleep_entries: int = 0
	for c3 in ex3.get("contributions", []) as Array:
		if String((c3 as Dictionary).get("source", "")) == SimNeeds.SLEEP_SOURCE:
			sleep_entries += 1
	if sleep_entries != 1:
		push_error("SLEEP MOOD: three rough nights left %d `mood.sleep` entries, not one" % sleep_entries)
		return false

	# And it stops costing it: decay ticks (the same `% 20` mood-tick cadence grief and arguments
	# drain on) bring the accumulator, and the mood it costs, back to nothing.
	var decay_ticks: int = int(ceil(SimNeeds.SLEEP_MOOD_CAP / SimNeeds.SLEEP_DECAY)) + 1
	for _j in decay_ticks:
		w.tick += 20
		SimNeeds._tick_slept_mood(w)
	var recovered: float = float(SimNeeds.of(w, ent).get("sleptMood", 0.0))
	if recovered > 0.001:
		push_error("SLEEP MOOD: %.4f of sleep-cost mood survived %d decay ticks" % [recovered, decay_ticks])
		return false
	if absf(float(w.modifiers.call("resolve", "mood", ent)) - baseline_mood) > 0.001:
		push_error("SLEEP MOOD: mood did not return to baseline after decay (%.3f vs %.3f)" % [float(w.modifiers.call("resolve", "mood", ent)), baseline_mood])
		return false

	print("SLEEP MOOD OK a good night charges nothing, one rough night costs %.2f (named `mood.sleep`), three cap at %.2f in one modifier, and decay clears it back to baseline" % [
		baseline_mood - after_one, capped,
	])
	return true


# --- drinks -----------------------------------------------------------------------------------
#
# A `drink` block is what makes something drinkable, the way `food` makes it edible; the water
# bottle's +50 was a literal in SimNeeds.drink and is content now; `empties` names what a spent
# unit leaves behind, decided in the one spend path. And the energy drink -- in two loot tables
# since the first cut, read by nothing -- is a stimulant: a lift on the rest pool now and a debt on
# the same pool later, docs/04's "real crash afterward". Every lane below has a true negative, and
# the reader is exercised through `item.use`, never by calling the leaf.

# Fabricated bases the lanes lean on, injected under a path of their own so the real tree is not
# edited: a stimulant on a forty-tick clock (a real one lands three in-game hours out, which is
# more sim than a gate should spend proving arithmetic), a lift with no crash behind it, a thirst
# that is not a number, and the two foods FOOD CONTENT spawns.
func _inject_fixture(w: Variant) -> void:
	(w.content as Dictionary)["items/_needs_gate_fixture.json"] = [
		{"id": "item.gate.stim", "name": "Gate Stimulant", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1, "stack": 4,
			"drink": {"thirst": 5, "rest": 20, "crashRest": 25, "crashAfterTicks": 40}},
		{"id": "item.gate.freelift", "name": "Free Lift", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"drink": {"thirst": 10, "rest": 20}},
		{"id": "item.gate.badthirst", "name": "Bad Thirst", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"drink": {"thirst": "lots"}},
		{"id": "item.gate.perishable", "name": "Gate Perishable", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"food": {"hunger": 10, "spoilDays": 1}},
		{"id": "item.gate.keeps", "name": "Gate Keeper", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"food": {"hunger": 10, "spoilDays": 0}},
		{"id": "item.gate.quick", "name": "Gate Quick", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"food": {"hunger": 10, "spoilDays": 0.002}},
	]


func _count_carried(w: Variant, actor: int, base_id: String) -> int:
	var n: int = 0
	for item in SimInventory.carried_items(w, actor):
		var b: Variant = w.components.get_component(int(item), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			n += 1
	return n


func _has_digit(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c >= 48 and c <= 57:
			return true
	return false


# Pockets are 4x2; a hiking pack on the back gives the lanes room to stow without the puzzle
# becoming the subject.
func _give_pack(w: Variant, actor: int) -> bool:
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	return SimInventory.equip(w, actor, pack)


func _quiet_pools(w: Variant, actor: int) -> Dictionary:
	var n: Dictionary = SimNeeds.of(w, actor)
	for k in SimNeeds.POOLS:
		n[k] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	n["crisis"] = "none"
	n["slept"] = "up"
	return n


func _drink_is_content_and_the_bottle_leaves_an_empty() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, 0.3)
	var spec_v: Variant = SimNeeds.drink_spec(w, "item.water.bottle")
	if not (spec_v is Dictionary) or absf(float((spec_v as Dictionary).get("thirst", -1.0)) - 50.0) > 0.001:
		push_error("DRINK: the water bottle's drink block reads %s; SimNeeds.drink used to carry +50 as a literal" % str(spec_v))
		return false
	var water_entry: Variant = SimItems.content_entry(w, "item", "item.water.bottle")
	if not (water_entry is Dictionary) or String((water_entry as Dictionary).get("empties", "")) != "item.water.bottle.empty":
		push_error("DRINK: the water bottle does not name item.water.bottle.empty as what it leaves")
		return false
	if SimItems.content_entry(w, "item", "item.water.bottle.empty") == null:
		push_error("DRINK: the empty bottle is not a base")
		return false
	for not_drink in ["item.scrap.metal", "item.food.canned", "item.not.a.real.base"]:
		if SimNeeds.is_drink(w, not_drink):
			push_error("DRINK: %s reads as a drink" % not_drink)
			return false
	_inject_fixture(w)
	if SimNeeds.is_drink(w, "item.gate.freelift"):
		push_error("DRINK: a lift with no crash behind it was accepted as drinkable -- a free stimulant")
		return false
	if SimNeeds.is_drink(w, "item.gate.badthirst"):
		push_error("DRINK: a thirst that is not a number was accepted")
		return false
	if not SimNeeds.is_drink(w, "item.gate.stim"):
		push_error("DRINK: a whole stimulant block was refused")
		return false
	# Through the command. The empties are counted on the body, before and after.
	if not _give_pack(w, w.player):
		push_error("DRINK: could not equip the pack")
		return false
	var drank: Array = []
	w.events.subscribe({"id": "gate.drank", "type": "need.drank", "handler": func(e: Dictionary) -> void: drank.append(e)})
	var n: Dictionary = _quiet_pools(w, w.player)
	var empties_before: int = _count_carried(w, w.player, "item.water.bottle.empty")
	var bottle: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, bottle):
		push_error("DRINK: could not stow the bottle")
		return false
	n["thirst"] = 10.0
	w.commands.push({"type": "item.use", "item": bottle})
	w.step()
	n = SimNeeds.of(w, w.player)
	if float(n["thirst"]) < 55.0:
		push_error("DRINK: item.use on a bottle left thirst at %s" % str(n["thirst"]))
		return false
	if w.components.has_component(bottle, "itemBase"):
		push_error("DRINK: the drunk bottle is still an item")
		return false
	if _count_carried(w, w.player, "item.water.bottle.empty") != empties_before + 1:
		push_error("DRINK: drinking left %d empties, want %d" % [_count_carried(w, w.player, "item.water.bottle.empty"), empties_before + 1])
		return false
	if drank.size() != 1 or bool((drank[0] as Dictionary).get("stimulant", true)):
		push_error("DRINK: need.drank fired %d times for one plain drink, or called water a stimulant" % drank.size())
		return false
	if int(n.get("stimulantUntilTick", -1)) != -1 or float(n.get("stimulantCrashRest", 0.0)) != 0.0:
		push_error("DRINK: water booked a stimulant crash")
		return false
	# A wash spends a bottle through the same path and leaves the same thing.
	var bottle2: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	SimInventory.stow(w, w.player, bottle2)
	n["hygiene"] = "filthy"
	w.commands.push({"type": "item.wash", "item": bottle2})
	w.step()
	n = SimNeeds.of(w, w.player)
	if String(n["hygiene"]) != "clean" or _count_carried(w, w.player, "item.water.bottle.empty") != empties_before + 2:
		push_error("DRINK: a wash read %s and left %d empties" % [str(n["hygiene"]), _count_carried(w, w.player, "item.water.bottle.empty")])
		return false
	# The true negative on empties: an energy drink names none, so a can of two becomes a can of
	# one and nothing else appears.
	var can: int = SimItems.spawn_item(w, "item.drink.energy", {"tier": "scavenged", "count": 2})
	SimInventory.stow(w, w.player, can)
	n["thirst"] = 10.0
	w.commands.push({"type": "item.use", "item": can})
	w.step()
	n = SimNeeds.of(w, w.player)
	var stack: Variant = w.components.get_component(can, "stack")
	if not (stack is Dictionary) or int((stack as Dictionary).get("count", 0)) != 1:
		push_error("DRINK: a can of two read %s after one drink" % str(stack))
		return false
	if _count_carried(w, w.player, "item.water.bottle.empty") != empties_before + 2:
		push_error("DRINK: an energy drink left an empty bottle")
		return false
	# Two drinks on the bus, not three: a wash spends a bottle and is not a drink.
	if float(n["thirst"]) < 24.0 or drank.size() != 2 or not bool((drank[1] as Dictionary).get("stimulant", false)):
		push_error("DRINK: the energy drink read thirst %s, %d drank events, stimulant flag %s" % [str(n["thirst"]), drank.size(), str((drank[1] as Dictionary).get("stimulant")) if drank.size() > 1 else "-"])
		return false
	print("DRINK OK water drinks +50 off its own block and leaves an empty (twice: a drink and a wash, and only the drink is on the bus); a lift with no crash, a non-numeric thirst, scrap, a tin and a missing base all refuse; a can of two energy drinks becomes one and leaves nothing")
	return true


func _a_stimulant_lifts_rest_now_and_crashes_later() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, 0.3)
	# The content clause: every stimulant in the tree is a loan, not a gift.
	var stims: Array[String] = []
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var d: Variant = e.get("drink")
		if not (d is Dictionary) or float((d as Dictionary).get("rest", 0.0)) <= 0.0:
			continue
		var id: String = String(e.get("id", ""))
		stims.append(id)
		if float((d as Dictionary).get("crashRest", 0.0)) < float((d as Dictionary)["rest"]) or int((d as Dictionary).get("crashAfterTicks", 0)) <= 0:
			push_error("STIMULANT: %s lifts %s and crashes %s after %s ticks -- a gift, not a loan" % [id, str((d as Dictionary)["rest"]), str((d as Dictionary).get("crashRest")), str((d as Dictionary).get("crashAfterTicks"))])
			return false
	if not stims.has("item.drink.energy"):
		push_error("STIMULANT: item.drink.energy is not a stimulant; the dead socket is still dead")
		return false
	var findable: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for t_v in file_v as Array:
			if t_v is Dictionary and String((t_v as Dictionary).get("id", "")).begins_with("loot."):
				for row_v in (t_v as Dictionary).get("entries", []) as Array:
					findable[String((row_v as Dictionary).get("item", ""))] = true
	if not findable.has("item.drink.energy") or findable.has("item.gate.stim"):
		push_error("STIMULANT: the loot scan cannot see the energy drink, or sees a base that is in no table")
		return false
	# The real can: the lift lands now, the clock is the block's, the HUD says so in a word.
	if not _give_pack(w, w.player):
		return false
	var n: Dictionary = _quiet_pools(w, w.player)
	n["rest"] = 75.0
	var can: int = SimItems.spawn_item(w, "item.drink.energy", {"tier": "scavenged"})
	SimInventory.stow(w, w.player, can)
	var t0: int = int(w.tick)
	w.commands.push({"type": "item.use", "item": can})
	w.step()
	n = SimNeeds.of(w, w.player)
	var lift: float = float(n["rest"]) - 75.0
	if lift < 20.0 - SimNeeds.drain_rest() - 0.01 or lift > 20.0 + 0.01:
		push_error("STIMULANT: the energy drink lifted rest by %.4f, want 20 less at most one drain" % lift)
		return false
	var until: int = int(n.get("stimulantUntilTick", -1))
	if until - t0 < 36000 or until - t0 > 36001:
		push_error("STIMULANT: the crash clock reads %d ticks out, want the block's 36000" % (until - t0))
		return false
	if absf(float(n.get("stimulantCrashRest", 0.0)) - 25.0) > 0.001:
		push_error("STIMULANT: the debt reads %s, want 25" % str(n.get("stimulantCrashRest")))
		return false
	var clause: String = SimNeeds.hud_clause(w, w.player)
	if not clause.contains("wired") or _has_digit(clause):
		push_error("STIMULANT: the HUD reads '%s' under a stimulant" % clause)
		return false
	var mara: int = _mara(w)
	if mara >= 0:
		var mn: Dictionary = _quiet_pools(w, mara)
		mn["stimulantUntilTick"] = int(w.tick) + 100
		if not SimNeeds.hud_clause(w, mara).contains("looks wired"):
			push_error("STIMULANT: a wired colonist reads '%s'" % SimNeeds.hud_clause(w, mara))
			return false
	# The crash, on the fixture's forty-tick clock, in a fresh world so the arithmetic is clean.
	var crashed: Array = []
	var w2: Variant = _world()
	w2.tick = Clock.tick_on_day(1, 0.3)
	_inject_fixture(w2)
	_give_pack(w2, w2.player)
	w2.events.subscribe({"id": "gate.crashed", "type": "need.crashed", "handler": func(e: Dictionary) -> void: crashed.append(e)})
	var n2: Dictionary = _quiet_pools(w2, w2.player)
	n2["rest"] = 40.0
	var s1: int = SimItems.spawn_item(w2, "item.gate.stim", {"tier": "scavenged"})
	SimInventory.stow(w2, w2.player, s1)
	w2.commands.push({"type": "item.use", "item": s1})
	w2.step()
	n2 = SimNeeds.of(w2, w2.player)
	if absf(float(n2["rest"]) - 60.0) > SimNeeds.drain_rest() + 0.01:
		push_error("STIMULANT: the fixture lifted 40 to %s" % str(n2["rest"]))
		return false
	var steps: int = 0
	var drop: float = 0.0
	while int(n2.get("stimulantUntilTick", -1)) >= 0 and steps < 60:
		var before: float = float(n2["rest"])
		w2.step()
		steps += 1
		n2 = SimNeeds.of(w2, w2.player)
		drop = before - float(n2["rest"])
	if steps < 38 or steps > 42:
		push_error("STIMULANT: the crash landed after %d steps on a forty-tick clock" % steps)
		return false
	if drop < 25.0 - 0.001 or drop > 25.0 + SimNeeds.drain_rest() + 0.001:
		push_error("STIMULANT: the crash dropped rest by %.4f, want 25 plus at most one drain" % drop)
		return false
	if crashed.size() != 1 or float(n2.get("stimulantCrashRest", 1.0)) != 0.0:
		push_error("STIMULANT: %d need.crashed events, debt left %s" % [crashed.size(), str(n2.get("stimulantCrashRest"))])
		return false
	if SimNeeds.hud_clause(w2, w2.player).contains("wired"):
		push_error("STIMULANT: still wired after the crash")
		return false
	# The twin that never drank: same seed, same ticks, no crash and no tick moving rest by more
	# than one drain.
	var crashed3: Array = []
	var w3: Variant = _world()
	w3.tick = Clock.tick_on_day(1, 0.3)
	w3.events.subscribe({"id": "gate.crashed3", "type": "need.crashed", "handler": func(e: Dictionary) -> void: crashed3.append(e)})
	var n3: Dictionary = _quiet_pools(w3, w3.player)
	n3["rest"] = 40.0
	var worst: float = 0.0
	for i in 45:
		var b3: float = float(n3["rest"])
		w3.step()
		n3 = SimNeeds.of(w3, w3.player)
		worst = maxf(worst, absf(b3 - float(n3["rest"])))
	if not crashed3.is_empty() or worst > SimNeeds.drain_rest() + 0.000001:
		push_error("STIMULANT: a world that drank nothing crashed %d times or moved rest %.4f in a tick" % [crashed3.size(), worst])
		return false
	# Chaining defers and compounds: two cans back to back, one crash of fifty.
	var crashed4: Array = []
	var w4: Variant = _world()
	w4.tick = Clock.tick_on_day(1, 0.3)
	_inject_fixture(w4)
	_give_pack(w4, w4.player)
	w4.events.subscribe({"id": "gate.crashed4", "type": "need.crashed", "handler": func(e: Dictionary) -> void: crashed4.append(e)})
	var n4: Dictionary = _quiet_pools(w4, w4.player)
	n4["rest"] = 40.0
	var pair: int = SimItems.spawn_item(w4, "item.gate.stim", {"tier": "scavenged", "count": 2})
	SimInventory.stow(w4, w4.player, pair)
	w4.commands.push({"type": "item.use", "item": pair})
	w4.step()
	w4.commands.push({"type": "item.use", "item": pair})
	w4.step()
	n4 = SimNeeds.of(w4, w4.player)
	if absf(float(n4.get("stimulantCrashRest", 0.0)) - 50.0) > 0.001:
		push_error("STIMULANT: two cans booked a debt of %s, want 50" % str(n4.get("stimulantCrashRest")))
		return false
	var steps4: int = 0
	var drop4: float = 0.0
	while int(n4.get("stimulantUntilTick", -1)) >= 0 and steps4 < 60:
		var b4: float = float(n4["rest"])
		w4.step()
		steps4 += 1
		n4 = SimNeeds.of(w4, w4.player)
		drop4 = b4 - float(n4["rest"])
	if crashed4.size() != 1 or drop4 < 50.0 - 0.001 or absf(float((crashed4[0] as Dictionary).get("rest", 0.0)) - 50.0) > 0.001:
		push_error("STIMULANT: chaining landed %d crashes, the last dropping %.4f" % [crashed4.size(), drop4])
		return false
	# And the crash is real: three cans on a tired pool land on the floor, and the floor is the
	# ordinary collapse.
	var w5: Variant = _world()
	w5.tick = Clock.tick_on_day(1, 0.3)
	_inject_fixture(w5)
	_give_pack(w5, w5.player)
	var n5: Dictionary = _quiet_pools(w5, w5.player)
	n5["rest"] = 5.0
	var trio: int = SimItems.spawn_item(w5, "item.gate.stim", {"tier": "scavenged", "count": 3})
	SimInventory.stow(w5, w5.player, trio)
	for i in 3:
		w5.commands.push({"type": "item.use", "item": trio})
		w5.step()
	n5 = SimNeeds.of(w5, w5.player)
	var steps5: int = 0
	while int(n5.get("stimulantUntilTick", -1)) >= 0 and steps5 < 60:
		w5.step()
		steps5 += 1
		n5 = SimNeeds.of(w5, w5.player)
	var sleeping: Variant = w5.components.get_component(w5.player, "sleeping")
	# Under one rather than exactly zero: the collapse starts the sleep that refills the pool on
	# the very tick the crash lands (need.rest runs after need.stimulant).
	if float(n5["rest"]) >= 1.0 or String(n5.get("crisis", "")) != "passed_out" or not (sleeping is Dictionary) or int((sleeping as Dictionary).get("bed", 0)) != -1:
		push_error("STIMULANT: three cans on a pool of five left rest %s, crisis %s, sleeping %s" % [str(n5["rest"]), str(n5.get("crisis")), str(sleeping)])
		return false
	# The hold clears the clock and the debt with everything else.
	var w6: Variant = _world()
	_inject_fixture(w6)
	_give_pack(w6, w6.player)
	w6.needsHoldMax = true
	var s6: int = SimItems.spawn_item(w6, "item.gate.stim", {"tier": "scavenged"})
	SimInventory.stow(w6, w6.player, s6)
	w6.commands.push({"type": "item.use", "item": s6})
	w6.step()
	var n6: Dictionary = SimNeeds.of(w6, w6.player)
	if int(n6.get("stimulantUntilTick", 0)) != -1 or float(n6.get("stimulantCrashRest", 1.0)) != 0.0:
		push_error("STIMULANT: the hold left a clock of %s and a debt of %s" % [str(n6.get("stimulantUntilTick")), str(n6.get("stimulantCrashRest"))])
		return false
	print("STIMULANT OK %d stimulant(s) in content, each a loan; the energy drink lifts 20 now, books 25 in 36000 ticks and reads 'wired' with no digit; on a forty-tick fixture the crash lands after %d steps for 25, a twin that drank nothing never crashes, two cans land one crash of 50, three on a pool of five collapse, and the hold clears it" % [stims.size(), steps])
	return true


# `spoilage_rate` has a reader. It was declared in stats.gd, sold by the `surv.cook` web node and
# resolved by nothing, so "a careful pantry" was a node a survivor could own and nobody could feel.
# The owner's rule: a perishable ages at the best living colonist's rate. Measured on a fixture
# food that spoils in 576 ticks: with nobody owning the node it spoils at 576 and not at 575; with
# Mara owning it, not at 606 and by 607 (576 / 0.95, rounded up); with Mara dead, at 576 again.
func _a_careful_pantry_slows_spoilage() -> bool:
	var w: Variant = _world()
	_inject_fixture(w)
	w.needsHoldMax = true
	var mara: int = _mara(w)
	if mara < 0:
		push_error("PANTRY: no Mara in the booted colony, so nothing was judged")
		return false
	var node: Variant = null
	for n in (SimSkills._web().get("nodes", []) as Array):
		if String((n as Dictionary).get("id", "")) == "surv.cook":
			node = n
	if node == null or String((node as Dictionary).get("stat", "")) != "spoilage_rate":
		push_error("PANTRY: the web has no surv.cook node targeting spoilage_rate, so there is nothing to feel")
		return false
	var mul: float = float((node as Dictionary).get("value", 1.0))

	# Nobody owns the node: on schedule, to the tick.
	var quick: int = SimItems.spawn_item(w, "item.gate.quick", {"tier": "scavenged"})
	var sp: Variant = w.components.get_component(quick, "spoilage")
	if not (sp is Dictionary) or int((sp as Dictionary).get("spoilTicks", 0)) != 576:
		push_error("PANTRY: the fixture food did not get a 576-tick spoilage clock: %s" % str(sp))
		return false
	for _i in 575:
		w.step()
	if bool((sp as Dictionary).get("spoiled", false)):
		push_error("PANTRY: spoiled a tick early with nobody keeping the pantry")
		return false
	w.step()
	if not bool((sp as Dictionary).get("spoiled", false)):
		push_error("PANTRY: not spoiled on its 576th tick with nobody keeping the pantry")
		return false
	if absf(SimNeeds.pantry_rate(w) - 1.0) > 0.0001:
		push_error("PANTRY: the rate with nobody owning the node is %.4f, not 1.0" % SimNeeds.pantry_rate(w))
		return false

	# Mara buys it through the real command path, and every perishable in the colony feels it.
	SimJobs.set_focus(w, mara, "Manual")
	SimSkills._earn(w, mara, "Survival", 1)
	var learned: Array = []
	w.events.subscribe({"id": "gate.pantry.learned", "type": "web.learned", "handler": func(e: Dictionary) -> void:
		learned.append(e)
	})
	w.commands.push({"type": "web.buy", "entity": mara, "node": "surv.cook"})
	w.step()
	if learned.size() != 1 or not SimSkills.has_node(w, mara, "surv.cook"):
		push_error("PANTRY: Mara did not learn surv.cook (learned %d, owns %s)" % [learned.size(), str(SimSkills.has_node(w, mara, "surv.cook"))])
		return false
	if absf(float(w.modifiers.resolve("spoilage_rate", mara)) - mul) > 0.0001 or absf(SimNeeds.pantry_rate(w) - mul) > 0.0001:
		push_error("PANTRY: Mara resolves spoilage_rate %.4f and the pantry reads %.4f, wanted %.4f" % [float(w.modifiers.resolve("spoilage_rate", mara)), SimNeeds.pantry_rate(w), mul])
		return false
	var slow: int = SimItems.spawn_item(w, "item.gate.quick", {"tier": "scavenged"})
	var ssp: Dictionary = w.components.get_component(slow, "spoilage") as Dictionary
	var later: int = int(ceil(576.0 / mul))
	for _i in later - 1:
		w.step()
	if bool(ssp.get("spoiled", false)):
		push_error("PANTRY: with a careful pantry the food spoiled by tick %d, no later than before" % (later - 1))
		return false
	w.step()
	if not bool(ssp.get("spoiled", false)):
		push_error("PANTRY: with a careful pantry the food had not spoiled by tick %d" % later)
		return false

	# The dead keep no pantry: Mara's node dies with her and the clock runs at full speed again.
	SimHealth.finish_death(w, mara)
	w.events.drain()
	if absf(SimNeeds.pantry_rate(w) - 1.0) > 0.0001:
		push_error("PANTRY: a dead Mara still keeps the pantry at %.4f" % SimNeeds.pantry_rate(w))
		return false
	var after: int = SimItems.spawn_item(w, "item.gate.quick", {"tier": "scavenged"})
	var asp: Dictionary = w.components.get_component(after, "spoilage") as Dictionary
	for _i in 575:
		w.step()
	if bool(asp.get("spoiled", false)):
		push_error("PANTRY: spoiled early after the pantry-keeper died")
		return false
	w.step()
	if not bool(asp.get("spoiled", false)):
		push_error("PANTRY: not spoiled on its 576th tick after the pantry-keeper died")
		return false
	print("PANTRY OK 576 ticks with nobody, %d with Mara's careful pantry (x%.2f), 576 again once she is dead" % [later, mul])
	return true


# Untreated water carries illness (docs/04). The well used to fill a bottle with `item.water.bottle`
# by rename -- clean water for the price of a walk, and the doc's sentence built by nothing. Now
# it fills `item.water.bottle.untreated`, which drinks like water and rolls the food-poisoning
# bout, and a lit campfire boils one clean. Four claims, each with its negative:
#   CONTENT  the untreated base declares its chance, the bottled one declares none, both leave the
#            same empty, no loot table rolls the untreated one (the well is its only source), and a
#            block with a chance outside 0..1 is refused as not drinkable at all
#   RATE     400 untreated drinks make somebody ill a measured number of times strictly between 0
#            and 400 and near the authored chance; 400 bottled make exactly 0; iron_stomach makes 0
#   BOIL     a lit fire boils one bottle and stays lit; an unlit one refuses; an empty pack refuses;
#            through the E ladder, a lit fire boils rather than douses and an unlit one lights
#            rather than boils
#   NPC      thirsty, with an untreated bottle and a fire and nothing clean: boils, then drinks
#            clean; with a clean bottle beside it: drinks at once and boils nothing; with no fire
#            and thirst below SOFT: drinks it untreated; with no fire and thirst above SOFT: waits
func _untreated_water_carries_illness_and_a_fire_boils_it() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, 0.3)
	var raw_spec: Variant = SimNeeds.drink_spec(w, SimNeeds.UNTREATED_ID)
	if not (raw_spec is Dictionary) or float((raw_spec as Dictionary).get("illnessChance", 0.0)) <= 0.0:
		push_error("WATER: %s declares no illness chance: %s" % [SimNeeds.UNTREATED_ID, str(raw_spec)])
		return false
	var chance: float = float((raw_spec as Dictionary).get("illnessChance", 0.0))
	var clean_spec: Variant = SimNeeds.drink_spec(w, SimNeeds.WATER_ID)
	if not (clean_spec is Dictionary) or (clean_spec as Dictionary).has("illnessChance"):
		push_error("WATER: bottled water declares an illness chance: %s" % str(clean_spec))
		return false
	var raw_entry: Dictionary = SimItems.content_entry(w, "item", SimNeeds.UNTREATED_ID) as Dictionary
	var clean_entry: Dictionary = SimItems.content_entry(w, "item", SimNeeds.WATER_ID) as Dictionary
	if String(raw_entry.get("empties", "")) != String(clean_entry.get("empties", "x")):
		push_error("WATER: the two bottles leave different empties: %s vs %s" % [raw_entry.get("empties", ""), clean_entry.get("empties", "")])
		return false
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for t_v in file_v as Array:
			if t_v is Dictionary and String((t_v as Dictionary).get("id", "")).begins_with("loot."):
				for row_v in (t_v as Dictionary).get("entries", []) as Array:
					if String((row_v as Dictionary).get("item", "")) == SimNeeds.UNTREATED_ID:
						push_error("WATER: a loot table rolls untreated water, which only the well should make")
						return false
	(w.content as Dictionary)["items/_water_gate_fixture.json"] = [
		{"id": "item.gate.badwater", "name": "Bad Water", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"drink": {"thirst": 50, "illnessChance": 1.5}},
	]
	if SimNeeds.is_drink(w, "item.gate.badwater"):
		push_error("WATER: an illness chance of 1.5 was accepted as drinkable")
		return false

	# RATE. Same shape as the raw-food lane: stow, drink, count the bouts.
	const MEALS: int = 400
	var rates: Dictionary = {}
	for c in [
		{"key": "raw", "id": SimNeeds.UNTREATED_ID, "iron": false},
		{"key": "clean", "id": SimNeeds.WATER_ID, "iron": false},
		{"key": "iron", "id": SimNeeds.UNTREATED_ID, "iron": true},
	]:
		var w2: Variant = _world()
		if bool(c["iron"]):
			var ident: Variant = w2.components.get_component(w2.player, "identity")
			var id_d: Dictionary = (ident as Dictionary) if ident is Dictionary else {"id": "survivor.gate", "name": "Gate"}
			var traits: Array = ((id_d.get("traits", []) as Array).duplicate()) if id_d.get("traits") is Array else []
			traits.append("iron_stomach")
			id_d["traits"] = traits
			w2.components.set_component(w2.player, "identity", id_d)
			if not SimNeeds.has_trait(w2, w2.player, "iron_stomach"):
				push_error("WATER: could not give the player an iron stomach")
				return false
		var ill: Array = []
		w2.events.subscribe({"type": "illness.contracted", "id": "gate.water.ill", "handler": func(_e: Dictionary) -> void:
			ill.append(1)
		})
		for _m in MEALS:
			var bottle: int = SimItems.spawn_item(w2, String(c["id"]), {"tier": "scavenged"})
			w2.components.set_component(bottle, "stored", {"container": w2.player})
			SimNeeds.of(w2, w2.player)["thirst"] = 10.0
			if not SimNeeds.drink_item(w2, w2.player, bottle):
				push_error("WATER: could not drink %s" % String(c["id"]))
				return false
			w2.events.drain()
		rates[String(c["key"])] = float(ill.size()) / float(MEALS)
	var raw_rate: float = float(rates["raw"])
	if float(rates["clean"]) != 0.0:
		push_error("WATER: bottled water made somebody ill %.3f of the time" % float(rates["clean"]))
		return false
	if float(rates["iron"]) != 0.0:
		push_error("WATER: an iron stomach still fell ill %.3f of the time" % float(rates["iron"]))
		return false
	if raw_rate <= 0.0 or raw_rate >= 1.0 or absf(raw_rate - chance) > 0.07:
		push_error("WATER: untreated water made somebody ill %.3f of the time against an authored %.2f" % [raw_rate, chance])
		return false

	# BOIL, direct and through the one key.
	var w3: Variant = _world()
	w3.tick = Clock.tick_on_day(1, 0.3)
	var fires: Array[int] = w3.components.query(["campfire"])
	if fires.is_empty():
		push_error("WATER: the booted district sited no campfire, so boiling has nothing to judge")
		return false
	var fire: int = int(fires[0])
	if not _give_pack(w3, w3.player):
		push_error("WATER: could not equip the pack")
		return false
	var boiled: Array = []
	w3.events.subscribe({"type": "need.boiled", "id": "gate.water.boiled", "handler": func(e: Dictionary) -> void:
		boiled.append(e)
	})
	var none: Dictionary = SimNeeds.boil(w3, w3.player, fire)
	if bool(none.get("ok", false)) or String(none.get("reason", "")) not in ["unlit", "no-bottle"]:
		push_error("WATER: boiling with nothing to boil returned %s" % str(none))
		return false
	var jug: int = SimItems.spawn_item(w3, SimNeeds.UNTREATED_ID, {"tier": "scavenged"})
	if not SimInventory.stow(w3, w3.player, jug):
		push_error("WATER: could not stow the untreated bottle")
		return false
	SimNeeds.set_lit(w3, fire, false)
	var cold: Dictionary = SimNeeds.boil(w3, w3.player, fire)
	if bool(cold.get("ok", false)) or String(cold.get("reason", "")) != "unlit":
		push_error("WATER: an unlit fire boiled, or refused for the wrong reason: %s" % str(cold))
		return false
	SimNeeds.set_lit(w3, fire, true)
	var hot: Dictionary = SimNeeds.boil(w3, w3.player, fire)
	w3.events.drain()
	var jug_base: Dictionary = w3.components.get_component(jug, "itemBase") as Dictionary
	if not bool(hot.get("ok", false)) or String(jug_base.get("baseId", "")) != SimNeeds.WATER_ID or boiled.size() != 1:
		push_error("WATER: a lit fire did not boil the bottle clean: %s, base %s, %d events" % [str(hot), jug_base.get("baseId", ""), boiled.size()])
		return false
	if not bool((w3.components.get_component(fire, "campfire") as Dictionary).get("lit", false)):
		push_error("WATER: boiling put the fire out")
		return false
	var again: Dictionary = SimNeeds.boil(w3, w3.player, fire)
	if bool(again.get("ok", false)) or String(again.get("reason", "")) != "no-bottle":
		push_error("WATER: with the bottle already clean, boil returned %s" % str(again))
		return false
	# The E ladder: stand at the lit fire with an untreated bottle -> boil, fire stays lit; at an
	# unlit fire -> the fire lights and nothing boils.
	var fp: Dictionary = w3.components.get_component(fire, "position") as Dictionary
	w3.components.set_component(w3.player, "position", {"x": float(fp["x"]) + 1.0, "y": float(fp["y"])})
	# The ladder's higher rungs first -- loose loot, then a cupboard -- and the annex has both in
	# reach of its fire. Clear them so this presses E at the fire and not at the floor; the rung
	# order itself is `godot:m2:fortify`'s to judge.
	for loose in SimInventory.ground_items(w3):
		w3.despawn(int(loose))
	for box in w3.components.query(["searchable"]):
		w3.despawn(int(box))
	var jug2: int = SimItems.spawn_item(w3, SimNeeds.UNTREATED_ID, {"tier": "scavenged"})
	SimInventory.stow(w3, w3.player, jug2)
	boiled.clear()
	w3.commands.push({"type": "use.context"})
	w3.step()
	if boiled.size() != 1 or not bool((w3.components.get_component(fire, "campfire") as Dictionary).get("lit", false)):
		push_error("WATER: E at a lit fire with a bottle of well water boiled %d and left the fire lit=%s" % [boiled.size(), str((w3.components.get_component(fire, "campfire") as Dictionary).get("lit", false))])
		return false
	SimNeeds.set_lit(w3, fire, false)
	var jug3: int = SimItems.spawn_item(w3, SimNeeds.UNTREATED_ID, {"tier": "scavenged"})
	SimInventory.stow(w3, w3.player, jug3)
	boiled.clear()
	w3.commands.push({"type": "use.context"})
	w3.step()
	if not boiled.is_empty() or not bool((w3.components.get_component(fire, "campfire") as Dictionary).get("lit", false)):
		push_error("WATER: E at an unlit fire boiled %d or did not light it" % boiled.size())
		return false

	# NPC. Four worlds, one rung each.
	var out: Array[String] = []
	for c in [
		{"name": "boils", "fire": true, "clean": false, "thirst": 35.0, "want_boil": 1, "want_drink": SimNeeds.WATER_ID},
		{"name": "clean-first", "fire": true, "clean": true, "thirst": 35.0, "want_boil": 0, "want_drink": SimNeeds.WATER_ID},
		{"name": "raw-at-soft", "fire": false, "clean": false, "thirst": 25.0, "want_boil": 0, "want_drink": SimNeeds.UNTREATED_ID},
		{"name": "waits", "fire": false, "clean": false, "thirst": 35.0, "want_boil": 0, "want_drink": ""},
	]:
		var w4: Variant = _world()
		w4.tick = Clock.tick_on_day(1, 0.3)
		var mara: int = _mara(w4)
		if mara < 0:
			push_error("WATER: no Mara")
			return false
		for item in w4.components.query(["itemBase"]):
			var b: Dictionary = w4.components.get_component(int(item), "itemBase") as Dictionary
			if String(b.get("baseId", "")) == SimNeeds.WATER_ID:
				w4.despawn(int(item))
		if not bool(c["fire"]):
			for f in w4.components.query(["campfire"]):
				w4.despawn(int(f))
		else:
			for f in w4.components.query(["campfire"]):
				SimNeeds.set_lit(w4, int(f), true)
		if not _give_pack(w4, mara):
			push_error("WATER: could not equip Mara's pack")
			return false
		var jug4: int = SimItems.spawn_item(w4, SimNeeds.UNTREATED_ID, {"tier": "scavenged"})
		if not SimInventory.stow(w4, mara, jug4):
			push_error("WATER: could not stow Mara's untreated bottle")
			return false
		if bool(c["clean"]):
			var cb: int = SimItems.spawn_item(w4, SimNeeds.WATER_ID, {"tier": "scavenged"})
			SimInventory.stow(w4, mara, cb)
		var n: Dictionary = _quiet_pools(w4, mara)
		n["thirst"] = float(c["thirst"])
		w4.components.remove(mara, "job")
		var boils: Array = []
		var drinks: Array = []
		w4.events.subscribe({"type": "need.boiled", "id": "gate.npc.boiled", "handler": func(e: Dictionary) -> void:
			if int(e.get("entity", -1)) == mara:
				boils.append(e)
		})
		w4.events.subscribe({"type": "need.drank", "id": "gate.npc.drank", "handler": func(e: Dictionary) -> void:
			if int(e.get("entity", -1)) == mara:
				drinks.append(String(e.get("baseId", "")))
		})
		for _i in 3000:
			w4.step()
			if not drinks.is_empty():
				break
			n = SimNeeds.of(w4, mara)
			if float(n.get("thirst", 100.0)) > float(c["thirst"]) + 20.0:
				break
		var drank: String = drinks[0] if not drinks.is_empty() else ""
		if boils.size() != int(c["want_boil"]) or drank != String(c["want_drink"]):
			push_error("WATER: NPC case '%s' boiled %d and drank '%s'; wanted %d and '%s'" % [c["name"], boils.size(), drank, int(c["want_boil"]), c["want_drink"]])
			return false
		out.append("%s(boil %d, drank %s)" % [c["name"], boils.size(), drank if drank != "" else "nothing"])
	print("WATER OK untreated %.3f ill of %d, bottled 0, iron 0; a lit fire boils and an unlit one refuses, E boils before it douses; NPC %s" % [raw_rate, MEALS, ", ".join(out)])
	return true


# --- a lit fire burns down (2026-09-06, the playable state) -----------------------------------
#
# A fire lit by a cook, a warm-seek or the E key used to stay lit for the rest of the run. Now
# `set_lit` stamps `litUntilTick` and `need.fires` douses past it unless a cook is at it. Three
# readers see the douse (the flag, the light source, `lit_campfire_near`); the clock is read off
# the constant and then shortened by hand so the mechanism is judged in fifty ticks rather than
# thirty-six thousand; cooking holds it; a re-light refreshes it; a lit fire with no clock (a save
# from before the clock) is stamped rather than doused.
func _a_lit_fire_burns_down() -> bool:
	var w: Variant = _world()
	var start: Vector2i = SimTileMap.player_start(w.tilemap)
	var fx: float = float(start.x) + 2.5
	var fy: float = float(start.y) + 0.5
	var fire: int = SimNeeds.make_campfire(w, fx, fy, false)
	SimNeeds.set_lit(w, fire, true)
	var cf: Dictionary = w.components.get_component(fire, "campfire") as Dictionary
	if int(cf.get("litUntilTick", -1)) != int(w.tick) + SimNeeds.CAMPFIRE_BURN_TICKS:
		push_error("fire: lighting did not stamp the clock (%s)" % str(cf))
		return false
	if not w.components.has_component(fire, "light_source") or not SimNeeds.lit_campfire_near(w, fx, fy, 1.0):
		push_error("fire: lit, but the light source or the heat reader does not see it")
		return false
	# Not doused before its time.
	for _i in 60:
		w.step()
	if not bool((w.components.get_component(fire, "campfire") as Dictionary).get("lit", false)):
		push_error("fire: doused before its clock")
		return false
	# The clock, shortened: doused the tick it is reached, and every reader sees it.
	cf = w.components.get_component(fire, "campfire") as Dictionary
	cf["litUntilTick"] = int(w.tick) + 50
	for _i in 51:
		w.step()
	cf = w.components.get_component(fire, "campfire") as Dictionary
	if bool(cf.get("lit", false)) or w.components.has_component(fire, "light_source") or SimNeeds.lit_campfire_near(w, fx, fy, 1.0):
		push_error("fire: past its clock it is still lit / lighting / warming (%s)" % str(cf))
		return false
	# Cooking holds it past the clock.
	SimNeeds.set_lit(w, fire, true, true)
	cf = w.components.get_component(fire, "campfire") as Dictionary
	cf["litUntilTick"] = int(w.tick) + 10
	for _i in 60:
		w.step()
	if not bool((w.components.get_component(fire, "campfire") as Dictionary).get("lit", false)):
		push_error("fire: a cook's fire was doused under them")
		return false
	# A re-light refreshes the clock.
	SimNeeds.set_lit(w, fire, true, false)
	cf = w.components.get_component(fire, "campfire") as Dictionary
	cf["litUntilTick"] = int(w.tick) + 10
	for _i in 5:
		w.step()
	SimNeeds.set_lit(w, fire, true, false)
	var refreshed: int = int((w.components.get_component(fire, "campfire") as Dictionary).get("litUntilTick", -1))
	if refreshed != int(w.tick) + SimNeeds.CAMPFIRE_BURN_TICKS:
		push_error("fire: a re-light did not refresh the clock (%d vs %d)" % [refreshed, int(w.tick) + SimNeeds.CAMPFIRE_BURN_TICKS])
		return false
	# No clock at all: stamped, not doused.
	cf = w.components.get_component(fire, "campfire") as Dictionary
	cf.erase("litUntilTick")
	w.step()
	cf = w.components.get_component(fire, "campfire") as Dictionary
	if not bool(cf.get("lit", false)) or not cf.has("litUntilTick"):
		push_error("fire: a lit fire with no clock was doused or left unstamped (%s)" % str(cf))
		return false
	print("FIRE OK lit stamps tick+%d, not doused early, doused at the clock and the flag, the light and the heat reader all see it, a cook holds it, a re-light refreshes it, a clockless lit fire is stamped" % SimNeeds.CAMPFIRE_BURN_TICKS)
	return true


# --- BED ----------------------------------------------------------------------------------------
#
# What you sleep *on*. docs/04's Rest clause names bed quality first of the five things recovery
# depends on, and `sleep_quality` shipped without it because there was nothing to read: `make_bed`
# made a bare marker and every bed in the district was the identical nothing. This lane judges the
# key that fixed that, in three parts, because each of the three is a different way it could be
# wrong.
#
# PINNED is the one that matters most. A bed with no bedding must be arithmetically the bed that
# shipped before this existed -- this is an addition to the roster, not a quiet rebalance of
# everybody's nights -- so the three scenarios whose figures were already pinned elsewhere in this
# file are re-derived here from the constants alone and must land on them exactly.
#
# PAIRED is the dead-socket half: two identically seeded districts, one sleeper on a bedroll and
# one on the bare boards, and the rest they actually wake with has to differ in the right
# direction. It follows check_m2_medicine.gd's CLEAR lane in shape, including its second claim --
# it is not enough for the figures to be ordered, some seed has to actually turn on the bedding,
# and neither figure may be zero or the pair proves nothing.
#
# SOAP is the other key this slice authored. A wash already reaches `clean` on water alone, so what
# soap buys is a wash that lasts: charges banked at the well and spent one per dirtying, which is
# the only door hygiene walks back down.
const BED_SEEDS: Array[int] = [20260805, 20260806, 20260807, 20260808, 20260809, 20260810]
const BEDDING_GOOD: String = "item.sleepingbag.down"
const BEDDING_POOR: String = "item.bedroll.foam"
const SOAP_ID: String = "item.soap.bar"


func _world_seeded(seed_val: int) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# docs/10's footprint puzzle, live and in the way: a sleeping bag is two squares by three, and a
# booted colonist's belt pouch is not three squares tall and already has the district's starting kit
# in it. So the fixture puts everything loose on the floor -- dropped rather than despawned, because
# despawning somebody's gear out from under the inventory is a different bug to go looking for --
# keeps what they are wearing, and gives them a hiking pack to put a bedroll in. Without this the
# lane would fail on the grid rather than on the thing under test.
func _empty_pack(w: Variant, ent: int) -> void:
	var worn: Dictionary = {}
	for eq in SimInventory.equipped_items(w, ent):
		worn[int(eq)] = true
	for item in SimInventory.carried_items(w, ent):
		if worn.has(int(item)):
			continue
		SimInventory.drop_at_feet(w, ent, int(item))
	for eq in SimInventory.equipped_items(w, ent):
		if w.components.has_component(int(eq), "container"):
			SimInventory.unequip_item(w, int(eq))
			SimInventory.drop_at_feet(w, ent, int(eq))
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(w, ent, pack, "back"):
		push_error("BED: the fixture could not put a hiking pack on a survivor's back")


func _give(w: Variant, ent: int, id: String) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.stow(w, ent, item):
		push_error("BED: the fixture '%s' would not go in a pocket" % id)
		return -1
	return item


# A sleeper put to bed on `bed`, in the named temperature band, with every other pool full so the
# only thing moving is the night. Returns the rest they wake with.
func _rest_after_a_night(w: Variant, ent: int, bed: int, band: String) -> float:
	SimNeeds.start_sleep(w, ent, bed)
	var n: Dictionary = SimNeeds.of(w, ent)
	n["rest"] = 0.0
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["relief"] = 100.0
	n["temperature"] = band
	n["hygiene"] = "clean"
	_sleep_a_night(w, ent, n)
	return float(n["rest"])


func _bedding_moves_the_night_and_bare_boards_move_nothing() -> bool:
	# --- PINNED ---------------------------------------------------------------------------------
	# The three figures that were already true, re-derived from the constants and asserted against a
	# bed the district itself sited. If any of these moves, this slice rebalanced sleep instead of
	# adding to it.
	var wp: Variant = _world_seeded(BED_SEEDS[0])
	var ep: int = int(wp.player)
	var plain: int = _first_bed(wp)
	if plain < 0:
		push_error("BED: the booted district sited no bed, so this lane has nothing to judge")
		return false
	if absf(SimNeeds.bed_comfort(wp, plain) - 0.0) > 0.0001:
		push_error("BED: a bed the district built came with comfort %.4f rather than bare boards" % SimNeeds.bed_comfort(wp, plain))
		return false
	if SimNeeds.band_pressure("temperature", "very_cold") != "soft":
		push_error("BED: `very_cold` no longer reads as the soft band, so the pinned arithmetic below is not the arithmetic being tested")
		return false
	var pins: Array[Dictionary] = [
		{"bed": plain, "band": "comfortable", "want": 1.0},
		{"bed": plain, "band": "very_cold", "want": 1.0 - SimNeeds.SLEEP_PENALTY_TEMP_SOFT},
		{"bed": -1, "band": "comfortable", "want": 1.0 - SimNeeds.SLEEP_PENALTY_ROUGH},
	]
	for pin in pins:
		SimNeeds.start_sleep(wp, ep, int(pin["bed"]))
		var np: Dictionary = SimNeeds.of(wp, ep)
		np["temperature"] = String(pin["band"])
		var got: float = SimNeeds.sleep_quality(wp, ep)
		if absf(got - float(pin["want"])) > 0.0001:
			push_error("BED PINNED: on bed %d in `%s` the quality is %.4f and the constants say %.4f -- bedding changed a night nobody put bedding on" % [int(pin["bed"]), String(pin["band"]), got, float(pin["want"])])
			return false
		SimNeeds.wake(wp, ep)

	# --- FURNISH --------------------------------------------------------------------------------
	# The builder's half: an empty pack changes nothing, the best of two grades is the one that goes
	# in, it comes out of the pack rather than being copied out of it, and what lands on the bed is
	# a plain float that a save can carry.
	var wf: Variant = _world_seeded(BED_SEEDS[0])
	var ef: int = int(wf.player)
	var bare: int = SimNeeds.make_bed(wf, 8.5, 8.5)
	if SimNeeds.furnish_bed(wf, ef, bare) != "":
		push_error("BED FURNISH: an empty pack furnished a bed")
		return false
	if SimNeeds.bed_comfort(wf, bare) > 0.0:
		push_error("BED FURNISH: a bed nobody furnished is not bare boards")
		return false
	_empty_pack(wf, ef)
	if _give(wf, ef, BEDDING_POOR) < 0 or _give(wf, ef, BEDDING_GOOD) < 0:
		return false
	var carried_before: int = SimInventory.carried_items(wf, ef).size()
	var grade: String = SimNeeds.furnish_bed(wf, ef, bare)
	if grade != "proper":
		push_error("BED FURNISH: carrying a down bag and a foam roll, the bed took '%s' rather than the better of the two" % grade)
		return false
	if absf(SimNeeds.bed_comfort(wf, bare) - SimNeeds.bedding_comfort("proper")) > 0.0001:
		push_error("BED FURNISH: the bed carries %.4f and the grade is priced at %.4f" % [SimNeeds.bed_comfort(wf, bare), SimNeeds.bedding_comfort("proper")])
		return false
	if SimInventory.carried_items(wf, ef).size() != carried_before - 1:
		push_error("BED FURNISH: the bedding went into the bed and stayed in the pack")
		return false
	var comp: Variant = wf.components.get_component(bare, "bed")
	if not (comp is Dictionary) or not ((comp as Dictionary)["comfort"] is float):
		push_error("BED FURNISH: `comfort` is not a plain float on the bed component, so it will not survive a save")
		return false

	# --- PAIRED ---------------------------------------------------------------------------------
	# Two identically seeded districts per seed. One sleeper is handed a bedroll and builds it into
	# the bed the district sited; the other sleeps on the same bed untouched. Both nights are the
	# cold band, because comfort is spent against a penalty and a night with no penalty has nothing
	# for it to buy -- which is the pin above, seen from the other side.
	var better: int = 0
	var judged: int = 0
	var sample_bare: float = 0.0
	var sample_soft: float = 0.0
	for seed_val in BED_SEEDS:
		var wa: Variant = _world_seeded(int(seed_val))
		var ba: int = _first_bed(wa)
		var wb: Variant = _world_seeded(int(seed_val))
		var bb: int = _first_bed(wb)
		if ba < 0 or bb < 0:
			continue
		# Both packs are emptied, not just the one that gets the bedroll, so the only difference
		# between the two districts is the bedding itself.
		_empty_pack(wa, int(wa.player))
		_empty_pack(wb, int(wb.player))
		# The foam roll rather than the down bag on purpose: `proper` comfort would cancel the cold
		# band outright and land the bedded night on the full-night cap, and a figure sitting on a
		# clamp is a figure that would still sit there if the arithmetic underneath it were wrong.
		# The middling grade leaves both nights strictly between the floor and the cap.
		if _give(wb, int(wb.player), BEDDING_POOR) < 0:
			return false
		if SimNeeds.furnish_bed(wb, int(wb.player), bb) == "":
			push_error("BED PAIRED: on seed %d the bedding would not go into the bed" % int(seed_val))
			return false
		var rest_bare: float = _rest_after_a_night(wa, int(wa.player), ba, "very_cold")
		var rest_soft: float = _rest_after_a_night(wb, int(wb.player), bb, "very_cold")
		if rest_bare <= 0.0 or rest_soft <= 0.0:
			push_error("BED PAIRED: on seed %d a night restored nothing (bare %.3f, bedded %.3f) -- neither figure is decided" % [int(seed_val), rest_bare, rest_soft])
			return false
		if rest_bare >= SimNeeds.SLEEP_FULL_NIGHT - 0.001:
			push_error("BED PAIRED: on seed %d the bare night was already a perfect one (%.3f), so there was no room for bedding to matter and the pair proves nothing" % [int(seed_val), rest_bare])
			return false
		if rest_soft < rest_bare:
			push_error("BED PAIRED: on seed %d the bedroll slept worse than the boards (%.3f against %.3f)" % [int(seed_val), rest_soft, rest_bare])
			return false
		if rest_soft >= SimNeeds.SLEEP_FULL_NIGHT - 0.001:
			push_error("BED PAIRED: on seed %d the bedded night landed on the full-night cap (%.3f), so the figure is a clamp rather than a measurement" % [int(seed_val), rest_soft])
			return false
		judged += 1
		if rest_soft > rest_bare + 0.001:
			better += 1
			sample_bare = rest_bare
			sample_soft = rest_soft
	if judged == 0:
		push_error("BED PAIRED: no seed sited a bed, so the pair has nothing to judge")
		return false
	if better != judged:
		push_error("BED PAIRED: over %d seeds the bedding changed the night on only %d of them -- the comfort reaches the component and not the quality" % [judged, better])
		return false

	print("BEDDING OK bare boards restore exactly what they always did (%.4f, %.4f and %.4f on the three pinned scenarios); a builder spends the better of two bedrolls and the bed keeps a plain float; over %d paired districts a cold night on a foam bedroll restored %.2f against the boards' %.2f" % [
		1.0, 1.0 - SimNeeds.SLEEP_PENALTY_TEMP_SOFT, 1.0 - SimNeeds.SLEEP_PENALTY_ROUGH, judged, sample_soft, sample_bare,
	])
	return true


# Soap: the second key, and the only headroom hygiene had. A wash reaches `clean` on water alone, so
# what a bar of soap buys is the dirtying afterwards that does not land. True positive, true
# negative, and an exhaustion case -- a bar is a day or two of grave-digging, never an exemption.
func _soap_buys_a_wash_that_lasts() -> bool:
	var w: Variant = _world_seeded(BED_SEEDS[0])
	var ent: int = int(w.player)

	# Without soap: a wash cleans, and the next dirtying lands immediately.
	var n: Dictionary = SimNeeds.of(w, ent)
	SimNeeds.dirt(w, ent, 2)
	if String(n.get("hygiene", "")) == "clean":
		push_error("SOAP: two bands of dirt left the body clean, so this lane has nothing to judge")
		return false
	if not SimNeeds.wash_at_source(w, ent):
		push_error("SOAP: a wash at the source was refused")
		return false
	if String(n.get("hygiene", "")) != "clean":
		push_error("SOAP: a wash did not reach `clean` (%s)" % String(n.get("hygiene", "")))
		return false
	if int(n.get("scrubbed", 0)) != 0:
		push_error("SOAP: a wash with no soap banked %d charges" % int(n.get("scrubbed", 0)))
		return false
	SimNeeds.dirt(w, ent, 1)
	if String(n.get("hygiene", "")) == "clean":
		push_error("SOAP: with nothing banked, a dirtying left the body clean anyway")
		return false

	# With soap: the same wash banks the grade's charges, and that many dirtyings leave the band
	# where it is. The charges then run out -- the negative that stops this being an exemption.
	var bar: int = _give(w, ent, SOAP_ID)
	if bar < 0:
		return false
	var charges: int = int(SimNeeds.HYGIENE_SCRUBS.get("scrub", 0))
	if charges <= 0:
		push_error("SOAP: the shipped bar is worth no charges, so there is nothing to spend")
		return false
	var pocket_before: int = SimInventory.carried_items(w, ent).size()
	if not SimNeeds.wash_at_source(w, ent):
		push_error("SOAP: a wash with soap in the pack was refused")
		return false
	if int(n.get("scrubbed", 0)) != charges:
		push_error("SOAP: a bar worth %d charges banked %d" % [charges, int(n.get("scrubbed", 0))])
		return false
	if SimInventory.carried_items(w, ent).size() != pocket_before - 1:
		push_error("SOAP: the bar was spent and is still in the pack")
		return false
	for i in charges:
		SimNeeds.dirt(w, ent, 1)
		if String(n.get("hygiene", "")) != "clean":
			push_error("SOAP: dirtying number %d got through %d banked charges" % [i + 1, charges])
			return false
	SimNeeds.dirt(w, ent, 1)
	if String(n.get("hygiene", "")) == "clean":
		push_error("SOAP: the charges never ran out -- a bar of soap is an exemption rather than a day")
		return false

	print("SOAP OK a wash with nothing banked is dirty again on the next job; a bar banks %d charges, is spent out of the pack, holds `clean` through %d dirtyings and is dirty on the one after" % [charges, charges])
	return true


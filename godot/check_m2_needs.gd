extends SceneTree
# Drain, bands, player eat/drink/wash/sleep/fire, HUD prose, Need hold.

const SimBoot = preload("res://sim/boot.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
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
	if ok:
		print("M2_NEEDS_OK drain bands verbs hud hold, low mood has consequences, food is content and can make you ill, a death costs the living, everybody has to go, a meal's mood wears off, the dead give back the bed, and the deep cold is reachable")
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


# "Arguments -- which damage other survivors' mood, so misery spreads." And the half that keeps it
# from being the meltdown docs/04 rules out: the damage is capped and it drains away.
func _arguments_spread_misery_and_stop_short_of_a_spiral() -> bool:
	var w: Variant = _world()
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
		w.step()
		# Hold both in place and the arguer miserable, so this measures arguing rather than the
		# job AI walking one of them out of earshot.
		there["x"] = float(at["x"]) + 1.0
		there["y"] = float(at["y"])
		_set_mood(w, arguer, SimNeeds.MOOD_MISERABLE - 5.0)

	if heard.is_empty():
		push_error("no argument in %d ticks with a miserable survivor standing next to somebody" % runs)
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
	var quiet: Array = []
	calm.events.subscribe({"type": "mood.argument", "id": "gate.calm", "handler": func(_e: Dictionary) -> void:
		quiet.append(1)
	})
	for ent4 in calm.components.query(["needs", "position"]):
		_set_mood(calm, int(ent4), 0.0)
	for _i in runs:
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

	print("FOOD CONTENT OK %d foods read from content with the retired table's numbers; canned has no clock, raw has %d ticks; three non-foods and a missing base all refuse" % [
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
func _an_npc_takes_itself_to_the_latrine() -> bool:
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
	# Every fire out, so the only warmth in question is the roof. A wrap would shift the band one
	# step toward comfortable, which is the wrap working -- but it is not what is under test here.
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = w.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == "item.wrap.cloth":
			SimInventory.unequip_item(w, item)
	if SimNeeds.wearing_wrap(w, ent):
		push_error("COLD: the survivor is still wearing a wrap, so the band under test is shifted")
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
		var base3: Variant = thawed.components.get_component(item3, "itemBase")
		if base3 is Dictionary and String((base3 as Dictionary).get("baseId", "")) == "item.wrap.cloth":
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

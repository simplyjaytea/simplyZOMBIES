extends SceneTree
# Drain, bands, player eat/drink/wash/sleep/fire, HUD prose, Need hold.

const SimBoot = preload("res://sim/boot.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
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
	if ok:
		print("M2_NEEDS_OK drain bands verbs hud hold, low mood has consequences, food is content and can make you ill")
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

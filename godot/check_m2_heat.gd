extends SceneTree
# The heat wave's clock, thirst and rot (docs/adr/0016, the owner's decision of 2026-09-06). The
# spine gate `godot:m2:weather` owns the sky itself -- the spans, the calendar, the wind, and the
# one band the shift is worth. This gate owns what the heat then costs, and it is the mirror of
# the cold's: heat is a dose, not a reading of the sky.
#
# What this gate holds down:
#  1. **The deep bands are reachable, and only the way they are meant to be.** A bare body in the
#     sun reads `a_little_hot` at once and `very_hot` after EXPOSURE_TICKS -- and never worse,
#     however long it stands there. `extremely_hot` is heatstroke, and it is what body armour in
#     a heat wave costs after twice that. Any roof clears the clock.
#  2. **Every reader is reached.** The thirst drain, the pantry's spoilage rate, the corpse's
#     scent, the mid-job interrupt and the three HUD sentences: the dead-socket rule. Each is
#     measured as an effect -- a pool that fell further, an `aged` that ran twice, a magnitude
#     published twice as loud, a job that is gone -- never as a helper returning a number.
#  3. **A true negative beside every positive.** The same world under `clear` is the control for
#     all of it, and where the rule has an edge (the sun alone, armour before the second dose,
#     a living body's scent, `very_hot` mid-job) the case on the other side of it is asserted too.
#
# Every number here is measured and printed. The bands are content-driven through
# `SimWeather.temp_shift`; EXPOSURE_TICKS is needs.gd's, shared with the cold.

const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")
const Hud = preload("res://ui/hud.gd")

const SEED: int = 20260906
const FAR: int = 1 << 40
const ARMOR_ID: String = "item.jacket.leather"
const WRAP_ID: String = "item.wrap.cloth"
# Noon on day one: full daylight, so the sky's shift applies and the night is not the relief.
const NOON: float = 0.4

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _the_sun_deepens_and_armour_is_punishing() and ok
	ok = _a_roof_clears_the_clock_and_a_wrap_buys_a_band() and ok
	ok = _thirst_runs_faster_in_the_heat() and ok
	ok = _food_rots_twice_as_fast() and ok
	ok = _the_dead_smell_twice_as_strong_and_the_living_do_not() and ok
	ok = _heatstroke_drops_the_tool() and ok
	ok = _the_hud_says_the_heat_in_words() and ok
	if ok:
		print("M2_HEAT_OK the heat wave costs: a hot clock that deepens to very hot and no further, heatstroke as the price of armour, thirst x1.5, food rotting x2, the dead smelling x2 and the living unchanged, the tool dropped at the deep band, and three sentences with no digits in them")
		quit(0)
	else:
		push_error("M2_HEAT_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# Through the one public path, so the event and the modifiers follow (weather.gd's set_kind).
func _force(w: Variant, k: String) -> void:
	SimWeather.set_kind(w, k, FAR)


func _tile_where(w: Variant, indoors: bool) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_indoors(w.tilemap, x, y) == indoors and not SimTileMap.is_solid(w.tilemap, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(w: Variant, ent: int, tile: Vector2i) -> void:
	w.components.set_component(ent, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})


# Every fire out and nothing on the torso, so the only thing moving the band is the sky and
# whatever this lane then puts on the body.
func _bare_body(w: Variant, ent: int) -> void:
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary and (base as Dictionary).has("armor"):
			SimInventory.unequip_item(w, int(item))


func _band(w: Variant, ent: int) -> String:
	return String(SimNeeds.of(w, ent).get("temperature", ""))


func _pools_full(w: Variant, ent: int) -> void:
	var n: Dictionary = SimNeeds.of(w, ent)
	for k in SimNeeds.POOLS:
		n[k] = 100.0
	n["crisis"] = "none"


# One body, one sky, one place, one garment, and a hot clock that has already been running for
# `baked` ticks. The clock is aged by writing its own field back rather than by stepping eighteen
# thousand times: `hotSinceTick` is the mechanism under test, and the tick after it is written
# re-reads it exactly as the tick before did.
func _reading(kind: String, where: String, gear: String, baked: int) -> Dictionary:
	var w: Variant = _world()
	var e: int = int(w.player)
	_bare_body(w, e)
	if gear != "":
		var item: int = SimItems.spawn_item(w, ARMOR_ID if gear == "armor" else WRAP_ID)
		if item < 0 or not SimInventory.equip(w, e, item):
			return {}
	w.tick = Clock.tick_on_day(1, NOON)
	_force(w, kind)
	var tile: Vector2i = _tile_where(w, where == "in")
	if tile.x < 0:
		return {}
	for i in 3:
		_place(w, e, tile)
		_pools_full(w, e)
		if i == 1 and baked > 0:
			SimNeeds.of(w, e)["hotSinceTick"] = int(w.tick) - baked
		w.step()
	return {
		"band": _band(w, e),
		"mood": float(w.modifiers.resolve("mood", e)),
		"work": SimNeeds.work_mul(w, e),
		"since": int(SimNeeds.of(w, e).get("hotSinceTick", -2)),
		"armored": SimNeeds.wearing_armor(w, e),
	}


# --- lanes --------------------------------------------------------------------------------

# REACHABLE. The ladder itself, every rung and every rung's absence.
func _the_sun_deepens_and_armour_is_punishing() -> bool:
	var exp_t: int = SimNeeds.EXPOSURE_TICKS
	var cases: Dictionary = {
		"clear/out/bare/0": ["clear", "out", "", 0],
		"clear/in/bare/0": ["clear", "in", "", 0],
		"heat/out/bare/0": ["heat_wave", "out", "", 0],
		"heat/in/bare/0": ["heat_wave", "in", "", 0],
		"heat/in/bare/2x": ["heat_wave", "in", "", 2 * exp_t + 2],
		"heat/out/bare/1x": ["heat_wave", "out", "", exp_t + 2],
		"heat/out/bare/2x": ["heat_wave", "out", "", 2 * exp_t + 2],
		"heat/out/armor/0": ["heat_wave", "out", "armor", 0],
		"heat/out/armor/1x": ["heat_wave", "out", "armor", exp_t + 2],
		"heat/out/armor/2x": ["heat_wave", "out", "armor", 2 * exp_t + 2],
		"clear/out/armor/2x": ["clear", "out", "armor", 2 * exp_t + 2],
	}
	var want: Dictionary = {
		"clear/out/bare/0": "comfortable",
		"clear/in/bare/0": "comfortable",
		"heat/out/bare/0": "a_little_hot",
		"heat/in/bare/0": "comfortable",
		# A roof is the whole relief: the clock does not even start under one.
		"heat/in/bare/2x": "comfortable",
		"heat/out/bare/1x": "very_hot",
		# The true negative for heatstroke: the sun alone never reaches it, however long.
		"heat/out/bare/2x": "very_hot",
		"heat/out/armor/0": "very_hot",
		# And armour alone does not either, until the dose has been doubled.
		"heat/out/armor/1x": "very_hot",
		"heat/out/armor/2x": "extremely_hot",
		# And none of it happens under a sky that is not hot.
		"clear/out/armor/2x": "comfortable",
	}
	var got: Dictionary = {}
	for name in cases.keys():
		var c: Array = cases[name] as Array
		var r: Dictionary = _reading(String(c[0]), String(c[1]), String(c[2]), int(c[3]))
		if r.is_empty():
			push_error("REACHABLE: could not build the case %s (no tile, or the gear would not equip)" % name)
			return false
		got[name] = r
		if String(r["band"]) != String(want[name]):
			push_error("REACHABLE: %s reads %s, wanted %s" % [name, String(r["band"]), String(want[name])])
			return false
	# The jacket is body armour and the wrap is not -- the coverage rule, asserted rather than
	# assumed, because the whole armour half hangs off it.
	if not bool((got["heat/out/armor/0"] as Dictionary)["armored"]):
		push_error("REACHABLE: the leather jacket does not read as body armour")
		return false
	var wrapped: Dictionary = _reading("heat_wave", "out", "wrap", 0)
	if wrapped.is_empty() or bool(wrapped["armored"]):
		push_error("REACHABLE: the cloth wrap reads as body armour: %s" % str(wrapped))
		return false
	# The deeper band costs something, or it is a word with nothing behind it.
	var shallow: Dictionary = got["heat/out/bare/0"] as Dictionary
	var deep: Dictionary = got["heat/out/bare/1x"] as Dictionary
	if float(deep["mood"]) >= float(shallow["mood"]) or float(deep["work"]) >= float(shallow["work"]):
		push_error("REACHABLE: very_hot costs no more than a_little_hot (mood %.2f vs %.2f, work %.3f vs %.3f)" % [float(deep["mood"]), float(shallow["mood"]), float(deep["work"]), float(shallow["work"])])
		return false
	var stroke: Dictionary = got["heat/out/armor/2x"] as Dictionary
	if float(stroke["mood"]) >= float(deep["mood"]):
		push_error("REACHABLE: heatstroke's mood %.2f is no worse than very_hot's %.2f" % [float(stroke["mood"]), float(deep["mood"])])
		return false
	print("REACHABLE OK a_little_hot in the sun, very_hot after %d ticks (mood %.1f vs %.1f, work %.2f vs %.2f) and no worse; armour reads very_hot at once and heatstroke at %d (mood %.1f); a roof, a clear sky and the wrap's own coverage are each the negative" % [exp_t, float(deep["mood"]), float(shallow["mood"]), float(deep["work"]), float(shallow["work"]), 2 * exp_t, float(stroke["mood"])])
	return true


# REACHABLE, continued: the clock is a clock -- one tick under a roof throws the dose away, and
# the wrap is still worth a band in the sun as it is at night.
func _a_roof_clears_the_clock_and_a_wrap_buys_a_band() -> bool:
	var w: Variant = _world()
	var e: int = int(w.player)
	_bare_body(w, e)
	w.tick = Clock.tick_on_day(1, NOON)
	_force(w, "heat_wave")
	var out: Vector2i = _tile_where(w, false)
	var inside: Vector2i = _tile_where(w, true)
	if out.x < 0 or inside.x < 0:
		push_error("ROOF: no outdoor or no indoor tile")
		return false
	for i in 3:
		_place(w, e, out)
		_pools_full(w, e)
		if i == 1:
			SimNeeds.of(w, e)["hotSinceTick"] = int(w.tick) - (SimNeeds.EXPOSURE_TICKS + 2)
		w.step()
	var hot_band: String = _band(w, e)
	var running: int = int(SimNeeds.of(w, e).get("hotSinceTick", -1))
	_place(w, e, inside)
	w.step()
	var after: int = int(SimNeeds.of(w, e).get("hotSinceTick", -1))
	var after_band: String = _band(w, e)
	if hot_band != "very_hot" or running < 0:
		push_error("ROOF: the body was not baking outdoors first (%s, clock %d)" % [hot_band, running])
		return false
	if after != -1 or after_band != "comfortable":
		push_error("ROOF: one tick indoors left the clock at %d and the band at %s" % [after, after_band])
		return false
	# And back out: the dose starts again from this tick, not from the one it was thrown away at.
	_place(w, e, out)
	w.step()
	var restarted: int = int(SimNeeds.of(w, e).get("hotSinceTick", -1))
	if restarted < running:
		push_error("ROOF: the clock resumed at %d rather than restarting (was %d)" % [restarted, running])
		return false
	if _band(w, e) != "a_little_hot":
		push_error("ROOF: back in the sun the body reads %s rather than a_little_hot" % _band(w, e))
		return false
	var bare: Dictionary = _reading("heat_wave", "out", "", 0)
	var wrapped: Dictionary = _reading("heat_wave", "out", "wrap", 0)
	if bare.is_empty() or wrapped.is_empty():
		push_error("ROOF: could not read the wrap case")
		return false
	if String(bare["band"]) != "a_little_hot" or String(wrapped["band"]) != "comfortable":
		push_error("ROOF: the wrap reads %s where a bare body reads %s" % [String(wrapped["band"]), String(bare["band"])])
		return false
	print("ROOF OK the clock ran to %d ticks outdoors (very_hot), one tick under a roof cleared it to -1 and the band to comfortable, and it restarted at %d on the way back out; a wrap reads comfortable where a bare body reads a_little_hot" % [int(w.tick) - running, restarted])
	return true


# THIRST. The pool, measured, not the multiplier.
func _thirst_runs_faster_in_the_heat() -> bool:
	var ticks: int = 600
	var drops: Dictionary = {}
	for k in ["clear", "heat_wave"]:
		var w: Variant = _world()
		var e: int = int(w.player)
		w.tick = Clock.tick_on_day(1, NOON)
		_force(w, k)
		var inside: Vector2i = _tile_where(w, true)
		_place(w, e, inside)
		var n: Dictionary = SimNeeds.of(w, e)
		n["thirst"] = 100.0
		var before: float = 100.0
		for _i in ticks:
			w.step()
		drops[k] = before - float(SimNeeds.of(w, e).get("thirst", 0.0))
	var clear_drop: float = float(drops["clear"])
	var heat_drop: float = float(drops["heat_wave"])
	var one_tick: float = SimNeeds.drain_thirst() * 1.5
	var want: float = clear_drop * SimWeather.thirst_mul(_a_forced_world("heat_wave"))
	if clear_drop <= 0.0:
		push_error("THIRST: nothing drained under a clear sky, so there is nothing to compare")
		return false
	if absf(heat_drop - want) > one_tick:
		push_error("THIRST: %d ticks drop %.4f under heat and %.4f under clear (wanted %.4f, tolerance %.4f)" % [ticks, heat_drop, clear_drop, want, one_tick])
		return false
	# The true negative on the other side: a clear sky is the identity, so it equals the drain a
	# world with no weather at all would have taken.
	var plain: float = float(ticks) * SimNeeds.drain_thirst()
	if absf(clear_drop - plain) > one_tick:
		push_error("THIRST: a clear sky is not the identity -- %.4f drained where the bare drain is %.4f" % [clear_drop, plain])
		return false
	print("THIRST OK %d ticks drain %.4f under a heat wave and %.4f under clear (x%.2f, the content's %.2f); clear equals the bare drain %.4f" % [ticks, heat_drop, clear_drop, heat_drop / clear_drop, SimWeather.thirst_mul(_a_forced_world("heat_wave")), plain])
	return true


func _a_forced_world(kind: String) -> Variant:
	var w: Variant = _world()
	_force(w, kind)
	return w


# ROT. One perishable, two skies, the same thousand ticks.
func _food_rots_twice_as_fast() -> bool:
	var ticks: int = 1000
	var aged: Dictionary = {}
	var rates: Dictionary = {}
	for k in ["clear", "heat_wave"]:
		var w: Variant = _world()
		w.tick = Clock.tick_on_day(1, NOON)
		_force(w, k)
		var item: int = SimItems.spawn_item(w, WRAP_ID)
		if item < 0:
			push_error("ROT: could not spawn something to rot")
			return false
		w.components.set_component(item, "spoilage", {"bornTick": int(w.tick), "spoilTicks": 1 << 30, "spoiled": false, "aged": 0.0})
		rates[k] = SimNeeds.pantry_rate(w)
		for _i in ticks:
			w.step()
		var sp: Variant = w.components.get_component(item, "spoilage")
		if not sp is Dictionary:
			push_error("ROT: the spoilage record is gone")
			return false
		aged[k] = float((sp as Dictionary).get("aged", 0.0))
	var clear_aged: float = float(aged["clear"])
	var heat_aged: float = float(aged["heat_wave"])
	var pantry: float = float(rates["clear"])
	if clear_aged <= 0.0:
		push_error("ROT: nothing aged under a clear sky")
		return false
	if absf(clear_aged - float(ticks) * pantry) > pantry:
		push_error("ROT: a clear sky aged %.3f where the pantry rate %.3f over %d ticks is %.3f" % [clear_aged, pantry, ticks, float(ticks) * pantry])
		return false
	var mul: float = SimWeather.spoilage_mul(_a_forced_world("heat_wave"))
	if absf(heat_aged - clear_aged * mul) > pantry * mul:
		push_error("ROT: a heat wave aged %.3f where clear x%.2f is %.3f" % [heat_aged, mul, clear_aged * mul])
		return false
	print("ROT OK %d ticks age a perishable %.1f under a heat wave and %.1f under clear (x%.2f); clear is exactly the pantry rate %.3f" % [ticks, heat_aged, clear_aged, heat_aged / clear_aged, pantry])
	return true


# CORPSE. The magnitude actually published, for the dead body and for a living one beside it.
func _the_dead_smell_twice_as_strong_and_the_living_do_not() -> bool:
	var ticks: int = 61
	var dead: Dictionary = {}
	var living: Dictionary = {}
	for k in ["clear", "heat_wave"]:
		var w: Variant = _world()
		var e: int = int(w.player)
		var npc: int = -1
		for ent in w.components.query(["needs", "velocity"]):
			if int(ent) != e and not w.components.has_component(int(ent), "corpse"):
				npc = int(ent)
				break
		if npc < 0:
			push_error("CORPSE: no body to kill")
			return false
		w.tick = Clock.tick_on_day(1, NOON)
		_force(w, k)
		var out: Vector2i = _tile_where(w, false)
		var body_tile := Vector2i(out.x, out.y)
		var mine := Vector2i(out.x + 8, out.y + 8)
		_place(w, npc, body_tile)
		_place(w, e, mine)
		SimRecruits._make_corpse(w, npc)
		# An Array, not a float: a lambda capturing a primitive mutates its own copy (CLAUDE.md).
		var tally: Array = [0.0, 0.0]
		w.events.subscribe({"id": "gate.heat.scent", "type": "scent.accumulated", "handler": func(ev: Dictionary) -> void:
			var x: float = float(ev.get("x", 0.0))
			var y: float = float(ev.get("y", 0.0))
			if absf(x - (float(body_tile.x) + 0.5)) < 0.6 and absf(y - (float(body_tile.y) + 0.5)) < 0.6:
				tally[0] = float(tally[0]) + float(ev.get("magnitude", 0.0))
			elif absf(x - (float(mine.x) + 0.5)) < 0.6 and absf(y - (float(mine.y) + 0.5)) < 0.6:
				tally[1] = float(tally[1]) + float(ev.get("magnitude", 0.0))
		})
		for _i in ticks:
			_place(w, npc, body_tile)
			_place(w, e, mine)
			w.step()
		dead[k] = float(tally[0])
		living[k] = float(tally[1])
	var clear_dead: float = float(dead["clear"])
	var heat_dead: float = float(dead["heat_wave"])
	var clear_living: float = float(living["clear"])
	var heat_living: float = float(living["heat_wave"])
	if clear_dead <= 0.0 or clear_living <= 0.0:
		push_error("CORPSE: nothing was published for the dead (%.2f) or the living (%.2f) -- there is nothing to judge" % [clear_dead, clear_living])
		return false
	var mul: float = SimWeather.corpse_scent_mul(_a_forced_world("heat_wave"))
	if absf(heat_dead - clear_dead * mul) > 0.001:
		push_error("CORPSE: the dead publish %.3f under heat where clear x%.2f is %.3f" % [heat_dead, mul, clear_dead * mul])
		return false
	if absf(heat_living - clear_living) > 0.001:
		push_error("CORPSE: a living body publishes %.3f under heat and %.3f under clear -- the multiplier reached the wrong bodies" % [heat_living, clear_living])
		return false
	print("CORPSE OK over %d ticks a corpse publishes %.1f of scent under a heat wave and %.1f under clear (x%.2f), while the living body beside it publishes %.1f under both" % [ticks, heat_dead, clear_dead, heat_dead / clear_dead, heat_living])
	return true


# INTERRUPT. The deep band is hard: it drops the tool mid-action the way freezing does, and the
# band above it does not.
func _heatstroke_drops_the_tool() -> bool:
	var results: Dictionary = {}
	for want_band in ["very_hot", "extremely_hot"]:
		var w: Variant = _world()
		var npc: int = -1
		for ent in w.components.query(["needs", "velocity", "jobPriorities"]):
			if int(ent) != int(w.player) and not w.components.has_component(int(ent), "corpse"):
				npc = int(ent)
				break
		if npc < 0:
			push_error("INTERRUPT: no NPC with a job list")
			return false
		_bare_body(w, npc)
		var item: int = SimItems.spawn_item(w, ARMOR_ID)
		if item < 0 or not SimInventory.equip(w, npc, item):
			push_error("INTERRUPT: could not put armour on the body")
			return false
		w.tick = Clock.tick_on_day(1, NOON)
		_force(w, "heat_wave")
		var out: Vector2i = _tile_where(w, false)
		_place(w, npc, out)
		_pools_full(w, npc)
		w.components.remove(npc, "job")
		w.step()
		# The dose: none for very_hot (armour alone is worth that band), twice the exposure for
		# heatstroke. Written to the clock, read back by the next tick.
		if want_band == "extremely_hot":
			SimNeeds.of(w, npc)["hotSinceTick"] = int(w.tick) - (2 * SimNeeds.EXPOSURE_TICKS + 2)
		_place(w, npc, out)
		_pools_full(w, npc)
		# A stand-in job with a channel: Patient's arm does nothing but stand, which is what Guard's
		# did when this lane was written. Guard is a dusk-to-dawn post since 2026-09-06 and its arm
		# completes the watch by day, so at noon it could not be the job that "works through" a band.
		w.components.set_component(npc, "job", {"kind": "Patient", "tx": out.x, "ty": out.y, "ticksLeft": 500, "path": [], "pathGen": -1})
		# Twice, and the second one is the assertion: `jobs.ai` runs in the `ai` phase and
		# `need.temperature` in `needs`, so the tick that first writes the deep band is a tick
		# jobs has already spent reading the band before it. The interrupt lands on the next one.
		w.step()
		_place(w, npc, out)
		_pools_full(w, npc)
		w.step()
		var band: String = _band(w, npc)
		var job: Variant = w.components.get_component(npc, "job")
		var kind: String = String((job as Dictionary).get("kind", "")) if job is Dictionary else ""
		results[want_band] = {"band": band, "job": kind}
		if band != want_band:
			push_error("INTERRUPT: wanted the body at %s, it reads %s" % [want_band, band])
			return false
	var deep: Dictionary = results["extremely_hot"] as Dictionary
	var soft: Dictionary = results["very_hot"] as Dictionary
	if String(deep["job"]) == "Patient":
		push_error("INTERRUPT: heatstroke did not drop the job: %s" % str(deep))
		return false
	if String(soft["job"]) != "Patient":
		push_error("INTERRUPT: very_hot dropped a job it should have worked through: %s" % str(soft))
		return false
	print("INTERRUPT OK a body at extremely_hot drops a job with 500 ticks left (job now '%s'); the same body at very_hot works on" % [String(deep["job"]) if String(deep["job"]) != "" else "none"])
	return true


# HUD. Three sentences, in the ranks the cold half already uses, reaching the screen, with no
# digit in any of them.
func _the_hud_says_the_heat_in_words() -> bool:
	var w: Variant = _world()
	w.step()
	var e: int = int(w.player)
	var said: Dictionary = {}
	for band in ["a_little_hot", "very_hot", "extremely_hot"]:
		var n: Dictionary = SimNeeds.of(w, e)
		n["temperature"] = band
		n["hygiene"] = "clean"
		for k in SimNeeds.POOLS:
			n[k] = 100.0
		n["crisis"] = "none"
		var line: String = SimNeeds.hud_clause(w, e)
		if line.is_empty():
			push_error("HUD: %s says nothing" % band)
			return false
		for ch in line:
			if String(ch).is_valid_int():
				push_error("HUD: the %s line carries a digit: '%s'" % [band, line])
				return false
		if said.values().has(line):
			push_error("HUD: two bands share the sentence '%s'" % line)
			return false
		said[band] = line
	# The ranks, proved against a need whose own ranks are known: hunger at 70 is peckish (rank
	# 22) and hunger at 20 is hungry (rank 12), both from `_hud_need` above.
	# a_little_hot (24) loses to both, very_hot (14) beats peckish and loses to hungry, and
	# heatstroke (4) beats everything either of them can say.
	var ladder: Array = [
		["a_little_hot", 70.0, false], ["very_hot", 70.0, true], ["extremely_hot", 70.0, true],
		["a_little_hot", 20.0, false], ["very_hot", 20.0, false], ["extremely_hot", 20.0, true],
	]
	for row in ladder:
		var band: String = String((row as Array)[0])
		var hunger: float = float((row as Array)[1])
		var wins: bool = bool((row as Array)[2])
		var n2: Dictionary = SimNeeds.of(w, e)
		n2["temperature"] = band
		n2["hunger"] = hunger
		n2["crisis"] = "none"
		var line2: String = SimNeeds.hud_clause(w, e)
		if (line2 == String(said[band])) != wins:
			push_error("HUD: with hunger %.0f the %s line %s the say, and it should%s have ('%s')" % [hunger, band, "took" if line2 == String(said[band]) else "lost", "" if wins else " not", line2])
			return false
	# And it reaches the screen: the self column carries the deepest of them.
	var n3: Dictionary = SimNeeds.of(w, e)
	n3["temperature"] = "extremely_hot"
	n3["hunger"] = 90.0
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, e, "")
	var left: Array = (hud.get("_left") as Array).duplicate()
	hud.queue_free()
	if not left.has(String(said["extremely_hot"])):
		push_error("HUD: the self column does not carry '%s': %s" % [String(said["extremely_hot"]), str(left)])
		return false
	print("HUD OK three sentences (%s), each ranked against hunger's own two, none with a digit, and the deepest reaches the self column" % str(said.values()))
	return true

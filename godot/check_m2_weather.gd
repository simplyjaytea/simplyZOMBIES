extends SceneTree
# The sky has kinds (docs/adr/0016, 2026-09-06), widening docs/adr/0015's one rain flag: at any
# tick the world is under one weather kind -- clear, rain, storm, cold_snap, snow, heat_wave --
# drawn as spans on the world's own `weather` stream from one content entry per kind, against a
# calendar (`climate/temperate.json`) whose seasons weight the draw. A non-clear span is always
# followed by clear, and the first is always clear. Wind is a direction that drifts daily and
# leans the scent field. This gate is the spine's: the storm, cold and heat slices hold their
# own effects in `godot:m2:storm`, `godot:m2:cold` and `godot:m2:heat`.
#
# What this gate holds down:
#  1. **Nothing but clear in a fixture that never asked for weather**, and a booted world starts
#     clear. Every other gate in the chain boots a world, and none of them is about the sky.
#  2. **Every reader is reached.** The temperature band and the mood behind it, the scent on the
#     field, the wind in the field's weights, the modifier on a living body and the speed of a
#     dead one, the HUD line and (textually, in check_weather.gd) the draw call: the dead-socket
#     rule.
#  3. **The calendar is read.** A kind weighted zero in a season is never drawn there, and the
#     same seed under a different season length draws a different sky.
#  4. **Assert the effect, never the mechanism** where an effect exists: mood resolved lower on
#     the wet body, scent measured lower on the raining field and downwind of the source, an
#     NPC's velocity measured slower on the snow.
#
# Every assertion carries a true negative beside its positive.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimPath = preload("res://sim/path.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const ContentValidator = preload("res://platform/content_validator.gd")
const Hud = preload("res://ui/hud.gd")

const SEED: int = 20260805
const FAR: int = 1 << 40

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _the_kinds_are_content_and_the_validator_sees_them() and ok
	ok = _it_starts_clear_and_kinds_come_and_go_inside_their_ranges() and ok
	ok = _the_calendar_is_read() and ok
	ok = _the_sky_survives_a_save() and ok
	ok = _the_schedule_is_the_seeds() and ok
	ok = _a_body_in_the_rain_gets_wet_and_dries_by_a_fire() and ok
	ok = _a_wet_body_reads_one_band_colder() and ok
	ok = _the_sky_shifts_the_band() and ok
	ok = _rain_washes_scent_off_the_field() and ok
	ok = _the_wind_leans_the_field() and ok
	ok = _the_sky_slows_the_living_and_the_dead() and ok
	ok = _a_hot_body_seeks_a_roof_and_a_cold_one_a_fire() and ok
	ok = _the_hud_names_the_sky_and_nothing_when_clear() and ok
	if ok:
		print("M2_WEATHER_OK the sky has kinds: drawn on its own stream against a calendar, clear between spells, a wind that leans the field, wet bodies one band colder, a cold snap's shift and a heat wave's, the living and the dead slowed, and one sentence a kind")
		quit(0)
	else:
		push_error("M2_WEATHER_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# Through the one public path, so the event, the modifier and the wind all follow.
func _force(w: Variant, k: String) -> void:
	SimWeather.set_kind(w, k, FAR)


func _tile_where(w: Variant, indoors: bool) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_indoors(w.tilemap, x, y) == indoors:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(w: Variant, ent: int, tile: Vector2i) -> void:
	w.components.set_component(ent, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})


# Every fire out and no wrap, so the only thing moving the band is the sky.
func _bare_body(w: Variant, ent: int) -> bool:
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = w.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == "item.wrap.cloth":
			SimInventory.unequip_item(w, item)
	return not SimNeeds.wearing_wrap(w, ent)


func _band(w: Variant, ent: int) -> String:
	return String(SimNeeds.of(w, ent).get("temperature", ""))


# Jump the clock to just before the next flip and step through it; returns the spans seen as
# {tick, kind, span, season}.
func _walk_spans(w: Variant, days: int) -> Array:
	var flips: Array = []
	var stop: int = int(w.tick) + days * Clock.DAY_TICKS
	var guard: int = 0
	while int(w.tick) < stop and guard < 400:
		guard += 1
		var until: int = int((w.weather as Dictionary).get("untilTick", 0))
		if until <= int(w.tick):
			w.step()
			continue
		w.tick = until - 1
		var was: String = SimWeather.kind(w)
		w.step()
		w.step()
		if SimWeather.kind(w) != was or int((w.weather as Dictionary).get("untilTick", 0)) > int(w.tick):
			flips.append({"tick": int(w.tick), "kind": SimWeather.kind(w), "span": int((w.weather as Dictionary).get("untilTick", 0)) - int(w.tick), "season": SimWeather.season_of(w)})
	return flips


func _range_of(w: Variant, k: String) -> Dictionary:
	return SimWeather.spec_of(w, k).get("durationTicks", {}) as Dictionary


# --- lanes --------------------------------------------------------------------------------

func _the_kinds_are_content_and_the_validator_sees_them() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var w: Variant = _world()
	var names: Array[String] = SimWeather.kinds(w)
	if names.size() < 6 or not names.has("clear") or not names.has("rain"):
		push_error("CONTENT: the tree declares %s, wanted at least the six shipped kinds" % str(names))
		return false
	var drawable: Dictionary = {}
	for k in names:
		var entry: Variant = tree.get(SimWeather.CONTENT_DIR + k + ".json")
		if not (entry is Dictionary) or String((entry as Dictionary).get("id", "")) != "weather." + k:
			push_error("CONTENT: weather/%s.json is not loaded as weather.%s: %s" % [k, k, str(entry)])
			return false
		var e: Dictionary = entry as Dictionary
		var r: Dictionary = e.get("durationTicks", {}) as Dictionary
		if int(r.get("min", 0)) <= 0 or int(r.get("min", 0)) >= int(r.get("max", 0)):
			push_error("CONTENT: %s's range is not 0 < min < max: %s" % [k, str(r)])
			return false
		for season in SimWeather.SEASONS:
			var wt: float = SimWeather.weight_of(w, k, season)
			if wt < 0.0:
				push_error("CONTENT: %s weighs %.2f in %s" % [k, wt, season])
				return false
			if wt > 0.0 and k != "clear":
				drawable[season] = true
		for key in ["scentHalfLifeMul", "noiseHalfLifeMul", "zombieMoveMul"]:
			if e.has(key) and (float(e[key]) <= 0.0 or float(e[key]) > 1.0):
				push_error("CONTENT: %s's %s %.3f is outside (0, 1]" % [k, key, float(e[key])])
				return false
		if e.has("lightning"):
			var mag: float = float(((e["lightning"] as Dictionary).get("noise", 0.0)))
			if mag == 180.0 or mag == 120.0 or mag == 4.0:
				push_error("CONTENT: %s's lightning is magnitude %.0f, which sfx.gd would play as a gun, a shout or a bow" % [k, mag])
				return false
		# The booted world reads the entry and not the mirrored default, and the two agree.
		var mine: Dictionary = SimWeather.DEFAULTS.get(k, {}) as Dictionary
		if SimWeather.spec_of(w, k) == mine and not mine.is_empty():
			push_error("CONTENT: the booted world reads SimWeather.DEFAULTS[%s] rather than the content entry" % k)
			return false
		if not mine.is_empty() and not _same_numbers(mine, e):
			push_error("CONTENT: the mirrored default for %s drifted from content:\n %s\n %s" % [k, JSON.stringify(mine), JSON.stringify(e)])
			return false
	for season in SimWeather.SEASONS:
		if not drawable.has(season):
			push_error("CONTENT: nothing but clear can be drawn in %s" % season)
			return false
	# The climate: the calendar is four seasons in some order, the drying timings ordered.
	var climate: Variant = tree.get(SimWeather.CLIMATE_PATH)
	if not (climate is Dictionary) or String((climate as Dictionary).get("id", "")) != "climate.temperate":
		push_error("CONTENT: %s is not loaded as climate.temperate" % SimWeather.CLIMATE_PATH)
		return false
	var c: Dictionary = climate as Dictionary
	# Duplicated before the sort: an Array is a reference, and sorting the tree's own would
	# re-order every calendar read after it.
	var order: Array = (c.get("seasonOrder", []) as Array).duplicate()
	order.sort()
	if order != ["autumn", "spring", "summer", "winter"] or not SimWeather.SEASONS.has(String(c.get("startSeason", ""))):
		push_error("CONTENT: the calendar is %s from %s" % [str(c.get("seasonOrder")), str(c.get("startSeason"))])
		return false
	var after: int = int(c.get("wetAfterTicks", 0))
	var fire: int = int(c.get("dryByFireTicks", 0))
	var air: int = int(c.get("dryAfterTicks", 0))
	if not (after > 0 and after < fire and fire < air):
		push_error("CONTENT: wetAfterTicks < dryByFireTicks < dryAfterTicks does not hold: %d %d %d" % [after, fire, air])
		return false
	var thr: float = float(c.get("snowCoverThreshold", 0.0))
	if thr <= 0.0 or thr >= 1.0:
		push_error("CONTENT: snowCoverThreshold %.2f is not inside (0, 1)" % thr)
		return false
	if SimWeather.climate(w) == SimWeather.CLIMATE_DEFAULTS:
		push_error("CONTENT: the booted world reads CLIMATE_DEFAULTS rather than the content entry")
		return false
	if not _same_numbers(SimWeather.CLIMATE_DEFAULTS, c):
		push_error("CONTENT: the mirrored climate default drifted from content:\n %s\n %s" % [JSON.stringify(SimWeather.CLIMATE_DEFAULTS), JSON.stringify(c)])
		return false
	# Both validators are registered for both types: the shipped entries raise nothing, and a
	# fabricated entry with a stray top-level key raises exactly one issue for it.
	var issues: Array[String] = ContentValidator.validate_tree()
	for issue in issues:
		if String(issue).contains("weather/") or String(issue).contains("climate/"):
			push_error("CONTENT: the validator reports %s" % issue)
			return false
	var schemas: Dictionary = ContentValidator._load_schemas()
	for type_id in ["weather", "climate"]:
		if not schemas.has(type_id):
			push_error("CONTENT: no %s schema is registered, so the directory validates in silence" % type_id)
			return false
	var bad: Dictionary = (tree.get("weather/rain.json") as Dictionary).duplicate(true)
	bad["forecast"] = "sunny"
	if ContentValidator._validate_shape(bad, schemas["weather"] as Dictionary, "weather/fake.json").is_empty():
		push_error("CONTENT: a fabricated weather entry with a stray key raised nothing")
		return false
	var bad_c: Dictionary = c.duplicate(true)
	bad_c["forecast"] = "sunny"
	if ContentValidator._validate_shape(bad_c, schemas["climate"] as Dictionary, "climate/fake.json").is_empty():
		push_error("CONTENT: a fabricated climate entry with a stray key raised nothing")
		return false
	if ContentValidator._type_of_path("climate/temperate.json") != "climate":
		push_error("CONTENT: climate/ resolves to type '%s'" % ContentValidator._type_of_path("climate/temperate.json"))
		return false
	print("CONTENT OK %d kinds loaded (%s), every range ordered, every season drawable, drying %d < %d < %d, both schemas registered and a stray key refused in each" % [names.size(), ", ".join(names), after, fire, air])
	return true


# The mirror and the JSON entry compared as what they mean: every number, bool and list the
# mirror holds equal in the entry within a tolerance, ints as floats -- the parser hands back
# floats where the mirror holds ints -- and the entry's id and description ignored.
func _same_numbers(mine: Dictionary, theirs: Dictionary) -> bool:
	for k in mine.keys():
		var a: Variant = mine[k]
		var b: Variant = theirs.get(k)
		if a is Dictionary:
			if not (b is Dictionary) or not _same_numbers(a as Dictionary, b as Dictionary):
				return false
		elif a is bool:
			if not (b is bool) or bool(a) != bool(b):
				return false
		elif a is int or a is float:
			if not (b is int or b is float) or absf(float(a) - float(b)) > 0.000000001:
				return false
		elif a is Array:
			if not (b is Array) or str(a) != str(b):
				return false
		elif str(a) != str(b):
			return false
	for k in theirs.keys():
		if String(k) != "id" and String(k) != "description" and not mine.has(k):
			return false
	return true


func _it_starts_clear_and_kinds_come_and_go_inside_their_ranges() -> bool:
	var w: Variant = _world()
	if SimWeather.kind(w) != "clear" or SimWeather.raining(w):
		push_error("SCHEDULE: the booted world is under %s at tick 0" % SimWeather.kind(w))
		return false
	var born: int = int(w.tick)
	w.step()
	if SimWeather.kind(w) != "clear":
		push_error("SCHEDULE: the first span is %s, not clear" % SimWeather.kind(w))
		return false
	var clear_r: Dictionary = _range_of(w, "clear")
	# Measured from the tick the world was born on -- a playable world boots at dawn, not at 0.
	var first_span: int = int((w.weather as Dictionary).get("untilTick", 0)) - born
	if first_span < int(clear_r["min"]) or first_span > int(clear_r["max"]) + 1:
		push_error("SCHEDULE: the first clear span is %d ticks, outside [%d, %d]" % [first_span, int(clear_r["min"]), int(clear_r["max"])])
		return false
	# A booted world stepped a short while stays clear: every other gate's world is safe.
	for _i in 999:
		w.step()
	if SimWeather.kind(w) != "clear":
		push_error("SCHEDULE: %s inside the first thousand ticks" % SimWeather.kind(w))
		return false
	# Forty days on two seeds: every span inside its kind's range, every non-clear span followed
	# by clear, and every kind the calendar can draw in a season it met drawn at least once.
	var seen: Dictionary = {}
	var seasons_met: Dictionary = {}
	var spans: int = 0
	var non_clear: int = 0
	for sd in [SEED, 90210]:
		var ww: Variant = _world(int(sd))
		var flips: Array = _walk_spans(ww, 40)
		var prev: String = "clear"
		for f in flips:
			var fd: Dictionary = f as Dictionary
			var k: String = String(fd["kind"])
			var span: int = int(fd["span"])
			var r: Dictionary = _range_of(ww, k)
			if span < int(r["min"]) or span > int(r["max"]):
				push_error("SCHEDULE: a %s span of %d ticks is outside [%d, %d]" % [k, span, int(r["min"]), int(r["max"])])
				return false
			if prev != "clear" and k != "clear":
				push_error("SCHEDULE: %s followed %s without a clear between" % [k, prev])
				return false
			prev = k
			spans += 1
			if k != "clear":
				non_clear += 1
				seen[k] = true
			seasons_met[String(fd["season"])] = true
	if spans < 8 or non_clear < 3:
		push_error("SCHEDULE: eighty days saw %d spans and %d spells" % [spans, non_clear])
		return false
	var missing: Array[String] = []
	for k in SimWeather.kinds(w):
		if k == "clear":
			continue
		var could: bool = false
		for season in seasons_met.keys():
			if SimWeather.weight_of(w, k, String(season)) > 0.0:
				could = true
		if could and not seen.has(k):
			missing.append(k)
	if not missing.is_empty():
		push_error("SCHEDULE: eighty days across %s never drew %s, which the calendar could have" % [str(seasons_met.keys()), str(missing)])
		return false
	# A kernel-less fixture that never registered the module stays clear, and grows no weather
	# state -- the shape every treatment, wounds and recovery world has.
	var bare: Variant = World.new({
		"seed": SEED, "tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	})
	for _j in 1000:
		bare.step()
	if SimWeather.kind(bare) != "clear" or SimWeather.raining(bare) or not (bare.weather as Dictionary).is_empty():
		push_error("SCHEDULE: a bare fixture left clear, or grew weather state: %s" % str(bare.weather))
		return false
	# And every kind can be read back, so the negatives above are not a reader that always says clear.
	for k in SimWeather.kinds(w):
		var forced: Variant = _world()
		_force(forced, k)
		if SimWeather.kind(forced) != k:
			push_error("SCHEDULE: a forced %s reads %s" % [k, SimWeather.kind(forced)])
			return false
		if SimWeather.raining(forced) != bool(SimWeather.spec_of(forced, k).get("wets", false)):
			push_error("SCHEDULE: `raining` under %s disagrees with its content" % k)
			return false
	print("SCHEDULE OK clear at boot and for a thousand ticks, %d spans over eighty days on two seeds (%d spells: %s) across %s, every span inside its range and clear between every two; a bare fixture never leaves clear" % [spans, non_clear, str(seen.keys()), str(seasons_met.keys())])
	return true


# The calendar is read twice over: a kind weighted zero in a season is never drawn in it, and the
# same seed under a shorter season draws a different sky -- against the true negative of the same
# seed under the same calendar drawing the same one.
func _the_calendar_is_read() -> bool:
	var w: Variant = _world()
	if SimWeather.season_at(w, 0) != "spring" or SimWeather.season_at(w, Clock.tick_on_day(5, 0.5)) != "spring" or SimWeather.season_at(w, Clock.tick_on_day(6, 0.5)) != "summer" or SimWeather.season_at(w, Clock.tick_on_day(21, 0.5)) != "spring":
		push_error("SEASONS: the calendar reads day 1 %s, day 5 %s, day 6 %s, day 21 %s" % [SimWeather.season_at(w, 0), SimWeather.season_at(w, Clock.tick_on_day(5, 0.5)), SimWeather.season_at(w, Clock.tick_on_day(6, 0.5)), SimWeather.season_at(w, Clock.tick_on_day(21, 0.5))])
		return false
	var zero_hits: int = 0
	var draws: int = 0
	for sd in [SEED, 404, 90210]:
		var ww: Variant = _world(int(sd))
		for f in _walk_spans(ww, 40):
			var fd: Dictionary = f as Dictionary
			var k: String = String(fd["kind"])
			if k == "clear":
				continue
			draws += 1
			if SimWeather.weight_of(ww, k, String(fd["season"])) <= 0.0:
				zero_hits += 1
				push_error("SEASONS: %s drawn in %s where it weighs zero" % [k, String(fd["season"])])
	if zero_hits > 0 or draws < 6:
		push_error("SEASONS: %d draws, %d against a zero weight" % [draws, zero_hits])
		return false
	# A kind pinned to zero everywhere is never drawn; restored, it is -- the weight is the
	# thing being read and not the kind's presence in the tree.
	var pinned: Variant = _world()
	var rain: Dictionary = (pinned.content["weather/rain.json"] as Dictionary).duplicate(true)
	rain["weights"] = {"spring": 0, "summer": 0, "autumn": 0, "winter": 0}
	pinned.content["weather/rain.json"] = rain
	var pinned_rain: int = 0
	var free_rain: int = 0
	for f in _walk_spans(pinned, 40):
		if String((f as Dictionary)["kind"]) == "rain":
			pinned_rain += 1
	for f in _walk_spans(_world(), 40):
		if String((f as Dictionary)["kind"]) == "rain":
			free_rain += 1
	if pinned_rain != 0 or free_rain == 0:
		push_error("SEASONS: rain weighted zero was drawn %d times; weighted as shipped %d times" % [pinned_rain, free_rain])
		return false
	# The season length: one day a season on the same seed draws a different schedule.
	var short: Variant = _world()
	var climate: Dictionary = (short.content[SimWeather.CLIMATE_PATH] as Dictionary).duplicate(true)
	climate["seasonDays"] = 1
	short.content[SimWeather.CLIMATE_PATH] = climate
	var same: Variant = _world()
	var fs: Array = _walk_spans(short, 40)
	var fa: Array = _walk_spans(_world(), 40)
	var fb: Array = _walk_spans(same, 40)
	if str(fa) != str(fb):
		push_error("SEASONS: two worlds on one seed and one calendar drew different skies")
		return false
	if str(fs) == str(fa):
		push_error("SEASONS: a one-day season drew the five-day season's sky, so seasonDays is read by nothing")
		return false
	print("SEASONS OK day 1..5 spring, 6 summer, 21 spring again; %d draws on three seeds none against a zero weight; rain weighted zero never falls (%d as shipped); a one-day season changes the sky" % [draws, free_rain])
	return true


func _the_sky_survives_a_save() -> bool:
	var w: Variant = _world()
	w.step()
	_force(w, "snow")
	(w.weather as Dictionary)["untilTick"] = 123456
	(w.weather as Dictionary)["windX"] = 0.25
	(w.weather as Dictionary)["windY"] = -0.5
	(w.weather as Dictionary)["snowCover"] = 0.75
	w.step()
	var snap: Dictionary = w.snapshot()
	var txt: String = w.serialize()
	var w2: Variant = _world()
	w2.restore(snap)
	for k in (w.weather as Dictionary).keys():
		if str((w.weather as Dictionary)[k]) != str((w2.weather as Dictionary).get(k)):
			push_error("ROUND-TRIP: weather %s restored as %s" % [str(w.weather), str(w2.weather)])
			return false
	if w2.serialize() != txt:
		push_error("ROUND-TRIP: the serialisation differs after restore")
		return false
	if not (w2.rng.save() as Dictionary).has(SimWeather.STREAM):
		push_error("ROUND-TRIP: the %s stream did not come back" % SimWeather.STREAM)
		return false
	# The field's wind and the modifier store's move multiplier are outside the snapshot's
	# weather record: one tick after the restore both have been re-applied from it.
	var before: float = float(w2.field.wind_x)
	w2.step()
	var want: Dictionary = SimWeather.wind(w2)
	if absf(float(w2.field.wind_x) - float(want["x"])) > 0.000001 or absf(float(w2.field.wind_y) - float(want["y"])) > 0.000001:
		push_error("ROUND-TRIP: the field's wind (%.3f, %.3f) is not the restored (%.3f, %.3f); it read %.3f before the tick" % [float(w2.field.wind_x), float(w2.field.wind_y), float(want["x"]), float(want["y"]), before])
		return false
	if absf(float(w2.modifiers.resolve("move_speed", int(w2.player))) - SimWeather.survivor_move_mul(w2)) > 0.000001:
		push_error("ROUND-TRIP: move_speed resolves %.3f after restore, the sky says %.3f" % [float(w2.modifiers.resolve("move_speed", int(w2.player))), SimWeather.survivor_move_mul(w2)])
		return false
	# A snapshot with no weather (the shape a v19 save had) restores clear -- the merge reads the key.
	var w3: Variant = _world()
	var stripped: Dictionary = snap.duplicate(true)
	stripped.erase("weather")
	w3.restore(stripped)
	if SimWeather.kind(w3) != "clear":
		push_error("ROUND-TRIP: a snapshot with no weather key restored %s" % SimWeather.kind(w3))
		return false
	print("ROUND-TRIP OK weather %s survives, the field's wind and the move multiplier are re-applied a tick later, and a snapshot without it restores clear" % str(w.weather))
	return true


func _the_schedule_is_the_seeds() -> bool:
	var a: Variant = _world()
	var b: Variant = _world()
	var c: Variant = _world(404)
	var fa: Array = _walk_spans(a, 20)
	var fb: Array = _walk_spans(b, 20)
	var fc: Array = _walk_spans(c, 20)
	if str(fa) != str(fb):
		push_error("DETERMINISM: two worlds on one seed drew different skies: %s vs %s" % [str(fa), str(fb)])
		return false
	if str(fa) == str(fc):
		push_error("DETERMINISM: seed 404 drew the canonical seed's sky, so the comparison proves nothing")
		return false
	# The wind too: same seed same drift, and it does drift.
	if absf(float(a.weather["windX"]) - float(b.weather["windX"])) > 0.000001 or absf(float(a.weather["windY"]) - float(b.weather["windY"])) > 0.000001:
		push_error("DETERMINISM: two worlds on one seed hold different winds")
		return false
	var first: Dictionary = {"x": float(a.weather["windX"]), "y": float(a.weather["windY"])}
	a.tick = int(a.weather["windUntilTick"]) + 1
	a.step()
	if absf(float(a.weather["windX"]) - float(first["x"])) < 0.000001 and absf(float(a.weather["windY"]) - float(first["y"])) < 0.000001:
		push_error("DETERMINISM: the wind did not drift past windUntilTick")
		return false
	print("DETERMINISM OK same seed same sky (%d spans) and same wind, seed 404 differs, the wind drifts on schedule" % fa.size())
	return true


# A cold snap reads one band colder by day, indoors too, unless a fire is lit; a heat wave reads
# one band hotter by day outdoors and not indoors -- the hot half of the ladder, reachable for
# the first time -- and the effect behind the word: mood lower under both than under clear.
func _the_sky_shifts_the_band() -> bool:
	var out: Vector2i = _tile_where(_world(), false)
	var inside: Vector2i = _tile_where(_world(), true)
	if out.x < 0 or inside.x < 0:
		push_error("SHIFT: no outdoor or no indoor tile")
		return false
	var got: Dictionary = {}
	var moods: Dictionary = {}
	for k in ["clear", "cold_snap", "heat_wave"]:
		for where in ["out", "in"]:
			var w: Variant = _world()
			var e: int = int(w.player)
			_bare_body(w, e)
			w.tick = Clock.tick_on_day(1, 0.35)
			_force(w, k)
			for _i in 3:
				_place(w, e, out if where == "out" else inside)
				w.step()
			got[k + "/" + where] = _band(w, e)
			moods[k + "/" + where] = float(w.modifiers.resolve("mood", e))
	var want: Dictionary = {
		"clear/out": "comfortable", "clear/in": "comfortable",
		"cold_snap/out": "a_little_cold", "cold_snap/in": "a_little_cold",
		"heat_wave/out": "a_little_hot", "heat_wave/in": "comfortable",
	}
	for k in want.keys():
		if String(got.get(k, "")) != String(want[k]):
			push_error("SHIFT: %s reads %s, wanted %s (all: %s)" % [k, str(got.get(k)), str(want[k]), str(got)])
			return false
	if float(moods["cold_snap/out"]) >= float(moods["clear/out"]) or float(moods["heat_wave/out"]) >= float(moods["clear/out"]):
		push_error("SHIFT: mood under cold %.2f / heat %.2f is no lower than clear %.2f" % [float(moods["cold_snap/out"]), float(moods["heat_wave/out"]), float(moods["clear/out"])])
		return false
	# A lit fire cancels the cold shift and does nothing for the heat.
	var fires: Dictionary = {}
	for k in ["cold_snap", "heat_wave"]:
		var w: Variant = _world()
		var e: int = int(w.player)
		_bare_body(w, e)
		w.tick = Clock.tick_on_day(1, 0.35)
		_force(w, k)
		var fs: Array = w.components.query(["campfire"])
		if fs.is_empty():
			push_error("SHIFT: no campfire")
			return false
		SimNeeds.set_lit(w, int(fs[0]), true)
		var fp: Dictionary = w.components.get_component(int(fs[0]), "position") as Dictionary
		var by_fire: bool = w.tilemap != null and not SimTileMap.is_indoors(w.tilemap, floori(float(fp["x"])), floori(float(fp["y"])))
		for _i in 3:
			w.components.set_component(e, "position", {"x": float(fp["x"]) + 1.0, "y": float(fp["y"])})
			w.step()
		fires[k] = {"band": _band(w, e), "outdoors": by_fire}
	if String((fires["cold_snap"] as Dictionary)["band"]) != "comfortable":
		push_error("SHIFT: a cold snap by a lit fire reads %s" % str(fires["cold_snap"]))
		return false
	var heat_fire: String = String((fires["heat_wave"] as Dictionary)["band"])
	var heat_want: String = "a_little_hot" if bool((fires["heat_wave"] as Dictionary)["outdoors"]) else "comfortable"
	if heat_fire != heat_want:
		push_error("SHIFT: a heat wave by a lit fire (%s) reads %s, wanted %s" % ["outdoors" if bool((fires["heat_wave"] as Dictionary)["outdoors"]) else "indoors", heat_fire, heat_want])
		return false
	print("SHIFT OK clear comfortable; cold snap a_little_cold out and in (mood %.1f vs %.1f), comfortable by a fire; heat wave a_little_hot out (mood %.1f), comfortable in, and a fire is no relief" % [float(moods["cold_snap/out"]), float(moods["clear/out"]), float(moods["heat_wave/out"])])
	return true


# The wind is the field's four diffusion weights. Scent added at a point and diffused under an
# east wind peaks east of the source; under a west wind, west; and the tick hands the world's
# stored wind (times the kind's multiplier) to the field, so a storm doubles the lean.
func _the_wind_leans_the_field() -> bool:
	var w: Variant = _world()
	var f0: Variant = w.field
	var cm: float = float(f0.cell_metres)
	var x: float = -1.0
	var y: float = -1.0
	for ty in range(24, 40):
		for tx in range(24, 40):
			var px: float = float(tx) + 0.5
			var py: float = float(ty) + 0.5
			if not f0.is_solid(f0.cell_at(px, py)) and not f0.is_solid(f0.cell_at(px + 2.0 * cm, py)) and not f0.is_solid(f0.cell_at(px - 2.0 * cm, py)):
				x = px
				y = py
				break
		if x >= 0.0:
			break
	if x < 0.0:
		push_error("WIND: no open cell with open cells two cells east and west of it")
		return false
	var lean: Dictionary = {}
	for dir in [1.0, -1.0, 0.0]:
		var f: Variant = w.field
		f.clear_field()
		f.set_wind(0.8 * float(dir), 0.0)
		f.add_scent(x, y, 500.0)
		for _i in 20:
			f.diffuse_scent()
		lean[dir] = float(f.scent_at(x + 2.0 * cm, y)) - float(f.scent_at(x - 2.0 * cm, y))
	if not (float(lean[1.0]) > 0.0 and float(lean[-1.0]) < 0.0 and absf(float(lean[0.0])) < 0.000001):
		push_error("WIND: east-minus-west scent reads east %.4f / west %.4f / still %.4f" % [float(lean[1.0]), float(lean[-1.0]), float(lean[0.0])])
		return false
	# The tick applies the stored wind, and the storm's multiplier doubles it.
	var a: Variant = _world()
	(a.weather as Dictionary)["windX"] = 0.3
	(a.weather as Dictionary)["windY"] = -0.2
	(a.weather as Dictionary)["windUntilTick"] = FAR
	a.step()
	if absf(float(a.field.wind_x) - 0.3) > 0.000001 or absf(float(a.field.wind_y) + 0.2) > 0.000001:
		push_error("WIND: the field reads (%.3f, %.3f) after the tick, the world stores (0.3, -0.2)" % [float(a.field.wind_x), float(a.field.wind_y)])
		return false
	# A kind's `windMul` multiplies it -- on a fabricated storm entry, because no shipped kind
	# declares one (the storm's first cut of 2.0 was the difference between a colony and none on
	# one harness seed, docs/23's record) and a mechanism nothing exercises is a socket.
	var gusty: Dictionary = (a.content["weather/storm.json"] as Dictionary).duplicate(true)
	gusty["windMul"] = 2.0
	a.content["weather/storm.json"] = gusty
	_force(a, "storm")
	a.step()
	var mul: float = 2.0
	if absf(float(a.field.wind_x) - 0.3 * mul) > 0.000001 or absf(float(a.field.wind_y) + 0.2 * mul) > 0.000001:
		push_error("WIND: under a storm with windMul %.1f the field reads (%.3f, %.3f)" % [mul, float(a.field.wind_x), float(a.field.wind_y)])
		return false
	# And the shipped storm, which declares none, leaves the wind at the climate's.
	var shipped: Variant = _world()
	(shipped.weather as Dictionary)["windX"] = 0.3
	(shipped.weather as Dictionary)["windY"] = -0.2
	(shipped.weather as Dictionary)["windUntilTick"] = FAR
	_force(shipped, "storm")
	shipped.step()
	if absf(float(shipped.field.wind_x) - 0.3) > 0.000001:
		push_error("WIND: the shipped storm multiplies the wind by %.2f, and content declares no windMul" % (float(shipped.field.wind_x) / 0.3))
		return false
	_force(a, "clear")
	a.step()
	if absf(float(a.field.wind_x) - 0.3) > 0.000001:
		push_error("WIND: back under clear the field still reads %.3f" % float(a.field.wind_x))
		return false
	# The wind wanders inside windDriftDeg of the prevailing lean: forty draws all inside it on
	# the shipped climate, a climate pinned to 0 draws the lean exactly, and one opened to 180
	# lands a draw outside 45 degrees -- so the bound is read, not assumed.
	var outside: Dictionary = {"shipped": 0, "pinned": 0, "free": 0}
	for label in ["shipped", "pinned", "free"]:
		var ww: Variant = _world(90210 if label == "free" else SEED)
		var cl: Dictionary = (ww.content[SimWeather.CLIMATE_PATH] as Dictionary).duplicate(true)
		if label == "pinned":
			cl["windDriftDeg"] = 0
		elif label == "free":
			cl["windDriftDeg"] = 180
		ww.content[SimWeather.CLIMATE_PATH] = cl
		var prevailing: float = SimWeather.prevailing_angle(ww)
		for _d in 40:
			ww.tick = int((ww.weather as Dictionary).get("windUntilTick", 0))
			ww.step()
			var ang: float = atan2(float(ww.weather["windY"]), float(ww.weather["windX"]))
			var dev: float = absf(wrapf(ang - prevailing, -PI, PI))
			if dev > deg_to_rad(45.0) + 0.000001:
				outside[label] = int(outside[label]) + 1
			if label == "pinned" and dev > 0.000001:
				push_error("WIND: a climate pinned to 0 degrees drew %.3f rad off the lean" % dev)
				return false
	if int(outside["shipped"]) > 0 or int(outside["free"]) == 0:
		push_error("WIND: forty shipped draws landed %d outside 45 degrees of the lean; a free climate landed %d outside (wanted some)" % [int(outside["shipped"]), int(outside["free"])])
		return false
	# The boot value is the field's own calibration, and a world that never drew a wind holds it.
	var fresh: Variant = _world()
	var calib_x: float = float(fresh.field.calibration["windX"])
	if absf(float(fresh.field.wind_x) - calib_x) > 0.000001:
		push_error("WIND: a fresh field's wind %.3f is not its calibration's %.3f" % [float(fresh.field.wind_x), calib_x])
		return false
	print("WIND OK east wind leans scent east (%.3f), west wind west (%.3f), still is still; the tick applies the stored wind, a fabricated windMul %.1f multiplies it and the shipped storm does not; forty daily draws stay inside 45 degrees of the calibrated lean, a pinned climate draws it exactly and a free one wanders out (%d of 40)" % [float(lean[1.0]), float(lean[-1.0]), mul, int(outside["free"])])
	return true


# The living slow on snow that has settled and the dead slow in a cold snap, each measured on the
# body rather than read off the stat: an NPC's velocity under the sky against the same NPC's
# under clear, and a shambler's seek speed through the one accessor every movement site uses.
func _the_sky_slows_the_living_and_the_dead() -> bool:
	var cover_mul: float = float(SimWeather.CLIMATE_DEFAULTS["snowCoverMoveMul"])
	var speeds: Dictionary = {}
	var resolved: Dictionary = {}
	for k in ["clear", "snow"]:
		var w: Variant = _world()
		_force(w, k)
		if k == "snow":
			(w.weather as Dictionary)["snowCover"] = 1.0
		w.step()
		resolved[k] = float(w.modifiers.resolve("move_speed", int(w.player)))
		# An NPC walking a job: the velocity `_walk` writes, in metres a tick.
		var npc: int = -1
		for ent in w.components.query(["needs", "velocity"]):
			if int(ent) != int(w.player) and not w.components.has_component(int(ent), "recruit") and not w.components.has_component(int(ent), "corpse"):
				npc = int(ent)
				break
		if npc < 0:
			push_error("MOVE: no NPC survivor to walk")
			return false
		var target: Vector2i = _tile_where(w, false)
		_place(w, npc, target)
		var job: Dictionary = {"kind": "Haul", "ticksLeft": 0, "path": [{"x": target.x + 20, "y": target.y}], "pathGen": int(w.mapGeneration)}
		SimJobs._walk(w, npc, job, Vector2i(target.x + 20, target.y))
		var v: Dictionary = w.components.get_component(npc, "velocity") as Dictionary
		speeds[k] = sqrt(float(v["dx"]) * float(v["dx"]) + float(v["dy"]) * float(v["dy"]))
	if absf(float(resolved["clear"]) - 1.0) > 0.000001:
		push_error("MOVE: move_speed under clear resolves %.3f, not 1" % float(resolved["clear"]))
		return false
	if absf(float(resolved["snow"]) / float(resolved["clear"]) - cover_mul) > 0.000001:
		push_error("MOVE: settled snow resolves move_speed x%.3f, wanted x%.2f" % [float(resolved["snow"]) / float(resolved["clear"]), cover_mul])
		return false
	if float(speeds["clear"]) <= 0.0 or absf(float(speeds["snow"]) / float(speeds["clear"]) - cover_mul) > 0.000001:
		push_error("MOVE: an NPC walks %.3f a tick under clear and %.3f on snow (wanted x%.2f)" % [float(speeds["clear"]), float(speeds["snow"]), cover_mul])
		return false
	# Snow falling on bare ground does not slow anyone yet; snow on the ground after it stops does.
	var falling: Variant = _world()
	_force(falling, "snow")
	falling.step()
	var settled: Variant = _world()
	(settled.weather as Dictionary)["snowCover"] = 1.0
	settled.step()
	if absf(float(falling.modifiers.resolve("move_speed", int(falling.player))) - 1.0) > 0.000001 or absf(float(settled.modifiers.resolve("move_speed", int(settled.player))) - cover_mul) > 0.000001:
		push_error("MOVE: falling snow on bare ground resolves %.3f, settled snow under a clear sky %.3f" % [float(falling.modifiers.resolve("move_speed", int(falling.player))), float(settled.modifiers.resolve("move_speed", int(settled.player)))])
		return false
	# The cover lays while it snows and melts when it stops.
	var lay: Variant = _world()
	_force(lay, "snow")
	for _i in 200:
		lay.step()
	var laid: float = SimWeather.snow_cover(lay)
	_force(lay, "clear")
	for _j in 200:
		lay.step()
	if laid <= 0.0 or SimWeather.snow_cover(lay) >= laid:
		push_error("MOVE: cover after 200 ticks of snow %.6f, after 200 clear %.6f" % [laid, SimWeather.snow_cover(lay)])
		return false
	# The dead: the shambler's one speed accessor under a cold snap, snow and clear.
	var dead: Dictionary = {}
	for k in ["clear", "cold_snap", "snow"]:
		var w: Variant = _world()
		_force(w, k)
		var zs: Array = w.components.query(["shambler"])
		if zs.is_empty():
			push_error("MOVE: no shambler")
			return false
		var sd: Dictionary = w.components.get_component(int(zs[0]), "shambler") as Dictionary
		dead[k] = SimShambler._speed_of(w, int(zs[0]), sd, "seekSpeed") / float(sd["seekSpeed"])
	var cold_mul: float = float(SimWeather.DEFAULTS["cold_snap"]["zombieMoveMul"])
	var snow_mul: float = float(SimWeather.DEFAULTS["snow"]["zombieMoveMul"])
	if absf(float(dead["clear"]) - 1.0) > 0.000001 or absf(float(dead["cold_snap"]) - cold_mul) > 0.000001 or absf(float(dead["snow"]) - snow_mul) > 0.000001:
		push_error("MOVE: a shambler seeks at x%.2f clear / x%.2f cold / x%.2f snow, wanted 1 / %.2f / %.2f" % [float(dead["clear"]), float(dead["cold_snap"]), float(dead["snow"]), cold_mul, snow_mul])
		return false
	print("MOVE OK an NPC walks %.3f a tick under clear and %.3f on settled snow (x%.2f, the modifier every body resolves); falling snow on bare ground slows nobody; cover lays %.5f in 200 ticks and melts; a shambler seeks x%.2f in a cold snap, x%.2f in snow, x1 clear" % [float(speeds["clear"]), float(speeds["snow"]), cover_mul, laid, cold_mul, snow_mul])
	return true


# The seek behind the band, for the one band the spine makes reachable: an NPC outdoors at noon
# under a heat wave walks to the nearest roof and never to the campfire; the same NPC under a
# cold snap walks to the fire (the seek that was already there); under clear it does neither.
func _a_hot_body_seeks_a_roof_and_a_cold_one_a_fire() -> bool:
	var out: Vector2i = _tile_where(_world(), false)
	if out.x < 0:
		push_error("SEEK: no outdoor tile")
		return false
	var ends: Dictionary = {}
	for k in ["clear", "heat_wave", "cold_snap"]:
		var w: Variant = _world()
		# The boot shamblers go first: this lane places a colonist alone outdoors, 12 to 20 tiles
		# from the fire, and walks them for 1,500 ticks, and since every zombie has eyes (the
		# playable-state group's fifth piece) a wanderer sees that walk at 12 m and ends it --
		# the body lost its `position` mid-lane on the heat-wave arm. What is judged here is the
		# seek, not the district's teeth. `world.despawn`, not `entities.despawn`.
		for zed in w.components.query(["shambler"]):
			w.despawn(int(zed))
		var npc: int = -1
		for ent in w.components.query(["needs", "velocity"]):
			if int(ent) != int(w.player) and not w.components.has_component(int(ent), "recruit") and not w.components.has_component(int(ent), "corpse"):
				npc = int(ent)
				break
		if npc < 0:
			push_error("SEEK: no NPC")
			return false
		_bare_body(w, npc)
		for fire in w.components.query(["campfire"]):
			SimNeeds.set_lit(w, int(fire), true)
		var fp: Dictionary = w.components.get_component(int(w.components.query(["campfire"])[0]), "position") as Dictionary
		# Far from the fire, outdoors, at noon, with every other need full.
		var far: Vector2i = out
		for y in range(1, 63):
			for x in range(1, 63):
				var d: float = absf(float(x) - float(fp["x"])) + absf(float(y) - float(fp["y"]))
				if not SimTileMap.is_indoors(w.tilemap, x, y) and not SimTileMap.is_solid(w.tilemap, x, y) and d > 12.0 and d < 20.0 and SimJobs._nearest_roof(w, float(x) + 0.5, float(y) + 0.5).x >= 0 and not SimPath.find(w, Vector2i(x, y), Vector2i(floori(float(fp["x"])), floori(float(fp["y"])))).is_empty():
					far = Vector2i(x, y)
					break
			if far != out:
				break
		w.tick = Clock.tick_on_day(1, 0.4)
		_force(w, k)
		_place(w, npc, far)
		w.components.remove(npc, "job")
		var n: Dictionary = SimNeeds.of(w, npc)
		for pk in SimNeeds.POOLS:
			n[pk] = 100.0
		# A body walks a tenth of a tile a tick and the path round the colony's walls runs to
		# sixty-odd tiles, so this is the walk and a margin, not a number about the seek.
		# Watched over the walk rather than read at the end: a body that reaches a roof reads
		# comfortable, takes Guard at the gate, walks out, gets hot and seeks again -- the same
		# oscillation the cold seek has always had with the fire. What is asserted is that the
		# seek happened, that a roof was reached while hot, and how close to a fire the body
		# stood while it was hot (never) or cold (at the fire's stand distance).
		var sought: bool = false
		var roofed: int = -1
		var nearest_fire_while: float = 1e9
		for i in 1500:
			w.step()
			var job: Variant = w.components.get_component(npc, "job")
			if job is Dictionary and String((job as Dictionary).get("kind", "")) == "Seek":
				sought = true
			var pos: Dictionary = w.components.get_component(npc, "position") as Dictionary
			var band: String = _band(w, npc)
			if band != "comfortable":
				for fire in w.components.query(["campfire"]):
					var p2: Dictionary = w.components.get_component(int(fire), "position") as Dictionary
					nearest_fire_while = minf(nearest_fire_while, absf(float(pos["x"]) - float(p2["x"])) + absf(float(pos["y"]) - float(p2["y"])))
			if roofed < 0 and SimTileMap.is_indoors(w.tilemap, floori(float(pos["x"])), floori(float(pos["y"]))):
				roofed = i
		ends[k] = {"sought": sought, "roofed_at": roofed, "nearest_fire_while_uncomfortable": nearest_fire_while, "from": far}
	var hot: Dictionary = ends["heat_wave"] as Dictionary
	var cold: Dictionary = ends["cold_snap"] as Dictionary
	var clear: Dictionary = ends["clear"] as Dictionary
	if not bool(hot["sought"]) or int(hot["roofed_at"]) < 0 or float(hot["nearest_fire_while_uncomfortable"]) <= SimJobs.CAMPFIRE_STAND:
		push_error("SEEK: a hot body did not seek a roof and keep off the fire: %s" % str(hot))
		return false
	if not bool(cold["sought"]) or float(cold["nearest_fire_while_uncomfortable"]) > SimJobs.CAMPFIRE_STAND + 1.0:
		push_error("SEEK: a cold body did not walk to the fire: %s" % str(cold))
		return false
	if bool(clear["sought"]):
		push_error("SEEK: a comfortable body sought something: %s" % str(clear))
		return false
	print("SEEK OK under a heat wave an NPC seeks a roof (under one at tick %d, never nearer a fire than %.1f while hot); under a cold snap it walks to the fire (%.1f); under clear it stays at work" % [int(hot["roofed_at"]), float(hot["nearest_fire_while_uncomfortable"]), float(cold["nearest_fire_while_uncomfortable"])])
	return true


func _the_hud_names_the_sky_and_nothing_when_clear() -> bool:
	var w: Variant = _world()
	w.step()
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var right_clear: Array = (hud.get("_right") as Array).duplicate()
	var lines: Dictionary = {}
	for k in SimWeather.kinds(w):
		if k == "clear":
			continue
		_force(w, k)
		hud.call("refresh", w, w.player, "")
		var right: Array = (hud.get("_right") as Array).duplicate()
		var line: String = SimWeather.hud_clause(w)
		if line.is_empty() or not right.has(line):
			push_error("HUD: the world column does not carry '%s' under %s: %s" % [line, k, str(right)])
			hud.queue_free()
			return false
		if right_clear.has(line):
			push_error("HUD: the world column says '%s' under a clear sky" % line)
			hud.queue_free()
			return false
		for ch in line:
			if String(ch).is_valid_int():
				push_error("HUD: the %s line carries a digit: '%s'" % [k, line])
				hud.queue_free()
				return false
		if lines.values().has(line):
			push_error("HUD: two kinds share the sentence '%s'" % line)
			hud.queue_free()
			return false
		lines[k] = line
	hud.queue_free()
	if not SimWeather.hud_clause(_world()).is_empty():
		push_error("HUD: a clear world's clause is not empty")
		return false
	print("HUD OK one sentence a kind (%s), nothing under clear, no digits" % str(lines.values()))
	return true


func _a_body_in_the_rain_gets_wet_and_dries_by_a_fire() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var out: Vector2i = _tile_where(w, false)
	var inside: Vector2i = _tile_where(w, true)
	if out.x < 0 or inside.x < 0:
		push_error("WET: the booted district has no outdoor tile or no indoor one, so this lane has nothing to judge")
		return false
	if not _bare_body(w, ent):
		push_error("WET: could not take the wrap off")
		return false
	w.tick = Clock.tick_on_day(1, 0.3)
	_force(w, "rain")
	_place(w, ent, out)
	var after: int = SimWeather.wet_after_ticks(w)
	for _i in after - 1:
		_place(w, ent, out)
		w.step()
	if SimNeeds.is_wet(w, ent):
		push_error("WET: wet before %d ticks in the rain" % after)
		return false
	for _j in 2:
		_place(w, ent, out)
		w.step()
	if not SimNeeds.is_wet(w, ent):
		push_error("WET: still dry after %d ticks out in the rain" % (after + 1))
		return false
	var until: int = int(SimNeeds.of(w, ent).get("wetUntilTick", -1))
	if until != int(w.tick) + SimWeather.dry_after_ticks(w) and until != int(w.tick) - 1 + SimWeather.dry_after_ticks(w):
		push_error("WET: wetUntilTick %d is not tick %d + dryAfterTicks %d" % [until, int(w.tick), SimWeather.dry_after_ticks(w)])
		return false

	# Under a roof, the same rain, the same span: never wet.
	var roofed: Variant = _world()
	var e2: int = int(roofed.player)
	_bare_body(roofed, e2)
	roofed.tick = Clock.tick_on_day(1, 0.3)
	_force(roofed, "rain")
	for _k in after + 5:
		_place(roofed, e2, inside)
		roofed.step()
	if SimNeeds.is_wet(roofed, e2):
		push_error("WET: a survivor under a roof got wet")
		return false

	# The same body, dry sky: never wet.
	var clear: Variant = _world()
	var e3: int = int(clear.player)
	_bare_body(clear, e3)
	clear.tick = Clock.tick_on_day(1, 0.3)
	for _m in after + 5:
		_place(clear, e3, out)
		clear.step()
	if SimNeeds.is_wet(clear, e3):
		push_error("WET: a survivor outdoors under a clear sky got wet")
		return false

	# Out of the rain, a wet body dries on the air clock -- wet three ticks short, dry one past.
	_force(w, "clear")
	_place(w, ent, out)
	w.tick = until - 3
	w.step()
	if not SimNeeds.is_wet(w, ent):
		push_error("WET: dried early on the air clock")
		return false
	w.tick = until + 1
	_place(w, ent, out)
	w.step()
	if SimNeeds.is_wet(w, ent):
		push_error("WET: still wet past the air clock")
		return false

	# By a lit fire, the same wet body dries on the fire's clock instead.
	var warm: Variant = _world()
	var e4: int = int(warm.player)
	_bare_body(warm, e4)
	warm.tick = Clock.tick_on_day(1, 0.3)
	_force(warm, "rain")
	for _n in after + 2:
		_place(warm, e4, out)
		warm.step()
	if not SimNeeds.is_wet(warm, e4):
		push_error("WET: the fire lane's body never got wet")
		return false
	_force(warm, "clear")
	var fires: Array = warm.components.query(["campfire"])
	if fires.is_empty():
		push_error("WET: no campfire to dry by")
		return false
	SimNeeds.set_lit(warm, int(fires[0]), true)
	var fp: Dictionary = warm.components.get_component(int(fires[0]), "position") as Dictionary
	warm.components.set_component(e4, "position", {"x": float(fp["x"]) + 1.0, "y": float(fp["y"])})
	warm.step()
	var by_fire: int = int(SimNeeds.of(warm, e4).get("wetUntilTick", -1))
	var fire_ticks: int = SimWeather.dry_by_fire_ticks(warm)
	if by_fire > int(warm.tick) + fire_ticks or by_fire < int(warm.tick) - 1 + fire_ticks:
		push_error("WET: a lit fire did not bring the dry clock to tick + %d (reads %d at tick %d)" % [fire_ticks, by_fire, int(warm.tick)])
		return false
	if by_fire >= until:
		push_error("WET: the fire clock %d is no sooner than the air clock %d" % [by_fire, until])
		return false
	print("WET OK wet after %d ticks in the rain, never under a roof or a clear sky, dries at +%d in the air and +%d by a fire" % [after, SimWeather.dry_after_ticks(w), fire_ticks])
	return true


func _a_wet_body_reads_one_band_colder() -> bool:
	var out: Vector2i = _tile_where(_world(), false)
	if out.x < 0:
		push_error("COLD: no outdoor tile")
		return false
	var after: int = SimWeather.wet_after_ticks(_world())

	# Day, outdoors, no fire, no wrap: dry is comfortable, wet is a little cold, and the mood
	# behind the band is lower -- the effect, not the word.
	var wet: Variant = _world()
	var ew: int = int(wet.player)
	_bare_body(wet, ew)
	wet.tick = Clock.tick_on_day(1, 0.3)
	_force(wet, "rain")
	for _i in after + 2:
		_place(wet, ew, out)
		wet.step()
	var dry: Variant = _world()
	var ed: int = int(dry.player)
	_bare_body(dry, ed)
	dry.tick = Clock.tick_on_day(1, 0.3)
	for _j in after + 2:
		_place(dry, ed, out)
		dry.step()
	if _band(dry, ed) != "comfortable":
		push_error("COLD: a dry body on a mild day reads %s" % _band(dry, ed))
		return false
	if _band(wet, ew) != "a_little_cold":
		push_error("COLD: a wet body on a mild day reads %s, not a_little_cold" % _band(wet, ew))
		return false
	var mood_wet: float = float(wet.modifiers.resolve("mood", ew))
	var mood_dry: float = float(dry.modifiers.resolve("mood", ed))
	if mood_wet >= mood_dry:
		push_error("COLD: a wet body's mood %.2f is no lower than a dry one's %.2f" % [mood_wet, mood_dry])
		return false

	# Night, outdoors, no fire: dry is very cold, wet is freezing at once.
	var night_wet: Variant = _world()
	var nw: int = int(night_wet.player)
	_bare_body(night_wet, nw)
	night_wet.tick = Clock.tick_on_day(2, 0.8)
	_force(night_wet, "rain")
	for _k in after + 2:
		_place(night_wet, nw, out)
		night_wet.step()
	var night_dry: Variant = _world()
	var nd: int = int(night_dry.player)
	_bare_body(night_dry, nd)
	night_dry.tick = Clock.tick_on_day(2, 0.8)
	for _m in after + 2:
		_place(night_dry, nd, out)
		night_dry.step()
	if _band(night_dry, nd) != "very_cold" or _band(night_wet, nw) != "extremely_cold":
		push_error("COLD: a night outdoors reads dry %s / wet %s, wanted very_cold / extremely_cold" % [_band(night_dry, nd), _band(night_wet, nw)])
		return false

	# A wrap buys the band back: wet and wrapped on a mild day is comfortable again.
	var wrapped: Variant = _world()
	var ww: int = int(wrapped.player)
	for fire in wrapped.components.query(["campfire"]):
		SimNeeds.set_lit(wrapped, int(fire), false)
	if not SimNeeds.wearing_wrap(wrapped, ww):
		var wrap: int = SimItems.spawn_item(wrapped, "item.wrap.cloth", {"tier": "scavenged"})
		if not SimInventory.equip(wrapped, ww, wrap) or not SimNeeds.wearing_wrap(wrapped, ww):
			push_error("COLD: could not put a wrap on the player, so the wrap negative has nothing to judge")
			return false
	wrapped.tick = Clock.tick_on_day(1, 0.3)
	_force(wrapped, "rain")
	for _n in after + 2:
		_place(wrapped, ww, out)
		wrapped.step()
	if not SimNeeds.is_wet(wrapped, ww) or _band(wrapped, ww) != "comfortable":
		push_error("COLD: wet and wrapped reads %s (wet=%s), wanted comfortable" % [_band(wrapped, ww), str(SimNeeds.is_wet(wrapped, ww))])
		return false
	# The HUD's own word for it, with every other need pinned fine.
	var n: Dictionary = SimNeeds.of(wet, ew)
	for k in SimNeeds.POOLS:
		n[k] = 100.0
	n["hygiene"] = "clean"
	n["soiled"] = 0.0
	n["grief"] = 0.0
	var clause: String = SimNeeds.hud_clause(wet, ew, false)
	if clause != "You're soaked.":
		push_error("COLD: a wet, slightly cold body says '%s'" % clause)
		return false
	print("COLD OK day wet a_little_cold (mood %.1f) vs dry comfortable (mood %.1f), night wet extremely_cold vs dry very_cold, wet+wrap comfortable, and the word is 'soaked'" % [mood_wet, mood_dry])
	return true


func _rain_washes_scent_off_the_field() -> bool:
	var rain: Variant = _world()
	var dry: Variant = _world()
	var still: Variant = _world()
	_force(rain, "rain")
	(still.weather as Dictionary).clear()
	var at: Vector2i = _tile_where(rain, false)
	var x: float = float(at.x) + 0.5
	var y: float = float(at.y) + 0.5
	for w in [rain, dry, still]:
		w.tick = Clock.tick_on_day(1, 0.3)
		w.field.add_scent(x, y, 500.0)
	for _i in 100:
		rain.step()
		dry.step()
		still.step()
	var s_rain: float = float(rain.field.scent_at(x, y))
	var s_dry: float = float(dry.field.scent_at(x, y))
	var s_still: float = float(still.field.scent_at(x, y))
	if s_dry <= 0.0:
		push_error("SCENT: the dry field lost all of its scent, so there is nothing to compare")
		return false
	if s_rain >= s_dry:
		push_error("SCENT: rain left %.4f against a dry %.4f -- it washed nothing" % [s_rain, s_dry])
		return false
	if absf(s_dry - s_still) > 0.000001:
		push_error("SCENT: a dry sky costs the field something: %.6f with weather, %.6f with none" % [s_dry, s_still])
		return false
	if absf(SimWeather.scent_half_life_mul(dry) - 1.0) > 0.000001 or SimWeather.scent_half_life_mul(rain) >= 1.0:
		push_error("SCENT: the multipliers read dry %.3f / rain %.3f" % [SimWeather.scent_half_life_mul(dry), SimWeather.scent_half_life_mul(rain)])
		return false
	# Heavily, not totally: after a hundred ticks of rain the field is still a field. The first
	# cut (x0.85 a step) left 4% of the dry scent here and wiped colonies in the harness.
	if s_rain < 0.5 * s_dry:
		push_error("SCENT: rain left %.4f of a dry %.4f after a hundred ticks -- that is a wipe, not a wash" % [s_rain, s_dry])
		return false
	print("SCENT OK after twenty diffusions rain leaves %.4f where a dry sky leaves %.4f (half-life x%.2f), and a dry sky equals no weather at all" % [s_rain, s_dry, SimWeather.scent_half_life_mul(rain)])
	return true



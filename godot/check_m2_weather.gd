extends SceneTree
# A minimal rain state (docs/adr/0015, 2026-09-06). Rain is sim state now: it starts and stops on
# the world's own `weather` stream, in spans content declares; a body out in it gets wet and reads
# one temperature band colder; scent decays faster on the field while it falls; the rain layer
# draws only while it rains; and the HUD says so in one sentence. docs/16's rule -- every weather
# state moves two systems in opposing directions -- is the WET/COLD pair against the SCENT lane.
#
# What this gate holds down:
#  1. **Nothing rains in a fixture that never asked for weather**, and a booted world starts dry.
#     Every other gate in the chain boots a world, and none of them is about the sky.
#  2. **Every reader is reached.** The temperature band, the mood behind it, the scent on the
#     field, the HUD line and (textually, in check_weather.gd) the draw call: the dead-socket rule.
#  3. **Assert the effect, never the mechanism** where an effect exists: mood resolved lower on
#     the wet body, scent measured lower on the raining field.
#
# Every assertion carries a true negative beside its positive.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
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
	ok = _the_rain_is_content_and_the_validator_sees_it() and ok
	ok = _it_starts_dry_and_rain_comes_and_goes_inside_its_ranges() and ok
	ok = _the_sky_survives_a_save() and ok
	ok = _the_schedule_is_the_seeds() and ok
	ok = _a_body_in_the_rain_gets_wet_and_dries_by_a_fire() and ok
	ok = _a_wet_body_reads_one_band_colder() and ok
	ok = _rain_washes_scent_off_the_field() and ok
	ok = _the_hud_says_it_is_raining_and_nothing_when_it_is_not() and ok
	if ok:
		print("M2_WEATHER_OK rain is sim state: it comes and goes on its own stream, wets bodies one band colder, washes scent, and says so in one sentence")
		quit(0)
	else:
		push_error("M2_WEATHER_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


func _force(w: Variant, raining: bool) -> void:
	(w.weather as Dictionary)["raining"] = raining
	(w.weather as Dictionary)["untilTick"] = FAR
	(w.weather as Dictionary)["spans"] = 1


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


# Jump the clock to just before the next flip and step through it; returns the flips seen.
func _walk_spans(w: Variant, days: int) -> Array:
	var flips: Array = []
	var stop: int = int(w.tick) + days * Clock.DAY_TICKS
	var guard: int = 0
	while int(w.tick) < stop and guard < 200:
		guard += 1
		var until: int = int((w.weather as Dictionary).get("untilTick", 0))
		if until <= int(w.tick):
			w.step()
			continue
		w.tick = until - 1
		var was: bool = SimWeather.raining(w)
		w.step()
		w.step()
		if SimWeather.raining(w) != was:
			flips.append({"tick": int(w.tick), "raining": SimWeather.raining(w), "span": int((w.weather as Dictionary).get("untilTick", 0)) - int(w.tick)})
	return flips


# --- lanes --------------------------------------------------------------------------------

func _the_rain_is_content_and_the_validator_sees_it() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var entry: Variant = tree.get(SimWeather.CONTENT_PATH)
	if not (entry is Dictionary) or String((entry as Dictionary).get("id", "")) != "weather.rain":
		push_error("CONTENT: %s is not loaded as weather.rain: %s" % [SimWeather.CONTENT_PATH, str(entry)])
		return false
	var e: Dictionary = entry as Dictionary
	var dry: Dictionary = e.get("dryTicks", {}) as Dictionary
	var wet: Dictionary = e.get("wetTicks", {}) as Dictionary
	if int(dry.get("min", 0)) <= 0 or int(dry.get("min", 0)) >= int(dry.get("max", 0)) or int(wet.get("min", 0)) <= 0 or int(wet.get("min", 0)) >= int(wet.get("max", 0)):
		push_error("CONTENT: the span ranges are not 0 < min < max: dry %s wet %s" % [str(dry), str(wet)])
		return false
	var mul: float = float(e.get("scentHalfLifeMul", 1.0))
	if mul <= 0.0 or mul >= 1.0:
		push_error("CONTENT: scentHalfLifeMul %.3f is not inside (0, 1), so rain either kills scent or does nothing to it" % mul)
		return false
	var after: int = int(e.get("wetAfterTicks", 0))
	var fire: int = int(e.get("dryByFireTicks", 0))
	var air: int = int(e.get("dryAfterTicks", 0))
	if not (after > 0 and after < fire and fire < air):
		push_error("CONTENT: wetAfterTicks < dryByFireTicks < dryAfterTicks does not hold: %d %d %d" % [after, fire, air])
		return false
	# The booted world reads the entry and not the defaults, and the defaults still agree with it.
	var w: Variant = _world()
	if SimWeather.spec(w) == SimWeather.DEFAULTS:
		push_error("CONTENT: the booted world reads SimWeather.DEFAULTS rather than the content entry")
		return false
	# Compared as numbers: JSON hands back floats where the mirror holds ints.
	for k in SimWeather.DEFAULTS.keys():
		var mine: Variant = SimWeather.DEFAULTS[k]
		var theirs: Variant = e.get(k)
		var same: bool = false
		if mine is Dictionary and theirs is Dictionary:
			same = int((mine as Dictionary).get("min", -1)) == int((theirs as Dictionary).get("min", -2)) and int((mine as Dictionary).get("max", -1)) == int((theirs as Dictionary).get("max", -2))
		else:
			same = absf(float(mine) - float(theirs)) < 0.000001
		if not same:
			push_error("CONTENT: the mirrored default for %s (%s) drifted from content (%s)" % [k, str(mine), str(theirs)])
			return false
	# The validator is registered for the type: the shipped entry raises nothing, and a fabricated
	# entry with a stray top-level key raises exactly one issue for it.
	var issues: Array[String] = ContentValidator.validate_tree()
	for issue in issues:
		if String(issue).contains("weather/"):
			push_error("CONTENT: the validator reports %s" % issue)
			return false
	var schemas: Dictionary = ContentValidator._load_schemas()
	if not schemas.has("weather"):
		push_error("CONTENT: no weather schema is registered, so the directory validates in silence")
		return false
	var bad: Dictionary = e.duplicate(true)
	bad["forecast"] = "sunny"
	var raised: Array[String] = ContentValidator._validate_shape(bad, schemas["weather"] as Dictionary, "weather/fake.json")
	if raised.is_empty():
		push_error("CONTENT: a fabricated weather entry with a stray key raised nothing")
		return false
	print("CONTENT OK weather.rain loaded, ranges ordered, scent half-life x%.2f, drying %d < %d < %d, schema registered and a stray key refused" % [mul, after, fire, air])
	return true


func _it_starts_dry_and_rain_comes_and_goes_inside_its_ranges() -> bool:
	var w: Variant = _world()
	if SimWeather.raining(w):
		push_error("SCHEDULE: the booted world is raining at tick 0")
		return false
	var born: int = int(w.tick)
	w.step()
	if SimWeather.raining(w):
		push_error("SCHEDULE: the first span is not dry")
		return false
	var e: Dictionary = SimWeather.spec(w)
	var dry: Dictionary = e["dryTicks"] as Dictionary
	var wet: Dictionary = e["wetTicks"] as Dictionary
	# Measured from the tick the world was born on -- a playable world boots at dawn, not at 0.
	var first_span: int = int((w.weather as Dictionary).get("untilTick", 0)) - born
	if first_span < int(dry["min"]) or first_span > int(dry["max"]) + 1:
		push_error("SCHEDULE: the first dry span is %d ticks, outside [%d, %d]" % [first_span, int(dry["min"]), int(dry["max"])])
		return false
	# A booted world stepped a short while never rains: every other gate's world is safe.
	for _i in 999:
		w.step()
	if SimWeather.raining(w):
		push_error("SCHEDULE: rain inside the first thousand ticks")
		return false
	var flips: Array = _walk_spans(w, 10)
	var wets: int = 0
	for f in flips:
		var fd: Dictionary = f as Dictionary
		var span: int = int(fd["span"])
		var r: Dictionary = wet if bool(fd["raining"]) else dry
		if span < int(r["min"]) or span > int(r["max"]):
			push_error("SCHEDULE: a %s span of %d ticks is outside [%d, %d]" % ["wet" if bool(fd["raining"]) else "dry", span, int(r["min"]), int(r["max"])])
			return false
		if bool(fd["raining"]):
			wets += 1
	if flips.size() < 2 or wets < 1:
		push_error("SCHEDULE: ten days saw %d flips and %d spells of rain" % [flips.size(), wets])
		return false
	# A kernel-less fixture that never registered the module never rains, and grows no weather
	# state -- the shape every treatment, wounds and recovery world has.
	var bare: Variant = World.new({
		"seed": SEED, "tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	})
	for _j in 1000:
		bare.step()
	if SimWeather.raining(bare) or not (bare.weather as Dictionary).is_empty():
		push_error("SCHEDULE: a bare fixture rained, or grew weather state: %s" % str(bare.weather))
		return false
	# And the flag can be read true, so the negatives above are not a reader that always says no.
	var forced: Variant = _world()
	_force(forced, true)
	if not SimWeather.raining(forced):
		push_error("SCHEDULE: a forced rain reads dry, so `raining` cannot say yes")
		return false
	print("SCHEDULE OK dry at boot and for a thousand ticks, %d flips over ten days (%d spells), every span inside its range; a bare fixture never rains" % [flips.size(), wets])
	return true


func _the_sky_survives_a_save() -> bool:
	var w: Variant = _world()
	w.step()
	_force(w, true)
	(w.weather as Dictionary)["untilTick"] = 123456
	(w.weather as Dictionary)["spans"] = 3
	var snap: Dictionary = w.snapshot()
	var txt: String = w.serialize()
	var w2: Variant = _world()
	w2.restore(snap)
	if (w2.weather as Dictionary) != (w.weather as Dictionary):
		push_error("ROUND-TRIP: weather %s restored as %s" % [str(w.weather), str(w2.weather)])
		return false
	if w2.serialize() != txt:
		push_error("ROUND-TRIP: the serialisation differs after restore")
		return false
	if not (w2.rng.save() as Dictionary).has(SimWeather.STREAM):
		push_error("ROUND-TRIP: the %s stream did not come back" % SimWeather.STREAM)
		return false
	# A snapshot with no weather (the shape a v19 save had) restores dry -- the merge reads the key.
	var w3: Variant = _world()
	var stripped: Dictionary = snap.duplicate(true)
	stripped.erase("weather")
	w3.restore(stripped)
	if SimWeather.raining(w3):
		push_error("ROUND-TRIP: a snapshot with no weather key restored raining")
		return false
	print("ROUND-TRIP OK weather %s survives, and a snapshot without it restores dry" % str(w.weather))
	return true


func _the_schedule_is_the_seeds() -> bool:
	var a: Variant = _world()
	var b: Variant = _world()
	var c: Variant = _world(404)
	var fa: Array = _walk_spans(a, 10)
	var fb: Array = _walk_spans(b, 10)
	var fc: Array = _walk_spans(c, 10)
	if str(fa) != str(fb):
		push_error("DETERMINISM: two worlds on one seed drew different rain: %s vs %s" % [str(fa), str(fb)])
		return false
	if str(fa) == str(fc):
		push_error("DETERMINISM: seed 404 drew the canonical seed's rain, so the comparison proves nothing")
		return false
	print("DETERMINISM OK same seed same sky (%d flips), seed 404 differs" % fa.size())
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
	_force(w, true)
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
	_force(roofed, true)
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
	_force(w, false)
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
	_force(warm, true)
	for _n in after + 2:
		_place(warm, e4, out)
		warm.step()
	if not SimNeeds.is_wet(warm, e4):
		push_error("WET: the fire lane's body never got wet")
		return false
	_force(warm, false)
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
	_force(wet, true)
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
	_force(night_wet, true)
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
	_force(wrapped, true)
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
	_force(rain, true)
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


func _the_hud_says_it_is_raining_and_nothing_when_it_is_not() -> bool:
	var w: Variant = _world()
	w.step()
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var right_dry: Array = (hud.get("_right") as Array).duplicate()
	_force(w, true)
	hud.call("refresh", w, w.player, "")
	var right_wet: Array = (hud.get("_right") as Array).duplicate()
	hud.queue_free()
	var line: String = SimWeather.hud_clause(w)
	if line.is_empty() or not right_wet.has(line):
		push_error("HUD: the world column does not carry '%s' while it rains: %s" % [line, str(right_wet)])
		return false
	if right_dry.has(line):
		push_error("HUD: the world column says it is raining under a clear sky")
		return false
	for ch in line:
		if String(ch).is_valid_int():
			push_error("HUD: the rain line carries a digit: '%s'" % line)
			return false
	if not SimWeather.hud_clause(_world()).is_empty():
		push_error("HUD: a dry world's clause is not empty")
		return false
	print("HUD OK '%s' while it rains, nothing when dry, no digits" % line)
	return true

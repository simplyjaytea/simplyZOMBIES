extends SceneTree
# Fog, the seventh weather kind (docs/16's table: "sight range collapses both ways"). The spine
# gate `godot:m2:weather` owns the sky itself -- the spans, the calendar, the wind. This gate owns
# what a fog then costs, and unlike the cold and the heat it costs the *dead* exactly what it costs
# the living: one number, `sightMul`, multiplied into every observer's range and into a zombie's
# own sight reach, so neither side of the district gets an edge out of the weather.
#
# What this gate holds down:
#  1. **The number is content, and it is read.** `weather/fog.json` declares `sightMul` inside
#     (0, 1]; `SimWeather.DEFAULTS["fog"]` mirrors it number for number; `SimWeather.sight_mul` is
#     the identity under a clear sky and exactly the content value under fog. The fabricated
#     entry is the proof it is the *number* and not the kind's name that closes the eyes: a fog
#     whose content says 1.0 hides nothing.
#  2. **Both halves of the symmetry are reached.** The living: a body 20 m off on open ground in
#     daylight is seen under clear and unseen under fog, its tile count collapsed, while a body at
#     8 m is still seen -- the fog is a range, not a blindfold. The dead: `SimShambler.sight_reach`
#     falls by the same factor and `_seen_target` stops returning the survivor three metres in
#     front of it, and the night's lit-target escape (`full_squared`) closes with it.
#  3. **What is remembered follows what is seen.** A body the fog hides never enters
#     `SimSightings`, so the prose that reads that memory goes quiet -- the dead-socket rule
#     applied one layer downstream.
#  4. **The parameter is plumbed where it belongs and nowhere else.** `_refresh_vision` and
#     `sight_reach` read it; `_sight_metres` and `SimLight.sight_metres` must not, because their
#     ratio against `range_metres` is the alpha of the night wash and a fog folded in there would
#     paint midday in the night's colour. That one is textual, so the scanner is proved on a
#     fabricated body before it is trusted.
#
# Every lane carries a true negative -- a clear-sky control world, or the same geometry inside the
# fog's reach -- and every number it judges on is printed. A lane that finds nothing to judge (no
# open line long enough on the district it booted) fails loudly rather than passing quietly.

const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLightModule = preload("res://sim/modules/light.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentValidator = preload("res://platform/content_validator.gd")
const Hud = preload("res://ui/hud.gd")

const SEED: int = 20260908
const FAR: int = 1 << 40
const FOG_PATH: String = "weather/fog.json"
# Noon on day one: ambient is 1.0, so a 48 m pair of eyes reaches 48 m and the only thing that can
# close them is the sky. Night is the other end of the same ladder, ambient 0.04.
const NOON: float = 0.4
const NIGHT: float = 0.95
# The two distances the lane is built around: 20 m is outside a fogged 48 m (48 x 0.25 = 12 m) and
# 8 m is inside it, so one world answers both halves of "a range, not a blindfold".
const FAR_M: int = 20
const NEAR_M: int = 8
# One spare tile past the far body, so the run is genuinely open at both ends of the sightline.
const RUN_TILES: int = 22
# The zombie lane's geometry: a survivor 3 m off is inside a shambler's 3.79 m and outside its
# fogged 0.95 m; the night lane's 8 m is inside its 12 m eyes and outside a fogged 3 m.
const EYES_M: int = 3
const NIGHT_M: int = 8
# The scent lane's window: the spine's, a hundred ticks -- twenty diffusion passes. It cannot be
# widened. Over two thousand ticks the district's own living and dead have breathed enough scent
# into the sample tile to swamp the decay and the fogged field measures *higher* than the clear
# one, which is a true reading of the wrong question. The fog's 0.8 is gentle, so what it leaves
# over twenty passes differs from a clear sky in the fourth significant figure; the fabricated
# identity below is what tells that gap from nothing rather than a threshold nobody can justify.
const SCENT_TICKS: int = 100


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_fog_is_content_and_the_number_is_read() and ok
	ok = _the_fog_closes_the_range_and_not_the_eyes() and ok
	ok = _the_dead_are_blinded_by_exactly_as_much() and ok
	ok = _what_is_not_seen_is_not_remembered() and ok
	ok = _the_fog_muffles_scent() and ok
	ok = _the_hud_says_the_fog_in_words() and ok
	ok = _the_fog_survives_a_save() and ok
	ok = _the_multiplier_is_read_where_it_belongs() and ok
	if ok:
		print("M2_FOG_OK the seventh kind: one content number closing every observer's range and a zombie's reach by the same factor, a body at 20 m lost and at 8 m kept, the night's lit escape closed, nothing seen and so nothing remembered, scent muffled, one sentence with no digit, and the parameter plumbed through boot and the shambler but never into the night wash")
		quit(0)
	else:
		push_error("M2_FOG_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# Through the one public path, so the event and the modifiers follow (weather.gd's set_kind).
func _force(w: Variant, k: String) -> void:
	SimWeather.set_kind(w, k, FAR)


func _a_forced_world(kind: String) -> Variant:
	var w: Variant = _world()
	_force(w, kind)
	return w


func _place(w: Variant, ent: int, tile: Vector2i) -> void:
	w.components.set_component(ent, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})


func _pos_of(w: Variant, ent: int) -> Vector2:
	var p: Variant = w.components.get_component(ent, "position")
	if not p is Dictionary:
		return Vector2(-1000.0, -1000.0)
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


# Open ground, in the sense this gate needs it: nothing solid, nothing that stops a sightline for a
# standing eye, and no roof over it. `is_solid` alone is not enough -- a Low tile is walkable and a
# crouched eye cannot see past it -- and the roof matters because the lane is about daylight.
func _open_outdoor(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	if SimTileMap.is_solid(map, tx, ty) or SimTileMap.is_indoors(map, tx, ty):
		return false
	return not SimTileMap.blocks_sight(map, tx, ty, SimTileMap.Eye.Standing)


# A straight run of `need` open outdoor tiles, as {x, y, dx, dy} for its first tile and its
# direction. Rows first, then columns. Empty when the district has none, which every caller
# treats as "this lane has nothing to judge" and fails on rather than skipping.
func _open_run(map: Variant, need: int) -> Dictionary:
	for axis in 2:
		var across: int = int(map.h) if axis == 0 else int(map.w)
		var along: int = int(map.w) if axis == 0 else int(map.h)
		for a in across:
			var run: int = 0
			for b in along:
				var tx: int = b if axis == 0 else a
				var ty: int = a if axis == 0 else b
				if _open_outdoor(map, tx, ty):
					run += 1
					if run >= need:
						var start: int = b - run + 1
						if axis == 0:
							return {"x": start, "y": a, "dx": 1, "dy": 0}
						return {"x": a, "y": start, "dx": 0, "dy": 1}
				else:
					run = 0
	return {}


# An open outdoor tile at least `away` metres from `from`, for parking bodies this lane does not
# want in the answer. Empty when the district has none.
func _far_tile(map: Variant, from: Vector2i, away: float) -> Vector2i:
	for ty in int(map.h):
		for tx in int(map.w):
			if not _open_outdoor(map, tx, ty):
				continue
			if Vector2(float(tx - from.x), float(ty - from.y)).length() >= away:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


# The district's own wanderers, out of the way. The `shambler` component goes rather than the
# entity: `entities.despawn` leaves every component in place and `components.query` does not check
# alive (CLAUDE.md), so a despawned body would still be gathered as a hostile by
# `SimSightings.observe` and still be steered by the shambler AI. Removing what is queried is the
# only removal that removes anything.
func _strip_zombies(w: Variant) -> int:
	var n: int = 0
	for ent in w.components.query(["shambler"]):
		w.components.remove(int(ent), "shambler")
		n += 1
	return n


func _people_besides(w: Variant, keep: int) -> Array:
	var out: Array = []
	for ent in w.components.query(["position"]):
		if int(ent) == keep or not SimAllegiance.is_person(w, int(ent)):
			continue
		if w.components.has_component(int(ent), "corpse"):
			continue
		out.append(int(ent))
	return out


func _visible_tiles(w: Variant, ent: int) -> int:
	var v: Variant = w.vision.call("tiles_for", ent)
	if v == null:
		return -1
	var n: int = 0
	var r: int = int(v.range_tiles)
	for ty in range(int(v.origin_y) - r, int(v.origin_y) + r + 1):
		for tx in range(int(v.origin_x) - r, int(v.origin_x) + r + 1):
			if bool(v.has_tile(tx, ty)):
				n += 1
	# The structure keeps its own tally; if the two disagree the count below means nothing.
	if n != int(v.count):
		push_error("TILES: walking the shadowcast found %d tiles where it counted %d" % [n, int(v.count)])
		return -1
	return n


# --- CONTENT --------------------------------------------------------------------------------

# The entry, the mirror, the accessor and the schema. The fabricated entries are the negatives on
# the validator: one with the wrong type for `sightMul` and one with a key the schema never
# declared, both refused, beside the shipped shape which raises nothing.
func _the_fog_is_content_and_the_number_is_read() -> bool:
	var w: Variant = _world()
	if not SimWeather.kinds(w).has("fog"):
		push_error("CONTENT: the tree declares %s -- no fog" % str(SimWeather.kinds(w)))
		return false
	var entry: Variant = (w.content as Dictionary).get(FOG_PATH)
	if not entry is Dictionary or String((entry as Dictionary).get("id", "")) != "weather.fog":
		push_error("CONTENT: %s is not loaded as weather.fog: %s" % [FOG_PATH, str(entry)])
		return false
	var e: Dictionary = entry as Dictionary
	var mul: float = float(e.get("sightMul", -1.0))
	var scent: float = float(e.get("scentHalfLifeMul", -1.0))
	if mul <= 0.0 or mul > 1.0:
		push_error("CONTENT: fog's sightMul %.4f is outside (0, 1]" % mul)
		return false
	if scent <= 0.0 or scent > 1.0:
		push_error("CONTENT: fog's scentHalfLifeMul %.4f is outside (0, 1]" % scent)
		return false
	# A fog is not weather that rains on you and not weather that stops a job: the two keys the
	# storm and the rain own must stay absent, or the kind quietly grew a second effect.
	for stray in ["wets", "outdoorWork"]:
		if e.has(stray):
			push_error("CONTENT: fog declares %s, which belongs to the rain and the storm" % stray)
			return false
	var span: Dictionary = e.get("durationTicks", {}) as Dictionary
	if int(span.get("min", 0)) <= 0 or int(span.get("min", 0)) >= int(span.get("max", 0)):
		push_error("CONTENT: fog's range is not 0 < min < max: %s" % str(span))
		return false
	var drawable: int = 0
	for season in SimWeather.SEASONS:
		var wt: float = SimWeather.weight_of(w, "fog", season)
		if wt < 0.0:
			push_error("CONTENT: fog weighs %.2f in %s" % [wt, season])
			return false
		if wt > 0.0:
			drawable += 1
	if drawable == 0:
		push_error("CONTENT: fog is weighted zero in every season, so it can never be drawn")
		return false
	# The booted world reads the entry rather than the mirror, and the two agree number for number.
	var mine: Dictionary = SimWeather.DEFAULTS.get("fog", {}) as Dictionary
	if mine.is_empty():
		push_error("CONTENT: SimWeather.DEFAULTS has no fog, so a fixture world with no tree has no fog to draw")
		return false
	if SimWeather.spec_of(w, "fog") == mine:
		push_error("CONTENT: the booted world reads SimWeather.DEFAULTS[fog] rather than the content entry")
		return false
	if not _same_numbers(mine, e):
		push_error("CONTENT: the mirrored default for fog drifted from content:\n %s\n %s" % [JSON.stringify(mine), JSON.stringify(e)])
		return false
	# The accessor: identity under a clear sky, exactly the content number under fog.
	var clear_mul: float = SimWeather.sight_mul(_world())
	var fog_mul: float = SimWeather.sight_mul(_a_forced_world("fog"))
	if absf(clear_mul - 1.0) > 0.000001:
		push_error("CONTENT: a clear sky's sight_mul is %.6f, not the identity" % clear_mul)
		return false
	if absf(fog_mul - mul) > 0.000001:
		push_error("CONTENT: sight_mul reads %.6f under fog where the content says %.6f" % [fog_mul, mul])
		return false
	# The validator. It is shallow by design (CLAUDE.md's trap: only the frozen oracle's Ajv
	# recurses and enforces the bounds), so what is asserted here is what it can actually judge --
	# the declared type and the closed key set -- and the *bounds* are asserted on the schema
	# itself, which is the document Ajv reads on `npm test`.
	var issues: Array[String] = ContentValidator.validate_tree()
	for issue in issues:
		if String(issue).contains("weather/"):
			push_error("CONTENT: the validator reports %s" % issue)
			return false
	var schemas: Dictionary = ContentValidator._load_schemas()
	if not schemas.has("weather"):
		push_error("CONTENT: no weather schema is registered, so the directory validates in silence")
		return false
	var schema: Dictionary = schemas["weather"] as Dictionary
	var props: Dictionary = schema.get("properties", {}) as Dictionary
	if not props.has("sightMul"):
		push_error("CONTENT: the weather schema does not declare sightMul, so the entry rides on additionalProperties")
		return false
	var decl: Dictionary = props["sightMul"] as Dictionary
	if String(decl.get("type", "")) != "number" or absf(float(decl.get("exclusiveMinimum", -1.0))) > 0.000001 or absf(float(decl.get("maximum", -1.0)) - 1.0) > 0.000001:
		push_error("CONTENT: the schema's sightMul is %s -- the (0, 1] bound the oracle's Ajv enforces is not declared" % str(decl))
		return false
	# Positive: the shipped shape raises nothing through the shallow path either.
	var good: Dictionary = e.duplicate(true)
	if not ContentValidator._validate_shape(good, schema, "weather/fog.json").is_empty():
		push_error("CONTENT: the shipped fog entry raises %s" % str(ContentValidator._validate_shape(good, schema, "weather/fog.json")))
		return false
	# Negative one: sightMul with the wrong type. Negative two: a key the schema never declared.
	var bad_type: Dictionary = e.duplicate(true)
	bad_type["sightMul"] = "thick"
	if ContentValidator._validate_shape(bad_type, schema, "weather/fake.json").is_empty():
		push_error("CONTENT: a fabricated fog entry with sightMul: \"thick\" raised nothing")
		return false
	var bad_key: Dictionary = e.duplicate(true)
	bad_key["visibility"] = 0.25
	if ContentValidator._validate_shape(bad_key, schema, "weather/fake.json").is_empty():
		push_error("CONTENT: a fabricated fog entry with a stray key raised nothing")
		return false
	print("CONTENT OK weather.fog sightMul %.2f, scentHalfLifeMul %.2f, span %d..%d, drawable in %d of 4 seasons, no wets and no outdoorWork; the mirror agrees; sight_mul reads %.2f clear and %.2f under fog; the schema declares number in (%.0f, %.0f] and the shallow validator refuses a wrong type and a stray key" % [mul, scent, int(span["min"]), int(span["max"]), drawable, clear_mul, fog_mul, float(decl.get("exclusiveMinimum", 0.0)), float(decl.get("maximum", 1.0))])
	return true


# The mirror and the JSON entry compared as what they mean: every number, bool and list the mirror
# holds equal in the entry within a tolerance, ints as floats -- the parser hands back floats where
# the mirror holds ints -- and the entry's id and description ignored. check_m2_weather.gd's shape.
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


# --- the staged sightline -------------------------------------------------------------------

# One colonist and one or two shambler bodies on a straight open outdoor line at noon, stepped
# under `kind`. `override_mul` >= 0 rewrites the world's own fog entry before the sky is forced,
# which is the negative that separates "the fog closes eyes" from "the number closes eyes".
#
# The bodies are re-placed before every step and the answer is measured against where they
# actually ended up: `movement.integrate` runs at order 0 and `kernel.visibility` at 100, so the
# cast is taken a tick's drift after the placement, and a lane that asserted on the placement
# rather than the position would be asserting on a number the sim never used.
func _stage(kind: String, override_mul: float, want_near: bool) -> Dictionary:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, NOON)
	var run: Dictionary = _open_run(w.tilemap, RUN_TILES)
	if run.is_empty():
		push_error("STAGE: the booted district has no straight run of %d open outdoor tiles, so there is no %d m sightline to judge" % [RUN_TILES, FAR_M])
		return {}
	var dx: int = int(run["dx"])
	var dy: int = int(run["dy"])
	var me := Vector2i(int(run["x"]), int(run["y"]))
	var far_t := Vector2i(me.x + dx * FAR_M, me.y + dy * FAR_M)
	var near_t := Vector2i(me.x + dx * NEAR_M, me.y + dy * NEAR_M)
	var stripped: int = _strip_zombies(w)
	var rng: Variant = w.rng.stream("shambler")
	var far_z: int = SimRoster.spawn_zombie(w, float(far_t.x) + 0.5, float(far_t.y) + 0.5, SimRoster.TYPE_SHAMBLER, rng)
	var near_z: int = -1
	if want_near:
		near_z = SimRoster.spawn_zombie(w, float(near_t.x) + 0.5, float(near_t.y) + 0.5, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	var e: int = int(w.player)
	w.components.set_component(e, "facing", {"radians": atan2(float(dy), float(dx))})
	if override_mul >= 0.0:
		var fab: Dictionary = ((w.content as Dictionary)[FOG_PATH] as Dictionary).duplicate(true)
		fab["sightMul"] = override_mul
		(w.content as Dictionary)[FOG_PATH] = fab
	if kind != "clear":
		_force(w, kind)
	for _i in 4:
		_place(w, e, me)
		_place(w, far_z, far_t)
		if near_z >= 0:
			_place(w, near_z, near_t)
		w.step()
	var at_me: Vector2 = _pos_of(w, e)
	var at_far: Vector2 = _pos_of(w, far_z)
	var out: Dictionary = {
		"w": w, "player": e, "far": far_z, "near": near_z,
		"me": me, "far_tile": far_t, "near_tile": near_t,
		"stripped": stripped,
		"mul": SimWeather.sight_mul(w),
		"far_dist": at_me.distance_to(at_far),
		"far_detail": int(w.vision.call("detail", e, at_far.x, at_far.y)),
		"far_los": bool(w.vision.call("line_of_sight", e, at_far.x, at_far.y)),
		"tiles": _visible_tiles(w, e),
	}
	if near_z >= 0:
		var at_near: Vector2 = _pos_of(w, near_z)
		out["near_dist"] = at_me.distance_to(at_near)
		out["near_detail"] = int(w.vision.call("detail", e, at_near.x, at_near.y))
	return out


# --- SIGHT ----------------------------------------------------------------------------------

func _the_fog_closes_the_range_and_not_the_eyes() -> bool:
	var clear: Dictionary = _stage("clear", -1.0, true)
	var fog: Dictionary = _stage("fog", -1.0, true)
	var fake: Dictionary = _stage("fog", 1.0, true)
	if clear.is_empty() or fog.is_empty() or fake.is_empty():
		return false
	# Positive: under a clear sky the far body is both seen and shootable.
	if int(clear["far_detail"]) == SimVisibility.Detail.Unseen or not bool(clear["far_los"]):
		push_error("SIGHT: under a clear sky a body %.1f m off on open ground was unseen (detail %d, line_of_sight %s) -- this lane has no positive" % [float(clear["far_dist"]), int(clear["far_detail"]), str(clear["far_los"])])
		return false
	if float(clear["far_dist"]) < float(FAR_M) - 1.0 or float(clear["far_dist"]) > float(FAR_M) + 1.0:
		push_error("SIGHT: the far body ended up %.2f m off, not the %d m this lane is built on" % [float(clear["far_dist"]), FAR_M])
		return false
	# Negative: the same geometry under fog, and both answers move together.
	if int(fog["far_detail"]) != SimVisibility.Detail.Unseen or bool(fog["far_los"]):
		push_error("SIGHT: under fog a body %.2f m off was still seen (detail %d, line_of_sight %s) with sight_mul %.2f" % [float(fog["far_dist"]), int(fog["far_detail"]), str(fog["far_los"]), float(fog["mul"])])
		return false
	# A range, not a blindfold: inside the fogged reach the same eyes work as they always did.
	if int(fog["near_detail"]) == SimVisibility.Detail.Unseen:
		push_error("SIGHT: under fog a body %.2f m off was lost too -- that is a blindfold, not a range" % float(fog["near_dist"]))
		return false
	if int(clear["near_detail"]) == SimVisibility.Detail.Unseen:
		push_error("SIGHT: the near body was unseen under a clear sky, so the fog's near case proves nothing")
		return false
	# The shadowcast itself shrank: the pool the roofs and the light wash key on is smaller.
	if int(clear["tiles"]) < 0 or int(fog["tiles"]) < 0:
		return false
	if int(fog["tiles"]) >= int(clear["tiles"]):
		push_error("SIGHT: the visible pool is %d tiles under fog and %d under clear -- the cast did not close" % [int(fog["tiles"]), int(clear["tiles"])])
		return false
	# The number, not the name. A fog whose content says 1.0 hides nothing at all.
	if absf(float(fake["mul"]) - 1.0) > 0.000001:
		push_error("SIGHT: the fabricated fog reads sight_mul %.4f, so its case judges nothing" % float(fake["mul"]))
		return false
	if int(fake["far_detail"]) == SimVisibility.Detail.Unseen or not bool(fake["far_los"]):
		push_error("SIGHT: under a fog whose content says sightMul 1.0 the %.2f m body was lost anyway -- the kind's name is closing the eyes, not the number" % float(fake["far_dist"]))
		return false
	if int(fake["tiles"]) != int(clear["tiles"]):
		push_error("SIGHT: a fog at sightMul 1.0 sees %d tiles where a clear sky sees %d" % [int(fake["tiles"]), int(clear["tiles"])])
		return false
	print("SIGHT OK %d wanderers stripped; clear: %.2f m detail %d los %s, %d tiles; fog (x%.2f): %.2f m detail %d los %s, %d tiles, and %.2f m still detail %d; a fabricated fog at x1.00 keeps the far body (detail %d) and all %d tiles" % [int(clear["stripped"]), float(clear["far_dist"]), int(clear["far_detail"]), str(clear["far_los"]), int(clear["tiles"]), float(fog["mul"]), float(fog["far_dist"]), int(fog["far_detail"]), str(fog["far_los"]), int(fog["tiles"]), float(fog["near_dist"]), int(fog["near_detail"]), int(fake["far_detail"]), int(fake["tiles"])])
	return true


# --- EYES -----------------------------------------------------------------------------------

# The other half of the symmetry. `SIGHT_ENABLED` is a gate-drivable static shared by every world
# this process boots (CLAUDE.md), so it is pinned for the lane and restored on every exit path --
# including the failing ones, which is why the body is a separate function.
func _the_dead_are_blinded_by_exactly_as_much() -> bool:
	var was: bool = SimShambler.SIGHT_ENABLED
	SimShambler.SIGHT_ENABLED = true
	var ok: bool = _eyes_body()
	SimShambler.SIGHT_ENABLED = was
	if not ok:
		return false
	print("EYES OK SIGHT_ENABLED restored to %s" % str(was))
	return true


func _eyes_body() -> bool:
	var day: Dictionary = {}
	for kind in ["clear", "fog"]:
		var r: Dictionary = _zombie_reading(kind)
		if r.is_empty():
			return false
		day[kind] = r
	var clear: Dictionary = day["clear"] as Dictionary
	var fog: Dictionary = day["fog"] as Dictionary
	var want_clear: float = 12.0 * sqrt(0.1)
	if absf(float(clear["reach"]) - want_clear) > 0.01:
		push_error("EYES: a shambler's reach under a clear sky is %.4f m, wanted %.4f (12 m eyes, sensory.light 0.1)" % [float(clear["reach"]), want_clear])
		return false
	var mul: float = SimWeather.sight_mul(_a_forced_world("fog"))
	if absf(float(fog["reach"]) - want_clear * mul) > 0.000001:
		push_error("EYES: the fogged reach is %.4f m where clear x%.4f is %.4f" % [float(fog["reach"]), mul, want_clear * mul])
		return false
	if absf(float(fog["reach"]) / float(clear["reach"]) - mul) > 0.000001:
		push_error("EYES: the reach ratio is %.8f and the content says %.8f" % [float(fog["reach"]) / float(clear["reach"]), mul])
		return false
	# The reach is a number until something reads it. `_seen_target` is the read.
	if int(clear["seen"]) != int(clear["survivor"]):
		push_error("EYES: with a survivor %.2f m in front of it a shambler saw %d, wanted %d" % [float(clear["dist"]), int(clear["seen"]), int(clear["survivor"])])
		return false
	if int(fog["seen"]) != -1:
		push_error("EYES: in fog (reach %.2f m) a shambler still saw a survivor %.2f m off" % [float(fog["reach"]), float(fog["dist"])])
		return false
	if int(clear["detail"]) == SimVisibility.Detail.Unseen:
		push_error("EYES: the survivor was not even visible to the zombie under a clear sky, so the fog case proves nothing")
		return false
	# Night: the lit-target escape. A survivor standing in a light 8 m off is seen through the dark
	# because `full_squared` is the eyes' full 12 m; under fog that reach is 3 m and the escape
	# closes with it. The unlit case is the negative that says it was the light doing the work.
	var night: Dictionary = {}
	for case in ["clear-lit", "clear-dark", "fog-lit"]:
		var r2: Dictionary = _night_reading("fog" if case.begins_with("fog") else "clear", case.ends_with("lit"))
		if r2.is_empty():
			return false
		night[case] = r2
	var lit: Dictionary = night["clear-lit"] as Dictionary
	var dark: Dictionary = night["clear-dark"] as Dictionary
	var fog_lit: Dictionary = night["fog-lit"] as Dictionary
	if float(lit["ambient"]) > 0.1:
		push_error("EYES: the night fixture reads ambient %.3f -- it is not dark" % float(lit["ambient"]))
		return false
	if int(lit["detail"]) == SimVisibility.Detail.Unseen:
		push_error("EYES: a lit survivor %.2f m off after dark was unseen under a clear sky -- the escape this lane closes does not exist" % float(lit["dist"]))
		return false
	if int(dark["detail"]) != SimVisibility.Detail.Unseen:
		push_error("EYES: an unlit survivor %.2f m off after dark was seen -- the night is not dark, so the lit case proves nothing" % float(dark["dist"]))
		return false
	if int(fog_lit["detail"]) != SimVisibility.Detail.Unseen:
		push_error("EYES: in fog a lit survivor %.2f m off was still seen after dark -- full_squared did not shrink" % float(fog_lit["dist"]))
		return false
	print("EYES OK reach %.4f m clear and %.4f m fog (ratio %.4f, content %.4f); at %.2f m _seen_target returns %d clear (detail %d) and null in fog; at night ambient %.3f a lit survivor %.2f m off reads detail %d clear, %d unlit, %d in fog" % [float(clear["reach"]), float(fog["reach"]), float(fog["reach"]) / float(clear["reach"]), mul, float(clear["dist"]), int(clear["seen"]), int(clear["detail"]), float(lit["ambient"]), float(lit["dist"]), int(lit["detail"]), int(dark["detail"]), int(fog_lit["detail"])])
	return true


# One shambler with the player EYES_M metres in front of it in daylight, every other person parked
# far enough away that `_seen_target`'s nearest-first answer can only be the player.
func _zombie_reading(kind: String) -> Dictionary:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, NOON)
	var run: Dictionary = _open_run(w.tilemap, EYES_M + 3)
	if run.is_empty():
		push_error("EYES: no straight run of %d open outdoor tiles to stand a zombie and a survivor on" % (EYES_M + 3))
		return {}
	var dx: int = int(run["dx"])
	var dy: int = int(run["dy"])
	var z_tile := Vector2i(int(run["x"]), int(run["y"]))
	var s_tile := Vector2i(z_tile.x + dx * EYES_M, z_tile.y + dy * EYES_M)
	var exile: Vector2i = _far_tile(w.tilemap, z_tile, 30.0)
	if exile.x < 0:
		push_error("EYES: no open outdoor tile 30 m from the lane to park the other colonists on")
		return {}
	_strip_zombies(w)
	var z: int = SimRoster.spawn_zombie(w, float(z_tile.x) + 0.5, float(z_tile.y) + 0.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	if not w.components.has_component(z, "observer"):
		push_error("EYES: the spawned shambler has no observer")
		return {}
	w.components.set_component(z, "facing", {"radians": atan2(float(dy), float(dx))})
	var e: int = int(w.player)
	var others: Array = _people_besides(w, e)
	if kind != "clear":
		_force(w, kind)
	for _i in 4:
		_place(w, e, s_tile)
		_place(w, z, z_tile)
		for o in others:
			_place(w, int(o), exile)
		w.step()
	var sd: Variant = w.components.get_component(z, "shambler")
	if not sd is Dictionary:
		push_error("EYES: the shambler component is gone")
		return {}
	var survivors: Array = SimShambler._gather_survivors(w)
	var seen: Variant = SimShambler._seen_target(w, z, survivors, sd as Dictionary)
	var at_z: Vector2 = _pos_of(w, z)
	var at_s: Vector2 = _pos_of(w, e)
	return {
		"reach": SimShambler.sight_reach(w, z, sd as Dictionary),
		"seen": int(seen) if seen != null else -1,
		"survivor": e,
		"dist": at_z.distance_to(at_s),
		"detail": int(w.vision.call("detail", z, at_s.x, at_s.y)),
		"others": others.size(),
	}


# The same pair after dark, NIGHT_M apart, with a lamp on the survivor's own tile when `lamp`.
func _night_reading(kind: String, lamp: bool) -> Dictionary:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(1, NIGHT)
	var run: Dictionary = _open_run(w.tilemap, NIGHT_M + 3)
	if run.is_empty():
		push_error("EYES: no straight run of %d open outdoor tiles for the night lane" % (NIGHT_M + 3))
		return {}
	var dx: int = int(run["dx"])
	var dy: int = int(run["dy"])
	var z_tile := Vector2i(int(run["x"]), int(run["y"]))
	var s_tile := Vector2i(z_tile.x + dx * NIGHT_M, z_tile.y + dy * NIGHT_M)
	_strip_zombies(w)
	var z: int = SimRoster.spawn_zombie(w, float(z_tile.x) + 0.5, float(z_tile.y) + 0.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	w.components.set_component(z, "facing", {"radians": atan2(float(dy), float(dx))})
	var e: int = int(w.player)
	# Every other light out, so the only thing lighting the survivor is this lane's own lamp.
	for src in w.components.query(["light_source"]):
		w.components.remove(int(src), "light_source")
	var torch: int = -1
	if lamp:
		torch = int(w.entities.spawn())
		SimLightModule.make_light_source(w, torch, 6.0)
	if kind != "clear":
		_force(w, kind)
	for _i in 4:
		_place(w, e, s_tile)
		_place(w, z, z_tile)
		if torch >= 0:
			_place(w, torch, s_tile)
		w.step()
	var at_z: Vector2 = _pos_of(w, z)
	var at_s: Vector2 = _pos_of(w, e)
	return {
		"ambient": Clock.ambient_light_at(int(w.tick)),
		"dist": at_z.distance_to(at_s),
		"detail": int(w.vision.call("detail", z, at_s.x, at_s.y)),
		"lit": float(w.light.lit_metres(at_s.x, at_s.y)) if w.light != null else -1.0,
	}


# --- MEMORY ---------------------------------------------------------------------------------

# One layer downstream: `SimSightings` records what `line_of_sight` answers, so a body the fog
# hides is a body the colony never knew was there, and the prose that reads that memory says
# nothing. The clear-sky world is the control for both halves.
func _what_is_not_seen_is_not_remembered() -> bool:
	var clear: Dictionary = _stage("clear", -1.0, false)
	var fog: Dictionary = _stage("fog", -1.0, false)
	if clear.is_empty() or fog.is_empty():
		return false
	var clear_rows: Array = SimSightings.remembered(clear["w"], int(clear["player"]))
	var fog_rows: Array = SimSightings.remembered(fog["w"], int(fog["player"]))
	var clear_has: bool = SimSightings.recall(clear["w"], int(clear["player"]), int(clear["far"])) != null
	var fog_has: bool = SimSightings.recall(fog["w"], int(fog["player"]), int(fog["far"])) != null
	if not clear_has:
		push_error("MEMORY: under a clear sky a body %.2f m off in plain view was not remembered (%d records) -- this lane has no positive" % [float(clear["far_dist"]), clear_rows.size()])
		return false
	if fog_has:
		push_error("MEMORY: under fog a body %.2f m off was remembered anyway (%d records)" % [float(fog["far_dist"]), fog_rows.size()])
		return false
	if not fog_rows.is_empty():
		push_error("MEMORY: the fogged colonist remembers %s, and this lane left only the one body standing" % str(fog_rows))
		return false
	var clear_line: String = SimSightings.clause(clear["w"], int(clear["player"]))
	var fog_line: String = SimSightings.clause(fog["w"], int(fog["player"]))
	if clear_line.is_empty():
		push_error("MEMORY: the clear-sky clause is empty with a body remembered, so the fog's silence proves nothing")
		return false
	if not fog_line.is_empty():
		push_error("MEMORY: the fogged colonist still says '%s'" % fog_line)
		return false
	print("MEMORY OK clear: %d record(s), the %.2f m body among them, clause '%s'; fog: %d records, no recall of it, clause ''" % [clear_rows.size(), float(clear["far_dist"]), clear_line, fog_rows.size()])
	return true


# --- SCENT ----------------------------------------------------------------------------------

# The fog's second effect, and the reason it is not a pure sight kind: scentHalfLifeMul 0.8 muffles
# the field a little. Measured on the field, with a clear sky and a world with no weather at all as
# the two controls -- check_m2_weather.gd's SCENT shape.
func _the_fog_muffles_scent() -> bool:
	var fog: Variant = _world()
	var dry: Variant = _world()
	var still: Variant = _world()
	# The fourth world is the one that makes the other three mean something: a fog in every respect
	# except that its content says the half-life is unchanged. It is the fogged world's own twin --
	# same kind, so the same draw off the `weather` stream and the same wind leaning the same four
	# diffusion weights -- and the only thing left between them is the number under test.
	var sham: Variant = _world()
	_force(fog, "fog")
	(still.weather as Dictionary).clear()
	var fab: Dictionary = ((sham.content as Dictionary)[FOG_PATH] as Dictionary).duplicate(true)
	fab["scentHalfLifeMul"] = 1.0
	(sham.content as Dictionary)[FOG_PATH] = fab
	_force(sham, "fog")
	var run: Dictionary = _open_run(fog.tilemap, 2)
	if run.is_empty():
		push_error("SCENT: no open outdoor tile to lay scent on")
		return false
	var x: float = float(int(run["x"])) + 0.5
	var y: float = float(int(run["y"])) + 0.5
	for w in [fog, dry, still, sham]:
		w.tick = Clock.tick_on_day(1, 0.3)
		w.field.add_scent(x, y, 500.0)
	for _i in SCENT_TICKS:
		fog.step()
		dry.step()
		still.step()
		sham.step()
	var s_fog: float = float(fog.field.scent_at(x, y))
	var s_dry: float = float(dry.field.scent_at(x, y))
	var s_still: float = float(still.field.scent_at(x, y))
	var s_sham: float = float(sham.field.scent_at(x, y))
	if s_dry <= 0.0:
		push_error("SCENT: the clear-sky field lost all of its scent, so there is nothing to compare")
		return false
	if s_fog >= s_dry:
		push_error("SCENT: fog left %.4f against a clear %.4f -- it muffled nothing" % [s_fog, s_dry])
		return false
	if absf(s_dry - s_still) > 0.000001:
		push_error("SCENT: a clear sky costs the field something: %.6f with weather, %.6f with none" % [s_dry, s_still])
		return false
	var mul: float = SimWeather.scent_half_life_mul(fog)
	if absf(SimWeather.scent_half_life_mul(dry) - 1.0) > 0.000001 or mul >= 1.0 or mul <= 0.0:
		push_error("SCENT: the multipliers read clear %.3f / fog %.3f" % [SimWeather.scent_half_life_mul(dry), mul])
		return false
	# A muffle, not a wash: the rain's own gate holds the line at half, and fog is gentler still.
	if s_fog < 0.5 * s_dry:
		push_error("SCENT: fog left %.4f of a clear %.4f over %d ticks -- that is the rain's wash, not a muffle" % [s_fog, s_dry, SCENT_TICKS])
		return false
	# The gap is the number and nothing else. Against its own twin the fogged field must sit lower,
	# and by enough to tell from what a forced kind moves for free: forcing any kind re-rolls the
	# wind off the `weather` stream, and a differently-leaning wind is worth a few parts in ten
	# million here (`s_sham` against `s_dry`, printed). The half-life is worth hundreds of times
	# that, so a first cut that quietly became the identity lands in the noise and fails.
	var wind_noise: float = absf(s_sham - s_dry)
	var by_the_number: float = s_sham - s_fog
	if by_the_number <= 0.0:
		push_error("SCENT: against its own twin at x1.00 the fogged field is %.6f and the twin %.6f -- the multiplier moved nothing" % [s_fog, s_sham])
		return false
	if by_the_number < 10.0 * wind_noise:
		push_error("SCENT: the half-life is worth %.8f against its twin where the wind alone is worth %.8f -- that is not a gap, it is the draw" % [by_the_number, wind_noise])
		return false
	if s_dry - s_fog <= 0.0:
		push_error("SCENT: the fogged field is %.6f and the clear one %.6f -- no gap at all" % [s_fog, s_dry])
		return false
	print("SCENT OK over %d ticks (twenty diffusion passes) fog leaves %.4f where a clear sky leaves %.4f (gap %.6f) at half-life x%.2f; a clear sky equals no weather at all (%.6f vs %.6f) and against its own twin at x1.00 (%.6f) the number alone is worth %.6f, %.0fx what re-rolling the wind is worth (%.8f)" % [SCENT_TICKS, s_fog, s_dry, s_dry - s_fog, mul, s_dry, s_still, s_sham, by_the_number, by_the_number / maxf(wind_noise, 0.000000001), wind_noise])
	return true


# --- HUD ------------------------------------------------------------------------------------

func _the_hud_says_the_fog_in_words() -> bool:
	var line: String = "Fog has closed in."
	if SimWeather.hud_clause(_world()) != "":
		push_error("HUD: a clear world's clause is not empty")
		return false
	var w: Variant = _world()
	w.step()
	_force(w, "fog")
	if SimWeather.hud_clause(w) != line:
		push_error("HUD: the fog's clause is '%s', wanted '%s'" % [SimWeather.hud_clause(w), line])
		return false
	for ch in line:
		if String(ch).is_valid_int():
			push_error("HUD: the fog line carries a digit: '%s'" % line)
			return false
	# No other kind may take this sentence, or the screen cannot tell them apart.
	for k in SimWeather.kinds(w):
		if k == "fog":
			continue
		var other: Variant = _a_forced_world(k)
		if SimWeather.hud_clause(other) == line:
			push_error("HUD: %s also says '%s'" % [k, line])
			return false
	# And it reaches the screen's world column, which a clause nothing renders would not.
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var under_fog: Array = (hud.get("_right") as Array).duplicate()
	_force(w, "clear")
	hud.call("refresh", w, w.player, "")
	var under_clear: Array = (hud.get("_right") as Array).duplicate()
	hud.queue_free()
	if not under_fog.has(line):
		push_error("HUD: the world column does not carry '%s' under fog: %s" % [line, str(under_fog)])
		return false
	if under_clear.has(line):
		push_error("HUD: the world column carries the fog's sentence under a clear sky: %s" % str(under_clear))
		return false
	print("HUD OK '%s' under fog and not under clear, no digits, and no other of the %d kinds shares it" % [line, SimWeather.kinds(w).size()])
	return true


# --- ROUND-TRIP -----------------------------------------------------------------------------

# The sky is state, and the multiplier is derived from it every tick rather than latched anywhere,
# so a restored fog has to close the range on the very first step after the restore with nothing
# else re-applied. The clear snapshot restored into the same fresh world is the negative.
func _the_fog_survives_a_save() -> bool:
	var readings: Dictionary = {}
	for kind in ["fog", "clear"]:
		var staged: Dictionary = _stage(kind, -1.0, false)
		if staged.is_empty():
			return false
		var w: Variant = staged["w"]
		var snap: Dictionary = w.snapshot()
		var txt: String = w.serialize()
		var w2: Variant = _world()
		w2.restore(snap)
		for k in (w.weather as Dictionary).keys():
			if str((w.weather as Dictionary)[k]) != str((w2.weather as Dictionary).get(k)):
				push_error("ROUND-TRIP: weather %s restored as %s" % [str(w.weather), str(w2.weather)])
				return false
		if w2.serialize() != txt:
			push_error("ROUND-TRIP: the serialisation differs after restore under %s" % kind)
			return false
		if SimWeather.kind(w2) != kind:
			push_error("ROUND-TRIP: %s restored as %s" % [kind, SimWeather.kind(w2)])
			return false
		# One step, no help: the first refresh after the restore reads the restored kind.
		_place(w2, int(staged["player"]), staged["me"] as Vector2i)
		_place(w2, int(staged["far"]), staged["far_tile"] as Vector2i)
		w2.step()
		var at_me: Vector2 = _pos_of(w2, int(staged["player"]))
		var at_far: Vector2 = _pos_of(w2, int(staged["far"]))
		readings[kind] = {
			"mul": SimWeather.sight_mul(w2),
			"dist": at_me.distance_to(at_far),
			"detail": int(w2.vision.call("detail", int(staged["player"]), at_far.x, at_far.y)),
			"tiles": _visible_tiles(w2, int(staged["player"])),
		}
	var fog: Dictionary = readings["fog"] as Dictionary
	var clear: Dictionary = readings["clear"] as Dictionary
	if int(clear["detail"]) == SimVisibility.Detail.Unseen:
		push_error("ROUND-TRIP: a clear sky restored and the %.2f m body was unseen on the first step -- the control is broken" % float(clear["dist"]))
		return false
	if int(fog["detail"]) != SimVisibility.Detail.Unseen:
		push_error("ROUND-TRIP: a fog restored (x%.2f) and the %.2f m body was still seen on the first step" % [float(fog["mul"]), float(fog["dist"])])
		return false
	if int(fog["tiles"]) < 0 or int(clear["tiles"]) < 0 or int(fog["tiles"]) >= int(clear["tiles"]):
		push_error("ROUND-TRIP: the restored pools are %d tiles fogged and %d clear" % [int(fog["tiles"]), int(clear["tiles"])])
		return false
	print("ROUND-TRIP OK fog survives the snapshot and on the first step after restore reads x%.2f, %d tiles and detail %d at %.2f m; the clear save restores to x%.2f, %d tiles and detail %d at %.2f m" % [float(fog["mul"]), int(fog["tiles"]), int(fog["detail"]), float(fog["dist"]), float(clear["mul"]), int(clear["tiles"]), int(clear["detail"]), float(clear["dist"])])
	return true


# --- SOCKET ---------------------------------------------------------------------------------

# Where the parameter is allowed to be read, and where it is not. `_sight_metres` and
# `SimLight.sight_metres` return a *ratio* against `range_metres` that the presentation uses as the
# alpha of the night wash: a fog folded in there would paint midday in the night's colour, which is
# a bug no sim assertion above could see. Textual, so the scanner is proved on a fabricated body
# first -- a `_function_body` that silently returned "" would pass every negative here.
func _the_multiplier_is_read_where_it_belongs() -> bool:
	var boot: String = "res://sim/boot.gd"
	var shambler: String = "res://sim/modules/shambler.gd"
	var vis: String = "res://sim/vision/visibility.gd"
	var wash: String = "res://sim/vision/light.gd"
	# Prove the scanner: a name that does not exist returns nothing, and a name that does returns
	# something with a line of that function's own code in it.
	if not _function_body(boot, "_no_such_function_at_all").is_empty():
		push_error("SOCKET: the scanner returned text for a function that does not exist")
		return false
	var probe: String = _function_body(vis, "tiles_for")
	if probe.is_empty() or not probe.contains("_views.get(observer)"):
		push_error("SOCKET: the scanner cannot read a function it is pointed at: '%s'" % probe)
		return false
	var reads: Array = [
		[boot, "_refresh_vision", "SimWeather.sight_mul("],
		[shambler, "sight_reach", "sight_mul("],
		[vis, "refresh", "sight_mul"],
	]
	for row in reads:
		var r: Array = row as Array
		var body: String = _code_of(String(r[0]), String(r[1]))
		if body.is_empty():
			push_error("SOCKET: %s has no %s" % [String(r[0]), String(r[1])])
			return false
		if not body.contains(String(r[2])):
			push_error("SOCKET: %s's %s does not read %s -- the fog reaches nothing through it" % [String(r[0]), String(r[1]), String(r[2])])
			return false
	var bans: Array = [[vis, "_sight_metres"], [wash, "sight_metres"]]
	for row2 in bans:
		var r2: Array = row2 as Array
		var body2: String = _code_of(String(r2[0]), String(r2[1]))
		if body2.is_empty():
			push_error("SOCKET: %s has no %s" % [String(r2[0]), String(r2[1])])
			return false
		if body2.contains("sight_mul"):
			push_error("SOCKET: %s's %s reads sight_mul -- that ratio is the night wash's alpha, and a fog folded into it paints midday in the night's colour" % [String(r2[0]), String(r2[1])])
			return false
	print("SOCKET OK boot._refresh_vision and shambler.sight_reach read sight_mul, visibility.refresh carries it, and neither visibility._sight_metres nor light.sight_metres mentions it; the scanner reads %d lines of a known body and nothing of an unknown one" % probe.split("\n").size())
	return true


# One function's body, from the `func` line to the next one. `static func` counts as both a start
# and a terminator -- half the functions this lane reads are statics -- and the comment lines are
# dropped, so what is asserted on is the code and never the prose beside it. Borrowed from
# check_weather.gd rather than imported: a gate that reaches into another gate for a helper is one
# edit away from failing for a reason that has nothing to do with what it tests.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


func _code_of(path: String, name: String) -> String:
	var out: String = ""
	for line in _function_body(path, name).split("\n"):
		var trimmed: String = String(line).strip_edges()
		if trimmed.begins_with("#"):
			continue
		out += line + "\n"
	return out

extends SceneTree
# The weather slice: the accent regrade and the rain layer, docs/30's "Rain is ambience, not
# weather". Two families of claim, and both pass by accident without their negatives. A palette
# lane that only checks the new values passes against a revert to the bright table -- so lane A
# carries the OLD values through the same predicates and requires each to be refused, the
# check_road_look.gd convention. And a rain layer is exactly the kind of mechanism that can be
# complete, correct and read by nothing -- so lanes B and D are dead-socket scans proving the
# draw loop reaches the keys and the resolver, in the order the slice decided (entities, then
# rain, then the night wash).
#
# check_light_look.gd owns the other half of the draw order (district -> pools -> entities) and
# _draw_night_wash's wash_alpha assertion; lane D names it as the standing co-assertion rather
# than duplicating it here.
#
# Five lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const RainLook = preload("res://presentation/rain_look.gd")
const Palette = preload("res://presentation/palette.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const PALETTE_GD: String = "res://presentation/palette.gd"
const RAIN_GD: String = "res://presentation/rain_look.gd"
const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const DAY_TICKS: float = 288000.0
const EPS: float = 0.000001

# The gate's own wall clock, docs/00 pillar 6: one 64-tile boot and a few thousand pure
# evaluations, so the headroom is for a loaded CI box, not for new boots.
const BUDGET_SECONDS: float = 60.0

var _stash: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _the_accents_are_muted_and_can_say_no() and ok
	ok = _the_dead_keys_are_wired_and_the_dead_constants_are_gone() and ok
	ok = _the_rain_is_pure_and_deterministic() and ok
	ok = _the_rain_is_wired_and_ordered() and ok
	ok = _the_roof_stops_the_rain() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_weather ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"WEATHER_OK accents muted with the bright table refused (window S%.3f V%.3f, groundItem V%.3f over the brightest ground %.3f), lamp pools pinned warm; three dead keys wired and five dead constants gone; rain hashed not drawn -- %d streaks, intensity in [%.2f, %.2f] over a day, pixel-centred and falling; entities -> rain -> wash ascending; %d roofed tiles stop it beside %d open ones on suburb@%d; %.1f s of a %.0f s budget"
				% [
					(Palette.COLOURS["window"] as Color).s,
					(Palette.COLOURS["window"] as Color).v,
					(Palette.COLOURS["groundItem"] as Color).v,
					float(_stash.get("brightest_ground", 0.0)),
					RainLook.STREAK_COUNT,
					float(_stash.get("intensity_min", 0.0)),
					float(_stash.get("intensity_max", 0.0)),
					int(_stash.get("indoor_tiles", 0)),
					int(_stash.get("outdoor_tiles", 0)),
					GATE_SIZE,
					seconds,
					BUDGET_SECONDS,
				]
			)
		)
		quit(0)
	else:
		push_error("WEATHER_FAIL")
		quit(1)


# --- lane A: the accent table ------------------------------------------------------------------

# Every bound is a property, never a hex pin, so tuning inside the mood stays legal; and every
# OLD value goes through the same predicate and must be refused, so a revert to the bright grade
# is provably caught rather than noticed in a screenshot.


func _rgb_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


# Window glass: muted and mid-dark, an overcast pane rather than a lit aquarium.
func _window_ok(c: Color) -> bool:
	return c.s <= 0.35 and c.v >= 0.40 and c.v <= 0.65


# The rim is district paint like the glass, so it shares the saturation band but may sit darker
# (a sash) or brighter (a sill) than the pane -- what it may never be is the pane's own value,
# which the separation bound below holds.
func _rim_ok(c: Color) -> bool:
	return c.s <= 0.35 and c.v >= 0.40 and c.v <= 0.75


# A ground item has to be findable, so it keeps more value than the street -- the floor below
# holds that -- but no longer reads as a gold coin on wet asphalt.
func _ground_item_ok(c: Color) -> bool:
	return c.s <= 0.38 and c.v <= 0.72


# The screen's own marks (facing line, aim cone, rain): light enough to read as marks, never
# white, never saturated.
func _mark_ok(c: Color) -> bool:
	return c.v >= 0.60 and c.v <= 0.88 and c.s <= 0.20


func _pool_warm_ok(c: Color) -> bool:
	return c.r > c.b and c.a <= 0.25


# The rain wash's own band: visible, never a curtain.
func _rain_alpha_ok(a: float) -> bool:
	return a >= 0.05 and a <= 0.18


# The edge rays derive from the arc's colour by this factor; dead at 0, a lie above 1.
func _dim_ok(d: float) -> bool:
	return d > 0.0 and d < 1.0


func _the_accents_are_muted_and_can_say_no() -> bool:
	var window: Color = Palette.COLOURS["window"] as Color
	var rim: Color = Palette.COLOURS["windowRim"] as Color
	var ground_item: Color = Palette.COLOURS["groundItem"] as Color
	var facing: Color = Palette.COLOURS["facing"] as Color
	var cone: Color = Palette.COLOURS["aimCone"] as Color
	var rain: Color = Palette.COLOURS["rain"] as Color

	# True positives: the shipped table sits inside the mood.
	if not _window_ok(window):
		push_error("window glass is outside the muted band: S %.3f V %.3f" % [window.s, window.v])
		return false
	if not _rim_ok(rim):
		push_error("windowRim is outside the muted band: S %.3f V %.3f" % [rim.s, rim.v])
		return false
	if not _ground_item_ok(ground_item):
		push_error("groundItem is outside the muted band: S %.3f V %.3f" % [ground_item.s, ground_item.v])
		return false
	for pair in [["facing", facing], ["aimCone", cone], ["rain", rain]]:
		var mark: Color = (pair as Array)[1] as Color
		if not _mark_ok(mark):
			push_error("%s is outside the mark band: S %.3f V %.3f" % [(pair as Array)[0], mark.s, mark.v])
			return false

	# Alpha floors and ceilings: a wash you cannot see is not a wash, and a wash you cannot see
	# through is a wall.
	if facing.a < 0.35 or facing.a > 0.60:
		push_error("facing alpha %.3f is outside [0.35, 0.60]" % facing.a)
		return false
	if cone.a < 0.15 or cone.a > 0.32:
		push_error("aimCone alpha %.3f is outside [0.15, 0.32]" % cone.a)
		return false
	if not _rain_alpha_ok(rain.a):
		push_error("rain alpha %.3f is outside [0.05, 0.18]" % rain.a)
		return false

	# The readability floor: an item on the ground must clear the brightest street it can lie on.
	var brightest_ground: float = 0.0
	for tint in Palette.SURFACE_TINTS:
		brightest_ground = maxf(brightest_ground, (tint as Color).v)
	_stash["brightest_ground"] = brightest_ground
	if ground_item.v < brightest_ground + 0.15:
		push_error(
			"groundItem V %.3f does not clear the brightest ground V %.3f by 0.15 -- muted into the pavement"
			% [ground_item.v, brightest_ground]
		)
		return false

	# Rim separation, against the pane the renderer actually paints (window lightened by 0.28 in
	# _draw_window_glass), not against the raw key: "can you see the rim on the glass".
	var pane: Color = window.lightened(0.28)
	if _rgb_distance(rim, pane) < 0.06:
		push_error(
			"windowRim is %.3f from the pane it edges (< 0.06): a rim you cannot see is not a rim"
			% _rgb_distance(rim, pane)
		)
		return false

	# Lamp pools stay warm on purpose -- the one deliberate warmth on an overcast street.
	if not _pool_warm_ok(Palette.LIGHT_POOL_NEAR) or not _pool_warm_ok(Palette.LIGHT_POOL_FAR):
		push_error("a light pool tint has gone cold or thick: the pools must stay warm (r > b) at alpha <= 0.25")
		return false
	# The O-key overlay variants are a developer diagram, loud by design: hold the warmth only.
	if not (Palette.LIGHT_POOL_NEAR_OVERLAY.r > Palette.LIGHT_POOL_NEAR_OVERLAY.b):
		push_error("the near overlay tint has gone cold")
		return false
	if not (Palette.LIGHT_POOL_FAR_OVERLAY.r > Palette.LIGHT_POOL_FAR_OVERLAY.b):
		push_error("the far overlay tint has gone cold")
		return false
	if not _dim_ok(Palette.AIM_EDGE_DIM):
		push_error("AIM_EDGE_DIM %.3f is not strictly between 0 and 1: the edge rays are dead or brighter than the arc" % Palette.AIM_EDGE_DIM)
		return false

	# True negatives: the bright table, refused by the same predicates.
	var refused: int = 0
	if _window_ok(Color("#7ec8e8")):
		push_error("the pre-regrade glass #7ec8e8 passes the muted band; a revert would not be caught")
		return false
	refused += 1
	if _rim_ok(Color("#b8eaff")):
		push_error("the pre-regrade rim #b8eaff passes the muted band; a revert would not be caught")
		return false
	refused += 1
	if _ground_item_ok(Color("#d8c07a")):
		push_error("the pre-regrade groundItem #d8c07a passes the muted band; a revert would not be caught")
		return false
	refused += 1
	if _mark_ok(Color(1, 1, 1, 0.55)):
		push_error("the old white facing line passes the mark band; a revert would not be caught")
		return false
	refused += 1
	if _mark_ok(Color(0.85, 0.9, 1.0, 0.35)):
		push_error("the old aim-cone blue passes the mark band; a revert would not be caught")
		return false
	refused += 1

	# Over-mute negatives, so the bounds are two-sided: a table tuned into the pavement is
	# refused too.
	if _mark_ok(Color("#3a3d40cc")):
		push_error("a near-invisible mark passes the mark band; the floor is dead")
		return false
	var sunk := Color("#4a4640")
	if not _ground_item_ok(sunk):
		push_error("the over-mute fixture is outside the muted band; the readability negative has nothing to judge")
		return false
	if sunk.v >= brightest_ground + 0.15:
		push_error("the over-mute fixture clears the ground floor; the readability negative has nothing to judge")
		return false

	# Rain alpha, both ends refused through the same predicate.
	if _rain_alpha_ok(Color("#c2c9cfcc").a):
		push_error("an opaque rain curtain passes the alpha band")
		return false
	if _rain_alpha_ok(Color("#c2c9cf00").a):
		push_error("an invisible rain passes the alpha floor")
		return false

	# A rim set to the pane's own colour is refused by the same arithmetic that passed the real one.
	if _rgb_distance(pane, pane) >= 0.06:
		push_error("the rim-separation bound accepted zero distance; it cannot say no")
		return false

	# Cold and thick pools refused through the same predicate.
	if _pool_warm_ok(Color(0.5, 0.6, 1.0, 0.2)):
		push_error("a cold blue pool passes the warm pin")
		return false
	if _pool_warm_ok(Color(1.0, 0.84, 0.55, 0.45)):
		push_error("a heavy pool passes the alpha cap")
		return false

	# The dim factor's own bounds can say no.
	if _dim_ok(0.0) or _dim_ok(1.2):
		push_error("the AIM_EDGE_DIM bound accepted a dead or over-bright factor")
		return false

	print(
		"ACCENT OK window #%s, rim #%s, groundItem #%s, marks muted at alpha; pools pinned warm; %d bright values refused"
		% [window.to_html(false), rim.to_html(false), ground_item.to_html(false), refused]
	)
	return true


# --- lane B: the dead keys are wired, the dead constants are gone ------------------------------


# Returns "" when the body is clean, or the complaint. One predicate for every socket below, so
# the lane's true negatives are refused by the same code the real bodies pass through. An empty
# body FAILS -- "had nothing to judge" -- it never skips.
func _socket_verdict(label: String, body: String, needles: Array, forbidden: Array) -> String:
	if body.is_empty():
		return "%s had nothing to judge: the function body could not be read" % label
	for needle in needles:
		if not body.contains(String(needle)):
			return "%s does not reach %s" % [label, String(needle)]
	for literal in forbidden:
		if body.contains(String(literal)):
			return "%s still carries the literal %s" % [label, String(literal)]
	return ""


func _the_dead_keys_are_wired_and_the_dead_constants_are_gone() -> bool:
	var checks: Array = [
		[
			"_draw_window_glass",
			['Palette.COLOURS["windowRim"]'],
			["#b8eaff", "#B8EAFF"],
		],
		[
			"_draw_entities",
			[
				'Palette.COLOURS["glimpse"]',
				'Palette.COLOURS["memory"]',
				'Palette.COLOURS["facing"]',
				'Palette.COLOURS["aimCone"]',
				'Palette.COLOURS["groundItem"]',
				"Palette.AIM_EDGE_DIM",
			],
			[
				"Color(0.32, 0.38, 0.32",
				"Color(0.24, 0.29, 0.24",
				"Color(1, 1, 1, 0.55)",
				"Color(0.85, 0.9, 1.0",
			],
		],
		[
			"_draw_night_wash",
			['Palette.COLOURS["night"]'],
			["Color(0.023"],
		],
	]
	for check in checks:
		var name: String = String((check as Array)[0])
		var verdict: String = _socket_verdict(
			name, _function_body(MAIN_GD, name), (check as Array)[1] as Array, (check as Array)[2] as Array
		)
		if not verdict.is_empty():
			push_error(verdict)
			return false

	# The palette itself: five dead constants deleted, and the LIVE one still present as the
	# control, so the next dead-socket sweep cannot mistake it for part of the batch.
	var palette_src: String = _file_text(PALETTE_GD)
	var verdict2: String = _socket_verdict(
		"palette.gd",
		palette_src,
		["const CONDITION_TINTS"],
		["SWING_RGB", "NIGHT_RGB", "SHADOW_RGB", "const SHADE", "CONDITION_TINT_HEX"]
	)
	if not verdict2.is_empty():
		push_error(verdict2)
		return false

	# True negatives, through the same predicate.
	if _socket_verdict("fixture", "\tdraw_line(a, b, Color(1, 1, 1, 0.55), 2.4)\n", [], ["Color(1, 1, 1, 0.55)"]).is_empty():
		push_error("a body carrying the old literal was not refused; the forbidden scan is dead")
		return false
	if _socket_verdict("fixture", "", ["anything"], []).is_empty():
		push_error("an empty body was not refused; 'had nothing to judge' is dead")
		return false
	if not _function_body(MAIN_GD, "_draw_no_such_function").is_empty():
		push_error("_function_body returned text for a function that does not exist")
		return false
	if _socket_verdict("fixture", "const CONDITION_TINT_HEX: Array\n", [], ["CONDITION_TINT_HEX"]).is_empty():
		push_error("a body carrying a deleted constant was not refused; the deletion scan is dead")
		return false

	print(
		"DEAD SOCKET OK windowRim/glimpse/memory/facing/aimCone/night reach the draw loop, the old literals are gone, and the five dead palette constants are deleted with CONDITION_TINTS standing (check_light_look.gd holds _draw_night_wash's wash_alpha assertion)"
	)
	return true


# --- lane C: the rain is pure ------------------------------------------------------------------


func _distinct_count(values: Array) -> int:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.size()


func _spread_of(samples: Array) -> float:
	var lo: float = 1.0e30
	var hi: float = -1.0e30
	for s in samples:
		lo = minf(lo, float(s))
		hi = maxf(hi, float(s))
	return hi - lo


func _the_rain_is_pure_and_deterministic() -> bool:
	var width: float = 1920.0
	var height: float = 1080.0
	var count: int = RainLook.STREAK_COUNT

	# Const sanity first, so a broken constant names itself rather than failing a bound below.
	if count <= 0 or count > 256:
		push_error("STREAK_COUNT %d is outside (0, 256]" % count)
		return false
	if RainLook.INTENSITY_MIN <= 0.0 or RainLook.INTENSITY_MIN >= 1.0:
		push_error("INTENSITY_MIN %.2f is not strictly between 0 and 1: the rain can stop, or never vary" % RainLook.INTENSITY_MIN)
		return false
	if RainLook.SLANT <= 0.0 or RainLook.FALL_PX_PER_TICK <= 0.0:
		push_error("the rain does not lean or does not fall: SLANT %.2f, FALL_PX_PER_TICK %.1f" % [RainLook.SLANT, RainLook.FALL_PX_PER_TICK])
		return false
	if absf(RainLook.alpha_scale(0.0) - 0.6) > EPS or absf(RainLook.alpha_scale(1.0) - 1.0) > EPS:
		push_error("alpha_scale does not span [0.6, 1.0]")
		return false

	# Determinism: the same instant renders the same sky, at boot, mid-run and a day in.
	for probe_t in [0.0, 1234.0, DAY_TICKS]:
		var t: float = float(probe_t)
		var a: PackedVector2Array = RainLook.segments(t, width, height, count)
		var b: PackedVector2Array = RainLook.segments(t, width, height, count)
		if a.size() != count * 2 or b.size() != count * 2:
			push_error("segments returned %d points for %d streaks at t=%.0f" % [a.size(), count, t])
			return false
		for i in a.size():
			if a[i] != b[i]:
				push_error("segments is not deterministic at t=%.0f, point %d" % [t, i])
				return false

	# Graceful absence: nothing to draw on, nothing drawn.
	if not RainLook.segments(10.0, 0.0, height, count).is_empty():
		push_error("a zero-width sky produced streaks")
		return false
	if not RainLook.segments(10.0, width, -1.0, count).is_empty():
		push_error("a negative-height sky produced streaks")
		return false
	if not RainLook.segments(10.0, width, height, 0).is_empty():
		push_error("a zero count produced streaks")
		return false

	# Geometry at one instant: snapped, bounded, leaning.
	var t0: float = 1234.0
	var pts: PackedVector2Array = RainLook.segments(t0, width, height, count)
	var max_len: float = RainLook.STREAK_LEN_MIN + RainLook.STREAK_LEN_SPAN
	var strict_lean: int = 0
	var columns: Array = []
	var lengths: Array = []
	for i in range(0, pts.size(), 2):
		var head: Vector2 = pts[i]
		var foot: Vector2 = pts[i + 1]
		for p in [head, foot]:
			var v: Vector2 = p as Vector2
			# Pixel CENTRES, not integers: a 1 px quad with whole-number endpoints sits its
			# edges on the sample points and rasterises to nothing (measured; see rain_look.gd).
			if v.x - floorf(v.x) != 0.5 or v.y - floorf(v.y) != 0.5:
				push_error("an endpoint is not snapped to a pixel centre: %s" % str(v))
				return false
		if head.x < -1.0 or head.x > width + max_len * RainLook.SLANT + 1.0:
			push_error("a head is out of the sky horizontally: %s" % str(head))
			return false
		if head.y < -RainLook.WRAP_MARGIN - 1.0 or foot.y > height + RainLook.WRAP_MARGIN + max_len + 1.0:
			push_error("a streak is outside the overscanned sky vertically: %s -> %s" % [str(head), str(foot)])
			return false
		if foot.y <= head.y:
			push_error("a streak does not fall: %s -> %s" % [str(head), str(foot)])
			return false
		if foot.x < head.x:
			push_error("a streak leans against the slant: %s -> %s" % [str(head), str(foot)])
			return false
		if foot.x > head.x:
			strict_lean += 1
		columns.append(head.x)
		lengths.append(foot.y - head.y)
	if strict_lean < int(0.8 * float(count)):
		push_error("only %d of %d streaks lean visibly" % [strict_lean, count])
		return false
	if _distinct_count(columns) < 8:
		push_error("only %d distinct columns: the hash has collapsed into stripes" % _distinct_count(columns))
		return false
	if _distinct_count(lengths) < 5:
		push_error("only %d distinct lengths: the length hash is dead" % _distinct_count(lengths))
		return false

	# It falls: one tick later, every non-wrapping streak moved down by exactly FALL_PX_PER_TICK
	# and drifted 1-2 px with the slant.
	var later: PackedVector2Array = RainLook.segments(t0 + 1.0, width, height, count)
	var non_wrap: int = 0
	var moved: int = 0
	for i2 in range(0, pts.size(), 2):
		var dy: float = later[i2].y - pts[i2].y
		var dx: float = later[i2].x - pts[i2].x
		if later[i2] != pts[i2]:
			moved += 1
		if dy == RainLook.FALL_PX_PER_TICK and dx >= 0.0:
			non_wrap += 1
			if dx < 1.0 or dx > 2.0:
				push_error("a non-wrapping streak drifted %.0f px in one tick; the slant is broken" % dx)
				return false
	if non_wrap < int(0.8 * float(count)):
		push_error("only %d of %d streaks fell cleanly between two ticks" % [non_wrap, count])
		return false
	# The frozen-rain negative: a sky identical one tick later is rain that is not falling.
	if moved < count / 2:
		push_error("the sky is nearly identical one tick later; the rain is not falling")
		return false

	# Intensity: alive, bounded, never stopping. The stride is deliberately non-commensurate
	# with PERIOD_TICKS so the sampler cannot lock onto the lattice.
	var samples: Array = []
	for k in 4096:
		samples.append(RainLook.intensity(float(k) * DAY_TICKS / 4096.0))
	var lo: float = 1.0e30
	var hi: float = -1.0e30
	for s in samples:
		lo = minf(lo, float(s))
		hi = maxf(hi, float(s))
	_stash["intensity_min"] = lo
	_stash["intensity_max"] = hi
	if lo <= 0.0 or lo < RainLook.INTENSITY_MIN - EPS:
		push_error("intensity fell to %.3f, under the floor %.2f: it stopped raining" % [lo, RainLook.INTENSITY_MIN])
		return false
	if hi > 1.0 + EPS:
		push_error("intensity reached %.3f, over 1" % hi)
		return false
	if _spread_of(samples) < 0.25:
		push_error("intensity spread %.3f over a day is under 0.25: the swell is dead" % _spread_of(samples))
		return false
	# Dead-spread and dead-column negatives, through the same helpers.
	var flat: Array = []
	for k2 in 4096:
		flat.append(0.7)
	if _spread_of(flat) >= 0.25:
		push_error("a constant intensity passed the spread bound; the spread helper is dead")
		return false
	var stripe: Array = []
	for k3 in count:
		stripe.append(640.0)
	if _distinct_count(stripe) >= 8:
		push_error("a single column passed the distinct bound; the distinct helper is dead")
		return false

	# Textual purity: the resolver keeps no state and draws from no generator. The scanner is
	# proven on a violating fixture first, so the scan itself can say no.
	var forbidden: Array = ["static var", "RandomNumberGenerator", "randi", "randf", ".stream(", "seed("]
	var violating: String = "static var cache: int = 0\n"
	var scanner_bit: bool = false
	for token in forbidden:
		if violating.contains(String(token)):
			scanner_bit = true
	if not scanner_bit:
		push_error("the purity scanner did not bite a fixture violation")
		return false
	var rain_src: String = _file_text(RAIN_GD)
	if rain_src.is_empty():
		push_error("rain_look.gd had nothing to judge: the file could not be read")
		return false
	for token2 in forbidden:
		if rain_src.contains(String(token2)):
			push_error("rain_look.gd contains %s: the layer is no longer pure" % String(token2))
			return false

	print(
		"RAIN PURE OK %d streaks deterministic, pixel-centred, leaning and falling 9 px/tick; intensity in [%.2f, %.2f] over a day with the floor at %.1f; no state, no generator"
		% [count, lo, hi, RainLook.INTENSITY_MIN]
	)
	return true


# --- lane D: the rain is wired, in order -------------------------------------------------------


func _ascending(indices: Array) -> bool:
	for i in range(1, indices.size()):
		if int(indices[i]) <= int(indices[i - 1]):
			return false
	return true


func _the_rain_is_wired_and_ordered() -> bool:
	var draw_fn: String = _function_body(MAIN_GD, "_draw")
	if draw_fn.is_empty():
		push_error("_draw had nothing to judge: the function body could not be read")
		return false
	var at_entities: int = draw_fn.find("_draw_entities()")
	var at_rain: int = draw_fn.find("_draw_rain()")
	var at_wash: int = draw_fn.find("_draw_night_wash()")
	if at_entities < 0 or at_rain < 0 or at_wash < 0:
		push_error("_draw is missing one of entities/rain/wash: %d %d %d" % [at_entities, at_rain, at_wash])
		return false
	if not _ascending([at_entities, at_rain, at_wash]):
		push_error("_draw is out of order: the rain must land over the bodies and under the night wash")
		return false
	# The order negative, through the same predicate with the real indices reversed.
	if _ascending([at_wash, at_rain, at_entities]):
		push_error("the order predicate accepted a reversed frame; it cannot say no")
		return false

	var verdict: String = _socket_verdict(
		"_draw_rain",
		_function_body(MAIN_GD, "_draw_rain"),
		[
			"RainLook.segments(",
			"RainLook.falls_at(",
			"RainLook.intensity(",
			"RainLook.alpha_scale(",
			"draw_multiline(",
			'Palette.COLOURS["rain"]',
			"world.tick",
		],
		["RandomNumberGenerator", "randf", "LightLook.", "NIGHT_WASH"]
	)
	if not verdict.is_empty():
		push_error(verdict)
		return false

	print(
		"RAIN WIRED OK _draw runs entities -> rain -> wash; _draw_rain reaches segments, falls_at, intensity, alpha_scale and the rain key off the tick (check_light_look.gd holds district -> pools -> entities)"
	)
	return true


# --- lane E: the roof stops the rain -----------------------------------------------------------


func _the_roof_stops_the_rain() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var map: Variant = boot["map"]
	var w: int = int(map.w)
	var h: int = int(map.h)

	var indoor_tiles: int = 0
	var outdoor_floor: int = 0
	var first_indoor: int = -1
	var first_outdoor_floor: int = -1
	for idx in w * h:
		if int(map.indoors[idx]) != 0:
			indoor_tiles += 1
			if first_indoor < 0:
				first_indoor = idx
		elif int(map.tiles[idx]) == SimTileMap.Tile.Floor:
			outdoor_floor += 1
			if first_outdoor_floor < 0:
				first_outdoor_floor = idx
	_stash["indoor_tiles"] = indoor_tiles
	_stash["outdoor_tiles"] = outdoor_floor

	# No data, no quiet pass: a canonical seed with no roofs would judge nothing.
	if indoor_tiles == 0:
		push_error("the canonical seed at %d placed no indoor tile; the roof assertion had nothing to judge" % GATE_SIZE)
		return false
	if outdoor_floor == 0:
		push_error("the canonical seed at %d has no outdoor floor; the open-sky assertion had nothing to judge" % GATE_SIZE)
		return false

	# True positive: the sky is open over the street.
	if not RainLook.falls_at(map, first_outdoor_floor % w, first_outdoor_floor / w):
		push_error("rain does not fall on an outdoor floor tile")
		return false
	# The true negative: a roof genuinely stops it. Without this, a falls_at that returns true
	# unconditionally -- a cull that culls nothing -- passes every other probe in the lane.
	if RainLook.falls_at(map, first_indoor % w, first_indoor / w):
		push_error("rain falls on an indoor tile: the roof does not stop it")
		return false

	# Off the map and with no map, the sky is open -- graceful absence, stated as behaviour.
	for probe in [[-1, 5], [GATE_SIZE, 5], [5, -1], [5, GATE_SIZE]]:
		if not RainLook.falls_at(map, int((probe as Array)[0]), int((probe as Array)[1])):
			push_error("rain stopped outside the map at %s" % str(probe))
			return false
	if not RainLook.falls_at(null, 5, 5):
		push_error("rain stopped with no map at all")
		return false
	var blank: Variant = SimTileMap.blank_map(8, 8)
	for idx2 in 64:
		if not RainLook.falls_at(blank, idx2 % 8, idx2 / 8):
			push_error("rain stopped on a blank map at tile %d" % idx2)
			return false

	print(
		"ROOF OK rain falls on %d outdoor floor tiles and none of %d roofed ones on suburb@%d seed %d; off-map, null-map and blank_map skies stay open"
		% [outdoor_floor, indoor_tiles, GATE_SIZE, CANON_SEED]
	)
	return true


# --- readers -----------------------------------------------------------------------------------


# The source text of one function, from its `func` line to the next top-level `func`.
# check_topdown.gd's and check_light_look.gd's reader, unchanged.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


func _file_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

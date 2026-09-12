extends SceneTree
# Warmth, wet and cooling -- docs/04-survival-needs.md's temperature clause ("ambient weather,
# clothing insulation, wetness, shelter, and heat sources"), and the owner's decision of
# 2026-09-12 that warmth is per-part, like `armor`.
#
# The defect this closes. `needs.gd` had `wearing_wrap`, which matched the literal string
# "item.wrap.cloth", and that was the entire clothing-warmth system in the game. Four weather
# kinds shipped gated -- the cold snap, the heat wave, the storm, the fog -- and not one thing in
# the roster insulated, shed rain or cooled; there was exactly one garment and it was named in
# code. Beside it `wearing_armor` asked the `torso` key and no other, so a suit of plate on every
# limb but the chest would have read as no armour at all when the sun came out.
#
# What replaces it is the shape `armor` already had, because `armor` had solved this: an open map
# keyed by body part, composed across worn items by max, resolved by one scan. `SimInfection.
# armor_coverage_of` is the pattern and this mirrors it rather than inventing a second one. The
# one thing it must say that armour does not is *cooling*, which is the same axis read negative --
# a sun hat and a wool hat are one mechanism, not two.
#
# The lane that matters most is PINNED. Everything else here is new behaviour, but the retrofit --
# `item.wrap.cloth` gaining a `warmth` block and losing its hardcoded reader -- has to reproduce
# the old bands *exactly*, or this slice is not a new mechanism, it is a silent rebalance of every
# night outdoors wearing one. Slice 2's PINNED lane did the same for the medical grades and is the
# precedent.
#
# Every lane carries a true negative, and every behavioural lane measures the *band a body
# actually reads* rather than the helper that computed it -- a table that says a coat is warm is a
# table agreeing with itself. A gate that cannot fail is worse than no gate.
#
# Nothing this slice authored declares an `appearance.equipSprite`: EQUIP_DRAW_ORDER in
# presentation/appearance.gd covers back, legs, torso, primary, secondary and head only, so a
# sprite key on the vest, belt, face, eyes, gloves or feet slot is a socket nothing reads. The
# scarf, the bandana, the wool gloves, the sandals and both vests are deliberately drawn by
# nothing until that slot list grows, and the ART lane below refuses art that would never draw.

const SimBoot = preload("res://sim/boot.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimCombat = preload("res://sim/combat.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentValidator = preload("res://platform/content_validator.gd")
const Appearance = preload("res://presentation/appearance.gd")

const SEED: int = 20260912
const FAR: int = 1 << 40
# The default district carries no water, so the ford half of RAIN boots the one that does --
# `check_water`'s WADE fixture, seed and size included, so the two lanes stand on the same ground.
const WET_DISTRICT: String = "district.forest_edge"
const WET_SEED: int = 20260805
# The one base the retrofit is about.
const WRAP: String = "item.wrap.cloth"
# The four bases `wearing_armor` said yes to before this slice generalised it, and which it must
# still say yes to afterwards.
const BODY_ARMOUR: Array[String] = [
	"item.jacket.leather", "item.vest.scrap", "item.vest.riot", "item.apron.welding",
]
# Fixtures out of the new roster. Slots deliberately spread, because the composition rule is the
# thing under test and two torso garments cannot both be worn.
const COAT: String = "item.coat.winter"
const HAT_WOOL: String = "item.hat.wool"
const GLOVES_WOOL: String = "item.gloves.wool"
const TROUSERS: String = "item.trousers.insulated"
const BOOTS_WARM: String = "item.boots.insulated"
const SHIRT_LINEN: String = "item.shirt.linen"
const HAT_SUN: String = "item.hat.sun"
const SHORTS: String = "item.shorts.cotton"
const SANDALS: String = "item.sandals.canvas"
const BANDANA: String = "item.bandana.cotton"
const PONCHO: String = "item.poncho.rain"

# Noon on day one is full daylight; deep night on day two is the cold half of the ladder.
const NOON: float = 0.4
const NIGHT: float = 0.8
# The slots the renderer actually draws. A copy would drift, so it is read off the renderer.
const DRAWN_SLOTS: Array[String] = ["back", "legs", "torso", "primary", "secondary", "head"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_retrofit_reproduces_the_old_bands() and ok
	ok = _every_block_is_a_real_body_part_and_reachable() and ok
	ok = _warmth_composes_by_max_across_worn_items() and ok
	ok = _clothing_moves_the_band_a_body_reads() and ok
	ok = _light_clothing_cools_and_costs() and ok
	ok = _being_wet_is_a_multiplier_on_what_is_worn() and ok
	ok = _a_poncho_turns_the_sky_away_and_not_the_ford() and ok
	ok = _body_armour_is_no_longer_one_hardcoded_key() and ok
	ok = _nothing_declares_art_that_would_never_draw() and ok
	if ok:
		print("M2_WARMTH_OK pinned content compose bands cool wet rain armour art")
		quit(0)
	else:
		push_error("M2_WARMTH_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


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


# Every fire out and every stitch off, so the only thing moving the band is the sky and what this
# lane then puts on the body. Stripped by the `warmth` block rather than by a base id, which is
# the whole difference between this slice and what it replaced.
func _strip(w: Variant, ent: int) -> bool:
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary and ((base as Dictionary).get("warmth") is Dictionary or bool((base as Dictionary).get("shedsRain", false))):
			SimInventory.unequip_item(w, int(item))
	return SimNeeds.warmth_points(w, ent) == 0 and not SimNeeds.sheds_rain(w, ent)


func _dress(w: Variant, ent: int, ids: Array) -> bool:
	for id in ids:
		var item: int = SimItems.spawn_item(w, String(id), {"tier": "scavenged"})
		if item < 0 or not SimInventory.equip(w, ent, item):
			push_error("the fixture '%s' would not go on" % String(id))
			return false
	return true


func _band(w: Variant, ent: int) -> String:
	return String(SimNeeds.of(w, ent).get("temperature", ""))


func _pools_full(w: Variant, ent: int) -> void:
	var n: Dictionary = SimNeeds.of(w, ent)
	for k in SimNeeds.POOLS:
		n[k] = 100.0
	n["crisis"] = "none"


# One body, one sky, one time of day, one outfit, and the band it settles on. Three steps, the
# way the heat gate's `_reading` does it: the position and the pools are re-pinned on each so the
# district cannot walk the body somewhere else or starve it into a crisis mid-measurement.
func _reading(kind: String, at: float, where: String, outfit: Array, seed_val: int = SEED) -> String:
	var w: Variant = _world(seed_val)
	var e: int = int(w.player)
	if not _strip(w, e):
		push_error("the booted player would not undress")
		return ""
	if not _dress(w, e, outfit):
		return ""
	w.tick = Clock.tick_on_day(1 if at < 0.5 else 2, at)
	_force(w, kind)
	var tile: Vector2i = _tile_where(w, where == "in")
	if tile.x < 0:
		push_error("the booted district has no %sdoor tile" % ("in" if where == "in" else "out"))
		return ""
	for _i in 3:
		_place(w, e, tile)
		_pools_full(w, e)
		w.step()
	return _band(w, e)


# Points and bands for an outfit, off a world nobody has to step.
func _score(outfit: Array) -> Dictionary:
	var w: Variant = _world()
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, outfit):
		return {}
	return {
		"points": SimNeeds.warmth_points(w, e),
		"dry": SimNeeds.warmth_bands(w, e, false),
		"wet": SimNeeds.warmth_bands(w, e, true),
	}


# How many rungs apart two bands are on the ladder, positive when `a` is warmer than `b`.
func _rungs(a: String, b: String) -> int:
	var i: int = SimNeeds.TEMP_ORDER.find(a)
	var j: int = SimNeeds.TEMP_ORDER.find(b)
	if i < 0 or j < 0:
		return 1 << 30
	return i - j


# --- PINNED -----------------------------------------------------------------------------------
#
# The retrofit is additive or it is a rebalance. The cloth wrap was worth exactly one band toward
# comfortable, wet or dry, for as long as it has existed -- `check_m2_weather`'s COLD lane pins
# "wet and wrapped on a mild day is comfortable" and `check_m2_heat`'s ROOF lane pins "a wrap
# reads comfortable where a bare body reads a_little_hot". Both of those still run. This lane
# says the same thing in the new mechanism's own terms, so that if somebody retunes the wrap's
# block the failure names the wrap rather than surfacing two gates away as a weather bug.
func _the_retrofit_reproduces_the_old_bands() -> bool:
	var wrap: Dictionary = _score([WRAP])
	if wrap.is_empty():
		return false
	if int(wrap["dry"]) != 1:
		push_error("PINNED: a dry cloth wrap is worth %d bands, not the one it has always been worth (%d points against WARMTH_PER_BAND %d)" % [int(wrap["dry"]), int(wrap["points"]), SimNeeds.WARMTH_PER_BAND])
		return false
	if int(wrap["wet"]) != 1:
		push_error("PINNED: a soaked cloth wrap is worth %d bands, not one -- the wet multiplier has eaten the retrofit" % int(wrap["wet"]))
		return false
	# And the band a body actually reads, in both of the two places the old gates pinned it.
	var bare_night: String = _reading("clear", NIGHT, "out", [])
	var wrapped_night: String = _reading("clear", NIGHT, "out", [WRAP])
	if bare_night == "" or wrapped_night == "":
		return false
	if bare_night != "very_cold" or _rungs(wrapped_night, bare_night) != 1:
		push_error("PINNED: a night outdoors reads %s bare and %s wrapped -- wanted very_cold and exactly one rung warmer" % [bare_night, wrapped_night])
		return false
	var bare_heat: String = _reading("heat_wave", NOON, "out", [])
	var wrapped_heat: String = _reading("heat_wave", NOON, "out", [WRAP])
	if bare_heat == "" or wrapped_heat == "":
		return false
	if bare_heat != "a_little_hot" or wrapped_heat != "comfortable":
		push_error("PINNED: under a heat wave a bare body reads %s and a wrapped one %s -- wanted a_little_hot and comfortable, which is the rule the wrap has always had" % [bare_heat, wrapped_heat])
		return false
	# The other half of the retrofit: the wrap is still not body armour. It shares a slot with
	# the leather jacket and `wearing_armor` has always had to tell them apart.
	var w: Variant = _world()
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, [WRAP]):
		return false
	if SimNeeds.wearing_armor(w, e):
		push_error("PINNED: the cloth wrap now reads as body armour, so a wrapped survivor bakes in a heat wave")
		return false
	print("  PINNED: the wrap is %d points, one band dry and one band soaked; very_cold -> %s at night and a_little_hot -> comfortable in the sun; still not body armour" % [int(wrap["points"]), wrapped_night])
	return true


# --- CONTENT ----------------------------------------------------------------------------------
#
# Both directions, the way `check_m2_medicine`'s CONTENT lane runs them. Every part a `warmth`
# block names is a part a body actually has (the validator is shallow and will never look inside
# this object, which is how a wrong key sat in `item.wrap.cloth`'s `armor` block for weeks giving
# zero arm protection); every value is inside the bound the schema declares; and both halves of
# the axis plus the rain flag are actually populated, because an axis with nothing negative on it
# is a warmth system with the cooling half written and unreachable.
func _every_block_is_a_real_body_part_and_reachable() -> bool:
	var w: Variant = _world()
	var findable: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for entry_v in file_v as Array:
			if entry_v is Dictionary and String((entry_v as Dictionary).get("id", "")).begins_with("loot."):
				for row_v in (entry_v as Dictionary).get("entries", []) as Array:
					findable[String((row_v as Dictionary).get("item", ""))] = true
	if findable.is_empty():
		push_error("CONTENT: no loot tables loaded, so the reachability half has nothing to judge")
		return false

	var insulating: int = 0
	var cooling: int = 0
	var waterproof: int = 0
	var judged: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var id: String = String(e.get("id", ""))
		var has_warmth: bool = e.get("warmth") is Dictionary
		var sheds: bool = e.has("shedsRain")
		if not has_warmth and not sheds:
			if e.has("warmth"):
				push_error("CONTENT: '%s' declares a `warmth` that is not an object: %s" % [id, str(e["warmth"])])
				return false
			continue
		judged += 1
		if not findable.has(id):
			push_error("CONTENT: '%s' insulates or sheds rain and sits in no loot table -- complete, correct and unreachable" % id)
			return false
		if sheds:
			if not (e["shedsRain"] is bool):
				push_error("CONTENT: '%s' declares shedsRain as %s, which is not a boolean" % [id, str(e["shedsRain"])])
				return false
			if bool(e["shedsRain"]):
				waterproof += 1
		if not has_warmth:
			continue
		var m: Dictionary = e["warmth"] as Dictionary
		if m.is_empty():
			push_error("CONTENT: '%s' declares an empty `warmth` block, which is a garment that does nothing" % id)
			return false
		for key in m.keys():
			var part: String = String(key)
			if not SimCombat.SURVIVOR_BODY_PARTS.has(part):
				push_error("CONTENT: '%s' warms '%s', which is not a part a survivor has -- the validator does not look inside this block, so nothing else would ever have said so" % [id, part])
				return false
			if not SimNeeds.WARMTH_WEIGHTS.has(part):
				push_error("CONTENT: '%s' warms '%s', which SimNeeds.WARMTH_WEIGHTS gives no weight -- declared and unread" % [id, part])
				return false
			var v: float = float(m[key])
			if v < -1.0 or v > 1.0 or is_equal_approx(v, 0.0):
				push_error("CONTENT: '%s' warms '%s' by %.4f, which is outside [-1, 1] or is a zero nobody needs to declare" % [id, part, v])
				return false
		var points: int = _points_of_block(m)
		if points > 0:
			insulating += 1
		elif points < 0:
			cooling += 1
	# Every weight the code carries is one some garment can actually reach, and no part of a body
	# is left unweighted. The reverse of the scan above -- a weight nothing covers is a dead rung.
	for part in SimCombat.SURVIVOR_BODY_PARTS:
		if not SimNeeds.WARMTH_WEIGHTS.has(String(part)):
			push_error("CONTENT: SURVIVOR_BODY has '%s' and WARMTH_WEIGHTS gives it no weight, so nothing worn there can ever count" % String(part))
			return false
	var total: int = 0
	for part in SimNeeds.WARMTH_WEIGHTS.keys():
		if not SimCombat.SURVIVOR_BODY_PARTS.has(String(part)):
			push_error("CONTENT: WARMTH_WEIGHTS weighs '%s', which is not a part of a survivor" % String(part))
			return false
		total += int(SimNeeds.WARMTH_WEIGHTS[part])
	if total != 100:
		push_error("CONTENT: the warmth weights sum to %d, not a hundred, so `warmth_points` is not on the scale WARMTH_PER_BAND is written against" % total)
		return false
	if judged < 20 or insulating < 8 or cooling < 4 or waterproof < 2:
		push_error("CONTENT: %d graded garments -- %d insulate, %d cool, %d shed rain. One of those halves is thin enough that this lane is judging almost nothing" % [judged, insulating, cooling, waterproof])
		return false

	# The schema, and the shallow validator's two negatives beside the shipped positive. The
	# bounds themselves are asserted on the schema document, which is what the frozen oracle's
	# Ajv reads on `npm test` -- the Godot validator cannot see inside an object and never will.
	for issue in ContentValidator.validate_tree():
		if String(issue).contains("items/"):
			push_error("CONTENT: the validator reports %s" % issue)
			return false
	var schemas: Dictionary = ContentValidator._load_schemas()
	if not schemas.has("item"):
		push_error("CONTENT: no item schema is registered, so the directory validates in silence")
		return false
	var schema: Dictionary = schemas["item"] as Dictionary
	var props: Dictionary = schema.get("properties", {}) as Dictionary
	for key in ["warmth", "shedsRain"]:
		if not props.has(key):
			push_error("CONTENT: the item schema does not declare `%s`, so every block of it rides on additionalProperties" % key)
			return false
	var decl: Dictionary = (props["warmth"] as Dictionary).get("additionalProperties", {}) as Dictionary
	if String(decl.get("type", "")) != "number" or absf(float(decl.get("minimum", 0.0)) + 1.0) > 0.000001 or absf(float(decl.get("maximum", 0.0)) - 1.0) > 0.000001:
		push_error("CONTENT: the schema's warmth values are %s -- the [-1, 1] bound the oracle's Ajv enforces is not declared" % str(decl))
		return false
	if String((props["shedsRain"] as Dictionary).get("type", "")) != "boolean":
		push_error("CONTENT: the schema's shedsRain is not declared boolean: %s" % str(props["shedsRain"]))
		return false
	var good: Dictionary = (SimItems.content_entry(w, "item", COAT) as Dictionary).duplicate(true)
	if not ContentValidator._validate_shape(good, schema, "items/clothing.json").is_empty():
		push_error("CONTENT: the shipped winter coat raises %s" % str(ContentValidator._validate_shape(good, schema, "items/clothing.json")))
		return false
	var bad_type: Dictionary = good.duplicate(true)
	bad_type["warmth"] = 0.9
	if ContentValidator._validate_shape(bad_type, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated coat whose warmth is a bare number raised nothing")
		return false
	var bad_bool: Dictionary = good.duplicate(true)
	bad_bool["shedsRain"] = "yes"
	if ContentValidator._validate_shape(bad_bool, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated coat whose shedsRain is a string raised nothing")
		return false
	var bad_key: Dictionary = good.duplicate(true)
	bad_key["insulation"] = {"torso": 1.0}
	if ContentValidator._validate_shape(bad_key, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated coat with a stray key raised nothing")
		return false
	print("  CONTENT: %d garments across the tables -- %d insulate, %d cool, %d shed rain; every part is a real part, the weights sum to %d, and the shallow validator refuses a bare number, a string flag and a stray key" % [judged, insulating, cooling, waterproof, total])
	return true


func _points_of_block(m: Dictionary) -> int:
	var total: float = 0.0
	for key in m.keys():
		if SimNeeds.WARMTH_WEIGHTS.has(String(key)):
			total += float(int(SimNeeds.WARMTH_WEIGHTS[key])) * float(m[key])
	return roundi(total)


# --- COMPOSE ----------------------------------------------------------------------------------
#
# The composition rule, which is `armor_coverage_of`'s on a signed key: per part, the layer
# furthest from zero. Three things have to be true and each has its own opposite.
#
#  1. Parts *add* across items -- a coat and a hat are worth more than a coat, or per-part is
#     decoration and this may as well have stayed one boolean.
#  2. On the same part the emphatic layer wins, and it wins in both directions: a bandana under
#     a sun hat must not warm the head back up, which is the trap a plain `maxf` would fall into
#     and the reason the rule is written as it is.
#  3. `warmth_of` and `warmth_points` agree. They are two scans of the same thing and the second
#     exists only because the first would cost ten passes a tick, so a drift between them is a
#     per-tick lie no lane above would catch.
func _warmth_composes_by_max_across_worn_items() -> bool:
	var coat: Dictionary = _score([COAT])
	var coat_hat: Dictionary = _score([COAT, HAT_WOOL])
	if coat.is_empty() or coat_hat.is_empty():
		return false
	if int(coat_hat["points"]) <= int(coat["points"]):
		push_error("COMPOSE: a coat and a hat score %d where the coat alone scores %d -- parts are not adding" % [int(coat_hat["points"]), int(coat["points"])])
		return false

	var w: Variant = _world()
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, [HAT_SUN]):
		return false
	var hat_alone: float = SimNeeds.warmth_of(w, e, "head")
	if hat_alone >= 0.0:
		push_error("COMPOSE: the sun hat warms the head by %.2f -- the cooling half is not negative" % hat_alone)
		return false
	if not _dress(w, e, [BANDANA]):
		return false
	var with_bandana: float = SimNeeds.warmth_of(w, e, "head")
	if not is_equal_approx(with_bandana, hat_alone):
		push_error("COMPOSE: a bandana under a sun hat moved the head from %.2f to %.2f -- 'max' on a signed axis has to keep the emphatic layer, or a second cool thing makes you warmer" % [hat_alone, with_bandana])
		return false
	# The positive direction of the same rule, on a part two worn items both claim: the wool hat
	# is warmer than the parka's hood, so the head reads the hat.
	var w2: Variant = _world()
	var e2: int = int(w2.player)
	if not _strip(w2, e2) or not _dress(w2, e2, ["item.coat.parka"]):
		return false
	var hood: float = SimNeeds.warmth_of(w2, e2, "head")
	if not _dress(w2, e2, [HAT_WOOL]):
		return false
	var hatted: float = SimNeeds.warmth_of(w2, e2, "head")
	if hood <= 0.0 or hatted <= hood:
		push_error("COMPOSE: a hood reads %.2f and a hood plus a wool hat reads %.2f -- the warmer layer did not win" % [hood, hatted])
		return false

	# The two scans agree, on a body wearing enough for the question to mean something.
	var w3: Variant = _world()
	var e3: int = int(w3.player)
	if not _strip(w3, e3) or not _dress(w3, e3, [COAT, HAT_WOOL, GLOVES_WOOL, TROUSERS, BOOTS_WARM]):
		return false
	var by_part: float = 0.0
	for part in SimCombat.SURVIVOR_BODY_PARTS:
		by_part += float(int(SimNeeds.WARMTH_WEIGHTS[part])) * SimNeeds.warmth_of(w3, e3, String(part))
	if roundi(by_part) != SimNeeds.warmth_points(w3, e3):
		push_error("COMPOSE: ten calls to warmth_of sum to %d and warmth_points says %d -- the fast scan and the slow one disagree" % [roundi(by_part), SimNeeds.warmth_points(w3, e3)])
		return false
	print("  COMPOSE: a coat scores %d and a coat plus a hat %d; a bandana under a sun hat leaves the head at %.2f; a wool hat beats a hood (%.2f over %.2f); both scans agree at %d" % [int(coat["points"]), int(coat_hat["points"]), with_bandana, hatted, hood, SimNeeds.warmth_points(w3, e3)])
	return true


# --- BANDS ------------------------------------------------------------------------------------
#
# The dead-socket question, asked of the whole mechanism: does a body actually *read* warmer for
# being dressed? Every rung is measured as the band a stepped world settles on, never as the
# number that produced it. The negative is the same outfit at noon under a clear sky, where there
# is no cold to buy off and the ladder cannot move -- a lane that only ever looked at midnight
# would pass for an implementation that shifted the band unconditionally.
func _clothing_moves_the_band_a_body_reads() -> bool:
	var cases: Array[Dictionary] = [
		{"name": "bare", "outfit": [], "bands": 0},
		{"name": "wrap", "outfit": [WRAP], "bands": 1},
		{"name": "coat", "outfit": [COAT], "bands": 1},
		{"name": "coat+hat", "outfit": [COAT, HAT_WOOL], "bands": 2},
		{"name": "winter kit", "outfit": [COAT, HAT_WOOL, GLOVES_WOOL, TROUSERS, BOOTS_WARM], "bands": 3},
	]
	var bare: String = _reading("clear", NIGHT, "out", [])
	if bare == "":
		return false
	if bare != "very_cold":
		push_error("BANDS: a bare body on a clear night outdoors reads %s, so this lane has no cold to buy off" % bare)
		return false
	var seen: Array[String] = []
	for c in cases:
		var want: int = int(c["bands"])
		var scored: Dictionary = _score(c["outfit"] as Array)
		if scored.is_empty():
			return false
		if int(scored["dry"]) != want:
			push_error("BANDS: %s scores %d points and %d bands, wanted %d" % [String(c["name"]), int(scored["points"]), int(scored["dry"]), want])
			return false
		var band: String = _reading("clear", NIGHT, "out", c["outfit"] as Array)
		if band == "":
			return false
		# `_shift_temp` clamps at comfortable, so a kit worth more bands than the body is cold
		# reads comfortable rather than overshooting -- which is the right answer and has to be
		# asked for rather than assumed.
		var moved: int = _rungs(band, bare)
		var expected: int = mini(want, _rungs("comfortable", bare))
		if moved != expected:
			push_error("BANDS: %s moved the night band %d rungs (%s -> %s), wanted %d" % [String(c["name"]), moved, bare, band, expected])
			return false
		seen.append("%s %s" % [String(c["name"]), band])
	# The negative: a fair noon is already comfortable, and the whole winter kit cannot make it
	# warmer than that.
	var noon_bare: String = _reading("clear", NOON, "out", [])
	var noon_kit: String = _reading("clear", NOON, "out", [COAT, HAT_WOOL, GLOVES_WOOL, TROUSERS, BOOTS_WARM])
	if noon_bare == "" or noon_kit == "":
		return false
	if noon_bare != "comfortable" or noon_kit != "comfortable":
		push_error("BANDS: a fair noon reads %s bare and %s in a winter kit -- wanted comfortable for both, since there is nothing there to buy off" % [noon_bare, noon_kit])
		return false
	print("  BANDS: %s; a fair noon stays comfortable in the same kit" % ", ".join(seen))
	return true


# --- COOL -------------------------------------------------------------------------------------
#
# The negative half of one axis, which is the point of making it one axis. Three rungs, because a
# single garment crossing a threshold proves only that a threshold exists: a linen shirt alone is
# not worth a band, the shirt and a sun hat are, and a full set of light clothes is worth two.
#
# And the cost, which is what stops this being a free button: the same clothes on a cold night
# read *colder* than a bare body. Cooling is not insulation with the sign flipped in the reader;
# it is strictly colder in both weathers, which is what linen is.
func _light_clothing_cools_and_costs() -> bool:
	var rungs: Array[Dictionary] = [
		{"name": "linen shirt", "outfit": [SHIRT_LINEN], "bands": 0},
		{"name": "shirt+sun hat", "outfit": [SHIRT_LINEN, HAT_SUN], "bands": -1},
		{"name": "light kit", "outfit": [SHIRT_LINEN, HAT_SUN, SHORTS, SANDALS], "bands": -2},
	]
	var printed: Array[String] = []
	for c in rungs:
		var scored: Dictionary = _score(c["outfit"] as Array)
		if scored.is_empty():
			return false
		if int(scored["dry"]) != int(c["bands"]):
			push_error("COOL: %s scores %d points and %d bands, wanted %d" % [String(c["name"]), int(scored["points"]), int(scored["dry"]), int(c["bands"])])
			return false
		printed.append("%s %d" % [String(c["name"]), int(scored["points"])])

	# The relief, measured. A bare body bakes at `a_little_hot`; the light kit reads cooler.
	var hot_bare: String = _reading("heat_wave", NOON, "out", [])
	var hot_light: String = _reading("heat_wave", NOON, "out", [SHIRT_LINEN, HAT_SUN])
	if hot_bare == "" or hot_light == "":
		return false
	if hot_bare != "a_little_hot":
		push_error("COOL: a bare body under a heat wave reads %s, so there is no heat here to relieve" % hot_bare)
		return false
	if _rungs(hot_light, hot_bare) != -1:
		push_error("COOL: a shirt and a sun hat under a heat wave read %s where a bare body reads %s -- wanted exactly one rung cooler" % [hot_light, hot_bare])
		return false
	# The cost, measured, and it is the true negative for "cooling is just warmth reversed": on a
	# cold night the same clothes are worse than nothing.
	var night_bare: String = _reading("clear", NIGHT, "out", [])
	var night_light: String = _reading("clear", NIGHT, "out", [SHIRT_LINEN, HAT_SUN])
	if night_bare == "" or night_light == "":
		return false
	if _rungs(night_light, night_bare) != -1:
		push_error("COOL: a shirt and a sun hat on a cold night read %s where a bare body reads %s -- light clothes have to cost something" % [night_light, night_bare])
		return false
	print("  COOL: %s; a heat wave reads %s in a shirt and a sun hat against %s bare, and the same clothes read %s on a night that reads %s bare" % [", ".join(printed), hot_light, hot_bare, night_light, night_bare])
	return true


# --- WET --------------------------------------------------------------------------------------
#
# docs/04: "being wet is a multiplier on cold". The multiplier is on the insulation -- wet
# clothing is what stops working -- and it lands on the bands rounded up, so the cloth wrap keeps
# the one band it has always had and what the rain takes is everything above the first. Both of
# those are asserted, because "wet costs nothing" and "wet costs everything" are the two ways to
# get this wrong and each passes half a lane.
#
# Cooling is deliberately untouched by wet, and that is asserted too: a damp linen shirt is not
# less cool for being damp, and halving it would be the wrong sign as well as the wrong size.
func _being_wet_is_a_multiplier_on_what_is_worn() -> bool:
	var wrap: Dictionary = _score([WRAP])
	var kit: Dictionary = _score([COAT, HAT_WOOL])
	var full: Dictionary = _score([COAT, HAT_WOOL, GLOVES_WOOL, TROUSERS, BOOTS_WARM])
	var light: Dictionary = _score([SHIRT_LINEN, HAT_SUN, SHORTS, SANDALS])
	if wrap.is_empty() or kit.is_empty() or full.is_empty() or light.is_empty():
		return false
	if int(wrap["wet"]) != int(wrap["dry"]):
		push_error("WET: the wrap is %d bands dry and %d soaked -- the retrofit says one and one" % [int(wrap["dry"]), int(wrap["wet"])])
		return false
	if int(kit["wet"]) >= int(kit["dry"]):
		push_error("WET: a coat and a hat are %d bands dry and %d soaked -- the multiplier is not costing anything" % [int(kit["dry"]), int(kit["wet"])])
		return false
	if int(full["wet"]) >= int(full["dry"]) or int(full["wet"]) <= 0:
		push_error("WET: a winter kit is %d bands dry and %d soaked -- wanted fewer and still some" % [int(full["dry"]), int(full["wet"])])
		return false
	if int(light["wet"]) != int(light["dry"]):
		push_error("WET: light clothes are %d bands dry and %d soaked -- cooling is not supposed to be multiplied at all" % [int(light["dry"]), int(light["wet"])])
		return false

	# And the band a soaked body actually reads. Rain on a mild day: bare is a rung colder for
	# the wet, the wrap buys that rung back (the shipped rule), and the coat-and-hat kit -- two
	# bands dry -- buys back exactly one.
	var mild_dry: String = _reading("clear", NOON, "out", [])
	var mild_wet: String = _rain_reading([])
	var mild_wrap: String = _rain_reading([WRAP])
	if mild_dry == "" or mild_wet == "" or mild_wrap == "":
		return false
	if _rungs(mild_wet, mild_dry) != -1:
		push_error("WET: rain on a mild day reads %s where a dry one reads %s -- wanted one rung colder" % [mild_wet, mild_dry])
		return false
	if mild_wrap != mild_dry:
		push_error("WET: wet and wrapped reads %s where a dry bare body reads %s -- the wrap has always bought that rung back" % [mild_wrap, mild_dry])
		return false
	print("  WET: the wrap holds at %d band wet and dry, a coat and a hat fall from %d to %d, a winter kit from %d to %d, light clothes hold at %d; rain drops a mild day from %s to %s and a wrap restores it" % [int(wrap["dry"]), int(kit["dry"]), int(kit["wet"]), int(full["dry"]), int(full["wet"]), int(light["dry"]), mild_dry, mild_wet])
	return true


# A body stood out in the rain long enough to soak through, then read. `wetAfterTicks` is content
# and the sky declares it, so the loop is driven off `SimWeather.wet_after_ticks` rather than off
# a number written here.
func _rain_reading(outfit: Array) -> String:
	var w: Variant = _world()
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, outfit):
		return ""
	w.tick = Clock.tick_on_day(1, NOON)
	_force(w, "rain")
	var out: Vector2i = _tile_where(w, false)
	if out.x < 0:
		push_error("WET: the booted district has no outdoor tile")
		return ""
	for _i in SimWeather.wet_after_ticks(w) + 2:
		_place(w, e, out)
		_pools_full(w, e)
		w.step()
	if not SimNeeds.is_wet(w, e) and not SimNeeds.sheds_rain(w, e):
		push_error("WET: a body stood in the rain past wetAfterTicks and is still dry")
		return ""
	return _band(w, e)


# --- RAIN -------------------------------------------------------------------------------------
#
# `shedsRain`, and the narrow thing it means. A poncho keeps the sky off: stood in the same
# downpour for the same span, a bare body soaks and a ponchoed one does not, and the soak clock
# on the component never even starts. The true negative is the ford -- a poncho is not waders,
# and a body that wades is wet on the tick it steps in, poncho or no poncho. Without that half
# the flag could have been implemented as "this body cannot be wet" and passed.
func _a_poncho_turns_the_sky_away_and_not_the_ford() -> bool:
	var soaked: Dictionary = _rain_state([])
	var dry: Dictionary = _rain_state([PONCHO])
	if soaked.is_empty() or dry.is_empty():
		return false
	if not bool(soaked["wet"]):
		push_error("RAIN: a bare body in a downpour never got wet, so this lane has nothing to judge")
		return false
	if bool(dry["wet"]):
		push_error("RAIN: a body in a rain poncho got wet anyway")
		return false
	if int(dry["since"]) != -1:
		push_error("RAIN: the poncho kept the body dry but the soak clock is running at %d -- one of the two is lying" % int(dry["since"]))
		return false
	if int(soaked["since"]) < 0:
		push_error("RAIN: the bare body soaked without the soak clock ever starting")
		return false

	# The ford. `check_water`'s WADE lane's fixture exactly -- the default district carries no
	# water at all, so the forest edge is booted for this half and the lane fails rather than
	# skips if that world has no ford in it either. Shallow water is the only water a body can
	# stand on, because deep water is solid.
	var w: Variant = SimBoot.playable(WET_SEED, 128, WET_DISTRICT)["world"]
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, [PONCHO]):
		return false
	if not SimNeeds.sheds_rain(w, e):
		push_error("RAIN: the poncho is on and `sheds_rain` says no")
		return false
	var ford: Vector2i = _shallow_water(w)
	if ford.x < 0:
		push_error("RAIN: %s carries no ford to stand in, so the half that says a poncho is not waders judged nothing" % WET_DISTRICT)
		return false
	w.tick = Clock.tick_on_day(1, NOON)
	_force(w, "clear")
	_place(w, e, ford)
	_pools_full(w, e)
	w.step()
	if not SimNeeds.is_wet(w, e):
		push_error("RAIN: a poncho kept a body dry while it stood in the ford at %s -- it turns the sky away, not the water it is standing in" % str(ford))
		return false
	print("  RAIN: a bare body soaks in a downpour (clock at %d) and a ponchoed one does not (clock at %d); the same poncho is no help at all in the ford at %s" % [int(soaked["since"]), int(dry["since"]), str(ford)])
	return true


func _rain_state(outfit: Array) -> Dictionary:
	var w: Variant = _world()
	var e: int = int(w.player)
	if not _strip(w, e) or not _dress(w, e, outfit):
		return {}
	w.tick = Clock.tick_on_day(1, NOON)
	_force(w, "rain")
	var out: Vector2i = _tile_where(w, false)
	if out.x < 0:
		push_error("RAIN: the booted district has no outdoor tile")
		return {}
	for _i in SimWeather.wet_after_ticks(w) + 2:
		_place(w, e, out)
		_pools_full(w, e)
		w.step()
	return {"wet": SimNeeds.is_wet(w, e), "since": int(SimNeeds.of(w, e).get("rainSinceTick", -1))}


func _shallow_water(w: Variant) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_solid(w.tilemap, x, y):
				continue
			if int(SimSurface.surface_at(w.tilemap, x, y)) == SimTileMap.SURFACE_WATER:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- ARMOUR -----------------------------------------------------------------------------------
#
# The other half of the defect. `wearing_armor` asked the `torso` key and no other, so it could
# not tell a chest plate from a suit of plate with the breastplate missing -- and there is nothing
# absurd about that shape, since `item.gloves.mesh` armours hands 0.8 and armours a torso not at
# all. It reads the whole body now, weighed by the same table warmth is.
#
# The fabricated bases are what make this lane able to fail. A body-part map is a dictionary and
# a dictionary comparing itself proves nothing, so the positive is a garment the *old* predicate
# would have answered "no" to -- heavy everywhere, bare at the chest -- and the negative is a real
# shipped base that covers one pair of parts very well and is still not armour.
func _body_armour_is_no_longer_one_hardcoded_key() -> bool:
	var w: Variant = _world()
	# Every base the old rule said yes to still says yes, and the wrap still says no.
	for id in BODY_ARMOUR:
		var base: Variant = SimItems.content_entry(w, "item", String(id))
		if not base is Dictionary:
			push_error("ARMOUR: '%s' is not a shipped base" % String(id))
			return false
		var points: int = SimNeeds.armor_points_of_base(base as Dictionary)
		if points < SimNeeds.ARMOR_POINTS_HEAT:
			push_error("ARMOUR: '%s' scores %d armour points and no longer reads as body armour -- the heat wave has stopped punishing it" % [String(id), points])
			return false
	var wrap_points: int = SimNeeds.armor_points_of_base(SimItems.content_entry(w, "item", WRAP) as Dictionary)
	if wrap_points >= SimNeeds.ARMOR_POINTS_HEAT:
		push_error("ARMOUR: the cloth wrap scores %d and reads as body armour" % wrap_points)
		return false
	# Nothing this slice authored is body armour, or a survivor dressed for a cold snap would
	# bake the moment the sky flipped.
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not (e.get("warmth") is Dictionary):
			continue
		var id2: String = String(e.get("id", ""))
		if id2 == WRAP:
			continue
		if SimNeeds.armor_points_of_base(e) >= SimNeeds.ARMOR_POINTS_HEAT:
			push_error("ARMOUR: the garment '%s' scores %d armour points, so dressing for the cold now costs a heatstroke" % [id2, SimNeeds.armor_points_of_base(e)])
			return false

	# The positive the old predicate could not have given: no torso coverage at all, and armour
	# everywhere else. `torso >= 0.4` would have answered no; the weighed read answers yes.
	var headless: Dictionary = {"armor": {
		"head": 1.0, "arm_left": 1.0, "arm_right": 1.0,
		"leg_left": 1.0, "leg_right": 1.0,
		"hand_left": 1.0, "hand_right": 1.0, "foot_left": 1.0, "foot_right": 1.0,
	}}
	if float((headless["armor"] as Dictionary).get("torso", 0.0)) != 0.0:
		push_error("ARMOUR: the fabricated suit has torso coverage, so it does not test what it claims to")
		return false
	if SimNeeds.armor_points_of_base(headless) < SimNeeds.ARMOR_POINTS_HEAT:
		push_error("ARMOUR: a suit of plate on every limb but the chest scores %d and still reads as no armour -- the torso key is still the only one being asked" % SimNeeds.armor_points_of_base(headless))
		return false
	# The negative: one pair of parts covered perfectly is not a suit.
	var gloves: Dictionary = SimItems.content_entry(w, "item", "item.gloves.mesh") as Dictionary
	if SimNeeds.armor_points_of_base(gloves) >= SimNeeds.ARMOR_POINTS_HEAT:
		push_error("ARMOUR: steel mesh gloves read as body armour, so a pair of gloves now causes heatstroke")
		return false
	# And a base with no armour block at all scores nothing rather than raising.
	if SimNeeds.armor_points_of_base({}) != 0:
		push_error("ARMOUR: a base with no armour block scores %d" % SimNeeds.armor_points_of_base({}))
		return false
	print("  ARMOUR: the four shipped plates still read as armour, the wrap scores %d and does not, a limbs-only suit scores %d and does, and mesh gloves score %d and do not" % [wrap_points, SimNeeds.armor_points_of_base(headless), SimNeeds.armor_points_of_base(gloves)])
	return true


# --- ART --------------------------------------------------------------------------------------
#
# The dead-socket rule, aimed at the one place this slice could quietly have created one.
# `presentation/appearance.gd`'s EQUIP_DRAW_ORDER covers six slots; an `equipSprite` declared on
# any other is a picture the renderer will never ask for. The scarf, the bandana, the wool gloves,
# the sandals and both vests sit in exactly those slots, so the rule is checked here rather than
# trusted -- and checked against the renderer's own table, not a copy of it, since a copy is the
# thing that drifts.
func _nothing_declares_art_that_would_never_draw() -> bool:
	var drawn: Dictionary = {}
	for row in Appearance.EQUIP_DRAW_ORDER:
		drawn[String((row as Dictionary)["slot"])] = true
	for slot in DRAWN_SLOTS:
		if not drawn.has(slot):
			push_error("ART: this gate believes '%s' is drawn and EQUIP_DRAW_ORDER does not list it" % slot)
			return false
	if drawn.size() != DRAWN_SLOTS.size():
		push_error("ART: EQUIP_DRAW_ORDER draws %s and this gate expected %s -- the renderer grew a slot and this lane has not been told" % [str(drawn.keys()), str(DRAWN_SLOTS)])
		return false
	var w: Variant = _world()
	var judged: int = 0
	var undrawn: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var slot: String = String(e.get("equipSlot", ""))
		if slot.is_empty() or drawn.has(slot):
			continue
		judged += 1
		var app: Variant = e.get("appearance")
		if app is Dictionary and ((app as Dictionary).has("equipSprite") or (app as Dictionary).has("equipSpriteFront")):
			push_error("ART: '%s' sits in the '%s' slot and declares an equipSprite, which EQUIP_DRAW_ORDER never reaches -- art that will never draw" % [String(e.get("id", "")), slot])
			return false
		undrawn += 1
	if judged == 0:
		push_error("ART: no shipped base occupies an undrawn slot, so this lane is judging nothing")
		return false
	print("  ART: EQUIP_DRAW_ORDER draws %d slots; %d shipped bases sit outside them and not one declares a sprite key" % [drawn.size(), undrawn])
	return true

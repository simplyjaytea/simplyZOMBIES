extends SceneTree
# Cooking and water, the transform keys -- docs/04-survival-needs.md's thirst clause, docs/12's
# Produced table, and the owner's decisions of 2026-09-12.
#
# What this slice fixed. Two welds of the same shape, each a pair of hardcoded base ids:
#
#   * **Every raw food in the game cooked into the same meal.** `SimJobs._cook_work` looked for
#     `item.food.raw` and nothing else, and `_do_cook` spawned `item.food.cooked` unconditionally,
#     so a tin, a fish and a sack of potatoes all became the identical dish and the forty other
#     foods the roster has grown could not be put on a fire at all.
#   * **Boiling was an id rename.** `SimNeeds.boil` overwrote `UNTREATED_ID` with `WATER_ID`, both
#     literals in the same file, so a second untreated vessel was a code change.
#
# Both are content now, and they are deliberately **the exact grammar of `empties`** -- a flat
# top-level string naming another base id -- because that grammar already shipped, is already read
# in one place (`SimNeeds._leave_empty`), and is already enforceable by a shallow validator. There
# is no new shape here, only a third and fourth use of a proven one.
#
# The third key is `purifies`, and it exists because docs/04 says purification needs "fuel
# (boiling -> heat, light, smoke) **or filters or chemicals**" and only the first of the three was
# ever built. It is a count of units on the *tool* rather than a string on the water, so the two
# keys never have to agree about a third thing: `boilsInto` says what a vessel becomes and
# `purifies` says who can do it without a fire.
#
# The lane that matters most is PINNED, for the reason check_m2_medicine.gd's and
# check_m2_materials.gd's PINNED lanes matter most: the retrofit is additive or it is a silent
# rebalance of the colony's whole food and water economy wearing one. `item.food.raw` must still
# cook into `item.food.cooked` with the identical numbers, and untreated water must still boil into
# the identical clean bottle, and both are asserted through the real verbs rather than off the
# content table -- a perfect table read by nothing would leave the colony unable to eat.
#
# Every lane carries a true negative. Two shapes were deliberately avoided while writing them,
# because this arc has now found six assertions that could not fail: an ordering claim is never
# anchored on the function that does the ordering (ORDER asks `SimNeeds.is_food`, which is not
# `_stock_cookable`), and no lane rests on an equality arithmetic alone guarantees.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const ContentValidator = preload("res://platform/content_validator.gd")

# The shipped pair, and the whole of what PINNED is allowed to know. Fixtures, not welds: the sim
# names neither of them in a cook or a boil any more, which is the point of the slice.
const RAW: String = "item.food.raw"
const COOKED: String = "item.food.cooked"
const UNTREATED: String = "item.water.bottle.untreated"
const CLEAN: String = "item.water.bottle"
# What the shipped cooked meal threw before the key existed, straight out of git. A change to any
# of these is a rebalance and this gate is where it is caught.
const COOKED_FOOD: Dictionary = {"hunger": 60.0, "mood": 8.0, "spoilDays": 1.0}
const CLEAN_THIRST: float = 50.0

# New bases the lanes below put on a pile or in a pack.
const GAME: String = "item.food.meat.game"
const ROAST: String = "item.meal.roast.game"
const BEANS: String = "item.food.beans.dry"
const STEW: String = "item.meal.beans.stewed"
const STRIPS: String = "item.food.meat.strips"
const CURED: String = "item.food.meat.cured"
const CANTEEN_RAW: String = "item.canteen.untreated"
const CANTEEN_CLEAN: String = "item.canteen.clean"
const TABLETS: String = "item.tablets.purification"
const FILTER: String = "item.filter.pump"
const POT: String = "item.pot.camp"

# The files that must be shown to read each key, and the call the reader is reached by. A textual
# assertion has to be able to find its needle after a refactor, so each of these is a *call*, named
# where the call is made, and the lane follows the link rather than matching a base id -- the
# lesson `check_respond` and `check_weather` both paid for when a helper moved.
const READERS: Array[Dictionary] = [
	{"key": "cooksInto", "file": "res://sim/modules/jobs.gd", "needle": "get(\"cooksInto\", \"\")"},
	{"key": "boilsInto", "file": "res://sim/modules/needs.gd", "needle": "get(\"boilsInto\", \"\")"},
	{"key": "purifies", "file": "res://sim/modules/needs.gd", "needle": "get(\"purifies\", 0)"},
]
# Where a *player or a colonist* reaches the purify verb, as opposed to where the key is parsed. A
# mechanism nothing in play can reach is the dead socket this milestone has paid for eleven times.
const VERB_CALLERS: Array[Dictionary] = [
	{"what": "the E ladder", "file": "res://sim/modules/fortify.gd", "needle": "\"purify\""},
	{"what": "thirst autonomy", "file": "res://sim/modules/jobs.gd", "needle": "SimNeeds.purify("},
]
# What a verb makes that no table rolls and no other base turns into. The well fills a bottle, and
# that is the whole list -- cooked food came off it with this slice, because jobs.gd does not name
# a meal any more.
const PRODUCED: Array[Dictionary] = [
	{"id": "item.water.bottle.untreated", "in": "res://sim/modules/needs.gd"},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_shipped_pair_still_makes_the_shipped_thing() and ok
	ok = _every_transform_names_a_real_base_and_the_schema_says_so() and ok
	ok = _two_ingredients_make_two_different_meals() and ok
	ok = _dinner_comes_before_the_pantry() and ok
	ok = _a_second_vessel_boils_and_an_unboilable_one_does_not() and ok
	ok = _a_filter_makes_water_safe_with_no_fire_in_the_world() and ok
	ok = _the_smallest_remainder_is_spent_first() and ok
	ok = _every_key_is_read_and_every_product_is_reachable() and ok
	if ok:
		print("M2_TRANSFORM_OK pinned content cook order boil purify rank reach")
		quit(0)
	else:
		push_error("M2_TRANSFORM_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------


# A pocket world with a body, a pack and nothing else. Enough for the water half, which is a verb
# on what somebody is carrying and needs no district at all.
func _pocket(seed_val: int = 5101) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	SimInventory.make_inventory(w, w.player)
	SimNeeds.attach(w, w.player)
	return w


# The booted district, which the cook half genuinely needs: Cook is a job, a job wants a colonist,
# a campfire and a stockpile, and all three come out of the shipped suburb rather than out of this
# file. The pile is emptied of anything cookable first for the reason check_m2_jobs.gd's COOK CLAIM
# lane does it: since this slice it is content that decides what is cookable, so what the loot roll
# dropped on the stockpile decides what a scan finds, and a lane that only passes on the seed that
# rolled a mask instead of a sack of beans is one loot edit from red.
func _district() -> Variant:
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	for item in SimNeeds.stockpile_items(w):
		if not SimJobs.cooks_into(w, int(item)).is_empty():
			w.components.remove(int(item), "position")
	return w


func _mara(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(e)
	return -1


func _stock_tile(w: Variant) -> Vector2i:
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if SimNeeds.is_stockpile_tile(w, i, j):
				return Vector2i(i, j)
	return Vector2i(-1, -1)


# Put one unit of `id` on the colony's stockpile and hand back its entity.
func _pile(w: Variant, id: String) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	var drop: Vector2i = _stock_tile(w)
	if drop.x < 0:
		push_error("the booted district has no stockpile tile, so the cook lanes have nowhere to put an ingredient")
		return -1
	w.components.set_component(item, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	return item


func _give(w: Variant, id: String, count: int = 1) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		push_error("the fixture '%s' would not go in a pocket" % id)
		return -1
	return item


func _base_of(w: Variant, item: int) -> String:
	var b: Variant = w.components.get_component(item, "itemBase")
	return String((b as Dictionary).get("baseId", "")) if b is Dictionary else ""


func _entry(w: Variant, id: String) -> Dictionary:
	var e: Variant = SimItems.content_entry(w, "item", id)
	return (e as Dictionary) if e is Dictionary else {}


func _count_base(w: Variant, base_id: String) -> int:
	var n: int = 0
	for item in w.components.query(["itemBase"]):
		if _base_of(w, int(item)) == base_id:
			n += 1
	return n


# Run one cook to completion at the fire and hand back the job that was taken.
func _cook_once(w: Variant, ent: int) -> Dictionary:
	var job: Dictionary = SimJobs._cook_work(w, ent)
	if job.is_empty():
		return {}
	w.components.set_component(ent, "job", job)
	var fires: Array[int] = w.components.query(["campfire"])
	var fp: Variant = w.components.get_component(fires[0], "position")
	w.components.set_component(ent, "position", {"x": float((fp as Dictionary)["x"]), "y": float((fp as Dictionary)["y"])})
	job["ticksLeft"] = 1
	SimJobs._do_cook(w, ent, job)
	w.events.drain()
	return job


# --- PINNED -----------------------------------------------------------------------------------
#
# The retrofit is additive or it is a rebalance. The shipped raw must still cook into the shipped
# meal and the shipped bottle must still boil into the shipped clean one, both through the real
# verbs, and the meal and the bottle must still throw the numbers they threw before the keys
# existed. Asserted through the verb and not off the table on purpose: a content pair nothing reads
# would leave the colony unable to cook at all, and a table read by nothing is the shape this
# milestone keeps finding.
func _the_shipped_pair_still_makes_the_shipped_thing() -> bool:
	var w: Variant = _district()
	var mara: int = _mara(w)
	if mara < 0:
		push_error("PINNED: the booted colony has no Mara, so nothing was judged")
		return false
	if w.components.query(["campfire"]).is_empty():
		push_error("PINNED: the booted district sited no campfire, so cooking has nothing to judge")
		return false
	var raw: int = _pile(w, RAW)
	if raw < 0:
		return false
	var before: int = _count_base(w, COOKED)
	var job: Dictionary = _cook_once(w, mara)
	if job.is_empty() or int(job.get("target", -1)) != raw:
		push_error("PINNED: the cook did not take the shipped raw off the pile: %s" % str(job))
		return false
	if _count_base(w, COOKED) != before + 1:
		push_error("PINNED: cooking '%s' made %d of '%s', not one -- the shipped pair no longer holds" % [RAW, _count_base(w, COOKED) - before, COOKED])
		return false
	if w.components.has_component(raw, "itemBase"):
		push_error("PINNED: the raw survived being cooked")
		return false
	# The numbers on the meal, straight out of git.
	var spec_v: Variant = SimNeeds.food_spec(w, COOKED)
	if not (spec_v is Dictionary):
		push_error("PINNED: '%s' is not food any more" % COOKED)
		return false
	var spec: Dictionary = spec_v as Dictionary
	for key in COOKED_FOOD.keys():
		if absf(float(spec.get(key, -999.0)) - float(COOKED_FOOD[key])) > 0.0001:
			push_error("PINNED: the shipped meal's %s is %s against the pinned %.1f" % [String(key), str(spec.get(key, "absent")), float(COOKED_FOOD[key])])
			return false
	if spec.has("illnessChance") and float(spec["illnessChance"]) > 0.0:
		push_error("PINNED: the shipped meal now carries an illness chance of %.3f" % float(spec["illnessChance"]))
		return false

	# The water half, through `boil` at a lit fire.
	var p: Variant = _pocket(5102)
	var fire: int = SimNeeds.make_campfire(p, 8.5, 16.5, true)
	if _give(p, UNTREATED) < 0:
		return false
	var boiled: Dictionary = SimNeeds.boil(p, p.player, fire)
	if not bool(boiled.get("ok", false)):
		push_error("PINNED: the shipped bottle would not boil at a lit fire: %s" % str(boiled))
		return false
	if _base_of(p, int(boiled.get("item", _only_carried(p)))) != CLEAN:
		push_error("PINNED: boiling the shipped bottle left '%s', not '%s'" % [_base_of(p, _only_carried(p)), CLEAN])
		return false
	var clean_spec: Variant = SimNeeds.drink_spec(p, CLEAN)
	if not (clean_spec is Dictionary) or absf(float((clean_spec as Dictionary).get("thirst", -1.0)) - CLEAN_THIRST) > 0.0001:
		push_error("PINNED: the shipped clean bottle drinks %s against the pinned %.1f" % [str(clean_spec), CLEAN_THIRST])
		return false
	if (clean_spec as Dictionary).has("illnessChance"):
		push_error("PINNED: the shipped clean bottle now declares an illness chance")
		return false
	print("  PINNED: the shipped raw still cooks into the shipped meal (%d hunger, %+d mood, %d day), and the shipped bottle still boils clean at %d thirst" % [int(COOKED_FOOD["hunger"]), int(COOKED_FOOD["mood"]), int(COOKED_FOOD["spoilDays"]), int(CLEAN_THIRST)])
	return true


func _only_carried(w: Variant) -> int:
	for item in SimInventory.carried_items(w, w.player):
		return int(item)
	return -1


# --- CONTENT ----------------------------------------------------------------------------------
#
# Both directions, the way check_m2_attach.gd's CONTENT and HOSTS lanes run, plus the shallow
# validator's negatives. Every transform names a base that exists; every declared `purifies` is a
# usable count; and the *distinctness* claim that is the whole headline -- before this slice there
# was exactly one meal in the game and any number of ingredients, so the number of distinct
# `cooksInto` targets is the one number that says the weld is gone.
func _every_transform_names_a_real_base_and_the_schema_says_so() -> bool:
	var w: Variant = _pocket(5201)
	var by_id: Dictionary = {}
	for e_v in SimItems.content_entries(w, "item"):
		by_id[String((e_v as Dictionary).get("id", ""))] = e_v as Dictionary
	if by_id.size() < 100:
		push_error("CONTENT: only %d item bases loaded, so this lane is judging almost nothing" % by_id.size())
		return false
	var cook_targets: Dictionary = {}
	var boil_targets: Dictionary = {}
	var cookables: int = 0
	var boilables: int = 0
	var purifiers: int = 0
	for id in by_id.keys():
		var e: Dictionary = by_id[id] as Dictionary
		for key in ["cooksInto", "boilsInto"]:
			if not e.has(key):
				continue
			var into: String = String(e[key])
			if not by_id.has(into):
				push_error("CONTENT: '%s' declares %s '%s', which is not a base -- content that has outrun the catalogue" % [String(id), key, into])
				return false
			if into == String(id):
				push_error("CONTENT: '%s' declares %s pointing at itself, which is a job that never finishes" % [String(id), key])
				return false
			if key == "cooksInto":
				cook_targets[into] = true
				cookables += 1
			else:
				boil_targets[into] = true
				boilables += 1
		if e.has("purifies"):
			purifiers += 1
			if int(e["purifies"]) < 1:
				push_error("CONTENT: '%s' declares purifies %s, which treats nothing" % [String(id), str(e["purifies"])])
				return false
			if not SimNeeds.is_drink(w, String(id)) and String(e.get("class", "")) not in ["material", "consumable"]:
				push_error("CONTENT: '%s' purifies and is a '%s'" % [String(id), String(e.get("class", ""))])
				return false
	# The headline, and the assertion that would have read 1 the day before this slice.
	if cook_targets.size() < 8:
		push_error("CONTENT: %d distinct meals across %d cookable bases -- cooking is still very nearly one dish" % [cook_targets.size(), cookables])
		return false
	if boilables < 2:
		push_error("CONTENT: %d boilable vessels -- with only one, `boilsInto` is the old hardcoded pair wearing a key" % boilables)
		return false
	if purifiers < 3:
		push_error("CONTENT: %d purifiers, and docs/04 names three routes (fuel, filters, chemicals)" % purifiers)
		return false

	# The shallow validator, and its negatives beside the shipped positive. The Godot validator
	# cannot see inside an object and never will, which is exactly why all three keys are flat
	# scalars at the top level -- up here the pattern and the bound are actually enforced.
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
	for key in ["cooksInto", "boilsInto", "purifies"]:
		if not props.has(key):
			push_error("CONTENT: the item schema does not declare `%s`, so it rides on additionalProperties and nothing checks it" % key)
			return false
	for key in ["cooksInto", "boilsInto"]:
		var decl: Dictionary = props[key] as Dictionary
		if String(decl.get("type", "")) != "string" or not String(decl.get("pattern", "")).begins_with("^item"):
			push_error("CONTENT: the schema's `%s` is %s -- the id pattern the oracle's Ajv enforces is not declared" % [key, str(decl)])
			return false
	var pd: Dictionary = props["purifies"] as Dictionary
	if String(pd.get("type", "")) != "integer" or int(pd.get("minimum", 0)) < 1:
		push_error("CONTENT: the schema's `purifies` is %s -- an integer of at least one is not declared" % str(pd))
		return false
	var good: Dictionary = (by_id[RAW] as Dictionary).duplicate(true)
	if not ContentValidator._validate_shape(good, schema, "items/supplies.json").is_empty():
		push_error("CONTENT: the shipped raw raises %s" % str(ContentValidator._validate_shape(good, schema, "items/supplies.json")))
		return false
	var bad_shape: Dictionary = good.duplicate(true)
	bad_shape["cooksInto"] = {"id": COOKED}
	if ContentValidator._validate_shape(bad_shape, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated raw whose cooksInto is an object raised nothing")
		return false
	var bad_id: Dictionary = good.duplicate(true)
	bad_id["boilsInto"] = "stew"
	if ContentValidator._validate_shape(bad_id, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated raw whose boilsInto is not a namespaced id raised nothing")
		return false
	# A *type* violation and not a bound one, deliberately. `purifies: 0` validates clean here --
	# the Godot validator checks the declared type and stops, so `minimum` is enforced only by the
	# frozen oracle's Ajv on `npm test`. That is the shallow-validator trap in its exact shape, and
	# the honest way to hold it is the schema-document assertion above (which reads `minimum`
	# itself) plus this, which is what the engine-side validator can actually refuse.
	var bad_count: Dictionary = good.duplicate(true)
	bad_count["purifies"] = "several"
	if ContentValidator._validate_shape(bad_count, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated raw whose purifies is a word raised nothing")
		return false
	var bad_key: Dictionary = good.duplicate(true)
	bad_key["cooksTo"] = COOKED
	if ContentValidator._validate_shape(bad_key, schema, "items/fake.json").is_empty():
		push_error("CONTENT: a fabricated raw with a stray transform key raised nothing")
		return false

	# And the half the validator cannot reach whatever the schema says: a target that is a legal id
	# and simply is not a base. `godot:validate` passes it; the *reader* is what refuses it.
	(w.content as Dictionary)["items/_transform_gate_fixture.json"] = [
		{"id": "item.gate.nowhere", "name": "Nowhere Pie", "class": "consumable",
			"size": {"w": 1, "h": 1}, "massKg": 0.1, "cooksInto": "item.gate.absent",
			"food": {"hunger": 1}},
	]
	if not SimJobs.cooks_into_base(w, "item.gate.nowhere").is_empty():
		push_error("CONTENT: an ingredient naming a meal that is not a base was accepted as cookable, so a cook would make something out of nothing")
		return false
	if SimJobs.cooks_into_base(w, RAW) != COOKED:
		push_error("CONTENT: the reader that refused the fabricated ingredient also refuses the shipped one, so it refuses everything")
		return false
	print("  CONTENT: %d cookable bases making %d distinct meals, %d boilable vessels, %d purifiers; the schema refuses an object, an un-namespaced id, a count that is a word and a stray key, and the reader refuses a meal that is not a base" % [cookables, cook_targets.size(), boilables, purifiers])
	return true


# --- COOK -------------------------------------------------------------------------------------
#
# The assertion that something *reads* `cooksInto`, and the one that says the weld is gone: two
# different ingredients on the same pile, cooked at the same fire by the same colonist, must make
# two different meals. One ingredient proves nothing -- the old hardcoded spawn would have passed
# that -- so the claim is the pair and the difference between them.
func _two_ingredients_make_two_different_meals() -> bool:
	var made: Array[String] = []
	for spec in [{"in": GAME, "out": ROAST}, {"in": BEANS, "out": STEW}, {"in": STRIPS, "out": CURED}]:
		var w: Variant = _district()
		var mara: int = _mara(w)
		if mara < 0 or w.components.query(["campfire"]).is_empty():
			push_error("COOK: the booted district has no cook or no fire, so nothing was judged")
			return false
		var ingredient: int = _pile(w, String(spec["in"]))
		if ingredient < 0:
			return false
		var before: int = _count_base(w, String(spec["out"]))
		var job: Dictionary = _cook_once(w, mara)
		if job.is_empty() or int(job.get("target", -1)) != ingredient:
			push_error("COOK: '%s' on the pile was not taken by the cook: %s" % [String(spec["in"]), str(job)])
			return false
		if _count_base(w, String(spec["out"])) != before + 1:
			push_error("COOK: cooking '%s' made %d of '%s' -- the meal comes from somewhere other than the ingredient" % [String(spec["in"]), _count_base(w, String(spec["out"])) - before, String(spec["out"])])
			return false
		if _count_base(w, COOKED) != 0:
			push_error("COOK: cooking '%s' made the generic '%s' as well, so the old hardcoded spawn is still in there" % [String(spec["in"]), COOKED])
			return false
		made.append(String(spec["out"]))
	if made.size() != 3 or made[0] == made[1] or made[1] == made[2] or made[0] == made[2]:
		push_error("COOK: three ingredients produced %s -- not three different meals" % str(made))
		return false

	# The true negative: something on the pile that cooks into nothing is not work. Before the key
	# this was the whole roster; it has to still be true, or `_cook_work` is answering "yes" to
	# everything and the meal is coming out of the spawn rather than out of the ingredient.
	var w2: Variant = _district()
	var mara2: int = _mara(w2)
	if _pile(w2, "item.scrap.metal") < 0:
		return false
	if not SimJobs._cook_work(w2, mara2).is_empty():
		push_error("COOK: a pile holding nothing but scrap metal was still offered as cook work")
		return false
	# And the other negative: a cook whose ingredient is gone at completion cooks nothing. The
	# claim lane in check_m2_jobs owns the general case; this is the transform's own version of
	# it, because `_do_cook` now reads the ingredient's id at completion as well as its claim.
	var w3: Variant = _district()
	var mara3: int = _mara(w3)
	var doomed: int = _pile(w3, GAME)
	if doomed < 0:
		return false
	var job3: Dictionary = SimJobs._cook_work(w3, mara3)
	if job3.is_empty():
		push_error("COOK: the district would not offer a cook job for game meat")
		return false
	w3.components.set_component(mara3, "job", job3)
	w3.components.remove(doomed, "itemBase")
	var fires3: Array[int] = w3.components.query(["campfire"])
	var fp3: Variant = w3.components.get_component(fires3[0], "position")
	w3.components.set_component(mara3, "position", {"x": float((fp3 as Dictionary)["x"]), "y": float((fp3 as Dictionary)["y"])})
	job3["ticksLeft"] = 1
	SimJobs._do_cook(w3, mara3, job3)
	w3.events.drain()
	if _count_base(w3, ROAST) != 0:
		push_error("COOK: a cook whose ingredient vanished still produced %d roast" % _count_base(w3, ROAST))
		return false
	print("  COOK: game meat, dried beans and salted strips make three different meals at the same fire, scrap metal is not work, and an ingredient that vanished makes nothing")
	return true


# --- ORDER ------------------------------------------------------------------------------------
#
# Dinner before the pantry. Salted strips cure into meat that keeps for a month and game meat
# roasts into tonight's dinner; both are cookable, so which the cook takes first is a decision
# rather than an accident of what the loot dropped. The claim is anchored on `SimNeeds.is_food`
# -- a *different* function from the one doing the ordering -- because comparing `_stock_cookable`
# against itself would only ever catch non-determinism.
#
# Both stow orders, because a scan that keeps the last thing it saw passes one of them by luck.
func _dinner_comes_before_the_pantry() -> bool:
	# There is no food-versus-preserve pair in the shipped roster where one is not food at all, so
	# the true positive is fabricated on purpose: a cookable that is *not* food, beside one that
	# is. `SimNeeds.is_food` is what decides, and it asks only for a `food` block.
	for food_first in [true, false]:
		var w: Variant = _district()
		var mara: int = _mara(w)
		(w.content as Dictionary)["items/_transform_gate_order.json"] = [
			{"id": "item.gate.tallow", "name": "Rendering Tallow", "class": "material",
				"size": {"w": 1, "h": 1}, "massKg": 0.4, "cooksInto": ROAST},
		]
		if SimNeeds.is_food(w, "item.gate.tallow"):
			push_error("ORDER: the fabricated non-food declares food, so this lane is comparing two foods")
			return false
		if not SimNeeds.is_food(w, GAME):
			push_error("ORDER: the shipped game meat is not food, so this lane has nothing to rank")
			return false
		var ids: Array = [GAME, "item.gate.tallow"] if food_first else ["item.gate.tallow", GAME]
		var placed: Dictionary = {}
		for id in ids:
			var e: int = _pile(w, String(id))
			if e < 0:
				return false
			placed[String(id)] = e
		var job: Dictionary = SimJobs._cook_work(w, mara)
		if job.is_empty():
			push_error("ORDER: with two cookables on the pile the cook was offered nothing")
			return false
		if int(job.get("target", -1)) != int(placed[GAME]):
			push_error("ORDER: with the food and the non-food both on the pile the cook took '%s' (food dropped first: %s)" % [_base_of(w, int(job.get("target", -1))), str(food_first)])
			return false
	# The other half, and the reason this is an order rather than a filter: with nothing edible on
	# the pile the non-food is still work. Without this, refusing non-food outright would pass.
	var w2: Variant = _district()
	var mara2: int = _mara(w2)
	(w2.content as Dictionary)["items/_transform_gate_order.json"] = [
		{"id": "item.gate.tallow", "name": "Rendering Tallow", "class": "material",
			"size": {"w": 1, "h": 1}, "massKg": 0.4, "cooksInto": ROAST},
	]
	var lone: int = _pile(w2, "item.gate.tallow")
	if lone < 0:
		return false
	var job2: Dictionary = SimJobs._cook_work(w2, mara2)
	if job2.is_empty() or int(job2.get("target", -1)) != lone:
		push_error("ORDER: with only the non-food on the pile the cook was offered %s -- preservation is being refused rather than deferred" % str(job2))
		return false
	print("  ORDER: with food and a preserving job both on the pile the cook feeds people first, whichever was dropped first, and takes the preserving job when there is nothing to eat")
	return true


# --- BOIL -------------------------------------------------------------------------------------
#
# The assertion that something reads `boilsInto`, and the one that says the weld is gone: a second
# vessel, which is not the bottle the old two literals named, boils into its own clean form at the
# same fire. Three negatives beside it: an unlit fire refuses, no fire at all refuses, and a vessel
# that declares no `boilsInto` is not boiled into anything.
func _a_second_vessel_boils_and_an_unboilable_one_does_not() -> bool:
	var w: Variant = _pocket(5301)
	var fire: int = SimNeeds.make_campfire(w, 8.5, 16.5, false)
	var canteen: int = _give(w, CANTEEN_RAW)
	if canteen < 0:
		return false
	var cold: Dictionary = SimNeeds.boil(w, w.player, fire)
	if bool(cold.get("ok", false)) or String(cold.get("reason", "")) != "unlit":
		push_error("BOIL: an unlit fire boiled the canteen, or refused for the wrong reason: %s" % str(cold))
		return false
	var nowhere: Dictionary = SimNeeds.boil(w, w.player, -1)
	if bool(nowhere.get("ok", false)) or String(nowhere.get("reason", "")) != "no-fire":
		push_error("BOIL: boiling with no fire at all returned %s" % str(nowhere))
		return false
	SimNeeds.set_lit(w, fire, true)
	var hot: Dictionary = SimNeeds.boil(w, w.player, fire)
	if not bool(hot.get("ok", false)):
		push_error("BOIL: a lit fire would not boil the canteen: %s" % str(hot))
		return false
	if _base_of(w, canteen) != CANTEEN_CLEAN:
		push_error("BOIL: the boiled canteen is '%s', not '%s' -- the rename is still going to one hardcoded id" % [_base_of(w, canteen), CANTEEN_CLEAN])
		return false
	if int(hot.get("item", -1)) != canteen:
		push_error("BOIL: the boil reported item %d and the canteen is %d" % [int(hot.get("item", -1)), canteen])
		return false
	# The instance survives, which is what makes this a rename rather than a swap: an affix roll, a
	# condition and a stack count all ride on the entity and a despawn-and-respawn would drop them.
	if not w.components.has_component(canteen, "itemBase"):
		push_error("BOIL: the canteen was destroyed and replaced rather than renamed")
		return false
	# The true negative: a vessel with no `boilsInto` is not boiled.
	var again: Dictionary = SimNeeds.boil(w, w.player, fire)
	if bool(again.get("ok", false)):
		push_error("BOIL: the clean canteen boiled a second time, so `boilsInto` is not what decides")
		return false
	if String(again.get("reason", "")) != "no-bottle":
		push_error("BOIL: a pack holding only clean water refused for '%s' rather than for having nothing to boil" % String(again.get("reason", "")))
		return false
	print("  BOIL: the canteen boils into its own clean form at a lit fire and keeps its instance; an unlit fire, no fire and a clean pack each refuse with their own word")
	return true


# --- PURIFY -----------------------------------------------------------------------------------
#
# docs/04's other two routes. The world this runs in has **no campfire in it at all**, which is the
# assertion: `boil` cannot be what is doing the work. A strip of tablets loses one tablet and stays
# a strip; a filter loses one of its many and stays a filter; the last use spends the unit and
# leaves whatever the base's `empties` names. Refusals both ways: no purifier, and nothing to
# treat.
func _a_filter_makes_water_safe_with_no_fire_in_the_world() -> bool:
	var w: Variant = _pocket(5401)
	if not w.components.query(["campfire"]).is_empty():
		push_error("PURIFY: the pocket world has a campfire in it, so this lane cannot tell purifying from boiling")
		return false
	var bottle: int = _give(w, UNTREATED)
	if bottle < 0:
		return false
	var bare: Dictionary = SimNeeds.purify(w, w.player)
	if bool(bare.get("ok", false)) or String(bare.get("reason", "")) != "no-purifier":
		push_error("PURIFY: a pack with water and nothing to treat it with returned %s" % str(bare))
		return false
	var strip: int = _give(w, TABLETS, 4)
	if strip < 0:
		return false
	var per_tablet: int = int(_entry(w, TABLETS).get("purifies", 0))
	if per_tablet < 1:
		push_error("PURIFY: the shipped tablets declare purifies %d" % per_tablet)
		return false
	var done: Dictionary = SimNeeds.purify(w, w.player)
	if not bool(done.get("ok", false)):
		push_error("PURIFY: tablets and a bottle of well water, and nothing happened: %s" % str(done))
		return false
	if _base_of(w, bottle) != CLEAN:
		push_error("PURIFY: the treated bottle is '%s', not '%s'" % [_base_of(w, bottle), CLEAN])
		return false
	if String(done.get("with", "")) != TABLETS:
		push_error("PURIFY: the treatment reported '%s' as what was spent" % String(done.get("with", "")))
		return false
	var stack: Variant = w.components.get_component(strip, "stack")
	if not (stack is Dictionary) or int((stack as Dictionary).get("count", -1)) != 3:
		push_error("PURIFY: a strip of four tablets is %s after one bottle, not three" % str(stack))
		return false

	# A filter of many uses: one bottle costs one use and the filter stays in the pack.
	var f: Variant = _pocket(5402)
	if _give(f, UNTREATED) < 0:
		return false
	var pump: int = _give(f, FILTER)
	if pump < 0:
		return false
	var capacity: int = int(_entry(f, FILTER).get("purifies", 0))
	if capacity < 2:
		push_error("PURIFY: the shipped pump filter declares purifies %d, so it cannot show a remainder" % capacity)
		return false
	if SimNeeds.purifier_uses(f, pump) != capacity:
		push_error("PURIFY: an unopened filter reads %d uses against its content's %d" % [SimNeeds.purifier_uses(f, pump), capacity])
		return false
	var one: Dictionary = SimNeeds.purify(f, f.player)
	if not bool(one.get("ok", false)) or int(one.get("usesLeft", -1)) != capacity - 1:
		push_error("PURIFY: one bottle through the filter left %s" % str(one))
		return false
	if SimNeeds.purifier_uses(f, pump) != capacity - 1:
		push_error("PURIFY: the filter reads %d uses after one bottle, so the count is not on the instance" % SimNeeds.purifier_uses(f, pump))
		return false
	if not f.components.has_component(pump, "itemBase"):
		push_error("PURIFY: the filter was spent after a single bottle")
		return false
	var dry: Dictionary = SimNeeds.purify(f, f.player)
	if bool(dry.get("ok", false)) or String(dry.get("reason", "")) != "no-bottle":
		push_error("PURIFY: a filter with nothing left to treat returned %s" % str(dry))
		return false

	# The last use, and what it leaves. The billy can is the shortest-lived shipped purifier, so it
	# is the cheapest one to run dry; the claim is that the unit goes through `_consume_item`, which
	# is the one place `empties` is decided, rather than being quietly deleted.
	var e: Variant = _pocket(5403)
	var billy: int = _give(e, POT)
	if billy < 0:
		return false
	var runs: int = int(_entry(e, POT).get("purifies", 0))
	if runs < 1:
		push_error("PURIFY: the billy can declares purifies %d" % runs)
		return false
	for i in runs:
		var next: int = _give(e, UNTREATED)
		if next < 0:
			return false
		var r: Dictionary = SimNeeds.purify(e, e.player)
		if not bool(r.get("ok", false)):
			push_error("PURIFY: the billy refused bottle %d of %d: %s" % [i + 1, runs, str(r)])
			return false
		# Off the body again before the next one. A treated bottle is not consumed -- that is the
		# whole point, it is the same instance renamed -- and a pack is a grid, so six of them in a
		# row run the survivor out of room rather than out of billy.
		SimInventory.remove_from_container(e, next)
		e.despawn(next)
	if e.components.has_component(billy, "itemBase"):
		push_error("PURIFY: the billy can treated %d bottles and is still in the pack -- the count never runs out" % runs)
		return false
	if e.components.has_component(billy, "purifier"):
		push_error("PURIFY: a spent purifier left its running count behind, which would make the next unit of a stack inert")
		return false
	print("  PURIFY: with no fire anywhere, a tablet treats a bottle and the strip loses one; a filter spends one of %d and stays a filter; a billy runs out after %d and is spent; an empty pack and a bare pack each refuse with their own word" % [capacity, runs])
	return true


# --- RANK -------------------------------------------------------------------------------------
#
# Which purifier is reached for. A strip of tablets treats one bottle and a pump filter treats many
# more, so a survivor carrying both should finish the tablet rather than crack the filter for a
# single litre. The claim is anchored on the *content numbers* -- read straight out of the two
# bases here -- rather than on the helper that picks, so it is an assertion about the rule and not
# a comparison of the selector with itself. Both stow orders, because a scan that keeps the last
# thing it saw passes one of them by luck.
func _the_smallest_remainder_is_spent_first() -> bool:
	var probe: Variant = _pocket(5501)
	var small: int = int(_entry(probe, TABLETS).get("purifies", 0))
	var large: int = int(_entry(probe, FILTER).get("purifies", 0))
	if small < 1 or large <= small:
		push_error("RANK: the shipped tablets purify %d and the filter %d, so there is no smaller remainder to prefer" % [small, large])
		return false
	for tablets_first in [true, false]:
		var w: Variant = _pocket(5502 + (1 if tablets_first else 2))
		if _give(w, UNTREATED) < 0:
			return false
		var ids: Array = [TABLETS, FILTER] if tablets_first else [FILTER, TABLETS]
		for id in ids:
			if _give(w, String(id)) < 0:
				return false
		var res: Dictionary = SimNeeds.purify(w, w.player)
		if not bool(res.get("ok", false)):
			push_error("RANK: a pack with two purifiers in it treated nothing: %s" % str(res))
			return false
		if String(res.get("with", "")) != TABLETS:
			push_error("RANK: with both in the pack the bottle was treated with '%s', not the nearly-spent tablet (tablets stowed first: %s)" % [String(res.get("with", "")), str(tablets_first)])
			return false

	# The true negative, and the reason this is a rule rather than a name: with the tablet gone the
	# filter is what gets used. Without this half, a scan hardcoded to the tablets would pass.
	var only: Variant = _pocket(5504)
	if _give(only, UNTREATED) < 0:
		return false
	if _give(only, FILTER) < 0:
		return false
	var res2: Dictionary = SimNeeds.purify(only, only.player)
	if not bool(res2.get("ok", false)) or String(res2.get("with", "")) != FILTER:
		push_error("RANK: with only the filter in the pack the bottle was treated with %s" % str(res2))
		return false
	print("  RANK: a pack holding a %d-use tablet and a %d-use filter spends the tablet, whichever went in first, and the filter when the tablet is gone" % [small, large])
	return true


# --- REACH ------------------------------------------------------------------------------------
#
# The dead-socket rule, both directions. Every base that declares one of the three keys is
# reachable -- a loot table, or another base's transform -- and every base a transform *names* is
# reachable through that transform or through a table, so a meal nobody can cook and an ingredient
# nobody can find are both refused. Then the textual half: each key is parsed in the file that owns
# it, the two hardcoded ids the slice deleted are actually gone, and the purify verb is reached
# from somewhere a player or a colonist can get to.
func _every_key_is_read_and_every_product_is_reachable() -> bool:
	var w: Variant = _pocket(5601)
	var findable: Dictionary = {}
	var tables: int = 0
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for t_v in file_v as Array:
			if not (t_v is Dictionary) or not String((t_v as Dictionary).get("id", "")).begins_with("loot."):
				continue
			tables += 1
			for row_v in (t_v as Dictionary).get("entries", []) as Array:
				findable[String((row_v as Dictionary).get("item", ""))] = true
	if tables == 0 or findable.is_empty():
		push_error("REACH: %d loot tables loaded, so the reachability half has nothing to judge" % tables)
		return false
	var by_id: Dictionary = {}
	var made_by: Dictionary = {}
	for e_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = e_v as Dictionary
		by_id[String(e.get("id", ""))] = e
		for key in ["cooksInto", "boilsInto"]:
			if e.has(key):
				made_by[String(e[key])] = String(e.get("id", ""))
	# The one base a *verb* produces rather than a table rolls or another base turns into: the well
	# fills a bottle with untreated water. Allowed by name, and the producer's source is read for
	# the id, so the allowance cannot outlive the code it describes -- check_m2_gear.gd's PRODUCED
	# is the precedent and this is the same list with the cook's entry gone, because the cook's
	# product is content's now.
	for row in PRODUCED:
		var pid: String = String(row["id"])
		var producer: String = FileAccess.get_file_as_string(String(row["in"]))
		if not producer.contains("\"%s\"" % pid):
			push_error("REACH: '%s' is allowed as produced but %s never names it" % [pid, String(row["in"])])
			return false
		findable[pid] = true
	var declared: int = 0
	var products: int = 0
	for id in by_id.keys():
		var e2: Dictionary = by_id[id] as Dictionary
		var declares: bool = false
		for key in ["cooksInto", "boilsInto", "purifies"]:
			if e2.has(key):
				declares = true
		if declares:
			declared += 1
			if not (findable.has(String(id)) or made_by.has(String(id))):
				push_error("REACH: '%s' transforms or purifies and is in no loot table and is nobody's product -- complete, correct and unfindable" % String(id))
				return false
		# A product that no table rolls is reachable only through the thing that makes it, so that
		# thing has to be reachable in turn. One that a table does roll needs no such argument.
		if made_by.has(String(id)) and not findable.has(String(id)):
			products += 1
			var src: String = String(made_by[String(id)])
			if not (findable.has(src) or made_by.has(src)):
				push_error("REACH: '%s' is only ever made from '%s', which is itself in no table and nobody's product" % [String(id), src])
				return false
	if declared < 12 or products < 8:
		push_error("REACH: %d bases declare a transform key and %d are products -- this lane is judging almost nothing" % [declared, products])
		return false
	# The scan says no to an id that is not there, which is what makes the yeses above mean
	# something.
	if findable.has("item.gate.absent") or made_by.has("item.gate.absent"):
		push_error("REACH: the scans found an id that does not exist")
		return false

	# The textual half. Each needle is the *parse* of the key in the file that owns it, so a
	# refactor that moves the call still has to keep reading content; and each is proved on a
	# fabricated miss before it is trusted, the rule check_wrecks.gd's `_low_arms` set.
	for row in READERS:
		var code: String = FileAccess.get_file_as_string(String(row["file"]))
		if code.is_empty():
			push_error("REACH: %s could not be read, so the textual half is asserting nothing" % String(row["file"]))
			return false
		if not code.contains(String(row["needle"])):
			push_error("REACH: %s never parses `%s` -- the key is in the schema and in the content and nothing reads it" % [String(row["file"]), String(row["key"])])
			return false
		if code.contains("get(\"cooksOut\", \"\")"):
			push_error("REACH: the needle scan matches a key that does not exist, so it is not reading what it thinks it is")
			return false
	for row2 in VERB_CALLERS:
		var code2: String = FileAccess.get_file_as_string(String(row2["file"]))
		if not code2.contains(String(row2["needle"])):
			push_error("REACH: %s does not reach the purify verb, so nothing in play can use a filter" % String(row2["what"]))
			return false
	# The two deleted welds, named. `jobs.gd` must not spawn a meal by name any more, and `boil`
	# must not name the clean bottle. WATER_ID still exists in needs.gd -- the thirst job and the
	# wash verb reach for water by name and always did -- so the assertion is scoped to `boil`'s
	# own body rather than to the file.
	var jobs_code: String = FileAccess.get_file_as_string("res://sim/modules/jobs.gd")
	if jobs_code.contains("\"%s\"" % COOKED):
		push_error("REACH: jobs.gd still names '%s' -- the cook weld is not deleted, it is doubled" % COOKED)
		return false
	var needs_code: String = FileAccess.get_file_as_string("res://sim/modules/needs.gd")
	var at: int = needs_code.find("static func boil(")
	if at < 0:
		push_error("REACH: needs.gd has no `boil` to read, so the weld assertion has nothing to judge")
		return false
	var body: String = needs_code.substr(at, needs_code.find("\nstatic func ", at + 10) - at)
	if not body.contains("_carried_treatable("):
		push_error("REACH: `boil` does not go through the content scan, so it is still choosing its own vessel")
		return false
	if body.contains("WATER_ID") or body.contains("UNTREATED_ID"):
		push_error("REACH: `boil` still names WATER_ID or UNTREATED_ID -- the boil weld is not deleted")
		return false
	print("  REACH: %d bases declare a transform key and each is rolled or made, %d products each have a reachable source across %d tables; jobs.gd and needs.gd each parse their key, `boil` names neither literal, and the E ladder and the thirst autonomy both reach purify" % [declared, products, tables])
	return true

extends SceneTree
# Build materials -- docs/12-resources.md's gathered and refined tiers, and the owner's decision
# of 2026-09-12: **typed materials, uniform cost**.
#
# The defect this closes: one item id, `item.scrap.metal`, was welded into a `SCRAP_ID` constant
# in fortify.gd *and* into a second copy of the same constant in jobs.gd, and it was the only
# substance in the game that could raise anything. Eleven `material`-class bases shipped beside it
# -- a bolt of cloth, a battery, duct tape, rags, a whetstone -- and not one of them could put a
# plank across a doorway. Meanwhile docs/12 promised a whole gathered and refined tier and none of
# it existed. A recipe now names a *kind*, content declares which kind a base is, and both welds
# are gone.
#
# The lane that matters most is PINNED. Everything else here is new reach, but the retrofit --
# `item.scrap.metal` becoming the `metal` kind -- has to reproduce the old behaviour *exactly*,
# or this is not a new mechanism, it is a silent rebalance of every buildable in the game wearing
# one. Slice 1's DEFAULT lane and slice 2's PINNED lane are the precedent, and this follows them:
# one barricade off one unit, one bench off SimGunsmith.BENCH_SCRAP, one repair off one unit, and
# every verb that was free before this slice still free after it.
#
# KINDS is the dead-socket half, both directions, the way check_m2_attach.gd runs CONTENT and
# HOSTS: every kind the code ranks is declared by something shipped, and every kind something
# shipped declares is one the code ranks. REACH is the other half of the same question and the
# one the milestone keeps paying for -- that the *scan the recipes call* actually reads all
# twelve kinds, rather than the eleven new ones being a vocabulary nothing can see.
#
# Every lane carries a true negative. A gate that cannot fail is worse than no gate.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimModification = preload("res://sim/modules/modification.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Clock = preload("res://sim/time/clock.gd")

# The shipped bases the behavioural lanes put in a pack. Fixtures, not welds: the sim names none
# of them any more, which is the whole point of the slice, but a gate still has to hold something
# concrete.
const SCRAP: String = "item.scrap.metal"
# A *different* metal base from the retrofitted one. The lane that proves a recipe reads the kind
# rather than the id is the lane that hands it this and expects a barricade.
const PIPE: String = "item.metal.pipe"
const BRANCH: String = "item.wood.branch"
# `material` by class, no `buildMaterial` at all: the reason the predicate is a kind and not the
# item class. A whetstone builds nothing and must keep building nothing.
const WHETSTONE: String = "item.whetstone"

# The verbs that cost nothing before this slice and must cost nothing after it. Named rather than
# counted, because the point is not "there are three recipes" -- a fourth is the intended future --
# it is "the slice did not quietly start charging for the alarm line".
const FREE_VERBS: Array[String] = ["window", "alarm", "noisemaker", "wind", "camp"]

# A kind and a verb that do not exist, for the true negatives. Nothing in content or code may
# answer to either.
const NO_KIND: String = "gate.nokind"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_retrofit_builds_exactly_what_it_always_built() and ok
	ok = _a_recipe_reads_the_kind_and_not_the_id() and ok
	ok = _every_kind_is_declared_and_every_declaration_is_a_kind() and ok
	ok = _every_material_can_be_found() and ok
	ok = _the_scan_reaches_every_kind_and_only_the_one_asked_for() and ok
	ok = _every_recipe_names_something_a_survivor_could_hold() and ok
	if ok:
		print("M2_MATERIALS_OK pinned kind kinds findable reach recipes")
		quit(0)
	else:
		push_error("M2_MATERIALS_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

func _world(seed_val: int = 71) -> Variant:
	var f: Dictionary = {
		"seed": seed_val, "tick_hz": 20,
		"map": {"width": 24, "height": 24, "walls": []},
		"player": {"id": 0, "x": 10.5, "y": 13.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimAttachments.register_module(w)
	SimFortify.register_module(w)
	SimModification.register_module(w)
	SimGunsmith.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": -PI / 2.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	SimSkills.attach(w, w.player)
	# The tile the barricade goes on, and the window that makes it scrappable at all
	# (SimFortify.can_scrap wants an outdoor floor next to a window).
	w.tilemap.tiles[11 * int(w.tilemap.w) + 10] = SimTileMap.Tile.Window
	return w


func _give(w: Variant, id: String, count: int = 1) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		push_error("the fixture '%s' would not go in a pocket" % id)
		return -1
	w.events.drain()
	return item


func _channel(w: Variant, cmd: Dictionary) -> void:
	w.commands.push(cmd)
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()


func _barricades(w: Variant) -> int:
	return (w.components.query(["scrapBarricade"]) as Array).size()


func _benches(w: Variant) -> int:
	return (w.components.query(["workbench"]) as Array).size()


## Every `buildMaterial` a shipped base declares: kind -> the ids that declare it.
func _declared(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var kind: String = String(e.get("buildMaterial", ""))
		if kind == "":
			continue
		var ids: Array = out.get(kind, []) as Array
		ids.append(String(e.get("id", "?")))
		out[kind] = ids
	return out


## Every item id any shipped loot table can yield. Read off the tree by path, the way
## check_m2_attach.gd's CONTENT lane reads it: `content_entries` resolves an item by shape and
## does not know the shape of a loot table.
func _droppable() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for table_v in value as Array:
			for row_v in (table_v as Dictionary).get("entries", []) as Array:
				out[String((row_v as Dictionary).get("item", ""))] = true
	return out


# --- PINNED -----------------------------------------------------------------------------------
#
# The retrofit is additive or it is a rebalance. Three things have to be exactly what they were:
# the barricade off one unit of scrap, the bench off SimGunsmith.BENCH_SCRAP of it, and the
# Repair job reaching for the same substance. Plus the half that is easiest to break by accident:
# the verbs that cost nothing before must still cost nothing, because a recipe table is exactly
# the place somebody would helpfully add a price for the alarm line.
func _the_retrofit_builds_exactly_what_it_always_built() -> bool:
	var lane: String = "PINNED"
	for verb in ["scrap", "bench", "repair"]:
		if SimFortify.recipe_kind(String(verb)) != "metal":
			push_error("%s: '%s' is built out of '%s' now, and it was built out of scrap metal before this slice" % [lane, String(verb), SimFortify.recipe_kind(String(verb))])
			return false
	for free_verb in FREE_VERBS:
		if SimFortify.RECIPES.has(free_verb):
			push_error("%s: '%s' cost nothing before this slice and now wants '%s' -- that is a rebalance, not a retrofit" % [lane, String(free_verb), String(SimFortify.RECIPES[free_verb])])
			return false
	if int(SimGunsmith.BENCH_SCRAP) != 3:
		push_error("%s: a bench costs %d units and it has always cost 3 -- if that is deliberate, move this pin, and check_m2_bench.gd reads the same constant" % [lane, int(SimGunsmith.BENCH_SCRAP)])
		return false

	# The shipped scrap carries the kind. A perfect recipe table over content that declares
	# nothing would leave the one buildable substance in the game unusable.
	var w: Variant = _world()
	var entry: Variant = SimItems.content_entry(w, "item", SCRAP)
	if not (entry is Dictionary) or String((entry as Dictionary).get("buildMaterial", "")) != "metal":
		push_error("%s: '%s' declares buildMaterial '%s' -- the shipped scrap was not retrofitted, so nothing in the game is metal" % [lane, SCRAP, String((entry as Dictionary).get("buildMaterial", "")) if entry is Dictionary else "<no entry>"])
		return false

	# One barricade, one unit. Two go in so the assertion is "one was spent", not "the pack is
	# empty" -- an implementation that burned the lot would pass the emptier test.
	if _give(w, SCRAP, 2) < 0:
		return false
	if SimFortify.material_count(w, w.player, "metal") != 2:
		push_error("%s: two scrap in the pack count as %d" % [lane, SimFortify.material_count(w, w.player, "metal")])
		return false
	_channel(w, {"type": "barricade.scrap", "tx": 10, "ty": 12})
	if _barricades(w) != 1:
		push_error("%s: %d barricades after a full channel with scrap in hand" % [lane, _barricades(w)])
		return false
	if not SimTileMap.is_solid(w.tilemap, 10, 12):
		push_error("%s: the barricade did not make the tile solid" % lane)
		return false
	var left: int = SimFortify.material_count(w, w.player, "metal")
	if left != 1:
		push_error("%s: a barricade cost %d units of metal, not one" % [lane, 2 - left])
		return false

	# One bench, BENCH_SCRAP units, off the same substance.
	var w2: Variant = _world(72)
	if _give(w2, SCRAP, int(SimGunsmith.BENCH_SCRAP) + 1) < 0:
		return false
	_channel(w2, {"type": "bench.build", "tx": 10, "ty": 12})
	for _i in int(SimGunsmith.BENCH_TICKS) + 4:
		w2.step()
		if _benches(w2) > 0:
			break
	if _benches(w2) != 1:
		push_error("%s: %d benches after a full channel" % [lane, _benches(w2)])
		return false
	var bench_left: int = SimFortify.material_count(w2, w2.player, "metal")
	if bench_left != 1:
		push_error("%s: a bench cost %d units, not the %d it has always cost" % [lane, int(SimGunsmith.BENCH_SCRAP) + 1 - bench_left, int(SimGunsmith.BENCH_SCRAP)])
		return false

	# The Repair job's reach, which was the second copy of the weld. `_material_for` is the only
	# thing standing between a worn coat and the substance that mends it, so it is asserted
	# directly rather than through the whole job -- and asserted in both directions.
	var w3: Variant = _world(73)
	if _give(w3, SCRAP) < 0:
		return false
	if SimJobs._material_for(w3, w3.player, SimFortify.recipe_kind("repair")) < 0:
		push_error("%s: the Repair job cannot find scrap metal in a pack that is holding some" % lane)
		return false
	if SimJobs._material_for(w3, w3.player, "wood") >= 0:
		push_error("%s: the Repair job found wood in a pack holding only scrap metal" % lane)
		return false
	if SimJobs._material_for(w3, w3.player, "") >= 0:
		push_error("%s: an empty kind matched something -- '' is what material_of answers for an ordinary item, so this would mend a rifle with a tin of beans" % lane)
		return false
	print("  PINNED: one barricade off one unit, one bench off %d, the Repair job still reaches for metal, and %d verbs that were free are still free" % [int(SimGunsmith.BENCH_SCRAP), FREE_VERBS.size()])
	return true


# --- KIND -------------------------------------------------------------------------------------
#
# The point of the slice, and the one assertion the old code could never have passed: the recipe
# asks for a *substance*, so a length of steel pipe raises the barricade that a twist of scrap
# used to. The two negatives are what make that mean anything -- a branch is a build material and
# the wrong one, and a whetstone is a `material` by class and no build material at all, and
# neither may put up a wall.
func _a_recipe_reads_the_kind_and_not_the_id() -> bool:
	var lane: String = "KIND"
	var w: Variant = _world(74)
	var pipe: int = _give(w, PIPE)
	if pipe < 0:
		return false
	if SimFortify.material_of(w, pipe) != "metal":
		push_error("%s: '%s' reads as '%s', not metal" % [lane, PIPE, SimFortify.material_of(w, pipe)])
		return false
	_channel(w, {"type": "barricade.scrap", "tx": 10, "ty": 12})
	if _barricades(w) != 1:
		push_error("%s: a survivor carrying steel pipe and no scrap raised %d barricades -- the recipe is still reading an item id" % [lane, _barricades(w)])
		return false
	# Gone from the pack, asked of the item itself rather than of a count: a miscounting
	# `material_of` would make an unspent pipe read as spent, and a gate that goes red pointing
	# at the wrong thing is the worst kind.
	if SimInventory.carried_items(w, w.player).has(pipe):
		push_error("%s: the barricade went up and the pipe is still in the pack" % lane)
		return false

	# TN 1: the right idea, the wrong substance.
	var w2: Variant = _world(75)
	var branch: int = _give(w2, BRANCH)
	if branch < 0:
		return false
	if SimFortify.material_of(w2, branch) != "wood":
		push_error("%s: '%s' reads as '%s', not wood -- if everything reads as one kind then the refusal below proves nothing" % [lane, BRANCH, SimFortify.material_of(w2, branch)])
		return false
	_channel(w2, {"type": "barricade.scrap", "tx": 10, "ty": 12})
	if _barricades(w2) != 0:
		push_error("%s: a branch raised a scrap barricade -- the recipe accepts any material, which is the old bug with more words" % lane)
		return false
	if not SimInventory.carried_items(w2, w2.player).has(branch):
		push_error("%s: the refused channel spent the branch anyway" % lane)
		return false

	# TN 2: `material` by class, and not a build material. This is why the predicate cannot be
	# "is this item class material" -- eleven bases would answer yes.
	var w3: Variant = _world(76)
	var stone: int = _give(w3, WHETSTONE)
	if stone < 0:
		return false
	if SimFortify.material_of(w3, stone) != "":
		push_error("%s: a whetstone reads as the build material '%s'" % [lane, SimFortify.material_of(w3, stone)])
		return false
	_channel(w3, {"type": "barricade.scrap", "tx": 10, "ty": 12})
	if _barricades(w3) != 0:
		push_error("%s: a whetstone raised a barricade" % lane)
		return false
	print("  KIND: steel pipe raises the barricade scrap used to; a branch and a whetstone are both refused, and neither is spent")
	return true


# --- KINDS ------------------------------------------------------------------------------------
#
# Both directions, the way check_m2_attach.gd's CONTENT and HOSTS lanes run. Neither
# SimFortify.MATERIAL_KINDS nor the schema's enum can see the other, and content can see neither,
# so a kind in the code that nothing declares is a branch no player can reach and a kind in
# content that the code does not rank is content that has outrun its reader.
func _every_kind_is_declared_and_every_declaration_is_a_kind() -> bool:
	var lane: String = "KINDS"
	var w: Variant = _world(77)
	var declared: Dictionary = _declared(w)
	if declared.is_empty():
		push_error("%s: no shipped base declares a build material, so this lane is judging nothing" % lane)
		return false
	if SimFortify.MATERIAL_KINDS.is_empty():
		push_error("%s: the code ranks no kinds at all" % lane)
		return false
	var unreachable: Array[String] = []
	for kind in SimFortify.MATERIAL_KINDS:
		if not declared.has(String(kind)):
			unreachable.append(String(kind))
	if not unreachable.is_empty():
		push_error("%s: %s -- the code names these and no shipped base is made of them, which is a branch nobody can reach" % [lane, str(unreachable)])
		return false
	var unknown: Array[String] = []
	for kind2 in declared.keys():
		if not SimFortify.MATERIAL_KINDS.has(String(kind2)):
			unknown.append("%s (declared by %s)" % [String(kind2), str(declared[kind2])])
	if not unknown.is_empty():
		push_error("%s: %s -- content declaring a kind the code ranks nowhere is content that has outrun its reader" % [lane, str(unknown)])
		return false

	# TN: the predicates have to be able to say no, and no real kind is left for them to say no
	# about -- that is what the two halves above just established -- so both negatives are
	# fabricated. The same shape as check_m2_attach.gd's HOSTS lane.
	if declared.has(NO_KIND) or SimFortify.MATERIAL_KINDS.has(NO_KIND):
		push_error("%s: the scans found a kind that does not exist" % lane)
		return false
	var probe_code: Array[String] = SimFortify.MATERIAL_KINDS.duplicate()
	probe_code.append(NO_KIND)
	var caught: Array[String] = []
	for kind3 in probe_code:
		if not declared.has(String(kind3)):
			caught.append(String(kind3))
	if caught != [NO_KIND]:
		push_error("%s: the reachability predicate cannot say no -- a fabricated kind produced %s" % [lane, str(caught)])
		return false
	var probe_content: Dictionary = declared.duplicate()
	probe_content[NO_KIND] = ["item.gate.orphan"]
	var caught2: Array[String] = []
	for kind4 in probe_content.keys():
		if not SimFortify.MATERIAL_KINDS.has(String(kind4)):
			caught2.append(String(kind4))
	if caught2 != [NO_KIND]:
		push_error("%s: the vocabulary predicate cannot say no -- a fabricated declaration produced %s" % [lane, str(caught2)])
		return false
	var bases: int = 0
	for ids in declared.values():
		bases += (ids as Array).size()
	print("  KINDS: %d kinds, %d bases made of them, every kind declared by something and every declaration ranked" % [SimFortify.MATERIAL_KINDS.size(), bases])
	return true


# --- FINDABLE ---------------------------------------------------------------------------------
#
# docs/12's scavenged tier is where materials come from, so a build material in no loot table is
# a substance no survivor will ever pick up: complete, correct and unreachable, which is this
# milestone's own definition of a dead socket. check_m2_gear.gd's CATALOGUE asks the same question
# of the whole roster now that `buildMaterial` is one of its READ_KEYS; this asks it here too,
# because a materials gate that did not would be trusting another gate to notice.
func _every_material_can_be_found() -> bool:
	var lane: String = "FINDABLE"
	var w: Variant = _world(78)
	var droppable: Dictionary = _droppable()
	if droppable.is_empty():
		push_error("%s: no loot table rows were read, so findability is asserting nothing" % lane)
		return false
	var declared: Dictionary = _declared(w)
	var lost: Array[String] = []
	var judged: int = 0
	for kind in declared.keys():
		for id in declared[kind] as Array:
			judged += 1
			if not droppable.has(String(id)):
				lost.append(String(id))
	if not lost.is_empty():
		push_error("%s: %s are made of something and sit in no loot table" % [lane, str(lost)])
		return false
	# Every kind, not merely every base: a kind whose only bases were all left out of the tables
	# would be a substance the world cannot hand you.
	var unfindable_kinds: Array[String] = []
	for kind2 in SimFortify.MATERIAL_KINDS:
		var any: bool = false
		for id2 in declared.get(String(kind2), []) as Array:
			if droppable.has(String(id2)):
				any = true
		if not any:
			unfindable_kinds.append(String(kind2))
	if not unfindable_kinds.is_empty():
		push_error("%s: %s -- nothing any table can yield is made of these" % [lane, str(unfindable_kinds)])
		return false
	# TN: the scan does not see an id that is not there.
	if droppable.has("item.gate.orphan"):
		push_error("%s: the loot scan found an id that does not exist" % lane)
		return false
	print("  FINDABLE: %d material bases across %d droppable ids, every kind yielded by some table" % [judged, droppable.size()])
	return true


# --- REACH ------------------------------------------------------------------------------------
#
# The dead-socket rule aimed at the thing this slice actually added. KINDS proves the vocabulary
# agrees with the content; it does not prove anything *reads* it. This walks all twelve kinds
# through the one scan every recipe calls -- put a shipped base of the kind in a pack, and the
# scan that a barricade would use has to find it -- so the eleven kinds no recipe names yet are
# still wired end to end rather than being a list nothing can see. The negative in the same loop:
# the scan must be deaf to a kind it was not asked for, or it is a scan that simply says yes.
func _the_scan_reaches_every_kind_and_only_the_one_asked_for() -> bool:
	var lane: String = "REACH"
	var probe: Variant = _world(79)
	var declared: Dictionary = _declared(probe)
	var reached: int = 0
	for kind_v in SimFortify.MATERIAL_KINDS:
		var kind: String = String(kind_v)
		var ids: Array = declared.get(kind, []) as Array
		if ids.is_empty():
			push_error("%s: nothing is made of '%s', so there is nothing to walk through the scan" % [lane, kind])
			return false
		var w: Variant = _world(80 + reached)
		var item: int = _give(w, String(ids[0]))
		if item < 0:
			return false
		if SimFortify.material_of(w, item) != kind:
			push_error("%s: '%s' is declared '%s' and reads as '%s'" % [lane, String(ids[0]), kind, SimFortify.material_of(w, item)])
			return false
		if SimFortify.carried_material(w, w.player, kind) != item:
			push_error("%s: a pack holding '%s' answers %d when asked for '%s' -- the kind is declared and nothing reads it" % [lane, String(ids[0]), SimFortify.carried_material(w, w.player, kind), kind])
			return false
		if SimFortify.material_count(w, w.player, kind) < 1:
			push_error("%s: the count of '%s' in a pack holding some is %d" % [lane, kind, SimFortify.material_count(w, w.player, kind)])
			return false
		# TN, in the same world: some other real kind, and a kind that does not exist.
		var other: String = "wood" if kind != "wood" else "metal"
		if SimFortify.carried_material(w, w.player, other) >= 0:
			push_error("%s: a pack holding only '%s' answered a question about '%s'" % [lane, kind, other])
			return false
		if SimFortify.carried_material(w, w.player, NO_KIND) >= 0 or SimFortify.material_count(w, w.player, NO_KIND) != 0:
			push_error("%s: a kind that does not exist found something" % lane)
			return false
		reached += 1
	if reached != SimFortify.MATERIAL_KINDS.size():
		push_error("%s: %d of %d kinds walked" % [lane, reached, SimFortify.MATERIAL_KINDS.size()])
		return false
	print("  REACH: all %d kinds go into a pack and come back out of the scan the recipes call; none answers for another kind or for one that does not exist" % reached)
	return true


# --- RECIPES ----------------------------------------------------------------------------------
#
# The recipe table's own reachability: a verb that asks for a substance nothing is made of, or
# that no table can hand you, is a buildable nobody can build. The print line names the kinds no
# recipe wants yet, because that is the honest half of this slice -- the vocabulary and the
# content shipped, the recipes that spend eleven of the twelve kinds did not, and a number in the
# build log is how that stays visible instead of being quietly forgotten.
func _every_recipe_names_something_a_survivor_could_hold() -> bool:
	var lane: String = "RECIPES"
	var w: Variant = _world(95)
	var declared: Dictionary = _declared(w)
	var droppable: Dictionary = _droppable()
	if SimFortify.RECIPES.is_empty():
		push_error("%s: no recipe names a material, so this lane is judging nothing" % lane)
		return false
	var wanted: Dictionary = {}
	for verb in SimFortify.RECIPES.keys():
		var kind: String = SimFortify.recipe_kind(String(verb))
		if not SimFortify.MATERIAL_KINDS.has(kind):
			push_error("%s: '%s' is built out of '%s', which is not a kind -- nobody can ever satisfy it" % [lane, String(verb), kind])
			return false
		var holdable: bool = false
		for id in declared.get(kind, []) as Array:
			if droppable.has(String(id)):
				holdable = true
		if not holdable:
			push_error("%s: '%s' wants '%s' and no base made of it is in any loot table" % [lane, String(verb), kind])
			return false
		wanted[kind] = true
	# TN: the same predicate, fed a fabricated recipe.
	var probe: Dictionary = SimFortify.RECIPES.duplicate()
	probe["gate.verb"] = NO_KIND
	var caught: Array[String] = []
	for verb2 in probe.keys():
		if not SimFortify.MATERIAL_KINDS.has(String(probe[verb2])):
			caught.append(String(verb2))
	if caught != ["gate.verb"]:
		push_error("%s: the predicate cannot say no -- a fabricated recipe produced %s" % [lane, str(caught)])
		return false
	var unspent: Array[String] = []
	for kind2 in SimFortify.MATERIAL_KINDS:
		if not wanted.has(String(kind2)):
			unspent.append(String(kind2))
	print("  RECIPES: %d recipes, each naming a kind something shipped is made of and some table yields; %d kinds no recipe spends yet%s" % [
		SimFortify.RECIPES.size(), unspent.size(), (" (%s)" % ", ".join(unspent)) if not unspent.is_empty() else "",
	])
	return true

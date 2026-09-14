extends SceneTree
# A body asleep in a building -- the third piece of the owner's 2026-09-14 procedural-population
# arc. The generator writes a `map.dormant` manifest into the far buildings, `SimBoot.playable`
# turns each record into a zombie the way it turns a parked-car record into a car, and the new
# `ShamblerState.Dormant` keeps that body still and blind until something wakes it.
#
# Seven lanes, each with its own true negative, because the whole feature is invisible from the
# outside: a body that is asleep and a body that is not there look identical to anything that only
# counts.
#
#   CONTENT      the `dormant` block's nested shape, which **neither** validator can see: the
#                Godot one is shallow, and the frozen oracle's CONTENT_TYPES never lists
#                `buildings/` at all. Negative: five fabricated blocks, each refused.
#   MANIFEST     every record is indoors, inside the building it names, outside the annex and
#                clear of both gates. Negative: the same seed and size through a content tree
#                whose every template declares `chance: 0` yields no records at all, on a map that
#                still has far buildings -- so the emptiness is the content and not the geometry.
#   BOOT         entities == records, every one of them Dormant, and the district's shambler count
#                is the old scatter plus the manifest. Negative: a seed whose manifest is empty
#                boots exactly the old count and no Dormant body, which is what says the counter
#                can tell nineteen from none.
#   ASLEEP       they are still asleep two hundred ticks later, in a real booted district.
#                This one is a regression lane with a measurement behind it: the first cut of the
#                Dormant arm woke on `smelled`, and every body on seed 20260805 at 256 woke on
#                **its own residue** on tick 21 (1.0 in its own cell against a 0.00556 threshold).
#   WAKE         a noise at a sleeping body's tile wakes it and it moves; its twin in an identical
#                silent world does neither.
#   NO SIGHT     textual, and the point of the whole state: the Dormant arm must never call
#                `_seen_target`, because a shadowcast is the most expensive thing one of these
#                bodies can do and a district's worth of them would pay for it every tick to look
#                at an empty room. The lane isolates the arm by indentation rather than by
#                searching the file (a needle a comment can satisfy cannot fail -- CLAUDE.md), and
#                proves the isolator on the *Seek* arm, which must contain the call.
#   SAVE         Dormant round-trips through real save text; a Wandering body beside it comes back
#                Wandering, so the assertion is not "everything reads 5".

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimSave = preload("res://sim/save.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

# The balance harness's seeds, so this lane and that one are talking about the same districts.
const FAST_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
# The shipped district, and the miniature every gate boots. Both are checked: at 64 the gates'
# map is mostly inside `GATE_EXCLUSION` of its own gate (the disc is half the map -- see
# check_m2_camp.gd's header) so most seeds legally hold nobody, which is why the skip line exists.
const SHIPPED_TILES: int = 256
const GATE_TILES: int = 64

const SHAMBLER_SOURCE: String = "res://sim/modules/shambler.gd"
# The indentation the `match int(sd["state"])` arms sit at inside `shambler.think`, and the one
# their bodies sit at. Counted rather than guessed, and asserted before either is used.
const ARM_INDENT: String = "\t\t\t\t"
const BODY_INDENT: String = "\t\t\t\t\t"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _content() and ok
	ok = _manifest() and ok
	ok = _boot() and ok
	ok = _stays_asleep() and ok
	ok = _wake() and ok
	ok = _no_sight() and ok
	ok = _save() and ok
	if ok:
		print("M2_DORMANT_OK content manifest boot asleep wake no-sight save")
		quit(0)
	else:
		push_error("M2_DORMANT_FAIL")
		quit(1)


# --- CONTENT ------------------------------------------------------------------------------------
#
# `dormant: {chance, max}` on a building template. Nobody else checks this shape: `godot:validate`
# stops at "is it an object", and `npm test`'s Ajv -- which does recurse -- never reads
# `buildings/` because the frozen oracle's CONTENT_TYPES does not list it. So this predicate is the
# whole of the enforcement, and it is proved on fabricated blocks before it is trusted on shipped
# ones.
const DORMANT_KEYS: Array[String] = ["chance", "max"]

func _dormant_block_bad(block: Variant) -> String:
	if not (block is Dictionary):
		return "not an object"
	var d: Dictionary = block as Dictionary
	for key in d.keys():
		if not DORMANT_KEYS.has(String(key)):
			return "unexpected key %s" % String(key)
	for key in DORMANT_KEYS:
		if not d.has(key):
			return "missing %s" % key
	var chance: Variant = d["chance"]
	if not (chance is float or chance is int):
		return "chance is not a number"
	if float(chance) < 0.0 or float(chance) > 1.0:
		return "chance %s is outside 0..1" % str(chance)
	var most: Variant = d["max"]
	if not (most is int) and not (most is float and float(most) == floor(float(most))):
		return "max is not an integer"
	if int(most) < 0:
		return "max %s is negative" % str(most)
	return ""

func _content() -> bool:
	var lane: String = "CONTENT"
	var tree: Dictionary = ContentLoader.load_tree()
	var declared: Array[String] = []
	for path in tree.keys():
		if not String(path).begins_with("buildings/"):
			continue
		var entry: Variant = tree[path]
		if not (entry is Dictionary):
			continue
		if not (entry as Dictionary).has("dormant"):
			continue
		var why: String = _dormant_block_bad((entry as Dictionary)["dormant"])
		if why != "":
			push_error("%s: %s declares a dormant block that is %s" % [lane, String(path), why])
			return false
		declared.append(String(path))
	if declared.size() < 1:
		push_error("%s: no building template declares a dormant block, so the pass has nothing to place" % lane)
		return false
	# The true negative. Each of these is a mistake `npm run godot:validate` passes with
	# GODOT_CONTENT_OK -- it checks that `dormant` is an object and stops -- and each has to be
	# refused here or this lane is decoration.
	var sabotage: Array = [
		{"chance": 1.4, "max": 2},
		{"chance": 0.3},
		{"chance": 0.3, "max": 2, "colour": "green"},
		{"chance": "often", "max": 1},
		{"chance": 0.3, "max": -1},
	]
	for bad in sabotage:
		if _dormant_block_bad(bad) == "":
			push_error("%s: the shape check accepted %s, so it would accept anything" % [lane, str(bad)])
			return false
	if _dormant_block_bad({"chance": 0.35, "max": 2}) != "":
		push_error("%s: the shape check refused the block every shipped template carries" % lane)
		return false
	print("%s OK %d templates declare a dormant block, %d fabricated blocks refused" % [lane, declared.size(), sabotage.size()])
	return true


# --- MANIFEST -----------------------------------------------------------------------------------

func _record_bad(map: Variant, rec: Variant, far: Array[int], seen: Dictionary) -> String:
	if not (rec is Dictionary):
		return "not a record"
	var r: Dictionary = rec as Dictionary
	for key in ["x", "y", "building"]:
		if not r.has(key):
			return "has no %s" % key
	var tx: int = int(r["x"])
	var ty: int = int(r["y"])
	var key2: String = "%d,%d" % [tx, ty]
	if seen.has(key2):
		return "shares tile %s with another body" % key2
	seen[key2] = true
	if not SimTileMap.is_indoors(map, tx, ty):
		return "is outdoors at %s" % key2
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return "is not on a Floor tile at %s" % key2
	if SimTileMap.is_solid(map, tx, ty):
		return "is inside something solid at %s" % key2
	var index: int = int(r["building"])
	if index < 0 or index >= (map.buildings as Array).size():
		return "names building %d, which the map does not have" % index
	if not far.has(index):
		return "names building %d, which is not far enough from home to hold anybody" % index
	var b: Dictionary = (map.buildings as Array)[index] as Dictionary
	var rect: Rect2i = Rect2i(int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"]))
	if not rect.has_point(Vector2i(tx, ty)):
		return "at %s is not inside the building %d it names, %s" % [key2, index, str(rect)]
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x > 0 and annex.has_point(Vector2i(tx, ty)):
		return "at %s is inside the colony's own annex" % key2
	for gate in [SimTileMap.gate_a(map), SimTileMap.gate_b(map)]:
		if gate.x < 0:
			continue
		var dx: float = float(tx - gate.x)
		var dy: float = float(ty - gate.y)
		if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
			return "at %s lies %.1f m from the gate at %s, inside GATE_EXCLUSION" % [key2, sqrt(dx * dx + dy * dy), str(gate)]
	return ""

func _manifest() -> bool:
	var lane: String = "MANIFEST"
	var tree: Dictionary = ContentLoader.load_tree()
	var placed_anywhere: int = 0
	var skipped: int = 0
	for size in [GATE_TILES, SHIPPED_TILES]:
		for seed_value in FAST_SEEDS:
			var map: Variant = SimWorldgen.generate(int(seed_value), int(size), tree)
			var far: Array[int] = SimWorldgen.far_buildings(map, SimDirector.GATE_EXCLUSION)
			var records: Array = map.dormant as Array
			if records.is_empty():
				# Said out loud rather than passed quietly: a seed with nowhere legal to sleep is
				# a fact about the map, and the lane only fails when *every* one is like that.
				print("DORMANT SKIP seed %d at %d has %d far buildings and no bodies in them" % [int(seed_value), int(size), far.size()])
				skipped += 1
				continue
			var seen: Dictionary = {}
			for rec in records:
				var why: String = _record_bad(map, rec, far, seen)
				if why != "":
					push_error("%s: seed %d at %d -- a record %s" % [lane, int(seed_value), int(size), why])
					return false
			placed_anywhere += records.size()
	if placed_anywhere < 1:
		push_error("%s: not one of the %d seed/size pairs placed a single body, so nothing here was judged" % [lane, FAST_SEEDS.size() * 2])
		return false
	# The negative, and it is the one that says the content is read at all: the same seed and the
	# same size through a tree whose every building declares `chance: 0`. The map still has far
	# buildings -- the geometry is untouched -- and the manifest is empty.
	var zeroed: Dictionary = tree.duplicate(true)
	var touched: int = 0
	for path in zeroed.keys():
		if not String(path).begins_with("buildings/"):
			continue
		var entry: Variant = zeroed[path]
		if entry is Dictionary:
			(entry as Dictionary)["dormant"] = {"chance": 0.0, "max": 2}
			touched += 1
	if touched < 1:
		push_error("%s: the fixture tree had no building templates to zero, so its emptiness proves nothing" % lane)
		return false
	var quiet: Variant = SimWorldgen.generate(int(FAST_SEEDS[0]), SHIPPED_TILES, zeroed)
	var quiet_far: Array[int] = SimWorldgen.far_buildings(quiet, SimDirector.GATE_EXCLUSION)
	if quiet_far.size() < 1:
		push_error("%s: the zeroed fixture has no far buildings either, so an empty manifest says nothing about chance" % lane)
		return false
	if not (quiet.dormant as Array).is_empty():
		push_error("%s: a tree with chance 0 on every template still placed %d bodies" % [lane, (quiet.dormant as Array).size()])
		return false
	print("%s OK %d bodies across %d seed/size pairs (%d skipped), chance 0 on %d templates placed none over %d far buildings" % [
		lane, placed_anywhere, FAST_SEEDS.size() * 2, skipped, touched, quiet_far.size(),
	])
	return true


# --- BOOT ---------------------------------------------------------------------------------------

func _dormant_ids(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for e in w.components.query(["shambler"]):
		var sd: Variant = w.components.get_component(int(e), "shambler")
		if sd is Dictionary and int((sd as Dictionary)["state"]) == SimShambler.ShamblerState["Dormant"]:
			out.append(int(e))
	return out

func _boot() -> bool:
	var lane: String = "BOOT"
	var judged: int = 0
	for pair in [[31337, GATE_TILES], [FAST_SEEDS[0], SHIPPED_TILES]]:
		var seed_value: int = int((pair as Array)[0])
		var size: int = int((pair as Array)[1])
		var boot: Dictionary = SimBoot.playable(seed_value, size)
		var w: Variant = boot["world"]
		var map: Variant = boot["map"]
		var records: Array = map.dormant as Array
		if records.is_empty():
			print("DORMANT SKIP seed %d at %d booted an empty manifest" % [seed_value, size])
			continue
		var asleep: Array[int] = _dormant_ids(w)
		if asleep.size() != records.size():
			push_error("%s: seed %d at %d has %d records and %d Dormant bodies" % [lane, seed_value, size, records.size(), asleep.size()])
			return false
		# Every record has a body standing on it, not merely the right number of bodies somewhere.
		var at_tile: Dictionary = {}
		for e in asleep:
			var pos: Dictionary = w.components.get_component(int(e), "position") as Dictionary
			at_tile["%d,%d" % [floori(float(pos["x"])), floori(float(pos["y"]))]] = int(e)
		for rec in records:
			var r: Dictionary = rec as Dictionary
			var key: String = "%d,%d" % [int(r["x"]), int(r["y"])]
			if not at_tile.has(key):
				push_error("%s: seed %d at %d wrote a record at %s and nobody is lying there" % [lane, seed_value, size, key])
				return false
			var zt: Variant = w.components.get_component(int(at_tile[key]), "zombieType")
			var id: String = String((zt as Dictionary).get("id", "")) if zt is Dictionary else ""
			if id != SimRoster.TYPE_SHAMBLER:
				push_error("%s: the body at %s is a %s -- the day-1 pick must be a shambler" % [lane, key, id])
				return false
		var total: int = w.components.query(["shambler"]).size()
		var want: int = SimBoot.wanderers_for(size) + records.size()
		if total != want:
			push_error("%s: seed %d at %d booted %d shamblers, want %d scatter + %d asleep" % [lane, seed_value, size, total, SimBoot.wanderers_for(size), records.size()])
			return false
		judged += 1
	if judged < 1:
		push_error("%s: every seed it tried booted an empty manifest, so nothing was judged" % lane)
		return false
	# The counter's true negative: a seed whose 64-tile map legally holds nobody boots the old
	# count and no Dormant body at all. Without this, "19 records, 19 asleep" is also what a lane
	# that cannot see a sleeping body would report on a map with none.
	var empty: Dictionary = SimBoot.playable(int(FAST_SEEDS[0]), GATE_TILES)
	var ew: Variant = empty["world"]
	if not (empty["map"].dormant as Array).is_empty():
		push_error("%s: seed %d at %d was chosen as the empty-manifest control and is no longer empty" % [lane, int(FAST_SEEDS[0]), GATE_TILES])
		return false
	if _dormant_ids(ew).size() != 0:
		push_error("%s: the empty-manifest control booted %d Dormant bodies" % [lane, _dormant_ids(ew).size()])
		return false
	if ew.components.query(["shambler"]).size() != SimBoot.wanderers_for(GATE_TILES):
		push_error("%s: the empty-manifest control booted %d shamblers, want %d" % [lane, ew.components.query(["shambler"]).size(), SimBoot.wanderers_for(GATE_TILES)])
		return false
	print("%s OK %d districts judged; the empty-manifest control boots %d shamblers and nobody asleep" % [lane, judged, SimBoot.wanderers_for(GATE_TILES)])
	return true


# --- ASLEEP -------------------------------------------------------------------------------------
#
# The regression this slice actually cost a measurement to find. A dormant body lays residue like
# every other body (docs/14, and nothing here special-cases that) -- so if the wake condition reads
# the raw `smelled`, the body reads its own residue and wakes on the first
# `SCENT_EMIT_INTERVAL`. Measured on seed 20260805 at 256 before the fix: 1.0 of scent in its own
# cell at t+20 against a threshold of 0.00556, and all nineteen awake at t+21. So this lane boots a
# real district, lets it run, and requires the bodies to still be where they were, still asleep.
const ASLEEP_TICKS: int = 200

func _stays_asleep() -> bool:
	var lane: String = "ASLEEP"
	var boot: Dictionary = SimBoot.playable(31337, GATE_TILES)
	var w: Variant = boot["world"]
	var records: Array = boot["map"].dormant as Array
	if records.is_empty():
		push_error("%s: seed 31337 at %d is the fixture for this lane and its manifest is empty" % [lane, GATE_TILES])
		return false
	var before: Dictionary = {}
	for e in _dormant_ids(w):
		var pos: Dictionary = w.components.get_component(int(e), "position") as Dictionary
		before[int(e)] = Vector2(float(pos["x"]), float(pos["y"]))
	if before.size() != records.size():
		push_error("%s: %d records and %d bodies asleep at boot" % [lane, records.size(), before.size()])
		return false
	for _t in ASLEEP_TICKS:
		w.step()
	for e in before.keys():
		var sd: Variant = w.components.get_component(int(e), "shambler")
		if not (sd is Dictionary) or int((sd as Dictionary)["state"]) != SimShambler.ShamblerState["Dormant"]:
			push_error("%s: body %d woke on its own after %d ticks with nothing near it -- state %d" % [
				lane, int(e), ASLEEP_TICKS, int((sd as Dictionary)["state"]) if sd is Dictionary else -1,
			])
			return false
		var now: Dictionary = w.components.get_component(int(e), "position") as Dictionary
		var was: Vector2 = before[int(e)] as Vector2
		if absf(float(now["x"]) - was.x) > 0.001 or absf(float(now["y"]) - was.y) > 0.001:
			push_error("%s: body %d moved from %s to (%.3f, %.3f) while asleep" % [lane, int(e), str(was), float(now["x"]), float(now["y"])])
			return false
	print("%s OK %d bodies still asleep and still where they lay after %d ticks" % [lane, before.size(), ASLEEP_TICKS])
	return true


# --- WAKE ---------------------------------------------------------------------------------------
#
# Two worlds built the same way, one of them loud. `world.step()` drains at the end of the tick
# (CLAUDE.md), so the noise is put straight onto the field rather than published -- the same thing
# `check_m2_roster.gd`'s residue lane does -- and the body is given the tick after it to read it.
const WAKE_TICKS: int = 40
const WAKE_NOISE_MULTIPLE: float = 7.0

func _fixture(seed_val: int) -> Dictionary:
	return {"seed": seed_val, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 2.0, "y": 2.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

func _sleeper_world(seed_val: int) -> Dictionary:
	var world: Variant = World.new(_fixture(seed_val))
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimShambler.register_module(world, map)
	var rng: Variant = world.rng.stream("shambler")
	var zed: int = SimRoster.spawn_zombie(world, 12.5, 12.5, SimRoster.TYPE_SHAMBLER, rng)
	SimShambler.make_dormant(world, zed)
	return {"world": world, "zed": zed}

func _wake() -> bool:
	var lane: String = "WAKE"
	var loud: Dictionary = _sleeper_world(4242)
	var quiet: Dictionary = _sleeper_world(4242)
	var lw: Variant = loud["world"]
	var qw: Variant = quiet["world"]
	var floor_v: float = float(lw.field.calibration["floor"])
	var start: Vector2 = Vector2(12.5, 12.5)
	# The component Dictionary is the same object `shambler.think` mutates, so this reads the live
	# state rather than a copy taken at the top.
	var lsd: Dictionary = lw.components.get_component(int(loud["zed"]), "shambler") as Dictionary
	var qsd: Dictionary = qw.components.get_component(int(quiet["zed"]), "shambler") as Dictionary
	var woke_at: int = -1
	for t in WAKE_TICKS:
		lw.field.emit_noise(start.x, start.y, floor_v * WAKE_NOISE_MULTIPLE)
		lw.step()
		qw.step()
		if woke_at < 0 and int(lsd["state"]) != SimShambler.ShamblerState["Dormant"]:
			woke_at = int(t)
	if woke_at < 0:
		push_error("%s: a noise at its own tile left the body asleep for all %d ticks" % [lane, WAKE_TICKS])
		return false
	# It leaves for Wander and the ordinary ladder takes it on from there -- a body that hears
	# something goes Wander -> Seek -> Investigate inside a few ticks, which is the point: waking
	# hands it back to the state machine rather than to a special case.
	if int(lsd["state"]) == SimShambler.ShamblerState["Dormant"]:
		push_error("%s: the body woke and went back to sleep, which nothing is supposed to do" % lane)
		return false
	var lpos: Dictionary = lw.components.get_component(int(loud["zed"]), "position") as Dictionary
	if Vector2(float(lpos["x"]), float(lpos["y"])).distance_to(start) < 0.01:
		push_error("%s: the body woke and then did not move, so waking reaches the state and not the legs" % lane)
		return false
	if int(qsd["state"]) != SimShambler.ShamblerState["Dormant"]:
		push_error("%s: the silent twin woke anyway, in state %d -- the noise proves nothing" % [lane, int(qsd["state"])])
		return false
	var qpos: Dictionary = qw.components.get_component(int(quiet["zed"]), "position") as Dictionary
	if Vector2(float(qpos["x"]), float(qpos["y"])).distance_to(start) > 0.001:
		push_error("%s: the silent twin moved to (%.3f, %.3f) without waking" % [lane, float(qpos["x"]), float(qpos["y"])])
		return false
	print("%s OK loud woke on tick %d into state %d and walked %.2f m; the silent twin did neither" % [
		lane, woke_at, int(lsd["state"]), Vector2(float(lpos["x"]), float(lpos["y"])).distance_to(start),
	])
	return true


# --- NO SIGHT -----------------------------------------------------------------------------------
#
# The arm is isolated by indentation, not by searching for words: `think`'s `match` has its arms at
# four tabs and their bodies at five, so "the lines after the Dormant label that are indented
# deeper than a label" is a slice no comment elsewhere in the file can satisfy and no later arm can
# displace. The isolator is then *shown to work* on the Seek arm, which must contain the call --
# CLAUDE.md's `main.gd` double-match trap: a textual assertion has to be proved it is reading what
# it thinks it is.
#
# **Comments are stripped**, and that is not tidiness either: the first run of this lane went red
# against code that was correct, because the Dormant arm's own comment explains that it does not
# call `_seen_target` and the needle found the words. CLAUDE.md's rule is that a needle a comment
# can satisfy cannot fail; its mirror is that a needle a comment can *trip* blames the wrong thing.
# Nothing in these arms puts a `#` inside a string literal, so cutting at the first one is exact.
func _arm_lines(lines: Array, label: String) -> Array:
	var out: Array = []
	var head: String = "%sShamblerState[\"%s\"]:" % [ARM_INDENT, label]
	var i: int = lines.find(head)
	if i < 0:
		return out
	for j in range(i + 1, lines.size()):
		var line: String = String(lines[j])
		if line.strip_edges() == "":
			continue
		if not line.begins_with(BODY_INDENT):
			break
		var hash_at: int = line.find("#")
		var code: String = line.substr(0, hash_at) if hash_at >= 0 else line
		if code.strip_edges() == "":
			continue
		out.append(code)
	return out

func _no_sight() -> bool:
	var lane: String = "NO SIGHT"
	var f := FileAccess.open(SHAMBLER_SOURCE, FileAccess.READ)
	if f == null:
		push_error("%s: cannot read %s" % [lane, SHAMBLER_SOURCE])
		return false
	var lines: Array = Array(f.get_as_text().split("\n"))
	var seek: Array = _arm_lines(lines, "Seek")
	if seek.is_empty():
		push_error("%s: the isolator found no Seek arm, so it is reading nothing" % lane)
		return false
	if not "\n".join(PackedStringArray(seek)).contains("_seen_target"):
		push_error("%s: the isolator sliced %d lines out of the Seek arm and none of them calls _seen_target, so it is not reading the arm it thinks it is" % [lane, seek.size()])
		return false
	var dormant: Array = _arm_lines(lines, "Dormant")
	if dormant.is_empty():
		push_error("%s: there is no Dormant arm in %s" % [lane, SHAMBLER_SOURCE])
		return false
	var body: String = "\n".join(PackedStringArray(dormant))
	if not body.contains("ShamblerState[\"Wander\"]"):
		push_error("%s: the Dormant arm never leaves for Wander, so a sleeping body never wakes" % lane)
		return false
	if body.contains("_seen_target"):
		push_error("%s: the Dormant arm calls _seen_target -- a sleeping body must not pay for a shadowcast" % lane)
		return false
	print("%s OK the Dormant arm is %d lines of code and casts no sight; the Seek arm the isolator was proved on does" % [lane, dormant.size()])
	return true


# --- SAVE ---------------------------------------------------------------------------------------

func _save() -> bool:
	var lane: String = "SAVE"
	var built: Dictionary = _sleeper_world(909)
	var w: Variant = built["world"]
	var sleeper: int = int(built["zed"])
	# A second body, awake, in the same world -- so "the state came back as 5" cannot be satisfied
	# by a restore that gives everybody the same number.
	var awake: int = SimRoster.spawn_zombie(w, 6.5, 6.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary)["snapshot"] is Dictionary):
		push_error("%s: the save did not come back as an object" % lane)
		return false
	var w2: Variant = World.new(_fixture(909))
	var map2: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w2, map2)
	SimShambler.register_module(w2, map2)
	w2.restore((parsed as Dictionary)["snapshot"] as Dictionary)
	var back: Variant = w2.components.get_component(sleeper, "shambler")
	if not (back is Dictionary):
		push_error("%s: the sleeping body has no shambler component after the restore" % lane)
		return false
	if int((back as Dictionary)["state"]) != SimShambler.ShamblerState["Dormant"]:
		push_error("%s: the sleeping body came back in state %d" % [lane, int((back as Dictionary)["state"])])
		return false
	var other: Variant = w2.components.get_component(awake, "shambler")
	if not (other is Dictionary) or int((other as Dictionary)["state"]) == SimShambler.ShamblerState["Dormant"]:
		push_error("%s: the body that was awake came back asleep, so the restore is not carrying the state at all" % lane)
		return false
	print("%s OK Dormant survived a save; the awake body beside it came back in state %d" % [lane, int((other as Dictionary)["state"])])
	return true

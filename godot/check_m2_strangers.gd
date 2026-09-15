extends SceneTree
# A stranger in a building -- the seventh piece of the owner's 2026-09-14 procedural-population
# arc, and the first of docs/07's three recruitment routes that is not the gate.
#
# The whole feature is invisible to anything that only counts, which is why every lane here
# carries its own true negative: a person hiding in a house and no person at all look identical
# to a survivor count, to the job scheduler, and to the ledger -- that is the *point* of the
# `recruit` tag they wear -- so a lane that merely reports "nothing changed" has measured nothing
# until something has been shown to change it.
#
#   PLACED      the body is indoors, inside a building `far_buildings` returned, outside the annex
#               and clear of both gates. Skips with a line when a seed's district has nowhere
#               legal, and fails only if every seed it tries is like that. Negatives: the
#               predicate refuses a fabricated placement in the colony's own annex, and a district
#               with no buildings at all places nobody **and spends neither the day nor the
#               stream**.
#   DAYLIGHT    the beat fires in the day and in no other phase. Not a mood: a stranger placed at
#               dusk on seed 31337 was killed and **turned** inside one 2,000-tick window, putting
#               a body in the district the director never placed and taking the balance harness's
#               live cap to 33 against 32 (measured with a throwaway driver, deleted). The lane
#               runs the same beat day at dawn, day, dusk and night and requires exactly one of
#               them to place anybody.
#   HIDES       nobody near, and a thousand ticks later they are on the same tile, still Hiding.
#               Negative: the identical fixture with a colonist walked into the room moves them --
#               so "did not move" is a measurement and not the only thing this lane can report.
#   APPROACHES  a colonist in the stranger's own line of sight is closed on to `APPROACH_METRES`.
#               Negative, and the reason the real sight system is used rather than a distance
#               check: a colonist the **same distance away behind a wall** is not approached and
#               not even noticed. Both halves run on one fixture, one stranger, one tick budget.
#   RECRUIT     the E rung that already exists -- `use.context` through the command queue, down
#               `SimFortify`'s ladder, `SimRecruits.waiting_in_reach` then `accept` -- takes them
#               in: the colony count rises by one, the `recruit` tag and the `stranger` component
#               both go, and `survivor.joined` says `recruit`. Negative: the same press with the
#               stranger five metres away accepts nobody.
#   LEDGER      `check_m2_balance.gd`'s `_survivors_alive` counting, reproduced here, is unmoved
#               by a hiding stranger and moves by one when that same stranger is accepted. Plus
#               the textual half: the balance gate's own counter still excludes `recruit`, because
#               a lane that reproduces a rule proves nothing about the rule it reproduced.
#   GATE BEAT   the two regressions this slice could cause, both halves each: a hidden stranger
#               does **not** cancel the day-8 gate beat (and a gate recruit still does), and a
#               waiting stranger is **not** despawned at dawn (and a gate recruit still is).
#   LEAVES      after `STRANGER_DAYS` they give up and go, and the colony is told nothing about
#               somebody it may never have met. Negative: a stranger whose clock has not run out
#               stays, and a gate recruit turned away at the same dawn *does* get its line.
#   SAVE        the `stranger` component and `world.strangers.spawned` round-trip through real
#               save text, path records included. Negative: a second stranger in another state
#               beside it, so "everything came back 0" cannot pass.
#
# Fixture note, stated once: the behaviour lanes boot a real district and then **empty it** --
# every shambler despawned, every colony body but the player despawned. Not because the feature
# needs quiet, but because "did the stranger move towards that colonist" is only an assertion
# about sight if there is exactly one colonist and nothing else in the district that can push a
# body around. `_quiet_solo` is that scrub and it is asserted rather than assumed.

const SimBoot = preload("res://sim/boot.gd")
const SimStrangers = preload("res://sim/modules/strangers.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimSave = preload("res://sim/save.gd")
const SimPeople = preload("res://sim/modules/people.gd")
const World = preload("res://sim/world.gd")
const Clock = preload("res://sim/time/clock.gd")

# The balance harness's seeds, so this gate and that one are talking about the same districts.
const FAST_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
const GATE_TILES: int = 64
const SHIPPED_TILES: int = 256

const BALANCE_SOURCE: String = "res://check_m2_balance.gd"

# How long a behaviour lane runs. 1200 ticks is a minute of sim; at `SimStrangers.SPEED` that is
# seventy metres of walking, which is more than the width of the miniature the gates boot.
const WATCH_TICKS: int = 1200
# The approach gets longer, because a path out of a building and round to a doorway is not a
# straight line: 3000 ticks is two and a half minutes of sim.
const APPROACH_TICKS: int = 3000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _placed() and ok
	ok = _daylight() and ok
	ok = _hides() and ok
	ok = _approaches() and ok
	ok = _recruit() and ok
	ok = _ledger() and ok
	ok = _gate_beat() and ok
	ok = _leaves() and ok
	ok = _save() and ok
	if ok:
		print("M2_STRANGERS_OK placed daylight hides approaches recruit ledger gate-beat leaves save")
		quit(0)
	else:
		push_error("M2_STRANGERS_FAIL")
		quit(1)


# --- fixtures -----------------------------------------------------------------------------------

func _boot(seed_value: int, size: int) -> Dictionary:
	return SimBoot.playable(seed_value, size)


## Empties the district of everything that moves on its own and of every colonist but the player.
## Returns false when it could not -- an empty scrub would make every behaviour lane below a lane
## about an empty room.
func _quiet_solo(w: Variant) -> bool:
	for e in w.components.query(["shambler"]):
		w.despawn(int(e))
	var removed: int = 0
	for e in w.components.query(["needs", "body"]):
		var ent: int = int(e)
		if ent == int(w.player):
			continue
		if w.components.has_component(ent, "stranger"):
			continue
		w.despawn(ent)
		removed += 1
	if not w.components.query(["shambler"]).is_empty():
		push_error("the scrub left %d shamblers in the district" % w.components.query(["shambler"]).size())
		return false
	if removed < 1:
		push_error("the scrub removed no colonists, so it is not doing what the lanes below assume")
		return false
	return true


func _colonists(w: Variant) -> int:
	# `check_m2_balance.gd`'s `_survivors_alive`, reproduced key for key. The LEDGER lane asserts
	# that the original still reads this way, so this copy cannot quietly drift into a kinder one.
	var n: int = 0
	for ent in w.components.query(["needs", "body"]):
		if w.components.has_component(int(ent), "corpse"):
			continue
		if w.components.has_component(int(ent), "recruit"):
			continue
		var body: Variant = w.components.get_component(int(ent), "body")
		if body is Dictionary and SimHealth.is_alive(body as Dictionary):
			n += 1
	return n


func _pos(w: Variant, ent: int) -> Vector2:
	var p: Variant = w.components.get_component(ent, "position")
	if not (p is Dictionary):
		return Vector2(-1.0, -1.0)
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


func _put(w: Variant, ent: int, x: float, y: float) -> void:
	w.components.set_component(ent, "position", {"x": x, "y": y})


func _state_of(w: Variant, ent: int) -> int:
	var s: Variant = w.components.get_component(ent, "stranger")
	return int((s as Dictionary).get("state", -1)) if s is Dictionary else -1


## A stranger placed in a real far building, or -1 with a SKIP line already printed.
func _place_one(w: Variant, seed_value: int, size: int, lane: String) -> int:
	var day: int = Clock.day_number(int(w.tick))
	var ent: int = SimStrangers.place(w, day)
	if ent < 0:
		print("STRANGERS SKIP %s seed %d at %d has no building far enough from home to hide in" % [lane, seed_value, size])
	return ent


# --- PLACED -------------------------------------------------------------------------------------
#
# Where a stranger may stand is three questions, and each is a fairness rule rather than a taste:
# indoors (the whole feature), inside a building the map actually placed (never a tile that
# happens to satisfy the geometry), and far enough from home that finding them is something you
# went out and did. The predicate is proved on a fabricated placement before it is trusted on a
# real one.

func _placement_bad(map: Variant, at: Vector2i, far: Array[int]) -> String:
	if not SimTileMap.is_indoors(map, at.x, at.y):
		return "at %s is not indoors" % str(at)
	if SimTileMap.is_solid(map, at.x, at.y):
		return "at %s is standing in something solid" % str(at)
	var inside: int = -1
	for index in far:
		var b: Dictionary = (map.buildings as Array)[index] as Dictionary
		var rect := Rect2i(int(b.get("x", 0)), int(b.get("y", 0)), int(b.get("w", 0)), int(b.get("h", 0)))
		if rect.has_point(at):
			inside = index
			break
	if inside < 0:
		return "at %s is in no building that `far_buildings` returned" % str(at)
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x > 0 and annex.has_point(at):
		return "at %s is inside the colony's own annex" % str(at)
	for gate in [SimTileMap.gate_a(map), SimTileMap.gate_b(map)]:
		if gate.x < 0:
			continue
		var dx: float = float(at.x - gate.x)
		var dy: float = float(at.y - gate.y)
		if dx * dx + dy * dy < SimStrangers.MIN_METRES * SimStrangers.MIN_METRES:
			return "at %s lies %.1f m from the gate at %s, inside MIN_METRES" % [str(at), sqrt(dx * dx + dy * dy), str(gate)]
	return ""


func _placed() -> bool:
	var lane: String = "PLACED"
	var judged: int = 0
	var skipped: int = 0
	var pairs: Array = []
	for seed_value in FAST_SEEDS:
		pairs.append([int(seed_value), GATE_TILES])
	pairs.append([int(FAST_SEEDS[0]), SHIPPED_TILES])
	for pair in pairs:
		var seed_value: int = int((pair as Array)[0])
		var size: int = int((pair as Array)[1])
		var boot: Dictionary = _boot(seed_value, size)
		var w: Variant = boot["world"]
		var map: Variant = boot["map"]
		var ent: int = _place_one(w, seed_value, size, lane)
		if ent < 0:
			skipped += 1
			continue
		var far: Array[int] = SimWorldgen.far_buildings(map, SimStrangers.MIN_METRES)
		var at: Vector2 = _pos(w, ent)
		var tile := Vector2i(floori(at.x), floori(at.y))
		var why: String = _placement_bad(map, tile, far)
		if why != "":
			push_error("%s: seed %d at %d put somebody %s" % [lane, seed_value, size, why])
			return false
		# The body is a person, not a marker: the same one `spawn_generated` makes for the gate.
		if not w.components.has_component(ent, "identity") or not w.components.has_component(ent, "observer"):
			push_error("%s: the body placed on seed %d has no identity or no eyes" % [lane, seed_value])
			return false
		var r: Variant = w.components.get_component(ent, "recruit")
		if not (r is Dictionary) or not bool((r as Dictionary).get("stranger", false)) or not bool((r as Dictionary).get("waiting", false)):
			push_error("%s: the body placed on seed %d is tagged %s" % [lane, seed_value, str(r)])
			return false
		if _state_of(w, ent) != int(SimStrangers.StrangerState.Hiding):
			push_error("%s: the body placed on seed %d starts in state %d" % [lane, seed_value, _state_of(w, ent)])
			return false
		judged += 1
	if judged < 1:
		push_error("%s: not one of the %d seed/size pairs had anywhere to put a stranger, so nothing was judged" % [lane, pairs.size()])
		return false
	# Negative one: the predicate itself. The colony's own start tile is indoors and solid-free and
	# would pass a lazier check; it is refused because it is the annex, and a stranger in the
	# colony's kitchen is the one place this feature may never put one.
	var control: Dictionary = _boot(int(FAST_SEEDS[0]), SHIPPED_TILES)
	var cmap: Variant = control["map"]
	var start: Vector2i = SimBoot.colony_start(cmap)
	if _placement_bad(cmap, start, SimWorldgen.far_buildings(cmap, SimStrangers.MIN_METRES)) == "":
		push_error("%s: the predicate accepted the colony's own start tile %s, so it accepts anything" % [lane, str(start)])
		return false
	# Negative two: a district with no buildings at all. Nobody is placed, and -- the half that
	# matters for determinism -- the beat spends neither the day nor a draw off the stream, so a
	# campaign on a bare map rolls exactly what it rolled before this slice.
	var bare: Dictionary = _boot(int(FAST_SEEDS[0]), GATE_TILES)
	var bw: Variant = bare["world"]
	bw.tilemap = SimTileMap.blank_map(24, 24)
	if not SimWorldgen.far_buildings(bw.tilemap, SimStrangers.MIN_METRES).is_empty():
		push_error("%s: the blank-map control has far buildings in it, so it controls nothing" % lane)
		return false
	var before_samples: int = _stream_samples(bw, SimStrangers.STREAM)
	bw.tick = Clock.tick_on_day(int(SimStrangers.BEATS[0]), Clock.DAY_BEGINS)
	bw.step()
	if not bw.components.query(["stranger"]).is_empty():
		push_error("%s: the blank-map control placed %d strangers" % [lane, bw.components.query(["stranger"]).size()])
		return false
	if not ((bw.strangers as Dictionary).get("spawned", []) as Array).is_empty():
		push_error("%s: the blank-map control spent beat day %d on a district with nowhere to stand" % [lane, int(SimStrangers.BEATS[0])])
		return false
	if _stream_samples(bw, SimStrangers.STREAM) != before_samples:
		push_error("%s: the blank-map control drew off the `%s` stream anyway" % [lane, SimStrangers.STREAM])
		return false
	print("%s OK %d districts judged (%d skipped); the annex is refused and a district with no buildings places nobody, spends no day and draws nothing" % [lane, judged, skipped])
	return true


func _stream_samples(w: Variant, name: String) -> int:
	var saved: Variant = (w.rng as RefCounted).call("save")
	if saved is Dictionary and (saved as Dictionary).has(name):
		var entry: Variant = (saved as Dictionary)[name]
		if entry is Dictionary:
			return int((entry as Dictionary).get("samples", 0))
	return 0


# --- DAYLIGHT -----------------------------------------------------------------------------------
#
# The arrival has a time of day. The beat used to fire on whatever tick of the beat day the world
# was running: dawn in a real campaign, and **dusk** in `check_m2_balance.gd`'s compressed tier,
# which jumps to each day's dusk and steps a window. A stranger placed at dusk is placed into the
# night the director is filling, and on seed 31337 both of them were killed and turned inside the
# window they arrived in -- two shamblers the director never placed, and a live cap of 33 against
# 32. Measured with a throwaway driver (deleted) before the guard was written, which is the only
# reason the guard is a day and not a guess.
#
# Four phases, one fixture each, and exactly one of them may place anybody.

func _daylight() -> bool:
	var lane: String = "DAYLIGHT"
	var day: int = int(SimStrangers.BEATS[0])
	var placed_in: Array[String] = []
	for probe in [["dawn", Clock.DAWN_ENDS * 0.5], ["day", 0.35], ["dusk", (Clock.DAY_ENDS + Clock.DUSK_ENDS) * 0.5], ["night", 0.95]]:
		var name: String = String((probe as Array)[0])
		var at: float = float((probe as Array)[1])
		var w: Variant = _boot(int(FAST_SEEDS[1]), SHIPPED_TILES)["world"]
		if SimWorldgen.far_buildings(w.tilemap, SimStrangers.MIN_METRES).is_empty():
			push_error("%s: the fixture district has nowhere to put a stranger, so no phase could place one and the lane judges nothing" % lane)
			return false
		w.tick = Clock.tick_on_day(day, at) - 1
		w.step()
		if Clock.phase_of(int(w.tick)) != _phase_named(name):
			push_error("%s: the %s probe stepped into phase %d, so it is not probing what it says" % [lane, name, Clock.phase_of(int(w.tick))])
			return false
		var made: int = w.components.query(["stranger"]).size()
		var spent: Array = (w.strangers as Dictionary).get("spawned", []) as Array
		if made > 0:
			placed_in.append(name)
		# The day is spent only when somebody is placed -- otherwise a beat day that fell at night
		# would be gone by morning and the feature would never fire in a real campaign at all.
		if (made > 0) != (not spent.is_empty()):
			push_error("%s: the %s probe placed %d and marked the day %s" % [lane, name, made, str(spent)])
			return false
	if placed_in.size() != 1 or placed_in[0] != "day":
		push_error("%s: beat day %d placed a stranger in %s -- it may fire in the day and nowhere else" % [lane, day, str(placed_in)])
		return false
	print("%s OK beat day %d places in the day and in none of dawn, dusk or night, and spends the day only when it places" % [lane, day])
	return true


func _phase_named(name: String) -> int:
	match name:
		"dawn":
			return Clock.Phase.Dawn
		"day":
			return Clock.Phase.Day
		"dusk":
			return Clock.Phase.Dusk
	return Clock.Phase.Night


# --- HIDES --------------------------------------------------------------------------------------

func _hides() -> bool:
	var lane: String = "HIDES"
	var built: Dictionary = _lone_stranger(lane)
	if built.is_empty():
		push_error("%s: no seed had a far building to hide anybody in, so nothing was judged" % lane)
		return false
	var w: Variant = built["world"]
	var ent: int = int(built["stranger"])
	var at_start: Vector2 = _pos(w, ent)
	# The player is parked in the colony, which is where the boot leaves them: `MIN_METRES` away
	# by construction, and the whole district between the two of them.
	for _t in WATCH_TICKS:
		w.step()
	var moved: float = _pos(w, ent).distance_to(at_start)
	if moved > 0.01:
		push_error("%s: a stranger nobody has seen moved %.2f m in %d ticks" % [lane, moved, WATCH_TICKS])
		return false
	if _state_of(w, ent) != int(SimStrangers.StrangerState.Hiding):
		push_error("%s: a stranger nobody has seen came out of hiding (state %d)" % [lane, _state_of(w, ent)])
		return false
	# The negative: the same body, the same tick budget, with the colonist walked into the room.
	# Without this, "moved 0.00 m" is also what a lane that cannot see movement at all reports.
	var seen: Vector2i = _a_tile_in_sight(w, ent, true)
	if seen.x < 0:
		print("STRANGERS SKIP %s the fixture's stranger can see nowhere a colonist could stand, so the movement counter is unproved here" % lane)
		return false
	_put(w, int(w.player), float(seen.x) + 0.5, float(seen.y) + 0.5)
	for _t2 in WATCH_TICKS:
		w.step()
		if _pos(w, ent).distance_to(at_start) > 1.0:
			break
	var after: float = _pos(w, ent).distance_to(at_start)
	if after <= 1.0:
		push_error("%s: with a colonist standing in sight the stranger still moved only %.2f m, so the stillness above proves nothing" % [lane, after])
		return false
	print("%s OK still on its tile for %d ticks with nobody near; moved %.2f m once a colonist stood in sight" % [lane, WATCH_TICKS, after])
	return true


## Boots a district, empties it, and hides one stranger in it. `{}` when no seed qualifies.
func _lone_stranger(lane: String) -> Dictionary:
	for seed_value in FAST_SEEDS:
		for size in [GATE_TILES, SHIPPED_TILES]:
			var boot: Dictionary = _boot(int(seed_value), int(size))
			var w: Variant = boot["world"]
			var ent: int = SimStrangers.place(w, Clock.day_number(int(w.tick)))
			if ent < 0:
				continue
			if not _quiet_solo(w):
				return {}
			# One step so `kernel.visibility` has cast from the stranger's own eyes before any
			# lane asks what it can see.
			w.step()
			return {"world": w, "map": boot["map"], "stranger": ent, "seed": int(seed_value), "size": int(size)}
	print("STRANGERS SKIP %s no seed at either size had a far building with floor in it" % lane)
	return {}


## An open tile a colonist could stand on that the stranger can (`want_seen`) or cannot see, or
## (-1, -1). Asked of the sight system itself, deliberately: the assertion these lanes make is
## about what the stranger *does*, and letting the fixture pick its tiles by the same rule the
## code under test reads is what makes the pair differ by sight and by nothing else.
func _a_tile_in_sight(w: Variant, ent: int, want_seen: bool, within: float = 1e9) -> Vector2i:
	var at: Vector2 = _pos(w, ent)
	var here := Vector2i(floori(at.x), floori(at.y))
	var best := Vector2i(-1, -1)
	var best_d: float = -1.0 if want_seen else 1e12
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			if dx == 0 and dy == 0:
				continue
			var tx: int = here.x + dx
			var ty: int = here.y + dy
			if tx < 1 or ty < 1 or tx >= int(w.tilemap.w) - 1 or ty >= int(w.tilemap.h) - 1:
				continue
			if w.is_blocked_tile(tx, ty):
				continue
			var x: float = float(tx) + 0.5
			var y: float = float(ty) + 0.5
			var d: float = at.distance_to(Vector2(x, y))
			if d < 2.5 or d > within:
				continue
			var visible: bool = bool(w.vision.call("line_of_sight", ent, x, y))
			if visible != want_seen:
				continue
			# The furthest one it can see, and the nearest one it cannot: the pair is then
			# "further away and visible" against "closer and blind", so distance cannot be the
			# explanation for either half.
			if want_seen and d > best_d:
				best_d = d
				best = Vector2i(tx, ty)
			elif not want_seen and d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best


# --- APPROACHES ---------------------------------------------------------------------------------

func _approaches() -> bool:
	var lane: String = "APPROACHES"
	var built: Dictionary = _lone_stranger(lane)
	if built.is_empty():
		push_error("%s: no seed had a far building to hide anybody in, so nothing was judged" % lane)
		return false
	var w: Variant = built["world"]
	var ent: int = int(built["stranger"])
	var player: int = int(w.player)
	var seen_tile: Vector2i = _a_tile_in_sight(w, ent, true)
	if seen_tile.x < 0:
		push_error("%s: the stranger can see nowhere a colonist could stand, so the positive half has no fixture" % lane)
		return false
	var seen_d: float = _pos(w, ent).distance_to(Vector2(float(seen_tile.x) + 0.5, float(seen_tile.y) + 0.5))
	# The blind tile is picked no further away than the visible one, so "it did not come" cannot be
	# explained by distance -- only by the wall.
	var blind_tile: Vector2i = _a_tile_in_sight(w, ent, false, seen_d)
	if blind_tile.x < 0:
		push_error("%s: no tile within %.1f m is out of the stranger's sight, so the negative half has no fixture" % [lane, seen_d])
		return false
	var blind_d: float = _pos(w, ent).distance_to(Vector2(float(blind_tile.x) + 0.5, float(blind_tile.y) + 0.5))

	# The negative first, on the untouched fixture: a colonist behind a wall is not noticed.
	_put(w, player, float(blind_tile.x) + 0.5, float(blind_tile.y) + 0.5)
	var at_start: Vector2 = _pos(w, ent)
	for _t in WATCH_TICKS:
		w.step()
	if _state_of(w, ent) != int(SimStrangers.StrangerState.Hiding):
		push_error("%s: a colonist %.1f m away **behind a wall** brought the stranger out of hiding" % [lane, blind_d])
		return false
	if _pos(w, ent).distance_to(at_start) > 0.01:
		push_error("%s: the stranger walked %.2f m towards a colonist it cannot see" % [lane, _pos(w, ent).distance_to(at_start)])
		return false

	# The positive: the same stranger, the same world, the colonist moved into view.
	_put(w, player, float(seen_tile.x) + 0.5, float(seen_tile.y) + 0.5)
	var arrived: bool = false
	var took: int = 0
	for _t2 in APPROACH_TICKS:
		w.step()
		took += 1
		if _pos(w, ent).distance_to(_pos(w, player)) <= SimStrangers.APPROACH_METRES:
			arrived = true
			break
	if not arrived:
		push_error("%s: a colonist %.1f m away in plain sight was never closed on -- %.1f m after %d ticks" % [
			lane, seen_d, _pos(w, ent).distance_to(_pos(w, player)), APPROACH_TICKS,
		])
		return false
	if _state_of(w, ent) != int(SimStrangers.StrangerState.Approaching):
		push_error("%s: the stranger arrived but is in state %d" % [lane, _state_of(w, ent)])
		return false
	# The path is an Array of `{x, y}` records and nothing else -- the shape a save can carry.
	var s: Dictionary = w.components.get_component(ent, "stranger") as Dictionary
	var path: Variant = s.get("path")
	if not (path is Array):
		push_error("%s: the stranger's path is a %s and not an Array" % [lane, type_string(typeof(path))])
		return false
	for row in path as Array:
		if not (row is Dictionary) or not (row as Dictionary).has("x") or not (row as Dictionary).has("y"):
			push_error("%s: a path step is %s, which is not an {x, y} record" % [lane, str(row)])
			return false
	# And it stands there rather than walking through them.
	for _t3 in 200:
		w.step()
	var held: float = _pos(w, ent).distance_to(_pos(w, player))
	if held > SimStrangers.APPROACH_METRES + 0.5:
		push_error("%s: the stranger arrived and then wandered back off to %.2f m" % [lane, held])
		return false
	print("%s OK closed %.1f m in %d ticks to a colonist in sight and stood at %.2f m; a colonist %.1f m away behind a wall was never noticed" % [
		lane, seen_d, took, held, blind_d,
	])
	return true


# --- RECRUIT ------------------------------------------------------------------------------------

func _recruit() -> bool:
	var lane: String = "RECRUIT"
	var built: Dictionary = _lone_stranger(lane)
	if built.is_empty():
		push_error("%s: no seed had a far building to hide anybody in, so nothing was judged" % lane)
		return false
	var w: Variant = built["world"]
	var ent: int = int(built["stranger"])
	var player: int = int(w.player)
	var at: Vector2 = _pos(w, ent)
	# The E ladder tries the ground and the cupboards before it reaches the people, on purpose, so
	# the fixture clears both: the kit this stranger dropped at their own feet, and the district's
	# cupboards -- one of which was standing in the very first house a stranger was placed in, and
	# ate the press. Otherwise this lane measures which rung came first rather than whether the
	# recruit rung fires at all.
	for item in w.components.query(["item", "position"]):
		w.despawn(int(item))
	for box in w.components.query(["searchable"]):
		w.despawn(int(box))
	# The negative first: out of reach, the same press, nobody accepted.
	_put(w, player, at.x + 5.0, at.y)
	var before: int = _colonists(w)
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(ent, "recruit"):
		push_error("%s: E accepted a stranger five metres away" % lane)
		return false
	if _colonists(w) != before:
		push_error("%s: the colony grew from %d to %d without anybody being accepted" % [lane, before, _colonists(w)])
		return false
	# The positive: standing at them.
	var joined: Array = []
	w.events.subscribe({"id": "strangers.gate.joined", "type": "survivor.joined", "handler": func(ev: Dictionary) -> void:
		# An Array and never a captured int: a GDScript lambda captures primitives by value and an
		# accumulator written in a handler reads back unchanged (CLAUDE.md's trap list).
		joined.append(String(ev.get("id", "")))
	})
	# What that press *did* land on, which is worth saying out loud: with nobody in reach the
	# ladder falls all the way through to the building rungs and starts a channel on the player,
	# and `fortify.intake` skips a body mid-channel entirely -- so the second press below would
	# have been swallowed before it reached any rung at all. Cleared here rather than worked
	# around, and asserted, because a fixture that silently made the positive half untestable is
	# exactly the shape of a gate that cannot fail.
	var started: bool = w.components.has_component(player, "construct")
	if started:
		w.components.remove(player, "construct")
	_put(w, player, at.x + 0.9, at.y)
	# Asked before the press, so a red lane blames the rung it means to: `waiting_in_reach` is the
	# call `SimFortify`'s ladder makes, and if it cannot see the stranger the press was never the
	# thing being measured.
	if SimRecruits.waiting_in_reach(w, player) != ent:
		push_error("%s: the stranger is not in reach of the E rung at 0.9 m, so the press below measures nothing" % lane)
		return false
	w.commands.push({"type": "use.context"})
	w.step()
	if w.components.has_component(ent, "recruit"):
		push_error("%s: E at arm's length did not accept the stranger" % lane)
		return false
	if not joined.has("recruit"):
		push_error("%s: nothing published survivor.joined for the recruit -- %s" % [lane, str(joined)])
		return false
	if _colonists(w) != before + 1:
		push_error("%s: the colony went from %d to %d on an acceptance" % [lane, before, _colonists(w)])
		return false
	for needed in ["needs", "jobPriorities", "identity", "body", "observer"]:
		if not w.components.has_component(ent, String(needed)):
			push_error("%s: the accepted body has no `%s`, so it is not a colonist" % [lane, String(needed)])
			return false
	# One more tick, and the module lets go of them: a colonist steered by `strangers.tick` and by
	# `jobs.ai` at once is two systems writing one velocity.
	w.step()
	if w.components.has_component(ent, "stranger"):
		push_error("%s: the accepted body still carries a `stranger` component, so this module is still steering a colonist" % lane)
		return false
	if SimStrangers.live_count(w) != 0:
		push_error("%s: the accepted body still fills a slot in LIVE_CAP" % lane)
		return false
	print("%s OK the existing E rung took them in -- colony %d to %d, tag gone, `stranger` released; the same press five metres off accepted nobody (it fell through to a building channel: %s)" % [
		lane, before, _colonists(w), str(started),
	])
	return true


# --- LEDGER -------------------------------------------------------------------------------------

func _ledger() -> bool:
	var lane: String = "LEDGER"
	var built: Dictionary = {}
	for seed_value in FAST_SEEDS:
		for size in [GATE_TILES, SHIPPED_TILES]:
			var boot: Dictionary = _boot(int(seed_value), int(size))
			var w0: Variant = boot["world"]
			var before0: int = _colonists(w0)
			var ent0: int = SimStrangers.place(w0, Clock.day_number(int(w0.tick)))
			if ent0 < 0:
				continue
			built = {"world": w0, "stranger": ent0, "before": before0, "seed": int(seed_value), "size": int(size)}
			break
		if not built.is_empty():
			break
	if built.is_empty():
		push_error("%s: no seed had a far building to hide anybody in, so nothing was judged" % lane)
		return false
	var w: Variant = built["world"]
	var ent: int = int(built["stranger"])
	var before: int = int(built["before"])
	if before < 1:
		push_error("%s: the district booted with %d colonists, so the counter has nothing to be unmoved about" % [lane, before])
		return false
	if _colonists(w) != before:
		push_error("%s: placing a stranger took the colony from %d to %d" % [lane, before, _colonists(w)])
		return false
	for _t in 200:
		w.step()
	if _colonists(w) != before:
		push_error("%s: two hundred ticks with a stranger hiding took the colony from %d to %d" % [lane, before, _colonists(w)])
		return false
	# The counter's true positive: the same counter, the same world, one acceptance.
	if not SimRecruits.accept(w, ent):
		push_error("%s: the stranger could not be accepted, so the counter is never moved here" % lane)
		return false
	if _colonists(w) != before + 1:
		push_error("%s: an accepted stranger did not raise the count (%d, want %d)" % [lane, _colonists(w), before + 1])
		return false
	# And the textual half. This gate reproduces `_survivors_alive`; that proves nothing about the
	# harness unless the harness still counts the same way. The line is isolated first and the
	# membership asked inside it, so no comment can satisfy the needle (CLAUDE.md, the comfort
	# gate's lesson) -- and the isolator is proved by requiring the function to be found at all.
	var body: String = _function_body(BALANCE_SOURCE, "func _survivors_alive")
	if body == "":
		push_error("%s: could not find `_survivors_alive` in %s -- follow the call rather than dropping the needle" % [lane, BALANCE_SOURCE])
		return false
	if not body.contains("has_component(int(ent), \"recruit\")"):
		push_error("%s: %s's `_survivors_alive` no longer excludes `recruit`, so a hidden stranger is on the colony's books" % [lane, BALANCE_SOURCE])
		return false
	print("%s OK %d colonists with a stranger hiding on seed %d at %d, %d once accepted; the balance harness's own counter still excludes `recruit`" % [
		lane, before, int(built["seed"]), int(built["size"]), _colonists(w),
	])
	return true


## The text of one function, from its `func` line to the next top-level `func`. Returns "" when
## the function is not there at all, which every caller treats as a failure rather than a pass.
func _function_body(path: String, header: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var lines: PackedStringArray = text.split("\n")
	var out: Array[String] = []
	var inside: bool = false
	for line in lines:
		var l: String = String(line)
		if l.begins_with(header):
			inside = true
			continue
		if inside and (l.begins_with("func ") or l.begins_with("static func ")):
			break
		if inside:
			out.append(l)
	if not inside:
		return ""
	return "\n".join(out)


# --- GATE BEAT ----------------------------------------------------------------------------------
#
# The two regressions this slice could cause, and both were live in the code before it: the gate
# beat refuses to fire while **any** recruit component exists, and the dawn leave despawns
# **every** waiting recruit. Either one, unnarrowed, makes a stranger hiding in a house on day 5
# into a bug on day 8 or a body that vanishes at the first dawn. Both halves of both are here.

func _gate_recruits(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for e in w.components.query(["recruit"]):
		var r: Variant = w.components.get_component(int(e), "recruit")
		if r is Dictionary and not bool((r as Dictionary).get("stranger", false)):
			out.append(int(e))
	return out


## A stranger standing wherever the caller says, without asking the map for a far building: the
## GATE BEAT and LEAVES lanes are about recruits.gd and must not be skipped by a district's
## geometry.
func _stranger_anywhere(w: Variant, x: float, y: float, day: int) -> int:
	var rolled: Dictionary = SimPeople.roll(w.rng.stream(SimStrangers.STREAM), w.rng.stream(SimStrangers.LOOK_STREAM), SimPeople.pool(w, SimPeople.SURVIVORS_POOL_ID))
	return SimStrangers.mark(w, SimRecruits.spawn_generated(w, rolled, x, y), day)


func _gate_beat() -> bool:
	var lane: String = "GATE BEAT"
	var day: int = int(SimRecruits.BEATS[0])
	# Half one, positive: a hidden stranger does not cancel the day-8 beat.
	var a: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var hidden: int = _stranger_anywhere(a, 20.5, 20.5, 5)
	a.tick = Clock.tick_on_day(day, Clock.DAWN_ENDS * 0.5)
	a.step()
	if _gate_recruits(a).is_empty():
		push_error("%s: a stranger hiding in a building cancelled the day-%d gate beat" % [lane, day])
		return false
	if not a.components.has_component(hidden, "recruit"):
		push_error("%s: the gate beat took the stranger's tag off" % lane)
		return false
	# Half one, negative: a recruit **at the gate** still blocks it, so the narrowing did not
	# simply delete the rule.
	var b: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var rolled: Dictionary = SimRecruits.roll(b, b.rng.stream(SimRecruits.STREAM))
	var at_gate: int = SimRecruits.spawn_generated(b, rolled, 20.5, 20.5)
	b.components.set_component(at_gate, "recruit", {"waiting": true, "beatDay": 1})
	b.tick = Clock.tick_on_day(day, Clock.DAWN_ENDS * 0.5)
	b.step()
	if _gate_recruits(b).size() != 1:
		push_error("%s: a gate recruit already waiting no longer blocks the day-%d beat (%d waiting)" % [lane, day, _gate_recruits(b).size()])
		return false
	# Half two: dawn. One world, one stranger, one gate recruit, one dawn -- so the two outcomes
	# cannot be explained by anything but the flag.
	var c: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var stays: int = _stranger_anywhere(c, 20.5, 20.5, 5)
	var rolled2: Dictionary = SimRecruits.roll(c, c.rng.stream(SimRecruits.STREAM))
	var goes: int = SimRecruits.spawn_generated(c, rolled2, 21.5, 20.5)
	c.components.set_component(goes, "recruit", {"waiting": true, "beatDay": 5})
	c.tick = Clock.tick_on_day(6, 0.0) - 1
	if Clock.phase_of(int(c.tick) + 1) != Clock.Phase.Dawn or Clock.phase_of(int(c.tick)) == Clock.Phase.Dawn:
		push_error("%s: the fixture's next step is not the tick the district enters Dawn, so the dawn leave never runs" % lane)
		return false
	c.step()
	if c.components.has_component(goes, "recruit"):
		push_error("%s: the dawn leave no longer takes the recruit waiting at the gate" % lane)
		return false
	if not c.components.has_component(stays, "recruit"):
		push_error("%s: the dawn leave despawned the stranger hiding in a building" % lane)
		return false
	if _state_of(c, stays) < 0:
		push_error("%s: the stranger survived the dawn without its `stranger` component" % lane)
		return false
	print("%s OK day %d fired over a hidden stranger and was still blocked by a gate recruit; one dawn took the gate recruit and left the stranger" % [lane, day])
	return true


# --- LEAVES -------------------------------------------------------------------------------------

func _leaves() -> bool:
	var lane: String = "LEAVES"
	var w: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var day: int = Clock.day_number(int(w.tick))
	# The negative first: a stranger whose clock has not run out stays put.
	var fresh: int = _stranger_anywhere(w, 20.5, 20.5, day)
	# And the positive beside it, in the same world and the same ticks: one placed
	# `STRANGER_DAYS` ago.
	var stale: int = _stranger_anywhere(w, 22.5, 20.5, day - SimStrangers.STRANGER_DAYS)
	w.step()
	if w.components.has_component(fresh, "leaving"):
		push_error("%s: a stranger placed today has already given up" % lane)
		return false
	if not w.components.has_component(stale, "leaving"):
		push_error("%s: a stranger placed %d days ago has not given up" % [lane, SimStrangers.STRANGER_DAYS])
		return false
	var lv: Variant = w.components.get_component(stale, "leaving")
	if String((lv as Dictionary).get("reason", "")) != "stranger":
		push_error("%s: the departure is booked as \"%s\"" % [lane, String((lv as Dictionary).get("reason", ""))])
		return false
	var lines_before: int = (w.chronicle as Array).size()
	var went: bool = false
	for _t in SimRecruits.LEAVE_TICKS + 40:
		w.step()
		if not w.components.has_component(stale, "position"):
			went = true
			break
	if not went:
		push_error("%s: the stranger who gave up is still in the district after %d ticks" % [lane, SimRecruits.LEAVE_TICKS + 40])
		return false
	if w.components.has_component(fresh, "leaving"):
		push_error("%s: the stranger placed today gave up during the same window" % lane)
		return false
	# The colony is told nothing about somebody it may never have met. Both halves: no line for the
	# stranger, and a line for the gate recruit turned away at dawn -- so "no line" is a decision
	# the chronicle made rather than a chronicle that writes nothing.
	for rec in (w.chronicle as Array).slice(lines_before):
		if String((rec as Dictionary).get("kind", "")) == "left":
			push_error("%s: the chronicle wrote \"%s\" about a stranger who gave up" % [lane, str(rec)])
			return false
	var c: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var rolled: Dictionary = SimRecruits.roll(c, c.rng.stream(SimRecruits.STREAM))
	var gate_recruit: int = SimRecruits.spawn_generated(c, rolled, 20.5, 20.5)
	c.components.set_component(gate_recruit, "recruit", {"waiting": true, "beatDay": 5})
	var before_lines: int = (c.chronicle as Array).size()
	c.tick = Clock.tick_on_day(6, 0.0) - 1
	c.step()
	var wrote: bool = false
	for rec2 in (c.chronicle as Array).slice(before_lines):
		if String((rec2 as Dictionary).get("kind", "")) == "left":
			wrote = true
	if not wrote:
		push_error("%s: the chronicle wrote nothing when the recruit at the gate gave up either, so its silence over a stranger says nothing" % lane)
		return false
	print("%s OK gone after %d days with no line written; a stranger placed today stayed, and the gate recruit turned away at dawn still gets its line" % [
		lane, SimStrangers.STRANGER_DAYS,
	])
	return true


# --- SAVE ---------------------------------------------------------------------------------------

func _save() -> bool:
	var lane: String = "SAVE"
	var w: Variant = _boot(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	var day: int = Clock.day_number(int(w.tick))
	var hiding: int = _stranger_anywhere(w, 20.5, 20.5, day)
	var walking: int = _stranger_anywhere(w, 22.5, 20.5, day)
	# A second body in another state, so "it came back 0" cannot pass for a restore that carries
	# nothing at all.
	var moving: Dictionary = w.components.get_component(walking, "stranger") as Dictionary
	moving["state"] = int(SimStrangers.StrangerState.Approaching)
	moving["goalX"] = 30
	moving["goalY"] = 31
	moving["path"] = [{"x": 23, "y": 20}, {"x": 24, "y": 20}]
	moving["pathGen"] = int(w.mapGeneration)
	(w.strangers as Dictionary)["spawned"] = [int(SimStrangers.BEATS[0])]
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary)["snapshot"] is Dictionary):
		push_error("%s: the save did not come back as an object" % lane)
		return false
	var restored: Variant = SimBoot.bare(int(FAST_SEEDS[0]), GATE_TILES)["world"]
	restored.restore((parsed as Dictionary)["snapshot"] as Dictionary)
	if ((restored.strangers as Dictionary).get("spawned", []) as Array) != [int(SimStrangers.BEATS[0])]:
		push_error("%s: the stranger beats came back as %s" % [lane, str((restored.strangers as Dictionary).get("spawned", []))])
		return false
	var back_hiding: Variant = restored.components.get_component(hiding, "stranger")
	var back_walking: Variant = restored.components.get_component(walking, "stranger")
	if not (back_hiding is Dictionary) or not (back_walking is Dictionary):
		push_error("%s: a stranger came back with no `stranger` component" % lane)
		return false
	if int((back_hiding as Dictionary)["state"]) != int(SimStrangers.StrangerState.Hiding):
		push_error("%s: the hiding stranger came back in state %d" % [lane, int((back_hiding as Dictionary)["state"])])
		return false
	if int((back_walking as Dictionary)["state"]) != int(SimStrangers.StrangerState.Approaching):
		push_error("%s: the walking stranger came back in state %d, so the restore is not carrying state at all" % [lane, int((back_walking as Dictionary)["state"])])
		return false
	var path: Variant = (back_walking as Dictionary).get("path")
	if not (path is Array) or (path as Array).size() != 2:
		push_error("%s: the path came back as %s" % [lane, str(path)])
		return false
	for row in path as Array:
		# The whole reason the path is an Array of records: a Dictionary keyed by anything comes
		# back from JSON with String keys and reads empty, silently (CLAUDE.md's trap list).
		if not (row is Dictionary) or not (row as Dictionary).has("x") or not (row as Dictionary).has("y"):
			push_error("%s: a path step came back as %s" % [lane, str(row)])
			return false
	if int((path as Array)[1]["x"]) != 24 or int((path as Array)[1]["y"]) != 20:
		push_error("%s: the second path step came back as %s" % [lane, str((path as Array)[1])])
		return false
	var tag: Variant = restored.components.get_component(hiding, "recruit")
	if not (tag is Dictionary) or not bool((tag as Dictionary).get("stranger", false)):
		push_error("%s: the recruit tag came back without its `stranger` flag, so the restored world would despawn them at dawn" % lane)
		return false
	print("%s OK both strangers round-tripped in their own states, the path came back as {x, y} records and the beats as %s" % [
		lane, str((restored.strangers as Dictionary).get("spawned", [])),
	])
	return true

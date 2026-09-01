extends SceneTree
# Day/night and the light look -- docs/30's clause on the overlay, ported from the frozen
# renderer: "the screen may draw a lit region only where the survivor can see it", and the night
# wash derives from `sightMetres` rather than raw ambient.
#
# Two claims, and both of them are the sort that pass by accident. A wash computed from raw
# ambient looks completely correct at midnight -- it is dark, and it is dark -- and only stops
# looking correct when a survivor walks into a campfire's pool and the screen does not lift; so
# SIGHT-DERIVED carries the raw-ambient formula spelled out by hand as a control, and goes red the
# moment somebody quietly reverts the wash to it. A pool drawn from the light index alone looks
# completely correct in an open street and is a leak the first time a wall stands between the lamp
# and the player; so LIT AND SEEN puts one there, proves the far-side tile is genuinely lit, and
# requires it to appear in no pool -- with the wall taken away in a *fresh* world as the true
# negative, because a lane where the tile never appears at all would pass against a helper that
# returns nothing.
#
# Every fixture boots its own world and reads that world's own light and vision indices. The
# kernel's indices are per-world (SimBoot.attach_kernel), and the static-var lesson recorded in
# docs/30 and CLAUDE.md is exactly this shape: a gate that boots two worlds and reads one.
#
# Emitters are placed and then the world is **stepped once** before anything is asserted: the
# light index refreshes in the `movement` phase (order 75, vision at 100), and events drain at the
# end of `world.step()`.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const Clock = preload("res://sim/time/clock.gd")
const LightLook = preload("res://presentation/light_look.gd")
const Palette = preload("res://presentation/palette.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const MAP_TILES: int = 24
const WALL_X: int = 12
const PLAYER_X: float = 8.5
const PLAYER_Y: float = 12.5
# Deep night: past DUSK_ENDS (0.75), so ambient sits flat at NIGHT_AMBIENT.
const NIGHT_FRACTION: float = 0.9
const CAMPFIRE_M: float = 20.0
const CANDLE_M: float = 3.0
# The wash constant main.gd owns; passed in rather than imported, so the gate is asserting the
# arithmetic and not re-reading the same literal from the file under test.
const NIGHT_WASH: float = 0.8
const EPS: float = 0.000000001


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_wash_comes_from_sight_not_from_raw_ambient() and ok
	ok = _with_nothing_to_ask_it_falls_back_to_ambient_exactly() and ok
	ok = _a_pool_behind_a_wall_is_lit_and_never_drawn() and ok
	ok = _the_split_lands_at_three_metres_of_remaining_reach() and ok
	ok = _full_daylight_washes_nothing() and ok
	ok = _dead_socket_main_gd_draws_what_light_look_returns() and ok
	if ok:
		print("LIGHT_LOOK_OK the wash derives from sight (and differs from raw ambient on the same lit scene), falls back to ambient exactly with no observer or no emitter, pools are lit-and-seen with a walled far side drawn nowhere, the near/far split lands at %.0f m, full daylight washes nothing, and main.gd's _draw calls both helpers" % LightLook.POOL_SPLIT_METRES)
		quit(0)
	else:
		push_error("LIGHT_LOOK_FAIL")
		quit(1)


# --- fixture ---------------------------------------------------------------------------------

# One world, its own kernel, its own light and vision indices. `walled` puts a solid column at
# WALL_X, which is what lets the same geometry serve "the lamp is behind a wall" and, in a second
# world built without it, "and here it is when it is not".
func _world(walled: bool, day_fraction: float) -> Variant:
	var f: Dictionary = {
		"seed": 4141,
		"tick_hz": 20,
		"map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []},
		"player": {"id": 0, "x": PLAYER_X, "y": PLAYER_Y, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(day_fraction)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	if walled:
		for y in range(0, MAP_TILES):
			map.tiles[y * MAP_TILES + WALL_X] = SimTileMap.Tile.Wall
	SimBoot.attach_kernel(w, map)
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	return w


func _emitter(w: Variant, x: float, y: float, magnitude: float) -> int:
	var e: int = int(w.entities.spawn())
	w.components.set_component(e, "position", {"x": x, "y": y})
	SimLightMod.make_light_source(w, e, magnitude)
	return e


# The whole map, so a lane's own bounds never quietly decide what it found.
func _all_bounds() -> Dictionary:
	return {"minX": 0.0, "minY": 0.0, "maxX": float(MAP_TILES), "maxY": float(MAP_TILES)}


# The raw-ambient fraction, written out here rather than read off Clock through light_look.gd, so
# the control cannot grade its own homework -- check_camera.gd's CLAMP IDENTITY lane, same reason.
func _raw_ambient(w: Variant) -> float:
	return Clock.ambient_light(Clock.time_of_day(int(w.tick)))


func _has(tiles: Array, tx: int, ty: int) -> bool:
	return (tiles as Array).has(Vector2i(tx, ty))


# --- lanes -----------------------------------------------------------------------------------

# SIGHT-DERIVED. A campfire a metre from the survivor at midnight. The fraction the wash is built
# from must be strictly above what raw ambient would have given on the *same scene* -- that
# difference is the whole clause, and it is what goes red if the wash is ever quietly reverted to
# `Clock.ambient_light`. `ambient_of` is pinned to the hand-written formula alongside, because it
# is the number main.gd's daylight early-out reads and a drifting one there would be silent.
func _the_wash_comes_from_sight_not_from_raw_ambient() -> bool:
	var w: Variant = _world(false, NIGHT_FRACTION)
	_emitter(w, PLAYER_X + 1.0, PLAYER_Y, CAMPFIRE_M)
	w.step()

	var ambient: float = _raw_ambient(w)
	if absf(LightLook.ambient_of(w) - ambient) > EPS:
		push_error("ambient_of() = %f but Clock.ambient_light(time_of_day(tick)) = %f -- the helper main.gd's daylight early-out reads is not the ambient formula" % [LightLook.ambient_of(w), ambient])
		return false
	if ambient >= 1.0:
		push_error("the night fixture is at ambient %f -- this lane has no darkness to lift and nothing to judge" % ambient)
		return false

	var fraction: float = LightLook.local_light_fraction(w, int(w.player))
	if fraction <= ambient + EPS:
		push_error("standing a metre from a %.0f m campfire at ambient %f, local_light_fraction returned %f -- no better than raw ambient, which is the quiet revert this lane exists to catch" % [CAMPFIRE_M, ambient, fraction])
		return false
	# The lit range really is what lifted it: 20 m of campfire, one metre away.
	var expect: float = (CAMPFIRE_M - 1.0) / float(SimVisibility.daylight_eyes()["range_metres"])
	if absf(fraction - expect) > 0.0001:
		push_error("local_light_fraction returned %f; sight_metres/range for this scene is %f -- the fraction is not the survivor's own sight over their own daylight range" % [fraction, expect])
		return false

	var lifted: float = LightLook.wash_alpha(w, int(w.player), NIGHT_WASH)
	var unlifted: float = (1.0 - ambient) * NIGHT_WASH
	if lifted >= unlifted - EPS:
		push_error("the wash alpha in the campfire's pool is %f, no lighter than the %f raw ambient would paint -- standing in light must lift the dark" % [lifted, unlifted])
		return false
	print("SIGHT-DERIVED OK a %.0f m campfire one metre away lifts the fraction from ambient %.4f to %.4f, and the wash from alpha %.3f to %.3f" % [CAMPFIRE_M, ambient, fraction, unlifted, lifted])
	return true


# AMBIENT FALLBACK, the true negative for the lane above. Two ways of having nothing to ask, both
# on scenes where the sight-derived answer would otherwise be visibly different:
#
#   - the same night scene with the emitter's magnitude at 0 (the light index refuses it, so
#     there is no pool to stand in) -- the fraction must be raw ambient *exactly*;
#   - the *lit* scene, asked about a body with no `observer` and about no body at all -- both must
#     be raw ambient exactly, while the player in that same world reads far above it.
func _with_nothing_to_ask_it_falls_back_to_ambient_exactly() -> bool:
	var dark: Variant = _world(false, NIGHT_FRACTION)
	_emitter(dark, PLAYER_X + 1.0, PLAYER_Y, 0.0)
	dark.step()
	var dark_ambient: float = _raw_ambient(dark)
	var dark_fraction: float = LightLook.local_light_fraction(dark, int(dark.player))
	if absf(dark_fraction - dark_ambient) > EPS:
		push_error("with a magnitude 0 emitter the fraction is %f, not the raw ambient %f it must fall back to" % [dark_fraction, dark_ambient])
		return false

	var lit: Variant = _world(false, NIGHT_FRACTION)
	_emitter(lit, PLAYER_X + 1.0, PLAYER_Y, CAMPFIRE_M)
	lit.step()
	var lit_ambient: float = _raw_ambient(lit)
	var seeing: float = LightLook.local_light_fraction(lit, int(lit.player))
	if seeing <= lit_ambient + EPS:
		push_error("the lit control world reads %f, no better than its ambient %f -- this lane cannot tell a fallback from a correct answer" % [seeing, lit_ambient])
		return false
	var eyeless: int = int(lit.entities.spawn())
	lit.components.set_component(eyeless, "position", {"x": PLAYER_X, "y": PLAYER_Y})
	var eyeless_fraction: float = LightLook.local_light_fraction(lit, eyeless)
	if absf(eyeless_fraction - lit_ambient) > EPS:
		push_error("a body with no observer component standing in the campfire's pool read %f, not the ambient %f -- the no-eyes fallback is answering with somebody else's sight" % [eyeless_fraction, lit_ambient])
		return false
	var nobody: float = LightLook.local_light_fraction(lit, -1)
	if absf(nobody - lit_ambient) > EPS:
		push_error("with no observer at all the fraction is %f, not the ambient %f the parity boot needs" % [nobody, lit_ambient])
		return false
	print("AMBIENT FALLBACK OK magnitude 0 reads ambient %.4f exactly; in a world where the player reads %.4f, a body with no eyes and no body at all both read %.4f" % [dark_ambient, seeing, eyeless_fraction])
	return true


# LIT AND SEEN, the no-leak lane. A campfire on the far side of a solid wall. Its own tile is
# genuinely lit -- asserted against the light index, so the lane is about the *drawing* rule and
# not about a light that failed to reach -- and it must appear in neither pool, because the player
# has no sightline to it. Nothing on the far side of the wall may appear at all.
#
# The true negative is a **fresh** world with no wall: same tick, same emitter, same tile, and now
# it must be there. Without it, a `lit_pool_tiles` that returned an empty Dictionary forever would
# pass the first half perfectly.
func _a_pool_behind_a_wall_is_lit_and_never_drawn() -> bool:
	var far_tx: int = 16
	var far_ty: int = 12
	var walled: Variant = _world(true, NIGHT_FRACTION)
	_emitter(walled, float(far_tx) + 0.5, float(far_ty) + 0.5, CAMPFIRE_M)
	walled.step()

	var lit_there: float = float(walled.light.lit_metres(float(far_tx) + 0.5, float(far_ty) + 0.5))
	if lit_there <= 0.0:
		push_error("the far-side tile (%d, %d) is not lit at all (%f m of reach) -- this lane has no leak to refuse" % [far_tx, far_ty, lit_there])
		return false
	var seen: Variant = walled.vision.tiles_for(int(walled.player))
	if seen != null and bool((seen as Object).call("has_tile", far_tx, far_ty)):
		push_error("the player can see through the wall to (%d, %d) -- the fixture is not testing what it claims" % [far_tx, far_ty])
		return false
	var blocked: Dictionary = LightLook.lit_pool_tiles(walled, int(walled.player), _all_bounds())
	if _has(blocked["near"] as Array, far_tx, far_ty) or _has(blocked["far"] as Array, far_tx, far_ty):
		push_error("a tile lit by %f m of campfire on the far side of a wall was returned for drawing -- lit is a fact about the world, lit and seen is a fact about the survivor" % lit_there)
		return false
	for pool in ["near", "far"]:
		for t in blocked[pool] as Array:
			if (t as Vector2i).x > WALL_X:
				push_error("tile %s is past the wall at x=%d and was still returned in the %s pool" % [str(t), WALL_X, pool])
				return false

	var open: Variant = _world(false, NIGHT_FRACTION)
	_emitter(open, float(far_tx) + 0.5, float(far_ty) + 0.5, CAMPFIRE_M)
	open.step()
	var drawn: Dictionary = LightLook.lit_pool_tiles(open, int(open.player), _all_bounds())
	if not _has(drawn["near"] as Array, far_tx, far_ty):
		push_error("with the wall taken away the same lit tile (%d, %d) is still in no near pool -- the refusal above may be a helper that returns nothing" % [far_tx, far_ty])
		return false

	var open_seen: Variant = open.vision.tiles_for(int(open.player))
	if open_seen == null:
		push_error("the open world's player has no view at all -- the every-tile-is-seen assertion had nothing to judge")
		return false
	var count: int = (drawn["near"] as Array).size() + (drawn["far"] as Array).size()
	if count == 0:
		push_error("the open world returned no pool tiles -- the every-tile-is-seen assertion had nothing to judge")
		return false
	for pool in ["near", "far"]:
		for t in drawn[pool] as Array:
			var tile: Vector2i = t as Vector2i
			if not bool((open_seen as Object).call("has_tile", tile.x, tile.y)):
				push_error("tile %s was returned in the %s pool but is not in the player's seen set" % [str(tile), pool])
				return false
	print("LIT AND SEEN OK (%d, %d) carries %.0f m of reach behind the wall and is drawn nowhere (no tile past x=%d is), and the same tile is in the near pool once the wall is gone; all %d returned tiles are in the seen set" % [far_tx, far_ty, lit_there, WALL_X, count])
	return true


# SPLIT. Remaining reach at or above POOL_SPLIT_METRES is the near half, below it the far half,
# and out of the emitter's cast entirely is neither. Daylight, so the observer's own range is not
# the thing under test -- the survivor sees the whole fixture map and the only question left is
# which pool each tile lands in. Each tile carries the negative of the other two.
func _the_split_lands_at_three_metres_of_remaining_reach() -> bool:
	var w: Variant = _world(false, Clock.DAY_BEGINS)
	var ex: int = 12
	var ey: int = 12
	_emitter(w, float(ex) + 0.5, float(ey) + 0.5, CANDLE_M)
	w.step()

	var at_source: float = float(w.light.lit_metres(float(ex) + 0.5, float(ey) + 0.5))
	var two_away: float = float(w.light.lit_metres(float(ex + 2) + 0.5, float(ey) + 0.5))
	var out_of_reach: float = float(w.light.lit_metres(float(ex + 4) + 0.5, float(ey) + 0.5))
	if at_source < LightLook.POOL_SPLIT_METRES or two_away <= 0.0 or two_away >= LightLook.POOL_SPLIT_METRES or out_of_reach > 0.0:
		push_error("the %.0f m candle fixture does not straddle the %.0f m split (reach %f at the source, %f two tiles out, %f four tiles out) -- the split has nothing to judge" % [CANDLE_M, LightLook.POOL_SPLIT_METRES, at_source, two_away, out_of_reach])
		return false

	var pools: Dictionary = LightLook.lit_pool_tiles(w, int(w.player), _all_bounds())
	var near: Array = pools["near"] as Array
	var far: Array = pools["far"] as Array
	if not _has(near, ex, ey) or _has(far, ex, ey):
		push_error("the emitter's own tile carries %f m of remaining reach and did not land in near alone" % at_source)
		return false
	if not _has(far, ex + 2, ey) or _has(near, ex + 2, ey):
		push_error("a tile with %f m of remaining reach (below the %.0f m split) did not land in far alone" % [two_away, LightLook.POOL_SPLIT_METRES])
		return false
	if _has(near, ex + 4, ey) or _has(far, ex + 4, ey):
		push_error("a tile outside the emitter's cast entirely was returned for drawing")
		return false
	print("SPLIT OK %.0f m of reach -> near, %.0f m -> far, no reach -> neither, at the %.0f m split" % [at_source, two_away, LightLook.POOL_SPLIT_METRES])
	return true


# DAYLIGHT. At noon the fraction is exactly 1 -- clamped, because sight_metres already caps at the
# observer's own range and a candle may not give better than daylight -- so the wash alpha is 0
# and the early-out that skips the fill is preserved. The night scene above is the true negative:
# there the same call must produce a positive alpha, or "washes nothing" is a claim about a
# function that never washes anything.
func _full_daylight_washes_nothing() -> bool:
	var day: Variant = _world(false, Clock.DAY_BEGINS)
	_emitter(day, PLAYER_X + 1.0, PLAYER_Y, CAMPFIRE_M)
	day.step()
	var fraction: float = LightLook.local_light_fraction(day, int(day.player))
	if absf(fraction - 1.0) > EPS:
		push_error("in full daylight beside a campfire the fraction is %f, not 1.0 -- either the day is not full or the clamp is gone" % fraction)
		return false
	var alpha: float = LightLook.wash_alpha(day, int(day.player), NIGHT_WASH)
	if alpha != 0.0:
		push_error("full daylight paints a wash of alpha %f; the >= 1.0 early-out is gone" % alpha)
		return false
	if LightLook.ambient_of(day) < 1.0:
		push_error("ambient_of() reads %f at noon, so main.gd would still paint pools in full daylight" % LightLook.ambient_of(day))
		return false

	var night: Variant = _world(false, NIGHT_FRACTION)
	night.step()
	if LightLook.wash_alpha(night, int(night.player), NIGHT_WASH) <= 0.0:
		push_error("the night scene also washes nothing -- the daylight assertion above cannot go red")
		return false
	print("DAYLIGHT OK fraction clamps to 1.0 beside a campfire at noon, alpha is 0, and the same call at midnight paints %.3f" % LightLook.wash_alpha(night, int(night.player), NIGHT_WASH))
	return true


# DEAD SOCKET. Everything above is true of two helpers nothing draws with -- which is precisely
# the state this milestone has found nine times. The frame loop cannot be exercised headless
# (`_draw` needs a running CanvasItem), so what the functions contain is read, the way
# check_topdown.gd, check_respond.gd and check_camera.gd all read main.gd.
#
# It also pins the draw *order*: pools go over the floor and under the bodies. A pool drawn after
# the entities would tint the survivors, which is the entity pass's business and not this one's.
func _dead_socket_main_gd_draws_what_light_look_returns() -> bool:
	var draw_fn: String = _function_body(MAIN_GD, "_draw")
	if draw_fn.is_empty():
		push_error("could not read _draw out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	var at_pools: int = draw_fn.find("_draw_light_pools()")
	var at_district: int = draw_fn.find("_draw_district()")
	var at_entities: int = draw_fn.find("_draw_entities()")
	if at_pools < 0:
		push_error("_draw does not call _draw_light_pools: the lit pools are never drawn")
		return false
	if at_district < 0 or at_entities < 0 or at_pools < at_district or at_pools > at_entities:
		push_error("_draw_light_pools is not called between _draw_district and _draw_entities (district %d, pools %d, entities %d)" % [at_district, at_pools, at_entities])
		return false

	var pools_fn: String = _function_body(MAIN_GD, "_draw_light_pools")
	if pools_fn.is_empty():
		push_error("could not read _draw_light_pools out of %s" % MAIN_GD)
		return false
	if not pools_fn.contains("LightLook.lit_pool_tiles("):
		push_error("_draw_light_pools does not call LightLook.lit_pool_tiles: the lit-and-seen rule is not what is on screen")
		return false
	if not pools_fn.contains("LightLook.ambient_of("):
		push_error("_draw_light_pools does not call LightLook.ambient_of: nothing keeps warm pools off a sunlit street")
		return false
	if not pools_fn.contains("Palette.LIGHT_POOL_NEAR") or not pools_fn.contains("Palette.LIGHT_POOL_FAR"):
		push_error("_draw_light_pools does not use both Palette pool tints: the near/far split reaches no colour")
		return false
	# The O-key rider. `attention_channel` had five values and drew nothing for any of them; the
	# light channel is now the one that draws, off the same helper. If this ever comes out, the
	# record in docs/23 has to change with it.
	if not pools_fn.contains("attention_channel == \"light\""):
		push_error("_draw_light_pools does not read attention_channel: the O key's light channel is a dead control again")
		return false

	var wash_fn: String = _function_body(MAIN_GD, "_draw_night_wash")
	if wash_fn.is_empty():
		push_error("could not read _draw_night_wash out of %s" % MAIN_GD)
		return false
	if not wash_fn.contains("LightLook.wash_alpha("):
		push_error("_draw_night_wash does not call LightLook.wash_alpha: the wash is not sight-derived")
		return false
	if wash_fn.contains("Clock.ambient_light"):
		push_error("_draw_night_wash reads Clock.ambient_light directly -- that is the raw-ambient wash this slice replaced")
		return false
	print("DEAD SOCKET OK _draw calls _draw_light_pools between the district and the entities; it reaches lit_pool_tiles, ambient_of, both Palette tints and the O channel; _draw_night_wash reaches wash_alpha and no longer reads raw ambient")
	return true


# The source text of one function, from its `func` line to the next top-level `func`.
# check_topdown.gd's and check_camera.gd's reader, unchanged.
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

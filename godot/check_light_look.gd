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
const ContentLoader = preload("res://platform/content_loader.gd")
const Items = preload("res://sim/modules/items.gd")
const Inventory = preload("res://sim/modules/inventory.gd")
const SimNeedsMod = preload("res://sim/modules/needs.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const Appearance = preload("res://presentation/appearance.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const MAP_TILES: int = 24
const WALL_X: int = 12
const PLAYER_X: float = 8.5
const PLAYER_Y: float = 12.5
# Deep night: past DUSK_ENDS (0.75), so ambient sits flat at NIGHT_AMBIENT.
const NIGHT_FRACTION: float = 0.9
const CAMPFIRE_M: float = 20.0
const CANDLE_M: float = 3.0
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
	ok = _source_tints_are_content_driven_and_pools_are_grouped() and ok
	ok = _tint_schema_is_strict_and_every_tint_has_a_reader() and ok
	ok = _dead_socket_main_gd_draws_what_light_look_returns() and ok
	ok = _the_light_map_lands_no_light_on_an_unseen_tile() and ok
	ok = _a_pool_is_rings_capped_by_its_reach() and ok
	ok = _a_beam_is_content_and_needs_a_facing() and ok
	ok = _a_flame_flickers_and_a_bulb_does_not() and ok
	ok = _a_window_lights_the_floor_beyond_not_the_masonry() and ok
	if ok:
		print("LIGHT_LOOK_OK the light map's texels put light on no unseen tile (a walled campfire's far side carries no seen byte and no source bit, the open twin is lit, remembered tiles read 128), light through a window lands on the floor beyond and not on the opaque tiles there, pools are rings capped by their reach (fire over lantern, and redder), the eye disc derives from sight (and differs from raw ambient on the same lit scene), falls back to ambient exactly with no observer or no emitter, pools are lit-and-seen with a walled far side drawn nowhere, the near/far split lands at %.0f m, full daylight clears the light map, and main.gd's _draw calls both helpers" % LightLook.POOL_SPLIT_METRES)
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
	w.content = ContentLoader.load_tree("res://content")
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

	# What the screen reads off that fraction: the survivor's own disc of ground, which in the pool
	# is the survivor's own sight held under the disc's cap, and in the dark is the sky's share.
	var range_m: float = float(SimVisibility.daylight_eyes()["range_metres"])
	var lifted: float = LightLook.eye_disc_metres(w, int(w.player))
	var unlifted: float = ambient * range_m
	if absf(lifted - minf(fraction * range_m, LightLook.EYE_DISC_MAX_M)) > 0.0001 or lifted <= unlifted + EPS:
		push_error("the eye disc in the campfire's pool is %f m, not min(sight %f, cap %f), or no wider than the %f m raw ambient would give" % [lifted, fraction * range_m, LightLook.EYE_DISC_MAX_M, unlifted])
		return false
	print("SIGHT-DERIVED OK a %.0f m campfire one metre away lifts the fraction from ambient %.4f to %.4f, and the eye disc from %.2f m to %.2f m" % [CAMPFIRE_M, ambient, fraction, unlifted, lifted])
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
	for group in (blocked.get("coloured", {}) as Dictionary).values():
		if (group as Dictionary).get("tiles", []).has(Vector2i(far_tx, far_ty)):
			push_error("a source-coloured tile on the far side of a wall was returned for drawing")
			return false
	for pool in ["near", "far"]:
		for t in blocked[pool] as Array:
			if (t as Vector2i).x > WALL_X:
				push_error("tile %s is past the wall at x=%d and was still returned in the %s pool" % [str(t), WALL_X, pool])
				return false

	var open: Variant = _world(false, NIGHT_FRACTION)
	# The explored map is the sightings module's; this fixture boots the kernel alone, so it is
	# registered here for the walk-away check below.
	SimSightings.register_module(open)
	SimSightings.attach(open, int(open.player))
	_emitter(open, float(far_tx) + 0.5, float(far_ty) + 0.5, CAMPFIRE_M)
	open.step()
	var drawn: Dictionary = LightLook.lit_pool_tiles(open, int(open.player), _all_bounds())
	if not _has(drawn["near"] as Array, far_tx, far_ty):
		push_error("with the wall taken away the same lit tile (%d, %d) is still in no near pool -- the refusal above may be a helper that returns nothing" % [far_tx, far_ty])
		return false
	var coloured_drawn: bool = false
	for group in (drawn.get("coloured", {}) as Dictionary).values():
		if (group as Dictionary).get("tiles", []).has(Vector2i(far_tx, far_ty)):
			coloured_drawn = true
	if not coloured_drawn:
		push_error("with no wall the visible lit tile still has no coloured group; the positive gate has no source-tint reader to judge")
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
# observer's own range and a candle may not give better than daylight -- and ambient_of is 1, which
# is what main.gd's early-out reads to clear the light map instead of drawing it: the day frame is
# the frame it was before the light map. The night scene is the true negative: there ambient_of must
# read below 1, or "draws nothing by day" is a claim about a branch that is always taken.
func _full_daylight_washes_nothing() -> bool:
	var day: Variant = _world(false, Clock.DAY_BEGINS)
	_emitter(day, PLAYER_X + 1.0, PLAYER_Y, CAMPFIRE_M)
	day.step()
	var fraction: float = LightLook.local_light_fraction(day, int(day.player))
	if absf(fraction - 1.0) > EPS:
		push_error("in full daylight beside a campfire the fraction is %f, not 1.0 -- either the day is not full or the clamp is gone" % fraction)
		return false
	if LightLook.ambient_of(day) < 1.0:
		push_error("ambient_of() reads %f at noon, so main.gd would still draw a night in full daylight" % LightLook.ambient_of(day))
		return false
	# main.gd clears the light map rather than drawing it whenever ambient_of says full day, so the
	# day frame is exactly the frame it was before the light map existed.
	var wash_fn: String = _function_body(MAIN_GD, "_draw_night_wash")
	var early: int = wash_fn.find("if ambient >= 1.0:")
	var cleared: int = wash_fn.find("_light_map.call(\"frame\", {}, false)")
	var texels_at: int = wash_fn.find("LightLook.light_texels(")
	if early < 0 or cleared < early or texels_at < cleared:
		push_error("_draw_night_wash has no daylight early-out clearing the light map before it builds one (early %d, clear %d, texels %d)" % [early, cleared, texels_at])
		return false

	var night: Variant = _world(false, NIGHT_FRACTION)
	night.step()
	if LightLook.ambient_of(night) >= 1.0:
		push_error("the night scene also reads full day -- the daylight assertion above cannot go red")
		return false
	print("DAYLIGHT OK fraction clamps to 1.0 beside a campfire at noon, ambient_of is 1 so the light map is cleared, and midnight reads ambient %.3f" % LightLook.ambient_of(night))
	return true


# CONTENT COLOUR. The source's item base decides the tint, while the existing cast still decides
# which visible bounded tiles receive it. The old arrays remain the exact near/far union.
func _source_tints_are_content_driven_and_pools_are_grouped() -> bool:
	var w: Variant = _world(false, NIGHT_FRACTION)
	var green: int = _emitter(w, PLAYER_X - 1.0, PLAYER_Y, 12.0)
	w.components.set_component(green, "itemBase", {"baseId": "item.glowstick"})
	var red: int = _emitter(w, PLAYER_X + 5.0, PLAYER_Y, 16.0)
	w.components.set_component(red, "itemBase", {"baseId": "item.flare.road"})
	w.step()
	if LightLook.source_tint(w, green) != Color("#a8d58b") or LightLook.source_tint(w, red) != Color("#ee856c"):
		push_error("glowstick and road flare did not resolve their declared green and red content tints")
		return false
	var placed: int = int(w.entities.spawn())
	w.components.set_component(placed, "placedLight", {"baseId": "item.floodlight.rigged"})
	if LightLook.source_tint(w, placed) != Color("#e5edf2"):
		push_error("a planted floodlight did not resolve its actual base's neutral tint")
		return false
	var campfire_world: Variant = _world(false, NIGHT_FRACTION)
	var stations: Array = campfire_world.content.get("props/stations.json", [])
	for entry in stations:
		if String((entry as Dictionary).get("id", "")) == "prop.campfire.lit":
			if ((entry as Dictionary).get("appearance", {}) as Dictionary).get("light", {}).get("tint", "") != "#ff9452":
				push_error("the shipped lit campfire must declare its warm content tint")
				return false
	var fire: int = int(campfire_world.entities.spawn())
	campfire_world.components.set_component(fire, "position", {"x": PLAYER_X, "y": PLAYER_Y})
	campfire_world.components.set_component(fire, "campfire", {"lit": true})
	SimLightMod.make_light_source(campfire_world, fire, CAMPFIRE_M)
	if LightLook.source_tint(campfire_world, fire) != Color("#ff9452"):
		push_error("the lit campfire did not read its prop appearance's actual tint")
		return false
	campfire_world.components.set_component(fire, "campfire", {"lit": false})
	campfire_world.components.remove(fire, "light_source")
	campfire_world.step()
	if LightLook.source_tint(campfire_world, fire) != LightLook.DEFAULT_SOURCE_TINT:
		push_error("an unlit campfire's missing tint did not fall back to the legacy warm colour")
		return false
	if campfire_world.light.sources_list().has(fire):
		push_error("an unlit campfire remained an active coloured light source")
		return false
	# The actor's actual equipped gear decides the colour. A weapon light attached to its primary
	# outranks the carried glowstick; exhausting that attachment reveals the glowstick again.
	var actor: int = int(w.entities.spawn())
	var glow: int = int(w.entities.spawn())
	var weapon: int = int(w.entities.spawn())
	var weapon_light: int = int(w.entities.spawn())
	w.components.set_component(glow, "itemBase", {"baseId": "item.glowstick"})
	w.components.set_component(weapon, "itemBase", {"baseId": "item.rifle.hunting"})
	w.components.set_component(weapon_light, "itemBase", {"baseId": "item.attach.underbarrel.light"})
	w.components.set_component(weapon, "attachments", {"slots": {"underbarrel": weapon_light}})
	w.components.set_component(actor, "equipment", {"slots": {"secondary": glow, "primary": weapon}})
	w.components.set_component(actor, "light_source", {"magnitude": 16.0})
	if LightLook.source_tint(w, actor) != Color("#e5edf2"):
		push_error("a current attached weapon light did not beat the carried glowstick tint")
		return false
	w.components.set_component(weapon_light, "lightFuel", {"ticksLeft": 0})
	w.components.set_component(actor, "light_source", {"magnitude": 6.0})
	if LightLook.source_tint(w, actor) != Color("#a8d58b"):
		push_error("an exhausted attached lamp kept its old colour instead of the next carried light")
		return false
	w.components.set_component(actor, "rangedWeapon", {"flash": 6.0, "flashTicks": 1})
	if LightLook.source_tint(w, actor) != LightLook.DEFAULT_SOURCE_TINT:
		push_error("an equal-magnitude active muzzle flash did not take its own fallback colour")
		return false
	w.components.set_component(actor, "rangedWeapon", {"flash": 8.0, "flashTicks": 1})
	if LightLook.source_tint(w, actor) != LightLook.DEFAULT_SOURCE_TINT:
		push_error("a stronger active muzzle flash did not temporarily override carried colour")
		return false
	w.components.set_component(actor, "rangedWeapon", {"flash": 8.0, "flashTicks": 0})
	if LightLook.source_tint(w, actor) != Color("#a8d58b"):
		push_error("carried light colour did not return when the flash counter expired")
		return false
	if LightLook.source_tint(w, -1) != LightLook.DEFAULT_SOURCE_TINT or LightLook._parse_tint("mystery") != LightLook.DEFAULT_SOURCE_TINT:
		push_error("missing or unknown light tint did not retain the legacy warm fallback")
		return false
	var pools: Dictionary = LightLook.lit_pool_tiles(w, int(w.player), _all_bounds())
	var coloured: Dictionary = pools.get("coloured", {})
	var has_green: bool = false
	var has_red: bool = false
	for group in coloured.values():
		var entry: Dictionary = group as Dictionary
		var tiles: Array = entry.get("tiles", [])
		if (entry.get("tint") as Color) == Color("#a8d58b") and not tiles.is_empty(): has_green = true
		if (entry.get("tint") as Color) == Color("#ee856c") and not tiles.is_empty(): has_red = true
	if not has_green or not has_red:
		push_error("the lit-and-seen pool output does not carry both source colours")
		return false
	# Exact overlap keeps source iteration tie order; increasing only the second source makes it
	# the winner, with no sum of their reaches.
	var tie_world: Variant = _world(false, NIGHT_FRACTION)
	var first: int = _emitter(tie_world, PLAYER_X, PLAYER_Y, 10.0)
	tie_world.components.set_component(first, "itemBase", {"baseId": "item.glowstick"})
	var second: int = _emitter(tie_world, PLAYER_X, PLAYER_Y, 10.0)
	tie_world.components.set_component(second, "itemBase", {"baseId": "item.flare.road"})
	tie_world.step()
	var tied: Dictionary = LightLook.lit_pool_tiles(tie_world, int(tie_world.player), _all_bounds())
	var tied_at_source: String = ""
	for group in (tied.get("coloured", {}) as Dictionary).values():
		if (group as Dictionary).get("tiles", []).has(Vector2i(floori(PLAYER_X), floori(PLAYER_Y))):
			tied_at_source = (group as Dictionary).get("tint", Color()).to_html(false)
	if tied_at_source != "a8d58b":
		push_error("equal remaining reach did not preserve first-source iteration order")
		return false
	SimLightMod.make_light_source(tie_world, second, 14.0)
	tie_world.step()
	var stronger: Dictionary = LightLook.lit_pool_tiles(tie_world, int(tie_world.player), _all_bounds())
	var stronger_at_source: String = ""
	for group in (stronger.get("coloured", {}) as Dictionary).values():
		if (group as Dictionary).get("tiles", []).has(Vector2i(floori(PLAYER_X), floori(PLAYER_Y))):
			stronger_at_source = (group as Dictionary).get("tint", Color()).to_html(false)
	if stronger_at_source != "ee856c" or absf(float(tie_world.light.lit_metres(PLAYER_X, PLAYER_Y)) - 14.0) > EPS:
		push_error("stronger overlapping source did not win as a max or appears to have summed reach")
		return false
	var near_union: Array = []
	var far_union: Array = []
	var coloured_near: Dictionary = {}
	var coloured_far: Dictionary = {}
	for group in coloured.values():
		var entry: Dictionary = group as Dictionary
		if bool(entry.get("near", false)):
			near_union.append_array(entry.get("tiles", []))
			for tile in entry.get("tiles", []): coloured_near[tile] = true
		else:
			far_union.append_array(entry.get("tiles", []))
			for tile in entry.get("tiles", []): coloured_far[tile] = true
	var same_sets: bool = near_union.size() == (pools["near"] as Array).size() and far_union.size() == (pools["far"] as Array).size()
	for tile in pools["near"] as Array: same_sets = same_sets and coloured_near.has(tile) and not coloured_far.has(tile)
	for tile in pools["far"] as Array: same_sets = same_sets and coloured_far.has(tile) and not coloured_near.has(tile)
	if not same_sets:
		push_error("coloured pools changed the exact legacy near/far tile sets")
		return false
	var bounded: Dictionary = LightLook.lit_pool_tiles(w, int(w.player), {"minX": 0.0, "maxX": 10.0, "minY": 12.0, "maxY": 12.0})
	for group in (bounded.get("coloured", {}) as Dictionary).values():
		for tile in (group as Dictionary).get("tiles", []):
			if (tile as Vector2i).x > 10 or (tile as Vector2i).y != 12:
				push_error("a coloured pool tile escaped the caller's viewport bounds")
				return false
	var removed_world: Variant = _world(false, NIGHT_FRACTION)
	var removed: int = _emitter(removed_world, PLAYER_X, PLAYER_Y, 8.0)
	removed_world.step()
	if (LightLook.lit_pool_tiles(removed_world, int(removed_world.player), _all_bounds()).get("coloured", {}) as Dictionary).is_empty():
		push_error("the positive source fixture never produced a colour before removal")
		return false
	removed_world.components.remove(removed, "light_source")
	removed_world.step()
	if not (LightLook.lit_pool_tiles(removed_world, int(removed_world.player), _all_bounds()).get("coloured", {}) as Dictionary).is_empty():
		push_error("a removed light source left stale coloured pool tiles")
		return false
	print("SOURCE COLOUR OK content selects green/red; carried attachments and exhausted fallback update; unknowns stay warm; groups preserve membership, max overlap and tie order")
	return true


func _tint_schema_is_strict_and_every_tint_has_a_reader() -> bool:
	var file: FileAccess = FileAccess.open("res://content/schemas/item.schema.json", FileAccess.READ)
	if file == null:
		push_error("item schema could not be read; light.tint shape has no gate")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var tint_schema: Variant = null
	# Read through explicit dictionary steps so malformed nesting fails this lane cleanly.
	if not parsed is Dictionary:
		push_error("item schema JSON did not parse to an object")
		return false
	var props: Dictionary = parsed.get("properties", {})
	var light: Dictionary = props.get("light", {})
	var light_props: Dictionary = light.get("properties", {})
	tint_schema = light_props.get("tint")
	if light.get("additionalProperties", true) != false or not tint_schema is Dictionary:
		push_error("item light block must remain strict and declare its optional tint schema")
		return false
	if (tint_schema as Dictionary).get("type") != "string" or String((tint_schema as Dictionary).get("pattern", "")) != "^#[0-9a-f]{6}$":
		push_error("light.tint must be strict lowercase six-digit hex")
		return false
	var prop_file: FileAccess = FileAccess.open("res://content/schemas/prop.schema.json", FileAccess.READ)
	var prop_parsed: Variant = JSON.parse_string(prop_file.get_as_text()) if prop_file != null else null
	var prop_appearance: Dictionary = ((prop_parsed as Dictionary).get("properties", {}) as Dictionary).get("appearance", {}) as Dictionary if prop_parsed is Dictionary else {}
	var prop_light: Dictionary = (prop_appearance.get("properties", {}) as Dictionary).get("light", {}) as Dictionary
	var prop_tint: Dictionary = (prop_light.get("properties", {}) as Dictionary).get("tint", {}) as Dictionary
	if prop_light.get("additionalProperties", true) != false or prop_tint.get("type") != "string" or prop_tint.get("pattern") != "^#[0-9a-f]{6}$":
		push_error("prop appearance.light.tint must be strict and optional")
		return false
	if not LightLook.tint_declaration_is_valid("#12abef"):
		push_error("valid strict hex tint was refused")
		return false
	if LightLook.DEFAULT_SOURCE_TINT != Palette.LIGHT_POOL_RGB:
		push_error("unknown sources no longer use the exact legacy warm pool RGB")
		return false
	if LightLook.tint_declaration_is_valid("#fff") or LightLook.tint_declaration_is_valid("#12Abef") or LightLook.tint_declaration_is_valid(42) or LightLook.tint_declaration_is_valid("neutral"):
		push_error("invalid tint format or type passed the declaration predicate")
		return false
	if absf(LightLook.pool_colour(Color("#ee856c"), true).a - Palette.LIGHT_POOL_NEAR.a) > EPS or absf(LightLook.pool_colour(Color("#ee856c"), false).a - Palette.LIGHT_POOL_FAR.a) > EPS or absf(LightLook.pool_colour(Color("#ee856c"), true, true).a - Palette.LIGHT_POOL_NEAR_OVERLAY.a) > EPS:
		push_error("source tint changed legacy near/far or developer overlay alpha")
		return false
	var resolver: String = _function_body("res://presentation/light_look.gd", "source_tint")
	if not resolver.contains("brightest_carried") or not resolver.contains("item_base_of") or not resolver.contains("placedLight") or not resolver.contains("Appearance.prop_look") or not resolver.contains("flashTicks"):
		push_error("source_tint no longer reads actual carried, placed and campfire source content")
		return false
	var pools_reader: String = _function_body("res://presentation/light_look.gd", "lit_pool_tiles")
	var metadata_at: int = pools_reader.find("source_tint(world, source_id)")
	var tile_scan_at: int = pools_reader.find("for ty in range")
	if not pools_reader.contains("source_meta[source_id]") or metadata_at < 0 or tile_scan_at < 0 or metadata_at > tile_scan_at:
		push_error("lit_pool_tiles must resolve and cache source metadata before its tile scan")
		return false
	print("TINT SHAPE AND READER OK strict hex accepts; malformed, wrong-typed and named aliases refuse; carried/placed/campfire/flash content paths are read")
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
	# The floor is _draw_world since the world was baked (presentation/world_layers.gd): the baked
	# ground draws behind main's own commands, and _draw_world brings it up to date first.
	var at_district: int = draw_fn.find("_draw_world()")
	var at_entities: int = draw_fn.find("_draw_entities()")
	if at_pools < 0:
		push_error("_draw does not call _draw_light_pools: the lit pools are never drawn")
		return false
	if at_district < 0 or at_entities < 0 or at_pools < at_district or at_pools > at_entities:
		push_error("_draw_light_pools is not called between _draw_world and _draw_entities (world %d, pools %d, entities %d)" % [at_district, at_pools, at_entities])
		return false

	var pools_fn: String = _function_body(MAIN_GD, "_draw_light_pools")
	if pools_fn.is_empty():
		push_error("could not read _draw_light_pools out of %s" % MAIN_GD)
		return false
	if not pools_fn.contains("LightLook.lit_pool_tiles("):
		push_error("_draw_light_pools does not call LightLook.lit_pool_tiles: the lit-and-seen rule is not what is on screen")
		return false
	# Since the light map (A10) the tile pools are the O channel's alone: the street's light is the
	# per-pixel night. A pool drawn as flat rects on an ordinary frame is the look A10 replaced.
	if not pools_fn.contains("if not overlay: return"):
		push_error("_draw_light_pools draws on an ordinary frame: the flat tile pools are back under the light map")
		return false
	if not _draw_uses_source_tint(pools_fn):
		push_error("_draw_light_pools does not pass each group's tint through pool_colour into the tile draw")
		return false
	var ignores_tint: String = pools_fn.replace("LightLook.pool_colour(tint, near_pool, overlay)", "LightLook.pool_colour(Palette.LIGHT_POOL_RGB, near_pool, overlay)")
	if _draw_uses_source_tint(ignores_tint):
		push_error("the light tint source scanner accepts a fabricated pool that always uses the warm default")
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
	# The light map: the night is built from LightLook's texels (lit ∩ seen as bits), its sky from
	# ambient_of, and handed to light_map.gd's frame; the night-wash constant still drives it.
	for needle in ["LightLook.light_texels(", "LightLook.ambient_of(", "LightLook.eye_disc_metres(", "_light_map.call(\"frame\"", "\"night_wash\": NIGHT_WASH", "_interp.offset(", "LightLook.hand_metres("]:
		if not wash_fn.contains(needle):
			push_error("_draw_night_wash does not reach %s: the light map is not what is on screen" % needle)
			return false
	if wash_fn.contains("Clock.ambient_light"):
		push_error("_draw_night_wash reads Clock.ambient_light directly -- that is the raw-ambient wash this slice replaced")
		return false
	var at_wash: int = draw_fn.find("_draw_night_wash()")
	var at_glow: int = draw_fn.find("_draw_effects(true)")
	if at_wash < 0 or at_glow < 0 or at_glow < at_wash:
		push_error("_draw does not lay the night before the lights (wash %d, glow %d)" % [at_wash, at_glow])
		return false
	var effects_fn: String = _function_body(MAIN_GD, "_draw_effects")
	if not effects_fn.contains("_light_map.call(\"glow_rect\""):
		push_error("_draw_effects(true) draws into main's own item, under the multiplied night: a flash would be dimmed")
		return false
	# light_map.gd hands the shader every number LightLook owns, and the shader multiplies (so it
	# can only darken) and reads the texels and the beams it is handed.
	var map_src: String = FileAccess.get_file_as_string("res://presentation/light_map.gd")
	for needle in ["LightLook.source_cap(", "LightLook.POOL_LEVELS", "LightLook.EYE_FLOOR", "LightLook.NIGHT_FLOOR", "LightLook.MAX_LIGHTS", "\"light_tex\"", "\"light_dir\"", "\"light_pos\"", "\"eye_reach\"", "\"spill_m\", SimLight.SPILL_M"]:
		if not map_src.contains(needle):
			push_error("light_map.gd does not hand the shader %s" % needle)
			return false
	var shader_src: String = FileAccess.get_file_as_string("res://presentation/night_light.gdshader")
	for needle in ["render_mode blend_mul", "float b = tint.w * rings(fall * mask, threshold);", "eye_floor * (1.0 - ambient) * eye_fade * rings(1.0 - smoothstep(disc_r * 0.45, disc_r, d_eye), threshold)", "texelFetch(light_tex", "light_dir[i]", "float mask = inside(own,", "if (light_count > 0 && own_r > 191)", "float hand = 1.0 - smoothstep(spill_m * 0.4, spill_m, d);", "float wedge = smoothstep(beam.z, beam.w, along);"]:
		if not shader_src.contains(needle):
			push_error("night_light.gdshader lost %s" % needle)
			return false
	print("DEAD SOCKET OK the O channel alone draws tile pools (lit_pool_tiles, both Palette tints); _draw_night_wash builds the light map from light_texels and ambient_of before _draw_effects(true), which blits into the glow item; light_map.gd hands the shader LightLook's caps, rings, eye floor, eye disc and texels and the sim's spill; a beam leaves the hand (LightLook.hand_metres); the shader multiplies, rings every light, feathers source light inward on seen tiles only, reads the beams, ends each at its half-angle and draws the spill's disc at the hand")
	return true


# --- the light map (A10) ---------------------------------------------------------------------

func _view() -> Rect2i:
	return Rect2i(0, 0, MAP_TILES, MAP_TILES)


func _texel(texels: Dictionary, tx: int, ty: int) -> PackedByteArray:
	var at: int = (ty * MAP_TILES + tx) * 4
	return (texels["bytes"] as PackedByteArray).slice(at, at + 4)


# NO LIGHT ON UNSEEN. The plan's lane: a campfire behind a wall lights its own side in the sim, and
# every tile there the survivor does not see carries no seen byte and no source bit in the light
# map, so the shader has nothing to put there. The R byte is 128 exactly where the survivor only
# remembers the tile (SimSightings.knows_tile and not seen), 0 for the void; the remembered case is
# made, not assumed -- the survivor walks away from tiles they saw. Every tile carrying a source bit carries the
# seen bit too (lit is a subset of seen, everywhere, not only past the wall). The true negative is
# the open twin: the same tile with the wall gone is seen and carries the campfire's bit, so a
# builder that returned zeros for everything could not pass.
func _the_light_map_lands_no_light_on_an_unseen_tile() -> bool:
	var far_tx: int = 16
	var far_ty: int = 12
	var walled: Variant = _world(true, NIGHT_FRACTION)
	_emitter(walled, float(far_tx) + 0.5, float(far_ty) + 0.5, CAMPFIRE_M)
	walled.step()
	if float(walled.light.lit_metres(float(far_tx) + 0.5, float(far_ty) + 0.5)) <= 0.0:
		push_error("NO LIGHT ON UNSEEN: the far-side tile is not lit in the sim -- the lane has no leak to refuse")
		return false
	var texels: Dictionary = LightLook.light_texels(walled, int(walled.player), _view())
	var seen: Variant = walled.vision.tiles_for(int(walled.player))
	var lit_unseen: int = 0
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var t: PackedByteArray = _texel(texels, tx, ty)
			var is_seen: bool = bool((seen as Object).call("has_tile", tx, ty))
			if (t[0] == 255) != is_seen or (t[0] != 255 and t[0] != 128 and t[0] != 0):
				push_error("NO LIGHT ON UNSEEN: tile (%d, %d) has seen byte %d but the survivor's sight says %s" % [tx, ty, t[0], str(is_seen)])
				return false
			if (t[1] | t[2] | t[3]) != 0 and t[0] != 255:
				push_error("NO LIGHT ON UNSEEN: tile (%d, %d) carries a source bit and no seen bit" % [tx, ty])
				return false
			if not is_seen and float(walled.light.lit_metres(float(tx) + 0.5, float(ty) + 0.5)) > 0.0:
				lit_unseen += 1
				if t[0] == 255 or (t[1] | t[2] | t[3]) != 0:
					push_error("NO LIGHT ON UNSEEN: tile (%d, %d) is lit in the sim and unseen, and its texel carries light or reads seen" % [tx, ty])
					return false
	if lit_unseen == 0:
		push_error("NO LIGHT ON UNSEEN: no tile was lit and unseen -- the lane judged nothing")
		return false

	var open: Variant = _world(false, NIGHT_FRACTION)
	# The explored map is the sightings module's; this fixture boots the kernel alone, so it is
	# registered here for the walk-away check below.
	SimSightings.register_module(open)
	SimSightings.attach(open, int(open.player))
	_emitter(open, float(far_tx) + 0.5, float(far_ty) + 0.5, CAMPFIRE_M)
	open.step()
	var open_texels: Dictionary = LightLook.light_texels(open, int(open.player), _view())
	var t_open: PackedByteArray = _texel(open_texels, far_tx, far_ty)
	if t_open[0] != 255 or (t_open[1] & 1) != 1 or (open_texels["sources"] as Array).size() != 1:
		push_error("NO LIGHT ON UNSEEN: with the wall gone the same tile is not seen-and-lit by the one source (bytes %s, sources %s) -- the refusal above may be a builder that returns nothing" % [str(t_open), str(open_texels["sources"])])
		return false
	if int(open_texels["lit"]) <= 0 or int(open_texels["lit"]) > int(open_texels["seen"]):
		push_error("NO LIGHT ON UNSEEN: the open twin reports %d lit of %d seen tiles" % [int(open_texels["lit"]), int(open_texels["seen"])])
		return false
	var p0: Dictionary = open.components.get_component(open.player, "position")
	open.components.set_component(open.player, "position", {"x": 2.5, "y": float(p0["y"])})
	# Two steps, not one: the player's recast after a move lands whole one tick later
	# (SimVisibility.STAGGER_PLAYER_CAST, A3), the check_memory_look precedent.
	open.step()
	open.step()
	var moved: Dictionary = LightLook.light_texels(open, int(open.player), _view())
	var seen_now: Variant = open.vision.tiles_for(int(open.player))
	var remembered: int = 0
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var r: int = _texel(moved, tx, ty)[0]
			var is_seen_now: bool = bool((seen_now as Object).call("has_tile", tx, ty))
			var known: bool = SimSightings.knows_tile(open, int(open.player), tx, ty)
			var want: int = 255 if is_seen_now else (128 if known else 0)
			if r != want:
				push_error("NO LIGHT ON UNSEEN: tile (%d, %d) reads R %d, not %d (seen %s, remembered %s)" % [tx, ty, r, want, str(is_seen_now), str(known)])
				return false
			if r == 128:
				remembered += 1
	if remembered == 0:
		push_error("NO LIGHT ON UNSEEN: walking away left no remembered tile -- the 128 byte was never judged")
		return false
	var nobody: Dictionary = LightLook.light_texels(open, -1, _view())
	if (nobody["sources"] as Array).size() != 0 or _texel(nobody, far_tx, far_ty)[1] != 0 or _texel(nobody, far_tx, far_ty)[0] != 255:
		push_error("NO LIGHT ON UNSEEN: with nobody to ask, the texels are not every-tile-seen with no source -- the ambient fallback moved")
		return false
	print("NO LIGHT ON UNSEEN OK %d tiles lit in the sim behind the wall carry no seen byte and no source bit; every source bit sits on a seen tile; the open twin's tile is seen and carries its bit (%d lit of %d seen); after walking away %d remembered tiles read 128 and the void 0; nobody to ask is the sky alone" % [lit_unseen, int(open_texels["lit"]), int(open_texels["seen"]), remembered])
	return true


# RINGS AND CAPS. A pool is drawn in POOL_LEVELS flat rings (the art review asked for four or five)
# at a brightness capped by how far the sim says its source reaches: source_cap keeps its bounds,
# never draws a stronger light dimmer than a weaker one, and puts the campfire above the storm
# lantern, whose content is also a yellower colour than the fire's redder one -- so where the two
# overlap the brighter shows as its own level and hue instead of both clipping to one. The eye disc
# never outgrows its cap, and the dark twin's disc is the sky's share of the survivor's range.
func _a_pool_is_rings_capped_by_its_reach() -> bool:
	if LightLook.POOL_LEVELS < 4 or LightLook.POOL_LEVELS > 5:
		push_error("RINGS: a pool is drawn in %d rings, not the four or five the review settled" % LightLook.POOL_LEVELS)
		return false
	if absf(LightLook.source_cap(0.0) - LightLook.CAP_MIN) > EPS or absf(LightLook.source_cap(1000.0) - LightLook.CAP_MAX) > EPS or LightLook.CAP_MAX > 0.95 + EPS:
		push_error("RINGS: source_cap's ends moved (%f at 0 m, %f at 1000 m)" % [LightLook.source_cap(0.0), LightLook.source_cap(1000.0)])
		return false
	var last: float = -1.0
	for m in 61:
		var cap: float = LightLook.source_cap(float(m))
		if cap < last - EPS:
			push_error("RINGS: source_cap(%d m) = %f is dimmer than a weaker light's %f" % [m, cap, last])
			return false
		last = cap
	var w: Variant = _world(false, NIGHT_FRACTION)
	var lantern: Dictionary = Items.content_entry(w, "item", "item.lantern.storm") as Dictionary
	var lantern_light: Dictionary = lantern.get("light", {}) as Dictionary
	var fire_cap: float = LightLook.source_cap(SimNeedsMod.CAMPFIRE_LIGHT_M)
	var lantern_cap: float = LightLook.source_cap(float(lantern_light.get("magnitude", 0.0)))
	if not (fire_cap > lantern_cap + 0.05):
		push_error("RINGS: the campfire's pool caps at %f and the storm lantern's at %f -- overlapping, they clip to one level" % [fire_cap, lantern_cap])
		return false
	var fire_tint: Color = Color("#ff9452")
	var lantern_tint: Color = Color(String(lantern_light.get("tint", "#ffffff")))
	# Redder: green falls further below red in the fire's hue than in the lantern's.
	if not (fire_tint.g / fire_tint.r < lantern_tint.g / lantern_tint.r - 0.1):
		push_error("RINGS: the campfire's tint %s is not redder than the storm lantern's %s" % [fire_tint.to_html(false), lantern_tint.to_html(false)])
		return false
	var night: Color = Palette.COLOURS["night"] as Color
	for ch in [night.r, night.g, night.b]:
		if float(ch) * LightLook.NIGHT_FLOOR * 255.0 > 8.0 + EPS:
			push_error("RINGS: the midnight floor is night x %f, a channel above 8 of 255 on a white tile" % LightLook.NIGHT_FLOOR)
			return false
	w.step()
	var dark_disc: float = LightLook.eye_disc_metres(w, int(w.player))
	var expect: float = LightLook.ambient_of(w) * float(SimVisibility.daylight_eyes()["range_metres"])
	if absf(dark_disc - expect) > 0.0001:
		push_error("RINGS: with no light the eye disc is %f m, not the sky's share of the range %f m" % [dark_disc, expect])
		return false
	if LightLook.eye_disc_metres(w, -1) != 0.0:
		push_error("RINGS: with nobody to ask there is still an eye disc")
		return false
	print("RINGS OK %d rings; caps %.2f..%.2f, monotonic; campfire %.2f over storm lantern %.2f, and redder; the dark eye disc is %.2f m" % [LightLook.POOL_LEVELS, LightLook.CAP_MIN, LightLook.CAP_MAX, fire_cap, lantern_cap, dark_disc])
	return true


# BEAM. The screen's beam is the sim's (slice B3). A carried hand torch reads the half-angle the
# light index keeps for it -- its content's, through sim/modules/light.gd -- and the light map's bits
# for it are `lights_tile`'s answer tile for tile: present ahead in the wedge and in the spill behind
# the holder's back, zero on a seen tile behind them past the spill, where the sim's round cast still
# reaches but its wedge does not. The negatives: a carried storm lantern is round and its bit is on
# that same tile behind; the same torch on a carrier with no facing throws round in the sim and so on
# the screen. The beam leaves the hand: a torch in the secondary hand starts at that hand's point off
# the feet-anchored pawn canvas, and a headlamp, held in no hand, at the body's own point. Every
# content light with a beam is an item a body can carry (an equipSlot or an attachment), or the key
# would be read by nothing.
func _a_beam_is_content_and_needs_a_facing() -> bool:
	var behind := Vector2i(int(PLAYER_X) - 6, int(PLAYER_Y))
	var ahead := Vector2i(int(PLAYER_X) + 6, int(PLAYER_Y))
	var spill := Vector2i(int(PLAYER_X) - 1, int(PLAYER_Y))
	var w: Variant = _world(false, NIGHT_FRACTION)
	var torch: int = int(Items.spawn_item(w, "item.torch.handheld", {}))
	if not Inventory.equip(w, int(w.player), torch, ""):
		push_error("BEAM: the fixture could not equip a hand torch")
		return false
	SimLightMod.refresh_carried(w, int(w.player))
	w.step()
	var want: float = deg_to_rad(float((Items.content_entry(w, "item", "item.torch.handheld").get("light", {}) as Dictionary).get("beam", 0.0)))
	var beam: float = LightLook.source_beam(w, int(w.player))
	var sim_beam: float = float((w.light.source_at(int(w.player)) as Dictionary).get("beam", -1.0))
	if not (want > 0.0) or absf(beam - want) > EPS or absf(beam - sim_beam) > EPS:
		push_error("BEAM: a carried hand torch reads beam %f on screen, %f in the sim, content says %f" % [beam, sim_beam, want])
		return false
	var texels: Dictionary = LightLook.light_texels(w, int(w.player), _view())
	var lights: Array = texels["lights"] as Array
	if lights.is_empty() or absf(float((lights[0] as Dictionary).get("beam", 0.0)) - want) > EPS:
		push_error("BEAM: light_texels does not hand the torch's beam on to the light map")
		return false
	var seen: Variant = w.vision.tiles_for(int(w.player))
	for t in [behind, ahead, spill]:
		if not bool((seen as Object).call("has_tile", (t as Vector2i).x, (t as Vector2i).y)):
			push_error("BEAM: the survivor does not see tile %s -- the lane has no bit to judge" % str(t))
			return false
	if not bool((w.light.tiles_for(int(w.player)) as Object).call("has_tile", behind.x, behind.y)):
		push_error("BEAM: the torch's round cast does not reach the tile behind -- nothing for the wedge to cut")
		return false
	for t in [behind, ahead, spill]:
		var tv: Vector2i = t as Vector2i
		var bit: bool = (_texel(texels, tv.x, tv.y)[1] & 1) == 1
		var sim: bool = bool(w.light.lights_tile(int(w.player), tv.x, tv.y))
		if bit != sim:
			push_error("BEAM: tile %s carries bit %s on screen and lights_tile says %s -- the drawn wedge is not the sim's" % [str(tv), str(bit), str(sim)])
			return false
	if (_texel(texels, behind.x, behind.y)[1] & 1) != 0 or (_texel(texels, ahead.x, ahead.y)[1] & 1) != 1 or (_texel(texels, spill.x, spill.y)[1] & 1) != 1:
		push_error("BEAM: a torch facing east is not lit 6 m ahead and in its spill and dark 6 m behind on screen")
		return false
	var hand: Vector2 = LightLook.hand_metres(w, int(w.player), 0.0, "", 64.0)
	var grip: Vector2i = Appearance.HELD_HANDS["secondary"]["e"] as Vector2i
	var want_hand := Vector2((float(grip.x) + 0.5 - float(Appearance.PAWN_CANVAS.x) / 2.0) / 32.0, (float(grip.y) + 0.5 - float(Appearance.PAWN_CANVAS.y)) / 32.0 + Appearance.FOOT_DROP_PX / 64.0)
	if hand.distance_to(want_hand) > 0.0001 or hand.length() < 0.05:
		push_error("BEAM: the torch's beam leaves %s, not the secondary hand's point %s" % [str(hand), str(want_hand)])
		return false
	# Seen from behind the beam starts at the hand's side on the ground, not above the head.
	var back: Vector2 = LightLook.hand_metres(w, int(w.player), -PI / 2.0, "", 64.0)
	var back_grip: Vector2i = Appearance.HELD_HANDS["secondary"]["n"] as Vector2i
	if absf(back.y) > 0.0001 or absf(back.x - (float(back_grip.x) + 0.5 - float(Appearance.PAWN_CANVAS.x) / 2.0) / 32.0) > 0.0001:
		push_error("BEAM: facing north the beam leaves %s, not the hand's side on the ground under the body" % str(back))
		return false
	w.components.remove(w.player, "facing")
	w.step()
	if LightLook.source_beam(w, int(w.player)) != 0.0 or not bool(w.light.lights_tile(int(w.player), behind.x, behind.y)):
		push_error("BEAM: a carrier with no facing still has a beam -- it has nowhere to point")
		return false
	var lw: Variant = _world(false, NIGHT_FRACTION)
	var lantern: int = int(Items.spawn_item(lw, "item.lantern.storm", {}))
	Inventory.equip(lw, int(lw.player), lantern, "")
	SimLightMod.refresh_carried(lw, int(lw.player))
	lw.step()
	if lw.light.source_count() < 1 or LightLook.source_beam(lw, int(lw.player)) != 0.0:
		push_error("BEAM: a carried storm lantern is not a lit round pool")
		return false
	if (_texel(LightLook.light_texels(lw, int(lw.player), _view()), behind.x, behind.y)[1] & 1) != 1:
		push_error("BEAM: a carried storm lantern leaves the tile behind its carrier dark on screen -- the cut is not the wedge's")
		return false
	var hw: Variant = _world(false, NIGHT_FRACTION)
	var lamp: int = int(Items.spawn_item(hw, "item.headlamp.band", {}))
	Inventory.equip(hw, int(hw.player), lamp, "")
	SimLightMod.refresh_carried(hw, int(hw.player))
	hw.step()
	if LightLook.source_beam(hw, int(hw.player)) <= 0.0 or LightLook.hand_metres(hw, int(hw.player), 0.0, "", 64.0) != Vector2.ZERO:
		push_error("BEAM: a headlamp is not a beam from the body's own point (beam %f, origin %s)" % [LightLook.source_beam(hw, int(hw.player)), str(LightLook.hand_metres(hw, int(hw.player), 0.0, "", 64.0))])
		return false
	var beams: int = 0
	for path in (w.content as Dictionary).keys():
		var rows: Variant = (w.content as Dictionary)[path]
		if not (String(path).begins_with("items/") and rows is Array):
			continue
		for row in rows as Array:
			var light: Variant = (row as Dictionary).get("light")
			if light is Dictionary and (light as Dictionary).has("beam"):
				beams += 1
				if not ((row as Dictionary).has("equipSlot") or (row as Dictionary).has("attachment")):
					push_error("BEAM: %s declares a beam and nothing can carry it" % String((row as Dictionary).get("id", "")))
					return false
	if beams == 0:
		push_error("BEAM: no content declares a beam -- the key is read by nothing")
		return false
	print("BEAM OK a carried hand torch is the sim's %.0f degree beam on screen: its bits are lights_tile's, lit 6 m ahead and in the spill, dark 6 m behind where its round cast reaches; it leaves the secondary hand (%.2f, %.2f) m off the feet, and seen from behind that hand's side on the ground; no facing and a lantern are round and light the tile behind; a headlamp leaves the body's point; %d content lights declare a beam and every one can be carried" % [rad_to_deg(want), hand.x, hand.y, beams])
	return true


# FLICKER. A campfire flickers and a cell torch does not; the flicker only ever dims (the shader
# multiplies reach by 1 - w * [0, 1]), so it is a fraction below one.
func _a_flame_flickers_and_a_bulb_does_not() -> bool:
	var w: Variant = _world(false, NIGHT_FRACTION)
	var fire: int = int(SimNeedsMod.make_campfire(w, PLAYER_X + 2.0, PLAYER_Y, true))
	var torch: int = int(Items.spawn_item(w, "item.torch.handheld", {}))
	Inventory.equip(w, int(w.player), torch, "")
	SimLightMod.refresh_carried(w, int(w.player))
	w.step()
	var flame: float = LightLook.source_flicker(w, fire)
	var bulb: float = LightLook.source_flicker(w, int(w.player))
	if not (flame > 0.0 and flame < 0.5) or bulb != 0.0:
		push_error("FLICKER: a campfire flickers %f and a cell torch %f -- want a small positive and zero" % [flame, bulb])
		return false
	var shader_src: String = FileAccess.get_file_as_string("res://presentation/night_light.gdshader")
	if not shader_src.contains("float flick = 1.0 - src.w * (0.5 + 0.5 *"):
		push_error("FLICKER: the shader's flicker is no longer a dip below the sim's reach")
		return false
	print("FLICKER OK a campfire dips by up to %.0f%% of its reach, a cell torch is steady" % (flame * 100.0))
	return true


# WINDOW. A campfire inside a room lights, through a row of windows, what lies beyond: the sim's
# shadowcast lights the first opaque tile it meets, so a screen of undergrowth behind the glass is
# in the fire's cast and in the survivor's sight. Its picture is solid and reads as the wall going
# on, so the screen must not light it -- light passes a window onto the floor beyond, not onto
# masonry (art review 3). The true positives: the floor seen through the same glass keeps its bit,
# the room-side face of the wall keeps its bit, and a screen tile with that lit floor beside it
# keeps its bit -- so a builder that dropped every opaque tile, or every tile past the glass, fails.
# Deep water is solid but clear: the middle of a pond, with only water round it, keeps its bit too.
func _a_window_lights_the_floor_beyond_not_the_masonry() -> bool:
	var f: Dictionary = {
		"seed": 4141,
		"tick_hz": 20,
		"map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []},
		"player": {"id": 0, "x": PLAYER_X, "y": PLAYER_Y, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(NIGHT_FRACTION)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	for y in range(0, MAP_TILES):
		map.tiles[y * MAP_TILES + WALL_X] = SimTileMap.Tile.Window if y >= 10 and y <= 14 else SimTileMap.Tile.Wall
	for y in range(9, 13):
		map.tiles[y * MAP_TILES + WALL_X + 1] = SimTileMap.Tile.Screen
	for y in range(14, 17):
		for x in range(6, 9):
			map.tiles[y * MAP_TILES + x] = SimTileMap.Tile.Water
	SimBoot.attach_kernel(w, map)
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.content = ContentLoader.load_tree("res://content")
	_emitter(w, 10.5, 12.5, CAMPFIRE_M)
	w.step()
	var cast: Variant = w.light.tiles_for(int(w.light.sources_list()[0]))
	var seen: Variant = w.vision.tiles_for(int(w.player))
	var masked: Vector2i = Vector2i(WALL_X + 1, 11)
	var floor_beyond: Vector2i = Vector2i(WALL_X + 1, 14)
	var screen_by_floor: Vector2i = Vector2i(WALL_X + 1, 12)
	var wall_face: Vector2i = Vector2i(WALL_X, 9)
	var water_middle: Vector2i = Vector2i(7, 15)
	for t in [masked, floor_beyond, screen_by_floor, wall_face, water_middle]:
		var at: Vector2i = t as Vector2i
		if not bool((cast as Object).call("has_tile", at.x, at.y)) or not bool((seen as Object).call("has_tile", at.x, at.y)):
			push_error("WINDOW: (%d, %d) is not lit and seen in the sim -- the lane has nothing to judge there" % [at.x, at.y])
			return false
	var texels: Dictionary = LightLook.light_texels(w, int(w.player), _view())
	var t_masked: PackedByteArray = _texel(texels, masked.x, masked.y)
	if t_masked[0] != 255 or (t_masked[1] | t_masked[2] | t_masked[3]) != 0:
		push_error("WINDOW: the screen behind the glass at (%d, %d) carries the fire's bit (bytes %s) -- light lands on masonry past a window" % [masked.x, masked.y, str(t_masked)])
		return false
	for t in [floor_beyond, screen_by_floor, wall_face, water_middle]:
		var at: Vector2i = t as Vector2i
		var b: PackedByteArray = _texel(texels, at.x, at.y)
		if b[0] != 255 or (b[1] & 1) != 1:
			push_error("WINDOW: (%d, %d) lost the fire's bit (bytes %s) -- the refusal took a tile it should keep" % [at.x, at.y, str(b)])
			return false
	print("WINDOW OK the screen behind the glass at (%d, %d) is lit and seen in the sim and carries no source bit; the floor beyond the same glass, the wall's room-side face, a screen beside that lit floor and the middle of a pond keep theirs" % [masked.x, masked.y])
	return true


func _draw_uses_source_tint(body: String) -> bool:
	var group_tint: String = "var tint: Color = group.get(\"tint\", Palette.LIGHT_POOL_RGB) as Color"
	var draw_tint: String = "_fill_pool_tiles(group[\"tiles\"] as Array, LightLook.pool_colour(tint, near_pool, overlay))"
	var group_at: int = body.find("for group_value in (pools[\"coloured\"] as Dictionary).values()")
	var tint_at: int = body.find(group_tint, group_at)
	var paint_at: int = body.find("LightLook.pool_colour(tint, near_pool, overlay)", tint_at)
	var draw_at: int = body.find(draw_tint, tint_at)
	return group_at >= 0 and tint_at > group_at and paint_at > tint_at and draw_at > tint_at and paint_at < draw_at + draw_tint.length()


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
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out

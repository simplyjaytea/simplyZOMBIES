extends SceneTree
# Water: one tile, one surface, and the six places that had to agree about it.
#
# docs/24's ground rule is "two arrays, never one enum" -- what is *in* a tile and what is
# *under* it are separate stories -- so a river costs exactly one new tile and one new surface
# rather than four combinations of blue:
#
#   deep water    Tile.Water  (SOLID, Opacity.Clear)  on  Surface.Water
#   a ford        Tile.Floor                          on  Surface.Water
#
# The deep tile carries precisely the pair `Tile.Window` already carried, which is the whole
# reason nothing in the pathfinder or the shadowcast needed touching: a river stops a body and
# not a sightline. The ford is an ordinary floor, so it walks -- slowly and loudly, through the
# surface table -- and that difference is the mechanic. You can be dry or you can be quiet.
#
# Six lanes, each with a true positive and a true negative, because a gate that cannot fail is
# worse than no gate:
#
#   TILE    the enum's two parallel arrays grew with it, and `is_solid` / `opacity_at` answer
#           over a real map. TN: a Floor beside the water is neither solid nor opaque, so the
#           lane is reading the tile and not the map.
#   FOOT    deep water refuses a foot and a ford accepts one, through the *same*
#           `SimPath.walkable_tile` and `walkable` the worldgen survivability pass uses -- so
#           the two answers cannot drift. TN: the ford, on the same surface, must walk; that is
#           what proves the refusal is about the tile rather than about the water underneath.
#   SEE     water is transparent: an observer sees the tile beyond a channel, and does not see
#           the tile beyond a wall in the identical geometry. TN: the wall arm, which is the
#           only thing that makes the water arm mean anything.
#   GROUND  the surface table's sixth entry, and the dead-socket assertion that something
#           *reads* it -- `world.surface_speed_at` over a placed ford, not `SPEED[5]` read back
#           to itself. Water is the slowest and the loudest ground in the game. TN: pavement
#           through the same call reads 1.0.
#   ROWS    the collision lane. `Appearance.ground_row_for` returns a *surface int as an atlas
#           row*, so the two painted rows have to sit after the last surface: before water
#           pushed them up, Surface.Water (5) collided with GroundRow.Sidewalk (5) and a river
#           drew as pavement with every gate green. TN: a sidewalk-masked tile still answers
#           Sidewalk, so the re-index did not simply shift the bug along.
#   DRAW    the draw path reaches water. `main.gd` matches on the tile class **twice** -- once
#           for a colour and once to draw -- and CLAUDE.md records a gate that read the wrong
#           arm and blamed correct code, so this enumerates both and requires the water arm in
#           each, plus the ground-rows exclusion that keeps the fringe pass out of the channel.
#
# What this gate deliberately does NOT do, named so the next session does not think it was
# missed: it does not assert `tools/sprites/palette.py`'s hard copy of the surface tints agrees
# with `Palette.SURFACE_TINTS`. GDScript cannot import Python, and it does not need to --
# `check_road_look.gd`'s CELLS lane decodes every atlas cell and requires it to average its
# GDScript palette tint, so a Python copy that disagreed would render a row that fails there.
# The drift is already caught, one layer down, by the gate that owns the pixels.
#
# It also does not judge a *generated* river: there is no worldgen water pass yet. That is the
# next slice, and its lanes belong to it.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimPath = preload("res://sim/path.gd")
const Shadowcast = preload("res://sim/vision/shadowcast.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Palette = preload("res://presentation/palette.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const MAIN_PATH: String = "res://presentation/main.gd"

# A gate that boots a world has a budget, the way check_worldgen.gd carries one: this one boots
# two small worlds and reads two files, so it is cheap and must stay cheap.
const BUDGET_SECONDS: float = 90.0

# The shipped district that declares water, and the two that do not. A river through the woods is
# where water belongs, and having a real reader is the point: a `water` block nothing shipped
# declared would be the thirteenth dead socket rather than a mechanism.
const WET_DISTRICT: String = "district.forest_edge"
const DRY_DISTRICTS: Array[String] = ["district.residential_suburb", "district.town_center"]

# Seeds and sizes for the generated-water lanes. Below `SimWorldgen.WATER_MIN_SIZE` the pass
# declines entirely, so every size here is above it on purpose.
const SEEDS: Array[int] = [20260805, 90210, 1337, 4242]
const SIZES: Array[int] = [64, 128]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true

	ok = _the_tile_is_solid_and_clear() and ok
	ok = _deep_water_refuses_a_foot_and_a_ford_accepts_one() and ok
	ok = _a_channel_does_not_block_a_sightline_and_a_wall_does() and ok
	ok = _the_ford_is_the_slowest_and_loudest_ground_and_something_reads_it() and ok
	ok = _the_atlas_row_is_the_surface_and_not_the_sidewalk() and ok
	ok = _the_draw_path_reaches_water_in_both_of_its_two_matches() and ok
	ok = _the_generator_carves_water_only_where_content_declares_it() and ok
	ok = _a_generated_river_never_leaves_ground_stranded() and ok
	ok = _the_dressing_cannot_gravel_a_ford_or_wear_a_track_down_one() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("BUDGET: %.1f s over the %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print("WATER_OK deep water is solid and clear (the Window pair) and refuses a foot while the ford on the same surface walks; a sightline crosses a channel and not a wall; the ford reads x%.2f speed and x%.2f noise through the world's own path -- the slowest and loudest ground there is; the atlas row is the water row and not the sidewalk's; both of main.gd's tile matches carry a water arm and the fringe pass stays out of the channel; the generator carves water only where content declares it and never leaves ground stranded on %d seeds x %d sizes, and the dressing can neither gravel a ford nor wear a track down one; %.1f s of a %.0f s budget" % [
			SimSurface.SPEED[SimSurface.Surface.Water],
			SimSurface.NOISE[SimSurface.Surface.Water],
			SEEDS.size(), SIZES.size(),
			seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("WATER_FAIL")
		quit(1)


# A small hand-built map: a vertical channel at column 4 with a ford at row 2, pavement either
# side. Everything below is measured on this rather than on a generated district, because there
# is no generator pass yet and a fixture says exactly what it contains.
func _fixture() -> Variant:
	var map: Variant = SimTileMap.blank_map(9, 9)
	for y in 9:
		_put(map, 4, y, SimTileMap.Tile.Water, SimTileMap.SURFACE_WATER)
	# The ford: the channel's own surface, but an ordinary floor on top of it.
	_put(map, 4, 2, SimTileMap.Tile.Floor, SimTileMap.SURFACE_WATER)
	return map


func _put(map: Variant, tx: int, ty: int, tile: int, surface: int) -> void:
	var idx: int = ty * int(map.w) + tx
	map.tiles[idx] = tile
	map.surfaces[idx] = surface


# 1. TILE: the two parallel arrays grew, and the accessors answer over a real map.
func _the_tile_is_solid_and_clear() -> bool:
	if SimTileMap.OPACITY.size() != SimTileMap.SOLID.size():
		push_error("TILE: OPACITY has %d entries and SOLID %d; the two tables must describe the same enum" % [SimTileMap.OPACITY.size(), SimTileMap.SOLID.size()])
		return false
	# Every enum value must be addressable in both. `Tile.Water` is the highest, so its index is
	# what the sizes have to cover -- an enum grown without the tables is the failure here.
	if SimTileMap.SOLID.size() <= SimTileMap.Tile.Water:
		push_error("TILE: Tile.Water is %d but the tables hold %d entries; the enum grew and the tables did not" % [SimTileMap.Tile.Water, SimTileMap.SOLID.size()])
		return false
	if not SimTileMap.SOLID[SimTileMap.Tile.Water]:
		push_error("TILE: Tile.Water is not SOLID; a river you can walk into is not a river")
		return false
	if SimTileMap.OPACITY[SimTileMap.Tile.Water] != SimTileMap.Opacity.Clear:
		push_error("TILE: Tile.Water is not Opacity.Clear; it must stop a body and not a sightline, which is the pair Window carries")
		return false

	var map: Variant = _fixture()
	if not SimTileMap.is_solid(map, 4, 0):
		push_error("TILE: the channel tile at (4,0) does not read solid through is_solid over a real map")
		return false
	if SimTileMap.opacity_at(map, 4, 0) != SimTileMap.Opacity.Clear:
		push_error("TILE: the channel tile at (4,0) does not read Clear through opacity_at over a real map")
		return false
	# The true negative: the bank beside it, so the lane is reading the tile rather than the map.
	if SimTileMap.is_solid(map, 3, 0):
		push_error("TILE: the bank at (3,0) reads solid; this lane is judging the map, not the tile")
		return false
	return true


# 2. FOOT: the channel refuses a foot, the ford takes one, through the same two functions the
# worldgen survivability pass and the live pathfinder both use.
func _deep_water_refuses_a_foot_and_a_ford_accepts_one() -> bool:
	var map: Variant = _fixture()
	if SimPath.walkable_tile(map, 4, 0):
		push_error("FOOT: walkable_tile says the deep channel at (4,0) is ground")
		return false
	# The true negative, and the more important half: the ford is on the *same surface* and must
	# walk. If this failed, the refusal above would be about the water underneath rather than
	# about the tile, and a river would have no crossings at all.
	if not SimPath.walkable_tile(map, 4, 2):
		push_error("FOOT: walkable_tile refuses the ford at (4,2); a Floor on the water surface has to be crossable or a river cannot be forded")
		return false

	# And the same answers through a booted world, so the two paths cannot drift: `walkable`
	# reads world.is_blocked_tile (the kernel's map_cells) and `walkable_tile` reads the map.
	var boot: Dictionary = SimBoot.bare(20260805, 64)
	var world: Variant = boot["world"]
	var wmap: Variant = boot["map"]
	_put(wmap, 10, 10, SimTileMap.Tile.Water, SimTileMap.SURFACE_WATER)
	_put(wmap, 11, 10, SimTileMap.Tile.Floor, SimTileMap.SURFACE_WATER)
	world.adopt_map(wmap)
	if SimPath.walkable(world, 10, 10):
		push_error("FOOT: a booted world walks onto deep water at (10,10); the kernel and the map disagree about it")
		return false
	if not SimPath.walkable(world, 11, 10):
		push_error("FOOT: a booted world refuses the ford at (11,10)")
		return false
	if not world.is_blocked_tile(10, 10):
		push_error("FOOT: world.is_blocked_tile is false on deep water; adopt_map did not carry SOLID into map_cells")
		return false
	return true


# 3. SEE: transparency, measured both ways in one geometry.
#
# Driven through `Shadowcast.shadowcast` -- the function `SimVisibility.refresh` actually calls --
# rather than through a booted world, so the lane reads the production sight rule with nothing
# between it and the answer. The rule itself is `SimTileMap.blocks_sight`, which is the only
# reader of the OPACITY table, so this is also the dead-socket assertion for the tile's opacity.
func _a_channel_does_not_block_a_sightline_and_a_wall_does() -> bool:
	# The rule first, on the tile alone.
	if SimTileMap.blocks_sight(_fixture(), 4, 0, SimTileMap.Eye.Standing):
		push_error("SEE: blocks_sight says the channel at (4,0) stops a sightline; Opacity.Clear must not")
		return false
	if SimTileMap.blocks_sight(_fixture(), 4, 0, SimTileMap.Eye.Crouched):
		push_error("SEE: blocks_sight stops a *crouched* sightline at the channel; water is Clear, not Low")
		return false

	# Then the cast, in one geometry, twice: a channel and a wall three tiles out, and the tile
	# five tiles out that only one of them may hide.
	var eye: Vector2i = Vector2i(1, 4)
	var behind: Vector2i = Vector2i(6, 4)
	var at: Vector2i = Vector2i(4, 4)
	var through_water: bool = _casts_past(at, SimTileMap.Tile.Water, eye, behind)
	var through_wall: bool = _casts_past(at, SimTileMap.Tile.Wall, eye, behind)
	if not through_water:
		push_error("SEE: a cast from %s cannot reach %s past a water tile at %s" % [str(eye), str(behind), str(at)])
		return false
	# The true negative: the same geometry with a wall. Without it the lane would pass on a cast
	# that simply marks everything.
	if through_wall:
		push_error("SEE: the same cast reaches %s past a *wall*, so the water arm proves nothing about transparency" % str(behind))
		return false
	return true


# Stands `obstacle` at `at` on an otherwise open 9x9 and answers whether a cast from `eye` marks
# `behind`. A fresh map each call, so the two arms cannot contaminate each other.
func _casts_past(at: Vector2i, obstacle: int, eye: Vector2i, behind: Vector2i) -> bool:
	var map: Variant = SimTileMap.blank_map(9, 9)
	_put(map, at.x, at.y, obstacle, SimTileMap.SURFACE_PAVED)
	var out: Variant = Shadowcast.VisibleTiles.new()
	Shadowcast.shadowcast(map, eye.x, eye.y, 8, out, SimTileMap.Eye.Standing)
	return out.has_tile(behind.x, behind.y)


# 4. GROUND: the sixth surface, and something that reads it.
func _the_ford_is_the_slowest_and_loudest_ground_and_something_reads_it() -> bool:
	if SimSurface.SPEED.size() != SimSurface.NOISE.size():
		push_error("GROUND: SPEED has %d entries and NOISE %d" % [SimSurface.SPEED.size(), SimSurface.NOISE.size()])
		return false
	if SimSurface.SPEED.size() != Palette.SURFACE_TINTS.size():
		push_error("GROUND: SPEED has %d entries and SURFACE_TINTS %d; a surface the sim knows and the screen cannot draw is half a surface" % [SimSurface.SPEED.size(), Palette.SURFACE_TINTS.size()])
		return false
	var w: int = SimSurface.Surface.Water
	for s in SimSurface.SPEED.size():
		if s == w:
			continue
		if SimSurface.SPEED[w] >= SimSurface.SPEED[s]:
			push_error("GROUND: water is x%.2f speed against %d's x%.2f; wading has to be the slowest ground there is" % [SimSurface.SPEED[w], s, SimSurface.SPEED[s]])
			return false
		if SimSurface.NOISE[w] <= SimSurface.NOISE[s]:
			push_error("GROUND: water is x%.2f noise against %d's x%.2f; splashing has to be the loudest ground there is" % [SimSurface.NOISE[w], s, SimSurface.NOISE[s]])
			return false

	# The dead-socket half: a placed ford read through the world's own speed path, not through
	# SPEED[5] handed back to itself. This is the same shape check_road_look.gd uses for rubble.
	var boot: Dictionary = SimBoot.bare(20260805, 64)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	_put(map, 12, 12, SimTileMap.Tile.Floor, SimTileMap.SURFACE_WATER)
	_put(map, 13, 12, SimTileMap.Tile.Floor, SimTileMap.SURFACE_PAVED)
	world.adopt_map(map)
	var wet: float = world.surface_speed_at(12.5, 12.5)
	if absf(wet - SimSurface.SPEED[w]) > 0.000001:
		push_error("GROUND: a placed ford reads x%.4f through world.surface_speed_at, not the table's x%.2f; nothing reads the new surface" % [wet, SimSurface.SPEED[w]])
		return false
	# The true negative: pavement through the same call, so the lane is reading the tile it
	# placed rather than returning one number for everything.
	var dry: float = world.surface_speed_at(13.5, 12.5)
	if absf(dry - 1.0) > 0.000001:
		push_error("GROUND: pavement reads x%.4f through the same call, not x1.0; the reader is not surface-sensitive" % dry)
		return false
	return true


# 5. ROWS: the collision that made a river draw as pavement.
func _the_atlas_row_is_the_surface_and_not_the_sidewalk() -> bool:
	# The first `Surface` values must *be* the first `GroundRow` values, because ground_row_for
	# returns one as the other. This is the assertion that would have caught the collision.
	if Appearance.GroundRow.Water != SimSurface.Surface.Water:
		push_error("ROWS: GroundRow.Water is %d and Surface.Water is %d; ground_row_for returns a surface int as a row, so the two enums have to agree" % [Appearance.GroundRow.Water, SimSurface.Surface.Water])
		return false
	if Appearance.GroundRow.Sidewalk < SimSurface.SPEED.size() or Appearance.GroundRow.Boards < SimSurface.SPEED.size():
		push_error("ROWS: the painted rows (Sidewalk %d, Boards %d) sit inside the %d surface rows; a surface would draw as a paint" % [Appearance.GroundRow.Sidewalk, Appearance.GroundRow.Boards, SimSurface.SPEED.size()])
		return false
	if Appearance.GROUND_ROWS != SimSurface.SPEED.size() + 2:
		push_error("ROWS: GROUND_ROWS is %d, not the %d surfaces plus the two paints" % [Appearance.GROUND_ROWS, SimSurface.SPEED.size()])
		return false

	var map: Variant = _fixture()
	var row: int = Appearance.ground_row_for(map, 4, 2, false)
	if row != Appearance.GroundRow.Water:
		push_error("ROWS: the ford at (4,2) draws row %d (%s), not the water row %d" % [row, "Sidewalk" if row == Appearance.GroundRow.Sidewalk else "another", Appearance.GroundRow.Water])
		return false
	var tint: Color = Appearance.ground_row_tint(Appearance.GroundRow.Water)
	if not tint.is_equal_approx(Palette.COLOURS["water"]):
		push_error("ROWS: the water row's tint is %s, not the palette's water %s -- ground_row_tint is still handing back a paint for this row" % [str(tint), str(Palette.COLOURS["water"])])
		return false
	# The true negative: the sidewalk row still answers the sidewalk, so the re-index moved the
	# paints out of the way rather than shifting the collision onto another surface.
	if Appearance.ground_row_for(map, 3, 0, true) != Appearance.GroundRow.Sidewalk:
		push_error("ROWS: a sidewalk-masked tile no longer answers GroundRow.Sidewalk; the re-index broke the paint substitution it was making room for")
		return false
	if not Appearance.ground_row_tint(Appearance.GroundRow.Sidewalk).is_equal_approx(Palette.COLOURS["sidewalk"]):
		push_error("ROWS: the sidewalk row's tint is no longer the sidewalk paint")
		return false
	return true


# 6. DRAW: both of main.gd's tile matches, enumerated rather than sliced.
#
# `_draw_district` matches on the tile class twice -- once picking a colour, once drawing -- and
# CLAUDE.md records a gate that sliced from the first label, read four lines of colour
# arithmetic, and turned red blaming code that was correct. So this counts the arms instead of
# trusting the first one it finds.
func _the_draw_path_reaches_water_in_both_of_its_two_matches() -> bool:
	var f: FileAccess = FileAccess.open(MAIN_PATH, FileAccess.READ)
	if f == null:
		push_error("DRAW: cannot open %s" % MAIN_PATH)
		return false
	var src: String = f.get_as_text()
	f.close()

	var matches: int = src.count("match tile:")
	if matches != 2:
		push_error("DRAW: main.gd has %d `match tile:` blocks, not the 2 this lane knows how to read; re-read _draw_district before trusting this assertion" % matches)
		return false
	# Each block on its own, sliced between the labels, so neither arm can stand in for the other
	# and neither can be satisfied by a mention somewhere else in the file. `if tile ==
	# SimTileMap.Tile.Water:` in the ground-rows cache is exactly such a mention -- it ends in a
	# colon too, which is why counting the bare needle over the whole file answered 3 and not 2.
	var first: int = src.find("match tile:")
	var second: int = src.find("match tile:", first + 1)
	var blocks: Array[String] = [src.substr(first, second - first), src.substr(second, 4000)]
	var names: Array[String] = ["the colour match", "the draw match"]
	for i in blocks.size():
		if not (blocks[i] as String).contains("SimTileMap.Tile.Water:"):
			push_error("DRAW: %s carries no `SimTileMap.Tile.Water:` arm, so deep water falls through it" % names[i])
			return false
	# And the arm has to *do* something in each: resolve the channel colour in the first, draw it
	# in the second. An empty arm is a socket too.
	if not (blocks[0] as String).contains("WATER_DEEP_SHADE"):
		push_error("DRAW: the colour match's water arm does not derive the channel from WATER_DEEP_SHADE; deep water and the ford would draw the same")
		return false
	if not (blocks[1] as String).contains("draw_rect(rect, col)"):
		push_error("DRAW: the draw match's water arm does not fill the tile; the channel would resolve a colour nothing paints")
		return false
	# The channel must not take the floor's furniture. The fringe pass reads the ground-rows
	# cache, and a water tile left in it would have the ground edges drawing grass into the
	# middle of the river.
	# Anchored on the *assignment*, which occurs once, and not on the first mention of ROW_NONE --
	# that one is a comment 950 lines earlier, and a window taken around it read a paragraph about
	# the cache instead of the branch that fills it. A textual assertion has to be shown it is
	# reading what it thinks it is reading.
	const ROWS_NEEDLE: String = "_ground_rows_cache[i] = Appearance.ROW_NONE"
	if src.count(ROWS_NEEDLE) != 1:
		push_error("DRAW: `%s` appears %d times in main.gd, not once; the ground-rows cache moved and this assertion cannot see it" % [ROWS_NEEDLE, src.count(ROWS_NEEDLE)])
		return false
	var rows_line: int = src.find(ROWS_NEEDLE)
	var guard: String = src.substr(maxi(0, rows_line - 400), 400)
	if not guard.contains("SimTileMap.Tile.Water"):
		push_error("DRAW: the ground-rows cache does not exclude Tile.Water, so _draw_ground_edges will fringe grass into the channel")
		return false
	return true


# 7. GENERATOR: water lands where content asks for it, and nowhere else.
#
# The dry half is the one that matters for everything already shipped: a district with no `water`
# block must generate the map it always did, because the pass takes **no draw at all** when the
# block is absent. That is what let this land without moving the balance harness, and it is
# asserted rather than claimed.
func _the_generator_carves_water_only_where_content_declares_it() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	for district in DRY_DISTRICTS:
		for size in SIZES:
			var map: Variant = SimWorldgen.generate(20260805, size, tree, district)
			var wet: int = _water_tiles(map)
			if wet != 0:
				push_error("GENERATOR: %s at %d carries %d water tiles and declares no water block" % [district, size, wet])
				return false
	# And the true positive: the district that *does* declare it gets both halves, deep and
	# shallow. Shallow matters on its own -- a river with no bank is a river with no ford.
	for size2 in SIZES:
		var wetmap: Variant = SimWorldgen.generate(20260805, size2, tree, WET_DISTRICT)
		var deep: int = 0
		var shallow: int = 0
		for i in wetmap.tiles.size():
			if int(wetmap.tiles[i]) == SimTileMap.Tile.Water:
				deep += 1
			elif int(wetmap.surfaces[i]) == SimTileMap.SURFACE_WATER:
				shallow += 1
		if deep < 1 or shallow < 1:
			push_error("GENERATOR: %s at %d carved %d deep and %d shallow tiles; it declares a river and a lake" % [WET_DISTRICT, size2, deep, shallow])
			return false
	# The layout half of the dressing-independence property, for water specifically: the pass is
	# layout, so switching the dressing off must not change one water tile.
	var dressed: Variant = SimWorldgen.generate(20260805, 128, tree, WET_DISTRICT, true)
	var bare: Variant = SimWorldgen.generate(20260805, 128, tree, WET_DISTRICT, false)
	if _water_mask(dressed) != _water_mask(bare):
		push_error("GENERATOR: the dressing moved the water; the pass is layout and must be identical with dress=false")
		return false
	return true


# 8. STRANDED: the guarantee. No seed, at any size, may leave ground the water holds apart.
#
# This is the lane the repair loop exists for: one forced ford at the midpoint passed three seeds
# and failed the fourth, where a lake sat against the river's bend and cut off a corner no single
# line reached. Four seeds and two sizes, and the clause must be *answered* on every one of them
# rather than skipped.
func _a_generated_river_never_leaves_ground_stranded() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	for seed_val in SEEDS:
		for size in SIZES:
			var map: Variant = SimWorldgen.generate(seed_val, size, tree, WET_DISTRICT)
			var report: Dictionary = SimWorldgen.survivability_report(map)
			var clause: Dictionary = SimWorldgen.clause_of(report, "water-crossable")
			if clause.is_empty():
				push_error("STRANDED: seed %d at %d produced no water-crossable clause" % [seed_val, size])
				return false
			if bool(clause.get("skipped", false)):
				push_error("STRANDED: seed %d at %d skipped water-crossable on a district carrying %d water tiles" % [seed_val, size, _water_tiles(map)])
				return false
			if not bool(clause.get("ok", false)):
				push_error("STRANDED: seed %d at %d left ground stranded: %s" % [seed_val, size, String(clause.get("said", ""))])
				return false
			if not bool(report["ok"]):
				push_error("STRANDED: seed %d at %d is not survivable: %s" % [seed_val, size, str(report["failed"])])
				return false
	# The true negative, and the one that makes this lane mean anything: dam every crossing on a
	# real generated map and the clause must say so. Without it the lane would pass on a clause
	# that answered true unconditionally.
	var sabotage: Variant = SimWorldgen.generate(20260805, 128, tree, WET_DISTRICT)
	if not bool(SimWorldgen.clause_of(SimWorldgen.survivability_report(sabotage), "water-crossable").get("ok", false)):
		push_error("STRANDED: the map chosen to sabotage was already failing, so the negative proves nothing")
		return false
	var w: int = int(sabotage.w)
	var dammed: int = 0
	for i in sabotage.tiles.size():
		# Every ford and bank -- a Floor standing on water -- becomes channel, which seals every
		# crossing the pass laid without touching anything else on the map.
		if int(sabotage.tiles[i]) == SimTileMap.Tile.Floor and int(sabotage.surfaces[i]) == SimTileMap.SURFACE_WATER:
			sabotage.tiles[i] = SimTileMap.Tile.Water
			dammed += 1
	if dammed < 1:
		push_error("STRANDED: the sabotage sealed no crossing, so it changed nothing")
		return false
	var after: Dictionary = SimWorldgen.clause_of(SimWorldgen.survivability_report(sabotage), "water-crossable")
	if bool(after.get("ok", true)) or bool(after.get("skipped", false)):
		push_error("STRANDED: sealing %d crossing tiles left water-crossable ok=%s skipped=%s; the clause cannot fail" % [dammed, after.get("ok"), after.get("skipped")])
		return false
	return true


# 9. PROTECTED: the dressing may not repaint a ford.
#
# The deep channel defends itself -- every dressing writer gates on `tiles[idx] == Tile.Floor` and a
# `Tile.Water` is not one. A **ford and a bank are ordinary Floor tiles**, and `_rubble_tile` and
# `_wear` write a *surface* onto a Floor tile without asking which surface is already there. So
# without `_protected_tiles` carrying the water the rubble pass would gravel a river and the paths
# pass would wear a dirt track down the middle of one. Counted before and after the dressing.
func _the_dressing_cannot_gravel_a_ford_or_wear_a_track_down_one() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	for size in SIZES:
		var bare: Variant = SimWorldgen.generate(20260805, size, tree, WET_DISTRICT, false)
		var dressed: Variant = SimWorldgen.generate(20260805, size, tree, WET_DISTRICT, true)
		var before: int = _water_tiles(bare)
		var after: int = _water_tiles(dressed)
		if before != after:
			push_error("PROTECTED: %s at %d carries %d water tiles undressed and %d dressed; the dressing repainted %d of them" % [WET_DISTRICT, size, before, after, before - after])
			return false
		if before < 1:
			push_error("PROTECTED: %s at %d carved no water, so this lane judged nothing" % [WET_DISTRICT, size])
			return false
	return true


# Every tile that is water at all, deep or shallow -- read off the surface, which both halves share.
func _water_tiles(map: Variant) -> int:
	var n: int = 0
	for i in map.surfaces.size():
		if int(map.surfaces[i]) == SimTileMap.SURFACE_WATER:
			n += 1
	return n


# The water as a byte per tile, for comparing two generations: 2 deep, 1 shallow, 0 dry.
func _water_mask(map: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map.tiles.size())
	for i in map.tiles.size():
		if int(map.tiles[i]) == SimTileMap.Tile.Water:
			out[i] = 2
		elif int(map.surfaces[i]) == SimTileMap.SURFACE_WATER:
			out[i] = 1
	return out

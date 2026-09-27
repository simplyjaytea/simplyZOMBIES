# PROTOTYPE -- the walls picture round (docs/30, "The whole outpost pack, 2026-09-25" -> "The
# walls get a picture round first"). A throwaway SceneTree driver, kept here only so the pictures
# beside it can be reproduced. It is NOT game code: nothing under godot/ loads it, no gate reads
# it, and the walls slice must not copy it -- it composes pictures with the Image API, headless,
# and exists to put two looks in front of the owner.
#
# Run from the repository root (the path is absolute because the script lives outside res://):
#   <godot 4.7.1> --headless --path godot --script "$PWD/.hermes/plans/2026-09-27_walls-picture-round/walls_round.gd"
#
# One closed render/plaster building, 7 x 5 tiles, on grass, daylight (no light modulate at all),
# 32 px a tile at 2x = 64 screen px a tile, the same map and the same pixel origin for every
# option. Option B reproduces main.gd's _draw_district arms for Wall / Window / Door tile by tile
# (wall_render_cap / wall_render_face / face_window / face_door, _draw_solid_tile,
# _draw_window_glass, _draw_threshold) with the palette's own constants; option A draws the
# pack's modules, feet on each tile's south edge, north to south.
extends SceneTree

const Palette = preload("res://presentation/palette.gd")
const Appearance = preload("res://presentation/appearance.gd")

const T: int = 64 # screen px per tile (32 native at 2x)
const S: int = 2
const MAP_W: int = 11
const MAP_H: int = 9
const BX0: int = 2
const BY0: int = 2
const BX1: int = 8 # inclusive
const BY1: int = 6 # inclusive

enum K { OUT, FLOOR, WALL, WINDOW, DOOR }

var pack_dir: String = ""
var sprite_dir: String = ""
var out_dir: String = ""
var pack: Dictionary = {}
var atlas: Image = null


func _init() -> void:
	pack_dir = ProjectSettings.globalize_path("res://art/simplyzombies/groups/environment/textures/")
	sprite_dir = ProjectSettings.globalize_path("res://assets/sprites/")
	out_dir = ProjectSettings.globalize_path("res://").path_join("../.hermes/plans/2026-09-27_walls-picture-round/").simplify_path()
	for n in ["wall-plaster", "wall-corner-nw", "wall-corner-ne", "wall-door-closed", "wall-door-open", "wall-window-intact"]:
		pack[n] = _load(pack_dir + n + ".png")
	atlas = _load(sprite_dir + "ground_atlas.png")

	var shots: Dictionary = {}
	shots["a1"] = _render_a(false, false)
	shots["a2"] = _render_a(true, false)
	shots["b"] = _render_b(false)
	shots["a2_open"] = _render_a(true, true)
	shots["b_open"] = _render_b(true)
	_save(shots["a1"], "a1-pack-corners-by-name.png")
	_save(shots["a2"], "a2-pack-corners-by-shape.png")
	_save(shots["b"], "b-generated-faces.png")
	_save(_side_by_side([shots["a1"], shots["a2"], shots["b"]]), "compare-closed-a1-a2-b.png")
	# 1:1 crop of the 2x render: the south-west corner, the west north-south run and the open door.
	var crop := Rect2i((BX0 - 1) * T, (BY0 - 1) * T, 6 * T, 7 * T)
	_save(_side_by_side([shots["a2_open"].get_region(crop), shots["b_open"].get_region(crop)]), "compare-open-door-ns-run-1to1.png")
	print("WALLS_ROUND_DONE ", out_dir)
	quit(0)


func _load(path: String) -> Image:
	var img := Image.new()
	if img.load(path) != OK:
		push_error("cannot load " + path)
		quit(1)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, name: String) -> void:
	img.save_png(out_dir.path_join(name))


# --- the map ---------------------------------------------------------------------------------

func _kind(tx: int, ty: int) -> int:
	if tx < BX0 or tx > BX1 or ty < BY0 or ty > BY1:
		return K.OUT
	if tx > BX0 and tx < BX1 and ty > BY0 and ty < BY1:
		return K.FLOOR
	if ty == BY1 and (tx == 4 or tx == 6):
		return K.WINDOW # two windows in the south face
	if ty == BY1 and tx == 5:
		return K.DOOR # the door in the south face
	if tx == BX1 and ty == 4:
		return K.WINDOW # a window in the east (north-south) run: the pack has no piece for it
	return K.WALL


func _solid(tx: int, ty: int) -> bool:
	return _kind(tx, ty) == K.WALL


func _is_wallish(tx: int, ty: int) -> bool:
	var k: int = _kind(tx, ty)
	return k == K.WALL or k == K.WINDOW or k == K.DOOR


# --- the ground, shared by every option --------------------------------------------------------

func _cell(row: int, variant: int, flat: Color, base: Color) -> Image:
	var c: Image = atlas.get_region(Rect2i(variant * 32, row * 32, 32, 32))
	var m: Color = Appearance.ground_modulate(flat, base)
	for y in 32:
		for x in 32:
			var p: Color = c.get_pixel(x, y)
			c.set_pixel(x, y, Color(p.r * m.r, p.g * m.g, p.b * m.b, p.a))
	c.resize(T, T, Image.INTERPOLATE_NEAREST)
	return c


func _ground(img: Image) -> void:
	var grass_tint: Color = Palette.SURFACE_TINTS[Appearance.GroundRow.Grass]
	var boards_col: Color = (Palette.SURFACE_TINTS[Appearance.GroundRow.Paved] as Color).lerp(Palette.COLOURS["indoorFloor"], Palette.INDOOR_MIX)
	var boards_tint: Color = Appearance.ground_row_tint(Appearance.GroundRow.Boards)
	for ty in MAP_H:
		for tx in MAP_W:
			var v: int = (tx * 7 + ty * 3) % Appearance.GROUND_VARIANTS
			var inside: bool = tx >= BX0 and tx <= BX1 and ty >= BY0 and ty <= BY1 and _kind(tx, ty) != K.DOOR
			var cell: Image
			if inside:
				cell = _cell(Appearance.GroundRow.Boards, v, boards_col, boards_tint)
			else:
				cell = _cell(Appearance.GroundRow.Grass, v, grass_tint, grass_tint)
			img.blit_rect(cell, Rect2i(0, 0, T, T), Vector2i(tx * T, ty * T))


func _canvas() -> Image:
	var img := Image.create(MAP_W * T, MAP_H * T, false, Image.FORMAT_RGBA8)
	_ground(img)
	return img


# --- option B: today's generated faces, main.gd's arms reproduced ------------------------------

func _tex(key: String) -> Image:
	var i: Image = _load(sprite_dir + key + ".png")
	i.resize(T, T, Image.INTERPOLATE_NEAREST)
	return i


func _solid_tile(img: Image, r: Rect2i, col: Color, tx: int, ty: int) -> void:
	img.fill_rect(r, col.darkened(Palette.WALL_CAP_DARKEN))
	var b: int = int(roundf(maxf(2.0, float(T) * Palette.WALL_FACE_SHARE)))
	var light: Color = col.lightened(Palette.WALL_FACE_LIT)
	var dim: Color = col.lightened(Palette.WALL_FACE_DIM)
	if not _solid(tx, ty - 1):
		img.fill_rect(Rect2i(r.position, Vector2i(T, b)), light)
	if not _solid(tx - 1, ty):
		img.fill_rect(Rect2i(r.position, Vector2i(b, T)), light)
	if not _solid(tx, ty + 1):
		img.fill_rect(Rect2i(r.position + Vector2i(0, T - b), Vector2i(T, b)), dim)
	if not _solid(tx + 1, ty):
		img.fill_rect(Rect2i(r.position + Vector2i(T - b, 0), Vector2i(b, T)), dim)


func _outline(img: Image, r: Rect2i, c: Color, w: int) -> void:
	img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, w)), c)
	img.fill_rect(Rect2i(r.position + Vector2i(0, r.size.y - w), Vector2i(r.size.x, w)), c)
	img.fill_rect(Rect2i(r.position, Vector2i(w, r.size.y)), c)
	img.fill_rect(Rect2i(r.position + Vector2i(r.size.x - w, 0), Vector2i(w, r.size.y)), c)


func _window_glass(img: Image, r: Rect2i, tx: int, ty: int) -> void:
	var col: Color = Palette.COLOURS["window"]
	var glass: Color = col.lightened(0.28)
	var horizontal: bool = _solid(tx - 1, ty) and _solid(tx + 1, ty)
	var vertical: bool = _solid(tx, ty - 1) and _solid(tx, ty + 1)
	var c: Vector2 = Vector2(r.position) + Vector2(T, T) / 2.0
	var lng: float = T * 0.75
	var sht: float = T * 0.25
	var pane: Rect2
	if horizontal and not vertical:
		pane = Rect2(c - Vector2(lng / 2.0, sht / 2.0), Vector2(lng, sht))
	elif vertical and not horizontal:
		pane = Rect2(c - Vector2(sht / 2.0, lng / 2.0), Vector2(sht, lng))
	else:
		pane = Rect2(c - Vector2(sht * 0.75, sht * 0.75), Vector2(sht * 1.5, sht * 1.5))
	var pr := Rect2i(pane.position.round(), pane.size.round())
	img.fill_rect(pr, glass)
	_outline(img, pr, Palette.COLOURS["windowRim"], 2)


func _render_b(open_door: bool) -> Image:
	var img: Image = _canvas()
	var cap: Image = _tex("wall_render_cap")
	var face: Image = _tex("wall_render_face")
	var face_window: Image = _tex("face_window")
	var face_door: Image = _tex("face_door")
	var grass_tint: Color = Palette.SURFACE_TINTS[Appearance.GroundRow.Grass]
	for ty in MAP_H:
		for tx in MAP_W:
			var k: int = _kind(tx, ty)
			var r := Rect2i(tx * T, ty * T, T, T)
			# RoofLook.south_open: the tile south is outdoor and not solid.
			var south_open: bool = _kind(tx, ty + 1) == K.OUT
			match k:
				K.WALL:
					img.blend_rect(face if south_open else cap, Rect2i(0, 0, T, T), r.position)
				K.WINDOW:
					img.blend_rect(face if south_open else cap, Rect2i(0, 0, T, T), r.position)
					if south_open:
						img.blend_rect(face_window, Rect2i(0, 0, T, T), r.position)
					else:
						_window_glass(img, r, tx, ty)
				K.DOOR:
					if not open_door:
						_solid_tile(img, r, Palette.COLOURS["door"], tx, ty)
					else:
						# _draw_threshold: boards lerped toward the threshold colour, jambs where a
						# solid neighbour is (none here: windows flank this door), then the face.
						var col: Color = grass_tint.lerp(Palette.COLOURS["threshold"], 0.75)
						var cell: Image = _cell(Appearance.GroundRow.Boards, 0, col, Appearance.ground_row_tint(Appearance.GroundRow.Boards))
						img.blit_rect(cell, Rect2i(0, 0, T, T), r.position)
						img.blend_rect(face_door, Rect2i(0, 0, T, T), r.position)
	return img


# --- option A: the pack's modules, feet on the south edge, north to south ---------------------

# A native crop of a pack piece, doubled.
func _piece(name: String, crop: Rect2i) -> Image:
	var i: Image = (pack[name] as Image).get_region(crop)
	i.resize(crop.size.x * S, crop.size.y * S, Image.INTERPOLATE_NEAREST)
	return i


# Blit a native crop so that native row `pivot_y` of the source lands on the tile's south edge and
# the crop's left edge lands `dx` native px right of the tile's west edge.
func _stamp(img: Image, name: String, crop: Rect2i, pivot_y: int, tx: int, ty: int, dx: int) -> void:
	var p: Image = _piece(name, crop)
	var south: int = (ty + 1) * T
	var y: int = south - (pivot_y - crop.position.y) * S
	img.blend_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i(tx * T + dx * S, y))


# Which 32-wide slice of a 64-wide module a run tile takes: its west end, its east end, or the
# middle (no side outline) -- the "per-tile half piece".
func _slice_x(tx: int) -> int:
	if tx == BX0:
		return 0
	if tx == BX1:
		return 32
	return 16


# The north-south run: the corner piece's leg, cropped. corner-nw's leg is native x 0..16 at the
# tile's west edge; corner-ne's is x 47..63 at the tile's east edge. A band y 8..24 of plain cap is
# repeated down the run. It starts under the north run's cap (native 30 px above the north run's
# south edge, where the module's cap ends) and stops at the south run's cap, which draws over it.
func _leg(img: Image, west: bool, tx: int, y_top: int, y_bottom: int) -> void:
	var name: String = "wall-corner-nw" if west else "wall-corner-ne"
	var crop := Rect2i(0, 8, 17, 16) if west else Rect2i(47, 8, 17, 16)
	var band: Image = _piece(name, crop)
	var x: int = tx * T + (0 if west else (32 - 17) * S)
	var y: int = y_top
	while y < y_bottom:
		var h: int = mini(band.get_height(), y_bottom - y)
		img.blend_rect(band, Rect2i(0, 0, band.get_width(), h), Vector2i(x, y))
		y += h


func _render_a(by_shape: bool, open_door: bool) -> Image:
	var img: Image = _canvas()
	var module_h: int = 44 # the 64x48 modules' pivot: feet at native y 44
	# North run first (row BY0).
	for tx in range(BX0, BX1 + 1):
		if not by_shape and (tx == BX0 or tx == BX0 + 1):
			continue
		if not by_shape and (tx == BX1 or tx == BX1 - 1):
			continue
		_stamp(img, "wall-plaster", Rect2i(_slice_x(tx), 0, 32, 48), module_h, tx, BY0, 0)
	if not by_shape:
		# By name: the pack's north-west and north-east corners at the building's north corners,
		# each 64 wide (two tiles), feet at native y 64.
		_stamp(img, "wall-corner-nw", Rect2i(0, 0, 64, 64), 64, BX0, BY0, 0)
		_stamp(img, "wall-corner-ne", Rect2i(0, 0, 64, 64), 64, BX1 - 1, BY0, 0)
	# The north-south runs, rows BY0+1 .. BY1-1. The leg rises into the north run's face to meet its
	# cap (drawn after the north run, so it covers the face's end). By shape, the south corner piece
	# brings its own leg for the last row, so the cropped leg stops a row sooner.
	var leg_top: int = (BY0 + 1) * T - 30 * S
	var leg_bottom: int = BY1 * T if not by_shape else (BY1 - 1) * T
	if not by_shape:
		leg_top = (BY0 + 1) * T - 22 * S # below the named corner's own cap (native 32..40 of 64)
	_leg(img, true, BX0, leg_top, leg_bottom)
	_leg(img, false, BX1, leg_top, leg_bottom)
	# South run last (row BY1): it sorts in front of everything above it.
	for tx in range(BX0, BX1 + 1):
		if by_shape and (tx == BX0 or tx == BX0 + 1 or tx == BX1 or tx == BX1 - 1):
			continue
		var k: int = _kind(tx, BY1)
		var name: String = "wall-plaster"
		var sx: int = _slice_x(tx)
		if k == K.WINDOW:
			name = "wall-window-intact"
			sx = 16
		elif k == K.DOOR:
			name = "wall-door-open" if open_door else "wall-door-closed"
			sx = 16
		_stamp(img, name, Rect2i(sx, 0, 32, 48), module_h, tx, BY1, 0)
	if by_shape:
		# By shape: the pack's "north-west" piece is a west leg coming down onto a face -- which is
		# what a building's south-west corner looks like from this camera -- and "north-east" the
		# south-east one.
		_stamp(img, "wall-corner-nw", Rect2i(0, 0, 64, 64), 64, BX0, BY1, 0)
		_stamp(img, "wall-corner-ne", Rect2i(0, 0, 64, 64), 64, BX1 - 1, BY1, 0)
	return img


func _side_by_side(imgs: Array) -> Image:
	var gap: int = 16
	var w: int = 0
	var h: int = 0
	for i in imgs:
		w += (i as Image).get_width() + gap
		h = maxi(h, (i as Image).get_height())
	var out := Image.create(w - gap, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.08, 0.08, 0.09))
	var x: int = 0
	for i in imgs:
		out.blit_rect(i, Rect2i(Vector2i.ZERO, (i as Image).get_size()), Vector2i(x, 0))
		x += (i as Image).get_width() + gap
	return out

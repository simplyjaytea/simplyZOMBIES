extends RefCounted
# The marks a fight leaves, drawn (plan item A13; docs/30, "Blood and bullet decals persist, for
# everything"). The sim keeps every mark whether anyone saw it made (sim/modules/decals.gd); this
# file decides only what each looks like and which ones the screen may show.
#
# **Shown only where the player sees now.** A mark draws on a tile in the player's live sight set
# and nowhere else -- not on the remembered map, where a mark made since the player last looked
# would be news they never earned, and never through a wall. The test is the one the floor under
# it is drawn by (`seen.has_tile`), so a mark appears with its tile and goes with it. A mark on a
# wall that stands as a picture in the entity sort (the A2 wall modules) is drawn by that picture's
# own call, after it, so the wall cannot paint over its own bullet hole and a body in front of the
# wall still covers both.
#
# **The pack's art at the pack's density.** Every picture is one of the outpost pack's decal
# frames (`fx-blood-pool-*`, `fx-bullet-hole-*`, `fx-scorch-mark`, `fx-wood-chips`) or its blood
# spray (`fx-blood-hit-*`), drawn at one art pixel to one art pixel -- never scaled, because a
# half-size pool is a pool drawn in pixels half the size of the ground's and the pack's whole read
# is one pixel grid. Variety is the eight turns and flips a square picture has, chosen by the
# record's `v`, and which picture a size or an age takes. The palette is the pack's: a dark, matte
# blood (the fresh pool's core is (74, 5, 10)) that browns as it dries; `godot:check:decals`'s
# MATTE lane holds every blood frame under a brightness ceiling.
#
# **Baked per chunk, bounded per chunk.** The marks lying on the ground are composited once into
# one picture per chunk (CHUNK tiles square, at one art pixel to the texel) and the frame blits
# that picture's seen tiles, a run of them per row, rather than one call per mark. A chunk is
# re-baked only when its own marks change (the sim bumps its `rev`), when a neighbour whose marks
# spill across the border changes, or when one of its marks changes stage (a pool spreading, blood
# drying) -- so a frame asks nothing of a chunk that did not change, and a new mark re-bakes the
# chunk it landed in. A chunk never holds more than SimDecals.PER_CHUNK marks, which bounds a bake.
# Visibility is still the tile's: a baked pixel shows only on a tile in the live sight set, and a
# wall tile's cell is cleared from the bake so blood never paints over a wall cap. Marks a round
# leaves in a wall or a car (WALL_KINDS) stay single draws, because they are drawn on pictures
# that stand in the entity sort.

const SimDecals = preload("res://sim/modules/decals.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Appearance = preload("res://presentation/appearance.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const Clock = preload("res://sim/time/clock.gd")

const ART_PX: int = SimDecals.ART_PX
# A body's pool starts as a splash and spreads to the full pool over this many ticks (five seconds
# at 20 Hz). Project Zomboid's pools appear in a moment and spread a little; this is that.
const POOL_SPREAD_TICKS: int = 100
# Blood browns after a quarter of a day. Rain does not wash it: Zomboid's blood stays until it is
# cleaned, and there is no cleaning yet.
const DRY_TICKS: int = Clock.DAY_TICKS / 4
# Old blood that has no dry picture of its own (a spray, a drop) takes the dry pool's own colours,
# shade for shade by brightness, so it browns in the pack's palette rather than a tint of it.
const DRY_SOURCE: String = "fx_blood_pool_dry"
# The pack's frames carry a faint fringe (alpha 1 to 94) that would darken the ground round every
# mark and mix new shades where marks overlap. A mark is cut hard: a pixel is there or it is not.
const ALPHA_CUT: float = 0.5
# A smear is the pool's own picture laid along the run every SMEAR_STEP_PX art pixels, each copy
# turned and nudged across the run by the record's variant, so the streak's edge is the pool's
# ragged edge and never a straight cut. A run steeper than it is long lays them turned a quarter.
const SMEAR_STEP_PX: int = 12
const SMEAR_SWAY_PX: int = 2
# The spray a blow throws: three of the pack's four hit frames (the fourth is a single drop).
const SPLAT_FRAMES: Array[String] = ["fx_blood_hit_1", "fx_blood_hit_2", "fx_blood_hit_0"]
# A round's hole in a wall drawn flat from above sits this many art pixels down the tile from its
# north edge -- on the face, not on the line the round crossed into the tile.
const HOLE_ROW_PX: int = 14
# Kinds a round leaves: drawn on the wall's face when the wall stands as a picture.
const WALL_KINDS: Array[String] = ["hole", "chips", "dent"]

# Baked chunks held at once. A full chunk's picture is 256 KB; this is what the screen needs at the
# widest zoom with room to walk, and the least recently drawn is let go past it.
const BAKED_MAX: int = 64

# Vector2i chunk -> {rev, until, items, spill}. `until` is the tick the next mark in it changes
# stage; `spill` a bit per neighbour (index (dy + 1) * 3 + dx + 1) its ground marks reach into.
var _cache: Dictionary = {}
# Vector2i chunk -> {sig, until, tex, rows, keys, walls, used, stamp}; `stamp` the world's
# decals_rev when the chunk was last found current.
var _baked: Dictionary = {}
# One mark's picture, cut, turned, flipped and shaded, by everything that decides it.
var _cut: Dictionary = {}
var _world: Variant = null
var _frame: int = 0
# Bakes done, for the gate and the bench.
var bakes: int = 0


func clear() -> void:
	_cache.clear()
	_baked.clear()
	_world = null


# Which picture a mark takes: its kind, its size, how old it is, and its variant.
static func art_for(kind: String, size: int, age: int, variant: int) -> String:
	match kind:
		"splat":
			# By the variant's high bits, so the frame and the turn (its low three) vary apart.
			return SPLAT_FRAMES[(variant >> 3) % SPLAT_FRAMES.size()]
		"drip":
			if size <= 1:
				return "fx_blood_hit_3"
			if size == 2:
				return "fx_blood_hit_0"
			return "fx_blood_pool_dry" if age >= DRY_TICKS else "fx_blood_pool_fresh"
		"smear":
			return "fx_blood_pool_dry" if age >= DRY_TICKS else "fx_blood_pool_fresh"
		"pool":
			if age < POOL_SPREAD_TICKS:
				return "fx_blood_hit_0"
			return "fx_blood_pool_dry" if age >= DRY_TICKS else "fx_blood_pool_fresh"
		"hole":
			return "fx_bullet_hole_concrete"
		"chips":
			return "fx_wood_chips"
		"dent":
			return "fx_bullet_hole_metal"
		"scorch":
			return "fx_scorch_mark"
	return ""


static func _is_blood(kind: String) -> bool:
	return kind in ["splat", "drip", "smear", "pool"]


# The tick after `tick` at which `rec` looks different, or -1.
static func changes_after(rec: Dictionary, tick: int) -> int:
	var k: String = String(rec["k"])
	if not _is_blood(k):
		return -1
	var t: int = int(rec["t"])
	if k == "pool" and tick < t + POOL_SPREAD_TICKS:
		return t + POOL_SPREAD_TICKS
	if tick < t + DRY_TICKS:
		return t + DRY_TICKS
	return -1


# One mark's draw items in art pixels of the world (1/32 m), each {key, texture, region (the part of
# the picture drawn), at (Vector2, its top-left), size (Vector2, on the ground, after any turn),
# transpose, flip (Vector2i), modulate, tile, wall, x, y}.
static func items_for(world: Variant, rec: Dictionary, tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind: String = String(rec["k"])
	var age: int = tick - int(rec["t"])
	var v: int = int(rec.get("v", 0))
	var key: String = art_for(kind, int(rec.get("s", 1)), age, v)
	var texture: Texture2D = Appearance.resolve(key)
	if texture == null:
		return out
	var full := Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	var dry: bool = _is_blood(kind) and age >= DRY_TICKS and not key.begins_with("fx_blood_pool")
	var mod: Color = Color.WHITE
	var x: int = int(rec["x"])
	var y: int = int(rec["y"])
	var tile := Vector2i(floori(float(x) / ART_PX), floori(float(y) / ART_PX))
	var wall: bool = WALL_KINDS.has(kind)
	if kind == "smear":
		var run := Vector2(float(rec.get("a", 0)), float(rec.get("b", 0)))
		var steep: bool = absf(run.y) > absf(run.x)
		var size: Vector2 = full.size
		var across: Vector2 = Vector2(1, 0) if steep else Vector2(0, 1)
		var steps: int = maxi(1, int(run.length()) / SMEAR_STEP_PX)
		for i in range(steps + 1):
			var f: float = float(i) / float(steps)
			var turn_i: int = (v * 5 + i * 3) & 7
			var sway: int = (v * 7 + i * 5) % (SMEAR_SWAY_PX * 2 + 1) - SMEAR_SWAY_PX
			var p := Vector2i(roundi(float(x) - run.x * (1.0 - f) + across.x * sway), roundi(float(y) - run.y * (1.0 - f) + across.y * sway))
			var fl := Vector2i(-1 if (turn_i & 2) != 0 else 1, -1 if (turn_i & 4) != 0 else 1)
			out.append({"key": key, "texture": texture, "region": full, "at": Vector2(p) - size * 0.5, "size": size,
				"mirror": Vector2(size.x * fl.x, size.y * fl.y),
				"transpose": steep, "flip": fl, "modulate": mod, "dry": false,
				"tile": Vector2i(floori(float(p.x) / ART_PX), floori(float(p.y) / ART_PX)), "wall": false, "x": p.x, "y": p.y, "t": int(rec["t"])})
		return out
	if kind == "hole" or kind == "dent":
		# On the face of the tile the round struck, a little up or down by its variant so a burst
		# reads as a group rather than a row.
		y = tile.y * ART_PX + HOLE_ROW_PX + (v % 5) - 2
	var turn: int = v & 7
	var mirror := Vector2(-full.size.x if (turn & 2) != 0 else full.size.x, -full.size.y if (turn & 4) != 0 else full.size.y)
	out.append({"key": key, "texture": texture, "region": full, "at": Vector2(x, y) - full.size * 0.5, "size": full.size, "mirror": mirror,
		"transpose": (turn & 1) == 1, "flip": Vector2i(-1 if (turn & 2) != 0 else 1, -1 if (turn & 4) != 0 else 1),
		"modulate": mod, "dry": dry, "tile": tile, "wall": wall, "x": x, "y": y, "t": int(rec["t"])})
	return out


# A chunk's draw items, from the cache while its records and their stages stand still.
func chunk_items(world: Variant, cx: int, cy: int) -> Array:
	return _entry(world, cx, cy)["items"] as Array


func _entry(world: Variant, cx: int, cy: int) -> Dictionary:
	if world != _world:
		_cache.clear()
		_baked.clear()
		_world = world
	var at := Vector2i(cx, cy)
	var rev: int = SimDecals.rev_of(world, cx, cy)
	var tick: int = int(world.tick)
	var hit: Variant = _cache.get(at)
	if hit is Dictionary and int((hit as Dictionary)["rev"]) == rev:
		var until: int = int((hit as Dictionary)["until"])
		if until < 0 or tick < until:
			return hit as Dictionary
	var items: Array = []
	var until2: int = -1
	for r in SimDecals.in_chunk(world, cx, cy):
		var rec: Dictionary = r as Dictionary
		items.append_array(items_for(world, rec, tick))
		var c: int = changes_after(rec, tick)
		if c >= 0 and (until2 < 0 or c < until2):
			until2 = c
	# Its ground marks sorted by the neighbours they reach into, so a bake takes from each of its
	# eight neighbours only the marks that cross its border: `reach[i]` for neighbour index
	# (dy + 1) * 3 + dx + 1, and `reach[4]` every ground mark of its own.
	var side: int = SimDecals.CHUNK * ART_PX
	var spill: int = 0
	var reach: Array = []
	for i in 9:
		reach.append([])
	var walls: Array = []
	for it in items:
		var d: Dictionary = it as Dictionary
		if bool(d["wall"]):
			walls.append(d)
			continue
		var r2 := Rect2(d["at"] as Vector2, d["size"] as Vector2)
		var lo := Vector2i(floori(r2.position.x / side), floori(r2.position.y / side))
		var hi := Vector2i(floori((r2.end.x - 0.001) / side), floori((r2.end.y - 0.001) / side))
		for ny in range(maxi(lo.y, cy - 1), mini(hi.y, cy + 1) + 1):
			for nx in range(maxi(lo.x, cx - 1), mini(hi.x, cx + 1) + 1):
				var bit: int = (ny - cy + 1) * 3 + nx - cx + 1
				spill |= 1 << bit
				(reach[bit] as Array).append(d)
	var e: Dictionary = {"rev": rev, "until": until2, "items": items, "spill": spill, "reach": reach, "walls": walls}
	_cache[at] = e
	return e


# A chunk's baked ground: the picture of every ground mark that reaches it, from it and its eight
# neighbours, in the order they landed; which tiles of it hold anything; the keys on each tile (for
# the scene gate); and its wall marks, which are not baked. Re-baked only when that changes.
func _bake(world: Variant, cx: int, cy: int) -> Dictionary:
	var at := Vector2i(cx, cy)
	var tick: int = int(world.tick)
	var stamp: int = int(world.decals_rev)
	var hit: Variant = _baked.get(at)
	# Nothing anywhere has changed since this chunk was last checked: one compare, no walk.
	if hit is Dictionary and int((hit as Dictionary)["stamp"]) == stamp:
		var u0: int = int((hit as Dictionary)["until"])
		if u0 < 0 or tick < u0:
			(hit as Dictionary)["used"] = _frame
			return hit as Dictionary
	var sig := PackedInt32Array()
	var until: int = -1
	var sources: Array[Dictionary] = []
	# Which of each source's `reach` lists faces this chunk; the chunk's own is index 4, all of it.
	var towards := PackedInt32Array()
	var own: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var e: Dictionary = _entry(world, cx + dx, cy + dy)
			if dx == 0 and dy == 0:
				own = e
			var toward: int = (1 - dy) * 3 + 1 - dx
			if (dx != 0 or dy != 0) and (int(e["spill"]) & (1 << toward)) == 0:
				sig.append(-1)
				continue
			sig.append(int(e["rev"]))
			sources.append(e)
			towards.append(toward)
			var u: int = int(e["until"])
			if u >= 0 and (until < 0 or u < until):
				until = u
	if hit is Dictionary and (hit as Dictionary)["sig"] == sig:
		var u2: int = int((hit as Dictionary)["until"])
		if u2 < 0 or tick < u2:
			(hit as Dictionary)["used"] = _frame
			(hit as Dictionary)["stamp"] = stamp
			return hit as Dictionary
	bakes += 1
	var span: int = SimDecals.CHUNK
	var side: int = span * ART_PX
	var corner := Vector2(cx * side, cy * side)
	var marks: Array = []
	var walls: Array = own["walls"] as Array
	for i in sources.size():
		marks.append_array((sources[i]["reach"] as Array)[towards[i]] as Array)
	if sources.size() > 1:
		marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) < int(b["t"]))
	var keys: Array = []
	keys.resize(span * span)
	var rows := PackedInt32Array()
	rows.resize(span)
	var tex: ImageTexture = null
	if not marks.is_empty():
		var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		for d in marks:
			var cut: Image = _cut_of(d)
			if cut == null:
				continue
			var pos := Vector2i((d["at"] as Vector2) - corner)
			img.blend_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()), pos)
			var lo := Vector2i(clampi(floori(float(pos.x) / ART_PX), 0, span - 1), clampi(floori(float(pos.y) / ART_PX), 0, span - 1))
			var hi := Vector2i(clampi(floori(float(pos.x + cut.get_width() - 1) / ART_PX), 0, span - 1), clampi(floori(float(pos.y + cut.get_height() - 1) / ART_PX), 0, span - 1))
			for ty in range(lo.y, hi.y + 1):
				for tx in range(lo.x, hi.x + 1):
					var i: int = ty * span + tx
					# A plain Array: a PackedStringArray read back out of `keys` is a copy, and an
					# append to it would land nowhere (CLAUDE.md's packed-array trap).
					if keys[i] == null:
						keys[i] = []
					if not (keys[i] as Array).has(String(d["key"])):
						(keys[i] as Array).append(String(d["key"]))
		var any: bool = false
		for ty in span:
			for tx in span:
				var cell := Rect2i(tx * ART_PX, ty * ART_PX, ART_PX, ART_PX)
				var wx: int = cx * span + tx
				var wy: int = cy * span + ty
				# Blood that spills onto a wall's tile would paint over its cap: the wall keeps it.
				if world.tilemap != null and SimTileMap.tile_at(world.tilemap, wx, wy) == SimTileMap.Tile.Wall:
					img.fill_rect(cell, Color(0, 0, 0, 0))
					keys[ty * span + tx] = null
					continue
				if keys[ty * span + tx] == null or img.get_region(cell).is_invisible():
					keys[ty * span + tx] = null
					continue
				rows[ty] |= 1 << tx
				any = true
		if any:
			var old: Variant = (hit as Dictionary).get("tex") if hit is Dictionary else null
			if old is ImageTexture:
				tex = old as ImageTexture
				tex.update(img)
			else:
				tex = ImageTexture.create_from_image(img)
	var b: Dictionary = {"sig": sig, "until": until, "tex": tex, "rows": rows, "keys": keys, "walls": walls, "used": _frame, "stamp": stamp}
	_baked[at] = b
	return b


# One mark's picture as the bake lays it: the region cut from the pack's frame, turned a quarter
# and mirrored when the record's variant says, cut hard at ALPHA_CUT, and given the dry pool's
# colours when it is old. Cached, because a handful of pictures and their eight turns are all the
# marks there are.
func _cut_of(d: Dictionary) -> Image:
	var region: Rect2 = d["region"] as Rect2
	var flip: Vector2i = d["flip"] as Vector2i
	var dry: bool = bool(d.get("dry", false))
	var key: String = "%s|%s|%d|%d|%d|%d" % [d["key"], str(region), int(bool(d["transpose"])), flip.x, flip.y, int(dry)]
	var hit: Variant = _cut.get(key)
	if hit is Image:
		return hit as Image
	var src: Image = _source(String(d["key"]), d["texture"] as Texture2D)
	if src == null:
		return null
	src = src.get_region(Rect2i(region))
	if bool(d["transpose"]):
		src.rotate_90(CLOCKWISE)
		src.flip_x()
	if flip.x < 0:
		src.flip_x()
	if flip.y < 0:
		src.flip_y()
	var dry_shades: Array = _dry_shades() if dry else []
	var top: float = 0.0
	if dry:
		for y in src.get_height():
			for x in src.get_width():
				var c0: Color = src.get_pixel(x, y)
				if c0.a >= ALPHA_CUT:
					top = maxf(top, c0.get_luminance())
	for y in src.get_height():
		for x in src.get_width():
			var c: Color = src.get_pixel(x, y)
			if c.a < ALPHA_CUT:
				src.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			c.a = 1.0
			if dry and not dry_shades.is_empty() and top > 0.0:
				# The same place in the dry pool's range of shades as this pixel holds in its own.
				var q: float = clampf(c.get_luminance() / top, 0.0, 1.0)
				c = dry_shades[roundi(q * float(dry_shades.size() - 1))] as Color
			src.set_pixel(x, y, c)
	_cut[key] = src
	return src


# A pack frame's pixels, as RGBA8.
static func _source(key: String, tex: Texture2D) -> Image:
	var src: Image = tex.get_image() if tex != null else null
	if src == null:
		# A renderer with no texture memory (the headless gates) hands back nothing; the source
		# picture on disk is the same pixels.
		var path: String = "%s/%s.png" % [Appearance.SPRITE_DIR, key]
		if FileAccess.file_exists(path):
			src = Image.load_from_file(path)
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	return src


# The dry pool's solid colours, darkest first: the browns old blood is drawn in.
var _dry: Array = []
func _dry_shades() -> Array:
	if not _dry.is_empty():
		return _dry
	var img: Image = _source(DRY_SOURCE, Appearance.resolve(DRY_SOURCE))
	if img == null:
		return _dry
	var seen_c: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a >= ALPHA_CUT:
				seen_c[Color(c.r, c.g, c.b, 1.0)] = true
	_dry = seen_c.keys()
	_dry.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return _dry


# A cut as a texture, for the marks drawn one by one on walls and cars.
var _cut_tex: Dictionary = {}
func _texture_of(d: Dictionary) -> Texture2D:
	var img: Image = _cut_of(d)
	if img == null:
		return null
	var hit: Variant = _cut_tex.get(img.get_instance_id())
	if hit is Texture2D:
		return hit as Texture2D
	var t := ImageTexture.create_from_image(img)
	_cut_tex[img.get_instance_id()] = t
	return t


# Every draw for the marks lying on the ground this frame, in screen pixels: for each chunk the view
# covers, a run of its baked picture per row of seen tiles that hold anything, and each wall mark
# whose tile is seen. A wall mark is left for the wall picture's own call when a picture stands on
# its tile (`standing` holds those tiles by index, as _a2_wall_modules returns them). The gates'
# read; the frame calls `draw_ground`, which is this same walk drawing as it goes. A baked run's
# draw carries `keys`, every picture lying on its tiles.
func ground_draws(world: Variant, camera: Dictionary, seen: Variant, standing: Dictionary, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_ground(world, camera, seen, standing, bounds, null, out, [])
	return out


# The same walk, drawn straight onto `canvas`. `drawn` gets, for the scene gate, each wall mark's
# key and each baked tile's Array of keys -- one append a tile, not one a picture.
func draw_ground(canvas: CanvasItem, world: Variant, camera: Dictionary, seen: Variant, standing: Dictionary, bounds: Dictionary, drawn: Array) -> void:
	_ground(world, camera, seen, standing, bounds, canvas, [], drawn)


func _ground(world: Variant, camera: Dictionary, seen: Variant, standing: Dictionary, bounds: Dictionary, canvas: CanvasItem, out: Array[Dictionary], drawn: Array) -> void:
	if world == null or not ("decals" in world) or (world.decals as Dictionary).is_empty():
		return
	var px: float = Appearance.blit_scale(float(camera.get("zoom", 0.0)))
	if px <= 0.0:
		return
	_frame += 1
	if world != _world:
		_cache.clear()
		_baked.clear()
		_world = world
	var origin: Vector2 = _origin(camera)
	var span: int = SimDecals.CHUNK
	var tile_px: float = float(ART_PX) * px
	var c0 := Vector2i(floori(float(bounds["minX"]) / span), floori(float(bounds["minY"]) / span))
	var c1 := Vector2i(floori(float(bounds["maxX"]) / span), floori(float(bounds["maxY"]) / span))
	var w: int = int(world.map_width)
	# The sight set read straight from its cells when it is the shadowcast's own (one array index a
	# tile rather than a call); any other set answers through `has_tile`.
	var cells := PackedByteArray()
	var vox: int = 0
	var voy: int = 0
	var vsize: int = 0
	var direct: bool = seen != null and seen is Object and "cells" in (seen as Object) and "size" in (seen as Object)
	if direct:
		cells = (seen as Object).get("cells") as PackedByteArray
		vsize = int((seen as Object).get("size"))
		vox = int((seen as Object).get("origin_x")) - int((seen as Object).get("range_tiles"))
		voy = int((seen as Object).get("origin_y")) - int((seen as Object).get("range_tiles"))
	var tx0: int = floori(float(bounds["minX"]))
	var ty0: int = floori(float(bounds["minY"]))
	var tx1: int = floori(float(bounds["maxX"]))
	var ty1: int = floori(float(bounds["maxY"]))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var b: Dictionary = _bake(world, cx, cy)
			var tex: ImageTexture = b["tex"] as ImageTexture
			if tex != null:
				var rows: PackedInt32Array = b["rows"] as PackedInt32Array
				var bkeys: Array = b["keys"] as Array
				var lx0: int = clampi(tx0 - cx * span, 0, span)
				var lx1: int = clampi(tx1 - cx * span + 1, 0, span)
				for ly in range(clampi(ty0 - cy * span, 0, span), clampi(ty1 - cy * span + 1, 0, span)):
					var mask: int = rows[ly]
					if mask == 0:
						continue
					var ty: int = cy * span + ly
					# This row's tiles that hold marks and are seen, as one mask.
					var show: int = 0
					for lx in range(lx0, lx1):
						if (mask & (1 << lx)) == 0:
							continue
						var tx: int = cx * span + lx
						var lit: bool
						if seen == null:
							lit = true
						elif direct:
							var vx: int = tx - vox
							var vy: int = ty - voy
							lit = vx >= 0 and vy >= 0 and vx < vsize and vy < vsize and cells[vy * vsize + vx] == 1
						else:
							lit = visible(seen, Vector2i(tx, ty))
						if lit:
							show |= 1 << lx
					var lx2: int = lx0
					while show != 0 and lx2 < lx1:
						if (show & (1 << lx2)) == 0:
							lx2 += 1
							continue
						# A run of seen tiles holding marks, drawn as one cut of the chunk's picture.
						var end: int = lx2 + 1
						while end < lx1 and (show & (1 << end)) != 0:
							end += 1
						var pos: Vector2 = (origin + Vector2(cx * span + lx2, ty) * float(ART_PX) * px).round()
						var rect := Rect2(pos, Vector2(float(end - lx2) * tile_px, tile_px))
						var region := Rect2(lx2 * ART_PX, ly * ART_PX, (end - lx2) * ART_PX, ART_PX)
						if canvas != null:
							canvas.draw_texture_rect_region(tex, rect, region)
							for i in range(lx2, end):
								drawn.append(bkeys[ly * span + i])
						else:
							var keys: Array = []
							for i in range(lx2, end):
								keys.append_array(bkeys[ly * span + i] as Array)
							out.append({"key": keys[0] if not keys.is_empty() else "", "keys": keys, "texture": tex, "region": region,
								"rect": rect, "canvas": rect, "transpose": false, "modulate": Color.WHITE})
						lx2 = end
			for it in b["walls"] as Array:
				var d: Dictionary = it as Dictionary
				var tile: Vector2i = d["tile"]
				if standing.has(tile.y * w + tile.x):
					continue
				# A dent in a parked car is drawn over the car's picture (`over_draws`), which stands
				# in the entity sort and would cover it here.
				if d["key"] == "fx_bullet_hole_metal" and world.tilemap != null and SimTileMap.tile_at(world.tilemap, tile.x, tile.y) == SimTileMap.Tile.Low:
					continue
				if direct:
					var vx2: int = tile.x - vox
					var vy2: int = tile.y - voy
					if vx2 < 0 or vy2 < 0 or vx2 >= vsize or vy2 >= vsize or cells[vy2 * vsize + vx2] != 1:
						continue
				elif not visible(seen, tile):
					continue
				var sd: Dictionary = _screen(origin, px, d, d["at"])
				if canvas != null:
					if sd["texture"] != null:
						canvas.draw_texture_rect(sd["texture"], sd["rect"], false)
						drawn.append(d["key"])
				else:
					out.append(sd)
	_let_go()


# Past BAKED_MAX baked chunks, the ones drawn longest ago are let go; walking back re-bakes them.
func _let_go() -> void:
	if _baked.size() <= BAKED_MAX:
		return
	var order: Array = _baked.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return int(_baked[a]["used"]) < int(_baked[b]["used"]))
	for i in order.size() - BAKED_MAX:
		_baked.erase(order[i])


# The marks on one standing wall picture, drawn over it: every wall mark on a tile the picture
# stands on, placed on the picture's face -- along the run at the height a round strikes for a
# picture wider than it is deep, down the leg at the struck point for a narrow north-south leg.
# `rect` is the picture in metres.
func wall_draws(world: Variant, camera: Dictionary, seen: Variant, rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or not ("decals" in world) or (world.decals as Dictionary).is_empty():
		return out
	var px: float = Appearance.blit_scale(float(camera.get("zoom", 0.0)))
	if px <= 0.0:
		return out
	var origin: Vector2 = _origin(camera)
	# The tiles under the picture: its own row (the one its foot stands on) across its width. A run
	# picture hangs a few pixels below its tile's south edge (the pack's pivot is row 44 of 48), so
	# the foot row is the one a quarter tile up from the picture's bottom.
	var row: int = floori(rect.end.y - 0.25)
	var x0: int = floori(rect.position.x)
	var x1: int = floori(rect.end.x - 0.001)
	var narrow: bool = rect.size.x < 0.75
	var top_rows: int = floori(rect.position.y)
	var span: int = SimDecals.CHUNK
	var seen_chunks: Dictionary = {}
	for ty in range(top_rows, row + 1):
		for tx in range(x0, x1 + 1):
			var ch := Vector2i(floori(float(tx) / span), floori(float(ty) / span))
			if seen_chunks.has(ch):
				continue
			seen_chunks[ch] = true
			for it in chunk_items(world, ch.x, ch.y):
				var d: Dictionary = it as Dictionary
				if not bool(d["wall"]):
					continue
				var tile: Vector2i = d["tile"] as Vector2i
				if tile.x < x0 or tile.x > x1 or tile.y < top_rows or tile.y > row:
					continue
				if not narrow and tile.y != row:
					continue
				if not visible(seen, tile):
					continue
				var centre := Vector2(float(d["x"]), float(d["y"]))
				var r_px := Rect2(rect.position * ART_PX, rect.size * ART_PX)
				if narrow:
					centre.x = r_px.get_center().x
					centre.y = clampf(centre.y, r_px.position.y + 4.0, r_px.end.y - 4.0)
				else:
					centre.x = clampf(centre.x, r_px.position.x + 4.0, r_px.end.x - 4.0)
					# Mid-face, a little up or down by the record's variant so a burst is a group.
					centre.y = r_px.position.y + r_px.size.y * 0.55 + float((int(d["x"]) + int(d["y"])) % 7 - 3)
				out.append(_screen(origin, px, d, centre - (d["size"] as Vector2) * 0.5))
	return out


# The marks on a parked car's picture, drawn over it: every wall mark on a footprint tile, at its own
# point. `foot` is the footprint in tiles. Without this a dent would lie on the ground under the car.
func over_draws(world: Variant, camera: Dictionary, seen: Variant, foot: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or not ("decals" in world) or (world.decals as Dictionary).is_empty():
		return out
	var px: float = Appearance.blit_scale(float(camera.get("zoom", 0.0)))
	if px <= 0.0:
		return out
	var origin: Vector2 = _origin(camera)
	var span: int = SimDecals.CHUNK
	var c0 := Vector2i(floori(foot.position.x / span), floori(foot.position.y / span))
	var c1 := Vector2i(floori((foot.end.x - 0.001) / span), floori((foot.end.y - 0.001) / span))
	var area := Rect2i(Vector2i(foot.position), Vector2i(foot.size))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for it in chunk_items(world, cx, cy):
				var d: Dictionary = it as Dictionary
				if bool(d["wall"]) and area.has_point(d["tile"] as Vector2i) and visible(seen, d["tile"] as Vector2i):
					out.append(_screen(origin, px, d, d["at"] as Vector2))
	return out


static func visible(seen: Variant, tile: Vector2i) -> bool:
	return seen == null or bool((seen as Object).call("has_tile", tile.x, tile.y))


# One mark drawn on its own (a wall's or a car's), from its hard-cut, already-turned picture.
func _screen(origin: Vector2, px: float, d: Dictionary, at: Vector2) -> Dictionary:
	var size: Vector2 = (d["size"] as Vector2) * px
	var pos: Vector2 = (origin + at * px).round()
	var tex: Texture2D = _texture_of(d)
	var rect := Rect2(pos, size)
	return {"key": d["key"], "texture": tex, "region": Rect2(Vector2.ZERO, d["size"] as Vector2), "rect": rect,
		"canvas": rect, "transpose": false, "modulate": Color.WHITE}


# Screen position of world art pixel (0, 0): the projection is a scale and an offset, so one call a
# frame stands in for one a mark.
static func _origin(camera: Dictionary) -> Vector2:
	var sc: Dictionary = TopDownProjection.world_to_screen(camera, 0.0, 0.0)
	return Vector2(float(sc["sx"]), float(sc["sy"]))

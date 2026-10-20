extends RefCounted
# The baked world: the ground, the walls and the roofs drawn once per chunk and kept, instead of
# redrawn tile by tile every frame (docs/22, "The world, baked"). Plan item A4.
#
# What changes per frame and what does not. A tile's *look* -- its ground cell, its paint, its
# wall cap or face, its roof sheet -- is a function of the map, the content, the seed, the zoom and
# the snow, and none of those move when the survivor walks. What moves is *which* look the screen
# shows: seen, remembered, roofed over, or nothing. So every look a tile can take is baked into its
# own layer, and a mask shader (world_mask.gdshader) picks between them per tile from the sight
# sets, which are uploaded as small textures when they change. Walking re-uploads a few kilobytes;
# it never rebakes.
#
# Layers, bottom to top, each one RenderingServer canvas item drawn behind main's own commands, so
# everything main draws per frame (nature, furnishings, props, light pools, bodies, effects) lands
# on top exactly as it did:
#   background  the screen-space clear the old _draw opened with
#   LIVE        every tile as the survivor sees it now          shows where LIVE and not A2
#   A2          the room boards under a standing wall module    shows where A2 and LIVE
#   DECOR       the flat furnishings and the nature pictures    shows where LIVE
#   REMEMBERED  every tile as the remembered map draws it       shows where EXPLORED and not LIVE
#   ROOF        every roofable tile's sheet                     shows where ROOF and not EXPLORED
#   ROOF_DIM    the same sheet, dimmed                          shows where ROOF and EXPLORED
#
# A chunk is CHUNK x CHUNK tiles, baked in world pixels (tile tx at tx * zoom) so the layer's own
# transform is the only thing the camera moves. A chunk is rebaked when what it was baked from
# changes: the zoom, the map object, the content tree or the seed (everything goes), a tile or
# overlay in or beside it (that chunk alone, by signature), or the snow (budgeted, a few chunks a
# frame, the stale picture standing in meanwhile -- snow settles over minutes, not frames).
#
# Lighting (A10) composites over these layers rather than into them: a light pass draws after
# them and can read the same sight textures (`mask_textures`) for a soft edge, without rebaking.

const Pen = preload("res://presentation/canvas_pen.gd")
const MaskShader = preload("res://presentation/world_mask.gdshader")
const Shadowcast = preload("res://sim/vision/shadowcast.gd")

const CHUNK: int = 8

enum Layer { LIVE, A2, DECOR, REMEMBERED, ROOF, ROOF_DIM }
const LAYER_COUNT: int = 6

# The tile-state bits world_mask.gdshader reads; the flags texture carries ROOF and A2, and LIVE
# and EXPLORED too when the sight sets arrive as something other than the sim's own types.
const BIT_LIVE: int = 1
const BIT_EXPLORED: int = 2
const BIT_ROOF: int = 4
const BIT_A2: int = 8

# want / deny per layer, in Layer order.
const RULES: Array = [
	[BIT_LIVE, BIT_A2],
	[BIT_A2 | BIT_LIVE, 0],
	[BIT_LIVE, 0],
	[BIT_EXPLORED, BIT_LIVE],
	[BIT_ROOF, BIT_EXPLORED],
	[BIT_ROOF | BIT_EXPLORED, 0],
]

# Snow is baked at this many steps between bare and fully covered. A step is a colour change of
# well under one 8-bit level per channel at Palette.SNOW_COVER_MAX, and a step's rebake is spread
# over frames, so a snowfall settles chunk by chunk instead of rebaking the screen every tick.
const SNOW_STEPS: float = 64.0
# Work that can wait -- the ring just off screen, and snow -- gets this much of a frame, and at
# least one chunk whenever nothing urgent was baked, so it always finishes.
const BUDGET_USEC: int = 2000
# Chunks kept beyond the visible ones, in chunks per side; anything farther is freed.
const PREFETCH_RING: int = 1
const KEEP_RING: int = 2
const ALL_LAYERS: int = (1 << LAYER_COUNT) - 1

var _parent: RID
var _background: RID
var _roots: Array[RID] = []
var _materials: Array[ShaderMaterial] = []
# Vector2i chunk -> {"items": Array[RID], "sig": int, "snow": int}
var _chunks: Dictionary = {}
var _attached: bool = false

# What every cached chunk was baked against; any of these changing frees them all.
var _zoom: float = -1.0
var _map: Variant = null
var _content: Variant = null
var _seed: int = -1
var _generation: int = -1
var _background_size: Vector2 = Vector2(-1, -1)
var _background_colour: Color = Color(0, 0, 0, 0)

# The mask inputs, kept so an unchanged one is never re-uploaded.
var _flags := PackedByteArray()
var _flags_size := Vector2i(-1, -1)
var _flags_tex: ImageTexture = null
var _cells := PackedByteArray()
var _cells_size: int = -1
var _cells_origin := Vector3i(0, 0, 0)
var _cells_tex: ImageTexture = null
# EXPLORED unpacked, one byte a tile, and the bitset it was unpacked from.
var _dense := PackedByteArray()
var _bits_seen := PackedByteArray()
var _sparse: Dictionary = {}
var _live_source: int = -1
# EXPLORED tiles per chunk (Vector2i -> int), kept as the dense bytes flip, for the cull below.
var _explored_count: Dictionary = {}
# Bumped whenever a mask input changes; the cull reruns when it has moved or a chunk was baked.
var _sight_rev: int = 0
# True when EXPLORED came from the sim's bitset (or there is no remembered map): the cull's
# counts are only kept for that path.
var _explored_dense: bool = true
var _culled_rev: int = -1

# Read by the frame bench and by the look gates: what the last frame baked, and how long it took.
var baked_last_frame: int = 0
var bake_usec_last_frame: int = 0
var baked_total: int = 0


func attach(parent: RID) -> void:
	if _attached:
		return
	_parent = parent
	_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_background, _parent)
	RenderingServer.canvas_item_set_draw_behind_parent(_background, true)
	RenderingServer.canvas_item_set_draw_index(_background, 0)
	for layer in LAYER_COUNT:
		var root: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(root, _parent)
		RenderingServer.canvas_item_set_draw_behind_parent(root, true)
		RenderingServer.canvas_item_set_draw_index(root, layer + 1)
		var mat := ShaderMaterial.new()
		mat.shader = MaskShader
		mat.set_shader_parameter("want", int(RULES[layer][0]))
		mat.set_shader_parameter("deny", int(RULES[layer][1]))
		RenderingServer.canvas_item_set_material(root, mat.get_rid())
		_roots.append(root)
		_materials.append(mat)
	_attached = true


func detach() -> void:
	if not _attached:
		return
	clear()
	for root in _roots:
		RenderingServer.free_rid(root)
	RenderingServer.free_rid(_background)
	_roots.clear()
	_materials.clear()
	_attached = false
	# A later attach makes new materials, so every parameter the old ones held is sent again:
	# the zoom and map size with the next global clear, the textures with the next set_sight.
	_zoom = -1.0
	_map = null
	_content = null
	_background_size = Vector2(-1, -1)
	_flags_tex = null
	_cells_tex = null
	_cells_size = -1
	_live_source = -1


# Frees every baked chunk. The next frame bakes what it can see again.
func clear() -> void:
	for key in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()


func chunk_count() -> int:
	return _chunks.size()


func is_baked(chunk: Vector2i) -> bool:
	return _chunks.has(chunk)


func mask_textures() -> Dictionary:
	return {"flags": _flags_tex, "live_cells": _cells_tex}


static func chunk_of(tx: int, ty: int) -> Vector2i:
	return Vector2i(floori(float(tx) / float(CHUNK)), floori(float(ty) / float(CHUNK)))


static func chunk_region(chunk: Vector2i, map_w: int, map_h: int) -> Rect2i:
	var r := Rect2i(chunk * CHUNK, Vector2i(CHUNK, CHUNK))
	return r.intersection(Rect2i(0, 0, map_w, map_h))


# The chunks a tile range touches, clipped to the map.
static func chunks_over(min_tx: int, min_ty: int, max_tx: int, max_ty: int, map_w: int, map_h: int) -> Rect2i:
	var a: Vector2i = chunk_of(maxi(0, min_tx), maxi(0, min_ty))
	var b: Vector2i = chunk_of(mini(map_w - 1, max_tx), mini(map_h - 1, max_ty))
	return Rect2i(a, b - a + Vector2i.ONE)


# One frame. `ctx`:
#   zoom, offset (Vector2, the screen position of world pixel 0,0), viewport (Vector2)
#   map, content, seed, generation (world.map_generation: every tile, overlay and vehicle writer
#   in the sim bumps it), map_w, map_h
#   view (Rect2i, the visible tiles, margin included), snow (float), background (Color)
#   signature (Callable(region: Rect2i) -> int), bake (Callable(region, layer, pen) -> void)
func frame(ctx: Dictionary) -> void:
	baked_last_frame = 0
	bake_usec_last_frame = 0
	if not _attached:
		return
	var viewport: Vector2 = ctx["viewport"]
	var colour: Color = ctx["background"] as Color
	if viewport != _background_size or colour != _background_colour:
		RenderingServer.canvas_item_clear(_background)
		RenderingServer.canvas_item_add_rect(_background, Rect2(Vector2.ZERO, viewport), colour)
		_background_size = viewport
		_background_colour = colour
	var zoom: float = float(ctx["zoom"])
	var map_w: int = int(ctx["map_w"])
	var map_h: int = int(ctx["map_h"])
	if zoom != _zoom or not is_same(ctx["map"], _map) or not is_same(ctx["content"], _content) or int(ctx["seed"]) != _seed:
		clear()
		_zoom = zoom
		_map = ctx["map"]
		_content = ctx["content"]
		_seed = int(ctx["seed"])
		_generation = int(ctx["generation"])
		for mat in _materials:
			mat.set_shader_parameter("zoom", zoom)
			mat.set_shader_parameter("map_size", Vector2i(map_w, map_h))
	var offset: Vector2 = ctx["offset"]
	var shift := Transform2D(0.0, Vector2(roundf(offset.x), roundf(offset.y)))
	for root in _roots:
		RenderingServer.canvas_item_set_transform(root, shift)
	if map_w <= 0 or map_h <= 0:
		return
	var view: Rect2i = ctx["view"]
	var visible: Rect2i = chunks_over(view.position.x, view.position.y, view.end.x - 1, view.end.y - 1, map_w, map_h)
	var snow: int = roundi(clampf(float(ctx["snow"]), 0.0, 1.0) * SNOW_STEPS)
	var signature: Callable = ctx["signature"]
	var bake: Callable = ctx["bake"]
	# A tile changed somewhere: re-sign every cached chunk and drop the ones whose inputs moved.
	if int(ctx["generation"]) != _generation:
		_generation = int(ctx["generation"])
		for key in _chunks.keys():
			var region: Rect2i = chunk_region(key as Vector2i, map_w, map_h)
			if int(signature.call(region)) != int((_chunks[key] as Dictionary)["sig"]):
				_free_chunk(key)
				_chunks.erase(key)
	var started: int = Time.get_ticks_usec()
	var later: Array[Vector2i] = []
	for cy in range(visible.position.y, visible.end.y):
		for cx in range(visible.position.x, visible.end.x):
			var key := Vector2i(cx, cy)
			if not _chunks.has(key):
				_bake(key, map_w, map_h, snow, signature, bake)
			elif int((_chunks[key] as Dictionary)["snow"]) != snow:
				later.append(key)
	var ring: Rect2i = visible.grow(PREFETCH_RING).intersection(chunks_over(0, 0, map_w - 1, map_h - 1, map_w, map_h))
	for cy in range(ring.position.y, ring.end.y):
		for cx in range(ring.position.x, ring.end.x):
			var key := Vector2i(cx, cy)
			if not _chunks.has(key):
				later.append(key)
			elif not visible.has_point(key) and int((_chunks[key] as Dictionary)["snow"]) != snow:
				later.append(key)
	for key in later:
		if baked_last_frame > 0 and Time.get_ticks_usec() - started >= BUDGET_USEC:
			break
		if _chunks.has(key):
			_free_chunk(key)
			_chunks.erase(key)
		_bake(key, map_w, map_h, snow, signature, bake)
	var keep: Rect2i = visible.grow(KEEP_RING)
	for key in _chunks.keys():
		if not keep.has_point(key as Vector2i):
			_free_chunk(key)
			_chunks.erase(key)
	bake_usec_last_frame = Time.get_ticks_usec() - started
	if baked_last_frame > 0 or _sight_rev != _culled_rev:
		_cull(map_w, map_h)
		_culled_rev = _sight_rev


func _bake(key: Vector2i, map_w: int, map_h: int, snow: int, signature: Callable, bake: Callable) -> void:
	var region: Rect2i = chunk_region(key, map_w, map_h)
	if not region.has_area():
		return
	var items: Array[RID] = []
	for layer in LAYER_COUNT:
		var item: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, _roots[layer])
		RenderingServer.canvas_item_set_use_parent_material(item, true)
		bake.call(region, layer, Pen.new(item))
		items.append(item)
	_chunks[key] = {"items": items, "sig": int(signature.call(region)), "snow": snow, "shown": ALL_LAYERS}
	baked_last_frame += 1
	baked_total += 1


func _free_chunk(key: Variant) -> void:
	var rec: Variant = _chunks.get(key)
	if not (rec is Dictionary):
		return
	for item in (rec as Dictionary)["items"]:
		RenderingServer.free_rid(item as RID)


# The sight sets for this frame. `seen` is the observer's VisibleTiles (or anything with
# `has_tile`, or null for no observer view: everything draws as seen); `explored` the remembered
# map (SimSightings.ExploredView, anything with `has_tile`, or null); `roof` the tiles the roof rule
# chose; `a2` the tiles a standing wall module covers ({index: true}). `view` bounds the slow path
# a duck-typed set takes.
#
# The flags texture is one byte a tile, so the shader asks one texel for everything but LIVE (the
# shadowcast's own cells, uploaded as they are). EXPLORED is unpacked from the sim's bitset into it
# here, and only where the bitset changed: a merge only ever sets bits inside the cast that made
# it, so the bytes under the cast window are compared and patched, and anything else (a load, a new
# world) is caught by comparing the whole patched copy and unpacked from scratch. Decoding the bits
# in the shader instead cost more than the rest of the mask together on the software renderer.
func set_sight(seen: Variant, explored: Variant, roof: Array, a2: Dictionary, map_w: int, map_h: int, view: Rect2i) -> void:
	if not _attached or map_w <= 0 or map_h <= 0:
		return
	var size := Vector2i(map_w, map_h)
	if size != _flags_size:
		_flags = PackedByteArray()
		_flags.resize(map_w * map_h)
		_dense = PackedByteArray()
		_dense.resize(map_w * map_h)
		_bits_seen = PackedByteArray()
		_sparse = {}
		_explored_count = {}
		_flags_size = size
		_flags_tex = null
	var fast_live: bool = seen != null and seen is Shadowcast.VisibleTiles
	var fast_explored: bool = explored != null and "bytes" in explored and "w" in explored and int(explored.w) == map_w and int(explored.h) == map_h
	var changed: bool = _flags_tex == null
	var explored_dense: bool = explored == null or fast_explored
	if explored_dense != _explored_dense:
		_explored_dense = explored_dense
		_sight_rev += 1
	# EXPLORED, dense, from the bitset.
	var bitset: PackedByteArray = explored.bytes if fast_explored else PackedByteArray()
	if bitset != _bits_seen:
		changed = true
		var patched: bool = false
		if fast_live and _bits_seen.size() == bitset.size():
			_patch_explored(bitset, seen as Shadowcast.VisibleTiles, map_w, map_h)
			patched = _bits_seen == bitset
		if not patched:
			_unpack_explored(bitset, map_w, map_h)
	# The sparse bits: the roof rule, the wall modules, and LIVE / EXPLORED from a duck-typed set.
	var sparse: Dictionary = {}
	for t in roof:
		var i: int = (t as Vector2i).y * map_w + (t as Vector2i).x
		sparse[i] = int(sparse.get(i, 0)) | BIT_ROOF
	for k in a2.keys():
		sparse[int(k)] = int(sparse.get(int(k), 0)) | BIT_A2
	if (seen != null and not fast_live) or (explored != null and not fast_explored):
		var x0: int = maxi(0, view.position.x)
		var y0: int = maxi(0, view.position.y)
		var x1: int = mini(map_w, view.end.x)
		var y1: int = mini(map_h, view.end.y)
		for ty in range(y0, y1):
			for tx in range(x0, x1):
				var b: int = 0
				if seen != null and not fast_live and bool((seen as Object).call("has_tile", tx, ty)):
					b |= BIT_LIVE
				if explored != null and not fast_explored and bool((explored as Object).call("has_tile", tx, ty)):
					b |= BIT_EXPLORED
				if b != 0:
					var i: int = ty * map_w + tx
					sparse[i] = int(sparse.get(i, 0)) | b
	if sparse != _sparse:
		changed = true
		for i in _sparse.keys():
			_flags[int(i)] = _dense[int(i)]
		_sparse = sparse
	if changed:
		for i in _sparse.keys():
			_flags[int(i)] = _dense[int(i)] | int(_sparse[i])
		_flags_tex = _upload(_flags_tex, _flags, map_w, map_h)
		_param("flags", _flags_tex)
		_sight_rev += 1
	if fast_live:
		var vt: Shadowcast.VisibleTiles = seen as Shadowcast.VisibleTiles
		var origin := Vector3i(vt.origin_x - vt.range_tiles, vt.origin_y - vt.range_tiles, vt.size)
		if _cells_tex == null or vt.size != _cells_size or origin != _cells_origin or vt.cells != _cells:
			_cells = vt.cells.duplicate()
			if vt.size != _cells_size:
				_cells_tex = null
			_cells_size = vt.size
			_cells_origin = origin
			if vt.size > 0:
				_cells_tex = _upload(_cells_tex, _cells, vt.size, vt.size)
				_param("live_cells", _cells_tex)
			_param("live_origin", origin)
			_sight_rev += 1
	var live_source: int = 2 if seen == null else (1 if fast_live else 0)
	if live_source != _live_source:
		_live_source = live_source
		_param("live_source", live_source)
		_sight_rev += 1


# Which of each cached chunk's five items has a tile to show, and every other item hidden. The
# mask would discard every fragment of a layer with nothing to show in a chunk anyway; hiding the
# item spares the renderer running the shader over it at all. On the software renderer that is
# most of the frame -- the remembered layer over a street nobody has walked away from yet, the
# roof sheets over every house in view -- and on a GPU it is the overdraw of five layers cut to
# what the sight sets use.
#
# A2, ROOF and ROOF_DIM are read off the sparse bits (their tiles are few). LIVE and REMEMBERED are
# counted per chunk: LIVE from the shadowcast's cells, a row slice at a time (DECOR rides on LIVE:
# its pictures exist only on seen tiles, so a chunk with no seen tile draws none), and REMEMBERED as
# "more EXPLORED tiles than LIVE ones", which is exact because the sim merges every cast into the
# remembered map in the tick that made it (sightings.gd), so a seen tile is always an explored
# one. A sight set that is not the sim's own (live_source 0, the gates' duck-typed sets) shows
# every layer: the cull is an optimisation and never decides what is seen.
func _cull(map_w: int, map_h: int) -> void:
	var shown: Dictionary = {}
	if _live_source == 2:
		for key in _chunks.keys():
			_show(key as Vector2i, (1 << Layer.LIVE) | (1 << Layer.A2) | (1 << Layer.DECOR) | _sparse_layers_all(key as Vector2i))
		return
	if _live_source != 1 or not _explored_dense:
		for key in _chunks.keys():
			_show(key as Vector2i, ALL_LAYERS)
		return
	for i in _sparse.keys():
		var key := Vector2i((int(i) % map_w) / CHUNK, (int(i) / map_w) / CHUNK)
		var state: int = state_at(int(i) % map_w, int(i) / map_w)
		var bits: int = int(shown.get(key, 0))
		for layer in [Layer.A2, Layer.ROOF, Layer.ROOF_DIM]:
			if shows(int(layer), state):
				bits |= 1 << int(layer)
		shown[key] = bits
	var live: Dictionary = _live_per_chunk(map_w, map_h)
	for key in _chunks.keys():
		var bits: int = int(shown.get(key, 0))
		var n_live: int = int(live.get(key, 0))
		if n_live > 0:
			bits |= (1 << Layer.LIVE) | (1 << Layer.DECOR)
		if int(_explored_count.get(key, 0)) > n_live:
			bits |= 1 << Layer.REMEMBERED
		_show(key as Vector2i, bits)


# With no observer view everything is seen: LIVE and A2 everywhere, the roofs where the rule chose
# them (it chooses none without a view, but the bits are read rather than assumed).
func _sparse_layers_all(key: Vector2i) -> int:
	var bits: int = 0
	var region: Rect2i = chunk_region(key, _flags_size.x, _flags_size.y)
	for i in _sparse.keys():
		var t := Vector2i(int(i) % _flags_size.x, int(i) / _flags_size.x)
		if not region.has_point(t):
			continue
		var state: int = state_at(t.x, t.y)
		for layer in [Layer.ROOF, Layer.ROOF_DIM]:
			if shows(int(layer), state):
				bits |= 1 << int(layer)
	return bits


# LIVE tiles per chunk, counted from the shadowcast's cells one chunk-wide row slice at a time.
func _live_per_chunk(map_w: int, map_h: int) -> Dictionary:
	var out: Dictionary = {}
	var size: int = _cells_origin.z
	if size <= 0 or _cells.size() < size * size:
		return out
	var ox: int = _cells_origin.x
	var oy: int = _cells_origin.y
	var x0: int = maxi(0, ox)
	var x1: int = mini(map_w, ox + size)
	var y0: int = maxi(0, oy)
	var y1: int = mini(map_h, oy + size)
	for ty in range(y0, y1):
		var row: int = (ty - oy) * size
		var cy: int = ty / CHUNK
		var tx: int = x0
		while tx < x1:
			var seg_end: int = mini(x1, (tx / CHUNK + 1) * CHUNK)
			var n: int = _cells.slice(row + tx - ox, row + seg_end - ox).count(1)
			if n > 0:
				var key := Vector2i(tx / CHUNK, cy)
				out[key] = int(out.get(key, 0)) + n
			tx = seg_end
	return out


func _show(key: Vector2i, bits: int) -> void:
	var rec: Dictionary = _chunks[key] as Dictionary
	if int(rec["shown"]) == bits:
		return
	var items: Array = rec["items"]
	for layer in LAYER_COUNT:
		RenderingServer.canvas_item_set_visible(items[layer] as RID, (bits & (1 << layer)) != 0)
	rec["shown"] = bits


# Whether a chunk's layer item is drawn at all (the cull above); false for a chunk not cached.
func layer_shown(key: Vector2i, layer: int) -> bool:
	var rec: Variant = _chunks.get(key)
	return rec is Dictionary and (int((rec as Dictionary)["shown"]) & (1 << layer)) != 0


# The bytes of the bitset under the cast window, compared and unpacked where they moved.
func _patch_explored(bitset: PackedByteArray, vt: Shadowcast.VisibleTiles, map_w: int, map_h: int) -> void:
	var y0: int = maxi(0, vt.origin_y - vt.range_tiles)
	var y1: int = mini(map_h - 1, vt.origin_y + vt.range_tiles)
	var x0: int = maxi(0, vt.origin_x - vt.range_tiles)
	var x1: int = mini(map_w - 1, vt.origin_x + vt.range_tiles)
	for ty in range(y0, y1 + 1):
		var first: int = (ty * map_w + x0) / 8
		var last: int = (ty * map_w + x1) / 8
		for byte_i in range(first, last + 1):
			if byte_i >= bitset.size():
				break
			if bitset[byte_i] != _bits_seen[byte_i]:
				_bits_seen[byte_i] = bitset[byte_i]
				_unpack_byte(bitset[byte_i], byte_i)


func _unpack_explored(bitset: PackedByteArray, map_w: int, map_h: int) -> void:
	_bits_seen = bitset.duplicate()
	for i in _dense.size():
		if _dense[i] != 0:
			_set_dense(i, 0)
	for byte_i in mini(bitset.size(), (map_w * map_h + 7) / 8):
		if bitset[byte_i] != 0:
			_unpack_byte(bitset[byte_i], byte_i)


func _unpack_byte(value: int, byte_i: int) -> void:
	for bit in 8:
		var i: int = byte_i * 8 + bit
		if i >= _dense.size():
			return
		var e: int = BIT_EXPLORED if (value & (1 << bit)) != 0 else 0
		if _dense[i] != e:
			_set_dense(i, e)


func _set_dense(i: int, e: int) -> void:
	var w: int = _flags_size.x
	var key := Vector2i((i % w) / CHUNK, (i / w) / CHUNK)
	_explored_count[key] = int(_explored_count.get(key, 0)) + (1 if e != 0 else -1)
	_dense[i] = e
	_flags[i] = e | int(_sparse.get(i, 0))


# The state world_mask.gdshader computes for a tile, computed here from the same inputs: the flags
# byte, and LIVE from wherever this frame's LIVE comes from. The shader cannot be run headless, so
# this is what a gate asks "which look does the screen show on this tile" of, and `shows` is the
# shader's discard rule over it. world_mask.gdshader and this pair are one rule written twice; the
# world gate (check_world_bake.gd) holds the two copies' constants and rule text together.
func state_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _flags_size.x or ty >= _flags_size.y:
		return 0
	var bits: int = int(_flags[ty * _flags_size.x + tx])
	if _live_source == 2:
		bits |= BIT_LIVE
	elif _live_source == 1:
		var cx: int = tx - _cells_origin.x
		var cy: int = ty - _cells_origin.y
		if cx >= 0 and cy >= 0 and cx < _cells_origin.z and cy < _cells_origin.z and int(_cells[cy * _cells_origin.z + cx]) == 1:
			bits |= BIT_LIVE
	return bits


static func shows(layer: int, state: int) -> bool:
	var want: int = int(RULES[layer][0])
	var deny: int = int(RULES[layer][1])
	return (state & want) == want and (state & deny) == 0


func _param(name: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(name, value)


static func _upload(tex: ImageTexture, bytes: PackedByteArray, w: int, h: int) -> ImageTexture:
	var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)
	if tex == null:
		return ImageTexture.create_from_image(img)
	tex.update(img)
	return tex

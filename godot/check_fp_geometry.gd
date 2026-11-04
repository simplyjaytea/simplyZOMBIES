extends SceneTree
# The first-person geometry gate (docs/40, slice 1: "The profile, drawn"). The sim's height profile
# (`SimSpace.PROFILE`) is the one authority; the first-person view must draw exactly its bands and the
# bodies exactly their cylinders. Printed as FP_GEOMETRY_OK or FP_GEOMETRY_FAIL.
#
# Lanes, each with a true positive and a true negative:
#   FIXTURE   a fixture map holding every tile class, every overlay kind and every board and door stage,
#             with every PROFILE key reached by some tile, so no band goes untested.
#   BANDS     each tile's built mesh has exactly the height levels its bands give (the bottom and top
#             of every band, to the millimetre) and the tile's full footprint. The whole district's
#             built meshes agree with the per-tile answer. Water draws no solid.
#   OLD WAY   a fixture drawn the old way (a window as one solid box, a Low tile undrawn) is refused by
#             the same comparison. The negative is the proof the comparison can fail.
#   BODIES    each body's built cylinder has the radius and height `SimSpace.body_of` gives, for a
#             standing, crouched and crawling survivor and a whole and a crawling zombie, and follows a
#             stance change between frames. A capsule is refused.
#   KIT       with the kit GLBs on disk, a full-height wall tile is drawn by `wall_module.glb`: its
#             drawn AABB is the wall band's 0..2550 height, one tile along the run and the module's own
#             0.12 m thickness, inside the tile and flush to an edge. A wrong-size module planted
#             through the same placement is refused. Without the GLBs the lane skips and the band
#             boxes are under test.
#   FINISHES  every content template resolves to one manifest model whose spatial vertices stay in
#             full wall tiles and within 0..2550 mm, with every wall tile capped over its footprint
#             exactly once: by the always-drawn mesh, or by its own per-tile wall piece when worldgen
#             may open it. Every per-tile piece the manifest counts is a node the view parses. Finish
#             vertices below the roof stay in solid template tiles, except floor overlays; glazing is
#             transparent and nearest-filtered. Planted open-tile and high-wall vertices are refused,
#             and a stamped house really draws its finish instance.
#   WORLDGEN  the four districts generated for real (`SimBoot.bare`, occluder pass included): every
#             sim wall in a finished building is drawn as a wall, and every sim window is drawn as
#             one, rays across its aperture (1.25 and 1.85 m) passing every opaque face the building
#             draws and rays at its sill and lintel (0.5 and 2.3 m) hitting one. No legacy band box
#             is left under a tile the building draws. A solid wall planted over a window worldgen
#             opened is refused by the same rays, and a baseline that still draws the band boxes is
#             refused by the same box count.
#   CEILINGS  in the same four districts, every tile the sim marks indoors in a finished building, a
#             wall excepted, is closed from above: two vertical rays from 5 cm above the floor each
#             cross a downward-facing face the building draws no higher than `SimSpace.FULL_MM`, the
#             top of every full-height band, and no lower than 25 mm under it, or under the bottom of
#             the tile's own head band where its profile has one (a window's lintel, a door's head).
#             Counters, shelves and partitions included. The ceiling stripped in memory from one
#             counter or shelf tile's mesh is refused by the same rays, at that tile.

const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BuildingView = preload("res://presentation/first_person/building_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const Assets = preload("res://presentation/first_person/assets.gd")
const SimSpace = preload("res://sim/space/space.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimTemplates = preload("res://sim/map/templates.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimStances = preload("res://sim/stances.gd")

const SMALL_TILES: int = 64
const EPSILON_M: float = 0.001

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture: Variant = _fixture()
	var ok: bool = _fixture_covers_profile(fixture)
	ok = _bands(fixture) and ok
	ok = _old_way(fixture) and ok
	ok = _bodies() and ok
	ok = _kit(fixture) and ok
	ok = _finishes() and ok
	_finish(ok)


func _finish(ok: bool) -> void:
	if ok:
		print("FP_GEOMETRY_OK every tile and all 22 building finishes keep their profile bands, every body keeps its cylinder, finish skins stay within 25 mm of a solid host, every sim window in four generated districts is drawn open and every indoor tile there has a ceiling, and planted wall-over-window, stripped-ceiling, band-box, window, Low-tile, module, open-tile and high-wall errors are refused")
		quit(0)
		return
	for failure in _failures:
		push_error("FP_GEOMETRY_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


# --- FIXTURE --------------------------------------------------------------------------------

# One tile per case along row 0: its class and, when it has one, its overlay.
func _fixture() -> Variant:
	var cases: Array = [
		[SimTileMap.Tile.Floor, null],
		[SimTileMap.Tile.Wall, null],
		[SimTileMap.Tile.Window, null],
		[SimTileMap.Tile.Screen, null],
		[SimTileMap.Tile.Low, null],
		[SimTileMap.Tile.Tree, null],
		[SimTileMap.Tile.Door, null],
		[SimTileMap.Tile.Water, null],
		[SimTileMap.Tile.Door, {"kind": "door", "open": false, "stage": 0}],
		[SimTileMap.Tile.Door, {"kind": "door", "open": true, "stage": 0}],
		[SimTileMap.Tile.Window, {"kind": "board", "stage": 0}],
		[SimTileMap.Tile.Window, {"kind": "board", "stage": 1}],
		[SimTileMap.Tile.Window, {"kind": "board", "stage": 2}],
		[SimTileMap.Tile.Window, {"kind": "board", "stage": 3}],
		[SimTileMap.Tile.Floor, {"kind": "scrap"}],
		[SimTileMap.Tile.Floor, {"kind": "timber"}],
		[SimTileMap.Tile.Floor, {"kind": "stone"}],
		[SimTileMap.Tile.Floor, {"kind": "fence"}],
		[SimTileMap.Tile.Door, {"kind": "door", "open": false, "stage": 2}],
	]
	var map: Variant = SimTileMap.blank_map(cases.size(), 1)
	for i in cases.size():
		var c: Array = cases[i] as Array
		map.tiles[i] = int(c[0])
		if c[1] != null:
			map.overlays[i] = c[1]
	return map


func _fixture_covers_profile(map: Variant) -> bool:
	var reached: Dictionary = {}
	for tx in int(map.w):
		reached[SimSpace.profile_key(map, tx, 0)] = true
	var ok: bool = true
	for key in SimSpace.PROFILE.keys():
		if not reached.has(key):
			ok = _fail("FIXTURE", "no fixture tile reaches the profile key %s" % key)
	if not reached.has("water") or not reached.has("door.closed") or not reached.has("door.open"):
		ok = _fail("FIXTURE", "the fixture misses a class the lanes rely on")
	return ok


# --- BANDS ----------------------------------------------------------------------------------

func _bands(map: Variant) -> bool:
	var ok: bool = true
	for tx in int(map.w):
		var key: String = SimSpace.profile_key(map, tx, 0)
		var want: Array = _levels_of_bands(key)
		var mesh: ArrayMesh = DistrictView.tile_mesh(map, tx, 0)
		var got: Array = _levels_of_mesh(mesh)
		if got != want:
			ok = _fail("BANDS", "tile %d (%s) draws levels %s, its bands give %s" % [tx, key, got, want])
		if mesh != null and not _footprint_ok(mesh, tx, 0):
			ok = _fail("BANDS", "tile %d (%s) does not fill its full footprint" % [tx, key])
	# The built district is the same answer: its opaque mesh holds every opaque tile's levels and its
	# fence mesh holds the fence's, and nothing else.
	var view: Node3D = DistrictView.new()
	root.add_child(view)
	view.call("build", map)
	var walls_by_module: bool = not (view.get("wall_instances") as Array).is_empty()
	var want_solid: Array = []
	var want_fence: Array = []
	for tx in int(map.w):
		var key: String = SimSpace.profile_key(map, tx, 0)
		var levels: Array = _levels_of_bands(key)
		if key == "fence":
			want_fence.append_array(levels)
		elif not levels.is_empty():
			# A wall drawn by its kit module is measured by the KIT lane instead; the abstract band
			# answer above and `tile_mesh` still include it.
			if walls_by_module and key == "wall":
				continue
			want_solid.append_array(levels)
	var solids: MeshInstance3D = view.get("solids") as MeshInstance3D
	var fence: MeshInstance3D = view.get("fence") as MeshInstance3D
	var solid_levels: Array = _levels_of_mesh(solids.mesh as ArrayMesh if solids != null else null)
	var fence_levels: Array = _levels_of_mesh(fence.mesh as ArrayMesh if fence != null else null)
	if solid_levels != _unique_sorted(want_solid):
		ok = _fail("BANDS", "the built SolidTiles levels %s are not the opaque bands' %s" % [solid_levels, _unique_sorted(want_solid)])
	if fence_levels != _unique_sorted(want_fence):
		ok = _fail("BANDS", "the built FenceTiles levels %s are not the fence band's %s" % [fence_levels, _unique_sorted(want_fence)])
	if view.get("ground") == null:
		ok = _fail("BANDS", "the district built no GroundTiles mesh")
	view.queue_free()
	# True negative for the water: its tile draws no solid, and its surface is below the floor.
	var water_x: int = -1
	for tx in int(map.w):
		if SimSpace.profile_key(map, tx, 0) == "water":
			water_x = tx
	if water_x < 0 or DistrictView.tile_mesh(map, water_x, 0) != null:
		ok = _fail("BANDS", "water drew a solid")
	return ok


# --- OLD WAY --------------------------------------------------------------------------------

# The foundation's drawing, kept here only as the thing the gate must refuse: a window as one solid
# box from the floor to the top of the wall, and a Low tile not drawn at all.
func _old_way_boxes(map: Variant, tx: int) -> Array:
	var key: String = SimSpace.profile_key(map, tx, 0)
	if key == "window":
		return [{"min": Vector3(float(tx), 0.0, 0.0), "max": Vector3(float(tx) + 1.0, 2.55, 1.0), "colour": Color.WHITE, "transparent": false}]
	if key == "low":
		return []
	return DistrictView.tile_boxes(map, tx, 0)


func _old_way(map: Variant) -> bool:
	var ok: bool = true
	var refused: Array[String] = []
	for tx in int(map.w):
		var key: String = SimSpace.profile_key(map, tx, 0)
		if key != "window" and key != "low":
			continue
		var mesh: ArrayMesh = _mesh_of(_old_way_boxes(map, tx))
		if _levels_of_mesh(mesh) == _levels_of_bands(key):
			ok = _fail("OLD WAY", "the old-way %s at %d matched its bands and was not refused" % [key, tx])
		else:
			refused.append(key)
	if refused.size() != 2:
		ok = _fail("OLD WAY", "expected the old-way window and Low to be refused, refused %s" % [refused])
	return ok


func _mesh_of(boxes: Array) -> ArrayMesh:
	if boxes.is_empty():
		return null
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in boxes:
		DistrictView._add_box_of(st, box as Dictionary)
	st.generate_normals()
	return st.commit()


# --- BODIES ---------------------------------------------------------------------------------

func _bodies() -> bool:
	var ok: bool = true
	var world: Variant = SimBoot.playable(SimBoot.DISTRICT_SEED, SMALL_TILES)["world"]
	var survivor: int = -1
	var zombie: int = -1
	for ent in world.components.query(["position", "body"]):
		var e: int = int(ent)
		if e == int(world.player):
			continue
		if world.components.has_component(e, "zombieType"):
			if zombie < 0:
				zombie = e
		elif survivor < 0:
			survivor = e
	if survivor < 0 or zombie < 0:
		return _fail("BODIES", "the boot has no survivor and no zombie to measure")
	# The capsule is the fallback this lane measures: the models are off here, and the models lane in
	# check_first_person.gd holds the character models.
	var view: BodyView = BodyView.new()
	view.models_enabled = false
	root.add_child(view)
	view.build()
	view.reset(world)

	# Walking, then a crouch, then a crawl: each read by the view between frames.
	ok = _check_body(view, world, survivor, "a standing survivor") and ok
	world.components.set_component(survivor, "posture", SimStances.make_posture(SimStances.Stance.Crouch))
	view.apply(world, 1.0)
	ok = _check_body(view, world, survivor, "a crouched survivor") and ok
	world.components.set_component(survivor, "posture", SimStances.make_posture(SimStances.Stance.Crawl))
	view.apply(world, 1.0)
	ok = _check_body(view, world, survivor, "a crawling survivor") and ok
	ok = _check_body(view, world, zombie, "a whole zombie") and ok
	var body: Dictionary = (world.components.get_component(zombie, "body") as Dictionary).duplicate()
	body["legs"] = 0
	world.components.set_component(zombie, "body", body)
	view.apply(world, 1.0)
	ok = _check_body(view, world, zombie, "a zombie with its legs gone") and ok

	# True negative: a capsule, the foundation's body, is refused by the same comparison.
	var capsule: MeshInstance3D = MeshInstance3D.new()
	capsule.mesh = CapsuleMesh.new()
	if _cylinder_matches(capsule, 1.75):
		ok = _fail("BODIES", "a capsule was accepted as a cylinder")
	capsule.free()
	view.queue_free()
	return ok


func _check_body(view: BodyView, world: Variant, entity: int, what: String) -> bool:
	var node: MeshInstance3D = view.node_for(entity)
	if node == null:
		return _fail("BODIES", "%s has no view" % what)
	var want: float = float(int(SimSpace.body_of(world, entity)["height"])) / 1000.0
	if not _cylinder_matches(node, want):
		return _fail("BODIES", "%s draws a cylinder that is not %.3f m high at the hit radius" % [what, want])
	if absf(node.position.y - want * 0.5) > EPSILON_M:
		return _fail("BODIES", "%s stands with its centre at %.3f, not half its height" % [what, node.position.y])
	return true


func _cylinder_matches(node: MeshInstance3D, height_m: float) -> bool:
	var cylinder: CylinderMesh = node.mesh as CylinderMesh
	if cylinder == null:
		return false
	var radius_m: float = float(SimSpace.HIT_RADIUS_MM) / 1000.0
	return absf(cylinder.height - height_m) <= EPSILON_M and absf(cylinder.top_radius - radius_m) <= EPSILON_M and absf(cylinder.bottom_radius - radius_m) <= EPSILON_M


# --- KIT ------------------------------------------------------------------------------------

# The kit's wall module is the wall's drawing. The sim's band is 0..2550 over the tile; the module is
# 1.00 x 2.60 x 0.12 with its origin at the floor centre, so it is scaled to the band's top and its
# 0.12 m depth is the drawn thickness. Every wall tile in the fixture must carry one instance, the
# all-wall fixture must leave no band box behind, and each instance's AABB must be the band's height
# and the tile's width. A wrong-size module placed through the same function is the true negative.
func _kit(map: Variant) -> bool:
	if not FileAccess.file_exists(Assets.WALL_MODULE):
		print("FP_GEOMETRY_SKIP KIT: wall_module.glb is not on disk, so the band boxes are under test")
		return true
	var ok: bool = true
	var mesh: Mesh = _kit_mesh(Assets.WALL_MODULE)
	if mesh == null:
		return _fail("KIT", "wall_module.glb is on disk but did not load")
	var authored: Vector3 = mesh.get_aabb().size
	if not _size_close(authored, Assets.WALL_MODULE_SIZE):
		ok = _fail("KIT", "the wall module is authored %s, not the published %s" % [authored, Assets.WALL_MODULE_SIZE])
	var wall_tiles: Array = []
	for tx in int(map.w):
		if SimSpace.profile_key(map, tx, 0) == "wall":
			wall_tiles.append(Vector2i(tx, 0))
	var view: Node3D = DistrictView.new()
	root.add_child(view)
	view.call("build", map, 0)
	var instances: Array = view.get("wall_instances") as Array
	if instances.size() != wall_tiles.size():
		ok = _fail("KIT", "the view drew %d wall modules for %d wall tiles" % [instances.size(), wall_tiles.size()])
	for info in instances:
		var item: Dictionary = info as Dictionary
		var tile: Vector2i = item["tile"] as Vector2i
		var box: AABB = (item["transform"] as Transform3D) * mesh.get_aabb()
		if not _wall_aabb_ok(box, tile):
			ok = _fail("KIT", "wall tile %s draws %s, not the band at the module's thickness" % [tile, box])
	# The module is what draws the wall: an all-wall fixture leaves the opaque band mesh empty and
	# draws one instance per tile.
	var walls_only: Variant = _walls_only_map(4)
	var walls_view: Node3D = DistrictView.new()
	root.add_child(walls_view)
	walls_view.call("build", walls_only, 0)
	var walls_solids: MeshInstance3D = walls_view.get("solids") as MeshInstance3D
	if walls_solids != null and walls_solids.mesh != null:
		ok = _fail("KIT", "wall tiles are still drawn as band boxes beside the modules")
	var walls_instances: Array = walls_view.get("wall_instances") as Array
	if walls_instances.size() != 4:
		ok = _fail("KIT", "an all-wall fixture drew %d modules, not four" % walls_instances.size())
	walls_view.queue_free()
	# True negative: the same placement with a half-width module is refused by the same measurement.
	var planted: BoxMesh = BoxMesh.new()
	planted.size = Vector3(0.5, Assets.WALL_MODULE_SIZE.y, Assets.WALL_MODULE_SIZE.z)
	var first: Vector2i = wall_tiles[0] as Vector2i
	var planted_box: AABB = DistrictView.wall_placement(map, first.x, first.y, planted.get_aabb().size) * planted.get_aabb()
	if _wall_aabb_ok(planted_box, first):
		ok = _fail("KIT", "a planted half-width module was accepted as the wall band")
	view.queue_free()
	return ok


# The drawn module is the wall band: 0..2550 high to within 1 cm, one tile (1.00 m) along the run and
# the module's 0.12 m thickness across it, wholly inside the tile and flush to one of its edges.
func _wall_aabb_ok(box: AABB, tile: Vector2i) -> bool:
	var eps: float = 0.01
	var top: float = float(int(SimSpace.bands("wall")[0][1])) / 1000.0
	if absf(box.position.y) > eps or absf(box.end.y - top) > eps:
		return false
	var width: float = 1.0
	var depth: float = Assets.WALL_MODULE_SIZE.z
	var spans: bool = (absf(box.size.x - width) <= eps and absf(box.size.z - depth) <= eps) or (absf(box.size.z - width) <= eps and absf(box.size.x - depth) <= eps)
	if not spans:
		return false
	if box.position.x < float(tile.x) - eps or box.end.x > float(tile.x) + 1.0 + eps:
		return false
	if box.position.z < float(tile.y) - eps or box.end.z > float(tile.y) + 1.0 + eps:
		return false
	return absf(box.position.x - float(tile.x)) <= eps or absf(box.end.x - float(tile.x) - 1.0) <= eps or absf(box.position.z - float(tile.y)) <= eps or absf(box.end.z - float(tile.y) - 1.0) <= eps


func _walls_only_map(width: int) -> Variant:
	var map: Variant = SimTileMap.blank_map(width, 1, SimTileMap.Tile.Wall)
	return map


func _kit_mesh(path: String) -> Mesh:
	var node: Node = Assets.load_model(path)["node"] as Node
	var mesh: Mesh = Assets.first_mesh(node)
	if node != null:
		node.free()
	return mesh


func _size_close(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= 0.01 and absf(a.y - b.y) <= 0.01 and absf(a.z - b.z) <= 0.01


# --- FINISHES -------------------------------------------------------------------------------

func _finishes() -> bool:
	var templates: Dictionary = _building_templates()
	var manifest: Dictionary = BuildingView.read_manifest()
	var models: Array = manifest.get("models", []) as Array
	var ok: bool = true
	if models.size() != templates.size():
		ok = _fail("FINISHES", "manifest has %d models for %d content templates" % [models.size(), templates.size()])
	var wall_looks: Dictionary = {}
	var roof_looks: Dictionary = {}
	for template_v in templates.values():
		var template: Dictionary = template_v as Dictionary
		wall_looks[String((template.get("look", {}) as Dictionary).get("wall", ""))] = true
		roof_looks[String((template.get("look", {}) as Dictionary).get("roof", ""))] = true
	var manifest_walls: Dictionary = (manifest.get("looks", {}) as Dictionary).get("wall", {}) as Dictionary
	var manifest_roofs: Dictionary = (manifest.get("looks", {}) as Dictionary).get("roof", {}) as Dictionary
	for look in wall_looks:
		if not manifest_walls.has(look):
			ok = _fail("FINISHES", "wall look %s has no atlas variants" % look)
	for look in roof_looks:
		if not manifest_roofs.has(look):
			ok = _fail("FINISHES", "roof look %s has no atlas variants" % look)
	for id in templates:
		var template: Dictionary = templates[id] as Dictionary
		var entry: Dictionary = BuildingView.entry_for(id)
		if entry.is_empty():
			ok = _fail("FINISHES", "%s does not resolve to a model" % id)
			continue
		var loaded: Dictionary = Assets.load_model(String(entry.get("glb", "")))
		var node: Node3D = loaded["node"] as Node3D
		if node == null:
			ok = _fail("FINISHES", "%s model did not load" % id)
			continue
		var spatial: MeshInstance3D = _named_mesh(node, "spatial_bands")
		var finish: MeshInstance3D = _named_mesh(node, "finish")
		if spatial == null or finish == null:
			ok = _fail("FINISHES", "%s lacks spatial or finish geometry" % id)
			node.free()
			continue
		var glass_found: bool = false
		var counts: Dictionary = {"jamb": 0, "wall": 0, "window": 0}
		var wall_pieces: Dictionary = {}
		var window_pieces: Dictionary = {}
		for mesh_node in BuildingView.mesh_nodes(node):
			var instance: MeshInstance3D = mesh_node as MeshInstance3D
			var piece: Dictionary = BuildingView.parse_piece(String(instance.name))
			if not piece.is_empty():
				counts[piece["kind"]] = int(counts[piece["kind"]]) + 1
				if String(piece["kind"]) == "wall":
					wall_pieces[piece["tile"]] = true
				elif String(piece["kind"]) == "window":
					window_pieces[piece["tile"]] = true
			elif instance != spatial and instance != finish:
				ok = _fail("FINISHES", "%s has an unnamed mesh node %s the view would draw on every instance" % [id, instance.name])
			for surface in instance.mesh.get_surface_count():
				var material: BaseMaterial3D = instance.get_active_material(surface) as BaseMaterial3D
				if material == null or material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
					ok = _fail("FINISHES", "%s has an unfiltered or missing atlas material" % id)
				if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					glass_found = true
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					if instance == spatial:
						if not _spatial_vertex_allowed(template, vertex):
							ok = _fail("FINISHES", "%s spatial vertex %s leaves a wall band or tile" % [id, vertex])
					elif not _finish_vertex_allowed(template, vertex):
						ok = _fail("FINISHES", "%s finish vertex %s enters an open tile or sinks" % [id, vertex])
		if _template_has_window(template) and not glass_found:
			ok = _fail("FINISHES", "%s has windows but no transparent glazing" % id)
		var box: AABB = spatial.mesh.get_aabb()
		if absf(box.position.y) > EPSILON_M or absf(box.end.y - 2.55) > EPSILON_M:
			ok = _fail("FINISHES", "%s spatial height is %s, not 0..2.55" % [id, box])
		var expected: Dictionary = entry.get("pieces", {}) as Dictionary
		for kind in counts:
			if int(counts[kind]) != int(expected.get(kind, -1)):
				ok = _fail("FINISHES", "%s parsed %d %s pieces, the manifest counts %s" % [id, counts[kind], kind, expected.get(kind, "none")])
		var capped: Dictionary = {}
		for tile_v in BuildingView.capped_tiles(node, "spatial_bands"):
			capped[tile_v] = true
		for y in range(int((template["size"] as Dictionary)["h"])):
			for x in range(int((template["size"] as Dictionary)["w"])):
				var tile: Vector2i = Vector2i(x, y)
				var value: int = _template_tile(template, x, y)
				if value == 2 and not window_pieces.has(tile):
					ok = _fail("FINISHES", "%s window %d,%d has no window piece" % [id, x, y])
				if value != 1:
					continue
				if capped.has(tile) == wall_pieces.has(tile):
					ok = _fail("FINISHES", "%s wall %d,%d is capped %s" % [id, x, y, "twice" if capped.has(tile) else "by nothing"])
				elif wall_pieces.has(tile) and not window_pieces.has(tile):
					ok = _fail("FINISHES", "%s wall %d,%d can be taken away but has no window to draw instead" % [id, x, y])
		node.free()
	var house: Dictionary = templates.get("building.house.small", {}) as Dictionary
	if not house.is_empty():
		if _spatial_vertex_allowed(house, Vector3(1.5, 2.56, 0.5)):
			ok = _fail("FINISHES", "a planted vertex above the wall band was accepted")
		if _finish_vertex_allowed(house, Vector3(1.5, 1.2, 1.5)):
			ok = _fail("FINISHES", "a planted finish vertex in an open indoor tile was accepted")
		if not _finish_vertex_allowed(house, Vector3(1.5, 0.004, 1.5)):
			ok = _fail("FINISHES", "the valid indoor floor overlay was refused")
		ok = _finish_placement(house) and ok
	ok = _finish_worldgen(templates) and ok
	return ok


func _building_templates() -> Dictionary:
	var out: Dictionary = {}
	for filename in DirAccess.get_files_at("res://content/buildings"):
		if not filename.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/buildings/" + filename))
		if parsed is Dictionary:
			out[String((parsed as Dictionary).get("id", ""))] = parsed
	return out


func _named_mesh(node: Node, prefix: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name.begins_with(prefix):
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _named_mesh(child, prefix)
		if found != null:
			return found
	return null


func _template_tile(template: Dictionary, x: int, y: int) -> int:
	var size: Dictionary = template["size"] as Dictionary
	if x < 0 or y < 0 or x >= int(size["w"]) or y >= int(size["h"]):
		return 0
	for door_v in template.get("doors", []) as Array:
		var door: Dictionary = door_v as Dictionary
		if int(door["x"]) == x and int(door["y"]) == y:
			return 6
	return int((template["tiles"] as Array)[y * int(size["w"]) + x])


func _template_indoors(template: Dictionary, x: int, y: int) -> bool:
	var size: Dictionary = template["size"] as Dictionary
	if x < 0 or y < 0 or x >= int(size["w"]) or y >= int(size["h"]):
		return false
	return int((template["indoors"] as Array)[y * int(size["w"]) + x]) != 0


func _candidate_tiles(x: float, z: float) -> Array:
	var xs: Array = [floori(x)]
	var ys: Array = [floori(z)]
	if absf(x - roundf(x)) <= EPSILON_M:
		xs.append(floori(x) - 1)
		xs.append(floori(x) + 1)
	if absf(z - roundf(z)) <= EPSILON_M:
		ys.append(floori(z) - 1)
		ys.append(floori(z) + 1)
	var out: Array = []
	for tx in xs:
		for ty in ys:
			out.append(Vector2i(tx, ty))
	return out


func _spatial_vertex_allowed(template: Dictionary, point: Vector3) -> bool:
	if point.y < -EPSILON_M or point.y > 2.55 + EPSILON_M:
		return false
	for tile_v in _candidate_tiles(point.x, point.z):
		var tile: Vector2i = tile_v as Vector2i
		if _template_tile(template, tile.x, tile.y) == 1:
			return true
	return false


func _finish_vertex_allowed(template: Dictionary, point: Vector3) -> bool:
	if point.y < -EPSILON_M:
		return false
	if point.y >= 2.50:
		return true
	for tile_v in _candidate_tiles(point.x, point.z):
		var tile: Vector2i = tile_v as Vector2i
		if point.y <= 0.005 and _template_indoors(template, tile.x, tile.y):
			return true
		if _template_tile(template, tile.x, tile.y) in [1, 2, 6]:
			return true
	var centre: Vector2i = Vector2i(floori(point.x), floori(point.z))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tile: Vector2i = centre + Vector2i(dx, dy)
			if _template_tile(template, tile.x, tile.y) not in [1, 2, 6]:
				continue
			var nearest: Vector2 = Vector2(clampf(point.x, tile.x, tile.x + 1), clampf(point.z, tile.y, tile.y + 1))
			if nearest.distance_to(Vector2(point.x, point.z)) <= 0.025:
				return true
	return false


func _template_has_window(template: Dictionary) -> bool:
	for tile in template.get("tiles", []) as Array:
		if int(tile) == 2:
			return true
	return false


func _finish_placement(template: Dictionary) -> bool:
	var map: Variant = SimTileMap.blank_map(16, 14)
	SimTemplates.stamp(map, template, 3, 2)
	map.tiles[8 * int(map.w) + 6] = SimTileMap.Tile.Door
	map.buildings.append({"id": "building.house.small", "x": 3, "y": 2, "w": 9, "h": 7, "doors": [{"x": 6, "y": 8}]})
	var view: Node3D = DistrictView.new()
	root.add_child(view)
	view.call("build", map, 20261101)
	var ok: bool = true
	var dresser: Node3D = view.get("building_finishes") as Node3D
	var instances: Array = dresser.get("instances") as Array if dresser != null else []
	if instances.size() != 1:
		ok = _fail("FINISHES", "stamped house drew %d finish instances, not one" % instances.size())
	elif int((instances[0] as Dictionary)["variant"]) != BuildingView.placement_hash(20261101, map.buildings[0]) % 3:
		ok = _fail("FINISHES", "stamped house variant is not the seeded manifest choice")
	if not (view.get("wall_instances") as Array).is_empty():
		ok = _fail("FINISHES", "finished house also drew fallback wall modules")
	view.queue_free()
	var baseline: Node3D = DistrictView.new()
	baseline.set("building_finishes_enabled", false)
	root.add_child(baseline)
	baseline.call("build", map, 20261101)
	if baseline.get("building_finishes") != null or (baseline.get("wall_instances") as Array).is_empty():
		ok = _fail("FINISHES", "disabled finishes did not restore the exact wall-module baseline")
	baseline.queue_free()
	return ok


# --- WORLDGEN -------------------------------------------------------------------------------

const FINISH_DISTRICTS: Array[String] = [
	"district.residential_suburb",
	"district.town_center",
	"district.industrial_park",
	"district.forest_edge",
]
const SIDE_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _finish_worldgen(templates: Dictionary) -> bool:
	var ok: bool = true
	var windows: int = 0
	var opened: int = 0
	var planted: bool = false
	var ceilings: Dictionary = {"judged": 0, "furnished": 0, "missing": 0, "first": "", "stripped": false, "templates": {}, "template_tiles": {}}
	for district_id in FINISH_DISTRICTS:
		var boot: Dictionary = SimBoot.bare(SimBoot.DISTRICT_SEED, SimTileMap.DISTRICT_TILES, district_id)
		var map: Variant = boot["map"]
		var view: Node3D = DistrictView.new()
		root.add_child(view)
		view.call("build", map, SimBoot.DISTRICT_SEED)
		var judged: Dictionary = _judge_windows(view, map, templates)
		for failure in judged["failures"] as Array:
			ok = _fail("WORLDGEN", "%s: %s" % [district_id, failure])
		windows += int(judged["windows"])
		opened += int(judged["opened"])
		var target: Variant = judged["opened_tile"]
		if not planted and target != null:
			planted = true
			# True negative: the review's defect, a wall drawn over a window worldgen opened.
			var wrong: Node3D = DistrictView.new()
			wrong.set("building_force_wall", {target: true})
			root.add_child(wrong)
			wrong.call("build", map, SimBoot.DISTRICT_SEED)
			var refused: Dictionary = _judge_windows(wrong, map, templates)
			var blocked: bool = false
			for failure in refused["failures"] as Array:
				if String(failure).begins_with("window %s is blocked" % [target]):
					blocked = true
			if not blocked:
				ok = _fail("WORLDGEN", "a solid wall planted over sim window %s was accepted" % [target])
			wrong.free()
			# True negative: the baseline still draws its band boxes under every finished tile.
			var baseline: Node3D = DistrictView.new()
			baseline.set("building_finishes_enabled", false)
			root.add_child(baseline)
			baseline.call("build", map, SimBoot.DISTRICT_SEED)
			var drawn: Dictionary = (view.get("building_finishes") as Node3D).get("drawn") as Dictionary
			if _legacy_boxes(baseline, map, drawn) == 0:
				ok = _fail("WORLDGEN", "the band-box count found nothing in a baseline that draws the boxes")
			baseline.free()
		ok = _ceiling_district(view, map, district_id, ceilings) and ok
		view.free()
	print("FP_GEOMETRY WORLDGEN judged %d sim windows in finished buildings across %d districts, %d of them opened by worldgen" % [windows, FINISH_DISTRICTS.size(), opened])
	if windows == 0 or opened == 0:
		ok = _fail("WORLDGEN", "judged %d sim windows, %d opened by worldgen: nothing to judge" % [windows, opened])
	if not planted:
		ok = _fail("WORLDGEN", "no window worldgen opened, so the planted wall was never tried")
	print("FP_GEOMETRY CEILINGS judged %d indoor tiles in finished buildings across %d districts, %d of them counter, shelf or partition tiles, %d without a ceiling" % [ceilings["judged"], FINISH_DISTRICTS.size(), ceilings["furnished"], ceilings["missing"]])
	if int(ceilings["missing"]) > 0:
		ok = _fail("CEILINGS", "%d of %d indoor tiles have no ceiling at %d mm (%d distinct tiles of %d templates); the first is %s" % [ceilings["missing"], ceilings["judged"], SimSpace.FULL_MM, (ceilings["template_tiles"] as Dictionary).size(), (ceilings["templates"] as Dictionary).size(), ceilings["first"]])
	if int(ceilings["judged"]) == 0 or int(ceilings["furnished"]) == 0:
		ok = _fail("CEILINGS", "judged %d indoor tiles, %d of them furnished: nothing to judge" % [ceilings["judged"], ceilings["furnished"]])
	if not bool(ceilings["stripped"]):
		ok = _fail("CEILINGS", "no ceiling was stripped, so the planted error was never tried")
	return ok


# Every footprint tile of every finished building in a built district view, against the sim's
# profile there. Returns {failures, windows, opened, opened_tile}.
func _judge_windows(view: Node3D, map: Variant, templates: Dictionary) -> Dictionary:
	var failures: Array = []
	var windows: int = 0
	var opened: int = 0
	var opened_tile: Variant = null
	var dresser: Node3D = view.get("building_finishes") as Node3D
	if dresser == null:
		return {"failures": ["no finished buildings were built"], "windows": 0, "opened": 0, "opened_tile": null}
	var drawn: Dictionary = dresser.get("drawn") as Dictionary
	for instance_v in dresser.get("instances") as Array:
		var instance: Dictionary = instance_v as Dictionary
		var record: Dictionary = instance["building"] as Dictionary
		var template: Dictionary = templates.get(String(record.get("id", "")), {}) as Dictionary
		var origin: Vector2i = Vector2i(int(record["x"]), int(record["y"]))
		var buckets: Dictionary = _opaque_buckets(instance["node"] as Node3D)
		for y in range(origin.y, origin.y + int(record["h"])):
			for x in range(origin.x, origin.x + int(record["w"])):
				var tile: Vector2i = Vector2i(x, y)
				var key: String = SimSpace.profile_key(map, x, y)
				var kind: String = String(drawn.get(tile, ""))
				if key == "wall" and kind != "wall":
					failures.append("sim wall %s is drawn as %s" % [tile, kind if kind != "" else "nothing"])
				if key != "window":
					continue
				windows += 1
				if _template_tile(template, x - origin.x, y - origin.y) == 1:
					opened += 1
					if opened_tile == null:
						opened_tile = tile
				if kind != "window":
					failures.append("sim window %s is drawn as %s" % [tile, kind if kind != "" else "nothing"])
				failures.append_array(_window_rays(map, tile, buckets))
	var boxes: int = _legacy_boxes(view, map, drawn)
	if boxes > 0:
		failures.append("%d band-box faces are still drawn under tiles the buildings draw" % boxes)
	return {"failures": failures, "windows": windows, "opened": opened, "opened_tile": opened_tile}


# Rays across one window tile from each face that meets open ground: from 5 cm outside to past the
# centre, at two points along the face. The aperture heights must pass, the sill and lintel must not.
func _window_rays(map: Variant, tile: Vector2i, buckets: Dictionary) -> Array:
	var failures: Array = []
	var near: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			near.append_array(buckets.get(tile + Vector2i(dx, dy), []) as Array)
	var sides: int = 0
	for side in 4:
		var offset: Vector2i = SIDE_OFFSETS[side]
		var neighbour: int = SimTileMap.tile_at(map, tile.x + offset.x, tile.y + offset.y)
		if neighbour in [SimTileMap.Tile.Wall, SimTileMap.Tile.Window, SimTileMap.Tile.Tree, SimTileMap.Tile.Water]:
			continue
		sides += 1
		var normal: Vector3 = Vector3(float(offset.x), 0.0, float(offset.y))
		var origin: Vector3 = Vector3(float(tile.x + (1 if side == 1 else 0)), 0.0, float(tile.y + (1 if side == 2 else 0)))
		var along_axis: Vector3 = Vector3(1, 0, 0) if side in [0, 2] else Vector3(0, 0, 1)
		for along in [0.3, 0.7]:
			for probe in [[0.5, true], [1.25, false], [1.85, false], [2.3, true]]:
				var base: Vector3 = origin + along_axis * float(along) + Vector3(0.0, float(probe[0]), 0.0)
				var hit: bool = _segment_hits(base + normal * 0.05, base - normal * 0.6, near)
				if hit != bool(probe[1]):
					var what: String = "is open in its sill or lintel" if bool(probe[1]) else "is blocked in its aperture"
					failures.append("window %s %s at %.2f m, side %d" % [tile, what, float(probe[0]), side])
	if sides == 0:
		failures.append("window %s has no face on open ground to look through" % [tile])
	return failures


func _segment_hits(from: Vector3, to: Vector3, triangles: Array) -> bool:
	for triangle_v in triangles:
		var t: PackedVector3Array = triangle_v as PackedVector3Array
		if Geometry3D.segment_intersects_triangle(from, to, t[0], t[1], t[2]) != null:
			return true
	return false


# Every opaque triangle a finished instance draws, in world space, bucketed by each tile its bounds
# touch. Glass is left out: it is transparent and the sim's aperture is clear.
func _opaque_buckets(node: Node3D) -> Dictionary:
	var buckets: Dictionary = {}
	for mesh_node in BuildingView.mesh_nodes(node):
		var instance: MeshInstance3D = mesh_node as MeshInstance3D
		var xform: Transform3D = instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var material: BaseMaterial3D = instance.get_active_material(surface) as BaseMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0, count, 3):
				var a: Vector3 = xform * vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = xform * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = xform * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				if a.y > 2.56 and b.y > 2.56 and c.y > 2.56:
					continue
				var triangle: PackedVector3Array = PackedVector3Array([a, b, c])
				for tx in range(floori(minf(a.x, minf(b.x, c.x)) - 0.001), floori(maxf(a.x, maxf(b.x, c.x)) + 0.001) + 1):
					for tz in range(floori(minf(a.z, minf(b.z, c.z)) - 0.001), floori(maxf(a.z, maxf(b.z, c.z)) + 0.001) + 1):
						var key: Vector2i = Vector2i(tx, tz)
						if not buckets.has(key):
							buckets[key] = []
						(buckets[key] as Array).append(triangle)
	return buckets


# --- CEILINGS -------------------------------------------------------------------------------

# The highest ceiling face counted: the top of every full-height band, the height the sim publishes.
const CEILING_TOP_M: float = float(SimSpace.FULL_MM) / 1000.0
# How far under it, or under a head band's bottom, a closing face may sit (the GLBs draw the ceiling
# 5 mm under, clear of the wall caps).
const CEILING_SLACK_M: float = 0.025
# No face lower than this is gathered as a ceiling: under every head band the profile holds.
const CEILING_FLOOR_M: float = 1.5
# Two points per tile, off both diagonals, so each triangle of a one-quad ceiling is crossed.
const CEILING_PROBES: Array[Vector2] = [Vector2(0.3, 0.6), Vector2(0.7, 0.4)]


# Judge one built district's ceilings into `totals`, and the first time a furnished tile (a counter,
# shelf or partition: the tiles the old build left open to the sky) passes, strip its ceiling from the
# instance's mesh in memory and require the same rays to refuse that tile.
func _ceiling_district(view: Node3D, map: Variant, district_id: String, totals: Dictionary) -> bool:
	var dresser: Node3D = view.get("building_finishes") as Node3D
	if dresser == null:
		return _fail("CEILINGS", "%s: no finished buildings were built" % district_id)
	var ok: bool = true
	for instance_v in dresser.get("instances") as Array:
		var instance: Dictionary = instance_v as Dictionary
		var judged: Dictionary = _judge_ceilings(map, instance)
		totals["judged"] = int(totals["judged"]) + int(judged["judged"])
		totals["furnished"] = int(totals["furnished"]) + int(judged["furnished"])
		var missing: Array = judged["missing"] as Array
		if not missing.is_empty():
			if int(totals["missing"]) == 0:
				totals["first"] = "%s in %s (%s)" % [missing[0], (instance["building"] as Dictionary).get("id", ""), district_id]
			totals["missing"] = int(totals["missing"]) + missing.size()
			var record: Dictionary = instance["building"] as Dictionary
			(totals["templates"] as Dictionary)[record.get("id", "")] = true
			for tile_v in missing:
				var local: Vector2i = (tile_v as Vector2i) - Vector2i(int(record["x"]), int(record["y"]))
				(totals["template_tiles"] as Dictionary)["%s %s" % [record.get("id", ""), local]] = true
		var target: Variant = judged["covered_furnished"]
		if bool(totals["stripped"]) or target == null:
			continue
		totals["stripped"] = true
		# True negative: the defect the review found, one furnished tile with no ceiling over it.
		var removed: int = _strip_ceiling(instance["node"] as Node3D, target as Vector2i)
		var refused: Array = _judge_ceilings(map, instance)["missing"] as Array
		if removed == 0 or refused != [target]:
			ok = _fail("CEILINGS", "%s: the ceiling stripped from %s (%d triangles) was not refused there; the rays found %s" % [district_id, target, removed, refused])
	return ok


# One finished instance's indoor tiles against its downward-facing faces at the ceiling height.
# Returns {judged, furnished, missing: [tile], covered_furnished: the first furnished tile with a
# ceiling, or null}.
func _judge_ceilings(map: Variant, instance: Dictionary) -> Dictionary:
	var record: Dictionary = instance["building"] as Dictionary
	var faces: Dictionary = _ceiling_faces(instance["node"] as Node3D)
	var judged: int = 0
	var furnished: int = 0
	var missing: Array = []
	var covered_furnished: Variant = null
	for y in range(int(record["y"]), int(record["y"]) + int(record["h"])):
		for x in range(int(record["x"]), int(record["x"]) + int(record["w"])):
			if not SimTileMap.is_indoors(map, x, y):
				continue
			var tile_class: int = SimTileMap.tile_at(map, x, y)
			if tile_class == SimTileMap.Tile.Wall:
				continue
			var tile: Vector2i = Vector2i(x, y)
			var is_furnished: bool = tile_class in [SimTileMap.Tile.Screen, SimTileMap.Tile.Low]
			judged += 1
			if is_furnished:
				furnished += 1
			var low: float = _ceiling_low(SimSpace.profile_key(map, x, y))
			var near: Array = []
			for face_v in faces.get(tile, []) as Array:
				var face: PackedVector3Array = face_v as PackedVector3Array
				if face[0].y >= low:
					near.append(face)
			var covered: bool = true
			for probe in CEILING_PROBES:
				var foot: Vector3 = Vector3(float(x) + probe.x, 0.05, float(y) + probe.y)
				if not _segment_hits(foot, Vector3(foot.x, CEILING_TOP_M + EPSILON_M, foot.z), near):
					covered = false
			if not covered:
				missing.append(tile)
			elif is_furnished and covered_furnished == null:
				covered_furnished = tile
	return {"judged": judged, "furnished": furnished, "missing": missing, "covered_furnished": covered_furnished}


# The lowest a face closing this profile key from above may sit: CEILING_SLACK_M under the bottom of
# a head band (one reaching FULL_MM from above the floor), or under FULL_MM itself.
func _ceiling_low(key: String) -> float:
	var low: float = CEILING_TOP_M
	for band_v in SimSpace.bands(key):
		var band: Array = band_v as Array
		if int(band[1]) == SimSpace.FULL_MM and int(band[0]) > 0:
			low = minf(low, float(band[0]) / 1000.0)
	return low - CEILING_SLACK_M


# The flat downward-facing triangles an instance draws from CEILING_FLOOR_M up to 1 mm over the
# ceiling height, in world space, bucketed by each tile their bounds touch.
func _ceiling_faces(node: Node3D) -> Dictionary:
	var buckets: Dictionary = {}
	for mesh_node in BuildingView.mesh_nodes(node):
		var instance: MeshInstance3D = mesh_node as MeshInstance3D
		var xform: Transform3D = instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			for triangle_v in _surface_ceiling_triangles(arrays, xform, CEILING_FLOOR_M):
				var t: PackedVector3Array = (triangle_v as Array)[1] as PackedVector3Array
				for tx in range(floori(minf(t[0].x, minf(t[1].x, t[2].x)) - 0.001), floori(maxf(t[0].x, maxf(t[1].x, t[2].x)) + 0.001) + 1):
					for tz in range(floori(minf(t[0].z, minf(t[1].z, t[2].z)) - 0.001), floori(maxf(t[0].z, maxf(t[1].z, t[2].z)) + 0.001) + 1):
						var key: Vector2i = Vector2i(tx, tz)
						if not buckets.has(key):
							buckets[key] = []
						(buckets[key] as Array).append(t)
	return buckets


# Each ceiling triangle of one surface as [first index position, world triangle]. A triangle counts
# when its three corners sit level, at or above `low` and no higher than 1 mm over the ceiling
# height, and its vertex normals face down.
func _surface_ceiling_triangles(arrays: Array, xform: Transform3D, low: float) -> Array:
	var out: Array = []
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if arrays[Mesh.ARRAY_NORMAL] == null:
		return out
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	var high: float = CEILING_TOP_M + EPSILON_M
	for i in range(0, count, 3):
		var ia: int = indices[i] if not indices.is_empty() else i
		var ib: int = indices[i + 1] if not indices.is_empty() else i + 1
		var ic: int = indices[i + 2] if not indices.is_empty() else i + 2
		var a: Vector3 = xform * vertices[ia]
		var b: Vector3 = xform * vertices[ib]
		var c: Vector3 = xform * vertices[ic]
		if a.y < low or a.y > high or absf(a.y - b.y) > EPSILON_M or absf(a.y - c.y) > EPSILON_M:
			continue
		if (xform.basis * (normals[ia] + normals[ib] + normals[ic])).y >= 0.0:
			continue
		out.append([i, PackedVector3Array([a, b, c])])
	return out


# The planted error: drop from the instance's meshes, in memory only, every ceiling triangle within
# CEILING_SLACK_M of the ceiling height whose centre is over `tile`. Each touched node gets its own copy of the mesh. Returns the triangles
# removed.
func _strip_ceiling(node: Node3D, tile: Vector2i) -> int:
	var removed: int = 0
	for mesh_node in BuildingView.mesh_nodes(node):
		var instance: MeshInstance3D = mesh_node as MeshInstance3D
		var source: Mesh = instance.mesh
		var stripped: ArrayMesh = ArrayMesh.new()
		var touched: bool = false
		for surface in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_INDEX] != null:
				var drop: Dictionary = {}
				for triangle_v in _surface_ceiling_triangles(arrays, instance.global_transform, CEILING_TOP_M - CEILING_SLACK_M):
					var t: PackedVector3Array = (triangle_v as Array)[1] as PackedVector3Array
					var centre: Vector3 = (t[0] + t[1] + t[2]) / 3.0
					if Vector2i(floori(centre.x), floori(centre.z)) == tile:
						drop[int((triangle_v as Array)[0])] = true
				if not drop.is_empty():
					var old: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var kept: PackedInt32Array = PackedInt32Array()
					for i in range(0, old.size(), 3):
						if not drop.has(i):
							kept.append_array([old[i], old[i + 1], old[i + 2]])
					arrays[Mesh.ARRAY_INDEX] = kept
					removed += drop.size()
					touched = true
			stripped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			stripped.surface_set_material(stripped.get_surface_count() - 1, source.surface_get_material(surface))
		if touched:
			instance.mesh = stripped
	return removed


# How many of the district's band-box faces sit under a tile a finished building drew as its sim
# profile. Every box has a top face over its whole tile, so a horizontal triangle's centroid names
# the tile its box belongs to.
func _legacy_boxes(view: Node3D, map: Variant, drawn: Dictionary) -> int:
	var solids: MeshInstance3D = view.get("solids") as MeshInstance3D
	if solids == null or solids.mesh == null:
		return 0
	var count: int = 0
	for surface in solids.mesh.get_surface_count():
		var arrays: Array = solids.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var total: int = indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, total, 3):
			var a: Vector3 = vertices[indices[i] if not indices.is_empty() else i]
			var b: Vector3 = vertices[indices[i + 1] if not indices.is_empty() else i + 1]
			var c: Vector3 = vertices[indices[i + 2] if not indices.is_empty() else i + 2]
			if absf(a.y - b.y) > EPSILON_M or absf(a.y - c.y) > EPSILON_M:
				continue
			var centre: Vector3 = (a + b + c) / 3.0
			var tile: Vector2i = Vector2i(floori(centre.x), floori(centre.z))
			var kind: String = String(drawn.get(tile, ""))
			if kind != "" and kind == SimSpace.profile_key(map, tile.x, tile.y):
				count += 1
	return count


# --- helpers --------------------------------------------------------------------------------

func _levels_of_bands(key: String) -> Array:
	var out: Array = []
	for band in SimSpace.bands(key):
		out.append(int(band[0]))
		out.append(int(band[1]))
	return _unique_sorted(out)


func _levels_of_mesh(mesh: ArrayMesh) -> Array:
	var out: Array = []
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			out.append(roundi(v.y * 1000.0))
	return _unique_sorted(out)


func _footprint_ok(mesh: ArrayMesh, tx: int, ty: int) -> bool:
	var box: AABB = mesh.get_aabb()
	return absf(box.position.x - float(tx)) <= EPSILON_M and absf(box.end.x - float(tx + 1)) <= EPSILON_M and absf(box.position.z - float(ty)) <= EPSILON_M and absf(box.end.z - float(ty + 1)) <= EPSILON_M


func _unique_sorted(values: Array) -> Array:
	var seen: Dictionary = {}
	for v in values:
		seen[int(v)] = true
	var out: Array = seen.keys()
	out.sort()
	return out

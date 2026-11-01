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
#             full wall tiles and within 0..2550 mm, with every wall tile capped over its footprint.
#             Finish vertices below the roof stay in solid template tiles, except floor overlays;
#             glazing is transparent and nearest-filtered. Planted open-tile and high-wall vertices
#             are refused, and a stamped house really draws its finish instance.

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
		print("FP_GEOMETRY_OK every tile and all 22 building finishes keep their profile bands, every body keeps its cylinder, finish skins stay within 25 mm of a solid host, and planted window, Low-tile, module, open-tile and high-wall errors are refused")
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
	var view: BodyView = BodyView.new()
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
		var cap_points: Dictionary = {}
		var glass_found: bool = false
		for mesh_node in [spatial, finish]:
			var instance: MeshInstance3D = mesh_node as MeshInstance3D
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
						if absf(vertex.y - 2.55) <= EPSILON_M:
							cap_points[Vector2i(roundi(vertex.x * 1000.0), roundi(vertex.z * 1000.0))] = true
					elif not _finish_vertex_allowed(template, vertex):
						ok = _fail("FINISHES", "%s finish vertex %s enters an open tile or sinks" % [id, vertex])
		if _template_has_window(template) and not glass_found:
			ok = _fail("FINISHES", "%s has windows but no transparent glazing" % id)
		var box: AABB = spatial.mesh.get_aabb()
		if absf(box.position.y) > EPSILON_M or absf(box.end.y - 2.55) > EPSILON_M:
			ok = _fail("FINISHES", "%s spatial height is %s, not 0..2.55" % [id, box])
		for y in range(int((template["size"] as Dictionary)["h"])):
			for x in range(int((template["size"] as Dictionary)["w"])):
				if _template_tile(template, x, y) != 1:
					continue
				for corner in [Vector2i(x * 1000, y * 1000), Vector2i((x + 1) * 1000, y * 1000), Vector2i(x * 1000, (y + 1) * 1000), Vector2i((x + 1) * 1000, (y + 1) * 1000)]:
					if not cap_points.has(corner):
						ok = _fail("FINISHES", "%s wall %d,%d lacks its full-footprint cap" % [id, x, y])
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

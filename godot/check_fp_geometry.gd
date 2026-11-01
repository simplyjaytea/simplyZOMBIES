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

const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const SimSpace = preload("res://sim/space/space.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
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
	_finish(ok)


func _finish(ok: bool) -> void:
	if ok:
		print("FP_GEOMETRY_OK every tile's built mesh has exactly its profile bands and every body its cylinder; the old-way window and Low tile are refused")
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
	var want_solid: Array = []
	var want_fence: Array = []
	for tx in int(map.w):
		var key: String = SimSpace.profile_key(map, tx, 0)
		var levels: Array = _levels_of_bands(key)
		if key == "fence":
			want_fence.append_array(levels)
		elif not levels.is_empty():
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

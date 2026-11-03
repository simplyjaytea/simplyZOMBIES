extends RefCounted
# The first-person art seam. Nothing here is required for the foundation to boot: every path is
# optional, and a missing model falls back to the placeholder box the view builds itself. That is
# deliberate -- the art worker owns `godot/assets/first_person/`, and this branch must not depend on
# files that have not merged yet.
#
# Conventions for whoever lands the models, repeated here so the contract travels with the code:
#   - glTF 2.0 `.glb`, +Y up, Godot forward -Z.
#   - Metres. A tile is one metre (`SimTileMap.TILE_METRES`).
#   - Origin at the floor centre, except the ledger: origin at its bottom centre, so it can stand
#     on the desk without a second offset.
#   - desk height 0.78 m; ledger 0.30 m x 0.22 m (x by z).
#
# The names are the seam: `desk.glb`, `ledger.glb`, `shelf.glb`, `barricade.glb`, `wall_module.glb`.
# The desk and ledger are read by `prop_view.gd`, the shelf by `container_view.gd`, and the barricade
# and wall module by `district_view.gd`. Building finishes use the manifest in `building_view.gd`.

const DIR: String = "res://assets/first_person/"
const DESK: String = DIR + "desk.glb"
const LEDGER: String = DIR + "ledger.glb"
const SHELF: String = DIR + "shelf.glb"
const BARRICADE: String = DIR + "barricade.glb"
const WALL_MODULE: String = DIR + "wall_module.glb"

const DESK_HEIGHT_M: float = 0.78
const DESK_WIDTH_M: float = 1.20
const DESK_DEPTH_M: float = 0.62
const LEDGER_WIDTH_M: float = 0.30
const LEDGER_DEPTH_M: float = 0.22
const LEDGER_THICKNESS_M: float = 0.026
const SHELF_SIZE: Vector3 = Vector3(0.90, 1.85, 0.32)
const BARRICADE_SIZE: Vector3 = Vector3(1.20, 1.10, 0.18)
const WALL_MODULE_SIZE: Vector3 = Vector3(1.00, 2.60, 0.12)
# Where the ledger's centre sits above the floor: the desk top plus half its own thickness. The
# ledger's authored origin is its bottom centre, so its node is placed on the desk top instead.
const LEDGER_TOP_M: float = DESK_HEIGHT_M + LEDGER_THICKNESS_M


## Reads the model at `path` straight from its bytes, with no dependency on the import system. A
## clean checkout has no `.import` files, so `ResourceLoader` would see nothing; `FileAccess` reads
## the file wherever it is (on disk, or packed into an export, which `export_presets.cfg` makes sure of).
## Returns {"node": Node3D, "source": "disk"} when it loaded, or {"node": null, "source": ...} with
## "missing" (no file) or "unreadable" (a file that is not a glTF the engine can read). Callers fall back
## to the published-size box on null, and the gate reads "source" to say which path ran.
##
## Materials are forced to nearest filtering with mipmaps: the atlas is 64 texels per metre, so at
## 720p minification begins at about 7 m (the independent art review's #281 note), and nearest with
## no mipmaps shimmers beyond that. Nearest magnification keeps the pixel art crisp up close. Back-face
## culling is left as authored.
static func load_model(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"node": null, "source": "missing"}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"node": null, "source": "unreadable"}
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_buffer(bytes, path.get_base_dir() + "/", state) != OK:
		return {"node": null, "source": "unreadable"}
	var root: Node = document.generate_scene(state)
	if not (root is Node3D):
		return {"node": null, "source": "unreadable"}
	_nearest(root)
	return {"node": root as Node3D, "source": "disk"}


static func _nearest(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(s)
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for child in node.get_children():
		_nearest(child)


## The first mesh in a loaded model, or null. A kit GLB is one mesh under a Node3D root, but the walk
## keeps the seam honest if the exporter ever wraps it differently. The mesh keeps the material
## `load_model` filtered, so a MultiMesh built from it inherits the filter.
static func first_mesh(node: Node) -> Mesh:
	if node == null:
		return null
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found: Mesh = first_mesh(child)
		if found != null:
			return found
	return null

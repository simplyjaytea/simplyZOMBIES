extends RefCounted
# The first-person model loader: manifests in, instances out. Presentation only -- it reads the
# manifests and the GLB bytes, and it writes nothing into the sim.
#
# A manifest is a `*.manifest.json` under `res://assets/first_person/`. Each entry names a GLB and
# the item it draws, by `match`: an item id (`{"id": ...}`), optionally qualified by `receiver`, or
# a class (`{"class": ...}`). A receiver-qualified id beats an unqualified id, which beats a class.
# An item with no match resolves to null, so the caller keeps whatever placeholder it already has.
#
# Loading is from bytes, as `assets.gd` does, so a clean checkout needs no `.import` files. Each GLB is
# parsed once and cached as a template that is never put in the tree; `instance_of` hands out a
# duplicate that shares the template's meshes and materials. Embedded textures are deduplicated by the
# hash of their decoded pixels, so two GLBs that embed the same atlas share one texture. Each shared
# texture gets mipmaps generated from its image, and its material samples with nearest-with-mipmaps,
# so the mipmaps are real and not just requested. `assets.gd` sends its textures through the same table.
# A material whose UVs stay inside the atlas samples it clamped, not repeating (`kit_sampling.gd`).

const KitSampling = preload("res://presentation/first_person/kit_sampling.gd")

const DIR: String = "res://assets/first_person/"
const MANIFEST_SUFFIX: String = ".manifest.json"
const MIPMAP_FILTER: int = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
const HIDDEN_SLOTS: Array[String] = ["internal", "spring", "sear", "extractor"]

# Parsed manifests, read once from the directory, in file-name order so the answer never depends on
# the order the filesystem lists them.
static var _manifests: Array = []
static var _manifests_read: bool = false
# GLB path -> the template root (never in the tree).
static var _templates: Dictionary = {}
# Content hash of a texture's pixels -> the one shared, mipmapped texture for it.
static var _textures: Dictionary = {}


## Every parsed manifest, read once. An unreadable or malformed file is skipped rather than fatal, so one
## bad kit cannot take down the rest.
static func manifests() -> Array:
	if _manifests_read:
		return _manifests
	_manifests_read = true
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return _manifests
	for file in dir.get_files():
		if file.ends_with(MANIFEST_SUFFIX):
			names.append(file)
	names.sort()
	for file in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
		if parsed is Dictionary and (parsed as Dictionary).get("models") is Array:
			_manifests.append(parsed)
	return _manifests


## The manifest entry that draws an item, or null. A receiver-qualified id match beats an unqualified
## id match, which beats a class match, in any manifest. Qualified entries never match another receiver.
static func resolve(item_id: String, item_class: String, receiver_id: String = "") -> Variant:
	return resolve_in(manifests(), item_id, item_class, receiver_id)


## `resolve`, over a list of manifests the caller holds. The gate uses it to test the rule on fabricated
## manifests as well as the real ones.
static func resolve_in(manifest_list: Array, item_id: String, item_class: String, receiver_id: String = "") -> Variant:
	if not item_id.is_empty() and not receiver_id.is_empty():
		for manifest in manifest_list:
			for entry in (manifest as Dictionary)["models"] as Array:
				var match_block: Dictionary = (entry as Dictionary).get("match", {}) as Dictionary
				if String(match_block.get("id", "")) == item_id and String(match_block.get("receiver", "")) == receiver_id:
					return entry
	if not item_id.is_empty():
		for manifest in manifest_list:
			for entry in (manifest as Dictionary)["models"] as Array:
				var match_block: Dictionary = (entry as Dictionary).get("match", {}) as Dictionary
				if String(match_block.get("id", "")) == item_id and not match_block.has("receiver"):
					return entry
	if not item_class.is_empty():
		for manifest in manifest_list:
			for entry in (manifest as Dictionary)["models"] as Array:
				var match_block: Dictionary = (entry as Dictionary).get("match", {}) as Dictionary
				if String(match_block.get("class", "")) == item_class:
					return entry
	return null


## A fresh instance of the model that draws this item, or null when no manifest names it.
static func model_for(item_id: String, item_class: String, receiver_id: String = "") -> Node3D:
	var entry: Variant = resolve(item_id, item_class, receiver_id)
	if not (entry is Dictionary):
		return null
	return instance_of(String((entry as Dictionary).get("glb", "")))


## A fresh instance of the GLB at `path`, sharing its template's meshes, materials and textures. Null when
## the file cannot be read.
static func instance_of(path: String) -> Node3D:
	var template: Node3D = template_of(path)
	if template == null:
		return null
	return template.duplicate() as Node3D


## The cached template for a GLB, loading it on first use. Null when the file is missing or unreadable.
static func template_of(path: String) -> Node3D:
	if _templates.has(path):
		return _templates[path] as Node3D
	var root: Node3D = _load_glb(path)
	_templates[path] = root
	return root


## The bounds of a node tree, in the space of `root`: each mesh's box carried through its transform chain.
## An empty box when the tree holds no mesh.
static func bounds(root: Node3D) -> AABB:
	var out: AABB = AABB()
	var found: bool = false
	for mesh in _meshes_under(root, Transform3D.IDENTITY):
		var local: AABB = (mesh["xform"] as Transform3D) * (mesh["mesh"] as Mesh).get_aabb()
		out = local if not found else out.merge(local)
		found = true
	return out


# --- loading ----------------------------------------------------------------------------------------

static func _load_glb(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_buffer(bytes, path.get_base_dir() + "/", state) != OK:
		return null
	var root: Node = document.generate_scene(state)
	if not (root is Node3D):
		return null
	_share_and_mipmap(root)
	KitSampling.clamp_inside_atlas(root)
	return root as Node3D


# Every albedo texture in the tree goes through the shared table, and its material samples the shared
# texture with nearest-with-mipmaps. Materials that are not `BaseMaterial3D` are left as authored.
static func _share_and_mipmap(root: Node) -> void:
	for mesh_node in _mesh_nodes(root):
		var mesh: Mesh = mesh_node.mesh
		for s in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(s)
			if not (material is BaseMaterial3D):
				continue
			var base: BaseMaterial3D = material as BaseMaterial3D
			if base.albedo_texture != null:
				base.albedo_texture = _shared_texture(base.albedo_texture)
			base.texture_filter = MIPMAP_FILTER


## The one shared, mipmapped texture for these pixels: the same object for every GLB that embeds the same
## atlas, whichever loader read it.
static func shared_texture(texture: Texture2D) -> Texture2D:
	return _shared_texture(texture)


static func _shared_texture(texture: Texture2D) -> Texture2D:
	var image: Image = texture.get_image()
	if image == null:
		return texture
	var key: String = _hash_of(image)
	if _textures.has(key):
		return _textures[key] as Texture2D
	var mipped: Image = image.duplicate() as Image
	if not mipped.has_mipmaps():
		mipped.generate_mipmaps()
	var shared: ImageTexture = ImageTexture.create_from_image(mipped)
	_textures[key] = shared
	return shared


# SHA-256 over the base level's pixels and the layout that gives them meaning, so two textures that differ
# only in size or format are never shared. The base level comes first in an image's data, so it is the first
# bytes an image without mipmaps would hold: a texture that already has its chain hashes like its base.
static func _hash_of(image: Image) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%d:%d:%d:" % [image.get_width(), image.get_height(), int(image.get_format())]).to_utf8_buffer())
	var base_size: int = Image.create(image.get_width(), image.get_height(), false, image.get_format()).get_data().size()
	ctx.update(image.get_data().slice(0, base_size))
	return ctx.finish().hex_encode()


static func _mesh_nodes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_mesh_nodes(child))
	return out


static func _meshes_under(node: Node3D, parent: Transform3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here: Transform3D = parent * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({"mesh": (node as MeshInstance3D).mesh, "xform": here})
	for child in node.get_children():
		if child is Node3D:
			out.append_array(_meshes_under(child as Node3D, here))
	return out

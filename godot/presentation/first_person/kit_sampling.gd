extends RefCounted
# How a kit's atlas is sampled once it is loaded (#448, #449). Presentation only: it changes how a
# loaded material reads its texture and never touches a mesh, a UV or a pixel of the atlas.
#
# Two faults are fixed here, for every GLB either loader reads (`assets.gd` and `models.gd`):
#   - No mipmaps. GLTFDocument hands back the embedded atlas as an ImageTexture with no mip chain, so a
#     material set to nearest-with-mipmaps samples the base level only and a wall 40 m out is unfiltered
#     64-texel-per-metre noise that shimmers. The loaders swap in a shared, mipmapped copy
#     (`Models.shared_texture`); `has_mipmaps` reads that copy's image, because in Godot 4.7.1
#     `ImageTexture.has_mipmaps()` answers false even for a texture made from a mipmapped image.
#   - A repeating sampler. The GLB sampler is REPEAT, and building faces end exactly on the atlas's outer
#     edges (u or v of 0 or 1), so a nearest sample at v = 1.0 reads row 0 of the opposite cell and puts
#     stray pixels on other buildings. A material whose every UV lies inside the atlas is set to clamp;
#     one that tiles past the edge keeps repeat, because it relies on it.
#
# The mip chain cannot be capped. The atlases hold 64 px cells aligned to powers of two, so the box
# filter never mixes two cells up to level 6 (one texel a cell); levels 7 and up average neighbouring
# cells. Neither BaseMaterial3D nor the Compatibility renderer exposes a maximum level, so the full chain
# ships and the bleed above level 6 was measured instead (docs/decisions/2026-11-12-kit-atlas-sampling.md).

# --- PRESENTATION TUNING ----------------------------------------------------------------------------
# A UV this far outside 0..1 still counts as inside the atlas: the exporter writes edges as -0.000015 or
# -0.000053, which is a rounding of 0, not a tile.
const UV_INSIDE_TOLERANCE: float = 0.001
# The edge of one atlas cell in texels, the same in every world kit (buildings, props, the starter kit).
# log2 of it is the last mip level that keeps cells apart.
const ATLAS_CELL_TEXELS: int = 64
# --- end of tuning ----------------------------------------------------------------------------------


## The last mip level at which one atlas cell is still at least one texel, so no cell bleeds into another.
static func clean_mip_levels() -> int:
	return int(round(log(float(ATLAS_CELL_TEXELS)) / log(2.0)))


## Clamps every BaseMaterial3D under `root` whose UVs all lie inside the atlas, and leaves repeat on for
## one that tiles. A material shared by several meshes is judged over all of them. Returns the number of
## materials clamped.
static func clamp_inside_atlas(root: Node) -> int:
	var ranges: Dictionary = {}
	var materials: Dictionary = {}
	_collect_ranges(root, ranges, materials)
	var clamped: int = 0
	for id in materials:
		var material: BaseMaterial3D = materials[id] as BaseMaterial3D
		var box: Rect2 = ranges[id] as Rect2
		if uv_inside_atlas(box):
			material.texture_repeat = false
			clamped += 1
	return clamped


## True when a UV rectangle stays inside 0..1 within the tolerance, so no sample needs to wrap.
static func uv_inside_atlas(box: Rect2) -> bool:
	var t: float = UV_INSIDE_TOLERANCE
	return box.position.x >= -t and box.position.y >= -t and box.end.x <= 1.0 + t and box.end.y <= 1.0 + t


## The UV rectangle every surface drawn with `material` under `root` covers, or an empty rectangle with a
## negative size when nothing under `root` uses it.
static func uv_range_of(root: Node, material: Material) -> Rect2:
	var ranges: Dictionary = {}
	var materials: Dictionary = {}
	_collect_ranges(root, ranges, materials)
	var id: int = material.get_instance_id()
	return ranges[id] as Rect2 if ranges.has(id) else Rect2(0.0, 0.0, -1.0, -1.0)


## Why a loaded kit material samples its atlas wrongly, or "" when it is right: nearest-with-mipmaps, an
## albedo texture whose image carries a mip chain down past the last clean level, and no repeat. The gates
## call it on a loaded material and on a raw GLTFDocument load, which must be refused.
static func fault_of(material: BaseMaterial3D) -> String:
	if material == null:
		return "no material"
	if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
		return "filter %d is not nearest-with-mipmaps" % material.texture_filter
	var texture: Texture2D = material.albedo_texture
	if texture == null:
		return "no albedo texture"
	var image: Image = texture.get_image()
	if image == null:
		return "the albedo texture has no image to read"
	if image.get_mipmap_count() < clean_mip_levels():
		return "the albedo texture has %d mip levels, fewer than %d" % [image.get_mipmap_count(), clean_mip_levels()]
	if material.texture_repeat:
		return "the sampler repeats, so a face on the atlas edge reads the opposite edge"
	return ""


static func _collect_ranges(node: Node, ranges: Dictionary, materials: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = instance.mesh
		for s in mesh.get_surface_count():
			var material: Material = instance.get_active_material(s)
			if not (material is BaseMaterial3D):
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if not (uvs is PackedVector2Array) or (uvs as PackedVector2Array).is_empty():
				continue
			var low: Vector2 = Vector2(INF, INF)
			var high: Vector2 = Vector2(-INF, -INF)
			for uv in uvs as PackedVector2Array:
				low = low.min(uv)
				high = high.max(uv)
			var id: int = material.get_instance_id()
			var box: Rect2 = Rect2(low, high - low)
			ranges[id] = (ranges[id] as Rect2).merge(box) if ranges.has(id) else box
			materials[id] = material
	for child in node.get_children():
		_collect_ranges(child, ranges, materials)

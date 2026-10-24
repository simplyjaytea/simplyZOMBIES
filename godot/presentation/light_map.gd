extends RefCounted
# The night over the district, per pixel (plan item A10). One screen-sized rect, multiplied into
# everything main draws, carrying night_light.gdshader; and one item over it for the things that
# are themselves light -- a muzzle flash, a campfire's flame -- which the night may not dim.
#
# Two RenderingServer canvas items, children of main's own, so they draw after every command main
# issues in `_draw` and under the HUD's CanvasLayer:
#   dark   the multiply rect (draw index DARK_INDEX)
#   glow   what `_draw_effects(true)` blits, over the dark (GLOW_INDEX)
#
# What a pixel's light *is* lives in light_look.gd (the texels: lit ∩ seen as bits) and in the
# shader (the sim's own reach rule measured to the pixel); this file only uploads and places them.
# There is nothing here a gate needs to call headless: every number it hands the shader comes out
# of LightLook, where check_light_look.gd judges it.

const LightLook = preload("res://presentation/light_look.gd")
const NightShader = preload("res://presentation/night_light.gdshader")

const DARK_INDEX: int = 1000
const GLOW_INDEX: int = 1001
# Pixels of art per tile: the pack's 32 px tile, so at zoom 64 one art pixel is two screen pixels
# and the light steps on the same grid the sprites do.
const ART_TILE_PX: float = 32.0

var _parent: RID
var _dark: RID
var _glow: RID
var _material: ShaderMaterial = null
var _tex: ImageTexture = null
var _tex_size: Vector2i = Vector2i(-1, -1)
var _attached: bool = false

# Read by the look gates and the frame bench: what the last frame drew.
var drew_dark: bool = false
var last_texels: Dictionary = {}


func attach(parent: RID) -> void:
	if _attached:
		return
	_parent = parent
	_dark = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_dark, _parent)
	RenderingServer.canvas_item_set_draw_index(_dark, DARK_INDEX)
	_glow = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_glow, _parent)
	RenderingServer.canvas_item_set_draw_index(_glow, GLOW_INDEX)
	_material = ShaderMaterial.new()
	_material.shader = NightShader
	RenderingServer.canvas_item_set_material(_dark, _material.get_rid())
	_attached = true


func detach() -> void:
	if not _attached:
		return
	RenderingServer.free_rid(_dark)
	RenderingServer.free_rid(_glow)
	_material = null
	_tex = null
	_tex_size = Vector2i(-1, -1)
	_attached = false


# Clear the glow item for this frame; `glow_rect` fills it again from `_draw_effects(true)`.
func begin_frame() -> void:
	if not _attached:
		return
	RenderingServer.canvas_item_clear(_glow)


func glow_rect(texture: Texture2D, rect: Rect2, transpose: bool) -> void:
	if not _attached or texture == null:
		return
	RenderingServer.canvas_item_add_texture_rect(_glow, rect, texture.get_rid(), false, Color.WHITE, transpose)


# The night for this frame. `ctx`: viewport (Vector2), zoom (screen px a tile), origin (screen
# position of world 0,0), view (Rect2i of tiles, clamped to the map), texels (LightLook.light_texels
# for that view), lights (its `lights`, positions already slid to where the bodies are drawn),
# ambient, range_m, eye (Vector2 tiles, absent with nobody to ask) and eye_reach (metres,
# LightLook.eye_disc_metres), night (Color), night_wash, edge_dark_day, edge_dark_night. `show`
# false clears the rect: full daylight is a frame with no night in it.
func frame(ctx: Dictionary, show: bool) -> void:
	if not _attached:
		return
	RenderingServer.canvas_item_clear(_dark)
	drew_dark = false
	if not show:
		return
	var view: Rect2i = ctx["view"] as Rect2i
	var texels: Dictionary = ctx["texels"] as Dictionary
	last_texels = texels
	var size := Vector2i(maxi(1, view.size.x), maxi(1, view.size.y))
	var bytes: PackedByteArray = texels["bytes"] as PackedByteArray
	if bytes.size() != size.x * size.y * 4:
		bytes = PackedByteArray()
		bytes.resize(size.x * size.y * 4)
	# The same texels as the last frame's (ctx.texels_cached) need no second upload.
	if _tex == null or _tex_size != size:
		_tex = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes))
		_tex_size = size
	elif not bool(ctx.get("texels_cached", false)):
		_tex.update(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes))
	var zoom: float = float(ctx["zoom"])
	var pos := PackedVector4Array()
	var tint := PackedVector4Array()
	var dir := PackedVector4Array()
	pos.resize(LightLook.MAX_LIGHTS)
	tint.resize(LightLook.MAX_LIGHTS)
	dir.resize(LightLook.MAX_LIGHTS)
	var lights: Array = ctx["lights"] as Array
	var count: int = mini(lights.size(), LightLook.MAX_LIGHTS)
	for i in count:
		var l: Dictionary = lights[i] as Dictionary
		pos[i] = Vector4(float(l["x"]), float(l["y"]), float(l["magnitude"]), float(l.get("flicker", 0.0)))
		var c: Color = l["tint"] as Color
		tint[i] = Vector4(c.r, c.g, c.b, LightLook.source_cap(float(l["magnitude"])))
		var beam: float = float(l.get("beam", 0.0))
		var facing: float = float(l.get("facing", 0.0))
		dir[i] = Vector4(cos(facing), sin(facing), cos(beam) if beam > 0.0 else 0.0, 0.0)
	var night: Color = ctx["night"] as Color
	_material.set_shader_parameter("light_tex", _tex)
	_material.set_shader_parameter("view_origin", view.position)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("zoom", zoom)
	_material.set_shader_parameter("origin_px", ctx["origin"] as Vector2)
	_material.set_shader_parameter("art_px", maxf(1.0, zoom / ART_TILE_PX))
	_material.set_shader_parameter("range_m", float(ctx["range_m"]))
	_material.set_shader_parameter("ambient", float(ctx["ambient"]))
	_material.set_shader_parameter("eye", ctx.get("eye", Vector2.ZERO) as Vector2)
	_material.set_shader_parameter("eye_fade", 1.0 if ctx.has("eye") else 0.0)
	_material.set_shader_parameter("eye_reach", float(ctx.get("eye_reach", 0.0)))
	_material.set_shader_parameter("light_count", count)
	_material.set_shader_parameter("light_pos", pos)
	_material.set_shader_parameter("light_tint", tint)
	_material.set_shader_parameter("light_dir", dir)
	_material.set_shader_parameter("night_colour", night)
	_material.set_shader_parameter("night_wash", float(ctx["night_wash"]))
	_material.set_shader_parameter("eye_floor", LightLook.EYE_FLOOR)
	_material.set_shader_parameter("pool_levels", float(LightLook.POOL_LEVELS))
	_material.set_shader_parameter("night_floor", LightLook.NIGHT_FLOOR)
	_material.set_shader_parameter("edge_dark_day", float(ctx["edge_dark_day"]))
	_material.set_shader_parameter("edge_dark_night", float(ctx["edge_dark_night"]))
	RenderingServer.canvas_item_add_rect(_dark, Rect2(Vector2.ZERO, ctx["viewport"] as Vector2), Color.WHITE)
	drew_dark = true

extends RefCounted
# A pen for one RenderingServer canvas item: the four CanvasItem draw calls the ground helpers in
# main.gd use, with the same names and arguments, writing into an item that keeps its commands
# until it is cleared. That is the whole of how the world is baked (presentation/world_layers.gd):
# the helpers call `_pen.draw_rect(...)`, `_pen` is main itself on an ordinary frame and one of
# these while a chunk is being baked, and the commands land in the chunk's own item instead of in
# a frame that is thrown away sixty times a second.
#
# Each call mirrors what CanvasItem does with the same arguments (scene/main/canvas_item.cpp), so
# a baked chunk draws exactly the pixels the old per-frame loop drew. A texture goes through its
# own draw_rect / draw_rect_region rather than the server's texture call with a bare RID, because
# an AtlasTexture maps its region there and a bare RID would blit the whole sheet.

var item: RID

func _init(target: RID) -> void:
	item = target


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	var r: Rect2 = rect.abs()
	if filled:
		RenderingServer.canvas_item_add_rect(item, r, color, antialiased)
	elif width >= r.size.x or width >= r.size.y:
		RenderingServer.canvas_item_add_rect(item, r.grow(0.5 * width), color, antialiased)
	else:
		var points := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0.0), r.end, r.position + Vector2(0.0, r.size.y), r.position])
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), width, antialiased)


func draw_circle(position: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	if filled:
		RenderingServer.canvas_item_add_circle(item, position, radius, color, antialiased)
		return
	var points := PackedVector2Array()
	var steps: int = 64
	for i in steps + 1:
		var a: float = TAU * float(i) / float(steps)
		points.append(position + Vector2(cos(a), sin(a)) * radius)
	RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), width, antialiased)


func draw_texture_rect(texture: Texture2D, rect: Rect2, tile: bool, modulate: Color = Color(1, 1, 1, 1), transpose: bool = false) -> void:
	if texture == null:
		return
	texture.draw_rect(item, rect, tile, modulate, transpose)


func draw_texture_rect_region(texture: Texture2D, rect: Rect2, src_rect: Rect2, modulate: Color = Color(1, 1, 1, 1), transpose: bool = false, clip_uv: bool = true) -> void:
	if texture == null:
		return
	texture.draw_rect_region(item, rect, src_rect, modulate, transpose, clip_uv)

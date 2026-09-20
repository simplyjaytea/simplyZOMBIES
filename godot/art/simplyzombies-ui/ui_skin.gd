extends RefCounted
## Optional bridge for the game's CanvasItem-drawn chrome.
## Call from _draw() or a helper invoked by _draw(); these do not redraw on their own.
const ROOT = "res://art/simplyzombies-ui/"
static var _styles: Dictionary = {}

static func draw_panel(canvas: CanvasItem, rect: Rect2, style_id: String = "panel_standard", opacity: float = 1.0) -> void:
	if not _styles.has(style_id):
		var resource=load(ROOT+"styles/"+style_id+".tres") as StyleBoxTexture
		if resource==null: return
		_styles[style_id]=resource
	var style=(_styles[style_id] as StyleBoxTexture).duplicate() as StyleBoxTexture
	style.modulate_color=Color(1,1,1,clampf(opacity,0,1))
	style.draw(canvas.get_canvas_item(),rect)

static func draw_icon(canvas: CanvasItem, texture: Texture2D, position: Vector2, integer_scale: int = 1, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect(texture,Rect2(position.round(),texture.get_size()*maxi(integer_scale,1)),false,tint)

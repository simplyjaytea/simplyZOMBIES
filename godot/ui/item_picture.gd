extends RefCounted
# One item's picture, drawn the one way on every screen that draws one: the bag plate, the quick
# strip along the bottom and the inspect pane (docs/23, "A picture per item base" and "Item pictures
# in the quick strip / inspect pane"). `Appearance.item_look` decides *what* a base looks like -- the
# pack's icon when content declares one, its class's glyph when it does not -- and this is *how* that
# answer reaches a canvas, so a thing in a bag, on the belt and under the inspector cannot look like
# three different objects, and the floor's own draw in `main.gd` is the only other reader of the look.
#
# Statics only, like `bag_grid.gd`: no state, and it never reaches the sim -- a caller that wants the
# picture for an item hands `world` to `Appearance.item_look` itself, with `base_of` for the base id.

const ItemGlyph = preload("res://presentation/item_glyph.gd")


# The content id of what an item is, "" for anything that is not one. The strip's rows and the
# inspect view name an item by entity id and carry no base id of their own -- a base id is a content
# id with digits in it (`item.ammo.308`), and neither read model may carry a digit.
static func base_of(world: Variant, item: int) -> String:
	if world == null or item < 0:
		return ""
	var base: Variant = world.components.get_component(item, "itemBase")
	return String((base as Dictionary).get("baseId", "")) if base is Dictionary else ""


# The art's painted extent, cached per texture: a 32 px icon is drawn edge to edge in a 28 px
# plate only if the transparent margin round it is left out of the sum.
static var _used: Dictionary = {}


static func used_rect(art: Texture2D) -> Rect2:
	var key: int = art.get_instance_id()
	if _used.has(key):
		return _used[key] as Rect2
	var r := Rect2(Vector2.ZERO, art.get_size())
	var img: Image = art.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var used: Rect2i = img.get_used_rect()
		if used.has_area():
			r = Rect2(used)
	_used[key] = r
	return r


# Draws `look` (an `Appearance.item_look` answer) into `box`, centred, at the world's own density:
# the painted part of the art (its transparent margin left out) at `scale` -- the district's 2x --
# smaller only by a whole step when the box cannot hold it, never larger and never by a fraction, so
# a 32 px icon is never resampled into doubled rows and a tin and a fuel can sit at the same pixel
# size, as they would on the floor. `lengthwise` lays a long picture along a long box: a rifle drawn
# across its icon lies down a one-cell-wide, six-cell-tall footprint rather than floating sideways in
# the middle of it. A base with no picture draws its class's glyph, as it did before the icons
# landed. `alpha` is the panel's opacity, so the picture fades with the plate it sits on. Returns
# the rect the picture covered (empty for a glyph).
static func draw(ci: CanvasItem, box: Rect2, look: Dictionary, alpha: float, scale: int = 2, lengthwise: bool = true) -> Rect2:
	var art: Texture2D = look["texture"] as Texture2D
	if art != null:
		var modulate: Color = (look["tint"] as Color) if bool(look["declaredTint"]) else Color.WHITE
		modulate.a = alpha
		var src: Rect2 = used_rect(art)
		var turn: bool = false
		if lengthwise:
			var box_tall: bool = box.size.y > box.size.x * 1.25
			var box_wide: bool = box.size.x > box.size.y * 1.25
			var art_tall: bool = src.size.y > src.size.x * 1.4
			var art_wide: bool = src.size.x > src.size.y * 1.4
			turn = (box_tall and art_wide) or (box_wide and art_tall)
		var drawn: Vector2 = Vector2(src.size.y, src.size.x) if turn else src.size
		var whole: float = float(scale)
		while whole > 1.0 and (drawn.x * whole > box.size.x or drawn.y * whole > box.size.y):
			whole -= 1.0
		var px: Vector2 = drawn * whole
		var at: Vector2 = (box.get_center() - px * 0.5).round()
		# Turned a quarter anticlockwise about the box's centre when it lies lengthwise: the muzzle of
		# a long gun points up.
		var size: Vector2 = Vector2(px.y, px.x) if turn else px
		ci.draw_set_transform(at + px * 0.5, -PI / 2.0 if turn else 0.0, Vector2.ONE)
		ci.draw_texture_rect_region(art, Rect2(-size * 0.5, size), src, modulate)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return Rect2(at, px)
	var tint: Color = look["tint"] as Color
	tint.a = alpha
	# The glyph is a drawn mark, not art: at the art's full 28 px a side it turns into a block letter,
	# so it is held to a size that reads as a symbol on the plate.
	var side: float = minf(minf(box.size.x, box.size.y), 16.0 * float(scale))
	ItemGlyph.draw_glyph(ci, Rect2(box.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), int(look["glyph"]), tint)
	return Rect2()

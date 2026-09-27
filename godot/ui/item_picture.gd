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


# Draws `look` (an `Appearance.item_look` answer) into `box`, centred. A picture is drawn at the
# largest whole multiple of the art that fits the box, on a whole pixel: a 32 px icon in a 37 px box
# would otherwise be stretched by 1.17 and come out with every sixth row doubled. A base with no
# picture draws its class's glyph in the box, exactly as it did before the icons landed. `alpha` is
# the panel's opacity, so the picture fades with the plate it sits on.
static func draw(ci: CanvasItem, box: Rect2, look: Dictionary, alpha: float) -> void:
	var art: Texture2D = look["texture"] as Texture2D
	if art != null:
		var modulate: Color = (look["tint"] as Color) if bool(look["declaredTint"]) else Color.WHITE
		modulate.a = alpha
		var art_size: Vector2 = art.get_size()
		var whole: float = maxf(1.0, floorf(minf(box.size.x / art_size.x, box.size.y / art_size.y)))
		var pic_size: Vector2 = art_size * whole
		ci.draw_texture_rect(art, Rect2((box.get_center() - pic_size * 0.5).round(), pic_size), false, modulate)
	else:
		var tint: Color = look["tint"] as Color
		tint.a = alpha
		ItemGlyph.draw_glyph(ci, box, int(look["glyph"]), tint)

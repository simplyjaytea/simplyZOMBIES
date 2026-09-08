extends RefCounted
# One drawn shape per item class, for a thing with no picture yet.
#
# `item.appearance.sprite` has been in the schema since the appearance pipeline landed and read by
# nothing -- the twelfth dead socket of the milestone, and a dropped item was a fixed ten-pixel
# square whatever it was. `Appearance.item_look` gives it a reader; this file is what it falls
# back to when a base declares no art, which today is every base.
#
# It is keyed by **class**, never by id. `presentation/appearance.gd`'s standing rule is that a
# per-id branch in the draw loop is exactly what the content `appearance` block replaced, and a
# table of sixty ids here would be that rule broken with extra steps. A class is what content
# already says about itself; the picture per base is its own slice, and when one lands the key it
# declares wins and this is never consulted for it.
#
# The shapes are deliberately coarse. At 56 px in a grid cell and about 20 px on the ground they
# have to read as silhouettes, and docs/00's invariant for the whole art track is silhouette
# first: an axe is a long haft with a head, a gun is an L, a bag is a box, a tin is a disc.

const Palette = preload("res://presentation/palette.gd")

# Every class `item.schema.json` allows, and the one shape each is drawn as. A class missing from
# this table draws DEFAULT rather than nothing, so a class added to content tomorrow is a plain
# marker and never an invisible item.
enum Shape { Bar = 0, Elbow = 1, Box = 2, Disc = 3, Slab = 4, Shield = 5, Tee = 6, Ring = 7 }
const BY_CLASS: Dictionary = {
	"weapon.melee": Shape.Bar,
	"weapon.ranged": Shape.Elbow,
	"container": Shape.Box,
	"consumable": Shape.Disc,
	"material": Shape.Slab,
	"armor": Shape.Shield,
	"tool": Shape.Tee,
	"attachment": Shape.Ring,
}
const DEFAULT: int = Shape.Slab


static func shape_for(item_class: String) -> int:
	return int(BY_CLASS.get(item_class, DEFAULT))


# Drawn to fit `rect`, centred, with a little margin. `tint` is the item's own if content declares
# one and the ground-item role colour if it does not -- the same "role colours are the floor" rule
# every other appearance fallback follows.
static func draw_glyph(ci: CanvasItem, rect: Rect2, shape: int, tint: Color) -> void:
	var c: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.5
	var line: float = maxf(1.5, r * 0.14)
	var edge: Color = tint.lightened(0.28)
	match shape:
		Shape.Bar:
			# A haft with a head on it: the long thing you swing.
			var half: Vector2 = Vector2(r * 0.13, r * 0.78)
			ci.draw_rect(Rect2(c - half, half * 2.0), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.46, r * 0.78), Vector2(r * 0.92, r * 0.42)), edge)
		Shape.Elbow:
			# Barrel and grip: the L that reads as a gun at any size.
			ci.draw_rect(Rect2(c - Vector2(r * 0.72, r * 0.30), Vector2(r * 1.44, r * 0.26)), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.30, r * 0.04), Vector2(r * 0.30, r * 0.80)), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.72, r * 0.30), Vector2(r * 1.44, r * 0.26)), edge, false, line)
		Shape.Box:
			# A bag with a flap: something that holds other things.
			ci.draw_rect(Rect2(c - Vector2(r * 0.66, r * 0.52), Vector2(r * 1.32, r * 1.04)), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.66, r * 0.52), Vector2(r * 1.32, r * 0.34)), edge)
			ci.draw_rect(Rect2(c - Vector2(r * 0.66, r * 0.52), Vector2(r * 1.32, r * 1.04)), edge, false, line)
		Shape.Disc:
			ci.draw_circle(c, r * 0.62, tint)
			ci.draw_circle(c, r * 0.62, edge, false, line)
		Shape.Slab:
			ci.draw_rect(Rect2(c - Vector2(r * 0.58, r * 0.38), Vector2(r * 1.16, r * 0.76)), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.58, r * 0.38), Vector2(r * 1.16, r * 0.76)), edge, false, line)
		Shape.Shield:
			# A plate, tapered to a point: what goes between you and a bite.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.56, -r * 0.62), c + Vector2(r * 0.56, -r * 0.62),
				c + Vector2(r * 0.56, r * 0.14), c + Vector2(0.0, r * 0.72), c + Vector2(-r * 0.56, r * 0.14),
			]), tint)
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.56, -r * 0.62), c + Vector2(r * 0.56, -r * 0.62),
				c + Vector2(r * 0.56, r * 0.14), c + Vector2(0.0, r * 0.72), c + Vector2(-r * 0.56, r * 0.14),
				c + Vector2(-r * 0.56, -r * 0.62),
			]), edge, line)
		Shape.Tee:
			ci.draw_rect(Rect2(c - Vector2(r * 0.62, r * 0.62), Vector2(r * 1.24, r * 0.30)), tint)
			ci.draw_rect(Rect2(c - Vector2(r * 0.15, r * 0.62), Vector2(r * 0.30, r * 1.24)), tint)
		Shape.Ring:
			ci.draw_circle(c, r * 0.58, edge, false, maxf(2.0, line * 1.4))

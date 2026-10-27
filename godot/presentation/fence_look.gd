extends RefCounted
# How a wire fence stands on its tile: the strands and the post, as a pure function of the tile's
# rect and what stands on each of its four sides, so `godot:check:topdown`'s FENCE lane judges the
# geometry without a frame and main.gd's `_draw_fence_wire` draws exactly what it answers. A side is
# NONE (open ground), FENCE (another fence tile) or ANCHOR (anything solid that is not a fence: a
# raised wall, a building's wall, a barricade), which a strand may be fixed to.
#
# The rules:
#   * **The strands run the way the fence runs.** A tile with a fence neighbour east or west carries
#     two horizontal strands; one with a fence neighbour north or south carries two vertical ones. A
#     tile with no fence beside it runs toward an anchor north or south if it has one and none east
#     or west, and east-west otherwise.
#   * **A strand reaches an edge only toward a fence or an anchor.** At a run's open end the strand
#     stops at the post, so no loose wire hangs past it; a run that ends against a wall reaches the
#     wall. A tile with nothing on either side of its run spans the tile.
#   * **A corner is mitred.** A tile with one fence neighbour across and one along (an L) turns each
#     strand into its partner: the outer pair meets at the outer corner and the inner pair at the
#     inner, so the turn neither leaves a gap nor overshoots, and its square post caps both joints.
#   * **One post per tile.** At the centre: a bar across the strands, or a square block where the run
#     turns or meets. Two runs side by side never draw a doubled post at their join.

const NONE: int = 0
const FENCE: int = 1
const ANCHOR: int = 2

# The strands sit at these fractions across the run.
const STRANDS: Array[float] = [0.35, 0.65]
# The post's bar spans this much of the tile across the run, centred.
const POST_SPAN: float = 0.6


# The width of a strand, in screen px, for a tile drawn `side` px across.
static func thickness(side: float) -> float:
	return maxf(1.0, roundf(side * 0.045))


# {"strands": Array[Rect2], "post": Rect2, "horizontal": bool, "vertical": bool} for a fence tile
# drawn at `rect`, with NONE, FENCE or ANCHOR standing east, west, north and south.
static func pieces(rect: Rect2, e: int, w: int, n: int, s: int) -> Dictionary:
	var t: float = thickness(rect.size.x)
	var horiz: bool = e == FENCE or w == FENCE
	var vert: bool = n == FENCE or s == FENCE
	if not horiz and not vert:
		vert = (n == ANCHOR or s == ANCHOR) and e == NONE and w == NONE
		horiz = not vert
	var c: Vector2 = rect.get_center()
	var o: Vector2 = rect.position
	var z: Vector2 = rect.size
	var corner: bool = ((e == FENCE) != (w == FENCE)) and ((n == FENCE) != (s == FENCE))
	var strands: Array[Rect2] = []
	if corner:
		# The L: a strand at fraction f across runs from where its partner stands (half a strand past
		# its centre line, so the joint is square and not notched) to the side the run leaves by.
		var east: bool = e == FENCE
		var south: bool = s == FENCE
		for f in STRANDS:
			var hx0: float = o.x + z.x * ((f if south else 1.0 - f) if east else 0.0) - (t * 0.5 if east else 0.0)
			var hx1: float = o.x + z.x * (1.0 if east else (1.0 - f if south else f)) + (0.0 if east else t * 0.5)
			strands.append(Rect2(Vector2(hx0, o.y + z.y * f - t * 0.5), Vector2(hx1 - hx0, t)))
		for g in STRANDS:
			var vy0: float = o.y + z.y * ((g if east else 1.0 - g) if south else 0.0) - (t * 0.5 if south else 0.0)
			var vy1: float = o.y + z.y * (1.0 if south else (1.0 - g if east else g)) + (0.0 if south else t * 0.5)
			strands.append(Rect2(Vector2(o.x + z.x * g - t * 0.5, vy0), Vector2(t, vy1 - vy0)))
	else:
		if horiz:
			var x0: float = o.x if (w != NONE or e == NONE) else c.x
			var x1: float = rect.end.x if (e != NONE or w == NONE) else c.x
			for f in STRANDS:
				strands.append(Rect2(Vector2(x0, o.y + z.y * f - t * 0.5), Vector2(x1 - x0, t)))
		if vert:
			var y0: float = o.y if (n != NONE or s == NONE) else c.y
			var y1: float = rect.end.y if (s != NONE or n == NONE) else c.y
			for f in STRANDS:
				strands.append(Rect2(Vector2(o.x + z.x * f - t * 0.5, y0), Vector2(t, y1 - y0)))
	var post: Rect2
	if horiz and vert:
		# Square, from the outer strand's outer edge to the inner strand's, so it caps every joint.
		var a: Vector2 = o + z * STRANDS[0] - Vector2(t, t) * 0.5
		var b: Vector2 = o + z * STRANDS[STRANDS.size() - 1] + Vector2(t, t) * 0.5
		post = Rect2(a, b - a)
	elif horiz:
		post = Rect2(Vector2(c.x - t, c.y - z.y * POST_SPAN * 0.5), Vector2(t * 2.0, z.y * POST_SPAN))
	else:
		post = Rect2(Vector2(c.x - z.x * POST_SPAN * 0.5, c.y - t), Vector2(z.x * POST_SPAN, t * 2.0))
	return {"strands": strands, "post": post, "horizontal": horiz, "vertical": vert}

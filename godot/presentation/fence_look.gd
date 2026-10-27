extends RefCounted
# How a wire fence stands on its tile: the strands and the post, as a pure function of the tile's
# rect and which of its four neighbours are fence too, so `godot:check:topdown`'s FENCE lane judges
# the geometry without a frame and main.gd's `_draw_fence_wire` draws exactly what it answers.
#
# The rules:
#   * **The strands run the way the fence runs.** A tile with a fence neighbour east or west carries
#     two horizontal strands; one with a neighbour north or south carries two vertical ones. A tile
#     with neither stands east-west on its own.
#   * **A strand reaches an edge only toward a neighbour.** Where the run joins on one side only, the
#     strand stops at the post; where the tile joins nothing that way, it spans the tile. So a run is
#     one unbroken pair of strands.
#   * **A corner is mitred.** A tile with one neighbour across and one along (an L) turns each strand
#     into its partner: the outer pair meets at the outer corner and the inner pair at the inner, so
#     the turn neither leaves a gap nor overshoots.
#   * **One post per tile.** At the centre: a bar across the strands, or a square block where the run
#     turns or meets. Two runs side by side never draw a doubled post at their join.

# The strands sit at these fractions across the run.
const STRANDS: Array[float] = [0.35, 0.65]
# The post's bar spans this much of the tile across the run, centred.
const POST_SPAN: float = 0.6


# The width of a strand, in screen px, for a tile drawn `side` px across.
static func thickness(side: float) -> float:
	return maxf(1.0, roundf(side * 0.045))


# {"strands": Array[Rect2], "post": Rect2, "horizontal": bool, "vertical": bool} for a fence tile
# drawn at `rect`, with fence neighbours east, west, north and south as given.
static func pieces(rect: Rect2, e: bool, w: bool, n: bool, s: bool) -> Dictionary:
	var t: float = thickness(rect.size.x)
	var vert: bool = n or s
	var horiz: bool = e or w or not vert
	var c: Vector2 = rect.get_center()
	var strands: Array[Rect2] = []
	if (e != w) and (n != s):
		# The L: a strand at fraction f across runs from where its partner stands (half a strand past
		# its centre line, so the joint is square and not notched) to the open side.
		var o: Vector2 = rect.position
		var z: Vector2 = rect.size
		for f in STRANDS:
			var hx0: float = o.x + z.x * ((f if s else 1.0 - f) if e else 0.0) - (t * 0.5 if e else 0.0)
			var hx1: float = o.x + z.x * (1.0 if e else (1.0 - f if s else f)) + (0.0 if e else t * 0.5)
			strands.append(Rect2(Vector2(hx0, o.y + z.y * f - t * 0.5), Vector2(hx1 - hx0, t)))
		for g in STRANDS:
			var vy0: float = o.y + z.y * ((g if e else 1.0 - g) if s else 0.0) - (t * 0.5 if s else 0.0)
			var vy1: float = o.y + z.y * (1.0 if s else (1.0 - g if e else g)) + (0.0 if s else t * 0.5)
			strands.append(Rect2(Vector2(o.x + z.x * g - t * 0.5, vy0), Vector2(t, vy1 - vy0)))
	elif horiz:
		var x0: float = rect.position.x if (w or not vert) else c.x
		var x1: float = rect.end.x if (e or not vert) else c.x
		for f in STRANDS:
			strands.append(Rect2(Vector2(x0, rect.position.y + rect.size.y * f - t * 0.5), Vector2(x1 - x0, t)))
	if vert and not ((e != w) and (n != s)):
		var y0: float = rect.position.y if (n or not horiz) else c.y
		var y1: float = rect.end.y if (s or not horiz) else c.y
		for f in STRANDS:
			strands.append(Rect2(Vector2(rect.position.x + rect.size.x * f - t * 0.5, y0), Vector2(t, y1 - y0)))
	var post: Rect2
	if horiz and vert:
		post = Rect2(c - Vector2(t * 2.0, t * 2.0), Vector2(t * 4.0, t * 4.0))
	elif horiz:
		post = Rect2(Vector2(c.x - t, c.y - rect.size.y * POST_SPAN * 0.5), Vector2(t * 2.0, rect.size.y * POST_SPAN))
	else:
		post = Rect2(Vector2(c.x - rect.size.x * POST_SPAN * 0.5, c.y - t), Vector2(rect.size.x * POST_SPAN, t * 2.0))
	return {"strands": strands, "post": post, "horizontal": horiz, "vertical": vert}

extends SceneTree
# The UI Field Kit, worn: the approved kit at art/simplyzombies-ui/ is what the screens draw
# (docs/30, "The UI Field Kit, live", 2026-09-25), and this gate is what keeps that true.
#
# The kit ships `styles/*.tres` and a `theme.tres`, and the running game loads neither: nothing
# is imported in a headless gate, so a kit PNG is not a Resource there and every .tres naming one
# fails to parse. `ui/kit.gd` loads the PNGs the two-path way `presentation/appearance.gd` does
# and builds each nine-slice in code from its NINE table -- which makes that table a copy, and a
# copy is the thing that drifts. So `manifest.json` and the `.tres` text stay the spec, read here
# as text, and the code is held to both.
#
# The gate lands with the first slice (S1, "The chrome wears the kit") and grows a lane per
# slice after it. Each lane is its own function so a later slice replaces one function and
# touches nothing beside it; a lane whose slice has not landed says so by name and passes
# nothing quietly. Every lane that judges carries a true positive and a true negative -- a gate
# that cannot fail is worse than no gate:
#
#   KIT       every margin in Kit.NINE equals manifest.json's `nine_slice_ltrb` and the style's
#             .tres `texture_margin_*`, at native kit pixels; the .tres sets nothing the code does
#             not build (no axis mode, no draw_center, no expand margin); every kit chrome id is
#             either consumed or listed unused here with its reason. The places the code departs
#             from the kit's files on purpose are named, not silent: Kit.SCALE is the owner's
#             OWNER_SCALE (the keycap alone at 1x, in Kit.NATIVE_STYLES); every built centre tiles
#             (CENTRE_MODE_DEVIATION); every consumed style is in exactly one edge group, and its
#             frame tiles its edges if it is in Kit.EDGE_TILED (EDGE_DEVIATION) and stretches them,
#             the .tres meaning, if it is in Kit.BRACKET_MARGINS; and those margins are widened
#             (MARGIN_DEVIATION) -- never narrower than the manifest's, and measured from the
#             pixels: no bracket ink runs across a widened margin into a stretched edge, and one
#             pixel less on any widened side lets it. Every surface a style is drawn on clears
#             that style's doubled margins, so none falls back to a drawn fill. A fabricated
#             record with one wrong margin, a fabricated .tres with one wrong margin, one with an
#             axis mode, one with an expand margin, a chrome id in neither list, a style in both
#             edge groups and one in neither, a tiled-edge style whose frame stretches, a
#             bracketed one whose frame tiles, a stretched centre, a frame that draws its own
#             centre, a centre tiling the whole texture, a bracket style at the kit's narrower
#             margin, one a pixel wider than its bracket needs, one below the manifest's margin,
#             a bracketed frame built at the manifest's margin, a shell row too short for its
#             button and each deviation naming no departure each fail the comparator that passed
#             the shipped files.
#   RESOLVE   every NINE texture and every manifest glyph, both sizes, resolves headless at the
#             manifest's size times its draw scale; a made-up style, texture and glyph resolve to
#             null.
#   PANEL     Kit.style hands back a textured Kit.Style (frame and centre) at the asked opacity, with
#             margins at NINE times Kit.SCALE, cached, and null for a rect smaller than those
#             margins; `Chrome.panel`, `cell`, `item_plate` and
#             `header` reach `Kit.style(` and `.draw(`, followed one call deep through `frame`,
#             by a scanner that refuses a fabricated body that only draws rectangles, a link
#             that does not reach the kit, and a needle that only a comment carries.
#   HELPERS   every public helper in chrome.gd has a caller outside it, in godot/ui/ or
#             main.gd, comments stripped -- the dead-socket rule. A helper waiting on its slice is
#             named in PENDING and printed as a SKIP; a PENDING helper that gains a caller is a
#             failure until it leaves the list; a fabricated name has no caller.
#   FONT      Chrome.font() is the kit's VT323 over the engine font, and nothing else under
#             godot/ui/ or godot/presentation/ names the engine font; every text size is on
#             Chrome.LADDER; every character the player can be shown is carried or named. Its five
#             parts (FACE, FALLBACK, METRICS, SCAN, LADDER) are spelled out above `_font_lane`.
#   GLYPHS, KEYCAPS, OUTLIERS, CURSORS, MOTION, EVENTS
#             stubs, each printing `SKIP <LANE>: not landed` until its slice replaces it.

const Kit = preload("res://ui/kit.gd")

const MANIFEST_PATH: String = "res://art/simplyzombies-ui/manifest.json"
const STYLES_DIR: String = "res://art/simplyzombies-ui/styles/"
const CHROME_GD: String = "res://ui/chrome.gd"
const UI_DIR: String = "res://ui/"
const ITEM_MENU_GD: String = "res://ui/item_menu.gd"
const MAIN_GD: String = "res://presentation/main.gd"
const BUDGET_SECONDS: float = 60.0

# Kit chrome the screens deliberately do not wear. The owner's 2026-09-25 decision (docs/30,
# "The UI Field Kit, live") keeps every kit piece that conflicts with a standing decision out,
# each with its reason; a chrome id in neither this list nor Kit.NINE is a failure, so a new kit
# piece cannot arrive unconsidered.
const UNUSED_STYLES: Dictionary = {
	"button_disabled": "never greyed: a verb is present or absent on this HUD, never dimmed",
	"slot_disabled": "never greyed: a slot is empty or holds something, never dimmed",
	"tab_normal": "no screen is tabbed",
	"tab_selected": "no screen is tabbed",
	"tab_hover": "no screen is tabbed",
	"scroll_track": "the sheet has no scrollbar",
}

# Chrome helpers that land ahead of their first caller outside chrome.gd, each naming the slice
# (docs/23's what's-left, "The UI Field Kit, live") that gives it one. A name leaves this list
# in the commit that gives it a reader.
const PENDING: Dictionary = {
}

# The owner's 2026-09-25 decision (docs/30, "The UI Field Kit, live"): the chrome draws at twice
# the kit's native pixels, as the approved mockups do and as the world's 32 px tile is drawn.
const OWNER_SCALE: int = 2

# The three ways the built styles depart from the kit's .tres on purpose, each the owner's decision
# of 2026-09-25 (docs/30, "The UI Field Kit, live"), named here so a departure is a decision the
# gate can see, not a drift it cannot. Every style .tres sets no axis mode, which is Godot's
# STRETCH on both the edges and the centre.
#
# The centre: stretched across a tall panel its fine noise smeared into blotches and streaks, so
# every built centre tiles.
const CENTRE_MODE_DEVIATION: Dictionary = {
	"centre": StyleBoxTexture.AXIS_STRETCH_MODE_TILE,
	"why": "docs/30, \"The UI Field Kit, live\": the owner tiled the centre on 2026-09-25; stretched, its noise smeared on tall panels",
}
# The edges, per style: tiled edges repeat a bracket's fragments along every border as tick marks,
# stretched edges lengthen a dashed line's dashes and a noisy rim's grain, so the dashed and noisy
# frames (Kit.EDGE_TILED) tile their edges and the bracketed ones keep the .tres files' stretch.
const EDGE_DEVIATION: Dictionary = {
	"tiled": StyleBoxTexture.AXIS_STRETCH_MODE_TILE,
	"why": "docs/30, \"The UI Field Kit, live\": the owner chose edges per style on 2026-09-25; tiled, a bracket repeats; stretched, dashes and noise lose their rhythm",
}
# The margins: a stretched edge lengthens whatever of a bracket lies in it, so the bracketed styles
# draw at Kit.BRACKET_MARGINS -- the manifest's margins widened just enough to hold each bracket.
# Kit.NINE, which the manifest and .tres comparisons read, stays the manifest's.
const MARGIN_DEVIATION: Dictionary = {
	"why": "docs/30, \"The UI Field Kit, live\": a stretched edge lengthened every bracket arm in it, so each bracket's margins hold the whole bracket",
}

# The only keys a kit style's [resource] section may set: the ones kit.gd builds from.
const TRES_KEYS: Array[String] = [
	"texture",
	"texture_margin_left", "texture_margin_top", "texture_margin_right", "texture_margin_bottom",
	"content_margin_left", "content_margin_top", "content_margin_right", "content_margin_bottom",
]

var _stash: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	var manifest: Dictionary = _manifest()
	if manifest.is_empty():
		push_error("UI_SKIN: %s did not parse; nothing below can be judged" % MANIFEST_PATH)
		ok = false
	else:
		ok = _kit_lane(manifest) and ok
		ok = _resolve_lane(manifest) and ok
	ok = _panel_lane() and ok
	ok = _helpers_lane() and ok
	ok = _font_lane() and ok
	ok = _glyphs_lane() and ok
	ok = _keycaps_lane() and ok
	ok = _outliers_lane() and ok
	ok = _cursors_lane() and ok
	ok = _motion_lane() and ok
	ok = await _events_lane() and ok
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_ui_skin ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false
	if ok:
		print(
			"UI_SKIN_OK %d kit styles agree with the manifest and their .tres, %d left unused with a reason; %d textures and %d glyphs at both sizes resolve headless; panel, cell, plate and header reach the kit; %d chrome helpers called, %d pending their slice; %.1f s of a %.0f s budget"
			% [
				int(_stash.get("styles", 0)), UNUSED_STYLES.size(), int(_stash.get("textures", 0)),
				int(_stash.get("glyphs", 0)), int(_stash.get("called", 0)), PENDING.size(), seconds,
				BUDGET_SECONDS,
			]
		)
		quit(0)
	else:
		push_error("UI_SKIN_FAIL")
		quit(1)


# --- helpers -----------------------------------------------------------------------------------


func _text_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_text_of(MANIFEST_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


# manifest.json lists each logical asset under `assets` and every exported file (glyph variants
# and animation frames included) under `sprites`; this indexes one of them by id.
func _records(manifest: Dictionary, list: String) -> Dictionary:
	var out: Dictionary = {}
	for rec_v in manifest.get(list, []) as Array:
		if rec_v is Dictionary:
			out[String((rec_v as Dictionary).get("id", ""))] = rec_v
	return out


func _ints(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if v is Array:
		for n in v as Array:
			out.append(int(n))
	return out


# One line with its comment cut off: the first `#` outside a string literal. A needle that only a
# comment carries must not satisfy a textual assertion -- `Color("#141810")` keeps its `#`.
func _code_line(line: String) -> String:
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if quote != "":
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				quote = ""
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line


func _code_of(text: String) -> String:
	var out: String = ""
	for line in text.split("\n"):
		out += _code_line(String(line)) + "\n"
	return out


# Every function in a file by name, bodies comment-stripped, static or not -- so a textual
# assertion is made against the function it names and never a comment elsewhere in the file.
func _bodies(text: String) -> Dictionary:
	var out: Dictionary = {}
	var current: String = ""
	for raw in text.split("\n"):
		var line: String = String(raw)
		var head: String = ""
		if line.begins_with("static func "):
			head = line.substr("static func ".length())
		elif line.begins_with("func "):
			head = line.substr("func ".length())
		if head != "":
			current = head.substr(0, head.find("("))
			out[current] = ""
			continue
		if current != "" and not line.is_empty() and not line.begins_with("\t") and not line.begins_with(" ") and not line.begins_with("#"):
			current = ""
		if current != "":
			out[current] = String(out[current]) + _code_line(line) + "\n"
	return out


# --- 1. KIT ------------------------------------------------------------------------------------


# What is wrong with one manifest record against the code's margins. Empty when they agree.
func _margin_faults(id: String, code: Array, rec: Variant) -> Array[String]:
	var faults: Array[String] = []
	if not (rec is Dictionary):
		faults.append("%s: manifest.json has no record" % id)
		return faults
	var want: Array[int] = _ints((rec as Dictionary).get("nine_slice_ltrb", null))
	if want != _ints(code):
		faults.append("%s: Kit.NINE says %s, manifest.json says %s" % [id, str(_ints(code)), str(want)])
	if String((rec as Dictionary).get("path", "")) != "textures/%s.png" % id:
		faults.append("%s: manifest path %s is not textures/%s.png, which is where kit.gd looks" % [id, str((rec as Dictionary).get("path", "")), id])
	return faults


# What is wrong with one style's .tres text against the code: a margin that disagrees, a key
# kit.gd does not build, or a texture that is not the one kit.gd loads.
func _tres_faults(id: String, code: Array, text: String) -> Array[String]:
	var faults: Array[String] = []
	if text.is_empty():
		faults.append("%s: no styles/%s.tres" % [id, id])
		return faults
	var got: Dictionary = {}
	var in_resource: bool = false
	for raw in text.split("\n"):
		var line: String = String(raw).strip_edges()
		if line.begins_with("[ext_resource") and line.contains("path=\""):
			var p: String = line.substr(line.find("path=\"") + 6)
			p = p.substr(0, p.find("\""))
			if p != Kit.ROOT + "textures/%s.png" % id:
				faults.append("%s: .tres textures %s, kit.gd loads textures/%s.png" % [id, p, id])
		if line.begins_with("["):
			in_resource = line == "[resource]"
			continue
		if not in_resource or not line.contains("="):
			continue
		var key: String = line.substr(0, line.find("=")).strip_edges()
		got[key] = line.substr(line.find("=") + 1).strip_edges()
		if not TRES_KEYS.has(key):
			faults.append("%s: .tres sets `%s`, which kit.gd does not build" % [id, key])
	var sides: Array[String] = ["left", "top", "right", "bottom"]
	for i in range(4):
		var k: String = "texture_margin_" + sides[i]
		if not got.has(k):
			faults.append("%s: .tres has no %s" % [id, k])
		elif int(float(String(got[k]))) != int((code as Array)[i]):
			faults.append("%s: .tres %s = %s, Kit.NINE says %d" % [id, k, String(got[k]), int((code as Array)[i])])
	return faults


# Every kit chrome id is worn (in `nine`) or listed unused with a reason -- and not both.
func _coverage_faults(assets: Array, nine: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	for rec_v in assets:
		var rec: Dictionary = rec_v as Dictionary
		if String(rec.get("category", "")) != "chrome":
			continue
		var id: String = String(rec.get("id", ""))
		if nine.has(id) and UNUSED_STYLES.has(id):
			faults.append("%s is both worn and listed unused" % id)
		elif not nine.has(id) and not UNUSED_STYLES.has(id):
			faults.append("%s is a kit chrome piece nobody decided about: wear it in Kit.NINE or list it unused with a reason" % id)
	return faults


# What is wrong with how a built style fills its edges and centre. The .tres files set no axis
# mode (TRES_KEYS refuses one), so what they mean is STRETCH everywhere. The frame's edges must be
# that stretch -- or, for a style in the tiled-edge group, the mode `edge_dev` names, which must
# depart from the stretch and give a reason -- and the frame must draw no centre of its own. The
# centre must match the stretch too, or match `centre_dev`, likewise named, reasoned and departing.
# The centre fill must tile the texture inside the frame's margins, from the frame's own texture,
# with no margins of its own.
func _mode_faults(id: String, st: Kit.Style, centre_dev: Dictionary, edge_dev: Dictionary, tiled_edges: bool) -> Array[String]:
	var faults: Array[String] = []
	var tres_mode: int = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var centre: int = tres_mode
	if not centre_dev.is_empty():
		centre = int(centre_dev.get("centre", tres_mode))
		if centre == tres_mode:
			faults.append("CENTRE_MODE_DEVIATION names the .tres files' own stretch for the centre -- it departs from nothing")
		if String(centre_dev.get("why", "")).strip_edges().is_empty():
			faults.append("CENTRE_MODE_DEVIATION gives no reason")
	var edges: int = tres_mode
	if tiled_edges and not edge_dev.is_empty():
		edges = int(edge_dev.get("tiled", tres_mode))
		if edges == tres_mode:
			faults.append("EDGE_DEVIATION names the .tres files' own stretch for the tiled-edge group -- it departs from nothing")
		if String(edge_dev.get("why", "")).strip_edges().is_empty():
			faults.append("EDGE_DEVIATION gives no reason")
	if st == null or st.border == null or st.border.texture == null:
		faults.append("%s: the built style has no textured frame" % id)
		return faults
	var b: StyleBoxTexture = st.border
	if b.axis_stretch_horizontal != edges or b.axis_stretch_vertical != edges:
		faults.append("%s: the frame fills its edges with axis modes %d/%d; its group (%s) means %d" % [id, b.axis_stretch_horizontal, b.axis_stretch_vertical, "tiled edges" if tiled_edges else "bracketed, stretched edges", edges])
	if b.draw_center:
		faults.append("%s: the frame draws its own centre, the frame's mode, under the centre fill" % id)
	if st.centre == null:
		faults.append("%s: the built style has no centre fill" % id)
		return faults
	var c: StyleBoxTexture = st.centre
	if c.axis_stretch_horizontal != centre or c.axis_stretch_vertical != centre:
		faults.append("%s: the centre fills with axis modes %d/%d; the .tres means %d and the named deviation %d" % [id, c.axis_stretch_horizontal, c.axis_stretch_vertical, tres_mode, centre])
	if c.texture != b.texture:
		faults.append("%s: the centre fill is not cut from the frame's texture" % id)
	var size: Vector2 = b.texture.get_size()
	var inside: Rect2 = Rect2(b.texture_margin_left, b.texture_margin_top, size.x - b.texture_margin_left - b.texture_margin_right, size.y - b.texture_margin_top - b.texture_margin_bottom)
	if c.region_rect != inside:
		faults.append("%s: the centre fill tiles %s of the texture, not %s inside the frame's margins" % [id, str(c.region_rect), str(inside)])
	if c.texture_margin_left != 0.0 or c.texture_margin_top != 0.0 or c.texture_margin_right != 0.0 or c.texture_margin_bottom != 0.0:
		faults.append("%s: the centre fill carries nine-slice margins of its own" % id)
	return faults


# A built frame is drawn at its style's own margins -- the widened ones for a bracketed style, the
# manifest's for every other -- at its scale, and Kit.margins (every caller's "does it fit") agrees.
func _draw_margin_faults(id: String, st: Kit.Style) -> Array[String]:
	var faults: Array[String] = []
	var want: Array[int] = []
	for n in Kit.BRACKET_MARGINS.get(id, Kit.NINE[id]) as Array:
		want.append(int(n) * Kit.scale_of(id))
	var got: Array[int] = [int(st.border.texture_margin_left), int(st.border.texture_margin_top), int(st.border.texture_margin_right), int(st.border.texture_margin_bottom)]
	if got != want or got != Kit.margins(id):
		faults.append("%s's frame is drawn at margins %s (Kit.margins says %s), not %s" % [id, str(got), str(Kit.margins(id)), str(want)])
	return faults


# Every style NINE wears is in exactly one edge group -- `tiled` or a key of `brackets` -- and
# neither group names a style NINE does not wear.
func _group_faults(nine: Dictionary, tiled: Array, brackets: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	for id_v in nine.keys():
		var id: String = String(id_v)
		if tiled.has(id) and brackets.has(id):
			faults.append("%s is in both Kit.EDGE_TILED and Kit.BRACKET_MARGINS -- its edges cannot both tile and stretch" % id)
		elif not tiled.has(id) and not brackets.has(id):
			faults.append("%s is in neither Kit.EDGE_TILED nor Kit.BRACKET_MARGINS -- nobody decided how its edges fill" % id)
	for id_v in tiled:
		if not nine.has(String(id_v)):
			faults.append("Kit.EDGE_TILED names %s, which NINE does not wear" % String(id_v))
	for id_v in brackets.keys():
		if not nine.has(String(id_v)):
			faults.append("Kit.BRACKET_MARGINS names %s, which NINE does not wear" % String(id_v))
	return faults


# A pixel's ink, coarsely: transparent, plain (the dark olives every frame is built from), amber,
# red, or pale (a highlight or a pale bracket). Coarse on purpose -- a bracket differs from the
# rim it sits on by hue or by a jump in brightness, never by one shade of olive.
func _ink(c: Color) -> int:
	if c.a < 0.1:
		return 0
	if c.s > 0.55 and c.h > 0.05 and c.h < 0.16 and c.v > 0.45:
		return 2
	if c.s > 0.5 and (c.h < 0.05 or c.h > 0.95) and c.v > 0.3:
		return 3
	if c.v > 0.55:
		return 4
	return 1


# Where a stretched edge would lengthen part of a bracket. `img` is the native texture and `m` the
# native margins [l, t, r, b] it would be drawn at. Each of the four edge strips is read line by
# line along its length -- a row of the top strip runs from the left corner to the right one -- and
# "ink" is any pixel whose class is not the strip's dominant one. A run of ink that crosses a margin
# (ink on both sides of it) and stops inside the strip is a piece of the corner carried into the
# edge: stretched, it grows with the frame. Ink that runs the strip's whole length is the rim itself
# (the danger button's red line), which stretching leaves as it is; ink that touches neither corner
# is the edge's own detail, a highlight the kit drew there. So the rule is that the pixel on each
# side of every margin, on every line, is not ink carried across it -- which also keeps the pixel
# that ends a bracket (its shadow, its rim) inside the corner, where the stretch cannot smear it.
func _protrusions(img: Image, m: Array) -> Array[String]:
	var out: Array[String] = []
	var w: int = img.get_width()
	var h: int = img.get_height()
	var l: int = int(m[0])
	var t: int = int(m[1])
	var r: int = int(m[2])
	var b: int = int(m[3])
	if l + r >= w or t + b >= h:
		out.append("margins %s leave no edge to stretch in a %dx%d texture" % [str(m), w, h])
		return out
	# [name, first pixel of the first line, step along a line, step to the next line, lines, length]
	var strips: Array = [
		["top", Vector2i(l, 0), Vector2i(1, 0), Vector2i(0, 1), t, w - l - r],
		["bottom", Vector2i(l, h - b), Vector2i(1, 0), Vector2i(0, 1), b, w - l - r],
		["left", Vector2i(0, t), Vector2i(0, 1), Vector2i(1, 0), l, h - t - b],
		["right", Vector2i(w - r, t), Vector2i(0, 1), Vector2i(1, 0), r, h - t - b],
	]
	for strip_v in strips:
		var strip: Array = strip_v as Array
		var along: Vector2i = strip[2]
		var across: Vector2i = strip[3]
		var n: int = int(strip[5])
		var counts: Array[int] = [0, 0, 0, 0, 0]
		for li in range(int(strip[4])):
			for k in range(n):
				counts[_ink(img.get_pixelv(strip[1] + across * li + along * k))] += 1
		var dom: int = counts.find(counts.max())
		for li in range(int(strip[4])):
			var start: Vector2i = strip[1] + across * li
			var ink: Array[bool] = []
			for k in range(-1, n + 1):
				ink.append(_ink(img.get_pixelv(start + along * k)) != dom)
			# ink[0] is the corner pixel before the strip, ink[n + 1] the one after it.
			var run: int = 0
			while run < n and ink[run + 1]:
				run += 1
			if ink[0] and ink[1] and run < n:
				out.append("%s edge, line %d: ink crosses the margin and runs %d px into the edge" % [String(strip[0]), li, run])
			var back: int = 0
			while back < n and ink[n - back]:
				back += 1
			if ink[n + 1] and ink[n] and back < n:
				out.append("%s edge, line %d: ink crosses the far margin and runs %d px into the edge" % [String(strip[0]), li, back])
	return out


# What is wrong with one bracketed style's widened margins `want` against its native texture and
# the manifest's `native` margins: narrower than the manifest on any side, a bracket carried into a
# stretched edge, or a side a pixel wider than its bracket needs.
func _bracket_faults(id: String, img: Image, want: Array, native: Array) -> Array[String]:
	var faults: Array[String] = []
	if img == null or img.is_empty():
		faults.append("%s: no texture to measure its bracket on" % id)
		return faults
	if want.size() != 4:
		faults.append("%s: Kit.BRACKET_MARGINS gives %s, not [l, t, r, b]" % [id, str(want)])
		return faults
	var sides: Array[String] = ["left", "top", "right", "bottom"]
	for i in range(4):
		if int(want[i]) < int(native[i]):
			faults.append("%s: its %s margin %d is narrower than the manifest's %d" % [id, sides[i], int(want[i]), int(native[i])])
	for p in _protrusions(img, want):
		faults.append("%s at %s: %s" % [id, str(want), p])
	for i in range(4):
		if int(want[i]) <= int(native[i]):
			continue
		var less: Array = want.duplicate()
		less[i] = int(less[i]) - 1
		if _protrusions(img, less).is_empty():
			faults.append("%s: its %s margin %d is wider than its bracket needs -- %d already holds it" % [id, sides[i], int(want[i]), int(less[i])])
	return faults


# Every surface a kit style is drawn on, at its smallest, read from the drawing file's own
# constants: [where, style ids, size in screen pixels]. A surface that falls under a style's
# doubled margins gets no kit frame at all -- `Kit.style` hands back null and the caller draws its
# fallback -- so a widened margin must be checked against every one of them.
func _surfaces() -> Array:
	var shell: Dictionary = (load("res://ui/shell.gd") as GDScript).get_script_constant_map()
	var bag: Dictionary = (load("res://ui/bag_grid.gd") as GDScript).get_script_constant_map()
	var strip: Dictionary = (load("res://ui/quick_strip.gd") as GDScript).get_script_constant_map()
	var inv: Dictionary = (load(INVENTORY_GD) as GDScript).get_script_constant_map()
	var bench: Dictionary = (load("res://ui/bench_panel.gd") as GDScript).get_script_constant_map()
	var hud: Dictionary = (load("res://ui/hud.gd") as GDScript).get_script_constant_map()
	var cap: float = float((load(CHROME_GD) as GDScript).get_script_constant_map()["KEYCAP_MIN"])
	var cell: float = float(bag["CELL"])
	return [
		["a shell row", ["button_normal", "button_hover", "button_focus", "button_danger"], Vector2(float(shell["PANEL_W"]) - float(shell["PAD"]) * 2.0, float(shell["ROW_H"]))],
		["a bag cell", ["slot_empty"], Vector2(cell - 4.0, cell - 4.0)],
		["a one-cell item plate and its selection ring", ["panel_inset", "slot_selected"], Vector2(cell - 8.0, cell - 8.0)],
		["a quick-strip slot", ["slot_empty", "slot_selected"], Vector2(float(strip["SLOT_W"]), float(strip["SLOT_H"]))],
		["an equipment slot", ["slot_empty", "slot_selected"], Vector2(float(inv["SLOT_W"]), float(inv["SLOT_H"]))],
		["a bench row", ["slot_empty"], Vector2(200.0, float(bench["ROW_H"]) - 4.0)],
		["the action bar", ["panel_standard"], Vector2(400.0, float(hud["BAR_H"]))],
		["the smallest keycap", ["keycap"], Vector2(cap, cap)],
	]


func _surface_faults(surfaces: Array) -> Array[String]:
	var faults: Array[String] = []
	for s_v in surfaces:
		var surf: Array = s_v as Array
		for id_v in surf[1] as Array:
			var id: String = String(id_v)
			if Kit.style(id, Rect2(Vector2.ZERO, surf[2] as Vector2), 1.0) == null:
				faults.append("%s (%s) is under %s's margins %s -- it would fall back to a drawn fill" % [String(surf[0]), str(surf[2]), id, str(Kit.margins(id))])
	return faults


# A copy of `st` with its frame and centre refilled in the given modes -- the shape a fabricated
# disagreement takes, so the comparator judges the same Kit.Style it judges for the shipped kit.
func _restyled(st: Kit.Style, edges: int, centre: int) -> Kit.Style:
	var out := Kit.Style.new()
	out.border = st.border.duplicate() as StyleBoxTexture
	out.border.axis_stretch_horizontal = edges
	out.border.axis_stretch_vertical = edges
	out.centre = st.centre.duplicate() as StyleBoxTexture
	out.centre.axis_stretch_horizontal = centre
	out.centre.axis_stretch_vertical = centre
	out.inset_begin = st.inset_begin
	out.inset_end = st.inset_end
	return out


func _kit_lane(manifest: Dictionary) -> bool:
	var ok: bool = true
	var assets: Dictionary = _records(manifest, "assets")
	var checked: int = 0
	for id_v in Kit.NINE.keys():
		var id: String = String(id_v)
		var code: Array = Kit.NINE[id] as Array
		var faults: Array[String] = _margin_faults(id, code, assets.get(id, null))
		faults.append_array(_tres_faults(id, code, _text_of(STYLES_DIR + id + ".tres")))
		for f in faults:
			push_error("KIT: " + f)
			ok = false
		checked += 1
	for f in _coverage_faults(manifest.get("assets", []) as Array, Kit.NINE):
		push_error("KIT: " + f)
		ok = false
	if Kit.SCALE != OWNER_SCALE:
		push_error("KIT: Kit.SCALE is %d; the owner's decision is %d" % [Kit.SCALE, OWNER_SCALE])
		ok = false
	# The one exception to the scale is named in kit.gd and held to a style that exists; every
	# other style draws at the owner's scale (true negative: panel_standard is not native).
	for id_v in Kit.NATIVE_STYLES:
		if not Kit.NINE.has(String(id_v)) or Kit.scale_of(String(id_v)) != 1:
			push_error("KIT: Kit.NATIVE_STYLES names %s, which NINE does not wear or which does not draw at 1x" % String(id_v))
			ok = false
	if Kit.scale_of("panel_standard") != OWNER_SCALE:
		push_error("KIT: panel_standard draws at %dx, not the owner's %dx" % [Kit.scale_of("panel_standard"), OWNER_SCALE])
		ok = false
	for f in _group_faults(Kit.NINE, Kit.EDGE_TILED, Kit.BRACKET_MARGINS):
		push_error("KIT: " + f)
		ok = false
	for id_v in Kit.NINE.keys():
		var id: String = String(id_v)
		var built: Kit.Style = Kit.style(id, Rect2(0, 0, 400, 400), 1.0)
		if built == null:
			push_error("KIT: %s built no style at 400x400 -- its fill mode cannot be judged" % id)
			ok = false
			continue
		for f in _mode_faults(id, built, CENTRE_MODE_DEVIATION, EDGE_DEVIATION, Kit.EDGE_TILED.has(id)):
			push_error("KIT: " + f)
			ok = false
		for f in _draw_margin_faults(id, built):
			push_error("KIT: " + f)
			ok = false
	# The widened margins, re-measured on the native pixels.
	var widened: int = 0
	for id_v in Kit.BRACKET_MARGINS.keys():
		var id: String = String(id_v)
		if not Kit.NINE.has(id):
			continue
		var native: Texture2D = Kit.texture("textures/%s.png" % id, 1)
		for f in _bracket_faults(id, native.get_image() if native != null else null, Kit.BRACKET_MARGINS[id] as Array, Kit.NINE[id] as Array):
			push_error("KIT: " + f)
			ok = false
		if Kit.BRACKET_MARGINS[id] != Kit.NINE[id]:
			widened += 1
	if widened == 0:
		push_error("KIT: MARGIN_DEVIATION names a widening, and no Kit.BRACKET_MARGINS entry is wider than the manifest -- it departs from nothing")
		ok = false
	if String(MARGIN_DEVIATION.get("why", "")).strip_edges().is_empty():
		push_error("KIT: MARGIN_DEVIATION gives no reason")
		ok = false
	var surfaces: Array = _surfaces()
	for f in _surface_faults(surfaces):
		push_error("KIT: " + f)
		ok = false
	for id_v in UNUSED_STYLES.keys():
		if not assets.has(String(id_v)):
			push_error("KIT: UNUSED_STYLES names %s, which the kit does not ship" % String(id_v))
			ok = false

	# True negatives: the comparators that passed the shipped files refuse one wrong thing each.
	var bad_rec: Dictionary = (assets.get("panel_standard", {}) as Dictionary).duplicate(true)
	bad_rec["nine_slice_ltrb"] = [10, 10, 11, 10]
	if _margin_faults("panel_standard", Kit.NINE["panel_standard"] as Array, bad_rec).is_empty():
		push_error("KIT: a manifest record with right margin 11 against the code's 10 passed -- the comparator cannot fail")
		ok = false
	var tres: String = _text_of(STYLES_DIR + "panel_standard.tres")
	if _tres_faults("panel_standard", Kit.NINE["panel_standard"] as Array, tres.replace("texture_margin_right = 10.0", "texture_margin_right = 11.0")).is_empty():
		push_error("KIT: a .tres with texture_margin_right = 11.0 against the code's 10 passed")
		ok = false
	if _tres_faults("panel_standard", Kit.NINE["panel_standard"] as Array, tres + "axis_stretch_horizontal = 1\n").is_empty():
		push_error("KIT: a .tres that sets an axis mode kit.gd does not build passed")
		ok = false
	if _tres_faults("panel_standard", Kit.NINE["panel_standard"] as Array, tres + "expand_margin_left = 2.0\n").is_empty():
		push_error("KIT: a .tres that sets an expand margin kit.gd does not build passed")
		ok = false
	var tile: int = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var stretch: int = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var shipped: Kit.Style = Kit.style("button_focus", Rect2(0, 0, 400, 400), 1.0)
	var dashed: Kit.Style = Kit.style("slot_empty", Rect2(0, 0, 400, 400), 1.0)
	var focus_px: Texture2D = Kit.texture("textures/button_focus.png", 1)
	if shipped == null or shipped.centre == null or dashed == null or dashed.centre == null or focus_px == null:
		push_error("KIT: button_focus or slot_empty built no filled style -- the fill comparator's negatives cannot be judged")
		ok = false
	else:
		if not _mode_faults("button_focus", shipped, CENTRE_MODE_DEVIATION, EDGE_DEVIATION, false).is_empty() or not _mode_faults("slot_empty", dashed, CENTRE_MODE_DEVIATION, EDGE_DEVIATION, true).is_empty():
			push_error("KIT: the shipped button_focus or slot_empty under the named deviations was refused -- the comparator cannot pass")
			ok = false
		var own_centre: Kit.Style = _restyled(shipped, stretch, tile)
		own_centre.border.draw_center = true
		var whole: Kit.Style = _restyled(shipped, stretch, tile)
		whole.centre.region_rect = Rect2(Vector2.ZERO, whole.border.texture.get_size())
		var both: Array = Kit.EDGE_TILED.duplicate()
		both.append("button_focus")
		var neither: Array = Kit.EDGE_TILED.duplicate()
		neither.erase("slot_empty")
		var focus_img: Image = focus_px.get_image()
		var wide: Array = (Kit.BRACKET_MARGINS["button_focus"] as Array).duplicate()
		wide[0] = int(wide[0]) + 1
		# slot_hover's bracket sits inside the kit's own margins, so a top margin one under the
		# manifest's is refused for that alone, not for a bracket it lets through.
		var hover_px: Texture2D = Kit.texture("textures/slot_hover.png", 1)
		var under: Array = (Kit.NINE["slot_hover"] as Array).duplicate()
		under[1] = int(under[1]) - 1
		var native_frame: Kit.Style = _restyled(shipped, stretch, tile)
		native_frame.border.texture_margin_left = float(int(Kit.NINE["button_focus"][0]) * Kit.SCALE)
		var short: Array = surfaces.duplicate()
		short.append(["a fabricated 30 px shell row", ["button_danger"], Vector2(560.0, 30.0)])
		var refusals: Array = [
			["a style in both edge groups passed", _group_faults(Kit.NINE, both, Kit.BRACKET_MARGINS)],
			["a style in neither edge group passed", _group_faults(Kit.NINE, neither, Kit.BRACKET_MARGINS)],
			["a tiled-edge style whose frame stretches passed -- slot_empty's dashes would lengthen", _mode_faults("slot_empty", _restyled(dashed, stretch, tile), CENTRE_MODE_DEVIATION, EDGE_DEVIATION, true)],
			["a bracketed style whose frame tiles passed -- every bracket fragment repeated along its border", _mode_faults("button_focus", _restyled(shipped, tile, tile), CENTRE_MODE_DEVIATION, EDGE_DEVIATION, false)],
			["a tiled-edge style with no edge deviation named passed -- a silent departure from the .tres", _mode_faults("slot_empty", dashed, CENTRE_MODE_DEVIATION, {}, true)],
			["a shipped style with no centre deviation named passed -- a silent departure from the .tres", _mode_faults("button_focus", shipped, {}, EDGE_DEVIATION, false)],
			["a stretched centre under a deviation that says tile passed", _mode_faults("button_focus", _restyled(shipped, stretch, stretch), CENTRE_MODE_DEVIATION, EDGE_DEVIATION, false)],
			["a frame that draws its own centre passed", _mode_faults("button_focus", own_centre, CENTRE_MODE_DEVIATION, EDGE_DEVIATION, false)],
			["a centre fill tiling the whole texture, frame and all, passed", _mode_faults("button_focus", whole, CENTRE_MODE_DEVIATION, EDGE_DEVIATION, false)],
			["a centre deviation naming the .tres files' own stretch passed", _mode_faults("button_focus", _restyled(shipped, stretch, stretch), {"centre": stretch, "why": "x"}, EDGE_DEVIATION, false)],
			["an edge deviation naming the .tres files' own stretch passed", _mode_faults("slot_empty", _restyled(dashed, stretch, tile), CENTRE_MODE_DEVIATION, {"tiled": stretch, "why": "x"}, true)],
			["button_focus at the kit's own margins, narrower than its bracket, passed", _bracket_faults("button_focus", focus_img, Kit.NINE["button_focus"] as Array, Kit.NINE["button_focus"] as Array)],
			["button_focus a pixel wider than its bracket needs passed", _bracket_faults("button_focus", focus_img, wide, Kit.NINE["button_focus"] as Array)],
			["slot_hover under the manifest's top margin passed", _bracket_faults("slot_hover", hover_px.get_image() if hover_px != null else null, under, Kit.NINE["slot_hover"] as Array)],
			["a button_focus frame built at the kit's own left margin rather than its widened one passed", _draw_margin_faults("button_focus", native_frame)],
			["a shell row too short for button_danger's widened margins passed", _surface_faults(short)],
		]
		for r_v in refusals:
			if ((r_v as Array)[1] as Array).is_empty():
				push_error("KIT: " + String((r_v as Array)[0]))
				ok = false
	var ghost: Array = (manifest.get("assets", []) as Array).duplicate(true)
	ghost.append({"id": "panel_ghost", "category": "chrome", "nine_slice_ltrb": [4, 4, 4, 4]})
	if _coverage_faults(ghost, Kit.NINE).is_empty():
		push_error("KIT: a kit chrome id in neither Kit.NINE nor UNUSED_STYLES passed")
		ok = false
	_stash["styles"] = checked
	if ok:
		print("KIT OK %d styles agree with manifest.json and their .tres at native pixels, drawn at the owner's %dx (%s at 1x, named), centres tiled; %d tile their edges and %d stretch them, %d of those at margins widened to hold their brackets, re-measured on the pixels; %d surfaces clear their styles' margins; %d kit chrome pieces left unused with a reason; twenty-one fabricated disagreements each refused" % [checked, Kit.SCALE, ", ".join(Kit.NATIVE_STYLES), Kit.EDGE_TILED.size(), Kit.BRACKET_MARGINS.size(), widened, surfaces.size(), UNUSED_STYLES.size()])
	return ok


# --- 2. RESOLVE --------------------------------------------------------------------------------


func _resolve_lane(manifest: Dictionary) -> bool:
	var ok: bool = true
	Kit.forget()
	var assets: Dictionary = _records(manifest, "assets")
	var sprites: Dictionary = _records(manifest, "sprites")
	var textures: int = 0
	for id_v in Kit.NINE.keys():
		var id: String = String(id_v)
		var tex: Texture2D = Kit.texture("textures/%s.png" % id, Kit.scale_of(id))
		var want: Array[int] = _ints((assets.get(id, {}) as Dictionary).get("size", null))
		if tex == null:
			push_error("RESOLVE: textures/%s.png did not resolve headless" % id)
			ok = false
		elif want.size() != 2 or Vector2i(tex.get_size()) != Vector2i(want[0], want[1]) * Kit.scale_of(id):
			push_error("RESOLVE: %s resolved at %s, the manifest says %s at %dx" % [id, str(tex.get_size()), str(want), Kit.scale_of(id)])
			ok = false
		else:
			textures += 1
	var glyphs: int = 0
	for rec_v in manifest.get("assets", []) as Array:
		var rec: Dictionary = rec_v as Dictionary
		if String(rec.get("category", "")) != "glyphs":
			continue
		var id: String = String(rec.get("id", ""))
		var big: Texture2D = Kit.glyph(id)
		var small: Texture2D = Kit.glyph(id, true)
		var want_big: Array[int] = _ints(rec.get("size", null))
		var want_small: Array[int] = _ints((sprites.get(id + "_small", {}) as Dictionary).get("size", null))
		if big == null or small == null:
			push_error("RESOLVE: glyph %s did not resolve headless (big %s, small %s)" % [id, str(big != null), str(small != null)])
			ok = false
			continue
		if want_big.size() != 2 or Vector2i(big.get_size()) != Vector2i(want_big[0], want_big[1]) * Kit.GLYPH_SCALE:
			push_error("RESOLVE: glyph %s is %s, the manifest says %s at %dx" % [id, str(big.get_size()), str(want_big), Kit.GLYPH_SCALE])
			ok = false
		elif want_small.size() != 2 or Vector2i(small.get_size()) != Vector2i(want_small[0], want_small[1]) * Kit.GLYPH_SCALE:
			push_error("RESOLVE: glyph %s small is %s, the manifest says %s at %dx" % [id, str(small.get_size()), str(want_small), Kit.GLYPH_SCALE])
			ok = false
		elif Kit.glyph(id.trim_prefix("glyph_")) != big:
			push_error("RESOLVE: glyph %s and its short name %s resolve to different textures" % [id, id.trim_prefix("glyph_")])
			ok = false
		else:
			glyphs += 1
	if glyphs == 0:
		push_error("RESOLVE: the manifest named no glyphs -- nothing was judged")
		ok = false
	# True negatives: a name the kit does not ship resolves to nothing, at every door.
	if Kit.texture("textures/panel_nonesuch.png") != null:
		push_error("RESOLVE: a texture the kit does not ship resolved")
		ok = false
	if Kit.glyph("nonesuch") != null or Kit.glyph("nonesuch", true) != null:
		push_error("RESOLVE: a glyph the kit does not ship resolved")
		ok = false
	if Kit.style("panel_nonesuch", Rect2(0, 0, 200, 120), 1.0) != null:
		push_error("RESOLVE: a style id Kit.NINE does not name built a style")
		ok = false
	if Kit.style("button_disabled", Rect2(0, 0, 200, 120), 1.0) != null:
		push_error("RESOLVE: button_disabled, listed unused, built a style")
		ok = false
	_stash["textures"] = textures
	_stash["glyphs"] = glyphs
	if ok:
		print("RESOLVE OK %d kit textures at their draw scale (%dx, the keycap 1x) and %d glyphs at both sizes at %dx resolve headless at the manifest's sizes; a made-up texture, glyph and style, and an unused one, resolve to nothing" % [textures, Kit.SCALE, glyphs, Kit.GLYPH_SCALE])
	return ok


# --- 3. PANEL ----------------------------------------------------------------------------------


# Does `fn` reach the kit: `Kit.style(` and `.draw(` in its own body, or through a call to
# another function in `bodies` that does, one link deep. The link is followed rather than the
# needle dropped because a helper that moves its draw into a shared function is still correct.
func _reaches_kit(bodies: Dictionary, fn: String) -> bool:
	var body: String = String(bodies.get(fn, ""))
	if body.contains("Kit.style(") and body.contains(".draw("):
		return true
	for other_v in bodies.keys():
		var other: String = String(other_v)
		if other == fn:
			continue
		var callee: String = String(bodies[other])
		if _calls(body, other) and callee.contains("Kit.style(") and callee.contains(".draw("):
			return true
	return false


# Whether `body` calls `fn(` as a bare name (not `x.fn(`, not `other_fn(`).
func _calls(body: String, fn: String) -> bool:
	var re: RegEx = RegEx.new()
	re.compile("(^|[^A-Za-z0-9_.])%s\\(" % fn)
	return re.search(body) != null


func _panel_lane() -> bool:
	var ok: bool = true
	var big: Rect2 = Rect2(0, 0, 200, 120)
	var sb: Kit.Style = Kit.style("panel_standard", big, 0.4)
	if sb == null or sb.border == null or sb.border.texture == null or sb.centre == null:
		push_error("PANEL: Kit.style(panel_standard, 200x120, 0.4) gave no textured frame and centre")
		ok = false
	else:
		if absf(sb.border.modulate_color.a - 0.4) > 0.001 or absf(sb.centre.modulate_color.a - 0.4) > 0.001:
			push_error("PANEL: the style's opacity is %.3f (frame) / %.3f (centre), asked 0.4" % [sb.border.modulate_color.a, sb.centre.modulate_color.a])
			ok = false
		var m: Array[int] = [int(sb.border.texture_margin_left), int(sb.border.texture_margin_top), int(sb.border.texture_margin_right), int(sb.border.texture_margin_bottom)]
		var want_m: Array[int] = []
		for n in _ints(Kit.NINE["panel_standard"]):
			want_m.append(n * Kit.SCALE)
		if m != want_m or m != Kit.margins("panel_standard"):
			push_error("PANEL: the built style's margins %s are not Kit.NINE's times %d, %s" % [str(m), Kit.SCALE, str(want_m)])
			ok = false
		if sb.inset_begin != Vector2(want_m[0], want_m[1]) or sb.inset_end != Vector2(want_m[2], want_m[3]):
			push_error("PANEL: the centre is drawn inset by %s/%s, not the frame's margins %s" % [str(sb.inset_begin), str(sb.inset_end), str(want_m)])
			ok = false
		if Vector2i(sb.border.texture.get_size()) != Vector2i(64, 64) * Kit.SCALE:
			push_error("PANEL: the built style's texture is %s, not the 64 px kit texture at %dx" % [str(sb.border.texture.get_size()), Kit.SCALE])
			ok = false
		if not is_same(sb, Kit.style("panel_standard", big, 0.4)):
			push_error("PANEL: the same style at the same opacity was built twice -- it is not cached")
			ok = false
		var edge: Kit.Style = Kit.style("panel_standard", big, 0.4, false)
		if edge == null or edge.centre != null or is_same(edge, sb):
			push_error("PANEL: the border-only pass is missing, draws its centre, or shares the filled style")
			ok = false
		elif not is_same(edge.border, sb.border):
			push_error("PANEL: the border-only pass built its own frame -- one frame per id per opacity is the cache's promise")
			ok = false
		var faded: Kit.Style = Kit.style("panel_standard", big, 0.9)
		if faded == null or is_same(faded, sb) or absf(faded.border.modulate_color.a - 0.9) > 0.001 or absf(faded.centre.modulate_color.a - 0.9) > 0.001:
			push_error("PANEL: a different opacity did not give its own style")
			ok = false
	# The margin boundary, both sides of it: two 10 kit-pixel margins at Kit.SCALE.
	var edge_px: float = float(20 * Kit.SCALE)
	if Kit.style("panel_standard", Rect2(0, 0, edge_px - 1.0, 120), 0.4) != null:
		push_error("PANEL: a %d px wide rect under %d px of margins built a style" % [int(edge_px) - 1, int(edge_px)])
		ok = false
	if Kit.style("panel_standard", Rect2(0, 0, 200, edge_px - 1.0), 0.4) != null:
		push_error("PANEL: a %d px tall rect under %d px of margins built a style" % [int(edge_px) - 1, int(edge_px)])
		ok = false
	if Kit.style("panel_standard", Rect2(0, 0, edge_px, edge_px), 0.4) == null:
		push_error("PANEL: a %d px rect, exactly the margins, built no style" % int(edge_px))
		ok = false

	# Textual: the shipped helpers reach the kit.
	var bodies: Dictionary = _bodies(_text_of(CHROME_GD))
	for fn in ["panel", "cell", "item_plate", "header"]:
		if not bodies.has(fn):
			push_error("PANEL: chrome.gd has no `func %s(`" % fn)
			ok = false
		elif not _reaches_kit(bodies, fn):
			push_error("PANEL: Chrome.%s does not reach `Kit.style(` and `.draw(` (followed one call deep)" % fn)
			ok = false
	# True negatives, through the same scanner: a body that only draws rectangles; a link to a
	# helper that itself only draws rectangles; and the needles present only in a comment.
	var only_rects: Dictionary = _bodies("static func panel(ci, rect, alpha):\n\tci.draw_rect(rect, Color.BLACK)\n")
	if _reaches_kit(only_rects, "panel"):
		push_error("PANEL: a fabricated panel that only calls draw_rect passed")
		ok = false
	var dead_link: Dictionary = _bodies("static func panel(ci, rect, alpha):\n\tframe(ci, rect, \"panel_standard\", alpha)\nstatic func frame(ci, rect, id, alpha):\n\tci.draw_rect(rect, Color.BLACK)\n")
	if _reaches_kit(dead_link, "panel"):
		push_error("PANEL: a fabricated panel whose frame() never reaches the kit passed")
		ok = false
	var commented: Dictionary = _bodies("static func panel(ci, rect, alpha):\n\t# Kit.style(\"panel_standard\", rect, alpha).draw(ci, rect)\n\tci.draw_rect(rect, Color.BLACK)\n")
	if _reaches_kit(commented, "panel"):
		push_error("PANEL: a fabricated panel that reaches the kit only in a comment passed")
		ok = false
	var live_link: Dictionary = _bodies("static func panel(ci, rect, alpha):\n\tframe(ci, rect, \"x\", alpha) # a comment\nstatic func frame(ci, rect, id, alpha):\n\tKit.style(id, rect, alpha).draw(ci.get_canvas_item(), rect)\n")
	if not _reaches_kit(live_link, "panel"):
		push_error("PANEL: a fabricated panel that does reach the kit through frame() was refused -- the scanner cannot pass")
		ok = false
	if ok:
		print("PANEL OK a textured frame and centre at the asked opacity and doubled margins, cached, border-only apart on the same frame, none under its margins; panel, cell, item_plate and header reach Kit.style and draw it; a rect-only body, a dead link and a commented needle each refused")
	return ok


# --- 4. HELPERS --------------------------------------------------------------------------------


# The public helpers a file declares: `static func name(`, not underscored.
func _public_helpers(text: String) -> Array[String]:
	var out: Array[String] = []
	for raw in text.split("\n"):
		var line: String = String(raw)
		if line.begins_with("static func ") and not line.begins_with("static func _"):
			var head: String = line.substr("static func ".length())
			out.append(head.substr(0, head.find("(")))
	return out


# Every file a chrome helper may be called from, comment-stripped: godot/ui/*.gd but chrome.gd
# itself -- a helper that only chrome.gd calls is still read by no screen -- and main.gd.
func _caller_sources() -> Dictionary:
	var out: Dictionary = {}
	var dir: DirAccess = DirAccess.open(UI_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".gd") and UI_DIR + f != CHROME_GD:
				out[UI_DIR + f] = _code_of(_text_of(UI_DIR + f))
	out[MAIN_GD] = _code_of(_text_of(MAIN_GD))
	return out


func _has_caller(sources: Dictionary, fn: String) -> bool:
	for src_v in sources.values():
		if String(src_v).contains("Chrome.%s(" % fn):
			return true
	return false


func _helpers_lane() -> bool:
	var ok: bool = true
	var helpers: Array[String] = _public_helpers(_text_of(CHROME_GD))
	var sources: Dictionary = _caller_sources()
	if helpers.is_empty() or sources.size() < 2:
		push_error("HELPERS: found %d helpers and %d caller files -- nothing to judge" % [helpers.size(), sources.size()])
		return false
	var called: int = 0
	for fn in helpers:
		var has: bool = _has_caller(sources, fn)
		if PENDING.has(fn):
			if has:
				push_error("HELPERS: Chrome.%s now has a caller -- take it out of PENDING in the same commit" % fn)
				ok = false
			else:
				print("SKIP HELPERS: Chrome.%s has no caller outside chrome.gd yet; it lands with %s" % [fn, String(PENDING[fn])])
		elif has:
			called += 1
		else:
			push_error("HELPERS: Chrome.%s has no caller in godot/ui/ or main.gd -- a helper nothing reads is a dead socket" % fn)
			ok = false
	for fn_v in PENDING.keys():
		if not helpers.has(String(fn_v)):
			push_error("HELPERS: PENDING names Chrome.%s, which chrome.gd does not declare" % String(fn_v))
			ok = false
	# True negatives, through the same scanner: a name nothing calls, and a call only a comment
	# makes; and its true positive on a fabricated live call.
	if _has_caller(sources, "zz_nobody_calls_this"):
		push_error("HELPERS: a fabricated helper name found a caller")
		ok = false
	var fake: Dictionary = {"a.gd": _code_of("func _draw() -> void:\n\t# Chrome.zz_only_in_a_comment(self, r, 1.0)\n\tpass\n")}
	if _has_caller(fake, "zz_only_in_a_comment"):
		push_error("HELPERS: a call made only in a comment counted as a caller")
		ok = false
	var live: Dictionary = {"a.gd": _code_of("func _draw() -> void:\n\tChrome.zz_live(self, r, 1.0) # drawn\n")}
	if not _has_caller(live, "zz_live"):
		push_error("HELPERS: a live call was not found -- the scanner cannot pass")
		ok = false
	_stash["called"] = called
	if ok:
		print("HELPERS OK %d chrome helpers each called from a screen; %d pending their slice; a fabricated name and a commented call have no caller" % [called, PENDING.size()])
	return ok


# --- 5. FONT -----------------------------------------------------------------------------------


# One typeface (docs/23's record, "UI -- one typeface"): every screen draws with `Chrome.font()`,
# the kit's VT323 with the engine's font behind it, at a size on `Chrome.LADDER`.
#
#   FACE      Chrome.font() is a FontVariation over the kit's VT323-Pixel.res (by path and by the
#             face's own name), the engine's fallback font in its fallbacks, the "fi" ligature
#             off, one cached object; a fabricated variation over the engine font, one with no
#             fallbacks and one with the ligature on each fail the same checks.
#   FALLBACK  the fallback matters: VT323 lacks a letter the engine font carries. And every
#             non-ASCII character a screen or the content can put in front of the player is in
#             VT323, in the fallback, or named in FONT_NO_FACE with its reason -- a character in
#             none of the three fails, and so does a fabricated one.
#   METRICS   Chrome.ascent and line_height are the face's own, not the variation's, which a
#             fallback stretches to the engine font's taller line -- shown by the two differing.
#   SCAN      no .gd under godot/ui/ or godot/presentation/ but chrome.gd names
#             `ThemeDB.fallback_font`, comments stripped; a fabricated source that does is caught
#             and one that only says so in a comment is not.
#   LADDER    every text size a screen names -- an int const called *SIZE, *FONT, *SMALL or
#             *TIGHT, and every literal size in a draw_string or get_string_size call -- is on
#             Chrome.LADDER; a fabricated 18 is caught both ways and a fabricated 25 is not.

const FONT_PATH: String = "res://art/simplyzombies-ui/fonts/VT323-Pixel.res"
const FONT_DIRS: Array[String] = ["res://ui/", "res://presentation/"]
const CONTENT_DIR: String = "res://content/"
# A letter VT323 does not carry and the engine font does: the proof the fallback is not dead.
const FONT_FALLBACK_PROBE: String = "Ж"
# Characters the screens draw that neither face carries, each with its reason. A desktop build
# draws them through the operating system's own font fallback; the web build has none and draws a
# box -- which was as true under the engine font as under VT323, because the engine font does not
# carry them either (docs/23's record, "UI -- one typeface"). Named here so a new one cannot arrive
# unconsidered; one no source uses any more is reported, not failed, so the slice that retires it
# can take it off this list.
const FONT_NO_FACE: Dictionary = {
	"→": "the bench's offer line (bench_panel.gd); neither face has it -- the OS fallback draws it on desktop",
}


func _font_lane() -> bool:
	var ok: bool = true
	var chrome: GDScript = load(CHROME_GD) as GDScript
	if chrome == null:
		push_error("FONT: %s did not load" % CHROME_GD)
		return false
	var f: Variant = chrome.call("font")
	var engine: Font = ThemeDB.fallback_font

	# FACE, with a true negative for every check.
	var faults: Array[String] = _font_faults(f)
	if not faults.is_empty():
		push_error("FACE: Chrome.font() %s" % "; ".join(faults))
		ok = false
	if chrome.call("font") != f:
		push_error("FACE: Chrome.font() built a second object; it is cached, not built per draw")
		ok = false
	var base: FontFile = (f as FontVariation).base_font as FontFile if f is FontVariation else null
	var over_engine := FontVariation.new()
	over_engine.base_font = engine
	over_engine.fallbacks = [engine]
	over_engine.opentype_features = {"liga": 0}
	var no_fallback := FontVariation.new()
	no_fallback.base_font = base
	no_fallback.opentype_features = {"liga": 0}
	var ligatured := FontVariation.new()
	ligatured.base_font = base
	ligatured.fallbacks = [engine]
	for fake in [[over_engine, "the engine font as its face"], [no_fallback, "no fallbacks"], [ligatured, "the ligature on"]]:
		if _font_faults((fake as Array)[0]).is_empty():
			push_error("FACE: a variation with %s passed the checks the shipped font is held to; they cannot say no" % String((fake as Array)[1]))
			ok = false

	# FALLBACK: the fallback carries something the face does not, and every character the player
	# can be shown is carried by one of them or named.
	var probe: int = FONT_FALLBACK_PROBE.unicode_at(0)
	if base == null or base.has_char(probe) or not engine.has_char(probe):
		push_error("FALLBACK: VT323 should lack %s and the engine font carry it; the fallback proves nothing" % FONT_FALLBACK_PROBE)
		ok = false
	if _font_files(CONTENT_DIR, ".json").size() < 10:
		push_error("FALLBACK: fewer than ten content files under %s; the coverage check judged too little" % CONTENT_DIR)
		ok = false
	var shown: Dictionary = _font_shown_chars()
	var uncovered: Array[String] = _font_uncovered(base, engine, shown.keys())
	if not uncovered.is_empty():
		push_error("FALLBACK: neither VT323 nor the engine font carries %s, and FONT_NO_FACE does not name it (first seen in %s)" % [str(uncovered), str(uncovered.map(func(c: String) -> String: return String(shown[c])))])
		ok = false
	if _font_uncovered(base, engine, ["ↂ"]).is_empty():
		push_error("FALLBACK: a character no face carries passed the coverage check; it cannot say no")
		ok = false
	for c in FONT_NO_FACE.keys():
		if not shown.has(c):
			print("NOTE FALLBACK: FONT_NO_FACE names %s and no source draws it any more; take it off the list" % String(c))

	# METRICS: the helpers answer with the face's line, and the variation's own would not.
	if base != null:
		var face_ascent: float = base.get_ascent(25)
		if float(chrome.call("ascent", 25)) != face_ascent or float(chrome.call("line_height", 25)) != base.get_height(25):
			push_error("METRICS: Chrome.ascent/line_height at 25 are not VT323's own %.0f/%.0f" % [face_ascent, base.get_height(25)])
			ok = false
		if (f as Font).get_ascent(25) == face_ascent:
			push_error("METRICS: the variation's ascent equals the face's; the fallback no longer stretches it and the helpers' reason is gone -- re-read them")
			ok = false

	# SCAN: nobody but chrome.gd names the engine font.
	var sources: Dictionary = _font_sources()
	var named: Array[String] = []
	for path in sources.keys():
		if String(path) != CHROME_GD and _font_names_engine(String(sources[path])):
			named.append(String(path))
	if not named.is_empty():
		push_error("SCAN: %s name ThemeDB.fallback_font; every screen draws with Chrome.font()" % str(named))
		ok = false
	if not _font_names_engine(_code_of("func _draw() -> void:\n\tvar f: Font = ThemeDB.fallback_font\n")):
		push_error("SCAN: a fabricated source naming the engine font passed; the scanner cannot say no")
		ok = false
	if _font_names_engine(_code_of("func _draw() -> void:\n\t# was ThemeDB.fallback_font\n\tvar f: Font = Chrome.font()\n")):
		push_error("SCAN: a comment was read as code; the scanner cannot say yes")
		ok = false
	if sources.size() < 10:
		push_error("SCAN: only %d sources read under %s; the scan judged too little" % [sources.size(), str(FONT_DIRS)])
		ok = false

	# LADDER: every size a screen names is a rung.
	var ladder: Array = chrome.get("LADDER") as Array if chrome.get("LADDER") is Array else []
	if ladder.is_empty():
		push_error("LADDER: chrome.gd has no LADDER to hold the sizes to")
		ok = false
	var off: Array[String] = []
	var judged: int = 0
	for path in sources.keys():
		var found: Array = _font_sizes(String(sources[path]))
		judged += found.size()
		for hit in found:
			if not ladder.has(int((hit as Array)[0])):
				off.append("%s: %s" % [String(path).get_file(), String((hit as Array)[1])])
	if not off.is_empty():
		push_error("LADDER: text sizes off %s: %s" % [str(ladder), str(off)])
		ok = false
	if judged < 20:
		push_error("LADDER: only %d sizes found; the scan judged too little" % judged)
		ok = false
	var bad_const: Array = _font_sizes("const BODY_SIZE: int = 18\n")
	var bad_call: Array = _font_sizes("\tdraw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)\n")
	var good_call: Array = _font_sizes("\tdraw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, c)\n")
	if bad_const.size() != 1 or ladder.has(int((bad_const[0] as Array)[0])) or bad_call.size() != 1 or ladder.has(int((bad_call[0] as Array)[0])):
		push_error("LADDER: a fabricated 18, as a const and as a call, was not caught; the scan cannot say no")
		ok = false
	if good_call.size() != 1 or not ladder.has(int((good_call[0] as Array)[0])):
		push_error("LADDER: a fabricated 25 was not read as on the ladder; the scan cannot say yes")
		ok = false

	if ok:
		print("FONT OK Chrome.font() is VT323 over the engine font, ligature off, cached, and three fabricated variations fail; the fallback carries %s and VT323 does not; %d characters the player can be shown are each carried or named (%d named); the metrics are the face's; %d sources name no engine font; %d text sizes all on %s" % [FONT_FALLBACK_PROBE, shown.size(), FONT_NO_FACE.size(), sources.size(), judged, str(ladder)])
	return ok


# What is wrong with `f` as the one UI font, or nothing.
func _font_faults(f: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (f is FontVariation):
		out.append("is not a FontVariation")
		return out
	var v: FontVariation = f as FontVariation
	var base: Font = v.base_font
	if not (base is FontFile) or (base.resource_path != FONT_PATH and base.get_font_name() != "VT323"):
		out.append("is not over the kit's VT323 (%s)" % (base.resource_path if base != null else "no base"))
	if not v.fallbacks.has(ThemeDB.fallback_font):
		out.append("has no engine fallback behind it")
	var line := TextLine.new()
	line.add_string("first", v, 25)
	if TextServerManager.get_primary_interface().shaped_text_get_glyph_count(line.get_rid()) != 5:
		out.append("shapes \"first\" as other than five cells (a ligature is on)")
	return out


# Every non-ASCII character in a string literal of a screen's code, and in the content's text,
# mapped to the first file it was seen in.
func _font_shown_chars() -> Dictionary:
	var out: Dictionary = {}
	var sources: Dictionary = _font_sources()
	for path in sources.keys():
		for lit in _font_literals(String(sources[path])):
			for c in String(lit):
				if c.unicode_at(0) > 126 and not out.has(c):
					out[c] = String(path).get_file()
	for path in _font_files(CONTENT_DIR, ".json"):
		for c in _text_of(path):
			if c.unicode_at(0) > 126 and not out.has(c):
				out[c] = path.get_file()
	return out


# The characters in `chars` neither face carries and FONT_NO_FACE does not name.
func _font_uncovered(base: Font, engine: Font, chars: Array) -> Array[String]:
	var out: Array[String] = []
	for c_v in chars:
		var c: String = String(c_v)
		var code: int = c.unicode_at(0)
		if base != null and base.has_char(code):
			continue
		if engine.has_char(code) or FONT_NO_FACE.has(c):
			continue
		out.append(c)
	return out


func _font_names_engine(code: String) -> bool:
	return code.contains("ThemeDB.fallback_font")


# Every .gd under FONT_DIRS, comment-stripped, by path.
func _font_sources() -> Dictionary:
	var out: Dictionary = {}
	for d in FONT_DIRS:
		for path in _font_files(d, ".gd"):
			out[path] = _code_of(_text_of(path))
	return out


func _font_files(dir_path: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(ext):
			out.append(dir_path + f)
	for sub in dir.get_directories():
		out.append_array(_font_files(dir_path + sub + "/", ext))
	return out


# The contents of every double-quoted string literal in comment-stripped code.
func _font_literals(code: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for m in re.search_all(code):
		out.append(m.get_string(1))
	return out


# Every text size a source names, as [size, the text that named it]: an int const whose name
# ends in a size word, and a literal size after a draw_string/get_string_size alignment and width.
func _font_sizes(code: String) -> Array:
	var out: Array = []
	var konst := RegEx.new()
	konst.compile("(?m)^const ([A-Z0-9_]*(?:SIZE|FONT|SMALL|TIGHT)[A-Z0-9_]*): int = (\\d+)\\s*$")
	for m in konst.search_all(code):
		out.append([int(m.get_string(2)), m.get_string(0).strip_edges()])
	var call := RegEx.new()
	call.compile("HORIZONTAL_ALIGNMENT_[A-Z]+,\\s*[^,()\\n]+,\\s*(\\d+)\\s*[,)]")
	for m in call.search_all(code):
		out.append([int(m.get_string(1)), m.get_string(0)])
	return out


# --- 6. GLYPHS ---------------------------------------------------------------------------------


# Empty slots say what goes there (docs/23's record; the "UI Field Kit, live" what's-left group).
# Every one of the manifest's 32 glyphs is in exactly one of three lists, so a new glyph the kit
# ships cannot arrive unconsidered:
#
#   READERS         {glyph_id: {"file", "slice"}} -- consumed, with a named reader. The twelve
#                   equipment glyphs (`glyph_head` .. `glyph_secondary`) are verified by the
#                   EQUIP check below, because their reader is data-driven from
#                   `inventory_panel.gd`'s LEFT_SLOTS/RIGHT_SLOTS rather than a literal in a
#                   `Chrome.glyph(`/`Chrome.header(` call; every other entry is verified by
#                   `_calls_with_glyph`, which finds the glyph's short name quoted at exactly the
#                   glyph_name position of one of those calls, comments stripped, balanced parens
#                   followed so a `Vector2(...)` argument does not truncate the scan early -- and
#                   never at the *label* position, which a bare substring search cannot tell from
#                   a glyph_name naming it (settings_panel.gd's own "settings" title is exactly
#                   that shape).
#   PENDING_GLYPHS  {glyph_id: slice name} -- awaits a later slice, printed as a SKIP. A pending
#                   glyph that already has a caller anywhere under godot/ui/ is a failure, the
#                   HELPERS lane's rule applied here: PENDING says "not yet", so the day it is
#                   read is the day the name leaves this list, not the day it quietly still sits
#                   in it.
#   UNUSED_GLYPHS   {glyph_id: reason} -- the owner did not take it, or it has nothing to attach
#                   to yet, each said out loud rather than left silent.
#
# Every kit frame this slice's files draw goes through `Chrome.frame`: `inventory_panel.gd`'s
# equipment slots, `quick_strip.gd`'s boxes and `bag_grid.gd`'s selection ring -- none keeps a
# private `Kit.style(...).draw(...)` of its own. `Chrome.glyph` left the PENDING dict in the commit
# that landed this slice, which gave it callers.

const INVENTORY_GD: String = "res://ui/inventory_panel.gd"

# The twelve equipment glyphs, verified by mapping (EQUIP below), and the four this slice reads
# by a literal in a Chrome.glyph(/Chrome.header( call.
const READERS: Dictionary = {
	"glyph_head": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_eyes": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_face": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_gloves": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_belt": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_primary": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_vest": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_torso": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_legs": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_feet": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_back": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_secondary": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_condition": {"file": INVENTORY_GD, "slice": "S3 Empty slots say what goes there"},
	"glyph_inspect": {"file": "res://ui/inspect_pane.gd", "slice": "S3 Empty slots say what goes there"},
	"glyph_inventory": {"file": "res://ui/bag_grid.gd", "slice": "S3 Empty slots say what goes there"},
	"glyph_settings": {"file": "res://ui/settings_panel.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_journal": {"file": "res://ui/legend.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_work": {"file": "res://ui/work_panel.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_skills": {"file": "res://ui/web_panel.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_pause": {"file": "res://ui/shell.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_warning": {"file": "res://ui/shell.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_right": {"file": "res://ui/shell.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_up": {"file": "res://ui/bench_panel.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_down": {"file": "res://ui/bench_panel.gd", "slice": "S4 The shell's rows are buttons"},
	"glyph_left": {"file": "res://ui/bench_panel.gd", "slice": "S4 The shell's rows are buttons"},
	# The word menu's gutter reads its glyphs through a verb-prefix table, not a literal at the
	# call: `table` names the const whose values must carry the glyph, in a file whose draw path
	# reaches Chrome.glyph( (the KEYCAPS lane proves every prefix resolves and widens size_of).
	"glyph_use": {"file": ITEM_MENU_GD, "table": "GLYPHS", "slice": "S5 Keys wear keycaps"},
	"glyph_drop": {"file": ITEM_MENU_GD, "table": "GLYPHS", "slice": "S5 Keys wear keycaps"},
	"glyph_search": {"file": ITEM_MENU_GD, "table": "GLYPHS", "slice": "S5 Keys wear keycaps"},
	"glyph_move": {"file": ITEM_MENU_GD, "table": "GLYPHS", "slice": "S5 Keys wear keycaps"},
}

# Kit glyphs the screens await a later slice for. Empty since "The shell's rows are buttons" gave
# the last ten their readers; kept, because a glyph that lands ahead of its reader belongs here.
const PENDING_GLYPHS: Dictionary = {
}

# The owner's 2026-09-25 decision (docs/30, "The UI Field Kit, live") keeps these out, each with
# its reason. `glyph_close` joins them here rather than in READERS: the approved mockup draws it
# beside a "Tab · Close" title bar (previews/inventory-approved.png), and this screen has no such
# hint yet to attach it to -- inventory_panel.gd's own close hint is the Tab binding in the
# action bar's legend (input_map.gd), not a word on this sheet.
const UNUSED_GLYPHS: Dictionary = {
	"glyph_lock": "no lock mechanic -- docs/30, \"The UI Field Kit, live\"",
	"glyph_rotate": "not taken by the owner -- docs/30, \"The UI Field Kit, live\"",
	"glyph_close": "the inventory sheet has no close hint yet to draw it beside -- the approved mockup's \"Tab · Close\" title bar is not built",
}


# Every glyph id under `manifest.json`'s "glyphs" category.
func _all_glyphs(manifest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for rec_v in manifest.get("assets", []) as Array:
		var rec: Dictionary = rec_v as Dictionary
		if String(rec.get("category", "")) == "glyphs":
			out.append(String(rec.get("id", "")))
	return out


# What is wrong with `glyphs` against the three lists: not in exactly one. Parameterised on the
# three dicts (not the consts) so a fabricated combination can prove the comparator both ways.
func _glyph_membership_faults(glyphs: Array, readers: Dictionary, pending: Dictionary, unused: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	for g_v in glyphs:
		var g: String = String(g_v)
		var lists: int = int(readers.has(g)) + int(pending.has(g)) + int(unused.has(g))
		if lists != 1:
			faults.append("%s is in %d of READERS/PENDING_GLYPHS/UNUSED_GLYPHS, not exactly one" % [g, lists])
	return faults


# Two independent claims about `slots` (LEFT_SLOTS+RIGHT_SLOTS, read from inventory_panel.gd
# rather than assumed), kept as separate comparators so a true-positive probe of one is not
# tripped by the other -- a single-slot array proving coverage is not also a twelve-slot array.

# The count is twelve.
func _equip_count_faults(slots: Array) -> Array[String]:
	var faults: Array[String] = []
	if slots.size() != 12:
		faults.append("LEFT_SLOTS+RIGHT_SLOTS name %d slots, expected 12" % slots.size())
	return faults


# Every slot has a `glyph_<slot>` entry in `readers`.
func _equip_coverage_faults(slots: Array, readers: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	for slot_v in slots:
		var slot: String = String(slot_v)
		var gid: String = "glyph_" + slot
		if not readers.has(gid):
			faults.append("equipment slot \"%s\" has no READERS entry (%s)" % [slot, gid])
	return faults


# The glyph_name argument's position in each callee's signature -- `glyph(ci, glyph_name, at,
# small, alpha)`, `header(ci, rect, label, alpha, glyph_name = "")`. Position matters and a bare
# substring search does not: `Chrome.header(self, p, "settings", 0.97)` (settings_panel.gd's own
# title, four arguments, no glyph_name at all) contains the quoted word "settings" in its *label*
# argument, which a substring check cannot tell from a glyph_name naming it -- proven below by the
# LABEL-ONLY true negative, which a plain `.contains(quoted)` scan does not refuse.
const GLYPH_ARG_INDEX: Dictionary = {"Chrome.glyph": 1, "Chrome.header": 4}


# Every call to `callee(` in `code`, each as its own top-level argument list: commas and parens
# inside a nested call (`Vector2(10.0, 20.0)`, `String(column.get("label", ""))`) or a quoted
# string do not split or close it early.
func _call_arg_lists(code: String, callee: String) -> Array:
	var out: Array = []
	var needle: String = callee + "("
	var start: int = 0
	while true:
		var idx: int = code.find(needle, start)
		if idx == -1:
			break
		var depth: int = 1
		var i: int = idx + needle.length()
		var arg_start: int = i
		var args: Array[String] = []
		var quote: String = ""
		while i < code.length() and depth > 0:
			var ch: String = code[i]
			if quote != "":
				if ch == "\\":
					i += 2
					continue
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
			elif ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
				if depth == 0:
					args.append(code.substr(arg_start, i - arg_start).strip_edges())
					i += 1
					break
			elif ch == "," and depth == 1:
				args.append(code.substr(arg_start, i - arg_start).strip_edges())
				arg_start = i + 1
			i += 1
		out.append(args)
		start = idx + needle.length()
	return out


# Whether `code` (comments stripped) calls `callee` with the quoted `short` glyph name at exactly
# the glyph_name position `GLYPH_ARG_INDEX` names for it -- never merely somewhere in the call.
func _calls_with_glyph(code: String, callee: String, short: String) -> bool:
	var pos: int = int(GLYPH_ARG_INDEX.get(callee, -1))
	if pos < 0:
		return false
	var quoted: String = "\"" + short + "\""
	for args_v in _call_arg_lists(code, callee):
		var args: Array = args_v as Array
		if args.size() > pos and String(args[pos]) == quoted:
			return true
	return false


# Every file a glyph may be read from, comment-stripped -- `godot/ui/*.gd` and `main.gd`, chrome
# itself included: a glyph consumed only from a comment-stripped chrome.gd would still be a live
# reader for `PENDING_GLYPHS`'s dead-socket check, even though none of this slice's readers are.
func _glyph_sources() -> Dictionary:
	var out: Dictionary = _caller_sources()
	out[CHROME_GD] = _code_of(_text_of(CHROME_GD))
	return out



# Whether `file`'s const `table` (a Dictionary) carries `short` among its values -- the reader
# shape for glyphs a screen picks by lookup rather than by a literal at the call.
func _table_reads_glyph(file: String, table: String, short: String) -> bool:
	var script: GDScript = load(file) as GDScript
	if script == null:
		return false
	var consts: Dictionary = script.get_script_constant_map()
	if not consts.has(table) or not (consts[table] is Dictionary):
		return false
	for v in (consts[table] as Dictionary).values():
		if String(v) == short:
			return true
	return false

func _glyphs_lane() -> bool:
	var ok: bool = true
	var manifest: Dictionary = _manifest()
	if manifest.is_empty():
		push_error("GLYPHS: manifest.json did not parse -- nothing can be judged")
		return false
	var glyphs: Array[String] = _all_glyphs(manifest)
	if glyphs.size() != 32:
		push_error("GLYPHS: manifest names %d glyphs, expected 32 -- the coverage check judged the wrong count" % glyphs.size())
		ok = false

	# Membership: every glyph in exactly one list, true positive and both true negatives.
	for f in _glyph_membership_faults(glyphs, READERS, PENDING_GLYPHS, UNUSED_GLYPHS):
		push_error("GLYPHS: " + f)
		ok = false
	for name_v in [READERS.keys(), PENDING_GLYPHS.keys(), UNUSED_GLYPHS.keys()]:
		for g_v in name_v:
			if not glyphs.has(String(g_v)):
				push_error("GLYPHS: %s is listed but the manifest ships no such glyph" % String(g_v))
				ok = false
	if _glyph_membership_faults(["glyph_zznonesuch"], READERS, PENDING_GLYPHS, UNUSED_GLYPHS).is_empty():
		push_error("GLYPHS: a glyph in none of the three lists passed -- the comparator cannot say no")
		ok = false
	var doubled: Dictionary = {"glyph_zzboth": {"file": "x", "slice": "y"}}
	if _glyph_membership_faults(["glyph_zzboth"], doubled, {"glyph_zzboth": "z"}, {}).is_empty():
		push_error("GLYPHS: a glyph in two of the three lists passed -- the comparator cannot say no")
		ok = false
	if not _glyph_membership_faults(["glyph_zzone"], {"glyph_zzone": {}}, {}, {}).is_empty():
		push_error("GLYPHS: a glyph in exactly one list was refused -- the comparator cannot say yes")
		ok = false

	# EQUIP: the twelve equipment glyphs, mapped from LEFT_SLOTS+RIGHT_SLOTS rather than a
	# literal, so verified differently -- read the consts, not assumed, per CLAUDE.md's dead-socket
	# rule ("is this findable" rather than "should be findable").
	var inv_script: GDScript = load(INVENTORY_GD) as GDScript
	var left: Array = inv_script.get("LEFT_SLOTS") as Array if inv_script != null and inv_script.get("LEFT_SLOTS") is Array else []
	var right: Array = inv_script.get("RIGHT_SLOTS") as Array if inv_script != null and inv_script.get("RIGHT_SLOTS") is Array else []
	var slots: Array[String] = []
	for s in left:
		slots.append(String(s))
	for s in right:
		slots.append(String(s))
	for f in _equip_count_faults(slots):
		push_error("GLYPHS: EQUIP: " + f)
		ok = false
	for f in _equip_coverage_faults(slots, READERS):
		push_error("GLYPHS: EQUIP: " + f)
		ok = false
	var inv_bodies: Dictionary = _bodies(_text_of(INVENTORY_GD))
	if not _reaches_needle(inv_bodies, "_draw_body", "Chrome.glyph("):
		push_error("GLYPHS: EQUIP: _draw_body does not reach Chrome.glyph( for the equipment slots")
		ok = false
	# True negatives: a wrong count fails on its own, a slot name with no matching glyph id fails
	# coverage on its own, a real slot with a real entry passes coverage, and a body that never
	# reaches the call fails the dead-socket check.
	if _equip_count_faults(["head"]).is_empty():
		push_error("GLYPHS: EQUIP: a one-slot array passed the count check")
		ok = false
	if not _equip_count_faults(slots).is_empty():
		push_error("GLYPHS: EQUIP: the real twelve slots failed the count check -- it cannot say yes")
		ok = false
	if _equip_coverage_faults(["nonesuch_slot"], READERS).is_empty():
		push_error("GLYPHS: EQUIP: a slot with no matching glyph id passed coverage")
		ok = false
	if not _equip_coverage_faults(["head"], READERS).is_empty():
		push_error("GLYPHS: EQUIP: a slot with a real READERS entry was refused coverage -- the comparator cannot say yes")
		ok = false
	if _reaches_needle({"_draw_body": "pass\n"}, "_draw_body", "Chrome.glyph("):
		push_error("GLYPHS: EQUIP: a fabricated _draw_body with no Chrome.glyph( call passed")
		ok = false
	if not _reaches_needle({"_draw_body": "Chrome.glyph(self, slot, at, false, alpha)\n"}, "_draw_body", "Chrome.glyph("):
		push_error("GLYPHS: EQUIP: a fabricated _draw_body that does call Chrome.glyph( was refused -- the scanner cannot say yes")
		ok = false

	# READERS (the four not covered by EQUIP): the file names the glyph's short name inside a
	# Chrome.glyph(/Chrome.header( call, comments stripped.
	var file_cache: Dictionary = {}
	var equip_ids: Array[String] = []
	for slot in slots:
		equip_ids.append("glyph_" + slot)
	var read_count: int = 0
	for g_v in READERS.keys():
		var g: String = String(g_v)
		if equip_ids.has(g):
			continue
		var spec: Dictionary = READERS[g] as Dictionary
		var file: String = String(spec.get("file", ""))
		if String(spec.get("slice", "")).is_empty():
			push_error("GLYPHS: READERS[%s] names no slice" % g)
			ok = false
		if not file_cache.has(file):
			file_cache[file] = _code_of(_text_of(file))
		var code: String = String(file_cache[file])
		var short: String = g.trim_prefix("glyph_")
		if spec.has("table"):
			if _table_reads_glyph(file, String(spec["table"]), short) and code.contains("Chrome.glyph("):
				read_count += 1
			else:
				push_error("GLYPHS: %s -- %s's %s does not carry \"%s\" into a Chrome.glyph( call" % [g, file, String(spec["table"]), short])
				ok = false
		elif _calls_with_glyph(code, "Chrome.header", short) or _calls_with_glyph(code, "Chrome.glyph", short):
			read_count += 1
		else:
			push_error("GLYPHS: %s -- %s has no Chrome.header(/Chrome.glyph( call naming \"%s\"" % [g, file, short])
			ok = false
	# True negatives: the literal only in a comment, a call for a different glyph, and the true
	# positive that a call carrying a nested Vector2(...) is still read whole.
	var commented: String = _code_of("func _draw() -> void:\n\t# Chrome.glyph(self, \"zzghost\", at, true, alpha)\n\tpass\n")
	if _calls_with_glyph(commented, "Chrome.glyph", "zzghost"):
		push_error("GLYPHS: a Chrome.glyph( call only in a comment counted as a reader")
		ok = false
	var other: String = _code_of("func _draw() -> void:\n\tChrome.glyph(self, \"zzother\", at, true, alpha)\n")
	if _calls_with_glyph(other, "Chrome.glyph", "zzghost"):
		push_error("GLYPHS: a call naming a different glyph satisfied the check for zzghost")
		ok = false
	var live: String = _code_of("func _draw() -> void:\n\tChrome.glyph(self, \"zzghost\", Vector2(1.0, 2.0), true, alpha) # ok\n")
	if not _calls_with_glyph(live, "Chrome.glyph", "zzghost"):
		push_error("GLYPHS: a live call with a nested Vector2(...) argument was not found -- the scanner cannot say yes")
		ok = false
	# The false positive this position-aware scan exists to refuse: a header's *label*, not its
	# glyph_name, spelling the same word -- settings_panel.gd's real "settings" title is exactly
	# this shape (Chrome.header(self, p, "settings", 0.97), four arguments, no glyph_name at all).
	var label_only: String = _code_of("func _draw() -> void:\n\tChrome.header(self, p, \"zzghost\", 0.97)\n")
	if _calls_with_glyph(label_only, "Chrome.header", "zzghost"):
		push_error("GLYPHS: a header whose *label* spells a glyph's short name, with no glyph_name argument, counted as a reader")
		ok = false

	# The table path, both ways: a glyph the named table does not carry, and a table that is not
	# there, are each refused; the real "use" in ItemMenu.GLYPHS is found.
	if _table_reads_glyph(ITEM_MENU_GD, "GLYPHS", "zzghost"):
		push_error("GLYPHS: a glyph ItemMenu.GLYPHS does not carry was found in it")
		ok = false
	if _table_reads_glyph(ITEM_MENU_GD, "ZZ_NO_TABLE", "use"):
		push_error("GLYPHS: a table that does not exist carried a glyph")
		ok = false
	if not _table_reads_glyph(ITEM_MENU_GD, "GLYPHS", "use"):
		push_error("GLYPHS: ItemMenu.GLYPHS' real \"use\" was not found -- the table check cannot say yes")
		ok = false

	# PENDING_GLYPHS: named, awaits its slice, and prints a SKIP; a pending glyph that already has
	# a caller anywhere is a failure -- HELPERS's rule applied to glyphs.
	var sources: Dictionary = _glyph_sources()
	for f in _pending_glyph_faults(PENDING_GLYPHS, sources):
		push_error("GLYPHS: " + f)
		ok = false
	var fake_sources: Dictionary = {"res://ui/zz.gd": _code_of("func _draw() -> void:\n\tChrome.glyph(self, \"use\", at, true, alpha)\n")}
	if _pending_glyph_faults({"glyph_use": "S5"}, fake_sources).is_empty():
		push_error("GLYPHS: a pending glyph with a live caller passed -- the dead-socket check cannot say no")
		ok = false
	for g_v in PENDING_GLYPHS.keys():
		print("SKIP GLYPHS: %s awaits %s" % [String(g_v).trim_prefix("glyph_"), String(PENDING_GLYPHS[g_v])])

	# RESOLVE: every consumed glyph resolves headless at both sizes; a name the kit does not ship
	# does not.
	Kit.forget()
	for g_v in READERS.keys():
		var g: String = String(g_v)
		var big: Texture2D = Kit.glyph(g)
		var small: Texture2D = Kit.glyph(g, true)
		if big == null or small == null:
			push_error("GLYPHS: %s does not resolve headless at both sizes (big %s, small %s)" % [g, str(big != null), str(small != null)])
			ok = false
	if Kit.glyph("glyph_zznonesuch") != null or Kit.glyph("glyph_zznonesuch", true) != null:
		push_error("GLYPHS: a glyph id the kit does not ship resolved")
		ok = false

	if ok:
		print(
			"GLYPHS OK %d/%d manifest glyphs consumed with a named reader (%d equipment, mapped from LEFT_SLOTS+RIGHT_SLOTS; %d by a literal in Chrome.glyph/header, both sizes headless), %d pending their slice, %d left unused with a reason; a glyph in none, both and two of the three lists, a commented call, a call for a different glyph, and a pending glyph with a live caller each refused"
			% [READERS.size(), glyphs.size(), equip_ids.size(), read_count, PENDING_GLYPHS.size(), UNUSED_GLYPHS.size()]
		)
	return ok


# What is wrong with `pending` against `sources`: a glyph still marked pending that some file
# already reads. The reverse of HELPERS's rule -- a PENDING name must stay a dead socket until the
# commit that takes it off this list.
func _pending_glyph_faults(pending: Dictionary, sources: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	for g_v in pending.keys():
		var g: String = String(g_v)
		var short: String = g.trim_prefix("glyph_")
		for src_v in sources.values():
			var code: String = String(src_v)
			if _calls_with_glyph(code, "Chrome.glyph", short) or _calls_with_glyph(code, "Chrome.header", short):
				faults.append("%s is PENDING (%s) but already has a caller -- take it out of PENDING_GLYPHS in the same commit" % [g, String(pending[g])])
				break
	return faults


# Whether `fn`'s body in `bodies` contains `needle`, or calls another function in `bodies` that
# does, one link deep -- `_reaches_kit`'s pattern generalised to any needle.
func _reaches_needle(bodies: Dictionary, fn: String, needle: String) -> bool:
	var body: String = String(bodies.get(fn, ""))
	if body.contains(needle):
		return true
	for other_v in bodies.keys():
		var other: String = String(other_v)
		if other == fn:
			continue
		var callee: String = String(bodies[other])
		if _calls(body, other) and callee.contains(needle):
			return true
	return false


# --- 7. KEYCAPS --------------------------------------------------------------------------------


# Keys wear keycaps (docs/23's what's left, "The UI Field Kit, live"): the action bar draws every
# key it names as the kit's keycap, and the word menu wears a gutter of small glyphs.
#
#   CAPS      `Hud.keycaps(action, tail)` -- the one list `_draw_action_bar` lays out -- is judged
#             for the idle bar and for a real `Hud.action_line` with E, T and H all live, the tail
#             read out of the bar's own single `var keys: String` line: every cap is a key
#             `presentation/input_map.gd` binds (BINDINGS' legend column, and INTERACT_KEY) and a
#             key `ui/legend.gd` names, so F1 can look it up; no cap carries a digit unless it is a
#             function key's name or listed in KEYCAPS_DIGIT_KEYS (none: the belt's number keys are
#             the quick strip's own labels, never the bar's); no token is words without a key; and
#             the parse loses nothing -- the tail rebuilt from the list is the line. A fabricated
#             "3 boards" and a fabricated "Q quit" each fail the same predicate, and "- = speed" is
#             shown to parse as two keys.
#   FIT       `Hud.fit_bar` lays out the whole list in a 1920 window's room, and on a 1280 window
#             with a long E clause a prefix of it inside the room, E and F1 kept -- the hint gives
#             way from its end, the clauses never.
#   DRAWN     `_draw_action_bar`, comments stripped, lays out `fit_bar(` over
#             `keycaps(_action, keys)` and reaches `Chrome.keycap(`; a fabricated body with the
#             cap only in a comment, and one that draws caps from a list of its own, are each
#             refused by the same scanner.
#   GUTTER    `ItemMenu.size_of` carries the glyph gutter, so `verb_rects` -- which check_context
#             holds to the drawn rows -- is wider by exactly `gutter_of` when a glyph verb joins
#             the menu and not at all when none does; every verb prefix the gutter names finds a
#             glyph that resolves, "attack" and "unequip" find none; `draw_menu` reaches
#             `Chrome.glyph(` through `glyph_of(`, and `size_of` reaches `gutter_of(`.

const KEYCAPS_HUD_GD: String = "res://ui/hud.gd"
const KEYCAPS_MENU_GD: String = "res://ui/item_menu.gd"
const KEYCAPS_INPUT_GD: String = "res://presentation/input_map.gd"
const KEYCAPS_LEGEND_GD: String = "res://ui/legend.gd"
# Digit-row keys the bar may draw as a cap. None today, deliberately: a lone digit on the bar
# reads as a count, and the belt's number keys are labelled by the quick strip itself.
const KEYCAPS_DIGIT_KEYS: Array[String] = []


func _keycaps_lane() -> bool:
	var ok: bool = true
	var hud: GDScript = load(KEYCAPS_HUD_GD) as GDScript
	var menu: GDScript = load(KEYCAPS_MENU_GD) as GDScript
	if hud == null or menu == null:
		push_error("KEYCAPS: ui/hud.gd or ui/item_menu.gd did not load -- nothing to judge")
		return false
	var bound: Dictionary = _keycaps_bound()
	var legended: Dictionary = _keycaps_legended()
	if bound.size() < 10 or legended.size() < 10:
		push_error("KEYCAPS: read %d bound keys and %d legend keys -- too few to judge anything" % [bound.size(), legended.size()])
		return false

	# CAPS. The tail is the bar's own line, read out of the function that draws it.
	var bodies: Dictionary = _bodies(_text_of(KEYCAPS_HUD_GD))
	var tail: String = _keycaps_tail(String(bodies.get("_draw_action_bar", "")))
	if tail.is_empty():
		push_error("KEYCAPS: `_draw_action_bar` has no single-line `var keys: String` to read the tail from")
		return false
	var action: String = _keycaps_action()
	for lead in ["E — ", "T — ", "H — "]:
		if not action.contains(lead):
			push_error("KEYCAPS: the fixture's action line never offered %s-- the lead caps have nothing to judge: '%s'" % [lead, action])
			ok = false
	var idle: Array = hud.call("keycaps", "", tail) as Array
	var busy: Array = hud.call("keycaps", action, tail) as Array
	var caps: int = 0
	for pair in [["idle", idle], ["with E, T and H live", busy]]:
		var faults: Array[String] = _keycaps_faults(pair[1] as Array, bound, legended)
		if not faults.is_empty():
			push_error("KEYCAPS: the bar %s draws caps that are not bound keys: %s" % [String(pair[0]), "; ".join(faults)])
			ok = false
	var leads: Array[String] = []
	for e_v in busy:
		var e: Dictionary = e_v as Dictionary
		caps += (e.get("keys", []) as Array).size()
		if bool(e.get("lead", false)):
			leads.append(" ".join(e.get("keys", []) as Array))
	if leads != ["E", "T", "H"]:
		push_error("KEYCAPS: the lead caps are %s, not E, T, H in order" % str(leads))
		ok = false
	var rebuilt: Array[String] = []
	for e_v in idle:
		var e: Dictionary = e_v as Dictionary
		if bool(e.get("lead", false)):
			push_error("KEYCAPS: the idle bar drew a lead cap with no action line")
			ok = false
		var words: Array = (e.get("keys", []) as Array).duplicate()
		words.append(String(e.get("word", "")))
		rebuilt.append(" ".join(words))
	if " · ".join(rebuilt) != tail:
		push_error("KEYCAPS: the tail rebuilt from the caps is '%s', not the line '%s' -- the parse drops something" % [" · ".join(rebuilt), tail])
		ok = false
	var speed: Array = hud.call("keycaps", "", "- = speed") as Array
	if speed.size() != 1 or (speed[0] as Dictionary).get("keys", []) != ["-", "="] or String((speed[0] as Dictionary).get("word", "")) != "speed":
		push_error("KEYCAPS: '- = speed' did not parse as two keys and a word: %s" % str(speed))
		ok = false
	# FIT: what the bar lays out is the list, whole where there is room, and on a 1280 window with a
	# long clause the list with the hint's tail left off -- a prefix, E and F1 kept, inside the room.
	var font: Font = (load(CHROME_GD) as GDScript).call("font") as Font
	var wide: Dictionary = hud.call("fit_bar", font, idle, 1920.0 - 96.0) as Dictionary
	var all_idle: Array[String] = _keycaps_listed(idle)
	if _keycaps_drawn(wide["runs"] as Array) != all_idle:
		push_error("KEYCAPS: with a 1920 window's room the idle bar lays out %s, not its whole list %s" % [str(_keycaps_drawn(wide["runs"] as Array)), str(all_idle)])
		ok = false
	var long_list: Array = hud.call("keycaps", "E — There's a cupboard here worth going through.", tail) as Array
	var narrow: Dictionary = hud.call("fit_bar", font, long_list, 1280.0 - 96.0) as Dictionary
	var drawn: Array[String] = _keycaps_drawn(narrow["runs"] as Array)
	var listed: Array[String] = _keycaps_listed(long_list)
	if float(narrow["total"]) > 1280.0 - 96.0 or drawn.size() >= listed.size() or listed.slice(0, drawn.size()) != drawn or not drawn.has("E") or not drawn.has("F1"):
		push_error("KEYCAPS: a 1280 window with a long clause lays out %s (%.0f px of %.0f) -- not a prefix of %s keeping E and F1 inside the room" % [str(drawn), float(narrow["total"]), 1280.0 - 96.0, str(listed)])
		ok = false
	# True negatives, through the same parse and the same predicate.
	var counted: Array[String] = _keycaps_faults(hud.call("keycaps", "", "3 boards") as Array, bound, legended)
	if counted.is_empty() or not "; ".join(counted).contains("digit"):
		push_error("KEYCAPS: a fabricated '3 boards' cap was not refused for its digit: %s" % str(counted))
		ok = false
	if _keycaps_faults(hud.call("keycaps", "", "Q quit") as Array, bound, legended).is_empty():
		push_error("KEYCAPS: a fabricated 'Q quit' cap, a key nothing binds, passed")
		ok = false
	if _keycaps_faults(hud.call("keycaps", "Q — quit", "") as Array, bound, legended).is_empty():
		push_error("KEYCAPS: a fabricated lead clause on an unbound key passed")
		ok = false
	if _keycaps_faults(hud.call("keycaps", "", "keys") as Array, bound, legended).is_empty():
		push_error("KEYCAPS: a fabricated token with words and no key passed")
		ok = false

	# DRAWN.
	if not _keycaps_draws(bodies):
		push_error("KEYCAPS: `_draw_action_bar` does not lay out fit_bar( over keycaps(_action, keys) and reach Chrome.keycap( -- the list judged above is not what the bar draws")
		ok = false
	var commented: Dictionary = _bodies("func _draw_action_bar(font, view):\n\tvar fit = fit_bar(font, keycaps(_action, keys), room)\n\t# w = Chrome.keycap(self, at, k, 25, 1.0)\n\tdraw_string(font, at, k)\n")
	if _keycaps_draws(commented):
		push_error("KEYCAPS: a fabricated bar that draws a keycap only in a comment passed")
		ok = false
	var own_list: Dictionary = _bodies("func _draw_action_bar(font, view):\n\tfor k in [\"E\", \"Tab\"]:\n\t\tChrome.keycap(self, at, k, 25, 1.0)\n")
	if _keycaps_draws(own_list):
		push_error("KEYCAPS: a fabricated bar drawing caps from a list of its own passed")
		ok = false
	var live: Dictionary = _bodies("func _draw_action_bar(font, view):\n\tvar fit = fit_bar(font, keycaps(_action, keys), room) # the list\n\tx += Chrome.keycap(self, at, k, 25, 1.0)\n")
	if not _keycaps_draws(live):
		push_error("KEYCAPS: a fabricated bar that does draw its caps was refused -- the scanner cannot pass")
		ok = false

	# GUTTER.
	var gutter_ok: bool = _keycaps_gutter(menu)
	ok = gutter_ok and ok
	if ok:
		print("KEYCAPS OK %d caps with E, T and H live and %d idle, each a bound key the legend names, digit-free but a function key's name; the tail rebuilds from its caps; '3 boards', 'Q quit', an unbound lead and a keyless token refused; all %d idle caps fit a 1920 window and %d of %d a 1280 one with a long clause, E and F1 kept; the bar draws fit_bar(keycaps(_action, keys)) through Chrome.keycap, and a commented call and a list of its own are refused; the word menu's glyph gutter is in size_of and so in verb_rects" % [caps, all_idle.size(), all_idle.size(), drawn.size(), listed.size()])
	return ok


# Every key name input_map.gd binds, as the legend column spells it (a "Ctrl+Z / Ctrl+C" cell
# split into its keys), plus INTERACT_KEY, which is a constant rather than a BINDINGS row.
func _keycaps_bound() -> Dictionary:
	var out: Dictionary = {}
	var script: GDScript = load(KEYCAPS_INPUT_GD) as GDScript
	if script == null:
		return out
	var consts: Dictionary = script.get_script_constant_map()
	for row_v in (consts.get("BINDINGS", {}) as Dictionary).values():
		for cell in (row_v as Dictionary).get("legend", []) as Array:
			for key in String(cell).split(" / ", false):
				out[String(key).strip_edges()] = true
	if consts.has("INTERACT_KEY"):
		out[OS.get_keycode_string(int(consts["INTERACT_KEY"]))] = true
	return out


# Every key name the F1 legend shows, split the same way.
func _keycaps_legended() -> Dictionary:
	var out: Dictionary = {}
	var script: GDScript = load(KEYCAPS_LEGEND_GD) as GDScript
	if script == null:
		return out
	for group_v in script.get_script_constant_map().get("GROUPS", []) as Array:
		for row_v in (group_v as Array)[1] as Array:
			for key in String((row_v as Array)[0]).split(" / ", false):
				out[String(key).strip_edges()] = true
	return out


# The literal of the one `var keys: String = "..."` line in a comment-stripped function body.
func _keycaps_tail(body: String) -> String:
	for raw in body.split("\n"):
		var line: String = String(raw).strip_edges()
		if line.begins_with("var keys: String = \"") and line.ends_with("\""):
			return line.substr(line.find("\"") + 1, line.length() - line.find("\"") - 2)
	return ""


# A real action line with all three keys live: a boarded window in reach (E), a bleeding torso
# (T), and Mara held beside the player (H) -- check_hud's ACTION fixture, rebuilt here so the
# lead caps judged are ones `Hud.action_line` actually offers.
func _keycaps_action() -> String:
	var world_script: GDScript = load("res://sim/world.gd") as GDScript
	var health: GDScript = load("res://sim/modules/health.gd") as GDScript
	var wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	var hud: GDScript = load(KEYCAPS_HUD_GD) as GDScript
	var w: Variant = world_script.new({"seed": 31, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 8.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}})
	health.call("make_survivor_body", w, w.player)
	wounds.call("append_wound", w, w.player, "laceration", "torso", -1, 30.0)
	var mara: int = int(w.entities.spawn())
	w.components.set_component(mara, "identity", {"id": "survivor.test.mara", "name": "Mara Sato"})
	w.components.set_component(mara, "position", {"x": 8.5, "y": 8.0})
	health.call("make_survivor_body", w, mara)
	w.components.set_component(mara, "grabbed", {"by": 4242, "sinceTick": 0})
	return String(hud.call("action_line", w, w.player, {"window": "boarded, holding"}, ""))


# What is wrong with a list of bar entries. Empty when every cap is a bound, legended key name.
func _keycaps_faults(entries: Array, bound: Dictionary, legended: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	var fkey := RegEx.new()
	fkey.compile("^F[0-9]+$")
	for e_v in entries:
		var e: Dictionary = e_v as Dictionary
		var keys: Array = e.get("keys", []) as Array
		if keys.is_empty():
			faults.append("'%s' is drawn with no key" % String(e.get("word", "")))
		for k_v in keys:
			var k: String = String(k_v)
			var has_digit: bool = false
			for ch in k:
				if ch >= "0" and ch <= "9":
					has_digit = true
			if has_digit and fkey.search(k) == null and not KEYCAPS_DIGIT_KEYS.has(k):
				faults.append("'%s' puts a digit on a cap that is not a key's name" % k)
			if not bound.has(k):
				faults.append("'%s' is not a key input_map.gd binds" % k)
			if not legended.has(k):
				faults.append("'%s' is not a key the F1 legend names" % k)
	return faults


# Every key a `keycaps` list names, in order; and every cap a `fit_bar` row of runs lays out.
func _keycaps_listed(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for e_v in entries:
		for k in (e_v as Dictionary).get("keys", []) as Array:
			out.append(String(k))
	return out


func _keycaps_drawn(runs: Array) -> Array[String]:
	var out: Array[String] = []
	for r_v in runs:
		if String((r_v as Array)[0]) == "cap":
			out.append(String((r_v as Array)[1]))
	return out


# Does the bar draw the list: `keycaps(_action, keys)` and `fit_bar(` called as bare names, and
# `Chrome.keycap(`, all in `_draw_action_bar`'s own comment-stripped body.
func _keycaps_draws(bodies: Dictionary) -> bool:
	var body: String = String(bodies.get("_draw_action_bar", ""))
	var re := RegEx.new()
	re.compile("(^|[^A-Za-z0-9_.])keycaps\\(\\s*_action\\s*,\\s*keys\\s*\\)")
	return re.search(body) != null and _calls(body, "fit_bar") and body.contains("Chrome.keycap(")


# The word menu's gutter, both ways, and its readers.
func _keycaps_gutter(menu: GDScript) -> bool:
	var ok: bool = true
	var long: String = "a fabricated verb long enough to set the menu's width on its own"
	var plain: Vector2 = menu.call("size_of", [long]) as Vector2
	var marked: Vector2 = menu.call("size_of", [long, "use"]) as Vector2
	var gutter: float = float(menu.call("gutter_of", [long, "use"]))
	var small: Texture2D = Kit.glyph("use", true)
	if small == null or gutter < float(small.get_width()) or absf(marked.x - plain.x - gutter) > 0.01:
		push_error("KEYCAPS: a glyph verb widened the menu by %.1f, not its %.1f gutter (at least a small glyph wide)" % [marked.x - plain.x, gutter])
		ok = false
	if float(menu.call("gutter_of", [long, "attack"])) != 0.0:
		push_error("KEYCAPS: a menu with no glyph verb carries a gutter")
		ok = false
	for pair in [[[long], plain.x], [[long, "use"], marked.x]]:
		for row_v in menu.call("verb_rects", Vector2.ZERO, pair[0]) as Array:
			var w: float = ((row_v as Dictionary)["rect"] as Rect2).size.x
			if absf(w - float(pair[1])) > 0.01:
				push_error("KEYCAPS: a click rect is %.1f wide where the menu is %.1f -- verb_rects left the gutter out" % [w, float(pair[1])])
				ok = false
	for pair in [["use", "use"], ["drop", "drop"], ["inspect", "inspect"], ["look at Mara Sato", "inspect"], ["open the crate", "search"], ["search", "search"], ["walk here", "move"], ["move", "move"]]:
		var got: String = String(menu.call("glyph_of", String(pair[0])))
		if got != String(pair[1]) or Kit.glyph(got, true) == null:
			push_error("KEYCAPS: '%s' wears glyph '%s', not a resolving '%s'" % [String(pair[0]), got, String(pair[1])])
			ok = false
	for verb in ["attack", "unequip", "equip", "shout"]:
		if not String(menu.call("glyph_of", verb)).is_empty():
			push_error("KEYCAPS: '%s' wears a glyph the gutter does not name for it" % verb)
			ok = false
	var bodies: Dictionary = _bodies(_text_of(KEYCAPS_MENU_GD))
	var draw: String = String(bodies.get("draw_menu", ""))
	if not (draw.contains("Chrome.glyph(") and _calls(draw, "glyph_of") and _calls(draw, "gutter_of")):
		push_error("KEYCAPS: draw_menu does not draw glyph_of's glyph through Chrome.glyph( at gutter_of's offset")
		ok = false
	if not _calls(String(bodies.get("size_of", "")), "gutter_of"):
		push_error("KEYCAPS: size_of leaves gutter_of out, so verb_rects and draw_menu can disagree")
		ok = false
	return ok


# --- 8. OUTLIERS -------------------------------------------------------------------------------


# The two screens the kit's panel/cell/item_plate/header trio doesn't reach, S6 "Bubbles and the
# dashboard in kit frames": a speech bubble's plate (main.gd) and a vehicle's dashboard housing
# (dashboard.gd, all three layouts) each frame themselves through `Chrome.frame(` rather than
# drawing their own rect and rim. True positives: `_draw_bubbles` reaches `Chrome.frame(` naming
# `"panel_tooltip"`; `_draw_cluster`, `_draw_handlebar` and `_draw_board` each reach
# `Chrome.frame(`; and a representative one-line bubble, sized the same way `_draw_bubbles` sizes
# one (through main.gd's own `_bubble_plate`, exposed so this lane never boots a scene), is at
# least as large as the tooltip style's own margins -- proof the frame really draws instead of
# falling back. True negatives, through the same comment-stripped `_bodies` scanner PANEL already
# uses: a call present only in a comment, a body that only calls `draw_rect`, and a plate shrunk
# under the margins.

const DASHBOARD_GD: String = "res://ui/dashboard.gd"


func _outliers_lane() -> bool:
	var ok: bool = true
	var main_bodies: Dictionary = _bodies(_text_of(MAIN_GD))
	var dash_bodies: Dictionary = _bodies(_text_of(DASHBOARD_GD))

	var bubble: String = String(main_bodies.get("_draw_bubbles", ""))
	if bubble.is_empty():
		push_error("OUTLIERS: %s has no `func _draw_bubbles(`" % MAIN_GD)
		ok = false
	elif not (bubble.contains("Chrome.frame(") and bubble.contains("panel_tooltip")):
		push_error("OUTLIERS: _draw_bubbles does not reach Chrome.frame( naming \"panel_tooltip\"")
		ok = false

	for fn in ["_draw_cluster", "_draw_handlebar", "_draw_board"]:
		var body: String = String(dash_bodies.get(fn, ""))
		if body.is_empty():
			push_error("OUTLIERS: %s has no `func %s(`" % [DASHBOARD_GD, fn])
			ok = false
		elif not body.contains("Chrome.frame("):
			push_error("OUTLIERS: dashboard.gd's %s does not reach Chrome.frame(" % fn)
			ok = false

	# The bubble plate really draws the frame: a representative one-line bubble, sized main.gd's
	# own way, clears panel_tooltip's own margins.
	var m: Array[int] = Kit.margins("panel_tooltip")
	var main_script: GDScript = load(MAIN_GD) as GDScript
	if main_script == null:
		push_error("OUTLIERS: %s did not load" % MAIN_GD)
		ok = false
	elif not main_bodies.has("_bubble_plate"):
		push_error("OUTLIERS: %s has no static `_bubble_plate` to size a representative bubble with" % MAIN_GD)
		ok = false
	else:
		var tag_size: int = int(main_script.get("TAG_SIZE"))
		var chrome: GDScript = load(CHROME_GD) as GDScript
		var font: Font = chrome.call("font") as Font
		var line_h: float = float(tag_size) * 1.2
		var block_w: float = font.get_string_size("hello there", HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
		var plate: Rect2 = main_script.call("_bubble_plate", 400.0, 400.0, 20.0, block_w, 1, line_h)
		if plate.size.x < float(m[0] + m[2]) or plate.size.y < float(m[1] + m[3]):
			push_error("OUTLIERS: a representative one-line bubble plate %s is smaller than panel_tooltip's margins %s -- Chrome.frame would fall back" % [str(plate.size), str(m)])
			ok = false

	# True negatives: a call present only in a comment, and a body that only draws rectangles.
	var commented: Dictionary = _bodies("func _draw_bubbles() -> void:\n\t# Chrome.frame(self, plate, \"panel_tooltip\", a)\n\tdraw_rect(plate, fill)\n")
	var commented_body: String = String(commented.get("_draw_bubbles", ""))
	if commented_body.contains("Chrome.frame(") and commented_body.contains("panel_tooltip"):
		push_error("OUTLIERS: a fabricated _draw_bubbles that reaches the kit only in a comment passed")
		ok = false
	var rects_only: Dictionary = _bodies("func _draw_cluster() -> void:\n\tdraw_rect(panel, PANEL)\n\tdraw_rect(panel, RIM, false, 2.0)\n")
	if String(rects_only.get("_draw_cluster", "")).contains("Chrome.frame("):
		push_error("OUTLIERS: a fabricated _draw_cluster that only calls draw_rect passed")
		ok = false
	# A plate shrunk under the margins is caught -- the comparator that passed the shipped one.
	var shrunk: Rect2 = Rect2(Vector2.ZERO, Vector2(float(m[0] + m[2]) - 1.0, float(m[1] + m[3]) - 1.0))
	if shrunk.size.x >= float(m[0] + m[2]) and shrunk.size.y >= float(m[1] + m[3]):
		push_error("OUTLIERS: a plate one pixel under the margins was not judged smaller -- the comparator cannot say no")
		ok = false

	if ok:
		print("OUTLIERS OK _draw_bubbles and all three dashboard layouts reach Chrome.frame(; a representative one-line bubble clears panel_tooltip's margins; a commented call, a rect-only body and a shrunk plate each refused")
	return ok


# --- 9. CURSORS --------------------------------------------------------------------------------


# The four cursors (docs/23's what's left, "The UI Field Kit, live"): `ui/cursors.gd` installs the
# kit's arrow, hand, move and blocked at the manifest's own hotspots, the screens say which shape
# they want where through a pure `cursor_at`, and a drag the sim would refuse wears blocked with
# the kit's `slot_invalid` over the cells. The OS pointer itself is never judged -- the headless
# display server has none -- so the lane judges the table, who reaches it, and what each screen
# asks for.
#
#   TABLE     every UiCursors.TABLE record's id, native size and native hotspot equal manifest.json's
#             record for that id; arrow, hand, move and blocked are all named; every `control_cursor_*`
#             the kit ships is worn by some shape. A fabricated record with the arrow's hotspot one
#             pixel off, and a manifest carrying a fifth pointer nobody wears, each fail the
#             comparator that passed the shipped table.
#   SCALE     UiCursors.SCALE is the chrome's Kit.SCALE; every pointer resolves through Kit.texture at
#             the manifest's size times that scale, its installed hotspot is the manifest's times the
#             same and inside the picture; a pointer the kit does not ship resolves to nothing.
#   REACH     `_ensure_ui`, comments stripped, reaches `UiCursors.install(`; `install` reaches
#             `Input.set_custom_mouse_cursor(` through `texture_of(` and dresses every shape in TABLE
#             (headless the call is a no-op; the count is not). Each screen's input path sets
#             `mouse_default_cursor_shape` from its `cursor_at(`, and the ghost reaches the drop
#             frame. The same predicate refuses a body with the install only in a comment.
#   SURFACES  the shell's rows, a context-menu verb, a settings slider and an inventory item each
#             give the hand; the shell's empty panel space, the menu's padding, the settings sheet's
#             corner and the inventory sheet's margin each give the arrow -- and not the hand.
#   DROP      in a small world, a held item over each pocket cell gives blocked exactly where
#             `SimInventory.can_place` refuses and the move exactly where it accepts, both seen, the
#             refusal with the cells it would cover; `_drop_verdict` asks `SimInventory.can_place(`
#             and a fabricated verdict ruling with `SimGrid.fits` alone is refused. Every shape a
#             screen answered with is one TABLE dresses.

const UiCursors = preload("res://ui/cursors.gd")
const CURSORS_GD: String = "res://ui/cursors.gd"
const CURSORS_SHELL_GD: String = "res://ui/shell.gd"
const CURSORS_CONTEXT_GD: String = "res://ui/context_menu.gd"
const CURSORS_SETTINGS_GD: String = "res://ui/settings_panel.gd"
const CursorsWorld = preload("res://sim/world.gd")
const CursorsSimHealth = preload("res://sim/modules/health.gd")
const CursorsSimNeeds = preload("res://sim/modules/needs.gd")
const CursorsSimItems = preload("res://sim/modules/items.gd")
const CursorsSimInventory = preload("res://sim/modules/inventory.gd")
const CursorsBagGrid = preload("res://ui/bag_grid.gd")
# The four pointers the kit ships, by the shape each must answer for.
const CURSORS_REQUIRED: Dictionary = {
	Input.CURSOR_ARROW: "control_cursor_arrow",
	Input.CURSOR_POINTING_HAND: "control_cursor_hand",
	Input.CURSOR_MOVE: "control_cursor_move",
	Input.CURSOR_FORBIDDEN: "control_cursor_blocked",
}


func _cursors_lane() -> bool:
	var ok: bool = true
	var manifest: Dictionary = _manifest()
	var assets: Dictionary = _records(manifest, "assets")
	var answered: Dictionary = {}

	# TABLE: the code's copy against the manifest, at native pixels.
	for shape_v in UiCursors.TABLE.keys():
		for f in _cursor_faults(UiCursors.TABLE[shape_v], assets):
			push_error("CURSORS: shape %d: %s" % [int(shape_v), f])
			ok = false
	for shape_v in CURSORS_REQUIRED.keys():
		var entry: Variant = UiCursors.TABLE.get(shape_v, null)
		if not (entry is Dictionary) or String((entry as Dictionary).get("id", "")) != String(CURSORS_REQUIRED[shape_v]):
			push_error("CURSORS: shape %d does not wear %s" % [int(shape_v), String(CURSORS_REQUIRED[shape_v])])
			ok = false
	for f in _cursor_coverage_faults(manifest.get("assets", []) as Array, UiCursors.TABLE):
		push_error("CURSORS: " + f)
		ok = false
	# True negatives: one pixel off, and a pointer nobody wears.
	var bad: Dictionary = (UiCursors.TABLE[Input.CURSOR_ARROW] as Dictionary).duplicate(true)
	bad["hotspot"] = Vector2i(7, 2)
	if _cursor_faults(bad, assets).is_empty():
		push_error("CURSORS: a table record with the arrow's hotspot at (7, 2) against the manifest's (6, 2) passed -- the comparator cannot fail")
		ok = false
	var ghost: Array = (manifest.get("assets", []) as Array).duplicate(true)
	ghost.append({"id": "control_cursor_crosshair", "category": "controls", "size": [24, 24], "hotspot": [12, 12]})
	if _cursor_coverage_faults(ghost, UiCursors.TABLE).is_empty():
		push_error("CURSORS: a manifest pointer no shape wears passed")
		ok = false

	# SCALE: the chrome's scale, both the picture and the hotspot.
	if UiCursors.SCALE != Kit.SCALE:
		push_error("CURSORS: pointers install at %dx, the chrome draws at %dx" % [UiCursors.SCALE, Kit.SCALE])
		ok = false
	for shape_v in UiCursors.TABLE.keys():
		var shape: int = int(shape_v)
		var entry: Dictionary = UiCursors.TABLE[shape_v] as Dictionary
		var rec: Dictionary = assets.get(String(entry.get("id", "")), {}) as Dictionary
		var want_size: Array[int] = _ints(rec.get("size", null))
		var want_hot: Array[int] = _ints(rec.get("hotspot", null))
		var tex: Texture2D = UiCursors.texture_of(shape)
		if tex == null:
			push_error("CURSORS: %s did not resolve through Kit.texture" % String(entry.get("id", "")))
			ok = false
			continue
		if want_size.size() != 2 or Vector2i(tex.get_size()) != Vector2i(want_size[0], want_size[1]) * UiCursors.SCALE:
			push_error("CURSORS: %s resolved at %s, the manifest says %s at %dx" % [String(entry.get("id", "")), str(tex.get_size()), str(want_size), UiCursors.SCALE])
			ok = false
		var hot: Vector2 = UiCursors.hotspot_of(shape)
		if want_hot.size() != 2 or Vector2i(hot) != Vector2i(want_hot[0], want_hot[1]) * UiCursors.SCALE:
			push_error("CURSORS: %s installs its hotspot at %s, the manifest's %s at %dx is not that" % [String(entry.get("id", "")), str(hot), str(want_hot), UiCursors.SCALE])
			ok = false
		elif not Rect2(Vector2.ZERO, tex.get_size()).has_point(hot):
			push_error("CURSORS: %s's hotspot %s is outside its own picture" % [String(entry.get("id", "")), str(hot)])
			ok = false
	if Kit.texture("controls/control_cursor_nonesuch.png", UiCursors.SCALE) != null:
		push_error("CURSORS: a pointer the kit does not ship resolved")
		ok = false

	# REACH: main.gd installs, install dresses, and every screen's input path asks its cursor_at.
	var ensure: String = String(_bodies(_text_of(MAIN_GD)).get("_ensure_ui", ""))
	if not _cursor_reaches(ensure, ["UiCursors.install("]):
		push_error("CURSORS: main.gd's _ensure_ui, comments stripped, never reaches UiCursors.install(")
		ok = false
	var install: String = String(_bodies(_text_of(CURSORS_GD)).get("install", ""))
	if not _cursor_reaches(install, ["Input.set_custom_mouse_cursor(", "texture_of(", "TABLE"]):
		push_error("CURSORS: UiCursors.install never reaches Input.set_custom_mouse_cursor( with a texture_of( from TABLE")
		ok = false
	var dressed: int = UiCursors.install()
	if dressed != UiCursors.TABLE.size():
		push_error("CURSORS: install dressed %d of %d shapes" % [dressed, UiCursors.TABLE.size()])
		ok = false
	var commented: String = String(_bodies("func _ensure_ui() -> void:\n\t# UiCursors.install()\n\tvar layer := CanvasLayer.new()\n").get("_ensure_ui", ""))
	if _cursor_reaches(commented, ["UiCursors.install("]):
		push_error("CURSORS: a fabricated _ensure_ui with the install only in a comment passed")
		ok = false
	var readers: Array = [
		[CURSORS_SHELL_GD, "_gui_input", ["cursor_at(", "mouse_default_cursor_shape"]],
		[CURSORS_CONTEXT_GD, "_gui_input", ["cursor_at(", "mouse_default_cursor_shape"]],
		[CURSORS_SETTINGS_GD, "_gui_input", ["cursor_at(", "mouse_default_cursor_shape"]],
		[INVENTORY_GD, "_gui_input", ["cursor_at(", "mouse_default_cursor_shape"]],
		[INVENTORY_GD, "_loot_point", ["loot_cursor_at(", "mouse_default_cursor_shape"]],
		[INVENTORY_GD, "_drop_verdict", ["SimInventory.can_place("]],
		[INVENTORY_GD, "_draw_drop_hint_into", ["Chrome.frame(", "\"slot_invalid\"", "CURSOR_FORBIDDEN"]],
	]
	for r_v in readers:
		var r: Array = r_v as Array
		var body: String = String(_bodies(_text_of(String(r[0]))).get(String(r[1]), ""))
		if not _cursor_reaches(body, r[2] as Array):
			push_error("CURSORS: %s's %s, comments stripped, does not reach %s" % [String(r[0]), String(r[1]), str(r[2])])
			ok = false
	# The inner classes are indented, so `_bodies` does not split them out: the whole file, comments
	# stripped, is asked instead -- the window hands its events to `_loot_point` and the ghost draws
	# the refusal.
	var inv_code: String = _code_of(_text_of(INVENTORY_GD))
	for needle in ["panel.call(\"_loot_point\"", "panel.call(\"_draw_drop_hint_into\""]:
		if not inv_code.contains(needle):
			push_error("CURSORS: inventory_panel.gd never calls %s -- the pointer or the frame has no reader" % needle)
			ok = false
	var fits_only: String = String(_bodies("func _drop_verdict(places: Array, p: Vector2) -> Dictionary:\n\t# SimInventory.can_place(_world, item, box, x, y, r)\n\tvar ok: bool = SimGrid.fits(box, items, sizes, candidate)\n").get("_drop_verdict", ""))
	if _cursor_reaches(fits_only, ["SimInventory.can_place("]):
		push_error("CURSORS: a fabricated _drop_verdict ruling with SimGrid.fits, the sim's call only in a comment, passed")
		ok = false

	# SURFACES: the hand where a press acts, the arrow where it does not. At the game's own
	# 1920 x 1080 rather than the headless root's 64 px square, so every screen lays out as it does
	# in play; the root's size is put back after.
	var root_was: Vector2i = root.size
	root.size = Vector2i(1920, 1080)
	var shell: Control = (load(CURSORS_SHELL_GD) as GDScript).new() as Control
	root.add_child(shell)
	shell.call("show_state", 2, {})
	var rows: Array = shell.call("_row_rects") as Array
	var panel_rect: Rect2 = shell.call("_panel_rect") as Rect2
	var empty_panel: Vector2 = panel_rect.position + Vector2(8.0, panel_rect.size.y - 8.0)
	if rows.is_empty():
		push_error("CURSORS: the pause screen laid out no rows -- the shell's hand has nothing to judge")
		ok = false
	else:
		for rect_v in rows:
			var at_row: int = int(shell.call("cursor_at", (rect_v as Rect2).get_center()))
			answered[at_row] = true
			if at_row != Input.CURSOR_POINTING_HAND:
				push_error("CURSORS: the shell over a row gave shape %d, not the hand" % at_row)
				ok = false
		var at_empty: int = int(shell.call("cursor_at", empty_panel))
		answered[at_empty] = true
		if not panel_rect.has_point(empty_panel) or at_empty == Input.CURSOR_POINTING_HAND or at_empty != Input.CURSOR_ARROW:
			push_error("CURSORS: the shell over its own empty panel space gave shape %d, not the arrow" % at_empty)
			ok = false
	shell.free()

	var menu: Control = (load(CURSORS_CONTEXT_GD) as GDScript).new() as Control
	root.add_child(menu)
	var verbs: Array[Dictionary] = [{"text": "walk here"}, {"text": "pick up the tin can"}]
	menu.call("open", Vector2(100, 100), verbs)
	var verb_rects: Array = (load(ITEM_MENU_GD) as GDScript).call("verb_rects", Vector2.ZERO, ["walk here", "pick up the tin can"]) as Array
	var on_verb: int = int(menu.call("cursor_at", ((verb_rects[1] as Dictionary)["rect"] as Rect2).get_center()))
	var in_pad: int = int(menu.call("cursor_at", Vector2(4.0, 3.0)))
	answered[on_verb] = true
	answered[in_pad] = true
	if on_verb != Input.CURSOR_POINTING_HAND:
		push_error("CURSORS: the context menu over a verb gave shape %d, not the hand" % on_verb)
		ok = false
	if in_pad != Input.CURSOR_ARROW:
		push_error("CURSORS: the context menu over its top padding gave shape %d, not the arrow" % in_pad)
		ok = false
	menu.free()

	var settings: Control = (load(CURSORS_SETTINGS_GD) as GDScript).new() as Control
	root.add_child(settings)
	var on_slider: int = int(settings.call("cursor_at", (settings.call("_grab_rect", 0) as Rect2).get_center()))
	var in_corner: int = int(settings.call("cursor_at", (settings.call("_panel_rect") as Rect2).position + Vector2(8.0, 8.0)))
	answered[on_slider] = true
	answered[in_corner] = true
	if on_slider != Input.CURSOR_POINTING_HAND:
		push_error("CURSORS: the settings sheet over a slider gave shape %d, not the hand" % on_slider)
		ok = false
	if in_corner != Input.CURSOR_ARROW:
		push_error("CURSORS: the settings panel's top-left corner gave shape %d, not the arrow" % in_corner)
		ok = false
	settings.free()

	# DROP, and the inventory's hand: a small world, two things in the pockets.
	ok = _cursor_drop_lane(answered) and ok
	root.size = root_was

	for shape_v in answered.keys():
		if not UiCursors.TABLE.has(shape_v):
			push_error("CURSORS: a screen answered with shape %d, which no kit pointer dresses" % int(shape_v))
			ok = false
	if ok:
		print("CURSORS OK %d shapes wear the kit's four pointers at the manifest's sizes and hotspots, installed at the chrome's %dx; _ensure_ui reaches install and install reaches Input.set_custom_mouse_cursor; the shell's rows, a menu verb, a slider and an item give the hand and the space around each the arrow; a held item is blocked exactly where SimInventory.can_place refuses and the move where it accepts; a hotspot one pixel off, a pointer nobody wears, a commented install and a verdict of its own each refused" % [UiCursors.TABLE.size(), UiCursors.SCALE])
	return ok


# What is wrong with one TABLE record against the manifest, at native kit pixels. Empty when they
# agree.
func _cursor_faults(entry_v: Variant, assets: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	if not (entry_v is Dictionary):
		faults.append("the record is not a Dictionary")
		return faults
	var entry: Dictionary = entry_v as Dictionary
	var id: String = String(entry.get("id", ""))
	if not assets.has(id):
		faults.append("%s is not a pointer manifest.json ships" % id)
		return faults
	var rec: Dictionary = assets[id] as Dictionary
	if String(rec.get("category", "")) != "controls":
		faults.append("%s is a %s, not a control" % [id, String(rec.get("category", ""))])
	var size: Array[int] = _ints(rec.get("size", null))
	var hot: Array[int] = _ints(rec.get("hotspot", null))
	if size.size() != 2 or entry.get("size", null) != Vector2i(size[0], size[1]):
		faults.append("%s's size %s against the manifest's %s" % [id, str(entry.get("size", null)), str(size)])
	if hot.size() != 2 or entry.get("hotspot", null) != Vector2i(hot[0], hot[1]):
		faults.append("%s's hotspot %s against the manifest's %s" % [id, str(entry.get("hotspot", null)), str(hot)])
	return faults


# Every `control_cursor_*` the manifest ships must be worn by some shape in `table`.
func _cursor_coverage_faults(assets: Array, table: Dictionary) -> Array[String]:
	var worn: Dictionary = {}
	for entry_v in table.values():
		worn[String((entry_v as Dictionary).get("id", ""))] = true
	var faults: Array[String] = []
	for rec_v in assets:
		var id: String = String((rec_v as Dictionary).get("id", ""))
		if id.begins_with("control_cursor_") and not worn.has(id):
			faults.append("%s is a kit pointer no shape in UiCursors.TABLE wears" % id)
	return faults


# Whether a comment-stripped body carries every needle.
func _cursor_reaches(body: String, needles: Array) -> bool:
	if body.is_empty():
		return false
	for n in needles:
		if not body.contains(String(n)):
			return false
	return true


# The drop verdict against the sim's own `can_place`, cell by cell, and the inventory's hand and
# arrow, in a world with two different things in the pockets.
func _cursor_drop_lane(answered: Dictionary) -> bool:
	var ok: bool = true
	var w: Variant = CursorsWorld.new({
		"seed": 4471,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	})
	CursorsSimHealth.register_module(w)
	CursorsSimNeeds.register_module(w)
	CursorsSimItems.register_module(w)
	CursorsSimInventory.register_module(w)
	CursorsSimHealth.make_survivor_body(w, w.player)
	CursorsSimHealth.make_stamina(w, w.player, 100)
	CursorsSimNeeds.attach(w, w.player)
	CursorsSimInventory.make_inventory(w, w.player)
	var held: int = CursorsSimItems.spawn_item(w, "item.food.jerky", {"tier": "scavenged"})
	var other: int = CursorsSimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	if not CursorsSimInventory.stow(w, w.player, held) or not CursorsSimInventory.stow(w, w.player, other):
		push_error("CURSORS: the two tins would not go in the pockets -- DROP has nothing to judge")
		return false

	var panel: Control = (load(INVENTORY_GD) as GDScript).new() as Control
	root.add_child(panel)
	panel.call("set_world", w, w.player)
	panel.call("set_open", true)
	var pockets: Dictionary = {}
	for placed_v in panel.call("_column_places") as Array:
		var placed: Dictionary = placed_v as Dictionary
		if int((placed["column"] as Dictionary).get("container", -1)) == int(w.player):
			pockets = placed
	if pockets.is_empty():
		push_error("CURSORS: the open sheet laid out no pockets column")
		panel.free()
		return false
	var column: Dictionary = pockets["column"] as Dictionary
	var origin: Vector2 = CursorsBagGrid.origin_of(pockets["at"] as Vector2)
	var cell_px: float = float(CursorsBagGrid.CELL)

	# Nothing held: the hand over an item, the arrow over the sheet's margin.
	var item_view: Dictionary = {}
	for e in column.get("items", []) as Array:
		if int((e as Dictionary).get("item", -1)) == other:
			item_view = e as Dictionary
	var over_item: Vector2 = origin + (Vector2(float(int(item_view.get("x", 0))), float(int(item_view.get("y", 0)))) + Vector2(0.5, 0.5)) * cell_px
	var hand: int = int(panel.call("cursor_at", over_item))
	var margin: int = int(panel.call("cursor_at", Vector2(4.0, 4.0)))
	answered[hand] = true
	answered[margin] = true
	if item_view.is_empty() or hand != Input.CURSOR_POINTING_HAND:
		push_error("CURSORS: the sheet over an item gave shape %d, not the hand" % hand)
		ok = false
	if margin != Input.CURSOR_ARROW:
		push_error("CURSORS: the sheet's own margin gave shape %d, not the arrow" % margin)
		ok = false

	# Held: every pocket cell, the pointer against the sim's own verdict on that cell.
	panel.call("_begin_drag", held, false, Vector2i.ONE)
	var refused: int = 0
	var accepted: int = 0
	for cy in range(int(column.get("h", 0))):
		for cx in range(int(column.get("w", 0))):
			var p: Vector2 = origin + (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * cell_px
			var sim_ok: bool = bool(CursorsSimInventory.can_place(w, held, int(w.player), cx, cy, false).get("ok", false))
			var shape: int = int(panel.call("cursor_at", p))
			var hint: Dictionary = panel.call("drop_hint", p) as Dictionary
			answered[shape] = true
			if sim_ok:
				accepted += 1
				if shape != Input.CURSOR_MOVE:
					push_error("CURSORS: can_place accepts cell (%d, %d) and the pointer is shape %d, not the move" % [cx, cy, shape])
					ok = false
			else:
				refused += 1
				var r: Rect2 = hint.get("rect", Rect2()) as Rect2
				if shape != Input.CURSOR_FORBIDDEN:
					push_error("CURSORS: can_place refuses cell (%d, %d) and the pointer is shape %d, not blocked" % [cx, cy, shape])
					ok = false
				elif not r.has_area() or not r.has_point(p):
					push_error("CURSORS: a refused cell (%d, %d) carries no frame over the cells it would cover (%s)" % [cx, cy, str(r)])
					ok = false
	if refused == 0 or accepted == 0:
		push_error("CURSORS: the pockets gave %d refused and %d accepted cells -- both are needed to judge the verdict" % [refused, accepted])
		ok = false
	panel.call("_cancel_drag")
	panel.free()
	if ok:
		print("CURSORS DROP a held tin over %d pocket cells: blocked on the %d can_place refuses, framed; the move on the %d it accepts" % [refused + accepted, refused, accepted])
	return ok


# --- 10. MOTION --------------------------------------------------------------------------------


func _motion_lane() -> bool:
	print("SKIP MOTION: not landed")
	return true


# --- 11. EVENTS --------------------------------------------------------------------------------


# A coroutine from the start: the lane that replaces this boots main.tscn and waits on frames,
# and `_run` already awaits it, so that slice touches this function and nothing else.
func _events_lane() -> bool:
	await process_frame
	print("SKIP EVENTS: not landed")
	return true

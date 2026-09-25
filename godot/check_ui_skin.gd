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
#             either consumed or listed unused here with its reason. The two places the code
#             departs from the kit's files on purpose are named, not silent: Kit.SCALE is the
#             owner's OWNER_SCALE (with the keycap alone at 1x, named in Kit.NATIVE_STYLES), and
#             every built style fills its edges and centre the way
#             CENTRE_MODE_DEVIATION says rather than the .tres files' stretch. A fabricated record
#             with one wrong margin, a fabricated .tres with one wrong margin, one with an axis
#             mode, one with an expand margin, a chrome id in neither list, a tiled style with no
#             deviation named, and a deviation that names no departure each fail the comparator
#             that passed the shipped files.
#   RESOLVE   every NINE texture and every manifest glyph, both sizes, resolves headless at the
#             manifest's size times its draw scale; a made-up style, texture and glyph resolve to
#             null.
#   PANEL     Kit.style hands back a textured StyleBoxTexture at the asked opacity, with margins at
#             NINE times Kit.SCALE, cached, and null for a rect smaller than those margins; `Chrome.panel`, `cell`, `item_plate` and
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
	"frame": "S4 The shell's rows are buttons, S6 Bubbles and the dashboard in kit frames",
	"keycap": "S5 Keys wear keycaps",
	"glyph": "S3 Empty slots say what goes there",
}

# The owner's 2026-09-25 decision (docs/30, "The UI Field Kit, live"): the chrome draws at twice
# the kit's native pixels, as the approved mockups do and as the world's 32 px tile is drawn.
const OWNER_SCALE: int = 2

# The one way the built styles depart from the kit's .tres on purpose. Every style .tres sets no
# axis mode, which is Godot's STRETCH; stretched across a tall panel the centre's fine noise
# smeared into blotches and streaks, so by the same decision the styles tile on both axes. Named
# here so the departure is a decision the gate can see, not a drift it cannot: a built style
# that fills any other way than this says is a failure, and so is this entry naming no departure.
const CENTRE_MODE_DEVIATION: Dictionary = {
	"mode": StyleBoxTexture.AXIS_STRETCH_MODE_TILE,
	"why": "docs/30, \"The UI Field Kit, live\": the owner tiled the centre on 2026-09-25; stretched, its noise smeared on tall panels",
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
# mode (TRES_KEYS refuses one), so what they mean is STRETCH; the built style must match that, or
# match a deviation that is named, has a reason, and actually departs from it.
func _mode_faults(id: String, h: int, v: int, deviation: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	var tres_mode: int = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var want: int = tres_mode
	if not deviation.is_empty():
		want = int(deviation.get("mode", tres_mode))
		if want == tres_mode:
			faults.append("CENTRE_MODE_DEVIATION names the .tres files' own stretch -- it departs from nothing")
		if String(deviation.get("why", "")).strip_edges().is_empty():
			faults.append("CENTRE_MODE_DEVIATION gives no reason")
	if h != want or v != want:
		faults.append("%s: the built style fills with axis modes %d/%d; the .tres means %d and the named deviation %s" % [id, h, v, tres_mode, str(deviation.get("mode", "none"))])
	return faults


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
	for id_v in Kit.NINE.keys():
		var built: StyleBoxTexture = Kit.style(String(id_v), Rect2(0, 0, 400, 400), 1.0)
		if built == null:
			push_error("KIT: %s built no style at 400x400 -- its fill mode cannot be judged" % String(id_v))
			ok = false
			continue
		for f in _mode_faults(String(id_v), built.axis_stretch_horizontal, built.axis_stretch_vertical, CENTRE_MODE_DEVIATION):
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
	if not _mode_faults("panel_standard", tile, tile, CENTRE_MODE_DEVIATION).is_empty():
		push_error("KIT: a tiled style under the named deviation was refused -- the comparator cannot pass")
		ok = false
	if _mode_faults("panel_standard", tile, tile, {}).is_empty():
		push_error("KIT: a tiled style with no deviation named passed -- a silent departure from the .tres")
		ok = false
	if _mode_faults("panel_standard", stretch, stretch, CENTRE_MODE_DEVIATION).is_empty():
		push_error("KIT: a stretched style under a deviation that says tile passed")
		ok = false
	if _mode_faults("panel_standard", stretch, stretch, {"mode": stretch, "why": "x"}).is_empty():
		push_error("KIT: a deviation naming the .tres files' own stretch passed")
		ok = false
	var ghost: Array = (manifest.get("assets", []) as Array).duplicate(true)
	ghost.append({"id": "panel_ghost", "category": "chrome", "nine_slice_ltrb": [4, 4, 4, 4]})
	if _coverage_faults(ghost, Kit.NINE).is_empty():
		push_error("KIT: a kit chrome id in neither Kit.NINE nor UNUSED_STYLES passed")
		ok = false
	_stash["styles"] = checked
	if ok:
		print("KIT OK %d styles agree with manifest.json and their .tres at native pixels, drawn at the owner's %dx (%s at 1x, named) and tiled by the named deviation; %d kit chrome pieces left unused with a reason; eight fabricated disagreements each refused" % [checked, Kit.SCALE, ", ".join(Kit.NATIVE_STYLES), UNUSED_STYLES.size()])
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
	var sb: StyleBoxTexture = Kit.style("panel_standard", big, 0.4)
	if sb == null or sb.texture == null:
		push_error("PANEL: Kit.style(panel_standard, 200x120, 0.4) gave no textured style")
		ok = false
	else:
		if absf(sb.modulate_color.a - 0.4) > 0.001:
			push_error("PANEL: the style's opacity is %.3f, asked 0.4" % sb.modulate_color.a)
			ok = false
		var m: Array[int] = [int(sb.texture_margin_left), int(sb.texture_margin_top), int(sb.texture_margin_right), int(sb.texture_margin_bottom)]
		var want_m: Array[int] = []
		for n in _ints(Kit.NINE["panel_standard"]):
			want_m.append(n * Kit.SCALE)
		if m != want_m or m != Kit.margins("panel_standard"):
			push_error("PANEL: the built style's margins %s are not Kit.NINE's times %d, %s" % [str(m), Kit.SCALE, str(want_m)])
			ok = false
		if Vector2i(sb.texture.get_size()) != Vector2i(64, 64) * Kit.SCALE:
			push_error("PANEL: the built style's texture is %s, not the 64 px kit texture at %dx" % [str(sb.texture.get_size()), Kit.SCALE])
			ok = false
		if not sb.draw_center:
			push_error("PANEL: the default style does not draw its centre")
			ok = false
		if not is_same(sb, Kit.style("panel_standard", big, 0.4)):
			push_error("PANEL: the same style at the same opacity was built twice -- it is not cached")
			ok = false
		var edge: StyleBoxTexture = Kit.style("panel_standard", big, 0.4, false)
		if edge == null or edge.draw_center or is_same(edge, sb):
			push_error("PANEL: the border-only pass is missing, draws its centre, or shares the filled style")
			ok = false
		var faded: StyleBoxTexture = Kit.style("panel_standard", big, 0.9)
		if faded == null or is_same(faded, sb) or absf(faded.modulate_color.a - 0.9) > 0.001:
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
		print("PANEL OK a textured style at the asked opacity and doubled margins, cached, border-only apart, none under its margins; panel, cell, item_plate and header reach Kit.style and draw it; a rect-only body, a dead link and a commented needle each refused")
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
	"▲": "the bench's better arrow (bench_panel.gd); \"The shell's rows are buttons\" turns it into a kit glyph",
	"▼": "the bench's worse arrow (bench_panel.gd); \"The shell's rows are buttons\" turns it into a kit glyph",
	"↔": "the bench's same arrow (bench_panel.gd); \"The shell's rows are buttons\" turns it into a kit glyph",
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


func _glyphs_lane() -> bool:
	print("SKIP GLYPHS: not landed")
	return true


# --- 7. KEYCAPS --------------------------------------------------------------------------------


func _keycaps_lane() -> bool:
	print("SKIP KEYCAPS: not landed")
	return true


# --- 8. OUTLIERS -------------------------------------------------------------------------------


func _outliers_lane() -> bool:
	print("SKIP OUTLIERS: not landed")
	return true


# --- 9. CURSORS --------------------------------------------------------------------------------


func _cursors_lane() -> bool:
	print("SKIP CURSORS: not landed")
	return true


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

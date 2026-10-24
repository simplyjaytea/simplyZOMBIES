extends SceneTree
# The overcast day, graded (slice B5 of the three-features plan; docs/30, "The overcast day, as a
# grade"). `presentation/day_grade.gd` grades the finished picture -- toward its own grey, cooled,
# veiled toward an overcast sky -- by the sky's share of daylight, under the night's multiply and
# over nothing the HUD draws. This gate holds the grade to what that sentence promises, each lane
# with its own true negative:
#
#   PHASE     the weight is 1 under a full day's sky and exactly 0 at night, rises monotonically
#             through dawn's ambient, and is partway at mid-dusk; a weight that is still on at
#             night, or flat across dusk, is refused
#   DAY       the palette through the day grade, pinned to a measured table (DAY_TABLE): the
#             source table itself fails the pins (the old warm grade is the case refused), and so
#             does the night (weight 0); every warm surface loses warmth (r - b falls) and every
#             coloured one loses saturation; the void goes to a dark grey
#   NIGHT     weight 0 hands every palette colour back bit for bit, so the night frame is the
#             light map's picture; the grade sits under the night's multiply and its glow (draw
#             index), so a pool's hue and a flame are laid on after it and never graded
#   CONTRAST  the speech bubble -- the one piece of chrome drawn in the world rather than on the
#             HUD's layer -- keeps its 4.5:1 for speech under the grade; a zombie's dim
#             sound-word is measured and reported (it sits under 4.5:1 before the grade too)
#   SHADER    day_grade.gdshader reads the screen and runs DayGrade.grade's steps in its order,
#             on the uniforms day_grade.gd hands it; a needle the shader does not carry is refused
#   READS     the dead socket: main.tscn's `_draw` calls `_draw_day_grade()` before
#             `_draw_night_wash()`; at noon the frame grades at weight 1, at midnight it draws
#             nothing, and with the grade switched off it draws nothing; the HUD's panels all sit
#             on a CanvasLayer above main's canvas item, so none of them is in the graded picture
#   PIXELS    with a display, the day street captured with and without the grade: the street's
#             pixels move and cool, the HUD's saturated chrome is the same pixels in both; skips
#             without a display (`npm run godot:check:grade` runs it headed when DISPLAY is set)
#
# A lane with no data to judge says so and skips, never passes quietly.

const Scenes = preload("res://review/scenes.gd")
const DayGrade = preload("res://presentation/day_grade.gd")
const LightMap = preload("res://presentation/light_map.gd")
const Palette = preload("res://presentation/palette.gd")
const Chrome = preload("res://ui/chrome.gd")
const Clock = preload("res://sim/time/clock.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const SHADER: String = "res://presentation/day_grade.gdshader"
const TICK_SECONDS: float = 1.0 / 20.0

# The palette through a full day's grade, measured off DayGrade.grade at weight 1 (8-bit, rounded)
# when the grade was chosen. A tune of day_grade.gd re-measures this table, in the same commit,
# with the shots.
const DAY_TABLE: Dictionary = {
	"floor": "47484b",
	"dirt": "796952",
	"grass": "485038",
	"water": "314c53",
	"wall": "635b51",
	"door": "554d43",
	"window": "6d818d",
	"indoorFloor": "625245",
	"sidewalk": "8e9193",
	"player": "cfcbae",
	"raider": "8c7267",
	"groundItem": "98947e",
	"roof": "2e2d2c",
	"background": "1c1c20",
}
# The void through the grade: a dark grey, no more than this much chroma (max - min, 8-bit) and
# its value inside VOID_VALUE.
const VOID_CHROMA: int = 6
const VOID_VALUE: Vector2 = Vector2(0.08, 0.16)
const CONTRAST_MIN: float = 4.5

var _failed: bool = false
var _notes: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_phase()
	_day()
	_night()
	_contrast()
	_shader()
	await _reads()
	await _pixels()
	if _failed:
		push_error("GRADE_LOOK_FAIL")
		quit(1)
		return
	for n in _notes:
		print(n)
	print("GRADE_LOOK_OK the day grade is on by day and off by night, pinned to its measured table, under the night and over no HUD")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


func _hex(c: Color) -> String:
	return "%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]


func _within(a: Color, b: Color, eight_bit: int) -> bool:
	var t: float = (float(eight_bit) + 0.5) / 255.0
	return absf(a.r - b.r) <= t and absf(a.g - b.g) <= t and absf(a.b - b.b) <= t


# PHASE.
func _phase() -> void:
	var noon: float = DayGrade.weight_of(Clock.ambient_light(0.5))
	var midnight: float = DayGrade.weight_of(Clock.ambient_light(0.9))
	var dusk: float = DayGrade.weight_of(Clock.ambient_light((Clock.DAY_ENDS + Clock.DUSK_ENDS) / 2.0))
	if noon != 1.0:
		_fail("PHASE: the weight at noon is %f, not 1" % noon)
	if midnight != 0.0:
		_fail("PHASE: the weight at midnight is %f -- the grade is still on at night" % midnight)
	if not (dusk > 0.25 and dusk < 0.75):
		_fail("PHASE: the weight at mid-dusk is %f, not partway" % dusk)
	var last: float = -1.0
	for i in 41:
		var f: float = Clock.DAWN_ENDS * float(i) / 40.0
		var w: float = DayGrade.weight_of(Clock.ambient_light(f))
		if w < last:
			_fail("PHASE: the weight falls through dawn at %f (%f after %f)" % [f, w, last])
			break
		last = w
	_notes.append("PHASE OK weight 1 at noon, 0 at midnight, %.3f at mid-dusk, never falling through dawn" % dusk)


# DAY.
func _day() -> void:
	var bad: int = 0
	for key in DAY_TABLE:
		var src: Color = Palette.COLOURS[key] as Color
		var pin := Color("#" + String(DAY_TABLE[key]))
		var graded: Color = DayGrade.grade(src, 1.0)
		if not _within(graded, pin, 1):
			_fail("DAY: %s grades to #%s, pinned #%s" % [key, _hex(graded), DAY_TABLE[key]])
			bad += 1
		# The old table is the case refused: the source colour, or the night's identity, is not
		# the day's.
		if _within(src, pin, 1):
			_fail("DAY: %s's source colour #%s already passes its day pin -- the pin judges nothing" % [key, _hex(src)])
		if _within(DayGrade.grade(src, 0.0), pin, 1):
			_fail("DAY: %s at weight 0 passes its day pin" % key)
	var warm: int = 0
	var coloured: int = 0
	for key in Palette.COLOURS:
		var c: Color = Palette.COLOURS[key] as Color
		if c.a < 1.0:
			continue
		var g: Color = DayGrade.grade(c, 1.0)
		if c.r - c.b > 0.02:
			warm += 1
			if not (g.r - g.b < c.r - c.b):
				_fail("DAY: %s stays as warm under the grade (r - b %.3f -> %.3f)" % [key, c.r - c.b, g.r - g.b])
		# A cool colour (the glass, the outline) is the one thing the cool cast is allowed to keep
		# coloured; everything else gives its colour up to the grey sky.
		if c.s > 0.1 and c.r >= c.b:
			coloured += 1
			if not (g.s < c.s):
				_fail("DAY: %s keeps its saturation under the grade (%.3f -> %.3f)" % [key, c.s, g.s])
	if warm == 0 or coloured == 0:
		_fail("DAY: no warm or no coloured entries to judge (%d, %d)" % [warm, coloured])
	var void_src: Color = Palette.COLOURS["background"] as Color
	var v: Color = DayGrade.grade(void_src, 1.0)
	var chroma: int = roundi((maxf(v.r, maxf(v.g, v.b)) - minf(v.r, minf(v.g, v.b))) * 255.0)
	var src_chroma: int = roundi((maxf(void_src.r, maxf(void_src.g, void_src.b)) - minf(void_src.r, minf(void_src.g, void_src.b))) * 255.0)
	if chroma > VOID_CHROMA or v.v < VOID_VALUE.x or v.v > VOID_VALUE.y:
		_fail("DAY: the void grades to #%s (chroma %d, value %.3f), not a dark grey" % [_hex(v), chroma, v.v])
	if src_chroma <= VOID_CHROMA:
		_fail("DAY: the source void #%s is already grey -- the void lane judges nothing" % _hex(void_src))
	_notes.append("DAY OK %d pinned entries grade to their measured table and their source colours fail it; %d warm entries lose warmth, %d coloured ones that are not cool lose saturation; the void #%s (chroma %d) grades to #%s (chroma %d)" % [DAY_TABLE.size(), warm, coloured, _hex(void_src), src_chroma, _hex(v), chroma])


# NIGHT.
func _night() -> void:
	var moved: int = 0
	for key in Palette.COLOURS:
		var c: Color = Palette.COLOURS[key] as Color
		if DayGrade.grade(c, 0.0) != c:
			_fail("NIGHT: %s is not handed back bit for bit at weight 0" % key)
		if DayGrade.grade(c, 1.0) != c:
			moved += 1
	if moved == 0:
		_fail("NIGHT: the day grade moves nothing either, so weight 0 proves nothing")
	if not (DayGrade.GRADE_INDEX < LightMap.DARK_INDEX and DayGrade.GRADE_INDEX < LightMap.GLOW_INDEX):
		_fail("NIGHT: the grade (draw index %d) is not under the night (%d) and its glow (%d)" % [DayGrade.GRADE_INDEX, LightMap.DARK_INDEX, LightMap.GLOW_INDEX])
	_notes.append("NIGHT OK weight 0 hands back all %d palette colours (weight 1 moves %d); the grade draws at %d, under the night's multiply %d and the glow %d" % [Palette.COLOURS.size(), moved, DayGrade.GRADE_INDEX, LightMap.DARK_INDEX, LightMap.GLOW_INDEX])


func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _ratio(a: Color, b: Color) -> float:
	var la: float = _lum(a)
	var lb: float = _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


# CONTRAST.
func _contrast() -> void:
	var plate: Color = Chrome.PANEL
	var before: float = _ratio(Chrome.TEXT, plate)
	var after: float = _ratio(DayGrade.grade(Chrome.TEXT, 1.0), DayGrade.grade(plate, 1.0))
	if after < CONTRAST_MIN:
		_fail("CONTRAST: a bubble's speech is %.2f:1 on its plate under the grade, under %.1f:1" % [after, CONTRAST_MIN])
	# The negative: the bound can fail -- the dim text on the same plate does not clear it even
	# ungraded, so a lane that passed it would be judging nothing.
	var dim_before: float = _ratio(Chrome.TEXT_DIM, plate)
	var dim_after: float = _ratio(DayGrade.grade(Chrome.TEXT_DIM, 1.0), DayGrade.grade(plate, 1.0))
	if dim_before >= CONTRAST_MIN:
		_fail("CONTRAST: the dim text clears %.1f:1 ungraded, so the bound was never shown to fail" % CONTRAST_MIN)
	_notes.append("CONTRAST OK a bubble's speech %.2f:1 -> %.2f:1 under the grade; a zombie's dim sound-word %.2f:1 -> %.2f:1 (under %.1f:1 before the grade too, named in docs/23)" % [before, after, dim_before, dim_after, CONTRAST_MIN])


# SHADER.
func _shader() -> void:
	var src: String = FileAccess.get_file_as_string(SHADER)
	if src.is_empty():
		_fail("SHADER: could not read %s" % SHADER)
		return
	var steps: Array[String] = [
		"hint_screen_texture",
		"dot(c, vec3(0.299, 0.587, 0.114))",
		"mix(shadow_saturation, saturation, smoothstep(0.0, shadow_luma, luma))",
		"mix(vec3(luma), c, keep)",
		"clamp(g * cool, 0.0, 1.0)",
		"mix(g, haze, haze_amount)",
		"mix(c, g, weight)",
	]
	var at: int = -1
	for s in steps:
		var i: int = src.find(s)
		if i < 0:
			_fail("SHADER: day_grade.gdshader lost `%s`" % s)
			continue
		if i < at:
			_fail("SHADER: `%s` runs out of DayGrade.grade's order" % s)
		at = i
	if src.find("mix(c, haze, weight)") >= 0:
		_fail("SHADER: a needle the shader never carried was found -- the search is broken")
	var gd: String = FileAccess.get_file_as_string("res://presentation/day_grade.gd")
	for u in ["weight", "saturation", "shadow_saturation", "shadow_luma", "cool", "haze", "haze_amount"]:
		if src.find("uniform ") < 0 or not src.contains("uniform float %s" % u) and not src.contains("uniform vec3 %s" % u):
			_fail("SHADER: the shader declares no uniform `%s`" % u)
		if not gd.contains("set_shader_parameter(\"%s\"" % u):
			_fail("SHADER: day_grade.gd never hands the shader `%s`" % u)
	_notes.append("SHADER OK day_grade.gdshader reads the screen and runs DayGrade.grade's five steps in order on the seven uniforms day_grade.gd sets")


func _tap(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	root.push_input(ev)
	var up := InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	root.push_input(up)


func _function_body(path: String, name: String) -> String:
	var src: String = FileAccess.get_file_as_string(path)
	var start: int = src.find("\nfunc %s(" % name)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, (end if end >= 0 else src.length()) - start)


# READS.
func _reads() -> void:
	var draw_fn: String = _function_body(MAIN_GD, "_draw")
	var at_grade: int = draw_fn.find("_draw_day_grade()")
	var at_wash: int = draw_fn.find("_draw_night_wash()")
	if at_grade < 0:
		_fail("READS: main.gd's _draw never calls _draw_day_grade()")
	elif at_wash < 0 or at_grade > at_wash:
		_fail("READS: _draw calls _draw_day_grade() after (or without) _draw_night_wash()")
	var main: Node = await Scenes.boot(self)
	if main == null:
		_fail("READS: main.tscn did not boot")
		return
	var world: Variant = main.get("world")
	var grade: Variant = main.get("_day_grade")
	if grade == null:
		_fail("READS: main has no _day_grade")
		await _discard(main)
		return
	world.tick = Clock.tick_on_day(1, 0.5)
	await _redraw(main)
	var noon_drew: bool = bool(grade.get("drew"))
	var noon_w: float = float(grade.get("last_weight"))
	world.tick = Clock.tick_on_day(1, 0.9)
	await _redraw(main)
	var night_drew: bool = bool(grade.get("drew"))
	world.tick = Clock.tick_on_day(1, 0.5)
	var kept: bool = DayGrade.enabled
	DayGrade.enabled = false
	await _redraw(main)
	var off_drew: bool = bool(grade.get("drew"))
	DayGrade.enabled = kept
	if not noon_drew or noon_w != 1.0:
		_fail("READS: the noon frame did not grade at weight 1 (drew %s, weight %f)" % [noon_drew, noon_w])
	if night_drew:
		_fail("READS: the midnight frame drew the grade")
	if off_drew:
		_fail("READS: the frame graded with the grade switched off -- `drew` reads nothing")
	# The HUD: every Control main owns is under a CanvasLayer above main's canvas (layer >= 1), so
	# none of it is drawn before the grade reads the screen.
	var controls: int = 0
	for n in main.find_children("*", "Control", true, false):
		var c: Control = n as Control
		var layer: CanvasLayer = null
		var p: Node = c.get_parent()
		while p != null and p != main:
			if p is CanvasLayer:
				layer = p as CanvasLayer
				break
			p = p.get_parent()
		controls += 1
		if layer == null or layer.layer < 1:
			_fail("READS: the HUD control %s is not on a CanvasLayer above the world, so the grade would read it" % str(c.get_path()))
	if controls == 0:
		_fail("READS: main owns no HUD control to judge")
	await _discard(main)
	_notes.append("READS OK _draw calls _draw_day_grade() before _draw_night_wash(); noon grades at weight 1, midnight and the switched-off grade draw nothing; all %d HUD controls sit on a CanvasLayer over the graded world" % controls)


func _redraw(main: Node) -> void:
	main.call("_process", TICK_SECONDS)
	main.call("queue_redraw")
	await process_frame
	await process_frame


func _discard(main: Node) -> void:
	main.queue_free()
	await process_frame


# PIXELS.
func _pixels() -> void:
	if DisplayServer.get_name() == "headless":
		_notes.append("PIXELS SKIP no display, so no picture was taken (run with DISPLAY or xvfb-run)")
		return
	root.size = Vector2i(1280, 720)
	await process_frame
	var main: Node = await Scenes.boot(self)
	if main == null:
		_fail("PIXELS: main.tscn did not boot")
		return
	var err: String = await Scenes.setup(self, main, "day_street")
	if err.is_empty():
		err = Scenes.verify(main, "day_street")
	if not err.is_empty():
		_fail("PIXELS: the day street: %s" % err)
		await _discard(main)
		return
	await process_frame
	var graded: Image = root.get_texture().get_image()
	var kept: bool = DayGrade.enabled
	DayGrade.enabled = false
	main.call("queue_redraw")
	await process_frame
	await process_frame
	var plain: Image = root.get_texture().get_image()
	DayGrade.enabled = kept
	# Where the HUD is: every visible control on a CanvasLayer that does not cover the window.
	var hud: Array[Rect2] = []
	for n in main.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if c.is_visible_in_tree() and c.get_global_rect().get_area() < 0.5 * 1280.0 * 720.0:
			hud.append(c.get_global_rect())
	await _discard(main)
	if graded == null or plain == null or graded.is_empty() or plain.is_empty():
		_fail("PIXELS: a capture came back empty")
		return
	# The HUD's saturated chrome -- the key chips' amber, inside a HUD control's rect -- is the same
	# pixels in both. The street, away from every panel, moves, and cools: its mean r - b falls.
	# (Not its saturation: the asphalt is a neutral grey, and the cool cast gives a grey a little
	# blue rather than taking colour away.)
	var size: Vector2i = plain.get_size()
	var chrome: int = 0
	var chrome_same: int = 0
	var world_px: int = 0
	var world_same: int = 0
	var warm_plain: float = 0.0
	var warm_graded: float = 0.0
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			var a: Color = plain.get_pixel(x, y)
			var b: Color = graded.get_pixel(x, y)
			var in_hud: bool = false
			for r in hud:
				if r.has_point(Vector2(x, y)):
					in_hud = true
					break
			if in_hud:
				if a.s > 0.8 and a.v > 0.6:
					chrome += 1
					if a == b:
						chrome_same += 1
			elif x > 400 and x < 880 and y > 200 and y < 400:
				world_px += 1
				if a == b:
					world_same += 1
				warm_plain += a.r - a.b
				warm_graded += b.r - b.b
	if chrome == 0:
		_fail("PIXELS: no saturated HUD chrome in the day street to judge")
	elif chrome_same != chrome:
		_fail("PIXELS: %d of %d saturated HUD pixels changed under the grade -- the HUD is graded" % [chrome - chrome_same, chrome])
	if world_px == 0 or float(world_same) > 0.05 * float(world_px):
		_fail("PIXELS: %d of %d street pixels are unchanged by the grade" % [world_same, world_px])
	if not (warm_graded < warm_plain):
		_fail("PIXELS: the street did not cool under the grade (mean r - b %.4f -> %.4f)" % [warm_plain / maxf(1.0, float(world_px)), warm_graded / maxf(1.0, float(world_px))])
	_notes.append("PIXELS OK the day street at 1280x720: %d saturated HUD pixels identical with and without the grade; %d of %d street pixels moved, mean r - b %.4f -> %.4f" % [chrome, world_px - world_same, world_px, warm_plain / maxf(1.0, float(world_px)), warm_graded / maxf(1.0, float(world_px))])

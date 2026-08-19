extends Control
# Port of src/render/paperdoll.ts + src/render/sprites/outline.ts diagrams.
# A person, flat on, not the body in the district. Tint per region, no numbers cross.
# ponytail: single file for Control; extract to presentation/outline.gd when reused elsewhere.

const Palette = preload("res://presentation/palette.gd")
const SimStances = preload("res://sim/stances.gd")

enum OutlinePose { Stand = 0, Crouch = 1, Prone = 2 }

# fractions of standing height, same P as outline.ts
const P: Dictionary = {
	"headCentreY": 0.925, "headRx": 0.052, "headRy": 0.062,
	"neckY": 0.855, "neckHalf": 0.022, "shoulderY": 0.815, "shoulderHalf": 0.145,
	"waistY": 0.6, "waistHalf": 0.098, "hipY": 0.485, "hipHalf": 0.112,
	"armHalf": 0.026, "wristY": 0.44, "wristHalf": 0.175, "handR": 0.032,
	"legHalf": 0.042, "hipStanceHalf": 0.055, "ankleY": 0.055, "ankleHalf": 0.062, "footR": 0.036,
}
const CROUCH_KNEE_SPREAD: float = 0.085
const PRONE_REACH: float = 0.14
const PRONE_WRIST_Y: float = 0.955 # shoulderY + reach approx
const CRAWL_FRAC: float = 0.34
const CROUCH_FRAC: float = 0.68

# Worst-case extent, as a fraction of `h`, over every pose this file draws -- used to size
# `h` to whatever box the control actually is rather than a constant. Standing is the tall
# pose (head reaches headCentreY + headRy above the anchor, unfolded); prone is the wide one,
# because lying down rotates the body into the horizontal axis and the ankle-to-wrist span
# becomes screen-horizontal. Getting these two fractions right is what makes h fill the
# control at every stance without clipping at any of them.
const TALLEST_ABOVE_ANCHOR_FRAC: float = 0.99 # stand: headCentreY (0.925) + headRy (0.062)
const WIDEST_HALF_FRAC: float = 0.6 # prone: |0.5 - ankleY| after PRONE_REACH, rounded up

const TOP_MARGIN: float = 12.0
const BOTTOM_MARGIN: float = 20.0
const SIDE_MARGIN: float = 12.0
const MIN_HEIGHT: float = 40.0

# The figure faces the viewer, like a medical chart -- so *their* left is *your* right, the
# same convention every other paperdoll-style UI and anatomical diagram uses. side == -1 is
# screen-left, which is therefore the person's right; side == 1 is screen-right, their left.
# Nothing in the sim depends on this (nothing currently selects a limb by clicking the
# figure), so getting it backwards would be a purely cosmetic mistake -- but it would still
# be a wrong one, so it is named once here rather than re-decided at each call site.
const SIDE_NAME: Dictionary = {-1: "right", 1: "left"}

var _view: Dictionary = {} # {parts:[{part,state,prose,wounded,infected,armored}], stance:int, worst:int}
var _by_part: Dictionary = {} # part name -> its full dict from _view, rebuilt in set_view

func set_view(view: Dictionary) -> void:
	_view = view
	_by_part = {}
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		_by_part[String(d.get("part", ""))] = d
	queue_redraw()

# `h` used to be a hardcoded 118.0, so giving this control more room -- the corner glimpse is
# 280px, the gear panel is 520px -- drew exactly the same figure either way. This fits the
# figure to whatever `size` actually is, bounded by whichever pose is tightest so no stance
# clips once it's picked.
func _figure_height() -> float:
	var from_height: float = (size.y - BOTTOM_MARGIN - TOP_MARGIN) / TALLEST_ABOVE_ANCHOR_FRAC
	var from_width: float = (size.x / 2.0 - SIDE_MARGIN) / WIDEST_HALF_FRAC
	return maxf(MIN_HEIGHT, minf(from_height, from_width))

func _pose_for_stance(stance: int) -> int:
	if stance == 0: return OutlinePose.Prone # Crawl
	if stance == 1: return OutlinePose.Crouch # Crouch (Eye.Crouched)
	return OutlinePose.Stand

func _tint_for(part: String) -> Variant:
	var d: Variant = _by_part.get(part)
	if not (d is Dictionary):
		return null
	var st: int = int((d as Dictionary).get("state", 0))
	if st == 0:
		return null
	return Palette.CONDITION_TINTS[st] if st < Palette.CONDITION_TINTS.size() else null

# Two things this file draws that are not a tint: whether a mark belongs at a point (wound,
# infection) and whether a stroke belongs around a shape (armour). Both read the same
# boolean/word fields condition.gd already limited itself to -- a wound mark never counts
# wounds, and an infected mark never shows a stage, because the data behind them cannot: see
# condition.gd's PART_KEYS comment. A part with several things true draws several marks
# rather than picking one, so nothing here decides a mark is more important than another.
func _wounded(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and bool((d as Dictionary).get("wounded", false))

func _infected(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and String((d as Dictionary).get("infected", "none")) != "none"

func _armored(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and bool((d as Dictionary).get("armored", false))

# The figure is a filled silhouette now, not a stroked stick: every limb is a capsule
# (thick round-capped segment), the torso a filled polygon with rounded shoulders, and the
# whole body sits on a soft ground shadow -- the Tarkov-register body diagram the owner
# asked for, drawn in code so every part stays individually tintable. Condition still
# crosses only as the four state tints; armour is a steel outer stroke; nothing numeric.
const BASE_FILL: Color = Color("#4d5546")
const RIM: Color = Color("#12150f")
const ARMOUR_COL: Color = Color(0.55, 0.66, 0.78)
const TINT_BLEND: float = 0.72


func _fill_for(part: String) -> Color:
	var tint: Variant = _tint_for(part)
	if tint == null:
		return BASE_FILL
	return BASE_FILL.lerp(tint as Color, TINT_BLEND)


# A rounded limb: round-capped thick segment. Drawn twice -- rim then fill -- so every
# part carries a dark edge that separates it from its neighbours and the panel.
func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	if a.distance_to(b) < 0.5:
		draw_circle(a, r, col)
		return
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


func _limb(a: Vector2, b: Vector2, r: float, part: String) -> void:
	if _armored(part):
		_capsule(a, b, r + maxf(2.6, r * 0.32), ARMOUR_COL)
	_capsule(a, b, r + 1.6, RIM)
	_capsule(a, b, r, _fill_for(part))


func _draw() -> void:
	if _view.is_empty():
		return
	var pose: int = _pose_for_stance(int(_view.get("stance", 2)))
	# anchor at bottom-center of control
	var anchor_x: float = size.x / 2.0
	var anchor_y: float = size.y - BOTTOM_MARGIN
	var h: float = _figure_height()
	# frame projector
	var prone: bool = pose == OutlinePose.Prone
	var pivot: float = 0.5
	var mark_r: float = maxf(3.0, h * 0.028)
	# soft ground shadow under the figure, squashed into an ellipse
	draw_set_transform(Vector2(anchor_x, anchor_y), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, h * (0.5 if prone else 0.22), Color(0.0, 0.0, 0.0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# A part with both a wound and an infection needs two marks that don't sit on top of each
	# other; offsets keeps them apart along whichever axis this pose draws limbs across.
	var mark_backing: Color = Color(0.05, 0.055, 0.06)
	var draw_marks: Callable = func(at: Vector2, part: String, axis: Vector2) -> void:
		var slot: int = 0
		if _wounded(part):
			var pos: Vector2 = at + axis * mark_r * 2.2 * float(slot)
			draw_circle(pos, mark_r, mark_backing) # solid backing so the ring reads over any tint
			draw_circle(pos, mark_r, Color(0.72, 0.24, 0.22), false, 2.0)
			slot += 1
		if _infected(part):
			var pos2: Vector2 = at + axis * mark_r * 2.2 * float(slot)
			draw_circle(pos2, mark_r * 0.85, mark_backing)
			draw_circle(pos2, mark_r * 0.85, Color(0.68, 0.82, 0.36), false, 2.4)
			slot += 1
	var project: Callable = func(fx: float, fy: float) -> Vector2:
		if prone:
			return Vector2(anchor_x + (pivot - fy) * h, anchor_y - CRAWL_FRAC * h + fx * h)
		return Vector2(anchor_x + fx * h, anchor_y - fy * h)
	var fold: float = CROUCH_FRAC if pose == OutlinePose.Crouch else 1.0
	var up: Callable = func(f: float) -> float: return f * fold
	var shoulder_y: float = up.call(P["shoulderY"])
	var hip_y: float = up.call(P["hipY"])
	var ankle_y: float = (float(P["ankleY"]) - PRONE_REACH) if prone else float(P["ankleY"])
	var wrist_y: float = PRONE_WRIST_Y if prone else up.call(P["wristY"])
	# legs -- side -1/1 is screen left/right; SIDE_NAME maps that to the person's own
	# right/left, since the figure faces the viewer.
	for side in [-1, 1]:
		var leg_part: String = "leg_" + String(SIDE_NAME[side])
		var foot_part: String = "foot_" + String(SIDE_NAME[side])
		var hip_x: float = float(side) * float(P["hipStanceHalf"])
		var knee_x: float = float(side) * (float(P["hipStanceHalf"]) + (CROUCH_KNEE_SPREAD if pose == OutlinePose.Crouch else 0.0))
		var ankle_x: float = float(side) * float(P["ankleHalf"])
		var p0: Vector2 = project.call(hip_x, hip_y)
		var p1: Vector2 = project.call(knee_x, (hip_y + ankle_y) / 2.0)
		var p2: Vector2 = project.call(ankle_x, ankle_y)
		var half: float = float(P["legHalf"]) * h
		_limb(p0, p1, half, leg_part)
		_limb(p1, p2, half * 0.86, leg_part)
		var foot_r: float = float(P["footR"]) * h
		var foot_at: Vector2 = p2 + Vector2(0, -foot_r * 0.2) if not prone else p2 + Vector2(foot_r * 0.4, 0)
		_limb(foot_at, foot_at, foot_r, foot_part)
		draw_marks.call(p1, leg_part, Vector2(0, 1) if not prone else Vector2(1, 0))
		draw_marks.call(foot_at, foot_part, Vector2(1, 0))
	# arms
	for side in [-1, 1]:
		var arm_part: String = "arm_" + String(SIDE_NAME[side])
		var hand_part: String = "hand_" + String(SIDE_NAME[side])
		var shoulder_x: float = float(side) * (float(P["shoulderHalf"]) - float(P["armHalf"]))
		var wrist_x: float = float(side) * (float(P["wristHalf"]) * (0.62 if prone else 1.0))
		var mid_x: float = (shoulder_x + wrist_x) / 2.0
		var mid_y: float = (shoulder_y + wrist_y) / 2.0
		var pS: Vector2 = project.call(shoulder_x, shoulder_y)
		var pM: Vector2 = project.call(mid_x, mid_y)
		var pW: Vector2 = project.call(wrist_x, wrist_y)
		var aw: float = float(P["armHalf"]) * h
		_limb(pS, pM, aw, arm_part)
		_limb(pM, pW, aw * 0.88, arm_part)
		var hand_r: float = float(P["handR"]) * h
		var hand_at: Vector2 = pW + Vector2(0, hand_r * 0.6 if prone else -hand_r * 0.6)
		_limb(hand_at, hand_at, hand_r, hand_part)
		draw_marks.call(pM, arm_part, Vector2(0, 1) if not prone else Vector2(1, 0))
		draw_marks.call(hand_at, hand_part, Vector2(1, 0))
	# torso -- filled polygon with a rim, shoulders and hips rounded by joint circles so
	# the outline reads as a body rather than a kite
	var poly: PackedVector2Array = PackedVector2Array([
		project.call(-float(P["neckHalf"]), up.call(P["neckY"])),
		project.call(float(P["neckHalf"]), up.call(P["neckY"])),
		project.call(float(P["shoulderHalf"]), shoulder_y),
		project.call(float(P["waistHalf"]), up.call(P["waistY"])),
		project.call(float(P["hipHalf"]), hip_y),
		project.call(-float(P["hipHalf"]), hip_y),
		project.call(-float(P["waistHalf"]), up.call(P["waistY"])),
		project.call(-float(P["shoulderHalf"]), shoulder_y),
	])
	var torso_fill: Color = _fill_for("torso")
	var joint_r: float = float(P["armHalf"]) * h * 1.35
	if _armored("torso"):
		var grow: float = maxf(3.0, h * 0.022)
		draw_polyline(poly + PackedVector2Array([poly[0]]), ARMOUR_COL, grow * 2.0)
	draw_polyline(poly + PackedVector2Array([poly[0]]), RIM, 3.2)
	draw_colored_polygon(poly, torso_fill)
	for corner in [poly[2], poly[7], poly[4], poly[5]]:
		draw_circle(corner as Vector2, joint_r, torso_fill)
	draw_marks.call(project.call(0.0, up.call(P["waistY"])), "torso", Vector2(1, 0))
	# neck and head
	var head: Vector2 = project.call(0.0, up.call(P["headCentreY"]))
	var neck_at: Vector2 = project.call(0.0, up.call(P["neckY"]))
	var rx: float = float(P["headRx"]) * h
	var ry: float = float(P["headRy"]) * h
	if prone:
		var tmp: float = rx; rx = ry; ry = tmp
	var head_r: float = (rx + ry) / 2.0
	_capsule(neck_at, head, float(P["neckHalf"]) * h, torso_fill)
	if _armored("head"):
		draw_circle(head, head_r + maxf(2.6, head_r * 0.3), ARMOUR_COL)
	draw_circle(head, head_r + 1.6, RIM)
	draw_circle(head, head_r, _fill_for("head"))
	draw_marks.call(head, "head", Vector2(1, 0))
	# prose below figure — posture hint only, no numbers cross the boundary (docs/05)
	if _view.has("parts"):
		var y: float = size.y - 56.0
		# SimStances.NAMES is the one canonical stance-name list; this used to be its own
		# three-way ternary that mapped stance 0 to "stand" (it is Crawl) and stances 3/4
		# (Jog/Sprint) both to "walk" -- three of five stances were mislabeled, and jogging
		# and sprinting were visually indistinguishable from walking.
		var stance: int = int(_view.get("stance", SimStances.Stance.Walk))
		var label: String = SimStances.name_of(stance) if stance >= 0 and stance < SimStances.NAMES.size() else "walking"
		# tint already encodes worst visibly; text only names posture
		draw_string(ThemeDB.fallback_font, Vector2(12, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.COLOURS["outline"])

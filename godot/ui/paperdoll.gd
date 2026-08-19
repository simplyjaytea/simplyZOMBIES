extends Control
# The survivor's body, flat on, like a medical chart. A filled human figure -- tapered
# limbs, an A-pose with the arms clear of the trunk, a chest-to-waist-to-hip curve, an
# elliptical head -- drawn entirely in code so all ten parts stay individually tintable
# and the health-bar ban stays trivially honoured: condition crosses as the four state
# tints, armour as a steel outer stroke, wounds and infection as marks, never a number.

const Palette = preload("res://presentation/palette.gd")
const SimStances = preload("res://sim/stances.gd")

enum OutlinePose { Stand = 0, Crouch = 1, Prone = 2 }

# Fractions of standing height. Tuned 2026-08-19 for the human silhouette: the stance is
# wider, the wrists sit further out (a true A-pose, so the arms read as their own shapes
# instead of hugging the trunk), and the chest row gives the torso its taper.
const P: Dictionary = {
	"headCentreY": 0.925, "headRx": 0.048, "headRy": 0.062,
	"neckY": 0.85, "neckHalf": 0.024, "shoulderY": 0.81, "shoulderHalf": 0.14,
	"chestY": 0.72, "chestHalf": 0.125,
	"waistY": 0.585, "waistHalf": 0.095, "hipY": 0.485, "hipHalf": 0.11,
	"armHalf": 0.03, "wristY": 0.415, "wristHalf": 0.215, "handR": 0.034,
	"legHalf": 0.048, "hipStanceHalf": 0.062, "ankleY": 0.055, "ankleHalf": 0.075, "footR": 0.038,
}
const ELBOW_OUT: float = 0.022
const CROUCH_KNEE_SPREAD: float = 0.085
const PRONE_REACH: float = 0.14
const PRONE_WRIST_Y: float = 0.955
const CRAWL_FRAC: float = 0.34
const CROUCH_FRAC: float = 0.68

const TALLEST_ABOVE_ANCHOR_FRAC: float = 0.99
const WIDEST_HALF_FRAC: float = 0.6

const TOP_MARGIN: float = 12.0
const BOTTOM_MARGIN: float = 20.0
const SIDE_MARGIN: float = 12.0
const MIN_HEIGHT: float = 40.0

# The figure faces the viewer, like a medical chart -- so *their* left is *your* right.
const SIDE_NAME: Dictionary = {-1: "right", 1: "left"}

const BASE_FILL: Color = Color("#4d5546")
const RIM: Color = Color("#12150f")
const ARMOUR_COL: Color = Color(0.55, 0.66, 0.78)
const TINT_BLEND: float = 0.72

var _view: Dictionary = {}
var _by_part: Dictionary = {}


func set_view(view: Dictionary) -> void:
	_view = view
	_by_part = {}
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		_by_part[String(d.get("part", ""))] = d
	queue_redraw()


func _figure_height() -> float:
	var from_height: float = (size.y - BOTTOM_MARGIN - TOP_MARGIN) / TALLEST_ABOVE_ANCHOR_FRAC
	var from_width: float = (size.x / 2.0 - SIDE_MARGIN) / WIDEST_HALF_FRAC
	return maxf(MIN_HEIGHT, minf(from_height, from_width))


func _pose_for_stance(stance: int) -> int:
	if stance == 0: return OutlinePose.Prone # Crawl
	if stance == 1: return OutlinePose.Crouch
	return OutlinePose.Stand


func _tint_for(part: String) -> Variant:
	var d: Variant = _by_part.get(part)
	if not (d is Dictionary):
		return null
	var st: int = int((d as Dictionary).get("state", 0))
	if st == 0:
		return null
	return Palette.CONDITION_TINTS[st] if st < Palette.CONDITION_TINTS.size() else null


func _wounded(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and bool((d as Dictionary).get("wounded", false))


func _infected(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and String((d as Dictionary).get("infected", "none")) != "none"


func _armored(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and bool((d as Dictionary).get("armored", false))


func _fill_for(part: String) -> Color:
	var tint: Variant = _tint_for(part)
	if tint == null:
		return BASE_FILL
	return BASE_FILL.lerp(tint as Color, TINT_BLEND)


# A tapered limb segment: a quad from the perpendicular offsets at each end plus a circle
# at each end, so a thigh can be thicker than its ankle and the joint stays round. Works in
# any orientation, which is what keeps the prone pose free.
func _tapered(a: Vector2, b: Vector2, ra: float, rb: float, col: Color) -> void:
	var seg: Vector2 = b - a
	if seg.length() < 0.5:
		draw_circle(a, maxf(ra, rb), col)
		return
	var n: Vector2 = seg.normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([a + n * ra, a - n * ra, b - n * rb, b + n * rb]), col)
	draw_circle(a, ra, col)
	draw_circle(b, rb, col)


func _limb(a: Vector2, b: Vector2, ra: float, rb: float, part: String) -> void:
	if _armored(part):
		var g: float = maxf(2.6, maxf(ra, rb) * 0.32)
		_tapered(a, b, ra + g, rb + g, ARMOUR_COL)
	_tapered(a, b, ra + 1.6, rb + 1.6, RIM)
	_tapered(a, b, ra, rb, _fill_for(part))


# An ellipse via a scaled circle: used by the head and the feet.
func _ellipse(at: Vector2, r: float, scale_x: float, scale_y: float, col: Color) -> void:
	draw_set_transform(at, 0.0, Vector2(scale_x, scale_y))
	draw_circle(Vector2.ZERO, r, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if _view.is_empty():
		return
	var pose: int = _pose_for_stance(int(_view.get("stance", 2)))
	var anchor_x: float = size.x / 2.0
	var anchor_y: float = size.y - BOTTOM_MARGIN
	var h: float = _figure_height()
	var prone: bool = pose == OutlinePose.Prone
	var pivot: float = 0.5
	var mark_r: float = maxf(3.0, h * 0.028)
	# soft ground shadow
	draw_set_transform(Vector2(anchor_x, anchor_y), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, h * (0.5 if prone else 0.24), Color(0.0, 0.0, 0.0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mark_backing: Color = Color(0.05, 0.055, 0.06)
	var draw_marks: Callable = func(at: Vector2, part: String, axis: Vector2) -> void:
		var slot: int = 0
		if _wounded(part):
			var pos: Vector2 = at + axis * mark_r * 2.2 * float(slot)
			draw_circle(pos, mark_r, mark_backing)
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
	# legs -- thigh thicker than calf, calf thicker than ankle
	for side in [-1, 1]:
		var leg_part: String = "leg_" + String(SIDE_NAME[side])
		var foot_part: String = "foot_" + String(SIDE_NAME[side])
		var hip_x: float = float(side) * float(P["hipStanceHalf"])
		var knee_x: float = float(side) * (float(P["hipStanceHalf"]) + 0.012 + (CROUCH_KNEE_SPREAD if pose == OutlinePose.Crouch else 0.0))
		var ankle_x: float = float(side) * float(P["ankleHalf"])
		var p0: Vector2 = project.call(hip_x, hip_y)
		var p1: Vector2 = project.call(knee_x, (hip_y + ankle_y) / 2.0)
		var p2: Vector2 = project.call(ankle_x, ankle_y)
		var half: float = float(P["legHalf"]) * h
		_limb(p0, p1, half * 1.2, half * 0.9, leg_part)
		_limb(p1, p2, half * 0.88, half * 0.58, leg_part)
		var foot_r: float = float(P["footR"]) * h
		var foot_at: Vector2 = p2 + (Vector2(float(side) * foot_r * 0.35, -foot_r * 0.25) if not prone else Vector2(foot_r * 0.5, 0))
		if _armored(foot_part):
			_ellipse(foot_at, foot_r + maxf(2.4, foot_r * 0.3), 1.25, 0.85, ARMOUR_COL)
		_ellipse(foot_at, foot_r + 1.6, 1.25, 0.85, RIM)
		_ellipse(foot_at, foot_r, 1.25, 0.85, _fill_for(foot_part))
		draw_marks.call(p1, leg_part, Vector2(0, 1) if not prone else Vector2(1, 0))
		draw_marks.call(foot_at, foot_part, Vector2(1, 0))
	# arms -- an A-pose with a slight elbow bend, upper arm thicker than forearm
	for side in [-1, 1]:
		var arm_part: String = "arm_" + String(SIDE_NAME[side])
		var hand_part: String = "hand_" + String(SIDE_NAME[side])
		var shoulder_x: float = float(side) * (float(P["shoulderHalf"]) - float(P["armHalf"]) * 0.4)
		var wrist_x: float = float(side) * (float(P["wristHalf"]) * (0.62 if prone else 1.0))
		var mid_x: float = (shoulder_x + wrist_x) / 2.0 + float(side) * ELBOW_OUT
		var mid_y: float = (shoulder_y + wrist_y) / 2.0
		var pS: Vector2 = project.call(shoulder_x, shoulder_y - 0.01)
		var pM: Vector2 = project.call(mid_x, mid_y)
		var pW: Vector2 = project.call(wrist_x, wrist_y)
		var aw: float = float(P["armHalf"]) * h
		_limb(pS, pM, aw * 1.1, aw * 0.85, arm_part)
		_limb(pM, pW, aw * 0.82, aw * 0.55, arm_part)
		var hand_r: float = float(P["handR"]) * h
		var hand_at: Vector2 = pW + Vector2(0, hand_r * 0.6 if prone else -hand_r * 0.7)
		_limb(hand_at, hand_at, hand_r, hand_r, hand_part)
		draw_marks.call(pM, arm_part, Vector2(0, 1) if not prone else Vector2(1, 0))
		draw_marks.call(hand_at, hand_part, Vector2(1, 0))
	# torso -- shoulders, chest, waist, hips: the curve is what makes it read as a body
	var poly: PackedVector2Array = PackedVector2Array([
		project.call(-float(P["neckHalf"]), up.call(P["neckY"])),
		project.call(float(P["neckHalf"]), up.call(P["neckY"])),
		project.call(float(P["shoulderHalf"]), shoulder_y),
		project.call(float(P["chestHalf"]), up.call(P["chestY"])),
		project.call(float(P["waistHalf"]), up.call(P["waistY"])),
		project.call(float(P["hipHalf"]), hip_y),
		project.call(-float(P["hipHalf"]), hip_y),
		project.call(-float(P["waistHalf"]), up.call(P["waistY"])),
		project.call(-float(P["chestHalf"]), up.call(P["chestY"])),
		project.call(-float(P["shoulderHalf"]), shoulder_y),
	])
	var torso_fill: Color = _fill_for("torso")
	var joint_r: float = float(P["armHalf"]) * h * 1.5
	if _armored("torso"):
		draw_polyline(poly + PackedVector2Array([poly[0]]), ARMOUR_COL, maxf(3.0, h * 0.022) * 2.0)
	draw_polyline(poly + PackedVector2Array([poly[0]]), RIM, 3.2)
	draw_colored_polygon(poly, torso_fill)
	# rounded shoulders and hips
	for corner in [poly[2], poly[9], poly[5], poly[6]]:
		draw_circle(corner as Vector2, joint_r, torso_fill)
	draw_marks.call(project.call(0.0, up.call(P["waistY"])), "torso", Vector2(1, 0))
	# neck and head -- the head is an ellipse, taller than it is wide
	var head: Vector2 = project.call(0.0, up.call(P["headCentreY"]))
	var neck_at: Vector2 = project.call(0.0, up.call(P["neckY"]))
	var head_r: float = float(P["headRy"]) * h
	var head_sx: float = float(P["headRx"]) / float(P["headRy"])
	if prone:
		head_sx = 1.0 / head_sx
	_tapered(neck_at, neck_at.lerp(head, 0.6), float(P["neckHalf"]) * h * 1.05, float(P["neckHalf"]) * h * 0.85, torso_fill)
	if _armored("head"):
		_ellipse(head, head_r + maxf(2.6, head_r * 0.3), head_sx, 1.0, ARMOUR_COL)
	_ellipse(head, head_r + 1.6, head_sx, 1.0, RIM)
	_ellipse(head, head_r, head_sx, 1.0, _fill_for("head"))
	draw_marks.call(head, "head", Vector2(1, 0))
	# prose below figure -- posture hint only, no numbers cross the boundary (docs/05)
	if _view.has("parts"):
		var y: float = size.y - 56.0
		var stance: int = int(_view.get("stance", SimStances.Stance.Walk))
		var label: String = SimStances.name_of(stance) if stance >= 0 and stance < SimStances.NAMES.size() else "walking"
		draw_string(ThemeDB.fallback_font, Vector2(12, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.COLOURS["outline"])

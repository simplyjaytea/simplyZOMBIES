extends Control
# Port of src/render/paperdoll.ts + src/render/sprites/outline.ts diagrams.
# A person, flat on, not the body in the district. Tint per region, no numbers cross.
# ponytail: single file for Control; extract to presentation/outline.gd when reused elsewhere.

const Palette = preload("res://presentation/palette.gd")

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

var _view: Dictionary = {} # {parts:[{part,state,prose}], stance:int, worst:int}
var _height: float = 118.0

func set_view(view: Dictionary) -> void:
	_view = view
	queue_redraw()

func _pose_for_stance(stance: int) -> int:
	if stance == 0: return OutlinePose.Prone # Crawl
	if stance == 1: return OutlinePose.Crouch # Crouch (Eye.Crouched)
	return OutlinePose.Stand

func _get_tint(region: String) -> Variant:
	for part in _view.get("parts", []) as Array:
		var d: Dictionary = part as Dictionary
		if String(d.get("part", "")) == region:
			var st: int = int(d.get("state", 0))
			if st == 0: return null
			return Palette.CONDITION_TINTS[st] if st < Palette.CONDITION_TINTS.size() else null
	return null

func _draw() -> void:
	if _view.is_empty():
		return
	var pose: int = _pose_for_stance(int(_view.get("stance", 2)))
	var tint_for: Callable = func(region: String) -> Variant: return _get_tint(region)
	# anchor at bottom-center of control
	var anchor_x: float = size.x / 2.0
	var anchor_y: float = size.y - 10.0
	var h: float = _height
	# frame projector
	var prone: bool = pose == OutlinePose.Prone
	var pivot: float = 0.5
	# simplified prone span/pivot
	var draw_poly: Callable = func(points: PackedVector2Array, region: String) -> void:
		if points.size() < 3: return
		var col: Variant = tint_for.call(region)
		if col != null:
			draw_colored_polygon(points, col as Color)
		draw_polyline(points + PackedVector2Array([points[0]]), Palette.COLOURS["outline"], maxf(1.0, h * 0.014))
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
	# legs
	for side in [-1, 1]:
		var hip_x: float = float(side) * float(P["hipStanceHalf"])
		var knee_x: float = float(side) * (float(P["hipStanceHalf"]) + (CROUCH_KNEE_SPREAD if pose == OutlinePose.Crouch else 0.0))
		var ankle_x: float = float(side) * float(P["ankleHalf"])
		var p0: Vector2 = project.call(hip_x, hip_y)
		var p1: Vector2 = project.call(knee_x, (hip_y + ankle_y) / 2.0)
		var p2: Vector2 = project.call(ankle_x, ankle_y)
		var half: float = float(P["legHalf"]) * h
		# crude quads as polygons
		var a: Vector2 = Vector2(half, 0)
		if not prone:
			draw_poly.call(PackedVector2Array([p0 + Vector2(-half, 0), p0 + Vector2(half, 0), p1 + Vector2(half * 0.86, 0), p1 + Vector2(-half * 0.86, 0)]), "legs")
			draw_poly.call(PackedVector2Array([p1 + Vector2(-half * 0.86, 0), p1 + Vector2(half * 0.86, 0), p2 + Vector2(half * 0.86, 0), p2 + Vector2(-half * 0.86, 0)]), "legs")
		else:
			draw_poly.call(PackedVector2Array([p0 + Vector2(0, -half), p0 + Vector2(0, half), p1 + Vector2(0, half * 0.86), p1 + Vector2(0, -half * 0.86)]), "legs")
			draw_poly.call(PackedVector2Array([p1 + Vector2(0, -half * 0.86), p1 + Vector2(0, half * 0.86), p2 + Vector2(0, half * 0.86), p2 + Vector2(0, -half * 0.86)]), "legs")
		var foot_r: float = float(P["footR"]) * h
		draw_circle(p2 + Vector2(0, -foot_r * 0.8), foot_r * 0.62, Palette.COLOURS["outline"] if tint_for.call("feet") == null else tint_for.call("feet") as Color)
	# arms
	for side in [-1, 1]:
		var shoulder_x: float = float(side) * (float(P["shoulderHalf"]) - float(P["armHalf"]))
		var wrist_x: float = float(side) * (float(P["wristHalf"]) * (0.62 if prone else 1.0))
		var mid_x: float = (shoulder_x + wrist_x) / 2.0
		var mid_y: float = (shoulder_y + wrist_y) / 2.0
		var pS: Vector2 = project.call(shoulder_x, shoulder_y)
		var pM: Vector2 = project.call(mid_x, mid_y)
		var pW: Vector2 = project.call(wrist_x, wrist_y)
		var aw: float = float(P["armHalf"]) * h
		draw_poly.call(PackedVector2Array([pS + Vector2(-aw, 0), pS + Vector2(aw, 0), pM + Vector2(aw * 0.88, 0), pM + Vector2(-aw * 0.88, 0)]), "arms")
		draw_poly.call(PackedVector2Array([pM + Vector2(-aw * 0.88, 0), pM + Vector2(aw * 0.88, 0), pW + Vector2(aw * 0.88, 0), pW + Vector2(-aw * 0.88, 0)]), "arms")
		var hand_r: float = float(P["handR"]) * h
		draw_circle(pW + Vector2(0, hand_r * 0.6 if prone else -hand_r * 0.6), hand_r, Palette.COLOURS["outline"] if tint_for.call("hands") == null else tint_for.call("hands") as Color)
	# torso
	var neck_half: float = float(P["neckHalf"]) * h
	var shoulder_half: float = float(P["shoulderHalf"]) * h
	var waist_half: float = float(P["waistHalf"]) * h
	var hip_half: float = float(P["hipHalf"]) * h
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
	draw_poly.call(poly, "torso")
	# head
	var head: Vector2 = project.call(0.0, up.call(P["headCentreY"]))
	var rx: float = float(P["headRx"]) * h
	var ry: float = float(P["headRy"]) * h
	if prone:
		var tmp: float = rx; rx = ry; ry = tmp
	draw_circle(head, (rx + ry) / 2.0, Palette.COLOURS["outline"] if tint_for.call("head") == null else tint_for.call("head") as Color)
	# prose below figure — posture hint only, no numbers cross the boundary (docs/05)
	if _view.has("parts"):
		var y: float = size.y - 28.0
		var label: String = "stand" if int(_view.get("stance", 2)) == 0 else ("crouch" if int(_view.get("stance", 2)) == 1 else "walk")
		# tint already encodes worst visibly; text only names posture
		draw_string(ThemeDB.fallback_font, Vector2(6, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.COLOURS["outline"])

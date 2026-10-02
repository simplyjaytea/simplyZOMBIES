extends Control
# The survivor's body, flat on, like a medical chart -- ten parts, each its own picture, stacked
# at one rect and each tinted by its own state.
#
# What this replaced was the same figure drawn live out of tapered capsules: a small elliptical
# head, a wide A-pose, limbs that were two cones and a circle. Asked to judge it at the size the
# inventory sheet draws it, the owner's word was **"too alien"**, and the call (docs/30, "The
# inventory sheet") was a pixel chart rather than a re-proportioned drawing. The shape of a person
# now lives in `tools/sprites/parts/paperdoll.py`, where it is authored once and regenerated under
# `npm run sprites:check`; this file decides only where it goes and what colour it comes out.
#
# **The art is a mask.** Every part is drawn near-white and multiplied by its state tint here, so
# a white pixel comes out as the tint exactly and a shaded one as a darker version of it. The
# shading is the file's and the meaning is the sim's -- which is what keeps `godot:ban:healthbar`
# true of a textured doll for the reason it was true of a drawn one: the picture cannot say how
# much, only which, because the only thing it is handed is a *state* and the art has no idea what
# one is.
#
# **Armour costs no art.** The same texture is drawn four times, a pixel out in each direction, in
# steel, with the part over the top: an outline pass on the part's own alpha. Thirty keys, not
# sixty.
#
# What has not changed: the ban this screen is held to (condition as four state tints, armour as
# an outer stroke, wounds and infection as marks, never a fill), the anonymity of the figure, and
# the stance word under it. `godot:ban:healthbar` never sees this file at all -- the doll reads
# `SimCondition.view` and nothing else, which is why that ban is mechanical on the read model
# rather than on the drawing.

const Palette = preload("res://presentation/palette.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Chrome = preload("res://ui/chrome.gd")
const SimStances = preload("res://sim/stances.gd")

enum OutlinePose { Stand = 0, Crouch = 1, Prone = 2 }
const POSE_NAMES: Array[String] = ["stand", "crouch", "prone"]

# The ten parts in the order they are stacked, back to front: legs and feet first, then the trunk
# over the top of the thighs, then the arms, the hands and the head. `parts/characters.py`'s
# `_figure` fixes the roster's draw order in one place for the same reason -- getting it wrong is
# not merely untidy, it is a hand behind a hip.
const DRAW_ORDER: Array[String] = [
	"leg_left", "leg_right", "foot_left", "foot_right",
	"torso",
	"arm_left", "arm_right", "hand_left", "hand_right",
	"head",
]

const BASE_FILL: Color = Color("#4d5546")
const ARMOUR_COL: Color = Color(0.55, 0.66, 0.78)
const LABEL_H: float = 26.0

var _view: Dictionary = {}
var _by_part: Dictionary = {}
var _mark_plan_cache: Dictionary = {}
var _armour_mask_cache: Dictionary = {}


func set_view(view: Dictionary) -> void:
	_view = view
	_by_part = {}
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		_by_part[String(d.get("part", ""))] = d
	queue_redraw()


func _pose_for_stance(stance: int) -> int:
	if stance == 0: return OutlinePose.Prone # Crawl
	if stance == 1: return OutlinePose.Crouch
	return OutlinePose.Stand


# The colour one part comes out as: its state's tint, or the drab base when it is unhurt. Four
# grades and a floor, exactly the four `Palette.CONDITION_TINTS` carries and the four
# `SimCondition.part_state` returns -- never a fraction, and there is no fifth value to have one.
func _tint_for(part: String) -> Color:
	var d: Variant = _by_part.get(part)
	if not (d is Dictionary):
		return BASE_FILL
	var st: int = int((d as Dictionary).get("state", 0))
	if st <= 0 or st >= Palette.CONDITION_TINTS.size():
		return BASE_FILL
	return Palette.CONDITION_TINTS[st] as Color


func _flag(part: String, key: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and bool((d as Dictionary).get(key, false))


func _infected(part: String) -> bool:
	var d: Variant = _by_part.get(part)
	return d is Dictionary and String((d as Dictionary).get("infected", "none")) != "none"


# Select a point and complete mark radius that fit inside the actual plate. This keeps the
# combined wound/infection mark usable on the narrow hand masks at both inventory scales.
func _chart_mark_plan(texture: Texture2D) -> Dictionary:
	var cache_key: int = texture.get_instance_id()
	if _mark_plan_cache.has(cache_key):
		return _mark_plan_cache[cache_key] as Dictionary
	var image: Image = texture.get_image().duplicate()
	var used: Rect2i = image.get_used_rect()
	var centre := Vector2(used.position) + Vector2(used.size) * 0.5
	for radius in [2.0, 1.5, 1.0]:
		var best := Vector2(-1.0, -1.0)
		var best_distance := INF
		for y in range(used.position.y, used.end.y):
			for x in range(used.position.x, used.end.x):
				if image.get_pixel(x, y).a <= 0.5:
					continue
				var fits := true
				for oy in range(-2, 3):
					for ox in range(-2, 3):
						if Vector2(ox, oy).length() > radius + 0.5:
							continue
						var px: Vector2i = Vector2i(x + ox, y + oy)
						if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height() or image.get_pixelv(px).a <= 0.5:
							fits = false
							break
					if not fits:
						break
				if fits and Vector2(x, y).distance_squared_to(centre) < best_distance:
					best = Vector2(x, y)
					best_distance = best.distance_squared_to(centre)
		if best.x >= 0.0:
			var plan := {"center": best, "radius": radius}
			_mark_plan_cache[cache_key] = plan
			return plan
	var empty_plan := {"center": centre, "radius": 0.0}
	_mark_plan_cache[cache_key] = empty_plan
	return empty_plan


func _armor_offsets(_scale: float) -> Array[Vector2]:
	# One screen pixel keeps the stroke visible without consuming the chart's native-pixel moat.
	return [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]


func _armor_mask(texture: Texture2D) -> Texture2D:
	# Armour is a steel silhouette stroke. Recolour every opaque source pixel before modulation so
	# the chart's intentionally dark inner outline cannot turn the outer stroke nearly black.
	var cache_key: int = texture.get_instance_id()
	if _armour_mask_cache.has(cache_key):
		return _armour_mask_cache[cache_key] as Texture2D
	var image: Image = texture.get_image().duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha: float = image.get_pixel(x, y).a
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var mask: Texture2D = ImageTexture.create_from_image(image)
	_armour_mask_cache[cache_key] = mask
	return mask


# Where the chart is drawn inside this control, and at what whole-number scale. Integer only: the
# art is pixels, and a chart at 1.7x is a chart with some rows twice as thick as others.
func _chart_rect() -> Rect2:
	var canvas: Vector2 = Vector2(Appearance.CHART_CANVAS)
	var room: Vector2 = Vector2(size.x, maxf(1.0, size.y - LABEL_H))
	var scale: float = maxf(1.0, floorf(minf(room.x / canvas.x, room.y / canvas.y)))
	var box: Vector2 = canvas * scale
	return Rect2(Vector2(roundf((size.x - box.x) / 2.0), roundf((room.y - box.y) / 2.0)), box)


func _draw() -> void:
	if _view.is_empty():
		return
	var pose: String = POSE_NAMES[_pose_for_stance(int(_view.get("stance", 2)))]
	var rect: Rect2 = _chart_rect()
	# The compact 2x glimpse sits above the always-on bottom key strip; the sheet's 3x chart keeps
	# its authored position. This is a drawing translation only, so both still use identical masks.
	var corner_shift: float = -76.0 if size.y < 400.0 else 0.0
	rect.position.y += corner_shift
	var scale: float = rect.size.x / float(Appearance.CHART_CANVAS.x)

	# A soft ground shadow under the figure, as before: it is what stops the chart floating.
	draw_set_transform(Vector2(rect.get_center().x, rect.position.y + rect.size.y - 4.0 * scale), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, rect.size.x * 0.30, Color(0.0, 0.0, 0.0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var marks: Array[Dictionary] = []
	for part in DRAW_ORDER:
		var key: String = Appearance.chart_key(part, pose)
		var texture: Texture2D = Appearance.resolve(key)
		if texture == null:
			continue
		# Armour first and underneath: the same picture nudged one pixel out in each direction, in
		# steel, so what shows is a ring around the part's own silhouette. No second sprite.
		if _flag(part, "armored"):
			var armour_mask: Texture2D = _armor_mask(texture)
			for step in _armor_offsets(scale):
				draw_texture_rect(armour_mask, Rect2(rect.position + step, rect.size), false, ARMOUR_COL)
		draw_texture_rect(texture, rect, false, _tint_for(part))
		if _flag(part, "wounded") or _infected(part):
			# Hung on the part's own opaque middle, read off the picture rather than off a table
			# of anchors -- a table would be a third copy of the skeleton and would drift the first
			# time a limb moved.
			var plan: Dictionary = _chart_mark_plan(texture)
			marks.append({
				"at": rect.position + (plan["center"] as Vector2) * scale,
				"radius": float(plan["radius"]) * scale,
				"wounded": _flag(part, "wounded"),
				"infected": _infected(part),
			})

	# The marks last, over every part, so a wound on a thigh is not painted over by the trunk.
	var backing: Color = Color(0.05, 0.055, 0.06)
	for mark in marks:
		var at: Vector2 = mark["at"] as Vector2
		var mark_r: float = float(mark["radius"])
		var stroke: float = maxf(1.0, scale * 0.45)
		if bool(mark["wounded"]):
			draw_circle(at, mark_r, backing)
			draw_circle(at, mark_r, Color(0.72, 0.24, 0.22), false, stroke)
		if bool(mark["infected"]):
			if bool(mark["wounded"]):
				draw_circle(at, maxf(1.0, mark_r * 0.35), Color(0.68, 0.82, 0.36))
			else:
				draw_circle(at, mark_r, backing)
				draw_circle(at, mark_r, Color(0.68, 0.82, 0.36), false, stroke)

	# Posture below the figure, in a word. No numbers cross the boundary (docs/05).
	var stance: int = int(_view.get("stance", SimStances.Stance.Walk))
	var label: String = SimStances.name_of(stance) if stance >= 0 and stance < SimStances.NAMES.size() else "walking"
	var font: Font = Chrome.font()
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Chrome.FONT_SIZE).x
	draw_string(font, Vector2(roundf(size.x / 2.0 - lw / 2.0), size.y - 6.0 + corner_shift), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Chrome.FONT_SIZE, Palette.COLOURS["outline"])

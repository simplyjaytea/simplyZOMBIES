extends RefCounted
# The overcast day (slice B5 of the three-features plan; docs/30, "Overcast or torchlight" and
# "The overcast day, as a grade"). Cool, desaturated daylight under a grey sky, with the night left
# exactly as the light map draws it, so the pools, the fire and the torch stay the one saturated
# thing after dark.
#
# It is a grade of the finished picture, not a regrade of the palette. Most of what is on screen is
# the outpost pack's own art -- the ground, the walls, the props, the pawns -- which no palette entry
# reaches, so a palette regrade would cool the generated half of the street and leave the pack half
# warm. One screen-space pass treats both halves alike, follows the phase every frame without a
# rebake, and leaves every source table (and the lanes that pin them) where it is.
#
# One RenderingServer canvas item, a child of main's own like the light map's two, at GRADE_INDEX:
# after every command main issues in `_draw`, before the night's multiply (LightMap.DARK_INDEX) and
# the glow over it, and under the HUD's CanvasLayer. So the grade sees the district and the bodies,
# the night darkens and tints the graded picture (a pool's hue is laid on after the grade, never
# washed out by it), a flash or a flame in the glow is light and is never graded, and no panel,
# label or chip of the HUD is in the picture the shader reads.
#
# `grade` below is the shader's arithmetic on a Color, step for step. check_grade_look.gd judges
# the palette through it, and holds the shader's text to the same steps.

const Clock = preload("res://sim/time/clock.gd")
const GradeShader = preload("res://presentation/day_grade.gdshader")

const GRADE_INDEX: int = 999

# The share of a colour's distance from its own grey that a full day keeps: SATURATION in the lit
# middle and top, SHADOW_SATURATION in the darks, eased between over luma 0 to SHADOW_LUMA. Under a
# grey sky a shadow has no colour of its own to speak of, and the void -- the blue-black the
# district sat in -- goes to a dark grey on this rather than on a palette change.
const SATURATION: float = 0.68
const SHADOW_SATURATION: float = 0.2
const SHADOW_LUMA: float = 0.25
# The cool cast: a gain per channel, red down a little and blue up a little.
const COOL: Color = Color(0.97, 1.0, 1.03)
# The overcast sky's grey, and how far toward it every pixel is veiled: lifts the darks, takes the
# top off the brightest pack colours, and is near neutral so the cool comes from COOL alone.
const HAZE: Color = Color("#5c5e60")
const HAZE_AMOUNT: float = 0.1

var _parent: RID
var _item: RID
var _material: ShaderMaterial = null
var _attached: bool = false

# Read by the look gates and the frame bench: whether the last frame graded, and by how much.
var drew: bool = false
var last_weight: float = 0.0

# Static so a gate can draw the same frame with the grade off and compare. Never changed in a
# running game.
static var enabled: bool = true


# How much of the grade a frame takes from the sky's share of daylight (Clock.ambient_light):
# all of it under a full day's sky, none at night, eased through dawn and dusk.
static func weight_of(ambient: float) -> float:
	return smoothstep(Clock.NIGHT_AMBIENT, 1.0, ambient)


# The shader's three steps on one colour, in sRGB as the shader reads the screen: toward its own
# grey, the cool gain, the veil. `weight` 0 returns the colour unchanged.
static func grade(c: Color, weight: float) -> Color:
	var luma: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var keep: float = lerpf(SHADOW_SATURATION, SATURATION, smoothstep(0.0, SHADOW_LUMA, luma))
	var g := Vector3(lerpf(luma, c.r, keep), lerpf(luma, c.g, keep), lerpf(luma, c.b, keep))
	g = Vector3(clampf(g.x * COOL.r, 0.0, 1.0), clampf(g.y * COOL.g, 0.0, 1.0), clampf(g.z * COOL.b, 0.0, 1.0))
	g = Vector3(lerpf(g.x, HAZE.r, HAZE_AMOUNT), lerpf(g.y, HAZE.g, HAZE_AMOUNT), lerpf(g.z, HAZE.b, HAZE_AMOUNT))
	return Color(lerpf(c.r, g.x, weight), lerpf(c.g, g.y, weight), lerpf(c.b, g.z, weight), c.a)


func attach(parent: RID) -> void:
	if _attached:
		return
	_parent = parent
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, _parent)
	RenderingServer.canvas_item_set_draw_index(_item, GRADE_INDEX)
	_material = ShaderMaterial.new()
	_material.shader = GradeShader
	_material.set_shader_parameter("saturation", SATURATION)
	_material.set_shader_parameter("shadow_saturation", SHADOW_SATURATION)
	_material.set_shader_parameter("shadow_luma", SHADOW_LUMA)
	_material.set_shader_parameter("cool", Vector3(COOL.r, COOL.g, COOL.b))
	_material.set_shader_parameter("haze", Vector3(HAZE.r, HAZE.g, HAZE.b))
	_material.set_shader_parameter("haze_amount", HAZE_AMOUNT)
	RenderingServer.canvas_item_set_material(_item, _material.get_rid())
	_attached = true


func detach() -> void:
	if not _attached:
		return
	RenderingServer.free_rid(_item)
	_material = null
	_attached = false


# The grade for this frame: one rect over the viewport at the phase's weight, or nothing at all at
# night (weight 0), so a night frame costs no screen read and is exactly the light map's picture.
func frame(viewport: Vector2, ambient: float) -> void:
	if not _attached:
		return
	RenderingServer.canvas_item_clear(_item)
	last_weight = weight_of(ambient) if enabled else 0.0
	drew = last_weight > 0.0
	if not drew:
		return
	_material.set_shader_parameter("weight", last_weight)
	RenderingServer.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, viewport), Color.WHITE)

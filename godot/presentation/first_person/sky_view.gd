extends Node3D
# Day, night, weather and carried light for the first-person scene, read from the sim. Presentation
# only: nothing here writes a component or decides what the player can see.
#
# The sim owns the sky's share of daylight (`SimClock.ambient_light_at`), the weather kind
# (`SimWeather.kind`), fog's sight multiplier (`SimWeather.sight_mul`) and every carried lamp
# (`SimLightModule.carried_magnitude` / `brightest_carried` / `beam_of`). This file reads those and
# dresses a WorldEnvironment, one DirectionalLight3D and the eye's own light. Bodies are still drawn
# only where `world.vision.detail` says they are seen (`body_view.gd`); a torch never reveals one.
#
# The look follows `day_grade.gd` in intent rather than in mechanism: muted, cool, overcast by day,
# and the night left dark and unsaturated, with the torch the one warm thing in it.

const Clock = preload("res://sim/time/clock.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimLightMod = preload("res://sim/modules/light.gd")

# --- PRESENTATION TUNING (not sim values; change them here and nowhere else) ----------------
# Sun and ambient at full day and at the night's 0.04 daylight share, before the overcast and
# weather multipliers. Night values are low on purpose: unlit geometry beyond the sim's sight must
# not stay readable after dark.
const SUN_ENERGY_DAY: float = 1.05
const SUN_ENERGY_NIGHT: float = 0.0
const AMBIENT_ENERGY_DAY: float = 1.0
const AMBIENT_ENERGY_NIGHT: float = 0.06
const SUN_COLOUR_DAY: Color = Color(0.94, 0.96, 1.0)
const SUN_COLOUR_NIGHT: Color = Color(0.35, 0.42, 0.58)
const AMBIENT_COLOUR_DAY: Color = Color(0.64, 0.68, 0.72)
const AMBIENT_COLOUR_NIGHT: Color = Color(0.12, 0.16, 0.24)
const SKY_COLOUR_DAY: Color = Color(0.46, 0.49, 0.51)
const SKY_COLOUR_NIGHT: Color = Color(0.015, 0.02, 0.035)
# The overcast grade: the same muted day `day_grade.gd` paints in 2D. The saturation is eased in by
# the sky's share of daylight, so night keeps the lamp's colour.
const OVERCAST_SATURATION: float = 0.72
const OVERCAST_CONTRAST: float = 1.02
const OVERCAST_SUN_MUL: float = 0.78
# Rain and storm darken the grade; snow, cold and heat keep the clear sky. No particles: the sim's
# weather is read, not re-enacted.
const RAIN_SUN_MUL: float = 0.55
const RAIN_AMBIENT_MUL: float = 0.62
const RAIN_SKY_DARKEN: float = 0.55
# Fog's distance comes from the sim's own sight multiplier: `fog` says 0.25, so a clear 30 m is
# 7.5 m under it. Depth fog is cheap and needs no volumetric pass.
const FOG_DEPTH_BEGIN_M: float = 1.0
const FOG_CLEAR_SIGHT_M: float = 30.0
const FOG_LIGHT_ENERGY: float = 0.7
# The eye light: one spot or one omni, no shadows. The range and the cone are the sim's; the energy
# and the anchor are presentation.
const EYE_LIGHT_ENERGY: float = 2.2
const EYE_LIGHT_POSITION: Vector3 = Vector3(0.10, -0.06, 0.0)
const EYE_LIGHT_MAX_RANGE_M: float = 90.0
const EYE_LIGHT_FALLBACK_COLOUR: Color = Color(1.0, 0.86, 0.62)

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _spot: SpotLight3D = null
var _omni: OmniLight3D = null
var _sun_energy: float = 0.0
var _ambient_energy: float = 0.0
var _eye_on: bool = false
var _eye_range: float = 0.0
var _eye_angle_degrees: float = 0.0
var _eye_is_spot: bool = false
var _kind: String = SimWeather.CLEAR
var _fog_on: bool = false


func build(camera: Camera3D) -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = SKY_COLOUR_DAY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT_COLOUR_DAY
	_env.ambient_light_energy = AMBIENT_ENERGY_DAY
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = OVERCAST_CONTRAST
	_env.adjustment_saturation = OVERCAST_SATURATION
	_env.fog_enabled = false
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = FOG_DEPTH_BEGIN_M
	_env.fog_depth_end = FOG_CLEAR_SIGHT_M
	_env.fog_light_color = SKY_COLOUR_DAY
	_env.fog_light_energy = FOG_LIGHT_ENERGY
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "World"
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	_sun.light_energy = SUN_ENERGY_DAY
	_sun.shadow_enabled = false
	add_child(_sun)

	_spot = SpotLight3D.new()
	_spot.name = "EyeLightSpot"
	_spot.position = EYE_LIGHT_POSITION
	_spot.light_energy = EYE_LIGHT_ENERGY
	_spot.spot_range = 1.0
	_spot.spot_angle = 22.0
	_spot.shadow_enabled = false
	_spot.visible = false
	_omni = OmniLight3D.new()
	_omni.name = "EyeLightRound"
	_omni.position = EYE_LIGHT_POSITION
	_omni.light_energy = EYE_LIGHT_ENERGY
	_omni.omni_range = 1.0
	_omni.shadow_enabled = false
	_omni.visible = false
	if camera != null:
		# A child of the eye, pointing along its -Z: the beam leaves the look, not a modelled hand.
		camera.add_child(_spot)
		camera.add_child(_omni)


## Read the sim and dress the sky for this frame.
func update(world: Variant) -> void:
	if world == null or _env == null:
		return
	var daylight: float = clampf(Clock.ambient_light_at(int(world.tick)), 0.0, 1.0)
	var kind: String = SimWeather.kind(world)
	var raining: bool = SimWeather.raining(world)
	var grade_weight: float = smoothstep(Clock.NIGHT_AMBIENT, 1.0, daylight)
	var sun_mul: float = OVERCAST_SUN_MUL
	var ambient_mul: float = 1.0
	if raining:
		sun_mul *= RAIN_SUN_MUL
		ambient_mul = RAIN_AMBIENT_MUL
	_sun_energy = lerpf(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, daylight) * sun_mul
	_ambient_energy = lerpf(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, daylight) * ambient_mul
	_sun.light_energy = _sun_energy
	_sun.light_color = SUN_COLOUR_NIGHT.lerp(SUN_COLOUR_DAY, daylight)
	_env.ambient_light_energy = _ambient_energy
	_env.ambient_light_color = AMBIENT_COLOUR_NIGHT.lerp(AMBIENT_COLOUR_DAY, daylight)
	var sky: Color = SKY_COLOUR_NIGHT.lerp(SKY_COLOUR_DAY, daylight)
	if raining:
		sky = sky.darkened(RAIN_SKY_DARKEN)
	_env.background_color = sky
	_env.adjustment_saturation = lerpf(1.0, OVERCAST_SATURATION, grade_weight)
	_env.adjustment_contrast = lerpf(1.0, OVERCAST_CONTRAST, grade_weight)
	var foggy: bool = kind == "fog"
	_env.fog_enabled = foggy
	if foggy:
		_env.fog_light_color = sky
		_env.fog_depth_begin = FOG_DEPTH_BEGIN_M
		_env.fog_depth_end = FOG_CLEAR_SIGHT_M * clampf(SimWeather.sight_mul(world), 0.05, 1.0)
	_kind = kind
	_fog_on = foggy
	_update_eye_light(world)


## The eye's light is whatever the sim says is lit and carried: the brightest item in the four
## light slots, its magnitude as the range and its `beam` as the cone. A round light is an omni at
## the eye; a beam is a spot along the look. Off when the sim has removed `light_source` (nothing
## lit, or the wick burnt out), and off for a corpse and the end panel.
func _update_eye_light(world: Variant) -> void:
	_eye_on = false
	_eye_range = 0.0
	_eye_angle_degrees = 0.0
	_eye_is_spot = false
	_spot.visible = false
	_omni.visible = false
	var player: int = int(world.player)
	if bool(world.runOver) or world.components.has_component(player, "corpse"):
		return
	var magnitude: float = SimLightMod.carried_magnitude(world, player)
	if magnitude <= 0.0:
		return
	var pick: Dictionary = SimLightMod.brightest_carried(world, player)
	var item: int = int(pick.get("item", -1))
	var beam: float = SimLightMod.beam_of(world, item)
	var colour: Color = EYE_LIGHT_FALLBACK_COLOUR
	var block: Variant = SimLightMod.light_block_of(world, item)
	if block is Dictionary and String((block as Dictionary).get("tint", "")) != "":
		colour = Color(String((block as Dictionary)["tint"]))
	_eye_on = true
	_eye_range = clampf(magnitude, 1.0, EYE_LIGHT_MAX_RANGE_M)
	if beam > 0.0:
		_eye_is_spot = true
		_eye_angle_degrees = rad_to_deg(clampf(beam, 0.05, SimLightMod.BEAM_CAP_RAD))
		_spot.light_color = colour
		_spot.spot_range = _eye_range
		_spot.spot_angle = _eye_angle_degrees
		_spot.visible = true
	else:
		_omni.light_color = colour
		_omni.omni_range = _eye_range
		_omni.visible = true


func sun_energy() -> float:
	return _sun_energy


func ambient_energy() -> float:
	return _ambient_energy


func eye_light_on() -> bool:
	return _eye_on


func eye_light_range() -> float:
	return _eye_range


func eye_light_angle_degrees() -> float:
	return _eye_angle_degrees


func eye_light_is_spot() -> bool:
	return _eye_is_spot


func weather_kind() -> String:
	return _kind


func fog_enabled() -> bool:
	return _fog_on

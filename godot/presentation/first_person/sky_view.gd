extends Node3D
# Day, night, weather, air and carried light for the first-person scene, read from the sim. Presentation
# only: nothing here writes a component or decides what the player can see.
#
# The sim owns the sky's share of daylight (`SimClock.ambient_light_at`), the hour (`SimClock.time_of_day`),
# the weather kind (`SimWeather.kind`), fog's sight multiplier (`SimWeather.sight_mul`) and every carried lamp
# (`SimLightModule.carried_magnitude` / `brightest_carried` / `beam_of`). This file reads those and dresses a
# WorldEnvironment with a drawn sky (`sky.gdshader`), the sun (a DirectionalLight3D that casts shadows and
# moves with the clock), the night sky's faint share of light after dark (a second, shadowless one), the
# air's haze, a grade (`grade.gdshader`) and the eye's own light.
# Bodies are still drawn only where `world.vision.detail` says they are seen (`body_view.gd`); a torch never
# reveals one, and a body's shadow leaves with its node.
#
# The look is docs/46: quiet, cool and low in chroma by day, the dusk and dawn carrying the colour script's
# bands, and the night left dark, with the torch the one warm thing in it. `sky_state` is the whole look as a
# pure function of the sim's five readings, so a gate can ask it what a given hour and weather look like.
#
# Renderer: Compatibility (GLES3, WebGL2). Everything here was run on it: a sky shader as the background,
# depth fog, one shadowed directional light, the filmic tonemap and one blended full-screen quad.
#
# One thing about that renderer shapes every energy below. It draws a directional light that casts shadows
# in a pass of its own and adds that pass to the picture after the tonemap and the sRGB curve, so the sun is
# added to the ambient in display space, not in linear light (measured: ambient 0.12 and sun 0.18 on a white
# floor give 0.84, the sum of the two encoded, not the 0.58 of their linear sum). A light without shadows is
# in the first pass and adds in linear light. So the sun and the ambient are tuned as two display-space
# layers, the contrast adjustment stays at exactly 1 (it would be applied to each pass), and the night's
# light is a second, shadowless light: near black the two passes round to nothing separately.

const Clock = preload("res://sim/time/clock.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SKY_SHADER: Shader = preload("res://presentation/first_person/sky.gdshader")
const GRADE_SHADER: Shader = preload("res://presentation/first_person/grade.gdshader")

# --- PRESENTATION TUNING (not sim values; change them here and nowhere else) ----------------
# Colours are sRGB, as docs/46's colour script writes them.
#
# The clear sky through the day: [day fraction, zenith, middle, horizon]. The sim's day starts at dawn
# (fraction 0), is full day from 0.125 to 0.625, dusk to 0.75 and night after. Rows are read in order and
# the last wraps to the first.
const CLEAR_SKY_KEYS: Array = [
	[0.000, Color("1a2234"), Color("3d4257"), Color("7a6c74")],
	[0.060, Color("56627a"), Color("9a94a2"), Color("d3b8a8")],
	[0.125, Color("6585a8"), Color("a3b6c6"), Color("cdd0cf")],
	[0.200, Color("6f8fb4"), Color("9cb2c6"), Color("c3cfd4")],
	[0.550, Color("6f8fb4"), Color("9cb2c6"), Color("c3cfd4")],
	[0.640, Color("5d7aa2"), Color("9a9fb0"), Color("d9c3a4")],
	[0.700, Color("2b3350"), Color("6e6a86"), Color("d99a72")],
	[0.750, Color("10162a"), Color("2b2c44"), Color("5e4446")],
	[0.800, Color("05070c"), Color("080b12"), Color("0b1018")],
	[0.960, Color("05070c"), Color("080b12"), Color("0b1018")],
]
# Where the middle stop sits (sine of the elevation): low by day, higher when the horizon band is the picture.
const SKY_MIDDLE_HEIGHT_DAY: float = 0.30
const SKY_MIDDLE_HEIGHT_LOW_SUN: float = 0.22
# The overcast deck at full day, and the night it falls back to. A deck keeps a little of the hour's own hue.
const DECK_ZENITH: Color = Color("8e979c")
const DECK_HORIZON: Color = Color("c4c8c6")
const DECK_NIGHT_ZENITH: Color = Color("040508")
const DECK_NIGHT_HORIZON: Color = Color("090c11")
const DECK_HOUR_TINT: float = 0.16
# Fog weather is a wall of this colour by day.
const FOG_WALL_COLOUR: Color = Color("c6c9c7")
const FOG_WALL_NIGHT: Color = Color("090c11")

# The sun's arc: up at fraction 0 in the east, highest in the south, down at SUN_SET_FRACTION in the west.
const SUN_SET_FRACTION: float = 0.75
const SUN_NOON_ELEVATION_DEG: float = 45.0
# The light never rakes lower than this, so a dusk shadow is long and not endless.
const SUN_LIGHT_MIN_ELEVATION_DEG: float = 11.0
const SUN_COLOUR_DAY: Color = Color("fff2dc")
const SUN_COLOUR_DUSK: Color = Color("ffb070")
const SUN_COLOUR_DAWN: Color = Color("ffd2b4")
# The sun is its low colour under the first elevation and its day colour over the second.
const SUN_LOW_BELOW_DEG: float = 7.0
const SUN_DAY_ABOVE_DEG: float = 30.0
const SUN_COLOUR_OVERCAST: Color = Color("eef1f4")
# After dark a second, shadowless light is the night sky's share: faint, cold, from high up, with no sun or
# moon in the sky. Kept under the LIGHT lane's 0.05, and sized with the night ambient so the ground and the
# walls come out as dark as they were before the sun moved (the tonemap's toe takes a quarter off).
const NIGHT_LIGHT_ENERGY: float = 0.034
const NIGHT_LIGHT_COLOUR: Color = Color(0.37, 0.44, 0.60)
const NIGHT_LIGHT_ELEVATION_DEG: float = 70.0
const NIGHT_LIGHT_AZIMUTH_DEG: float = 124.0
const NIGHT_LIGHT_FADE_FRACTION: float = 0.03
# Sun and ambient at full day under a clear sky. The ambient's colour follows the sky: a share of the zenith
# in the horizon, part desaturated, scaled so its brightest channel is AMBIENT_TINT_VALUE.
const SUN_ENERGY_DAY: float = 0.52
const AMBIENT_ENERGY_DAY: float = 0.60
const AMBIENT_ENERGY_NIGHT: float = 0.118
const AMBIENT_COLOUR_NIGHT: Color = Color(0.141, 0.181, 0.259)
const AMBIENT_ZENITH_SHARE: float = 0.6
const AMBIENT_DESATURATE: float = 0.5
const AMBIENT_TINT_VALUE: float = 0.68

# The sun's shadows. One shadowed directional light; the atlas and the filter are set once at build.
const SHADOW_ATLAS_SIZE: int = 4096
const SHADOW_MAX_DISTANCE_M: float = 70.0
const SHADOW_SPLIT_1: float = 0.14
const SHADOW_SPLIT_2: float = 0.38
const SHADOW_FADE_START: float = 0.85
const SHADOW_BIAS: float = 0.12
const SHADOW_NORMAL_BIAS: float = 2.0
const SHADOW_BLUR: float = 1.0
const SHADOW_PANCAKE_M: float = 40.0

# What each weather looks like. `SKY_OF_KIND` names a look per sim weather kind; a kind it does not name is
# `deck` when the sim says it wets and `clear` otherwise.
#   deck          0 keeps the clear sky, 1 is the overcast deck
#   deck_shade    multiplies the deck's colours (rain and storm darken it, snow lifts it)
#   wall          1 turns the whole sky into the fog wall
#   cloud_cover   share of the sky under the cloud layer; cloud_amount its opacity; cloud_mottle how far it
#                 lightens and darkens the deck; cloud_scale the size of its shapes (smaller is a lower deck);
#                 cloud_drift its speed against CLOUD_DRIFT_PER_TICK; cloud_shade darkens the cloud itself
#   sun_disc, sun_glow   the sun in the sky
#   sun_mul, ambient_mul the light against a clear day
#   shadow        the sun shadow's opacity
#   haze_end_m, haze_max the air: full haze distance and the most it takes
#   ridges        how much of the far ridges the air leaves
#   stars         0 or 1
const SKY_LOOKS: Dictionary = {
	"clear": {
		"deck": 0.0, "deck_shade": 1.0, "wall": 0.0,
		"cloud_cover": 0.24, "cloud_amount": 0.60, "cloud_mottle": 0.02, "cloud_scale": 0.30, "cloud_drift": 1.0, "cloud_shade": 0.0,
		"sun_disc": 1.0, "sun_glow": 0.22, "sun_mul": 1.0, "ambient_mul": 1.0, "shadow": 0.85,
		"haze_end_m": 200.0, "haze_max": 0.90, "ridges": 1.0, "stars": 1.0,
	},
	"cold": {
		"deck": 0.0, "deck_shade": 1.0, "wall": 0.0,
		"cloud_cover": 0.18, "cloud_amount": 0.40, "cloud_mottle": 0.02, "cloud_scale": 0.34, "cloud_drift": 1.4, "cloud_shade": 0.0,
		"sun_disc": 1.0, "sun_glow": 0.16, "sun_mul": 1.0, "ambient_mul": 0.96, "shadow": 0.88,
		"haze_end_m": 240.0, "haze_max": 0.86, "ridges": 1.0, "stars": 1.0,
	},
	"heat": {
		"deck": 0.22, "deck_shade": 1.10, "wall": 0.0,
		"cloud_cover": 0.24, "cloud_amount": 0.35, "cloud_mottle": 0.02, "cloud_scale": 0.30, "cloud_drift": 0.5, "cloud_shade": 0.0,
		"sun_disc": 1.0, "sun_glow": 0.42, "sun_mul": 1.05, "ambient_mul": 1.04, "shadow": 0.80,
		"haze_end_m": 170.0, "haze_max": 0.92, "ridges": 0.7, "stars": 1.0,
	},
	"deck": {
		"deck": 1.0, "deck_shade": 0.84, "wall": 0.0,
		"cloud_cover": 0.52, "cloud_amount": 0.55, "cloud_mottle": 0.07, "cloud_scale": 0.22, "cloud_drift": 2.0, "cloud_shade": 0.55,
		"sun_disc": 0.0, "sun_glow": 0.05, "sun_mul": 0.50, "ambient_mul": 1.15, "shadow": 0.30,
		"haze_end_m": 150.0, "haze_max": 0.93, "ridges": 0.5, "stars": 0.0,
	},
	"storm": {
		"deck": 1.0, "deck_shade": 0.56, "wall": 0.0,
		"cloud_cover": 0.68, "cloud_amount": 0.70, "cloud_mottle": 0.12, "cloud_scale": 0.18, "cloud_drift": 4.0, "cloud_shade": 0.75,
		"sun_disc": 0.0, "sun_glow": 0.0, "sun_mul": 0.32, "ambient_mul": 0.80, "shadow": 0.20,
		"haze_end_m": 120.0, "haze_max": 0.95, "ridges": 0.25, "stars": 0.0,
	},
	"snow": {
		"deck": 1.0, "deck_shade": 1.10, "wall": 0.0,
		"cloud_cover": 0.30, "cloud_amount": 0.20, "cloud_mottle": 0.03, "cloud_scale": 0.26, "cloud_drift": 0.8, "cloud_shade": 0.25,
		"sun_disc": 0.0, "sun_glow": 0.04, "sun_mul": 0.50, "ambient_mul": 1.25, "shadow": 0.25,
		"haze_end_m": 120.0, "haze_max": 0.95, "ridges": 0.3, "stars": 0.0,
	},
	"fog": {
		"deck": 1.0, "deck_shade": 1.0, "wall": 1.0,
		"cloud_cover": 0.0, "cloud_amount": 0.0, "cloud_mottle": 0.0, "cloud_scale": 0.30, "cloud_drift": 0.0, "cloud_shade": 0.0,
		"sun_disc": 0.0, "sun_glow": 0.05, "sun_mul": 0.45, "ambient_mul": 1.15, "shadow": 0.12,
		"haze_end_m": 120.0, "haze_max": 0.95, "ridges": 0.0, "stars": 0.0,
	},
}
const SKY_OF_KIND: Dictionary = {
	"clear": "clear", "cold_snap": "cold", "heat_wave": "heat", "rain": "deck", "storm": "storm", "snow": "snow", "fog": "fog",
}
# The cloud layer: a tiling noise built once from a fixed seed, drifting by the sim's tick.
const CLOUD_NOISE_SIZE: int = 256
const CLOUD_NOISE_SEED: int = 4601
const CLOUD_NOISE_FREQUENCY: float = 0.011
const CLOUD_NOISE_OCTAVES: int = 4
const CLOUD_DRIFT_PER_TICK: Vector2 = Vector2(0.000055, 0.000021)
const CLOUD_LIGHT_LIFT: float = 0.45
const CLOUD_DARK_DROP: float = 0.12
# The warm band on the sun's side of the horizon and the wider glow, at their most when the sun is low.
const HORIZON_GLOW_LOW_SUN: float = 0.55
const SUN_GLOW_LOW_SUN: float = 0.30
const STAR_BRIGHTNESS: float = 0.55
# The far ridges in the sky: cedar seen through more and more air. The three figures are how much of the
# horizon's colour each has taken, nearest first; at dawn the mist at their feet is at its thickest.
const RIDGE_COLOUR_DAY: Color = Color("2f4337")
const RIDGE_COLOUR_NIGHT: Color = Color("020304")
const RIDGE_HAZE: Array[float] = [0.50, 0.66, 0.80]
const RIDGE_MIST_DAY: float = 0.70
const RIDGE_MIST_DAWN: float = 0.95
# The ridges and the haze take their colour from the horizon with this share of the sky's middle stop in it,
# so a dusk's far side is mauve and not the sun's orange.
const AIR_MIDDLE_SHARE: float = 0.40
# Under the horizon the sky is the valley floor seen through the air: the horizon with this much of the
# ridges' dark in it.
const BELOW_HORIZON_SHADE: float = 0.55
# The ambient keeps more of itself than the sun does while the daylight falls: the sky stays lit after the
# ground has lost the sun. 1 follows the sim's daylight exactly; lower holds the ambient up at dusk and dawn.
const AMBIENT_DAYLIGHT_CURVE: float = 0.6

# The air. By day a thin haze in the horizon's colour: none inside HAZE_BEGIN_M, the look's `haze_max` from
# its `haze_end_m` on, so a clear noon takes about two thirds of the far side of the district (128 m). It
# thickens at dawn and leaves with the daylight, so the night's ground is not lit by it.
const HAZE_BEGIN_M: float = 4.0
const HAZE_CURVE: float = 0.85
const HAZE_DAWN_END_MUL: float = 0.55
const HAZE_DAWN_UNTIL_FRACTION: float = 0.16
# Fog weather's distance comes from the sim's own sight multiplier: `fog` says 0.25, so a clear 30 m is
# 7.5 m under it. Depth fog is cheap and needs no volumetric pass.
const FOG_DEPTH_BEGIN_M: float = 1.0
const FOG_CLEAR_SIGHT_M: float = 30.0

# The grade: a gentle filmic curve, a little saturation taken out by day (the night keeps the lamp's colour),
# and one full-screen quad under the HUD that only ever darkens: a light vignette and fine grain.
const TONEMAP_MODE: int = Environment.TONE_MAPPER_FILMIC
const TONEMAP_EXPOSURE: float = 1.0
const TONEMAP_WHITE: float = 6.0
const GRADE_SATURATION_DAY: float = 0.90
const VIGNETTE_STRENGTH: float = 0.20
const VIGNETTE_INNER: float = 0.62
const VIGNETTE_OUTER: float = 1.18
const GRAIN_STRENGTH: float = 0.035
const GRADE_CANVAS_LAYER: int = -1

# The eye light: one spot or one omni, no shadows. The range and the cone are the sim's; the energy
# and the anchor are presentation.
const EYE_LIGHT_ENERGY: float = 2.2
const EYE_LIGHT_POSITION: Vector3 = Vector3(0.10, -0.06, 0.0)
const EYE_LIGHT_MAX_RANGE_M: float = 90.0
const EYE_LIGHT_FALLBACK_COLOUR: Color = Color(1.0, 0.86, 0.62)
# --- end of PRESENTATION TUNING -------------------------------------------------------------

# The state keys of `sky_state` the sky shader takes, and the uniform each one sets.
const SKY_UNIFORMS: Dictionary = {
	"zenith": "zenith_colour", "middle": "middle_colour", "horizon": "horizon_colour", "below": "below_colour",
	"middle_height": "middle_height", "sun_direction": "sun_direction", "sun_colour": "sun_colour",
	"sun_disc": "sun_disc", "sun_glow": "sun_glow", "horizon_glow": "horizon_glow",
	"cloud_cover": "cloud_cover", "cloud_amount": "cloud_amount", "cloud_mottle": "cloud_mottle",
	"cloud_scale": "cloud_scale", "cloud_light": "cloud_light", "cloud_dark": "cloud_dark",
	"star_amount": "star_amount", "ridge_amount": "ridge_amount", "ridge_near": "ridge_near",
	"ridge_mid": "ridge_mid", "ridge_far": "ridge_far", "ridge_mist": "ridge_mist",
}

var _env: Environment = null
var _sky_material: ShaderMaterial = null
var _grade_material: ShaderMaterial = null
var _sun: DirectionalLight3D = null
var _night: DirectionalLight3D = null
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
var _haze_on: bool = false
var _state: Dictionary = {}


func build(camera: Camera3D) -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("cloud_noise", _cloud_noise())
	var sky: Sky = Sky.new()
	sky.sky_material = _sky_material
	# Nothing reads the sky's radiance (the ambient is a colour and reflections are off), so the smallest
	# map there is and no update of it.
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT_COLOUR_NIGHT
	_env.ambient_light_energy = AMBIENT_ENERGY_DAY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = TONEMAP_MODE
	_env.tonemap_exposure = TONEMAP_EXPOSURE
	_env.tonemap_white = TONEMAP_WHITE
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.0
	_env.adjustment_saturation = GRADE_SATURATION_DAY
	_env.fog_enabled = false
	# Setting the depth mode makes `fog_density` the most the fog takes (1.0 until `update` says otherwise).
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = HAZE_BEGIN_M
	_env.fog_depth_end = FOG_CLEAR_SIGHT_M
	_env.fog_light_energy = 1.0
	_env.fog_sun_scatter = 0.0
	# The sky draws its own horizon in the haze's colour; the fog leaves it alone.
	_env.fog_sky_affect = 0.0
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "World"
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = SUN_ENERGY_DAY
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE_M
	_sun.directional_shadow_split_1 = SHADOW_SPLIT_1
	_sun.directional_shadow_split_2 = SHADOW_SPLIT_2
	_sun.directional_shadow_fade_start = SHADOW_FADE_START
	_sun.directional_shadow_pancake_size = SHADOW_PANCAKE_M
	_sun.directional_shadow_blend_splits = false
	_sun.shadow_bias = SHADOW_BIAS
	_sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
	_sun.shadow_blur = SHADOW_BLUR
	add_child(_sun)
	_night = DirectionalLight3D.new()
	_night.name = "NightSky"
	_night.light_energy = 0.0
	_night.light_color = NIGHT_LIGHT_COLOUR
	_night.shadow_enabled = false
	_night.visible = false
	add_child(_night)
	_night.look_at_from_position(Vector3.ZERO, -_direction(NIGHT_LIGHT_AZIMUTH_DEG, NIGHT_LIGHT_ELEVATION_DEG), Vector3.UP)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZE, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)

	# The grade's quad sits under every other canvas layer, so the HUD is drawn over it and is not graded.
	_grade_material = ShaderMaterial.new()
	_grade_material.shader = GRADE_SHADER
	_grade_material.set_shader_parameter("vignette_strength", VIGNETTE_STRENGTH)
	_grade_material.set_shader_parameter("vignette_inner", VIGNETTE_INNER)
	_grade_material.set_shader_parameter("vignette_outer", VIGNETTE_OUTER)
	_grade_material.set_shader_parameter("grain_strength", GRAIN_STRENGTH)
	var grade_layer: CanvasLayer = CanvasLayer.new()
	grade_layer.name = "Grade"
	grade_layer.layer = GRADE_CANVAS_LAYER
	add_child(grade_layer)
	var grade_rect: ColorRect = ColorRect.new()
	grade_rect.name = "Lens"
	grade_rect.material = _grade_material
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_layer.add_child(grade_rect)
	grade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
	var tick: int = int(world.tick)
	var daylight: float = clampf(Clock.ambient_light_at(tick), 0.0, 1.0)
	var kind: String = SimWeather.kind(world)
	_state = sky_state(Clock.time_of_day(tick), daylight, kind, SimWeather.raining(world), SimWeather.sight_mul(world))
	_apply(_state, tick)
	_kind = kind
	_update_eye_light(world)


## The whole look of one moment, from the sim's five readings and nothing else: the day fraction, the sky's
## share of daylight, the weather kind, whether it wets, and fog's sight multiplier. Pure and deterministic.
static func sky_state(fraction: float, daylight: float, kind: String, raining: bool, sight_mul: float) -> Dictionary:
	var look: Dictionary = SKY_LOOKS[look_of(kind, raining)] as Dictionary
	var day_weight: float = clampf((daylight - Clock.NIGHT_AMBIENT) / (1.0 - Clock.NIGHT_AMBIENT), 0.0, 1.0)
	var deck: float = float(look["deck"])
	var wall: float = float(look["wall"])
	var elevation: float = sun_elevation_deg(fraction)
	var low_sun: float = (1.0 - smoothstep(SUN_LOW_BELOW_DEG, SUN_DAY_ABOVE_DEG, elevation)) * smoothstep(-6.0, 2.0, elevation)

	# The sky's three stops: the clear sky of the hour, under the deck, behind the wall.
	var clear: Array = _clear_sky_at(fraction)
	var shade: float = float(look["deck_shade"])
	var deck_zenith: Color = DECK_NIGHT_ZENITH.lerp(_scaled(DECK_ZENITH, shade), day_weight).lerp(clear[0] as Color, DECK_HOUR_TINT)
	var deck_horizon: Color = DECK_NIGHT_HORIZON.lerp(_scaled(DECK_HORIZON, lerpf(1.0, shade, 0.7)), day_weight).lerp(clear[2] as Color, DECK_HOUR_TINT)
	var zenith: Color = (clear[0] as Color).lerp(deck_zenith, deck)
	var horizon: Color = (clear[2] as Color).lerp(deck_horizon, deck)
	var middle: Color = (clear[1] as Color).lerp(deck_zenith.lerp(deck_horizon, 0.5), deck)
	var wall_colour: Color = FOG_WALL_NIGHT.lerp(FOG_WALL_COLOUR, day_weight)
	zenith = zenith.lerp(wall_colour, wall)
	middle = middle.lerp(wall_colour, wall)
	horizon = horizon.lerp(wall_colour, wall)

	# The sun in the sky and the light on the ground.
	var sun_colour: Color = (SUN_COLOUR_DAWN if fraction < SUN_SET_FRACTION * 0.5 else SUN_COLOUR_DUSK).lerp(SUN_COLOUR_DAY, smoothstep(SUN_LOW_BELOW_DEG, SUN_DAY_ABOVE_DEG, elevation))
	var sun_up: float = smoothstep(0.0, 6.0, elevation)
	var sun_energy: float = SUN_ENERGY_DAY * float(look["sun_mul"]) * day_weight * sun_up
	var night_light: float = NIGHT_LIGHT_ENERGY * night_weight(fraction)
	var ambient_tint: Color = horizon.lerp(zenith, AMBIENT_ZENITH_SHARE)
	var grey: float = ambient_tint.get_luminance()
	ambient_tint = ambient_tint.lerp(Color(grey, grey, grey), AMBIENT_DESATURATE)
	ambient_tint = _scaled(ambient_tint, AMBIENT_TINT_VALUE / maxf(0.001, maxf(ambient_tint.r, maxf(ambient_tint.g, ambient_tint.b))))

	var ambient_weight: float = pow(day_weight, AMBIENT_DAYLIGHT_CURVE)

	# The air.
	var foggy: bool = wall >= 0.5
	var haze_end: float = float(look["haze_end_m"]) * lerpf(HAZE_DAWN_END_MUL, 1.0, smoothstep(0.0, HAZE_DAWN_UNTIL_FRACTION, fraction))
	var haze_max: float = float(look["haze_max"]) * day_weight
	var ridges: float = float(look["ridges"])
	var air_colour: Color = horizon.lerp(middle, AIR_MIDDLE_SHARE)
	var ridge_dark: Color = RIDGE_COLOUR_NIGHT.lerp(RIDGE_COLOUR_DAY, day_weight * lerpf(1.0, shade, deck * 0.6))

	var cloud_base: Color = zenith.lerp(horizon, 0.6)
	var cloud_shade: float = float(look["cloud_shade"])
	return {
		"look": look_of(kind, raining),
		"zenith": zenith,
		"middle": middle,
		"horizon": horizon,
		"below": air_colour.lerp(ridge_dark, BELOW_HORIZON_SHADE * (1.0 - wall)),
		"middle_height": lerpf(SKY_MIDDLE_HEIGHT_DAY, SKY_MIDDLE_HEIGHT_LOW_SUN, low_sun),
		"sun_direction": sun_direction(fraction),
		"sun_colour": sun_colour,
		"sun_disc": float(look["sun_disc"]) * smoothstep(-1.5, 1.5, elevation),
		"sun_glow": lerpf(float(look["sun_glow"]), SUN_GLOW_LOW_SUN * float(look["sun_glow"]) / 0.22, low_sun) * smoothstep(-8.0, 2.0, elevation),
		"horizon_glow": HORIZON_GLOW_LOW_SUN * low_sun * (1.0 - deck * 0.85),
		"cloud_cover": float(look["cloud_cover"]),
		"cloud_amount": float(look["cloud_amount"]),
		"cloud_mottle": float(look["cloud_mottle"]),
		"cloud_scale": float(look["cloud_scale"]),
		"cloud_drift": float(look["cloud_drift"]),
		"cloud_light": cloud_base.lerp(Color(1.0, 1.0, 1.0), CLOUD_LIGHT_LIFT * (1.0 - cloud_shade) * day_weight),
		"cloud_dark": _scaled(cloud_base, 1.0 - CLOUD_DARK_DROP - 0.3 * cloud_shade),
		"star_amount": STAR_BRIGHTNESS * float(look["stars"]) * (1.0 - smoothstep(0.0, 0.25, day_weight)) * night_weight(fraction),
		"ridge_amount": 1.0 if ridges > 0.0 else 0.0,
		"ridge_near": ridge_dark.lerp(air_colour, 1.0 - (1.0 - RIDGE_HAZE[0]) * ridges),
		"ridge_mid": ridge_dark.lerp(air_colour, 1.0 - (1.0 - RIDGE_HAZE[1]) * ridges),
		"ridge_far": ridge_dark.lerp(air_colour, 1.0 - (1.0 - RIDGE_HAZE[2]) * ridges),
		"ridge_mist": lerpf(RIDGE_MIST_DAWN, RIDGE_MIST_DAY, smoothstep(0.0, HAZE_DAWN_UNTIL_FRACTION, fraction)),
		"sun_energy": sun_energy,
		"night_energy": night_light,
		"light_colour": sun_colour.lerp(SUN_COLOUR_OVERCAST, deck),
		"light_from": _direction(sun_azimuth_deg(fraction), maxf(elevation, SUN_LIGHT_MIN_ELEVATION_DEG)),
		"shadow_opacity": float(look["shadow"]),
		"ambient_energy": lerpf(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY * float(look["ambient_mul"]), ambient_weight),
		"ambient_colour": AMBIENT_COLOUR_NIGHT.lerp(ambient_tint, ambient_weight),
		"fog": foggy,
		"haze": not foggy and haze_max > 0.0,
		"air_begin_m": FOG_DEPTH_BEGIN_M if foggy else HAZE_BEGIN_M,
		"air_end_m": FOG_CLEAR_SIGHT_M * clampf(sight_mul, 0.05, 1.0) if foggy else haze_end,
		"air_curve": 1.0 if foggy else HAZE_CURVE,
		"air_max": 1.0 if foggy else haze_max,
		"air_colour": air_colour,
		"saturation": lerpf(1.0, GRADE_SATURATION_DAY, smoothstep(0.0, 1.0, day_weight)),
	}


## The look a sim weather kind wears: the table's, or the deck for an unnamed kind that wets.
static func look_of(kind: String, raining: bool) -> String:
	if SKY_OF_KIND.has(kind):
		return String(SKY_OF_KIND[kind])
	return "deck" if raining else "clear"


## The sun's height over the horizon at a day fraction, in degrees: an arc from 0 at dawn's first tick to
## SUN_NOON_ELEVATION_DEG and back to 0 at SUN_SET_FRACTION, and under the horizon for the night.
static func sun_elevation_deg(fraction: float) -> float:
	var f: float = fposmod(fraction, 1.0)
	if f <= SUN_SET_FRACTION:
		return SUN_NOON_ELEVATION_DEG * sin(PI * f / SUN_SET_FRACTION)
	return -SUN_NOON_ELEVATION_DEG * sin(PI * (f - SUN_SET_FRACTION) / (1.0 - SUN_SET_FRACTION))


## The sun's compass bearing in the sim's axes, in degrees: 0 is east (+x), 90 south (+y, the river side),
## 180 west. It keeps turning under the horizon, through the north.
static func sun_azimuth_deg(fraction: float) -> float:
	var f: float = fposmod(fraction, 1.0)
	if f <= SUN_SET_FRACTION:
		return 180.0 * f / SUN_SET_FRACTION
	return 180.0 + 180.0 * (f - SUN_SET_FRACTION) / (1.0 - SUN_SET_FRACTION)


## A unit vector from the ground towards the sun, in the scene's axes (sim x is x, sim y is z).
static func sun_direction(fraction: float) -> Vector3:
	return _direction(sun_azimuth_deg(fraction), sun_elevation_deg(fraction))


## 1 in the dead of night, 0 while the sun is up, easing over NIGHT_LIGHT_FADE_FRACTION after sunset and
## before sunrise.
static func night_weight(fraction: float) -> float:
	var f: float = fposmod(fraction, 1.0)
	if f <= SUN_SET_FRACTION:
		return 0.0
	return smoothstep(SUN_SET_FRACTION, SUN_SET_FRACTION + NIGHT_LIGHT_FADE_FRACTION, f) * (1.0 - smoothstep(1.0 - NIGHT_LIGHT_FADE_FRACTION, 1.0, f))


## How much of a thing `metres` away the air takes, 0 to 1, for a state of `sky_state`: the engine's own
## depth fog (measured on the Compatibility renderer: smoothstep from begin to end, to the curve, times the
## most it takes).
static func air_at(state: Dictionary, metres: float) -> float:
	if not bool(state.get("fog", false)) and not bool(state.get("haze", false)):
		return 0.0
	var t: float = smoothstep(float(state["air_begin_m"]), float(state["air_end_m"]), metres)
	return pow(t, float(state["air_curve"])) * float(state["air_max"])


static func _direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var a: float = deg_to_rad(azimuth_deg)
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(cos(e) * cos(a), sin(e), cos(e) * sin(a))


static func _scaled(c: Color, by: float) -> Color:
	return Color(clampf(c.r * by, 0.0, 1.0), clampf(c.g * by, 0.0, 1.0), clampf(c.b * by, 0.0, 1.0))


# The clear sky's [zenith, middle, horizon] at a day fraction, between the two rows of CLEAR_SKY_KEYS around it.
static func _clear_sky_at(fraction: float) -> Array:
	var f: float = fposmod(fraction, 1.0)
	var count: int = CLEAR_SKY_KEYS.size()
	for i in range(count):
		var a: Array = CLEAR_SKY_KEYS[i] as Array
		var b: Array = CLEAR_SKY_KEYS[(i + 1) % count] as Array
		var from: float = float(a[0])
		var to: float = float(b[0]) if i + 1 < count else float(b[0]) + 1.0
		if f >= from and f <= to:
			var t: float = 0.0 if to <= from else (f - from) / (to - from)
			return [(a[1] as Color).lerp(b[1] as Color, t), (a[2] as Color).lerp(b[2] as Color, t), (a[3] as Color).lerp(b[3] as Color, t)]
	var last: Array = CLEAR_SKY_KEYS[count - 1] as Array
	return [last[1], last[2], last[3]]


# The cloud layer's noise: tiling, built in code from a fixed seed, so every boot draws the same sky.
func _cloud_noise() -> Texture2D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = CLOUD_NOISE_SEED
	noise.frequency = CLOUD_NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = CLOUD_NOISE_OCTAVES
	var image: Image = noise.get_seamless_image(CLOUD_NOISE_SIZE, CLOUD_NOISE_SIZE)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _apply(s: Dictionary, tick: int) -> void:
	for key in SKY_UNIFORMS:
		_sky_material.set_shader_parameter(String(SKY_UNIFORMS[key]), s[key])
	# The drift is the sim's tick, so a paused sim holds its clouds still and two runs draw one sky.
	var drift: Vector2 = CLOUD_DRIFT_PER_TICK * float(tick % Clock.DAY_TICKS) * float(s["cloud_drift"])
	_sky_material.set_shader_parameter("cloud_offset", Vector2(fposmod(drift.x, 1.0), fposmod(drift.y, 1.0)))
	_sky_material.set_shader_parameter("cloud_offset_fine", Vector2(fposmod(drift.x * 1.7 + 0.37, 1.0), fposmod(drift.y * 1.7 + 0.61, 1.0)))

	# The sun by day, the night sky's share after dark, never both: each leaves the tree's draw when it gives
	# nothing, so the night pays for no shadow pass.
	var sun_energy_now: float = float(s["sun_energy"])
	var night_energy_now: float = float(s["night_energy"])
	_sun_energy = maxf(sun_energy_now, night_energy_now)
	_ambient_energy = float(s["ambient_energy"])
	_sun.visible = sun_energy_now > 0.0
	_sun.light_energy = sun_energy_now
	_sun.light_color = s["light_colour"] as Color
	_sun.shadow_opacity = float(s["shadow_opacity"])
	_sun.look_at_from_position(Vector3.ZERO, -(s["light_from"] as Vector3), Vector3.UP)
	_night.visible = night_energy_now > 0.0
	_night.light_energy = night_energy_now
	_env.ambient_light_energy = _ambient_energy
	_env.ambient_light_color = s["ambient_colour"] as Color
	_env.adjustment_saturation = float(s["saturation"])

	_fog_on = bool(s["fog"])
	_haze_on = bool(s["haze"])
	_env.fog_enabled = _fog_on or _haze_on
	if _env.fog_enabled:
		_env.fog_light_color = s["air_colour"] as Color
		_env.fog_depth_begin = float(s["air_begin_m"])
		_env.fog_depth_end = float(s["air_end_m"])
		_env.fog_depth_curve = float(s["air_curve"])
		_env.fog_density = float(s["air_max"])
	# The grain moves with the sim's tick and holds still with it.
	_grade_material.set_shader_parameter("grain_seed", Vector2(float(tick % 251), float(tick % 241)))


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


## True while the sim's fog weather limits sight: the depth fog then ends at the sim's own distance.
func fog_enabled() -> bool:
	return _fog_on


## True while the day's thin haze is in the air. Never true together with `fog_enabled`.
func haze_enabled() -> bool:
	return _haze_on


## How much of a thing `metres` away the air takes this frame, 0 to 1 (haze or fog, whichever is on).
func air_fraction_at(metres: float) -> float:
	return air_at(_state, metres)


## The state this frame was dressed from (`sky_state`), for a gate.
func state() -> Dictionary:
	return _state


func environment() -> Environment:
	return _env


func sky_material() -> ShaderMaterial:
	return _sky_material


func grade_material() -> ShaderMaterial:
	return _grade_material


func sun() -> DirectionalLight3D:
	return _sun


func night_light() -> DirectionalLight3D:
	return _night

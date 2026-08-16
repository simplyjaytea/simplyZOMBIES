extends RefCounted
# The attention field, in words.
#
# docs/03-attention.md is the spine of the game -- noise, scent and light are what bring the
# dead to you -- but until now the only way to read it was the developer overlay on `O`. A
# player who cannot tell loud from quiet cannot make the trade the game is about.
#
# hardcore-contract clause 4 rules out putting the raw field values on screen, and docs/01
# rules out gauges, so this returns prose. The bands below are display thresholds, and they
# are derived rather than invented wherever the calibration gives something to derive from:
#
#   docs/03-attention.md#scale-and-calibration: an emitter's magnitude *is* its reach in
#   metres x attenuationPerMetre (0.7). So a field value converts back to a distance --
#   value / 0.7 metres -- and the noise bands below are written in metres, which is a thing
#   a player can reason about on a 256 m district. For reference, from
#   modules/attention_emitter.gd: walking emits 1.0 (~1.4 m), sprinting 6.0 (~8.6 m), a
#   shout 120.0 (~171 m, most of the district).
#
# Scent has no equivalent distance conversion -- it diffuses and decays on a half-life
# rather than attenuating over a reach -- so its bands are multiples of the calibrated
# scentFloor. Those multiples are a presentation judgement, and the one place in this file
# where a number was chosen rather than derived.

const Clock = preload("res://sim/time/clock.gd")
const SimAttentionField = preload("res://sim/field/attention.gd")

# Noise reach in metres, at or above which each phrase applies. Ordered loudest first.
const NOISE_BANDS: Array = [
	[120.0, "the district can hear this"],
	[40.0, "carrying a long way"],
	[12.0, "audible nearby"],
	[2.0, "quiet"],
]
const NOISE_SILENT: String = "silent"

# Multiples of the calibrated scentFloor. Ordered strongest first.
const SCENT_BANDS: Array = [
	[2000.0, "a heavy trail"],
	[100.0, "a trail worth following"],
	[10.0, "a faint trail"],
]
const SCENT_NONE: String = "no trail"

const DAYLIGHT: float = 0.6
const DIM: float = 0.25


# Returns {noise, scent, light, worst} -- four phrases, no numbers.
# `worst` is the single line worth putting on a crowded HUD: the channel most likely to be
# bringing something towards you right now.
static func clause(world: Variant, entity: int) -> Dictionary:
	var out: Dictionary = {"noise": NOISE_SILENT, "scent": SCENT_NONE, "light": "dark", "worst": ""}
	if world == null:
		return out
	var pos: Variant = world.components.get_component(entity, "position")
	if not (pos is Dictionary):
		return out
	var x: float = float((pos as Dictionary).get("x", 0.0))
	var y: float = float((pos as Dictionary).get("y", 0.0))

	var calib: Dictionary = SimAttentionField.default_calibration()
	var per_metre: float = float(calib.get("attenuationPerMetre", 0.7))
	var noise_floor: float = float(calib.get("floor", 0.05))
	var scent_floor: float = float(calib.get("scentFloor", 0.005))

	var noise_v: float = 0.0
	var scent_v: float = 0.0
	if world.field != null:
		noise_v = float(world.field.call("noise_at", x, y))
		scent_v = float(world.field.call("scent_at", x, y))

	# Noise, as the distance it reaches.
	if noise_v > noise_floor and per_metre > 0.0:
		var metres: float = noise_v / per_metre
		for band in NOISE_BANDS:
			if metres >= float((band as Array)[0]):
				out["noise"] = String((band as Array)[1])
				break

	# Scent, as multiples of the floor it has to clear to register at all.
	if scent_v > scent_floor and scent_floor > 0.0:
		var ratio: float = scent_v / scent_floor
		for band in SCENT_BANDS:
			if ratio >= float((band as Array)[0]):
				out["scent"] = String((band as Array)[1])
				break
		if out["scent"] == SCENT_NONE:
			out["scent"] = "a faint trail"

	# Light is two different facts: how well *you* can see, and whether you are the thing
	# lit up in the dark. The second is the one that costs you.
	var ambient: float = Clock.ambient_light(Clock.time_of_day(int(world.tick)))
	var lit: float = 0.0
	if world.light != null and (world.light as Object).has_method("lit_metres"):
		lit = float(world.light.call("lit_metres", x, y))
	if ambient >= DAYLIGHT:
		out["light"] = "daylight"
	elif lit > 0.0:
		out["light"] = "lit, and visible from the dark"
	elif ambient >= DIM:
		out["light"] = "failing light"
	else:
		out["light"] = "dark"

	out["worst"] = _worst(String(out["noise"]), String(out["scent"]), String(out["light"]))
	return out


# One line for a crowded HUD. Noise outranks scent outranks light, because that is the order
# in which they act: noise summons now, scent leads them here later, light only matters to
# something already looking.
static func _worst(noise: String, scent: String, light: String) -> String:
	if noise != NOISE_SILENT and noise != "quiet":
		return noise
	if scent != SCENT_NONE and scent != "a faint trail":
		return scent
	if light == "lit, and visible from the dark":
		return light
	if noise != NOISE_SILENT:
		return noise
	if scent != SCENT_NONE:
		return scent
	return NOISE_SILENT

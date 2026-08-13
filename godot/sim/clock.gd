class_name SimClock
extends RefCounted

# Keep in sync with src/sim/time/clock.ts
# ponytail: pure functions on tick; upgrade to World-clock resource when save needs wall time.

const DAY_SECONDS: int = 4 * 60 * 60 # 14400
const TICK_HZ: int = 20
const DAY_TICKS: int = DAY_SECONDS * TICK_HZ # 288000

enum Phase { DAWN = 0, DAY = 1, DUSK = 2, NIGHT = 3 }

const PHASE_NAMES: Dictionary = {Phase.DAWN: "dawn", Phase.DAY: "day", Phase.DUSK: "dusk", Phase.NIGHT: "night"}

const DAWN_ENDS: float = 0.5 / 4.0
const DAY_ENDS: float = DAWN_ENDS + 2.0 / 4.0
const DUSK_ENDS: float = DAY_ENDS + 0.5 / 4.0
const DAY_BEGINS: float = DAWN_ENDS
const NIGHT_AMBIENT: float = 0.04


static func time_of_day(tick: int) -> float:
	return float(tick % DAY_TICKS) / float(DAY_TICKS)


static func day_number(tick: int) -> int:
	return int(tick / DAY_TICKS) + 1


static func phase_at(fraction: float) -> int:
	if fraction < DAWN_ENDS:
		return Phase.DAWN
	if fraction < DAY_ENDS:
		return Phase.DAY
	if fraction < DUSK_ENDS:
		return Phase.DUSK
	return Phase.NIGHT


static func phase_of(tick: int) -> int:
	return phase_at(time_of_day(tick))


static func ambient_light(fraction: float) -> float:
	if fraction < DAWN_ENDS:
		return NIGHT_AMBIENT + (1.0 - NIGHT_AMBIENT) * (fraction / DAWN_ENDS)
	if fraction < DAY_ENDS:
		return 1.0
	if fraction < DUSK_ENDS:
		return 1.0 - (1.0 - NIGHT_AMBIENT) * ((fraction - DAY_ENDS) / (DUSK_ENDS - DAY_ENDS))
	return NIGHT_AMBIENT


static func ambient_light_at(tick: int) -> float:
	return ambient_light(time_of_day(tick))


static func clock_time(tick: int) -> Dictionary:
	var hours: float = fmod(time_of_day(tick) + 0.25, 1.0) * 24.0
	return {"hour": int(hours), "minute": int(fmod(hours, 1.0) * 60.0)}


static func tick_at_time_of_day(fraction: float) -> int:
	var f: float = fmod(fmod(fraction, 1.0) + 1.0, 1.0)
	return int(f * float(DAY_TICKS))

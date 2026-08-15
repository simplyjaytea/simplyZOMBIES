class_name SimClock
extends RefCounted

const TICK_HZ: int = 20
const DAY_SECONDS: int = 4 * 60 * 60
const DAY_TICKS: int = DAY_SECONDS * TICK_HZ
const NIGHT_AMBIENT: float = 0.04

enum Phase { Dawn = 0, Day = 1, Dusk = 2, Night = 3 }

const PHASE_NAMES: Array[String] = ["dawn", "day", "dusk", "night"]

const DAWN_ENDS: float = 0.5 / 4.0
const DAY_ENDS: float = 0.125 + 0.5
const DUSK_ENDS: float = 0.625 + 0.125
const DAY_BEGINS: float = 0.125


static func time_of_day(tick: int) -> float:
	return float(tick % DAY_TICKS) / float(DAY_TICKS)


static func day_number(tick: int) -> int:
	return int(floor(float(tick) / float(DAY_TICKS))) + 1


static func phase_at(fraction: float) -> int:
	if fraction < DAWN_ENDS:
		return Phase.Dawn
	if fraction < DAY_ENDS:
		return Phase.Day
	if fraction < DUSK_ENDS:
		return Phase.Dusk
	return Phase.Night


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
	var h := fmod(time_of_day(tick) + 0.25, 1.0) * 24.0
	return {"hour": int(floor(h)), "minute": int(floor(fmod(h, 1.0) * 60.0))}


static func tick_at_time_of_day(fraction: float) -> int:
	var f := fmod(fmod(fraction, 1.0) + 1.0, 1.0)
	return int(floor(f * float(DAY_TICKS)))


static func tick_on_day(day: int, fraction: float) -> int:
	return (maxi(1, day) - 1) * DAY_TICKS + tick_at_time_of_day(fraction)

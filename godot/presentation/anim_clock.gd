extends RefCounted
# The animation clock: which walk or breath frame a body shows, on the render clock rather than
# the sim tick (docs/23, "Frames on the render clock"). Presentation only -- nothing here writes a
# component, and `godot/sim/` never reads this file.
#
# Until this landed a walk frame was `tick * fps / 20 + id`: the frame moved only when a tick did,
# so at 20 Hz a body changed pose in 50 ms steps whatever the screen's rate, and the cadence was the
# same for a crawl and a sprint -- a limping survivor's feet moonwalked and a sprinter's skated.
# Here the walk is driven by ground covered: every draw hands over where the body is *drawn*
# (presentation/interp.gd's glide), the metres since the last draw advance the body's place in its
# cycle, and the cycle picks the frame. Faster bodies step faster, a body that stops stops stepping,
# and the same path walked at 30 or at 144 frames a second ends on the same frame.
#
# The cadence follows a real gait rather than a treadmill: a body moving at its family's own pace
# (authored.json's `pace`) takes one cycle per `stride` metres, and away from that pace the stride
# lengthens with the square root of the speed -- a sprint at three times the pace steps about 1.7
# times as often, not three, and a crouch at half the pace about 0.7 times. Fixed stride would have
# a sprinter's legs a blur and a crawler's frozen.
#
# A body standing still breathes: its idle loop runs on presentation time (seconds of game time,
# so it stops on pause and quickens under fast-forward with everything else), at the family's
# `breath_fps`, staggered by id so a crowd does not inhale as one.
#
# The motion a draw asks about is one Dictionary, {walking, cycle, idle}, built by `motion()` and
# read by `Appearance.frame_key`. The action animations (alpha plan A8, docs/23 "Actions on the
# render clock") add to it through `act()`: the action a body is in and how long it has been in it,
# and the stance it holds -- every one of them read off what the sim already published or already
# holds, so the sim stays the authority on what happened and this file only on how long it shows:
#
#   one-shots, from the events a step drained (`from_events`):
#     weapon.fired          the firer's recoil
#     attack.connected      a zombie attacker's lunge; a living target's flinch
#     grab.started          the grabbing zombie's lunge
#     entity.staggered      a zombie's stagger; a living body's flinch
#     entity.killed         the fall the dead body plays before its settled picture (`fall_of`)
#   held states, from components the sim keeps (`act`):
#     swing.state           WindUp holds the guard; the change to Recover throws the strike
#     rangedWeapon.state    Reload and Clearing play the reload (the pistol's or the long gun's)
#     posture.current       Crouch and Crawl are the crouch and prone stances
#
# Times are presentation seconds (`begin_draw`'s `now`), so an action stops on pause and quickens
# under fast-forward with the walk and the breath.

# A drawn body that moved farther than this between two draws did not walk there (a load, a mount,
# a body that was off screen and came back): the clock re-seats it rather than spinning its legs
# through the whole distance. The same number as presentation/interp.gd's snap.
const SNAP_METRES: float = 4.0
# Below this many metres per second of game time a drawn body counts as standing: the tail of a
# glide after the sim has already stopped it is still walking, a float jitter is not.
const STILL_MPS: float = 0.05
# The slowest and fastest a stride may stretch to, as multiples of the family's own: the square-root
# law above is a gait, not a law of nature, and it should not answer a zero or a teleport.
const STRIDE_MIN: float = 0.5
const STRIDE_MAX: float = 2.0
# A one-shot older than this is forgotten whatever its frame count: the longest action played is
# well under a second, and a record nothing drew again must not outlive the body.
const ACTION_FORGET_SECONDS: float = 3.0
# The melee and firearm states the clock reads (sim/modules/melee.gd SwingState, ranged.gd
# FireState) and the stances (sim/stances.gd), named rather than numbered.
const SWING_WINDUP: int = 1
const SWING_RECOVER: int = 2
const FIRE_RELOAD: int = 4
const FIRE_CLEARING: int = 5
const STANCE_CRAWL: int = 0
const STANCE_CROUCH: int = 1
# A hold past any reload's last frame: Appearance.action_index clamps it to the last one.
const RELOAD_HOLD: int = 999

# id -> {"x", "y", "cycle", "idle", "seen"}: one record per body drawn last frame.
var _bodies: Dictionary = {}
# Which draw pass this is, so a body nobody drew last pass is forgotten and re-seated if it returns.
var _pass: int = 0
# Presentation time at the last pass, and the game seconds this pass covers.
var _time: float = 0.0
var _dt: float = 0.0
# id -> {"action", "at", "start", "hold"}: the one-shot each body is playing.
var _acts: Dictionary = {}
# id -> {"swing", "fire", "at_swing", "at_fire"}: the held states as last read, and since when.
var _held: Dictionary = {}
# id -> {"key", "view", "lie"}: the family and view each living body was last drawn with, so a
# body that dies falls as it stood, and the side a prone body last lay toward.
var _looks: Dictionary = {}
# id -> {"key", "view", "at"}: the falls in progress.
var _falls: Dictionary = {}


# Where a body is in its walk after covering `metres` at `mps` metres per second, for a family
# whose own stride is `stride` metres a cycle at `pace` metres per second. 0 to 1, wrapping. Pure,
# so the gates can walk a path through it without a scene.
static func cycle_after(cycle: float, metres: float, mps: float, stride: float, pace: float) -> float:
	if metres <= 0.0 or stride <= 0.0:
		return fposmod(cycle, 1.0)
	return fposmod(cycle + metres / stride_at(mps, stride, pace), 1.0)


# The stride at `mps`: the family's own at its own pace, longer when faster and shorter when slower,
# by the square root of the ratio, clamped.
static func stride_at(mps: float, stride: float, pace: float) -> float:
	if pace <= 0.0 or mps <= 0.0:
		return stride
	return stride * clampf(sqrt(mps / pace), STRIDE_MIN, STRIDE_MAX)


# The frame a cycle shows out of `frames`. A cycle of exactly 1.0 is frame 0 again.
static func frame_at(cycle: float, frames: int) -> int:
	if frames <= 0:
		return 0
	return clampi(int(floor(fposmod(cycle, 1.0) * float(frames))), 0, frames - 1)


# The breath frame after `seconds` of standing, at `fps` frames a second out of `frames`.
static func breath_at(seconds: float, fps: float, frames: int) -> int:
	if frames <= 0 or fps <= 0.0 or seconds <= 0.0:
		return 0
	return int(floor(seconds * fps)) % frames


# Where a body first seen starts its walk and its breath: spread by id with the golden ratio, so
# neighbours land far apart in the cycle and a crowd that set off together does not step as one.
static func seat(id: int) -> float:
	return fposmod(float(id) * 0.6180339887, 1.0)


func clear() -> void:
	_bodies = {}
	_pass = 0
	_time = 0.0
	_dt = 0.0
	_acts = {}
	_held = {}
	_looks = {}
	_falls = {}


# The start of a draw pass. `now` is presentation time in game seconds -- the frame loop's own
# running total of `delta * speed` while the world runs, held still while it does not. A pass with
# no time behind it (a second draw in one frame, a paused world) moves nothing.
func begin_draw(now: float) -> void:
	_dt = maxf(0.0, now - _time)
	_time = now
	_pass += 1


# The motion of one body this pass, from where it is drawn and whether the sim says it moves:
# {walking, cycle, idle}. `stride` and `pace` are its family's (Appearance.stride_of / pace_of).
# Called once per drawn body per pass; a body not drawn in the last pass is re-seated.
func motion(id: int, drawn: Vector2, sim_moving: bool, stride: float, pace: float) -> Dictionary:
	var rec: Variant = _bodies.get(id)
	if not (rec is Dictionary) or int((rec as Dictionary)["seen"]) < _pass - 1:
		rec = {"x": drawn.x, "y": drawn.y, "cycle": seat(id), "idle": seat(id + 7919) * 4.0, "seen": _pass}
		_bodies[id] = rec
	var r: Dictionary = rec as Dictionary
	var moved: float = drawn.distance_to(Vector2(float(r["x"]), float(r["y"])))
	if moved > SNAP_METRES:
		moved = 0.0
	var mps: float = moved / _dt if _dt > 0.0 else 0.0
	# Walking is the sim's word or the picture's: a body the sim has just stopped still glides the
	# last tick out, and a paused body the sim says is moving holds its stride rather than standing.
	var walking: bool = sim_moving or mps > STILL_MPS
	if walking:
		r["cycle"] = cycle_after(float(r["cycle"]), moved, mps, stride, pace)
		r["idle"] = 0.0
	else:
		r["idle"] = float(r["idle"]) + _dt
	r["x"] = drawn.x
	r["y"] = drawn.y
	r["seen"] = _pass
	return {"walking": walking, "cycle": float(r["cycle"]), "idle": float(r["idle"])}


# How many bodies the clock is holding -- a reader for the gate, so "a body nobody drew is
# forgotten" is a number it can judge.
func held() -> int:
	return _bodies.size()


# Drops every record not drawn in the last pass. Called after a draw so the table never outgrows
# what is on screen.
func end_draw() -> void:
	for id in _bodies.keys():
		if int((_bodies[id] as Dictionary)["seen"]) < _pass:
			_bodies.erase(id)
			_held.erase(id)
	for id in _acts.keys():
		if _time - float((_acts[id] as Dictionary)["at"]) > ACTION_FORGET_SECONDS:
			_acts.erase(id)
	for id in _falls.keys():
		if _time - float((_falls[id] as Dictionary)["at"]) > ACTION_FORGET_SECONDS:
			_falls.erase(id)
	for id in _looks.keys():
		if not _bodies.has(id) and not _falls.has(id):
			_looks.erase(id)


# --- actions ---------------------------------------------------------------------------------

# Starts a one-shot on `id` at `now`, replacing whatever it was playing: the latest thing that
# happened to a body is the one it shows.
func start(id: int, action: String, now: float, first: int = 0, hold: int = -1) -> void:
	_acts[id] = {"action": action, "at": now, "start": first, "hold": hold}


# Reads the events one step drained (`world.events.drained`, the list sfx and the effects read --
# never a subscription to the bus) into one-shots. `now` is presentation time. A body is a zombie
# when it carries the `shambler` component.
func from_events(world: Variant, drained: Array, now: float) -> void:
	if world == null:
		return
	for e in drained:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e as Dictionary
		match String(ev.get("type", "")):
			"weapon.fired":
				start(int(ev.get("entity", -1)), "recoil", now)
			"attack.connected":
				var attacker: int = int(ev.get("attacker", -1))
				var target: int = int(ev.get("target", -1))
				if _is_zombie(world, attacker):
					start(attacker, "lunge", now)
				if target >= 0 and not _is_zombie(world, target):
					start(target, "flinch", now)
			"grab.started":
				var source: int = int(ev.get("source", -1))
				if _is_zombie(world, source):
					start(source, "lunge", now)
			"entity.staggered":
				var who: int = int(ev.get("entity", -1))
				# A hit publishes its flinch above in the same drain; a stagger alone (a shove, a
				# torso blow on the dead) starts one too, but never restarts one already running.
				if _is_zombie(world, who):
					start(who, "stagger", now)
				elif not (_acts.has(who) and String((_acts[who] as Dictionary)["action"]) == "flinch" and float((_acts[who] as Dictionary)["at"]) == now):
					start(who, "flinch", now)
			"entity.killed":
				# Fired more than once for one death (CLAUDE.md's trap): the first starts the fall,
				# the rest find it running and leave it be. A body nobody drew has no look to fall
				# from, and settles at once.
				var dead: int = int(ev.get("entity", -1))
				if _looks.has(dead) and not _falls.has(dead):
					var look: Dictionary = _looks[dead] as Dictionary
					_falls[dead] = {"key": String(look["key"]), "view": String(look["view"]), "at": now}
					_acts.erase(dead)


# appearance.gd preloads this file, so it is loaded here when first needed rather than preloaded:
# a preload cycle is a parse error in GDScript (sim/modules/items.gd's attachments is the precedent).
static func _appearance() -> GDScript:
	return load("res://presentation/appearance.gd") as GDScript


static func _is_zombie(world: Variant, id: int) -> bool:
	return id >= 0 and world.components.has_component(id, "shambler")


# The action fields of one body's motion this pass, to merge into `motion()`'s answer: the one-shot
# or held action it is in (`action`, `t` seconds in, `start`, `hold`), its stance, and the side a
# lying body lies toward. Records the family and view it is drawn with, for a fall.
func act(id: int, world: Variant, key: String, view: String) -> Dictionary:
	var lie: String = view if view == "e" or view == "w" else String((_looks.get(id, {}) as Dictionary).get("lie", "e"))
	_looks[id] = {"key": key, "view": view, "lie": lie}
	var out: Dictionary = {"stance": "", "lie": lie}
	if world == null:
		return out
	var posture: Variant = world.components.get_component(id, "posture")
	if posture is Dictionary:
		var current: int = int((posture as Dictionary).get("current", -1))
		out["stance"] = "crouch" if current == STANCE_CROUCH else "prone" if current == STANCE_CRAWL else ""
	_read_held(id, world)
	var held: Dictionary = _held[id] as Dictionary
	# The swing is the sim's state, so it is read rather than guessed: the guard holds through the
	# wind-up however long the weapon's is, and the change to Recover throws the strike from the
	# frame after the guard (`_read_held` started it).
	if int(held["swing"]) == SWING_WINDUP:
		out.merge({"action": "swing", "t": 0.0, "start": 0, "hold": 0})
		return out
	if int(held["fire"]) == FIRE_RELOAD or int(held["fire"]) == FIRE_CLEARING:
		# Played once from the state's start and held on its last beat, the stance, for as long as
		# the sim's reload lasts; the pistol's or the long gun's by what the body holds.
		out.merge({"action": _appearance().reload_action(world, id), "t": _time - float(held["at_fire"]), "start": 0, "hold": RELOAD_HOLD})
		return out
	var one: Variant = _acts.get(id)
	if one is Dictionary:
		out.merge({"action": String((one as Dictionary)["action"]), "t": _time - float((one as Dictionary)["at"]), "start": int((one as Dictionary)["start"]), "hold": int((one as Dictionary)["hold"])})
	return out


# Reads a body's swing and firearm state, noting when each changed; a wind-up that ends in Recover
# starts the strike one-shot, one that ends any other way (a stagger, a refusal) starts nothing.
func _read_held(id: int, world: Variant) -> void:
	var swing: int = 0
	var swing_v: Variant = world.components.get_component(id, "swing")
	if swing_v is Dictionary:
		swing = int((swing_v as Dictionary).get("state", 0))
	var fire: int = 0
	var fire_v: Variant = world.components.get_component(id, "rangedWeapon")
	if fire_v is Dictionary:
		fire = int((fire_v as Dictionary).get("state", 0))
	var rec: Variant = _held.get(id)
	if not (rec is Dictionary):
		_held[id] = {"swing": swing, "fire": fire, "at_swing": _time, "at_fire": _time}
		return
	var r: Dictionary = rec as Dictionary
	if swing != int(r["swing"]):
		if int(r["swing"]) == SWING_WINDUP and swing == SWING_RECOVER:
			start(id, "swing", _time, 1)
		r["swing"] = swing
		r["at_swing"] = _time
	if fire != int(r["fire"]):
		r["fire"] = fire
		r["at_fire"] = _time


# The fall `id` is playing, {key, view, t}, or {} when it is not falling.
func fall_of(id: int) -> Dictionary:
	var f: Variant = _falls.get(id)
	if not (f is Dictionary):
		return {}
	return {"key": String((f as Dictionary)["key"]), "view": String((f as Dictionary)["view"]), "t": _time - float((f as Dictionary)["at"])}

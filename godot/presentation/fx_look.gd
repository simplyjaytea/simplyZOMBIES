extends RefCounted
# The shot is seen (docs/23's outpost group, 2026-09-26): the muzzle flash, the ejected casing, the
# blood where a blow lands and the campfire's flame, drawn off four of the outpost pack's
# four-frame effect sheets. Before this file nothing drew any of them -- a shot was a sound, a
# light the sim already kept (`ranged.gd`'s `flashTicks`) and a camera kick, and a lit campfire
# was one still picture.
#
# **Presentation only, and read-only against the sim.** A one-shot is born from a record the sim
# has already drained (`world.events.drained`, the same read `_camera_shake_from_events` and
# sfx.gd take -- never a subscription to the bus), and the flame from the `campfire` component's
# `lit` flag the prop resolver already reads. Nothing here writes a component, publishes an event
# or draws from an RNG stream. The clock is presentation-side: `advance` is handed the frame's
# wall-clock delta while the world runs, so a flash lasts its sheet's own fraction of a second at
# every speed on the ladder -- at speed ten a whole flash would fall inside one frame's ticks, and a
# clock keyed to `world.tick` would never draw it.
#
# **Nothing here says what the player could not see** (docs/01 clause 4; docs/30, "The whole
# outpost pack"). Every one-shot is judged against the player's own sight twice -- when the event
# arrives, so a shot fired where the player cannot see draws nothing ever, and again each frame it
# draws, so turning away from a flash takes it off the screen -- and the test is Focal detail, the
# test a body's own picture passes (`_draw_entities`), because a Peripheral glimpse is an anonymous
# moving disc and a blood burst on it would say more than the glimpse does. A flame is a prop and
# takes a prop's rule: its tile is in the player's seen set, or it is not drawn.
#
# **Blood never varies with the blow.** The sheet is chosen by who was struck -- the struck body's
# own appearance block names it (`hitFx`) -- and the one-shot record carries the body's position
# and nothing else about the event: not the damage, not the part, not whether it was a swipe, a
# shot or a bite, and not whether that bite will present as a scratch. A graze and a killing blow
# draw the identical frames, which is `godot:check:fx`'s SAME lane.
#
# What the pack ships and this deliberately does not draw: sparks, dust, splinters, splash and the
# explosion have no impact point the sim records (a miss lands nowhere), the smoke loop has no
# source (a campfire's smoke would be a second picture of the one fact the flame already shows),
# and the decals are a record the sim would have to keep first -- docs/30 keeps all of them in the
# report.

const Appearance = preload("res://presentation/appearance.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const SimAim = preload("res://sim/aim.gd")

# The most one-shots alive at once. A full magazine emptied into a crowd is a flash, a casing and
# a hit a round -- thirty-odd records for a third of a second -- so 48 never drops a visible one in
# play, and bounds the list a stuck clock could otherwise grow without end.
const LIVE_CAP: int = 48
# Where a blow lands on a body, in body-canvas pixels (the 32x40 pawn canvas, soles on row 39):
# the middle of the chest, fifteen rows above the soles. The sheet's own anchor goes on it.
const HIT_AT: Vector2i = Vector2i(16, 24)
# The body canvas's sole row: an ejected casing lands on the ground under the hand that fired.
const SOLE_ROW: int = 39
# The flame's anchor stands this many art pixels below a campfire's centre -- on the logs of the
# lit picture rather than in the middle of its tile.
const FLAME_DROP_ART_PX: float = 4.0

# The blow is felt (alpha plan A9): a struck body flashes and jolts, and a weapon that fired kicks
# back in the hand. All three are one-shots on this file's clock, born from the same drained events
# the blood and the flash are, under the same sight rule, and none of them varies with the blow --
# a graze and a killing blow flash as brightly and jolt as far (`godot:check:fx`'s FELT lane).
# How long the white flash over a struck body lasts, from full to nothing.
const HIT_FLASH_SECONDS: float = 0.12
# How far a struck body's picture jolts away from whoever struck it, in art pixels, and how long it
# takes to settle back. The sim never moves the body: this is the picture alone, so the world, its
# hash and every save are exactly what they were.
const KNOCK_ART_PX: float = 3.0
const KNOCK_SECONDS: float = 0.18
# How far a fired weapon kicks back along its barrel, in art pixels, and how long it takes to come
# back to the hand. The recoil *frames* of the body are the action-animation slice's (plan A8); this
# is the weapon's own kick, and `kick` is the hook those frames can key to.
const KICK_ART_PX: float = 2.0
const KICK_SECONDS: float = 0.12

# Presentation seconds since this world started running; advanced by the frame loop only while the
# world is stepping, so a paused game holds every flash exactly where it was, like the rain.
var clock: float = 0.0
# The live one-shots: {key, x, y, view, point, turn, glow, born}. `point` is the body-canvas pixel
# the sheet's anchor lands on, `turn` whether the sheet turns with the view the way a held weapon
# does, `glow` whether it is a light (drawn over the night) or a thing (drawn under it).
var live: Array[Dictionary] = []
# The bodies struck and the shooters that fired, as Arrays of records ({e, born, dir} and {e, born})
# rather than Dictionaries keyed by id -- the same shape the sim keeps per-entity memory in, and
# scanned the same way. Pruned as each one finishes, so neither grows past what is moving now.
var struck: Array[Dictionary] = []
var kicks: Array[Dictionary] = []
# The body frame each body was last drawn on ({entity id: member key}), told by the draw loop
# (`note_frame`), so a flash leaves the hand where the walk has carried it rather than the rest
# view's. Presentation memory only, never saved, rebuilt by the next draw.
var drawn_frames: Dictionary = {}


func clear() -> void:
	live.clear()
	struck.clear()
	kicks.clear()
	drawn_frames.clear()


# The draw loop's word on which frame a body was drawn on this frame.
func note_frame(entity: int, member: String) -> void:
	drawn_frames[entity] = member


# Whether body frame `member` is a picture of `view`: `<family>_<view>`, `<family>_walk_<view>_<n>`
# or `<family>_idle_<view>_<n>`.
static func member_in_view(member: String, view: String) -> bool:
	return member.ends_with("_" + view) or member.contains("_walk_%s_" % view) or member.contains("_idle_%s_" % view)


func advance(delta: float) -> void:
	if delta > 0.0:
		clock += delta
	var keep_struck: Array[Dictionary] = []
	for r in struck:
		if clock - float(r["born"]) < maxf(HIT_FLASH_SECONDS, KNOCK_SECONDS):
			keep_struck.append(r)
	struck = keep_struck
	var keep_kicks: Array[Dictionary] = []
	for r in kicks:
		if clock - float(r["born"]) < KICK_SECONDS:
			keep_kicks.append(r)
	kicks = keep_kicks


# The newest record for `entity` in `records`, or {}.
static func _record_of(records: Array[Dictionary], entity: int) -> Dictionary:
	for i in range(records.size() - 1, -1, -1):
		if int(records[i]["e"]) == entity:
			return records[i]
	return {}


# How white a struck body draws this frame, 1 at the blow falling to 0.
func hit_flash(entity: int) -> float:
	var r: Dictionary = _record_of(struck, entity)
	if r.is_empty():
		return 0.0
	return clampf(1.0 - (clock - float(r["born"])) / HIT_FLASH_SECONDS, 0.0, 1.0)


# Where a struck body's picture is pushed this frame, in art pixels: the whole jolt the instant the
# blow lands, easing back to nothing.
func knock(entity: int) -> Vector2:
	var r: Dictionary = _record_of(struck, entity)
	if r.is_empty():
		return Vector2.ZERO
	var left: float = clampf(1.0 - (clock - float(r["born"])) / KNOCK_SECONDS, 0.0, 1.0)
	return (r["dir"] as Vector2) * KNOCK_ART_PX * left * left


# How far back a weapon that just fired sits in its hand, 1 at the shot falling to 0. Multiplied by
# KICK_ART_PX it is the slide `Appearance.held_quad` is handed.
func kick(entity: int) -> float:
	var r: Dictionary = _record_of(kicks, entity)
	if r.is_empty():
		return 0.0
	var left: float = clampf(1.0 - (clock - float(r["born"])) / KICK_SECONDS, 0.0, 1.0)
	return left * left


# Which frame of a sheet shows `age` seconds after it started, or -1 once a one-shot has finished.
# `phase` offsets a loop so two fires side by side do not flicker as one; a one-shot ignores it.
static func frame_at(age: float, fps: int, frames: int, loop: bool, phase: int = 0) -> int:
	if fps <= 0 or frames <= 0 or age < 0.0:
		return -1
	var n: int = floori(age * float(fps))
	if loop:
		return posmod(n + phase, frames)
	if n >= frames:
		return -1
	return n


# Whether the player sees a point well enough for an effect on it to be drawn: Focal detail, the
# test a body's own picture passes. The player's own body always is.
static func sees(world: Variant, x: float, y: float, entity: int = -1) -> bool:
	if world == null or world.vision == null:
		return false
	if entity >= 0 and entity == int(world.player):
		return true
	return int(world.vision.detail(int(world.player), x, y)) == SimVisibility.Detail.Focal


# Reads one tick's drained events and starts a one-shot for each the player sees. Every other
# event, and every event the player does not see, starts nothing.
func from_events(world: Variant, drained: Array) -> void:
	if world == null or world.components == null:
		return
	for e in drained:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e as Dictionary
		match String(ev.get("type", "")):
			"weapon.fired":
				_shot(world, int(ev.get("entity", -1)), int(ev.get("item", -1)))
			"attack.connected":
				_hit(world, int(ev.get("target", -1)))
				_felt(world, int(ev.get("target", -1)), int(ev.get("attacker", -1)))
			"bite.landed":
				_hit(world, int(ev.get("victim", -1)))
				_felt(world, int(ev.get("victim", -1)), int(ev.get("source", -1)))


func _position(world: Variant, entity: int) -> Variant:
	var p: Variant = world.components.get_component(entity, "position")
	if not (p is Dictionary):
		return null
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


# A round left a weapon: its muzzle flash at the muzzle of the weapon in the hand, and its casing on
# the ground under that hand, each only if the fired item's appearance names one.
func _shot(world: Variant, shooter: int, item: int) -> void:
	var at: Variant = _position(world, shooter)
	if at == null or not sees(world, (at as Vector2).x, (at as Vector2).y, shooter):
		return
	# The weapon kicks back in the hand whether or not its content names a flash: it is the gun
	# moving, not a picture the gun chose.
	_kick(shooter)
	var base: Variant = world.components.get_component(item, "itemBase")
	if not (base is Dictionary):
		return
	var block: Dictionary = Appearance.of_content(world, "item", String((base as Dictionary).get("baseId", "")))
	var fire: String = String(block.get("fireFx", ""))
	var casing: String = String(block.get("casingFx", ""))
	if fire.is_empty() and casing.is_empty():
		return
	# The flash leaves the muzzle of the weapon as it is drawn: placed for the view the aim falls
	# in, then turned about the hand by what is left of the aim (Appearance.held_turn), the same
	# two steps the held weapon takes.
	var aim: float = SimAim.radians_of(world.components, shooter)
	var turned: bool = world.components.has_component(shooter, "facing")
	var view: String = Appearance.view_of(aim) if turned else Appearance.VIEW_REST
	var turn: float = Appearance.held_turn(view, aim) if turned else 0.0
	var slot: String = _slot_holding(world, shooter, item)
	# The hand on the frame the shooter was last drawn on, when that frame shows this view (a walk
	# swings the arm), and the rest view's hand otherwise -- the hand the held weapon is drawn on.
	var member: String = String(drawn_frames.get(shooter, ""))
	var hand: Vector2i = Appearance.frame_hand(member if member_in_view(member, view) else "", slot, view)
	var muzzle: Vector2i = hand
	var held: String = String(block.get("equipSprite", ""))
	var picture: Texture2D = Appearance.resolve(held) if Appearance.holds(held) else null
	if picture != null and Appearance.muzzle_of(held).x >= 0:
		var size := Vector2i(picture.get_size())
		var pose: Dictionary = Appearance.held_pose(size, Appearance.grip_of(held), hand, view)
		muzzle = Appearance.held_point(pose, size, Appearance.muzzle_of(held), view)
	if not Appearance.sheet_of(fire).is_empty():
		_start({"key": fire, "x": (at as Vector2).x, "y": (at as Vector2).y, "view": view, "point": muzzle, "turn": true, "glow": true,
				"pivot": hand, "spin": turn})
	if not Appearance.sheet_of(casing).is_empty():
		_start({"key": casing, "x": (at as Vector2).x, "y": (at as Vector2).y, "view": "e", "point": Vector2i(hand.x, SOLE_ROW), "turn": false, "glow": false})


# The slot the fired item is equipped in, for the hand it is drawn in; the primary hand when it is
# in neither (a weapon fired from a slot with no hand of its own).
func _slot_holding(world: Variant, shooter: int, item: int) -> String:
	var eq: Variant = world.components.get_component(shooter, "equipment")
	if eq is Dictionary:
		var slots: Variant = (eq as Dictionary).get("slots", {})
		if slots is Dictionary:
			for slot in Appearance.HELD_HANDS.keys():
				var there: Variant = (slots as Dictionary).get(slot)
				if there != null and int(there) == item:
					return String(slot)
	return "primary"


# A blow landed on a body: the struck body's own blood, on its chest. Only the body is read -- see
# the header: nothing about the blow reaches the picture.
func _hit(world: Variant, struck: int) -> void:
	var at: Variant = _position(world, struck)
	if at == null or not sees(world, (at as Vector2).x, (at as Vector2).y, struck):
		return
	var key: String = String(Appearance.body_block_for(world, Appearance.body_look_id(world, struck)).get("hitFx", ""))
	if Appearance.sheet_of(key).is_empty():
		return
	_start({"key": key, "x": (at as Vector2).x, "y": (at as Vector2).y, "view": "e", "point": HIT_AT, "turn": false, "glow": false})


# A blow landed and the struck body is seen: its flash and its jolt, away from whoever struck it.
# Read from the event: who was struck and who struck them -- where they stand is the direction --
# and nothing else; no damage, no part, so a graze and a killing blow are felt alike. A blow with
# nobody behind it, or one from the struck body's own spot, jolts nowhere and still flashes.
func _felt(world: Variant, struck_id: int, by: int) -> void:
	var at: Variant = _position(world, struck_id)
	if at == null or not sees(world, (at as Vector2).x, (at as Vector2).y, struck_id):
		return
	var dir := Vector2.ZERO
	var from: Variant = _position(world, by) if by >= 0 else null
	if from != null and (at as Vector2) != (from as Vector2):
		dir = ((at as Vector2) - (from as Vector2)).normalized()
	struck.append({"e": struck_id, "born": clock, "dir": dir})
	while struck.size() > LIVE_CAP:
		struck.pop_front()


func _kick(shooter: int) -> void:
	kicks.append({"e": shooter, "born": clock})
	while kicks.size() > LIVE_CAP:
		kicks.pop_front()


func _start(record: Dictionary) -> void:
	record["born"] = clock
	live.append(record)
	while live.size() > LIVE_CAP:
		live.pop_front()


# Everything to draw this frame on one side of the night -- `glow` true for the lights (a flash, a
# flame), false for the things (a casing, blood) -- as {key, frame, texture, rect, transpose}, in
# screen pixels. Finished one-shots are dropped here; a one-shot the player no longer sees is kept
# and not drawn.
func draws(world: Variant, camera: Dictionary, glow: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var px: float = Appearance.blit_scale(float(camera.get("zoom", 0.0)))
	if px <= 0.0:
		return out
	var body: Vector2 = Vector2(Appearance.PAWN_CANVAS) * px
	var keep: Array[Dictionary] = []
	for record in live:
		var sheet: Dictionary = Appearance.sheet_of(String(record["key"]))
		var frames: Array = sheet.get("frames", []) as Array
		var frame: int = frame_at(clock - float(record["born"]), int(sheet.get("fps", 0)), frames.size(), bool(sheet.get("loop", false)))
		if frame < 0:
			continue
		keep.append(record)
		if bool(record["glow"]) != glow or not sees(world, float(record["x"]), float(record["y"])):
			continue
		var texture: Texture2D = Appearance.resolve(String(frames[frame]))
		if texture == null:
			continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(record["x"]), float(record["y"]))
		var rect: Rect2 = Appearance.body_rect(float(sc["sx"]), float(sc["sy"]), body, 1.0)
		var view: String = String(record["view"]) if bool(record["turn"]) else "e"
		var pose: Dictionary = Appearance.held_pose(sheet["canvas"] as Vector2i, sheet["anchor"] as Vector2i, record["point"] as Vector2i, view)
		var at: Vector2i = pose["at"] as Vector2i
		var size: Vector2i = pose["size"] as Vector2i
		var drawn: Dictionary = {"key": String(record["key"]), "frame": frame, "texture": texture, "transpose": bool(pose["transpose"]),
				"rect": Rect2(rect.position + Vector2(at) * px, Vector2(size) * px)}
		# A flash from a weapon turned to its aim turns with it, about the same hand: one polygon,
		# the held weapon's own `held_quad`, so the drawn flash and the drawn muzzle cannot part.
		var spin: float = float(record.get("spin", 0.0))
		if spin != 0.0:
			var quad: Dictionary = Appearance.held_quad({"at": at, "view": view, "hand": record.get("pivot", record["point"])}, sheet["canvas"] as Vector2i, spin)
			var points := PackedVector2Array()
			for p in quad["points"] as PackedVector2Array:
				points.append(rect.position + p * px)
			drawn["points"] = points
			drawn["uvs"] = quad["uvs"]
		out.append(drawn)
	live = keep
	if glow:
		_flames(world, camera, px, out)
	return out


# Every lit campfire standing where the player sees it, its flame looping on the same clock,
# staggered by the entity id so two fires do not burn in step.
func _flames(world: Variant, camera: Dictionary, px: float, out: Array[Dictionary]) -> void:
	if world.components == null or world.vision == null:
		return
	var seen: Variant = world.vision.tiles_for(int(world.player))
	if seen == null:
		return
	for ent in world.components.query(["campfire", "position"]):
		var e: int = int(ent)
		if world.entities != null and not world.entities.is_alive(e):
			continue
		var at: Variant = _position(world, e)
		if at == null or not bool((seen as Object).call("has_tile", floori((at as Vector2).x), floori((at as Vector2).y))):
			continue
		var key: String = String(Appearance.prop_look(world, e).get("flameFx", ""))
		var sheet: Dictionary = Appearance.sheet_of(key)
		var frames: Array = sheet.get("frames", []) as Array
		var frame: int = frame_at(clock, int(sheet.get("fps", 0)), frames.size(), true, e)
		if frame < 0:
			continue
		var texture: Texture2D = Appearance.resolve(String(frames[frame]))
		if texture == null:
			continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, (at as Vector2).x, (at as Vector2).y)
		var anchor: Vector2 = Vector2(sheet["anchor"] as Vector2i) * px
		var ground := Vector2(roundf(float(sc["sx"])), roundf(float(sc["sy"]) + FLAME_DROP_ART_PX * px))
		out.append({"key": key, "frame": frame, "texture": texture, "transpose": false,
				"rect": Rect2(ground - anchor, Vector2(sheet["canvas"] as Vector2i) * px)})

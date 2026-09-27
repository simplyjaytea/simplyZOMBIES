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

# Presentation seconds since this world started running; advanced by the frame loop only while the
# world is stepping, so a paused game holds every flash exactly where it was, like the rain.
var clock: float = 0.0
# The live one-shots: {key, x, y, view, point, turn, glow, born}. `point` is the body-canvas pixel
# the sheet's anchor lands on, `turn` whether the sheet turns with the view the way a held weapon
# does, `glow` whether it is a light (drawn over the night) or a thing (drawn under it).
var live: Array[Dictionary] = []


func clear() -> void:
	live.clear()


func advance(delta: float) -> void:
	if delta > 0.0:
		clock += delta


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
			"bite.landed":
				_hit(world, int(ev.get("victim", -1)))


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
	var base: Variant = world.components.get_component(item, "itemBase")
	if not (base is Dictionary):
		return
	var block: Dictionary = Appearance.of_content(world, "item", String((base as Dictionary).get("baseId", "")))
	var fire: String = String(block.get("fireFx", ""))
	var casing: String = String(block.get("casingFx", ""))
	if fire.is_empty() and casing.is_empty():
		return
	var facing: Variant = world.components.get_component(shooter, "facing")
	var view: String = Appearance.view_of(float((facing as Dictionary).get("radians", 0.0))) if facing is Dictionary else Appearance.VIEW_REST
	var slot: String = _slot_holding(world, shooter, item)
	var hand: Vector2i = (Appearance.HELD_HANDS[slot] as Dictionary)[view] as Vector2i
	var muzzle: Vector2i = hand
	var held: String = String(block.get("equipSprite", ""))
	var picture: Texture2D = Appearance.resolve(held) if Appearance.holds(held) else null
	if picture != null and Appearance.muzzle_of(held).x >= 0:
		var size := Vector2i(picture.get_size())
		var pose: Dictionary = Appearance.held_pose(size, Appearance.grip_of(held), hand, view)
		muzzle = Appearance.held_point(pose, size, Appearance.muzzle_of(held), view)
	if not Appearance.sheet_of(fire).is_empty():
		_start({"key": fire, "x": (at as Vector2).x, "y": (at as Vector2).y, "view": view, "point": muzzle, "turn": true, "glow": true})
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
		out.append({"key": String(record["key"]), "frame": frame, "texture": texture, "transpose": bool(pose["transpose"]),
				"rect": Rect2(rect.position + Vector2(at) * px, Vector2(size) * px)})
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

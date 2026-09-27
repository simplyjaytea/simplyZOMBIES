extends RefCounted
# The pointer, in the kit's own pictures and the outpost pack's (docs/30, "The UI Field Kit, live",
# 2026-09-25, and "The whole outpost pack", the same day, whose "Cursors split by place" this is):
# the UI Field Kit ships four OS cursors -- arrow, hand, move and blocked -- and this is the one
# table that installs them. The pack's crosshair and interaction hand join that same table rather
# than a second cursor system beside it, so **which pointer you have says where you are**: over
# any panel or menu it is one of the kit's four; over the street while playing it is the crosshair,
# and it turns to the interaction hand over something you can see and do something about.
#
# What each screen does is say *which* shape it wants where, through a pure `cursor_at(p)` of its
# own and the Control's `mouse_default_cursor_shape`; the engine then draws whatever picture is
# installed for that shape. So a screen names a shape and never a texture, and this file is the
# only place a shape becomes a picture. The street has no Control of its own to say it, so
# `main.gd` asks `world_shape` below and hands the answer to `Input.set_default_cursor_shape`,
# which is what the engine draws wherever no Control claims the pointer.
#
# **Scale.** The chrome draws at the owner's 2x (`Kit.SCALE`), and a pointer is drawn over that
# chrome, so a pointer is the same 2x: the kit's 24 px pictures install at 48 px, the pack's 16 px
# ones at 32, and every hotspot is scaled with its picture, as the kit's integration notes ask
# ("scale both together"). The native values stay in TABLE, so `godot:check:ui_skin`'s CURSORS lane
# compares them against the manifests unscaled, the way KIT compares `Kit.NINE`.
#
# **What "something you can see and act on" means.** Two questions, both asked of the sim's own
# answers and neither guessed here: `SimContext.verbs_at` -- the rows the right-click menu would
# offer -- has one that is more than a walk, a shout, a camp or an attack; and the thing is seen
# *now*. The second is information scarcity's own rule: `Pick.pick_at` also finds a cupboard or a
# door that is only *remembered* (you may walk to one; clause 4 hides what is in it, never where
# it stood), and a hand over a remembered thing would say a door behind you is still there. So the
# hand asks the player's own `vision.detail` of the thing's own spot and never shows over
# `Unseen`. An attack is not a hand: a zombie under the pointer is what the crosshair is for.
#
# **Headless.** `Input.set_custom_mouse_cursor` reaches the display server, and the headless one
# every gate runs under has no pointer to dress, so there it does nothing and raises nothing.
# `install()` is safe to call there; the gate judges the table and who reaches it, never the OS.

const Kit = preload("res://ui/kit.gd")
const Pick = preload("res://presentation/pick.gd")
const SimContext = preload("res://sim/context.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")

# Screen pixels per kit pixel for a pointer: the chrome's own scale, so a pointer's pixels are
# the same size as the frame's under it.
const SCALE: int = Kit.SCALE

# Where the pack's two pointers live. A record with a `path` wears a pack picture and is judged
# against the pack's `manifest.json` (its `anchor` is the hotspot); a record without one wears
# `controls/<id>.png` from the kit and is judged against the kit's.
const PACK_ROOT: String = "res://art/simplyzombies/"

const MOVE: Dictionary = {"id": "control_cursor_move", "size": Vector2i(24, 24), "hotspot": Vector2i(12, 12)}

# The two shapes the street wears. Godot names seventeen and no screen uses these two: CROSS is the
# crosshair, HELP (a question mark) is the hand -- POINTING_HAND is already the kit's, over panels,
# and one shape cannot wear two pictures.
const CROSSHAIR: int = Input.CURSOR_CROSS
const INTERACT: int = Input.CURSOR_HELP

# Input.CursorShape -> the pointer that shape wears, at native pixels: `size` and `hotspot` are the
# manifest's, copied, and the CURSORS lane holds this table to it. Eight shapes, six pictures: a
# held item wears `move` under every shape the engine or a screen may name for it -- DRAG while it
# is lifted, CAN_DROP over a place that takes it, MOVE, which is what the inventory sheet names --
# so no path through a drag falls back to the operating system's arrow.
const TABLE: Dictionary = {
	Input.CURSOR_ARROW: {"id": "control_cursor_arrow", "size": Vector2i(24, 24), "hotspot": Vector2i(6, 2)},
	Input.CURSOR_POINTING_HAND: {"id": "control_cursor_hand", "size": Vector2i(24, 24), "hotspot": Vector2i(9, 2)},
	Input.CURSOR_DRAG: MOVE,
	Input.CURSOR_CAN_DROP: MOVE,
	Input.CURSOR_MOVE: MOVE,
	Input.CURSOR_FORBIDDEN: {"id": "control_cursor_blocked", "size": Vector2i(24, 24), "hotspot": Vector2i(12, 12)},
	CROSSHAIR: {"id": "ui-crosshair", "size": Vector2i(16, 16), "hotspot": Vector2i(8, 8), "path": "groups/utility/native/ui-crosshair.png"},
	INTERACT: {"id": "ui-interaction-hand", "size": Vector2i(16, 16), "hotspot": Vector2i(8, 8), "path": "groups/utility/native/ui-interaction-hand.png"},
}

# Commands a right-click row can carry that are not something to *do to the thing under the
# pointer*: walking to a tile, shouting, the camp verbs (which act on the tile you stand on) and an
# attack, which is the crosshair's. Every other row -- open, pick up, treat, rescue, talk, use -- is
# a verb, so a verb added to `SimContext.verbs_at` tomorrow gets its hand without a line here.
const PASSIVE_COMMANDS: Array[String] = ["walk.to", "shout", "camp.establish", "camp.abandon", "attack.context"]


# The picture a shape wears, at SCALE, or null for a shape the table does not name or a picture
# that did not resolve. Through `Kit.texture`, the one two-path loader, for the pack's pictures too.
static func texture_of(shape: int) -> Texture2D:
	if not TABLE.has(shape):
		return null
	var rec: Dictionary = TABLE[shape] as Dictionary
	if rec.has("path"):
		return Kit.texture(PACK_ROOT + String(rec["path"]), SCALE)
	return Kit.texture("controls/%s.png" % String(rec["id"]), SCALE)


# Where the click lands inside that picture, in installed pixels: the manifest's hotspot times
# SCALE, because the picture was scaled by the same.
static func hotspot_of(shape: int) -> Vector2:
	if not TABLE.has(shape):
		return Vector2.ZERO
	return Vector2((TABLE[shape] as Dictionary)["hotspot"] as Vector2i * SCALE)


# Dresses every shape in TABLE. Once, from `main.gd`'s `_ensure_ui`, before any screen exists to
# name a shape. Returns how many shapes were given a picture -- a shape whose picture did not
# resolve keeps the operating system's own pointer rather than an empty one.
static func install() -> int:
	var dressed: int = 0
	for shape_v in TABLE.keys():
		var shape: int = int(shape_v)
		var tex: Texture2D = texture_of(shape)
		if tex == null:
			continue
		Input.set_custom_mouse_cursor(tex, shape as Input.CursorShape, hotspot_of(shape))
		dressed += 1
	return dressed


# Whether any row is a verb on the thing itself: `rows` is `SimContext.verbs_at`'s answer, and a row
# with no command ("look at") or a PASSIVE_COMMANDS one is not.
static func has_verb(rows: Array) -> bool:
	for row_v in rows:
		var cmd: Variant = (row_v as Dictionary).get("command", {})
		if cmd is Dictionary and not (cmd as Dictionary).is_empty() and not PASSIVE_COMMANDS.has(String((cmd as Dictionary).get("type", ""))):
			return true
	return false


# Whether the player can see what `hit` (a `Pick.pick_at` answer) found, right now: the player's
# own `vision.detail` of the thing's spot is not Unseen. The spot is the entity's position, or the
# centre of the tile for a door, which is an entity of no kind. Bare ground is not a thing.
static func seen_now(world: Variant, hit: Dictionary) -> bool:
	if world == null or world.vision == null or String(hit.get("kind", "ground")) == "ground":
		return false
	var x: float = 0.0
	var y: float = 0.0
	var entity: int = int(hit.get("entity", -1))
	var pos: Variant = world.components.get_component(entity, "position") if entity >= 0 else null
	if pos is Dictionary:
		x = float((pos as Dictionary).get("x", 0.0))
		y = float((pos as Dictionary).get("y", 0.0))
	else:
		var tile: Vector2i = hit.get("tile", Vector2i(-1, -1)) as Vector2i
		if tile.x < 0:
			return false
		x = float(tile.x) + 0.5
		y = float(tile.y) + 0.5
	return int(world.vision.detail(int(world.player), x, y)) != SimVisibility.Detail.Unseen


# The street's pointer for a hit and the rows for it: the hand only for a thing that is seen *and*
# has a verb, the crosshair for everything else. Pure, so the gate can hold each half to a true
# positive and a true negative.
static func shape_for(hit: Dictionary, rows: Array, seen: bool) -> int:
	if seen and String(hit.get("kind", "ground")) != "ground" and has_verb(rows):
		return INTERACT
	return CROSSHAIR


# The pointer over the street at screen point `p`: what `Pick.pick_at` finds there, what the
# right-click menu would offer for it, and whether it is seen. `main.gd` reads this while playing
# and never over a panel -- a panel's own `cursor_at` and the engine's per-Control shape answer
# there -- and outside PLAYING the arrow is the shape and this is not asked.
static func world_shape(world: Variant, camera: Dictionary, p: Vector2) -> int:
	if world == null:
		return Input.CURSOR_ARROW
	var hit: Dictionary = Pick.pick_at(world, camera, p)
	var rows: Array[Dictionary] = SimContext.verbs_at(world, int(world.player), hit)
	return shape_for(hit, rows, seen_now(world, hit))

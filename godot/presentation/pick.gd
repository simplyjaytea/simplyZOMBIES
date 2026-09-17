extends RefCounted
# Which colonist a screen point lands on. Pure: a world, a camera and a point in; an entity id
# or -1 out. main.gd's left click asks this first and attacks only when the answer is -1, so a
# click on Mara selects her and a click on the street swings at it, as before.
#
# The hit-test is the pawn's own rect -- Appearance.body_rect on the pawn canvas (32 x 48 at
# 1x, feet on the shadow line), at the draw pass's scale -- so what you can click is exactly
# what is drawn, and a body the sim does not let you see (Unseen, or a Peripheral glimpse
# drawn as a disc) is not clickable either: hardcore contract clause 4, the same rule the draw
# loop keeps. Among overlapping pawns the one lower on screen wins, because it is drawn in
# front (TopDownProjection.depth_of).
#
# People only: `identity` and `position`, not a corpse, not a zombie, not a raider. The
# player's own pawn is returned too, and the caller reads that as "clear the selection" --
# clicking yourself is how you go back to your own lines.

const TopDownProjection = preload("res://presentation/projection.gd")
const Appearance = preload("res://presentation/appearance.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const CameraUtil = preload("res://presentation/camera.gd")

# How close a click has to land to a small entity's own position to hit it -- an item, a container,
# a prop, a parked vehicle. Half a tile plus a hair, so a click anywhere over the tile a thing
# stands on finds it without also reaching into the tile beside it.
const NEAR_METRES: float = 0.65


static func pick_colonist(world: Variant, camera: Dictionary, screen_pos: Vector2) -> int:
	if world == null:
		return -1
	var px_scale: float = Appearance.blit_scale(float(camera["zoom"]))
	var size: Vector2 = Vector2(Appearance.PAWN_CANVAS) * px_scale
	var best: int = -1
	var best_depth: float = -1e12
	# The player's own pawn is drawn whether or not it carries an identity (the draw loop's
	# `is_player`), so it is clickable on the same terms.
	var candidates: Array = world.components.query(["identity", "position"])
	if not candidates.has(int(world.player)) and world.components.has_component(int(world.player), "position"):
		candidates.append(int(world.player))
	for ent in candidates:
		var e: int = int(ent)
		if world.components.has_component(e, "corpse") or world.components.has_component(e, "shambler") or world.components.has_component(e, "raider"):
			continue
		var p: Variant = world.components.get_component(e, "position")
		if not (p is Dictionary):
			continue
		var x: float = float((p as Dictionary).get("x", 0.0))
		var y: float = float((p as Dictionary).get("y", 0.0))
		# A body inside a car is not drawn (the car is), so it is not clickable either.
		var mounted: Variant = world.components.get_component(e, "mounted")
		if mounted is Dictionary and bool((mounted as Dictionary).get("cab", false)):
			continue
		if e != int(world.player) and world.vision != null:
			if int(world.vision.detail(int(world.player), x, y)) != SimVisibility.Detail.Focal:
				continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, x, y)
		var rect: Rect2 = Appearance.body_rect(float(sc["sx"]), float(sc["sy"]), size, 1.0)
		if not rect.has_point(screen_pos):
			continue
		var depth: float = TopDownProjection.depth_of(x, y)
		if depth > best_depth:
			best_depth = depth
			best = e
	return best


## What is under a screen point, for the right-click menu: a kind, an entity id (-1 for none) and
## the tile the point falls in, so a walk-here or a door toggle always has a tile to act on even
## where there is no entity. Read-only, like `pick_colonist` above -- `SimContext.verbs_at` is the
## one place that turns this into what you may do about it.
##
## Precedence: a body (Focal only, the same pawn rect `pick_colonist` hit-tests, widened here to
## also answer for a zombie and a raider rather than refusing them) beats a ground item (Focal
## only) beats a container/prop/vehicle (seen **or** explored -- you can walk to a remembered
## cupboard, hardcore-contract clause 4 hides what is inside a thing, never where it stood) beats
## a door (same rule) beats the bare tile.
static func pick_at(world: Variant, camera: Dictionary, screen_pos: Vector2) -> Dictionary:
	var out: Dictionary = {"kind": "ground", "entity": -1, "tile": Vector2i(-1, -1)}
	if world == null:
		return out
	var at: Dictionary = CameraUtil.screen_to_world(camera, screen_pos.x, screen_pos.y)
	var wx: float = float(at["x"])
	var wy: float = float(at["y"])
	var tile := Vector2i(floori(wx), floori(wy))
	out["tile"] = tile

	var body: Dictionary = _pick_body(world, camera, screen_pos)
	if int(body["entity"]) >= 0:
		out["kind"] = String(body["kind"])
		out["entity"] = int(body["entity"])
		return out

	var item: int = _pick_ground_item(world, wx, wy)
	if item >= 0:
		out["kind"] = "item"
		out["entity"] = item
		return out

	if _known_tile(world, tile.x, tile.y):
		var container: int = _pick_near(world, wx, wy, world.components.query(["searchable", "position"]), NEAR_METRES)
		if container >= 0:
			out["kind"] = "container"
			out["entity"] = container
			return out
		var prop: int = _pick_prop(world, wx, wy)
		if prop >= 0:
			out["kind"] = "prop"
			out["entity"] = prop
			return out
		var vehicle: int = _pick_near(world, wx, wy, world.components.query(["vehicle", "position"]), NEAR_METRES)
		if vehicle >= 0:
			out["kind"] = "vehicle"
			out["entity"] = vehicle
			return out
		if world.tilemap != null and SimTileMapRes.tile_at(world.tilemap, tile.x, tile.y) == SimTileMapRes.Tile.Door:
			out["kind"] = "door"
			return out
	return out


# A body under the point, Focal only -- `pick_colonist`'s own rect and depth tie-break, widened to
# a second candidate set (`position` alone, rather than `identity, position`) because that one's
# own header rules a zombie and a raider out on purpose and the menu needs both back in, named.
static func _pick_body(world: Variant, camera: Dictionary, screen_pos: Vector2) -> Dictionary:
	var none: Dictionary = {"entity": -1, "kind": ""}
	var px_scale: float = Appearance.blit_scale(float(camera["zoom"]))
	var size: Vector2 = Vector2(Appearance.PAWN_CANVAS) * px_scale
	var best: int = -1
	var best_depth: float = -1e12
	var best_kind: String = ""
	for ent in world.components.query(["position"]):
		var e: int = int(ent)
		if world.components.has_component(e, "corpse"):
			continue
		var kind: String = ""
		if e == int(world.player):
			kind = "colonist"
		elif world.components.has_component(e, "shambler"):
			kind = "zombie"
		elif world.components.has_component(e, "raider"):
			kind = "raider"
		elif world.components.has_component(e, "identity"):
			kind = "colonist"
		else:
			continue
		var p: Variant = world.components.get_component(e, "position")
		if not (p is Dictionary):
			continue
		var x: float = float((p as Dictionary).get("x", 0.0))
		var y: float = float((p as Dictionary).get("y", 0.0))
		var mounted: Variant = world.components.get_component(e, "mounted")
		if mounted is Dictionary and bool((mounted as Dictionary).get("cab", false)):
			continue
		if e != int(world.player) and world.vision != null:
			if int(world.vision.detail(int(world.player), x, y)) != SimVisibility.Detail.Focal:
				continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, x, y)
		var rect: Rect2 = Appearance.body_rect(float(sc["sx"]), float(sc["sy"]), size, 1.0)
		if not rect.has_point(screen_pos):
			continue
		var depth: float = TopDownProjection.depth_of(x, y)
		if depth > best_depth:
			best_depth = depth
			best = e
			best_kind = kind
	if best < 0:
		return none
	return {"entity": best, "kind": best_kind}


static func _pick_ground_item(world: Variant, wx: float, wy: float) -> int:
	var best: int = -1
	var best_d: float = NEAR_METRES * NEAR_METRES
	for ent in world.components.query(["itemBase", "position"]):
		var e: int = int(ent)
		if world.components.has_component(e, "stored"):
			continue
		var p: Variant = world.components.get_component(e, "position")
		if not (p is Dictionary):
			continue
		var x: float = float((p as Dictionary)["x"])
		var y: float = float((p as Dictionary)["y"])
		if world.vision != null and int(world.vision.detail(int(world.player), x, y)) != SimVisibility.Detail.Focal:
			continue
		var dx: float = x - wx
		var dy: float = y - wy
		var d: float = dx * dx + dy * dy
		if d <= best_d:
			best_d = d
			best = e
	return best


static func _pick_near(world: Variant, wx: float, wy: float, entities: Array, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for ent in entities:
		var e: int = int(ent)
		var p: Variant = world.components.get_component(e, "position")
		if not (p is Dictionary):
			continue
		var dx: float = float((p as Dictionary)["x"]) - wx
		var dy: float = float((p as Dictionary)["y"]) - wy
		var d: float = dx * dx + dy * dy
		if d <= best_d:
			best_d = d
			best = e
	return best


# A prop under the point: `Appearance.PROP_KINDS`' own component list, minus `searchable` (a
# container, already its own kind above) -- one definition of what a prop is, not a second list
# that can drift from the one the draw loop already reads.
static func _pick_prop(world: Variant, wx: float, wy: float) -> int:
	for kind in Appearance.PROP_KINDS:
		var comp: String = String((kind as Dictionary)["component"])
		if comp == "searchable":
			continue
		var hit: int = _pick_near(world, wx, wy, world.components.query([comp, "position"]), NEAR_METRES)
		if hit >= 0:
			return hit
	return -1


# Seen right now, or remembered: the same composite `main.gd`'s `CompositeSeen` widens tree and
# vehicle visibility with, asked here of one tile rather than built as a standing object.
static func _known_tile(world: Variant, tx: int, ty: int) -> bool:
	if world.vision != null:
		var seen: Variant = world.vision.tiles_for(int(world.player))
		if seen != null and bool((seen as Object).call("has_tile", tx, ty)):
			return true
	return SimSightings.knows_tile(world, int(world.player), tx, ty)

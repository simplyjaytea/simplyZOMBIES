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

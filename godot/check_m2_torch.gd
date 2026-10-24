extends SceneTree
# The torch is a cone in the sim -- docs/03-attention.md#light, and the owner's decisions of
# 2026-10-24 (docs/30): a hand torch lights the wedge its content's `light.beam` declares, along
# its carrier's facing, plus the spill round its own feet; and only a zombie in that light is
# drawn toward it. A round light is unchanged, and so is every save that carries one.
#
# Every lane carries a true negative. Sabotage that proves it: forcing `beam` to 0 in
# `beam_of` turns CONE red; a recast on turn turns TURN red; ignoring the wedge in
# `_lean_to_light` turns LEAN red; light_texels asking the round cast instead of `lights_tile`
# turns READS red.
#
# A beam lights a tile any of it falls on (`BEAM_EDGE_M`, B3), so the screen's straight-edged beam
# lies inside the lit tiles: CONE holds a tile just past the half-angle lit and the far diagonal
# dark, and a carrier with no facing throws round.
#
# READS is the dead-socket rule. `lit_metres`, `_lean_to_light` and `LightLook` (the screen, since
# the beam on screen, B3) must reach `lights_tile`.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimLightIndex = preload("res://sim/vision/light.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimSave = preload("res://sim/save.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Clock = preload("res://sim/time/clock.gd")
const LightLook = preload("res://presentation/light_look.gd")

const TORCH: String = "item.torch.handheld"
const LANTERN: String = "item.lantern.storm"
const MAP_TILES: int = 40
# The holder stands at the centre of this tile; tiles are one metre, so 8 tiles is 8 m.
const HOLDER_TX: int = 20
const HOLDER_TY: int = 20
const REACH_M: int = 8
const NIGHT: float = 0.9
const EPS: float = 0.0001


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_torch_is_a_cone_and_a_lantern_is_round() and ok
	ok = _turning_moves_the_wedge_and_recasts_nothing() and ok
	ok = _a_zombie_in_the_beam_leans_and_one_behind_does_not() and ok
	ok = _a_lantern_pulls_the_zombie_behind() and ok
	ok = _the_beam_helps_the_holder_see_further() and ok
	ok = _the_beam_survives_a_save() and ok
	ok = _the_beam_reaches_the_reader() and ok
	if ok:
		print("M2_TORCH_OK cone turn lean sight save reads")
		quit(0)
	else:
		push_error("M2_TORCH_FAIL")
		quit(1)


# A blank, open world with the holder at the centre of HOLDER_TX/TY, facing east, carrying `item_id`
# ("" carries nothing). Stepped once, so the light index has cast the holder's light.
func _world(item_id: String, night: bool = false) -> Variant:
	var f: Dictionary = {
		"seed": 4242,
		"tick_hz": 20,
		"map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []},
		"player": {"id": 0, "x": _mid(HOLDER_TX), "y": _mid(HOLDER_TY), "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(NIGHT if night else 0.5)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	SimBoot.attach_kernel(w, map)
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.content = ContentLoader.load_tree("res://content")
	if item_id != "":
		var item: int = int(SimItems.spawn_item(w, item_id, {}))
		SimInventory.equip(w, int(w.player), item, "")
		SimLightMod.refresh_carried(w, int(w.player))
	w.step()
	return w


func _mid(tile: int) -> float:
	return float(tile) + 0.5


func _lit(w: Variant, source: int, tx: int, ty: int) -> bool:
	return bool(w.light.lights_tile(source, tx, ty))


# CONE. A hand torch lights the tile 8 m along its facing and not the one 8 m behind; it lights the
# spill at its own feet; it does not light the far diagonal, outside its half-angle. A lantern is a
# round light and lights the tile 8 m behind it.
func _a_torch_is_a_cone_and_a_lantern_is_round() -> bool:
	var w: Variant = _world(TORCH)
	var holder: int = int(w.player)
	if not _lit(w, holder, HOLDER_TX + REACH_M, HOLDER_TY):
		push_error("CONE: a hand torch facing east does not light the tile 8 m ahead of it")
		return false
	if _lit(w, holder, HOLDER_TX - REACH_M, HOLDER_TY):
		push_error("CONE: a hand torch facing east lights the tile 8 m behind it -- the beam is round")
		return false
	if not _lit(w, holder, HOLDER_TX - 1, HOLDER_TY):
		push_error("CONE: the spill tile at the holder's back is dark -- the torch lights nothing at its own feet")
		return false
	if _lit(w, holder, HOLDER_TX + 4, HOLDER_TY + 4):
		push_error("CONE: the far diagonal, 45 degrees off the facing, is lit by a 22 degree beam")
		return false
	# The tile whose centre is 27 degrees off the facing, 4.5 m out: the beam's edge falls across it,
	# though not through its centre.
	if not _lit(w, holder, HOLDER_TX + 4, HOLDER_TY - 2):
		push_error("CONE: the tile the beam's edge falls across, 27 degrees off at 4.5 m, is dark -- the wedge is cut at tile centres")
		return false
	w.components.remove(holder, "facing")
	w.step()
	if not _lit(w, holder, HOLDER_TX - REACH_M, HOLDER_TY) or float((w.light.source_at(holder) as Dictionary)["beam"]) != 0.0:
		push_error("CONE: a torch carried by a body with no facing still throws a wedge -- it has nowhere to point")
		return false
	var lw: Variant = _world(LANTERN)
	var lantern_holder: int = int(lw.player)
	if lw.light.source_at(lantern_holder) == null or float((lw.light.source_at(lantern_holder) as Dictionary)["beam"]) != 0.0:
		push_error("CONE: a carried storm lantern reads a beam -- it throws round")
		return false
	if not _lit(lw, lantern_holder, HOLDER_TX - REACH_M, HOLDER_TY):
		push_error("CONE: a storm lantern does not light the tile 8 m behind its carrier")
		return false
	print("CONE OK a torch lights 8 m ahead, its spill and the tile its edge falls across, not 8 m behind or 45 degrees off; with no facing it throws round; a lantern lights both ways")
	return true


# TURN. Turning the holder north moves the wedge with them, and the light index recasts nothing: the
# round shadowcast stands, only the wedge is clipped to the new facing.
func _turning_moves_the_wedge_and_recasts_nothing() -> bool:
	var w: Variant = _world(TORCH)
	var holder: int = int(w.player)
	var before: int = int(w.light.recomputes)
	w.components.set_component(w.player, "facing", {"radians": -PI / 2.0})
	w.step()
	if not _lit(w, holder, HOLDER_TX, HOLDER_TY - REACH_M):
		push_error("TURN: turning north did not light the tile 8 m north")
		return false
	if _lit(w, holder, HOLDER_TX + REACH_M, HOLDER_TY):
		push_error("TURN: the tile 8 m east is still lit after turning north -- the wedge did not move")
		return false
	if int(w.light.recomputes) != before:
		push_error("TURN: turning recast the light (%d -> %d recomputes)" % [before, int(w.light.recomputes)])
		return false
	print("TURN OK turning north moves the wedge 8 m north and recasts nothing (%d recomputes)" % before)
	return true


# LEAN. A zombie four metres ahead of a torch, in the wedge and facing the holder, turns west toward
# the holder. One six metres behind it, outside the wedge and the spill, does not turn at all.
func _a_zombie_in_the_beam_leans_and_one_behind_does_not() -> bool:
	var w: Variant = _world(TORCH)
	var ahead: int = _zombie(w, HOLDER_TX + 4, HOLDER_TY, PI)
	var behind: int = _zombie(w, HOLDER_TX - 6, HOLDER_TY, 0.0)
	w.step()
	var pull_ahead: Dictionary = {"dx": 0.0, "dy": -1.0}
	SimShambler._lean_to_light(w, ahead, _pos(w, ahead), pull_ahead)
	if not (float(pull_ahead["dx"]) < -EPS):
		push_error("LEAN: a zombie four metres into the beam did not turn west toward the torch (dx %f)" % float(pull_ahead["dx"]))
		return false
	var pull_behind: Dictionary = {"dx": 0.0, "dy": -1.0}
	SimShambler._lean_to_light(w, behind, _pos(w, behind), pull_behind)
	if absf(float(pull_behind["dx"])) > EPS or absf(float(pull_behind["dy"]) + 1.0) > EPS:
		push_error("LEAN: a zombie six metres behind the torch turned toward it (dx %f, dy %f)" % [float(pull_behind["dx"]), float(pull_behind["dy"])])
		return false
	print("LEAN OK a zombie in the beam turns toward the torch (dx %.3f); one six metres behind does not (dx %.3f)" % [float(pull_ahead["dx"]), float(pull_behind["dx"])])
	return true


# A round light is unchanged: a lantern pulls the zombie six metres behind it, as it always has.
func _a_lantern_pulls_the_zombie_behind() -> bool:
	var w: Variant = _world(LANTERN)
	var behind: int = _zombie(w, HOLDER_TX - 6, HOLDER_TY, 0.0)
	w.step()
	var pull: Dictionary = {"dx": 0.0, "dy": -1.0}
	SimShambler._lean_to_light(w, behind, _pos(w, behind), pull)
	if not (float(pull["dx"]) > EPS):
		push_error("LEAN: a lantern did not pull a zombie six metres behind its carrier toward it (dx %f)" % float(pull["dx"]))
		return false
	print("LEAN OK a storm lantern still pulls a zombie six metres behind (dx %.3f)" % float(pull["dx"]))
	return true


# SIGHT. At night, a survivor sees farther along a torch's beam than behind it.
func _the_beam_helps_the_holder_see_further() -> bool:
	var w: Variant = _world(TORCH, true)
	var holder: int = int(w.player)
	var observer: Dictionary = w.components.get_component(holder, "observer") as Dictionary
	var ahead: float = SimLightIndex.sight_metres(w, observer, _mid(HOLDER_TX + 6), _mid(HOLDER_TY))
	var behind: float = SimLightIndex.sight_metres(w, observer, _mid(HOLDER_TX - 6), _mid(HOLDER_TY))
	if not (ahead > behind + 1.0):
		push_error("SIGHT: at night the holder sees %.2f m along the beam and %.2f m behind it -- the beam does not reach sight" % [ahead, behind])
		return false
	print("SIGHT OK at night the holder sees %.1f m along the beam and %.1f m behind it" % [ahead, behind])
	return true


# SAVE. The beam is part of the carried light and comes back with a load: the restored holder throws
# the same wedge the saved one did.
func _the_beam_survives_a_save() -> bool:
	var w: Variant = _world(TORCH)
	var holder: int = int(w.player)
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save_or_throw(text)
	var back: Variant = _world("")
	back.restore(decoded["snapshot"] as Dictionary)
	var source: Variant = back.components.get_component(holder, "light_source")
	if not (source is Dictionary) or absf(float((source as Dictionary).get("beam", 0.0)) - float(w.components.get_component(holder, "light_source").get("beam", 0.0))) > EPS:
		push_error("SAVE: the torch's beam did not survive a save")
		return false
	back.light.refresh(back, back.tilemap)
	if not _lit(back, holder, HOLDER_TX + REACH_M, HOLDER_TY) or _lit(back, holder, HOLDER_TX - REACH_M, HOLDER_TY):
		push_error("SAVE: the restored torch does not throw its wedge")
		return false
	print("SAVE OK the beam is in the save and the restored torch throws the same wedge")
	return true


# READS. `lit_metres` answers the wedge, not the round cast: a point 6 m ahead is lit and one 6 m
# behind is not. `_lean_to_light` is proved by LEAN above. LightLook's light map carries the torch's
# bit on the tile 6 m ahead and not on the one 6 m behind, which the round cast reaches -- so the
# screen reads `lights_tile`, not the cast.
func _the_beam_reaches_the_reader() -> bool:
	var w: Variant = _world(TORCH)
	if not (w.light.lit_metres(_mid(HOLDER_TX + 6), _mid(HOLDER_TY)) > 0.0):
		push_error("READS: lit_metres does not light the wedge 6 m ahead of the torch")
		return false
	if w.light.lit_metres(_mid(HOLDER_TX - 6), _mid(HOLDER_TY)) > 0.0:
		push_error("READS: lit_metres lights 6 m behind a torch -- it reads the round cast, not lights_tile")
		return false
	var holder: int = int(w.player)
	var texels: Dictionary = LightLook.light_texels(w, holder, Rect2i(0, 0, MAP_TILES, MAP_TILES))
	var lights: Array = texels["lights"] as Array
	if lights.size() != 1 or int((lights[0] as Dictionary)["entity"]) != holder:
		push_error("READS: the light map does not carry the torch as its one source (%s)" % str(lights))
		return false
	var seen: Variant = w.vision.tiles_for(holder)
	if not bool((w.light.tiles_for(holder) as Object).call("has_tile", HOLDER_TX - 6, HOLDER_TY)) or not bool((seen as Object).call("has_tile", HOLDER_TX - 6, HOLDER_TY)):
		push_error("READS: the tile 6 m behind is not in the torch's round cast and the holder's sight -- the screen half has nothing to judge")
		return false
	if _bit(texels, HOLDER_TX + 6, HOLDER_TY) != 1 or _bit(texels, HOLDER_TX - 6, HOLDER_TY) != 0:
		push_error("READS: LightLook's light map carries the torch's bit %d ahead and %d behind -- it reads the round cast, not lights_tile" % [_bit(texels, HOLDER_TX + 6, HOLDER_TY), _bit(texels, HOLDER_TX - 6, HOLDER_TY)])
		return false
	print("READS OK lit_metres reads the wedge; _lean_to_light is proved by LEAN; LightLook's light map lights the tile 6 m ahead and not the one 6 m behind")
	return true


func _bit(texels: Dictionary, tx: int, ty: int) -> int:
	return int((texels["bytes"] as PackedByteArray)[(ty * MAP_TILES + tx) * 4 + 1]) & 1


func _zombie(w: Variant, tx: int, ty: int, facing: float) -> int:
	var z: int = int(w.entities.spawn())
	w.components.set_component(z, "position", {"x": _mid(tx), "y": _mid(ty)})
	w.components.set_component(z, "observer", SimVisibility.daylight_eyes())
	w.components.set_component(z, "facing", {"radians": facing})
	return z


func _pos(w: Variant, entity: int) -> Dictionary:
	return (w.components.get_component(entity, "position") as Dictionary).duplicate()

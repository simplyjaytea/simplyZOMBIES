extends SceneTree
# Civic annex overlay: blit is confined to rect; loot tables place; 256 m playable boot.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimBoot = preload("res://sim/boot.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const ContentValidator = preload("res://platform/content_validator.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _content_valid() and ok
	ok = _blit_confined() and ok
	ok = _annex_shell() and ok
	ok = _playable_boot() and ok
	ok = _two_worlds_do_not_share_an_attention_field() and ok
	if ok:
		print("M2_DISTRICT_OK validate blit annex boot isolation")
		quit(0)
	else:
		push_error("M2_DISTRICT_FAIL")
		quit(1)

func _content_valid() -> bool:
	var issues: Array = ContentValidator.validate_tree("res://content")
	if not issues.is_empty():
		push_error("content invalid: %s" % str(issues[0]))
		return false
	print("CONTENT OK")
	return true

func _blit_confined() -> bool:
	var seed_val: int = 20260805
	var raw: Variant = SimTileMap.generate_district(seed_val, 64)
	var patched: Variant = SimTileMap.generate_district(seed_val, 64)
	var content: Dictionary = ContentLoader.load_tree()
	var patch: Variant = SimTileMap.load_patch_from_content(content, "map.district.alpha")
	if not patch is Dictionary:
		push_error("missing district_alpha patch")
		return false
	SimTileMap.apply_patch(patched, patch as Dictionary)
	var rect: Dictionary = (patch as Dictionary)["rect"] as Dictionary
	var rx: int = int(rect["x"])
	var ry: int = int(rect["y"])
	var rw: int = int(rect["w"])
	var rh: int = int(rect["h"])
	var changed: int = 0
	var leaked: int = 0
	for y in 64:
		for x in 64:
			var a: int = int(raw.tiles[y * raw.w + x])
			var b: int = int(patched.tiles[y * patched.w + x])
			var inside: bool = x >= rx and x < rx + rw and y >= ry and y < ry + rh
			if a != b:
				changed += 1
				if not inside:
					leaked += 1
	if leaked != 0:
		push_error("patch leaked %d tiles outside rect" % leaked)
		return false
	if changed == 0:
		push_error("patch changed nothing")
		return false
	print("BLIT OK changed=%d leaked=0" % changed)
	return true

func _annex_shell() -> bool:
	var content: Dictionary = ContentLoader.load_tree()
	var patch: Variant = SimTileMap.load_patch_from_content(content, "map.district.alpha")
	var map: Variant = SimTileMap.generate_district(20260805, 64)
	SimTileMap.apply_patch(map, patch as Dictionary)
	var windows: int = 0
	var screens: int = 0
	var lows: int = 0
	var indoors: int = 0
	var rect: Dictionary = (patch as Dictionary)["rect"] as Dictionary
	for j in int(rect["h"]):
		for i in int(rect["w"]):
			var tx: int = int(rect["x"]) + i
			var ty: int = int(rect["y"]) + j
			var t: int = SimTileMap.tile_at(map, tx, ty)
			if t == SimTileMap.Tile.Window:
				windows += 1
			elif t == SimTileMap.Tile.Screen:
				screens += 1
			elif t == SimTileMap.Tile.Low:
				lows += 1
			if SimTileMap.is_indoors(map, tx, ty):
				indoors += 1
	if windows < 6:
		push_error("annex windows %d < 6" % windows)
		return false
	if screens < 1 or lows < 1:
		push_error("annex missing screen/low s=%d l=%d" % [screens, lows])
		return false
	if indoors < 20:
		push_error("annex indoors %d" % indoors)
		return false
	# Gate: three floor tiles on the south door.
	var gate: int = 0
	if SimTileMap.tile_at(map, 50, 57) == SimTileMap.Tile.Floor:
		gate += 1
	if SimTileMap.tile_at(map, 51, 57) == SimTileMap.Tile.Floor:
		gate += 1
	if SimTileMap.tile_at(map, 52, 57) == SimTileMap.Tile.Floor:
		gate += 1
	if gate < 2:
		push_error("gate missing at 50–52,57")
		return false
	print("ANNEX OK windows=%d screens=%d indoors=%d" % [windows, screens, indoors])
	return true

func _playable_boot() -> bool:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	var world: Variant = boot["world"]
	if int(world.map_width) != 64:
		push_error("playable map %d" % world.map_width)
		return false
	var zeds: int = 0
	var screamers: int = 0
	var bloaters: int = 0
	for e in world.components.query(["shambler"]):
		zeds += 1
		var zt: Variant = world.components.get_component(int(e), "zombieType")
		var id: String = String((zt as Dictionary).get("id", "")) if zt is Dictionary else ""
		if id == "zombie.screamer":
			screamers += 1
		elif id == "zombie.bloater":
			bloaters += 1
	if zeds != SimBoot.WANDERERS or screamers != 0 or bloaters != 0:
		push_error("day-1 boot z=%d s=%d b=%d want %d shamblers" % [zeds, screamers, bloaters, SimBoot.WANDERERS])
		return false
	var ground: int = 0
	for e2 in world.components.query(["itemBase", "position"]):
		if world.components.has_component(int(e2), "stored"):
			continue
		ground += 1
	if ground < 5:
		push_error("loot missing ground=%d" % ground)
		return false
	if not world.components.has_component(world.player, "meleeWeapon"):
		push_error("player not armed")
		return false
	print("BOOT OK zeds=%d loot=%d" % [zeds, ground])
	return true


# Two worlds, two attention fields. The spine (docs/03) is per-world state, and for as long as
# `attach_kernel` existed it was not: SimBoot kept "the last world that called attach_kernel" in a
# `static var` and the `noise.emitted` / `scent.accumulated` handlers wrote into *that* world's
# field rather than the field of the world that published. Measured before the fix -- boot A
# (seed 101), boot B (seed 102), publish magnitude 500 at (8,8) on A, step A -- A's own field read
# 0.0000 and B's read 500.0000. Every gate that boots a positive world and a negative world was
# reading the wrong field for anything about noise or scent, negative controls included, and three
# gates carried fixture comments explaining that they stayed off `attach_kernel` to dodge it.
#
# docs/30 records the same hazard twice already, for `putDown` and `mourned`: "a static would be
# shared between the two worlds a gate boots."
#
# Both directions, because "B got nothing" would also be true of a field that had stopped
# recording anything at all: A must receive its own noise, **and** B must receive none of it.
func _two_worlds_do_not_share_an_attention_field() -> bool:
	var a: Variant = SimBoot.bare(101, 32)["world"]
	var b: Variant = SimBoot.bare(102, 32)["world"]
	var cell_a: int = int(a.field.cell_at(8.0, 8.0))
	var cell_b: int = int(b.field.cell_at(8.0, 8.0))
	a.events.publish({"type": "noise.emitted", "x": 8.0, "y": 8.0, "magnitude": 500.0})
	a.step()
	var got_a: float = float(a.field.noise[cell_a])
	var got_b: float = float(b.field.noise[cell_b])
	if got_a <= 0.0:
		push_error("the world that published its own noise did not hear it: %.4f" % got_a)
		return false
	if got_b != 0.0:
		push_error("world A's noise landed in world B's field: A %.4f, B %.4f" % [got_a, got_b])
		return false

	# Same again for scent, which travels the other subscription.
	b.events.publish({"type": "scent.accumulated", "x": 8.0, "y": 8.0, "magnitude": 40.0})
	b.step()
	if float(b.field.scent[cell_b]) <= 0.0:
		push_error("world B did not receive its own scent: %.4f" % float(b.field.scent[cell_b]))
		return false
	if float(a.field.scent[cell_a]) != 0.0:
		push_error("world B's scent landed in world A's field: %.4f" % float(a.field.scent[cell_a]))
		return false
	print("ISOLATION OK A hears %.2f of its own noise and B hears none of it, both ways" % got_a)
	return true

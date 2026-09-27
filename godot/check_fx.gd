extends SceneTree
# The shot is seen (docs/23's outpost group, 2026-09-26): the muzzle flash, the ejected casing, the
# blood where a blow lands and the campfire's flame, drawn from sim events off four of the outpost
# pack's four-frame effect sheets by `presentation/fx_look.gd`, and blitted by `main.gd`'s
# `_draw_effects`. Every lane has a true positive and a true negative, because a gate that cannot
# fail is worse than no gate.
#
#   RATE     every authored `sheet` is the pack's own: its frames the manifest's frames in order,
#            its `fps`, `loop`, `anchor` and canvas equal to the manifest's, and `Appearance.sheet_of`
#            answering the same; the frame a sheet shows is chosen by that fps (a flash is over
#            after four twenty-fourths of a second, blood after four twelfths); and nothing in the
#            renderer loads a pack `.tres`. TN: a fabricated copy with the wrong fps, the wrong
#            anchor, a frame out of order, and a `.tres` load, each refused.
#   ADMITS   authored.json declares exactly the six sheets this slice draws -- three muzzle flashes,
#            the casing, the blood, the flame -- and none of the effects with no impact point
#            (sparks, dust, splinters, splash, explosion), the smoke, or a decal (docs/30, "The
#            whole outpost pack"). TN: a fabricated declaration adding the explosion, refused.
#   READS    every sheet is named by a content effect field (`fireFx`, `casingFx`, `hitFx`,
#            `flameFx`), and every key a content effect field names is a sheet. TN: a content set
#            missing one sheet, and a field naming a sheet that does not exist, each refused.
#   SHAPE    the nested-shape lane `godot:validate` cannot be (it is shallow): every content effect
#            field is a string of the `fx_` form, on the one kind that fires, bleeds or burns it
#            (`fireFx`/`casingFx` on an item, `hitFx` on a body, `flameFx` on a prop), and names an
#            authored sheet. TN: a field on the wrong kind, a number, and a key without the prefix,
#            each refused by the same predicate.
#   SHOT     a real pistol fired through the real sim starts a flash at the held pistol's muzzle
#            (a light, drawn over the night) and a casing (a thing, drawn under it); the same trigger
#            on a bow starts neither, and no events start nothing.
#   UNSEEN   a shot, and a blow, where the player cannot see -- behind them, and at the edge of the
#            eye where only a Peripheral glimpse reaches -- start nothing; the same events in Focal
#            view do. A one-shot started in view and then turned away from stops drawing, and
#            draws again once the player looks back.
#   SAME     a graze on a hand, a killing blow to the head and a bite (which the sim may present as
#            a scratch) draw the identical blood, frame for frame and pixel for pixel; the comparison
#            says no to the same blood on a different body. And no reader of the blow in fx_look.gd
#            touches its damage or the part it struck.
#   KINDS    every body kind in content -- zombies, raiders, the player, the uniques, the colony and
#            raider looks -- names a blood sheet, and `Appearance.body_look_id` finds the look a body
#            is drawn with for the player, a zombie, a person and a raider. TN: a body with no look
#            resolves none and bleeds nothing.
#   FLAME    a lit campfire the player sees draws its flame, looping on the presentation clock; an
#            unlit one, and a lit one the player does not see, draw none.
#   DRAWN    the dead-socket lane, executing: the real scene boots, and one frame of `main.gd`'s
#            `_draw` blits every sheet this slice declares; a frame with nothing live blits no
#            one-shot. And `_process` feeds the drained events and the clock, read out of its body.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")
const FxLook = preload("res://presentation/fx_look.gd")

const AUTHORED_PATH: String = "res://assets/sprites/authored.json"
const PACK_MANIFEST_PATH: String = "res://art/simplyzombies/manifest.json"
const PACK_ROOT: String = "art/simplyzombies/"
const MAIN_GD: String = "res://presentation/main.gd"
const FX_GD: String = "res://presentation/fx_look.gd"
const APPEARANCE_GD: String = "res://presentation/appearance.gd"
const SCENE_PATH: String = "res://presentation/main.tscn"

# The six sheets this slice draws, and the pack's effect ids they are cut from.
const ADMITTED: Dictionary = {
	"fx_blood_hit": "fx-blood-hit",
	"fx_ejected_casing": "fx-ejected-casing",
	"fx_flame_loop": "fx-flame-loop",
	"fx_pistol_muzzle": "fx-pistol-muzzle",
	"fx_rifle_muzzle": "fx-rifle-muzzle",
	"fx_shotgun_muzzle": "fx-shotgun-muzzle",
}
# What stays in the report (docs/30, "The whole outpost pack"): the effects with no impact point,
# the smoke with no source, and every decal. Named so a later declaration of one is red here.
const REFUSED: Array[String] = ["fx_metal_sparks", "fx_concrete_dust", "fx_wood_splinters", "fx_water_splash",
	"fx_explosion", "fx_smoke_loop", "fx_blood_pool_dry", "fx_blood_pool_fresh", "fx_bullet_hole_metal",
	"fx_bullet_hole_concrete", "fx_scorch_mark", "fx_wood_chips", "fx_shell_pile", "fx_footprint"]
const WALL_X: int = 4
const EFFECT_FIELDS: Array[String] = ["fireFx", "casingFx", "hitFx", "flameFx"]
const BODY_KINDS: Array[String] = ["zombies/", "raiders/", "players/", "survivors/uniques/", "colony/looks"]

# A frame's worth of wall clock, and the camera every pure lane draws through.
const CAMERA: Dictionary = {"x": 12.0, "y": 12.0, "zoom": 64.0, "width": 1280.0, "height": 720.0}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _every_sheet_is_the_packs_own_at_its_own_rate() and ok
	ok = _only_the_effects_with_an_impact_point_are_admitted() and ok
	ok = _every_sheet_is_read_by_content() and ok
	ok = _every_effect_field_is_well_formed() and ok
	ok = _a_real_shot_starts_a_flash_and_a_casing() and ok
	ok = _what_the_player_does_not_see_draws_nothing() and ok
	ok = _blood_never_varies_with_the_blow() and ok
	ok = _every_body_kind_bleeds_the_same_sheet() and ok
	ok = _a_seen_lit_fire_burns() and ok
	var drawn: bool = await _the_draw_loop_blits_every_sheet()
	ok = drawn and ok
	if ok:
		print("FX_OK every sheet is the pack's own at the manifest's rate and no pack .tres is loaded, only the effects with an impact point are admitted, every sheet is read by content, every effect field is well formed on its own kind, a real shot starts a flash at the muzzle and a casing while a bow starts neither, nothing the player does not see is drawn, blood never varies with the blow, every body kind bleeds the one sheet, a seen lit fire burns and nothing else does, and main.gd's draw loop blits every sheet")
		quit(0)
	else:
		push_error("FX_FAIL")
		quit(1)


# --- fixtures -----------------------------------------------------------------------------

# check_m2_ranged.gd's fixture: a blank 24x24 map in daylight, the player at (8, 12) facing east.
func _world() -> Variant:
	var f: Dictionary = {"seed": 21, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	# A wall down column 4, four tiles behind the player: what is west of it is out of sight in
	# every direction the player faces, which is what a tile outside the seen set needs.
	for y in 24:
		map.tiles[y * 24 + WALL_X] = SimTileMap.Tile.Wall
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	# The player's eyes, which the ranged fixture never needed: every lane here asks what they see.
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.step()
	w.events.drain()
	return w


# The first point at `metres` from the player whose detail is `want` and whose two neighbours five
# degrees either side are too, scanning the compass -- a point in the middle of its band rather than
# on the edge of it, where a nearby body widening the eye would tip it over; or Vector2.INF when the
# fixture has none (the lane says so rather than passing).
func _spot(w: Variant, want: int, metres: float) -> Vector2:
	var p: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	for i in 72:
		var inside: bool = true
		for k in [-1, 0, 1]:
			var a: float = TAU * float(i + k) / 72.0
			if int(w.vision.detail(int(w.player), float(p["x"]) + cos(a) * metres, float(p["y"]) + sin(a) * metres)) != want:
				inside = false
		if inside:
			var at: float = TAU * float(i) / 72.0
			return Vector2(float(p["x"]) + cos(at) * metres, float(p["y"]) + sin(at) * metres)
	return Vector2.INF


func _shambler_at(w: Variant, at: Vector2) -> int:
	var z: int = SimRoster.spawn_zombie(w, at.x, at.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	return z


func _move(w: Variant, ent: int, at: Vector2) -> void:
	w.components.set_component(ent, "position", {"x": at.x, "y": at.y})


func _keys(draws: Array) -> Array:
	var out: Array = []
	for d in draws:
		out.append(String((d as Dictionary)["key"]))
	return out


func _authored() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_PATH))
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("keys", {}) as Dictionary


func _sheets_declared() -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = _authored()
	for key in keys.keys():
		if String((keys[key] as Dictionary).get("kind", "")) == "sheet":
			out[String(key)] = keys[key]
	return out


func _pack_asset(asset_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_MANIFEST_PATH))
	if not (parsed is Dictionary):
		return {}
	for a in (parsed as Dictionary).get("assets", []) as Array:
		if a is Dictionary and String((a as Dictionary).get("id", "")) == asset_id:
			return a as Dictionary
	return {}


# --- RATE ---------------------------------------------------------------------------------

# What is wrong with one sheet's declaration against the manifest asset it is cut from, or "".
func _rate_complaint(key: String, entry: Dictionary, asset: Dictionary) -> String:
	if asset.is_empty():
		return "is cut from no manifest effect"
	if String(asset.get("category", "")) != "effects":
		return "is cut from a manifest asset of category '%s', not an effect" % String(asset.get("category", ""))
	if int(entry.get("fps", -1)) != int(asset.get("fps", -2)):
		return "plays at %s fps where the manifest says %s" % [str(entry.get("fps")), str(asset.get("fps"))]
	if bool(entry.get("loop", false)) != bool(asset.get("loop", false)):
		return "loops %s where the manifest says %s" % [str(entry.get("loop")), str(asset.get("loop"))]
	var anchor: Array = entry.get("anchor", []) as Array
	var want_anchor: Array = asset.get("anchor", []) as Array
	if anchor.size() != 2 or want_anchor.size() != 2 or int(anchor[0]) != int(want_anchor[0]) or int(anchor[1]) != int(want_anchor[1]):
		return "anchors at %s where the manifest says %s" % [str(anchor), str(want_anchor)]
	var canvas: Array = entry.get("canvas", []) as Array
	var size: Array = asset.get("size", []) as Array
	if canvas.size() != 2 or size.size() != 2 or int(canvas[0]) != int(size[0]) or int(canvas[1]) != int(size[1]):
		return "declares canvas %s where the manifest's frame is %s" % [str(canvas), str(size)]
	var frames_v: Variant = (asset.get("frames", {}) as Dictionary).values()
	var frames: Array = ((frames_v as Array)[0] as Array) if (frames_v as Array).size() == 1 else []
	var members: Dictionary = entry.get("members", {}) as Dictionary
	if frames.is_empty() or members.size() != frames.size():
		return "has %d frames where the manifest has %d" % [members.size(), frames.size()]
	for i in frames.size():
		var member: String = "%s_%d" % [key, i]
		var path: String = String(((members.get(member, {}) as Dictionary).get("source", {}) as Dictionary).get("path", ""))
		if path != PACK_ROOT + String((frames[i] as Dictionary).get("path", "")):
			return "frame %d ('%s') is cut from '%s', not the manifest's frame %d" % [i, member, path, i]
	return ""


# Whether a source text loads a `.tres`: the pack's docs/godot/*.tres are null headless (the UI
# kit's trap), and frame rates come from the manifest's copy in authored.json instead.
func _loads_a_tres(text: String) -> bool:
	var re := RegEx.new()
	re.compile("load\\([^)]*\\.tres")
	return re.search(text) != null


func _every_sheet_is_the_packs_own_at_its_own_rate() -> bool:
	var sheets: Dictionary = _sheets_declared()
	if sheets.is_empty():
		push_error("RATE: authored.json declares no sheet; the lane had nothing to judge")
		return false
	var real_key: String = ""
	for key in sheets.keys():
		var entry: Dictionary = sheets[key] as Dictionary
		var asset: Dictionary = _pack_asset(String(ADMITTED.get(key, "")))
		var complaint: String = _rate_complaint(String(key), entry, asset)
		if not complaint.is_empty():
			push_error("RATE: '%s' %s" % [String(key), complaint])
			return false
		var read: Dictionary = Appearance.sheet_of(String(key))
		if int(read.get("fps", -1)) != int(entry["fps"]) or bool(read.get("loop", false)) != bool(entry.get("loop", false)) \
				or (read.get("frames", []) as Array).size() != (entry["members"] as Dictionary).size() \
				or read.get("anchor") != Vector2i(int((entry["anchor"] as Array)[0]), int((entry["anchor"] as Array)[1])):
			push_error("RATE: the renderer reads '%s' as %s, not as authored.json declares it" % [String(key), str(read)])
			return false
		if real_key.is_empty() or String(key) == "fx_pistol_muzzle":
			real_key = String(key)

	# True negatives, each a real declaration broken one way.
	var real: Dictionary = sheets[real_key] as Dictionary
	var asset_real: Dictionary = _pack_asset(String(ADMITTED[real_key]))
	var slow: Dictionary = real.duplicate(true)
	slow["fps"] = int(real["fps"]) / 2
	var shifted: Dictionary = real.duplicate(true)
	shifted["anchor"] = [int((real["anchor"] as Array)[0]) + 1, int((real["anchor"] as Array)[1])]
	var shuffled: Dictionary = real.duplicate(true)
	var m: Dictionary = shuffled["members"] as Dictionary
	var first: Variant = m["%s_0" % real_key]
	m["%s_0" % real_key] = m["%s_1" % real_key]
	m["%s_1" % real_key] = first
	for case in [[slow, "half the manifest's fps"], [shifted, "an anchor one pixel off"], [shuffled, "two frames swapped"]]:
		if _rate_complaint(real_key, case[0] as Dictionary, asset_real).is_empty():
			push_error("RATE: %s passed; the lane cannot say no to it" % String(case[1]))
			return false

	# The frame is chosen by the sheet's own rate: at 24 fps a flash is on its third frame 0.1 s in
	# and over by 0.17 s; at 12 fps blood is on its second frame at 0.1 s and still going at 0.3 s.
	var flash: Dictionary = Appearance.sheet_of("fx_pistol_muzzle")
	var blood: Dictionary = Appearance.sheet_of("fx_blood_hit")
	var flame: Dictionary = Appearance.sheet_of("fx_flame_loop")
	var checks: Array = [
		[FxLook.frame_at(0.1, int(flash["fps"]), 4, false), 2, "a 24 fps flash 0.1 s in"],
		[FxLook.frame_at(0.17, int(flash["fps"]), 4, false), -1, "a 24 fps flash 0.17 s in"],
		[FxLook.frame_at(0.1, int(blood["fps"]), 4, false), 1, "12 fps blood 0.1 s in"],
		[FxLook.frame_at(0.3, int(blood["fps"]), 4, false), 3, "12 fps blood 0.3 s in"],
		[FxLook.frame_at(0.6, int(flame["fps"]), 4, true), 0, "an 8 fps flame 0.6 s in, wrapped"],
		[FxLook.frame_at(0.6, int(flame["fps"]), 4, true, 3), 3, "the same flame a phase of 3 on"],
	]
	for c in checks:
		if int(c[0]) != int(c[1]):
			push_error("RATE: %s shows frame %d, not %d" % [String(c[2]), int(c[0]), int(c[1])])
			return false
	# TN: the same age at the wrong rate is a different frame, so the check above can tell.
	if FxLook.frame_at(0.1, int(blood["fps"]), 4, false) == FxLook.frame_at(0.1, int(flash["fps"]), 4, false):
		push_error("RATE: two rates show one frame at 0.1 s; the rate check cannot tell them apart")
		return false

	for path in [FX_GD, APPEARANCE_GD, MAIN_GD]:
		if _loads_a_tres(FileAccess.get_file_as_string(path)):
			push_error("RATE: %s loads a .tres; the pack's .tres files are null headless and the rate is authored.json's copy of the manifest" % path)
			return false
	if not _loads_a_tres("var s = load(\"res://art/simplyzombies/docs/godot/fx-blood-hit.tres\")"):
		push_error("RATE: the .tres scan passed a load of one; it cannot say no")
		return false

	print("RATE OK %d sheets are the pack's own frames in order at the manifest's fps, loop, anchor and frame size, read the same by the renderer; the frame is chosen by that rate; no pack .tres is loaded; half the rate, a shifted anchor, swapped frames and a .tres load refused" % sheets.size())
	return true


# --- ADMITS -------------------------------------------------------------------------------

func _admits_complaint(declared: Array) -> String:
	for key in REFUSED:
		if declared.has(key):
			return "declares '%s', which docs/30 keeps in the report" % key
	for key in ADMITTED.keys():
		if not declared.has(key):
			return "does not declare '%s'" % String(key)
	for key in declared:
		if not ADMITTED.has(key):
			return "declares '%s', which this slice never admitted" % String(key)
	return ""


func _only_the_effects_with_an_impact_point_are_admitted() -> bool:
	var declared: Array = _sheets_declared().keys()
	for key in _authored().keys():
		if String(key).begins_with("fx_") and not declared.has(key):
			push_error("ADMITS: '%s' is an fx_ key that is not a sheet" % String(key))
			return false
	var complaint: String = _admits_complaint(declared)
	if not complaint.is_empty():
		push_error("ADMITS: authored.json %s" % complaint)
		return false
	var widened: Array = declared.duplicate()
	widened.append("fx_explosion")
	if _admits_complaint(widened).is_empty():
		push_error("ADMITS: a declaration adding the explosion passed; the lane cannot say no")
		return false
	print("ADMITS OK exactly the %d admitted sheets are declared and none of the %d kept in the report; the explosion added is refused" % [ADMITTED.size(), REFUSED.size()])
	return true


# --- READS --------------------------------------------------------------------------------

# `{sheet key: [content ids]}` for every content effect field.
func _effect_readers() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var raw: Variant = tree[path]
		for entry_v in (raw as Array if raw is Array else [raw]):
			if not (entry_v is Dictionary):
				continue
			var block: Variant = (entry_v as Dictionary).get("appearance")
			if not (block is Dictionary):
				continue
			for field in EFFECT_FIELDS:
				if (block as Dictionary).has(field):
					var key: String = String((block as Dictionary)[field])
					var readers: Array = out.get(key, [])
					readers.append(String((entry_v as Dictionary).get("id", "?")))
					out[key] = readers
	return out


func _reads_complaint(sheets: Array, readers: Dictionary) -> String:
	for key in sheets:
		if not readers.has(key):
			return "'%s' is named by no content effect field: art nothing draws" % String(key)
	for key in readers.keys():
		if not sheets.has(key):
			return "content names '%s' (%s), which is no authored sheet" % [String(key), str(readers[key])]
	return ""


func _every_sheet_is_read_by_content() -> bool:
	var sheets: Array = _sheets_declared().keys()
	var readers: Dictionary = _effect_readers()
	var complaint: String = _reads_complaint(sheets, readers)
	if not complaint.is_empty():
		push_error("READS: %s" % complaint)
		return false
	for key in sheets:
		var claim: String = String((_sheets_declared()[key] as Dictionary).get("reads", ""))
		if not (readers[key] as Array).has(claim):
			push_error("READS: authored.json says '%s' is read by '%s'; the content that names it is %s" % [String(key), claim, str(readers[key])])
			return false
	var missing: Dictionary = readers.duplicate(true)
	missing.erase("fx_flame_loop")
	var stray: Dictionary = readers.duplicate(true)
	stray["fx_not_a_sheet"] = ["item.gate"]
	if _reads_complaint(sheets, missing).is_empty() or _reads_complaint(sheets, stray).is_empty():
		push_error("READS: a sheet with no reader, or a reader naming no sheet, passed; the lane cannot say no")
		return false
	print("READS OK %d sheets are each named by a content effect field and every effect field names a sheet; an unread sheet and a stray field refused" % sheets.size())
	return true


# --- SHAPE ----------------------------------------------------------------------------------

const FIELD_KINDS: Dictionary = {
	"fireFx": ["items/"],
	"casingFx": ["items/"],
	"hitFx": ["zombies/", "raiders/", "players/", "survivors/", "colony/looks"],
	"flameFx": ["props/"],
}


func _field_complaint(field: String, value: Variant, path: String, sheets: Array) -> String:
	var placed: bool = false
	for prefix in FIELD_KINDS.get(field, []) as Array:
		if path.begins_with(String(prefix)):
			placed = true
	if not placed:
		return "carries %s, which belongs on %s only" % [field, str(FIELD_KINDS.get(field, []))]
	if not (value is String):
		return "gives %s a %s, not a sheet key" % [field, type_string(typeof(value))]
	var re := RegEx.new()
	re.compile("^fx_[a-z0-9_]+$")
	if re.search(String(value)) == null:
		return "gives %s '%s', which is not an fx_ key" % [field, String(value)]
	if not sheets.has(String(value)):
		return "gives %s '%s', which is no authored sheet" % [field, String(value)]
	return ""


func _every_effect_field_is_well_formed() -> bool:
	var sheets: Array = _sheets_declared().keys()
	var tree: Dictionary = ContentLoader.load_tree()
	var judged: int = 0
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var raw: Variant = tree[path]
		for entry_v in (raw as Array if raw is Array else [raw]):
			if not (entry_v is Dictionary) or not ((entry_v as Dictionary).get("appearance") is Dictionary):
				continue
			var block: Dictionary = (entry_v as Dictionary)["appearance"] as Dictionary
			for field in EFFECT_FIELDS:
				if not block.has(field):
					continue
				var complaint: String = _field_complaint(field, block[field], String(path), sheets)
				if not complaint.is_empty():
					push_error("SHAPE: %s (%s) %s" % [String((entry_v as Dictionary).get("id", "?")), String(path), complaint])
					return false
				judged += 1
	if judged == 0:
		push_error("SHAPE: no content effect field was found; the lane had nothing to judge")
		return false
	for case in [["hitFx", "fx_blood_hit", "items/ranged.json", "blood on an item"], ["fireFx", 3, "items/ranged.json", "a number"],
			["flameFx", "flame_loop", "props/stations.json", "a key without the prefix"]]:
		if _field_complaint(String(case[0]), case[1], String(case[2]), sheets).is_empty():
			push_error("SHAPE: %s passed; the lane cannot say no to it" % String(case[3]))
			return false
	print("SHAPE OK %d content effect fields are fx_ strings on their own kind naming an authored sheet; blood on an item, a number and an unprefixed key refused" % judged)
	return true


# --- SHOT ---------------------------------------------------------------------------------

func _fire(w: Variant, fx: RefCounted) -> void:
	w.commands.push({"type": "fire"})
	for i in 40:
		w.step()
		fx.call("from_events", w, w.events.drained)
		var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
		if rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle and i > 0:
			break


func _a_real_shot_starts_a_flash_and_a_casing() -> bool:
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	SimInventory.stow(w, w.player, SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 20}))
	w.events.drain()
	var idle: RefCounted = FxLook.new()
	idle.call("from_events", w, [])
	if not (idle.get("live") as Array).is_empty():
		push_error("SHOT: no events started a one-shot")
		return false
	var fx: RefCounted = FxLook.new()
	_fire(w, fx)
	var lights: Array = fx.call("draws", w, CAMERA, true)
	var things: Array = fx.call("draws", w, CAMERA, false)
	if _keys(lights) != ["fx_pistol_muzzle"] or _keys(things) != ["fx_ejected_casing"]:
		push_error("SHOT: a pistol shot drew lights %s and things %s, not the pistol flash over the night and a casing under it" % [str(_keys(lights)), str(_keys(things))])
		return false
	# The flash's anchor pixel lands on the held pistol's muzzle, not on the hand.
	var held: String = "item_held_pistol"
	var slot: String = "secondary"
	var hand: Vector2i = (Appearance.HELD_HANDS[slot] as Dictionary)["e"] as Vector2i
	var size := Vector2i(Appearance.resolve(held).get_size())
	var pose: Dictionary = Appearance.held_pose(size, Appearance.grip_of(held), hand, "e")
	var muzzle: Vector2i = Appearance.held_point(pose, size, Appearance.muzzle_of(held), "e")
	var record: Dictionary = {}
	for r in fx.get("live") as Array:
		if String((r as Dictionary)["key"]) == "fx_pistol_muzzle":
			record = r as Dictionary
	if record.is_empty() or record["point"] != muzzle or muzzle == hand or Appearance.muzzle_of(held).x < 0:
		push_error("SHOT: the flash stands at %s; the held pistol's muzzle is %s and the hand %s" % [str(record.get("point")), str(muzzle), str(hand)])
		return false

	# TN: the same trigger on a bow is a real `weapon.fired` whose item names no flash and no casing.
	var bw: Variant = _world()
	var bow: int = SimItems.spawn_item(bw, "item.bow.hunting", {"tier": "scavenged"})
	SimInventory.equip(bw, bw.player, bow)
	SimInventory.stow(bw, bw.player, SimItems.spawn_item(bw, "item.ammo.arrow", {"tier": "scavenged", "count": 6}))
	bw.events.drain()
	var bow_fx: RefCounted = FxLook.new()
	var fired: Array = [false]
	bw.commands.push({"type": "fire"})
	for i in 40:
		bw.step()
		for e in bw.events.drained:
			if String((e as Dictionary).get("type", "")) == "weapon.fired":
				fired[0] = true
		bow_fx.call("from_events", bw, bw.events.drained)
	if not bool(fired[0]):
		push_error("SHOT: the bow never fired, so the true negative had nothing to judge")
		return false
	if not (bow_fx.get("live") as Array).is_empty():
		push_error("SHOT: a bow shot started %s; a bow makes no flame and keeps no brass" % str(_keys(bow_fx.get("live") as Array)))
		return false
	print("SHOT OK a real pistol shot drew the pistol flash over the night with its anchor on the held pistol's muzzle %s (the hand is %s) and a casing under it; a real bow shot and no events started nothing" % [str(muzzle), str(hand)])
	return true


# --- UNSEEN -------------------------------------------------------------------------------

func _what_the_player_does_not_see_draws_nothing() -> bool:
	var w: Variant = _world()
	var focal: Vector2 = _spot(w, SimVisibility.Detail.Focal, 4.0)
	var side: Vector2 = _spot(w, SimVisibility.Detail.Peripheral, 4.0)
	var behind: Vector2 = _spot(w, SimVisibility.Detail.Unseen, 4.0)
	if focal == Vector2.INF or side == Vector2.INF or behind == Vector2.INF:
		push_error("UNSEEN: the fixture has no Focal, Peripheral or Unseen spot (%s, %s, %s); nothing to judge" % [str(focal), str(side), str(behind)])
		return false
	var z: int = _shambler_at(w, behind)
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	var shot: Array = [{"type": "weapon.fired", "entity": z, "item": pistol}]
	var blow: Array = [{"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "torso", "damage": 10.0}]
	for at in [[behind, "behind the player"], [side, "at the edge of the eye (Peripheral)"]]:
		_move(w, z, at[0] as Vector2)
		var fx: RefCounted = FxLook.new()
		fx.call("from_events", w, shot + blow)
		if not (fx.get("live") as Array).is_empty():
			push_error("UNSEEN: a shot and a blow %s (detail %d at %s) started %s" % [String(at[1]), int(w.vision.detail(int(w.player), (at[0] as Vector2).x, (at[0] as Vector2).y)), str(at[0]), str(_keys(fx.get("live") as Array))])
			return false
	_move(w, z, focal)
	var seen_fx: RefCounted = FxLook.new()
	seen_fx.call("from_events", w, shot + blow)
	var drawn: Array = _keys(seen_fx.call("draws", w, CAMERA, true) as Array) + _keys(seen_fx.call("draws", w, CAMERA, false) as Array)
	drawn.sort()
	if drawn != ["fx_blood_hit", "fx_ejected_casing", "fx_pistol_muzzle"]:
		push_error("UNSEEN: the same shot and blow in Focal view drew %s" % str(drawn))
		return false

	# Started in view, then turned away from: kept, not drawn; and drawn again on looking back.
	var p: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	var toward: float = atan2(focal.y - float(p["y"]), focal.x - float(p["x"]))
	w.components.set_component(w.player, "facing", {"radians": toward + PI})
	w.step()
	if not (seen_fx.call("draws", w, CAMERA, false) as Array).is_empty():
		push_error("UNSEEN: blood started in view still drew once the player turned away from it")
		return false
	if (seen_fx.get("live") as Array).is_empty():
		push_error("UNSEEN: turning away deleted the one-shots rather than hiding them")
		return false
	w.components.set_component(w.player, "facing", {"radians": toward})
	w.step()
	if _keys(seen_fx.call("draws", w, CAMERA, false) as Array).is_empty():
		push_error("UNSEEN: looking back did not draw the blood again; the re-check cannot say yes")
		return false
	print("UNSEEN OK a shot and a blow behind the player and at the edge of the eye started nothing; in Focal view they drew the flash, the casing and the blood; turned away they stayed live and undrawn, and looking back drew them again")
	return true


# --- SAME ---------------------------------------------------------------------------------

func _blood_of(w: Variant, events: Array) -> Array:
	var fx: RefCounted = FxLook.new()
	fx.call("advance", 0.1)
	fx.call("from_events", w, events)
	fx.call("advance", 0.1)
	var out: Array = []
	for d in fx.call("draws", w, CAMERA, false) as Array:
		out.append([String((d as Dictionary)["key"]), int((d as Dictionary)["frame"]), (d as Dictionary)["rect"], (d as Dictionary)["texture"]])
	return out


# The function bodies in fx_look.gd that read a blow's event, as text.
func _function_body(path: String, name: String) -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


func _reads_the_blow(body: String) -> bool:
	for needle in ["\"damage\"", "\"bodyPart\"", "\"source\"", "\"attacker\"", "presentation"]:
		if body.contains(needle):
			return true
	return false


func _blood_never_varies_with_the_blow() -> bool:
	var w: Variant = _world()
	var focal: Vector2 = _spot(w, SimVisibility.Detail.Focal, 4.0)
	var other: Vector2 = _spot(w, SimVisibility.Detail.Focal, 3.0)
	if focal == Vector2.INF or other == Vector2.INF:
		push_error("SAME: the fixture has no Focal spot; nothing to judge")
		return false
	var z: int = _shambler_at(w, focal)
	var graze: Array = _blood_of(w, [{"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "leftArm", "damage": 0.5}])
	var kill: Array = _blood_of(w, [{"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "head", "damage": 400.0, "item": 7}])
	var bite: Array = _blood_of(w, [{"type": "bite.landed", "victim": z, "source": w.player, "bodyPart": "torso", "damage": 25.0}])
	if graze.is_empty():
		push_error("SAME: a graze in Focal view drew no blood; the comparison had nothing to judge")
		return false
	if graze != kill or graze != bite:
		push_error("SAME: blood differs with the blow -- graze %s, killing blow %s, bite %s" % [str(graze), str(kill), str(bite)])
		return false
	var elsewhere: int = _shambler_at(w, other)
	if graze == _blood_of(w, [{"type": "attack.connected", "attacker": w.player, "target": elsewhere, "bodyPart": "leftArm", "damage": 0.5}]):
		push_error("SAME: blood on another body compared equal; the comparison cannot say no")
		return false
	for name in ["_hit", "from_events"]:
		var body: String = _function_body(FX_GD, name)
		if body.is_empty():
			push_error("SAME: could not read %s out of %s" % [name, FX_GD])
			return false
		if name == "_hit" and _reads_the_blow(body):
			push_error("SAME: fx_look.gd's _hit reads something about the blow; the blood would be free to vary with it")
			return false
	if not _reads_the_blow("var d: float = float(ev.get(\"damage\", 0.0))"):
		push_error("SAME: the blow-reading scan passed a damage read; it cannot say no")
		return false
	print("SAME OK a graze on an arm, a killing blow to the head and a bite drew the identical blood, frame and pixel; the same blood on another body compared different; _hit reads nothing about the blow")
	return true


# --- KINDS --------------------------------------------------------------------------------

func _every_body_kind_bleeds_the_same_sheet() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var judged: int = 0
	for path in tree.keys():
		var p: String = String(path)
		var body_kind: bool = false
		for prefix in BODY_KINDS:
			if p.begins_with(prefix):
				body_kind = true
		if not body_kind:
			continue
		var raw: Variant = tree[path]
		for entry_v in (raw as Array if raw is Array else [raw]):
			if not (entry_v is Dictionary) or not (entry_v as Dictionary).has("appearance"):
				continue
			var hit: String = String(((entry_v as Dictionary)["appearance"] as Dictionary).get("hitFx", ""))
			if hit != "fx_blood_hit":
				push_error("KINDS: %s (%s) bleeds '%s', not the one blood sheet" % [String((entry_v as Dictionary).get("id", "?")), p, hit])
				return false
			judged += 1
	if judged < 20:
		push_error("KINDS: only %d body entries were judged; the scan is not reading the body kinds" % judged)
		return false

	var w: Variant = _world()
	var z: int = _shambler_at(w, Vector2(14.0, 12.0))
	var person: int = int(w.entities.spawn())
	w.components.set_component(person, "identity", {"id": "survivor.generated.x", "look": "colony.look.03"})
	var raider: int = int(w.entities.spawn())
	w.components.set_component(raider, "raider", {"id": "raider.scav", "person": {"look": "raider.look.02"}})
	var archetype: int = int(w.entities.spawn())
	w.components.set_component(archetype, "raider", {"id": "raider.gunhand"})
	var bare: int = int(w.entities.spawn())
	var cases: Array = [[w.player, "player.body"], [z, "zombie.shambler"], [person, "colony.look.03"], [raider, "raider.look.02"], [archetype, "raider.gunhand"]]
	for c in cases:
		var id: String = Appearance.body_look_id(w, int(c[0]))
		if id != String(c[1]):
			push_error("KINDS: body %d reads its look from '%s', not '%s'" % [int(c[0]), id, String(c[1])])
			return false
		if String(Appearance.body_block_for(w, id).get("hitFx", "")) != "fx_blood_hit":
			push_error("KINDS: '%s' resolves no blood through the renderer" % id)
			return false
	if not Appearance.body_look_id(w, bare).is_empty() or not Appearance.body_block_for(w, "").is_empty():
		push_error("KINDS: a body with no look resolved one")
		return false
	w.components.set_component(bare, "position", {"x": 12.0, "y": 12.0})
	var fx: RefCounted = FxLook.new()
	fx.call("from_events", w, [{"type": "attack.connected", "target": bare, "damage": 5.0}])
	if not (fx.get("live") as Array).is_empty():
		push_error("KINDS: a body with no look bled")
		return false
	print("KINDS OK %d body entries across zombies, raiders, the player, the uniques and the looks all bleed fx_blood_hit; the player, a zombie, a person, a raider and an archetype resolve their look's blood; a body with no look bleeds nothing" % judged)
	return true


# --- FLAME --------------------------------------------------------------------------------

func _a_seen_lit_fire_burns() -> bool:
	var w: Variant = _world()
	var focal: Vector2 = _spot(w, SimVisibility.Detail.Focal, 3.0)
	var behind: Vector2 = _spot(w, SimVisibility.Detail.Unseen, 3.0)
	if focal == Vector2.INF or behind == Vector2.INF:
		push_error("FLAME: the fixture has no Focal or Unseen spot; nothing to judge")
		return false
	var cold: int = SimNeeds.make_campfire(w, focal.x, focal.y, false)
	w.step()
	var fx: RefCounted = FxLook.new()
	if not (fx.call("draws", w, CAMERA, true) as Array).is_empty():
		push_error("FLAME: an unlit campfire drew a flame")
		return false
	var lit_behind: int = SimNeeds.make_campfire(w, float(WALL_X) - 1.5, 12.5, true)
	w.step()
	if not (fx.call("draws", w, CAMERA, true) as Array).is_empty():
		push_error("FLAME: a lit campfire behind a wall drew its flame")
		return false
	w.components.set_component(cold, "campfire", {"lit": true, "cooking": false})
	var first: Array = fx.call("draws", w, CAMERA, true)
	if _keys(first) != ["fx_flame_loop"]:
		push_error("FLAME: a lit campfire in view drew %s" % str(_keys(first)))
		return false
	if (fx.call("draws", w, CAMERA, false) as Array).size() != 0:
		push_error("FLAME: the flame drew under the night as well as over it")
		return false
	var fps: int = int(Appearance.sheet_of("fx_flame_loop")["fps"])
	fx.call("advance", 1.0 / float(fps) + 0.001)
	var next: Array = fx.call("draws", w, CAMERA, true)
	if int((next[0] as Dictionary)["frame"]) != (int((first[0] as Dictionary)["frame"]) + 1) % 4:
		push_error("FLAME: one frame's worth of clock moved the flame from frame %d to %d" % [int((first[0] as Dictionary)["frame"]), int((next[0] as Dictionary)["frame"])])
		return false
	if not (fx.get("live") as Array).is_empty():
		push_error("FLAME: drawing a flame started a one-shot")
		return false
	print("FLAME OK a lit campfire in view burns over the night and steps one frame per 1/%d s of the presentation clock (entity %d); an unlit one and a lit one behind a wall (entity %d) draw nothing" % [fps, cold, lit_behind])
	return true


# --- DRAWN --------------------------------------------------------------------------------

func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)


func _boot() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("DRAWN: cannot load %s" % SCENE_PATH)
		return null
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		push_error("DRAWN: the main scene did not construct a world")
		main.queue_free()
		return null
	main.set_process(false)
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		_tap(KEY_ENTER)
		await process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		_tap(KEY_ESCAPE)
		await process_frame
	main.set_process(false)
	return main


func _redraw(main: Node) -> Array:
	main.call("queue_redraw")
	await process_frame
	await process_frame
	var keys: Array = []
	for d in main.get("_fx_drawn") as Array:
		if not keys.has(String((d as Dictionary)["key"])):
			keys.append(String((d as Dictionary)["key"]))
	keys.sort()
	return keys


func _the_draw_loop_blits_every_sheet() -> bool:
	# The frame loop's reach, read out of `_process`: the drained events and the clock both arrive.
	var process: String = _function_body(MAIN_GD, "_process")
	if not process.contains("_fx.call(\"from_events\", world, world.events.drained)") or not process.contains("_fx.call(\"advance\", delta)"):
		push_error("DRAWN: _process does not feed FxLook the drained events and the frame's delta")
		return false
	var draw: String = _function_body(MAIN_GD, "_draw")
	if not draw.contains("_draw_effects(false)") or not draw.contains("_draw_effects(true)"):
		push_error("DRAWN: _draw does not draw the effects on both sides of the night")
		return false

	var main: Node = await _boot()
	if main == null:
		return false
	var world: Variant = main.get("world")
	world.step()
	var quiet: Array = await _redraw(main)
	for key in quiet:
		if String(key) != "fx_flame_loop":
			push_error("DRAWN: a frame with nothing live blitted '%s'" % String(key))
			main.queue_free()
			return false
	# Every one-shot sheet, started on the player (whom the player always sees), and a lit fire at
	# the player's feet.
	var fx: RefCounted = main.get("_fx") as RefCounted
	var p: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	for key in ["fx_pistol_muzzle", "fx_rifle_muzzle", "fx_shotgun_muzzle", "fx_ejected_casing", "fx_blood_hit"]:
		var glow: bool = key.ends_with("_muzzle")
		fx.call("_start", {"key": key, "x": float(p["x"]), "y": float(p["y"]), "view": "e", "point": FxLook.HIT_AT, "turn": glow, "glow": glow})
	SimNeeds.make_campfire(world, float(p["x"]), float(p["y"]), true)
	world.step()
	var drawn: Array = await _redraw(main)
	main.queue_free()
	await process_frame
	var want: Array = ADMITTED.keys()
	want.sort()
	if drawn != want:
		push_error("DRAWN: one frame of main.gd's _draw blitted %s, not every sheet %s" % [str(drawn), str(want)])
		return false
	print("DRAWN OK _process feeds FxLook the drained events and the frame's delta, _draw draws the effects both sides of the night, one frame of the real scene blitted all %d sheets %s, and a frame with nothing live blitted no one-shot" % [drawn.size(), str(drawn)])
	return true

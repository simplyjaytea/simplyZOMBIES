extends SceneTree
# The new art must reach ordinary play: content selects seven bodies, the shared renderer
# animates their four views from the sim clock, death retains a matching settled picture, and
# the picture neither survives as an active zombie nor spends sight the player did not earn.
# check_authored owns pixel bounds and source reproduction; this gate owns those real readers.

const World = preload("res://sim/world.gd")
const Appearance = preload("res://presentation/appearance.gd")
const SimSave = preload("res://sim/save.gd")
const VisualRemainsChecks = preload("res://test/visual_remains_checks.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")

const EXPECT: Dictionary = {
	"body_zombie_workwear": {"type": "zombie.shambler", "fps": 5, "canvas": Vector2i(32, 40)},
	"body_zombie_commuter": {"type": "zombie.shambler", "fps": 5, "canvas": Vector2i(32, 40)},
	"body_zombie_raincoat": {"type": "zombie.shambler", "fps": 5, "canvas": Vector2i(32, 40)},
	"body_zombie_stalker": {"type": "zombie.stalker", "fps": 6, "canvas": Vector2i(32, 40)},
	"body_zombie_runner": {"type": "zombie.runner", "fps": 9, "canvas": Vector2i(32, 40)},
	"body_zombie_armored": {"type": "zombie.armored", "fps": 4, "canvas": Vector2i(32, 40)},
	"body_zombie_heavy": {"type": "zombie.heavy", "fps": 4, "canvas": Vector2i(40, 48)},
}
const DIRECTIONS: Dictionary = {
	"e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0), "n": Vector2(0, -1),
}
const BUDGET_SECONDS: float = 30.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _variants_are_content_and_stable() and ok
	ok = _every_body_walks_and_stands() and ok
	ok = _settled_poses_match() and ok
	ok = VisualRemainsChecks.run() and ok
	ok = _appearances_survive_save() and ok
	ok = _the_game_reads_the_art() and ok
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _require(seconds <= BUDGET_SECONDS, "BUDGET: %.2f s exceeds %.0f s" % [seconds, BUDGET_SECONDS]) and ok
	if ok:
		print("ZOMBIE_ART_OK CONTENT seven selected families; MOTION four views with four distinct poses and static idle, sim-tick timing; CORPSES matching art centered on ground; DEATH one drop/despawn and no active corpse zombie; SAVE optional bounded cosmetic history without RNG/allocation; READERS Focal-only settled draw before standing gear/facing/speech; %.2f s" % seconds)
		quit(0)
	else:
		push_error("ZOMBIE_ART_FAIL")
		quit(1)


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
	return ok


func _world() -> Variant:
	return World.new({
		"seed": 20261002, "tick_hz": 20,
		"map": {"width": 16, "height": 16, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 8.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	})


func _item(type_id: String, entity: int) -> Dictionary:
	return {"ztype": type_id, "id": entity, "zed": true}


func _variants_are_content_and_stable() -> bool:
	var block: Dictionary = {
		"sprite": "fallback", "tint": "#abcdef", "hitFx": "kept",
		"variants": [{"sprite": "a", "corpseSprites": ["a_dead"]}, {"sprite": "b", "corpseSprites": ["b_dead"]}],
	}
	var before: Dictionary = block.duplicate(true)
	for entity in [0, 1, 2, 1048577]:
		var chosen: Dictionary = Appearance.body_variant(block, int(entity))
		var expected: String = "a" if posmod(int(entity), 2) == 0 else "b"
		if not _require(chosen.get("sprite") == expected and chosen.get("hitFx") == "kept" and chosen.get("tint") == "#abcdef", "CONTENT: variant does not override the base while keeping inherited fields"):
			return false
	if not _require(block == before and Appearance.body_variant({"sprite": "plain"}, 12).get("sprite") == "plain", "CONTENT: resolving a variant mutated shared content or changed a body with no variants"):
		return false
	# The same exact matching predicate refuses another body's key: a default-only resolver
	# cannot satisfy this lane merely by returning a valid Texture2D.
	if not _require(_matches({"sprite": "a"}, "a") and not _matches({"sprite": "b"}, "a"), "CONTENT: key predicate accepts the wrong variant"):
		return false
	var w: Variant = _world()
	var rng_before: Dictionary = w.rng.save()
	var entities_before: Dictionary = w.entities.save()
	var seen: Dictionary = {}
	for family in EXPECT:
		var type_id: String = String((EXPECT[family] as Dictionary)["type"])
		for entity in 6:
			var look: Dictionary = Appearance.for_entity(w, _item(type_id, entity))
			if _matches(look, String(family)):
				if not _require(look.get("texture") != null, "CONTENT: %s is selected but resolves no picture" % family):
					return false
				seen[family] = true
			if look != Appearance.for_entity(w, _item(type_id, entity)):
				return _require(false, "CONTENT: repeated lookup changed the same body's appearance")
	if not _require(seen.size() == EXPECT.size(), "CONTENT: seven families are not all selected by shipped content: %s" % str(seen.keys())):
		return false
	if not _require(rng_before == w.rng.save() and entities_before == w.entities.save(), "CONTENT: drawing bodies consumes RNG or entity allocations"):
		return false
	print("CONTENT OK all seven family keys selected, inherited fields kept, original content unchanged, no RNG/allocation")
	return true


func _matches(look: Dictionary, key: String) -> bool:
	return String(look.get("sprite", "")) == key


func _all_distinct(values: Array, required: int) -> bool:
	if values.size() != required:
		return false
	for i in values.size():
		for j in range(i + 1, values.size()):
			if values[i] == values[j]:
				return false
	return true


# A translated copy is not a new pose. Compare the solid silhouette in its own bounding box;
# alpha specks outside it are ignored for the measurement, never removed from the asset.
func _silhouette(image: Image) -> PackedByteArray:
	var left: int = image.get_width()
	var top: int = image.get_height()
	var right: int = -1
	var bottom: int = -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	if right < left:
		return PackedByteArray()
	var out := PackedByteArray([right - left + 1, bottom - top + 1])
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			out.append(1 if image.get_pixel(x, y).a >= 0.5 else 0)
	return out


func _every_body_walks_and_stands() -> bool:
	if not _require(_all_distinct([1, 2, 3, 4], 4) and not _all_distinct([1, 2, 1, 4], 4) and not _all_distinct([1, 2], 4), "MOTION: distinct-frame predicate accepts duplicates or incomplete data"):
		return false
	var control: Image = Image.create(5, 5, false, Image.FORMAT_RGBA8)
	control.set_pixel(1, 1, Color.WHITE)
	control.set_pixel(1, 2, Color.WHITE)
	var shifted: Image = Image.create(5, 5, false, Image.FORMAT_RGBA8)
	shifted.set_pixel(3, 2, Color.WHITE)
	shifted.set_pixel(3, 3, Color.WHITE)
	if not _require(_silhouette(control) == _silhouette(shifted), "MOTION: silhouette comparison mistakes a translated static pose for animation"):
		return false
	shifted.set_pixel(2, 3, Color.WHITE)
	if not _require(_silhouette(control) != _silhouette(shifted), "MOTION: silhouette comparison ignores a real change of pose"):
		return false
	for key_v in EXPECT:
		var key: String = String(key_v)
		var spec: Dictionary = EXPECT[key]
		var fps: int = int(spec["fps"])
		if not _require(Appearance.turns(key) and Appearance.walk_frames(key) == 4 and Appearance.walk_fps(key) == fps, "MOTION: %s lacks four views/four walk frames at %d fps" % [key, fps]):
			return false
		for view_v in DIRECTIONS:
			var view: String = String(view_v)
			var direction: Vector2 = DIRECTIONS[view]
			var velocity: Dictionary = {"dx": direction.x, "dy": direction.y}
			if not _require(Appearance.body_view(key, null, velocity) == view and Appearance.body_view(key, {"radians": direction.angle()}, null) == view, "MOTION: %s does not select the %s heading" % [key, view]):
				return false
			var idle: String = "%s_%s" % [key, view]
			var rest: Texture2D = Appearance.resolve(idle)
			if not _require(rest != null and Vector2i(rest.get_size()) == spec["canvas"], "MOTION: idle missing or wrong canvas: %s" % idle):
				return false
			var bytes: Array = []
			var shapes: Array = []
			for index in 4:
				var frame: String = "%s_walk_%s_%d" % [key, view, index]
				var tex: Texture2D = Appearance.resolve(frame)
				if not _require(tex != null and Vector2i(tex.get_size()) == spec["canvas"], "MOTION: frame missing or wrong canvas: %s" % frame):
					return false
				var img: Image = tex.get_image()
				var shape: PackedByteArray = _silhouette(img)
				if not _require(not shape.is_empty(), "MOTION: empty frame: %s" % frame):
					return false
				bytes.append(img.get_data())
				shapes.append(shape)
			if not _require(_all_distinct(bytes, 4) and _all_distinct(shapes, 4), "MOTION: %s %s repeats or merely translates a pose" % [key, view]):
				return false
			var seen_frames: Dictionary = {}
			for tick in 80:
				var expected: String = "%s_walk_%s_%d" % [key, view, (tick * fps / 20 + 2) % 4]
				var selected: String = Appearance.frame_key(key, view, true, tick, 2)
				var look: Dictionary = {"sprite": key, "texture": rest}
				if not _require(selected == expected and Appearance.body_texture(look, view, true, tick, 2) == Appearance.resolve(expected), "MOTION: texture reader ignores declared frame rate/view/phase for %s" % key):
					return false
				if not _require(Appearance.frame_key(key, view, false, tick, 2) == idle, "MOTION: idle advances for %s" % key):
					return false
				seen_frames[selected] = true
			if not _require(seen_frames.size() == 4, "MOTION: sim clock never reaches the complete cycle"):
				return false
		var east: Image = Appearance.resolve("%s_e" % key).get_image()
		east.flip_x()
		if not _require(Appearance.flip_for(key, PI) == 1.0 and east.get_data() != Appearance.resolve("%s_w" % key).get_image().get_data(), "MOTION: %s mirrors its east-facing picture for west" % key):
			return false
	if not _require(not Appearance.turns("no_such_body") and Appearance.resolve("no_such_body") == null, "MOTION: unknown body resolves to unrelated art"):
		return false
	print("MOTION OK 140 pictures; 28 four-frame loops have distinct pixels and silhouettes; idle/view/fps/phase and unmirrored west reach body_texture")
	return true


func _settled_poses_match() -> bool:
	var w: Variant = _world()
	var seen: Dictionary = {}
	for family in EXPECT:
		var type_id: String = String((EXPECT[family] as Dictionary)["type"])
		for entity in 6:
			var item: Dictionary = _item(type_id, entity)
			var body: Dictionary = Appearance.for_entity(w, item)
			if not _matches(body, String(family)):
				continue
			var block: Dictionary = Appearance.body_variant(Appearance.body_block_for(w, type_id), entity)
			var poses: Array = block.get("corpseSprites", []) as Array
			if not _require(poses.size() == 2 and poses[0] != poses[1], "CORPSES: %s has no two distinct settled keys" % family):
				return false
			var look: Dictionary = Appearance.corpse_look(w, item)
			var expected: String = String(poses[posmod(entity / 3, poses.size())])
			if not _require(_matches(look, expected) and look.get("texture") == Appearance.resolve(expected) and look.get("texture") != null, "CORPSES: living %s resolves another variant's corpse" % family):
				return false
			if not _require((look["texture"] as Texture2D).get_image().get_data() != (body["texture"] as Texture2D).get_image().get_data(), "CORPSES: %s still stands after death" % family):
				return false
			seen[expected] = true
	if not _require(seen.size() == 14, "CORPSES: real content reaches %d zombie poses rather than fourteen" % seen.size()):
		return false
	var human: Dictionary = {}
	for entity in 12:
		var look: Dictionary = Appearance.corpse_look(w, {"id": entity, "unique": true, "cid": "survivor.unique.mara"})
		if not _require(look.get("texture") != null, "CORPSES: survivor lacks player.body corpse fallback"):
			return false
		human[String(look.get("sprite", ""))] = true
	if not _require(human.size() == 4, "CORPSES: human fallback does not reach all four poses"):
		return false
	# After succession the former player need not carry a content identity. Its fallback art
	# remains unmodulated; the old role colour was only the no-texture disc's fallback.
	var anonymous: Dictionary = Appearance.corpse_look(w, {"id": 0, "corpse": true})
	if not _require(anonymous.get("texture") != null and anonymous.get("tint") == Color.WHITE, "CORPSES: identity-free human fallback inherits the old no-texture role colour"):
		return false
	var tinted: Dictionary = Appearance.corpse_look(w, {"id": 0, "corpse": true, "tint": "#abcdef"})
	if not _require(tinted.get("tint") == Color("#abcdef"), "CORPSES: explicit body tint is lost when a corpse uses fallback art"):
		return false
	if not _require(Appearance.corpse_look(w, _item("zombie.no_art", 0)).get("texture") == null, "CORPSES: unknown zombie draws an unrelated human corpse"):
		return false
	for size in [Vector2(48, 32), Vector2(96, 64)]:
		var rect: Rect2 = Appearance.corpse_rect(104.0, 208.0, size)
		if not _require(rect.size == size and rect.get_center().is_equal_approx(Vector2(104, 208)), "CORPSES: settled picture is feet-anchored or incorrectly scaled"):
			return false
	if not _require(not Appearance.body_rect(104, 208, Vector2(48, 32), 1.0).get_center().is_equal_approx(Vector2(104, 208)), "CORPSES: anchor control fails to distinguish a standing rectangle"):
		return false
	print("CORPSES OK fourteen variant-matched zombie poses and four human poses; no art yields no picture; ground-centered at both scales")
	return true


func _appearances_survive_save() -> bool:
	var w: Variant = _world()
	for entity in 6:
		w.remember_visual_remains({"entity": entity, "x": 3.5, "y": 4.5, "ztype": "zombie.shambler", "sinceTick": 27})
	var saved: Dictionary = SimSave.decode_save(SimSave.encode_save(SimSave.create_save(w)))
	var restored: Variant = _world()
	SimSave.apply_save(restored, saved)
	for record in restored.visualRemains:
		var item: Dictionary = _item(String(record["ztype"]), int(record["entity"]))
		if not _require(Appearance.for_entity(w, item) == Appearance.for_entity(restored, item) and Appearance.corpse_look(w, item) == Appearance.corpse_look(restored, item), "SAVE: body or corpse variant changed after JSON restore"):
			return false
	print("SAVE-LOOK OK all three common variants and both poses retain their original look after JSON restore")
	return true


# Textual checks isolate real functions and ignore comments. Fabricated controls prove each
# ordered call chain fails if its reader is missing, commented out, or placed after the draw.
func _code(source: String) -> String:
	var lines: PackedStringArray = []
	for line in source.split("\n"):
		lines.append(String(line).split("#", true, 1)[0])
	return "\n".join(lines)


func _function(source: String, declaration: String) -> String:
	var start: int = source.find(declaration)
	if start < 0:
		return ""
	var end: int = source.find("\nfunc ", start + declaration.length())
	var next_static: int = source.find("\nstatic func ", start + declaration.length())
	if end < 0 or (next_static >= 0 and next_static < end):
		end = next_static
	return _code(source.substr(start, end - start if end >= 0 else -1))


func _ordered(source: String, needles: Array) -> bool:
	var code: String = _code(source)
	var cursor: int = 0
	for needle in needles:
		var found: int = code.find(String(needle), cursor)
		if found < 0:
			return false
		cursor = found + String(needle).length()
	return true


# A corpse is a ground picture, not a standing picture sorted on its centre. It must be drawn
# and removed before the standing sort, or one south of a survivor can paint over their boots.
# Judge the prefix before the FIRST sort, so a later corpse branch cannot satisfy the reader.
func _flat_pass_before_standing_sort(source: String) -> bool:
	var code: String = _code(source)
	var sort_at: int = code.find("items.sort_custom(")
	if sort_at < 0 or code.count("_draw_corpse(") != 1:
		return false
	return _ordered(code.substr(0, sort_at), [
		"items.append_array(_visual_remains_items())", "var standing: Array[Dictionary] = []",
		"for it in items:", 'if bool(it.get("corpse", false)):', "_draw_corpse(it, px_scale)",
		"continue", "standing.append(it)", "items = standing",
	])


func _corpses_are_below_standing_pictures(draw: String) -> bool:
	var flat: String = 'items.append_array(_visual_remains_items())\nvar standing: Array[Dictionary] = []\nfor it in items:\n\tif bool(it.get("corpse", false)):\n\t\t_draw_corpse(it, px_scale)\n\t\tcontinue\n\tstanding.append(it)\nitems = standing\n'
	var sort: String = "items.sort_custom(compare_depth)\n"
	if not _require(_flat_pass_before_standing_sort(flat + sort), "GROUND: flat-pass predicate refuses the draw/remove/sort control"):
		return false
	var refused: Array[String] = [
		sort + flat,
		flat.replace("continue", "pass") + sort,
		flat.replace("items = standing", "pass") + sort,
		flat.replace("_draw_corpse(", "# _draw_corpse(") + sort,
		flat + sort + "_draw_corpse(it, px_scale)\n",
	]
	for source in refused:
		if not _require(not _flat_pass_before_standing_sort(source), "GROUND: flat-pass predicate accepts a late, unremoved, commented, or repeated corpse draw"):
			return false
	if not _require(_flat_pass_before_standing_sort(draw), "GROUND: real corpse draw/removal does not precede the standing sort; remains can cover standing feet"):
		return false
	print("GROUND OK settled pictures draw once and leave the list before standing depth sort; late/missing-removal/commented/repeated controls refused")
	return true


# Sightings remembers where and when a living actor was seen. A newly drawn corpse must not
# replace that frozen picture, because its different ground point is not in that observation.
# Require both real readers: Focal corpses draw without touching the cache, and living memory
# still uses the sim's position plus the exact frame/equipment that the living draw cached.
func _living_memory_contract(settled: String, living: String, remembered: String) -> bool:
	var corpse: String = _code(settled)
	var memory: String = _code(remembered)
	return _ordered(corpse, ["Appearance.corpse_look(", "draw_texture_rect("]) \
		and not corpse.contains("_last_look") \
		and _ordered(living, ["Appearance.body_texture(", "_blit_body(", '_last_look[eid] = {"look": look, "texture": texture, "equip": equip, "flip": flip}']) \
		and _ordered(memory, ["SimSightings.remembered(", 'var mx: float = float(m["x"])', 'var my: float = float(m["y"])', "TopDownProjection.world_to_screen(camera, mx, my)", '_last_look.get(int(m["entity"]))', 'c.get("texture", look["texture"])', '_blit_body(Appearance.body_rect(sx, sy, size, float(c["flip"])), texture, faded, c["equip"]']) \
		and not memory.contains("Appearance.corpse_") \
		and not memory.contains("world.visualRemains")


func _corpses_preserve_living_memory(settled: String, living: String, remembered: String) -> bool:
	var corpse: String = 'Appearance.corpse_look(world, it)\ndraw_texture_rect(texture, rect, false)\n'
	var body: String = 'Appearance.body_texture(look, view, moving, tick, eid)\n_blit_body(rect, texture, col, equip)\n_last_look[eid] = {"look": look, "texture": texture, "equip": equip, "flip": flip}\n'
	var memory: String = 'SimSightings.remembered(world, player)\nvar mx: float = float(m["x"])\nvar my: float = float(m["y"])\nTopDownProjection.world_to_screen(camera, mx, my)\n_last_look.get(int(m["entity"]))\nc.get("texture", look["texture"])\n_blit_body(Appearance.body_rect(sx, sy, size, float(c["flip"])), texture, faded, c["equip"])\n'
	if not _require(_living_memory_contract(corpse, body, memory) and _living_memory_contract(corpse + '# _last_look[eid] = corpse\n', body, memory), "MEMORY: reader predicate refuses valid frozen living memory or counts a comment as a cache write"):
		return false
	var refused: Array = [
		[corpse + '_last_look[int(it["id"])] = {"look": look, "texture": texture}\n', body, memory],
		["", body, memory],
		[corpse, body.replace('_last_look[eid] =', '# _last_look[eid] ='), memory],
		[corpse, body, memory.replace('float(m["x"])', 'float(c["x"])')],
		[corpse, body, memory.replace('c.get("texture", look["texture"])', 'Appearance.corpse_look(world, it)')],
	]
	for row in refused:
		if not _require(not _living_memory_contract(String(row[0]), String(row[1]), String(row[2])), "MEMORY: predicate accepts a corpse overwrite, missing live writer, relocated memory, or freshly resolved corpse picture"):
			return false
	if not _require(_living_memory_contract(settled, living, remembered), "MEMORY: settled art changes the living look cache or afterimages stop using the frozen live frame at the sim's remembered point"):
		return false
	print("MEMORY OK Focal corpse draw never touches living _last_look; living frame/equipment remain frozen at Sightings coordinates; overwrite/absent-reader/relocated/fresh-corpse controls refused")
	return true


# A controlled visibility response drives the real main.gd collection helper. The helper is
# called at each detail level, so changing != Focal to == Unseen exposes the peripheral case.
class GateSight:
	extends RefCounted
	var answer: int = 0
	func detail(_observer: int, _x: float, _y: float) -> int:
		return answer


func _the_game_reads_the_art() -> bool:
	var control: String = 'if bool(it.get("corpse", false)):\n\t_draw_corpse(it, px_scale)\n\tcontinue\nAppearance.for_entity(world, it)\nAppearance.equipment_layers_for(world, eid)\n_focal_drawn.append(it)\ndraw_line(a, b, c)\n'
	var needles: Array = ['if bool(it.get("corpse", false)):', "_draw_corpse(it, px_scale)", "continue", "Appearance.for_entity(", "Appearance.equipment_layers_for(", "_focal_drawn.append(", "draw_line("]
	if not _require(_ordered(control, needles) and not _ordered(control.replace("_draw_corpse(", "# _draw_corpse("), needles) and not _ordered(control.replace("continue", "pass"), needles) and not _ordered(control, ["Appearance.equipment_layers_for(", "_draw_corpse("]), "READERS: scanner accepts a missing/commented/misordered reader"):
		return false
	var main: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	var draw: String = _function(main, "func _draw_entities(")
	if not _corpses_are_below_standing_pictures(draw):
		return false
	if not _require(_ordered(draw, needles), "READERS: real entity pass does not draw and exit the corpse branch before standing body, equipment, speech and facing"):
		return false
	if not _require(_ordered(draw, ['world.components.has_component(int(ent), "corpse")', 'if is_corpse and det != SimVisibility.Detail.Focal:', 'continue', '"corpse": is_corpse', 'items.append_array(_visual_remains_items())']), "READERS: human corpses or saved zombie remains do not join the Focal entity pass"):
		return false
	if not _require(_ordered(draw, ["Appearance.body_view(", "Appearance.body_texture(look, view, Appearance.moving(vel_v), int(world.tick), eid)", "_blit_body("]), "READERS: real body draw does not consume motion and sim-tick animation"):
		return false
	var settled: String = _function(main, "func _draw_corpse(")
	if not _require(_ordered(settled, ['if int(it["det"]) != SimVisibility.Detail.Focal:', "return", "Appearance.corpse_look(", "draw_texture_rect(texture, Appearance.corpse_rect("]) and not settled.contains("equipment_layers_for(") and not settled.contains("body_texture("), "READERS: settled draw omits Focal/ground-center checks or draws standing gear/animation"):
		return false
	var afterimages: String = _function(main, "func _draw_afterimages(")
	if not _corpses_preserve_living_memory(settled, draw, afterimages):
		return false
	var w: Variant = _world()
	w.remember_visual_remains({"entity": 34, "x": 3.5, "y": 4.5, "ztype": "zombie.runner", "tint": "#abcdef"})
	var sight := GateSight.new()
	w.vision = sight
	var script: GDScript = load("res://presentation/main.gd") as GDScript
	if not _require(script != null and script.can_instantiate(), "READERS: real game scene script did not load"):
		return false
	var scene: Variant = script.new()
	scene.world = w
	var ok: bool = true
	for level in [SimVisibility.Detail.Unseen, SimVisibility.Detail.Peripheral, SimVisibility.Detail.Focal]:
		sight.answer = int(level)
		var items: Array = scene.call("_visual_remains_items")
		if int(level) != SimVisibility.Detail.Focal:
			ok = _require(items.is_empty(), "READERS: unseen/peripheral zombie remains reveal a settled picture") and ok
		else:
			ok = _require(items.size() == 1, "READERS: Focal remains do not reach the entity list") and ok
			if items.size() == 1:
				var item: Dictionary = items[0]
				ok = _require(int(item.get("id", -1)) == 34 and item.get("ztype") == "zombie.runner" and item.get("tint") == "#abcdef" and bool(item.get("corpse", false)) and Appearance.corpse_look(w, item).get("texture") != null, "READERS: real collector loses identity/type/tint/corpse art") and ok
	scene.free()
	if ok:
		print("READERS OK real remains collector refuses Unseen/Peripheral and passes Focal art; entity branch exits before gear, speech and facing; living afterimage memory is unchanged")
	return ok

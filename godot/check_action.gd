extends SceneTree
# The action animations (alpha plan A8, docs/23 "Actions on the render clock"): what a body does
# besides walk and breathe, each played from something the sim already published or already holds.
#
# The frames are members of each body's own family (godot/art/simplyzombies/motion/actions.py and
# build_motion.py write them; authored.json's `actions` block says how fast each plays and whether
# it loops). presentation/anim_clock.gd reads the sim's drained events and components into an
# action and how long it has run, and presentation/appearance.gd's `action_key` / `fall_key` turn
# that into the member drawn. This gate proves every link of that, and -- the dead-socket rule --
# that a published event reaches the picture the real draw puts up, one lane per action.
#
# Lanes, each with its true positive and its true negative:
#   CATALOGUE  every family declaring actions carries each in every view (a lying one only east and
#              west), with the same count in each; an undeclared action, a lying action seen from
#              the south and a face-on key carry none.
#   TIMING     action_index steps at the family's rate, ends a one-shot with -1, wraps a loop, holds
#              at `hold` and starts at `start`; an action a family does not declare answers -1.
#   PRIORITY   action_key: a one-shot beats a stance, a stance stands or steps on the stride, a body
#              lying down plays nothing upright, a lying body seen end-on lies toward its last side;
#              no action and no stance answers "", and a played-out one-shot falls back to the rest.
#   GEOMETRY   a derived frame invents no colour (every colour is its source picture's); a crouch and
#              a fall stand lower than the rest, a prone body is wider than tall; each measure is
#              shown failing on a fabricated picture.
#   REACH      both reloads (pistol, long gun), every view: the weapon hand travels, the off hand
#              comes to it and leaves, and the last beat is the stance; the head-bob reload this
#              replaced, hands never moving, is refused.
#   STATES     the clock's named states are the sim's own enum values (melee SwingState, ranged
#              FireState, the stances), so a renumbered enum turns this red rather than the picture
#              quietly wrong; and an invented value is not one of them.
#   CLOCK      the clock on its own: each event starts the right one-shot for the right body and
#              nothing for the wrong one; a repeated entity.killed does not restart a fall; a body
#              never drawn has nothing to fall from; a wind-up ending in Recover throws the strike
#              and one ending any other way does not.
#   PUBLISHERS every event type the clock matches is published somewhere under godot/sim/; an
#              invented type is not.
#   READERS    main.gd hands the drained events to the clock in the frame loop, merges the clock's
#              action into the motion before the body's picture is chosen, and draws the fall in
#              the corpse pass; each needle is shown missing from a fabricated body.
#   SCENE      the shipped scene, booted, real sim steps and the real draw, reading back the member
#              each body was drawn with: RECOIL (weapon.fired), FLINCH and LUNGE (attack.connected),
#              STAGGER (entity.staggered), FALL (entity.killed, through the corpse pass), SWING (the
#              swing command and the sim's own wind-up and strike), RELOAD (the firearm's Reload
#              state, with the player's own weapon and with a rifle in hand), CROUCH and PRONE (the stance command; prone draws no worn layer). Each is
#              judged against the same body drawn without it.

const SCENE_PATH: String = "res://presentation/main.tscn"
const MAIN_GD: String = "res://presentation/main.gd"
const CLOCK_GD: String = "res://presentation/anim_clock.gd"
const SPRITES: String = "res://assets/sprites"
const AnimClock = preload("res://presentation/anim_clock.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Session = preload("res://presentation/session.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimStances = preload("res://sim/stances.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimItems = preload("res://sim/modules/items.gd")

const TICK_SECONDS: float = 1.0 / 20.0
const SURVIVOR: String = "body_survivor"
const LYING_VIEWS: Array[String] = ["e", "w"]
const VIEWS: Array[String] = ["s", "e", "n", "w"]
# The most ticks a scene lane waits for the sim to move a state on (a wind-up, a stance change).
const WAIT_TICKS: int = 40
# How near the weapon hand a long gun's off hand must come: the well five pixels along, and three.
const LONG_REACH: int = 8

var _report: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _catalogue() and ok
	ok = _timing() and ok
	ok = _priority() and ok
	ok = _geometry() and ok
	ok = _states() and ok
	ok = _reach() and ok
	ok = _publishers() and ok
	ok = _readers() and ok
	var main: Node = await _boot()
	if main == null:
		push_error("ACTION_FAIL the scene did not boot")
		quit(1)
		return
	ok = _clock(main) and ok
	var scene_ok: bool = await _scene(main)
	ok = scene_ok and ok
	main.queue_free()
	await process_frame
	if ok:
		print("ACTION_OK every action is catalogued per view, timed, ranked against the stance, drawn from its source's own colours, and reached from the event or state the sim publishes through the real draw: %s" % "; ".join(PackedStringArray(_report)))
		quit(0)
	else:
		push_error("ACTION_FAIL")
		quit(1)


# --- helpers ----------------------------------------------------------------------------------

func _families_with_actions() -> Dictionary:
	var out: Dictionary = {}
	var f: FileAccess = FileAccess.open("%s/authored.json" % SPRITES, FileAccess.READ)
	if f == null:
		return out
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if not (doc is Dictionary):
		return out
	var keys: Dictionary = (doc as Dictionary).get("keys", {}) as Dictionary
	for key in keys.keys():
		var entry: Variant = keys[key]
		if entry is Dictionary and (entry as Dictionary).get("actions") is Dictionary:
			out[String(key)] = (entry as Dictionary)["actions"]
	return out


func _image(key: String) -> Image:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path("%s/%s.png" % [SPRITES, key])) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _colours(img: Image) -> Dictionary:
	var out: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a8 > 0:
				out[c.to_rgba32()] = true
	return out


# The first colour of `img` not in `palette`, or -1.
func _foreign(img: Image, palette: Dictionary) -> int:
	for c in _colours(img).keys():
		if not palette.has(c):
			return int(c)
	return -1


func _bounds(img: Image) -> Rect2i:
	return img.get_used_rect()


func _function_body(text: String, name: String) -> String:
	var out: String = ""
	var inside: bool = false
	for line in text.split("\n"):
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


# --- CATALOGUE --------------------------------------------------------------------------------

func _catalogue() -> bool:
	var ok: bool = true
	var fams: Dictionary = _families_with_actions()
	if not fams.has(SURVIVOR):
		push_error("CATALOGUE: %s declares no actions" % SURVIVOR)
		return false
	var zombies: int = 0
	var counted: int = 0
	for fam in fams.keys():
		if String(fam).begins_with("body_zombie_"):
			zombies += 1
		for action in (fams[fam] as Dictionary).keys():
			var lying: bool = Appearance.LYING_ACTIONS.has(String(action))
			var views: Array[String] = LYING_VIEWS if lying else VIEWS
			var first: int = -1
			for view in views:
				var n: int = Appearance.action_frames(String(fam), String(action), view)
				counted += n
				if n <= 0:
					push_error("CATALOGUE: %s declares %s but has no %s frame" % [fam, action, view])
					ok = false
				elif first >= 0 and n != first:
					push_error("CATALOGUE: %s %s has %d frames in %s and %d in another view" % [fam, action, n, view, first])
					ok = false
				first = n if first < 0 else first
			if lying:
				for view in ["s", "n"]:
					if Appearance.action_frames(String(fam), String(action), view) != 0:
						push_error("CATALOGUE: %s's lying %s is drawn from %s" % [fam, action, view])
						ok = false
	for action in ["swing", "recoil", "reload", "reload_long", "flinch", "crouch", "crouchwalk", "prone", "fall"]:
		if not (fams[SURVIVOR] as Dictionary).has(action):
			push_error("CATALOGUE: the survivor does not carry %s" % action)
			ok = false
	if zombies < 7:
		push_error("CATALOGUE: only %d zombie families carry actions; the seven pose families should" % zombies)
		ok = false
	for fam in fams.keys():
		if String(fam).begins_with("body_zombie_"):
			for action in ["lunge", "stagger", "fall"]:
				if not (fams[fam] as Dictionary).has(action):
					push_error("CATALOGUE: %s does not carry %s" % [fam, action])
					ok = false
	# Negatives: nothing answers for an action nobody declared, a lying one end-on, or a face-on key.
	if Appearance.action_frames(SURVIVOR, "moonwalk", "e") != 0:
		push_error("CATALOGUE: an undeclared action answered frames")
		ok = false
	if Appearance.action_frames(SURVIVOR, "prone", "s") != 0:
		push_error("CATALOGUE: the prone body answered a south view")
		ok = false
	if Appearance.action_frames("zombie_screamer", "lunge", "e") != 0:
		push_error("CATALOGUE: a face-on key answered action frames")
		ok = false
	if ok:
		print("CATALOGUE OK %d families, %d action frames, every view present and equal" % [fams.size(), counted])
		_report.append("CATALOGUE %d families / %d frames" % [fams.size(), counted])
	return ok


# --- TIMING -----------------------------------------------------------------------------------

func _timing() -> bool:
	var ok: bool = true
	var fps: float = Appearance.action_fps(SURVIVOR, "recoil")
	var n: int = Appearance.action_frames(SURVIVOR, "recoil", "e")
	if fps <= 0.0 or n < 2:
		push_error("TIMING: recoil has %d frames at %s fps; nothing to judge" % [n, fps])
		return false
	var step: float = 1.0 / fps
	var checks: Array = [
		["recoil at 0", Appearance.action_index(SURVIVOR, "recoil", "e", 0.0), 0],
		["recoil one frame in", Appearance.action_index(SURVIVOR, "recoil", "e", step * 1.01), 1],
		["recoil played through", Appearance.action_index(SURVIVOR, "recoil", "e", step * (float(n) + 0.01)), -1],
		["recoil before it started", Appearance.action_index(SURVIVOR, "recoil", "e", -1.0), 0],
		["swing held at the guard", Appearance.action_index(SURVIVOR, "swing", "e", 9.0, 0, 0), 0],
		["swing struck from frame 1", Appearance.action_index(SURVIVOR, "swing", "e", 0.0, 1), 1],
		["undeclared action", Appearance.action_index(SURVIVOR, "moonwalk", "e", 0.0), -1],
	]
	for reload in ["reload", "reload_long"]:
		var rn: int = Appearance.action_frames(SURVIVOR, reload, "e")
		checks.append(["%s has six to eight beats" % reload, rn >= 6 and rn <= 8, true])
		checks.append(["%s held at its stance" % reload, Appearance.action_index(SURVIVOR, reload, "e", 60.0, 0, AnimClock.RELOAD_HOLD), rn - 1])
		checks.append(["%s unheld ends" % reload, Appearance.action_index(SURVIVOR, reload, "e", 60.0), -1])
		checks.append(["%s does not loop" % reload, Appearance.action_loops(SURVIVOR, reload), false])
	checks.append(["recoil does not loop", Appearance.action_loops(SURVIVOR, "recoil"), false])
	for c in checks:
		if c[1] != c[2]:
			push_error("TIMING: %s answered %s, wanted %s" % [c[0], str(c[1]), str(c[2])])
			ok = false
	if ok:
		print("TIMING OK one-shots step and end, loops wrap, a hold holds and a start starts")
	return ok


# --- PRIORITY ---------------------------------------------------------------------------------

func _priority() -> bool:
	var ok: bool = true
	var cases: Array = [
		["a one-shot over a crouch", {"action": "recoil", "t": 0.0, "stance": "crouch"}, "e", "%s_recoil_e_0" % SURVIVOR],
		["a standing crouch", {"stance": "crouch"}, "e", "%s_crouch_e_0" % SURVIVOR],
		["a crouched walk", {"stance": "crouch", "walking": true, "cycle": 0.0}, "n", "%s_crouchwalk_n_0" % SURVIVOR],
		["a one-shot while prone", {"action": "recoil", "t": 0.0, "stance": "prone"}, "w", "%s_prone_w_0" % SURVIVOR],
		["prone seen from the south", {"stance": "prone", "lie": "w"}, "s", "%s_prone_w_0" % SURVIVOR],
		["prone with no side remembered", {"stance": "prone"}, "n", "%s_prone_e_0" % SURVIVOR],
		["nothing at all", {}, "e", ""],
		["a played-out one-shot", {"action": "recoil", "t": 60.0}, "e", ""],
		["a stance nobody carries", {"stance": "sitting"}, "e", ""],
	]
	for c in cases:
		var got: String = Appearance.action_key(SURVIVOR, String(c[2]), c[1] as Dictionary)
		if got != String(c[3]):
			push_error("PRIORITY: %s drew '%s', wanted '%s'" % [c[0], got, c[3]])
			ok = false
	# And the frame the draw asks for falls back to the rest when the action has ended.
	var rest: String = Appearance.frame_key(SURVIVOR, "e", {"action": "recoil", "t": 60.0})
	if rest.contains("_recoil_"):
		push_error("PRIORITY: a played-out recoil still drew %s" % rest)
		ok = false
	if Appearance.fall_key(SURVIVOR, "e", 0.0) != "%s_fall_e_0" % SURVIVOR or Appearance.fall_key(SURVIVOR, "e", 60.0) != "":
		push_error("PRIORITY: fall_key does not start on frame 0 and end empty")
		ok = false
	# A face-on key never acts: frame_key answers the key itself.
	if Appearance.frame_key("zombie_screamer", "e", {"action": "lunge", "t": 0.0}) != "zombie_screamer":
		push_error("PRIORITY: a face-on key drew an action")
		ok = false
	if ok:
		print("PRIORITY OK one-shots beat stances, lying blocks upright, end-on lies to its side, nothing answers nothing")
	return ok


# --- GEOMETRY ---------------------------------------------------------------------------------

func _geometry() -> bool:
	var ok: bool = true
	var judged: int = 0
	# Every derived frame against the picture it was moved from. The swing is generated, the
	# crouched walk and the crawl are moved from the walk frames, so those draw from a wider palette.
	var derived: Dictionary = {SURVIVOR: ["recoil", "reload", "reload_long", "flinch", "crouch", "fall"]}
	for fam in _families_with_actions().keys():
		if String(fam).begins_with("body_zombie_"):
			derived[fam] = ["lunge", "stagger", "fall"]
	for fam in derived.keys():
		for view in VIEWS:
			var rest: Image = _image("%s_%s" % [fam, view])
			if rest == null:
				push_error("GEOMETRY: no rest picture for %s %s" % [fam, view])
				ok = false
				continue
			var palette: Dictionary = _colours(rest)
			for action in derived[fam]:
				for i in Appearance.action_frames(String(fam), String(action), view):
					var key: String = "%s_%s_%s_%d" % [fam, action, view, i]
					var img: Image = _image(key)
					if img == null:
						push_error("GEOMETRY: %s has no picture" % key)
						ok = false
						continue
					judged += 1
					var foreign: int = _foreign(img, palette)
					if foreign >= 0:
						push_error("GEOMETRY: %s carries colour %08x its rest view does not" % [key, foreign])
						ok = false
	var rest_e: Image = _image("%s_e" % SURVIVOR)
	var crouch_e: Image = _image("%s_crouch_e_0" % SURVIVOR)
	var fall_n: int = Appearance.action_frames(SURVIVOR, "fall", "e")
	var fall_e: Image = _image("%s_fall_e_%d" % [SURVIVOR, fall_n - 1])
	var prone_e: Image = _image("%s_prone_e_0" % SURVIVOR)
	if rest_e == null or crouch_e == null or fall_e == null or prone_e == null:
		push_error("GEOMETRY: a measured picture is missing")
		return false
	if _bounds(crouch_e).position.y <= _bounds(rest_e).position.y:
		push_error("GEOMETRY: the crouch stands as tall as the rest")
		ok = false
	if _bounds(fall_e).position.y <= _bounds(crouch_e).position.y:
		push_error("GEOMETRY: the fall's last frame stands no lower than the crouch")
		ok = false
	if _bounds(prone_e).size.x <= _bounds(prone_e).size.y:
		push_error("GEOMETRY: the prone body is not wider than tall (%s)" % str(_bounds(prone_e).size))
		ok = false
	# Negatives: the measures fail on pictures that should fail them.
	var painted: Image = rest_e.duplicate() as Image
	var r: Rect2i = _bounds(painted)
	painted.set_pixel(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2, Color(0.0, 1.0, 0.0, 1.0))
	if _foreign(painted, _colours(rest_e)) < 0:
		push_error("GEOMETRY: a painted green pixel was not found foreign")
		ok = false
	if _bounds(rest_e).size.x > _bounds(rest_e).size.y:
		push_error("GEOMETRY: the standing rest view measures wider than tall, so the prone measure cannot fail")
		ok = false
	if ok:
		print("GEOMETRY OK %d derived frames carry only their rest view's colours; crouch < rest, fall < crouch, prone lies flat" % judged)
		_report.append("GEOMETRY %d derived frames" % judged)
	return ok


# --- REACH ------------------------------------------------------------------------------------

# The reload's hands over its beats, as declared: [[primary, secondary], ...] in body pixels.
func _reload_hands(action: String, view: String) -> Array:
	var out: Array = []
	var members: Dictionary = {}
	var f: FileAccess = FileAccess.open("%s/authored.json" % SPRITES, FileAccess.READ)
	if f != null:
		members = ((JSON.parse_string(f.get_as_text()) as Dictionary)["keys"] as Dictionary)[SURVIVOR]["members"] as Dictionary
	for i in Appearance.action_frames(SURVIVOR, action, view):
		var hands: Variant = (members.get("%s_%s_%s_%d" % [SURVIVOR, action, view, i], {}) as Dictionary).get("hands")
		if not (hands is Dictionary):
			return []
		var p: Array = (hands as Dictionary)["primary"] as Array
		var o: Array = (hands as Dictionary)["secondary"] as Array
		out.append([Vector2i(int(p[0]), int(p[1])), Vector2i(int(o[0]), int(o[1]))])
	return out


# What a reload has to show: the weapon hand travels (lowered and brought in), the off hand comes to
# the weapon and goes away again, and the stance it ends on is the rest's.
# `reach` is how near the weapon hand the off hand must come: the pistol is worked at the grip, a
# long gun at its well and fore-end, a few pixels along (actions.py's LONG_WELL).
func _reach_complaint(hands: Array, rest: Array, reach: int) -> String:
	if hands.size() < 6:
		return "only %d beats" % hands.size()
	var travel: int = 0
	var off_travel: int = 0
	var closest: int = 1 << 20
	for h in hands:
		var p: Vector2i = h[0]
		var o: Vector2i = h[1]
		travel = maxi(travel, absi(p.x - (rest[0] as Vector2i).x) + absi(p.y - (rest[0] as Vector2i).y))
		off_travel = maxi(off_travel, absi(o.x - (rest[1] as Vector2i).x) + absi(o.y - (rest[1] as Vector2i).y))
		closest = mini(closest, absi(p.x - o.x) + absi(p.y - o.y))
	if travel < 2:
		return "the weapon hand travels %d px" % travel
	if closest > reach or off_travel < 4:
		return "the off hand comes within %d px of the weapon hand (wanted %d) and travels %d px" % [closest, reach, off_travel]
	if hands[hands.size() - 1][0] != rest[0]:
		return "it ends with the weapon hand at %s, not the stance's %s" % [str(hands[hands.size() - 1][0]), str(rest[0])]
	return ""


func _reach() -> bool:
	var ok: bool = true
	for action in ["reload", "reload_long"]:
		for view in VIEWS:
			var rest: Array = [Appearance.HELD_HANDS["primary"][view], Appearance.HELD_HANDS["secondary"][view]]
			var complaint: String = _reach_complaint(_reload_hands(action, view), rest, 3 if action == "reload" else LONG_REACH)
			if not complaint.is_empty():
				push_error("REACH: %s %s: %s" % [action, view, complaint])
				ok = false
	# Negative: the head-bob reload this replaced -- three beats, hands never moving -- is refused,
	# and so is a reload whose off hand never leaves its side.
	var rest_e: Array = [Appearance.HELD_HANDS["primary"]["e"], Appearance.HELD_HANDS["secondary"]["e"]]
	var still: Array = []
	for i in 8:
		still.append(rest_e.duplicate())
	if _reach_complaint(still.slice(0, 3), rest_e, LONG_REACH).is_empty() or _reach_complaint(still, rest_e, LONG_REACH).is_empty():
		push_error("REACH: a reload whose hands never move was not refused")
		ok = false
	if ok:
		print("REACH OK both reloads, every view: the weapon hand travels, the off hand comes to it and leaves, and it ends on the stance")
	return ok


# --- STATES -----------------------------------------------------------------------------------

func _states() -> bool:
	var ok: bool = true
	var pairs: Array = [
		["swing wind-up", AnimClock.SWING_WINDUP, int(SimMelee.SwingState.WindUp)],
		["swing recover", AnimClock.SWING_RECOVER, int(SimMelee.SwingState.Recover)],
		["fire reload", AnimClock.FIRE_RELOAD, int(SimRanged.FireState.Reload)],
		["fire clearing", AnimClock.FIRE_CLEARING, int(SimRanged.FireState.Clearing)],
		["stance crawl", AnimClock.STANCE_CRAWL, int(SimStances.Stance.Crawl)],
		["stance crouch", AnimClock.STANCE_CROUCH, int(SimStances.Stance.Crouch)],
	]
	for p in pairs:
		if int(p[1]) != int(p[2]):
			push_error("STATES: the clock's %s is %d, the sim's is %d" % [p[0], p[1], p[2]])
			ok = false
	if SimMelee.SwingState.values().has(99) or AnimClock.SWING_WINDUP == int(SimMelee.SwingState.Idle):
		push_error("STATES: the comparison cannot tell states apart")
		ok = false
	if ok:
		print("STATES OK the clock's named states are the sim's enum values")
	return ok


# --- PUBLISHERS -------------------------------------------------------------------------------

func _clock_event_types() -> Array[String]:
	var out: Array[String] = []
	var body: String = _function_body(_read(CLOCK_GD), "from_events")
	var rx := RegEx.new()
	rx.compile("^\\t\\t\\t\"([a-z]+\\.[a-z.]+)\":")
	for line in body.split("\n"):
		var m: RegExMatch = rx.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


func _sim_text() -> String:
	var out: String = ""
	var stack: Array[String] = ["res://sim"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d: DirAccess = DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir, sub])
		for file in d.get_files():
			if file.ends_with(".gd"):
				out += _read("%s/%s" % [dir, file]) + "\n"
	return out


func _published(sim: String, type: String) -> bool:
	return sim.contains("\"type\": \"%s\"" % type)


func _publishers() -> bool:
	var ok: bool = true
	var types: Array[String] = _clock_event_types()
	var want: Array[String] = ["weapon.fired", "attack.connected", "grab.started", "entity.staggered", "entity.killed"]
	for t in want:
		if not types.has(t):
			push_error("PUBLISHERS: the clock's from_events has no arm for %s" % t)
			ok = false
	var sim: String = _sim_text()
	for t in types:
		if not _published(sim, t):
			push_error("PUBLISHERS: the clock matches %s and nothing under sim/ publishes it" % t)
			ok = false
	if _published(sim, "weapon.misfired_on_purpose"):
		push_error("PUBLISHERS: an invented event type was found published")
		ok = false
	if types.size() < want.size():
		ok = false
	if ok:
		print("PUBLISHERS OK the clock's %d event arms are each published by the sim (%s)" % [types.size(), ", ".join(PackedStringArray(types))])
	return ok


# --- READERS ----------------------------------------------------------------------------------

func _readers_complaint(text: String) -> String:
	var process: String = _function_body(text, "_process")
	if not process.contains("_anim.from_events(world, world.events.drained"):
		return "_process does not hand the drained events to the clock"
	var entities: String = _function_body(text, "_draw_entities")
	var merge_at: int = entities.find("motion.merge(_anim.act(")
	var pick_at: int = entities.find("Appearance.body_texture(look, view, motion)")
	if merge_at < 0 or pick_at < 0 or merge_at > pick_at:
		return "_draw_entities does not merge the clock's action before it picks the body's picture"
	var corpse: String = _function_body(text, "_draw_corpse")
	if not corpse.contains("_anim.fall_of(") or not corpse.contains("Appearance.fall_key(") or not corpse.contains("_falls_drawn.append("):
		return "_draw_corpse does not draw the fall"
	return ""


func _readers() -> bool:
	var ok: bool = true
	var text: String = _read(MAIN_GD)
	var complaint: String = _readers_complaint(text)
	if not complaint.is_empty():
		push_error("READERS: %s" % complaint)
		ok = false
	# Negatives: each needle, taken out of an otherwise true copy, is missed.
	var sabotage: Array = [
		"_anim.from_events(world, world.events.drained",
		"motion.merge(_anim.act(",
		"_anim.fall_of(",
	]
	for needle in sabotage:
		if _readers_complaint(text.replace(String(needle), "_nothing(")).is_empty():
			push_error("READERS: removing '%s' went unnoticed" % needle)
			ok = false
	if ok:
		print("READERS OK the frame loop feeds the clock, the draw merges its action before the picture, the corpse pass draws the fall")
	return ok


# --- CLOCK ------------------------------------------------------------------------------------

func _clock(main: Node) -> bool:
	var ok: bool = true
	var world: Variant = main.get("world")
	var pid: int = int(world.player)
	var clock = AnimClock.new()
	clock.begin_draw(1.0)
	clock.from_events(world, [{"type": "weapon.fired", "entity": pid, "item": -1}], 1.0)
	if String(clock.act(pid, world, SURVIVOR, "e").get("action", "")) != "recoil":
		push_error("CLOCK: weapon.fired did not start the firer's recoil")
		ok = false
	if String(clock.act(pid + 100000, world, SURVIVOR, "e").get("action", "")) != "":
		push_error("CLOCK: a body nobody shot started acting")
		ok = false
	clock.from_events(world, [{"type": "attack.connected", "attacker": -1, "target": pid, "bodyPart": "torso", "damage": 0.0, "item": -1}], 1.0)
	if String(clock.act(pid, world, SURVIVOR, "e").get("action", "")) != "flinch":
		push_error("CLOCK: a hit on a living body did not flinch it")
		ok = false
	clock.from_events(world, [{"type": "speech.said", "entity": pid}], 1.0)
	if String(clock.act(pid, world, SURVIVOR, "e").get("action", "")) != "flinch":
		push_error("CLOCK: an unrelated event changed the action")
		ok = false
	# A death falls once: the look act() recorded is what it falls from, and a second killed event
	# later does not restart it.
	clock.from_events(world, [{"type": "entity.killed", "entity": pid}], 1.0)
	clock.begin_draw(1.5)
	clock.from_events(world, [{"type": "entity.killed", "entity": pid}], 1.5)
	var fall: Dictionary = clock.fall_of(pid)
	if fall.is_empty() or absf(float(fall["t"]) - 0.5) > 0.0001 or String(fall["key"]) != SURVIVOR:
		push_error("CLOCK: the fall was %s, wanted one started at the first death, 0.5 s in" % str(fall))
		ok = false
	clock.from_events(world, [{"type": "entity.killed", "entity": pid + 200000}], 1.5)
	if not clock.fall_of(pid + 200000).is_empty():
		push_error("CLOCK: a body never drawn fell")
		ok = false
	# The swing, read off the sim's own component: WindUp holds the guard, Recover throws the strike.
	var saved: Variant = world.components.get_component(pid, "swing")
	var swing: Dictionary = {"state": int(SimMelee.SwingState.WindUp), "ticksLeft": 3}
	world.components.set_component(pid, "swing", swing)
	var guard: Dictionary = clock.act(pid, world, SURVIVOR, "e")
	swing["state"] = int(SimMelee.SwingState.Recover)
	clock.begin_draw(1.6)
	var strike: Dictionary = clock.act(pid, world, SURVIVOR, "e")
	if String(guard.get("action", "")) != "swing" or int(guard.get("hold", -1)) != 0:
		push_error("CLOCK: the wind-up did not hold the guard (%s)" % str(guard))
		ok = false
	if String(strike.get("action", "")) != "swing" or int(strike.get("start", 0)) != 1:
		push_error("CLOCK: the wind-up ending in Recover did not throw the strike (%s)" % str(strike))
		ok = false
	var other = AnimClock.new()
	other.begin_draw(1.0)
	swing["state"] = int(SimMelee.SwingState.WindUp)
	other.act(pid, world, SURVIVOR, "e")
	swing["state"] = int(SimMelee.SwingState.Idle)
	other.begin_draw(1.1)
	if String(other.act(pid, world, SURVIVOR, "e").get("action", "")) == "swing":
		push_error("CLOCK: a wind-up refused back to Idle threw a strike")
		ok = false
	if saved is Dictionary:
		world.components.set_component(pid, "swing", saved)
	else:
		world.components.remove_component(pid, "swing")
	if ok:
		print("CLOCK OK each event starts its one-shot on its own body, a death falls once, a wind-up strikes only into Recover")
	return ok


# --- SCENE ------------------------------------------------------------------------------------

func _boot() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		return null
	main.set_process(false)
	main.call("_enter_state", Session.State.PLAYING)
	main.set("paused", false)
	main.set("accumulator", 0.0)
	return main


# One sim step through the real frame loop, then one real draw.
func _tick(main: Node) -> void:
	main.set("paused", false)
	main.set("accumulator", 0.0)
	main.call("_process", TICK_SECONDS)
	main.queue_redraw()
	await process_frame
	await process_frame


# A draw with the world held still: no step, no presentation time.
func _still(main: Node) -> void:
	main.set("paused", true)
	main.call("_process", 0.0)
	main.queue_redraw()
	await process_frame
	await process_frame


# The member `id` was drawn with in the last draw, "" when it was not drawn in Focal.
func _drawn(main: Node, id: int) -> String:
	var seen: bool = false
	for b in main.get("_focal_drawn") as Array:
		if int((b as Dictionary).get("id", -1)) == id:
			seen = true
	if not seen:
		return ""
	var rec: Variant = (main.get("_last_look") as Dictionary).get(id)
	if not (rec is Dictionary):
		return ""
	var texture: Texture2D = (rec as Dictionary).get("texture") as Texture2D
	var family: String = String(((rec as Dictionary).get("look", {}) as Dictionary).get("sprite", ""))
	for m in _members(family):
		if Appearance.resolve(String(m)) == texture:
			return String(m)
	return "?"


func _members(family: String) -> Array:
	Appearance.action_frames(family, "", "e")
	var fams: Dictionary = Appearance._families
	if not fams.has(family):
		return []
	return (fams[family] as Dictionary)["members"] as Array


func _fail(lane: String, why: String) -> bool:
	push_error("%s: %s" % [lane, why])
	return false


func _spot(w: Variant, metres: float) -> Vector2:
	var p: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	for i in 72:
		var inside: bool = true
		for k in [-1, 0, 1]:
			var a: float = TAU * float(i + k) / 72.0
			if int(w.vision.detail(int(w.player), float(p["x"]) + cos(a) * metres, float(p["y"]) + sin(a) * metres)) != int(SimVisibility.Detail.Focal):
				inside = false
		if inside:
			var at: float = TAU * float(i) / 72.0
			return Vector2(float(p["x"]) + cos(at) * metres, float(p["y"]) + sin(at) * metres)
	return Vector2.INF


func _scene(main: Node) -> bool:
	var ok: bool = true
	var w: Variant = main.get("world")
	var pid: int = int(w.player)
	await _tick(main)
	var at_rest: String = _drawn(main, pid)
	if at_rest.is_empty() or at_rest == "?" or at_rest.contains("_recoil_") or at_rest.contains("_flinch_"):
		return _fail("SCENE", "the player was drawn as '%s' before anything happened" % at_rest)
	var r: bool = await _recoil(main, w, pid)
	ok = r and ok
	r = await _swing(main, w, pid)
	ok = r and ok
	r = await _reload(main, w, pid)
	ok = r and ok
	r = await _stances(main, w, pid)
	ok = r and ok
	r = await _zombie(main, w, pid)
	ok = r and ok
	return ok


func _recoil(main: Node, w: Variant, pid: int) -> bool:
	var before: String = _drawn(main, pid)
	w.events.publish({"type": "weapon.fired", "entity": pid, "item": -1})
	await _tick(main)
	var during: String = _drawn(main, pid)
	for i in 6:
		await _tick(main)
	var after: String = _drawn(main, pid)
	if before.contains("_recoil_") or not during.contains("_recoil_") or after.contains("_recoil_"):
		return _fail("RECOIL", "drawn '%s' before, '%s' on the shot, '%s' after" % [before, during, after])
	print("RECOIL OK weapon.fired drew %s, and the body was %s before and %s after" % [during, before, after])
	_report.append("RECOIL %s" % during)
	return true


func _swing(main: Node, w: Variant, pid: int) -> bool:
	if not w.components.has_component(pid, "swing"):
		return _fail("SWING", "the player carries no swing component; the swing command cannot be judged")
	var before: String = _drawn(main, pid)
	w.commands.push({"type": "swing"})
	await _tick(main)
	var state: int = int((w.components.get_component(pid, "swing") as Dictionary)["state"])
	var guard: String = _drawn(main, pid)
	if state != int(SimMelee.SwingState.WindUp):
		return _fail("SWING", "the swing command left the swing in state %d, not WindUp" % state)
	var strike: String = ""
	for i in WAIT_TICKS:
		await _tick(main)
		if int((w.components.get_component(pid, "swing") as Dictionary)["state"]) == int(SimMelee.SwingState.Recover):
			strike = _drawn(main, pid)
			break
	for i in WAIT_TICKS:
		await _tick(main)
		if int((w.components.get_component(pid, "swing") as Dictionary)["state"]) == int(SimMelee.SwingState.Idle):
			break
	for i in 10:
		await _tick(main)
	var after: String = _drawn(main, pid)
	if before.contains("_swing_") or not guard.contains("_swing_") or not guard.ends_with("_0"):
		return _fail("SWING", "drawn '%s' before and '%s' in the wind-up, wanted a guard frame 0" % [before, guard])
	if not strike.contains("_swing_") or strike.ends_with("_0"):
		return _fail("SWING", "drawn '%s' on the strike, wanted a swing frame past the guard" % strike)
	if after.contains("_swing_"):
		return _fail("SWING", "still drawn '%s' after the swing ended" % after)
	print("SWING OK the swing command drew %s through the wind-up and %s on the strike, and %s after" % [guard, strike, after])
	_report.append("SWING %s, %s" % [guard, strike])
	return true


func _reload(main: Node, w: Variant, pid: int) -> bool:
	# The firearm's Reload state, set with the world held still so no firearm system acts on a
	# weapon the player is not carrying; the clock reads the component exactly as the sim leaves it.
	var saved: Variant = w.components.get_component(pid, "rangedWeapon")
	await _still(main)
	var before: String = _drawn(main, pid)
	var fire: Dictionary = (saved as Dictionary).duplicate(true) if saved is Dictionary else {}
	fire["state"] = int(SimRanged.FireState.Reload)
	w.components.set_component(pid, "rangedWeapon", fire)
	await _still(main)
	var during: String = _drawn(main, pid)
	fire["state"] = int(SimRanged.FireState.Idle)
	await _still(main)
	var after: String = _drawn(main, pid)
	if saved is Dictionary:
		w.components.set_component(pid, "rangedWeapon", saved)
	else:
		w.components.remove_component(pid, "rangedWeapon")
	var short: bool = Appearance.reload_action(w, pid) == "reload"
	if before.contains("_reload") or not during.contains("_reload_") or after.contains("_reload"):
		return _fail("RELOAD", "drawn '%s' before, '%s' in Reload, '%s' after" % [before, during, after])
	if short == during.contains("_reload_long_"):
		return _fail("RELOAD", "the player's weapon calls for %s and drew %s" % ["the pistol's" if short else "the long gun's", during])
	# The other variant: a hunting rifle put in the player's primary hand while the world is still.
	var eq: Dictionary = w.components.get_component(pid, "equipment") as Dictionary
	var slots_saved: Dictionary = (eq.get("slots", {}) as Dictionary).duplicate(true)
	var rifle: int = SimItems.spawn_item(w, "item.rifle.hunting", {})
	(eq["slots"] as Dictionary)["primary"] = rifle
	w.components.set_component(pid, "rangedWeapon", fire)
	fire["state"] = int(SimRanged.FireState.Reload)
	await _still(main)
	var long_during: String = _drawn(main, pid)
	eq["slots"] = slots_saved
	if saved is Dictionary:
		w.components.set_component(pid, "rangedWeapon", saved)
	else:
		w.components.remove_component(pid, "rangedWeapon")
	w.despawn(rifle)
	await _still(main)
	var restored: String = _drawn(main, pid)
	if not long_during.contains("_reload_long_") or restored.contains("_reload"):
		return _fail("RELOAD", "a rifle in hand drew '%s' in Reload, and '%s' put back" % [long_during, restored])
	print("RELOAD OK the Reload state drew %s with the player's own weapon and %s with a rifle, and %s either side" % [during, long_during, after])
	_report.append("RELOAD %s / %s" % [during, long_during])
	return true


func _stance_to(main: Node, w: Variant, pid: int, stance: int) -> bool:
	w.commands.push({"type": "stance", "stance": stance})
	for i in WAIT_TICKS:
		await _tick(main)
		if int((w.components.get_component(pid, "posture") as Dictionary)["current"]) == stance:
			await _tick(main)
			return true
	return false


func _stances(main: Node, w: Variant, pid: int) -> bool:
	var ok: bool = true
	var walk: int = int(SimStances.Stance.Walk)
	var standing: String = _drawn(main, pid)
	var standing_equip: int = ((main.get("_last_look") as Dictionary)[pid] as Dictionary)["equip"].size()
	var crouched: bool = await _stance_to(main, w, pid, int(SimStances.Stance.Crouch))
	var crouch: String = _drawn(main, pid)
	var prone_ok: bool = await _stance_to(main, w, pid, int(SimStances.Stance.Crawl))
	var prone: String = _drawn(main, pid)
	var prone_equip: int = ((main.get("_last_look") as Dictionary)[pid] as Dictionary)["equip"].size()
	var back: bool = await _stance_to(main, w, pid, walk)
	var stood: String = _drawn(main, pid)
	if not crouched or not crouch.contains("_crouch"):
		ok = _fail("CROUCH", "the crouch stance drew '%s' (reached: %s)" % [crouch, str(crouched)])
	if not prone_ok or not prone.contains("_prone_") or prone_equip != 0:
		ok = _fail("PRONE", "the crawl stance drew '%s' with %d layers (reached: %s)" % [prone, prone_equip, str(prone_ok)])
	if standing.contains("_crouch") or standing.contains("_prone_") or not back or stood.contains("_crouch") or stood.contains("_prone_"):
		ok = _fail("CROUCH", "standing drew '%s' before and '%s' after (stood back up: %s)" % [standing, stood, str(back)])
	if ok:
		var layers: String = "%d layers standing" % standing_equip if standing_equip > 0 else "no layers standing either, so the layer half is not judged"
		print("CROUCH OK the crouch stance drew %s, standing %s and %s" % [crouch, standing, stood])
		print("PRONE OK the crawl stance drew %s with no worn layer (%s)" % [prone, layers])
		_report.append("CROUCH %s" % crouch)
		_report.append("PRONE %s (%s)" % [prone, layers])
	return ok


func _zombie(main: Node, w: Variant, pid: int) -> bool:
	var ok: bool = true
	var at: Vector2 = _spot(w, 3.0)
	if at == Vector2.INF:
		return _fail("LUNGE", "no Focal spot near the player to stand a zombie in")
	var z: int = SimRoster.spawn_zombie(w, at.x, at.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("debug"))
	await _tick(main)
	await _tick(main)
	var before: String = _drawn(main, z)
	var player_before: String = _drawn(main, pid)
	if before.is_empty() or before == "?":
		return _fail("LUNGE", "the zombie standing in Focal view was drawn as '%s'" % before)
	if before.contains("_lunge_") or before.contains("_stagger_") or player_before.contains("_flinch_"):
		return _fail("LUNGE", "drawn '%s' / player '%s' before anything happened" % [before, player_before])
	# A blow that lands with nothing in it: the attacker lunges, the struck living body flinches.
	w.events.publish({"type": "attack.connected", "attacker": z, "target": pid, "bodyPart": "torso", "damage": 0.0, "item": -1})
	await _tick(main)
	var lunge: String = _drawn(main, z)
	var flinch: String = _drawn(main, pid)
	if not lunge.contains("_lunge_"):
		ok = _fail("LUNGE", "attack.connected from the zombie drew it '%s'" % lunge)
	if not flinch.contains("_flinch_"):
		ok = _fail("FLINCH", "attack.connected on the player drew it '%s'" % flinch)
	for i in 10:
		await _tick(main)
	var settled: String = _drawn(main, z)
	var player_settled: String = _drawn(main, pid)
	if settled.contains("_lunge_") or player_settled.contains("_flinch_"):
		ok = _fail("LUNGE", "still drawn '%s' / player '%s' half a second on" % [settled, player_settled])
	w.events.publish({"type": "entity.staggered", "entity": z, "ticks": 4})
	await _tick(main)
	var stagger: String = _drawn(main, z)
	if not stagger.contains("_stagger_"):
		ok = _fail("STAGGER", "entity.staggered on the zombie drew it '%s'" % stagger)
	for i in 12:
		await _tick(main)
	# The fall: a head blow that kills, through the sim's own health and the corpse pass.
	if not _fell(main, z).is_empty():
		ok = _fail("FALL", "the living zombie was in the falls drawn")
	w.events.publish({"type": "attack.connected", "attacker": pid, "target": z, "bodyPart": "head", "damage": 999.0, "item": -1})
	var fall: String = ""
	for i in 6:
		await _tick(main)
		fall = _fell(main, z)
		if not fall.is_empty():
			break
	for i in 20:
		await _tick(main)
	var gone: String = _fell(main, z)
	if not fall.contains("_fall_"):
		ok = _fail("FALL", "the killing blow drew no fall in the corpse pass (zombie alive: %s)" % str(w.entities.is_alive(z) if w.entities.has_method("is_alive") else "?"))
	if not gone.is_empty():
		ok = _fail("FALL", "a second on, the fall still drew %s instead of the settled body" % gone)
	if ok:
		print("LUNGE OK attack.connected drew the zombie %s, %s before and %s after" % [lunge, before, settled])
		print("FLINCH OK the same hit drew the player %s, %s before and %s after" % [flinch, player_before, player_settled])
		print("STAGGER OK entity.staggered drew the zombie %s" % stagger)
		print("FALL OK the killing blow drew %s in the corpse pass, and the settled body after it played" % fall)
		_report.append("LUNGE %s" % lunge)
		_report.append("FLINCH %s" % flinch)
		_report.append("STAGGER %s" % stagger)
		_report.append("FALL %s" % fall)
	return ok


func _fell(main: Node, id: int) -> String:
	for f in main.get("_falls_drawn") as Array:
		if int((f as Dictionary).get("id", -1)) == id:
			return String((f as Dictionary)["key"])
	return ""

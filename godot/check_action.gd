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
#   GEOMETRY   a derived frame invents no colour (every colour is its source picture's, a magazine
#              reload's magazine the held pistol's gunmetal and the tube reload's shells the shells
#              icon's red and brass, shown in every reload view); a crouch and
#              a fall stand lower than the rest, a prone body is wider than tall; each measure is
#              shown failing on a fabricated picture.
#   LANDING    every fall, rest to the corpse it settles onto as its own last frame, inside art
#              review's bounds a step (mass 15%, centre 4 columns, any edge 6 px, the sole row
#              held); the pack's corpse cut in centred after the turn and the fall at every third
#              frame both break them.
#   HEAD       every fall's settle, from the last turned frame to the corpse, keeps a head on every
#              beat: the turned frame's head or the corpse's, found where it went, at least half
#              there; the two summed only where they overlap; the carried head ends within 4 px of
#              the corpse's own head; and the corpse's head does not arrive at the hold frame in
#              more pixels than the mass bound allows a step. A settle with its head erased, two
#              half heads apart and a head left where it fell are refused.
#   STRIKE     every lunge and stagger, rest to its beats and home, inside the same 15% mass step
#              and on the sole row (a stagger may rise one row, the knock-back); a cut beat and a
#              beat lifted past its allowance are refused.
#   REACH      all three reloads (pistol, long gun, tube-fed shotgun), every view: the weapon hand
#              travels (a pixel at least for a long gun seen from behind, held still but for the
#              rack's jolt, two everywhere else), the off hand comes to it and leaves, and the last
#              beat is the stance; the head-bob reload this replaced, hands never moving, is refused.
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
#              state, with the player's own weapon, a rifle and a pump shotgun in hand), CROUCH and
#              PRONE (the stance command; prone draws no worn layer). Each is
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
	ok = _landing() and ok
	ok = _head() and ok
	ok = _strike() and ok
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


# Whether `img` carries a colour of `wanted` that `besides` does not have.
func _carries_any(img: Image, wanted: Dictionary, besides: Dictionary) -> bool:
	for c in _colours(img).keys():
		if wanted.has(c) and not besides.has(c):
			return true
	return false


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
	for action in ["swing", "recoil", "reload", "reload_long", "reload_tube", "flinch", "crouch", "crouchwalk", "prone", "fall"]:
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
	for reload in ["reload", "reload_long", "reload_tube"]:
		var rn: int = Appearance.action_frames(SURVIVOR, reload, "e")
		# A magazine swap is six to eight beats. The tube loads three shells one at a time (a reach,
		# the port and a push each) before the rack and the stance, so it may run to twelve.
		var most: int = 12 if reload == "reload_tube" else 8
		checks.append(["%s has six to %d beats" % [reload, most], rn >= 6 and rn <= most, true])
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

# LANDING: a fall goes down and lies there without a jump (art review rounds 1 and 2,
# 2026-10-20: the corpse used to jump up and sideways on the cut, then to swell or shrink by up to
# 95% when the pack's corpse picture replaced the last turned frame). For every family and view,
# the sequence the game draws -- the rest view, each fall frame, then the settled body, all placed
# exactly as main.gd places them at scale 1 -- holds the review's bounds on every consecutive pair:
# the solid mass changes by at most LAND_MASS_STEP, the centre of mass moves at most
# LAND_CENTRE_STEP columns, no edge of the silhouette moves more than LAND_EDGE_STEP pixels, and the
# lowest row is the rest's sole row throughout. The settled body is the fall's own last frame
# (`Appearance.lying_key`), lying to the view's fall side. Negatives: the pack's corpse picture as
# the settled body breaks the bounds, and so does the same fall played at every third frame.
const LAND_MASS_STEP: float = 0.15
const LAND_CENTRE_STEP: float = 4.0
const LAND_EDGE_STEP: int = 6


func _placed(img: Image, rect: Rect2) -> Dictionary:
	var low: int = -1
	var top: int = 1 << 20
	var left: int = 1 << 20
	var right: int = -1
	var sum_x: float = 0.0
	var n: int = 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a8 >= 128:
				var screen_x: int = int(rect.position.x) + x
				var screen_y: int = int(rect.position.y) + y
				sum_x += float(screen_x)
				n += 1
				low = maxi(low, screen_y)
				top = mini(top, screen_y)
				left = mini(left, screen_x)
				right = maxi(right, screen_x)
	return {"low": low, "top": top, "left": left, "right": right, "cx": sum_x / float(maxi(n, 1)), "n": n}


func _step_complaint(a: Dictionary, b: Dictionary, sole: int) -> String:
	var mass: float = absf(float(b["n"]) - float(a["n"])) / float(maxi(int(a["n"]), 1))
	var centre: float = absf(float(b["cx"]) - float(a["cx"]))
	var edge: int = 0
	for side in ["low", "top", "left", "right"]:
		edge = maxi(edge, absi(int(b[side]) - int(a[side])))
	if mass > LAND_MASS_STEP:
		return "its mass changes %.1f%%" % (mass * 100.0)
	if centre > LAND_CENTRE_STEP:
		return "its centre of mass moves %.1f columns" % centre
	if edge > LAND_EDGE_STEP:
		return "an edge moves %d px" % edge
	if int(b["low"]) != sole:
		return "its lowest row is %d, not the sole row %d" % [int(b["low"]), sole]
	return ""


func _seq_worst(seq: Array) -> Dictionary:
	var out: Dictionary = {"mass": 0.0, "centre": 0.0, "edge": 0}
	for i in range(1, seq.size()):
		var a: Dictionary = seq[i - 1]
		var b: Dictionary = seq[i]
		out["mass"] = maxf(float(out["mass"]), absf(float(b["n"]) - float(a["n"])) / float(maxi(int(a["n"]), 1)))
		out["centre"] = maxf(float(out["centre"]), absf(float(b["cx"]) - float(a["cx"])))
		for side in ["low", "top", "left", "right"]:
			out["edge"] = maxi(int(out["edge"]), absi(int(b[side]) - int(a[side])))
	return out


func _drawn_at(key: String, sx: float, sy: float) -> Dictionary:
	var img: Image = _image(key)
	if img == null:
		return {}
	return _placed(img, Appearance.body_rect(sx, sy, Vector2(img.get_size()), 1.0))


func _landing() -> bool:
	var ok: bool = true
	var sx: float = 100.0
	var sy: float = 100.0
	var judged: int = 0
	var steps: int = 0
	var corpse_breaks: int = 0
	var coarse_breaks: int = 0
	var worst: Dictionary = {"mass": 0.0, "centre": 0.0, "edge": 0}
	for fam_v in _families_with_actions().keys():
		var fam: String = String(fam_v)
		if Appearance.action_frames(fam, "fall", "e") == 0:
			continue
		for view in Appearance.VIEWS:
			var frames: int = Appearance.action_frames(fam, "fall", view)
			var seq: Array = [_drawn_at("%s_%s" % [fam, view], sx, sy)]
			for i in frames:
				seq.append(_drawn_at("%s_fall_%s_%d" % [fam, view, i], sx, sy))
			var lying: String = Appearance.lying_key(fam, view)
			if lying != "%s_fall_%s_%d" % [fam, view, frames - 1]:
				push_error("LANDING: %s from %s settles as '%s', not its fall's last frame" % [fam, view, lying])
				ok = false
				continue
			seq.append(_drawn_at(lying, sx, sy))
			if seq.has({}):
				push_error("LANDING: %s's %s fall has a frame that does not load" % [fam, view])
				ok = false
				continue
			var sole: int = int((seq[0] as Dictionary)["low"])
			for i in range(1, seq.size()):
				var complaint: String = _step_complaint(seq[i - 1], seq[i], sole)
				if not complaint.is_empty():
					push_error("LANDING: %s from %s, step %d of %d: %s" % [fam, view, i, seq.size() - 1, complaint])
					ok = false
				steps += 1
			var w: Dictionary = _seq_worst(seq)
			worst["mass"] = maxf(float(worst["mass"]), float(w["mass"]))
			worst["centre"] = maxf(float(worst["centre"]), float(w["centre"]))
			worst["edge"] = maxi(int(worst["edge"]), int(w["edge"]))
			var side: int = int(Appearance.FALL_SIDE[view])
			if signf(float((seq.back() as Dictionary)["cx"]) - sx) != float(side):
				push_error("LANDING: %s from %s lies to %+d of its feet, not its fall side %+d" % [fam, view, int(signf(float((seq.back() as Dictionary)["cx"]) - sx)), side])
				ok = false
			# Negatives: the pack's corpse picture laid down on its ground centre after the last
			# frame (the old cut), and the fall played at every third frame.
			for corpse in _corpses_for(fam):
				var img: Image = _image(corpse)
				var laid: Dictionary = _placed(img, Appearance.corpse_rect(sx, sy, Vector2(img.get_size())))
				if not _step_complaint(seq[seq.size() - 2], laid, sole).is_empty():
					corpse_breaks += 1
			var coarse: Array = []
			for i in range(0, seq.size(), 3):
				coarse.append(seq[i])
			var coarse_ok: bool = true
			for i in range(1, coarse.size()):
				if not _step_complaint(coarse[i - 1], coarse[i], sole).is_empty():
					coarse_ok = false
			if not coarse_ok:
				coarse_breaks += 1
			judged += 1
	if judged == 0:
		push_error("LANDING: no family falls; nothing was judged")
		return false
	if corpse_breaks == 0:
		push_error("LANDING: the pack's corpse picture after the last fall frame keeps the bounds everywhere; the lane cannot fail")
		ok = false
	if coarse_breaks == 0:
		push_error("LANDING: the falls played at every third frame keep the bounds everywhere; the lane cannot fail")
		ok = false
	if Appearance.lying_key(SURVIVOR, "moonwalk") != "" or Appearance.lying_key("corpse_human_prone", "e") != "":
		push_error("LANDING: a view or a key with no fall answered a lying frame")
		ok = false
	if ok:
		print("LANDING OK %d falls, %d steps from the rest view down to lying flat: at most %.1f%% mass, %.1f columns of centre and %d px of edge a step (bounds %.0f%%, %.0f, %d), the sole row held, each lying to its fall side as its own last frame; the pack's corpse in its place breaks the bounds %d times and the falls at every third frame %d times" % [judged, steps, float(worst["mass"]) * 100.0, float(worst["centre"]), int(worst["edge"]), LAND_MASS_STEP * 100.0, LAND_CENTRE_STEP, LAND_EDGE_STEP, corpse_breaks, coarse_breaks])
		_report.append("LANDING %d falls" % judged)
	return ok


# HEAD: art review round 4 found the side views' settle dissolving the head away first and drawing
# the corpse's in last, so the body lay headless for a beat or three and the head popped back on the
# hold frame; no bound caught it, since the torso filled in as the head drained. Every view
# (HEAD_VIEWS) carries its head across (motion/actions.py HEAD_CARRIED): the side views land face
# down with the head rows above where it fell, the front and back views on their backs with the
# head about where it fell, and each hands the head's colours over to the corpse's in its last
# beats (art review rounds 4 and 5). A head here is the
# fall-side end of a lying body, HEAD_COLS columns of it: the last turned frame's (frame
# FALL_TURNED - 1) and the corpse's (the last frame). Lying on its back (HEAD_SUPINE: the front and
# back views), that end is the head and the arms raised beside it, so a head there is the
# HEAD_CORE pixels of it nearest a point HEAD_COLS / 2 columns in from the end column, at that
# column's middle row (art review round 6: the bloater's south end is 126 px, its head 61). On
# every settle beat one of the two must be
# found, its own colours in their own places, at least HEAD_PRESENT of it, somewhere between where
# the two heads lie, or the two together, where their boxes overlap, as much of the larger as
# the colours hand over; and the corpse's head may not land on more empty pixels at the
# hold frame than the mass bound lets a step add. And the carried head must end on the corpse's
# head: on the last beat, the turned frame's head where it is found lies within HEAD_LAND pixels of
# the corpse's own head (art review round 6 found 24 of 30 front and back settles carrying it to
# the chest, 6.9 to 10 px off). The corpse's head for that is located in the lying body itself:
# on its back, as above; face down, the HEAD_CORE pixels nearest the top of its fall-side third,
# HEAD_COLS / 2 rows down (the end column of a face-down body may be an outstretched hand).
# Negatives: each beat with both heads erased where they were found is refused, in every view;
# where the two heads lie apart, under half of each in its own place is refused, so two heads are
# never counted as one; and a head left where it fell is refused as a landing wherever the corpse's
# head lies farther than HEAD_LAND from it.
const FALL_TURNED: int = 9  # the buckle and the eight turns of motion/actions.py FALL_TURNS
const HEAD_VIEWS: Array[String] = ["s", "e", "n", "w"]
const HEAD_COLS: int = 8
const HEAD_PRESENT: float = 0.5
const HEAD_SLACK: int = 6
const HEAD_CORE: int = 64
const HEAD_LAND: float = 4.0
const HEAD_SUPINE: Array[String] = ["s", "n"]


func _solid(img: Image) -> Dictionary:
	var out: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a8 >= 128:
				out[Vector2i(x, y)] = c.to_rgba32()
	return out


# The fall-side end of a lying body: {pixel: colour} of its last HEAD_COLS columns toward `side`;
# lying on its back (`supine`), the HEAD_CORE of them nearest the head's middle, HEAD_COLS / 2
# columns in from the end column at that column's middle row.
func _head_end(px: Dictionary, side: int, supine: bool) -> Dictionary:
	var end: int = -(1 << 20)
	for p in px.keys():
		end = maxi(end, side * (p as Vector2i).x)
	var out: Dictionary = {}
	for p in px.keys():
		if end - side * (p as Vector2i).x < HEAD_COLS:
			out[p] = px[p]
	if not supine or out.size() <= HEAD_CORE:
		return out
	var rows: Array = []
	for p in out.keys():
		if end - side * (p as Vector2i).x <= 1:
			rows.append((p as Vector2i).y)
	rows.sort()
	var mid := Vector2(float(side * end - side * (HEAD_COLS / 2)), float(rows[rows.size() / 2]))
	return _nearest(out, mid, HEAD_CORE)


# The `count` pixels of `px` nearest `at` ({pixel: colour}), ties to the higher, then the left.
func _nearest(px: Dictionary, at: Vector2, count: int) -> Dictionary:
	var keys: Array = px.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: float = Vector2(a).distance_squared_to(at)
		var db: float = Vector2(b).distance_squared_to(at)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	var out: Dictionary = {}
	for k in range(mini(count, keys.size())):
		out[keys[k]] = px[keys[k]]
	return out


# A lying corpse's own head: on its back, its fall-side end's (`_head_end`); face down, the
# HEAD_CORE pixels nearest the top of its fall-side third (the farthest out of the top row there),
# HEAD_COLS / 2 rows down.
func _corpse_head(px: Dictionary, side: int, supine: bool) -> Dictionary:
	if supine:
		return _head_end(px, side, true)
	var lo: int = 1 << 20
	var hi: int = -(1 << 20)
	for p in px.keys():
		lo = mini(lo, (p as Vector2i).x)
		hi = maxi(hi, (p as Vector2i).x)
	var third: int = (hi - lo + 1) / 3
	var top := Vector2i(0, 1 << 20)
	for p in px.keys():
		var q: Vector2i = p
		if (side > 0 and q.x >= hi - third) or (side < 0 and q.x <= lo + third):
			if q.y < top.y or (q.y == top.y and side * q.x > side * top.x):
				top = q
	return _nearest(px, Vector2(top.x, top.y + HEAD_COLS / 2), HEAD_CORE)


func _centre(px: Dictionary) -> Vector2:
	var s: Vector2 = Vector2.ZERO
	for p in px.keys():
		s += Vector2(p as Vector2i)
	return s / float(maxi(px.size(), 1))


# The best share of `head` found in `frame` at an offset in the box between `from` and `to`, widened
# by HEAD_SLACK each way (the head travels between the two ends, not along the line joining them:
# the corpse's end column may be an outstretched hand beside its head), that offset, and the frame
# pixels found there.
func _head_found(head: Dictionary, frame: Dictionary, from: Vector2, to: Vector2) -> Array:
	var best: int = -1
	var best_at: Vector2i = Vector2i.ZERO
	var x0: int = int(floorf(minf(from.x, to.x))) - HEAD_SLACK
	var x1: int = int(ceilf(maxf(from.x, to.x))) + HEAD_SLACK
	var y0: int = int(floorf(minf(from.y, to.y))) - HEAD_SLACK
	var y1: int = int(ceilf(maxf(from.y, to.y))) + HEAD_SLACK
	for dy in range(y0, y1 + 1):
		for dx in range(x0, x1 + 1):
			var at := Vector2i(dx, dy)
			var n: int = 0
			for p in head.keys():
				if frame.get((p as Vector2i) + at, -1) == int(head[p]):
					n += 1
			if n > best:
				best = n
				best_at = at
	var found: Dictionary = {}
	for p in head.keys():
		if frame.get((p as Vector2i) + best_at, -1) == int(head[p]):
			found[(p as Vector2i) + best_at] = true
	return [float(best) / float(maxi(head.size(), 1)), best_at, found]


# How much head a settle beat carries: the larger share of either head found whole, or of the two
# found together over the larger head, which is what a head handing its colours over to the
# corpse's shows (art review round 5: part of it in each palette on the last beats). The two are
# summed only where they overlap, one head in two palettes: two heads apart are not one head
# (art review round 6, which found the sum hiding a second head on the chest).
func _head_on(frame: Dictionary, h8: Dictionary, hc: Dictionary, path: Vector2) -> Array:
	var a: Array = _head_found(h8, frame, Vector2.ZERO, path)
	var b: Array = _head_found(hc, frame, -path, Vector2.ZERO)
	var together: float = 0.0
	if _boxes_meet(a[2] as Dictionary, b[2] as Dictionary):
		var both: Dictionary = (a[2] as Dictionary).duplicate()
		both.merge(b[2] as Dictionary)
		together = float(both.size()) / float(maxi(maxi(h8.size(), hc.size()), 1))
	return [maxf(together, maxf(float(a[0]), float(b[0]))), a, b]


# Whether the boxes around two sets of pixels share a pixel.
func _boxes_meet(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var ra: Rect2i = Rect2i(a.keys()[0] as Vector2i, Vector2i.ONE)
	for p in a.keys():
		ra = ra.expand(p as Vector2i)
	var rb: Rect2i = Rect2i(b.keys()[0] as Vector2i, Vector2i.ONE)
	for p in b.keys():
		rb = rb.expand(p as Vector2i)
	return ra.grow_individual(0, 0, 1, 1).intersects(rb.grow_individual(0, 0, 1, 1))


func _head() -> bool:
	var ok: bool = true
	var judged: int = 0
	var beats: int = 0
	var worst: float = 1.0
	var worst_at: String = ""
	var worst_add: float = 0.0
	var erased_refused: int = 0
	var apart: int = 0
	var apart_refused: int = 0
	var worst_land: float = 0.0
	var stayed: int = 0
	for fam_v in _families_with_actions().keys():
		var fam: String = String(fam_v)
		if Appearance.action_frames(fam, "fall", "e") == 0:
			continue
		for view in HEAD_VIEWS:
			var frames: int = Appearance.action_frames(fam, "fall", view)
			if frames <= FALL_TURNED:
				push_error("HEAD: %s's %s fall has %d frames, no settle after its %d turned ones" % [fam, view, frames, FALL_TURNED])
				ok = false
				continue
			var side: int = int(Appearance.FALL_SIDE[view])
			var seq: Array = []
			for i in range(FALL_TURNED - 1, frames):
				var img: Image = _image("%s_fall_%s_%d" % [fam, view, i])
				if img == null:
					push_error("HEAD: %s_fall_%s_%d does not load" % [fam, view, i])
					return false
				seq.append(_solid(img))
			var supine: bool = view in HEAD_SUPINE
			var h8: Dictionary = _head_end(seq[0], side, supine)
			var hc: Dictionary = _head_end(seq.back(), side, supine)
			var path: Vector2 = _centre(hc) - _centre(h8)
			var target: Vector2 = _centre(_corpse_head(seq.back(), side, supine))
			var erased_ok: bool = true
			for i in range(1, seq.size() - 1):
				var frame: Dictionary = seq[i]
				var found: Array = _head_on(frame, h8, hc, path)
				var share: float = float(found[0])
				if share < HEAD_PRESENT:
					push_error("HEAD: %s from %s, settle beat %d of %d: only %.0f%% of a head is on the body" % [fam, view, i, seq.size() - 2, share * 100.0])
					ok = false
				if share < worst:
					worst = share
					worst_at = "%s %s beat %d" % [fam, view, i]
				beats += 1
				# Negative: the same beat with both heads taken off where they were found.
				var cut: Dictionary = frame.duplicate()
				for pair in [[h8, (found[1] as Array)[1]], [hc, (found[2] as Array)[1]]]:
					for p in (pair[0] as Dictionary).keys():
						cut.erase((p as Vector2i) + (pair[1] as Vector2i))
				if float(_head_on(cut, h8, hc, path)[0]) >= HEAD_PRESENT:
					erased_ok = false
			# The landing: the carried head, where the last beat has it, on the corpse's own head.
			var carried: Array = _head_found(h8, seq[seq.size() - 2], Vector2.ZERO, target - _centre(h8))
			var off: float = (_centre(h8) + Vector2(carried[1] as Vector2i)).distance_to(target)
			worst_land = maxf(worst_land, off)
			if off > HEAD_LAND:
				push_error("HEAD: %s from %s ends its carried head %.1f px from the corpse's head (bound %.0f)" % [fam, view, off, HEAD_LAND])
				ok = false
			# Negative: the head left where it fell, wherever that is not already the corpse's head.
			if _centre(h8).distance_to(target) > HEAD_LAND:
				stayed += 1
			if not erased_ok:
				push_error("HEAD: %s from %s keeps a head with both heads erased; the lane cannot fail there" % [fam, view])
				ok = false
			else:
				erased_refused += 1
			# Negative: where the two heads lie apart, under half of each where it lies is two
			# heads, not one, and is refused (art review round 6's double head).
			if not _boxes_meet(h8, hc):
				var two: Dictionary = {}
				for pair in [[h8, 0], [hc, 1]]:
					var keys: Array = (pair[0] as Dictionary).keys()
					keys.sort()
					var take: int = int(floor(float(keys.size()) * (HEAD_PRESENT - 0.05)))
					for k in range(take):
						var q: Vector2i = keys[k if int(pair[1]) == 0 else keys.size() - 1 - k]
						two[q] = (pair[0] as Dictionary)[q]
				apart += 1
				if float(_head_on(two, h8, hc, path)[0]) >= HEAD_PRESENT:
					push_error("HEAD: %s from %s takes two half heads apart for one; the lane cannot see a double head there" % [fam, view])
					ok = false
				else:
					apart_refused += 1
			# The hold frame: the corpse's head on what the last beat left empty.
			var last: Dictionary = seq[seq.size() - 2]
			var empty: int = 0
			for p in hc.keys():
				if not last.has(p):
					empty += 1
			var add: float = float(empty) / float(maxi(last.size(), 1))
			worst_add = maxf(worst_add, add)
			if add > LAND_MASS_STEP:
				push_error("HEAD: %s from %s: the corpse's head lands on %d empty pixels at the hold frame, %.1f%% of the last beat" % [fam, view, empty, add * 100.0])
				ok = false
			judged += 1
	if judged == 0:
		push_error("HEAD: no family falls; nothing was judged")
		return false
	if apart == 0:
		push_error("HEAD: no settle's two heads lie apart; the double-head negative judged nothing")
		return false
	if stayed == 0:
		push_error("HEAD: every head falls onto the corpse's; the landing negative judged nothing")
		return false
	if ok:
		print("HEAD OK %d settles in every view, %d beats: a head carried on every one, at least %.0f%% of it (%s), and the corpse's head adds at most %.1f%% of the body at the hold frame (bound %.0f%%); the carried head ends at most %.1f px from the corpse's (bound %.0f), where a head left where it fell is refused (%d of %d); each settle with both heads erased is refused (%d of %d), and two half heads apart are not one (%d of %d)" % [judged, beats, worst * 100.0, worst_at, worst_add * 100.0, LAND_MASS_STEP * 100.0, worst_land, HEAD_LAND, stayed, judged, erased_refused, judged, apart_refused, apart])
		_report.append("HEAD %d settles" % judged)
	return ok


# STRIKE: a lunge and a stagger, rest to their beats and home to rest, with the mass bound a fall
# keeps (art review round 2: the north lunge lost a fifth of its body in one beat) and the sole row
# held: a lunge plants its feet, and a stagger may leave the ground by one row, the knock-back push
# seen from the front (art review round 3's ruling), never more. Negatives: a beat with its lower
# half cut off breaks the mass bound, a lunge beat one row up and a stagger beat two rows up break
# the sole row.
const STAGGER_LIFT: int = 1


func _lifted(seen: Dictionary, rows: int) -> Dictionary:
	var out: Dictionary = seen.duplicate()
	out["low"] = int(seen["low"]) - rows
	return out


func _strike() -> bool:
	var ok: bool = true
	var sx: float = 100.0
	var sy: float = 100.0
	var judged: int = 0
	var worst: float = 0.0
	var worst_at: String = ""
	var refused: int = 0
	var lifts: int = 0
	for fam_v in _families_with_actions().keys():
		var fam: String = String(fam_v)
		for action in ["lunge", "stagger"]:
			if Appearance.action_frames(fam, action, "e") == 0:
				continue
			var allowance: int = STAGGER_LIFT if action == "stagger" else 0
			for view in Appearance.VIEWS:
				var frames: int = Appearance.action_frames(fam, action, view)
				var keys: Array[String] = ["%s_%s" % [fam, view]]
				for i in frames:
					keys.append("%s_%s_%s_%d" % [fam, action, view, i])
				keys.append("%s_%s" % [fam, view])
				var seq: Array = []
				for k in keys:
					seq.append(_drawn_at(k, sx, sy))
				if seq.has({}):
					push_error("STRIKE: %s's %s %s has a frame that does not load" % [fam, view, action])
					ok = false
					continue
				var sole: int = int((seq[0] as Dictionary)["low"])
				for i in range(1, seq.size()):
					var a: Dictionary = seq[i - 1]
					var b: Dictionary = seq[i]
					var mass: float = absf(float(b["n"]) - float(a["n"])) / float(maxi(int(a["n"]), 1))
					if mass > worst:
						worst = mass
						worst_at = "%s %s %s step %d" % [fam, action, view, i]
					if mass > LAND_MASS_STEP:
						push_error("STRIKE: %s %s from %s, step %d of %d: its mass changes %.1f%%, past %.0f%%" % [fam, action, view, i, seq.size() - 1, mass * 100.0, LAND_MASS_STEP * 100.0])
						ok = false
					if int(b["low"]) > sole or int(b["low"]) < sole - allowance:
						push_error("STRIKE: %s %s from %s, step %d: its lowest row is %d, the sole row %d (allowed %d up)" % [fam, action, view, i, int(b["low"]), sole, allowance])
						ok = false
					if int(b["low"]) < sole:
						lifts += 1
				# Negatives on this view's middle beat.
				var mid: Dictionary = seq[(seq.size() - 1) / 2]
				var full: Image = _image(keys[(keys.size() - 1) / 2])
				var cut: Image = full.duplicate() as Image
				for y in range(cut.get_height() / 2, cut.get_height()):
					for x in cut.get_width():
						cut.set_pixel(x, y, Color(0, 0, 0, 0))
				var cut_seen: Dictionary = _placed(cut, Appearance.body_rect(sx, sy, Vector2(cut.get_size()), 1.0))
				var cut_mass: float = absf(float(cut_seen["n"]) - float(mid["n"])) / float(maxi(int(mid["n"]), 1))
				var raised: Dictionary = _lifted(mid, allowance + 1)
				if cut_mass > LAND_MASS_STEP and int(raised["low"]) < sole - allowance:
					refused += 1
				judged += 1
	if judged == 0:
		push_error("STRIKE: no family lunges or staggers; nothing was judged")
		return false
	if refused != judged:
		push_error("STRIKE: a cut beat or a beat lifted past its allowance kept the bounds in %d of %d views; the lane cannot fail" % [judged - refused, judged])
		ok = false
	if ok:
		print("STRIKE OK %d lunges and staggers, rest to their beats and home: at most %.1f%% mass a step (%s, bound %.0f%%), the sole row held (a stagger %d row up on %d steps, its allowance); a beat with its lower half cut off and a beat lifted past its allowance are refused in all %d" % [judged, worst * 100.0, worst_at, LAND_MASS_STEP * 100.0, STAGGER_LIFT, lifts, refused])
		_report.append("STRIKE %d views" % judged)
	return ok


func _corpses_for(fam: String) -> Array[String]:
	var out: Array[String] = []
	var stem: String = "corpse_human_" if fam == SURVIVOR else "corpse_zombie_%s_" % fam.trim_prefix("body_zombie_")
	var dir: DirAccess = DirAccess.open(SPRITES)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with(stem) and f.ends_with(".png"):
			out.append(f.trim_suffix(".png"))
	out.sort()
	return out


func _geometry() -> bool:
	var ok: bool = true
	var judged: int = 0
	# Every derived frame against the picture it was moved from. The swing is generated, the
	# crouched walk and the crawl are moved from the walk frames, so those draw from a wider palette.
	var derived: Dictionary = {SURVIVOR: ["recoil", "reload", "reload_long", "reload_tube", "flinch", "crouch", "fall"]}
	# The magazine's gunmetal: the held pistol's own colours, opaque (actions.py's _weapon_ramp).
	var gunmetal: Dictionary = {}
	var pistol: Image = _image("item_held_pistol")
	if pistol == null:
		push_error("GEOMETRY: no held pistol picture to read the gunmetal from")
		return false
	for c in _colours(pistol).keys():
		var col: Color = Color.hex(int(c))
		col.a = 1.0
		gunmetal[col.to_rgba32()] = true
	# The tube reload's shells: the shells icon's own colours, opaque (actions.py's _shell_ramp).
	var shells: Dictionary = {}
	var shell_icon: Image = _image("item_shells")
	if shell_icon == null:
		push_error("GEOMETRY: no shells icon to read the shells' colours from")
		return false
	for c in _colours(shell_icon).keys():
		var col: Color = Color.hex(int(c))
		col.a = 1.0
		shells[col.to_rgba32()] = true
	# What tells the two loads apart: the colours each has and the other does not (both are
	# outlined in the same black).
	var gunmetal_own: Dictionary = {}
	for c in gunmetal.keys():
		if not shells.has(c):
			gunmetal_own[c] = true
	var shells_own: Dictionary = {}
	for c in shells.keys():
		if not gunmetal.has(c):
			shells_own[c] = true
	var magazines: int = 0
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
				# A reload also draws its magazine, in the held pistol's gunmetal and nothing else -- or,
				# tube-fed, its shells, in the shells icon's colours and nothing else.
				var reload: bool = String(action).begins_with("reload")
				var loads: Dictionary = shells if action == "reload_tube" else gunmetal
				var allowed: Dictionary = palette
				if reload:
					allowed = palette.duplicate()
					allowed.merge(loads)
				# A fall settles onto the family's own corpse picture (motion/actions.py
				# `settle_plan`), so its settle beats and its last frame carry the corpse's colours
				# too, and nothing else.
				if action == "fall":
					allowed = palette.duplicate()
					for corpse in _corpses_for(String(fam)):
						allowed.merge(_colours(_image(corpse)))
				var shows_magazine: bool = false
				for i in Appearance.action_frames(String(fam), String(action), view):
					var key: String = "%s_%s_%s_%d" % [fam, action, view, i]
					var img: Image = _image(key)
					if img == null:
						push_error("GEOMETRY: %s has no picture" % key)
						ok = false
						continue
					judged += 1
					var foreign: int = _foreign(img, allowed)
					if foreign >= 0:
						push_error("GEOMETRY: %s carries colour %08x its rest view does not" % [key, foreign])
						ok = false
					if reload and _carries_any(img, shells_own if action == "reload_tube" else gunmetal_own, palette):
						shows_magazine = true
				if reload and not shows_magazine:
					push_error("GEOMETRY: %s %s %s never shows its magazine" % [fam, action, view])
					ok = false
				elif reload:
					magazines += 1
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
	# The fall ends lying on the ground: its last frame (the corpse it settles onto) is wider than
	# it is tall, as the crawl is.
	if _bounds(fall_e).size.x <= _bounds(fall_e).size.y:
		push_error("GEOMETRY: the fall's last frame is not wider than tall (%s)" % str(_bounds(fall_e).size))
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
	if _carries_any(rest_e, gunmetal, _colours(rest_e)) or _carries_any(rest_e, shells, _colours(rest_e)):
		push_error("GEOMETRY: the rest view already shows gunmetal or shells, so the magazine measure cannot fail")
		ok = false
	if _carries_any(_image("%s_reload_e_1" % SURVIVOR), shells_own, _colours(rest_e)) or _carries_any(_image("%s_reload_tube_e_1" % SURVIVOR), gunmetal_own, _colours(rest_e)):
		push_error("GEOMETRY: a magazine reload shows shells, or the tube reload gunmetal, so neither is judged by its own load")
		ok = false
	if _bounds(rest_e).size.x > _bounds(rest_e).size.y:
		push_error("GEOMETRY: the standing rest view measures wider than tall, so the prone measure cannot fail")
		ok = false
	if ok:
		print("GEOMETRY OK %d derived frames carry only their rest view's colours (a fall's also its corpse's, a reload's magazine its gunmetal or its shells their own red and brass, shown in %d reload views); crouch < rest, the fall and the crawl lie flat" % [judged, magazines])
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
func _reach_complaint(hands: Array, rest: Array, reach: int, min_travel: int = 2) -> String:
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
	if travel < min_travel:
		return "the weapon hand travels %d px" % travel
	if closest > reach or off_travel < 4:
		return "the off hand comes within %d px of the weapon hand (wanted %d) and travels %d px" % [closest, reach, off_travel]
	if hands[hands.size() - 1][0] != rest[0]:
		return "it ends with the weapon hand at %s, not the stance's %s" % [str(hands[hands.size() - 1][0]), str(rest[0])]
	return ""


func _reach() -> bool:
	var ok: bool = true
	for action in ["reload", "reload_long", "reload_tube"]:
		for view in VIEWS:
			var rest: Array = [Appearance.HELD_HANDS["primary"][view], Appearance.HELD_HANDS["secondary"][view]]
			# A long gun seen from behind stands taller than the body: it is held still but for the
			# rack's jolt, a pixel up, so its stock and muzzle never show a frame at a time.
			var travel: int = 1 if action != "reload" and view == "n" else 2
			var complaint: String = _reach_complaint(_reload_hands(action, view), rest, 3 if action == "reload" else LONG_REACH, travel)
			if not complaint.is_empty():
				push_error("REACH: %s %s: %s" % [action, view, complaint])
				ok = false
	# Negative: the head-bob reload this replaced -- three beats, hands never moving -- is refused,
	# and so is a reload whose off hand never leaves its side.
	var rest_e: Array = [Appearance.HELD_HANDS["primary"]["e"], Appearance.HELD_HANDS["secondary"]["e"]]
	var still: Array = []
	for i in 8:
		still.append(rest_e.duplicate())
	if _reach_complaint(still.slice(0, 3), rest_e, LONG_REACH).is_empty() or _reach_complaint(still, rest_e, LONG_REACH).is_empty() or _reach_complaint(still, rest_e, LONG_REACH, 1).is_empty():
		push_error("REACH: a reload whose hands never move was not refused")
		ok = false
	if ok:
		print("REACH OK all three reloads, every view: the weapon hand travels, the off hand comes to it and leaves, and it ends on the stance")
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
	# And lays it down: the settled body is the fall's own last frame, dressed (LANDING judges the
	# sequence these calls draw).
	for call in ["Appearance.lying_key(", "Appearance.dressed_texture(", "_lying_drawn.append("]:
		if not corpse.contains(call):
			return "_draw_corpse does not lay the fallen body down (no %s)" % call
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
		"Appearance.lying_key(",
		"Appearance.dressed_texture(",
	]
	for needle in sabotage:
		if _readers_complaint(text.replace(String(needle), "_nothing(")).is_empty():
			push_error("READERS: removing '%s' went unnoticed" % needle)
			ok = false
	if ok:
		print("READERS OK the frame loop feeds the clock, the draw merges its action before the picture, the corpse pass draws the fall and lays the body down as its last frame, dressed")
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
	# A clothed body falls in its clothes: the outfit act() was drawn with goes with the fall, and a
	# body drawn bare falls bare.
	var dressed_clock: Variant = AnimClock.new()
	var clothes: Array = ["wear_tee_sand", "wear_pants_denim", "wear_shoes_worn"]
	dressed_clock.act(pid, world, SURVIVOR, "w", clothes)
	dressed_clock.act(pid + 1, world, SURVIVOR, "w")
	dressed_clock.from_events(world, [{"type": "entity.killed", "entity": pid}, {"type": "entity.killed", "entity": pid + 1}], 2.0)
	if (dressed_clock.fall_of(pid).get("outfit", []) as Array) != clothes or not (dressed_clock.fall_of(pid + 1).get("outfit", []) as Array).is_empty():
		push_error("CLOCK: the fall carried %s / %s, wanted the outfit it was drawn in and none for a bare body" % [str(dressed_clock.fall_of(pid).get("outfit")), str(dressed_clock.fall_of(pid + 1).get("outfit"))])
		ok = false
	# And every fall frame composes dressed: each garment's member for it is there at the frame's own
	# (wider) canvas, so dressed_image answers rather than leaving a garment off.
	for view in VIEWS:
		for i in Appearance.action_frames(SURVIVOR, "fall", view):
			var frame: String = "%s_fall_%s_%d" % [SURVIVOR, view, i]
			var bare: Image = Appearance.image_of(frame)
			var dressed: Image = Appearance.dressed_image(SURVIVOR, frame, clothes)
			if bare == null or dressed == null or dressed.get_size() != bare.get_size() or dressed.get_data() == bare.get_data():
				push_error("CLOCK: %s does not compose dressed at its own canvas" % frame)
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
	var look: Dictionary = (rec as Dictionary).get("look", {}) as Dictionary
	var family: String = String(look.get("sprite", ""))
	var outfit: Variant = look.get("outfit", [])
	for m in _members(family):
		if Appearance.resolve(String(m)) == texture:
			return String(m)
		# A clothed body draws every frame dressed, its action pictures included
		# (`Appearance.body_texture`).
		if outfit is Array and not (outfit as Array).is_empty() \
				and Appearance.dressed_texture(family, String(m), outfit as Array) == texture:
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
	var own: String = Appearance.reload_action(w, pid)
	if before.contains("_reload") or not during.contains("_reload_") or after.contains("_reload"):
		return _fail("RELOAD", "drawn '%s' before, '%s' in Reload, '%s' after" % [before, during, after])
	if not during.contains("_%s_" % own):
		return _fail("RELOAD", "the player's weapon calls for %s and drew %s" % [own, during])
	# The other variants: a hunting rifle, then a pump shotgun, put in the player's primary hand
	# while the world is still -- the rifle drops a magazine, the shotgun takes shells.
	var drew: Array = []
	for pair in [["item.rifle.hunting", "_reload_long_"], ["item.shotgun.pump", "_reload_tube_"]]:
		var eq: Dictionary = w.components.get_component(pid, "equipment") as Dictionary
		var slots_saved: Dictionary = (eq.get("slots", {}) as Dictionary).duplicate(true)
		var gun: int = SimItems.spawn_item(w, String(pair[0]), {})
		(eq["slots"] as Dictionary)["primary"] = gun
		w.components.set_component(pid, "rangedWeapon", fire)
		fire["state"] = int(SimRanged.FireState.Reload)
		await _still(main)
		var gun_during: String = _drawn(main, pid)
		eq["slots"] = slots_saved
		if saved is Dictionary:
			w.components.set_component(pid, "rangedWeapon", saved)
		else:
			w.components.remove_component(pid, "rangedWeapon")
		w.despawn(gun)
		await _still(main)
		var restored: String = _drawn(main, pid)
		if not gun_during.contains(String(pair[1])) or restored.contains("_reload"):
			return _fail("RELOAD", "%s in hand drew '%s' in Reload, and '%s' put back" % [pair[0], gun_during, restored])
		drew.append(gun_during)
	print("RELOAD OK the Reload state drew %s with the player's own weapon, %s with a rifle and %s with a pump shotgun, and %s either side" % [during, drew[0], drew[1], after])
	_report.append("RELOAD %s / %s / %s" % [during, drew[0], drew[1]])
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
	# The five-beat lunge lasts half a second at the common zombie's 10 fps; 0.7 s on it is over.
	for i in 14:
		await _tick(main)
	var settled: String = _drawn(main, z)
	var player_settled: String = _drawn(main, pid)
	if settled.contains("_lunge_") or player_settled.contains("_flinch_"):
		ok = _fail("LUNGE", "still drawn '%s' / player '%s' 0.7 s on" % [settled, player_settled])
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
	# Ten beats at 12 fps: 0.83 s; 1.2 s on it has played and the body lies as its last frame.
	for i in 24:
		await _tick(main)
	var gone: String = _fell(main, z)
	var lying: String = _lay(main, z)
	if not fall.contains("_fall_"):
		ok = _fail("FALL", "the killing blow drew no fall in the corpse pass (zombie alive: %s)" % str(w.entities.is_alive(z) if w.entities.has_method("is_alive") else "?"))
	if not gone.is_empty():
		ok = _fail("FALL", "1.2 s on, the fall still drew %s instead of the settled body" % gone)
	if fall.contains("_fall_") and lying != Appearance.lying_key(fall.substr(0, fall.find("_fall_")), fall.substr(fall.find("_fall_") + 6, 1)):
		ok = _fail("FALL", "the settled body drew '%s', not the fall's own last frame after %s" % [lying, fall])
	if ok:
		print("LUNGE OK attack.connected drew the zombie %s, %s before and %s after" % [lunge, before, settled])
		print("FLINCH OK the same hit drew the player %s, %s before and %s after" % [flinch, player_before, player_settled])
		print("STAGGER OK entity.staggered drew the zombie %s" % stagger)
		print("FALL OK the killing blow drew %s in the corpse pass, and the settled body lay as %s after it played" % [fall, lying])
		_report.append("LUNGE %s" % lunge)
		_report.append("FLINCH %s" % flinch)
		_report.append("STAGGER %s" % stagger)
		_report.append("FALL %s" % fall)
	return ok


func _lay(main: Node, id: int) -> String:
	for f in main.get("_lying_drawn") as Array:
		if int((f as Dictionary).get("id", -1)) == id:
			return String((f as Dictionary)["key"])
	return ""


func _fell(main: Node, id: int) -> String:
	for f in main.get("_falls_drawn") as Array:
		if int((f as Dictionary).get("id", -1)) == id:
			return String((f as Dictionary)["key"])
	return ""

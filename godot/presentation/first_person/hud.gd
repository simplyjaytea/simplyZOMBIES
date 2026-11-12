extends Control
# The first-person screen's words. It follows the standing HUD rules rather than inventing a
# second language: condition and needs arrive as prose from `sim/condition.gd` and
# `needs.hud_clause`, there is no bar to fill and no number to read, and the help line carries no
# digit. The gate scans every line this file will draw, so a numeric slip is red rather than a
# matter of taste.
#
# Drawn with `draw_string` rather than anchored Labels for the same reason `ui/hud.gd` does: a
# Control parented to a CanvasLayer has no rect of its own until one is set, and anchor presets on
# children resolve against nothing. `lines()` is the one list both the draw and the gate read.
#
# How it is dressed (docs/46, "Words on the screen"): no slab behind anything. The state sentences
# stand low on the left in bone ink over a soft shadow, harm in rust; a sentence arrives at full
# strength, and one that only says all is well recedes after a few seconds and never leaves. The
# prompt stands under the centre in amber, its key on a keycap. The keys are a short strip of
# keycaps along the top that leaves once the player is walking, and comes back whenever the
# pointer is free or the world is held. Every fade runs on the wall clock (the frame's own delta),
# never the sim's tick, so a held world still breathes. `marks()` is the one list the draw paints
# and `godot:check:fp_look`'s WORDS lane reads: what is drawn, where, in which ink and how strongly.

const Chrome = preload("res://ui/chrome.gd")
const Kit = preload("res://ui/kit.gd")
const Motion = preload("res://ui/motion.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimStances = preload("res://sim/stances.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimAim = preload("res://sim/aim.gd")

# === PRESENTATION TUNING ===========================================================================
# Every colour, strength, distance and time the words are dressed with. Colours are docs/46's colour
# script, sRGB, as they read under neutral white light.
#
# Inks.
const INK: Color = Color("#E4DFCF") # bone: every sentence that is not harm
const INK_PROMPT: Color = Color("#E2A33A") # amber: the prompt under the centre, and the held world
const INK_HARM: Color = Color("#DE6A3F") # rust, lifted far enough to read over wet asphalt and at night
const INK_SHADOW: Color = Color("#07090C") # the soft shadow under every word
# The soft shadow: the word again in INK_SHADOW at each offset (pixels) and strength, painted in this
# order under the ink. The first two are the fall, down and to the right, which lifts the word off the
# ground; the eight one-pixel taps are the rim that keeps bone ink a whole letter on a white sky. Drawn
# as offset copies because the face has no antialiasing and its stroked outline closes the counters.
const SHADOW_TAPS: Array = [
	[Vector2(2.0, 3.0), 0.35], [Vector2(1.0, 2.0), 0.55],
	[Vector2(-1.0, -1.0), 0.75], [Vector2(1.0, -1.0), 0.75], [Vector2(-1.0, 1.0), 0.75], [Vector2(1.0, 1.0), 0.75],
	[Vector2(-1.0, 0.0), 0.75], [Vector2(1.0, 0.0), 0.75], [Vector2(0.0, -1.0), 0.75], [Vector2(0.0, 1.0), 0.75],
]
# One size: VT323 is pixel-exact at 25 (one font pixel, one screen pixel) and this screen uses no other.
const BODY_SIZE: int = 25
# Where things stand. Pixels from the window's edges unless a fraction of its height.
const MARGIN: float = 28.0 # the left edge of the state sentences and of the key strip
const STATE_FOOT: float = 26.0 # from the window's bottom to the last state sentence's descender
const LINE_PITCH: float = 30.0 # baseline to baseline
const PROMPT_TOP_FRACTION: float = 0.62 # the prompt's top, as a share of the window's height: under the centre, over the hands
const KEYS_TOP: float = 20.0 # the key strip's top
const KEY_WORD_GAP: float = 7.0 # a keycap to its word
const KEY_PAIR_GAP: float = 18.0 # a word to the next keycap
# How strongly each kind of sentence stands once it has been read (1 is full).
const REST_HARM: float = 1.0
const REST_SAID: float = 1.0 # a tell, the weapon's state, the chronicle's news
const REST_NEED: float = 0.82 # a need that presses
const REST_STEADY: float = 0.52 # all is well: steady, the posture, the clock's speed
const KEY_WORD_ALPHA: float = 0.80 # a strip word beside its keycap
# The wall clock, in seconds.
const ARRIVE_S: float = 0.25 # a new sentence comes up over this long
const FRESH_S: float = 4.0 # and stands at full strength this long
const RECEDE_S: float = 1.5 # before it eases to its rest
const KEYS_SHOW_S: float = 20.0 # the key strip stays this long after it is called for
const KEYS_FADE_S: float = 1.5 # and leaves over this long
const KEYS_REST_ALPHA: float = 0.0 # what is left of it afterwards: nothing
const ALERT_FADE_MS: int = 400 # an alert's last moments
# The end of the run and the held world.
const HELD_WASH_ALPHA: float = 0.0 # a wash over the street while the world is held (0 is none)
# ===================================================================================================

# Worst-part states from condition.gd, as a sentence rather than a grade. Kept local because it is
# wording, not a sim fact, and `ui/hud.gd` owns the top-down screen's own copy of the same words.
const CONDITION_WORDS: Array[String] = ["", "hurt", "badly hurt", "barely standing"]
const HELP: String = "WASD walk   mouse look   E use/ledger   LMB/F swing   G fire   R reload   P hold   Esc release or title   click to look"
# The key strip the screen paints: the keys a first minute needs, each a keycap and a word. It says nothing
# HELP does not (the WORDS lane holds every keycap and word here to HELP, which `lines()` carries whole for the
# digit scan), and the key reference holds the rest.
const KEY_STRIP: Array = [["WASD", "walk"], ["E", "use"], ["F", "swing"], ["P", "hold"], ["Esc", "release"]]
# The prompt's key: a prompt that opens with one of these and a space wears it as a keycap.
const PROMPT_KEYS: Array[String] = ["E"]
# What the held world says, in the state sentences' place.
const HELD_WORLD_LINE: String = "The world is holding still."
# The kinds of sentence, which decide the ink and the rest.
enum Kind { HARM, SAID, NEED, STEADY, HELD }
# The end-of-run panel: the shell's heading and frame, held to this screen's own size. One action,
# and it goes back to the game's title rather than quitting the process.
const RUN_OVER_HEADING: String = "the run is over"
const RUN_OVER_ACTION: String = "Escape returns to the title"
const END_PANEL_W: float = 720.0
const END_PAD: float = 40.0
const END_LINE_H: float = 34.0
# The harm lines (docs/05, docs/01's scarce information). A wound is named for this long after it lands.
const WOUND_HUD_TICKS: int = 80
const HELD_LINE: String = "Something has hold of you. F struggles free."
const HELD_SEVERAL_LINE: String = "Several things have hold of you. F struggles free."
const BLEEDING_LINE: String = "You are bleeding."
# wounds.gd's own first-person bleeding clause, which the line above already says; not repeated.
const BLEEDING_CLAUSE_FIRST: String = "You're bleeding."
const INFECTED_LINE: String = "You have been bitten and the wound is wrong."
# The zombie tells: prose cues from the sim's own readers (no sound, no marker). A notice is a zombie that went
# Seek or Pursue on a fresh notice (shambler.gd `_notice`, its noticedAt), within TELL_NOTICE_METRES, for
# TELL_NOTICE_TICKS (3 s). "Ahead", "left", "right" and "behind" are measured from the player's look (its aim).
const TELL_NOTICE_TICKS: int = 60
const TELL_NOTICE_METRES: float = 30.0
const TELL_CLOSE_METRES: float = 6.0
const TELL_SCREAM_TICKS: int = 100
const TELL_SCREAM_METRES: float = 60.0
const TELL_MAX_LINES: int = 2
const TELL_AHEAD_HALF: float = PI / 4.0
const TELL_BEHIND_FROM: float = 3.0 * PI / 4.0
const NOTICE_LINES: Dictionary = {
	"ahead": "Something groans ahead.",
	"left": "Something groans to your left.",
	"right": "Something groans to your right.",
	"behind": "Something groans behind you.",
}
const CLOSE_LINES: Dictionary = {
	"left": "Something is close to your left.",
	"right": "Something is close to your right.",
	"behind": "Something is close behind you.",
}
const SEVERAL_STIR_LINE: String = "Several things stir."
const SCREAM_LINE: String = "A scream carries across the district."

var world: Variant = null
var player: int = -1
var prompt: String = ""
# The clock in words, from session.gd's speed_words: "normal speed", "fast", "paused".
var time_words: String = ""
var alert: String = ""
var menu_open: bool = false
var paused: bool = false
var inventory_open: bool = false
# A chronicle line the scene wants said once -- the succession sentence ("You are Mara Sato now.").
var news: String = ""
var run_over: bool = false
# True while the pointer is free of the look (the scene's own flag): the key strip comes back for it.
var pointer_free: bool = false
# What is left of the alert's life on the wall clock, in milliseconds; the scene sets it beside the alert.
# Negative means nobody said, and the alert stands at full strength.
var alert_left_ms: int = -1
var _end_lines: Array[String] = []
# The wall clock this screen fades on: the sum of its own frame deltas, so a fixed frame step gives the
# same picture twice and a held world still moves it.
var _clock: float = 0.0
# The state sentences as [text, Kind], read from the sim once per `set_state`.
var _rows: Array = []
# When each sentence on screen arrived, by its text, on `_clock`.
var _born: Dictionary = {}
var _prompt_shown: String = ""
var _prompt_born: float = 0.0
var _alert_shown: String = ""
var _alert_born: float = 0.0
# When the key strip was last called for: at the start, and whenever the pointer is free or the world held.
var _keys_called: float = 0.0
var _seen_state: bool = false
# The last painted picture's signature, so a frame in which nothing moved paints nothing.
var _painted: int = 0
# The key strip's width, measured once: the face is one face and the strip one list.
static var _strip_w: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()
	get_viewport().size_changed.connect(_sync_size)


func _sync_size() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _process(delta: float) -> void:
	tick_wall(delta)


## Moves this screen's wall clock on by `seconds` and repaints if anything it draws has changed strength.
## `_process` calls it with the frame's delta; a gate calls it to let time pass.
func tick_wall(seconds: float) -> void:
	_clock += maxf(0.0, seconds)
	_repaint_if_changed()


func set_state(world_ref: Variant, player_ref: int, prompt_text: String, alert_text: String, menu: bool, is_paused: bool, inventory: bool = false, news_text: String = "") -> void:
	world = world_ref
	player = player_ref
	prompt = prompt_text
	alert = alert_text
	menu_open = menu
	paused = is_paused
	inventory_open = inventory
	news = news_text
	_rows = _state_rows()
	_note_arrivals()
	_repaint_if_changed()


# Which sentences are new. A sentence already on screen keeps its age; one that left and comes back arrives
# again. The first state this screen is given stands as if it had just finished arriving: a boot does not
# fade its own words in.
func _note_arrivals() -> void:
	var first: bool = not _seen_state
	_seen_state = true
	var born_at: float = _clock - ARRIVE_S if first else _clock
	var live: Dictionary = {}
	for row in _rows:
		var text: String = String((row as Array)[0])
		live[text] = _born.get(text, born_at)
	_born = live
	if prompt != _prompt_shown:
		_prompt_shown = prompt
		_prompt_born = born_at
	if alert != _alert_shown:
		_alert_shown = alert
		_alert_born = born_at
	if first or pointer_free or paused:
		_keys_called = _clock


func _repaint_if_changed() -> void:
	var view_size: Vector2 = size if size != Vector2.ZERO else get_viewport_rect().size
	var sig: int = hash(marks(view_size))
	if sig != _painted:
		queue_redraw()


## The end of the run: `lines` is the chronicle's epitaph, already prose. The screen stays up until
## the process leaves; the first-person title flow is a later piece.
func set_run_over(end_lines: Array) -> void:
	run_over = true
	_end_lines.clear()
	for line in end_lines:
		_end_lines.append(String(line))
	if _end_lines.is_empty():
		_end_lines.append("There is nobody left to be.")
	visible = true
	queue_redraw()


## The harm, the weapon and the state lines, in the order the panel draws them: held, the newest wound,
## bleeding, the blood-loss words, infected, the weapon, then the body's posture and needs. One list, so the
## gate and the eyes agree.
func _state_lines() -> Array[String]:
	var out: Array[String] = []
	for row in _state_rows():
		out.append(String((row as Array)[0]))
	return out


# The same sentences, each with its Kind: [text, Kind]. The Kind is how the sentence is dressed (its ink and
# how far it recedes), never what it says.
func _state_rows() -> Array:
	var out: Array = []
	if world != null and player >= 0:
		out.append_array(_body_rows())
		for tell in _tell_lines():
			out.append([tell, Kind.SAID])
		var needs: String = SimNeeds.hud_clause(world, player)
		out.append([needs, Kind.NEED] if needs != "" else ["You feel steady.", Kind.STEADY])
		# The posture word the top-down paper doll shows under the figure (`SimStances.name_of`).
		out.append(["You are " + SimStances.name_of(SimStances.stance_of(world.components, player)) + ".", Kind.STEADY])
		if not time_words.is_empty():
			out.append(["Time is " + time_words + ".", Kind.STEADY])
		var view: Dictionary = SimCondition.view(world, player)
		var worst: int = int(view.get("worst", 0)) if not view.is_empty() else 0
		if worst > 0 and worst < CONDITION_WORDS.size():
			out.append(["You are " + CONDITION_WORDS[worst] + ".", Kind.HARM])
	if news != "":
		out.append([news, Kind.SAID])
	if paused:
		out.append([HELD_WORLD_LINE, Kind.HELD])
	return out


# The tells the player can hear about, nearest first, at most TELL_MAX_LINES. Read only from the sim.
func _tell_lines() -> Array[String]:
	var out: Array[String] = []
	if world == null or player < 0:
		return out
	var ppos: Vector2 = _pos_of(player)
	var yaw: float = SimAim.radians_of(world.components, player)
	var now: int = int(world.tick)
	var candidates: Array = []
	var noticers: Array = []
	for zed in world.components.query(["shambler", "position"]):
		var sd: Dictionary = world.components.get_component(int(zed), "shambler") as Dictionary
		var st: int = int(sd.get("state", -1))
		var zp: Vector2 = _pos_of(int(zed))
		var d: float = ppos.distance_to(zp)
		var rel: float = _relative(ppos, zp, yaw)
		var fresh: bool = now - int(sd.get("noticedAt", -100000)) < TELL_NOTICE_TICKS
		if (st == SimShambler.ShamblerState["Seek"] or st == SimShambler.ShamblerState["Pursue"]) and fresh and d <= TELL_NOTICE_METRES:
			noticers.append({"d": d, "sector": _sector(rel)})
		if st == SimShambler.ShamblerState["Pursue"] and d <= TELL_CLOSE_METRES and absf(rel) > TELL_AHEAD_HALF:
			candidates.append({"d": d, "line": CLOSE_LINES[_sector(rel)]})
	if noticers.size() == 1:
		var one: Dictionary = noticers[0] as Dictionary
		candidates.append({"d": float(one["d"]), "line": NOTICE_LINES[String(one["sector"])]})
	elif noticers.size() > 1:
		var nearest: float = INF
		for n in noticers:
			nearest = minf(nearest, float((n as Dictionary)["d"]))
		candidates.append({"d": nearest, "line": SEVERAL_STIR_LINE})
	for sc in world.components.query(["alarm", "position"]):
		var ad: Dictionary = world.components.get_component(int(sc), "alarm") as Dictionary
		var ready: int = int(ad.get("ticksUntilReady", 0))
		var cooldown: int = int(ad.get("cooldownTicks", 600))
		var sd_dist: float = ppos.distance_to(_pos_of(int(sc)))
		# A scream is the alarm's own clock: set to the cooldown when it fires, counted down since.
		if ready > 0 and cooldown - ready <= TELL_SCREAM_TICKS and sd_dist <= TELL_SCREAM_METRES:
			candidates.append({"d": sd_dist, "line": SCREAM_LINE})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for c in candidates:
		if out.size() >= TELL_MAX_LINES:
			break
		out.append(String((c as Dictionary)["line"]))
	return out


func _pos_of(ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


# The angle from `from` to `to`, measured from the look (`yaw`). Positive is to the right: a look at (cos r, sin r)
# has its right hand at r + 90 degrees (the scene's _push_aim and _right_horizontal).
static func _relative(from: Vector2, to: Vector2, yaw: float) -> float:
	var a: float = atan2(to.y - from.y, to.x - from.x)
	return wrapf(a - yaw, -PI, PI)


static func _sector(rel: float) -> String:
	if absf(rel) <= TELL_AHEAD_HALF:
		return "ahead"
	if absf(rel) >= TELL_BEHIND_FROM:
		return "behind"
	return "right" if rel > 0.0 else "left"


func _body_rows() -> Array:
	var out: Array = []
	var grabbed: Variant = world.components.get_component(player, "grabbed")
	if grabbed is Dictionary:
		var holders: int = ((grabbed as Dictionary).get("sources", []) as Array).size()
		out.append([HELD_SEVERAL_LINE if holders > 1 else HELD_LINE, Kind.HARM])
	var wound: String = _newest_wound_line()
	if wound != "":
		out.append([wound, Kind.HARM])
	var view: Dictionary = SimCondition.view(world, player)
	var bleeding: bool = false
	for part in (view.get("parts", []) as Array):
		var pd: Dictionary = part as Dictionary
		if bool(pd.get("bleeding", false)):
			bleeding = true
	if bleeding:
		out.append([BLEEDING_LINE, Kind.HARM])
	var blood: String = SimWounds.hud_clause(world, player)
	if blood != "" and blood != BLEEDING_CLAUSE_FIRST:
		out.append([blood, Kind.HARM])
	if _transmitted_exposure():
		out.append([INFECTED_LINE, Kind.HARM])
	var weapon: String = _weapon_line()
	if weapon != "":
		out.append([weapon, Kind.SAID])
	return out


# A bite that transmitted and was neither cauterised nor amputated (infection.gd's exposures). A bite that did
# not transmit says nothing: the condition view reads every exposure as "watch", and that would tell the player
# about a bite that did nothing.
func _transmitted_exposure() -> bool:
	var state: Variant = world.components.get_component(player, "zombieInfection")
	if not (state is Dictionary):
		return false
	for e in ((state as Dictionary).get("exposures", []) as Array):
		var ed: Dictionary = e as Dictionary
		if bool(ed.get("transmitted", false)) and not bool(ed.get("cauterized", false)) and not bool(ed.get("amputated", false)):
			return true
	return false


# The newest wound, as a sentence: the sim's presentation word (a bite can present as a scratch, docs/01),
# on the part's label. Shown for WOUND_HUD_TICKS after it landed.
func _newest_wound_line() -> String:
	var inj: Variant = world.components.get_component(player, "injuries")
	if not (inj is Dictionary):
		return ""
	var best: Dictionary = {}
	var best_at: int = -1
	for wound in ((inj as Dictionary).get("wounds", []) as Array):
		var wd: Dictionary = wound as Dictionary
		var at: int = int(wd.get("sustainedAtTick", -1))
		if at > best_at:
			best_at = at
			best = wd
	if best.is_empty() or int(world.tick) - best_at >= WOUND_HUD_TICKS:
		return ""
	var noun: String = String(best.get("presentation", best.get("kind", "wound")))
	return "A %s on your %s." % [noun, SimCondition.label_of(String(best.get("bodyPart", "")))]


# The fire state, from the held weapon's own state (ranged.gd's FireState). Idle is nothing. A press in
# Steady does nothing: the shot fires on its own when Steady ends, so Steady says so.
func _weapon_line() -> String:
	var rw: Variant = world.components.get_component(player, "rangedWeapon")
	if not (rw is Dictionary):
		return ""
	var st: int = int((rw as Dictionary).get("state", SimRanged.FireState.Idle))
	if st == SimRanged.FireState.Raise:
		return "You raise the weapon."
	if st == SimRanged.FireState.Steady:
		return "You are steady. The weapon fires on its own."
	if st == SimRanged.FireState.Recover:
		return "The weapon recovers."
	if st == SimRanged.FireState.Reload:
		return "You are reloading."
	if st == SimRanged.FireState.Clearing:
		return "You clear a jam."
	return ""


## Every line of prose this screen can show, for the gate's digit scan and the player's eyes.
func lines() -> Array[String]:
	var out: Array[String] = []
	if run_over:
		out.append(RUN_OVER_HEADING)
		for line in _end_lines:
			out.append(line)
		out.append(RUN_OVER_ACTION)
		return out
	out.append_array(_state_lines())
	out.append(HELP)
	if menu_open:
		out.append("The ledger is open. Escape closes it.")
	if inventory_open:
		out.append("The inventory is open. Escape closes it.")
	out.append(prompt)
	out.append(alert)
	return out


# --- the picture ------------------------------------------------------------------------------------

## Everything this screen paints at `view_size`, in paint order: one Dictionary per mark. A mark's "what" is
## "line" (a sentence: text, at = its baseline's left end, ink, alpha, and in "kind" its Kind, or "key",
## "prompt" or "alert"), "keycap" (a key: text, at = its top-left, alpha, and "key" or "prompt" in "kind")
## or "wash" (the whole view: ink, alpha). `_draw` paints
## exactly this list and the WORDS lane reads it, so the gate and the eyes agree on what is on screen.
func marks(view_size: Vector2) -> Array:
	var out: Array = []
	if run_over:
		return out
	var still: bool = Motion.reduced()
	var font: Font = Chrome.font()
	if paused and HELD_WASH_ALPHA > 0.0:
		out.append({"what": "wash", "ink": Chrome.FIELD, "alpha": HELD_WASH_ALPHA})

	# The key strip, along the top.
	var keys_alpha: float = _keys_alpha(still)
	if keys_alpha > 0.0:
		var x: float = MARGIN
		for pair in KEY_STRIP:
			var key: String = String((pair as Array)[0])
			var word: String = String((pair as Array)[1])
			out.append({"what": "keycap", "kind": "key", "text": key, "at": Vector2(x, KEYS_TOP), "alpha": keys_alpha})
			x += _keycap_w(font, key) + KEY_WORD_GAP
			out.append({"what": "line", "kind": "key", "text": word, "at": Vector2(x, KEYS_TOP + _keycap_base()), "ink": INK, "alpha": keys_alpha * KEY_WORD_ALPHA})
			x += _text_w(font, word) + KEY_PAIR_GAP

	# The state sentences, low on the left: the last one sits on the foot and the rest stack up from it.
	var base: float = roundf(view_size.y - STATE_FOOT - (Chrome.line_height(BODY_SIZE) - Chrome.ascent(BODY_SIZE)))
	base -= LINE_PITCH * float(_rows.size() - 1)
	for row in _rows:
		var text: String = String((row as Array)[0])
		var kind: int = int((row as Array)[1])
		var alpha: float = _row_alpha(kind, _clock - float(_born.get(text, _clock - ARRIVE_S)), still)
		out.append({"what": "line", "kind": kind, "text": text, "at": Vector2(MARGIN, base), "ink": _ink_of(kind), "alpha": alpha})
		base += LINE_PITCH

	# The prompt, under the centre; an alert takes its place while it lasts.
	# No reticle and no centre dot: docs/40 owner question 6's default, and docs/09 bans a reticle
	# that reports certainty. The weapon in the hand is the only aiming furniture.
	var top: float = roundf(view_size.y * PROMPT_TOP_FRACTION)
	if alert != "":
		var a: float = _arrival(_clock - _alert_born, still)
		if alert_left_ms >= 0 and not still:
			a *= clampf(float(alert_left_ms) / float(ALERT_FADE_MS), 0.0, 1.0)
		var w: float = _text_w(font, alert)
		out.append({"what": "line", "kind": "alert", "text": alert, "at": Vector2(roundf((view_size.x - w) * 0.5), top + _keycap_base()), "ink": INK, "alpha": a})
	elif prompt != "":
		var pa: float = _arrival(_clock - _prompt_born, still)
		var key: String = _prompt_key(prompt)
		if key == "":
			var pw: float = _text_w(font, prompt)
			out.append({"what": "line", "kind": "prompt", "text": prompt, "at": Vector2(roundf((view_size.x - pw) * 0.5), top + _keycap_base()), "ink": INK_PROMPT, "alpha": pa})
		else:
			var rest: String = prompt.substr(key.length() + 1)
			var cap_w: float = _keycap_w(font, key)
			var total: float = cap_w + KEY_WORD_GAP + _text_w(font, rest)
			var left: float = roundf((view_size.x - total) * 0.5)
			out.append({"what": "keycap", "kind": "prompt", "text": key, "at": Vector2(left, top), "alpha": pa})
			out.append({"what": "line", "kind": "prompt", "text": rest, "at": Vector2(left + cap_w + KEY_WORD_GAP, top + _keycap_base()), "ink": INK_PROMPT, "alpha": pa})
	return out


func _draw() -> void:
	var font: Font = Chrome.font()
	if run_over:
		_draw_run_over(font)
		return
	var view_size: Vector2 = size
	if view_size == Vector2.ZERO:
		view_size = get_viewport_rect().size
	var painted: Array = marks(view_size)
	_painted = hash(painted)
	for mark_v in painted:
		var mark: Dictionary = mark_v as Dictionary
		var alpha: float = float(mark["alpha"])
		match String(mark["what"]):
			"wash":
				var wash: Color = mark["ink"] as Color
				wash.a = alpha
				draw_rect(Rect2(Vector2.ZERO, view_size), wash)
			"keycap":
				var at: Vector2 = mark["at"] as Vector2
				var cap: Vector2 = Vector2(_keycap_w(font, String(mark["text"])), _keycap_h())
				var fall: Color = INK_SHADOW
				fall.a = 0.40 * alpha
				draw_rect(Rect2(at + Vector2(1.0, 2.0), cap), fall)
				Chrome.keycap(self, at, String(mark["text"]), BODY_SIZE, alpha)
			_:
				_say(font, mark["at"] as Vector2, String(mark["text"]), mark["ink"] as Color, alpha)


# One sentence: its soft shadow, then its ink.
func _say(font: Font, at: Vector2, text: String, ink: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var shade: Color = INK_SHADOW
	for tap in SHADOW_TAPS:
		shade.a = float((tap as Array)[1]) * alpha
		draw_string(font, at + ((tap as Array)[0] as Vector2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, shade)
	var col: Color = ink
	col.a = alpha
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, col)


static func _ink_of(kind: int) -> Color:
	if kind == Kind.HARM:
		return INK_HARM
	if kind == Kind.HELD:
		return INK_PROMPT
	return INK


static func _rest_of(kind: int) -> float:
	match kind:
		Kind.HARM:
			return REST_HARM
		Kind.NEED:
			return REST_NEED
		Kind.STEADY:
			return REST_STEADY
	return REST_SAID


# How strongly a sentence stands `age` seconds after it arrived: up over ARRIVE_S, full for FRESH_S, then
# eased to its Kind's rest over RECEDE_S. With motion reduced it steps: full, then its rest.
static func _row_alpha(kind: int, age: float, still: bool) -> float:
	var rest: float = _rest_of(kind)
	if age >= FRESH_S + RECEDE_S:
		return rest
	if age >= FRESH_S:
		return rest if still else lerpf(1.0, rest, smoothstep(0.0, 1.0, (age - FRESH_S) / RECEDE_S))
	return _arrival(age, still)


static func _arrival(age: float, still: bool) -> float:
	if still or age >= ARRIVE_S:
		return 1.0
	return clampf(age / ARRIVE_S, 0.0, 1.0)


# The key strip's strength: full while it is called for (the first KEYS_SHOW_S of this screen, and for as
# long as the pointer is free or the world is held, then KEYS_SHOW_S more), then gone over KEYS_FADE_S.
func _keys_alpha(still: bool) -> float:
	var age: float = _clock - _keys_called
	if age <= KEYS_SHOW_S:
		return 1.0
	if still or age >= KEYS_SHOW_S + KEYS_FADE_S:
		return KEYS_REST_ALPHA
	return lerpf(1.0, KEYS_REST_ALPHA, smoothstep(0.0, 1.0, (age - KEYS_SHOW_S) / KEYS_FADE_S))


# The key a prompt opens with, or "" when it opens with none.
static func _prompt_key(text: String) -> String:
	for key in PROMPT_KEYS:
		if text.begins_with(key + " "):
			return key
	return ""


static func _text_w(font: Font, text: String) -> float:
	return ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x)


# A keycap's box, by `Chrome.keycap`'s own arithmetic: the label, the cap's rim and four pixels a side, never
# narrower than it is tall.
static func _keycap_h() -> float:
	return maxf(Chrome.KEYCAP_MIN, float(BODY_SIZE) + 8.0)


static func _keycap_w(font: Font, label: String) -> float:
	var rim: Array[int] = Kit.margins("keycap")
	var pad: float = float(rim[0]) + 4.0 if not rim.is_empty() else 9.0
	return roundf(maxf(_keycap_h(), _text_w(font, label) + pad * 2.0))


# Where a word's baseline sits beside a keycap whose top is at zero: the keycap's own label line.
static func _keycap_base() -> float:
	return floorf((_keycap_h() - Chrome.line_height(BODY_SIZE)) / 2.0 + Chrome.ascent(BODY_SIZE))


## The over screen: the shell's danger panel and heading, the chronicle's epitaph, and the one
## action. Nothing numeric, and no bar -- the same words contract as the rest of this HUD.
func _draw_run_over(font: Font) -> void:
	var view_size: Vector2 = size
	if view_size == Vector2.ZERO:
		view_size = get_viewport_rect().size
	var dim: Color = Chrome.FIELD
	dim.a = 0.88
	draw_rect(Rect2(Vector2.ZERO, view_size), dim)
	var panel_h: float = Chrome.HEADER_H + END_PAD * 2.0 + float(_end_lines.size()) * END_LINE_H + 58.0
	var panel: Rect2 = Rect2(((view_size - Vector2(END_PANEL_W, panel_h)) * 0.5).round(), Vector2(END_PANEL_W, panel_h))
	if not Chrome.frame(self, panel, "panel_danger", 0.98):
		var fill: Color = Chrome.PANEL
		fill.a = 0.98
		draw_rect(panel, fill)
		draw_rect(panel, Chrome.DANGER, false, 1.5)
	Chrome.header(self, panel, RUN_OVER_HEADING, 0.98, "warning")
	var y: float = panel.position.y + Chrome.HEADER_H + END_PAD + 24.0
	for line in _end_lines:
		draw_string(font, Vector2(panel.position.x + END_PAD, y), line, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - END_PAD * 2.0, BODY_SIZE, Chrome.TEXT)
		y += END_LINE_H
	draw_string(font, Vector2(panel.position.x + END_PAD, y + 22.0), RUN_OVER_ACTION, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)


# The key strip: the keycaps that name the keys, one short row along the top of the view from the left
# margin. It stands clear of the bare hands, which rest in the lower part of the view (the first-person
# gate's HANDS lane projects them at 1280x720 and 960x720 and holds this rectangle off them), and clear
# of the held weapon at every window size, which the strip under the middle of the view was not. One
# rectangle, by the same arithmetic `marks` lays the strip out with; the WORDS lane compares the two.
static func help_rect(_view_size: Vector2) -> Rect2:
	if _strip_w < 0.0:
		var font: Font = Chrome.font()
		var x: float = 0.0
		for i in KEY_STRIP.size():
			var pair: Array = KEY_STRIP[i] as Array
			x += _keycap_w(font, String(pair[0])) + KEY_WORD_GAP + _text_w(font, String(pair[1]))
			if i < KEY_STRIP.size() - 1:
				x += KEY_PAIR_GAP
		_strip_w = x
	return Rect2(MARGIN, KEYS_TOP, _strip_w, _keycap_h())


## True when `text` contains a decimal digit, the same test the top-down HUD gate makes.
static func has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false

extends SceneTree
# Variance: every dead body is an individual.
#
# Every zombie of a kind used to be the same body -- same colour, same head, same torso, same
# legs -- so a street of twenty shamblers was one shambler drawn twenty times. `SimRoster.roll_look`
# rolls three things per body off its own `zombieLook` stream: a tint from the type's
# `variance.tints`, a size in [1 - variance.body, 1 + variance.body] applied to `body` *and*
# `bodyMax`, and with probability `variance.crawlers` a body whose legs are already gone.
#
# Six lanes, each with a true positive and a true negative, and each run red on purpose before it
# was trusted (the sabotage that did it is named on each):
#
#   DISTINCT  twenty bodies of one kind carry at least two tints and at least two torso maxima;
#             the same twenty against a tree whose `variance` is all zeros carry exactly one of
#             each. Red by deleting the `variance` block from the shipped tree.
#   STATE     a body scaled up and a body scaled down both read Unhurt from
#             `SimHealth.part_state_of`, which is the one normaliser (CLAUDE.md's trap: the parts
#             do not share a scale). Its own negative is built in the lane -- the same shrunken
#             integrity against the *authored* maxima reads Hurt -- so the lane is shown to be
#             capable of noticing before it is believed. Red by scaling `body` and not `bodyMax` --
#             but only after the lane learned to pick its two bodies off the *integrity*: the
#             first version picked them off `bodyMax` and so went quiet, "no scaled body to
#             judge", against exactly the bug it exists for.
#   CRAWLER   a body rolled with legs 0 covers `crawlFactor` of an intact control's ground over
#             the same window, so the roll reaches the locomotion rather than merely writing a
#             zero into a dictionary. Red twice, once per half: by leaving the legs alone in
#             `spawn_zombie`, and by making `SimShambler._speed_of` skip the crawl multiplier,
#             which took the ratio to 1.000 with the zero still written.
#   STREAM    `SimBoot.playable(20260805, 64)`'s `placement` stream ends the boot on the number
#             the tree printed before any of this was written, and `zombieLook` exists and has
#             moved. This is the slice's balance claim: no campaign that already exists is
#             re-rolled by adding, or later retuning, any of this. Red by handing `roll_look` the
#             rng `spawn_zombie` was called with.
#   READER    `Appearance.for_entity` answers the stored tint for a body carrying one and the
#             content block's tint for one that does not -- plus the socket question, that
#             `main.gd::_draw_entities` actually reads the component and hands the value over.
#             Red twice: by deleting the stored-tint branch in `appearance.gd`, and by dropping
#             the `tint` key from the draw item `_draw_entities` assembles.
#   SAVE      the tints and the scaled maxima survive a round trip through the real save *text*,
#             each body getting its own back. Red by skipping `zombieType` in
#             `ComponentStore.restore`. Dropping the tint at spawn instead makes this lane SKIP
#             rather than fail -- correctly, since there is then nothing to have lost -- and
#             DISTINCT is what refuses that.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRngStream = preload("res://sim/rng_stream.gd")
const SimSave = preload("res://sim/save.gd")
const Appearance = preload("res://presentation/appearance.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const HEX: String = "^#[0-9a-f]{6}$"

# The kind every lane below spawns. The shambler is the one that is on the table from day 1 and
# the one 80 draws in 100 are, so it is the body the player actually sees a street of.
const KIND: String = SimRoster.TYPE_SHAMBLER

# Enough bodies that "at least two tints" is a statement about the roll rather than about luck:
# with the shipped five-entry palette, twenty bodies coming back one colour is a 5 x (1/5)^20
# event. If the palette ever shrinks to one entry the lane says so and skips instead.
const SAMPLE: int = 20

# --- the STREAM pin --------------------------------------------------------------------------
# Captured by a throwaway driver on the tree as it stood *before* this slice, which is the only
# moment the number could be captured honestly. It is the state of the `placement` stream at the
# end of `SimBoot.playable(20260805, 64)` -- after the dormant pass, after the outdoor scatter --
# so it moves if any draw is added to, removed from or reordered inside that boot.
const PIN_SEED: int = 20260805
const PIN_TILES: int = 64
const PIN_PLACEMENT: int = 3003379315


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _distinct() and ok
	ok = _state() and ok
	ok = _crawler() and ok
	ok = _stream() and ok
	ok = _reader() and ok
	ok = _save() and ok
	if ok:
		print("M2_VARIANCE_OK distinct tints and sizes, scaled bodies read Unhurt, crawlers reach crawlFactor, placement pinned, the rolled tint reaches the draw loop, and all of it survives a save")
		quit(0)
	else:
		push_error("M2_VARIANCE_FAIL")
		quit(1)


# --- fixtures --------------------------------------------------------------------------------

func _fixture(seed_val: int, tree: Variant = null) -> Dictionary:
	var f: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	if tree is Dictionary:
		f["content_tree"] = tree
	return f


# A world with just enough registered to move a body: health, the shambler brain, and a player
# for it to want. `SimShambler.register_module(w, null)` is the no-field form check_m2_contact.gd
# uses for exactly this reason -- these lanes measure a speed, not a stimulus.
func _world(seed_val: int, tree: Variant = null) -> Variant:
	var w: Variant = World.new(_fixture(seed_val, tree))
	SimHealth.register_module(w)
	SimShambler.register_module(w, null)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	return w


# The shipped content tree with `variance` replaced on every zombie entry. `_tree_with_weights`
# in check_m2_roster.gd is the precedent; the difference is that this writes the block onto every
# kind rather than a named one, because `extends` merges dictionaries key by key and a base left
# alone would seep back into a child that declares only half of one.
#
# `variance` null removes the block entirely, which is the "this kind was never given any" case.
func _tree_with_variance(variance: Variant) -> Dictionary:
	var src: Variant = World.new(_fixture(1))
	var tree: Dictionary = {}
	for path in src.content.keys():
		var entry: Variant = src.content[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")).begins_with("zombie."):
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			if variance == null:
				copy.erase("variance")
			else:
				copy["variance"] = (variance as Dictionary).duplicate(true)
			tree[path] = copy
		else:
			tree[path] = entry
	return tree


func _spawn(w: Variant, x: float, y: float) -> int:
	return SimRoster.spawn_zombie(w, x, y, KIND, w.rng.stream("shambler"))


func _tint_of(w: Variant, ent: int) -> String:
	var zt: Variant = w.components.get_component(ent, "zombieType")
	return String((zt as Dictionary).get("tint", "")) if zt is Dictionary else ""


func _max_of(w: Variant, ent: int, part: String) -> float:
	var m: Variant = w.components.get_component(ent, "bodyMax")
	return float((m as Dictionary).get(part, 0.0)) if m is Dictionary else 0.0


# --- DISTINCT --------------------------------------------------------------------------------

func _distinct() -> bool:
	var w: Variant = _world(4101)
	var tints: Dictionary = {}
	var torsos: Dictionary = {}
	var declared: Array = _declared_tints(w)
	var hex := RegEx.new()
	hex.compile(HEX)
	for i in SAMPLE:
		var ent: int = _spawn(w, 8.0 + float(i) * 0.1, 8.0)
		var t: String = _tint_of(w, ent)
		if t.is_empty():
			push_error("DISTINCT: body %d came back with no tint, and the shipped %s declares %d of them" % [i, KIND, declared.size()])
			return false
		if hex.search(t) == null:
			push_error("DISTINCT: body %d drew tint '%s', which is not #rrggbb lowercase -- the same shape check_appearance.gd holds appearance.tint to" % [i, t])
			return false
		if not declared.has(t):
			push_error("DISTINCT: body %d drew tint '%s', which is not in the kind's own palette %s -- a colour from somewhere other than content" % [i, t, str(declared)])
			return false
		tints[t] = true
		torsos[_max_of(w, ent, "torso")] = true

	if declared.size() < 2:
		print("DISTINCT SKIP the shipped %s declares %d tint(s), so 'at least two colours' has nothing to judge" % [KIND, declared.size()])
	elif tints.size() < 2:
		push_error("DISTINCT: %d bodies drew %d colour(s) out of a palette of %d -- every body of a kind is the same body again" % [SAMPLE, tints.size(), declared.size()])
		return false
	if torsos.size() < 2:
		push_error("DISTINCT: %d bodies came back with %d torso maximum(s); the size roll is not reaching the body" % [SAMPLE, torsos.size()])
		return false

	# The true negative, and the reason it is a *content* fixture rather than a flag: a kind whose
	# variance is all zeros makes no colour draw at all and a size roll that cannot move, so
	# twenty bodies are twenty copies -- which is exactly what every kind was before this landed.
	var flat: Variant = _world(4101, _tree_with_variance({"tints": [], "body": 0.0, "crawlers": 0.0}))
	var flat_tints: Dictionary = {}
	var flat_torsos: Dictionary = {}
	for i in SAMPLE:
		var ent2: int = _spawn(flat, 8.0 + float(i) * 0.1, 8.0)
		flat_tints[_tint_of(flat, ent2)] = true
		flat_torsos[_max_of(flat, ent2, "torso")] = true
	if flat_tints.size() != 1 or not flat_tints.has(""):
		push_error("DISTINCT: an all-zero variance still produced %s -- the tints are coming from somewhere other than the block" % str(flat_tints.keys()))
		return false
	if flat_torsos.size() != 1:
		push_error("DISTINCT: an all-zero variance produced %d torso maxima %s -- `body: 0` is not zero spread" % [flat_torsos.size(), str(flat_torsos.keys())])
		return false

	print("DISTINCT OK %d bodies: %d of %d palette colours, %d torso maxima; the all-zero fixture gives 1 and 1" % [
		SAMPLE, tints.size(), declared.size(), torsos.size(),
	])
	return true


func _declared_tints(w: Variant) -> Array:
	var entry: Variant = SimRoster.content_entry(w, KIND)
	if not (entry is Dictionary):
		return []
	var v: Variant = (entry as Dictionary).get("variance")
	if not (v is Dictionary):
		return []
	var t: Variant = (v as Dictionary).get("tints")
	return (t as Array) if t is Array else []


# --- STATE -----------------------------------------------------------------------------------
#
# The lane that catches scaling `body` without `bodyMax`. `HURT_BELOW` is 1.0, so *any* integrity
# under its maximum is Hurt: a body shrunk to 0.85 and judged against the authored 60 is Hurt from
# the tick it spawns, and everything that reads a torso state -- the speed multiplier, the NPC
# break-off, the condition prose -- would have believed it.
func _state() -> bool:
	var w: Variant = _world(7311)
	var authored: Dictionary = {}
	var entry: Variant = SimRoster.content_entry(w, KIND)
	if entry is Dictionary and (entry as Dictionary).get("body") is Dictionary:
		authored = ((entry as Dictionary)["body"] as Dictionary).duplicate()
	if authored.is_empty():
		print("STATE SKIP %s declares no body block, so there is no authored size to have scaled" % KIND)
		return true

	# Picked off the *integrity*, never off `bodyMax`: `bodyMax` is half of what this lane is here
	# to judge, and a search that used it would go quiet -- "no scaled body to judge" -- against
	# exactly the bug of scaling one and not the other. Measured: it did, before this line said
	# `body`.
	var big: int = -1
	var small: int = -1
	for i in 60:
		var ent: int = _spawn(w, 8.0 + float(i) * 0.1, 20.0)
		var fresh: Dictionary = w.components.get_component(ent, "body") as Dictionary
		# A rolled crawler is not a fresh body: its legs read Unusable on purpose, and this lane
		# asserts every part of a *whole* body is Unhurt. One in twenty arrives that way, so
		# skipping them here is what keeps the lane measuring the size roll rather than failing
		# on the crawler roll one run in a handful. CRAWLER is where the legs are judged.
		if float(fresh.get("legs", 1.0)) <= 0.0:
			continue
		var torso: float = float(fresh.get("torso", 0.0))
		if torso > float(authored["torso"]) and big < 0:
			big = ent
		elif torso < float(authored["torso"]) and small < 0:
			small = ent
		if big >= 0 and small >= 0:
			break
	if big < 0 or small < 0:
		print("STATE SKIP 60 bodies produced no %s one, so there is no scaled body to judge" % ("larger" if big < 0 else "smaller"))
		return true

	for ent in [big, small]:
		for part in authored.keys():
			var state: Variant = SimHealth.part_state_of(w, int(ent), String(part))
			if state == null:
				push_error("STATE: a fresh body's %s has no state at all" % String(part))
				return false
			if int(state) != int(SimHealth.PartState.Unhurt):
				push_error("STATE: a fresh body's %s reads %d, not Unhurt -- its %.0f is being judged against something other than its own %.0f" % [
					String(part), int(state), float((w.components.get_component(int(ent), "body") as Dictionary)[part]), _max_of(w, int(ent), String(part)),
				])
				return false

	# The lane's own true negative: the shrunken body's integrity against the *authored* maxima,
	# which is precisely the bug of scaling one and not the other. If this reads Unhurt the
	# assertion above proves nothing, whatever it says.
	var probe: int = int(w.entities.spawn())
	var shrunk: Dictionary = (w.components.get_component(small, "body") as Dictionary).duplicate()
	w.components.set_component(probe, "body", shrunk)
	w.components.set_component(probe, "bodyMax", authored.duplicate())
	var probe_state: Variant = SimHealth.part_state_of(w, probe, "torso")
	if probe_state == null or int(probe_state) == int(SimHealth.PartState.Unhurt):
		push_error("STATE: a torso of %.0f judged against the authored %.0f still read Unhurt -- this lane cannot see the bug it exists for" % [
			float(shrunk["torso"]), float(authored["torso"]),
		])
		return false

	print("STATE OK big torso %.0f/%.0f and small torso %.0f/%.0f both Unhurt; the small one against the authored %.0f reads %d" % [
		float((w.components.get_component(big, "body") as Dictionary)["torso"]), _max_of(w, big, "torso"),
		float(shrunk["torso"]), _max_of(w, small, "torso"), float(authored["torso"]), int(probe_state),
	])
	return true


# --- CRAWLER ---------------------------------------------------------------------------------
#
# Measured on ground covered rather than on the number written into the dictionary, because the
# number is the easy half: `crawlFactor` sat on the component unread for a whole milestone, and a
# crawler roll that wrote a zero nothing steered by would be the twelfth dead socket rather than a
# feature. check_m2_contact.gd's CRIPPLE lane is the precedent and this is the same measurement
# with the legs arriving from a content roll instead of from a bullet.
func _crawler() -> bool:
	const RUN_TICKS: int = 20
	var covered: Array = []
	var legs_gone: bool = false
	var legs_max: float = 0.0
	var legs_state: Variant = null
	for crawlers in [1.0, 0.0]:
		var w: Variant = _world(9500, _tree_with_variance({"tints": [], "body": 0.0, "crawlers": float(crawlers)}))
		var zed: int = _spawn(w, 19.5, 16.5)
		var sd: Dictionary = w.components.get_component(zed, "shambler") as Dictionary
		# Pursue explicitly, and no grabbing: this measures a speed, and a hold would pin both
		# bodies and measure the grab instead.
		sd["state"] = SimShambler.ShamblerState["Pursue"]
		sd["canGrab"] = false
		var body: Dictionary = w.components.get_component(zed, "body") as Dictionary
		if crawlers > 0.5:
			legs_gone = float(body.get("legs", -1.0)) == 0.0
			legs_max = _max_of(w, zed, "legs")
			legs_state = SimHealth.part_state_of(w, zed, "legs")
		elif float(body.get("legs", 0.0)) <= 0.0:
			push_error("CRAWLER: the control was born legless at `crawlers: 0` -- the roll is not reading the number")
			return false
		var from: Dictionary = (w.components.get_component(zed, "position") as Dictionary).duplicate()
		for _i in RUN_TICKS:
			w.step()
		var now: Dictionary = w.components.get_component(zed, "position") as Dictionary
		covered.append(sqrt(pow(float(now["x"]) - float(from["x"]), 2.0) + pow(float(now["y"]) - float(from["y"]), 2.0)))

	if not legs_gone:
		push_error("CRAWLER: `crawlers: 1.0` produced a body with its legs intact")
		return false
	# The maxima are what make the zero mean "destroyed" rather than "never had any": a legs
	# maximum of zero would make `part_state_of` answer null and every reader shrug.
	if legs_max <= 0.0 or legs_state == null or int(legs_state) != int(SimHealth.PartState.Unusable):
		push_error("CRAWLER: a crawler's legs read state %s against a maximum of %.0f; a born crawler must be Unusable against a real maximum, the way a shot-out pair is" % [str(legs_state), legs_max])
		return false

	var crawled: float = float(covered[0])
	var walked: float = float(covered[1])
	if walked <= 0.001:
		push_error("CRAWLER: the intact control never moved, so there is no speed to compare against")
		return false
	if crawled <= 0.001:
		push_error("CRAWLER: a born crawler stopped dead -- crawlFactor is a fraction of a speed, not a halt")
		return false
	var ratio: float = crawled / walked
	var want: float = float(SimShambler.DEFAULT_LOCOMOTION["crawl"])
	var declared: Variant = SimRoster.content_entry(_world(1), KIND)
	if declared is Dictionary and (declared as Dictionary).get("locomotion") is Dictionary:
		var loco: Dictionary = (declared as Dictionary)["locomotion"] as Dictionary
		if loco.has("crawl"):
			want = float(loco["crawl"])
	if absf(ratio - want) > 0.05:
		push_error("CRAWLER: a born crawler covered %.3f of the control's ground over %d ticks, expected crawlFactor %.2f -- the rolled zero is not reaching SimShambler._speed_of" % [ratio, RUN_TICKS, want])
		return false
	print("CRAWLER OK born legless: %.3f m against the intact control's %.3f m over %d ticks, a ratio of %.3f against crawlFactor %.2f; legs Unusable against a maximum of %.0f" % [
		crawled, walked, RUN_TICKS, ratio, want, legs_max,
	])
	return true


# --- STREAM ----------------------------------------------------------------------------------
#
# The slice's balance claim, and the reason `zombieLook` exists at all. `spawn_zombie` is handed
# `placement` at boot and `director` at night; three draws a body threaded into either would have
# shifted every roll after them, which is every wanderer's tile, every night packet and every kind
# drawn for the rest of the campaign. The pin is the number the tree printed before a line of this
# was written, so there is nothing circular about it.
func _stream() -> bool:
	var boot: Dictionary = SimBoot.playable(PIN_SEED, PIN_TILES)
	var w: Variant = boot["world"]
	var streams: Dictionary = w.rng.save() as Dictionary
	if not streams.has("placement"):
		push_error("STREAM: the boot created no `placement` stream, so there is nothing to compare")
		return false
	var placement: int = int(streams["placement"])
	if placement != PIN_PLACEMENT:
		push_error("STREAM: seed %d at %d tiles ends its boot with placement at %d, pinned at %d -- something is drawing from the stream that places the district, and every campaign that already exists has moved" % [
			PIN_SEED, PIN_TILES, placement, PIN_PLACEMENT,
		])
		return false

	# The other half, and the one that keeps the pin from passing against a slice that was simply
	# deleted: the look stream has to exist and to have moved off its derived seed.
	if not streams.has(SimRoster.LOOK_STREAM):
		push_error("STREAM: nothing ever drew from `%s`, so the pin above is passing against a boot that rolls no looks at all" % SimRoster.LOOK_STREAM)
		return false
	var look: int = int(streams[SimRoster.LOOK_STREAM])
	var virgin: int = SimRngStream.derive_seed(int(w.rng.master_seed), SimRoster.LOOK_STREAM)
	if look == virgin:
		push_error("STREAM: `%s` is still sitting on its derived seed %d -- the stream was named but never drawn from" % [SimRoster.LOOK_STREAM, virgin])
		return false
	var bodies: int = w.components.query(["zombieType"]).size()
	print("STREAM OK seed %d at %d tiles: placement %d unchanged from the pin, %s moved %d -> %d over %d bodies" % [
		PIN_SEED, PIN_TILES, placement, SimRoster.LOOK_STREAM, virgin, look, bodies,
	])
	return true


# --- READER ----------------------------------------------------------------------------------
#
# A colour stored on a component and read by nothing is the eleven-times-paid mistake of this
# milestone, so this asks both halves: the resolver prefers a stored tint, and the draw loop is
# what hands it one.
func _reader() -> bool:
	# A fixture kind that declares a block tint of its own, so "the stored one wins" and "the
	# block's is what a body without one gets" are two answers to the same question rather than
	# one answer and an absence. The shipped kinds declare a sprite and no tint.
	const BLOCK_TINT: String = "#123456"
	const STORED_TINT: String = "#abcdef"
	var tree: Dictionary = _tree_with_variance(null)
	for path in tree.keys():
		var entry: Variant = tree[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == KIND:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			copy["appearance"] = {"tint": BLOCK_TINT}
			tree[path] = copy
	var w: Variant = World.new(_fixture(5150, tree))

	var bare: Dictionary = Appearance.for_entity(w, {"ztype": KIND, "zed": true})
	if (bare["tint"] as Color) != Color(BLOCK_TINT):
		push_error("READER: a body carrying no rolled tint drew %s, not its kind's declared %s" % [str(bare["tint"]), BLOCK_TINT])
		return false
	var rolled: Dictionary = Appearance.for_entity(w, {"ztype": KIND, "zed": true, "tint": STORED_TINT})
	if (rolled["tint"] as Color) != Color(STORED_TINT):
		push_error("READER: a body carrying the rolled tint %s drew %s -- the stored colour is not preferred to the block's" % [STORED_TINT, str(rolled["tint"])])
		return false
	# An empty string is what every body of a kind with no palette carries, and it must fall all
	# the way through rather than resolving to black.
	var empty: Dictionary = Appearance.for_entity(w, {"ztype": KIND, "zed": true, "tint": ""})
	if (empty["tint"] as Color) != Color(BLOCK_TINT):
		push_error("READER: an empty rolled tint drew %s instead of falling through to the block's %s" % [str(empty["tint"]), BLOCK_TINT])
		return false

	# The socket: main.gd has to read the component and put the value in the draw item, or every
	# assertion above is about a function nothing calls with a tint.
	var loop: String = _function_body(MAIN_GD, "_draw_entities")
	if loop.is_empty():
		push_error("READER: main.gd::_draw_entities could not be read, so the socket question has nothing to judge")
		return false
	if not loop.contains("\"zombieType\")"):
		push_error("READER: main.gd::_draw_entities no longer reads the `zombieType` component -- follow the read to where it went rather than dropping this needle")
		return false
	var append_line: String = ""
	for line in loop.split("\n"):
		if String(line).strip_edges().begins_with("items.append("):
			append_line = String(line)
			break
	if append_line.is_empty():
		push_error("READER: main.gd::_draw_entities builds no `items.append(` line any more; find where the draw item is assembled and point this at it")
		return false
	if not append_line.contains("\"tint\""):
		push_error("READER: the draw item main.gd::_draw_entities assembles carries no `tint` key, so Appearance.for_entity can never see a rolled colour:\n  %s" % append_line.strip_edges())
		return false

	print("READER OK stored %s wins over the block's %s, an empty one falls through, and _draw_entities hands the key over" % [STORED_TINT, BLOCK_TINT])
	return true


# --- SAVE ------------------------------------------------------------------------------------

func _save() -> bool:
	var w: Variant = _world(2604)
	var ids: Array[int] = []
	for i in 8:
		ids.append(_spawn(w, 8.0 + float(i) * 0.1, 12.0))
	var before_tints: Dictionary = {}
	var before_torsos: Dictionary = {}
	for ent in ids:
		before_tints[ent] = _tint_of(w, int(ent))
		before_torsos[ent] = _max_of(w, int(ent), "torso")
	var distinct: Dictionary = {}
	for ent in ids:
		distinct[before_tints[ent]] = true
	if distinct.size() < 2:
		print("SAVE SKIP the eight bodies drew %d colour(s), so 'each body got its own back' has nothing to judge" % distinct.size())
		return true

	# Through the real save *text*, not `snapshot()` straight into `restore()`: the component
	# store's in-memory round trip hands back the same objects, so it would carry a value JSON
	# cannot represent and say nothing. Two of CLAUDE.md's traps live on this crossing -- the
	# integer keys a Dictionary loses and the value that is quietly not what you stored -- and
	# neither is reachable without encoding.
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save(text)
	if decoded.has("__error"):
		push_error("SAVE: the save did not decode: %s" % str(decoded))
		return false
	var w2: Variant = _world(2604)
	SimSave.apply_save(w2, decoded)
	var snap: Dictionary = decoded["snapshot"] as Dictionary
	for ent in ids:
		var after: String = _tint_of(w2, int(ent))
		if after != String(before_tints[ent]):
			push_error("SAVE: body %d saved tint '%s' and came back '%s'" % [int(ent), String(before_tints[ent]), after])
			return false
		var torso: float = _max_of(w2, int(ent), "torso")
		if not is_equal_approx(torso, float(before_torsos[ent])):
			push_error("SAVE: body %d saved a torso maximum of %.2f and came back with %.2f" % [int(ent), float(before_torsos[ent]), torso])
			return false
	print("SAVE OK v%d: 8 bodies, %d distinct tints and their scaled maxima, each back on its own body" % [
		int(snap["version"]), distinct.size(),
	])
	return true


# --- helpers ---------------------------------------------------------------------------------

# check_weather.gd's reader, copied rather than shared: a gate that reaches into another gate for
# its scanner is a gate that goes red when the other one is edited.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
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

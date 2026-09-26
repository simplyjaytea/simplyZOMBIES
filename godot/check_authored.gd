extends SceneTree
# Art this project did not generate, held to the spec it was commissioned against.
#
# The owner's call of 2026-09-09 (docs/30, "Art we did not generate") was that proper sprites are
# **commissioned to this project's own spec** rather than bought as a pack. That answer is what
# makes this gate small: the artist comes to our geometry, so there is nothing to adapt and only
# something to check. `godot/assets/sprites/authored.json` declares the tier and
# `tools/sprites/build.py` proves each declared key is present at the canvas it claims; this gate
# is the half that needs decoded pixels and the numbers GDScript already carries.
#
# The owner's call of 2026-09-17 (docs/30, "The outpost pack, adopted") opened a second door into
# the same tier: an entry may now declare a `source` under `godot/art/simplyzombies/` that
# `build.py` reproduces (crop, then pad, never repainted), or a `members` family sharing one
# canvas across several such sources. A pack key is still `kind`, `canvas` and `reads`, still
# judged by MANIFEST, TIER and READS exactly as a commissioned one is, and by
# SPEC/INTERIOR/TONES/HIGHLIGHT only when `kind` is `"rig"`. What changed below is a new lane,
# SOURCE, and what `reads` is allowed to name -- see both in the five lanes just below.
#
# **The bounds below are held against the eight generated rigs too, and that is the point.** A
# spec measured only against art that does not exist yet is a spec nobody can be held to; a spec
# the shipped roster already satisfies is one an artist can be handed. If a bound here ever goes
# red on a generated rig, the rig and the spec have drifted apart and one of them is wrong --
# which is a thing worth being told, and today is exactly how `assets/sprites/README.md`'s prose
# is kept true.
#
# Measured off the committed PNGs on 2026-09-09, which is where every number below comes from:
#
#   rig                 shoulders   head   height   clearance   outline
#   player_body                20     12       28           6   every edge pixel
#   survivor_mara              20     12       28           5   every edge pixel
#   survivor_ellis             22     12       28           5   every edge pixel
#   survivor_colonist          20     12       28           6   every edge pixel
#   raider_body                20     12       28           6   every edge pixel
#   zombie_shambler            20     12       27           5   every edge pixel
#   zombie_screamer            16     12       29           8   every edge pixel
#   zombie_bloater             26     10       25           3   every edge pixel
#
# Shoulders and head are read at the **published skeleton rows** rather than guessed from the
# silhouette: the widest row of a body is not its shoulders (an outstretched arm is wider) and
# the widest row above the middle is not its head (it is the shoulders). `SHOULDER_Y` and
# `HEAD_CY` say where to look, so what is measured is the thing the bound is about.
#
# Five lanes, each with a true positive and a true negative, because a gate that cannot fail is
# worse than no gate:
#
#   MANIFEST  authored.json parses and every entry is well formed -- a two-integer canvas, a
#             known kind, a non-empty `reads`, and, where present, a well-shaped `source`
#             (a `path` that exists, `crop`/`pad` each four integers), `members` (a Dictionary of
#             `^[a-z0-9_.]+$` keys each carrying a sound `source`), `anchor` ([x, y]) and
#             `palette` (`"generator"` or `"pack"`). `Appearance.canvas_of` answers the declared
#             canvas for a declared key. TN: seven fabricated entries, each malformed one way,
#             each refused by the same predicate the real ones go through.
#   TIER      no declared key collides with a rule `canvas_of` already places. The other half of
#             this -- that no declared key is also in the Python registry -- is build.py's, which
#             is the only side that can see a registry. TN: a fabricated declaration of
#             `player_body`.
#   SOURCE    every sourced key or family member resolves a texture at the canvas its entry
#             declares. The pixel-for-pixel proof that the file matches what the source
#             reproduces is `sprites:check`'s (`tools/sprites/build.py --check`), which runs
#             outside this chain; this lane is the half a Godot process can prove on its own. TN:
#             a fabricated source whose path does not exist.
#   SPEC      the bounds above, on decoded pixels, for every generated rig AND every authored key
#             of kind `rig`. TN: six fabrications off a real rig, each breaking exactly one bound,
#             each refused by its own code rather than by "something went wrong".
#   READS     the dead-socket lane: every authored key is named by some content entry's
#             appearance block, and `reads` names one of the ids that actually does -- since
#             2026-09-17 it need not be the *only* one, so two bases sharing an icon can each
#             claim it (the old last-writer-wins comparison was a latent bug this never shipped a
#             fixture for). Art nothing draws is the shape this milestone has paid for twelve
#             times. Says so and SKIPS when the tier is empty, which it is until the first
#             commissioned sprite lands.
#
# What this gate deliberately does NOT do, named so the next session does not think it was
# missed: it does not put an authored rig into `Appearance.PAWN_KEYS`. One key belongs to one
# tier -- the TIER lane below is what refuses a key that is in both -- so the roster the other
# gates judge is the UNION of that array and the manifest's `rig` keys, never the array alone.
# That widening landed with the first commissioned body on 2026-09-11:
# `Appearance.authored_rig_keys()` is the one reader, `check_topdown.gd`'s FLIP lane iterates the
# union, and `check_worn.gd` splits its count into a pinned eight generated plus one per declared
# rig. Its FITS envelope -- the union of the rigs' opaque boxes, which every equipment overlay is
# measured inside -- was the one that could have gone weaker silently, since every body added to
# a union only makes "is this overlay inside it" easier to answer yes; it now asserts that the
# commissioned rigs do not widen it at all, so layering staying a requirement of any art we take
# (the owner's call of 2026-09-09) is mechanical rather than remembered.

const Appearance = preload("res://presentation/appearance.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const AUTHORED_PATH: String = "res://assets/sprites/authored.json"

# `pack_rig`/`pack_overlay`/`module`/`sheet`/`prop` are the outpost pack's later slices'
# placeholders (docs/30, "The outpost pack, adopted"): accepted here, judged by no shape lane
# yet, one gains a lane when the slice that reads it lands.
#
# `vehicle` is a parked car's east-west picture from the pack (docs/23, "The cars are the pack's,
# east-west"), and the first of the pack's kinds to land with its shape lane: check_wrecks.gd's
# PACK lane holds its painted span to the class's `lEw` and its crop to the pack's anchor row.
const KINDS: Array[String] = ["rig", "overlay", "tile", "pack_rig", "pack_overlay", "module", "sheet", "prop", "vehicle"]

# A member key inside a `members` family, and a sourced entry's own key -- both are a
# `godot/assets/sprites/<key>.png` basename, so both share the pattern `check_appearance.gd`'s
# own KEY constant already uses for a content-declared sprite string.
const KEY_FORMAT: String = "^[a-z0-9_.]+$"

# The four-tone model (docs/30, "The decoupled paperdoll", decision 5). `tools/sprites` writes
# the manifest beside the art; this gate is the half that judges the pixels against it.
const TONES_PATH: String = "res://assets/sprites/tones.json"

# The most distinct colours a rig may carry. Measured off the committed PNGs on 2026-09-12,
# after the four-tone pass landed: 13 (player), 16 (mara), 20 (ellis), 5 (colonist), 13
# (raider), 5 (shambler), 9 (screamer), 5 (bloater). Ellis is the rig at the wall -- four
# materials plus a beard -- and the cap is his count exactly, the same arrangement the shoulder
# bound takes with the bloater: a bound the shipped roster already sits on, so it cannot have
# been set by guessing. Before the pass the same eight carried 27 to 88.
const TONE_CAP: int = 20

# The share of a body the highlight tone may cover, from the supplied spec's "<= 10% area".
# `Canvas.tone_pass` spends it as a ceiling rather than an exact count, so the measured shares
# land just under: 7.9% to 9.6% across the eight.
const HIGHLIGHT_MAX: float = 0.10

# The published skeleton rows this gate reads, in pixels above the soles -- a hand-written copy of
# `tools/sprites/parts/characters.py`'s, for the reason `check_worn.gd` carries its own: GDScript
# cannot import a Python module, and a measurement against these rows has to name them. If the
# generator's rows move, this moves with them.
const SKEL_SHOULDER_Y: int = -14
const SKEL_HEAD_CY: int = -21

# The bounds, from the table above. `HEIGHT_MIN` is 25 and not 26 because the bloater is 25: its
# head is sunk two rows on purpose (`BLOATER_HEAD_SINK`), and a bound that excluded the shipped
# roster would be a bound that had never been run.
const HEIGHT_MIN: int = 25
const HEIGHT_MAX: int = 30
const SHOULDER_MAX: int = 26
const SHOULDER_MAX_NARROW: int = 22
const HEAD_MAX: int = 13
const CLEARANCE_MIN: int = 3
const OUTLINE: Color = Color("#161614")

# The one rig allowed the family's outer bound, and the reason nothing else may come near it:
# it sits exactly on 26 with exactly 3 px of clearance, so it is the rig at the wall.
const BROAD_RIGS: Array[String] = ["zombie_bloater"]

const GENERATED_RIGS: Array[String] = [
	"player_body", "survivor_mara", "survivor_ellis", "survivor_colonist",
	"raider_body", "zombie_shambler", "zombie_screamer", "zombie_bloater",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_manifest_is_well_formed() and ok
	ok = _no_key_is_in_both_tiers() and ok
	ok = _every_source_resolves_at_its_declared_canvas() and ok
	ok = _every_rig_meets_the_published_bounds() and ok
	ok = _no_rig_draws_ink_inside_its_silhouette() and ok
	ok = _every_rig_is_four_tones_a_material() and ok
	ok = _no_highlight_covers_more_than_its_share() and ok
	ok = _authored_art_is_read_by_something() and ok
	if ok:
		print("AUTHORED_OK the manifest is well formed, no key is in two tiers, every sourced key resolves at its declared canvas, every rig meets the published bounds, no rig draws ink inside its silhouette, every rig is four tones a material, no highlight covers more than its share, and authored art is read by something")
		quit(0)
	else:
		push_error("AUTHORED_FAIL")
		quit(1)


# --- the manifest --------------------------------------------------------------------------

func _entries() -> Dictionary:
	if not FileAccess.file_exists(AUTHORED_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_PATH))
	if not (parsed is Dictionary):
		return {}
	var keys: Variant = (parsed as Dictionary).get("keys")
	return keys as Dictionary if keys is Dictionary else {}


# Whether an optional `source` block is well formed: a `path` that resolves under res://, and
# `crop`/`pad` each exactly four numbers when present. Shape only -- whether the file at `path`
# actually reproduces the committed PNG is decoded pixels, which is SOURCE's job below (and
# `sprites:check`'s beyond this chain), not this predicate's.
func _complaint_about_source(source_v: Variant) -> String:
	if not (source_v is Dictionary):
		return "declares a `source` that is not an object"
	var source: Dictionary = source_v as Dictionary
	var path: String = String(source.get("path", "")).strip_edges()
	if path.is_empty():
		return "declares a `source` with no `path`"
	if not FileAccess.file_exists("res://%s" % path):
		return "declares a `source.path` of '%s', which does not exist" % path
	for field in ["crop", "pad"]:
		if not source.has(field):
			continue
		var arr: Variant = source[field]
		if not (arr is Array and (arr as Array).size() == 4):
			return "declares `%s` %s; it is four integers" % [field, str(arr)]
		for v in (arr as Array):
			if not (v is float or v is int):
				return "declares `%s` %s; it is four integers" % [field, str(arr)]
	return ""


# Whether one declaration is well formed, as one predicate so the loop below and the negatives
# that prove it cannot drift apart. Returns the complaint, or "" when the entry is sound. It does
# not take the key: the caller names that in its own error, which keeps this a pure judgement on
# one entry and lets the fabricated negatives be entries rather than entries-plus-a-name.
func _complaint(entry_v: Variant) -> String:
	if not (entry_v is Dictionary):
		return "is not an object"
	var entry: Dictionary = entry_v as Dictionary
	var canvas: Variant = entry.get("canvas")
	if not (canvas is Array and (canvas as Array).size() == 2):
		return "declares canvas %s; it is [width, height]" % str(canvas)
	for v in (canvas as Array):
		if not (v is float or v is int) or int(v) <= 0:
			return "declares canvas %s; both are positive whole numbers of pixels" % str(canvas)
	var kind: String = String(entry.get("kind", ""))
	if not KINDS.has(kind):
		return "declares kind '%s'; it is one of %s" % [kind, ", ".join(KINDS)]
	if String(entry.get("reads", "")).strip_edges().is_empty():
		return "names no `reads`; art nothing draws is a dead socket, so say what draws it"
	if entry.has("source"):
		var source_complaint: String = _complaint_about_source(entry.get("source"))
		if not source_complaint.is_empty():
			return source_complaint
	if entry.has("members"):
		var members_v: Variant = entry.get("members")
		if not (members_v is Dictionary):
			return "declares `members` that is not an object"
		var members: Dictionary = members_v as Dictionary
		if members.is_empty():
			return "declares `members` with nothing in it"
		var key_format := RegEx.new()
		key_format.compile(KEY_FORMAT)
		for member_key in members.keys():
			if key_format.search(String(member_key)) == null:
				return "declares a member key '%s' that is not %s" % [String(member_key), KEY_FORMAT]
			var member_v: Variant = members[member_key]
			if not (member_v is Dictionary) or not (member_v as Dictionary).has("source"):
				return "declares member '%s' with no `source`" % String(member_key)
			var member_complaint: String = _complaint_about_source((member_v as Dictionary).get("source"))
			if not member_complaint.is_empty():
				return "declares member '%s' whose source %s" % [String(member_key), member_complaint]
	if entry.has("anchor"):
		var anchor_v: Variant = entry.get("anchor")
		if not (anchor_v is Array and (anchor_v as Array).size() == 2):
			return "declares anchor %s; it is [x, y] in pixels" % str(anchor_v)
		for v in (anchor_v as Array):
			if not (v is float or v is int):
				return "declares anchor %s; both are whole numbers of pixels" % str(anchor_v)
	if entry.has("palette"):
		var palette: String = String(entry.get("palette", ""))
		if not ["generator", "pack"].has(palette):
			return "declares palette '%s'; it is 'generator' or 'pack'" % palette
	return ""


func _the_manifest_is_well_formed() -> bool:
	if not FileAccess.file_exists(AUTHORED_PATH):
		push_error("%s is missing; the authored tier is declared there, and an absent file is a tier nothing can be added to" % AUTHORED_PATH)
		return false
	if JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_PATH)) == null:
		push_error("%s does not parse as JSON" % AUTHORED_PATH)
		return false

	var entries: Dictionary = _entries()
	for key in entries.keys():
		var complaint: String = _complaint(entries[key])
		if not complaint.is_empty():
			push_error("authored.json: '%s' %s" % [String(key), complaint])
			return false
		# The renderer has to agree with the declaration, or the file says one thing and the
		# blit rect another -- which is a picture that stretches without ever erroring.
		var declared: Array = (entries[key] as Dictionary)["canvas"] as Array
		var want: Vector2i = Vector2i(int(declared[0]), int(declared[1]))
		if Appearance.canvas_of(String(key)) != want:
			push_error("authored.json: '%s' declares %dx%d and Appearance.canvas_of answers %s" % [String(key), want.x, want.y, str(Appearance.canvas_of(String(key)))])
			return false

	# TN: seven malformed entries, each wrong one way, each refused by the same predicate the real
	# ones went through. A lane whose negatives are checked by a second copy of the rule proves
	# the copy, not the rule. The real crate PNG is the "exists" fixture for the source cases --
	# proving a bad source is refused starting from a path that resolves, not from a name that was
	# always going to fail.
	var real_source_path: String = "art/simplyzombies/groups/props/native/prop-wood-crate-closed.png"
	var fabricated: Array = [
		["no_canvas", {"kind": "rig", "reads": "x"}],
		["short_canvas", {"canvas": [32], "kind": "rig", "reads": "x"}],
		["bad_kind", {"canvas": [32, 40], "kind": "sprite", "reads": "x"}],
		["no_reads", {"canvas": [32, 40], "kind": "rig"}],
		["missing_source", {"canvas": [32, 32], "kind": "tile", "reads": "x",
			"source": {"path": "art/simplyzombies/groups/props/native/does-not-exist.png"}}],
		["short_crop", {"canvas": [32, 32], "kind": "tile", "reads": "x",
			"source": {"path": real_source_path, "crop": [0, 0, 32]}}],
		["member_no_source", {"canvas": [32, 32], "kind": "pack_rig", "reads": "x",
			"members": {"m": {}}}],
	]
	for pair in fabricated:
		if _complaint((pair as Array)[1]).is_empty():
			push_error("the manifest predicate accepted a fabricated entry '%s'; it proves nothing" % str((pair as Array)[0]))
			return false
	if not _complaint({"canvas": [32, 40], "kind": "rig", "reads": "survivor.unique.x"}).is_empty():
		push_error("the manifest predicate refused a sound fabricated entry; it would refuse real art too")
		return false
	if not _complaint({"canvas": [32, 32], "kind": "tile", "reads": "x",
			"source": {"path": real_source_path}}).is_empty():
		push_error("the manifest predicate refused a sound source entry; it would refuse real pack art too")
		return false
	if not _complaint({"canvas": [32, 32], "kind": "pack_rig", "reads": "x",
			"members": {"m": {"source": {"path": real_source_path}}}}).is_empty():
		push_error("the manifest predicate refused a sound family entry; it would refuse real pack art too")
		return false

	# `Appearance.authored_rig_keys()` is the renderer-side reader three gates share, and it reads
	# `kind` out of this same file. Two readers that must produce the same answer is the
	# cross-check this lane already runs on the canvas; since 2026-09-11 `kind` is read on both
	# sides too, so it gets the same treatment rather than being trusted because it is nearby.
	var rigs_here: Array[String] = []
	for key in entries.keys():
		if String((entries[key] as Dictionary).get("kind", "")) == "rig":
			rigs_here.append(String(key))
	rigs_here.sort()
	if Appearance.authored_rig_keys() != rigs_here:
		push_error("authored.json declares rigs %s and Appearance.authored_rig_keys() answers %s" % [str(rigs_here), str(Appearance.authored_rig_keys())])
		return false

	print("MANIFEST OK %d authored keys declared (%d of kind rig, agreed by both readers), seven malformed fabrications refused and three sound ones (a rig, a source, a family) accepted" % [entries.size(), rigs_here.size()])
	return true


# --- the tiers -----------------------------------------------------------------------------

# Whether `canvas_of`'s own rules already place a key. This is the GDScript half of "a key is in
# one tier"; the other half -- that a declared key is not also in the Python registry -- is
# build.py's, because only that side can see a registry.
func _rule_places(key: String) -> bool:
	if key.begins_with("chart_"):
		return true
	if key == Appearance.GROUND_ATLAS_KEY:
		return true
	if Appearance.PAWN_KEYS.has(key) or Appearance.TREE_KEYS.has(key):
		return true
	return Appearance.vehicle_canvas(key) != Vector2i.ZERO


func _no_key_is_in_both_tiers() -> bool:
	for key in _entries().keys():
		if _rule_places(String(key)):
			push_error("authored.json declares '%s', which canvas_of already places by rule: one key, one tier" % String(key))
			return false
	# TN, both ways: a generated key must be seen as rule-placed, and a plausible authored one
	# must not -- otherwise the predicate answers the same thing for everything.
	if not _rule_places("player_body"):
		push_error("the tier predicate does not see player_body as rule-placed; a zero above would prove nothing")
		return false
	if _rule_places("survivor_commissioned"):
		push_error("the tier predicate sees an undeclared key as rule-placed; it would refuse every authored key")
		return false
	print("TIER OK no declared key collides with a rule, and the predicate separates a generated key from an authored one")
	return true


# --- the source tier -------------------------------------------------------------------------

# Every `source` as `{key: Dictionary}`, flattened over families exactly the way
# `Appearance._read_authored` flattens `members`: a family's own key is never a file, so only its
# members contribute here, each keyed by its own member name.
func _sources() -> Dictionary:
	var out: Dictionary = {}
	for key in _entries().keys():
		var entry: Dictionary = _entries()[key] as Dictionary
		if entry.has("source"):
			out[String(key)] = entry["source"]
		var members_v: Variant = entry.get("members")
		if members_v is Dictionary:
			for member_key in (members_v as Dictionary).keys():
				var member_v: Variant = (members_v as Dictionary)[member_key]
				if member_v is Dictionary and (member_v as Dictionary).has("source"):
					out[String(member_key)] = (member_v as Dictionary)["source"]
	return out


# SOURCE: every sourced key or family member resolves a texture, and it is the canvas its entry
# declares. The pixel-for-pixel proof that the committed file is what the source actually
# reproduces belongs to `sprites:check` (`tools/sprites/build.py --check`), which runs outside
# this chain (CLAUDE.md's verifying section) and reads Pillow, not Godot; this lane is the half a
# Godot process can prove without it. SKIPS, loudly, the way READS does, while nothing is sourced
# yet -- which was true until the two containers adopted the outpost pack's crate art.
func _every_source_resolves_at_its_declared_canvas() -> bool:
	var sources: Dictionary = _sources()
	if sources.is_empty():
		print("SOURCE SKIPPED no authored key declares a `source` yet")
		return true
	var judged: int = 0
	for key in sources.keys():
		var complaint: String = _complaint_about_source(sources[key])
		if not complaint.is_empty():
			push_error("authored.json: '%s' %s" % [String(key), complaint])
			return false
		var canvas: Vector2i = Appearance.canvas_of(String(key))
		var image: Image = _image_of(String(key))
		if image == null:
			push_error("%s does not resolve; the source lane had nothing to judge" % String(key))
			return false
		if Vector2i(image.get_width(), image.get_height()) != canvas:
			push_error("%s is %dx%d; authored.json declares %s and its source is supposed to reproduce exactly that (sprites:check proves the pixels match)" % [String(key), image.get_width(), image.get_height(), str(canvas)])
			return false
		judged += 1

	# TN: a source whose path does not exist is refused by the same predicate the real entries
	# went through.
	if _complaint_about_source({"path": "art/simplyzombies/groups/props/native/does-not-exist.png"}).is_empty():
		push_error("the source predicate accepted a path that does not exist; it proves nothing")
		return false

	print("SOURCE OK %d sourced keys resolve at their declared canvas (the pixel-for-pixel proof is sprites:check's, outside this chain)" % judged)
	return true


# --- the published bounds ------------------------------------------------------------------

func _row_of(above_soles: int, h: int) -> int:
	return h - 1 + above_soles


# Every bound one rig breaks, as codes, so a negative can name which one it meant. One predicate
# for the shipped rigs and the commissioned ones both: a spec applied to only one of them is a
# spec that has not been run.
func _bounds_broken(image: Image, narrow: bool) -> Array[String]:
	var out: Array[String] = []
	var w: int = image.get_width()
	var h: int = image.get_height()

	var first: int = -1
	var last: int = -1
	var left: int = w
	var right: int = -1
	for y in range(h):
		for x in range(w):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			if first < 0:
				first = y
			last = y
			left = mini(left, x)
			right = maxi(right, x)
	if first < 0:
		out.append("empty")
		return out

	var height: int = last - first + 1
	if height < HEIGHT_MIN or height > HEIGHT_MAX:
		out.append("height")
	if mini(left, w - 1 - right) < CLEARANCE_MIN:
		out.append("clearance")

	# The soles are the anchor: `Appearance.anchor_of` stands a non-square canvas on its bottom
	# row and `FOOT_DROP_PX` hangs the contact shadow off the same number, so a body drawn one row
	# short floats without anything erroring.
	var soles: bool = false
	for x in range(w):
		if image.get_pixel(x, h - 1).a > 0.0:
			soles = true
			break
	if not soles:
		out.append("soles")

	var shoulder_row: int = _row_of(SKEL_SHOULDER_Y, h)
	var head_row: int = _row_of(SKEL_HEAD_CY, h)
	if shoulder_row >= 0 and shoulder_row < h:
		var run: int = 0
		for x in range(w):
			if image.get_pixel(x, shoulder_row).a > 0.0:
				run += 1
		if run > (SHOULDER_MAX_NARROW if narrow else SHOULDER_MAX):
			out.append("shoulders")
	if head_row >= 0 and head_row < h:
		var head: int = 0
		for x in range(w):
			if image.get_pixel(x, head_row).a > 0.0:
				head += 1
		if head > HEAD_MAX:
			out.append("head")

	# The 1 px inward outline every standing thing takes. Read as: an opaque pixel with a
	# transparent or off-canvas neighbour is an edge pixel, and every edge pixel is OUTLINE.
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(h):
		for x in range(w):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var edge: bool = false
			for o in offsets:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or image.get_pixel(nx, ny).a <= 0.0:
					edge = true
					break
			if edge and not image.get_pixel(x, y).is_equal_approx(OUTLINE):
				out.append("outline")
				return out
	return out


func _image_of(key: String) -> Image:
	var texture: Texture2D = Appearance.resolve(key)
	return null if texture == null else texture.get_image()


func _every_rig_meets_the_published_bounds() -> bool:
	var judged: int = 0
	for key in GENERATED_RIGS:
		var image: Image = _image_of(key)
		if image == null:
			push_error("%s does not resolve; the bounds had nothing to judge" % key)
			return false
		var broken: Array[String] = _bounds_broken(image, not BROAD_RIGS.has(key))
		if not broken.is_empty():
			push_error("%s breaks the published bounds: %s (assets/sprites/README.md)" % [key, ", ".join(broken)])
			return false
		judged += 1

	var declared: Dictionary = _entries()
	for key in declared.keys():
		var entry: Dictionary = declared[key] as Dictionary
		if String(entry.get("kind", "")) != "rig":
			continue
		var art: Image = _image_of(String(key))
		if art == null:
			push_error("authored.json declares rig '%s' and no file resolves" % String(key))
			return false
		var wrong: Array[String] = _bounds_broken(art, not BROAD_RIGS.has(String(key)))
		if not wrong.is_empty():
			push_error("commissioned rig '%s' breaks the published bounds: %s (assets/sprites/README.md)" % [String(key), ", ".join(wrong)])
			return false
		judged += 1

	# TN: six fabrications off a real rig, each breaking exactly one bound, each refused by its
	# own code. Proved on the shipped art rather than on a drawn blank, so the fabrication starts
	# from something that passes -- a negative built from nothing proves the emptiness, not the
	# bound.
	var base: Image = _image_of("player_body")
	if base == null:
		push_error("player_body does not resolve; the negatives cannot be fabricated")
		return false
	var w: int = base.get_width()
	var h: int = base.get_height()
	var cases: Array = [
		["height", func(im: Image) -> void: im.set_pixel(w / 2, 0, OUTLINE)],
		["clearance", func(im: Image) -> void: im.set_pixel(0, h / 2, OUTLINE)],
		["soles", func(im: Image) -> void:
			for x in range(w):
				im.set_pixel(x, h - 1, Color(0, 0, 0, 0))],
		["shoulders", func(im: Image) -> void:
			for x in range(w):
				im.set_pixel(x, _row_of(SKEL_SHOULDER_Y, h), OUTLINE)],
		["head", func(im: Image) -> void:
			for x in range(w):
				im.set_pixel(x, _row_of(SKEL_HEAD_CY, h), OUTLINE)],
		["outline", func(im: Image) -> void:
			# The sole line is opaque and on the canvas edge, so it is an edge pixel by
			# construction: recolouring one is the smallest possible outline break.
			for x in range(w):
				if im.get_pixel(x, h - 1).a > 0.0:
					im.set_pixel(x, h - 1, Color(1.0, 0.0, 1.0))
					return],
	]
	for case in cases:
		var code: String = String((case as Array)[0])
		var spoil: Callable = (case as Array)[1] as Callable
		var copy: Image = base.duplicate() as Image
		spoil.call(copy)
		if not _bounds_broken(copy, true).has(code):
			push_error("a rig fabricated to break '%s' passed that bound; the assertion proves nothing" % code)
			return false
	if not _bounds_broken(base, true).is_empty():
		push_error("the unmodified player rig broke a bound; the fabrications above start from something that already fails")
		return false

	print("SPEC OK %d rigs inside height %d-%d, shoulders <= %d (%d narrow), head <= %d, clearance >= %d, soles on the bottom row, every edge pixel OUTLINE; six fabrications each refused by their own bound" % [judged, HEIGHT_MIN, HEIGHT_MAX, SHOULDER_MAX, SHOULDER_MAX_NARROW, HEAD_MAX, CLEARANCE_MIN])
	return true


# --- the four-tone lanes ---------------------------------------------------------------------

# Every rig this gate judges: the generated eight plus every commissioned body. One helper so the
# three lanes below cannot drift from each other about what the roster is.
func _rigs_to_judge() -> Array[String]:
	var out: Array[String] = GENERATED_RIGS.duplicate()
	var declared: Dictionary = _entries()
	for key in declared.keys():
		if String((declared[key] as Dictionary).get("kind", "")) == "rig":
			out.append(String(key))
	return out


# Whether an opaque pixel has four opaque neighbours -- i.e. is strictly inside the silhouette
# rather than on its edge. The inverse of the predicate the SPEC lane's outline rule uses, and
# deliberately written as its own function so the two cannot disagree about what "inside" means.
func _is_interior(image: Image, x: int, y: int) -> bool:
	if image.get_pixel(x, y).a <= 0.0:
		return false
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + o.x
		var ny: int = y + o.y
		if nx < 0 or ny < 0 or nx >= image.get_width() or ny >= image.get_height():
			return false
		if image.get_pixel(nx, ny).a <= 0.0:
			return false
	return true


func _interior_ink(image: Image) -> int:
	var count: int = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if _is_interior(image, x, y) and image.get_pixel(x, y).is_equal_approx(OUTLINE):
				count += 1
	return count


# INTERIOR: the spec's "no dark lines inside the silhouette", made mechanical.
#
# The rule it enforces is narrow and worth stating exactly, because the wide reading would be
# wrong: it does not ban dark pixels inside a body -- an eye is dark and must be. It bans
# `OUTLINE` inside a body. The outline colour is the one colour that says "this is where the
# shape ends", and using it anywhere else is drawing an edge that is not an edge. Six rigs used
# to: an OUTLINE eye on five of them, and on the screamer an OUTLINE seam and mouth as well,
# nineteen pixels of it. They are all a material's deep tone now.
func _no_rig_draws_ink_inside_its_silhouette() -> bool:
	var judged: int = 0
	for key in _rigs_to_judge():
		var image: Image = _image_of(key)
		if image == null:
			push_error("%s does not resolve; the interior rule had nothing to judge" % key)
			return false
		var ink: int = _interior_ink(image)
		if ink > 0:
			push_error("%s draws %d OUTLINE pixel(s) strictly inside its silhouette: the outline colour says where a shape ends, so inside a body it is a line that is not an edge. Paint the detail in the material's deep tone (assets/sprites/README.md)" % [key, ink])
			return false
		judged += 1

	# TN: the same scanner, on a real rig with one interior pixel forced to OUTLINE, must find
	# it. Proved on shipped art rather than on a drawn blank, so the fabrication starts from
	# something that passes -- and proved *before* the zero above is trusted.
	var base: Image = _image_of("player_body")
	if base == null:
		push_error("player_body does not resolve; the interior negative cannot be fabricated")
		return false
	var spoiled: Image = base.duplicate() as Image
	var placed: bool = false
	for y in range(spoiled.get_height()):
		for x in range(spoiled.get_width()):
			if not placed and _is_interior(spoiled, x, y):
				spoiled.set_pixel(x, y, OUTLINE)
				placed = true
	if not placed:
		push_error("no interior pixel exists on player_body to fabricate with; the lane proves nothing")
		return false
	if _interior_ink(spoiled) == 0:
		push_error("a fabricated interior OUTLINE pixel was not found; the interior scanner cannot say no")
		return false

	print("INTERIOR OK %d rigs draw no OUTLINE strictly inside their silhouette; a fabricated interior pixel is refused" % judged)
	return true


func _tones_declared() -> Dictionary:
	if not FileAccess.file_exists(TONES_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TONES_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


func _distinct_opaque(image: Image) -> Dictionary:
	var seen: Dictionary = {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var col: Color = image.get_pixel(x, y)
			if col.a > 0.0:
				seen[col.to_html(false)] = true
	return seen


# TONES: a body is a handful of materials at four steps each, not a gradient.
#
# The number this replaces is the one worth remembering: the same eight rigs carried 27 to 88
# distinct colours when each was shaded by a continuous multiply. A cap is the cheapest possible
# assertion that the tone pass is still running at all -- delete it from the assembler and this
# lane goes red on every rig at once, which is what makes it a gate rather than a comment.
func _every_rig_is_four_tones_a_material() -> bool:
	var judged: int = 0
	var worst: int = 0
	var worst_key: String = ""
	for key in _rigs_to_judge():
		var image: Image = _image_of(key)
		if image == null:
			push_error("%s does not resolve; the tone cap had nothing to judge" % key)
			return false
		var count: int = _distinct_opaque(image).size()
		if count > TONE_CAP:
			push_error("%s carries %d distinct colours against a cap of %d: a rig is a few materials at four tones each, so this is a gradient rather than a palette (docs/30, the decoupled paperdoll)" % [key, count, TONE_CAP])
			return false
		if count > worst:
			worst = count
			worst_key = key
		judged += 1

	# TN: one more colour than the cap must be refused. Fabricated by recolouring interior pixels
	# of a real rig to values nothing else uses, so the negative is a rig that is otherwise sound.
	var base: Image = _image_of("player_body")
	if base == null:
		push_error("player_body does not resolve; the tone negative cannot be fabricated")
		return false
	var over: Image = base.duplicate() as Image
	var added: int = 0
	var want: int = TONE_CAP + 1 - _distinct_opaque(over).size()
	for y in range(over.get_height()):
		for x in range(over.get_width()):
			if added >= want:
				break
			if _is_interior(over, x, y):
				over.set_pixel(x, y, Color(0.01 * float(added + 1), 0.99, 0.5))
				added += 1
	if added < want:
		push_error("could not fabricate a rig over the tone cap; the lane proves nothing")
		return false
	if _distinct_opaque(over).size() <= TONE_CAP:
		push_error("a rig fabricated over the tone cap counted %d, at or under %d; the counter cannot say no" % [_distinct_opaque(over).size(), TONE_CAP])
		return false

	print("TONES OK %d rigs at or under %d distinct colours (worst %s at %d, was 27-88 before the pass); a rig one colour over is refused" % [judged, TONE_CAP, worst_key, worst])
	return true


# The share of a body wearing any material's highlight tone.
func _highlight_share(image: Image, highlights: Dictionary) -> float:
	var opaque: int = 0
	var lit: int = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var col: Color = image.get_pixel(x, y)
			if col.a <= 0.0:
				continue
			opaque += 1
			if highlights.has(col.to_html(false)):
				lit += 1
	return 0.0 if opaque == 0 else float(lit) / float(opaque)


# HIGHLIGHT: the spec's "highlight over at most 10% of the area", both ways.
#
# Both ways matters. A highlight over half a body is the failure the spec names, and the ceiling
# catches it. A highlight over *none* of it is the quieter failure and the one this project has
# seen before: `palette.ramp`'s own notes record top steps clamping together at a family's value
# ceiling, and a material whose highlight equals its base has a highlight nobody can see. The
# floor is what turns that from a picture somebody eventually notices into a red build.
func _no_highlight_covers_more_than_its_share() -> bool:
	var declared: Dictionary = _tones_declared()
	if declared.is_empty():
		push_error("%s is missing or does not parse; it is generated beside the art by tools/sprites and this lane cannot know which colour is a highlight without it" % TONES_PATH)
		return false
	var highlights: Dictionary = {}
	for name in declared.keys():
		var steps: Variant = declared[name]
		if not (steps is Array) or (steps as Array).size() != 4:
			push_error("tones.json: '%s' is %s; a material is four tones, darkest first" % [String(name), str(steps)])
			return false
		highlights[String((steps as Array)[3]).lstrip("#")] = true

	var judged: int = 0
	var worst: float = 0.0
	var worst_key: String = ""
	for key in _rigs_to_judge():
		var image: Image = _image_of(key)
		if image == null:
			push_error("%s does not resolve; the highlight share had nothing to judge" % key)
			return false
		var share: float = _highlight_share(image, highlights)
		if share > HIGHLIGHT_MAX:
			push_error("%s wears a highlight over %.1f%% of its body, past the %.0f%% the spec allows: a highlight that covers a body is the base tone with extra steps" % [key, share * 100.0, HIGHLIGHT_MAX * 100.0])
			return false
		if share <= 0.0:
			push_error("%s wears no highlight at all: either its ramp collapsed at the family ceiling or the tone pass did not run on it, and both are invisible without this line" % key)
			return false
		if share > worst:
			worst = share
			worst_key = key
		judged += 1

	# TN, both bounds, on real art: a rig repainted entirely in one material's highlight must be
	# refused by the ceiling, and the same rig with no highlight at all by the floor.
	var base: Image = _image_of("player_body")
	if base == null:
		push_error("player_body does not resolve; the highlight negatives cannot be fabricated")
		return false
	var lit_key: String = String(highlights.keys()[0])
	var flooded: Image = base.duplicate() as Image
	var blanked: Image = base.duplicate() as Image
	for y in range(base.get_height()):
		for x in range(base.get_width()):
			if base.get_pixel(x, y).a <= 0.0:
				continue
			flooded.set_pixel(x, y, Color(lit_key))
			if highlights.has(base.get_pixel(x, y).to_html(false)):
				blanked.set_pixel(x, y, OUTLINE)
	if _highlight_share(flooded, highlights) <= HIGHLIGHT_MAX:
		push_error("a rig repainted entirely in a highlight measured at or under the ceiling; the share cannot say no")
		return false
	if _highlight_share(blanked, highlights) > 0.0:
		push_error("a rig with every highlight pixel overpainted still measures a highlight; the floor cannot say no")
		return false

	print("HIGHLIGHT OK %d rigs wear a highlight over 0%% and at most %.0f%% of the body (worst %s at %.1f%%); a flooded rig and a highlight-free one are both refused" % [judged, HIGHLIGHT_MAX * 100.0, worst_key, worst * 100.0])
	return true


# --- the dead-socket lane -------------------------------------------------------------------

# `{sprite key: Array[String]}`, every content id whose appearance block declares it -- not the
# last one loaded. Until 2026-09-17 this kept only the most recent id, which is a latent bug
# rather than a rule anyone chose: two bases sharing one icon would have failed the moment the
# second was authored, because the first id it named was silently overwritten.
func _keys_content_declares() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var block: Variant = entry.get("appearance")
			if not (block is Dictionary):
				continue
			for prop in ["sprite", "equipSprite", "equipSpriteFront"]:
				if (block as Dictionary).has(prop):
					_declared_by(out, String((block as Dictionary)[prop]), String(entry.get("id", "?")))
			# A vehicle names its pictures per variant and axis rather than as one `sprite`
			# (vehicle.schema.json), so the pack's east-west cars -- the first authored keys a
			# vehicle declares -- would read as art nothing draws without this. One reader per
			# class however many of its variants share the key: the pack draws one intact car.
			var variants: Variant = (block as Dictionary).get("variants")
			if variants is Array:
				for variant_v in variants as Array:
					if not (variant_v is Dictionary):
						continue
					for axis in ["ns", "ew"]:
						if (variant_v as Dictionary).has(axis):
							_declared_by(out, String((variant_v as Dictionary)[axis]), String(entry.get("id", "?")))
	return out


func _declared_by(out: Dictionary, sprite_key: String, id: String) -> void:
	var readers: Array = out.get(sprite_key, [])
	if not readers.has(id):
		readers.append(id)
	out[sprite_key] = readers


# Whether a claimed `reads` is one of the content ids that actually declare the key -- membership,
# not equality, which is the fix for the last-writer-wins bug `_keys_content_declares` describes.
func _reads_claim_is_sound(readers: Array, claim: String) -> bool:
	return readers.has(claim)


func _authored_art_is_read_by_something() -> bool:
	var entries: Dictionary = _entries()
	var declared: Dictionary = _keys_content_declares()
	if declared.is_empty():
		push_error("no content entry declares any sprite key; the dead-socket lane had nothing to judge")
		return false

	if entries.is_empty():
		# Says so and skips loudly rather than passing quietly on nothing -- the arrangement
		# `check_worn.gd`'s PLAYED lane sets. The tier is empty until the first commissioned
		# sprite lands, and a green line here would otherwise read as "checked".
		print("READS SKIPPED the authored tier is empty, so there is no commissioned art to find a reader for; %d content-declared keys were loaded and the lane is ready for the first one" % declared.size())
		return true

	# `entries.keys()` are authored.json's top-level keys only -- a family's members never appear
	# here, so a family is judged by its family key exactly as a flat entry is, and there is
	# nothing extra to special-case for it.
	for key in entries.keys():
		var name: String = String(key)
		if not declared.has(name):
			push_error("authored.json declares '%s' and no content entry's appearance block names it: art nothing draws" % name)
			return false
		var claims: String = String((entries[key] as Dictionary).get("reads", ""))
		var readers: Array = declared[name] as Array
		if not _reads_claim_is_sound(readers, claims):
			push_error("authored.json says '%s' is read by '%s'; the content entries that actually declare it are %s" % [name, claims, str(readers)])
			return false

	# TN, both shapes: a claim absent from its readers is refused, and a key with two readers
	# accepts either of them -- the second is the fix itself, proved rather than assumed.
	if _reads_claim_is_sound(["a.id"], "b.id"):
		push_error("the reads predicate accepted a claim absent from its readers; it proves nothing")
		return false
	if not _reads_claim_is_sound(["a.id", "b.id"], "a.id"):
		push_error("the reads predicate refused the first of two sound readers; two bases sharing one icon would fail")
		return false

	print("READS OK %d authored keys are each named by one of the content entries that declare them" % entries.size())
	return true

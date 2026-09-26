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
#   player_body                20     12       28           6   every edge pixel   (retired)
#   survivor_mara              20     12       28           5   every edge pixel   (retired)
#   survivor_ellis             22     12       28           5   every edge pixel   (retired)
#   survivor_colonist          20     12       28           6   every edge pixel   (retired)
#   raider_body                20     12       28           6   every edge pixel   (retired)
#   zombie_shambler            20     12       27           5   every edge pixel   (retired)
#   zombie_screamer            16     12       29           8   every edge pixel
#   zombie_bloater             26     10       25           3   every edge pixel
#
# The six marked retired were deleted by "The bodies turn and walk" (2026-09-26), when every human
# and the shambler moved onto the outpost pack's four-direction rigs. Their rows stay because the
# bounds were set by them, and a bound whose evidence is erased is a bound nobody can re-derive.
# The pack rigs are kind `pack_rig`, never judged by SPEC's outline rule or the colour lanes --
# the "geometry gated, colour not" rule docs/30 set -- but PACK below holds their geometry, at a
# named alpha threshold, to the same published height and the same sole row.
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
#   PACK      the outpost pack's families, held to the pack's own manifest: a `pack_rig` has four
#             idle views and the same number of walk frames every way under authored.json's
#             member-name convention, its `fps` is the manifest's `fps.walk`, its crop ends on the
#             manifest's anchor row and drops no pixel at or above ALPHA_SOLID, its idle views
#             stand on the bottom row at the published height and its walk frames within
#             SOLE_LIFT_MAX of it; a `pack_overlay` has four views, its `z` is the manifest's
#             `z_by_direction`, and each view's solid box is exactly the manifest's `fit` for it.
#             TN: a fabrication per claim, each refused by its own predicate, and a sub-visible
#             speck and a one-row step accepted.
#   ICON      every authored key of kind `icon` -- an inventory picture, one item base seen from
#             above -- is a picture (opaque pixels at ICON_ALPHA or more, not only the alpha-6
#             specks the pack leaves inside its canvas), centred on its canvas within
#             ICON_CENTRE_TOLERANCE, clear of the canvas edge, and the size and anchor the pack's
#             own manifest says it is. That the floor and the bag plate then *draw* it is
#             `godot:check:appearance`'s ITEMS lane. TN: five fabrications -- speck-only, a
#             corner-flush picture, a real pixel in a corner, a wrong size, a wrong anchor -- and
#             one control, a centred picture with a speck in the corner, which must pass.
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

# `pack_rig`/`pack_overlay`/`module`/`sheet`/`prop` are the outpost pack's kinds (docs/30, "The
# outpost pack, adopted"). `pack_rig` and `pack_overlay` gained their lane, PACK, with "The bodies
# turn and walk" (2026-09-26); `module`, `sheet` and `prop` are accepted here and judged by no
# shape lane yet, each gaining one when the slice that reads it lands. `icon` is an inventory
# picture, judged by ICON since "A picture per item base" (2026-09-26).
#
# `vehicle` is a parked car's east-west picture from the pack (docs/23, "The cars are the pack's,
# east-west"), and its shape lane lives beside the parking it judges: check_wrecks.gd's PACK lane
# holds its painted span to the class's `lEw` and its crop to the pack's anchor row.
const KINDS: Array[String] = ["rig", "overlay", "tile", "icon", "pack_rig", "pack_overlay", "module", "sheet", "prop", "vehicle"]

# The pack's own spec for the art it ships, read as text and never loaded as a resource (the pack's
# docs/godot/*.tres are null headless -- the UI kit's trap). PACK compares authored.json's copies of
# `fps` and `z` against it, and its `anchor` and `fit` against the crop and the pixels.
const PACK_MANIFEST_PATH: String = "res://art/simplyzombies/manifest.json"
const PACK_ROOT: String = "art/simplyzombies/"

# The alpha at which a pack pixel counts as drawn, as a byte. The pack's walk frames carry
# sub-visible specks (alpha <= 6) out to the canvas edges -- the pickup's measured finding -- so
# "drawn means alpha above zero" would make every box the whole canvas and an envelope that could
# never fail. 128 is half coverage: it refuses a real pixel and accepts a speck, and PACK proves
# both on fabricated pixels before it trusts either.
const ALPHA_SOLID: int = 128

# How many rows a walk frame's sole may lift off the bottom row: a step raises a foot. Measured
# off the pack at ALPHA_SOLID: every idle view stands on row 39, and the highest walk-frame sole
# is row 38 (the survivor walking west, frame 1).
const SOLE_LIFT_MAX: int = 1

# The alpha at which a pixel is part of a picture rather than a speck. The pack's icons carry
# alpha 1-6 specks (8 to 118 of them an icon, measured 2026-09-26) and a bounding box taken at
# "alpha above zero" would treat every one as a real pixel; 128 is the named threshold the pickup
# doc asks any lane judging pack geometry for -- it refuses a real pixel and accepts a speck.
const ICON_ALPHA: int = 128
# How far the opaque box's centre may sit from the canvas centre, in pixels, per axis. Measured
# across the 48 icons: 0 or 1 (an odd-width box on an even canvas), so 2 is the first value a
# corner-flush picture breaks and no shipped icon does.
const ICON_CENTRE_TOLERANCE: int = 2
# Fewest opaque pixels a picture may have. The smallest of the 48 is the bow's 75.
const ICON_MIN_OPAQUE: int = 40

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

const GENERATED_RIGS: Array[String] = ["zombie_screamer", "zombie_bloater"]

# The generated rig every fabricated negative below starts from: a real body that passes, so each
# negative is one broken bound away from shipped art. The player's rig until 2026-09-26; the
# screamer since the player moved onto the pack survivor, because it is narrow (not in
# BROAD_RIGS) and sits inside every bound with room to break each one on its own.
const BASE_RIG: String = "zombie_screamer"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_manifest_is_well_formed() and ok
	ok = _no_key_is_in_both_tiers() and ok
	ok = _every_source_resolves_at_its_declared_canvas() and ok
	ok = _every_icon_is_a_centred_picture() and ok
	ok = _every_rig_meets_the_published_bounds() and ok
	ok = _no_rig_draws_ink_inside_its_silhouette() and ok
	ok = _every_rig_is_four_tones_a_material() and ok
	ok = _no_highlight_covers_more_than_its_share() and ok
	ok = _the_pack_families_keep_the_packs_own_spec() and ok
	ok = _authored_art_is_read_by_something() and ok
	if ok:
		print("AUTHORED_OK the manifest is well formed, no key is in two tiers, every sourced key resolves at its declared canvas, every rig meets the published bounds, no rig draws ink inside its silhouette, every rig is four tones a material, no highlight covers more than its share, the pack families keep the pack's own spec, every icon is a centred picture, and authored art is read by something")
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
	if entry.has("fps"):
		var fps_v: Variant = entry.get("fps")
		if not (fps_v is float or fps_v is int) or int(fps_v) <= 0 or float(fps_v) != float(int(fps_v)):
			return "declares fps %s; it is a positive whole number of frames a second" % str(fps_v)
	if entry.has("z"):
		var z_v: Variant = entry.get("z")
		if not (z_v is Dictionary) or (z_v as Dictionary).is_empty():
			return "declares z %s; it is {view: whole number}" % str(z_v)
		for view in (z_v as Dictionary).keys():
			if not Appearance.VIEWS.has(String(view)):
				return "declares z for view '%s'; the views are %s" % [String(view), str(Appearance.VIEWS)]
			var zv: Variant = (z_v as Dictionary)[view]
			if not (zv is float or zv is int) or float(zv) != float(int(zv)):
				return "declares z %s for view '%s'; it is a whole number" % [str(zv), String(view)]
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
		["zero_fps", {"canvas": [32, 40], "kind": "pack_rig", "reads": "x", "fps": 0}],
		["fractional_fps", {"canvas": [32, 40], "kind": "pack_rig", "reads": "x", "fps": 7.5}],
		["z_bad_view", {"canvas": [32, 40], "kind": "pack_overlay", "reads": "x", "z": {"up": 1}}],
		["z_not_whole", {"canvas": [32, 40], "kind": "pack_overlay", "reads": "x", "z": {"s": 0.5}}],
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
	if not _complaint({"canvas": [32, 40], "kind": "pack_overlay", "reads": "x", "fps": 8,
			"z": {"s": 3, "e": -1, "n": 3, "w": -1}}).is_empty():
		push_error("the manifest predicate refused a sound fps and z; it would refuse the real wearables too")
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

	print("MANIFEST OK %d authored keys declared (%d of kind rig, agreed by both readers), %d malformed fabrications refused and four sound ones (a rig, a source, a family, an fps with a z) accepted" % [entries.size(), rigs_here.size(), fabricated.size()])
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
	if not _rule_places(BASE_RIG):
		push_error("the tier predicate does not see %s as rule-placed; a zero above would prove nothing" % BASE_RIG)
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


# --- the icons ---------------------------------------------------------------------------------

func _opaque_box(image: Image) -> Dictionary:
	var lo := Vector2i(image.get_width(), image.get_height())
	var hi := Vector2i(-1, -1)
	var count: int = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if roundi(image.get_pixel(x, y).a * 255.0) < ICON_ALPHA:
				continue
			count += 1
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return {"count": count, "lo": lo, "hi": hi}


# What is wrong with one icon, as words, or empty when nothing is. `expected_size` and `anchor` are
# the pack's own manifest entry (`occupiedSize`, `anchor`); one predicate so the loop and the
# fabrications that prove it go through the same code.
func _icon_faults(image: Image, expected_size: Vector2i, anchor: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var box: Dictionary = _opaque_box(image)
	if int(box["count"]) < ICON_MIN_OPAQUE:
		out.append("empty: %d pixels at alpha %d or more" % [int(box["count"]), ICON_ALPHA])
		return out
	var lo: Vector2i = box["lo"] as Vector2i
	var hi: Vector2i = box["hi"] as Vector2i
	var w: int = image.get_width()
	var h: int = image.get_height()
	if lo.x <= 0 or lo.y <= 0 or hi.x >= w - 1 or hi.y >= h - 1:
		out.append("touches the canvas edge at %s..%s" % [str(lo), str(hi)])
	var centre_off: Vector2 = Vector2(float(lo.x + hi.x + 1) * 0.5 - float(w) * 0.5, float(lo.y + hi.y + 1) * 0.5 - float(h) * 0.5)
	if absf(centre_off.x) > float(ICON_CENTRE_TOLERANCE) or absf(centre_off.y) > float(ICON_CENTRE_TOLERANCE):
		out.append("off-centre by %s" % str(centre_off))
	var size: Vector2i = hi - lo + Vector2i(1, 1)
	if size != expected_size:
		out.append("occupies %s, the pack's manifest says %s" % [str(size), str(expected_size)])
	if anchor != Vector2i(w / 2, h / 2):
		out.append("the pack anchors it at %s, not its canvas centre" % str(anchor))
	return out


func _pack_asset(asset_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_MANIFEST_PATH))
	if not (parsed is Dictionary):
		return {}
	for asset in (parsed as Dictionary).get("assets", []) as Array:
		if asset is Dictionary and String((asset as Dictionary).get("id", "")) == asset_id:
			return asset as Dictionary
	return {}


# A 32x32 fabrication: `fill` at `alpha`, and optionally one more pixel at `corner_at`.
func _blank_icon(fill: Rect2i, alpha: float, corner_alpha: float = -1.0, corner_at: Vector2i = Vector2i.ZERO) -> Image:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(fill.position.y, fill.end.y):
		for x in range(fill.position.x, fill.end.x):
			image.set_pixel(x, y, Color(0.6, 0.5, 0.3, alpha))
	if corner_alpha >= 0.0:
		image.set_pixel(corner_at.x, corner_at.y, Color(0.6, 0.5, 0.3, corner_alpha))
	return image


func _every_icon_is_a_centred_picture() -> bool:
	var judged: int = 0
	var entries: Dictionary = _entries()
	for key in entries.keys():
		var entry: Dictionary = entries[key] as Dictionary
		if String(entry.get("kind", "")) != "icon":
			continue
		var source: Variant = entry.get("source")
		var image: Image = _image_of(String(key))
		if image == null or not (source is Dictionary):
			push_error("icon '%s' has no picture or no source to judge it against" % String(key))
			return false
		var asset: Dictionary = _pack_asset(String((source as Dictionary).get("path", "")).get_file().get_basename())
		if asset.is_empty():
			push_error("icon '%s': no entry in the pack's manifest for its source, so its size and anchor cannot be judged" % String(key))
			return false
		var occ: Array = asset.get("occupiedSize", []) as Array
		var anc: Array = asset.get("anchor", []) as Array
		if occ.size() != 2 or anc.size() != 2:
			push_error("icon '%s': the pack's manifest entry has no occupiedSize or anchor" % String(key))
			return false
		var faults: Array[String] = _icon_faults(image, Vector2i(int(occ[0]), int(occ[1])), Vector2i(int(anc[0]), int(anc[1])))
		if not faults.is_empty():
			push_error("icon '%s' is not a centred picture: %s" % [String(key), "; ".join(faults)])
			return false
		judged += 1
	if judged == 0:
		print("ICON SKIPPED no authored key is of kind `icon` yet")
		return true

	# The fabrications. A 16x12 block centred on the 32x32 canvas is the control.
	var centred := Rect2i(8, 10, 16, 12)
	var good_size := Vector2i(16, 12)
	var centre := Vector2i(16, 16)
	if not _icon_faults(_blank_icon(centred, 1.0), good_size, centre).is_empty():
		push_error("the icon predicate refused a centred picture; it would refuse the real ones")
		return false
	if not _icon_faults(_blank_icon(centred, 1.0, 6.0 / 255.0, Vector2i(0, 0)), good_size, centre).is_empty():
		push_error("the icon predicate counted an alpha-6 speck as a picture; the pack's icons would all be refused")
		return false
	var refusals: Array = [
		["a speck-only image", _blank_icon(centred, 6.0 / 255.0), good_size, centre],
		["a corner-flush picture", _blank_icon(Rect2i(0, 0, 16, 12), 1.0), good_size, centre],
		["a real pixel in a corner", _blank_icon(centred, 1.0, 1.0, Vector2i(0, 0)), good_size, centre],
		["a size the manifest does not say", _blank_icon(centred, 1.0), Vector2i(20, 12), centre],
		["an anchor off the canvas centre", _blank_icon(centred, 1.0), good_size, Vector2i(16, 24)],
	]
	for row in refusals:
		var r: Array = row as Array
		if _icon_faults(r[1] as Image, r[2] as Vector2i, r[3] as Vector2i).is_empty():
			push_error("the icon predicate accepted %s; it proves nothing" % String(r[0]))
			return false
	print("ICON OK %d icons are pictures above alpha %d, centred within %d px, clear of the edge, at the size and anchor the pack's manifest gives; a speck-only image, a corner-flush picture, a corner pixel, a wrong size and a wrong anchor are each refused, and a speck beside a centred picture is not" % [judged, ICON_ALPHA, ICON_CENTRE_TOLERANCE])
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
	var base: Image = _image_of(BASE_RIG)
	if base == null:
		push_error("%s does not resolve; the negatives cannot be fabricated" % BASE_RIG)
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
		push_error("the unmodified %s broke a bound; the fabrications above start from something that already fails" % BASE_RIG)
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
	var base: Image = _image_of(BASE_RIG)
	if base == null:
		push_error("%s does not resolve; the interior negative cannot be fabricated" % BASE_RIG)
		return false
	var spoiled: Image = base.duplicate() as Image
	var placed: bool = false
	for y in range(spoiled.get_height()):
		for x in range(spoiled.get_width()):
			if not placed and _is_interior(spoiled, x, y):
				spoiled.set_pixel(x, y, OUTLINE)
				placed = true
	if not placed:
		push_error("no interior pixel exists on %s to fabricate with; the lane proves nothing" % BASE_RIG)
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
	var base: Image = _image_of(BASE_RIG)
	if base == null:
		push_error("%s does not resolve; the tone negative cannot be fabricated" % BASE_RIG)
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
	var base: Image = _image_of(BASE_RIG)
	if base == null:
		push_error("%s does not resolve; the highlight negatives cannot be fabricated" % BASE_RIG)
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


# --- the outpost pack's families -------------------------------------------------------------
#
# PACK: "The bodies turn and walk" (docs/23, 2026-09-26) is the first slice that reads a family for
# real, and a family copies three things out of the pack's manifest that the renderer then trusts
# without ever opening the manifest: the walk's frame rate, each wearable's per-view layering, and
# the anchor the crop keeps. A copy is a second statement of a fact, so this lane holds each copy
# to the manifest, and the pixels to both, at ALPHA_SOLID -- never at "alpha above zero", which the
# pack's specks would turn into an envelope that cannot fail.

func _pack_assets() -> Array:
	if not FileAccess.file_exists(PACK_MANIFEST_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_MANIFEST_PATH))
	if not (parsed is Dictionary):
		return []
	var assets: Variant = (parsed as Dictionary).get("assets")
	return assets as Array if assets is Array else []


# The manifest asset a source path was cut from: the one whose `frames` list that file.
func _asset_for_source(assets: Array, source_path: String) -> Dictionary:
	if not source_path.begins_with(PACK_ROOT):
		return {}
	var rel: String = source_path.substr(PACK_ROOT.length())
	for a in assets:
		if not (a is Dictionary):
			continue
		var frames: Variant = (a as Dictionary).get("frames")
		if not (frames is Dictionary):
			continue
		for clip in (frames as Dictionary).values():
			if not (clip is Array):
				continue
			for f in clip as Array:
				if f is Dictionary and String((f as Dictionary).get("path", "")) == rel:
					return a as Dictionary
	return {}


func _is_solid(c: Color) -> bool:
	return roundi(c.a * 255.0) >= ALPHA_SOLID


# The box of pixels at or above ALPHA_SOLID, as {min_x, min_y, max_x, max_y}, or {} for none.
func _solid_box(image: Image) -> Dictionary:
	var box: Dictionary = {}
	for y in image.get_height():
		for x in image.get_width():
			if not _is_solid(image.get_pixel(x, y)):
				continue
			if box.is_empty():
				box = {"min_x": x, "min_y": y, "max_x": x, "max_y": y}
			else:
				box["min_x"] = mini(int(box["min_x"]), x)
				box["min_y"] = mini(int(box["min_y"]), y)
				box["max_x"] = maxi(int(box["max_x"]), x)
				box["max_y"] = maxi(int(box["max_y"]), y)
	return box


# Whether a crop [x, y, w, h] leaves any solid pixel of the source outside it.
func _crop_drops_solid(source: Image, crop: Array) -> bool:
	var x0: int = int(crop[0])
	var y0: int = int(crop[1])
	var x1: int = x0 + int(crop[2])
	var y1: int = y0 + int(crop[3])
	for y in source.get_height():
		for x in source.get_width():
			if x >= x0 and x < x1 and y >= y0 and y < y1:
				continue
			if _is_solid(source.get_pixel(x, y)):
				return true
	return false


# A turning body's members under authored.json's convention: `<key>_<view>` for each of the four
# views, and `<key>_walk_<view>_<n>` for the same n = 0..frames-1 every way, and nothing else.
func _rig_members_complaint(key: String, members: Array) -> String:
	var want: Array[String] = []
	var frames: int = 0
	while members.has("%s_walk_%s_%d" % [key, Appearance.VIEW_REST, frames]):
		frames += 1
	if frames == 0:
		return "has no walk frames under '%s_walk_%s_0'" % [key, Appearance.VIEW_REST]
	for view in Appearance.VIEWS:
		want.append("%s_%s" % [key, view])
		for n in frames:
			want.append("%s_walk_%s_%d" % [key, view, n])
	for w in want:
		if not members.has(w):
			return "is missing member '%s'" % w
	for m in members:
		if not want.has(String(m)):
			return "carries member '%s', which the convention does not name" % String(m)
	return ""


func _overlay_members_complaint(key: String, members: Array) -> String:
	for view in Appearance.VIEWS:
		if not members.has("%s_%s" % [key, view]):
			return "is missing member '%s_%s'" % [key, view]
	if members.size() != Appearance.VIEWS.size():
		return "carries %d members; a wearable is one picture per view" % members.size()
	return ""


# Where a body's feet are, against the published bounds: an idle view stands on the bottom row, a
# walk frame within SOLE_LIFT_MAX of it, and either stands between HEIGHT_MIN and HEIGHT_MAX tall.
func _sole_complaint(box: Dictionary, h: int, idle: bool) -> String:
	if box.is_empty():
		return "draws nothing at or above alpha %d" % ALPHA_SOLID
	var lift: int = h - 1 - int(box["max_y"])
	if idle and lift != 0:
		return "stands %d row(s) off the bottom row; an idle view's soles are the anchor" % lift
	if lift < 0 or lift > SOLE_LIFT_MAX:
		return "lifts its sole %d row(s); a step lifts at most %d" % [lift, SOLE_LIFT_MAX]
	var height: int = int(box["max_y"]) - int(box["min_y"]) + 1
	if height < HEIGHT_MIN or height > HEIGHT_MAX:
		return "is %d px tall, outside %d-%d" % [height, HEIGHT_MIN, HEIGHT_MAX]
	return ""


func _fps_complaint(declared: Variant, asset: Dictionary) -> String:
	var fps: Variant = asset.get("fps")
	if not (fps is Dictionary) or not (fps as Dictionary).has("walk"):
		return "comes from a manifest asset with no fps.walk"
	if int(declared) != int((fps as Dictionary)["walk"]):
		return "declares fps %s where the pack's manifest says %s" % [str(declared), str((fps as Dictionary)["walk"])]
	return ""


func _z_complaint(declared: Variant, asset: Dictionary) -> String:
	var zs: Variant = asset.get("z_by_direction")
	if not (declared is Dictionary) or not (zs is Dictionary):
		return "has no z, or its manifest asset has no z_by_direction"
	for view in Appearance.VIEWS:
		if not (declared as Dictionary).has(view) or not (zs as Dictionary).has(view):
			return "has no z for view '%s'" % view
		if int((declared as Dictionary)[view]) != int((zs as Dictionary)[view]):
			return "declares z %s for view '%s' where the pack's manifest says %s" % [str((declared as Dictionary)[view]), view, str((zs as Dictionary)[view])]
	return ""


# A wearable view's solid box against the manifest's own `fit` for that view: the placement is the
# box's top-left and the occupied size its extent -- where the pack's author fitted it to the idle
# survivor, so a picture that moved by a pixel no longer sits where it was drawn to sit.
func _fit_complaint(box: Dictionary, fit: Variant) -> String:
	if not (fit is Dictionary):
		return "has no manifest fit"
	var at: Array = (fit as Dictionary).get("placement", []) as Array
	var size: Array = (fit as Dictionary).get("occupied_size", []) as Array
	if at.size() != 2 or size.size() != 2 or box.is_empty():
		return "has no box or a malformed fit"
	var got: Array = [int(box["min_x"]), int(box["min_y"]), int(box["max_x"]) - int(box["min_x"]) + 1, int(box["max_y"]) - int(box["min_y"]) + 1]
	var want: Array = [int(at[0]), int(at[1]), int(size[0]), int(size[1])]
	if got != want:
		return "sits at %s (x, y, w, h) where the manifest fits it at %s" % [str(got), str(want)]
	return ""


func _the_pack_families_keep_the_packs_own_spec() -> bool:
	var assets: Array = _pack_assets()
	if assets.is_empty():
		push_error("%s is missing or has no assets; PACK cannot hold a copy to a spec it cannot read" % PACK_MANIFEST_PATH)
		return false
	var entries: Dictionary = _entries()
	var rigs: int = 0
	var overlays: int = 0
	var judged: int = 0
	for key in entries.keys():
		var name: String = String(key)
		var entry: Dictionary = entries[key] as Dictionary
		var kind: String = String(entry.get("kind", ""))
		if kind != "pack_rig" and kind != "pack_overlay":
			continue
		var members_v: Variant = entry.get("members")
		if not (members_v is Dictionary):
			push_error("PACK: '%s' is a %s with no members; a pack body or wearable is a family" % [name, kind])
			return false
		var members: Array = (members_v as Dictionary).keys()
		var complaint: String = _rig_members_complaint(name, members) if kind == "pack_rig" else _overlay_members_complaint(name, members)
		if not complaint.is_empty():
			push_error("PACK: '%s' %s" % [name, complaint])
			return false
		if not Appearance.turns(name):
			push_error("PACK: Appearance.turns('%s') is false; the renderer would draw one picture for every view" % name)
			return false
		var rest: String = "%s_%s" % [name, Appearance.VIEW_REST]
		var rest_path: String = String((((members_v as Dictionary)[rest] as Dictionary)["source"] as Dictionary).get("path", ""))
		var asset: Dictionary = _asset_for_source(assets, rest_path)
		if asset.is_empty():
			push_error("PACK: '%s' is cut from '%s', which no manifest asset lists" % [name, rest_path])
			return false
		var canvas: Array = entry["canvas"] as Array
		var anchor: Array = asset.get("anchor", []) as Array
		if anchor.size() != 2 or int(anchor[1]) != int(canvas[1]):
			push_error("PACK: '%s' is %s tall and its manifest anchor is %s; the crop must end on the anchor row, so the soles stand where FOOT_DROP_PX puts them" % [name, str(canvas[1]), str(anchor)])
			return false
		for m in members:
			var member: String = String(m)
			var source: Dictionary = ((members_v as Dictionary)[m] as Dictionary)["source"] as Dictionary
			var path: String = String(source.get("path", ""))
			if String(_asset_for_source(assets, path).get("id", "")) != String(asset.get("id", "")):
				push_error("PACK: '%s' is cut from '%s', not from the family's own manifest asset '%s'" % [member, path, String(asset.get("id", ""))])
				return false
			var crop: Array = source.get("crop", []) as Array
			if crop != [0, 0, int(canvas[0]), int(canvas[1])] and crop != [0.0, 0.0, float(canvas[0]), float(canvas[1])]:
				push_error("PACK: '%s' crops %s; a pack member is cut [0, 0, %s, %s], the anchor row as its bottom" % [member, str(crop), str(canvas[0]), str(canvas[1])])
				return false
			var original := Image.new()
			if original.load("res://%s" % path) != OK:
				push_error("PACK: '%s' does not load" % path)
				return false
			if _crop_drops_solid(original, crop):
				push_error("PACK: cropping '%s' to %s drops a pixel at or above alpha %d; only the pack's specks may go" % [path, str(crop), ALPHA_SOLID])
				return false
			var image: Image = _image_of(member)
			if image == null:
				push_error("PACK: '%s' does not resolve" % member)
				return false
			var box: Dictionary = _solid_box(image)
			if kind == "pack_rig":
				var sole: String = _sole_complaint(box, image.get_height(), not member.contains("_walk_"))
				if not sole.is_empty():
					push_error("PACK: '%s' %s" % [member, sole])
					return false
			judged += 1
		if kind == "pack_rig":
			var fps_complaint: String = _fps_complaint(entry.get("fps"), asset)
			if not fps_complaint.is_empty():
				push_error("PACK: '%s' %s" % [name, fps_complaint])
				return false
			if Appearance.walk_fps(name) != int(entry.get("fps")):
				push_error("PACK: Appearance.walk_fps('%s') answers %d where authored.json declares %s" % [name, Appearance.walk_fps(name), str(entry.get("fps"))])
				return false
			var walk: Array = ((asset.get("frames", {}) as Dictionary).get("walk_%s" % Appearance.VIEW_REST, []) as Array)
			if Appearance.walk_frames(name) != walk.size():
				push_error("PACK: '%s' walks %d frames and the manifest's walk_%s has %d" % [name, Appearance.walk_frames(name), Appearance.VIEW_REST, walk.size()])
				return false
			rigs += 1
		else:
			var z_complaint: String = _z_complaint(entry.get("z"), asset)
			if not z_complaint.is_empty():
				push_error("PACK: '%s' %s" % [name, z_complaint])
				return false
			for view in Appearance.VIEWS:
				var z: int = int((entry["z"] as Dictionary)[view])
				if Appearance.layer_over(name, view) != (z >= 0):
					push_error("PACK: Appearance.layer_over('%s', '%s') disagrees with z %d" % [name, view, z])
					return false
				var fit: String = _fit_complaint(_solid_box(_image_of("%s_%s" % [name, view])), (asset.get("fit", {}) as Dictionary).get(view))
				if not fit.is_empty():
					push_error("PACK: '%s_%s' %s" % [name, view, fit])
					return false
			overlays += 1
	if rigs == 0 or overlays == 0:
		push_error("PACK judged %d pack rig(s) and %d pack overlay(s); the lane is here for both and had nothing to judge" % [rigs, overlays])
		return false

	# True negatives, one per claim, each through the predicate the real families just passed.
	var speck := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	speck.set_pixel(1, 1, Color8(10, 10, 10, 6))
	if not _solid_box(speck).is_empty():
		push_error("PACK: a speck at alpha 6 counted as solid; every box would reach the canvas edge")
		return false
	speck.set_pixel(2, 2, Color8(10, 10, 10, ALPHA_SOLID))
	if _solid_box(speck).is_empty():
		push_error("PACK: a pixel at alpha %d did not count as solid; the threshold refuses real art" % ALPHA_SOLID)
		return false
	var tall := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	tall.set_pixel(16, 44, Color8(10, 10, 10, 6))
	if _crop_drops_solid(tall, [0, 0, 32, 40]):
		push_error("PACK: a crop dropping only a speck was refused; the pack's specks may go")
		return false
	tall.set_pixel(16, 45, Color8(10, 10, 10, 255))
	if not _crop_drops_solid(tall, [0, 0, 32, 40]):
		push_error("PACK: a crop dropping a solid pixel was accepted; a cropped-off foot would pass")
		return false
	var real: Array = ((entries["body_survivor"] as Dictionary)["members"] as Dictionary).keys() if entries.has("body_survivor") else []
	if real.is_empty():
		push_error("PACK: no body_survivor to fabricate member negatives from")
		return false
	var short: Array = real.duplicate()
	short.erase("body_survivor_walk_n_3")
	var extra: Array = real.duplicate()
	extra.append("body_survivor_run_s_0")
	if _rig_members_complaint("body_survivor", short).is_empty() or _rig_members_complaint("body_survivor", extra).is_empty():
		push_error("PACK: a body missing a walk frame, or carrying one the convention does not name, passed")
		return false
	if _overlay_members_complaint("item_gear_x", ["item_gear_x_s", "item_gear_x_e", "item_gear_x_n"]).is_empty():
		push_error("PACK: a wearable missing its west view passed")
		return false
	if _sole_complaint({"min_x": 8, "min_y": 10, "max_x": 20, "max_y": 37}, 40, true).is_empty():
		push_error("PACK: an idle view standing two rows off the bottom passed; it would float")
		return false
	if not _sole_complaint({"min_x": 8, "min_y": 11, "max_x": 20, "max_y": 38}, 40, false).is_empty():
		push_error("PACK: a walk frame lifting its sole one row was refused; the pack's own step would fail")
		return false
	if _sole_complaint({"min_x": 8, "min_y": 10, "max_x": 20, "max_y": 37}, 40, false).is_empty():
		push_error("PACK: a walk frame lifting its sole two rows passed")
		return false
	if _fps_complaint(8, {"fps": {"walk": 5}}).is_empty() or not _fps_complaint(8, {"fps": {"walk": 8}}).is_empty():
		push_error("PACK: the fps comparison cannot tell 8 from 5, or refuses 8 against 8")
		return false
	if _z_complaint({"s": 3, "e": 1, "n": 3, "w": -1}, {"z_by_direction": {"s": 3, "e": -1, "n": 3, "w": -1}}).is_empty():
		push_error("PACK: a z that drew the backpack over the body seen from the east passed")
		return false
	if _fit_complaint({"min_x": 9, "min_y": 10, "max_x": 24, "max_y": 18}, {"placement": [8, 10], "occupied_size": [16, 9]}).is_empty():
		push_error("PACK: a wearable one pixel off its manifest fit passed")
		return false

	print("PACK OK %d pack rig(s) and %d pack overlay(s), %d members: members complete by convention, fps and z equal the pack manifest's, every crop ends on the anchor row and drops only specks (alpha < %d), idle soles on the bottom row and walk soles within %d, every wearable view exactly on its manifest fit; a fabrication per claim refused, a speck, a one-row step and a matching fps accepted" % [rigs, overlays, judged, ALPHA_SOLID, SOLE_LIFT_MAX])
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

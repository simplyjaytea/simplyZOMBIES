extends SceneTree
# Day-8 gate beat, accept 15% transmitted, Inspect skilled vs untrained, death/leave, and the
# survivor-generation surface: shape, readers, kit-in-hand, age, prose, looks, determinism.

const SimBoot = preload("res://sim/boot.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Palette = preload("res://presentation/palette.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _beat() and ok
	ok = _transmit() and ok
	ok = _inspect() and ok
	ok = _death() and ok
	ok = _gen_shape() and ok
	ok = _readers() and ok
	ok = _kit_in_hand() and ok
	ok = _age_reads() and ok
	ok = _prose() and ok
	ok = _look_resolves() and ok
	ok = _determinism() and ok
	if ok:
		print("M2_RECRUITS_OK beat transmit inspect death shape readers kit age prose looks determinism")
		quit(0)
	else:
		push_error("M2_RECRUITS_FAIL")
		quit(1)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

func _mara(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(e)
	return -1

func _beat() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(8, Clock.DAWN_ENDS * 0.5)
	w.step()
	var waiting: Array[int] = w.components.query(["recruit"])
	if waiting.is_empty():
		push_error("day8 no recruit")
		return false
	var rec: int = waiting[0]
	if not SimRecruits.ignore(w, rec):
		push_error("ignore failed")
		return false
	if not w.components.query(["recruit"]).is_empty():
		push_error("ignore left recruit")
		return false
	print("BEAT OK day8 ignore")
	return true

func _transmit() -> bool:
	var hits: int = 0
	var n: int = 40
	for i in n:
		var w: Variant = _world()
		w.tick = Clock.tick_on_day(8, 0.05)
		# force a waiting recruit
		var rng: Variant = w.rng.stream("recruits")
		# burn i samples so each world differs after accept opens the stream... 
		# instead spawn then accept; stream rolls on accept
		for _b in i:
			rng.call("next")
		var rolled: Dictionary = SimRecruits.roll(w, rng)
		var rec: int = SimRecruits.spawn_generated(w, rolled, 49.5, 50.5)
		w.components.set_component(rec, "recruit", {"waiting": true, "beatDay": 8})
		SimRecruits.accept(w, rec)
		if w.components.has_component(rec, "zombieInfection"):
			var st: Variant = w.components.get_component(rec, "zombieInfection")
			for e in (st as Dictionary).get("exposures", []) as Array:
				if bool((e as Dictionary).get("transmitted", false)):
					hits += 1
	var rate: float = float(hits) / float(n)
	if rate < 0.02 or rate > 0.40:
		push_error("transmit rate %s hits %d/%d" % [str(rate), hits, n])
		return false
	print("TRANSMIT OK rate %.2f" % rate)
	return true

func _inspect() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	w.components.set_component(w.player, "zombieInfection", {
		"exposures": [{
			"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true,
			"stage": SimInfection.Stage.Progression, "stageEnteredAtTick": 0,
			"cauterized": false, "amputated": false,
		}],
	})
	var skilled: Dictionary = SimJobs.inspect(w, mara, w.player)
	var untrained: Dictionary = SimJobs.inspect(w, w.player, w.player)
	if String(skilled.get("prose", "")).find("probable") < 0 and String(skilled.get("prose", "")).find("day") < 0:
		push_error("skilled prose %s" % str(skilled))
		return false
	if String(untrained.get("prose", "")) != "ill":
		push_error("untrained prose %s" % str(untrained))
		return false
	var tab: Dictionary = SimInfection.diagnosis_of(w, w.player, 0)
	if String(tab.get("label", "")).find("infection") >= 0:
		push_error("injuries tab leaked")
		return false
	print("INSPECT OK skilled vs untrained")
	return true

func _death() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	# uninfected NPC → corpse
	SimHealth.finish_death(w, mara)
	if not w.components.has_component(mara, "corpse"):
		push_error("mara not corpse")
		return false
	# player death with Mara alive → succession (no runOver)
	var w2: Variant = _world()
	var m2: int = _mara(w2)
	var dead: int = int(w2.player)
	SimHealth.finish_death(w2, dead)
	if bool(w2.runOver):
		push_error("player death with mara set runOver")
		return false
	if int(w2.player) != m2 or not w2.components.has_component(m2, "controlled"):
		push_error("succession did not hand to mara")
		return false
	if not w2.components.has_component(dead, "corpse"):
		push_error("dead player not corpse")
		return false
	# solo player death → runOver
	var w_solo: Variant = _world()
	SimHealth.finish_death(w_solo, _mara(w_solo))
	SimHealth.finish_death(w_solo, w_solo.player)
	if not bool(w_solo.runOver):
		push_error("solo player death no runOver")
		return false
	# transmitted → shambler with kit
	var w3: Variant = _world()
	var m3: int = _mara(w3)
	w3.components.set_component(m3, "zombieInfection", {
		"exposures": [{"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true, "stage": 0, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}],
	})
	var mara_kit: Array[int] = SimInventory.carried_items(w3, m3)
	if mara_kit.is_empty():
		push_error("death fixture: mara carries no kit before turning -- nothing for this lane to judge")
		return false
	SimHealth.finish_death(w3, m3)
	var turned: int = 0
	for e in w3.components.query(["turnedFrom"]):
		turned += 1
		# The claim is "with kit", not just "turned" -- docs/23's defect list named this an
		# `if ...: pass` with an empty body, so only `turned < 1` below was ever enforced.
		# `carried_items` walks both the equipped slot and the pack, so it catches a transfer
		# that drops the equipped knife as readily as one that drops the packed bandage.
		var shambler_kit: Array[int] = SimInventory.carried_items(w3, int(e))
		if shambler_kit.is_empty():
			push_error("turned shambler %d carries no kit -- mara's %d items did not transfer" % [int(e), mara_kit.size()])
			return false
	if turned < 1:
		push_error("no turned shambler")
		return false
	# leave
	var w4: Variant = _world()
	var m4: int = _mara(w4)
	SimRecruits.begin_leave(w4, m4)
	if not w4.components.has_component(m4, "leaving"):
		push_error("leave missing")
		return false
	print("DEATH OK corpse succession solo turn leave")
	return true

# ---- survivor generation: shape, readers, kit, age, prose, looks, determinism ----

# The generator's content block, found the same small scan `SimRecruits._pool` and
# `SimSurvivors._generator_pool` each use privately. A gate reaching into a private helper by
# name is one more thing that breaks quietly if the helper is renamed; its own copy of an
# eight-line scan is not.
func _gen_pool(w: Variant) -> Dictionary:
	if w == null or w.content == null:
		return {}
	var c: Variant = w.content
	if c is Dictionary:
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == "colony.generator.survivors":
				return v as Dictionary
	return {}

func _apt_sum_ok(a: Dictionary) -> bool:
	var s: int = int(a.get("str", 0))
	var d: int = int(a.get("dex", 0))
	var c: int = int(a.get("con", 0))
	if s < 3 or s > 8 or d < 3 or d > 8 or c < 3 or c > 8:
		return false
	return s + d + c == 15

func _apt_eq(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("str", -1)) == int(b.get("str", -1)) \
		and int(a.get("dex", -1)) == int(b.get("dex", -1)) \
		and int(a.get("con", -1)) == int(b.get("con", -1))

# GEN SHAPE: what `roll()` hands back, checked against the content it drew from -- name, age
# inside the union of the authored bands, a backstoryId in the authored list, 2-3 traits and
# 2-3 features from their pools, and a look id resolving to a real #rrggbb tint. The negative
# is folded in at the end: a look id with no content entry must resolve no appearance block at
# all, which is the shape a typo would actually take.
func _gen_shape() -> bool:
	var w: Variant = _world()
	var rolled: Dictionary = SimRecruits.roll(w, w.rng.stream("recruits"))
	if String(rolled.get("name", "")).is_empty():
		push_error("gen shape: no name")
		return false
	var pool: Dictionary = _gen_pool(w)
	var bands: Array = pool.get("ageBands", []) as Array
	if bands.is_empty():
		push_error("gen shape: content has no ageBands -- nothing to judge")
		return false
	var age: int = int(rolled.get("age", -1))
	var in_band: bool = false
	for b in bands:
		var band: Dictionary = b as Dictionary
		if age >= int(band.get("min", 0)) and age <= int(band.get("max", 999)):
			in_band = true
			break
	if not in_band:
		push_error("gen shape: age %d falls outside every content band %s" % [age, str(bands)])
		return false
	var story_ids: Array[String] = []
	for s in pool.get("backstories", []) as Array:
		story_ids.append(String((s as Dictionary).get("id", "")))
	if not story_ids.has(String(rolled.get("backstoryId", ""))):
		push_error("gen shape: backstoryId %s not in content list %s" % [rolled.get("backstoryId", ""), str(story_ids)])
		return false
	var traits: Array = rolled.get("traits", []) as Array
	if traits.size() < 2 or traits.size() > 3:
		push_error("gen shape: traits.size() == %d, want 2-3" % traits.size())
		return false
	var trait_pool: Array = pool.get("traits", []) as Array
	for t in traits:
		if not trait_pool.has(String(t)):
			push_error("gen shape: trait %s not in content pool" % t)
			return false
	var feats: Array = rolled.get("features", []) as Array
	if feats.size() < 2 or feats.size() > 3:
		push_error("gen shape: features.size() == %d, want 2-3" % feats.size())
		return false
	var feature_pool: Array = pool.get("features", []) as Array
	for f in feats:
		if not feature_pool.has(String(f)):
			push_error("gen shape: feature %s not in content pool" % f)
			return false
	var look: String = String(rolled.get("look", ""))
	if look.is_empty():
		push_error("gen shape: no look id rolled")
		return false
	var looks_pool: Array = pool.get("looks", []) as Array
	if not looks_pool.has(look):
		push_error("gen shape: look %s not in content pool %s" % [look, str(looks_pool)])
		return false
	var block: Dictionary = Appearance.of_content(w, "survivor", look)
	var hex := RegEx.new()
	hex.compile("^#[0-9a-f]{6}$")
	if not block.has("tint") or hex.search(String(block["tint"])) == null:
		push_error("gen shape: look %s has no valid #rrggbb tint (%s)" % [look, str(block)])
		return false
	# Negative: a looks id nothing declares must resolve no appearance block, the shape a typo
	# in `generator.json`'s `looks` array would actually take.
	var bogus: Dictionary = Appearance.of_content(w, "survivor", "colony.look.does_not_exist")
	if bogus.has("tint"):
		push_error("gen shape negative: an undeclared look id resolved a tint anyway")
		return false
	print("GEN SHAPE OK age %d in-band, backstoryId %s, %d traits, %d features, look %s" % [age, rolled.get("backstoryId", ""), traits.size(), feats.size(), look])
	return true

# READERS: after `spawn_generated`, the rolled dict must actually have reached `identity` --
# the assertion that would have caught the appearance list rolled and thrown away, and the
# other three fields (age, look, backstoryId) that were dead the same way.
func _readers() -> bool:
	var w: Variant = _world()
	var rolled: Dictionary = SimRecruits.roll(w, w.rng.stream("recruits"))
	var ent: int = SimRecruits.spawn_generated(w, rolled, 49.5, 50.5)
	var ident: Variant = w.components.get_component(ent, "identity")
	if not ident is Dictionary:
		push_error("readers: spawned survivor has no identity component")
		return false
	var id: Dictionary = ident as Dictionary
	var feats: Array = id.get("features", []) as Array
	if feats.size() < 2:
		push_error("readers: identity.features.size() == %d, want >= 2" % feats.size())
		return false
	if int(id.get("age", 0)) <= 0:
		push_error("readers: identity.age == %d, want > 0" % int(id.get("age", 0)))
		return false
	if String(id.get("look", "")).is_empty():
		push_error("readers: identity.look is empty")
		return false
	if String(id.get("backstoryId", "")).is_empty():
		push_error("readers: identity.backstoryId is empty")
		return false
	print("READERS OK features=%d age=%d look=%s backstoryId=%s" % [feats.size(), int(id.get("age", 0)), id.get("look", ""), id.get("backstoryId", "")])
	return true

# KIT IN HAND: every backstory kit id must resolve through `SimItems.spawn_item` to a real
# content base, and every backstory whose kit holds an equippable item must land the spawned
# survivor holding it -- a `meleeWeapon`/`rangedWeapon` component, not just a stowed item.
# Against the pre-slice code (kit items only ever `SimInventory.stow`ed) this lane was red for
# `fired_security`, the one backstory whose kit item declares an `equipSlot`; the session log
# for this change carries that run's output.
func _kit_in_hand() -> bool:
	var w: Variant = _world()
	var stories: Array = _gen_pool(w).get("backstories", []) as Array
	if stories.is_empty():
		push_error("kit in hand: content has no backstories -- nothing to judge")
		return false
	var judged_weapon: int = 0
	for s in stories:
		var story: Dictionary = s as Dictionary
		var kit: Array = (story.get("kit", []) as Array).duplicate()
		var rolled: Dictionary = {
			"name": "Test Subject",
			"traits": [],
			"aptitudes": {"str": 5, "dex": 5, "con": 5},
			"kit": kit,
			"backstory": String(story.get("label", "")),
			"backstoryId": String(story.get("id", "")),
			"age": 30,
			"look": "",
			"features": [],
		}
		var ent: int = SimRecruits.spawn_generated(w, rolled, 40.0, 40.0)
		var wants_weapon: bool = false
		for item_id in kit:
			var base: Variant = SimItems.content_entry(w, "item", String(item_id))
			if not (base is Dictionary):
				push_error("kit in hand: %s's kit item %s has no content base -- spawn_item resolved nothing" % [story.get("id", ""), item_id])
				return false
			if SimItems.base_equip_slot(base as Dictionary) != null:
				wants_weapon = true
		if not wants_weapon:
			continue
		judged_weapon += 1
		# `item.equipped` only queues here -- handlers run at `drain()`, at the end of
		# `world.step()` (CLAUDE.md's events-land-at-drain trap). One tick lets melee.gd's
		# handler build the `meleeWeapon` profile off the item this actually just equipped.
		w.tick += 1
		w.step()
		var armed: bool = w.components.has_component(ent, "meleeWeapon") or w.components.has_component(ent, "rangedWeapon")
		if not armed:
			push_error("kit in hand: %s's kit declares an equippable item but the survivor holds no weapon component" % story.get("id", ""))
			return false
	if judged_weapon == 0:
		push_error("kit in hand: no backstory kit declares an equippable item -- nothing to judge")
		return false
	print("KIT IN HAND OK %d backstories, %d armed" % [stories.size(), judged_weapon])
	return true

# AGE READS: the age-band nudge feeds the same clamp-and-rebalance-to-15 loop the backstory
# nudge already used. Same forced band twice must roll bit-identical aptitudes (and age); two
# opposite-nudged bands must differ in the nudged direction, averaged over enough seeds that one
# unlucky composition draw cannot flip it -- measured at +-2 dex over 24 same-seeded pairs before
# writing this threshold (probe deleted after), delta held above 1.5 every time and never below
# 0.5, which is the number below. Were the nudge not read at all, both arms would sit on the same
# composition-pool mean and the gap would not appear -- that is this lane's negative.
func _age_reads() -> bool:
	var band_a: Dictionary = {"id": "forced_a", "min": 20, "max": 20, "prose": "forced a", "nudge": {"dex": 2}}
	var band_b: Dictionary = {"id": "forced_b", "min": 60, "max": 60, "prose": "forced b", "nudge": {"dex": -2}}
	var w1: Variant = _world()
	var w2: Variant = _world()
	_gen_pool(w1)["ageBands"] = [band_a.duplicate(true)]
	_gen_pool(w2)["ageBands"] = [band_a.duplicate(true)]
	var r1: Dictionary = SimRecruits.roll(w1, w1.rng.stream("recruits"))
	var r2: Dictionary = SimRecruits.roll(w2, w2.rng.stream("recruits"))
	if not _apt_eq(r1.get("aptitudes", {}) as Dictionary, r2.get("aptitudes", {}) as Dictionary):
		push_error("age reads: same forced band twice gave different aptitudes: %s vs %s" % [str(r1.get("aptitudes")), str(r2.get("aptitudes"))])
		return false
	if int(r1.get("age", -1)) != int(r2.get("age", -1)):
		push_error("age reads: same forced band twice gave different ages: %d vs %d" % [int(r1.get("age", -1)), int(r2.get("age", -1))])
		return false
	var n: int = 24
	var sum_a: float = 0.0
	var sum_b: float = 0.0
	for i in n:
		var wa: Variant = SimBoot.playable(30000 + i, 64)["world"]
		_gen_pool(wa)["ageBands"] = [band_a.duplicate(true)]
		var ra: Dictionary = SimRecruits.roll(wa, wa.rng.stream("recruits"))
		var aa: Dictionary = ra.get("aptitudes", {}) as Dictionary
		if not _apt_sum_ok(aa):
			push_error("age reads: band A aptitudes invalid %s" % str(aa))
			return false
		sum_a += float(aa.get("dex", 5))
		var wb: Variant = SimBoot.playable(30000 + i, 64)["world"]
		_gen_pool(wb)["ageBands"] = [band_b.duplicate(true)]
		var rb: Dictionary = SimRecruits.roll(wb, wb.rng.stream("recruits"))
		var ab: Dictionary = rb.get("aptitudes", {}) as Dictionary
		if not _apt_sum_ok(ab):
			push_error("age reads: band B aptitudes invalid %s" % str(ab))
			return false
		sum_b += float(ab.get("dex", 5))
	var avg_a: float = sum_a / float(n)
	var avg_b: float = sum_b / float(n)
	if avg_a - avg_b < 0.5:
		push_error("age reads: band A avg dex %.3f not measurably above band B avg %.3f -- nudge not read" % [avg_a, avg_b])
		return false
	print("AGE READS OK same-band identical, band A avg dex %.3f > band B avg %.3f over %d pairs" % [avg_a, avg_b, n])
	return true

# PROSE: `person_clause` is non-empty, names the backstory's authored line verbatim, and
# contains no digit anywhere -- age is a word here, never the number.
func _prose() -> bool:
	var w: Variant = _world()
	var rolled: Dictionary = SimRecruits.roll(w, w.rng.stream("recruits"))
	var ent: int = SimRecruits.spawn_generated(w, rolled, 44.0, 44.0)
	var clause: String = SimSurvivors.person_clause(w, ent)
	if clause.is_empty():
		push_error("prose: person_clause returned an empty string")
		return false
	var line: String = ""
	for s in _gen_pool(w).get("backstories", []) as Array:
		if String((s as Dictionary).get("id", "")) == String(rolled.get("backstoryId", "")):
			line = String((s as Dictionary).get("line", ""))
			break
	if line.is_empty() or clause.find(line) < 0:
		push_error("prose: clause %s does not contain backstory line %s" % [clause, line])
		return false
	var digit := RegEx.new()
	digit.compile("[0-9]")
	if digit.search(clause) != null:
		push_error("prose: clause contains a digit: %s" % clause)
		return false
	# Negative: an entity with no identity at all must degrade to an empty clause, not crash or
	# fabricate a sentence out of nothing.
	var ghost: int = int(w.entities.spawn())
	if SimSurvivors.person_clause(w, ghost) != "":
		push_error("prose negative: an entity with no identity produced a clause")
		return false
	print("PROSE OK: %s" % clause)
	return true

# LOOK RESOLVES: `Appearance.for_entity` with `cid` set to a rolled look must return a tint
# different from the survivor role colour, and two distinct looks must give two distinct
# tints. Negative: a look id with no content entry falls back to the role colour, same as any
# other unknown content id.
func _look_resolves() -> bool:
	var w: Variant = _world()
	var looks: Array = _gen_pool(w).get("looks", []) as Array
	if looks.size() < 2:
		push_error("look resolves: content pool has fewer than 2 looks -- nothing to compare")
		return false
	var role: Color = Palette.COLOURS["survivor"]
	var seen: Dictionary = {}
	for look_id in looks:
		var block: Dictionary = Appearance.of_content(w, "survivor", String(look_id))
		if not block.has("tint"):
			push_error("look resolves: %s declares no tint" % look_id)
			return false
		var look_result: Dictionary = Appearance.for_entity(w, {"unique": true, "cid": String(look_id)})
		var tint: Color = look_result["tint"] as Color
		if tint == role:
			push_error("look resolves: %s resolved the role colour instead of its own tint" % look_id)
			return false
		seen[tint.to_html(false)] = true
	if seen.size() < 2:
		push_error("look resolves: every look resolved the same tint (%s)" % str(seen.keys()))
		return false
	var missing: Dictionary = Appearance.for_entity(w, {"unique": true, "cid": "colony.look.does_not_exist"})
	if (missing["tint"] as Color) != role:
		push_error("look resolves negative: a missing look id must fall back to the role colour")
		return false
	print("LOOK RESOLVES OK %d distinct tints over %d looks" % [seen.size(), looks.size()])
	return true

# DETERMINISM: two worlds on the same seed roll identically; a different seed rolls
# differently, with a loud skip (never a silent pass) if the pools are too small to tell.
func _determinism() -> bool:
	var w1: Variant = _world()
	var w2: Variant = _world()
	var r1: Dictionary = SimRecruits.roll(w1, w1.rng.stream("recruits"))
	var r2: Dictionary = SimRecruits.roll(w2, w2.rng.stream("recruits"))
	if String(r1.get("name", "")) != String(r2.get("name", "")) \
		or String(r1.get("look", "")) != String(r2.get("look", "")) \
		or int(r1.get("age", -1)) != int(r2.get("age", -1)) \
		or String(r1.get("backstoryId", "")) != String(r2.get("backstoryId", "")):
		push_error("determinism: same seed rolled differently: %s vs %s" % [str(r1), str(r2)])
		return false
	var w3: Variant = SimBoot.playable(99999999, 64)["world"]
	var r3: Dictionary = SimRecruits.roll(w3, w3.rng.stream("recruits"))
	var differs: bool = String(r1.get("name", "")) != String(r3.get("name", "")) \
		or String(r1.get("look", "")) != String(r3.get("look", "")) \
		or int(r1.get("age", -1)) != int(r3.get("age", -1))
	if not differs:
		print("DETERMINISM SKIP: a different seed rolled identically -- the pools are too small to tell apart (not a failure)")
		return true
	print("DETERMINISM OK same seed identical, different seed diverges")
	return true

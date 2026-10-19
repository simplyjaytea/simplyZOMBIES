extends SceneTree
# The tick, brought to budget one system at a time (alpha plan A3, docs/22's "Bringing the tick to
# budget"). `npm run godot:bench:runtime` is the number; this gate is what keeps each cut honest.
#
# Every speed-up here is a memo or an index over something the sim already answered the slow way,
# and the defect a memo invites is the quiet kind: a stale answer, no error, no wrong number anyone
# looks at. So every lane holds the fast path to the slow one it replaced -- agreement on the
# shipped data (the true positive) -- and then changes the data underneath it the ways the game and
# its gates actually do, and asks again (the true negative: a memo that cannot go stale is a memo
# this lane cannot fail). The last lane of each slice asks the dead-socket question: does the
# shipped reader reach the fast path at all.
#
# Every lane runs on its own world. The `and ok` order is deliberate: one red lane must not hide
# the ones behind it.

const World = preload("res://sim/world.gd")
const SimItems = preload("res://sim/modules/items.gd")

const FIXTURE: Dictionary = {"seed": 71, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 8.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_index_agrees_with_the_scan() and ok
	ok = _content_index_follows_the_tree() and ok
	ok = _content_index_is_what_item_reads_reach() and ok
	if ok:
		print("M2_TICK_OK content-agree content-follows content-reader")
		quit(0)
	else:
		push_error("M2_TICK_FAIL")
		quit(1)


func _fail(lane: String, why: String) -> bool:
	push_error("M2_TICK_FAIL %s: %s" % [lane, why])
	return false


func _world() -> Variant:
	return World.new(FIXTURE.duplicate(true))


# Every id in the shipped tree, in tree order, once.
func _ids(tree: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for v in tree.values():
		var entries: Array = v as Array if v is Array else [v]
		for e in entries:
			if e is Dictionary and (e as Dictionary).has("id"):
				var id: String = String((e as Dictionary)["id"])
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


# CONTENT-AGREE. For every id the shipped tree carries, the memo hands back the very object the
# old linear scan finds -- asked cold and then warm, so both the build and the hit are judged. An
# id the tree does not carry is null both ways.
func _content_index_agrees_with_the_scan() -> bool:
	var w: Variant = _world()
	var tree: Dictionary = w.content as Dictionary
	var ids: Array[String] = _ids(tree)
	if ids.size() < 100:
		return _fail("CONTENT-AGREE", "the shipped tree has only %d ids; the lane has nothing to judge" % ids.size())
	for pass_name in ["cold", "warm"]:
		for id in ids:
			var fast: Variant = SimItems.content_entry(w, "item", id)
			var slow: Variant = SimItems._scan_for_id(tree, id)
			if not is_same(fast, slow):
				return _fail("CONTENT-AGREE", "%s lookup of %s is not the entry the scan finds" % [pass_name, id])
	if SimItems.content_entry(w, "item", "item.not.in.the.tree") != null:
		return _fail("CONTENT-AGREE", "an id the tree does not carry came back non-null")
	return true


# CONTENT-FOLLOWS. The memo is warmed, then the tree is changed under it the ways gates and the
# reload path change it, and each answer must be the scan's answer for the changed tree:
#   swap   -- an entry replaced at its own key by an edited copy (check_m2_weather pins rain so);
#   remove -- a key erased outright;
#   add    -- a key that did not exist when the memo was built;
#   tree   -- `world.content` replaced wholesale (platform/content_reload.gd);
#   forged -- the memo row itself lies about the object, which only the liveness check can catch.
func _content_index_follows_the_tree() -> bool:
	var w: Variant = _world()
	var tree: Dictionary = w.content as Dictionary
	var path: String = ""
	var id: String = ""
	for p in tree.keys():
		var v: Variant = tree[p]
		if v is Dictionary and (v as Dictionary).has("id"):
			path = String(p)
			id = String((v as Dictionary)["id"])
			break
	if path == "":
		return _fail("CONTENT-FOLLOWS", "no single-entry file in the tree to swap; the lane has nothing to judge")
	var original: Variant = SimItems.content_entry(w, "item", id)
	if not is_same(original, tree[path]):
		return _fail("CONTENT-FOLLOWS", "warming the memo did not find %s at %s" % [id, path])

	var edited: Dictionary = (tree[path] as Dictionary).duplicate(true)
	edited["gateMark"] = "swapped"
	tree[path] = edited
	if not is_same(SimItems.content_entry(w, "item", id), edited):
		return _fail("CONTENT-FOLLOWS", "swap: the memo handed back the entry it was built from")

	tree.erase(path)
	if not is_same(SimItems.content_entry(w, "item", id), SimItems._scan_for_id(tree, id)):
		return _fail("CONTENT-FOLLOWS", "remove: the memo still answers for an erased key")

	var added: Dictionary = {"id": "item.gate.tick.added", "name": "Added after the build"}
	tree["items/gate_tick_added.json"] = added
	if not is_same(SimItems.content_entry(w, "item", "item.gate.tick.added"), added):
		return _fail("CONTENT-FOLLOWS", "add: an entry added after the build was not found")

	var other: Dictionary = {"items/other.json": {"id": id, "name": "From another tree"}}
	w.content = other
	if not is_same(SimItems.content_entry(w, "item", id), other["items/other.json"]):
		return _fail("CONTENT-FOLLOWS", "tree: the memo outlived the tree it was built from")

	var forged: Dictionary = {"id": id, "name": "Not in any tree"}
	((w.content_index as Dictionary)[id] as Dictionary)["e"] = forged
	if not is_same(SimItems.content_entry(w, "item", id), other["items/other.json"]):
		return _fail("CONTENT-FOLLOWS", "forged: a memo row naming an object the tree does not hold was trusted")
	return true


# CONTENT-READER. `item_base_of` is the read that made the scan the tick's biggest cost (about a
# hundred calls a tick in the shipped world). It must reach the memo, not a private copy of the
# scan: on a fresh world nothing has built the memo, and one item read must leave it built over
# this world's tree. A world the reads never reach keeps an empty memo, which is the negative.
func _content_index_is_what_item_reads_reach() -> bool:
	var w: Variant = _world()
	if not (w.content_index as Dictionary).is_empty() or w.content_index_of != null:
		return _fail("CONTENT-READER", "a fresh world already carries a memo, so this lane proves nothing")
	var item: int = SimItems.spawn_item(w, "item.bandage.cloth")
	if item < 0:
		return _fail("CONTENT-READER", "could not spawn the probe item")
	w.content_index = {}
	w.content_index_of = null
	var base: Variant = SimItems.item_base_of(w, item)
	if not base is Dictionary:
		return _fail("CONTENT-READER", "item_base_of found nothing for the probe item")
	if not is_same(w.content_index_of, w.content) or (w.content_index as Dictionary).is_empty():
		return _fail("CONTENT-READER", "item_base_of answered without building this world's memo")
	var quiet: Variant = _world()
	if not (quiet.content_index as Dictionary).is_empty():
		return _fail("CONTENT-READER", "a world nothing read from built a memo anyway")
	return true

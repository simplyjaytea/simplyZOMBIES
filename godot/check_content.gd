extends SceneTree
# The content registry validates, and validation cannot switch itself off.
#
# Two lanes. TREE is the validator run over the shipped tree -- the same call `main.gd`'s reload
# poll and four other gates make. SCHEMA-COVERAGE is the lane docs/23's defect list asked for: a
# content type walked with no schema used to be a `push_warning` and a `continue`, and the run
# still printed GODOT_CONTENT_OK -- shape validation off for a whole directory, in silence. Now
# `validate_tree` reports it as an issue, and this lane proves the detector can say no on a
# fabricated pair, pins the exemption list to exactly the one directory that is gated elsewhere
# by name, and checks that every schema file on disk is registered. A gate that cannot fail is
# worse than no gate.

const ContentValidator = preload("res://platform/content_validator.gd")
const ROOT: String = "res://content"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _the_tree_validates() and ok
	ok = _a_missing_schema_is_a_failure() and ok
	if ok:
		print("GODOT_CONTENT_OK")
		quit(0)
	else:
		print("GODOT_CONTENT_FAIL")
		quit(1)


func _the_tree_validates() -> bool:
	var issues: Array = ContentValidator.validate_tree(ROOT)
	if issues.is_empty():
		print("TREE OK")
		return true
	for msg in issues:
		push_error(String(msg))
	push_error("TREE: %d issue(s)" % issues.size())
	return false


func _a_missing_schema_is_a_failure() -> bool:
	# The detector can say no: a fabricated walk naming a type no schema covers.
	var ghost: Array[String] = ContentValidator.missing_schemas(["item", "ghost"], {"item": {}}, [])
	if ghost != (["ghost"] as Array[String]):
		push_error("SCHEMA-COVERAGE: missing_schemas found %s on a walk missing exactly ghost, so it cannot say no" % str(ghost))
		return false
	# And an exemption is honoured, by name and by nothing else.
	if not ContentValidator.missing_schemas(["ghost"], {}, ["ghost"]).is_empty():
		push_error("SCHEMA-COVERAGE: an exempt type was still reported")
		return false
	if ContentValidator.UNSCHEMA_EXEMPT != (["colony"] as Array[String]):
		push_error("SCHEMA-COVERAGE: the exemption list is %s; colony is the one directory gated elsewhere by name, and a second entry is a decision" % str(ContentValidator.UNSCHEMA_EXEMPT))
		return false
	# Every schema file on disk is one _load_schemas registers, so a schema added beside the
	# others cannot sit unread.
	var schemas: Dictionary = ContentValidator._load_schemas(ROOT)
	var da: DirAccess = DirAccess.open(ROOT + "/schemas")
	if da == null:
		push_error("SCHEMA-COVERAGE: no schemas directory")
		return false
	var on_disk: Array[String] = []
	for f in da.get_files():
		if f.ends_with(".schema.json"):
			on_disk.append(f.trim_suffix(".schema.json"))
	on_disk.sort()
	if on_disk.is_empty():
		push_error("SCHEMA-COVERAGE: no schema files on disk, so nothing was judged")
		return false
	for id in on_disk:
		if not schemas.has(id):
			push_error("SCHEMA-COVERAGE: %s.schema.json is on disk and _load_schemas does not register it" % id)
			return false
	# The real walk: the shipped tree names no type without a schema, colony excepted -- which
	# TREE above already enforces through validate_tree; asked again here directly so the message
	# names the lane.
	var walked: Array = []
	var loader: GDScript = load("res://platform/content_loader.gd") as GDScript
	var tree: Dictionary = loader.call("load_tree", ROOT) as Dictionary
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var t: String = ContentValidator._type_of_path(String(path))
		if not walked.has(t):
			walked.append(t)
	var missing: Array[String] = ContentValidator.missing_schemas(walked, schemas, ContentValidator.UNSCHEMA_EXEMPT)
	if not missing.is_empty():
		push_error("SCHEMA-COVERAGE: the shipped tree walks %s with no schema" % str(missing))
		return false
	print("SCHEMA-COVERAGE OK %d schemas registered and on disk, %d types walked, colony the one exemption; a fabricated ghost type is refused" % [schemas.size(), walked.size()])
	return true

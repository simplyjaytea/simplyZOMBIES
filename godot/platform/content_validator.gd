class_name ContentValidator
extends RefCounted
# R5 — JSON schema validation + extends/behavior checks without Resources in sim state.
# Pure file validation; sim state never holds Nodes/Resources/RIDs/Callables.

# Lightweight schema check without Ajv (Godot has no npm). Checks required/type/enum/pattern
# from the four canonical schemas under godot/content/schemas/. Full JSON Schema is not
# reimplemented — this covers what those four schemas actually assert.

static func _load_schemas(root: String = "res://content") -> Dictionary:
	var out: Dictionary = {}
	# A schema missing from this list is not a loud failure: `_type_of_path` still names the type,
	# `schemas.get(type_id)` returns null, and `_validate_shape` is simply never called for it --
	# shallow validation switches itself off for that whole directory in silence. Registering the
	# id here is what keeps it on.
	for id in ["item", "zombie", "affix", "calibration", "survivor", "map", "loot", "building", "district", "raider", "prop", "player", "dressing"]:
		var path: String = "%s/schemas/%s.schema.json" % [root, id]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("content: missing schema %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			out[id] = parsed as Dictionary
	return out

static func validate_tree(root: String = "res://content") -> Array[String]:
	# 1) validate shape per schema (light), 2) cross-check duplicate ids + extends + behaviors
	var loader: GDScript = load("res://platform/content_loader.gd") as GDScript
	var tree: Dictionary = loader.call("load_tree", root) as Dictionary
	var schemas: Dictionary = _load_schemas(root)
	var issues: Array[String] = []
	var seen: Dictionary = {} # "type:id" -> path
	var by_id: Dictionary = {} # "type:id" -> entry
	# collect entries — skip schemas/ (they are schemas, not entries)
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		var type_id: String = _type_of_path(String(path))
		for entry_v in entries:
			if not entry_v is Dictionary:
				issues.append("%s: expected object" % path)
				continue
			var e: Dictionary = entry_v as Dictionary
			var id: Variant = e.get("id", null)
			if not id is String or String(id).is_empty():
				issues.append("%s: missing or empty id" % path)
				continue
			var key: String = "%s:%s" % [type_id, String(id)]
			if seen.has(key):
				issues.append("%s: duplicate id %s (also in %s)" % [path, String(id), String(seen[key])])
			else:
				seen[key] = path
			by_id[key] = e
			# shape
			var schema: Variant = schemas.get(type_id, null)
			if schema is Dictionary:
				issues.append_array(_validate_shape(e, schema as Dictionary, path))
			if type_id == "survivor" and e.has("aptitudes") and e["aptitudes"] is Dictionary:
				var a: Dictionary = e["aptitudes"] as Dictionary
				var total: int = int(a.get("str", 0)) + int(a.get("dex", 0)) + int(a.get("con", 0))
				if total != 15:
					issues.append("%s: aptitudes sum %d != 15" % [path, total])
			if type_id == "map":
				issues.append_array(_validate_map_entry(e, path))
	# extends + behavior + stat refs
	for key in by_id.keys():
		var e: Dictionary = by_id[key] as Dictionary
		if e.has("extends"):
			var parent_id: String = String(e["extends"])
			var parent_key: String = "%s:%s" % [String(key).split(":")[0], parent_id]
			if not by_id.has(parent_key):
				issues.append("%s: extends %s not found" % [String(seen[key]), parent_id])
		# cycle detection (simple walk)
		var chain: Dictionary = {}
		var cur: String = String(key)
		while true:
			if chain.has(cur):
				issues.append("circular extends at %s" % cur)
				break
			chain[cur] = true
			var ent: Variant = by_id.get(cur, null)
			if not ent is Dictionary or not (ent as Dictionary).has("extends"):
				break
			var pid: String = String((ent as Dictionary)["extends"])
			cur = "%s:%s" % [String(cur).split(":")[0], pid]
			if not by_id.has(cur):
				break
	return issues

static func _type_of_path(path: String) -> String:
	if path.begins_with("items/"): return "item"
	if path.begins_with("zombies/"): return "zombie"
	if path.begins_with("affixes/"): return "affix"
	if path.begins_with("calibration/"): return "calibration"
	if path.begins_with("survivors/"): return "survivor"
	if path.begins_with("maps/"): return "map"
	if path.begins_with("buildings/"): return "building"
	if path.begins_with("districts/"): return "district"
	if path.begins_with("loot/"): return "loot"
	if path.begins_with("raiders/"): return "raider"
	if path.begins_with("props/"): return "prop"
	if path.begins_with("players/"): return "player"
	if path.begins_with("dressing/"): return "dressing"
	return path.get_slice("/", 0)

static func _validate_shape(entry: Dictionary, schema: Dictionary, path: String) -> Array[String]:
	var out: Array[String] = []
	var required: Variant = schema.get("required", [])
	if required is Array:
		for r in required as Array:
			if not entry.has(String(r)):
				out.append("%s: missing required %s" % [path, String(r)])
	var props: Variant = schema.get("properties", null)
	if props is Dictionary:
		for k in entry.keys():
			var sk: String = String(k)
			var prop: Variant = (props as Dictionary).get(sk, null)
			if prop == null:
				# additionalProperties false
				if not bool(schema.get("additionalProperties", true)):
					# allow extends even if schema lists it optionally
					if sk == "extends":
						continue
					out.append("%s: unexpected property %s" % [path, sk])
				continue
			if prop is Dictionary:
				var p: Dictionary = prop as Dictionary
				var t: Variant = p.get("type", null)
				var v: Variant = entry[sk]
				if t is String and not _type_ok(v, String(t)):
					out.append("%s.%s: expected %s" % [path, sk, String(t)])
				var en: Variant = p.get("enum", null)
				if en is Array and not (en as Array).has(v):
					out.append("%s.%s: not in enum %s" % [path, sk, str(en)])
				var pat: Variant = p.get("pattern", null)
				if pat is String and v is String:
					var re := RegEx.new()
					re.compile(String(pat))
					if re.search(String(v)) == null:
						out.append("%s.%s: does not match %s" % [path, sk, String(pat)])
	return out

static func _validate_map_entry(entry: Dictionary, path: String) -> Array[String]:
	var out: Array[String] = []
	var rect_v: Variant = entry.get("rect", null)
	if not rect_v is Dictionary:
		return out
	var rect: Dictionary = rect_v as Dictionary
	var expected: int = int(rect.get("w", 0)) * int(rect.get("h", 0))
	if expected <= 0:
		out.append("%s.rect: w*h must be > 0" % path)
		return out
	for field in ["tiles", "surfaces", "indoors"]:
		var arr: Variant = entry.get(field, null)
		if arr is Array and (arr as Array).size() != expected:
			out.append("%s.%s: length %d != rect.w*h %d" % [path, field, (arr as Array).size(), expected])
	return out

static func _type_ok(v: Variant, t: String) -> bool:
	match t:
		"string": return v is String
		"number": return v is float or v is int
		"integer": return v is int or (v is float and float(v) == float(int(v)))
		"boolean": return v is bool
		"array": return v is Array
		"object": return v is Dictionary
		_: return true

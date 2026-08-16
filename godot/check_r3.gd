extends SceneTree
func _init() -> void:
	var files: Array[String] = [
		"res://sim/inventory/grid.gd",
		"res://sim/modules/items.gd",
		"res://sim/modules/inventory.gd",
		"res://sim/kernel/serialize.gd",
		"res://sim/world.gd",
	]
	var ok: bool = true
	for p in files:
		var s: Variant = load(p)
		if s == null:
			push_error("FAIL load %s" % p)
			ok = false
		else:
			print("OK %s" % p)
	# smoke SimGrid
	var grid_mod: Variant = load("res://sim/inventory/grid.gd")
	print("grid %s" % str(grid_mod))
	# smoke items/inventory can be loaded
	print("items loaded %s" % str(load("res://sim/modules/items.gd") != null))
	print("inventory loaded %s" % str(load("res://sim/modules/inventory.gd") != null))
	# serialize smoke
	var ser: Variant = load("res://sim/kernel/serialize.gd")
	var canon: String = ser.call("canonicalize", {"b": 2, "a": 1, "c": [3, 2]})
	print("canon %s" % canon)
	var fp: String = ser.call("fingerprint", canon)
	print("fp %s" % fp)
	if canon != '{"a":1,"b":2,"c":[3,2]}':
		push_error("canonicalize mismatch: %s" % canon)
		ok = false
	var vcanon: String = ser.call("canonicalize", {"p": Vector2i(3, 4), "path": [Vector2i(1, 2)]})
	if vcanon != '{"p":{"x":3,"y":4},"path":[{"x":1,"y":2}]}':
		push_error("Vector2i canonicalize mismatch: %s" % vcanon)
		ok = false
	else:
		print("Vector2i OK")
	if ok:
		print("R3_SMOKE_OK")
	else:
		print("R3_SMOKE_FAIL")
	quit(0 if ok else 1)

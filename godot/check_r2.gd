extends SceneTree
func _init():
	var ok := true
	var files := [
		"res://sim/map/tilemap.gd",
		"res://sim/map/surface.gd",
		"res://sim/locomotion.gd",
		"res://sim/stances.gd",
		"res://sim/time/clock.gd",
		"res://sim/spatial/hash.gd",
		"res://sim/vision/shadowcast.gd",
		"res://sim/vision/visibility.gd",
		"res://sim/vision/light.gd",
		"res://sim/field/attention.gd",
	]
	for p in files:
		var s = load(p)
		if s == null:
			push_error("FAIL load %s" % p)
			ok = false
		else:
			print("OK %s" % p)
	# smoke instantiate tilemap + attention + spatial + clock
	var map = load("res://sim/map/tilemap.gd").generate_district(12345, 16)
	print("map %d x %d tiles=%d indoors=%d" % [map.w, map.h, map.tiles.size(), map.indoors.size()])
	var field = load("res://sim/field/attention.gd").for_map(map)
	print("field %d cols %d rows" % [field.cols, field.rows])
	field.emit_noise(5.0, 5.0, 10.0)
	print("emit cells %d live %d peak %.2f" % [field.last_emit_cells, field.live_cells(), field.peak_noise()])
	field.add_scent(5.0, 5.0, 2.0)
	print("scent live %d" % field.live_scent_cells())
	field.decay()
	field.diffuse_scent()
	print("after decay/diffuse live %d" % field.live_cells())
	# clock
	var clock = load("res://sim/time/clock.gd")
	print("tick 0 ambient %.3f phase %d" % [clock.ambient_light_at(0), clock.phase_of(0)])
	print("tick 28800 noon ambient %.3f" % [clock.ambient_light_at(28800)])
	# shadowcast
	var vis_tiles = load("res://sim/vision/shadowcast.gd").VisibleTiles.new()
	load("res://sim/vision/shadowcast.gd").shadowcast(map, 8, 8, 5, vis_tiles)
	print("shadowcast count %d" % vis_tiles.count)
	# stances
	var stances = load("res://sim/stances.gd")
	print("walk noise %.1f factor %.2f" % [stances.noise_of(stances.Stance.Walk), stances.speed_factor_of(stances.Stance.Walk)])
	# locomotion
	print("walk speed %.2f" % load("res://sim/locomotion.gd").WALK_SPEED)
	if ok:
		print("R2_MODULES_OK")
	quit(0 if ok else 1)

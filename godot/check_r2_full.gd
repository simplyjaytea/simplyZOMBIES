extends SceneTree
func _init():
	print("SMOKE_START")
	var ok := true
	var tilemap = load("res://sim/map/tilemap.gd") as GDScript
	var map = tilemap.call("blank_map", 16, 16)
	print("blank_map ", map.w, "x", map.h)
	var dmap = tilemap.call("generate_district", 12345, 32)
	print("district ", dmap.w, "x", dmap.h, " tiles ", dmap.tiles.size())
	var surf = load("res://sim/map/surface.gd") as GDScript
	print("surface_at ", surf.call("surface_at", dmap, 5, 5))
	var loco = load("res://sim/locomotion.gd") as GDScript
	print("WALK_SPEED ", loco.WALK_SPEED)
	var st = load("res://sim/stances.gd") as GDScript
	print("stance_eye crawl ", st.call("eye_of", 0), " walk ", st.call("eye_of", 2))
	var clk = load("res://sim/time/clock.gd") as GDScript
	print("ambient ", clk.call("ambient_light_at", 0), " ", clk.call("ambient_light_at", clk.DAY_TICKS/2))
	var hash = load("res://sim/spatial/hash.gd") as GDScript
	var h = hash.call("empty_hash")
	print("hash empty ", h.cols, "x", h.rows)
	var sc = load("res://sim/vision/shadowcast.gd") as GDScript
	var vt = sc.VisibleTiles.new()
	sc.call("shadowcast", dmap, 8, 8, 5, vt, 0)
	print("shadowcast count ", vt.count)
	var attn = load("res://sim/field/attention.gd") as GDScript
	var field = attn.call("for_map", dmap)
	print("field ", field.cols, "x", field.rows)
	field.emit_noise(5.0, 5.0, 10.0)
	print("emit live ", field.live_cells(), " peak ", field.peak_noise(), " cells ", field.last_emit_cells)
	field.add_scent(5.0, 5.0, 2.0)
	field.diffuse_scent()
	field.decay()
	print("after scent/decay live ", field.live_cells(), " scent ", field.live_scent_cells())
	print("SMOKE_R2_OK")
	quit(0)

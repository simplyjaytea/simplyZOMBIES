extends SceneTree
# M2 stats MVP + unique spawn: aptitudes, CON duration, STR carry/escape, DEX speed, Mara.

const World = preload("res://sim/world.gd")
const SimAptitudes = preload("res://sim/modules/aptitudes.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimInfection = preload("res://sim/modules/infection.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _midpoint_is_neutral() and ok
	ok = _formulas() and ok
	ok = _con_lengthens_infection() and ok
	ok = _dex_speeds_walk() and ok
	ok = _mara_spawns() and ok
	ok = _roll_is_budgeted_and_seeded() and ok
	ok = _save_roundtrip() and ok
	if ok:
		print("M2_STATS_OK midpoint formulas con dex mara roll save")
		quit(0)
	else:
		push_error("M2_STATS_FAIL")
		quit(1)

func _fixture(seed_val: int = 4242) -> Dictionary:
	return {"seed": seed_val, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

func _midpoint_is_neutral() -> bool:
	var w: Variant = World.new(_fixture())
	SimAptitudes.apply(w, w.player, {"str": 5, "dex": 5, "con": 5})
	var carry: float = float(w.modifiers.call("resolve", "carry_capacity", w.player))
	var esc: float = float(w.modifiers.call("resolve", "grab_escape", w.player))
	var spd: float = float(w.modifiers.call("resolve", "move_speed", w.player))
	var inf: float = float(w.modifiers.call("resolve", "infection_progression", w.player))
	var dmg: float = float(w.modifiers.call("resolve", "damage_taken", w.player))
	if absf(carry - 25.0) > 0.001 or absf(esc - 1.0) > 0.001 or absf(spd - 1.0) > 0.001 or absf(inf - 1.0) > 0.001 or absf(dmg - 1.0) > 0.001:
		push_error("midpoint not neutral carry=%s esc=%s spd=%s inf=%s dmg=%s" % [carry, esc, spd, inf, dmg])
		return false
	var p: float = SimAptitudes.escape_chance(w, w.player, 0.5)
	if absf(p - (1.0 / 1.5)) > 0.001:
		push_error("baseline escape vs 1 shambler %s != 2/3" % p)
		return false
	print("MIDPOINT OK")
	return true

func _formulas() -> bool:
	var w: Variant = World.new(_fixture(7))
	# Mara's spread: STR 3 / DEX 5 / CON 7
	SimAptitudes.apply(w, w.player, {"str": 3, "dex": 5, "con": 7})
	var carry: float = float(w.modifiers.call("resolve", "carry_capacity", w.player))
	var esc: float = float(w.modifiers.call("resolve", "grab_escape", w.player))
	var inf: float = float(w.modifiers.call("resolve", "infection_progression", w.player))
	var dmg: float = float(w.modifiers.call("resolve", "damage_taken", w.player))
	if absf(carry - 19.0) > 0.001:
		push_error("STR 3 carry %s != 19" % carry)
		return false
	if absf(esc - 0.8) > 0.001:
		push_error("STR 3 grab_escape %s != 0.8" % esc)
		return false
	if absf(inf - 0.90) > 0.001:
		push_error("CON 7 infection_progression %s != 0.90" % inf)
		return false
	if absf(dmg - 0.92) > 0.001:
		push_error("CON 7 damage_taken %s != 0.92" % dmg)
		return false
	var w8: Variant = World.new(_fixture(8))
	SimAptitudes.apply(w8, w8.player, {"str": 8, "dex": 8, "con": 3})
	var spd: float = float(w8.modifiers.call("resolve", "move_speed", w8.player))
	if absf(spd - 1.18) > 0.001:
		push_error("DEX 8 move_speed %s != 1.18" % spd)
		return false
	print("FORMULAS OK")
	return true

func _con_lengthens_infection() -> bool:
	var w_lo: Variant = World.new(_fixture(9))
	var w_hi: Variant = World.new(_fixture(9))
	SimAptitudes.apply(w_lo, w_lo.player, {"str": 5, "dex": 5, "con": 3})
	SimAptitudes.apply(w_hi, w_hi.player, {"str": 5, "dex": 5, "con": 7})
	var d_lo: int = SimInfection.stage_duration_ticks(SimInfection.Stage.Latent, w_lo, w_lo.player)
	var d_hi: int = SimInfection.stage_duration_ticks(SimInfection.Stage.Latent, w_hi, w_hi.player)
	var d_mid: int = SimInfection.stage_duration_ticks(SimInfection.Stage.Latent, null)
	if d_hi <= d_mid or d_lo >= d_mid:
		push_error("CON should lengthen duration hi=%d mid=%d lo=%d" % [d_hi, d_mid, d_lo])
		return false
	print("CON OK latent lo=%d mid=%d hi=%d" % [d_lo, d_mid, d_hi])
	return true

func _dex_speeds_walk() -> bool:
	var f: Dictionary = _fixture(11)
	var slow: Variant = World.new(f)
	var fast: Variant = World.new(f)
	SimAptitudes.apply(slow, slow.player, {"str": 7, "dex": 3, "con": 5})
	SimAptitudes.apply(fast, fast.player, {"str": 4, "dex": 8, "con": 3})
	for _i in 20:
		slow.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		fast.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		slow.step()
		fast.step()
	var xs: float = float((slow.components.get_component(slow.player, "position") as Dictionary)["x"])
	var xf: float = float((fast.components.get_component(fast.player, "position") as Dictionary)["x"])
	if xf <= xs:
		push_error("DEX 8 should walk farther than DEX 3: %s vs %s" % [xf, xs])
		return false
	print("DEX OK x_lo=%s x_hi=%s" % [xs, xf])
	return true

func _mara_spawns() -> bool:
	var w: Variant = World.new(_fixture(21))
	var mara: int = SimSurvivors.boot_playable(w)
	if mara < 0:
		push_error("no unique spawned")
		return false
	var ident: Variant = w.components.get_component(mara, "identity")
	if ident == null or String((ident as Dictionary).get("name", "")) != "Mara Okoro":
		push_error("mara identity %s" % str(ident))
		return false
	var apt: Dictionary = SimAptitudes.of(w, mara)
	if int(apt["str"]) != 3 or int(apt["con"]) != 7 or int(apt["dex"]) != 5:
		push_error("mara aptitudes %s" % str(apt))
		return false
	if int(apt["str"]) + int(apt["dex"]) + int(apt["con"]) != 15:
		push_error("mara budget")
		return false
	var carry: float = float(w.modifiers.call("resolve", "carry_capacity", mara))
	if absf(carry - 19.0) > 0.001:
		push_error("mara STR 3 carry %s" % carry)
		return false
	var kit: Array = []
	# pockets
	var box: Variant = w.components.get_component(mara, "container")
	if box is Dictionary:
		for p in (box as Dictionary).get("items", []) as Array:
			kit.append(int((p as Dictionary)["item"]))
	if kit.size() < 1:
		push_error("mara kit empty")
		return false
	print("MARA OK entity=%d kit=%d" % [mara, kit.size()])
	return true

func _roll_is_budgeted_and_seeded() -> bool:
	var pool: Array[Dictionary] = SimAptitudes.compositions()
	if pool.is_empty():
		push_error("no compositions")
		return false
	for c in pool:
		var s: int = int(c["str"]) + int(c["dex"]) + int(c["con"])
		if s != 15 or int(c["str"]) < 3 or int(c["str"]) > 8:
			push_error("bad composition %s" % str(c))
			return false
	var a: Variant = World.new(_fixture(99))
	var b: Variant = World.new(_fixture(99))
	var r1: Dictionary = SimAptitudes.roll(a)
	var r2: Dictionary = SimAptitudes.roll(b)
	if r1["str"] != r2["str"] or r1["dex"] != r2["dex"] or r1["con"] != r2["con"]:
		push_error("roll not deterministic %s vs %s" % [str(r1), str(r2)])
		return false
	print("ROLL OK n=%d sample=%s" % [pool.size(), str(r1)])
	return true

func _save_roundtrip() -> bool:
	var w: Variant = World.new(_fixture(33))
	SimSurvivors.boot_playable(w)
	var snap: Dictionary = w.snapshot()
	var w2: Variant = World.new(_fixture(33))
	w2.restore(snap)
	if w.serialize() != w2.serialize():
		push_error("aptitudes save roundtrip drifted")
		return false
	print("SAVE OK")
	return true

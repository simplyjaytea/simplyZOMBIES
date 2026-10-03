extends SceneTree
# Actual shipped world, including all registered modules and the event drain. The old
# bench.gd's synthetic dictionary does not exercise this consumer.
const Boot = preload("res://sim/boot.gd")
const Clock = preload("res://sim/time/clock.gd")
const WARMUP: int = 100
const SAMPLES: int = 600

func _init() -> void:
	var w: Variant = Boot.playable()["world"]
	var boot_tick: int = int(w.tick)
	var zombies_start: int = w.components.query(["shambler"]).size()
	for i in WARMUP:
		w.step()
	var start_tick: int = int(w.tick)
	var samples: Array[float] = []
	for i in SAMPLES:
		var started: int = Time.get_ticks_usec()
		w.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	# FULL stops on day ten's end of dusk, not the end of ten complete days. This is
	# an early-day throughput projection, not a campaign result or a completion promise.
	var campaign_ticks: int = Clock.tick_on_day(10, Clock.DUSK_ENDS) - boot_tick
	print("RUNTIME_RESULT " + JSON.stringify({
		"id": "shipped-tick", "samples_ms": samples, "warmup": WARMUP,
		"seed": int(w.seed), "tiles": int(w.map_width), "start_tick": start_tick,
		"end_tick": int(w.tick), "zombies_start": zombies_start,
		"zombies_end": w.components.query(["shambler"]).size(),
		"systems": w.systems.ids.size(), "campaign_ticks": campaign_ticks,
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(),
		"cpu": OS.get_processor_name(), "scope": "SimBoot.playable default; world.step including drain"
	}))
	print("RUNTIME_MEASUREMENT_COMPLETE tick")
	quit(0)

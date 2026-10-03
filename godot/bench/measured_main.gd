extends "res://presentation/main.gd"
# Wrap the shipped consumer, never copy its drawing implementation into a benchmark.
# Only _draw command generation is timed here. Presentation, GPU and V-Sync are separate.
var bench_draw_us: int = 0
var bench_draw_count: int = 0

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	super._draw()
	bench_draw_us = Time.get_ticks_usec() - started
	bench_draw_count += 1

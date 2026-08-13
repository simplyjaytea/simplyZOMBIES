extends Node2D

const World = preload("res://sim/world.gd")
const Content = preload("res://platform/content_loader.gd")
const CELL: float = 44.0
const ORIGIN := Vector2(180.0, 50.0)

var fixture: Dictionary
var content: Dictionary
var world: Variant
var commands_by_tick: Dictionary = {}
var accumulator: float = 0.0


func _ready() -> void:
	content = Content.load_tree()
	var fixture_path := ProjectSettings.globalize_path("res://parity/r1-walking-skeleton.json")
	var file := FileAccess.open(fixture_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open R1 fixture: %s" % fixture_path)
		return
	fixture = JSON.parse_string(file.get_as_text())
	world = World.new(fixture)
	for command_value: Variant in fixture["commands"]:
		var timed: Dictionary = command_value
		var at_tick := int(timed["tick"])
		var command := timed.duplicate(true)
		command.erase("tick")
		if not commands_by_tick.has(at_tick):
			commands_by_tick[at_tick] = []
		(commands_by_tick[at_tick] as Array).append(command)
	queue_redraw()
	print("GODOT_R1_READY")


func _process(delta: float) -> void:
	if world == null:
		return
	accumulator += delta
	while accumulator >= World.TICK_SECONDS:
		accumulator -= World.TICK_SECONDS
		var next_tick: int = int(world.tick) + 1
		for command_value: Variant in commands_by_tick.get(next_tick, []):
			world.commands.push(command_value)
		world.step()
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for y in world.map_height:
		for x in world.map_width:
			var rect := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2.ONE * CELL)
			draw_rect(rect, Color("111419") if world.is_blocked_tile(x, y) else Color("29312c"))
			draw_rect(rect, Color("414a45"), false, 1.0)
	var position: Dictionary = world.components.get_component(world.player, "position")
	var centre := ORIGIN + Vector2(float(position["x"]), float(position["y"])) * CELL
	draw_circle(centre, CELL * 0.28, Color("d4ad5b"))
	draw_circle(centre, CELL * 0.28, Color("f5df9d"), false, 2.0)

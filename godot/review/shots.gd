extends SceneTree
# The screenshot review: photographs the fixed scenes in `scenes.gd` at both supported windows,
# so an art slice's before and after shots come from the same states and can be compared.
#
#   DISPLAY=:1 npm run godot:shots                 # writes <repo>/review-shots/<W>x<H>/<scene>.png
#   DISPLAY=:1 npm run godot:shots -- --out=DIR    # or anywhere else
#   DISPLAY=:1 npm run godot:shots -- --only=colony,viewing   # just those scenes, while iterating
#
# Run it with a display: the capture reads the root viewport, and `--headless` has no pixels to
# read. On a headless VM, `xvfb-run -a npm run godot:shots` gives it one. The gate that keeps this
# driver honest is `npm run godot:check:shots` (`check_shots.gd`), which runs the same scene setups
# and refuses a capture that is blank or identical to another scene's.
#
# Every scene is refused, loudly and with a nonzero exit, when its setup cannot be made or the
# world is not the state the scene names -- a photograph of the wrong state is worse than none.

const Scenes = preload("res://review/scenes.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = _out_dir()
	DirAccess.make_dir_recursive_absolute(out)
	for size in Scenes.SIZES:
		var dir: String = out.path_join("%dx%d" % [size.x, size.y])
		DirAccess.make_dir_recursive_absolute(dir)
		for scene in Scenes.NAMES:
			if _only().is_empty() or _only().has(scene):
				await _shoot(size, dir, scene)
	print("SHOTS_OUT %s" % out)
	quit(1 if _failed else 0)


func _shoot(size: Vector2i, dir: String, scene: String) -> void:
	root.size = size
	await process_frame
	var main: Node = await Scenes.boot(self)
	if main == null:
		_refuse("%s: the main scene did not come up" % scene)
		return
	var err: String = await Scenes.setup(self, main, scene)
	if err.is_empty():
		err = Scenes.verify(main, scene)
	if not err.is_empty():
		_refuse("%s at %dx%d: %s" % [scene, size.x, size.y, err])
		main.queue_free()
		await process_frame
		return
	# One more frame so everything the setup queued has been drawn.
	await process_frame
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_refuse("%s: no pixels, run with a display (DISPLAY=:1 or xvfb-run)" % scene)
	else:
		var path: String = dir.path_join("%s.png" % scene)
		var saved: Error = image.save_png(path)
		if saved != OK:
			_refuse("%s: could not write %s (error %d)" % [scene, path, saved])
		else:
			print("SHOT %s" % path)
	main.queue_free()
	await process_frame


func _refuse(message: String) -> void:
	push_error("SHOTS REFUSED %s" % message)
	_failed = true


# `--only=a,b` if given: the scenes to shoot, by name. Empty means every scene.
func _only() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.substr("--only=".length()).split(",", false)
	return PackedStringArray()


# `--out=DIR` if given, else `review-shots/` beside the repository's godot/ folder. The default is
# inside the repository and gitignored, so a capture is one command away for the art threads.
func _out_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.substr("--out=".length())
	return ProjectSettings.globalize_path("res://").path_join("../review-shots").simplify_path()

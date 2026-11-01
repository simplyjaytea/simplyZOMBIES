extends SceneTree
# The survivor review: the first-person survivor model photographed in the game's own renderer, so the
# art is judged under the sky, sun, lens and eye height the first-person scene uses, not only in Blender.
#
#   npm run godot:shots:survivor                                  # res://assets/first_person/survivor.glb
#   npm run godot:shots:survivor -- --glb=PATH                    # a candidate GLB, by absolute path
#   SURVIVOR_GLB=PATH npm run godot:shots:survivor                # the same, by environment (the argument wins)
#   npm run godot:shots:survivor -- --out=DIR                     # default: a dated folder under the survivor-base review
#   npm run godot:shots:survivor -- --size=1920x1080 --tick=36000 --concept=PATH
#
# Needs a display: the pixels come from the root viewport, as `shots.gd` does (DISPLAY=:1 on a VM).
#
# The views: full body front, three-quarter and back; head close-ups front, three-quarter, profile and
# back; the first-person ranges 0.9 m, 2 m and 5 m from the eye; the `walk` clip at eight phases, one frame
# each and as one strip. Then `sheet.png`: the concept beside the renders, labelled. `review.json` records
# which GLB (by SHA-256), tick, size and lenses made the set, so two sets can be told apart later.
#
# The look is the first-person scene's own: `SkyView` builds the same environment, sun, fog and eye light
# from the sim's clock (`--tick`, noon by default), the camera is the first-person lens (75 degrees, near
# 0.05, far 240) at the standing eye of 1.62 m, and the model comes through `models.gd`, the loader the game
# uses. The orbit views use narrower lenses (35 degrees for the full body, 24 for the head) so the figure is
# not distorted at close range: that is the one place the lens is not the game's.
#
# The one write to the sim is `world.tick`, set the way `review/scenes.gd` sets it before a shot; nothing is
# stepped. The clips are read from the model's own AnimationPlayer: each is played at speed zero and sought
# to its phase, as `body_view.gd` does for every body, so the pose is the clip's and never a clock's.

const Clock = preload("res://sim/time/clock.gd")
const SimBoot = preload("res://sim/boot.gd")
const SkyView = preload("res://presentation/first_person/sky_view.gd")
const Models = preload("res://presentation/first_person/models.gd")
const Chrome = preload("res://ui/chrome.gd")

const DEFAULT_GLB: String = "res://assets/first_person/survivor.glb"
const DEFAULT_OUT_ROOT: String = "C:/Users/jtf/orca/sz-shared/survivor-base/review"
const DEFAULT_CONCEPT: String = "C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png"
const DEFAULT_SIZE: Vector2i = Vector2i(1920, 1080)

# The first-person lens and eye: first_person.gd's camera, and the standing eye of the posture.
const FP_FOV: float = 75.0
const FP_NEAR: float = 0.05
const FP_FAR: float = 240.0
const FP_EYE_M: float = 1.62
const FP_RANGES_M: Array[float] = [0.9, 2.0, 5.0]
# The height the eye looks at on the body: the chest, where a glance lands.
const FP_TARGET_M: float = 1.2

# The orbit lenses. A full-body frame is this many figure heights tall; a head frame this many metres.
const FULL_FOV: float = 35.0
const FULL_FRAME_RATIO: float = 1.2
const HEAD_FOV: float = 24.0
const HEAD_FRAME_M: float = 0.44
# The head close-ups are centred on the standing eye height, not on the model's bounding-box crown: a
# bun or a tall hairstyle raises the crown and would push the face out of frame.
const HEAD_CENTRE_M: float = FP_EYE_M

const WALK_CLIP: String = "walk"
const WALK_PHASES: int = 8
# The strip keeps the column that holds the figure, centred on the frame, and scales each cell to this.
const STRIP_COLUMN_PX: int = 540
const STRIP_CELL: Vector2i = Vector2i(360, 720)

const FLOOR_COLOUR: Color = Color(0.16, 0.17, 0.17)
const CAPTION_COLOUR: Color = Color(0.94, 0.88, 0.66)
const SHEET_BACKGROUND: Color = Color(0.07, 0.08, 0.09)
const CAPTION_SIZE: int = 25
const SHEET_WIDTH: int = 1900
const SHEET_MARGIN: int = 40
const SHEET_GAP: int = 30
const SHEET_CAPTION_H: int = 34

var _failed: bool = false
var _view: SubViewport = null
var _camera: Camera3D = null
var _sky: SkyView = null
var _out: String = ""
var _saved: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var glb: String = _glb_path()
	if not FileAccess.file_exists(glb):
		_refuse("no survivor GLB at %s" % glb)
		quit(1)
		return
	var size: Vector2i = _size()
	_out = _out_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	# The stage is drawn in its own viewport with its own 3D world, not the window's root viewport: the root
	# grabbed blank and at the wrong size on a headed Windows run, while a SubViewport reads back exactly.
	_view = SubViewport.new()
	_view.name = "ReviewView"
	_view.size = size
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	await process_frame

	var boot: Dictionary = SimBoot.playable(SimBoot.DISTRICT_SEED)
	var world: Variant = boot["world"]
	world.tick = _tick()
	var stage: Node3D = _build_stage(world)

	var holder: Node3D = Node3D.new()
	holder.name = "Survivor"
	stage.add_child(holder)
	var model: Node3D = Models.instance_of(glb)
	if model == null:
		_refuse("%s did not load as a GLB" % glb)
		quit(1)
		return
	holder.add_child(model)
	var box: AABB = Models.bounds(model)
	if box.size.y <= 0.0:
		_refuse("%s has no mesh to photograph" % glb)
		quit(1)
		return

	var centre: Vector3 = box.get_center()
	var full_d: float = _distance(box.size.y * FULL_FRAME_RATIO, FULL_FOV)
	var full_front: Image = await _shot("full_front", _orbit(centre, full_d, 0.0), centre, FULL_FOV, size)
	var full_34: Image = await _shot("full_three_quarter", _orbit(centre, full_d, 45.0), centre, FULL_FOV, size)
	var full_back: Image = await _shot("full_back", _orbit(centre, full_d, 180.0), centre, FULL_FOV, size)

	var head_at: Vector3 = Vector3(centre.x, HEAD_CENTRE_M, centre.z)
	var head_d: float = _distance(HEAD_FRAME_M, HEAD_FOV)
	var head_front: Image = await _shot("head_front", _orbit(head_at, head_d, 0.0), head_at, HEAD_FOV, size)
	var head_34: Image = await _shot("head_three_quarter", _orbit(head_at, head_d, 45.0), head_at, HEAD_FOV, size)
	var head_profile: Image = await _shot("head_profile", _orbit(head_at, head_d, 90.0), head_at, HEAD_FOV, size)
	var head_back: Image = await _shot("head_back", _orbit(head_at, head_d, 180.0), head_at, HEAD_FOV, size)

	var fp_images: Array[Image] = []
	for metres in FP_RANGES_M:
		var eye: Vector3 = Vector3(centre.x, FP_EYE_M, centre.z - metres)
		var aim: Vector3 = Vector3(centre.x, FP_TARGET_M, centre.z)
		var file_name: String = "fp_%s" % _metres_label(metres)
		fp_images.append(await _shot(file_name, eye, aim, FP_FOV, size))

	var player: AnimationPlayer = _player_in(model)
	if player == null or not player.has_animation(WALK_CLIP):
		_refuse("%s has no AnimationPlayer with a `%s` clip" % [glb, WALK_CLIP])
		quit(1)
		return
	var walk: Dictionary = await _walk(player, centre, full_d, size)

	var figures: Array = [["full front", full_front], ["full three-quarter", full_34], ["full back", full_back]]
	var heads: Array = [["head front", head_front], ["head three-quarter", head_34], ["head profile", head_profile], ["head back", head_back]]
	await _sheet(figures, heads, fp_images, walk["strip"] as Image)
	_write_info(glb, world, size)
	print("SURVIVOR_OUT %s" % _out)
	quit(1 if _failed else 0)


# --- the stage: the first-person sky, a plain floor, the model -------------------------------------

func _build_stage(world: Variant) -> Node3D:
	var stage: Node3D = Node3D.new()
	stage.name = "Stage"
	_view.add_child(stage)
	_camera = Camera3D.new()
	_camera.name = "Eye"
	_camera.near = FP_NEAR
	_camera.far = FP_FAR
	_camera.current = true
	stage.add_child(_camera)
	_sky = SkyView.new()
	_sky.name = "Sky"
	stage.add_child(_sky)
	_sky.build(_camera)
	_sky.update(world)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOUR
	material.roughness = 0.95
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "ReviewFloor"
	floor_mesh.mesh = plane
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	return stage


# --- one photograph -------------------------------------------------------------------------------

# Points the lens at `at` from `eye`, lets two frames draw, and saves what the root viewport shows.
func _shot(file_name: String, eye: Vector3, at: Vector3, fov: float, size: Vector2i) -> Image:
	_camera.fov = fov
	_camera.position = eye
	_camera.look_at(at, Vector3.UP)
	await process_frame
	await process_frame
	var image: Image = _view.get_texture().get_image()
	if image == null or image.is_empty():
		_refuse("%s: no pixels, run with a display (DISPLAY=:1 or xvfb-run)" % file_name)
		return null
	if image.get_size() != size:
		_refuse("%s: captured %s, asked for %s" % [file_name, image.get_size(), size])
		return null
	_save(image, file_name)
	return image


# The camera position on a ring about `at`, `yaw` degrees round from the model's front. The model faces
# -Z, so yaw 0 is the front, 90 is the +X side, 180 is the back.
func _orbit(at: Vector3, distance: float, yaw_degrees: float) -> Vector3:
	var yaw: float = deg_to_rad(yaw_degrees)
	return at + Vector3(sin(yaw), 0.0, -cos(yaw)) * distance


# The distance at which a vertical frame of `height` metres fills the lens's `fov` (degrees).
func _distance(height: float, fov: float) -> float:
	return height * 0.5 / tan(deg_to_rad(fov) * 0.5)


# --- the walk clip: eight phases through the model's own player ----------------------------------

# Returns {"strip": Image} with the eight crops in order, each a full frame saved as walk_NN.png.
func _walk(player: AnimationPlayer, centre: Vector3, distance: float, size: Vector2i) -> Dictionary:
	var length: float = player.get_animation(WALK_CLIP).length
	# Speed zero: the clip moves only when this loop seeks it, never on its own clock.
	player.play(WALK_CLIP, -1.0, 0.0)
	var strip: Image = Image.create(STRIP_CELL.x * WALK_PHASES, STRIP_CELL.y, false, Image.FORMAT_RGBA8)
	for phase in WALK_PHASES:
		player.seek(length * float(phase) / float(WALK_PHASES), true)
		var frame: Image = await _shot("walk_%02d" % phase, _orbit(centre, distance, 45.0), centre, FULL_FOV, size)
		if frame == null:
			return {"strip": strip}
		var column: Image = frame.get_region(Rect2i((size.x - STRIP_COLUMN_PX) / 2, 0, STRIP_COLUMN_PX, size.y))
		column.resize(STRIP_CELL.x, STRIP_CELL.y, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(column, Rect2i(Vector2i.ZERO, STRIP_CELL), Vector2i(phase * STRIP_CELL.x, 0))
	_save(strip, "walk_strip")
	return {"strip": strip}


# --- the sheet: the concept beside the renders, labelled, drawn by the engine's own text --------

func _sheet(figures: Array, heads: Array, fp: Array[Image], strip: Image) -> bool:
	var concept_path: String = _arg("--concept=")
	if concept_path.is_empty():
		concept_path = DEFAULT_CONCEPT
	var concept: Image = Image.load_from_file(concept_path)
	if concept == null or concept.is_empty():
		_refuse("no concept image to set beside the renders")
		return false
	for pair in figures + heads:
		if pair[1] == null:
			_refuse("%s is missing, so the sheet cannot be composed" % pair[0])
			return false
	for image in fp:
		if image == null:
			_refuse("a first-person render is missing, so the sheet cannot be composed")
			return false
	if strip == null:
		_refuse("the walk strip is missing, so the sheet cannot be composed")
		return false

	var cells: Array = []
	var y: float = float(SHEET_MARGIN)
	# Row one: the concept, then the full body front, three-quarter and back.
	var row_h: float = 600.0
	var concept_w: float = 780.0
	var concept_scaled: Image = concept.duplicate() as Image
	concept_scaled.resize(int(concept_w), int(concept_w * float(concept.get_height()) / float(concept.get_width())), Image.INTERPOLATE_LANCZOS)
	cells.append({"label": "concept (owner)", "image": concept_scaled, "at": Vector2(SHEET_MARGIN, y)})
	var x: float = SHEET_MARGIN + concept_w + SHEET_GAP
	for pair in figures:
		cells.append({"label": pair[0], "image": _column(pair[1] as Image, Vector2i(int(row_h * 0.5), int(row_h))), "at": Vector2(x, y)})
		x += row_h * 0.5 + SHEET_GAP
	y += row_h + SHEET_CAPTION_H + SHEET_GAP

	# Row two: the head close-ups, front, three-quarter, profile and back.
	var head_h: float = 300.0
	x = SHEET_MARGIN
	for pair in heads:
		cells.append({"label": pair[0], "image": _square(pair[1] as Image, int(head_h)), "at": Vector2(x, y)})
		x += head_h + SHEET_GAP
	y += head_h + SHEET_CAPTION_H + SHEET_GAP

	# Row three: the first-person ranges, one frame each, the eye's own lens.
	var fp_w: float = 480.0
	var fp_h: float = 270.0
	x = SHEET_MARGIN
	var labels: Array[String] = ["first person 0.9 m", "first person 2 m", "first person 5 m"]
	for i in fp.size():
		var shot: Image = (fp[i] as Image).duplicate() as Image
		shot.resize(int(fp_w), int(fp_h), Image.INTERPOLATE_LANCZOS)
		cells.append({"label": labels[i], "image": shot, "at": Vector2(x, y)})
		x += fp_w + SHEET_GAP
	y += fp_h + SHEET_CAPTION_H + SHEET_GAP

	# Row four: the walk clip, eight phases.
	var strip_h: float = 300.0
	var strip_w: float = strip_h * float(strip.get_width()) / float(strip.get_height())
	var strip_scaled: Image = strip.duplicate() as Image
	strip_scaled.resize(int(strip_w), int(strip_h), Image.INTERPOLATE_LANCZOS)
	cells.append({"label": "walk, %d phases" % WALK_PHASES, "image": strip_scaled, "at": Vector2(SHEET_MARGIN, y)})
	y += strip_h + SHEET_CAPTION_H + SHEET_MARGIN

	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(SHEET_WIDTH, int(y))
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = SHEET_BACKGROUND
	backdrop.size = Vector2(SHEET_WIDTH, y)
	view.add_child(backdrop)
	for cell in cells:
		var image: Image = cell["image"] as Image
		var at: Vector2 = cell["at"] as Vector2
		var shown: Vector2 = Vector2(image.get_width(), image.get_height())
		var rect: TextureRect = TextureRect.new()
		rect.texture = ImageTexture.create_from_image(image)
		rect.position = at
		rect.size = shown
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		view.add_child(rect)
		var label: Label = Label.new()
		label.text = cell["label"] as String
		label.position = Vector2(at.x, at.y + shown.y + 4.0)
		label.add_theme_font_override("font", Chrome.font())
		label.add_theme_font_size_override("font_size", CAPTION_SIZE)
		label.add_theme_color_override("font_color", CAPTION_COLOUR)
		view.add_child(label)
	root.add_child(view)
	await process_frame
	await process_frame
	await process_frame
	var sheet: Image = view.get_texture().get_image()
	view.queue_free()
	if sheet == null or sheet.is_empty():
		_refuse("the sheet has no pixels, run with a display")
		return false
	_save(sheet, "sheet")
	return true


# A portrait crop of `frame`'s centre column, scaled to `to`.
func _column(frame: Image, to: Vector2i) -> Image:
	var column: Image = frame.get_region(Rect2i((frame.get_width() - STRIP_COLUMN_PX) / 2, 0, STRIP_COLUMN_PX, frame.get_height()))
	column.resize(to.x, to.y, Image.INTERPOLATE_LANCZOS)
	return column


# A square crop of the frame's centre, scaled to `side`: the head, on the head frames.
func _square(frame: Image, side: int) -> Image:
	var crop: int = int(frame.get_height() * 2 / 3)
	var square: Image = frame.get_region(Rect2i((frame.get_width() - crop) / 2, (frame.get_height() - crop) / 2, crop, crop))
	square.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return square


# --- output ---------------------------------------------------------------------------------------

func _save(image: Image, file_name: String) -> void:
	var path: String = _out.path_join("%s.png" % file_name)
	var saved: Error = image.save_png(path)
	if saved != OK:
		_refuse("could not write %s (error %d)" % [path, saved])
		return
	_saved.append(path)
	print("SURVIVOR_SHOT %s" % path)


func _write_info(glb: String, world: Variant, size: Vector2i) -> void:
	var info: Dictionary = {
		"glb": glb,
		"glb_sha256": FileAccess.get_sha256(glb),
		"glb_bytes": FileAccess.get_file_as_bytes(glb).size(),
		"tick": int(world.tick),
		"size": [size.x, size.y],
		"lens": {"full_fov": FULL_FOV, "head_fov": HEAD_FOV, "first_person_fov": FP_FOV},
		"first_person_ranges_m": FP_RANGES_M,
		"walk_phases": WALK_PHASES,
		"shots": _saved,
	}
	var file: FileAccess = FileAccess.open(_out.path_join("review.json"), FileAccess.WRITE)
	if file == null:
		_refuse("could not write review.json")
		return
	file.store_string(JSON.stringify(info, "  "))


func _out_dir() -> String:
	var given: String = _arg("--out=")
	if not given.is_empty():
		return given
	var d: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = "%04d-%02d-%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	return DEFAULT_OUT_ROOT.path_join(stamp)


# --- arguments ------------------------------------------------------------------------------------

func _glb_path() -> String:
	var given: String = _arg("--glb=")
	if not given.is_empty():
		return given
	var env: String = OS.get_environment("SURVIVOR_GLB")
	if not env.is_empty():
		return env
	return DEFAULT_GLB


func _size() -> Vector2i:
	var given: String = _arg("--size=")
	if given.is_empty():
		return DEFAULT_SIZE
	var parts: PackedStringArray = given.split("x")
	if parts.size() != 2:
		return DEFAULT_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))


func _tick() -> int:
	var given: String = _arg("--tick=")
	if given.is_empty():
		return Clock.tick_on_day(1, 0.5)
	return int(given)


# The value after a `--name=` argument the driver was given, or "" when it was not.
func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


# --- helpers --------------------------------------------------------------------------------------

static func _player_in(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _player_in(child)
		if found != null:
			return found
	return null


static func _metres_label(metres: float) -> String:
	if is_equal_approx(metres, roundf(metres)):
		return "%dm" % int(metres)
	return "%sm" % ("%.1f" % metres).replace(".", "_")


func _refuse(message: String) -> void:
	push_error("SURVIVOR REFUSED %s" % message)
	_failed = true

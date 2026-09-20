extends SceneTree

const ROOT="res://art/simplyzombies-ui/"
var checks: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		return
	checks.append(message)

func _initialize() -> void:
	call_deferred("validate")

func validate() -> void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
	for sprite in manifest.sprites:
		var texture=load(ROOT+sprite.path) as Texture2D
		check(texture!=null,"Texture loads: "+sprite.id)
		check(texture.get_size()==Vector2(sprite.size[0],sprite.size[1]),"Texture dimensions: "+sprite.id)
	for asset in manifest.assets:
		if asset.category=="chrome":
			var style=load(ROOT+"styles/"+asset.id+".tres") as StyleBoxTexture
			check(style!=null and style.texture!=null,"StyleBoxTexture loads: "+asset.id)
			check(style.get_texture_margin(SIDE_LEFT)+style.get_texture_margin(SIDE_RIGHT)<style.texture.get_width(),"Positive horizontal center: "+asset.id)
			check(style.get_texture_margin(SIDE_TOP)+style.get_texture_margin(SIDE_BOTTOM)<style.texture.get_height(),"Positive vertical center: "+asset.id)
		elif asset.category=="animation":
			var frames=load(ROOT+"animations/"+asset.id+".tres") as SpriteFrames
			check(frames!=null and frames.has_animation(asset.id),"Animation loads: "+asset.id)
			check(frames.get_frame_count(asset.id)==4,"Four frames: "+asset.id)
			check(frames.get_animation_speed(asset.id)==asset.fps,"Animation speed: "+asset.id)
			check(frames.get_animation_loop(asset.id)==asset.loop,"Animation loop: "+asset.id)
	var theme=load(ROOT+"theme.tres") as Theme
	check(theme!=null,"Theme loads")
	check(theme.default_font.antialiasing==TextServer.FONT_ANTIALIASING_NONE,"Pixel font disables smoothing")
	check(theme.has_stylebox("focus","Button"),"Keyboard focus texture provided")
	check(theme.has_icon("checked","CheckBox"),"Checkbox art provided")
	check(load(ROOT+"ui_skin.gd")!=null,"CanvasItem bridge parses")
	var scene=load(ROOT+"demo/demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.motion.size()==4,"Demo creates all four animations")
	scene.set_reduced_motion(true)
	for sprite in scene.motion:
		check(not sprite.is_playing(),"Reduced motion stops: "+sprite.animation)
		check(sprite.frame==(2 if sprite.animation==&"saved_tick" else 0),"Reduced motion static frame: "+sprite.animation)
	scene.set_reduced_motion(false)
	for sprite in scene.motion: check(sprite.is_playing(),"Animation resumes: "+sprite.animation)
	scene.play_one_shot(scene.motion[2])
	check(scene.motion[2].frame==0 and scene.motion[2].is_playing(),"One-shot restarts")
	await create_timer(0.6).timeout
	check(not scene.motion[2].is_playing(),"One-shot stops at end")
	check(scene.motion[2].frame==3,"One-shot holds last frame")
	var report={"engine":Engine.get_version_info().string,"headless":true,"checks_passed":checks.size(),"checks":checks}
	var file=FileAccess.open(ROOT+"docs/godot-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	scene.queue_free()
	await process_frame
	print("GODOT_VALIDATION_OK: ",checks.size()," checks")
	quit()

extends Control
## Standalone native resource demo. No game state or game save files are touched.

const ROOT = "res://art/simplyzombies-ui/"
var motion: Array[AnimatedSprite2D] = []
var reduce_motion := false
var status: Label

func label_at(parent: Node, text: String, rect: Rect2, font_size: int = 22, muted: bool = false) -> Label:
	var node=Label.new()
	node.text=text
	node.position=rect.position
	node.size=rect.size
	node.add_theme_font_size_override("font_size",font_size)
	if muted: node.theme_type_variation="MutedLabel"
	parent.add_child(node)
	return node

func panel_at(rect: Rect2, title: String, id: String = "panel_standard") -> Panel:
	var node=Panel.new()
	node.position=rect.position;node.size=rect.size
	node.add_theme_stylebox_override("panel",load(ROOT+"styles/"+id+".tres"))
	add_child(node)
	label_at(node,title,Rect2(16,8,rect.size.x-32,36),26)
	return node

func button_at(parent: Node, text: String, rect: Rect2, variant: String = "") -> Button:
	var node=Button.new()
	node.text=text;node.position=rect.position;node.size=rect.size
	node.theme_type_variation=variant
	parent.add_child(node)
	node.pressed.connect(func(): status.text="Preview action: "+text)
	return node

func _ready() -> void:
	theme=load(ROOT+"theme.tres")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	label_at(self,"simplyZOMBIES  /  UI FIELD KIT",Rect2(20,10,800,38),32)
	label_at(self,"Native Godot controls · mouse, keyboard focus, scalable frames",Rect2(20,48,720,28),20,true)
	status=label_at(self,"Select a control to try its states.",Rect2(20,555,920,28),20,true)
	var buttons=panel_at(Rect2(20,92,288,222),"BUTTONS & FOCUS")
	button_at(buttons,"Resume",Rect2(16,56,122,40))
	button_at(buttons,"Drop",Rect2(150,56,122,40),"DangerButton")
	var disabled=button_at(buttons,"Unavailable",Rect2(16,108,256,40));disabled.disabled=true
	var toggle=button_at(buttons,"Selected",Rect2(16,160,256,40))
	toggle.toggle_mode=true;toggle.button_pressed=true
	var settings=panel_at(Rect2(324,92,288,222),"SETTINGS")
	var checkbox=CheckBox.new()
	checkbox.text="Reduced motion";checkbox.position=Vector2(16,52);checkbox.size=Vector2(256,38)
	settings.add_child(checkbox)
	checkbox.toggled.connect(set_reduced_motion)
	var switch=CheckButton.new()
	switch.text="Ambient audio";switch.position=Vector2(16,104);switch.size=Vector2(256,38);switch.button_pressed=true
	settings.add_child(switch)
	switch.toggled.connect(func(on: bool): status.text="Ambient audio preview: "+("on" if on else "off"))
	var slider=HSlider.new()
	slider.position=Vector2(20,160);slider.size=Vector2(248,30);slider.value=65
	slider.tooltip_text="Volume preview"
	settings.add_child(slider)
	var slots=panel_at(Rect2(628,92,312,222),"SLOTS & GLYPHS")
	var group=ButtonGroup.new()
	var glyphs=["head","eyes","face","vest","torso","back","primary","secondary","legs","feet"]
	for i in range(glyphs.size()):
		var slot=button_at(slots,"",Rect2(16+(i%5)*56,56+(i/5)*62,48,48),"SlotButton")
		slot.toggle_mode=true;slot.button_group=group;slot.button_pressed=i==0
		slot.icon=load(ROOT+"glyphs/glyph_"+glyphs[i]+".png")
		slot.tooltip_text=glyphs[i].capitalize()
		slot.pressed.connect(func(): status.text="Selected equipment slot: "+slot.tooltip_text)
	var animations=panel_at(Rect2(20,330,920,208),"MOTION")
	var names=["focus_pulse","busy","item_ping","saved_tick"]
	for i in range(names.size()):
		var sprite=AnimatedSprite2D.new()
		sprite.sprite_frames=load(ROOT+"animations/"+names[i]+".tres")
		sprite.animation=names[i];sprite.position=Vector2(116+i*228,90);sprite.scale=Vector2(2,2)
		animations.add_child(sprite);motion.append(sprite)
		sprite.play()
		label_at(animations,names[i].replace("_"," ").capitalize(),Rect2(28+i*228,128,192,28),22)
		if i>=2:
			var replay=button_at(animations,"Replay",Rect2(28+i*228,160,176,32))
			replay.pressed.connect(func(): play_one_shot(sprite))
	label_at(animations,"Loop",Rect2(28,163,176,28),20,true)
	label_at(animations,"Loop",Rect2(256,163,176,28),20,true)

func play_one_shot(sprite: AnimatedSprite2D) -> void:
	if reduce_motion:
		sprite.stop();sprite.frame=2 if sprite.animation==&"saved_tick" else 0
	else:
		sprite.stop();sprite.play()

func set_reduced_motion(enabled: bool) -> void:
	reduce_motion=enabled
	for sprite in motion:
		if enabled:
			sprite.stop();sprite.frame=2 if sprite.animation==&"saved_tick" else 0
		else:
			sprite.play()
	status.text="Reduced motion enabled." if enabled else "UI animations enabled."

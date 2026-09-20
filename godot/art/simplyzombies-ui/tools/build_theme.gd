extends SceneTree

const ROOT = "res://art/simplyzombies-ui/"

func style(id: String) -> StyleBoxTexture:
	return load(ROOT + "styles/" + id + ".tres") as StyleBoxTexture

func icon(id: String) -> Texture2D:
	return load(ROOT + "controls/control_" + id + ".png") as Texture2D

func _initialize() -> void:
	var font = load(ROOT + "fonts/VT323-Regular.ttf").duplicate() as FontFile
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.multichannel_signed_distance_field = false
	font.hinting = TextServer.HINTING_NONE
	assert(ResourceSaver.save(font, ROOT + "fonts/VT323-Pixel.res") == OK)
	var theme = Theme.new()
	theme.default_font = load(ROOT + "fonts/VT323-Pixel.res")
	theme.default_font_size = 22
	for type in ["Label", "Button", "CheckBox", "CheckButton", "TabBar", "LineEdit"]:
		theme.set_color("font_color", type, Color("c8c2a6"))
		theme.set_color("font_hover_color", type, Color("e4d9ad"))
		theme.set_color("font_focus_color", type, Color("e4d9ad"))
		theme.set_color("font_pressed_color", type, Color("c99a3f"))
		theme.set_color("font_disabled_color", type, Color("807a63"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state,"Button",style("button_"+state))
	theme.set_constant("outline_size","Button",0)
	theme.set_constant("h_separation","Button",6)
	theme.set_stylebox("panel","Panel",style("panel_standard"))
	theme.set_stylebox("panel","PanelContainer",style("panel_standard"))
	theme.set_stylebox("panel","PopupPanel",style("panel_dialog"))
	theme.set_type_variation("DangerButton","Button")
	theme.set_stylebox("normal","DangerButton",style("button_danger"))
	theme.set_type_variation("SlotButton","Button")
	for states in [["normal","empty"],["hover","hover"],["pressed","selected"],["disabled","disabled"],["hover_pressed","selected"]]:
		theme.set_stylebox(states[0],"SlotButton",style("slot_"+states[1]))
	theme.set_stylebox("focus","SlotButton",style("button_focus"))
	theme.set_type_variation("InsetPanel","Panel")
	theme.set_stylebox("panel","InsetPanel",style("panel_inset"))
	theme.set_type_variation("MutedLabel","Label")
	theme.set_color("font_color","MutedLabel",Color("807a63"))
	for type in ["CheckBox","CheckButton"]:
		for state in ["normal","hover","pressed","disabled","hover_pressed"]:
			theme.set_stylebox(state,type,StyleBoxEmpty.new())
		theme.set_stylebox("focus",type,style("button_focus"))
	if true:
		for pair in [["unchecked","checkbox_off"],["checked","checkbox_on"],["checked_disabled","checkbox_disabled"],["unchecked_disabled","checkbox_off"],["radio_unchecked","radio_off"],["radio_checked","radio_on"],["indeterminate","checkbox_mixed"]]:
			theme.set_icon(pair[0],"CheckBox",icon(pair[1]))
		for pair in [["unchecked","toggle_off"],["checked","toggle_on"],["checked_disabled","toggle_on"],["unchecked_disabled","toggle_off"]]:
			theme.set_icon(pair[0],"CheckButton",icon(pair[1]))
	for pair in [["tab_unselected","tab_normal"],["tab_selected","tab_selected"],["tab_hovered","tab_hover"],["tab_disabled","button_disabled"],["tab_focus","button_focus"]]:
		theme.set_stylebox(pair[0],"TabBar",style(pair[1]))
	theme.set_color("font_selected_color","TabBar",Color("e4d9ad"))
	theme.set_color("font_unselected_color","TabBar",Color("807a63"))
	var rail=StyleBoxTexture.new()
	rail.texture=icon("slider_rail")
	rail.texture_margin_left=3; rail.texture_margin_right=3
	theme.set_stylebox("slider","HSlider",rail)
	for state in ["grabber","grabber_highlight","grabber_disabled"]:
		theme.set_icon(state,"HSlider",icon("scroll_thumb_hover" if state=="grabber_highlight" else "scroll_thumb"))
	theme.set_stylebox("grabber_area","HSlider",StyleBoxEmpty.new())
	theme.set_stylebox("grabber_area_highlight","HSlider",StyleBoxEmpty.new())
	var scroll=StyleBoxTexture.new()
	scroll.texture=icon("scroll_track")
	scroll.texture_margin_left=3;scroll.texture_margin_right=3
	scroll.texture_margin_top=5;scroll.texture_margin_bottom=5
	theme.set_stylebox("scroll","VScrollBar",scroll)
	for state in ["grabber","grabber_highlight","grabber_pressed"]:
		var thumb=StyleBoxTexture.new()
		thumb.texture=icon("scroll_thumb_hover" if state!="grabber" else "scroll_thumb")
		thumb.texture_margin_left=3;thumb.texture_margin_right=3
		thumb.texture_margin_top=4;thumb.texture_margin_bottom=4
		theme.set_stylebox(state,"VScrollBar",thumb)
	theme.set_stylebox("normal","LineEdit",style("panel_inset"))
	theme.set_stylebox("focus","LineEdit",style("button_focus"))
	theme.set_stylebox("panel","TooltipPanel",style("panel_tooltip"))
	theme.set_color("font_color","TooltipLabel",Color("c8c2a6"))
	assert(ResourceSaver.save(theme,ROOT+"theme.tres")==OK)
	print("THEME_BUILT: textured controls, pixel font, variants")
	quit()

extends Node
## Dev tool: render a prototype of the new "Tactical HUD" UI language (sleek, cyan
## primary + amber secondary) to renders/hud_prototype.png — for design review only.
## Run on the GPU:  flatpak run --filesystem=home org.godotengine.Godot --path . \
##   --resolution 96x96 tools/hud_prototype_runner.tscn

const T := preload("res://scripts/hud/hud_tokens.gd")
const OUT := "res://renders/hud_prototype.png"
const W := 1366
const H := 800


class GridBg extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.05, 0.072))
		var step := 44.0
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.035), 1.0)
			x += step
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.035), 1.0)
			y += step


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(_build())
	get_tree().root.add_child(vp)
	for _i in range(24):
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var img := vp.get_texture().get_image()
	img.save_png(OUT)
	print("HUD_RENDERED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()


func _label(text: String, font: FontFile, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _accent_line() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var amber := ColorRect.new()
	amber.color = T.AMBER
	amber.custom_minimum_size = Vector2(26, T.ACCENT_LINE)
	var cyan := ColorRect.new()
	cyan.color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.85)
	cyan.custom_minimum_size = Vector2(0, T.ACCENT_LINE)
	cyan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(amber)
	h.add_child(cyan)
	return h


## A framed HUD panel; returns its content VBox to fill.
func _panel(title: String, index: String, pos: Vector2, psize: Vector2) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", T.panel_style())
	pc.position = pos
	pc.custom_minimum_size = psize
	pc.size = psize
	_root.add_child(pc)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	var m := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(s, 12)
	m.add_child(outer)
	pc.add_child(m)

	var header := HBoxContainer.new()
	header.add_child(_label(title, T.head_font(), 16, T.TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(_label(index, T.mono_font(), 12, T.AMBER))
	outer.add_child(header)
	outer.add_child(_accent_line())

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	outer.add_child(content)
	return content


func _button(text: String, styles: Dictionary, accent_text: Color = T.TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, T.BUTTON_H)
	b.add_theme_font_override("font", T.body_font())
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", styles.normal)
	b.add_theme_stylebox_override("hover", styles.hover)
	b.add_theme_stylebox_override("pressed", styles.pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", accent_text)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


var _root: Control


func _build() -> Control:
	_root = GridBg.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.size = Vector2(W, H)

	# Top status bar
	var bar := PanelContainer.new()
	var bar_style := T.panel_style()
	bar_style.shadow_size = 0
	bar.add_theme_stylebox_override("panel", bar_style)
	bar.position = Vector2(16, 14)
	bar.custom_minimum_size = Vector2(W - 32, 30)
	bar.size = Vector2(W - 32, 30)
	_root.add_child(bar)
	var bar_box := HBoxContainer.new()
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 12)
	bm.add_theme_constant_override("margin_right", 12)
	bm.add_child(bar_box)
	bar.add_child(bm)
	bar_box.add_child(_label("NIEMANDSLAND", T.head_font(), 14, T.CYAN))
	bar_box.add_child(_label("   //   ROUND ", T.mono_font(), 13, T.TEXT_MUTED))
	bar_box.add_child(_label("01", T.mono_font(), 13, T.AMBER))
	bar_box.add_child(_label("   //   ", T.mono_font(), 13, T.TEXT_MUTED))
	bar_box.add_child(_label("P1 ACTIVE", T.mono_font(), 13, T.CYAN))
	var bsp := Control.new()
	bsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_box.add_child(bsp)
	bar_box.add_child(_label("FPS 60  ·  OBJ 27", T.mono_font(), 13, T.TEXT_MUTED))

	# COMMAND panel (left)
	var cmd := _panel("COMMAND", "/// CMD", Vector2(20, 56), Vector2(248, 372))
	cmd.add_child(_button("  IMPORT OPR ARMY", T.primary_button()))
	cmd.add_child(_button("  IMPORT WGS GAME", T.ghost_button()))
	cmd.add_child(_button("  MAP LAYOUT", T.ghost_button()))
	cmd.add_child(_button("  SORT TABLE", T.ghost_button()))
	cmd.add_child(_button("  SAVE / LOAD", T.ghost_button()))
	cmd.add_child(_button("  NEXT ROUND  ›  02", T.amber_button(), T.AMBER))
	var cmd_div := ColorRect.new()
	cmd_div.color = T.HAIRLINE
	cmd_div.custom_minimum_size = Vector2(0, 1)
	cmd.add_child(cmd_div)
	cmd.add_child(_label("CLEAR TABLE", T.body_font(), 13, T.DANGER))

	# UNIT card (bottom-left)
	var unit := _panel("HIVE WARRIORS", "[3] · P1", Vector2(20, 444), Vector2(330, 200))
	var stat := HBoxContainer.new()
	stat.add_theme_constant_override("separation", 14)
	stat.add_child(_label("Q 4+", T.mono_font(), 14, T.CYAN))
	stat.add_child(_label("D 4+", T.mono_font(), 14, T.CYAN))
	stat.add_child(_label("40mm", T.mono_font(), 14, T.TEXT_MUTED))
	stat.add_child(_label("TOUGH 3", T.mono_font(), 14, T.AMBER))
	unit.add_child(stat)
	unit.add_child(_label("2x Razor Claws  (A2)", T.body_font(), 13, T.TEXT))
	unit.add_child(_label("Hive Bond · Strider", T.body_font(), 12, T.TEXT_MUTED))
	var wounds := HBoxContainer.new()
	wounds.add_theme_constant_override("separation", 4)
	wounds.add_child(_label("WOUNDS ", T.mono_font(), 12, T.TEXT_MUTED))
	for i in range(3):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 8)
		pip.color = T.AMBER if i < 2 else Color(1, 1, 1, 0.12)
		wounds.add_child(pip)
	unit.add_child(wounds)

	# CONTROLS readout (right)
	var ctl := _panel("CONTROLS", "/// REF", Vector2(W - 320, 56), Vector2(300, 196))
	for line in ["WASD      MOVE CAMERA", "L-CLICK   SELECT / DRAG", "R-CLICK   RADIAL MENU",
			"1-9       ARRANGE AT CURSOR", "DEL       REMOVE", "CTRL+Z    UNDO"]:
		ctl.add_child(_label(line, T.mono_font(), 13, T.TEXT_MUTED))

	# DICE panel (right)
	var dice := _panel("DICE", "D6", Vector2(W - 320, 268), Vector2(300, 360))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	for n in ["1", "2", "3", "5", "10"]:
		var c := _button(n, T.ghost_button())
		c.custom_minimum_size = Vector2(46, 38)
		c.alignment = HORIZONTAL_ALIGNMENT_CENTER
		chips.add_child(c)
	dice.add_child(chips)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", T.sunken_style())
	well.custom_minimum_size = Vector2(0, 110)
	var well_box := VBoxContainer.new()
	well_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var res := _label("17", T.head_font(), 52, T.AMBER)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_box.add_child(res)
	var sub := _label("5 × D6  ·  ⚅⚅⚄⚃⚀", T.mono_font(), 13, T.TEXT_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_box.add_child(sub)
	well.add_child(well_box)
	dice.add_child(well)
	dice.add_child(_button("  ROLL  ›", T.primary_button()))

	return _root

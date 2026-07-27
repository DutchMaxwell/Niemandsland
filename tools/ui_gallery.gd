extends Node
## UI gallery — pops every window/panel of the game one after another and saves a PNG of each.
## Purpose: SEE the dialogs side by side to judge whether they look like one product (UI audit).
##
## Needs a real display (Godot's headless renderer draws nothing):
##   DISPLAY=:0 godot --path . res://tools/ui_gallery.tscn
## (a SCENE, not -s: the dialog classes need the project's autoloads, e.g. ThemeManager)
## Output: user://ui_gallery/NN_name.png, path printed at the end.
##
## Dialogs with their own class are INSTANTIATED FOR REAL (pixel truth). The ones main.gd builds
## inline are rebuilt here with the same widgets, strings and helpers — noted per shot in the
## printed manifest so nothing pretends to be more authentic than it is.

const OUT_DIR := "user://ui_gallery"
const SHOT_SIZE := Vector2i(1280, 800)

var _root: Window
var _layer: CanvasLayer
var _index := 0
var _manifest: Array = []


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	_root = get_tree().root
	_root.size = SHOT_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# A neutral dark ground so the panels' own chrome is what we judge, not the desktop behind.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_layer = CanvasLayer.new()
	_root.add_child(_layer)

	await _shoot_real()
	await _shoot_inline()

	print("GALLERY_DIR %s" % ProjectSettings.globalize_path(OUT_DIR))
	for m in _manifest:
		print("SHOT %s" % m)
	get_tree().quit(0)


## One frame of settle time, then grab the viewport and write it out.
func _capture(name: String, kind: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := _root.get_texture().get_image()
	_index += 1
	var file := "%02d_%s.png" % [_index, name]
	img.save_png("%s/%s" % [OUT_DIR, file])
	_manifest.append("%s | %s" % [file, kind])


func _clear() -> void:
	for c in _layer.get_children():
		c.queue_free()
	for c in _root.get_children():
		if c is Window and c != _root:
			c.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Dialogs that own a class — instantiated for real.
# ---------------------------------------------------------------------------
func _shoot_real() -> void:
	var theme: Theme = ThemeManager.get_current_theme()

	var table := TableSizeDialog.new()
	_root.add_child(table)
	if table.has_method("open"):
		table.open()
	elif table.has_method("popup_centered"):
		table.popup_centered()
	await _capture("table_size", "real class TableSizeDialog")
	await _clear()

	# These three only draw once opened FOR something, so give them a stand-in model/unit.
	var model := ModelInstance.new()
	model.is_alive = true
	var unit := GameUnit.new()
	unit.unit_id = "gallery"
	unit.unit_properties = {"name": "Prosecution Sisters", "player_id": 1, "quality": 4,
		"defense": 4, "size": 5, "special_rules": ["Caster(2)"]}
	unit.models.append(model)

	# Control-based overlays: they anchor their own CHILDREN to the full rect but have no size
	# themselves inside a bare CanvasLayer, so stretch them first or they draw nothing.
	var wounds := WoundsDialog.new()
	_layer.add_child(wounds)
	wounds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wounds.open(model)
	await _capture("wounds", "real class WoundsDialog (opened for a model)")
	await _clear()

	var casts := CastsDialog.new()
	_layer.add_child(casts)
	casts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	casts.open(unit)
	await _capture("casts", "real class CastsDialog (opened for a caster unit)")
	await _clear()

	var marker := MarkerDialog.new()
	_layer.add_child(marker)
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.open_for_unit(unit)
	await _capture("marker", "real class MarkerDialog (opened for a unit)")
	await _clear()

	var loading := LoadingOverlay.new()
	_layer.add_child(loading)
	if loading.has_method("set_label"):
		loading.set_label("LOADING 3D MODELS")
	await _capture("loading_overlay", "real class LoadingOverlay")
	await _clear()

	# AcceptDialog-based net masks share one builder; shoot the host variant.
	var host := AcceptDialog.new()
	host.title = "Host Online Game"
	host.dialog_text = ""
	if theme != null:
		host.theme = theme
	_root.add_child(host)
	host.popup_centered()
	await _capture("net_host_plain", "AcceptDialog shell (NetDialog fills it at runtime)")
	await _clear()


# ---------------------------------------------------------------------------
# The prompts main.gd builds inline — rebuilt with the same widgets and strings.
# ---------------------------------------------------------------------------
func _shoot_inline() -> void:
	var theme: Theme = ThemeManager.get_current_theme()
	var width := 420

	var cases: Array = [
		{"n": "solo_saves", "t": "Incoming fire!", "conf": true,
			"b": "Assault Brothers hits Prosecution Sisters 4 times with Heavy Rifle.\nRoll your defense saves (AP 1 → save on 4+).",
			"ok": "Roll 4 saves", "cancel": ""},
		{"n": "solo_strike_back", "t": "Strike back?", "conf": true,
			"b": "Assault Brothers charges Prosecution Sisters.\nStrike back?", "ok": "Strike back", "cancel": "Hold"},
		{"n": "solo_versatile", "t": "Versatile Attack", "conf": true,
			"b": "Heavy Rifle is Versatile (target over 9\").\nChoose the mode for this volley:",
			"ok": "AP(+1) — recommended", "cancel": "+1 to hit"},
		{"n": "solo_pull_back", "t": "Pull Back 1\"", "conf": true,
			"b": "Neither unit was destroyed. Drag the models back 1\", then click OK.", "ok": "OK", "cancel": ""},
		{"n": "solo_consolidate", "t": "Consolidate 3\"", "conf": true,
			"b": "Prosecution Sisters survived. You may consolidate up to 3\".\nClick OK when you are done.",
			"ok": "OK", "cancel": ""},
		{"n": "solo_cast_window", "t": "Cast window", "conf": true,
			"b": "High Sister can still cast BEFORE this attack.\nCast first, or attack without casting?",
			"ok": "Cast first", "cancel": "Attack without casting"},
		{"n": "solo_game_over", "t": "Game over", "conf": false,
			"b": "4 rounds played.\n\nObjectives held:\n  You: 2\n  NACHTMAHR: 1\n  Neutral: 0\n\nYou win — NACHTMAHR yields.",
			"ok": "OK", "cancel": ""},
	]
	for c in cases:
		var dlg: AcceptDialog = ConfirmationDialog.new() if bool(c["conf"]) else AcceptDialog.new()
		dlg.title = str(c["t"])
		dlg.dialog_text = str(c["b"])
		dlg.ok_button_text = str(c["ok"])
		if dlg is ConfirmationDialog:
			if str(c["cancel"]).is_empty():
				(dlg as ConfirmationDialog).get_cancel_button().hide()
			else:
				(dlg as ConfirmationDialog).cancel_button_text = str(c["cancel"])
		if theme != null:
			dlg.theme = theme
		dlg.min_size = Vector2i(width, 0)
		_root.add_child(dlg)
		dlg.popup_centered()
		await _capture(str(c["n"]), "inline in main.gd — rebuilt with the shipped theme + width")
		await _clear()

	# The AI-opponent dialog carries real widgets, so build those too.
	var ai := ConfirmationDialog.new()
	ai.title = "AI Opponent"
	ai.min_size = Vector2i(width, 220)
	if theme != null:
		ai.theme = theme
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	for line in ["NACHTMAHR builds its own list.", "Faction:"]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)
	var opt := OptionButton.new()
	opt.add_item("Human Defense Force")
	box.add_child(opt)
	var l2 := Label.new()
	l2.text = "Points:"
	l2.add_theme_font_size_override("font_size", 13)
	box.add_child(l2)
	var opt2 := OptionButton.new()
	opt2.add_item("1000 points")
	box.add_child(opt2)
	ai.add_child(box)
	ai.ok_button_text = "Build & deploy list"
	_root.add_child(ai)
	ai.popup_centered()
	await _capture("ai_opponent", "inline in main.gd — rebuilt with real widgets")
	await _clear()

	# The deployment strip: the central solo surface, now panel-styled.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -18.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	var lab := Label.new()
	lab.text = "Place ONE unit in your zone, then hand over. In reserve: Winged Warriors, Snipers."
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 15)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size.x = 580
	vb.add_child(lab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for t in ["✔ Unit placed", "No units left — NACHTMAHR deploys the rest"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size.x = 280
		UiPolish.primary_button(b)
		row.add_child(b)
	_layer.add_child(panel)
	await _capture("deployment_strip", "inline in main.gd — rebuilt with the shipped panel style")
	await _clear()

	# The three top-centre status lanes together — the collision this pass resolved.
	for spec in [["NACHTMAHR is taking its turn…", 12], ["Assault Brothers fires at Prosecution Sisters", 40],
			["Waiting for Player 2 to finish loading…", 68]]:
		var l3 := Label.new()
		l3.text = str(spec[0])
		l3.add_theme_font_size_override("font_size", 18)
		l3.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
		l3.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l3.add_theme_constant_override("outline_size", 4)
		l3.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(spec[1]))
		_layer.add_child(l3)
	await _capture("status_lanes", "the three top-centre lanes at once (banner / toast / peer-busy)")
	await _clear()

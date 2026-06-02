extends Node
## Dev tool: render ONE example menu screenshot to renders/<name>.png, then quit.
## Runs as a NORMAL scene (tools/render_runner.tscn) so the autoload globals
## (ThemeManager, ...) are available — a `-s` SceneTree script does not get them,
## which breaks every themed dialog. One menu per process also keeps software-GL
## window capture fast and isolated (multiple OS windows per process stall under
## Mesa llvmpipe). Not shipped with the game.
##
## Usage (loop over names in the shell):
##   xvfb-run -a godot --path . --display-driver x11 --rendering-driver opengl3 \
##     --resolution 1366x900 tools/render_runner.tscn -- <menu_name>
##
## menu_name: table_size_dialog | opr_import_dialog | wgs_import_dialog | lighting_panel
##          | wounds_dialog | marker_dialog | unit_card | map_layout | startup_menu

const OUT_DIR := "res://renders"
const BG := Color(0.06, 0.06, 0.10)  # app background so glass panels read


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var args := OS.get_cmdline_user_args()
	var name := args[0] if args.size() > 0 else ""
	await _settle(4)

	match name:
		"table_size_dialog":
			await _window(name, TableSizeDialog.new())
		"opr_import_dialog":
			await _window(name, OPRImportDialog.new())
		"wgs_import_dialog":
			await _window(name, WGSImportDialog.new())
		"lighting_panel":
			await _window(name, load("res://scripts/lighting_panel.gd").new())
		"wounds_dialog":
			var wd := WoundsDialog.create_simple()
			await _modal(name, wd, func(): wd.open(_sample_unit().models[0]))
		"marker_dialog":
			var md := MarkerDialog.create_simple()
			await _modal(name, md, func(): md.open_for_model(_sample_unit().models[0]))
		"casts_dialog":
			var cd := CastsDialog.create_simple()
			await _modal(name, cd, func(): cd.open(_sample_unit()))
		"model_info_popup":
			var mip := ModelInfoPopup.create_simple()
			await _modal(name, mip, func(): mip.open(_sample_unit().models[0]))
		"unit_card":
			var card: Control = load("res://scenes/unit_card.tscn").instantiate()
			await _control(name, card, Vector2i(420, 560))
		"map_layout":
			var ml: Control = load("res://scenes/map_layout.tscn").instantiate()
			await _control(name, ml, Vector2i(1366, 860))
		"startup_menu":
			var sm: Control = load("res://scenes/startup_menu.tscn").instantiate()
			await _control(name, sm, Vector2i(1366, 860))
		_:
			print("UNKNOWN menu: '%s'" % name)
	get_tree().quit()


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save(img: Image, name: String) -> void:
	if img == null or img.is_empty():
		print("SKIP %s (empty image)" % name)
		return
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("RENDERED %s (%dx%d)" % [name, img.get_width(), img.get_height()])


## Window dialog: add, show, capture its own viewport texture.
func _window(name: String, win: Window) -> void:
	if win == null:
		print("SKIP %s (null)" % name)
		return
	# Embed the dialog into the root viewport so its frame + drop shadow render over a
	# dark backdrop (captures the dialog as it actually appears, not just its content).
	get_tree().root.gui_embed_subwindows = true
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(bg)
	get_tree().root.add_child(win)
	win.popup_centered()
	await _settle(16)
	_save(get_tree().root.get_texture().get_image(), name)


## Full-screen Control modal: backdrop + modal in the root viewport, run open() to
## populate, capture the root viewport.
func _modal(name: String, node: Control, opener: Callable) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(bg)
	get_tree().root.add_child(node)
	if opener.is_valid():
		opener.call()
	await _settle(14)
	_save(get_tree().root.get_texture().get_image(), name)


## Control / scene into a fixed SubViewport over a dark backdrop.
func _control(name: String, node: Control, size: Vector2i) -> void:
	if node == null:
		print("SKIP %s (null)" % name)
		return
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	vp.add_child(node)
	get_tree().root.add_child(vp)
	await _settle(80)  # let intro/fade-in animations (e.g. the start menu) finish
	_save(vp.get_texture().get_image(), name)


## A small demo unit so data-driven dialogs have something to show.
func _sample_unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "demo"
	u.unit_properties = {
		"name": "Hive Warriors", "custom_name": "", "size": 3,
		"quality": 4, "defense": 4, "cost": 115,
		"special_rules": ["Tough(3)", "Hive Bond"],
		"base_size_round": 40, "player_id": 1,
		"attached_heroes": [], "attached_to": null,
	}
	for i in range(3):
		var m := ModelInstance.new()
		m.unit = u
		m.model_index = i
		m.wounds_max = 3
		m.wounds_current = 2 if i == 0 else 3
		m.properties = {
			"weapons": [{"name": "Razor Claws", "attacks": 2}],
			"equipment": [], "special_rules": ["Tough(3)", "Hive Bond"], "tough": 3,
		}
		u.models.append(m)
	return u

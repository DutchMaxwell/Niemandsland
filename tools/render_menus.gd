extends SceneTree
## Dev tool: render example screenshots of the game's menus/dialogs to renders/.
## Run headless-with-software-GL:
##   xvfb-run -a godot --path . --display-driver x11 --rendering-driver opengl3 \
##     --resolution 1366x900 -s tools/render_menus.gd
## Not shipped with the game; purely for design review.

const OUT_DIR := "res://renders"
const BG := Color(0.06, 0.06, 0.10)  # app background so glass panels read


func _initialize() -> void:
	_run()


func _settle(n: int) -> void:
	for _i in range(n):
		await process_frame


func _save(img: Image, name: String) -> void:
	if img == null or img.is_empty():
		print("SKIP %s (empty image)" % name)
		return
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("RENDERED %s (%dx%d)" % [name, img.get_width(), img.get_height()])


## Render a Window-based dialog: add, show, capture its own viewport texture.
func _render_window(name: String, win: Window) -> void:
	if win == null:
		print("SKIP %s (null)" % name)
		return
	win.transparent_bg = false
	root.add_child(win)
	win.position = Vector2i(40, 40)
	win.show()
	await _settle(18)
	_save(win.get_texture().get_image(), name)
	win.queue_free()
	await process_frame


## Render a Control/scene into a fixed SubViewport over a dark backdrop.
func _render_control(name: String, node: Control, size: Vector2i) -> void:
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
	if node.theme == null:
		var glass = load("res://scripts/glassmorphism_theme.gd")
		node.theme = glass.get_theme()
	vp.add_child(node)
	root.add_child(vp)
	await _settle(18)
	_save(vp.get_texture().get_image(), name)
	vp.queue_free()
	await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _settle(4)

	# --- Window-based dialogs (no constructor args) ---
	await _render_window("table_size_dialog", TableSizeDialog.new())
	await _render_window("opr_import_dialog", OPRImportDialog.new())
	await _render_window("wgs_import_dialog", WGSImportDialog.new())
	var lp: Window = load("res://scripts/lighting_panel.gd").new()
	await _render_window("lighting_panel", lp)

	# --- Control modals with a known open() API, fed sample data ---
	var unit := _sample_unit()
	var wounds := WoundsDialog.new()
	root.add_child(wounds)
	if wounds.has_method("open"):
		wounds.open(unit.models[0])
	await _settle(12)
	_save(wounds.get_viewport().get_texture().get_image(), "wounds_dialog")
	wounds.queue_free()
	await process_frame

	var marker := MarkerDialog.new()
	root.add_child(marker)
	if marker.has_method("open_for_model"):
		marker.open_for_model(unit.models[0])
	await _settle(12)
	_save(marker.get_viewport().get_texture().get_image(), "marker_dialog")
	marker.queue_free()
	await process_frame

	# --- Scenes ---
	var card_scene: Control = load("res://scenes/unit_card.tscn").instantiate()
	await _render_control("unit_card", card_scene, Vector2i(420, 560))

	var map_scene: Control = load("res://scenes/map_layout.tscn").instantiate()
	await _render_control("map_layout", map_scene, Vector2i(1366, 860))

	var menu_scene: Control = load("res://scenes/startup_menu.tscn").instantiate()
	await _render_control("startup_menu", menu_scene, Vector2i(1366, 860))

	print("RENDER_DONE")
	quit()


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

extends SceneTree
## One-shot generator for the bundled tutorial board (assets/tutorial/tutorial_board.nml),
## produced by the REAL pipeline end to end — no synthesized data:
##  · Armies: the maintainer's official tutorial lists, imported through the production
##    TTS parser (import_from_tts_json == import_from_share_link's parser, incl. the
##    army-book faction/rules fetch). Fixtures are the exact /api/tts bodies, fetched once:
##      P1 Battle Brothers  https://army-forge.onepagerules.com/share?id=__FfT0jOYHtc
##      P2 Robot Legions    https://army-forge.onepagerules.com/share?id=gLi7he9YFjEt
##  · Models: the real spawn path (R2/ctex resolution); the build FAILS if any model
##    falls back to a placeholder peg or a faction folder is missing.
##  · Terrain: the game's own OPR-guideline autogen (map_layout_editor) with FRONT_LINE
##    (12") deployment zones — prefab ruins/forests/containers/dangerous, not boxes.
##  · Save: the normal SaveManager, so cards/trays/rules restore like any player save.
##
## Run (then copy the printed user:// file into assets/tutorial/):
##   flatpak run org.godotengine.Godot --path <wt> --headless -s res://tools/tutorial_board_builder.gd

const P1_FIXTURE := "res://assets/tutorial/tutorial_army_p1.json"  # Battle Brothers (player)
const P2_FIXTURE := "res://assets/tutorial/tutorial_army_p2.json"  # Robot Legions (enemy)
const OUT_PATH := "user://tutorial_board.nml"
const MAX_BOOT_FRAMES := 900
const DROP_SETTLE_S := 4.0
const LAYOUT_SEED := 20260710  # freeze the autogen result; bump to reroll the layout
const FRONT_LINE_DEPLOYMENT := 1  # MapLayout.DeploymentType.FRONT_LINE (12" long edges)
# Deployment rows (6x4 ft table: x within ±0.915 m, z within ±0.61 m; 12" zone starts
# at |z| >= 0.305). Player south, enemy north, two rows each.
const P1_ROWS: Array = [[Vector3(-0.55, 0.0, 0.40), Vector3(0.0, 0.0, 0.40), Vector3(0.55, 0.0, 0.40)],
	[Vector3(-0.55, 0.0, 0.53), Vector3(0.0, 0.0, 0.53), Vector3(0.55, 0.0, 0.53)]]
const P2_ROWS: Array = [[Vector3(-0.66, 0.0, -0.40), Vector3(-0.22, 0.0, -0.40), Vector3(0.22, 0.0, -0.40), Vector3(0.66, 0.0, -0.40)],
	[Vector3(-0.66, 0.0, -0.53), Vector3(-0.22, 0.0, -0.53), Vector3(0.22, 0.0, -0.53), Vector3(0.66, 0.0, -0.53)]]


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_build.call_deferred()


func _build() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	var main: Node = await _await_main()
	if main == null:
		printerr("BOARD-FAIL: main.tscn did not become ready")
		quit(1)
		return
	var army_manager: Node = main.get("opr_army_manager")
	var save_manager: Node = main.get("save_manager")
	var layout_editor: Control = main.get("map_layout_editor")
	if army_manager == null or save_manager == null or layout_editor == null:
		printerr("BOARD-FAIL: managers missing (army=%s save=%s layout=%s)" % [army_manager, save_manager, layout_editor])
		quit(1)
		return

	# --- Armies through the production import + spawn path ---
	if not await _import_and_spawn(army_manager, P1_FIXTURE, 1):
		return
	if not await _import_and_spawn(army_manager, P2_FIXTURE, 2):
		return
	await create_timer(DROP_SETTLE_S).timeout  # let the tray drop animation settle

	# --- Validation: every model must be a REAL mini (imported mesh), never a peg ---
	var real_models := 0
	var peg_models := 0
	for unit in army_manager.get("game_units").values():
		for model in unit.models:
			if model == null or not is_instance_valid(model.node):
				continue
			if _has_imported_mesh(model.node):
				real_models += 1
			else:
				peg_models += 1
				printerr("BOARD-PEG: %s model %d has no imported mesh" % [unit.get_name(), model.model_index])
	if peg_models > 0 or real_models == 0:
		printerr("BOARD-FAIL: %d placeholder peg(s), %d real models — model resolution broken" % [peg_models, real_models])
		quit(1)
		return

	# --- Terrain through the game's own OPR autogen (frozen seed) + 12" zones ---
	seed(LAYOUT_SEED)
	layout_editor._generate_terrain_layout()
	layout_editor.deployment_type = FRONT_LINE_DEPLOYMENT
	layout_editor._rebuild_derived()
	layout_editor._emit_layout_update()
	layout_editor.deployment_type_changed.emit(FRONT_LINE_DEPLOYMENT)
	await process_frame
	var piece_count: int = layout_editor.placed_pieces.size()
	var cell_count: int = layout_editor.grid_cells.size()
	var object_count: int = layout_editor.placed_objects.size()
	if piece_count < 5:
		printerr("BOARD-FAIL: terrain autogen produced only %d pieces" % piece_count)
		quit(1)
		return

	# --- Deployment: slide the spawned unit blocks into the two 12" zones ---
	_deploy_units(army_manager)
	await process_frame

	var err: Error = await save_manager.save_game(OUT_PATH)
	if err != OK:
		printerr("BOARD-FAIL: save_game returned %d" % err)
		quit(1)
		return
	var unit_count: int = army_manager.get("game_units").size()
	printerr("BOARD-OK: %d units / %d real models (0 pegs) | terrain: %d prefab pieces, %d cells, %d decorations | -> %s" % [
		unit_count, real_models, piece_count, cell_count, object_count,
		ProjectSettings.globalize_path(OUT_PATH)])
	quit(0)


## Import one fixture through the production TTS parser and spawn it. False on failure.
func _import_and_spawn(army_manager: Node, fixture: String, player_id: int) -> bool:
	var text := FileAccess.get_file_as_string(fixture)
	if text.is_empty():
		printerr("BOARD-FAIL: fixture missing/empty: %s" % fixture)
		quit(1)
		return false
	printerr("BOARD: importing player %d (%s)…" % [player_id, fixture.get_file()])
	var army = await army_manager.api_client.import_from_tts_json(text)
	if army == null or army.units.is_empty():
		printerr("BOARD-FAIL: player %d import produced no units" % player_id)
		quit(1)
		return false
	if String(army.faction_folder).is_empty():
		printerr("BOARD-FAIL: player %d army has no faction_folder (army-book fetch failed) — models would degrade to pegs" % player_id)
		quit(1)
		return false
	printerr("BOARD: player %d = '%s' (%s), %d units, %d pts" % [
		player_id, army.name, army.faction_folder, army.units.size(), army.points])
	army.player_id = player_id
	army_manager.get("armies")[player_id] = army
	await army_manager.spawn_army(army)
	return true


func _await_main() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		var scene := current_scene
		if scene != null and scene.get("opr_army_manager") != null \
				and scene.get("save_manager") != null and scene.get("map_layout_editor") != null:
			return scene
	return null


## True when the model wrapper carries an imported mesh (ArrayMesh) anywhere in its
## subtree. The placeholder peg is built from primitive CylinderMeshes only.
func _has_imported_mesh(node: Node) -> bool:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh is ArrayMesh:
			return true
		for child in current.get_children():
			stack.append(child)
	return false


## Slide each unit's model block from its army tray into its deployment zone (rows of
## unit centroids; whole-block x/z translation keeps the spawned formation intact).
func _deploy_units(army_manager: Node) -> void:
	var p1_units: Array = []
	var p2_units: Array = []
	for unit in army_manager.get("game_units").values():
		var pid: int = int(unit.unit_properties.get("player_id", 0))
		if pid == 1:
			p1_units.append(unit)
		elif pid == 2:
			p2_units.append(unit)
	p1_units.sort_custom(func(a, b) -> bool: return a.get_name() < b.get_name())
	p2_units.sort_custom(func(a, b) -> bool: return a.get_name() < b.get_name())
	_place_rows(p1_units, P1_ROWS)
	_place_rows(p2_units, P2_ROWS)


func _place_rows(units: Array, rows: Array) -> void:
	var spots: Array[Vector3] = []
	for row in rows:
		for spot in row:
			spots.append(spot)
	for i in units.size():
		if i < spots.size():
			_move_unit_to(units[i], spots[i])


func _move_unit_to(unit, table_pos: Vector3) -> void:
	var nodes: Array[Node3D] = []
	var centroid := Vector3.ZERO
	for model in unit.models:
		if model != null and is_instance_valid(model.node):
			nodes.append(model.node)
			centroid += model.node.global_position
	if nodes.is_empty():
		return
	centroid /= nodes.size()
	var delta := table_pos - centroid
	delta.y = 0.0  # translate on the table plane only; resting height stays as spawned
	for node in nodes:
		node.global_position += delta

extends SceneTree
## One-shot generator for the bundled tutorial board (assets/tutorial/tutorial_board.nml).
## Boots the REAL main.tscn in harness mode, imports the two bundled Army Forge JSON
## fixtures offline (player 1: Battle Brothers ranged + Assault Brothers melee + Support
## Brothers; player 2: one enemy Battle Brothers squad as the dummy target), deploys the
## units onto the table (south band vs north band), adds two terrain pieces, then saves
## via the normal SaveManager — so the board is a REAL .nml that loads through the
## standard pending_load_path seam with real unit cards, trays and coherency.
##
## Run (then copy the printed user:// file into assets/tutorial/):
##   flatpak run org.godotengine.Godot --path <wt> --headless -s res://tools/tutorial_board_builder.gd

const P1_LIST := "res://assets/tutorial/tutorial_army_p1.json"
const P2_LIST := "res://assets/tutorial/tutorial_army_p2.json"
const OUT_PATH := "user://tutorial_board.nml"
const MAX_BOOT_FRAMES := 900
const DROP_SETTLE_S := 4.0
# Deployment (6x4 ft table = 1.83 x 1.22 m): player south band, enemy north band.
const P1_Z := 0.35
const P2_Z := -0.35
const P1_XS: Array[float] = [-0.5, 0.0, 0.5]
const TERRAIN_SPOTS: Array[Vector3] = [Vector3(-0.3, 0.0, -0.05), Vector3(0.35, 0.0, 0.1)]


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
	var object_manager: Node = main.get("object_manager")
	var save_manager: Node = main.get("save_manager")
	if army_manager == null or object_manager == null or save_manager == null:
		printerr("BOARD-FAIL: managers missing (army=%s object=%s save=%s)" % [army_manager, object_manager, save_manager])
		quit(1)
		return

	# Import both fixture lists offline and spawn them (models resolve from cache/R2;
	# uncached+offline falls back to procedural tokens — the board stays valid either way).
	printerr("BOARD: importing player 1 list…")
	await army_manager.import_army_for_player(P1_LIST, 1)
	printerr("BOARD: importing player 2 list…")
	await army_manager.import_army_for_player(P2_LIST, 2)
	var armies: Dictionary = army_manager.get("armies")
	if not (armies.has(1) and armies.has(2)):
		printerr("BOARD-FAIL: army import failed (have players: %s)" % str(armies.keys()))
		quit(1)
		return
	printerr("BOARD: spawning armies…")
	await army_manager.spawn_army(armies[1])
	await army_manager.spawn_army(armies[2])
	await create_timer(DROP_SETTLE_S).timeout  # let the tray drop animation settle

	_deploy_units(army_manager)
	for spot in TERRAIN_SPOTS:
		object_manager.spawn_terrain(spot, false)
	await process_frame

	var err: Error = await save_manager.save_game(OUT_PATH)
	if err != OK:
		printerr("BOARD-FAIL: save_game returned %d" % err)
		quit(1)
		return
	var unit_count: int = army_manager.get("game_units").size()
	printerr("BOARD-OK: %d units + %d terrain saved -> %s" % [
		unit_count, TERRAIN_SPOTS.size(), ProjectSettings.globalize_path(OUT_PATH)])
	quit(0)


func _await_main() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		var scene := current_scene
		if scene != null and scene.get("opr_army_manager") != null \
				and scene.get("object_manager") != null and scene.get("save_manager") != null:
			return scene
	return null


## Slide each unit's model block from its army tray onto the table: player 1 spread
## across the south band, player 2 centred in the north band. Whole-block translation
## (x/z only) keeps the spawned coherent formation intact.
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

	for i in p1_units.size():
		var x: float = P1_XS[i] if i < P1_XS.size() else 0.0
		_move_unit_to(p1_units[i], Vector3(x, 0.0, P1_Z))
	for unit in p2_units:
		_move_unit_to(unit, Vector3(0.0, 0.0, P2_Z))


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

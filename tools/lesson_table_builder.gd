extends SceneTree
## Build a lesson table through the game's import, spawn and save paths.
## Run: godot --path <wt> --headless -s res://tools/lesson_table_builder.gd -- chapter=S-01

const MAX_BOOT_FRAMES := 900
const DROP_SETTLE_S := 4.0
const INCH := 0.0254
var _id := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("chapter="):
			_id = arg.trim_prefix("chapter=")
	if LessonRecipes.recipe(_id).is_empty():
		_fail("unknown chapter")
		return
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_build.call_deferred()

func _build() -> void:
	var recipe := LessonRecipes.recipe(_id)
	change_scene_to_file("res://scenes/main.tscn")
	var main := await _await_main()
	if main == null:
		_fail("main.tscn did not become ready")
		return
	var manager: OPRArmyManager = main.opr_army_manager
	var layout: Control = main.map_layout_editor
	main._set_table_size(recipe.size_feet)
	main.table.set_biome(recipe.biome)
	if recipe.deployment >= 0:
		layout.deployment_type = recipe.deployment
		layout._rebuild_derived()
		layout._emit_layout_update()
		layout.deployment_type_changed.emit(recipe.deployment)
	var placements: Dictionary = {}
	for side in recipe.sides:
		var body := FileAccess.get_file_as_string(side.fixture)
		if body.is_empty():
			_fail("fixture missing: " + side.fixture)
			return
		var army: OPRApiClient.OPRArmy = await manager.api_client.import_from_tts_json(body)
		if army == null or army.faction_folder.is_empty():
			_fail("army import or faction folder missing: " + side.fixture)
			return
		var chosen: Array[OPRApiClient.OPRUnit] = []
		for pick in side.units:
			var matches: Array[OPRApiClient.OPRUnit] = []
			for unit in army.units:
				if unit.name == pick.name:
					matches.append(unit)
			var nth := int(pick.nth) - 1
			if nth < 0 or nth >= matches.size():
				_fail("unit not found: %s #%d" % [pick.name, pick.nth])
				return
			chosen.append(matches[nth])
			placements[matches[nth]] = pick
		army.units = chosen
		army.player_id = int(side.player)
		manager.armies[army.player_id] = army
		await manager.spawn_army(army)
	await create_timer(DROP_SETTLE_S).timeout
	var model_count := 0
	for opr_unit in placements:
		var unit: GameUnit = manager.get_game_unit(opr_unit)
		if unit == null:
			_fail("spawned unit missing")
			return
		unit.unit_properties["lesson_tag"] = placements[opr_unit].tag
		var spot: Vector2 = placements[opr_unit].at_in
		_move_unit_to(unit, Vector3(spot.x * INCH, 0, spot.y * INCH))
		for model in unit.models:
			if not is_instance_valid(model.node) or not _has_imported_mesh(model.node):
				_fail("placeholder peg in " + unit.get_name())
				return
			model_count += 1
	manager.set_game_phase(int(recipe.phase))
	manager.set_current_round(int(recipe.round))
	await process_frame
	var path := "user://lesson_%s.nml" % _id
	var err: Error = await main.save_manager.save_game(path)
	if err != OK:
		_fail("save_game returned %d" % err)
		return
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(state) != TYPE_DICTIONARY:
		_fail("saved table is invalid JSON")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot compact saved table")
		return
	file.store_string(JSON.stringify(state))
	file.close()
	print("LESSON-OK %s: %d units / %d models -> %s" % [_id, placements.size(), model_count, ProjectSettings.globalize_path(path)])
	quit(0)

func _await_main() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.get("opr_army_manager") != null and current_scene.get("save_manager") != null:
			return current_scene
	return null

func _has_imported_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).mesh is ArrayMesh:
			return true
	return false

func _move_unit_to(unit: GameUnit, spot: Vector3) -> void:
	var nodes: Array[Node3D] = []
	var centre := Vector3.ZERO
	for model in unit.models:
		if is_instance_valid(model.node):
			nodes.append(model.node)
			centre += model.node.global_position
	if nodes.is_empty():
		return
	var delta := spot - centre / nodes.size()
	delta.y = 0.0
	for node in nodes:
		node.global_position += delta


func _fail(reason: String) -> void:
	printerr("LESSON-FAIL %s: %s" % [_id, reason])
	quit(1)

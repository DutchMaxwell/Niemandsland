extends SceneTree
## Build a lesson table through the game's import, spawn and save paths.
## Run: godot --path <wt> --headless -s res://tools/lesson_table_builder.gd -- chapter=S-01

const MAX_BOOT_FRAMES := 900
const DROP_SETTLE_S := 4.0
const INCH := 0.0254
const CELL_IN := 3.0   # terrain grid cell size (TerrainOverlay.GRID_SIZE_INCHES)
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
	if recipe.has("cells"):
		_apply_cells(layout, recipe.cells)
	if recipe.has("objectives_in"):
		layout.set_objectives_from_table_inches(recipe.objectives_in)
		layout.objectives_changed.emit(layout.mission_objectives)
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
			# A visible custom name (recipe "label") so the lesson text and the unit on the table agree
			# (the player must never be told a lesson tag — see SpielschuleLessons).
			var label := String(pick.get("label", ""))
			if not label.is_empty():
				matches[nth].custom_name = label
			pick["player"] = int(side.player)
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
		_apply_unit_state(manager, unit, placements[opr_unit], int(placements[opr_unit].get("player", 0)))
	manager.set_game_phase(int(recipe.phase))
	manager.set_current_round(int(recipe.round))
	if recipe.has("ai_slots"):
		var slots: Dictionary = {}
		for pid in recipe.get("ai_slots", []):
			slots[int(pid)] = true
		main.solo_ai_slots = slots
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


## Paint the recipe's terrain rectangles (world-centred inches) into the layout's free cells — the
## painting source of truth — then rebuild the derived grid/overlay (as the old board builder does).
func _apply_cells(layout: Control, cells: Array) -> void:
	var dims: Vector2i = layout._calculate_grid_dimensions()
	var half := Vector2(dims) / 2.0
	for rect in cells:
		var t := int(rect.get("type", 0))
		var a: Vector2 = rect.get("from_in", Vector2.ZERO)
		var b: Vector2 = rect.get("to_in", Vector2.ZERO)
		var x0 := int(floor(minf(a.x, b.x) / CELL_IN) + half.x)
		var x1 := int(floor(maxf(a.x, b.x) / CELL_IN) + half.x)
		var y0 := int(floor(minf(a.y, b.y) / CELL_IN) + half.y)
		var y1 := int(floor(maxf(a.y, b.y) / CELL_IN) + half.y)
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				layout.free_cells[Vector2i(cx, cy)] = t
	layout._rebuild_derived()   # also emits the layout update — no second _emit_layout_update()


## Start a lesson unit in the state its step teaches: Shaken, Fatigued, or with parked casualties.
func _apply_unit_state(manager: OPRArmyManager, unit: GameUnit, pick: Dictionary, player: int) -> void:
	if bool(pick.get("shaken", false)):
		unit.is_shaken = true
	if bool(pick.get("fatigued", false)):
		unit.is_fatigued = true
	var dead := int(pick.get("dead", 0))
	if dead > 0:
		# Park from the FRONT (model 0 up): the per-model loadout puts a unit's special weapon on the
		# last carrier (e.g. the Battle Brothers' single Plasma Rifle sits on model 9 of 10), so parking
		# the tail would strip the special weapon first. Lessons that keep the special weapon shooting
		# (S-07's 4 Heavy Rifles + 1 Plasma) rely on the front park. Count-only lessons are unaffected.
		var models := unit.models
		for i in range(0, mini(dead, models.size())):
			var node: Node3D = models[i].node
			if is_instance_valid(node):
				manager.set_loose_model_dead(node, player, true, unit.unit_id)
			# set_loose_model_dead parks the NODE (a meta + a dead slot); the saved table reads the
			# ModelInstance flags, so kill the model itself too or the load shows it alive again.
			var mi := models[i] as ModelInstance
			if mi != null:
				mi.is_alive = false
				mi.wounds_current = 0
	# `wounds` pre-places whole wounds on a SINGLE-model Tough unit (Tough(3) with 2 wounds = below
	# half strength) — `dead` only parks whole models, so a lone partially-wounded model needs this.
	var wounds := int(pick.get("wounds", 0))
	if wounds > 0:
		if unit.models.size() != 1:
			_fail("wounds needs a single-model unit: " + unit.get_name())
			return
		var lone := unit.models[0]
		lone.wounds_current = maxi(int(lone.wounds_max) - wounds, 0)
		lone.is_alive = lone.wounds_current > 0

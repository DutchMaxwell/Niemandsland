extends GdUnitTestSuite
## Frontage-cycle hotkey (Shift+F): OPRArmyManager.cycle_selected_regiment_frontage
## walks the selected RegimentTray blocks through the frontage cycle (5 -> 4 -> 3 ->
## 2 -> 1 -> 5, AoF:R v3.5.1 p.6 "Unit Formations"), re-ranks the block in place,
## syncs the Regiment companion + unit_properties, and pushes an undoable
## FrontageAction. No network (single-player path); MP is exercised by the soak harness.

const CELL := 0.025
const APPROX := Vector3(0.0001, 0.0001, 0.0001)

const OPRArmyManagerScript = preload("res://scripts/opr_army_manager.gd")


func _fps(n: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(Vector2(CELL, CELL))
	return a


func _game_unit(n: int, unit_id: String = "test_regiment") -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = unit_id
	gu.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	for i in range(n):
		var mi := ModelInstance.new()
		var node := Node3D.new()
		add_child(node)
		auto_free(node)
		mi.node = node
		mi.is_alive = true
		mi.unit = gu
		gu.models.append(mi)
	return gu


func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


## Minimal OPRArmyManager wired for single-player (no network, no undo) cycle tests.
func _army_manager() -> OPRArmyManager:
	var om: Node3D = auto_free(Node3D.new())
	om.name = "ObjectManager"
	add_child(om)
	var am: OPRArmyManager = auto_free(OPRArmyManagerScript.new())
	am.name = "OPRArmyManager"
	om.add_child(am)
	am.object_manager = om
	return am


## Build a formed regiment (tray + Regiment companion set) for `gu` at `frontage`.
func _formed_regiment(am: OPRArmyManager, gu: GameUnit, frontage: int) -> RegimentTray:
	var members := RegimentTray.collect_members(gu)
	var tray := _tray()
	tray.form(members.nodes, members.footprints, frontage)
	var regiment := Regiment.new(gu, tray, frontage)
	tray.set_meta("regiment", regiment)
	gu.unit_properties["frontage"] = frontage
	am.regiments[gu.unit_id] = regiment
	return tray


# ===== cycle_selected_regiment_frontage =====


func test_cycle_advances_frontage_and_reranks() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 5)

	var cycled: int = am.cycle_selected_regiment_frontage([tray])
	assert_int(cycled).is_equal(1)
	assert_int(tray.frontage).is_equal(4)
	assert_int(int(gu.unit_properties["frontage"])).is_equal(4)
	# The Regiment companion is kept in sync.
	var regiment := tray.get_meta("regiment") as Regiment
	assert_int(regiment.frontage).is_equal(4)
	# Models re-laid at frontage 4 (two rows of 4 + 2, centred rear rank).
	var offs := RegimentFormation.local_offsets(_fps(10), 4)
	assert_vector((gu.models[0].node as Node3D).position).is_equal_approx(offs[0], APPROX)


func test_cycle_wraps_from_one_to_five() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 1)

	am.cycle_selected_regiment_frontage([tray])
	assert_int(tray.frontage).is_equal(5)


func test_cycle_skips_non_regiment_selection() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 5)
	# A loose Node3D in the selection must be ignored, the regiment still cycled.
	var loose: Node3D = auto_free(Node3D.new())
	add_child(loose)

	var cycled: int = am.cycle_selected_regiment_frontage([loose, tray])
	assert_int(cycled).is_equal(1)
	assert_int(tray.frontage).is_equal(4)


func test_cycle_no_op_when_only_one_live_model() -> void:
	var am := _army_manager()
	var gu := _game_unit(1)
	var tray := _formed_regiment(am, gu, 1)

	var cycled: int = am.cycle_selected_regiment_frontage([tray])
	assert_int(cycled).is_equal(0)
	assert_int(tray.frontage).is_equal(1)


func test_cycle_preserves_tray_transform() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 5)
	tray.global_position = Vector3(1.5, 0.0, -2.0)
	tray.rotation.y = 0.75
	var pos_before := tray.global_position
	var rot_before := tray.rotation.y

	am.cycle_selected_regiment_frontage([tray])

	assert_vector(tray.global_position).is_equal_approx(pos_before, APPROX)
	assert_float(tray.rotation.y).is_equal_approx(rot_before, 0.0001)


# ===== FrontageAction (undo/redo) =====


func test_frontage_action_undo_restores_width() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 5)

	var action := UndoManager.FrontageAction.new(tray, gu, 5, 3, null, 0)
	action.redo()
	assert_int(tray.frontage).is_equal(3)
	action.undo()
	assert_int(tray.frontage).is_equal(5)
	assert_int(int(gu.unit_properties["frontage"])).is_equal(5)


func test_frontage_action_redo_reapplies_width() -> void:
	var am := _army_manager()
	var gu := _game_unit(10)
	var tray := _formed_regiment(am, gu, 5)

	var action := UndoManager.FrontageAction.new(tray, gu, 5, 2, null, 0)
	action.redo()
	assert_int(tray.frontage).is_equal(2)
	action.undo()
	assert_int(tray.frontage).is_equal(5)
	action.redo()
	assert_int(tray.frontage).is_equal(2)
	# Regiment companion stayed in sync through redo.
	var regiment := tray.get_meta("regiment") as Regiment
	assert_int(regiment.frontage).is_equal(2)

extends GdUnitTestSuite

const MAIN := preload("res://scripts/main.gd")

class DropMain extends "res://scripts/main.gd":
	func _solo_tray_roll(_count: int, _target: int, _owner: String, kind: String = "attack", _purpose: String = "") -> Array:
		return [1, 6] if kind == "jump" else [6]

func test_skirmish_flying_passes_and_failed_jump_ends_activation() -> void:
	var f := _fixture(DropMain)
	add_child(f.model)
	f.main.battle_log = auto_free(BattleLog.new())
	f.unit.unit_properties.merge({"game_system": "gff", "special_rules": ["Flying"]})
	var model := ModelInstance.new()
	model.node = f.model
	f.unit.models.append(model)
	f.army.start_game()
	var moves := [{"node": f.model, "inches": 4.0, "from_raw": Vector3(0, 0.1016, 0), "path": PackedVector2Array([Vector2.ZERO, Vector2(0.1, 0)])}]
	await f.main._on_units_dropped(moves)
	assert_int(f.main.battle_log.entries().size()).is_equal(1)
	assert_bool(f.unit.is_activated).is_false()
	f.unit.unit_properties.special_rules = []
	await f.main._on_units_dropped(moves)
	assert_bool(f.unit.is_activated).is_true()


func _fixture(script = MAIN) -> Dictionary:
	var main: Node3D = auto_free(script.new())
	var objects: ObjectManager = auto_free(ObjectManager.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var unit: GameUnit = auto_free(GameUnit.new())
	unit.unit_id = "own_unit"
	unit.unit_properties = {"player_id": 1, "name": "Own Unit"}
	var model: Node3D = auto_free(Node3D.new())
	model.set_meta("game_unit", unit)
	objects._selected_objects = [model]
	main.object_manager = objects
	main.opr_army_manager = army
	return {"main": main, "objects": objects, "army": army, "unit": unit, "model": model}


func test_plain_click_in_play_does_not_mark_unit_moved() -> void:
	var f := _fixture()
	(f["army"] as OPRArmyManager).start_game()
	(f["main"] as Node3D)._on_unit_moved()
	assert_bool((f["unit"] as GameUnit).unit_properties.has("moved_round")).is_false()


func test_deployment_drag_does_not_mark_round_one_move() -> void:
	var f := _fixture()
	assert_bool((f["army"] as OPRArmyManager).is_deployment_phase()).is_true()
	(f["main"] as Node3D)._on_units_dropped([{"node": f["model"], "inches": 4.0}])
	(f["main"] as Node3D)._on_unit_moved()
	assert_bool((f["unit"] as GameUnit).unit_properties.has("moved_round")).is_false()


func test_only_moved_unit_is_stamped_during_play() -> void:
	var f := _fixture()
	var other: GameUnit = auto_free(GameUnit.new())
	other.unit_id = "selected_but_still"
	other.unit_properties = {"player_id": 1, "name": "Selected But Still"}
	var other_model: Node3D = auto_free(Node3D.new())
	other_model.set_meta("game_unit", other)
	(f["objects"] as ObjectManager)._selected_objects.append(other_model)
	(f["army"] as OPRArmyManager).start_game()
	(f["main"] as Node3D)._on_units_dropped([{"node": f["model"], "inches": 4.0}])
	(f["main"] as Node3D)._on_unit_moved()
	assert_int(int((f["unit"] as GameUnit).unit_properties.get("moved_round", -1))).is_equal(1)
	assert_bool(other.unit_properties.has("moved_round")).is_false()


func test_takeback_restores_previous_moved_round_stamp() -> void:
	var f := _fixture()
	var main := f["main"] as Node3D
	var unit := f["unit"] as GameUnit
	var model := f["model"] as Node3D
	var trails: MoveTrails = auto_free(MoveTrails.new())
	var undo: UndoManager = auto_free(UndoManager.new())
	main.move_trails = trails
	main.undo_manager = undo
	(f["army"] as OPRArmyManager).start_game()
	model.global_position = Vector3(0.2, 0, 0)
	var moves := [{"node": model, "from": Vector3.ZERO, "to": model.global_position,
		"from_raw": Vector3.ZERO, "from_rot": 0.0, "inches": 0.2 / 0.0254,
		"path": PackedVector2Array([Vector2.ZERO, Vector2(0.2, 0)]),
		"radius_m": 0.0125, "drop_id": 1}]
	main._on_trails_dropped(moves, true)
	main._on_units_dropped(moves)
	assert_int(int(unit.unit_properties.get("moved_round", -1))).is_equal(1)
	assert_str(undo.undo_for(0)).contains("Take back")
	assert_bool(unit.unit_properties.has("moved_round")).is_false()
	assert_vector(model.global_position).is_equal(Vector3.ZERO)


func test_a_step_over_3in_logs_an_impassable_warning() -> void:
	# D5a: non-strict never blocks the drag, but the drop's battle log still flags the
	# rule (GF p.11) — a logged warning, not a hard stop.
	var f := _fixture()
	var main := f["main"] as Node3D
	var log_node: BattleLog = auto_free(BattleLog.new())
	main.battle_log = log_node
	(f["army"] as OPRArmyManager).start_game()
	main._on_battle_log_dropped([{"node": f["model"], "inches": 6.0, "arc_in": 6.0, "climb_in": 6.0}])
	var texts: Array = []
	for e in log_node.entries():
		texts.append(str(e["text"]))
	assert_array(texts).contains(["Own Unit climbs 6.0\" — over 3\", impassable (GF p.11)"])

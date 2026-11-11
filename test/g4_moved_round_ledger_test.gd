extends GdUnitTestSuite
## G4-H-MOVED — the act state the table hands to the core (and records) names the round each unit last moved.
## The table stamps `unit_properties["moved_round"]` on every executed move and reads it for Artillery (a target
## that moved this round keeps no -1 to hit), Entrenched and the stationary alias penalty. The act state carried
## no such field, so the core read every unit as "never moved". The exporter (`AiActRecorder._ledger_of`) writes
## the stamp from EPOCH_73_V36; below it the export is byte-identical to before.
##
## The stamp is written the way the game writes it: a real drop through `main.gd` (`_on_units_dropped` +
## `_on_unit_moved`), not a hand-set property.

const MAIN := preload("res://scripts/main.gd")

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


func _fixture() -> Dictionary:
	var main: Node3D = auto_free(MAIN.new())
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
	army.start_game()
	return {"main": main, "unit": unit, "model": model}


## The unit's player drags it 4" during play: the table stamps the round it moved in.
func _move_the_unit(f: Dictionary) -> void:
	(f["main"] as Node3D)._on_units_dropped([{"node": f["model"], "inches": 4.0}])
	(f["main"] as Node3D)._on_unit_moved()


func test_the_exported_state_names_the_round_a_unit_moved() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var f := _fixture()
	_move_the_unit(f)
	var ledger := AiActRecorder._ledger_of(f["unit"] as GameUnit)
	assert_int(int(ledger.get("moved_round", -1))) \
		.override_failure_message("G4-H-MOVED: the act state does not name the round the unit moved, so the core reads it as never moved.") \
		.is_equal(1)


func test_a_unit_that_has_not_moved_exports_no_key() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var f := _fixture()
	assert_bool(AiActRecorder._ledger_of(f["unit"] as GameUnit).has("moved_round")).is_false()


func test_below_epoch_73_the_export_is_unchanged() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	var f := _fixture()
	_move_the_unit(f)
	assert_bool(AiActRecorder._ledger_of(f["unit"] as GameUnit).has("moved_round")).is_false()

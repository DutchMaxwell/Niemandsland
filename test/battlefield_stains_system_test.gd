extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 15: the oil pool (and the fires of a burning wreck) is a grimdark look. A fantasy table's machine
## leaves blood like any other model; gf and gff leave what they always did. A look only - the stain is not a rule. Also pinned:
## the auto-generate of terrain (`_generate_terrain_layout`) emits terrain TYPES only, so it needs no system gate (the looks
## follow steps 12 - 14). Red proof: on main a machine removed from an aofs table still left oil and fire.

const MainScript := preload("res://scripts/main.gd")


class RecordingStains extends BattlefieldStains:
	var calls: Array = []

	func _ready() -> void:
		pass   # no decal library, no network: only the decision is recorded

	func add_stain(_pos: Vector3, _radius: float, is_vehicle: bool, _seed: int, _owner: Node3D = null) -> void:
		calls.append(is_vehicle)


func _main(system: String) -> Array:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.opr_army_manager.table_system = system
	var stains := RecordingStains.new()
	m.battlefield_stains = stains
	auto_free(stains)
	auto_free(m)
	return [m, stains]


func _machine_model() -> ModelInstance:
	var unit := GameUnit.new()
	unit.unit_properties = {"name": "Heavy Annihilator", "special_rules": ["Tough(6)"]}   # reads as a machine (model_stuff_test)
	var model := ModelInstance.new()
	model.unit = unit
	var node := Node3D.new()
	add_child(node)
	auto_free(node)
	model.node = node
	return model


func test_the_oil_decision_follows_the_system() -> void:
	for system in ["gf", "gff", ""]:
		assert_bool(BattlefieldStains.uses_oil(true, system)).override_failure_message("%s lost the oil pool" % system).is_true()
	for system in ["aof", "aofs", "aofr"]:
		assert_bool(BattlefieldStains.uses_oil(true, system)).override_failure_message("%s left oil" % system).is_false()
	assert_bool(BattlefieldStains.uses_oil(false, "gf")).is_false()   # infantry never leaves oil


func test_a_machine_removed_from_a_table_leaves_oil_on_grimdark_and_blood_on_fantasy() -> void:
	for spec in [["gf", true], ["gff", true], ["aof", false], ["aofs", false], ["aofr", false]]:
		var pair := _main(spec[0])
		(pair[0] as Node)._spawn_stain_for_model(_machine_model())
		assert_array((pair[1] as RecordingStains).calls).override_failure_message("%s" % spec[0]).is_equal([spec[1]])

extends GdUnitTestSuite
## A planner node recording stamps the RULES EPOCH in its header (REPORT_castparity finding 1). Without the
## key the Rust replay reads epoch 0 and takes every pre-epoch rule branch (42/72 exact on a fresh recording).

const IN2M := 0.0254

var _dir := ""


func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://node_epoch_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	OS.set_environment("NML_NODE_DUMP", _dir)
	AiPlanner.close()


func after_test() -> void:
	AiPlanner.close()
	OS.unset_environment("NML_NODE_DUMP")
	DirAccess.remove_absolute(_dir.path_join("nodes.jsonl"))


func _one_unit_state() -> Dictionary:
	var u := GameUnit.new()
	u.unit_id = "Solo"
	u.unit_properties = {"player_id": 1, "name": "Solo", "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(6.0 * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	u.source_type = "opr"
	u.source_data = OPRApiClient.OPRUnit.new()
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Solo": u}
	return BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)


func test_the_node_header_carries_the_rules_epoch() -> void:
	var state := _one_unit_state()
	AiPlanner._record_node(state, {"unit": "Solo", "kind": "hold"}, state, 0.0, 1, false)
	AiPlanner.close()
	var f := FileAccess.open(_dir.path_join("nodes.jsonl"), FileAccess.READ)
	assert_object(f).is_not_null()
	var header: Dictionary = JSON.parse_string(f.get_line())
	# The Rust node reader takes the epoch from `seams.rules_epoch` (io.rs Header.seams).
	var seams: Dictionary = header.get("seams", {})
	assert_bool(seams.has("rules_epoch")) \
		.override_failure_message("the node header's seams has no rules_epoch key: %s" % str(seams)).is_true()
	assert_int(int(seams.get("rules_epoch", -1))).is_equal(AiActRecorder.rules_epoch)

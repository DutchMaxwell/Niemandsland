extends GdUnitTestSuite
## Soak game 16 (cast lane, gaps2 lane): `Chosen Change Brothers.versatile_pick differs (table {  }, core {ap 1})` and `versatile_pick_round differs (table -1, core 2)` on
## every Versatile volley the core resolves. The table's latch (`_solo_versatile_latch_write`) is written by the table's own pick and counts only in the round it was
## written (`_solo_versatile_latch_read`); a core-resolved volley never runs that pick, so an empty or older latch is no table pick to differ from. The landing now
## reports a split only against a latch of THIS round. Calls the two landing functions with the delta fields the core carries (round 2). Real: the main scene, the units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.current_round = 2


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The splits the landing of a core pick (`mode` 1 = +1 to hit, 2 = AP(+1)) reports against a table latch (`round`, `pick`; round -1 = none), and what lands.
func _land(table_round: int, table_pick: Dictionary, mode: int) -> Dictionary:
	var gu := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 3, "x_in": 0.0}, true), {})
	if table_round != -1:
		gu.unit_properties["versatile_pick_round"] = table_round
		gu.unit_properties["versatile_pick"] = table_pick
	var d := {"versatile_pick_mode": mode, "stamps": {"versatile_pick_round": 2}}
	var before := CoreActivation.stamp_splits
	CoreActivation._land_versatile_mode(_main, gu, d)
	CoreActivation._land_stamps(_main, gu, d)
	var out := {"splits": CoreActivation.stamp_splits - before, "pick": gu.unit_properties.get("versatile_pick"), "round": gu.unit_properties.get("versatile_pick_round")}
	_main.opr_army_manager.game_units.erase(gu.unit_id)
	for m in gu.models:
		if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
			(m as ModelInstance).node.free()
	return out


func test_a_core_pick_with_no_table_latch_or_an_older_one_lands_without_a_split() -> void:
	var none := _land(-1, {}, 2)
	assert_int(int(none["splits"])).override_failure_message("no table latch: %s" % str(none)).is_equal(0)
	assert_dict(none["pick"]).is_equal({"hit_mod": 0, "ap": 1})
	assert_int(int(none["round"])).is_equal(2)
	var stale := _land(1, {"hit_mod": 0, "ap": 1}, 1)   # the table's pick of the last round, the core's new one
	assert_int(int(stale["splits"])).override_failure_message("an older latch: %s" % str(stale)).is_equal(0)
	assert_dict(stale["pick"]).is_equal({"hit_mod": 1, "ap": 0})
	assert_int(int(stale["round"])).is_equal(2)


func test_a_latch_of_this_round_that_differs_is_still_a_split() -> void:
	var same := _land(2, {"hit_mod": 0, "ap": 1}, 2)
	assert_int(int(same["splits"])).override_failure_message("the same pick: %s" % str(same)).is_equal(0)
	var other := _land(2, {"hit_mod": 1, "ap": 0}, 2)
	assert_int(int(other["splits"])).override_failure_message("the table picked +1 to hit, the core AP(+1): %s" % str(other)).is_equal(1)
	assert_dict(other["pick"]).is_equal({"hit_mod": 0, "ap": 1})

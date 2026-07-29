extends GdUnitTestSuite
## E2E — #190: "ambushing leader (jetpack) not registering as being placed". The Ambush ✓
## click detected arrivals by the unit's CENTRE — silent in both failure directions: a
## placed leader with the squad still on the tray did not register (the report), and a
## mostly-placed squad counted as complete while leftover models stayed hidden on the tray.
##
## Under test on the real main.tscn: _solo_reserve_table_presence (all-models rule +
## partial counts) and the honor-system >9" proximity warning (rules-must-log).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OFF_TABLE := Vector3(5.0, 0.0, 0.0)   # tray-side: far outside any table rect

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reserve_unit(unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, unit_name, positions)
	u.unit_properties["ambush_reserve"] = true
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_fully_tabled_unit_registers(timeout := 120000) -> void:
	var u := _reserve_unit("Whole", [Vector3.ZERO, Vector3(0.05, 0, 0), Vector3(0.1, 0, 0)])
	var res: Dictionary = _main._solo_reserve_table_presence()
	assert_array(res["placed"] as Array).contains([u])
	assert_array(res["partial"] as Array).is_empty()


func test_placed_leader_with_squad_on_tray_reports_partial(timeout := 120000) -> void:
	# The community case: the jetpack LEADER stands on the table, its host squad still on
	# the tray. The unit must NOT register — and the counts must say what is missing.
	var squad := _reserve_unit("JetSquad", [OFF_TABLE, OFF_TABLE + Vector3(0.05, 0, 0)])
	var hero := E2EBoot.make_unit(_main, 1, "JetLeader", [Vector3.ZERO])
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	var res: Dictionary = _main._solo_reserve_table_presence()
	assert_array(res["placed"] as Array) \
		.override_failure_message("#190 — a lone placed leader counted the whole unit as arrived") \
		.is_empty()
	var partial: Array = res["partial"] as Array
	assert_int(partial.size()).is_equal(1)
	var pe := partial[0] as Dictionary
	assert_int(int(pe["on"])).is_equal(1)
	assert_int(int(pe["total"])).is_equal(3)


func test_mostly_placed_squad_is_not_complete(timeout := 120000) -> void:
	# Inverse direction: 3 of 4 models tabled (the CENTRE lands on the table). The old
	# centre test accepted this as placed — the leftover model stayed hidden on the tray.
	var u := _reserve_unit("Stragglers",
		[Vector3.ZERO, Vector3(0.05, 0, 0), Vector3(0.1, 0, 0), OFF_TABLE])
	var res: Dictionary = _main._solo_reserve_table_presence()
	assert_array(res["placed"] as Array) \
		.override_failure_message("#190 — a partially placed unit registered as complete: its leftover models would stay hidden on the tray") \
		.is_empty()
	var partial: Array = res["partial"] as Array
	assert_int(partial.size()).is_equal(1)
	assert_int(int((partial[0] as Dictionary)["on"])).is_equal(3)
	assert_that((partial[0] as Dictionary)["unit"]).is_equal(u)


func test_proximity_violation_is_named_not_silent(timeout := 120000) -> void:
	var arrived := E2EBoot.make_unit(_main, 1, "Arriver", [Vector3.ZERO])
	_main.opr_army_manager.game_units[arrived.unit_id] = arrived
	var foe := E2EBoot.make_unit(_main, 2, "Watcher", [Vector3(0.1016, 0, 0)])   # 4" away
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	_main._solo_warn_ambush_proximity(arrived)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("#190 — an arrival inside the 9\" ring stayed silent (honor system needs a visible line)") \
		.contains("Ambush arrivals must be >9")

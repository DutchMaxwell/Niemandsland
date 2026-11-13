extends GdUnitTestSuite
## E2E — a wound sync of a LIVING model must not write "returns to the battle".
##
## THE DEFECT. NetworkManager.sync_model_wounds replays the host's model state on the receiver. For a
## loose model it called set_loose_model_dead(node, pid, not is_alive, ...) UNCONDITIONALLY, and that
## call is the choke point whose signal the battle log turns into "<unit> returns to the battle" for
## dead=false. broadcast_model_wounds fires on EVERY wound change, so a Tough model that merely lost one
## wound (alive before, alive after) made the receiving player's log announce a revival that never
## happened. Only a model that was really parked may be reported as returning.
##
## The suite delivers the real RPC body (the REAL main.tscn and its real NetworkManager, called
## directly: the frame a peer would receive) and reads the real battle log.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const REVIVE_LINE := "returns to the battle"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _logged_containing(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


## A registered two-model unit owned by player 2 (so the receiver is "the other side").
func _unit(unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, unit_name, [Vector3(0.2, 0.0, 0.0), Vector3(0.23, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
	return u


## A living Tough model takes a wound: the host sends the new wound count with is_alive still true.
func test_a_wound_on_a_living_model_logs_no_revive(timeout := 120000) -> void:
	var u := _unit("ToughPair")
	var tough := u.models[0] as ModelInstance
	tough.wounds_current = 3
	_main.network_manager.sync_model_wounds(u.unit_id, 0, 2, true, -1)
	assert_int(tough.wounds_current) \
		.override_failure_message("fixture check: the wound sync must have been applied") \
		.is_equal(2)
	assert_bool(tough.is_alive).is_true()
	assert_int(_logged_containing(REVIVE_LINE)) \
		.override_failure_message("a wound on a living model was logged as a revival:\n%s" % _log_text()) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


## Several wound frames in a row for the same living model stay silent too.
func test_repeated_wound_frames_stay_silent(timeout := 120000) -> void:
	var u := _unit("ToughTrio")
	var tough := u.models[1] as ModelInstance
	tough.wounds_current = 3
	for w in [2, 1]:
		_main.network_manager.sync_model_wounds(u.unit_id, 1, w, true, -1)
	assert_int(_logged_containing(REVIVE_LINE)) \
		.override_failure_message("a wound on a living model was logged as a revival:\n%s" % _log_text()) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


## The real revive still reports: a model that was parked and comes back alive logs exactly one line.
func test_a_real_revive_logs_exactly_one_line(timeout := 120000) -> void:
	var u := _unit("RevivePair")
	var back := u.models[0] as ModelInstance
	# The host kills the model ...
	_main.network_manager.sync_model_wounds(u.unit_id, 0, 0, false, -1)
	assert_bool(back.is_alive).is_false()
	assert_bool(bool(back.node.get_meta("deleted", false))) \
		.override_failure_message("fixture check: the death frame must park the model") \
		.is_true()
	assert_int(_logged_containing(REVIVE_LINE)).is_equal(0)
	# ... and later brings it back.
	_main.network_manager.sync_model_wounds(u.unit_id, 0, 1, true, -1)
	assert_bool(back.is_alive).is_true()
	assert_int(_logged_containing(REVIVE_LINE)) \
		.override_failure_message("a real revival must be logged exactly once:\n%s" % _log_text()) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


## The guard is conservative: a model the receiver already knows as dead (is_alive false) still
## reports its return even if nothing had parked it, so a real revival is never swallowed.
func test_a_revive_of_a_model_flagged_dead_still_logs(timeout := 120000) -> void:
	var u := _unit("FlaggedPair")
	var back := u.models[1] as ModelInstance
	back.is_alive = false
	back.wounds_current = 0
	_main.network_manager.sync_model_wounds(u.unit_id, 1, 1, true, -1)
	assert_bool(back.is_alive).is_true()
	assert_int(_logged_containing(REVIVE_LINE)) \
		.override_failure_message("a revival of a model flagged dead was swallowed:\n%s" % _log_text()) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())

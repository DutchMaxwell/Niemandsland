extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the "this unit already earned the AI's answer" mark must not outlive its round on a
## table that did not close the round.
##
## THE DEFECT. `_solo_replied_ids` (main.gd, kept in the match rule state) remembers which units already earned the AI's
## reply THIS round; `_on_solo_human_activated` returns early for a marked unit ("re-toggling an activation marker must
## never grant a second answer") and so skips every activation door and never books the AI's reply. The mark was
## cleared only by `_solo_end_round`, i.e. only on the machine that CLOSED the round. In an online co-op room two humans
## activate on their own machines, so the other machine only gets the round advance (`_on_remote_round_advanced`): the
## unit it activated in round N stayed marked in round N+1 and its next activation did nothing - no AI answer, no
## Reckless / Utility Buff / Precision Tag / Mend / Surprise Attack / Storm / Re-Deployment / Coordinate door.
##
## The "other machine" is this table receiving the round advance the way `sync_round_advance` delivers it:
## `advance_round()` plus `_on_remote_round_advanced()`, never `_solo_end_round()`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _ai_acted: PackedStringArray = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_ai_acted = PackedStringArray()
	_main.solo_controller.ai_unit_activated.connect(func(gu: GameUnit) -> void:
		_ai_acted.append(gu.get_name()))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Two units of the human (so the round never closes by itself) and three of the AI (so it can answer in both rounds).
func _table() -> GameUnit:
	var mine := _reg(1, "Wachtturm", Vector3(-0.30, 0.0, 0.20))
	_reg(1, "Reserve", Vector3(-0.30, 0.0, 0.32))
	for i in range(3):
		_reg(2, "Nachtzehrer%d" % (i + 1), Vector3(0.30, 0.0, -0.20 + 0.12 * i))
	return mine


## What the radial does: the unit is marked activated, then the activation signal reaches main.
func _activate(u: GameUnit) -> void:
	u.activate(_main.opr_army_manager.current_round)
	await _main._on_solo_human_activated(u)


## The round advance as the table that did NOT close the round receives it.
func _remote_round_advance() -> void:
	_main.opr_army_manager.advance_round()
	_main._on_remote_round_advanced()


func test_a_unit_activated_last_round_is_answered_again_on_the_table_that_did_not_close_it(timeout := 120000) -> void:
	var mine := _table()
	await _activate(mine)
	assert_int(_ai_acted.size()).override_failure_message("fixture check: the AI answers the first activation").is_equal(1)

	_remote_round_advance()
	assert_int(_main.opr_army_manager.current_round).is_equal(2)
	await _activate(mine)

	assert_int(_ai_acted.size()) \
		.override_failure_message("the unit's activation in round 2 earned no AI answer on the table that did not close round 1 (its replied mark outlived the round)") \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


## The doors of the activation run again too: a unit that moved last round has its once-per-activation Utility Buff stamp
## cleared by the round, and the Reckless Piercing roll (a once-per-round stamp) is asked again. Here the cheap witness:
## the pending-reply bookkeeping the early return skipped.
func test_the_round_two_activation_books_its_reply_before_the_pump_pays_it(timeout := 120000) -> void:
	var mine := _table()
	await _activate(mine)
	_remote_round_advance()
	mine.activate(_main.opr_army_manager.current_round)
	_main._solo_ai_busy = true   # park the pump: the booking is the question, not the AI's turn
	await _main._on_solo_human_activated(mine)
	_main._solo_ai_busy = false

	assert_int(_main._solo_pending_replies) \
		.override_failure_message("round 2: the activation booked no owed AI reply (the early return skipped _solo_finish_human_activation)") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


## The finding-5 invariant stays: re-toggling an activation marker inside ONE round grants no second answer.
func test_a_second_activation_signal_in_the_same_round_grants_no_second_answer(timeout := 120000) -> void:
	var mine := _table()
	await _activate(mine)
	assert_int(_ai_acted.size()).override_failure_message("fixture check").is_equal(1)

	await _main._on_solo_human_activated(mine)   # the marker re-toggled, same round

	assert_int(_ai_acted.size()) \
		.override_failure_message("a re-toggled marker earned the AI a second answer in the same round") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


## The mark still survives a save: a round-1 mark written as `true` by an older save reads as "replied in round 1".
func test_an_older_saves_boolean_mark_still_means_replied_this_round(timeout := 120000) -> void:
	var mine := _table()
	_main._solo_replied_ids[mine.unit_id] = true   # what a save written before this change holds
	mine.activate(_main.opr_army_manager.current_round)
	await _main._on_solo_human_activated(mine)

	assert_int(_ai_acted.size()) \
		.override_failure_message("an older save's boolean mark no longer blocks a second answer in its own round") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())

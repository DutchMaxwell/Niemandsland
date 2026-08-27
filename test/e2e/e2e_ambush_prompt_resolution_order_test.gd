extends GdUnitTestSuite
## NML-1089 — the round-start Ambush question must not open on top of an UNRESOLVED volley. In the
## maintainer's test game (2026-08-27, seed 55815, round 2) the log reads
##   "Warriors fires Gauss Rifle at Custodian Brothers — 7 hits"
##   "Custodian Brothers saves on 6+"
##   "Your Ambush reserve keeps waiting this round"      <-- the reserve prompt, mid-volley
##   "AI (Custodian Brothers) defends: …"
## The human volley resolves as a DETACHED coroutine (the targeting click fires it and returns), so
## the alternation could reach the round boundary — and the round-start reserve beat — while the
## shot was still awaiting its dice. Drives the REAL prompt on the real main.tscn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._ensure_solo_controller()


func after_test() -> void:
	if _main != null:
		_main._solo_tray_busy = false
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The prompt is "up" when its panel layer exists AND is visible (_solo_deploy_ui_hide only hides).
func _prompt_is_up() -> bool:
	var ui = _main._solo_deploy_ui
	return ui != null and is_instance_valid(ui) and ui.visible


func test_the_ambush_prompt_waits_for_the_pending_volley() -> void:
	var held := E2EBoot.make_unit(_main, 1, "HeldGuard", [Vector3(5.0, 0, 0)])
	(held.models[0] as ModelInstance).model_index = 0
	_main.opr_army_manager.game_units[held.unit_id] = held
	held.unit_properties["ambush_reserve"] = true
	assert_bool(_prompt_is_up()).is_false()   # nothing standing before the beat

	# A volley is mid-resolution: the one tray is rolling the defender's saves, exactly the window
	# the maintainer's log caught (between "saves on 6+" and "AI … defends").
	_main._solo_tray_busy = true
	_main._solo_ambush_human_turn(2, [held])
	await _runner.simulate_frames(12)
	assert_bool(_prompt_is_up()) \
		.override_failure_message("the Ambush prompt opened while a volley was still resolving") \
		.is_false()
	assert_bool(_main.object_manager.is_object_locked((held.models[0] as ModelInstance).node)) \
		.override_failure_message("the placement lock was installed before the prompt could open") \
		.is_false()

	# The volley finishes — now, and only now, the question opens, and exactly once.
	_main._solo_tray_busy = false
	await _runner.simulate_frames(12)
	assert_bool(_prompt_is_up()) \
		.override_failure_message("the Ambush prompt never opened after the volley had resolved") \
		.is_true()
	assert_str(_main._solo_deploy_ui_label.text).contains("Ambush — round 2")

	# "None this round — keep waiting" closes it; nothing re-opens behind it.
	_main._solo_deploy_ui_btn2.pressed.emit()
	await _runner.simulate_frames(8)
	assert_bool(_prompt_is_up()) \
		.override_failure_message("the Ambush prompt stood again after it was answered") \
		.is_false()
	await E2EBoot.settle(get_tree())


## The guard is a WAIT, not a skip: with nothing resolving the prompt opens on the same frame it
## always did (no regression for the ordinary round start).
func test_the_prompt_opens_at_once_when_nothing_is_resolving() -> void:
	var held := E2EBoot.make_unit(_main, 1, "HeldGuard2", [Vector3(5.0, 0, 0)])
	(held.models[0] as ModelInstance).model_index = 0
	_main.opr_army_manager.game_units[held.unit_id] = held
	held.unit_properties["ambush_reserve"] = true
	_main._solo_ambush_human_turn(3, [held])
	await _runner.simulate_frames(2)
	assert_bool(_prompt_is_up()) \
		.override_failure_message("the guard delayed a prompt with no resolution in flight") \
		.is_true()
	_main._solo_deploy_ui_btn2.pressed.emit()
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())

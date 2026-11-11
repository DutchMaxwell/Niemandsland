extends GdUnitTestSuite
## W34-NOTICE (0.3.15): two refusals were correct but silent. A save made before 0.3.15 is refused by SaveManager (0 armies,
## 0 units) and the reason only reached push_error; an online join between different game versions is refused by the host and
## the guest wrote the reason into a status label that sits inside the CLOSED left menu. Either way the player stood in front
## of an empty table with no word of why. Both refusals now raise the top-centre notice (UI/SoloActionToast) with the reason,
## and keep it up longer than a plain notice (the table intro may still be running). Driven on the real main.tscn through the
## real signals; the test never calls the toast helper itself. Reads are null-safe on purpose: on main the toast does not
## exist yet, and a SCRIPT ERROR would not count as a red test.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _toast() -> Label:
	return _main.get_node_or_null("UI/SoloActionToast") as Label


func _toast_visible() -> bool:
	var t := _toast()
	return t != null and t.visible


func _toast_text() -> String:
	var t := _toast()
	return "" if t == null else t.text


func test_a_refused_save_says_why_on_screen() -> void:
	# The sentence SaveManager really produces for a save that carries no rules version (made before 0.3.15).
	var reason := SaveMigrations.rules_version_error({}, OPRApiClient.rules_core_version("gf"))
	assert_str(reason).is_not_empty()
	_main.save_manager.load_failed.emit(reason)
	await _runner.simulate_frames(2)
	assert_bool(_toast_visible()) \
		.override_failure_message("a refused save raised no visible on-screen notice (the reason only reached push_error)") \
		.is_true()
	assert_str(_toast_text()).contains(reason)
	assert_bool(_main._solo_toast_sticky) \
		.override_failure_message("a refusal is an app notice, not an AI explanation: it must fade, not stay sticky") \
		.is_false()


func test_a_refused_online_join_says_why_on_screen() -> void:
	_main.network_manager.version_rejected.emit("0.3.14.0-alpha", "0.3.15.0-alpha")
	await _runner.simulate_frames(2)
	assert_bool(_toast_visible()) \
		.override_failure_message("a refused online join raised no visible on-screen notice (the reason sat in the closed menu)") \
		.is_true()
	assert_str(_toast_text()).contains("0.3.14.0-alpha")
	assert_str(_toast_text()).contains("0.3.15.0-alpha")
	assert_bool(_main._solo_toast_sticky).is_false()


func test_a_refusal_stays_up_longer_than_a_plain_notice() -> void:
	# The player lands on an empty table while the intro may still run; the plain 6 s fade is easy to miss.
	var consts: Dictionary = (_main.get_script() as GDScript).get_script_constant_map()
	var refusal_s := float(consts.get("REFUSAL_TOAST_HIDE_S", 0.0))
	assert_float(refusal_s) \
		.override_failure_message("REFUSAL_TOAST_HIDE_S is missing: a refusal would fade with the plain notice") \
		.is_greater(float(consts.get("SOLO_TOAST_HIDE_S", 6.0)))

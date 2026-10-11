extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.T2a-ext: the MANUAL Shaken and Fatigued toggles obey the SAME off-turn
## gate as Activate. On a hotseat Automatic table (two humans, no AI seat) a unit whose side is not on
## turn cannot be marked or cleared — through the radial menu OR the unit-dock card chip — and the
## refusal names the side on turn ("It is P1's turn", ONE line per attempt). The side on turn toggles
## normally. The engine's own callers (main.gd rules paths) pass manual=false and stay ungated, so the
## rules keep writing markers on either side.
##
## Semantics: a shared-mouse hotseat cannot tell WHO clicked, so the gate is per-UNIT-OWNER: a unit
## whose owner is not the side on turn is refused. "Own unit" = the off-turn side's unit (refused);
## "opponent unit" = the on-turn side's unit (toggles normally).
##
## Real: scenes/main.tscn, the real radial _on_action_selected, the real UnitDock card dispatch
## (_card_action), the real battle_log, the real hotseat_turn_refusal.

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	# The card chip reaches the radial controller through the dock; make the wiring deterministic.
	if _main.unit_dock != null:
		_main.unit_dock.radial_menu_controller = _main.radial_menu_controller


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


## The radial menu path: the dispatcher the context menu emits, manual=auto-stamped true for these rows.
func _radial_toggle(action: String, unit: GameUnit) -> void:
	_main.radial_menu_controller._on_action_selected(action, {"game_unit": unit})


## The unit-dock card-chip path: the chip's own dispatch, which must pass manual=true.
func _chip_toggle(kind: String, unit: GameUnit) -> void:
	_main.unit_dock._presented_unit = unit
	_main.unit_dock._card_action(kind)


func _refusals() -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find("It is P1's turn") != -1:
			n += 1
	return n


func test_the_off_turn_side_cannot_toggle_via_radial_or_chip(timeout := 120000) -> void:
	var off := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))     # P2, off-turn
	_register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))                # P1 opens the round
	_hotseat_automatic()
	assert_int(_refusals()).override_failure_message("precondition: no refusal yet").is_equal(0)

	_radial_toggle("toggle_shaken", off)
	assert_bool(off.is_shaken) \
		.override_failure_message("step 2.T2a-ext — off-turn radial Shaken was applied") \
		.is_false()
	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — off-turn radial Shaken logged no refusal") \
		.is_equal(1)

	_chip_toggle("shaken", off)
	assert_bool(off.is_shaken) \
		.override_failure_message("step 2.T2a-ext — off-turn chip Shaken was applied") \
		.is_false()
	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — off-turn chip Shaken logged no refusal") \
		.is_equal(2)

	_radial_toggle("toggle_fatigued", off)
	assert_bool(off.is_fatigued) \
		.override_failure_message("step 2.T2a-ext — off-turn radial Fatigued was applied") \
		.is_false()
	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — off-turn radial Fatigued logged no refusal") \
		.is_equal(3)

	_chip_toggle("fatigued", off)
	assert_bool(off.is_fatigued) \
		.override_failure_message("step 2.T2a-ext — off-turn chip Fatigued was applied") \
		.is_false()
	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — off-turn chip Fatigued logged no refusal") \
		.is_equal(4)
	await E2EBoot.settle(get_tree())


func test_the_on_turn_side_toggles_normally(timeout := 120000) -> void:
	var on := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))     # P1, on turn
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()

	_radial_toggle("toggle_shaken", on)
	assert_bool(on.is_shaken) \
		.override_failure_message("step 2.T2a-ext — on-turn radial Shaken was wrongly refused") \
		.is_true()

	_chip_toggle("shaken", on)
	assert_bool(on.is_shaken) \
		.override_failure_message("step 2.T2a-ext — on-turn chip Shaken was wrongly refused") \
		.is_false()

	_radial_toggle("toggle_fatigued", on)
	assert_bool(on.is_fatigued) \
		.override_failure_message("step 2.T2a-ext — on-turn radial Fatigued was wrongly refused") \
		.is_true()

	_chip_toggle("fatigued", on)
	assert_bool(on.is_fatigued) \
		.override_failure_message("step 2.T2a-ext — on-turn chip Fatigued was wrongly refused") \
		.is_false()

	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — the on-turn side was refused") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_the_engine_paths_stay_ungated(timeout := 120000) -> void:
	# main.gd's rules callers use card_toggle_* with the manual=false default: an off-turn unit CAN be
	# marked by the engine (round-start recovery, _solo_mirror_shaken). If that default ever flips to
	# true, the engine would silently stop writing markers.
	var off := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	_hotseat_automatic()
	_main.radial_menu_controller.card_toggle_shaken(off)   # the engine's convention: manual defaults false
	assert_bool(off.is_shaken) \
		.override_failure_message("step 2.T2a-ext — the engine toggle path was wrongly gated") \
		.is_true()
	assert_int(_refusals()) \
		.override_failure_message("step 2.T2a-ext — the engine toggle path logged a refusal") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
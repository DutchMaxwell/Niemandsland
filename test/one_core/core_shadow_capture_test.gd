extends GdUnitTestSuite
## C-3 (shadow run): `CoreShadow.capture` keeps a core board for an OPR AI unit the core door does not take (a weapon
## rule), and the tray's tap holds the table volley's rolls. Flag off: no board, no tap entry (the shipped game).
## RED: drop the `CoreShadow.note_roll` call in `_solo_tray_roll` -> the tap stays empty; drop the flag check -> the
## flag-off case captures.
## Real: the main scene, NmlCore, the table's `_solo_resolve_ai_volley` and its tray. Constructed: the golden grid's
## "ap" shape (an AP(1) rifle, not in the shipped slice) and its defender.

const SlicePin := preload("res://test/one_core/slice_pin.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	SlicePin.narrow()   # C-19: this suite is about what the narrow slice refuses
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1


func after_test() -> void:
	SlicePin.release()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreShadow._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The "ap" shape's attacker and defender, and the attacker's shots as `_run_ai_shooting` builds them.
func _pair() -> Array:
	var sc: Dictionary = Harness.scenarios().filter(func(s: Dictionary) -> bool: return s["name"] == "ap")[0]
	var weapon: Dictionary = (sc["weapon"] as Dictionary).duplicate(true)
	var att := ParityTable._make_unit(_main, sc["attacker"], weapon)
	var dfn := ParityTable._make_unit(_main, sc["defender"], {})
	var dist_in := float((sc["defender"] as Dictionary)["x_in"]) - float((sc["attacker"] as Dictionary)["x_in"])
	var plist: Array = AiShooting.profiles_in_range([(att.source_data as OPRApiClient.OPRUnit).weapons[0]], dist_in)
	var shots: Array = []
	for p in plist:
		shots.append({"member": att, "quality": att.get_quality(), "alive": att.get_alive_count(), "max": att.models.size(),
			"reach": float(weapon["range_in"]), "profile": p})
	return [att, dfn, shots]


func test_flag_off_captures_nothing_and_taps_nothing() -> void:
	CoreShadow._env = 0
	var p := _pair()
	assert_bool(CoreActivation.is_plain(p[0])).override_failure_message("fixture: the AP rifle must not be plain").is_false()
	_main._solo_core_shadow_h = CoreShadow.capture(_main, p[0])
	assert_int(_main._solo_core_shadow_h).is_equal(0)
	_main.seed_tray_rng(3)
	await _main._solo_resolve_ai_volley(p[0], p[1], p[2])
	assert_array(CoreShadow.tap).is_empty()
	Harness._free_units(_main, [p[0], p[1]])


func test_flag_on_captures_a_ruled_unit_and_taps_the_volley() -> void:
	CoreShadow._env = 1
	var p := _pair()
	_main._solo_core_shadow_h = CoreShadow.capture(_main, p[0])
	assert_int(_main._solo_core_shadow_h).override_failure_message("no shadow board for a ruled OPR unit").is_not_equal(0)
	_main.seed_tray_rng(3)
	await _main._solo_resolve_ai_volley(p[0], p[1], p[2])
	var tap: Array = CoreShadow.tap.duplicate(true)
	assert_bool(tap.is_empty()).override_failure_message("the tap holds no roll of the volley").is_false()
	if tap.is_empty():
		return
	assert_dict(tap[0]).contains_key_value("kind", "attack").contains_key_value("owner", "AI (%s)" % p[0].get_name())
	for r in tap:
		assert_int((r["faces"] as Array).size()).is_equal(int(r["count"]))
	CoreShadow.release(_main)
	assert_int(_main._solo_core_shadow_h).is_equal(0)
	assert_array(CoreShadow.tap).is_empty()
	Harness._free_units(_main, [p[0], p[1]])

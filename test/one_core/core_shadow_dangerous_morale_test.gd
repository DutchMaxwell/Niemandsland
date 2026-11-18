extends GdUnitTestSuite
## C-19 s2 (shadow run): a unit that took Dangerous wounds owes an end-of-activation morale test (GF v3.5.1 p.10/p.12).
## The core's one call rolls it right after the volley; the table's AI body throws it only after `_run_ai_shooting`
## returned. The shadow compare used to run at the end of the volley code, so the core's morale die found no table die
## and the record read "core_rolls_more" (soak 18.11.: Daemon Artillery, Blood Assault Brothers). The compare is now
## held until the body's end morale (`CoreShadow.hold` / `flush`).
## RED: `_run_ai_shooting` calling `CoreShadow.compare` directly (the old hand-off) -> every seed whose Dangerous test
## wounds the half-strength attacker records first_diff "core_rolls_more".
## Real: the main scene, NmlCore, the AI's decision and move, the body (`_solo_activate_one_ai`), the table's volley,
## tray and tap. Constructed: plain units (ParityTable), a painted Dangerous block under the attacker, a defender with a
## unit rule (the core door refuses it, so the table resolves the volley and the shadow compares it), both seats AI.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreShadow._env = 1
	CoreShadow.records.clear()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreShadow._env = -1
	CoreShadow.records.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One real AI activation of a 10-model attacker with 6 lost (at half strength) standing in Dangerous terrain, a Fast
## defender 8" away. Returns the attacker's morale verdict count and the activation's shadow records.
func _body(seed: int) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": -10.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": 8.0,
		"rules": ["Fast"]}, true), {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	Harness._kill_models(att, 6)
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	_main.seed_tray_rng(seed)
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	var before := CoreShadow.records.size()
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var morale := lines.filter(func(l: Variant) -> bool: return str(l).begins_with("COMBAT|Att ") and str(l).contains(" morale")).size()
	var out := {"morale": morale, "records": CoreShadow.records.slice(before), "lines": lines}
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, foe])
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


func test_a_dangerous_end_morale_replays_equal_in_the_shadow() -> void:
	var tested := 0
	for s in 8:
		var r := await _body(s)
		var why := "seed %d: morale %d, records %s\n%s" % [s, r["morale"], r["records"], "\n".join(r["lines"])]
		assert_int((r["records"] as Array).size()).override_failure_message("one shadow record per volley: " + why).is_equal(1)
		if (r["records"] as Array).size() != 1:
			continue
		tested += 1 if int(r["morale"]) > 0 else 0
		assert_dict(r["records"][0]).override_failure_message(why).contains_key_value("equal", true)
	assert_int(tested).override_failure_message("fixture: no seed's Dangerous test wounded the attacker").is_greater(0)

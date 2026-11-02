extends GdUnitTestSuite
## Audit doubt MOR-17a-doubt: a human charge on the table may pass no charge distance to
## Warding, so the rule could fall back to its blanket 6+ read and ignore Impact wounds even on
## a short charge. This drives the real human melee path (the test never hands the resolver a
## distance) with the charger one inch from a Warding target and asserts the gate's verdict plus
## the kept Impact wounds. The core twin is core/nml-core/src/tests/dice/v36_morale.rs (mor_17a).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}   # pid 1 is the human charger, pid 2 the AI Warding target
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models at `x_in`, carrying `rules` on the unit and on every model (the books the
## registry resolves Warding through), Defense `defense`, `wounds` per model.
func _unit(pid: int, unit_name: String, x_in: float, models: int, rules: Array, faction: String,
		defense: int, wounds: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x_in * INCH, 0.0, 0.02 * i))
	var u: GameUnit = E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.source_type = "opr"
	u.source_data = OPRApiClient.OPRUnit.new()
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules.duplicate()
	u.unit_properties["defense"] = defense
	for m in u.models:
		var mi := m as ModelInstance
		mi.properties["special_rules"] = rules.duplicate()
		mi.wounds_max = wounds
		mi.wounds_current = wounds
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_a_human_charge_from_within_six_inches_keeps_its_impact_wounds(timeout := 90000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var charger := _unit(1, "Charger", 0.0, 4, ["Impact(4)"], "blessed_sisters", 4, 1)
	var target := _unit(2, "Knight Squad", 1.0, 1, ["Knightborn"], "knight_brothers", 6, 30)
	_main.seed_tray_rng(1300)
	await _main._run_human_melee(charger, target)
	var text := _log_text()
	assert_str(text).override_failure_message(
		"a human charge must refuse Warding's 6+ within 6in — got: %s" % text.strip_edges()) \
		.contains("Warding: no 6+ ignore, %s was charged from within 6in" % target.get_name())
	assert_str(text).override_failure_message("a short charge must not ignore the Impact wounds") \
		.not_contains("Warding: %s ignores wounds on 6+ (charged from over" % target.get_name())
	var left := 0
	for m in target.models:
		left += (m as ModelInstance).wounds_current
	assert_int(left).override_failure_message("the Impact wounds must land, not be ignored") \
		.is_less(30)
	await E2EBoot.settle(get_tree())

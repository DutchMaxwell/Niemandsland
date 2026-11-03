extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AI-G2: a UNIT rule the faction map resolves to the Brace primitive ("Brace in
## Melee", the gf/aof common entry) blunts a charge like a Brace weapon, from the 3.6 epoch on, and the
## battle log names the book rule. Twin of core/nml-core/src/tests/sim/v36_melee_rows/aig_g2_brace.rs. The
## controls come first (gdUnit drops the cases declared after a failing one in a scene suite).

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
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models of `tough` wounds each at `x` inches, one melee weapon carrying `weapon_rules`, the given
## unit rules and Defense.
func _unit(pid: int, unit_name: String, x: float, models: int, weapon_rules: Array, rules: Array, defense: int,
		tough: int = 1) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	w.special_rules.assign(weapon_rules)
	u.unit_properties["special_rules"] = rules + (["Tough(%d)" % tough] if tough > 1 else [])
	u.unit_properties["defense"] = defense
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Battle-log index of the first line holding `needle`, -1 when none does.
func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## The dice count off the Impact roll's own battle-log line ("Charger: Impact(3) rolls 3 dice ...").
func _impact_dice() -> int:
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.contains("Impact(") and t.contains(" rolls "):
			return int(t.split(" rolls ")[1].split(" ")[0])
	return -1


## One AI charge: 1 charger model with Impact(3) into two defender models that carry `weapon_rules` on their
## weapon and `unit_rules` on the unit; `fatigued` marks the defender Fatigued.
func _charge(epoch: int, weapon_rules: Array, unit_rules: Array, fatigued: bool = false) -> void:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 1, [], ["Impact(3)"], 4, 9)
	var defender := _unit(1, "Defender", 1.0, 2, weapon_rules, unit_rules, 4, 9)
	defender.is_fatigued = fatigued
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})


## Control: the Brace weapon keeps its cut and its own name.
func test_a_brace_weapon_still_takes_one_die_under_its_own_name(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, ["Brace(1)"], [])
	assert_int(_impact_dice()).is_equal(2)
	assert_int(_line_of("Brace: Defender takes 1 Impact dice off Charger")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


## Control: below the 3.6 epoch the unit rule replays as before (nothing taken off, nothing logged).
func test_below_73_brace_in_melee_stays_inert(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, [], ["Brace in Melee"])
	assert_int(_impact_dice()).is_equal(3)
	assert_int(_line_of("Brace")).is_equal(-1)
	await E2EBoot.settle(get_tree())


func test_brace_in_melee_takes_one_impact_die_and_logs_its_own_name(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, [], ["Brace in Melee"])
	assert_int(_impact_dice()) \
		.override_failure_message("Impact(3) into a unit with Brace in Melee: rating 1, so 3 - 1 = 2 dice") \
		.is_equal(2)
	assert_int(_line_of("Brace in Melee: Defender takes 1 Impact dice off Charger")) \
		.override_failure_message("rules-must-log: the cut names Brace in Melee") \
		.is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_fatigued_unit_with_brace_in_melee_takes_nothing_and_logs_its_name(timeout := 90000) -> void:
	await _charge(AiActRecorder.EPOCH_73_V36, [], ["Brace in Melee"], true)
	assert_int(_impact_dice()).is_equal(3)
	assert_int(_line_of("Brace in Melee: no effect, Defender is Fatigued")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


## The AI's estimate reads the same cut: the defender context carries the Brace rating.
func test_the_ai_estimate_counts_brace_in_melee() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var defender := _unit(1, "Defender", 1.0, 2, [], ["Brace in Melee"], 4)
	assert_int(AiEv._brace_cut(defender)).is_equal(1)

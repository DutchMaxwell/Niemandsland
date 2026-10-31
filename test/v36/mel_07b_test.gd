extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-07b: from epoch 73 a defender's Parry(X) rolls X dice per living carrier
## model against a charge's Impact hits, AFTER the Impact hit dice and BEFORE the Impact saves. The
## heavy pool is cancelled first, then the plain one, and the dice never exceed the hits taken. Epoch
## 72 keeps today's behaviour (no Parry dice). The core's twin is
## core/nml-core/src/tests/sim/v36_melee_rows/mel_07b.rs; both engines draw the same seeded faces.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 7

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
	_main._solo_dice_trace_enabled = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models at `x` inches with one melee weapon, `rules` and Defense `defense`; Tough(9) keeps
## every model alive so neither leg depends on a save.
func _unit(pid: int, unit_name: String, x: float, models: int, rules: Array, defense: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules + ["Tough(9)"]
	u.unit_properties["defense"] = defense
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Host of `models` models with `host_rules` and one joined hero carrying `hero_rules`.
func _joined(host_name: String, models: int, host_rules: Array, hero_rules: Array) -> GameUnit:
	var host := _unit(1, host_name, 1.0, models, host_rules, 4)
	var hero := _unit(1, host_name + " Hero", 1.0, 1, hero_rules, 4)
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	return host


## Battle-log index of the first line holding `needle`, -1 when none does.
func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## The AI charges with Impact(`impact`) on one model into `defender`; seed 7 draws [6,2,5,6] first.
func _charge(epoch: int, impact: int, defender: GameUnit) -> void:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(2, "Charger", 0.0, 1, ["Impact(%d)" % impact], 4)
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	await E2EBoot.settle(get_tree())


## 2 Parry(1) models charged by Impact(4): 4 Impact hits, 2 Parry dice (one 6 cancels one hit),
## then the saves for the 3 remaining hits.
func test_parry_cancels_impact_hits_before_the_saves_at_epoch_73(timeout := 90000) -> void:
	var defender := _unit(1, "Defender", 1.0, 2, ["Parry(1)"], 4)
	await _charge(AiActRecorder.EPOCH_73_V36, 4, defender)
	var impact := _line_of("Charger: Impact(4) rolls 4 dice")
	var parry := _line_of("Parry: Defender rolls 2 dice and ignores 1 Impact hits")
	var saves := _line_of("Defender saves on")
	assert_bool(impact >= 0 and parry > impact and saves > parry) \
		.override_failure_message("Impact hits, then Parry, then the saves (lines %d, %d, %d)" % [impact, parry, saves]) \
		.is_true()


func test_no_parry_dice_are_drawn_at_epoch_72(timeout := 90000) -> void:
	var defender := _unit(1, "Defender", 1.0, 2, ["Parry(1)"], 4)
	await _charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 4, defender)
	assert_int(_line_of("Parry: Defender")) \
		.override_failure_message("epoch 72 draws no Parry dice") \
		.is_equal(-1)


func test_a_defender_without_parry_draws_no_parry_dice(timeout := 90000) -> void:
	var defender := _unit(1, "Defender", 1.0, 2, [], 4)
	await _charge(AiActRecorder.EPOCH_73_V36, 4, defender)
	assert_int(_line_of("Parry: Defender")) \
		.override_failure_message("a defender without Parry draws no Parry dice") \
		.is_equal(-1)


func test_a_joined_heros_parry_counts_beside_the_hosts(timeout := 90000) -> void:
	var defender := _joined("Defender", 1, ["Parry(1)"], ["Parry(1)"])
	await _charge(AiActRecorder.EPOCH_73_V36, 4, defender)
	assert_int(_line_of("Parry: Defender rolls 2 dice")) \
		.override_failure_message("host and hero each add one Parry(1) die") \
		.is_greater_equal(0)


## Impact(1) on one model rolls one hit, so 2 Parry(1) models draw ONE die, not two.
func test_parry_dice_never_exceed_the_hits_taken(timeout := 90000) -> void:
	var defender := _unit(1, "Defender", 1.0, 2, ["Parry(1)"], 4)
	await _charge(AiActRecorder.EPOCH_73_V36, 1, defender)
	assert_int(_line_of("Parry: Defender rolls 1 dice")) \
		.override_failure_message("one hit caps two Parry dice at one") \
		.is_greater_equal(0)

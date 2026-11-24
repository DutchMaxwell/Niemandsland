extends GdUnitTestSuite
## The AI door takes a Reanimation shooter. The table rolls the activation start (Reanimation) in `begin_activation` BEFORE the
## AI body captures the board, so `ai_transcript` opens with `paid{start}` and the core skips its own start slot: ONE pool roll.
## `CoreSlice` lets the AI shoot door take a deny group of kind `activation_start`; the human door keeps it (its capture is at
## "Activate", before the start).
## Per seed one activation through the door on the same board and tray seed: the door takes it, the Reanimation pool is rolled
## once and the rule's line is said once.
## Real: the main scene, NmlCore, the AI body, the table's Reanimation, the live deny file. Constructed: a gf Robot Legions unit of
## 10 with 4 dead (Reanimation, or Reanimation Aura on the unit) at a plain foe.
## RED (main without the paid start): the door does not take the shooter (ai_runs 0); taking it without `paid` rolls the pool twice
## (core_start_once_door_test's control leg, 8 of 8).
## The table arm left with the AI table resolver; door values are snapshot pins read on main ab595da20 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const SEEDS := 8
## The table's Reanimation pool roll: an "attack" roll at the rule's 5+ (the unit's own Quality is 4, so no volley roll matches).
const POOL_TARGET := 5
## Per seed: the door's Reanimation pool rolls, rolled exactly once (read on main from the table arm).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_POOL := [1, 1, 1, 1, 1, 1, 1, 1]
## Per seed: the door's count of the Reanimation line, said exactly once (read on main from the table arm).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_REA_LINES := [1, 1, 1, 1, 1, 1, 1, 1]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2])
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_main._autosave_controller.set_lesson_paused(true)
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## One AI activation of a 10-model bearer of `rule` with 4 dead, through the door. Returns {pool, runs, rea_lines}.
func _activation(rule: String, s: int) -> Dictionary:
	CoreActivation._env = 1
	CoreActivation.reset_all(_main)
	CoreActivation.ai_runs = 0
	var ai := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Bots", "models": 10, "x_in": -10.0, "rules": [rule]}, true), RIFLE)
	if rule.ends_with(" Aura"):
		(ai.source_data as OPRApiClient.OPRUnit).special_rules.append(rule)
		OPRArmyManager.expand_auras_of([ai.source_data], {ai.source_data: ai})   # the import's aura pass: the unit gets Reanimation
	for i in range(6, 10):
		(ai.models[i] as ModelInstance).wounds_current = 0
		(ai.models[i] as ModelInstance).is_alive = false
	var hu := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Humans", "models": 10, "x_in": 8.0}), RIFLE)
	var k0: int = (_main.solo_controller.decision_log as Array).size()
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(s)
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var dice: Array = (_main.solo_controller.decision_log as Array).slice(k0).filter(
		func(r: Dictionary) -> bool: return str(r.get("kind", "")) == "dice" and str(r.get("roll_kind", "")) == "attack")
	var out := {"pool": dice.filter(func(r: Dictionary) -> bool: return int(r["target"]) == POOL_TARGET).size(), "runs": CoreActivation.ai_runs,
		"rea_lines": lines.filter(func(l: String) -> bool: return l.contains("Reanimation")).size()}
	_free([ai, hu])
	await _main.get_tree().process_frame
	return out


func _sweep(rule: String) -> void:
	var taken := 0
	var pools: Array = []
	var rea: Array = []
	for s in SEEDS:
		var on := await _activation(rule, s)
		taken += 1 if int(on["runs"]) == 1 else 0
		pools.append(int(on["pool"]))
		rea.append(int(on["rea_lines"]))
	print("START_PAID %s seeds=%d taken=%d pools=%s rea=%s" % [rule, SEEDS, taken, str(pools), str(rea)])
	assert_int(taken).override_failure_message("%s: the door did not take the shooter" % rule).is_equal(SEEDS)
	assert_array(pools).override_failure_message("%s: the door's Reanimation pool rolls per seed" % rule).is_equal(WANT_POOL)
	assert_array(rea).override_failure_message("%s: the Reanimation line count per seed" % rule).is_equal(WANT_REA_LINES)


@warning_ignore('unused_parameter')
func test_the_ai_door_takes_a_reanimation_shooter_and_rolls_the_pool_once(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	await _sweep("Reanimation")


@warning_ignore('unused_parameter')
func test_the_ai_door_takes_a_reanimation_aura_carrier_and_rolls_the_pool_once(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	await _sweep("Reanimation Aura")

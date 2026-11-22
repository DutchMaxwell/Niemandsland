extends GdUnitTestSuite
## D-PAR3 step 15a: the AI door takes a Reanimation shooter. The table rolls the activation start (Reanimation) in
## `begin_activation` BEFORE the AI body captures the board, so `ai_transcript` now opens with `paid{start}` (14a) and the core
## skips its own start slot: ONE pool roll. `CoreSlice` lets the AI shoot door take a deny group of kind `activation_start`; the
## human door keeps it (its capture is at "Activate", before the start - step 16).
## Per seed the same activation twice on the same board and tray seed: door ON (the core takes it) and door OFF (the table).
## Real: the main scene, NmlCore, the AI body, the table's Reanimation, the live deny file. Constructed: a gf Robot Legions unit of
## 10 with 4 dead (Reanimation, or Reanimation Aura on the unit) at a plain foe.
## RED (main without 15a): the door does not take the shooter (ai_runs 0); taking it without `paid` rolls the pool twice
## (core_start_once_door_test's control leg, 8 of 8).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const SEEDS := 8   # per rule spelling: 16 activations per arm
## The table's Reanimation pool roll: an "attack" roll at the rule's 5+ (the unit's own Quality is 4, so no volley roll matches).
const POOL_TARGET := 5

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main._solo_fast = true
	_main._solo_auto_saves = true
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


## One AI activation of a 10-model bearer of `rule` with 4 dead. Returns {pool, runs, ai_alive, foe_alive, volley}.
func _activation(rule: String, s: int, door: bool) -> Dictionary:
	CoreActivation._env = 1 if door else 0
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
	await _main._solo_activate_one_ai()
	var dice: Array = (_main.solo_controller.decision_log as Array).slice(k0).filter(
		func(r: Dictionary) -> bool: return str(r.get("kind", "")) == "dice" and str(r.get("roll_kind", "")) == "attack")
	var volley: Array = dice.filter(func(r: Dictionary) -> bool: return int(r["target"]) != POOL_TARGET)
	var out := {"pool": dice.filter(func(r: Dictionary) -> bool: return int(r["target"]) == POOL_TARGET).size(), "runs": CoreActivation.ai_runs,
		"ai_alive": ai.get_alive_count(), "foe_alive": hu.get_alive_count(), "volley": int(volley[0]["count"]) if not volley.is_empty() else -1}
	_free([ai, hu])
	await _main.get_tree().process_frame
	return out


func _sweep(rule: String) -> void:
	var bad: Array = []
	var pooled := 0
	for s in SEEDS:
		var on := await _activation(rule, s, true)
		var off := await _activation(rule, s, false)
		pooled += 1 if int(off["pool"]) == 1 else 0
		if int(on["runs"]) != 1:
			bad.append("seed %d: the door did not take the shooter %s" % [s, on])
		elif int(on["pool"]) != 1 or int(on["pool"]) != int(off["pool"]):
			bad.append("seed %d: pool rolls door %d, table %d" % [s, on["pool"], off["pool"]])
		elif int(on["ai_alive"]) != int(off["ai_alive"]) or int(on["foe_alive"]) != int(off["foe_alive"]) or int(on["volley"]) != int(off["volley"]):
			bad.append("seed %d: door %s, table %s" % [s, on, off])
	print("START_PAID %s seeds=%d table_pooled=%d bad=%d" % [rule, SEEDS, pooled, bad.size()])
	assert_int(pooled).override_failure_message("%s: the table never rolled the pool - nothing was compared" % rule).is_equal(SEEDS)
	assert_array(bad).override_failure_message("%s:\n%s" % [rule, "\n".join(bad.slice(0, 4))]).is_empty()


@warning_ignore('unused_parameter')
func test_the_ai_door_takes_a_reanimation_shooter_and_rolls_the_pool_once(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	await _sweep("Reanimation")


@warning_ignore('unused_parameter')
func test_the_ai_door_takes_a_reanimation_aura_carrier_and_rolls_the_pool_once(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	await _sweep("Reanimation Aura")

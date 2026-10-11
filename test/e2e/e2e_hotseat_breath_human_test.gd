extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.7b "Breath Attack human door": a HUMAN Breath Attack bearer now rolls
## its trigger on its OWN tray and auto-picks an ENEMY unit (owner != bearer's owner — solo: the AI
## seat; hotseat: the other human) within 6" and LOS — the same procedure the AI runs. The book's
## wording is a plain instruction (no "may"), so it is automatic. On a Manual table nothing fires. The
## AI's own path is untouched.
##
## Real: scenes/main.tscn, the real radial activation door (_toggle_activation -> _on_solo_human_activated),
## the real _solo_apply_breath_attack / _solo_nearest_model_gap_in / _owner_roll, the real battle_log.
## Harness dice (_solo_batch); the trigger die is made deterministic by seeding the tray RNG.

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
	_main._solo_game_finished = false
	_main._solo_batch = true   # instant, non-physics dice (the harness dice seam)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3, rules: Array = [], faction := "") -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	if not rules.is_empty():
		u.unit_properties["special_rules"] = rules
	# unit_rule_active gates by (system, faction): "Breath Attack" is only in the faction sections of the
	# map (alien_hives / saurian_starhost), never in `common`. A real imported unit carries faction_folder.
	if not faction.is_empty():
		u.unit_properties["faction_folder"] = faction
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _manual() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL


## The trigger needs 2+; a fizzle (a 1) would make the target/damage assertions non-deterministic.
## The tray's batch RNG is a seed-reset RandomNumberGenerator, so a fresh generator with the same seed
## draws the same first face — pick a seed whose first 1d6 is not a 1.
func _seed_with_trigger_success() -> int:
	for s in range(1, 400):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if probe.randi_range(1, 6) >= 2:
			return s
	return 2


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(8)
	await E2EBoot.settle(get_tree())


func _lines_with(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


func test_a_human_bearer_breathes_on_an_enemy(timeout := 120000) -> void:
	# Breath Attack reaches 6" (0.152 m). The fixtures must sit INSIDE that, or the green finds no
	# target and the positive assertion fails for the wrong reason (the 2.7a lesson: 1 m = 39.4").
	var breather := _register(1, "Breather", Vector3(0.0, 0.0, 0.0), ["Breath Attack"], "alien_hives")
	# A friendly of the bearer's OWN side sits in range too (0.1 m = 3.9"): a wrong (human_slot) target
	# pick would breathe on it instead of the enemy, so naming the enemy is the discriminating assertion.
	_register(1, "Ally", Vector3(0.0, 0.0, 0.1))
	_register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	_hotseat_automatic()
	_main.seed_tray_rng(_seed_with_trigger_success())
	await _activate(breather)
	assert_int(_lines_with("Breath Attack:")) \
		.override_failure_message("step 2.7b — the human Breath Attack bearer did not fire") \
		.is_equal(1)
	assert_int(_lines_with("breathes on Foe")) \
		.override_failure_message("step 2.7b — the human bearer did not breathe on the enemy") \
		.is_equal(1)
	assert_int(_lines_with("breathes on Breather") + _lines_with("breathes on Ally")) \
		.override_failure_message("step 2.7b — the human bearer breathed on its own side") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_bearer_without_the_rule_does_not_fire(timeout := 120000) -> void:
	var plain := _register(1, "Rifles", Vector3(0.0, 0.0, 0.0), [], "alien_hives")
	_register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(plain)
	assert_int(_lines_with("Breath Attack:")) \
		.override_failure_message("step 2.7b — a unit without Breath Attack fired the rule") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_breath_does_not_fire_on_a_manual_table(timeout := 120000) -> void:
	var breather := _register(1, "Breather", Vector3(0.0, 0.0, 0.0), ["Breath Attack"], "alien_hives")
	_register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	_manual()
	await _activate(breather)
	assert_int(_lines_with("Breath Attack:")) \
		.override_failure_message("step 2.7b — a Manual table fired Breath Attack") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
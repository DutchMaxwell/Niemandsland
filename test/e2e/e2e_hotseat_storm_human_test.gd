extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.7c "Storm of X human door": a HUMAN Storm Attack bearer now rolls its
## 3 trigger dice on its OWN tray and auto-picks an ENEMY unit (owner != bearer's owner — solo: the AI
## seat; hotseat: the other human) within 12" — the same procedure the AI runs. The book's wording is a
## plain instruction (no "may"), so it is automatic. On a Manual table nothing fires. The AI's own path
## is untouched.
##
## Real: scenes/main.tscn, the real radial activation door (_toggle_activation -> _on_solo_human_activated),
## the real _solo_apply_storm_attack / _solo_nearest_model_gap_in / _owner_roll, the real battle_log.
## Harness dice (_solo_batch); the trigger + save dice are made deterministic by seeding the tray RNG.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _save_pump: Timer


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
	# unit_rule_active / unit_rules_of_primitive gate by (system, faction): "Storm of War" lives only
	# in the daemons faction sections of the map, never in `common`. A real imported unit carries
	# faction_folder.
	if not faction.is_empty():
		u.unit_properties["faction_folder"] = faction
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _manual() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL


## The storm is the FIRST tray roll of a bare activation (Stormer carries no other rolling rule), so a
## seeded RandomNumberGenerator draws the 3 trigger dice first, then the first save batch. Pick a seed
## whose trigger has at least one 2+ AND whose first save batch carries a non-6 (a face that cannot save
## against Defense 6 + AP(1) = 7+), so a wound is guaranteed to land on the Foe.
func _seed_trigger_and_failed_save() -> int:
	for s in range(1, 4000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var trigger := [probe.randi_range(1, 6), probe.randi_range(1, 6), probe.randi_range(1, 6)]
		if not trigger.any(func(f: int) -> bool: return f >= 2):
			continue
		var saves := [probe.randi_range(1, 6), probe.randi_range(1, 6), probe.randi_range(1, 6)]
		if saves.any(func(f: int) -> bool: return f != 6):
			return s
	return 2


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(8)
	await E2EBoot.settle(get_tree())


## The hotseat defender's save prompt ("P2 — incoming fire!") waits for a human click no headless run
## can make — a repeating timer presses its OK, the house pattern (e2e_game_school_ch6_test). The
## production prompt itself is untouched.
func _arm_save_pump() -> void:
	_save_pump = Timer.new()
	_save_pump.name = "StormSavePump"
	_save_pump.wait_time = 0.02
	_save_pump.one_shot = false
	get_tree().root.add_child(_save_pump)
	_save_pump.timeout.connect(_answer_save_prompt)
	_save_pump.start()


func _answer_save_prompt() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	for c in _main.get_children():
		var card := c as PromptCard
		if card != null and card.title.ends_with("incoming fire!"):
			card.ok_button.pressed.emit()


func _lines_with(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


func test_a_human_bearer_unleashes_the_storm_on_an_enemy(timeout := 120000) -> void:
	# Storm of War reaches 12" (0.30 m); the fixtures sit well inside (0.1 m = 3.9", the 2.7a lesson:
	# 1 m = 39.4"). The Foe is given Defense 6 so AP(1) puts every save out of reach (7+) except a
	# natural 6 — the seed then guarantees at least one unsaved hit.
	var stormer := _register(1, "Stormer", Vector3(0.0, 0.0, 0.0), ["Storm of War"],
		"wormhole_daemons_of_war")
	# A friendly of the bearer's OWN side sits in range too: a wrong (enemy-slot / no-owner-filter)
	# target pick would strike it, so "the Foe takes a wound and the Ally does not" is the
	# discriminating pair for the owner filter.
	var ally := _register(1, "Ally", Vector3(0.15, 0.0, 0.0))
	var foe := _register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	foe.unit_properties["defense"] = 6
	_hotseat_automatic()
	_main.seed_tray_rng(_seed_trigger_and_failed_save())
	_arm_save_pump()
	await _activate(stormer)
	assert_int(_lines_with("unleashes the storm")) \
		.override_failure_message("step 2.7c — the human Storm Attack bearer did not fire") \
		.is_equal(1)
	assert_int(_lines_with("Foe takes")) \
		.override_failure_message("step 2.7c — the storm did not hit the enemy") \
		.is_greater_equal(1)
	assert_int(_lines_with("Ally takes")) \
		.override_failure_message("step 2.7c — the storm hit its own side") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_bearer_without_the_rule_does_not_fire(timeout := 120000) -> void:
	var plain := _register(1, "Rifles", Vector3(0.0, 0.0, 0.0), [], "wormhole_daemons_of_war")
	_register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(plain)
	assert_int(_lines_with("unleashes the storm")) \
		.override_failure_message("step 2.7c — a unit without Storm of War fired the rule") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_storm_does_not_fire_on_a_manual_table(timeout := 120000) -> void:
	var stormer := _register(1, "Stormer", Vector3(0.0, 0.0, 0.0), ["Storm of War"],
		"wormhole_daemons_of_war")
	_register(2, "Foe", Vector3(0.1, 0.0, 0.0))
	_manual()
	await _activate(stormer)
	assert_int(_lines_with("unleashes the storm")) \
		.override_failure_message("step 2.7c — a Manual table fired Storm of War") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())

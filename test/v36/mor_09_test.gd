extends GdUnitTestSuite
## Rules 3.6 row MOR-09: "Valiant" resolves as the Banner primitive; the +1
## counts only over the 9" shot / 6" charge gate from EPOCH_73_V36. Built
## through the real registry so the stamp and the gate are the live ones.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rule: String, faction: String = "human_defense_force") -> GameUnit:
	var u := Boot.make_unit(_main, 1, "Carrier", [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = [rule]
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _seed_first_die_three() -> void:
	var rng := RandomNumberGenerator.new()
	for candidate in range(200):
		rng.seed = candidate
		if rng.randi_range(1, 6) == 3:
			_main.seed_tray_rng(candidate)
			return
	fail("no seed rolls a 3 first")


func test_valiant_resolves_through_the_registry_like_hold_the_line() -> void:
	var u := _unit("Valiant")
	assert_int(int(_main._solo_morale_bonus(u))).is_equal(1)


func test_old_banner_names_drop_inside_the_shot_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for spec in [["Hold the Line", "human_defense_force"], ["Hive Bond", "alien_hives"]]:
		var u := _unit(spec[0], spec[1])
		_seed_first_die_three()
		await _main._solo_morale_test(u, "Victim", false, "", 4.0, -1.0)
		assert_bool(u.is_shaken).override_failure_message("%s inside 9\": no Banner +1" % spec[0]).is_true()


func test_valiant_gate_covers_shots_and_charges_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for c in [[false, 4.0, -1.0, true], [false, 10.0, -1.0, false],
			[true, -1.0, 4.0, true], [true, -1.0, 8.0, false]]:
		var u := _unit("Valiant")
		_seed_first_die_three()
		await _main._solo_morale_test(u, "Victim", bool(c[0]), "", float(c[1]), float(c[2]))
		assert_bool(u.is_shaken).override_failure_message("melee=%s over=%s charge=%s" % [c[0], c[1], c[2]]).is_equal(bool(c[3]))


func test_old_banner_names_keep_the_bonus_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit("Hold the Line")
	_seed_first_die_three()
	await _main._solo_morale_test(u, "Victim", false, "", 4.0, -1.0)
	assert_bool(u.is_shaken).is_false()


func test_valiant_without_distance_keeps_the_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit("Valiant")
	_seed_first_die_three()
	await _main._solo_morale_test(u, "Victim", false)
	assert_bool(u.is_shaken).is_false()

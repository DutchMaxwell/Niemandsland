extends GdUnitTestSuite
## Soak S1: a hero joined to a unit is part of it (GF v3.5.1 p.14, one state), so the round-start
## Battleborn recovery rolls ONCE for the combined unit on the host and _solo_mirror_shaken carries
## the result to the hero. Rolling the hero too split the pair whenever only one side passed (host
## Shaken / hero cleared), the phantom hero diff the core shadow reported. Real: scenes/main.tscn,
## the real hotseat round start, _solo_battleborn_recovery, batch dice.

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
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main._solo_game_finished = false
	_main._solo_batch = true   # instant, non-physics dice (the harness dice seam)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The first seed whose FIRST batch die lands on the wanted side of the 4+ recovery.
func _seed(passes: bool) -> int:
	var rng := RandomNumberGenerator.new()
	for s in 1000:
		rng.seed = s
		if (rng.randi_range(1, 6) >= 4) == passes:
			return s
	return -1


## The S1 record: a Shaken Vale Defender joined to a Shaken host, both with Battleborn. Returns
## [host.is_shaken, hero.is_shaken, recovery lines logged] after the round start ran.
func _recover(host_passes: bool) -> Array:
	var host := _register(1, "Peasants", Vector3(-0.3, 0.0, 0.0), ["Battleborn"])
	var hero := _register(1, "Defender", Vector3(-0.3, 0.2, 0.0), ["Battleborn"])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	host.is_shaken = true
	hero.is_shaken = true
	var enemy := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_main.seed_tray_rng(_seed(host_passes))
	for u in [host, enemy]:   # both spent -> round 2 begins; the round-start recovery runs
		await _main.radial_menu_controller._toggle_activation({"game_unit": u})
		await _runner.simulate_frames(4)
		await E2EBoot.settle(get_tree())
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("the round did not advance — the recovery never ran").is_equal(2)
	var lines := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Battleborn:"):
			lines += 1
	return [host.is_shaken, hero.is_shaken, lines]


func test_a_failed_roll_keeps_host_and_hero_shaken(timeout := 120000) -> void:
	var r := await _recover(false)
	assert_bool(r[0]).override_failure_message("S1 — the host rolled below the target and must stay Shaken").is_true()
	assert_bool(r[1]).override_failure_message("S1 — the joined hero split from its host (rolled on its own)").is_true()
	assert_int(r[2]).override_failure_message("S1 — the joined pair rolled more than once").is_equal(1)


func test_a_passed_roll_clears_host_and_hero(timeout := 120000) -> void:
	var r := await _recover(true)
	assert_bool(r[0]).override_failure_message("S1 — the host rolled the target and must clear Shaken").is_false()
	assert_bool(r[1]).override_failure_message("S1 — the host's pass did not reach the joined hero").is_false()
	assert_int(r[2]).override_failure_message("S1 — the joined pair rolled more than once").is_equal(1)

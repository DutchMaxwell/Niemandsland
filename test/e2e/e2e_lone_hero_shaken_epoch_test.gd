extends GdUnitTestSuite
## Pending epoch 94 (acts.rs `EPOCH_94_PARITY_BATCH`, lead rule call 20.11., reading B): a lone joined hero is the unit once its host
## has no model left, so ITS Shaken flag decides the morale test. The dead host's flag outlives the hero's recovery (nothing clears a dead
## unit's Shaken) and used to fail the hero's next test without a die. Below 94 the table reads the unit's own flag, as always.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch_before := 0


func before_test() -> void:
	Boot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2])
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A host with no model left and its living hero (Quality 3), the flags as given.
func _lone_hero(host_shaken: bool, hero_shaken: bool) -> GameUnit:
	var host := Boot.make_unit(_main, 2, "Squad", [Vector3.ZERO])
	host.unit_properties["quality"] = 5
	var hero := Boot.make_unit(_main, 2, "Captain", [Vector3(0.0254, 0, 0)])
	hero.unit_properties["quality"] = 3
	hero.unit_properties["special_rules"] = ["Hero"]
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	(host.models[0] as ModelInstance).is_alive = false
	host.is_shaken = host_shaken
	hero.is_shaken = hero_shaken
	return host


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_a_stale_dead_host_flag_does_not_fail_the_recovered_lone_hero_from_94() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH
	var host := _lone_hero(true, false)
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).not_contains("already Shaken")
	assert_str(_log_text()).contains("(3+)")   # the hero's own die, rolled


func test_below_94_the_stale_dead_host_flag_still_fails_the_test_without_a_die() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH - 1
	var host := _lone_hero(true, false)
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).contains("Squad is already Shaken — automatically fails morale")
	assert_str(_log_text()).not_contains("(3+)")


func test_a_shaken_lone_hero_fails_without_a_die_from_94_whatever_its_dead_host_says() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH
	var host := _lone_hero(false, true)
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(host, "AI (Squad)")
	assert_str(_log_text()).contains("Squad is already Shaken — automatically fails morale")


func test_a_failed_die_flags_the_recovered_lone_hero_over_the_stale_host_flag() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH
	var flagged := false
	for seed in range(1, 40):
		var host := _lone_hero(true, false)
		_main.seed_tray_rng(seed)
		await _main._solo_morale_test(host, "AI (Squad)")
		var hero := host.get_attached_heroes()[0] as GameUnit
		if hero.is_shaken:
			flagged = true
			break
	assert_bool(flagged).is_true()   # the host's stale flag blocked the toggle, the mirror still flags the hero

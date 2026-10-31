extends GdUnitTestSuite
## SHO-08 (0.3.15, rules 3.6): Unstoppable no longer ignores a minus to hit that comes from the
## shooter's OWN rules (here Bad Shot's -1, gf/orc_marauders); a minus from the target (Evasive) is
## still ignored. From AiActRecorder.EPOCH_73_V36 on; at EPOCH_72_PLAYTEST_RULES the old single clamp
## over the whole sum stays. The volleys are the real table paths over main.tscn (AI and human), the
## to-hit target is read from the battle log's "hits on N+" line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch   # statics leak across gdUnit tests — restored in after_test
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _rifle() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 1
	var wr: Array[String] = ["Unstoppable"]
	w.special_rules = wr
	return w


## A Quality 4 orc squad with an Unstoppable rifle; `rules` are the unit's own.
func _gunners(pid: int, rules: Array) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, pid, "Gunners", [Vector3.ZERO]))
	(u.models[0] as ModelInstance).model_index = 0
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "orc_marauders"
	u.unit_properties["special_rules"] = rules
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [_rifle()]
	u.source_type = "opr"
	u.source_data = src
	return u


## Four models at 10", so two shots can never wipe the unit.
func _target(pid: int, rules: Array) -> GameUnit:
	var t := _reg(E2EBoot.make_unit(_main, pid, "Target", [Vector3(10.0 * INCH, 0, -1.0 * INCH),
		Vector3(10.0 * INCH, 0, 0), Vector3(10.0 * INCH, 0, 1.0 * INCH), Vector3(10.0 * INCH, 0, 2.0 * INCH)]))
	t.unit_properties["special_rules"] = rules
	return t


## ONE AI shot in the shape `_run_ai_shooting` builds (the e2e_spotter_ux_test.gd helper).
func _shots(attacker: GameUnit) -> Array:
	var profiles: Array = AiShooting.profiles_in_range([_rifle()], 0.0)
	return [{"member": attacker, "quality": attacker.get_quality(),
		"alive": attacker.get_alive_count(), "max": attacker.models.size(),
		"reach": 24, "profile": profiles[0]}]


## The AI volley makes the HUMAN roll their saves — press Roll for the absent player.
func _arm_save_pump() -> void:
	var pump := Timer.new()
	pump.name = "SHO08Pump"
	pump.wait_time = 0.02
	pump.one_shot = false
	get_tree().root.add_child(pump)   # freed by free_stray_root_nodes in after_test
	pump.timeout.connect(func() -> void:
		if _main == null or not is_instance_valid(_main):
			return
		for c in _main.get_children():
			var card := c as PromptCard
			if card != null and card.title == "Incoming fire!":
				card.ok_button.pressed.emit())
	pump.start()


func _ai_volley(epoch: int, shooter_rules: Array, target_rules: Array) -> String:
	AiActRecorder.rules_epoch = epoch
	var ai := _gunners(2, shooter_rules)
	var target := _target(1, target_rules)
	_arm_save_pump()
	await _main._solo_resolve_ai_volley(ai, target, _shots(ai), false)
	return _log_text()


## OLD leg: at 72 the AI's Unstoppable rifle ignores its own Bad Shot -1 (4+).
func test_ai_unstoppable_ignores_its_own_bad_shot_at_epoch_72(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Bad Shot"], [])
	assert_str(text).override_failure_message("72: one clamp over the whole sum:\n%s" % text) \
		.contains("Bad Shot -1 → hits on 4+")
	assert_str(text).contains("Unstoppable: negative to-hit modifiers ignored")


## NEW leg: from 73 the own -1 applies (5+) and the log names the kept minus.
func test_ai_unstoppable_keeps_its_own_bad_shot_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, ["Bad Shot"], [])
	assert_str(text).override_failure_message("73: the bearer's own -1 is not ignored:\n%s" % text) \
		.contains("Bad Shot -1 → hits on 5+")
	assert_str(text).contains("Unstoppable: own rules' -1 to hit kept")


## Own -1 kept, the target's Evasive -1 still ignored (5+, not 6+), both named.
func test_ai_unstoppable_keeps_own_minus_and_ignores_evasive_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, ["Bad Shot"], ["Evasive"])
	assert_str(text).override_failure_message("73: only the own -1 counts:\n%s" % text) \
		.contains("hits on 5+")
	assert_str(text).contains("Unstoppable: -1 to hit from other sources ignored, own rules' -1 kept")


## HOLD: an enemy minus alone (Evasive) is still ignored at 73 (4+).
func test_ai_unstoppable_still_ignores_enemy_evasive_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, [], ["Evasive"])
	assert_str(text).override_failure_message("73: Evasive is not the bearer's own rule:\n%s" % text) \
		.contains("Evasive -1 → hits on 4+")
	assert_str(text).contains("Unstoppable: negative to-hit modifiers ignored")


## The human volley folds the same split (5+ at 73).
func test_human_unstoppable_keeps_its_own_bad_shot_at_epoch_73(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var gunners := _gunners(1, ["Bad Shot"])
	var target := _target(2, [])
	await _main._run_human_shooting(gunners, target)
	var text := _log_text()
	assert_str(text).override_failure_message("73: the human's own -1 is not ignored:\n%s" % text) \
		.contains("Bad Shot -1 → hits on 5+")
	assert_str(text).contains("Unstoppable: own rules' -1 to hit kept")

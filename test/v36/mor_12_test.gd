extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-12: the Sergeant bearer no longer buys extra hits on 6s, it strikes one AP
## better (Great Sergeant two). The table stamps the bearer's share of the FIRST profile with attacks
## (AiEv.stamp_sergeant), the EV metric saves that share at the better AP, and the dice path
## (main._solo_resolve_saves) rolls the bearer's hits as their own save batch and logs the rule.
## The rules 3.5 legs (epoch 72) keep the extra-hit share and Great Sergeant's 5-6 window.

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array


func before_test() -> void:
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
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String, models: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "mor12_%s_%d" % [faction, rules.size()]
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	for _i in range(models):
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


func _profiles() -> Array:
	return [{"name": "Rifle", "range": 24, "attacks": 6, "ap": 0, "rules": []},
		{"name": "Blade", "range": 0, "attacks": 6, "ap": 0, "rules": []}]


func _log_text(start: int) -> String:
	var text := ""
	for entry in _main.battle_log.entries().slice(start):
		text += str(entry["text"]) + "\n"
	return text


func test_a_great_sergeant_strikes_its_share_at_ap_plus_2_instead_of_surging_at_epoch_73() -> void:
	var u := _unit(["Great Sergeant"], "aof", "ogres", 3)
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var profiles := AiEv.stamp_sergeant(_profiles(), u)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore first
	var shoot := profiles[0] as Dictionary
	assert_bool(bool(shoot.get("surge", false)) or bool((profiles[1] as Dictionary).get("surge", false))) \
		.override_failure_message("Great Sergeant must leave the extra-hit window from rules 3.6").is_false()
	assert_int(int(shoot.get("sergeant_ap", 0))) \
		.override_failure_message("a Great Sergeant bearer strikes at AP(+2) from rules 3.6").is_equal(2)
	assert_int(int(shoot.get("sergeant_ap_attacks", 0))) \
		.override_failure_message("the bearer's share is 6 attacks / 3 models = 2").is_equal(2)


func test_a_great_sergeant_keeps_its_surge_window_at_epoch_72() -> void:
	var u := _unit(["Great Sergeant"], "aof", "ogres", 3)
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var profiles := AiEv.stamp_sergeant(_profiles(), u)
	AiActRecorder.rules_epoch = epoch0
	var shoot := profiles[0] as Dictionary
	assert_bool(bool(shoot.get("surge", false))).override_failure_message("epoch 72 keeps the facet").is_true()
	assert_int(int(shoot.get("surge_low", 6))).override_failure_message("epoch 72 keeps the 5-6 window").is_equal(5)
	assert_int(int(shoot.get("sergeant_ap", 0))).override_failure_message("no AP bonus at epoch 72").is_equal(0)


func test_the_bearers_share_saves_one_ap_better_in_the_ev_at_epoch_73() -> void:
	# 10 attacks hit on 4+ = 5 hits against Defense 4. The bearer's 2 of 10 attacks bring 1 of those
	# hits, saved on 5+ (2/3 unsaved); the other 4 save on 4+ (2 unsaved): 2 + 2/3 instead of 2.5.
	var prof := {"name": "Rifle", "attacks": 10, "ap": 0, "range": 24, "rules": [],
		"sergeant_ap": 1, "sergeant_ap_attacks": 2}
	var ev: float = AiEv.profile_ev(prof, {"quality": 4, "models": 5},
		{"defense": 4, "tough": 1, "models": 5}, 12.0, false)
	assert_float(ev).override_failure_message("the bearer's share must save at AP(+1), got %f" % ev) \
		.is_equal_approx(2.0 + 2.0 / 3.0, 0.0001)


func test_the_bearers_hits_save_as_their_own_batch_at_ap_plus_1_and_log_it_at_epoch_73() -> void:
	# 60 hits, the bearer's share 12 of 60 attacks = 12 hits, rolled FIRST at AP(+1): Defense 4 saves
	# on 5+, so each 4 among those first 12 save dice becomes a wound the plain volley would have saved.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1300
	var fours := 0
	for i in range(12):
		if rng.randi_range(1, 6) == 4:
			fours += 1
	assert_int(fours).override_failure_message("fixture: seed 1300 must roll a 4 in the first 12").is_greater(0)
	var striker := _unit([], "gf", "battle_brothers", 5)
	var foe := _unit([], "gf", "battle_brothers", 5)
	var plain := {"name": "Rifle", "range": 24, "attacks": 60, "ap": 0, "rules": []}
	var stamped := plain.duplicate()
	stamped["sergeant_ap"] = 1
	stamped["sergeant_ap_attacks"] = 12
	stamped["sergeant_rule"] = "Sergeant"
	_main.seed_tray_rng(1300)
	var baseline: int = await _main._solo_resolve_saves(striker, foe, "Rifle", [], 60, 4,
		plain, false, false, true, false, 12.0)
	_main.seed_tray_rng(1300)
	var log_start: int = _main.battle_log.entries().size()
	var with_sergeant: int = await _main._solo_resolve_saves(striker, foe, "Rifle", [], 60, 4,
		stamped, false, false, true, false, 12.0)
	assert_int(with_sergeant - baseline) \
		.override_failure_message("the bearer's 12 hits must save at AP(+1)").is_equal(fours)
	assert_str(_log_text(log_start)).contains("Sergeant: Fixture strikes 12 hits with AP(+1)")

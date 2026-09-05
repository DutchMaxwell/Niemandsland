extends GdUnitTestSuite

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


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "rule_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func test_violent_profiles_and_expected_wounds_in_every_registered_faction() -> void:
	var covered := 0
	for system in RulesRegistry.SYSTEMS:
		var factions: Dictionary = RulesRegistry.map_for(system).get("factions", {})
		for faction in factions:
			if not factions[faction].has("Violent"):
				continue
			covered += 1
			var u := _unit(["Violent"], system, faction)
			for reach in [0, 24]:
				var profiles := AiEv.stamp_sergeant([
					{"range": reach, "attacks": 12, "ap": 0, "rules": []}], u)
				assert_bool(bool(profiles[0].get("shred", false))) \
					.override_failure_message("%s/%s reach=%d lacks Violent facet" % [system, faction, reach]).is_true()
				assert_float(AiEv.profile_ev(profiles[0], {"quality": 4}, {"defense": 4}, 12.0, false)) \
					.is_equal_approx(4.0, 0.0001)
	assert_int(covered).is_greater_equal(8)


func test_shred_alias_profiles_keep_attack_type_gates() -> void:
	for pair in [["Shred in Melee", 0], ["Shred when Shooting", 24]]:
		var u := _unit([pair[0]], "aof", "change_disciples")
		for reach in [0, 24]:
			var profiles := AiEv.stamp_sergeant([
				{"range": reach, "attacks": 12, "ap": 0, "rules": []}], u)
			if reach == pair[1]:
				assert_bool(bool(profiles[0].get("shred", false))).is_true()
			else:
				assert_bool(bool(profiles[0].get("shred", false))).is_false()


func test_violent_wound_delta_and_named_save_log() -> void:
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 1300
	var ones := 0
	for _i in range(60):
		if expected_rng.randi_range(1, 6) == 1:
			ones += 1
	assert_int(ones).is_greater(0)
	var plain := _unit([], "gf", "infected_colonies")
	var violent := _unit(["Violent"], "gf", "infected_colonies")
	var foe := _unit([], "gf", "infected_colonies")
	var profile := {"range": 0, "ap": 0, "rules": []}
	_main.seed_tray_rng(1300)
	var baseline: int = await _main._solo_resolve_saves(plain, foe, "Blade", [], 60, 2,
		profile, false, true)
	profile["shred"] = _main._solo_shred_facet_applies(violent, 0)
	_main.seed_tray_rng(1300)
	var log_start: int = _main.battle_log.entries().size()
	var wounds: int = await _main._solo_resolve_saves(violent, foe, "Blade", [], 60, 2,
		profile, false, true)
	assert_int(wounds - baseline).is_equal(ones)
	var text := ""
	for entry in _main.battle_log.entries().slice(log_start):
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Violent:")

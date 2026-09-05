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


func test_vicious_profiles_and_regeneration_ev_in_every_registered_faction() -> void:
	var covered := 0
	for system in RulesRegistry.SYSTEMS:
		var factions: Dictionary = RulesRegistry.map_for(system).get("factions", {})
		for faction in factions:
			if not factions[faction].has("Vicious"):
				continue
			covered += 1
			var u := _unit(["Vicious"], system, faction)
			for reach in [0, 24]:
				var profiles := AiEv.stamp_sergeant([
					{"range": reach, "attacks": 12, "ap": 0, "rules": []}], u)
				assert_bool(bool(profiles[0].get("bane", false))).is_true()
				assert_float(AiEv.profile_ev(profiles[0], {"quality": 4},
					{"defense": 4, "regeneration": true, "regen_target": 5}, 12.0, false)) \
					.is_equal_approx(7.0 / 3.0, 0.0001)
	assert_int(covered).is_greater_equal(4)


func test_bane_bypass_flag_preserves_weapon_bane_and_other_bypass_facets() -> void:
	var foe := {"defense": 4, "regeneration": true, "regen_target": 5}
	var profile := {"range": 24, "attacks": 12, "ap": 0, "rules": [], "bane": true,
		"bypass_regen": false}
	assert_float(AiEv.profile_ev(profile, {"quality": 4}, foe, 12.0, false)) \
		.is_equal_approx(7.0 / 3.0, 0.0001)
	profile["unstoppable"] = true
	assert_float(AiEv.profile_ev(profile, {"quality": 4}, foe, 12.0, false)) \
		.is_equal_approx(3.5, 0.0001)
	var u := _unit(["Vicious"], "gf", "goblin_reclaimers")
	var weapon := {"range": 24, "attacks": 12, "ap": 0, "rules": ["Bane"], "bane": true}
	AiEv.stamp_sergeant([weapon], u)
	assert_float(AiEv.profile_ev(weapon, {"quality": 4}, foe, 12.0, false)) \
		.is_equal_approx(3.5, 0.0001)


func test_vicious_real_rerolls_named_log_and_regeneration_remains_available() -> void:
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 1300
	var faces: Array = []
	var rerolls: Array = []
	var sixes := 0
	for _i in range(60):
		var face := expected_rng.randi_range(1, 6)
		faces.append(face)
		if face == 6:
			sixes += 1
	for _i in range(sixes):
		rerolls.append(expected_rng.randi_range(1, 6))
	assert_int(sixes).is_greater(0)
	var vicious := _unit(["Vicious"], "gf", "goblin_reclaimers")
	var foe := _unit([], "gf", "goblin_reclaimers")
	var profile := {"range": 24, "ap": 0, "rules": []}
	assert_bool(_main._solo_ignores_regen(vicious, profile)).is_false()
	_main.seed_tray_rng(1300)
	var log_start: int = _main.battle_log.entries().size()
	var wounds: int = await _main._solo_resolve_saves(vicious, foe, "Rifle", [], 60, 4,
		profile, false, false)
	assert_int(wounds).is_equal(60 - AiCombatMath.blocks_with_bane(faces, rerolls, 4, 0))
	var text := ""
	for entry in _main.battle_log.entries().slice(log_start):
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Vicious:")

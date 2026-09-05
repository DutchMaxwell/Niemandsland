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


const CONTEXTS := [["gf", "havoc_brothers"], ["aof", "havoc_dwarves"], ["aof", "havoc_warriors"]]


func test_piercing_warrior_and_existing_havocbound_share_the_conditional_gate() -> void:
	for context in CONTEXTS:
		for rule in ["Piercing Warrior", "Havocbound"]:
			var unit := _unit([rule], context[0], context[1])
			var foe := _unit([], context[0], context[1])
			for reach in [0, 24]:
				for charging in [false, true]:
					for distance in [-1.0, 9.0, 9.01]:
						var profile := {"range": reach, "attacks": 12, "ap": 0, "rules": []}
						var active: bool = charging or (reach > 0 and distance > 9.0)
						var expected := profile.duplicate(true)
						expected["ap"] = 1 if active else 0
						var stamped := AiEv.stamp_conditional_ap([profile], unit)
						var target := {"defense": 4, "charging": not charging}
						assert_float(AiEv.profile_ev(stamped[0], {"quality": 4}, target, distance, charging)) \
							.is_equal_approx(AiEv.profile_ev(expected, {"quality": 4}, target, distance, charging), 0.0001)
						var parts: Array = _main._solo_conditional_ap_parts(profile, unit, foe, charging, distance, reach == 0)
						assert_array(parts).is_equal([{"name": rule, "bonus": 1}] if active else [])


func test_existing_charge_ap_ev_uses_the_attacker_charge_flag() -> void:
	var p := {"range": 0, "attacks": 12, "ap": 0, "rules": [],
		"cond_ap": [{"ap_bonus": 1, "condition": "on_charge"}]}
	for charging in [false, true]:
		var expected := {"range": 0, "attacks": 12, "ap": 1 if charging else 0, "rules": []}
		var target := {"defense": 4, "charging": not charging}
		assert_float(AiEv.profile_ev(p, {"quality": 4}, target, 0.0, charging)) \
			.is_equal_approx(AiEv.profile_ev(expected, {"quality": 4}, target, 0.0, charging), 0.0001)


func test_piercing_warrior_registry_and_real_named_ap_save() -> void:
	for context in CONTEXTS:
		assert_bool(RulesRegistry.has_primitive(context[0], context[1], "Piercing Warrior")).is_true()
	var unit := _unit(["Piercing Warrior"], "gf", "havoc_brothers")
	var foe := _unit([], "gf", "havoc_brothers")
	var start: int = _main.battle_log.entries().size()
	await _main._solo_resolve_saves(unit, foe, "Blade", [], 1, 4,
		{"range": 0, "ap": 0, "rules": ["Piercing Warrior"]}, false, true, true, true)
	var text := ""
	var named := 0
	for entry in _main.battle_log.entries().slice(start):
		var line := str(entry["text"])
		text += line + "\n"
		if line.contains("Piercing Warrior: AP(+1)"):
			named += 1
	assert_int(named).is_equal(1)
	assert_str(text).contains("saves on 5+")

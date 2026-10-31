extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
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


const CONTEXTS := [["gf", "knight_brothers"], ["gf", "knight_prime_brothers"], ["aof", "kingdom_of_angels"]]


func test_warding_ev_uses_normal_and_spell_ignore_targets() -> void:
	for context in CONTEXTS:
		var unit := _unit(["Warding"], context[0], context[1])
		unit.unit_properties["defense"] = 4
		var ctx := AiEv.ctx_for(unit)
		assert_int(ctx["regen_target"]).is_equal(6)
		assert_float(AiEv.profile_ev({"range": 24, "attacks": 12, "ap": 0}, {"quality": 4}, ctx, 12.0, false)) \
			.is_equal_approx(2.5, 0.0001)
		assert_float(AiSpell.spell_damage_ev(6, ctx)).is_equal_approx(1.5, 0.0001)


## Below the rules 3.6 epoch Warding needs every model, and plain Regeneration reads the host alone.
func test_warding_requires_all_models_and_keeps_the_best_target_for_each_source_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var unit := _unit(["Warding"], "gf", "knight_brothers")
	unit.unit_properties["defense"] = 4
	var hero := _unit([], "gf", "knight_brothers")
	unit.unit_properties["attached_heroes"] = [hero]
	assert_int(AiEv.ctx_for(unit)["regen_target"]).is_equal(0)
	hero.unit_properties["special_rules"] = ["Warding"]
	unit.unit_properties["special_rules"] = ["Warding", "Regeneration"]
	var ctx := AiEv.ctx_for(unit)
	assert_int(ctx["regen_target"]).is_equal(5)
	assert_float(AiSpell.spell_damage_ev(6, ctx)).is_equal_approx(1.5, 0.0001)


## Rules 3.6 (row MOR-02, ruling D-MOST): Warding counts most models, a joined hero being one model. One
## Warding model with a hero without it is an exact half (off); three with the same hero are 3 of 4 (on).
func test_warding_counts_most_models_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _unit(["Warding"], "gf", "knight_brothers")
	unit.unit_properties["defense"] = 4
	unit.unit_properties["attached_heroes"] = [_unit([], "gf", "knight_brothers")]
	assert_int(AiEv.ctx_for(unit)["regen_target"]).is_equal(0)
	for _i in 2:
		var model := ModelInstance.new()
		model.is_alive = true
		unit.models.append(model)
	assert_int(AiEv.ctx_for(unit)["regen_target"]).is_equal(6)


func test_warding_real_ignore_rolls_and_named_log_for_both_sources() -> void:
	var unit := _unit(["Warding"], "gf", "knight_brothers")
	for from_spell in [false, true]:
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.seed = 1300
		var target := 4 if from_spell else 6
		var ignored := 0
		for _i in range(60):
			if expected_rng.randi_range(1, 6) >= target:
				ignored += 1
		assert_int(ignored).is_greater(0)
		_main.seed_tray_rng(1300)
		var start: int = _main.battle_log.entries().size()
		var landed: int = await _main._solo_apply_regeneration(unit, 60, from_spell)
		assert_int(landed).is_equal(60 - ignored)
		var text := ""
		for entry in _main.battle_log.entries().slice(start):
			text += str(entry["text"]) + "\n"
		assert_str(text).contains("Warding")

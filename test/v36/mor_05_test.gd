extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-05: the Fortified and Shielded families read "most models" instead of
## "all models" (ruling D-MOST) from the wave's epoch on. A squad whose models carry the rule keeps it when
## a joined hero without it makes up the minority; an exact half is still off; below the wave's epoch the
## old all-models read stays. The core's twin is core/nml-core/src/tests/unit/v36_morale.rs.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixture helpers ==========================================================================

## `models` models carrying `rules`, registered so the save plumbing finds them.
func _unit(pid: int, unit_name: String, faction: String, rules: Array, models: int,
		at: Vector3 = Vector3(0.2, 0.0, 0.2)) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	for i in range(u.models.size()):
		(u.models[i] as ModelInstance).model_index = i
	u.unit_properties["special_rules"] = rules
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	return u


## One joined hero carrying `rules`.
func _join_hero(host: GameUnit, rules: Array) -> GameUnit:
	var h := _unit(int(host.unit_properties.get("player_id", 1)), "Hero", str(host.unit_properties["faction_folder"]),
		rules, 1, Vector3(0.4, 0.0, 0.2))
	h.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [h]
	return h


## A squad of `models` carriers of `rules` with one joined hero that carries none of them.
func _squad_with_plain_hero(rules: Array, models: int, faction: String = "") -> GameUnit:
	var squad := _unit(1, "Squad", faction, rules, models)
	_join_hero(squad, ["Hero"])
	return squad


func _inject_gf_map(faction: String, entries: Dictionary) -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {faction: entries}, "common": {}}


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _set_epoch(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch


# === the EV twin ==============================================================================

func test_ev_fortified_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Fortified"], 5))
	assert_bool(bool(ctx["fortified"])) \
		.override_failure_message("five of six models carry Fortified: most models, the squad keeps it").is_true()


func test_ev_fortified_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Fortified"], 5))
	assert_bool(bool(ctx["fortified"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


func test_ev_a_lone_fortified_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Fortified"], 1))
	assert_bool(bool(ctx["fortified"])) \
		.override_failure_message("one of two models is exactly half, not most").is_false()


func test_ev_warden_alias_keeps_its_over_9_gate_with_a_plain_joined_hero_at_epoch_73() -> void:
	_inject_gf_map("test_wardens", {"Warden": {"primitive": "Fortified", "rated": false,
		"params": {"incoming_ap_reduction": 1, "over_in": 9}}})
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Warden"], 5, "test_wardens"))
	assert_float(float(ctx["fortified_over_in"])) \
		.override_failure_message("five of six models carry Warden: the alias stays on").is_equal(9.0)


func test_ev_warden_alias_is_off_with_a_plain_joined_hero_at_epoch_72() -> void:
	_inject_gf_map("test_wardens", {"Warden": {"primitive": "Fortified", "rated": false,
		"params": {"incoming_ap_reduction": 1, "over_in": 9}}})
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Warden"], 5, "test_wardens"))
	assert_float(float(ctx["fortified_over_in"])) \
		.override_failure_message("the old reading: one plain hero strips the alias").is_equal(-1.0)


func test_ev_shielded_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Shielded"], 5))
	assert_bool(bool(ctx["shielded"])) \
		.override_failure_message("five of six models carry Shielded: most models, the squad keeps it").is_true()


func test_ev_shielded_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Shielded"], 5))
	assert_bool(bool(ctx["shielded"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


func test_ev_a_lone_shielded_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Shielded"], 1))
	assert_bool(bool(ctx["shielded"])) \
		.override_failure_message("one of two models is exactly half, not most").is_false()


# === the table's dice path ====================================================================

func test_table_shielded_squad_keeps_the_defense_bonus_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Shielded"], 5)
	var parts: Array = _main._solo_defense_parts(squad, AiCombatMath.HIT_SOURCE_SHOOTING)
	var names: Array = parts.map(func(p): return str((p as Dictionary)["name"]))
	assert_array(names) \
		.override_failure_message("five of six models carry Shielded: the +1 Defense part stays, and the log names the majority") \
		.is_equal(["Shielded (most of its models carry it)"])


func test_table_shielded_squad_loses_the_defense_bonus_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Shielded"], 5)
	var parts: Array = _main._solo_defense_parts(squad, AiCombatMath.HIT_SOURCE_SHOOTING)
	assert_int(parts.size()) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_equal(0)


func test_table_fortified_squad_keeps_the_ap_reduction_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Fortified"], 5)
	var striker := _unit(2, "Raiders", "", [], 2, Vector3(0.5, 0.0, 0.5))
	var profile := {"name": "Claw", "ap": 1, "deadly": 0, "rules": []}
	await _main._solo_save_batch(striker, squad, "Claw", 3, 4, 1, profile, false, false)
	assert_str(_log_text()) \
		.override_failure_message("five of six models carry Fortified: the AP(-1) must apply:\n%s" % _log_text()) \
		.contains("Fortified: Squad takes the hits at AP(0) instead of AP(1)")
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: the line must say the majority kept the rule on:\n%s" % _log_text()) \
		.contains("(most of its models carry it)")
	await E2EBoot.settle(get_tree())


func test_table_fortified_squad_loses_the_ap_reduction_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Fortified"], 5)
	var striker := _unit(2, "Raiders", "", [], 2, Vector3(0.5, 0.0, 0.5))
	var profile := {"name": "Claw", "ap": 1, "deadly": 0, "rules": []}
	await _main._solo_save_batch(striker, squad, "Claw", 3, 4, 1, profile, false, false)
	assert_str(_log_text()) \
		.override_failure_message("the old reading: one plain hero strips the whole squad:\n%s" % _log_text()) \
		.not_contains("Fortified: Squad takes the hits")
	await E2EBoot.settle(get_tree())

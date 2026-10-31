extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-05b: the Guarded family (Guarded, Versatile Defense, Sturdy, Safety Gear,
## Tenacious) reads "most models" instead of "all models" (ruling D-MOST) from the wave's epoch on. A
## squad whose models carry the rule keeps it when a joined hero without it makes up the minority; an
## exact half is still off; below the wave's epoch the old all-models read stays. The core's twin is
## core/nml-core/src/tests/unit/v36_mor_05b.rs.

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


func _set_epoch(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch


# === the EV twin ==============================================================================

func test_ev_guarded_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Guarded"], 5))
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("five of six models carry Guarded: most models, the squad keeps it").is_true()


func test_ev_guarded_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Guarded"], 5))
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


func test_ev_a_lone_guarded_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Guarded"], 1))
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("one of two models is exactly half, not most").is_false()


func test_ev_guarded_squad_with_a_guarded_hero_stays_on_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _unit(1, "Squad", "", ["Guarded"], 5)
	_join_hero(squad, ["Hero", "Guarded"])
	var ctx := AiEv.ctx_for(squad)
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("every model carries it: the majority read agrees with the old one").is_true()


func test_ev_versatile_defense_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Versatile Defense"], 5))
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("five of six models carry Versatile Defense: most models, the squad keeps it").is_true()


func test_ev_versatile_defense_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Versatile Defense"], 5))
	assert_bool(bool(ctx["guarded"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


# === the table's over-9" defense rule =========================================================

func test_table_guarded_squad_projects_the_rule_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Guarded"], 5)
	assert_str(_main._solo_over9_defense_rule(squad)) \
		.override_failure_message("five of six models carry Guarded: the over-9\" +1 stays on").is_equal("Guarded")


func test_table_guarded_squad_loses_the_rule_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Guarded"], 5)
	assert_str(_main._solo_over9_defense_rule(squad)) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_equal("")


func test_table_a_lone_guarded_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Guarded"], 1)
	assert_str(_main._solo_over9_defense_rule(squad)) \
		.override_failure_message("one of two models is exactly half, not most").is_equal("")


func test_table_log_names_the_majority_when_it_keeps_the_rule_on() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Guarded"], 5)
	assert_str(_main._solo_most_models_note(squad, "Guarded")) \
		.override_failure_message("rules-must-log: the battle log must say the majority kept the rule on") \
		.is_equal(" (most of its models carry it)")


func test_table_log_note_is_empty_when_every_model_carries_the_rule() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _unit(1, "Squad", "", ["Guarded"], 5)
	_join_hero(squad, ["Hero", "Guarded"])
	assert_str(_main._solo_most_models_note(squad, "Guarded")) \
		.override_failure_message("no minority to explain: the tail stays empty").is_equal("")


func test_table_shooting_log_says_the_majority_kept_guarded_on() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _unit(1, "Squad", "", ["Guarded"], 5, Vector3(0.0, 0.0, 0.5))
	_join_hero(squad, ["Hero"])
	var striker := _unit(2, "Raiders", "", [], 2, Vector3.ZERO)
	assert_bool(_main._solo_ai_volley_distance_in(striker, squad) > AiCombatMath.LONG_RANGE_IN) \
		.override_failure_message("precondition: the shot is from over 9\"").is_true()
	await _main._solo_resolve_ai_volley(striker, squad, [])
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("rules-must-log: the shot line must carry the majority note:\n%s" % text) \
		.contains("Guarded): shot from over 9\" — +1 Defense")
	assert_str(text) \
		.override_failure_message("rules-must-log: the line must say the majority kept the rule on:\n%s" % text) \
		.contains("(most of its models carry it)")
	await E2EBoot.settle(get_tree())

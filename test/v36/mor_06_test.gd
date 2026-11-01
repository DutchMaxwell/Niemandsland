extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-06: Steadfast/Battleborn recovery, Evasive/Melee Evasion, the two
## Shrouding primitives and Grounded Evasion read "most models" instead of "all models" (ruling
## D-MOST) from the wave's epoch on. A squad whose models carry the rule keeps it when a joined hero
## without it makes up the minority; below the wave's epoch the old all-models read stays. The core's
## twin is core/nml-core/src/tests/unit/v36_mor_06.rs.

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

func test_ev_evasive_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Evasive"], 5, "battle_brothers"))
	assert_bool(bool(ctx["evasive"])) \
		.override_failure_message("five of six models carry Evasive: most models, the squad keeps it").is_true()


func test_ev_evasive_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Evasive"], 5, "battle_brothers"))
	assert_bool(bool(ctx["evasive"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


func test_ev_melee_evasion_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Melee Evasion"], 5, "dark_elf_raiders"))
	assert_bool(bool(ctx["melee_evasion"])) \
		.override_failure_message("five of six models carry Melee Evasion: most models, the squad keeps it").is_true()


func test_ev_melee_evasion_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Melee Evasion"], 5, "dark_elf_raiders"))
	assert_bool(bool(ctx["melee_evasion"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


func test_ev_ranged_shrouding_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Ranged Shrouding"], 5, "custodian_brothers"))
	assert_bool(bool(ctx["ranged_shrouding"])) \
		.override_failure_message("five of six models carry Ranged Shrouding: most models, the squad keeps it").is_true()


func test_ev_ranged_shrouding_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Ranged Shrouding"], 5, "custodian_brothers"))
	assert_bool(bool(ctx["ranged_shrouding"])) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_false()


# === the table's path =========================================================================

func test_table_steadfast_recovery_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Steadfast"], 5, "change_disciples")
	assert_str(_main._solo_round_start_recovery_rule(squad)) \
		.override_failure_message("five of six models carry Steadfast: the recovery die stays").is_equal("Steadfast")


func test_table_steadfast_recovery_needs_every_model_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Steadfast"], 5, "change_disciples")
	assert_str(_main._solo_round_start_recovery_rule(squad)) \
		.override_failure_message("the old reading: one plain hero strips the recovery die").is_equal("")


func test_table_melee_shrouding_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Melee Shrouding"], 5, "battle_brothers")
	assert_float(SoloController.melee_shroud_charge_in(12.0, squad)) \
		.override_failure_message("five of six models carry Melee Shrouding: the charge penalty stays").is_equal(10.0)


func test_table_melee_shrouding_needs_every_model_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Melee Shrouding"], 5, "battle_brothers")
	assert_float(SoloController.melee_shroud_charge_in(12.0, squad)) \
		.override_failure_message("the old reading: one plain hero strips the charge penalty").is_equal(12.0)


func test_table_ranged_shrouding_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Ranged Shrouding"], 5, "custodian_brothers")
	assert_float(SoloController.ranged_shroud_reach_in(24.0, squad)) \
		.override_failure_message("five of six models carry Ranged Shrouding: the range penalty stays").is_equal(20.0)


func test_table_ranged_shrouding_needs_every_model_at_epoch_72() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Ranged Shrouding"], 5, "custodian_brothers")
	assert_float(SoloController.ranged_shroud_reach_in(24.0, squad)) \
		.override_failure_message("the old reading: one plain hero strips the range penalty").is_equal(24.0)


func test_recorder_melee_shrouding_keeps_with_a_plain_joined_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Melee Shrouding"], 5, "battle_brothers")
	assert_int(AiActRecorder._melee_shroud_params(squad).size()) \
		.override_failure_message("five of six models carry Melee Shrouding: the replay read keeps it").is_equal(2)

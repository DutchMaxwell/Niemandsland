extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-07: "Spell Resistance" replaces the 3.5 "Resistance" name and both read
## "most models" (ruling D-MOST) from EPOCH_73_V36; below it the every-model read stays. The core's
## twin is core/nml-core/src/tests/unit/v36_mor_07.rs.

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

func test_ev_spell_resistance_keeps_its_targets_with_a_plain_hero_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Spell Resistance"], 5, "alien_hives"))
	assert_int(int(ctx["regen_target"])) \
		.override_failure_message("five of six models carry Spell Resistance: 6+ against wounds").is_equal(6)
	assert_int(int(ctx["regen_target_spell"])) \
		.override_failure_message("a spell wound is ignored on 2+").is_equal(2)


func test_ev_spell_resistance_tie_is_off_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var ctx := AiEv.ctx_for(_squad_with_plain_hero(["Spell Resistance"], 1, "alien_hives"))
	assert_int(int(ctx["regen_target"])) \
		.override_failure_message("one of two models is an exact half, not most").is_equal(0)


# === the table's path =========================================================================

func test_table_spell_resistance_names_itself_and_rolls_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Spell Resistance"], 5, "alien_hives")
	assert_int(int(_main._solo_regen_pick(squad, true).get("target"))) \
		.override_failure_message("a spell wound is ignored on 2+").is_equal(2)
	assert_int(int(_main._solo_regen_pick(squad, false).get("target"))) \
		.override_failure_message("a non-spell wound is ignored on 6+").is_equal(6)
	assert_str(str(_main._solo_regen_pick(squad, false).get("name"))) \
		.override_failure_message("the roll line names the 3.6 rule").is_equal("Spell Resistance")


func test_table_spell_resistance_tie_is_off_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Spell Resistance"], 1, "alien_hives")
	assert_int(int(_main._solo_regen_pick(squad, false).get("target"))) \
		.override_failure_message("one of two models is an exact half, not most").is_equal(0)


func test_table_resistance_keeps_every_model_below_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var squad := _squad_with_plain_hero(["Resistance"], 5, "alien_hives")
	assert_int(int(_main._solo_regen_pick(squad, false).get("target"))) \
		.override_failure_message("the old reading: one plain hero strips the whole squad").is_equal(0)


func test_table_resistance_takes_most_models_at_epoch_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _squad_with_plain_hero(["Resistance"], 5, "alien_hives")
	assert_int(int(_main._solo_regen_pick(squad, false).get("target"))) \
		.override_failure_message("five of six models carry it: the most-models read holds").is_equal(6)

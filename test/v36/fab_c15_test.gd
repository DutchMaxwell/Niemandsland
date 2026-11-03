extends GdUnitTestSuite
## FAB-C15 — rules 3.6 "Stealth Buff" is a once-grant of Stealth to ONE
## friendly unit within 12", not a permanent Stealth on the bearer. From 73
## the common entry is a Utility Buff granting `Stealth`; the bearer is no
## longer its own Stealth carrier. Second leg: "Spell Resistance" no longer
## carries `all_models`, and the mixed unit still takes the most-models read.

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


func _set_epoch(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


# === the data leg =============================================================================

func test_the_common_stealth_buff_entry_is_a_once_grant_at_73() -> void:
	RulesRegistry.reset_cache()
	var got := RulesRegistry.lookup("gf", "robot_legions", "Stealth Buff")
	assert_str(str(got.get("primitive", ""))) \
		.override_failure_message("the 3.6 entry is a Utility Buff, not a Stealth primitive") \
		.is_equal("Utility Buff")
	var params: Dictionary = got.get("params", {})
	assert_str(str(params.get("grants_rule", ""))).is_equal("Stealth")
	assert_str(str(params.get("target", ""))).is_equal("friendly")
	assert_int(int(params.get("max_targets", 0))).is_equal(1)
	assert_int(int(params.get("range_in", 0))).is_equal(12)
	assert_bool(bool(params.get("once", false))).is_true()


func test_spell_resistance_no_longer_carries_all_models() -> void:
	RulesRegistry.reset_cache()
	for system in ["gf", "aof"]:
		var got := RulesRegistry.lookup(system, "robot_legions", "Spell Resistance")
		assert_bool((got.get("params", {}) as Dictionary).has("all_models")) \
			.override_failure_message("%s: the 3.6 text has no all-models clause" % system) \
			.is_false()


# === the bearer leg ===========================================================================

func test_the_stealth_buff_bearer_is_not_stealth_itself_at_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var bearer := _unit(1, "Bearer", "robot_legions", ["Stealth Buff"], 1)
	var shooter := _unit(2, "Shooter", "robot_legions", [], 1, Vector3(12.0 * 0.0254, 0.0, 0.0))
	var info: Dictionary = _main._solo_hit_mod_info(shooter, bearer, 12.0, false)
	assert_int(int(info.get("mod", 0))) \
		.override_failure_message("a shot at the bearer past 9\" must not pay a Stealth -1") \
		.is_equal(0)


func test_the_table_grants_stealth_to_a_friendly_within_twelve_at_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var bearer := _unit(1, "Bearer", "robot_legions", ["Stealth Buff"], 1)
	var friend := _unit(1, "Friend", "robot_legions", [], 3, Vector3(5.0 * 0.0254, 0.0, 0.0))
	_main._solo_apply_utility_buffs(bearer)
	var records: Array = _main._solo_spell_mods.get(friend.get_instance_id(), [])
	assert_array(records).override_failure_message("the 5\" friend receives the once-grant").has_size(1)
	var rec: Dictionary = records[0]
	assert_str(str(rec.get("grants_rule", ""))).is_equal("Stealth")
	assert_bool(friend.has_special_rule("Stealth")) \
		.override_failure_message("the granted Stealth lands on the picked friendly").is_true()
	assert_bool(bearer.has_special_rule("Stealth")) \
		.override_failure_message("the bearer stays out of it").is_false()
	var log_text := _log_text()
	assert_str(log_text).override_failure_message("log: %s" % log_text.strip_edges()).contains("Stealth Buff")
	assert_str(log_text).contains("Friend")
	assert_str(log_text).contains("Stealth")


# === the Spell Resistance guard ===============================================================

func test_a_mixed_unit_keeps_the_most_models_spell_resistance_at_73() -> void:
	_set_epoch(AiActRecorder.EPOCH_73_V36)
	var squad := _unit(1, "Squad", "robot_legions", ["Spell Resistance"], 3)
	var hero := _unit(1, "Hero", "robot_legions", ["Hero"], 1, Vector3(0.4, 0.0, 0.2))
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	assert_int(int(_main._solo_regen_pick(squad, false).get("target"))) \
		.override_failure_message("three of four models: the 6+ most-models read holds").is_equal(6)
	assert_int(int(_main._solo_regen_pick(squad, true).get("target"))) \
		.override_failure_message("a spell wound is ignored on 2+").is_equal(2)

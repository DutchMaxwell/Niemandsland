extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-01a: an Indirect weapon may fire at an enemy out of line of sight only when
## its unit used a Hold action. A unit that moved fires it like any other gun and needs sight. The AI
## unit's Hold is its activation action; a human unit counts as holding when it has not moved this round
## (the table stores no Hold action for human units). Drives the real legality gate and the AI target
## pick over main.tscn with a container wall between shooter and target (the #182 suite's shape).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	RulesRegistry.reset_cache()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A registered unit with ONE 36" ranged weapon carrying `rules`, at Defense `defense`.
func _armed_unit(pid: int, unit_name: String, pos: Vector3, rules: Array, defense: int = 4) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	u.unit_properties["defense"] = defense
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Launcher"
	w.range_value = 36
	w.attacks = 2
	var sr: Array[String] = []
	for r in rules:
		sr.append(str(r))
	w.special_rules = sr
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A solid container wall across the line between x=-0.3 and x=+0.3 (z = 0).
func _wall_between(o: Node3D) -> void:
	for i in range(41):
		var t := float(i) / 40.0
		if t < 0.4 or t > 0.6:
			continue
		var p := Vector3(-0.3, 0, 0).lerp(Vector3(0.3, 0, 0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER


func test_the_shipped_indirect_entries_ask_for_a_hold_before_the_sight_waiver() -> void:
	for sys in ["gf", "aof"]:
		assert_bool(bool(RulesRegistry.param(sys, "", "Indirect", "los_needs_hold", false))) \
			.override_failure_message("%s common Indirect must carry los_needs_hold = true" % sys).is_true()


func test_a_human_indirect_unit_that_moved_a_nudge_needs_line_of_sight_at_epoch_73() -> void:
	_wall_between(_main.terrain_overlay)
	var target := _armed_unit(2, "Hidden", Vector3(0.3, 0, 0), [])
	var arty := _armed_unit(1, "Arty", Vector3(-0.3, 0, 0), ["Indirect", "Blast(3)"])
	_main.opr_army_manager.start_game()
	assert_str(_main._solo_validate_target(arty, target, false)) \
		.override_failure_message("not moved this round = Hold: the waiver stands").is_equal("")
	# 0.11": just over the table's 0.1" hand-jitter floor, the smallest drop that counts as a move.
	await _main._on_units_dropped([{"node": (arty.models[0] as ModelInstance).node, "inches": 0.11}])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_str(_main._solo_validate_target(arty, target, false)) \
		.override_failure_message("epoch 72 keeps the 3.5 waiver after a move").is_equal("")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var why: String = _main._solo_validate_target(arty, target, false)
	assert_str(why).override_failure_message("a moved human Indirect unit needs sight at epoch 73, got '%s'" % why) \
		.contains("no model has line of sight")
	assert_str(why).override_failure_message("the refusal names the Hold rule: '%s'" % why) \
		.contains("Indirect needs Hold: the unit moved this round")


## The AI pick: a juicy Defense-6 enemy behind the wall, a Defense-2 enemy in plain sight.
func test_the_ai_plans_no_unseen_indirect_shot_after_an_advance_at_epoch_73() -> void:
	_wall_between(_main.terrain_overlay)
	var arty := _armed_unit(2, "AiArty", Vector3(-0.3, 0, 0), ["Indirect"])
	_armed_unit(1, "Juicy", Vector3(0.3, 0, 0), [], 6)
	_armed_unit(1, "Tough", Vector3(-0.3, 0, 0.5), [], 2)
	var sc: SoloController = _main.solo_controller
	var hold_pick: GameUnit = sc.suggest_target(arty, AiDecision.Action.HOLD)
	assert_str(hold_pick.get_name() if hold_pick != null else "-") \
		.override_failure_message("a Hold keeps the waiver: the juicy unseen target").is_equal("Juicy")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old_pick: GameUnit = sc.suggest_target(arty, AiDecision.Action.ADVANCE)
	assert_str(old_pick.get_name() if old_pick != null else "-") \
		.override_failure_message("epoch 72: the moved AI keeps the 3.5 waiver").is_equal("Juicy")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var adv_pick: GameUnit = sc.suggest_target(arty, AiDecision.Action.ADVANCE)
	assert_str(adv_pick.get_name() if adv_pick != null else "-") \
		.override_failure_message("after an Advance only the seen target is a shot at epoch 73").is_equal("Tough")

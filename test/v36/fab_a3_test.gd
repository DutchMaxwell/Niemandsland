extends GdUnitTestSuite
## Rules 3.6 wave, row FAB-A3: the Indirect entry lifts cover granted by sight blockers only. The
## table grants Cover terrain and nothing else, so from EPOCH_73_V36 a HELD Indirect shot keeps the
## target's Cover +1 too. Below 73 the unconditional skip stands, and Blast / Ignores Cover drop
## cover at every epoch. Drives the real AI volley (_solo_resolve_ai_volley) over main.tscn, the
## path the AI and the human save resolution share, and reads the battle log the rule writes.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## A point far enough from the shooter to leave room for a forest cell under the target only.
const TARGET_POS := Vector3(0.0, 0.0, 0.5)

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


## A registered single-model unit at `pos`; `cover` paints one forest cell under it.
func _unit(pid: int, unit_name: String, pos: Vector3, cover: bool = false) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 2
	u.unit_properties["defense"] = 4
	_main.opr_army_manager.game_units[u.unit_id] = u
	if cover:
		var o: Node3D = _main.terrain_overlay
		o.grid_cells[o.world_to_cell(pos)] = o.TerrainType.FOREST
	return u


## The shot list `_solo_resolve_ai_volley` reads: one ranged weapon with `rules`.
func _shots(attacker: GameUnit, rules: Array[String]) -> Array:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Launcher"
	w.range_value = 24
	w.attacks = 10
	w.count = 1
	w.special_rules = rules
	return [{"member": attacker, "quality": attacker.get_quality(),
		"alive": attacker.get_alive_count(), "max": attacker.models.size(),
		"reach": 24, "profile": AiShooting.profiles_in_range([w], 0.0)[0]}]


## Mark the unit as having moved this round (the table's Hold = not moved this round).
func _mark_moved(u: GameUnit) -> void:
	u.unit_properties["moved_round"] = _main.opr_army_manager.current_round


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## One volley from an Indirect shooter at a covered target, at `epoch`, moved or held.
func _volley_at(epoch: int, moved: bool, rules: Array[String]) -> String:
	AiActRecorder.rules_epoch = epoch
	var shooter := _unit(2, "Arty", Vector3.ZERO)
	var target := _unit(2, "Hidden", TARGET_POS, true)
	assert_bool(_main._solo_majority_in_cover(target)) \
		.override_failure_message("fixture: the target must stand in cover").is_true()
	if moved:
		_mark_moved(shooter)
	seed(20250803)
	_main.seed_tray_rng(20250803)
	await _main._solo_resolve_ai_volley(shooter, target, _shots(shooter, rules), moved)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func test_a_held_indirect_shot_lets_cover_count_at_epoch_73() -> void:
	var text := await _volley_at(AiActRecorder.EPOCH_73_V36, false, ["Indirect"] as Array[String])
	assert_str(text).override_failure_message("the kept cover names itself: %s" % text) \
		.contains("cover counts")
	assert_str(text).override_failure_message("the target saves at the covered 3+: %s" % text) \
		.contains("saves on 3+")


func test_a_held_indirect_shot_ignores_cover_at_epoch_72() -> void:
	var text := await _volley_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false, ["Indirect"] as Array[String])
	assert_str(text).override_failure_message("epoch 72 keeps dropping cover: %s" % text) \
		.not_contains("cover counts")
	assert_str(text).override_failure_message("and never claims the covered save: %s" % text) \
		.not_contains("saves on 3+")


func test_blast_and_ignores_cover_drop_cover_at_epoch_73_whether_moved_or_held() -> void:
	for rule in ["Blast(3)", "Ignores Cover"]:
		for moved in [true, false]:
			var text := await _volley_at(AiActRecorder.EPOCH_73_V36, moved, [rule] as Array[String])
			assert_str(text).override_failure_message("%s drops cover (moved %s): %s" % [rule, moved, text]) \
				.not_contains("saves on 3+")
			assert_str(text).override_failure_message("and never names a kept cover: %s" % text) \
				.not_contains("cover counts")

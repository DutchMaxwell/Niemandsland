extends GdUnitTestSuite
## DAT-16a-move (0.3.15, rules 3.6): a move names the move rules that widened it, and a held-back
## ambush names Repel Ambushers.
##
## Two rules applied silently until now:
##   • Move bands — Agile / Scurry / Lustbound (Quick shape) and Highborn (Royal Legion shape) widen
##     Advance / Rush / Charge. A committed move now writes ONE battle-log line naming the carried
##     rules that did it; a unit without such a rule stays quiet.
##   • Repel Ambushers — an enemy's 12" ring pushes an Ambush arrival out. The placement now names
##     the rule and the unit that carries it.
## No inches move: the bands and placements are asserted unchanged where they are cheap to assert.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TRAY := Vector3(5.0, 0.0, 0.0)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A real GF book unit: its own faction section holds the rule, so the registry supplies the inches.
func _carrier(pid: int, name: String, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, name, [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _drop(u: GameUnit) -> void:
	_main._on_battle_log_dropped([{"node": (u.models[0] as ModelInstance).node, "arc_in": 5.0}])


func _zone() -> Rect2:
	return Rect2(Vector2(-0.61, -0.61), Vector2(1.22, 1.22))


## Dark Elf Raiders' Agile (+1\" Advance, +2\" Rush/Charge) — the move names the rule.
func test_an_agile_move_names_agile_in_the_battle_log() -> void:
	var u := _carrier(1, "Dark Riders", "dark_elf_raiders", ["Agile"])
	_drop(u)
	assert_str(_log_text()) \
		.override_failure_message("Agile widened the move bands and NO log line names it") \
		.contains("move bands widened by Agile")


## Ratmen Clans' Scurry (+1\"/+2\") — the same shape, named by its own book name.
func test_a_scurry_move_names_scurry_in_the_battle_log() -> void:
	var u := _carrier(1, "Scurriers", "ratmen_clans", ["Scurry"])
	_drop(u)
	assert_str(_log_text()) \
		.override_failure_message("Scurry widened the move bands and NO log line names it") \
		.contains("move bands widened by Scurry")


## No move-band rule: the move keeps its plain summary and invents no rule line.
func test_a_plain_move_stays_quiet() -> void:
	var u := _carrier(1, "Watchers", "human_defense_force", ["Fearless"])
	_drop(u)
	var text := _log_text()
	assert_str(text).contains("Watchers")
	assert_str(text) \
		.override_failure_message("a unit with no move-band rule got a phantom widening line") \
		.not_contains("move bands widened by")


## An enemy Repel Ambushers unit widens this arrival's ring to 12" — the placement names the rule
## and the carrier. The wider distance must actually be in force (the real registry value).
func test_an_arrival_held_back_by_repel_ambushers_names_the_rule_and_its_carrier() -> void:
	var solo = _main.solo_controller
	var enemy := _carrier(1, "Wardens", "human_defense_force", ["Repel Ambushers"])
	var ambusher := _carrier(2, "Infiltrators", "dark_elf_raiders", ["Ambush"])
	ambusher.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2.ZERO]
	var repel_m: float = SoloController.repel_ambush_dist_m(enemy)
	assert_float(repel_m / INCH) \
		.override_failure_message("fixture: the real GF book must carry Repel Ambushers' 12\"") \
		.is_equal_approx(12.0, 0.01)
	var entries: Array = []
	for m in enemy.get_alive_models():
		var mi := m as ModelInstance
		entries.append({"pos": Vector2(mi.node.global_position.x, mi.node.global_position.z),
			"min_dist_m": repel_m, "pad_m": SoloController.model_base_radius_m(mi)})
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), entries, [], 2, [])
	assert_object(arrived).is_equal(ambusher)
	_main._solo_log_ambush_variant_lines(ambusher, 2, false)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("Repel Ambushers held the arrival back and NO log line names it") \
		.contains("Repel Ambushers")
	assert_str(text).contains("Wardens")

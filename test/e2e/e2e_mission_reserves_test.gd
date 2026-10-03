extends GdUnitTestSuite
## NML-1010 D8a (flow half) — Attack & Defend reserves on the REAL main.tscn: after the phases each
## covered side's leftover is set aside, the round's reserve dice are ONE tray roll per side with a held
## unit, only a winning die lets a unit arrive, and a winning AI reserve lands in the zone clear of
## enemy and marker. The phase fixture reuses the D7a e2e's shape.

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
	MissionCatalog._catalog()["reserve_fixture"] = {"name": "Reserve Fixture", "family": "attack_defend", "rounds": 6,
		"scoring": "end", "deployment": "front_line", "roles": true,
		"deploy_phases": [["defender", "half", "centre_disc_12"], ["attacker", "half", "edge_band_12"]],
		"reserves": {"who": "both", "arrive_on": 4, "from_round": 2, "zone": "edge_band_12",
			"gates": {"min_from_enemy_in": 12, "min_from_marker_in": 12}},
		"markers": {"count": 1, "placement": "table_centre"}}
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _reg(u: GameUnit, cost: int = 0) -> GameUnit:
	var opr := OPRApiClient.OPRUnit.new()
	opr.cost = cost
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var lines: PackedStringArray = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary).get("text", "")))
	return "\n".join(lines)


func _deploy() -> Array:
	var ai: Array = []
	for i in range(5):
		ai.append(_reg(E2EBoot.make_unit(_main, 2, "Ai%d" % i, [TRAY]), 100 - i * 10))
	var hu: Array = []
	for i in range(3):
		hu.append(_reg(E2EBoot.make_unit(_main, 1, "Hu%d" % i, [TRAY])))
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	_main._solo_mission_id = "reserve_fixture"
	_main._solo_deploy_fsm = {"phase": "side", "winner_is_ai": true, "human_turn": false, "human_out": false,
		"objectives": [], "blocked_normal": Callable(), "blocked_flying": Callable(), "seed": 5,
		"w": 1.8288, "d": 1.2192, "depth": 0.3048, "human_placed": {}, "outcome": []}
	await _main._solo_deploy_begin_side(true)
	for m in (hu[0] as GameUnit).models:   # the human's one phase unit, inside the frame
		(m as ModelInstance).node.global_position = Vector3(0.0, 0.0, -20.0 * INCH)
	_main._solo_deploy_human_done_one()
	return [ai, hu]


func test_after_the_phases_each_covered_side_sets_its_leftover_aside() -> void:
	var both: Array = await _deploy()
	var ai: Array = both[0]
	var hu: Array = both[1]
	var held_ai: Array = ai.filter(func(u: GameUnit) -> bool: return bool(u.unit_properties.get("mission_reserve", false)))
	var held_hu: Array = hu.filter(func(u: GameUnit) -> bool: return bool(u.unit_properties.get("mission_reserve", false)))
	assert_int(held_ai.size()).override_failure_message("5 AI units, half (2) deployed, 3 reserve").is_equal(3)
	assert_int(held_hu.size()).override_failure_message("3 human units, half (1) deployed, 2 reserve").is_equal(2)
	for u in held_ai + held_hu:
		assert_bool(SoloController.unit_in_reserve(u)).is_true()
	assert_str(_log_text()).contains("aside in reserve")


func test_the_reserve_dice_are_one_roll_per_side_and_only_a_winner_may_arrive() -> void:
	var both: Array = await _deploy()
	var ai: Array = both[0]
	await _main._solo_mission_reserve_rolls(1)   # before from_round: nobody rolls
	assert_str(_log_text()).not_contains("Reserve roll")
	await _main._solo_mission_reserve_rolls(2)
	var text := _log_text()
	assert_int(text.count("Reserve roll:")).override_failure_message("a die per held unit: 3 AI + 2 human").is_equal(5)
	for u in ai:   # the log line of every held AI unit agrees with the arrival gate
		var gu := u as GameUnit
		if bool(gu.unit_properties.get("mission_reserve", false)):
			var line := "Reserve roll: %s rolls" % gu.get_name()
			assert_bool(text.contains(line)).is_true()
			var wins: bool = SoloController.may_arrive_this_round(gu, 2)
			var tail := text.substr(text.find(line))
			tail = tail.substr(0, tail.find("\n"))
			assert_bool(tail.contains("arrives this round")).is_equal(wins)

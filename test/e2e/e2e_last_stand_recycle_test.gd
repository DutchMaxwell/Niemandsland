extends GdUnitTestSuite
## NML-1010 D11a — Last Stand recycling on the REAL main.tscn: an attacker unit destroyed for the first
## time comes back as a full-strength mission reserve (once), arrives only on the mission's die, the
## copy's own destruction is final, and a round start with no attacker on the table loses the reserves.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	MissionCatalog._catalog()["stand_fixture"] = {"name": "Stand Fixture", "family": "attack_defend", "rounds": 6,
		"scoring": "end", "deployment": "front_line", "roles": true,
		"reserves": {"who": "attacker", "recycle": true, "arrive_on": 6, "from_round": 2, "zone": "edge_band_12", "gates": {}},
		"markers": {"count": 1, "placement": "table_centre"}}
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	SoloController.mission_roles = {"attacker": 2, "defender": 1}   # the AI attacks
	_main._solo_mission_id = "stand_fixture"


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _profile(unit_name: String, size: int) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 100
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	return u


func _on_table(pid: int, unit_name: String, size: int) -> GameUnit:
	var spots: Array = []
	for i in size:
		spots.append(Vector3(float(i) * 1.2 * INCH, 0.0, 10.0 * INCH))
	return _main.opr_army_manager.create_runtime_unit({"opr_unit": _profile(unit_name, size), "faction_folder": "ratmen_clans"},
		pid, spots, "spawn")


func _kill(u: GameUnit) -> void:
	for m in u.models:
		(m as ModelInstance).is_alive = false
	_main._on_battle_log_dead((u.models[0] as ModelInstance).node, true)


func _copies_of(unit_name: String) -> Array:
	return _main.opr_army_manager.get_game_units_for_player(2).filter(
		func(g: GameUnit) -> bool: return bool(g.unit_properties.get("recycled", false)) and g.get_name().begins_with(unit_name))


func test_a_destroyed_attacker_returns_once_as_a_full_strength_reserve() -> void:
	var u := _on_table(2, "Fighters", 3)
	_kill(u)
	var copies := _copies_of("Fighters")
	assert_int(copies.size()).override_failure_message("one full-strength copy").is_equal(1)
	var c: GameUnit = copies[0]
	assert_int(c.models.size()).is_equal(3)
	assert_bool(SoloController.unit_in_reserve(c)).is_true()
	assert_bool(bool(c.unit_properties.get("mission_reserve", false))).is_true()
	assert_bool(SoloController.may_arrive_this_round(c, 2)).override_failure_message("a 6 is needed first").is_false()
	_kill(c)   # the copy's own destruction is final
	assert_int(_copies_of("Fighters").size()).is_equal(1)


func test_the_defender_is_not_recycled_and_a_round_start_without_attackers_loses_the_reserves() -> void:
	var d := _on_table(1, "Holders", 2)
	_kill(d)
	assert_int(_main.opr_army_manager.get_game_units_for_player(1).filter(func(g: GameUnit) -> bool: return bool(g.unit_properties.get("recycled", false))).size()).is_equal(0)
	var a := _on_table(2, "Raiders", 2)
	_kill(a)   # no attacker unit is left on the table, only the recycled copy in reserve
	_main._solo_recycle_reserves_lost(1)
	assert_int(_copies_of("Raiders").size()).override_failure_message("round 1: before from_round nothing is lost").is_equal(1)
	assert_bool(SoloController.unit_in_reserve(_copies_of("Raiders")[0])).is_true()
	_main._solo_recycle_reserves_lost(2)
	assert_bool(SoloController.unit_in_reserve(_copies_of("Raiders")[0])).override_failure_message("lost at round 2's start").is_false()
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("reserve unit(s) are lost")

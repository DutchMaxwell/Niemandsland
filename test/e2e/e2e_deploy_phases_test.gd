extends GdUnitTestSuite
## NML-1010 D7a (flow half) — the Attack & Defend deployment phases on the REAL main.tscn: the
## defender (AI) deploys its HALF first, the human attacker only then, outside the zone is refused,
## and the defender's rest follows. A synthetic catalog mission carries the phase list.

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
	MissionCatalog._catalog()["phase_fixture"] = {"name": "Phase Fixture", "family": "attack_defend", "rounds": 6,
		"scoring": "end", "deployment": "front_line", "roles": true,
		"deploy_phases": [["defender", "half", "centre_disc_12"], ["attacker", "all", "edge_band_12"],
			["defender", "rest", "anywhere"]],
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


func _on_table(u: GameUnit) -> bool:
	return absf(_main.solo_controller.unit_centre(u).x) < 2.0


func _move(u: GameUnit, p: Vector3) -> void:
	for m in u.models:
		(m as ModelInstance).node.global_position = p


func _start(ai_units: int) -> Array:
	var ai: Array = []
	for i in range(ai_units):
		ai.append(_reg(E2EBoot.make_unit(_main, 2, "Ai%d" % i, [TRAY]), 100 - i * 10))
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	_main._solo_mission_id = "phase_fixture"
	_main._solo_deploy_fsm = {"phase": "side", "winner_is_ai": true, "human_turn": false, "human_out": false,
		"objectives": [], "blocked_normal": Callable(), "blocked_flying": Callable(), "seed": 5,
		"w": 1.8288, "d": 1.2192, "depth": 0.3048, "human_placed": {}, "outcome": []}
	return ai


func test_the_defenders_half_is_down_before_the_attacker_may_place() -> void:
	var ai := _start(5)
	var h1 := _reg(E2EBoot.make_unit(_main, 1, "Hu1", [TRAY]))
	var h2 := _reg(E2EBoot.make_unit(_main, 1, "Hu2", [TRAY]))
	await _main._solo_deploy_begin_side(true)
	var down: Array = ai.filter(func(u: GameUnit) -> bool: return _on_table(u))
	assert_int(down.size()).override_failure_message("the AI's half = floor(5/2)").is_equal(2)
	for u in down:   # the two highest-points units, inside the 12" disc
		assert_float(Vector2(_main.solo_controller.unit_centre(u).x, _main.solo_controller.unit_centre(u).z).length()).is_less(12.0 * INCH + 0.01)
	assert_that([ai[0].unit_id, ai[1].unit_id].filter(func(id: String) -> bool: return down.any(func(u: GameUnit) -> bool: return u.unit_id == id))).has_size(2)
	assert_int(int(_main._solo_deploy_fsm["phase_i"])).is_equal(1)
	assert_bool(bool(_main._solo_deploy_fsm["human_turn"])).is_true()
	assert_bool(_on_table(h1) or _on_table(h2)).is_false()


func test_outside_the_zone_is_refused_then_the_attacker_and_the_defenders_rest_follow() -> void:
	var ai := _start(5)
	var h1 := _reg(E2EBoot.make_unit(_main, 1, "Hu1", [TRAY]))
	var h2 := _reg(E2EBoot.make_unit(_main, 1, "Hu2", [TRAY]))
	await _main._solo_deploy_begin_side(true)
	_move(h1, Vector3(0.0, 0.0, 0.0))   # the table centre: not in the 12" frame
	_main._solo_deploy_human_done_one()
	assert_int(int(_main._solo_deploy_fsm["phase_left"])).override_failure_message("refused: still owes 2").is_equal(2)
	_move(h1, Vector3(0.0, 0.0, -20.0 * INCH))   # inside the frame
	_main._solo_deploy_human_done_one()
	assert_int(int(_main._solo_deploy_fsm["phase_left"])).is_equal(1)
	_move(h2, Vector3(20.0 * INCH, 0.0, -20.0 * INCH))
	_main._solo_deploy_human_done_one()
	var down: Array = ai.filter(func(u: GameUnit) -> bool: return _on_table(u))
	assert_int(down.size()).override_failure_message("the defender's rest follows: all 5 stand").is_equal(5)
	assert_bool(_main._solo_deploy_fsm.has("phases")).is_false()


## D7d: a phase may carry its OWN gates as a 4th catalog element. The attacker phase here forbids
## standing within 12" of an enemy base; a role-flat gate could not say it for this phase alone.
func test_a_phase_gate_refuses_a_spot_beside_an_enemy_base_for_that_phase_only() -> void:
	MissionCatalog._catalog()["phase_fixture"]["deploy_phases"] = [["defender", "half", "centre_disc_12"],
		["attacker", "all", "anywhere", {"min_from_enemy_in": 12}], ["defender", "rest", "anywhere"]]
	var ai := _start(5)
	var h1 := _reg(E2EBoot.make_unit(_main, 1, "Hu1", [TRAY]))
	var h2 := _reg(E2EBoot.make_unit(_main, 1, "Hu2", [TRAY]))
	await _main._solo_deploy_begin_side(true)
	var base: Vector3 = Vector3.ZERO
	for u in ai:
		if _on_table(u):
			base = _main.solo_controller.unit_centre(u)
			break
	_move(h1, base + Vector3(4.0 * INCH, 0.0, 0.0))   # 4" from a defender base: inside the zone, inside the gate
	_main._solo_deploy_human_done_one()
	assert_int(int(_main._solo_deploy_fsm["phase_left"])).override_failure_message("refused: still owes 2").is_equal(2)
	_move(h1, Vector3(33.0 * INCH, 0.0, -20.0 * INCH))   # far from every enemy base
	_main._solo_deploy_human_done_one()
	assert_int(int(_main._solo_deploy_fsm["phase_left"])).is_equal(1)


## D14.2: the pseudo-zone "own" is the mission's standard deployment zone at the side's OWN table half
## (Ambush's defender, R13a) — the -Z band when the AI took the -Z edge, the +Z band otherwise.
func _own_zone_half_stands_in_its_band(ai_neg_z: bool) -> void:
	MissionCatalog._catalog()["phase_fixture"]["deploy_phases"] = [["defender", "half", "own"],
		["attacker", "all", "anywhere"]]
	var ai := _start(5)
	_reg(E2EBoot.make_unit(_main, 1, "Hu1", [TRAY]))
	await _main._solo_deploy_begin_side(ai_neg_z)
	var down: Array = ai.filter(func(u: GameUnit) -> bool: return _on_table(u))
	assert_int(down.size()).is_equal(2)
	for u in down:
		var z: float = _main.solo_controller.unit_centre(u).z / INCH
		assert_bool(z <= -12.0 if ai_neg_z else z >= 12.0).override_failure_message("z=%.1f in" % z).is_true()


func test_the_own_zone_is_the_ai_defenders_negative_band_when_it_took_the_negative_edge() -> void:
	await _own_zone_half_stands_in_its_band(true)


func test_the_own_zone_is_the_positive_band_when_the_ai_took_the_other_edge() -> void:
	await _own_zone_half_stands_in_its_band(false)

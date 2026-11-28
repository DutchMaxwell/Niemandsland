extends GdUnitTestSuite
## Feature test FT-1: deployment on a hot-seat 48 x 48 in table, Firefight (gff) and Skirmish (aofs). FF36 p.6 l.415-427
## (AS36 the same): the players alternate placing one unit each fully within 12 in of their own table edge; play starts
## when all units are down.
## Scene: DEPLOYMENT, two 1-model units a side on the trays. P1 places A 6 in from its edge (z = -24 in) and B 14 in
## from it; Start with P2's units still on the tray; P2 places both; Start.
## FINDING #3864 (R-FT2): the hot-seat table checks neither the 12 in zone nor the alternation - B stands 14 in out,
## and P1 may place its second unit before P2's first. The book case stays here, skipped with that issue.
## Real: the main scene, the table system switch, a 4 x 4 ft table, the deployment phase, the Start button's deployment gate.

const INCH := 0.0254
const TRAY := Vector3(3.0, 0.0, 0.0)

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _deploy(sys: String) -> Array:
	assert_bool(_t.main.set_table_system(sys, "P1")).is_true()
	await _t.table_feet(Vector2(4, 4))
	SoloHarness.instant(_t.main, false)   # an instant (unattended) table skips the deployment gate
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	var out: Array = []
	for spec in [[1, "Alpha"], [1, "Bravo"], [2, "Crows"], [2, "Dogs"]]:
		var u := _t.unit(sys, int(spec[0]), str(spec[1]), 1, 1, 0.0, 0.0)
		(u.models[0] as ModelInstance).node.global_position = TRAY + Vector3(0, 0, 0.1 * out.size())
		out.append(u)
	return out


func _place(u: GameUnit, x_in: float, z_in: float) -> void:
	(u.models[0] as ModelInstance).node.global_position = Vector3(x_in * INCH, 0, z_in * INCH)


func _case(sys: String) -> void:
	var us := await _deploy(sys)
	_place(us[0], -6.0, -18.0)   # 6 in from P1's edge
	_place(us[1], 6.0, -18.0)
	await _t.press_start()
	assert_bool(_t.main.opr_army_manager.is_deployment_phase()).override_failure_message("%s: P2 still on its tray" % sys).is_true()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Start refused") != -1 and l.find("Crows") != -1)) \
		.override_failure_message("%s: the refusal names a tray unit: %s" % [sys, _t.lines]).is_true()
	_place(us[2], -6.0, 18.0)
	_place(us[3], 6.0, 18.0)
	await _t.press_start()
	assert_bool(_t.main.opr_army_manager.is_deployment_phase()).override_failure_message("%s: all down: play starts" % sys).is_false()
	assert_int(_t.main.opr_army_manager.current_round).is_equal(1)


func test_gff_play_starts_only_when_every_unit_stands(timeout := 120000) -> void:
	await _case("gff")


func test_aofs_play_starts_only_when_every_unit_stands(timeout := 120000) -> void:
	await _case("aofs")


@warning_ignore("unused_parameter")
func test_a_unit_14_in_from_its_edge_is_refused(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3864: the hot-seat table checks neither the 12 in zone nor the alternation") -> void:
	var us := await _deploy("gff")
	_place(us[0], -6.0, -18.0)
	_place(us[1], 6.0, -10.0)   # 14 in from P1's edge
	_place(us[2], -6.0, 18.0)
	_place(us[3], 6.0, 18.0)
	await _t.press_start()
	assert_bool(_t.main.opr_army_manager.is_deployment_phase()).override_failure_message("Bravo is out of its zone").is_true()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Bravo") != -1 and l.find("12") != -1)) \
		.override_failure_message("one line names the 12 in zone: %s" % [_t.lines]).is_true()

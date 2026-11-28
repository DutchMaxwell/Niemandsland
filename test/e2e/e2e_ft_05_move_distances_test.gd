extends GdUnitTestSuite
## Feature test FT-5: the move actions and their distances on a hot-seat Firefight (gff) table. FF36 p.7 l.457-500: Hold
## shoots, Advance moves up to 6 in and shoots, Rush moves up to 12 in and does not shoot.
## Scene (fresh table per case): A (one model, a 24 in rifle) 20 in from enemy E in the open.
## Real: the main scene, the card's Activate, the real drag (grab, move, release) under the movement selector, the drop
## door with the core's move check, the human attack door, the battle log.

const INCH := 0.0254

var _t: SkirmishTable
var _a: GameUnit
var _e: GameUnit
var _from: Vector3


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_a = _t.unit("gff", 1, "Rangers", 1, 1, -10.0, 0.0)
	_e = _t.unit("gff", 2, "Raiders", 1, 3, 10.0, 0.0)
	_t.unit("gff", 2, "Reserve", 1, 1, 10.0, 20.0)   # keeps P2's side of the round open
	_from = (_a.models[0] as ModelInstance).node.global_position
	assert_bool(await _t.start(_a)).override_failure_message("A starts").is_true()


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _moved_in() -> float:
	var p: Vector3 = (_a.models[0] as ModelInstance).node.global_position
	return Vector2(p.x - _from.x, p.z - _from.z).length() / INCH


func _volleys() -> int:
	return _t.lines.filter(func(l: String) -> bool: return l.find("Rangers") != -1 and l.find("Rifle") != -1).size()


func test_a_hold_shoots(timeout := 120000) -> void:
	await _t.shoot(_a, _e)
	assert_int(_volleys()).override_failure_message("a volley line: %s" % [_t.lines]).is_greater(0)


func test_b_an_advance_of_6_in_shoots(timeout := 120000) -> void:
	await _t.walk(_a, 6.0, 0.0, CoreActivation.CAP_ADVANCE)
	assert_float(_moved_in()).override_failure_message("6 in stands: %s" % [_t.lines]).is_equal_approx(6.0, 0.1)
	await _t.shoot(_a, _e)
	assert_int(_volleys()).override_failure_message("a volley line: %s" % [_t.lines]).is_greater(0)


func test_c_an_advance_of_6_5_in_does_not_stand(timeout := 120000) -> void:
	await _t.walk(_a, 6.5, 0.0, CoreActivation.CAP_ADVANCE)
	assert_float(_moved_in()).override_failure_message("the 6.5 in Advance snaps back: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_int(_t.count("Rangers: a model moved 6.5\" - the Advance allowance is 6.0\".")) \
		.override_failure_message("one line names the 6 in Advance: %s" % [_t.lines]).is_equal(1)


func test_d_a_rush_of_12_in_stands_and_may_not_shoot(timeout := 120000) -> void:
	await _t.walk(_a, 12.0, 0.0, CoreActivation.CAP_RUSH)
	assert_float(_moved_in()).override_failure_message("12 in stands: %s" % [_t.lines]).is_equal_approx(12.0, 0.1)
	await _t.shoot(_a, _e)
	assert_int(_volleys()).override_failure_message("no volley after a Rush: %s" % [_t.lines]).is_equal(0)
	assert_int(_t.count("Rangers rushed this activation - it cannot shoot.")) \
		.override_failure_message("one line says why: %s" % [_t.lines]).is_equal(1)


func test_e_a_rush_of_12_5_in_does_not_stand(timeout := 120000) -> void:
	await _t.walk(_a, 12.5, 0.0, CoreActivation.CAP_RUSH)
	assert_float(_moved_in()).override_failure_message("the 12.5 in Rush snaps back: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_int(_t.count("Rangers: a model moved 12.5\" - the Rush allowance is 12.0\".")) \
		.override_failure_message("one line names the 12 in Rush: %s" % [_t.lines]).is_equal(1)

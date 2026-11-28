extends GdUnitTestSuite
## Feature test FT-18: the AoF: Skirmish Musician on a command pick, hot-seat aofs table. AS36 p.13 l.1186-1189: the
## Musician's unit and up to 2 friendly units picked before the game move +1 in on move actions; when the bearer is killed
## the picked units lose it. (Ruling D17: the picks are made at deployment.)
## Scene: P1's Band (one model, Musician) picks Xan and Yor at deployment; Zed is not picked. P2 has Enemy and a Sniper.
## Round 1: Xan advances 7 in and shoots; Zed tries a 7 in Advance; the Sniper (tray seed 1) kills Band's only model.
## Round 2: Xan tries a 7 in Advance again.
## Real: the main scene, the deployment-phase pick door (CommandPicks.toggle, as the card's pick clicks), battle start,
## the card's Activate / End, the real drag, the radial targeting and click, the core's moves and volleys.

const INCH := 0.0254

var _t: SkirmishTable
var _band: GameUnit
var _x: GameUnit
var _y: GameUnit
var _z: GameUnit
var _e: GameUnit
var _s: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	_band = _t.unit("aofs", 1, "Band", 1, 1, -20.0, 12.0, {}, ["Musician"])
	_band.unit_properties["defense"] = 6
	_x = _t.unit("aofs", 1, "Xan", 1, 1, -20.0, 0.0)
	_y = _t.unit("aofs", 1, "Yor", 1, 1, -20.0, -5.0)
	_z = _t.unit("aofs", 1, "Zed", 1, 1, -20.0, -12.0)
	_e = _t.unit("aofs", 2, "Enemy", 1, 3, 0.0, 0.0)
	_s = _t.unit("aofs", 2, "Sniper", 1, 1, 0.0, 12.0, {"name": "Rifle", "range_in": 24, "attacks": 6, "count": 1, "rules": []})
	_s.unit_properties["quality"] = 2
	CommandPicks.toggle(_t.main, _band, _x)
	CommandPicks.toggle(_t.main, _band, _y)
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _advance(u: GameUnit, inches: float) -> float:
	var from: Vector3 = (u.models[0] as ModelInstance).node.global_position
	assert_bool(await _t.start(u)).override_failure_message("%s starts: %s" % [u.get_name(), _t.lines]).is_true()
	await _t.walk(u, inches, 0.0, CoreActivation.CAP_ADVANCE)
	return ((u.models[0] as ModelInstance).node.global_position - from).length() / INCH


func _idle(u: GameUnit) -> void:
	if await _t.start(u):
		await _t.end(u)
	await _t.runner.simulate_frames(4)


func test_a_picked_unit_advances_7_in_until_the_musician_dies(timeout := 240000) -> void:
	assert_array(_band.unit_properties.get("command_picks", [])).is_equal([_x.unit_id, _y.unit_id])
	assert_float(await _advance(_x, 7.0)).override_failure_message("Xan's 7 in Advance stands: %s" % [_t.lines]).is_equal_approx(7.0, 0.05)
	await _t.aim(_x, _e)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.begins_with("Musician (from Band") and l.ends_with("Xan moves +1\""))) \
		.override_failure_message("the Musician line: %s" % [_t.lines]).is_true()
	assert_int(_t.count("Xan fires Rifle at Enemy")).override_failure_message("an Advance shoots: %s" % [_t.lines]).is_equal(1)
	await _idle(_e)
	assert_float(await _advance(_z, 7.0)).override_failure_message("Zed is not picked: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_int(_t.count("Zed: a model moved 7.0\" - the Advance allowance is 6.0\".")).is_equal(1)
	await _t.end(_z)
	assert_bool(await _t.start(_s)).is_true()
	_t.main.seed_tray_rng(1)
	await _t.aim(_s, _band)
	assert_int(_band.get_alive_count()).override_failure_message("the bearer is killed: %s" % [_t.lines]).is_equal(0)
	await _idle(_y)
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("round 2: %s" % [_t.lines]).is_equal(2)
	await _idle(_e)   # P1 took round 1's last activation: P2 opens round 2
	assert_float(await _advance(_x, 7.0)).override_failure_message("the bearer is dead: Xan is back to 6 in: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_int(_t.count("Xan: a model moved 7.0\" - the Advance allowance is 6.0\".")).is_equal(1)

extends GdUnitTestSuite
## Feature test FT-19: the AoF: Skirmish Banner on a command pick, hot-seat aofs table. AS36 p.13 l.1200-1203: the Banner's
## unit and up to 2 friendly units picked before the game get +1 to Morale Test rolls triggered by shooting or melee.
## Scene: P1's Band (Banner) picks Xan and Wil at deployment; Zed is not picked; both one Tough(3) model, Quality 4.
## (a) P2's Gunners (Quality 2, 4 attacks) shoot Xan, tray seed 10: hits 5 4 4 3, blocks 5 4 2 1 -> 2 wounds, morale
## face 3 (+1 = 4: passes); (b) the same at Zed (fails); (c) Xan advances through a Dangerous cell, tray seed 18: dice
## 5 1 1 -> 2 wounds, morale face 3 (a terrain test: no +1, fails). Seeds by local scan (R-FT3).
## Real: the main scene, the deployment-phase pick door, battle start, the card's Activate / End, the real drag, the
## radial targeting and click, the core's volley, Dangerous test and morale.

const INCH := 0.0254

var _t: SkirmishTable
var _x: GameUnit
var _z: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	var band := _t.unit("aofs", 1, "Band", 1, 1, -20.0, 20.0, {}, ["Banner"])
	_x = _t.unit("aofs", 1, "Xan", 1, 3, -11.0, 0.0)
	_z = _t.unit("aofs", 1, "Zed", 1, 3, -11.0, -10.0)
	var w := _t.unit("aofs", 1, "Wil", 1, 1, -20.0, 24.0)
	CommandPicks.toggle(_t.main, band, _x)
	CommandPicks.toggle(_t.main, band, w)   # both slots taken: battle start adds no nearest unit
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _shot_at(target: GameUnit) -> void:
	var g := _t.unit("aofs", 2, "Gunners", 1, 1, 1.0, target.models[0].node.global_position.z / INCH,
		{"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	g.unit_properties["quality"] = 2
	_t.unit("aofs", 2, "Far", 1, 1, 10.0, 30.0)
	# P1 opens: Band stands idle, then P2's Gunners shoot.
	var band: GameUnit = _t.main.opr_army_manager.game_units["e2e_p1_Band"]
	if await _t.start(band):
		await _t.end(band)
	assert_bool(await _t.start(g)).is_true()
	_t.main.seed_tray_rng(10)
	await _t.aim(g, target)


func test_a_picked_unit_gets_plus_1_against_shooting(timeout := 120000) -> void:
	await _shot_at(_x)
	assert_int(_t.count("Xan takes 2 wounds (1/3 wounds)")).override_failure_message("2 wounds: %s" % [_t.lines]).is_equal(1)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Banner") != -1 and l.find("Xan") != -1)) \
		.override_failure_message("a line names the Banner: %s" % [_t.lines]).is_true()
	assert_int(_t.count("Xan passes morale")).override_failure_message("3 + 1 passes on 4+: %s" % [_t.lines]).is_equal(1)


func test_an_unpicked_unit_gets_nothing(timeout := 120000) -> void:
	await _shot_at(_z)
	assert_int(_t.count("Zed takes 2 wounds (1/3 wounds)")).override_failure_message("2 wounds: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.count("Zed fails morale — Shaken")).override_failure_message("3 fails on 4+: %s" % [_t.lines]).is_equal(1)


func test_a_dangerous_terrain_test_gets_nothing(timeout := 120000) -> void:
	_t.unit("aofs", 2, "Far", 1, 1, 10.0, 30.0)
	var o: Node3D = _t.main.terrain_overlay
	o.grid_cells[o.world_to_cell(Vector3(-7.0 * INCH, 0, 0))] = TerrainRules.TerrainType.DANGEROUS
	_t.main.seed_tray_rng(18)
	assert_bool(await _t.start(_x)).is_true()
	await _t.walk(_x, 6.0, 0.0, CoreActivation.CAP_ADVANCE)
	await _t.end(_x)
	assert_int(_t.count("P1: 5 1 1 → 2 wounds (each 1)")).override_failure_message("the terrain test: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.count("Xan fails morale — Shaken")).override_failure_message("no Banner +1 on a terrain test: %s" % [_t.lines]).is_equal(1)

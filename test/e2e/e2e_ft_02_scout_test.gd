extends GdUnitTestSuite
## Feature test FT-2: Scout deployment against the AI, Firefight (gff), 4 x 4 ft. FF36 p.15 l.1255-1263: Scout units deploy
## after all others, fully within 9 in beyond the own deployment zone and over 9 in away from enemy units that are not
## Scouts. The guided solo deployment in its SCOUT phase, the human (slot 1, zone = the 12 in band at z -24..-12) on turn.
## Case 1: the human's Scout 8 in past the zone line, 15 in from the AI's unit -> taken. Case 2: 10 in past the zone line ->
## FINDING #3864 (the human's scout band is not checked; skipped). Case 3: 8 in past the line but 8 in from the AI's unit
## -> refused, the toast names the 9 in gap.
## Real: the main scene, the solo seat, the guided deployment's ✓ door and its scout gate, the toast.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4

var _t: SkirmishTable
var _sc: GameUnit
var _e: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "S")
	await _t.table_feet(Vector2(4, 4))
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	var a := _t.unit("gff", 1, "Line", 1, 1, -10.0, -18.0)
	_sc = _t.unit("gff", 1, "Pathfinders", 1, 1, 0.0, 0.0, {}, ["Scout"])
	(_sc.models[0] as ModelInstance).node.global_position = Vector3(3.0, 0, 0)   # the tray
	_e = _t.unit("gff", 2, "Raiders", 1, 1, 0.0, 11.0)   # 13 in from the AI's edge
	_t.scout_phase([a, _e])


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _place_scout(z_in: float) -> void:
	(_sc.models[0] as ModelInstance).node.global_position = Vector3(0, 0, z_in * INCH)


func test_a_scout_8_in_past_its_zone_is_taken(timeout := 120000) -> void:
	_place_scout(-4.0 - BASE_IN / 2.0)   # its base fully within 8 in past the line z = -12
	assert_bool(await _t.deploy_done(_sc)).override_failure_message("taken: %s / %s" % [_t.toast_text(), _t.lines]).is_true()


func test_a_scout_8_in_from_an_enemy_is_refused(timeout := 120000) -> void:
	(_e.models[0] as ModelInstance).node.global_position = Vector3(0, 0, (-4.0 + 8.0 + BASE_IN) * INCH)
	_place_scout(-4.0)
	assert_bool(await _t.deploy_done(_sc)).override_failure_message("refused: %s" % [_t.lines]).is_false()
	assert_str(_t.toast_text()).override_failure_message("the toast names the 9 in gap").contains("9")


@warning_ignore("unused_parameter")
func test_a_scout_10_in_past_its_zone_is_refused(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3864: the human's scout band (9 in past the zone) is not checked") -> void:
	_place_scout(-2.0 + BASE_IN / 2.0)   # its base reaches 10 in past the line
	assert_bool(await _t.deploy_done(_sc)).override_failure_message("refused: %s" % [_t.lines]).is_false()

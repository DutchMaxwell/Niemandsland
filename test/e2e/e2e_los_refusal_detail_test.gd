extends GdUnitTestSuite
## E2E — #205: a refused shot said "no model has line of sight" and nothing more — the
## player couldn't see WHO blocked, and a rules-correct refusal (GF v3.5.1 p.5: the
## perimeter of OTHER units, friendly or enemy, blocks; only the shooter's own unit is
## see-through) read as a bug. The refusal now names the nearest lane's blocker, with the
## own-unit teaching note when it is the player's own other unit.
##
## Drives the REAL _solo_validate_target on main.tscn with an OPR-armed shooter.

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A unit whose members carry one real ranged OPR weapon (the validation reads weapons off
## source_data, like production imports do).
func _armed_unit(pid: int, unit_name: String, positions: Array, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Rifle"
	w.range_value = range_in
	var weapons: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = weapons
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_refusal_names_the_own_blocking_unit(timeout := 120000) -> void:
	# The community geometry: shooter → OWN other unit dead on the lane → enemy behind it.
	var shooter := _armed_unit(1, "Shooters", [Vector3.ZERO], 24)
	var wall := _armed_unit(1, "OwnWall", [Vector3(6.0 * INCH, 0, 0)], 24)
	var foe := _armed_unit(2, "Foes", [Vector3(12.0 * INCH, 0, 0)], 24)
	var msg: String = _main._solo_validate_target(shooter, foe, false)
	assert_str(msg).contains("no model has line of sight")
	assert_str(msg) \
		.override_failure_message("#205 — the refusal names no blocker (got: '%s'); a correct rule keeps reading as a bug" % msg) \
		.contains("blocked by %s" % wall.get_name())
	assert_str(msg).contains("your own unit")


func test_clear_lane_is_not_refused(timeout := 120000) -> void:
	# Same setup minus the wall: the shot is valid — the detail must never invent a blocker.
	var shooter := _armed_unit(1, "Shooters", [Vector3.ZERO], 24)
	var foe := _armed_unit(2, "Foes", [Vector3(12.0 * INCH, 0, 0)], 24)
	assert_str(_main._solo_validate_target(shooter, foe, false)).is_equal("")

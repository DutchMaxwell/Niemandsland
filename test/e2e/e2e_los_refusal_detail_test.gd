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


func test_another_own_unit_still_blocks_a_joined_hero(timeout := 120000) -> void:
	# CONTROL for the D10 fix (declared first: gdUnit drops tests declared after a failing one): only the
	# hero's OWN host is see-through. A different friendly unit on the lane still blocks (p.5 "perimeter of
	# other units (friendly or enemy)").
	var host := _armed_unit(1, "HostSquad", [Vector3(-6.0 * INCH, 0, 0)], 24)
	var hero := _armed_unit(1, "JoinedHero", [Vector3.ZERO], 24)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var wall := _armed_unit(1, "OtherOwnWall", [Vector3(6.0 * INCH, 0, 0)], 24)
	var foe := _armed_unit(2, "Foes", [Vector3(12.0 * INCH, 0, 0)], 24)
	assert_int(_main._solo_sighted_count(hero, foe, 24)) \
		.override_failure_message("control: another friendly unit on the lane (%s) must still block the hero" % wall.get_name()) \
		.is_equal(0)


func test_a_joined_hero_sees_through_its_own_host_squad(timeout := 120000) -> void:
	# D10 / Q1 (GF v3.5.1 p.14 "counts as part of that unit" + p.5 "always see through friendly models from
	# their own unit"): the hero shoots as its own member of the joined unit, and the host squad standing dead
	# on its lane is HIS unit — not "another unit" — so it must not block him.
	var host := _armed_unit(1, "HostSquad", [Vector3(6.0 * INCH, 0, 0)], 24)
	var hero := _armed_unit(1, "JoinedHero", [Vector3.ZERO], 24)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var foe := _armed_unit(2, "Foes", [Vector3(12.0 * INCH, 0, 0)], 24)
	assert_int(_main._solo_sighted_count(hero, foe, 24)) \
		.override_failure_message("D10 — a joined hero's line to the enemy is blocked by its OWN host squad") \
		.is_greater(0)
	assert_str(_main._solo_validate_target(hero, foe, false)).is_equal("")


func test_clear_lane_is_not_refused(timeout := 120000) -> void:
	# Same setup minus the wall: the shot is valid — the detail must never invent a blocker.
	var shooter := _armed_unit(1, "Shooters", [Vector3.ZERO], 24)
	var foe := _armed_unit(2, "Foes", [Vector3(12.0 * INCH, 0, 0)], 24)
	assert_str(_main._solo_validate_target(shooter, foe, false)).is_equal("")

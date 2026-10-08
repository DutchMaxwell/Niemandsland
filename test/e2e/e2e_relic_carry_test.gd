extends GdUnitTestSuite
## E2E — NML-1010 wave C step C2: the live-table carry step (Relic Hunt / Capture & Hold).
## Pins over the real scenes/main.tscn: a marker just seized is picked up onto the nearest
## eligible unit and the overlay hides its token; a carrier that goes Shaken or is destroyed
## drops it and the overlay shows the token again.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}   # plan 2.2: no implicit NACHTMAHR — this table designates player 2 explicitly
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_markers = [{"carry": true, "carried_by": ""}]


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var lines: PackedStringArray = []
	for entry in _main.battle_log.entries():
		lines.append(str((entry as Dictionary).get("text", "")))
	return "\n".join(lines)


## The first RNG seed whose single d6 fails `target` — a plain morale FAIL (never ROUT: this test
## always calls _solo_morale_test with melee=false, which cannot Rout by the rule's own text).
func _seed_for_morale_fail(target: int) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(100):
		rng.seed = candidate
		if rng.randi_range(1, 6) < target:
			return candidate
	fail("no seed under 100 fails a %d+ morale test" % target)
	return -1


func test_pickup_hides_the_token_and_shaken_carrier_drops_it() -> void:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main._solo_auto_seize()
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal(carrier.unit_id)
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_false()
	assert_str(_log_text()).contains("Relic picked up by Carrier")

	_main.seed_tray_rng(_seed_for_morale_fail(carrier.get_quality()))
	await _main._solo_morale_test(carrier, "Carrier")
	assert_bool(carrier.is_shaken).is_true()
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal("")
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_true()
	assert_str(_log_text()).contains("Relic dropped by Carrier (shaken)")


## A destroyed carrier drops the marker too (the OTHER drop hook, main.gd's battle-log-dead branch).
func test_destroyed_carrier_drops_it() -> void:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3.ZERO])
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier
	_main._solo_auto_seize()
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal(carrier.unit_id)

	(carrier.models[0] as ModelInstance).is_alive = false
	_main._on_battle_log_dead(carrier.models[0].node, true)
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal("")
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_true()
	assert_str(_log_text()).contains("Relic dropped by Carrier (destroyed)")


## No pickup while the marker is contested (owners[i] stays 0) — the seizing rule decides first.
func test_no_pickup_while_contested() -> void:
	var p1 := E2EBoot.make_unit(_main, 1, "P1", [Vector3.ZERO])
	var p2 := E2EBoot.make_unit(_main, 2, "P2", [Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[p1.unit_id] = p1
	_main.opr_army_manager.game_units[p2.unit_id] = p2
	_main._solo_auto_seize()
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal("")
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_true()

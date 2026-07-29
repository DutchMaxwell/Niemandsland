extends GdUnitTestSuite
## E2E — #209: embarking was a FREE action. GF v3.5.1 p.15: units enter/exit a transport
## "by using any move action" and "can't both embark/disembark as part of the same
## activation" — so in a solo game the transport move IS the unit's activation. It was
## never marked, the unit could act again, and the disembark could follow in the same
## round: a rules exploit the maintainer hit live.
##
## Under test on the real main.tscn radial controller: consumption + hand-over on embark,
## the same-round double-move refusal, and the sandbox/deployment exemptions.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _solo_playing_on() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


## Transport(6) truck at the origin + cargo in reach + an idle spare so the round stays open.
func _truck_and_cargo() -> Array:
	var truck := E2EBoot.make_unit(_main, 1, "Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var cargo := E2EBoot.make_unit(_main, 1, "Riders", [Vector3(0.04, 0, 0)])
	var spare := E2EBoot.make_unit(_main, 1, "Spare", [Vector3(1.0, 0, 0)])
	for u in [truck, cargo, spare]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Fixture must be able to embark at all — otherwise the tests pass vacuously.
	assert_bool(bool(_main.opr_army_manager.can_embark(cargo, truck).get("ok", false))).is_true()
	return [truck, cargo]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_embark_consumes_the_activation(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("#209 — embarking stayed a FREE action: the unit is not activated (GF v3.5.1 p.15: any move action)") \
		.is_true()
	assert_str(_log_text()).contains("spends its activation to embark")


func test_no_disembark_in_the_same_round(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)
	_main.radial_menu_controller._disembark_unit(tc[1])
	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("#209 — the unit hopped out in the same round it embarked (p.15 forbids both in one activation, and its activation is spent)") \
		.is_equal(tc[0])
	assert_str(_log_text()).contains("has already activated this round")


func test_disembark_keeps_the_shot_window(timeout := 120000) -> void:
	# #209 correction (maintainer rules check): exiting is "any move action" (p.15) and an
	# ADVANCE may shoot after moving (p.7) — the exit must NOT consume the activation.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_main.radial_menu_controller._disembark_unit(tc[1])
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_null()
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("#209 — the Advance exit consumed the activation: the unit lost its rulebook shot window (GF v3.5.1 p.7)") \
		.is_false()
	assert_str(_log_text()).contains("may still shoot this activation")


func test_no_reembark_in_the_exit_round(timeout := 120000) -> void:
	# p.15: "can't both embark/disembark as part of the same activation" — the open shot
	# window must not reopen the transport door.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_main.radial_menu_controller._disembark_unit(tc[1])
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("#209 — the unit hopped back IN during its exit round") \
		.is_null()
	assert_str(_log_text()).contains("can't embark again")


func test_sandbox_embark_stays_free(timeout := 120000) -> void:
	# No solo game engaged: the sandbox consumes nothing (like dice and rulers).
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated).is_false()


func test_deployment_reserve_loading_stays_free(timeout := 120000) -> void:
	# #160 reserve loading happens DURING deployment — no activation economy there.
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated).is_false()

extends GdUnitTestSuite
## E2E — audit row 48: the transport activation economy (#209) ran ONLY for a human playing the
## SOLO AI opponent. `_activation_economy_on` required `main._solo_alternation_active()`, and a
## plain human-vs-human MP room is deliberately free-for-all (AUDIT section 4b: no turn order at
## all) — so MP got a FREE transport move, with no "already activated" refusal and no marker.
##
## What is under test is deliberately narrow: the flag MP players could already set BY HAND (the
## manual Activate toggle) also gets set automatically by embarking, and the consumption
## broadcasts it, so both peers agree. NO turn-order enforcement is added anywhere.
##
## Room under test: a PLAIN MP room — solo_ai_slots stays EMPTY, FakeNet reports a live session.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## Stands in for NetworkManager at the radial controller's seam and records every outbound frame.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	var peer_to_slot: Dictionary = {}
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_activation(gu: GameUnit) -> void:
		sent.append({"kind": "activation", "unit": gu.unit_id})
	func broadcast_unit_embark(unit_id: String, _transport_id: String, _embarked: bool) -> void:
		sent.append({"kind": "embark", "unit": unit_id})


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# Plain MP room: NO solo_ai_slots, no solo controller — free-for-all, live session.
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	# main.gd:15986 copies its reference into the controller at _ready, so the fake has to
	# land at BOTH seams the transport flow reads.
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake
	_main.radial_menu_controller.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


## Transport(6) truck at the origin + cargo in reach — the same fixture the solo economy test uses.
func _truck_and_cargo() -> Array:
	var truck := E2EBoot.make_unit(_main, 1, "Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var cargo := E2EBoot.make_unit(_main, 1, "Riders", [Vector3(0.04, 0, 0)])
	for u in [truck, cargo]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Fixture must be able to embark at all — otherwise the tests pass vacuously.
	assert_bool(bool(_main.opr_army_manager.can_embark(cargo, truck).get("ok", false))).is_true()
	return [truck, cargo]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _activation_frames(u: GameUnit) -> Array:
	var out: Array = []
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) == "activation" and str(d["unit"]) == u.unit_id:
			out.append(d)
	return out


func test_embark_spends_the_activation_in_a_plain_mp_room(timeout := 120000) -> void:
	var tc := _truck_and_cargo()

	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)

	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("audit row 48 — in multiplayer embarking stayed a FREE action: the unit is not activated (GF v3.5.1 p.15: any move action)") \
		.is_true()
	assert_str(_log_text()).contains("spends its activation to embark")


func test_the_second_transport_move_is_refused_in_mp(timeout := 120000) -> void:
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)

	_main.radial_menu_controller._disembark_unit(tc[1])

	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("audit row 48 — the unit hopped out again in the same round: the already-activated refusal stayed dormant in MP (GF v3.5.1 p.15)") \
		.is_equal(tc[0])
	assert_str(_log_text()).contains("has already activated this round")


func test_the_activation_rides_the_wire(timeout := 120000) -> void:
	# The broadcast gap: the manual toggle broadcasts the marker, the transport consumption did
	# not — and sync_unit_embark never sets is_activated, so the peer kept the unit unactivated.
	var tc := _truck_and_cargo()

	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)

	assert_int(_activation_frames(tc[1]).size()) \
		.override_failure_message("the auto-activation never left this client — the peer keeps the unit unactivated and diverges (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("fixture check: the local half must fire for the wire half to mean anything") \
		.is_true()


func test_a_spent_unit_keeps_a_greyed_embark_entry_in_mp(timeout := 120000) -> void:
	# The refusal entry exists in the shared menu code but only rendered when the economy ran —
	# in MP a spent unit was offered a live, clickable Embark instead.
	var tc := _truck_and_cargo()
	(tc[1] as GameUnit).activate(1)

	var items: Array = []
	_main.radial_menu_controller._append_transport_items(tc[1], {}, items)
	var found = null
	for it in items:
		if str(it.id).begins_with("embark"):
			found = it
	assert_object(found) \
		.override_failure_message("the Embark entry VANISHED for a spent unit in MP — no option, no reason") \
		.is_not_null()
	if found == null:
		return   # the failure above is recorded; dereferencing null would abort the whole run
	assert_bool(bool(found.enabled)) \
		.override_failure_message("in MP the spent unit was offered a CLICKABLE embark — the already-activated refusal never rendered (GF v3.5.1 p.15)") \
		.is_false()
	assert_str(str(found.label)).contains("already activated")

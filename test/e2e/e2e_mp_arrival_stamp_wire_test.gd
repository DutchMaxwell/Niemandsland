extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the round a unit ARRIVED in has to reach the other table.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation resolves on whichever
## machine's activation it answered; the round-start arrivals run on the machine that closed the round, a human's
## own arrival on its owner's machine. The stamp `ambush_arrived_round` (written by every arrival: the AI's Ambush
## beat, the human's placement, the Reinforcement copy) was a plain `unit_properties[...] = ...` write, so the table
## that ENDS the round never knew the unit had just arrived: it contested and seized objectives with a unit that
## "can't seize or contest objectives on the round it deploys" (and the arrival bonuses that read the same stamp
## went missing). The Re-Deployment return date's erase at the arrival rode no frame either.
##
## The suite drives the REAL main.tscn doors and records what main and the controller hand to NetworkManager (the
## WireNet of e2e_mp_ai_door_latch_wire_test.gd: the REAL NetworkManager, transport swapped out, so the real allow-list
## gate applies), replays those exact frames into the REAL receiver on a "second machine" whose copy of the unit
## starts without the stamp, and runs the round-end seize there.
##
## NOT here: `mission_reserve` (D8a/D11a roles-mission reserves). The guided deployment that sets it is not offered in
## a multiplayer room (main.gd hides "Start Deployment" there), so no co-op game reaches that state; see the sweep notes.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


class WireNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: WireNet
var _real_net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	_main._solo_batch = true
	_real_net = _main.network_manager   # kept for the receive side (its handler is call_remote)
	_fake = auto_free(WireNet.new())
	_main.network_manager = _fake
	_main.solo_controller.network_manager = _fake   # the controller's own seam (SoloController.setup keeps the reference)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


# --- fixtures ----------------------------------------------------------------------------------

func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _unit(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, pid, unit_name, [at]))


func _frames() -> Array:
	var out: Array = []
	for w in _fake.wire:
		var p: Dictionary = (w as Dictionary)["p"] as Dictionary
		if str(p.get("m", "")) != "sync_unit_property":
			continue
		var a: Array = p["a"]
		out.append({"unit": str(a[0]), "key": str(a[1]), "value": a[2]})
	return out


func _values(key: String) -> Array:
	var out: Array = []
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			out.append((e as Dictionary)["value"])
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly (an out-of-bounds index
## takes gdUnit's -d run into the debugger and the whole headless process down).
func _first_unit(key: String) -> String:
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			return str((e as Dictionary)["unit"])
	return "<no message>"


func _take_frames() -> Array:
	var out := _frames()
	_fake.wire.clear()
	return out


func _replay(frames: Array) -> void:
	for e in frames:
		var d := e as Dictionary
		_real_net.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The round-end seize on THIS table with one objective at `at`: who holds it afterwards (0 = nobody).
func _seize_owner_at(at: Vector3) -> int:
	_main.terrain_overlay.update_objectives([at], [0])
	_main._solo_auto_seize()
	return int(_main.terrain_overlay.get_objective_owner(0))


# === 1. The AI's Ambush arrival ====================================================================

func test_the_ais_arrival_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var holder := _unit(1, "Holder", Vector3(0.03, 0, 0))
	var arrival := _unit(2, "FreshAmbush", Vector3(0.5, 0, 0.5))
	arrival.unit_properties["ambush_reserve"] = true
	arrival.unit_properties["ambush_return_round"] = 2   # a Re-Deployed unit coming back on its date
	_main.solo_controller._finish_reserve_arrival(arrival, Vector2(0.04, 0.0), [], 0.0125, 2)
	assert_array(_values("ambush_arrived_round")) \
		.override_failure_message("the arrival stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([2])
	assert_str(_first_unit("ambush_arrived_round")).is_equal(arrival.unit_id)
	assert_array(_values("ambush_return_round")) \
		.override_failure_message("the spent return date never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([null])

	# The other table ends the round: its copy of the arrival has no stamp and still holds the return date.
	var frames := _take_frames()
	arrival.unit_properties.erase("ambush_arrived_round")
	arrival.unit_properties["ambush_return_round"] = 2
	_replay(frames)
	assert_bool(arrival.unit_properties.has("ambush_return_round")).override_failure_message("the other table still holds the return date").is_false()
	assert_int(_seize_owner_at(Vector3.ZERO)) \
		.override_failure_message("the other table let a fresh Ambush arrival contest the objective (holder %s):\n%s" % [holder.get_name(), _log_text()]) \
		.is_equal(1)


# === 2. The human's placement ======================================================================

func test_a_humans_arrival_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var holder := _unit(2, "AiHolder", Vector3(0.03, 0, 0))
	var arrival := _unit(1, "HumanAmbush", Vector3(5.0, 0, 0))   # on the reserve tray, off the table
	arrival.unit_properties["ambush_reserve"] = true
	arrival.unit_properties["ambush_return_round"] = 2
	_main._solo_ambush_human_turn(2, [arrival])
	await _runner.simulate_frames(4)
	E2EBoot.place_unit_at(arrival, Vector3(0.04, 0, 0))   # the player drags it onto the table
	_fake.wire.clear()
	_main._solo_deploy_ui_btn1.pressed.emit()   # "Unit placed"
	await _runner.simulate_frames(6)
	assert_array(_values("ambush_arrived_round")) \
		.override_failure_message("the placement stamp never reached the wire (frames: %s)\n%s" % [str(_frames()), _log_text()]) \
		.is_equal([2])
	assert_str(_first_unit("ambush_arrived_round")).is_equal(arrival.unit_id)
	assert_array(_values("ambush_return_round")) \
		.override_failure_message("the spent return date never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([null])

	var frames := _take_frames()
	arrival.unit_properties.erase("ambush_arrived_round")
	arrival.unit_properties["ambush_return_round"] = 2
	_replay(frames)
	assert_int(_seize_owner_at(Vector3.ZERO)) \
		.override_failure_message("the other table let a fresh Ambush arrival contest the objective (holder %s):\n%s" % [holder.get_name(), _log_text()]) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


# === 3. The Reinforcement copy ====================================================================

func _profile(unit_name: String, size: int, rules: Array) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 130
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	for r in rules:
		u.special_rules.append(str(r))
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blade"
	w.attacks = 2
	u.weapons.append(w)
	return u


func test_a_reinforcement_copys_arrival_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var original: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": _profile("Clan Rats", 3, ["Tough(1)", "Reinforcement"]), "faction_folder": "ratmen_clans",
	}, 1, [Vector3(0.0, 0, 0), Vector3(1.2 * INCH, 0, 0), Vector3(2.4 * INCH, 0, 0)], "spawn")
	original.is_shaken = true
	await _main.solo_begin_reinforcement(original)
	_take_frames()   # the sacrifice's own frames are not the question
	_main.opr_army_manager.current_round = 3   # the copy arrives at the start of the NEXT round
	await _main._reinforcement_arrivals(3)
	var copy: GameUnit = null
	for g in _main.opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu != original and str(gu.unit_properties.get("origin", "")) == "reinforcement":
			copy = gu
	assert_object(copy).override_failure_message("fixture check: the copy came back").is_not_null()
	if copy == null:
		return
	assert_array(_values("ambush_arrived_round")) \
		.override_failure_message("the copy's arrival stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([3])
	assert_str(_first_unit("ambush_arrived_round")).is_equal(copy.unit_id if copy != null else "<no copy>")

	# The other table ends the round with an enemy standing on the same objective as the copy's first model.
	var frames := _take_frames()
	copy.unit_properties.erase("ambush_arrived_round")
	var spot: Vector3 = (copy.models[0] as ModelInstance).node.global_position
	_unit(2, "AiHolder", spot + Vector3(0.01, 0, 0))
	_replay(frames)
	assert_int(_seize_owner_at(spot)) \
		.override_failure_message("the other table let a Reinforcement copy contest the objective in its arrival round:\n%s" % _log_text()) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


# === 4. A look-ahead never speaks ====================================================================

func test_a_landing_preview_sends_no_arrival_frame(timeout := 120000) -> void:
	var fast0: bool = MovementPlanner.fast_planner
	var guard0: Variant = MovementPlanner.fast_planner_guard
	MovementPlanner.fast_planner = false   # deterministic precise planner (as e2e_auto_preview_test.gd)
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main._solo_fast = true
	var reserve := _unit(2, "Waiting", Vector3(5.0, 0, 0))
	reserve.unit_properties["ambush_reserve"] = true
	var shooter := E2EBoot.make_unit(_main, 1, "Riflemen", [Vector3(-0.8, 0, 0), Vector3(-0.8, 0, 1.5 * INCH), Vector3(-0.8, 0, -1.5 * INCH)])
	var opr := OPRApiClient.OPRUnit.new()
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 12
	rifle.attacks = 1
	opr.weapons = [rifle]
	shooter.source_type = "opr"
	shooter.source_data = opr
	_reg(shooter)
	var enemy := _unit(2, "Foe", Vector3(-0.8 + 16.0 * INCH, 0, 0))
	enemy.is_activated = true
	_fake.wire.clear()

	var advance: Dictionary = _main._solo_preview_for(shooter, AiDecision.Action.ADVANCE, enemy)
	_main._solo_preview_for(shooter, AiDecision.Action.CHARGE, enemy)

	assert_int((advance.get("landing", []) as Array).size()) \
		.override_failure_message("fixture check: the preview must really have run (landing ghosts)") \
		.is_greater(0)
	assert_array(_frames()) \
		.override_failure_message("a look-ahead sent hidden state to the other table: %s" % str(_frames())) \
		.is_empty()
	# CONTROL: the same recording does see a real arrival.
	_main.solo_controller._finish_reserve_arrival(reserve, Vector2(0.3, 0.3), [], 0.0125, 2)
	assert_array(_values("ambush_arrived_round")).is_equal([2])

	MovementPlanner.fast_planner = fast0
	MovementPlanner.fast_planner_guard = guard0


# === 5. Counter-proofs ================================================================================

## Offline the whole thing must stay silent and still stamp.
func test_a_solo_game_stamps_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var arrival := _unit(2, "FreshAmbush", Vector3(0.5, 0, 0.5))
	arrival.unit_properties["ambush_return_round"] = 2
	_main.solo_controller._finish_reserve_arrival(arrival, Vector2(0.04, 0.0), [], 0.0125, 2)

	assert_int(int(arrival.unit_properties.get("ambush_arrived_round", -1))).is_equal(2)
	assert_bool(arrival.unit_properties.has("ambush_return_round")).is_false()
	assert_array(_frames()).override_failure_message("an offline game broadcast hidden state").is_empty()


## The allow-list is still a boundary: the stamp is listed, the reserve flag (it travels with the visibility
## channel) and ownership are not.
func test_the_receiver_takes_the_arrival_stamp_and_still_refuses_other_keys(timeout := 120000) -> void:
	var alpha := _unit(1, "Alpha", Vector3(0.1, 0, 0))
	_real_net.sync_unit_property(alpha.unit_id, "ambush_arrived_round", 3)
	assert_int(int(alpha.unit_properties.get("ambush_arrived_round", 0))).is_equal(3)
	_real_net.sync_unit_property(alpha.unit_id, "ambush_arrived_round", null)
	assert_bool(alpha.unit_properties.has("ambush_arrived_round")).is_false()
	for key in ["player_id", "ambush_reserve", "mission_reserve"]:
		_real_net.sync_unit_property(alpha.unit_id, key, 9)
		assert_bool(alpha.unit_properties.get(key) == 9).override_failure_message(key).is_false()

extends GdUnitTestSuite
## One-core P3 step 53 (O9, O10): the lifecycle reaches the other table - the multiplayer half of the explicit activation.
## An agreed Automatic online room (no AI seat, seat 1 is this table's, a guest peer sits on seat 2), the real
## NetworkManager with only its transport swapped out: every frame - a former @rpc call and a command type alike - lands in
## ONE ordered list. What the other table is told:
##  - Start: one log line and nothing else (the unit is not activated, so no activation fact);
##  - Cancel after two drops: per model one move and one turn, one trails-undo per drop, the cancel line and the spent
##    Speed Feat latch given back through one property frame; no activation fact and NO check (a cancelled activation is
##    not announced);
##  - a shot at the OTHER player's unit: its saves are requested from that unit's owner (one `request_roll`, kind defense,
##    addressed to its peer) and not thrown on the local tray; the End that closes the volley sends the activation fact,
##    then one check;
##  - a Start off turn: the turn refusal and no frame.
## Real: the main scene, the drag machine, the radial doors, NmlCore. Constructed: plain units (ParityTable).

const INCH := 0.0254
const GUEST_PEER := 7
const FEAT := "speed_feat_used_speed_feat"
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")


## The REAL NetworkManager with its transport swapped out (core_activation_mp_test's WireNet): `send_command` records
## instead of sending, so a `broadcast_*` (through `_remote_call`) and a command type keep their send order in `wire`.
## Presence traffic (cursor, camera) is not game state and is not written down.
class WireNet extends "res://scripts/network_manager.gd":
	var wire: Array = []
	const PRESENCE := ["sync_cursor_position", "sync_camera_direction", "sync_camera_position"]
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		if type == "rpc" and PRESENCE.has(str((payload as Dictionary)["m"])):
			return true
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
var _real_net: Node
var _real_om_net: Node
var _net: WireNet
var _next_id := 900


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_real_om_net = _main.object_manager._network_manager
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	# The room as the agreement leaves it: Automatic, no AI seat, the host's token on seat 1; a guest peer sits on seat 2.
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.solo_ai_slots = {}
	_net = auto_free(WireNet.new())
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_net.player_names = {GUEST_PEER: "Guest"}
	_main.network_manager = _net
	_main.radial_menu_controller.network_manager = _net   # the activation fact goes out through the radial's own handle
	_main.object_manager._network_manager = _net   # the drag machine's own broadcasts
	_main._ensure_solo_controller()
	_main._apply_turn_token(1)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	if _main != null:
		_main.network_manager = _real_net
		_main.radial_menu_controller.network_manager = _real_net
		_main.object_manager._network_manager = _real_om_net
	_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A plain unit of seat `pid` with `models` models (network ids and indices set, as a synced army has them).
func _plain(pid: int, uname: String, x_in: float, models: int = 2) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": pid, "name": uname, "models": models, "x_in": x_in, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": models, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
		(u.models[i] as ModelInstance).node.set_meta("network_id", _next_id)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
		_next_id += 1
	return u


## The wire's frame names in send order (a former @rpc call by its handler name).
func _names() -> Array:
	return _net.wire.map(func(f: Dictionary) -> String: return str(f["p"]["m"]) if str(f["t"]) == "rpc" else str(f["t"]))


func _count(name: String) -> int:
	return _names().filter(func(n: String) -> bool: return n == name).size()


## The rpc frames of handler `m` (their args), or the command frames of that type (their payload).
func _args(m: String) -> Array:
	var out: Array = []
	for f in _net.wire:
		if str(f["t"]) == "rpc" and str(f["p"]["m"]) == m:
			out.append(f["p"]["a"])
		elif str(f["t"]) == m:
			out.append(f)
	return out


## The log lines that went to the other table, in order (a `sync_log_event` frame's text).
func _sent_lines() -> Array:
	return _args("sync_log_event").map(func(a: Array) -> String: return str(a[1]))


func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


func _poses(u: GameUnit) -> Array:
	return u.models.map(func(m: ModelInstance) -> Array: return [m.node.global_position, m.node.rotation.y])


## A real drag of the whole unit `dx_in` inches along +x, landed.
func _drag(u: GameUnit, dx_in: float) -> void:
	var om: Node3D = _main.object_manager
	om._deselect_all()
	for m in u.models:
		om._add_to_selection((m as ModelInstance).node)
	var a: Node3D = (u.models[0] as ModelInstance).node
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + dx_in * INCH, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(3)
	await get_tree().create_timer(0.3).timeout   # a new drop id (a millisecond stamp) for the next drag


## Start: exactly one frame - the O15 (2) sentence as a log event - and no activation fact (the unit is not activated).
func test_a_start_sends_one_log_line_and_nothing_else() -> void:
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	_net.wire.clear()
	await _main.radial_menu_controller.card_start_activation(u)
	assert_bool(CoreActivation.session_open(u.unit_id)).override_failure_message("no session").is_true()
	assert_array(_names()).override_failure_message("frames: %s" % [_names()]).is_equal(["sync_log_event"])
	assert_array(_sent_lines()).is_equal(["Rifles begins its activation."])
	assert_bool(u.is_activated).is_false()


## Cancel after two drops (and a spent Speed Feat latch): the other table is told a move and a turn per model, the undo of
## each drop's chalk, the cancel line, the spent line, and the latch's return through ONE property frame (null); no
## activation fact and no check.
func test_a_cancel_restores_on_the_other_table_and_announces_nothing() -> void:
	var u := _plain(1, "Rifles", 0.0, 4)
	_plain(2, "Guards", 18.0)
	await _main.radial_menu_controller.card_start_activation(u)
	var at := _poses(u)
	await _drag(u, 2.0)
	await _drag(u, 2.0)
	assert_array(_poses(u)).override_failure_message("the drags did not move").is_not_equal(at)
	_main._sync_unit_property(u, FEAT, true)   # a one-time spend inside the activation (step 37 gives it back)
	_net.wire.clear()
	_main.core_activation_cancel(u)
	await _runner.simulate_frames(4)
	assert_array(_poses(u)).override_failure_message("not back at the start").is_equal(at)
	assert_int(_count("move_object_networked")).override_failure_message("one move per model: %s" % [_names()]).is_equal(4)
	assert_int(_count("rotate_object_networked")).override_failure_message("one turn per model").is_equal(4)
	assert_int(_count("sync_move_trails_undo")).override_failure_message("one undo per drop").is_equal(2)
	assert_array(_sent_lines()).is_equal(["Rifles cancelled its activation - back at its start.",
		"Rifles: Speed Feat is unspent again."])
	var latch: Array = _args("sync_unit_property").filter(func(a: Array) -> bool: return a[1] == FEAT)
	assert_array(latch).override_failure_message("the latch frame").is_equal([[u.unit_id, FEAT, null]])
	assert_int(_count("sync_unit_activation")).override_failure_message("a cancel sent an activation").is_equal(0)
	assert_int(_count("activation_check")).override_failure_message("a cancelled activation was announced").is_equal(0)


## A shot at the other player's unit: its saves are requested from its owner - one `request_roll` of kind defense to the
## guest's peer - and the guest's faces are used; nothing more is thrown on the local tray for those dice. The End that
## closes the volley then sends the activation fact, and after it one check.
func test_a_shot_asks_the_defenders_owner_and_the_end_is_announced() -> void:
	var att := _plain(1, "Rifles", 0.0, 10)
	var foe := _plain(2, "Guards", 12.0, 10)
	await _main.radial_menu_controller.card_start_activation(att)
	_main.seed_tray_rng(3)
	_net.wire.clear()
	var done := [false]
	var run := func() -> void:
		await _main._run_human_attack(att, foe, false)
		done[0] = true
	run.call()   # suspends on the owner's answer
	for i in 300:
		if _count("request_roll") > 0:
			break
		await _runner.simulate_frames(1)
	var requests: Array = _args("request_roll")
	assert_int(requests.size()).override_failure_message("one request to the owner: %s" % [_names()]).is_equal(1)
	if requests.is_empty():
		return
	var rq: Dictionary = requests[0]["p"]
	assert_int(int(requests[0]["to"])).override_failure_message("addressed to the owner's peer").is_equal(GUEST_PEER)
	assert_str(str(rq["kind"])).is_equal("defense")
	assert_str(str(rq["unit"])).is_equal(foe.unit_id)
	var rng_at_request: int = _main._tray_rng.state   # the attack dice were thrown here; the defense dice are the owner's
	_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": range(int(rq["count"])).map(func(_i: int) -> int: return 6)}, GUEST_PEER)
	for i in 300:
		if done[0]:
			break
		await _runner.simulate_frames(1)
	assert_bool(done[0]).override_failure_message("the volley never finished").is_true()
	assert_int(_main._tray_rng.state).override_failure_message("the defender's dice were thrown on the local tray").is_equal(rng_at_request)
	assert_int(_count("request_roll")).override_failure_message("a second request: %s" % [_names()]).is_equal(1)
	assert_bool(att.is_activated).override_failure_message("the volley did not end the activation").is_true()
	var order := _names().filter(func(n: String) -> bool: return n in ["sync_unit_activation", "activation_check"])
	assert_array(order).override_failure_message("frames: %s" % [_names()]).is_equal(["sync_unit_activation", "activation_check"])


## A Start off turn (the token is on seat 2): the turn refusal, the unit not started, and no frame at all - the refusal is
## this table's own line.
func test_a_start_off_turn_is_refused_and_sends_nothing() -> void:
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	_main._apply_turn_token(2)
	_net.wire.clear()
	await _main.radial_menu_controller.card_start_activation(u)
	assert_bool(CoreActivation.session_open(u.unit_id)).override_failure_message("a session off turn").is_false()
	assert_bool(u.is_activated).is_false()
	assert_int(_main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == "It is P2's turn").size()) \
		.override_failure_message("lines: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(1)
	assert_array(_names()).override_failure_message("frames: %s" % [_names()]).is_empty()

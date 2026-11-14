extends GdUnitTestSuite
## One-core P3 step 41 (the human gate, the activation lifecycle, O9): the explicit Activate / Cancel / End of a human
## unit, driven through the doors a player uses, flag on, an AI seat, a recording network (FakeNet) for what the other
## table is told.
##  (a) explicit start: a unit that was not started cannot be dragged ("Activate <Unit> first."); after Activate it moves;
##  (b) the lock: while A's activation is open B cannot be dragged or started ("Finish A's activation first."); when A's
##      activation ended (a volley) B starts;
##  (c) Cancel (the card's button): the models go back to the move ledger's own starts, `moved_round` as before the Start,
##      the unit is NOT activated, the other table gets the move, the turn, the trails' undo and the line (no activation
##      fact); after a die Cancel is gone and a late cancel changes nothing;
##  (d) End without an action: the unit is Activated, the session is gone, one activation fact, the selector shows Off again;
##  (e) flag off: the drag works unstarted and "Activate" ends in one press, as today.
## Real: the main scene, NmlCore, the drag machine, the unit card. Constructed: plain units (10 rifles, 3 scouts, a foe of 5).

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const CANCELLED := "Rifles cancelled its activation - back at its start."


## The network with its transport swapped out: every frame is written down, nothing is sent (presence traffic is not
## game state and is not written down, so a "no frames" case does not depend on how long a frame takes).
class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	const PRESENCE := ["sync_cursor_position", "sync_camera_direction", "sync_camera_position"]
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:
		if not PRESENCE.has(method):
			sent.append({"m": method, "a": args})
	func send_command(type: String, payload: Variant = {}, _target_peer: int = 0) -> bool:
		sent.append({"m": type, "a": [payload]})
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
var _real_radial_net: Node
var _net: FakeNet
var _a: GameUnit   # Rifles, 10 models
var _b: GameUnit   # Scouts, 3 models: the other unit of the same side
var _foe: GameUnit


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	_a = _human("Rifles", 10, 0.0, 901)
	_b = _human("Scouts", 3, -14.0, 951)
	_foe = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	_foe.is_activated = true   # the AI has nothing left to do: no reply
	_real_net = _main.network_manager
	_net = FakeNet.new()
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net
	_real_om_net = _main.object_manager._network_manager
	_main.object_manager._network_manager = _net   # the drag machine's own broadcasts (the restore batch)
	_real_radial_net = _main.radial_menu_controller.network_manager
	_main.radial_menu_controller.network_manager = _net   # the activation fact goes out through the radial


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	_main.network_manager = _real_net
	_main.object_manager._network_manager = _real_om_net
	_main.radial_menu_controller.network_manager = _real_radial_net
	_net.free()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _human(unit_name: String, models: int, x_in: float, first_id: int) -> GameUnit:
	var u := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": unit_name, "models": models, "x_in": x_in}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": models, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", first_id + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


func _poses(u: GameUnit) -> Array:
	return u.models.map(func(m: ModelInstance) -> Array: return [m.node.global_position, m.node.rotation.y])


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _frames(method: String) -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return f["m"] == method)


## A real drag of the whole unit `dx_in` inches along +x, landed (the drop tween done).
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


## The activation buttons the presented card shows, sorted.
func _card_buttons() -> Array:
	var out: Array = []
	for n: Node in _main.unit_dock.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text in ["Activate", "End activation", "Cancel"]:
			out.append(b.text)
	out.sort()
	return out


func _present(u: GameUnit) -> void:
	_main.unit_dock.present_unit(u)
	await E2EBoot.settle(get_tree())


func _press(label: String) -> void:
	for n: Node in _main.unit_dock.find_children("*", "Button", true, false):
		if (n as Button).text == label and (n as Button).is_visible_in_tree():
			(n as Button).pressed.emit()
			return
	assert_bool(false).override_failure_message("no %s button on the card: %s" % [label, _card_buttons()]).is_true()


## (a) A unit that was not started cannot be dragged: nothing moves and the game says to activate it first, once (log and
## toast). After the card's Activate the same drag moves it and stamps it moved.
func test_a_unit_that_was_not_started_moves_only_after_activate() -> void:
	var at := _poses(_a)
	await _drag(_a, 4.0)
	assert_array(_poses(_a)).override_failure_message("an un-activated unit moved").is_equal(at)
	assert_int(_lines("Activate Rifles first.")).override_failure_message("lines: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(1)
	assert_bool(_a.unit_properties.has("moved_round")).is_false()
	await _main.radial_menu_controller.card_start_activation(_a)
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_true()
	assert_bool(_a.is_activated).override_failure_message("the Start spent the unit").is_false()
	await _drag(_a, 4.0)
	assert_array(_poses(_a)).override_failure_message("the started unit did not move").is_not_equal(at)
	assert_int(int(_a.unit_properties.get("moved_round", -1))).is_equal(1)
	assert_int(_lines("Activate Rifles first.")).override_failure_message("a second refusal").is_equal(1)


## (b) The lock: while A's activation is open B can be neither dragged nor started - the O5 sentence each time, B has no
## session. When A's activation ended (a volley) B starts and moves.
func test_one_open_activation_locks_the_others_until_it_ends() -> void:
	await _main.radial_menu_controller.card_start_activation(_a)   # A is open and has not moved
	var sentence := "Finish Rifles's activation first."
	var b_at := _poses(_b)
	await _drag(_b, 4.0)
	assert_array(_poses(_b)).override_failure_message("B moved while A was open").is_equal(b_at)
	assert_int(_lines(sentence)).override_failure_message("drag lines: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(1)
	await _main.radial_menu_controller.card_start_activation(_b)
	assert_int(_lines(sentence)).override_failure_message("the Activate on B").is_equal(2)
	assert_bool(CoreActivation.session_open(_b.unit_id)).override_failure_message("B got a session").is_false()
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_true()
	_main.seed_tray_rng(3)
	await _main._run_human_attack(_a, _foe, false)   # A's volley ends its activation
	assert_bool(_a.is_activated).override_failure_message("the volley did not end A's activation").is_true()
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_false()
	await _main.radial_menu_controller.card_start_activation(_b)
	assert_bool(CoreActivation.session_open(_b.unit_id)).override_failure_message("B could not start after A ended").is_true()
	await _drag(_b, 4.0)
	assert_array(_poses(_b)).override_failure_message("B did not move").is_not_equal(b_at)


## (c) Cancel after two drops: every model back at the move ledger's own start (read BEFORE the cancel), the stamp as it
## was, the unit not activated, the core's sentence once, the card offers Activate again; the other table is told a move
## and a turn per model, the undo of each drop's chalk and the line - and no activation fact.
func test_cancel_puts_the_unit_back_and_tells_the_other_table() -> void:
	await _present(_a)
	await _main.radial_menu_controller.card_start_activation(_a)
	await _runner.simulate_frames(2)
	assert_array(_card_buttons()).is_equal(["Cancel", "End activation"])
	var at := _poses(_a)
	await _drag(_a, 2.0)
	await _drag(_a, 2.0)
	assert_array(_poses(_a)).override_failure_message("the drags did not move").is_not_equal(at)
	var starts: Dictionary = _main.move_trails.ledger.round_starts_for_unit(_a.unit_id, 1)   # BEFORE the cancel
	assert_int(starts.size()).is_equal(10)
	_net.sent.clear()
	_press("Cancel")
	await _runner.simulate_frames(4)
	assert_array(_poses(_a)).override_failure_message("not back at the start").is_equal(at)
	for m in _a.models:
		var p: Vector3 = (m as ModelInstance).node.global_position
		var from: Vector2 = starts[int((m as ModelInstance).node.get_meta("network_id"))]
		assert_float(Vector2(p.x, p.z).distance_to(from)).override_failure_message("a model off the ledger's start").is_less(0.0001)
	assert_bool(_a.unit_properties.has("moved_round")).override_failure_message("moved_round kept").is_false()
	assert_bool(_a.is_activated).override_failure_message("a cancel spent the unit").is_false()
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_false()
	assert_int(_lines(CANCELLED)).is_equal(1)
	assert_array(_card_buttons()).is_equal(["Activate"])
	assert_int(_frames("move_object_networked").size()).is_equal(10)
	assert_int(_frames("rotate_object_networked").size()).is_equal(10)
	assert_int(_frames("sync_move_trails_undo").size()).override_failure_message("one undo per drop").is_equal(2)
	assert_int(_frames("sync_log_event").size()).is_equal(1)
	assert_int(_frames("sync_unit_activation").size()).override_failure_message("a cancel sent an activation").is_equal(0)


## (c) After the first die of the activation Cancel is gone (the card too) and a late cancel changes nothing.
func test_after_a_die_the_cancel_is_gone() -> void:
	await _present(_a)
	await _main.radial_menu_controller.card_start_activation(_a)
	await _drag(_a, 2.0)
	assert_bool(CoreActivation.can_cancel(_a.unit_id)).is_true()
	await _main._solo_tray_roll(1, 4, "You")   # a batch roll: one die
	assert_bool(CoreActivation.can_cancel(_a.unit_id)).override_failure_message("a die left the Cancel").is_false()
	await E2EBoot.settle(get_tree())
	assert_array(_card_buttons()).is_equal(["End activation"])
	var moved := _poses(_a)
	_main.core_activation_cancel(_a)
	await _runner.simulate_frames(3)
	assert_array(_poses(_a)).override_failure_message("a late cancel moved the unit").is_equal(moved)
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_true()
	assert_int(_lines(CANCELLED)).is_equal(0)


## (d) End without an action: the unit is Activated through the card's one door, the session is gone, the other table gets
## one activation fact, and the selector row shows Off again.
func test_end_without_an_action_activates_and_closes_the_session() -> void:
	await _present(_a)
	await _main.radial_menu_controller.card_start_activation(_a)
	_main.object_manager._deselect_all()   # the selector row follows the selection
	_main.object_manager._add_to_selection((_a.models[0] as ModelInstance).node)
	await _runner.simulate_frames(2)
	assert_bool((_main._movement_cap_buttons[ObjectManager.MovementCap.OFF] as Button).visible).override_failure_message("Off shown during the activation").is_false()
	_net.sent.clear()
	_press("End activation")
	await _runner.simulate_frames(6)
	assert_bool(_a.is_activated).override_failure_message("End did not activate").is_true()
	assert_bool(CoreActivation.session_open(_a.unit_id)).override_failure_message("the session stays open").is_false()
	assert_int(_frames("sync_unit_activation").size()).override_failure_message("frames: %s" % [_net.sent.map(func(f: Dictionary) -> String: return str(f["m"]))]).is_equal(1)
	assert_bool((_main._movement_cap_buttons[ObjectManager.MovementCap.OFF] as Button).visible).override_failure_message("Off still hidden").is_true()
	assert_array(_card_buttons()).is_empty()


## (e) Flag off: nothing of the lifecycle exists - an un-activated unit drags freely, no sentence, no session, and the
## card's Activate ends the activation in one press with one activation fact, as today.
func test_flag_off_plays_as_today() -> void:
	CoreActivation._env = 0
	var at := _poses(_a)
	await _drag(_a, 4.0)
	assert_array(_poses(_a)).override_failure_message("the drag was refused with the flag off").is_not_equal(at)
	assert_int(_lines("Activate Rifles first.")).is_equal(0)
	_net.sent.clear()
	await _main.radial_menu_controller.card_start_activation(_a)
	assert_bool(_a.is_activated).override_failure_message("Activate did not end in one press").is_true()
	assert_bool(CoreActivation.session_open(_a.unit_id)).is_false()
	assert_int(_lines("Rifles begins its activation.")).is_equal(0)
	assert_int(_frames("sync_unit_activation").size()).is_equal(1)

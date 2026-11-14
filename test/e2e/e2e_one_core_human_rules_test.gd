extends GdUnitTestSuite
## One-core P3 step 40 (the human gate, refusals and reset): the rules that say NO or take a move back, at the doors a
## player uses, flag on, an AI seat, a recording network (FakeNet) for what the other table is told.
##  (a) a unit that shot cannot be dragged: the table's own sentence and a snap-back (the core's order rule of step 9 is
##      its defensive twin);
##  (b) Rush declared and 9" moved, then a shot: the O3 Rush sentence, no die thrown, the activation stays open;
##  (c) the mode switch after a move: "Keep" changes nothing; "Reset and switch" puts the models back at their start (the
##      move ledger's own starts, read BEFORE the reset), writes the O3 line, restores `moved_round` and tells the other
##      table the move, the turn, the trails' undo and the line.
## Real: the main scene, NmlCore, the selector, the drag machine, the card. Constructed: plain units (10 rifles vs 5), a
## spare unit of the shooter's side so the round does not turn after a volley.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


## The network with its transport swapped out: every frame is written down, nothing is sent.
class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	## Presence traffic (cursor ~15 Hz, camera 5 Hz) is not game state: not written down, so a "no frames" case does not
	## depend on how long a frame takes on the machine (CI sends one every slow frame).
	const PRESENCE := ["sync_cursor_position", "sync_camera_direction", "sync_camera_position"]
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
var _net: FakeNet
var _att: GameUnit
var _foe: GameUnit
var _spare: GameUnit


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
	_att = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Rifles", "models": 10, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	for i in _att.models.size():
		(_att.models[i] as ModelInstance).node.set_meta("network_id", 901 + i)
		(_att.models[i] as ModelInstance).node.set_meta("model_instance", _att.models[i])
	_foe = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	_foe.is_activated = true   # the AI has nothing left to do: no reply
	_spare = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}), {})
	_real_net = _main.network_manager
	_net = FakeNet.new()
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net
	_real_om_net = _main.object_manager._network_manager
	_main.object_manager._network_manager = _net   # the drag machine's own broadcasts (the restore batch)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	_main.network_manager = _real_net
	_main.object_manager._network_manager = _real_om_net
	_net.free()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


func _poses() -> Array:
	return _att.models.map(func(m: ModelInstance) -> Array: return [m.node.global_position, m.node.rotation.y])


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _toasts(text: String) -> int:
	return _main.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == text).size()


func _frames(method: String) -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return f["m"] == method)


## A real drag of the whole unit `dx_in` inches along +x, landed (the drop tween done).
func _drag(dx_in: float) -> void:
	var om: Node3D = _main.object_manager
	om._deselect_all()
	for m in _att.models:
		om._add_to_selection((m as ModelInstance).node)
	var a: Node3D = (_att.models[0] as ModelInstance).node
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + dx_in * INCH, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(3)
	await get_tree().create_timer(0.3).timeout


## Presses `mode` on the selector and answers the card it opens ("Reset and switch" or "Keep"); true when a card asked.
func _switch(mode: int, answer: String) -> bool:
	_main._on_movement_cap_pressed(mode)   # not awaited: it waits on the card
	await _runner.simulate_frames(2)
	var card: PromptCard = null
	for c in _main.get_children():
		if c is PromptCard and not (c as Node).is_queued_for_deletion():
			card = c
	if card == null:
		return false
	(card.ok_button if answer == "Reset and switch" else card.cancel_button).pressed.emit()
	await _runner.simulate_frames(3)
	return true


## (a) The table's lock on a unit that shot, reached through the real drag: with the activation open and the shot stamped,
## a drag says the table's own sentence once, puts every model back where the drag found it and tells the other table
## the restore batch and the line. (The state is built by stamping `shot_round` on a started unit: after a real volley
## the activation is over and the step-30 gate answers first, see the next case.)
func test_a_unit_that_shot_cannot_be_dragged_and_snaps_back() -> void:
	assert_bool(_main.core_activation_start(_att)).is_true()
	_att.unit_properties["shot_round"] = 1
	var at := _poses()
	_net.sent.clear()
	await _drag(4.0)
	var sentence := "Rifles has already shot this round — it cannot move now"
	assert_array(_poses()).override_failure_message("the drag moved a unit that shot").is_equal(at)
	assert_int(_lines(sentence)).override_failure_message("the sentence: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(1)
	assert_int(_toasts(sentence)).is_equal(1)
	assert_int(_frames("move_objects_batch_networked").size()).override_failure_message("the restore batch").is_equal(1)
	assert_int(_frames("sync_log_event").size()).is_equal(1)


## (a) After a real core volley the activation is over and the unit stays where it is: a drag moves nothing and says why
## exactly once. FINDING (the sentence): it is the step-30 gate's "Activate <Unit> first." (the unit has no open session),
## not the table's "has already shot this round" above; this case pins only that nothing moves and one line is written.
func test_after_a_volley_a_drag_moves_nothing_and_says_so_once() -> void:
	assert_bool(_main.core_activation_start(_att)).is_true()
	_main.seed_tray_rng(3)
	await _main._run_human_attack(_att, _foe, false)
	assert_int(int(_att.unit_properties.get("shot_round", -1))).override_failure_message("no volley").is_equal(1)
	var at := _poses()
	var before: int = _main.battle_log.entries().size()
	await _drag(4.0)
	assert_array(_poses()).override_failure_message("the drag moved a unit that shot").is_equal(at)
	var said: Array = _main.battle_log.entries().slice(before).filter(func(e: Dictionary) -> bool:
		return int(e["category"]) == BattleLog.Category.MOVEMENT)
	assert_int(said.size()).override_failure_message("lines after the drag: %s" % [said]).is_equal(1)


## (b) Rush declared and 9" moved, then the shot: the core's O3 sentence once (log and toast), no die thrown, the unit
## neither stamped as having shot nor activated, its activation still open.
func test_a_rushed_move_then_a_shot_is_refused_with_the_o3_sentence() -> void:
	assert_bool(_main.core_activation_start(_att)).is_true()
	_main.object_manager.set_movement_cap(ObjectManager.MovementCap.RUSH)
	await _drag(9.0)
	var ended := [0]
	_main.radial_menu_controller.unit_activated.connect(func(_u: GameUnit) -> void: ended[0] += 1)
	var rng: int = _main._tray_rng.state
	await _main._run_human_attack(_att, _foe, false)
	var sentence := "Rifles rushed this activation - it cannot shoot."
	assert_int(_lines(sentence)).override_failure_message("the sentence: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(1)
	assert_int(_toasts(sentence)).is_equal(1)
	assert_int(_main._tray_rng.state).override_failure_message("a die was thrown").is_equal(rng)
	assert_int(_foe.get_alive_count()).is_equal(5)
	assert_bool(_att.unit_properties.has("shot_round")).override_failure_message("stamped as a shot").is_false()
	assert_int(ended[0]).override_failure_message("the refused shot ended the activation").is_equal(0)
	assert_bool(CoreActivation.session_open(_att.unit_id)).is_true()


## (c) A mode switch after a move asks. "Keep" changes nothing (models, selector, stamp, frames, lines). "Reset and switch"
## puts every model back at its start - cross-checked against the move ledger's own starts read BEFORE the reset - with
## the O3 line, `moved_round` as it was before the Start, and the other table told: a move and a turn per model, the
## trails' undo, the stamp, the line.
func test_a_mode_switch_after_a_move_keeps_or_resets_with_the_other_table_told() -> void:
	assert_bool(_main.core_activation_start(_att)).is_true()
	var at := _poses()
	await _drag(4.0)
	var moved := _poses()
	assert_array(moved).override_failure_message("the drag did not move").is_not_equal(at)
	assert_int(int(_att.unit_properties.get("moved_round", -1))).override_failure_message("not stamped moved").is_equal(1)
	var starts: Dictionary = _main.move_trails.ledger.round_starts_for_unit(_att.unit_id, 1)   # BEFORE the reset
	assert_int(starts.size()).is_equal(10)
	var line := "Rifles is back at its start - movement mode is now Rush."
	_net.sent.clear()
	_main._broadcast_presence(0.3)   # one cursor and one camera frame, as a slow CI frame sends every frame
	assert_bool(await _switch(ObjectManager.MovementCap.RUSH, "Keep")).override_failure_message("no card").is_true()
	assert_array(_poses()).override_failure_message("Keep moved the unit").is_equal(moved)
	assert_int(int(_main.object_manager._movement_cap)).is_equal(ObjectManager.MovementCap.ADVANCE)
	assert_int(int(_att.unit_properties.get("moved_round", -1))).is_equal(1)
	assert_int(_net.sent.size()).override_failure_message("Keep sent frames: %s" % [_net.sent.map(func(f: Dictionary) -> String: return str(f["m"]))]).is_equal(0)
	assert_int(_lines(line)).is_equal(0)
	assert_bool(await _switch(ObjectManager.MovementCap.RUSH, "Reset and switch")).is_true()
	assert_array(_poses()).override_failure_message("not back at the start").is_equal(at)
	for m in _att.models:
		var p: Vector3 = (m as ModelInstance).node.global_position
		var from: Vector2 = starts[int((m as ModelInstance).node.get_meta("network_id"))]
		assert_float(Vector2(p.x, p.z).distance_to(from)).override_failure_message("a model off the ledger's start").is_less(0.0001)
	assert_int(int(_main.object_manager._movement_cap)).is_equal(ObjectManager.MovementCap.RUSH)
	assert_bool(_att.unit_properties.has("moved_round")).override_failure_message("moved_round kept").is_false()
	assert_int(_lines(line)).is_equal(1)
	assert_int(_frames("move_object_networked").size()).is_equal(10)
	assert_int(_frames("rotate_object_networked").size()).is_equal(10)
	assert_int(_frames("sync_move_trails_undo").size()).is_equal(1)
	assert_int(_frames("sync_unit_property").filter(func(f: Dictionary) -> bool: return f["a"][1] == "moved_round").size()) \
		.override_failure_message("the stamp frame").is_equal(1)
	assert_int(_frames("sync_log_event").size()).is_equal(1)

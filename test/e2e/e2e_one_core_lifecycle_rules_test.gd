extends GdUnitTestSuite
## One-core P3 step 70 (O14 (1b)): the explicit activation of units WITH special rules, through the doors a player uses,
## flag on, an AI seat, a recording network (FakeNet) for what the other table is told.
##  (a) Cancel after a one-time effect: a Utility Buff bearer opens a Shoot pick (the buff lands on a friendly unit) and a
##      Speed Feat unit spends its feat; Cancel puts the unit back at its start (the table's own bands cap such a unit,
##      O18 (a)), gives every spend back on every unit, writes the cancel sentence and one "is unspent again" line per
##      rule, and tells the other table the move, the turn, the trails' undo, the spell records and the lines - no
##      activation fact, no unjournaled door (tripwire 0);
##  (c) End after a move: the unit is Activated and the AI replies exactly once;
##  (d) flag off: the same doors work without a Start, as today.
## Real: the main scene, NmlCore, the drag machine, the unit card, the registry rules. Constructed: AoF orc units.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const CANCELLED := "%s cancelled its activation - back at its start."
const FEAT := "speed_feat_used_speed_feat"


## The network with its transport swapped out: every frame is written down, nothing is sent (presence traffic is not
## game state and is not written down).
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
	CoreActivation.tripwire_hits = 0
	_real_net = _main.network_manager
	_net = FakeNet.new()
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net
	_real_om_net = _main.object_manager._network_manager
	_main.object_manager._network_manager = _net
	_real_radial_net = _main.radial_menu_controller.network_manager
	_main.radial_menu_controller.network_manager = _net


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


## An AoF orc unit of seat `seat` at `x_in` with `models` models (a friendly buff picks the unit with the most models).
func _orc(uname: String, models: int, x_in: float, rules: Array, seat: int = 1) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": seat, "name": uname, "models": models, "x_in": x_in, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "aof", "faction_folder": "orcs", "rules": rules},
		{"name": "Bow", "range_in": 24, "attacks": 1, "count": models, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", int(hash(uname) % 5000) * 100 + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


func _poses(u: GameUnit) -> Array:
	return u.models.map(func(m: ModelInstance) -> Array: return [m.node.global_position, m.node.rotation.y])


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _unspent() -> Array:
	var out: Array = _main.battle_log.entries().map(func(e: Dictionary) -> String: return str(e["text"])) \
		.filter(func(t: String) -> bool: return t.ends_with(" is unspent again."))
	out.sort()
	return out


func _frames(method: String) -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return f["m"] == method)


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
	await get_tree().create_timer(0.3).timeout


func _press(label: String) -> void:
	for n: Node in _main.unit_dock.find_children("*", "Button", true, false):
		if (n as Button).text == label and (n as Button).is_visible_in_tree():
			(n as Button).pressed.emit()
			return
	assert_bool(false).override_failure_message("no %s button on the card" % label).is_true()


func _start(u: GameUnit) -> void:
	_main.unit_dock.present_unit(u)
	await E2EBoot.settle(get_tree())
	await _main.radial_menu_controller.card_start_activation(u)
	assert_bool(CoreActivation.session_open(u.unit_id)).override_failure_message("no session for %s" % u.get_name()).is_true()
	await _runner.simulate_frames(2)


## Cancel through the card, then the frames: the other table was told the move, the turn and the trails' undo of the
## drag, the cancel line and the spend lines, and NEVER an activation fact; no door the journal missed.
func _cancel_and_check(u: GameUnit, at: Array, spent: Array) -> void:
	_net.sent.clear()
	_press("Cancel")
	await _runner.simulate_frames(4)
	assert_array(_poses(u)).override_failure_message("not back at the start").is_equal(at)
	assert_bool(u.unit_properties.has("moved_round")).override_failure_message("moved_round kept").is_false()
	assert_bool(u.is_activated).override_failure_message("a cancel spent the unit").is_false()
	assert_bool(CoreActivation.session_open(u.unit_id)).is_false()
	assert_int(_lines(CANCELLED % u.get_name())).is_equal(1)
	assert_array(_unspent()).override_failure_message("one line per spent rule").is_equal(spent)
	assert_int(_frames("move_object_networked").size()).is_equal(u.models.size())
	assert_int(_frames("rotate_object_networked").size()).is_equal(u.models.size())
	assert_int(_frames("sync_move_trails_undo").size()).is_equal(1)
	assert_int(_frames("sync_log_event").size()).override_failure_message("log frames: %s" % [_net.sent.map(func(f: Dictionary) -> String: return str(f["m"]))]).is_equal(1 + spent.size())
	assert_int(_frames("sync_unit_activation").size()).override_failure_message("a cancel sent an activation").is_equal(0)
	assert_int(CoreActivation.tripwire_hits).override_failure_message("an unjournaled door").is_equal(0)


## (a) A Utility Buff bearer: the Shoot pick spends the buff onto the friendly Boyz (a record and a granted rule on
## ANOTHER unit); the pick is right-clicked away; Cancel gives it all back on both units.
func test_cancel_gives_back_a_utility_buff_on_another_unit() -> void:
	var boss := _orc("Boss", 3, 0.0, ["Piercing Assault Buff"])
	var boyz := _orc("Boyz", 5, -6.0, [])
	_orc("Raiders", 5, 20.0, [], 2)
	var boyz_rules: Array = (boyz.unit_properties["special_rules"] as Array).duplicate()
	await _start(boss)
	var at := _poses(boss)
	await _drag(boss, 4.0)
	await _main.solo_begin_targeting(boss, false)   # the buff is spent at the pick, not at the shot
	_main._solo_end_targeting()   # the right-click
	assert_bool(not (_main._solo_spell_mods.get(boyz.get_instance_id(), []) as Array).is_empty()) \
		.override_failure_message("fixture: the buff did not land on the friend").is_true()
	assert_bool(int(boss.unit_properties.get("utility_buff_round", -1)) == 1).override_failure_message("fixture: no stamp").is_true()
	await _cancel_and_check(boss, at, ["Boss: Piercing Assault Buff is unspent again."])
	for u: GameUnit in [boss, boyz]:
		assert_array(_main._solo_spell_mods.get(u.get_instance_id(), [])).override_failure_message("%s keeps a record" % u.get_name()).is_empty()
	assert_array(boyz.unit_properties["special_rules"]).override_failure_message("the friend keeps the granted rule").is_equal(boyz_rules)
	assert_bool(boss.unit_properties.has("utility_buff_round")).override_failure_message("the stamp stays").is_false()
	var spell_frames: Array = _frames("sync_spell_mods").map(func(f: Dictionary) -> Array: return f["a"])
	assert_array(spell_frames).override_failure_message("one record frame, for the friend only: %s" % [spell_frames]).is_equal([[boyz.unit_id, []]])


## (a) A Speed Feat unit: the feat's latch and record go back on Cancel, the latch through exactly one property frame.
func test_cancel_gives_back_a_speed_feat() -> void:
	var runner_unit := _orc("Runner", 3, 0.0, ["Speed Feat"])
	_orc("Raiders", 5, 20.0, [], 2)
	await _start(runner_unit)
	var at := _poses(runner_unit)
	await _drag(runner_unit, 4.0)
	_main.solo_spend_speed_feat(runner_unit)
	assert_bool(bool(runner_unit.unit_properties.get(FEAT, false))).override_failure_message("fixture: no latch").is_true()
	await _cancel_and_check(runner_unit, at, ["Runner: Speed Feat is unspent again."])
	assert_bool(runner_unit.unit_properties.has(FEAT)).override_failure_message("the latch stays").is_false()
	assert_array(_main._solo_spell_mods.get(runner_unit.get_instance_id(), [])).is_empty()
	var latch: Array = _frames("sync_unit_property").filter(func(f: Dictionary) -> bool: return f["a"][1] == FEAT)
	assert_int(latch.size()).override_failure_message("latch frames").is_equal(1)
	assert_array(_frames("sync_spell_mods").map(func(f: Dictionary) -> Array: return f["a"])).is_equal([[runner_unit.unit_id, []]])



## (c) End after a move: the unit of a Utility Buff rule is Activated through the card's one door, the session is gone, the
## other table gets one activation fact, and the AI answers with exactly ONE of its two units.
func test_end_after_a_move_activates_and_the_ai_replies_once() -> void:
	var boss := _orc("Boss", 3, 0.0, ["Piercing Assault Buff"])
	var foes: Array = [_orc("Att A", 5, 20.0, [], 2), _orc("Att B", 5, 24.0, [], 2)]
	_orc("Spare", 1, -20.0, [])   # the human side still has a unit to activate, so the alternation waits for it after one reply
	await _start(boss)
	await _drag(boss, 4.0)
	_net.sent.clear()
	_press("End activation")
	for i in 400:   # the reply runs on its own, frame by frame (batch: no pacing)
		await _runner.simulate_frames(1)
		if foes.any(func(g: GameUnit) -> bool: return g.is_activated):
			break
	await _runner.simulate_frames(60)
	assert_bool(boss.is_activated).override_failure_message("End did not activate").is_true()
	assert_bool(CoreActivation.session_open(boss.unit_id)).override_failure_message("the session stays open").is_false()
	assert_int(_frames("sync_unit_activation").filter(func(f: Dictionary) -> bool: return f["a"][0] == boss.unit_id).size()).is_equal(1)
	assert_int(foes.filter(func(g: GameUnit) -> bool: return g.is_activated).size()).override_failure_message("the AI replies once").is_equal(1)


## (d) Flag off: the same doors work without a Start and nothing of the lifecycle exists - the Shoot pick opens and spends
## the buff, the feat is spent, the card offers no "Cancel".
func test_flag_off_the_doors_work_without_a_start() -> void:
	CoreActivation._env = 0
	var boss := _orc("Boss", 3, 0.0, ["Piercing Assault Buff"])
	var boyz := _orc("Boyz", 5, -6.0, [])
	var runner_unit := _orc("Runner", 3, 8.0, ["Speed Feat"])
	_orc("Raiders", 5, 20.0, [], 2)
	await _main.solo_begin_targeting(boss, false)
	assert_object(_main._solo_target_mode.get("unit")).override_failure_message("no pick without the flag").is_same(boss)
	assert_bool(int(boss.unit_properties.get("utility_buff_round", -1)) == 1).override_failure_message("the buff was not spent").is_true()
	assert_bool(not (_main._solo_spell_mods.get(boyz.get_instance_id(), []) as Array).is_empty()).is_true()
	_main._solo_end_targeting()
	_main.solo_spend_speed_feat(runner_unit)
	assert_bool(bool(runner_unit.unit_properties.get(FEAT, false))).override_failure_message("the feat was not spent").is_true()
	assert_bool(_main.battle_log.entries().any(func(e: Dictionary) -> bool: return str(e["text"]).ends_with(" first."))) \
		.override_failure_message("a refusal with the flag off").is_false()
	_main.unit_dock.present_unit(boss)
	await E2EBoot.settle(get_tree())
	var cancel_buttons: Array = _main.unit_dock.find_children("*", "Button", true, false).filter(func(n: Node) -> bool:
		return (n as Button).text == "Cancel" and (n as Button).is_visible_in_tree())
	assert_int(cancel_buttons.size()).override_failure_message("a Cancel button with the flag off").is_equal(0)

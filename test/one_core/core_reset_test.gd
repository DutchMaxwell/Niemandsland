extends GdUnitTestSuite
## One-core P3 step 32: `CoreActivation.reset_to_start` puts a unit back where its open activation started through the
## existing take-back: positions and facing, every drop's chalk and ledger entries (drags and step 65a's formation
## drops), moved_round, the undo stack, one log line, and the frames the other table reads.
## Real: the main scene with its move trails, ledger and undo manager, the NetworkManager class (only the transport is
## recorded, pattern e2e_mp_log_channel_test's FakeNet), the NmlCore extension. Constructed: a plain three-model human
## unit (ParityTable._make_unit) on an AI-seat table, flag on.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const LINE := "Rifles is back at its start - movement mode is now Rush."

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:
		sent.append({"m": method, "a": args})
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	_end_net()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The recording transport is not in the tree: it is freed inside the case that made it (no orphan).
func _end_net() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


func _recording_net() -> FakeNet:
	var net := FakeNet.new()
	net.army_manager = _main.opr_army_manager
	_net = net
	_main.network_manager = net
	return net


func _rifles() -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": 1, "name": "Rifles", "models": 3, "x_in": 0.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", 901 + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _nodes(u: GameUnit) -> Array:
	return u.models.map(func(m: ModelInstance) -> Node3D: return m.node)


## Every model's position and facing.
func _poses(u: GameUnit) -> Array:
	return u.models.map(func(m: ModelInstance) -> Array: return [m.node.global_position, m.node.rotation.y])


func _select(objs: Array) -> void:
	_main.object_manager._selected_objects.clear()
	for o in objs:
		_main.object_manager._selected_objects.append(o)


## Screen point whose y=0 table-plane ray hit is (wx, wz).
func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## A real drag of the whole unit `dx_in` inches along +x (the object_manager_test pattern); one drop, landed.
func _drag(u: GameUnit, dx_in: float) -> void:
	var om: Node3D = _main.object_manager
	var a: Node3D = (u.models[0] as ModelInstance).node
	_select(_nodes(u))
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + dx_in * 0.0254, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(3)
	await get_tree().create_timer(0.3).timeout   # the 0.2 s drop tween has landed; the next drop mints its own id


func _drop_ids(u: GameUnit) -> Array:
	var out: Array = []
	for e in _main.move_trails.ledger.entries_for_unit(u.unit_id):
		if not out.has(int(e["drop_id"])):
			out.append(int(e["drop_id"]))
	return out


func _chalk(u: GameUnit) -> Array:
	return _main.move_trails._trails.filter(func(r: Dictionary) -> bool: return str(r["unit"]) == u.unit_id)


func _log_lines(part: String) -> Array:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]).contains(part))


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


func _sent(net: FakeNet, method: String) -> Array:
	return net.sent.filter(func(f: Dictionary) -> bool: return f["m"] == method).map(func(f: Dictionary) -> Array: return f["a"])


## Step 32: two drags (two drop ids), then the reset with the selector-switch sentence: every model at its start
## position and facing, no ledger entry or chalk left, moved_round as before the Start, nothing for Ctrl+Z, exactly the
## passed line and no "takes back its move"; on the wire one move and one rotation per model, one trails-undo per drop
## id and the log event.
func test_a_reset_puts_the_unit_back_and_erases_every_drop() -> void:
	var u := _rifles()
	u.unit_properties["moved_round"] = 0   # moved last round: the reset must give back 0, not erase it
	var at := _poses(u)
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	await _drag(u, 2.0)
	await _drag(u, 2.0)
	var drops := _drop_ids(u)
	assert_int(drops.size()).override_failure_message("drops: %s" % [drops]).is_equal(2)
	assert_array(_poses(u)).override_failure_message("the drags did not move").is_not_equal(at)
	var peer: int = _main.network_manager.get_my_peer_id()
	var net := _recording_net()
	CoreActivation.reset_to_start(_main, u, LINE)
	assert_array(_poses(u)).override_failure_message("not back at the start").is_equal(at)
	assert_array(_main.move_trails.ledger.entries_for_unit(u.unit_id)).override_failure_message("ledger left").is_empty()
	assert_array(_chalk(u)).override_failure_message("chalk left").is_empty()
	assert_int(int(u.unit_properties.get("moved_round", -1))).override_failure_message("moved_round").is_equal(0)
	assert_array(_log_lines(LINE)).has_size(1)
	assert_array(_log_lines("takes back its move")).is_empty()
	# Exact multisets (sorted), not containment: each model moves and turns ONCE on the wire, each drop is undone once.
	assert_array(_sorted(_sent(net, "move_object_networked").map(func(a: Array) -> int: return int(a[0])))) \
		.override_failure_message("moves: %s" % [net.sent]).is_equal([901, 902, 903])
	assert_array(_sorted(_sent(net, "rotate_object_networked").map(func(a: Array) -> int: return int(a[0])))) \
		.override_failure_message("rotations: %s" % [net.sent]).is_equal([901, 902, 903])
	assert_array(_sorted(_sent(net, "sync_move_trails_undo").map(func(a: Array) -> int: return int(a[2])))) \
		.override_failure_message("trails undo: %s" % [net.sent]).is_equal(_sorted(drops))
	assert_array(_sent(net, "sync_log_event").filter(func(a: Array) -> bool: return a[1] == LINE)).has_size(1)
	assert_array(_sent(net, "sync_unit_property").filter(func(a: Array) -> bool: return a[1] == "moved_round")) \
		.override_failure_message("moved_round not sent: %s" % [net.sent]).is_equal([[u.unit_id, "moved_round", 0]])
	_end_net()
	assert_str(_main.undo_manager.undo_for(peer)).override_failure_message("Ctrl+Z after a reset").is_equal("")


## Step 32 + 65a (lead 13.11.): a re-form inside the activation is a drop too, and the reset undoes it with the drag; an
## empty line writes nothing.
func test_a_reset_undoes_a_formation_drop_and_an_empty_line_writes_nothing() -> void:
	var u := _rifles()
	var at := _poses(u)
	assert_bool(CoreActivation.open_session(_main, u)).is_true()
	await _drag(u, 2.0)
	_select(_nodes(u))
	_main.object_manager.arrange_selected_in_rows(1)
	assert_int(_drop_ids(u).size()).override_failure_message("no formation drop: %s" % [_drop_ids(u)]).is_equal(2)
	var lines: int = _main.battle_log.entries().size()
	CoreActivation.reset_to_start(_main, u, "")
	assert_array(_poses(u)).override_failure_message("the formation was not undone").is_equal(at)
	assert_array(_main.move_trails.ledger.entries_for_unit(u.unit_id)).is_empty()
	assert_array(_chalk(u)).is_empty()
	assert_bool(u.unit_properties.has("moved_round")).override_failure_message("moved_round stays").is_false()
	assert_int(_main.battle_log.entries().size()).override_failure_message("a line for an empty line").is_equal(lines)


## Step 32 (lead review): a joined hero moves with its started host, so the reset puts both back - every model of the
## pair at its exact start, the hero's own drops (recorded under its key) erased, and its moved_round given back too.
func test_a_reset_puts_a_joined_hero_back_with_its_host() -> void:
	var host := _rifles()
	var hero := ParityTable._make_unit(_main, {"player": 1, "name": "Captain", "models": 1, "x_in": -2.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": []},
		{"name": "Pistol", "range_in": 12, "attacks": 1, "count": 1, "rules": []})
	(hero.models[0] as ModelInstance).node.set_meta("network_id", 951)
	(hero.models[0] as ModelInstance).node.set_meta("model_instance", hero.models[0])
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	var at := _poses(host) + _poses(hero)
	assert_bool(CoreActivation.open_session(_main, host)).is_true()
	var om: Node3D = _main.object_manager
	var a: Node3D = (host.models[0] as ModelInstance).node
	_select(_nodes(host) + _nodes(hero))
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + 2.0 * 0.0254, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(3)
	await get_tree().create_timer(0.3).timeout
	assert_array(_poses(hero)).override_failure_message("the hero did not move").is_not_equal(at.slice(3))
	assert_array(_main.move_trails.ledger.entries_for_unit(hero.unit_id)).override_failure_message("no hero drop").is_not_empty()
	CoreActivation.reset_to_start(_main, host, "")
	assert_array(_poses(host) + _poses(hero)).override_failure_message("the pair is not back at its start").is_equal(at)
	assert_array(_main.move_trails.ledger.entries_for_unit(hero.unit_id)).override_failure_message("hero ledger left").is_empty()
	assert_bool(hero.unit_properties.has("moved_round")).override_failure_message("the hero stays moved").is_false()

extends GdUnitTestSuite
## E2E — combat effects are never replayed: after a resolved volley drew its cues, a late joiner's full
## state sync (the REAL _rpc_sync_game_state with the host's own serialized payload), a save + load and
## an undo + redo of the player's own table actions rebuild the table without drawing a single cue. Cues
## ride only the resolver paths; state and undo paths carry wounds and casualties, never a burst.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SAVE_PATH := "user://e2e_vfx_no_replay.nml"

class FakeNet extends Node:
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_game_version() -> String:
		return "e2e-test-version"
	func send_command(type: String, payload: Variant = {}, _peer: int = 0) -> bool:
		sent.append([type, payload])
		return true
	func broadcast_peer_busy(_busy: bool) -> void:
		pass
	func broadcast_cursor_position(_pos: Vector3) -> void:
		pass
	func broadcast_camera_direction(_yaw: float, _pitch: float, _zoom: float) -> void:
		pass
	func broadcast_camera_position(_pos: Vector3) -> void:
		pass

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _shooters: GameUnit   # the volley's shooters (they live through it), for the player's own table actions after it


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	for fx in _presenters():
		fx.force_for_tests = true
		fx.enabled = true


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A real seeded volley that draws cues; then the presenters are emptied so any later cue would show.
func _volley_then_clear() -> int:
	var shooters := E2EBoot.make_unit(_main, 1, "Rifles", [Vector3.ZERO, Vector3(0.03, 0, 0)])
	var target := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0, 0, 8 * INCH), Vector3(0.03, 0, 8 * INCH)])
	for u in [shooters, target]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	_shooters = shooters
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 3
	w.count = 2
	_main.seed_tray_rng(77)
	await _main._solo_resolve_ai_volley(shooters, target, [{"member": shooters, "quality": 4, "alive": 2,
		"max": 2, "reach": 24, "profile": AiShooting.profiles_in_range([w], 0.0)[0]}], false)
	var drawn: int = (_main._vfx_seen as Dictionary).size()
	assert_int(drawn).override_failure_message("fixture: the volley must draw cues").is_greater(0)
	# the shot show lands its rounds late (chaos window + burst + flight, under 1.7 s): let THIS cue finish first
	await get_tree().create_timer(2.0).timeout
	for fx in _presenters():
		for c in fx.get_children():
			c.free()
	return drawn


func _presenters() -> Array:
	return [_main.result_pips, _main.volley_cue, _main.spell_seal, _main.casualty_show, _main.shot_show, _main.spell_show]


func _children() -> int:
	return _presenters().reduce(func(n: int, fx: Node) -> int: return n + fx.get_child_count(), 0)


func _who() -> String:
	return ", ".join(_presenters().map(func(fx: Node) -> String: return "%s %d" % [fx.name, fx.get_child_count()]))


func test_a_late_joiners_state_sync_replays_no_cue(timeout := 240000) -> void:
	var drawn := await _volley_then_clear()
	var state: Dictionary = _main.save_manager.serialize_game_state()
	var real: Node = _main.network_manager
	var fake := FakeNet.new()
	_main.add_child(fake)   # in the tree like a live session's network node, so a stray cue WOULD be sent
	_main.network_manager = fake
	state["_host_version"] = fake.get_game_version()
	await _main._rpc_sync_game_state(state)
	await E2EBoot.settle(get_tree())
	_main.network_manager = real
	assert_int((_main._vfx_seen as Dictionary).size()).is_equal(drawn)
	assert_int(_children()).override_failure_message(_who()).is_equal(0)
	assert_array(fake.sent.filter(func(s): return s[0] == "vfx_cue")).is_empty()
	fake.free()


func test_a_save_and_load_replays_no_cue(timeout := 240000) -> void:
	var drawn := await _volley_then_clear()
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	assert_int(_main.save_manager.load_game(SAVE_PATH)).is_equal(OK)
	await E2EBoot.settle(get_tree())
	assert_int((_main._vfx_seen as Dictionary).size()).is_equal(drawn)
	assert_int(_children()).override_failure_message(_who()).is_equal(0)


func test_undo_and_redo_of_a_removal_replay_no_cue(timeout := 240000) -> void:
	var drawn := await _volley_then_clear()
	var removed: Array[Node3D] = [_shooters.models.filter(func(m: ModelInstance) -> bool: return m.is_alive)[0].node]
	_main.radial_menu_controller.delete_objects(removed)   # the player's own removal: an undoable table action
	assert_bool(_main.undo_manager.can_undo()).override_failure_message("fixture: the removal must be undoable").is_true()
	_main._undo()
	_main._redo()
	await E2EBoot.settle(get_tree())
	assert_int((_main._vfx_seen as Dictionary).size()).is_equal(drawn)
	assert_int(_children()).override_failure_message(_who()).is_equal(0)

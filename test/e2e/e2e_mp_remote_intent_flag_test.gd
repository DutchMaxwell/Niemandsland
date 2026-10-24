extends GdUnitTestSuite
## Automodus 0.3.15 step 3.4: the "roll my saves without the prompt" switch is the HOST player's own
## preference. An intent executed on the host for a GUEST's unit must never flip it; the host's own
## unit (and plain solo) still flips it on the first executed intent.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true


func after_test() -> void:
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


## A live session on `my_slot` (transport swapped out, as in e2e_rules_online_round_host_test.gd).
func _fake_session(my_slot: int) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(_method: String, _args: Array, _target_peer: int = 0) -> void:\n\tpass\n" \
		+ "func send_command(_type: String, _payload: Variant = {}, _target_peer: int = 0) -> bool:\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = true
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func _unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Reserves keep both sides from exhausting in one activation; Foe is pre-activated so it stays put.
func _run(actor_pid: int) -> void:
	_unit(1, "Reserves", Vector3(50.0 * INCH, 0, 0))
	_unit(2, "Watchers", Vector3(-50.0 * INCH, 0, 0))
	var actor := _unit(actor_pid, "Actor", Vector3.ZERO)
	var foe := _unit(3 - actor_pid, "Foe", Vector3(14.0 * INCH, 0, 0))
	foe.is_activated = true
	await _main._run_player_intent(actor, AiDecision.Action.ADVANCE, foe)
	await E2EBoot.settle(get_tree())


func test_guest_intent_leaves_host_save_prompt_alone(timeout := 60000) -> void:
	_fake_session(1)
	_main._solo_auto_saves = false
	await _run(2)
	assert_bool(_main._solo_auto_saves) \
		.override_failure_message("3.4 - a guest's unit executed on the host must not flip the host's save-prompt switch") \
		.is_false()
	_end_session()


func test_host_own_intent_still_flips_save_prompt(timeout := 60000) -> void:
	_fake_session(1)
	_main._solo_auto_saves = false
	await _run(1)
	assert_bool(_main._solo_auto_saves).is_true()
	_end_session()


func test_solo_intent_still_flips_save_prompt(timeout := 60000) -> void:
	_main._solo_auto_saves = false
	await _run(1)
	assert_bool(_main._solo_auto_saves).is_true()

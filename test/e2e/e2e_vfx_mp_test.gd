extends GdUnitTestSuite
## E2E — combat effects in co-op: the peer that resolves sends every cue ONCE as plain data on the command
## channel; a receiving peer draws it through the same path as the sender, once even when the frame arrives
## twice, and draws nothing for a malformed payload. The receiver never rolls and never touches state.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const A := Vector3(0.1, 0.03, 0.0)
const B := Vector3(0.1, 0.03, 0.25)

class StubNet extends Node:
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		sent.append([type, payload, target_peer])
		return true

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	for fx in [_main.result_pips, _main.volley_cue, _main.spell_seal]:
		fx.force_for_tests = true
		fx.enabled = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_peer_cue_draws_once_even_when_delivered_twice(timeout := 120000) -> void:
	var cue := {"k": "volley", "id": 7, "s": 99, "f": 1, "pairs": [[A, B]]}
	_main._on_network_command("vfx_cue", cue, 2)
	var drawn: int = _main.volley_cue.get_child_count()
	assert_int(drawn).is_greater(0)
	_main._on_network_command("vfx_cue", cue, 2)
	assert_int(_main.volley_cue.get_child_count()).is_equal(drawn)
	_main._on_network_command("vfx_cue", {"k": "pip", "id": 7, "s": 99, "t": 1, "at": A, "n": 1}, 3)
	assert_int(_main.result_pips.get_child_count()).override_failure_message("another peer's id 7 is its own cue").is_equal(1)
	await E2EBoot.settle(get_tree())


func test_a_malformed_cue_draws_nothing(timeout := 120000) -> void:
	_main._on_network_command("vfx_cue", {"k": "pip", "id": 1, "s": 1, "t": 0, "at": "here", "n": 1}, 2)
	_main._on_network_command("vfx_cue", {"k": "volley", "id": 2, "s": 1, "f": 9, "pairs": [["x", B], [A]]}, 2)
	_main._on_network_command("vfx_cue", {"k": "seal_end", "id": 3, "s": 1, "sid": 404, "o": 0}, 2)
	assert_int(_main.result_pips.get_child_count() + _main.volley_cue.get_child_count()
		+ _main.spell_seal.get_child_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_peer_seal_forms_and_ends(timeout := 120000) -> void:
	_main._on_network_command("vfx_cue", {"k": "seal", "id": 5, "s": 4, "at": A, "r": 0.3, "kind": "buff"}, 2)
	assert_int(_main.spell_seal.get_child_count()).is_equal(1)
	_main._on_network_command("vfx_cue", {"k": "seal_dim", "id": 6, "s": 4, "sid": 5}, 2)
	_main._on_network_command("vfx_cue", {"k": "seal_end", "id": 7, "s": 4, "sid": 5, "o": 1}, 2)
	await get_tree().create_timer(1.0).timeout
	assert_int(_main.spell_seal.get_child_count()).is_equal(0)


func test_the_resolving_peer_sends_each_cue_once(timeout := 120000) -> void:
	var real: Node = _main.network_manager
	var stub := StubNet.new()
	_main.add_child(stub)   # a live session's network node sits in the tree (out of it, nothing is sent)
	_main.network_manager = stub
	var mi := ModelInstance.new()
	mi.node = Node3D.new()
	_main.add_child(mi.node)
	_main._vfx_pip(ResultPips.Kind.KILL, mi, 1)
	_main._vfx_pip(ResultPips.Kind.WOUND, mi, 0)   # nothing landed: no cue, no frame
	_main.network_manager = real
	assert_int(stub.sent.size()).is_equal(1)
	assert_str(str(stub.sent[0][0])).is_equal("vfx_cue")
	var cue: Dictionary = stub.sent[0][1]
	assert_object(cue.get("at")).is_equal(ResultPips.eye_of(mi))
	assert_int(int(stub.sent[0][2])).is_equal(0)
	assert_int(_main.result_pips.get_child_count()).is_equal(1)
	stub.free()
	mi.node.free()

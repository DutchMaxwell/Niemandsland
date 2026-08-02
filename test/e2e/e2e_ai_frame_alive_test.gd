extends GdUnitTestSuite
## Community #163: an AI turn used to run as ONE synchronous burst — a run of HOLD/idle
## units awaited nothing, the OS message pump starved and Windows flagged the window
## "not responding". _solo_activate_one_ai now yields exactly one frame per unit when
## interactive, and ZERO frames in batch (the headless A/B harnesses must stay
## byte-identical). Both directions are asserted here over the real main.tscn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_interactive_activation_ticks_at_least_one_frame() -> void:
	# No armies imported: the activation returns null immediately — which is exactly the
	# HOLD/idle-shaped case that used to tick ZERO frames. The message-pump guarantee must
	# hold even for it.
	_main._solo_batch = false
	var before: int = Engine.get_process_frames()
	await _main._solo_activate_one_ai()
	assert_int(Engine.get_process_frames() - before).is_greater_equal(1)
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


func test_batch_activation_stays_frame_free() -> void:
	# The headless A/B harnesses run _solo_batch=true and must stay byte-identical — the
	# yield is guarded out, so a batch activation still ticks no frame at all.
	_main._solo_batch = true
	var before: int = Engine.get_process_frames()
	await _main._solo_activate_one_ai()
	assert_int(Engine.get_process_frames() - before).is_equal(0)   # measured BEFORE settle() pumps any
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads

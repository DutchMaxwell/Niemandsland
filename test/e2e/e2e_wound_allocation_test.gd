extends GdUnitTestSuite
## #172 — full wound allocation (grilled): the OWNER clicks wounds onto their own models
## (LMB = 1 wound, RMB = auto-allocate the rest), the prompt appears ONLY when the choice
## matters (Tough model or mixed loadouts), never for the AI / batch / overkill wipes.
## Drives the REAL main.tscn prompt with synthetic picks (the raycast layer is already
## exercised by the Takedown flow, which shares the pick machinery).

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
	_main.solo_ai_slots = {2: true}


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Three models: two plain with DIFFERENT weapons + one Tough(3) — the choice matters.
func _mixed_unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name,
		[Vector3(0, 0, 0), Vector3(0.05, 0, 0), Vector3(0.1, 0, 0)])
	for i in range(u.models.size()):
		(u.models[i] as ModelInstance).model_index = i
	(u.models[0] as ModelInstance).properties = {"weapons": [{"name": "Rifle"}]}
	(u.models[1] as ModelInstance).properties = {"weapons": [{"name": "Melta Rifle"}]}
	var tough := u.models[2] as ModelInstance
	tough.properties = {"weapons": [{"name": "Rifle"}]}
	tough.wounds_max = 3
	tough.wounds_current = 3
	return u


func test_choice_matters_exactly_when_it_can_matter() -> void:
	_main._solo_batch = false
	var mixed := _mixed_unit(1, "Mixed")
	assert_bool(_main._solo_wound_choice_matters(mixed, 2)).is_true()
	# Overkill wipe (pool = 1+1+3): nothing to choose.
	assert_bool(_main._solo_wound_choice_matters(mixed, 5)).is_false()
	# The AI's own unit never prompts (its casualty_order already protects value).
	var ai := _mixed_unit(2, "AiMixed")
	assert_bool(_main._solo_wound_choice_matters(ai, 2)).is_false()
	# Batch/harness never prompts (headless would deadlock on a click).
	_main._solo_batch = true
	assert_bool(_main._solo_wound_choice_matters(mixed, 2)).is_false()
	_main._solo_batch = false
	# Uniform non-Tough unit: allocation cannot change anything — stays automatic.
	var uniform := E2EBoot.make_unit(_main, 1, "Uniform", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	for i in range(uniform.models.size()):
		(uniform.models[i] as ModelInstance).model_index = i
	assert_bool(_main._solo_wound_choice_matters(uniform, 1)).is_false()


func test_clicked_model_takes_the_wound_and_rmb_hands_back_the_rest() -> void:
	# Godot 4.6 gotcha: an async function must be awaited DIRECTLY (capturing the
	# coroutine breaks into the debugger under -d and hangs headless). The picks are
	# therefore scheduled on timers BEFORE the await and fire while the prompt runs.
	_main._solo_batch = false
	var u := _mixed_unit(1, "Alloc")
	# t1: the owner clicks the TOUGH model — the wound must land THERE, not on the
	# casualty_order edge pick the auto path would have taken.
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": u, "index": 2}))
	# t2: right-click — the empty recommended pick means "auto-allocate the rest".
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({}))
	var left: int = await _main._solo_prompt_wound_allocation(u, 2, 1)
	# The clicked Tough model took exactly ONE wound and survives.
	assert_int((u.models[2] as ModelInstance).wounds_current).is_equal(2)
	assert_bool((u.models[2] as ModelInstance).is_alive).is_true()
	# One wound handed back to the auto path (RMB), none applied by it here.
	assert_int(left).is_equal(1)
	# The plain models were NOT touched by the click phase.
	assert_bool((u.models[0] as ModelInstance).is_alive).is_true()
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()

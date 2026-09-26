extends GdUnitTestSuite
## E2E — D17 / Q8: who picks the model a Deadly(X) wound lands on.
## The maintainer's ruling: "Die Automatik bei Restwunden, wenn dann weitere Modelle frisch angeschlagen werden, dann
## wählt der Verteidiger" — a wounded Tough model is finished off automatically (GF v3.5.1 p.15), but when a FRESH
## model is about to be hit the DEFENDER picks: a human defender gets the SAME click prompt as for normal wounds
## (#172), the AI defender and batch runs take the defender-optimal casualty order.
## Drives the REAL main.tscn prompt with synthetic picks (timers scheduled BEFORE the await — the same idiom as
## e2e_wound_allocation_test.gd; an async call must be awaited directly under -d).
## Controls are declared first: gdUnit drops tests declared after a failing one.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _prompts_seen := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = false
	_prompts_seen = 0


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Three models: two plain with DIFFERENT weapons + one Tough(3) — the choice matters, so a human defender is asked.
## casualty_order (the automatic order) takes index 0 first, then 1, and the Tough model last.
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
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## At `delay` seconds: if a wound prompt is open, count it and hand it `pick` ({} = right-click = "auto-allocate").
func _schedule_pick(delay: float, pick: Dictionary) -> void:
	var main := _main   # a fallback timer may outlive its test: it must only ever touch ITS scene
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(main) and not main._solo_model_pick.is_empty():
			_prompts_seen += 1
			(main._solo_model_pick["outcome"] as Array).append(pick))


func test_a_wounded_tough_model_takes_the_deadly_wound_without_asking() -> void:
	var u := _mixed_unit(1, "Wounded")
	(u.models[2] as ModelInstance).wounds_current = 1
	# A right-click at every plausible moment, so a prompt that wrongly opens cannot hang the test.
	_schedule_pick(0.3, {})
	_schedule_pick(0.9, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 2, 0, 1)
	assert_int(dealt).is_equal(1)
	assert_bool((u.models[2] as ModelInstance).is_alive) \
		.override_failure_message("the wounded Tough model must be finished off first (p.15)") \
		.is_false()
	assert_bool((u.models[0] as ModelInstance).is_alive).is_true()
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()
	assert_int(_prompts_seen) \
		.override_failure_message("a wound forced onto the wounded Tough model has no choice in it — no prompt") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_right_click_hands_the_fresh_hit_to_the_automatic_order() -> void:
	var u := _mixed_unit(1, "Auto")
	_schedule_pick(0.3, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 2, 0, 1)
	assert_int(dealt).is_equal(1)
	# casualty_order's first body — and the Tough model, the top rung, is untouched.
	assert_bool((u.models[0] as ModelInstance).is_alive).is_false()
	assert_int((u.models[2] as ModelInstance).wounds_current).is_equal(3)
	await E2EBoot.settle(get_tree())


func test_the_ai_defender_is_never_asked() -> void:
	var u := _mixed_unit(2, "AiSide")
	_schedule_pick(0.3, {"unit": u, "index": 1})   # would be honoured if a prompt (wrongly) opened
	_schedule_pick(0.9, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 2, 0, 1)
	assert_int(dealt).is_equal(1)
	assert_int(_prompts_seen).is_equal(0)
	assert_bool((u.models[0] as ModelInstance).is_alive).is_false()   # the automatic order, not the "click"
	assert_bool((u.models[1] as ModelInstance).is_alive).is_true()
	await E2EBoot.settle(get_tree())


func test_a_fresh_model_hit_by_deadly_is_picked_by_the_human_defender() -> void:
	var u := _mixed_unit(1, "Picked")
	_schedule_pick(0.3, {"unit": u, "index": 1})   # the human clicks the Melta bearer
	_schedule_pick(0.9, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 2, 0, 1)
	assert_int(dealt).is_equal(1)   # the model had 1 wound: Deadly(2) is capped, no carry-over
	assert_bool((u.models[1] as ModelInstance).is_alive) \
		.override_failure_message("D17 — the defender's click was not offered / not honoured for the Deadly wound") \
		.is_false()
	assert_bool((u.models[0] as ModelInstance).is_alive).is_true()
	assert_int((u.models[2] as ModelInstance).wounds_current).is_equal(3)
	await E2EBoot.settle(get_tree())


func test_right_click_means_auto_for_the_rest_of_the_volley() -> void:
	# The prompt's right-click is "auto-allocate the rest": after it, the volley's remaining fresh Deadly wounds
	# must NOT re-open the prompt one by one (six unsaved wounds would be six prompts).
	var u := _mixed_unit(1, "RestAuto")
	_schedule_pick(0.3, {})
	_schedule_pick(0.9, {})
	_schedule_pick(1.5, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 1, 0, 2)
	assert_int(dealt).is_equal(2)
	assert_int(_prompts_seen) \
		.override_failure_message("D17 — the second fresh Deadly wound re-opened the prompt after a right-click") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_the_forced_wound_finishes_first_then_the_defender_picks_the_next() -> void:
	# Two unsaved Deadly(2) wounds on a unit whose Tough model is down to 2: wound 1 is forced onto it (dies, the
	# excess is lost), wound 2 hits a FRESH model — the human picks it. One prompt only, for the second wound.
	var u := _mixed_unit(1, "Sequence")
	(u.models[2] as ModelInstance).wounds_current = 2
	_schedule_pick(0.3, {"unit": u, "index": 1})
	_schedule_pick(0.9, {})
	_schedule_pick(1.5, {})
	var dealt: int = await _main._solo_land_deadly_wounds(u, "Axe", 2, 0, 2)
	assert_int(dealt).is_equal(3)   # 2 (Tough, capped at what it had) + 1 (the clicked plain body)
	assert_bool((u.models[2] as ModelInstance).is_alive).is_false()
	assert_bool((u.models[1] as ModelInstance).is_alive) \
		.override_failure_message("D17 — the second (fresh) Deadly wound ignored the defender's pick") \
		.is_false()
	assert_bool((u.models[0] as ModelInstance).is_alive).is_true()
	await E2EBoot.settle(get_tree())

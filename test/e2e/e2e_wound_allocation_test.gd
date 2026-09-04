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


# === #590 — a joined hero is part of the unit: wounds go to the host's OWN models first =========
## GF v3.5.1 p.14: "a joined hero counts as part of the unit" — its wounds come from the SAME pool,
## and the host's own models are the ones that take them, the hero only once every one of them is a
## casualty. The automatic path (_solo_apply_wounds → _solo_wound_models → hero spill) already got
## this right; these suites lock the INTERACTIVE click prompt to the same order.

## A joined hero, Tough(`tough`) so a partially-absorbed wound is observable across more than one click.
func _joined_hero(host: GameUnit, hero_name: String, tough: int) -> GameUnit:
	var h := E2EBoot.make_unit(_main, int(host.unit_properties.get("player_id", 1)), hero_name,
		[Vector3(0.3, 0, 0.3)])
	(h.models[0] as ModelInstance).model_index = 0
	h.unit_properties["special_rules"] = ["Hero"]
	var m := h.models[0] as ModelInstance
	m.wounds_max = tough
	m.wounds_current = tough
	h.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [h]
	return h


## #590 RED 1/3: while the host's own model still stands, a click on the attached hero must be
## refused — the same feedback an invalid pick gets, and no wound spent.
func test_hero_click_refused_while_host_alive() -> void:
	_main._solo_batch = false
	var host := E2EBoot.make_unit(_main, 1, "Host590a", [Vector3.ZERO])
	(host.models[0] as ModelInstance).model_index = 0
	var hero := _joined_hero(host, "Hero590a", 1)
	# t1: click the hero while the host still stands — must be refused, not spent.
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero, "index": 0}))
	# t2: right-click hands the (still whole) wound to the auto path so the prompt returns.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({}))
	var left: int = await _main._solo_prompt_wound_allocation(host, 1, 1)
	assert_int(left) \
		.override_failure_message("the click on the hero must have been refused — nothing legal was spent") \
		.is_equal(1)
	assert_bool((hero.models[0] as ModelInstance).is_alive).is_true()
	assert_int((hero.models[0] as ModelInstance).wounds_current).is_equal(1)
	assert_bool((host.models[0] as ModelInstance).is_alive).is_true()


## #590 boundary: eligibility is re-checked on EVERY click, never cached across the prompt — the
## instant the host's last model falls, the SAME hero click that was just refused must be accepted.
func test_hero_eligible_the_instant_the_host_is_destroyed() -> void:
	_main._solo_batch = false
	var host := E2EBoot.make_unit(_main, 1, "Host590b", [Vector3.ZERO])
	(host.models[0] as ModelInstance).model_index = 0
	var hero := _joined_hero(host, "Hero590b", 1)
	# t1: the host's own model takes the first wound and dies.
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": host, "index": 0}))
	# t2: the host is gone — the SAME click on the hero must now be accepted.
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero, "index": 0}))
	var left: int = await _main._solo_prompt_wound_allocation(host, 2, 1)
	assert_int(left).is_equal(0)
	assert_bool((host.models[0] as ModelInstance).is_alive).is_false()
	assert_bool((hero.models[0] as ModelInstance).is_alive).is_false()


## #590 RED 2/3: an already-wounded Tough hero stays protected too — surviving a partial wound does
## not waive the host-before-hero order. Two host models must BOTH fall before the hero (Tough(3),
## already carrying one earlier wound) is eligible for its second.
func test_already_wounded_tough_hero_stays_protected_until_host_dies() -> void:
	_main._solo_batch = false
	var host := E2EBoot.make_unit(_main, 1, "Host590c", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	for i in range(host.models.size()):
		(host.models[i] as ModelInstance).model_index = i
	var hero := _joined_hero(host, "Hero590c", 3)
	(hero.models[0] as ModelInstance).wounds_current = 2   # one wound already landed earlier
	# t1: refused — TWO host models still stand.
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero, "index": 0}))
	# t2: the FIRST host model takes a wound and dies — one still stands.
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": host, "index": 0}))
	# t3: refused again — the SECOND host model is still alive.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero, "index": 0}))
	# t4: the second host model falls — the host is now fully destroyed.
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": host, "index": 1}))
	# t5: only NOW is the hero's already-wounded model eligible.
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero, "index": 0}))
	var left: int = await _main._solo_prompt_wound_allocation(host, 3, 1)
	assert_int(left) \
		.override_failure_message("all three wounds were legal picks (host, host, hero) — none should be left over") \
		.is_equal(0)
	assert_bool((host.models[0] as ModelInstance).is_alive).is_false()
	assert_bool((host.models[1] as ModelInstance).is_alive).is_false()
	assert_bool((hero.models[0] as ModelInstance).is_alive) \
		.override_failure_message("the hero absorbed 2 wounds total (1 earlier + 1 here) against Tough(3) — it must still stand") \
		.is_true()
	assert_int((hero.models[0] as ModelInstance).wounds_current).is_equal(1)


## #590 RED 3/3: given the SAME starting unit and the SAME wound count, the automatic path
## (_solo_apply_wounds on an AI unit, no prompt) and a legally ordered interactive click sequence
## (host models first, hero last) must land on the identical casualty state — the interactive gate
## may never legalise an order the automatic path forbids.
func test_auto_and_interactive_paths_agree_on_the_final_casualty_state() -> void:
	_main._solo_batch = true
	var host_auto := E2EBoot.make_unit(_main, 2, "HostAuto590", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	for i in range(host_auto.models.size()):
		(host_auto.models[i] as ModelInstance).model_index = i
	var hero_auto := _joined_hero(host_auto, "HeroAuto590", 3)
	await _main._solo_apply_wounds(host_auto, 3)   # AI-owned unit → the automatic path only, no prompt

	_main._solo_batch = false
	var host_click := E2EBoot.make_unit(_main, 1, "HostClick590", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	for i in range(host_click.models.size()):
		(host_click.models[i] as ModelInstance).model_index = i
	var hero_click := _joined_hero(host_click, "HeroClick590", 3)
	# Legal order: both host models, then the hero — the same choices a rule-following player makes.
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": host_click, "index": 0}))
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": host_click, "index": 1}))
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": hero_click, "index": 0}))
	var left: int = await _main._solo_prompt_wound_allocation(host_click, 3, 1)
	assert_int(left).is_equal(0)

	assert_bool((host_click.models[0] as ModelInstance).is_alive) \
		.is_equal((host_auto.models[0] as ModelInstance).is_alive)
	assert_bool((host_click.models[1] as ModelInstance).is_alive) \
		.is_equal((host_auto.models[1] as ModelInstance).is_alive)
	assert_bool((hero_click.models[0] as ModelInstance).is_alive) \
		.is_equal((hero_auto.models[0] as ModelInstance).is_alive)
	assert_int((hero_click.models[0] as ModelInstance).wounds_current) \
		.is_equal((hero_auto.models[0] as ModelInstance).wounds_current)

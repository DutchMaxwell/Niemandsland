extends GdUnitTestSuite
## E2E — NML-924: the OWNER spends Reanimation successes by CLICKING (#172's principle applied to the
## rule). v1 allocated every success automatically — living wounded first, then the cheapest casualty —
## which is a fine default and a poor decision-maker: OPR lets the owner choose, and the choice
## (a Tough elite back on the table vs. two wounds topped up) is often the whole activation.
##
## The prompt runs BETWEEN the dice and the restores. A fallen model has no body to click — a regiment
## casualty is hidden with its collider off, a loose one is parked on the army tray — so each casualty
## that CAN come back wears a candidate ring at its return spot, and the ring is the click target.
## Right-click hands whatever is left to the v1 automatic allocation, which the AI, batch mode and the
## self-play harness keep using unchanged.
##
## The suite drives the REAL main.tscn resolver with FIXED successes (the dice are the one part a test
## cannot pin) and synthetic picks, the way the #172 wound-allocation suite does: the physics raycast
## layer is shared with the Takedown flow, and the ring geometry gets its own direct case below.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = false   # the click prompt is an INTERACTIVE-only path


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## YOUR reanimating unit (player 1 — slot 2 is the AI): a wounded Tough(3), a casualty, and an
## untouched trooper. Three different things a success could buy, which is exactly the choice v1 took
## away from you.
func _legion(pid: int = 1, unit_name: String = "Legion") -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name,
		[Vector3.ZERO, Vector3(0.6 * INCH, 0, 0), Vector3(1.2 * INCH, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in u.models.size():
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.wounds_max = 1
		m.wounds_current = 1
	var tough := u.models[0] as ModelInstance
	tough.wounds_max = 3
	tough.wounds_current = 1      # two wounds missing
	var fallen := u.models[1] as ModelInstance
	fallen.wounds_current = 0
	fallen.is_alive = false
	return u


## Schedule ONE synthetic pick into the running prompt. Godot 4.6 gotcha (the #172 suite's finding):
## an async function must be awaited DIRECTLY, so the picks ride timers started BEFORE the await.
## The scene guard is load-bearing for the RED run: with the prompt switched off the test finishes
## before its own timers do, and an unguarded lambda would then read _main after the teardown nulled
## it — a debugger break instead of the clean failure the red proof is supposed to show.
func _pick_at(seconds: float, pick: Dictionary) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if _main == null or not is_instance_valid(_main):
			return
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append(pick))


# ===== (1) the gate: who is asked, and only when the answer can matter =====

func test_the_prompt_opens_only_where_a_choice_exists(timeout := 120000) -> void:
	var mine := _legion()
	assert_bool(_main._solo_reanimation_choice_matters(mine, 2)) \
		.override_failure_message("two successes over three wounds of capacity IS a choice") \
		.is_true()
	# Enough successes to fill every candidate: the allocation has no decision left in it.
	assert_bool(_main._solo_reanimation_choice_matters(mine, 3)) \
		.override_failure_message("a roll that fills everything cannot be allocated wrongly") \
		.is_false()
	assert_bool(_main._solo_reanimation_choice_matters(mine, 0)).is_false()
	# NACHTMAHR keeps its deterministic plan — its own units are never handed to a human click.
	var theirs := _legion(2, "AiLegion")
	assert_bool(_main._solo_reanimation_choice_matters(theirs, 2)) \
		.override_failure_message("the AI's own restore must stay automatic") \
		.is_false()
	# Batch/harness: headless would deadlock on a click that never comes (the self-play runs).
	_main._solo_batch = true
	assert_bool(_main._solo_reanimation_choice_matters(mine, 2)) \
		.override_failure_message("batch mode must never open an interactive prompt") \
		.is_false()
	_main._solo_batch = false
	# One candidate = nothing to weigh up.
	var single := E2EBoot.make_unit(_main, 1, "Pair", [Vector3.ZERO, Vector3(0.6 * INCH, 0, 0)])
	_main.opr_army_manager.game_units[single.unit_id] = single
	single.unit_properties["special_rules"] = ["Reanimation"]
	for i in single.models.size():
		(single.models[i] as ModelInstance).model_index = i
	var only := single.models[1] as ModelInstance
	only.wounds_max = 3
	only.wounds_current = 0
	only.is_alive = false
	assert_bool(_main._solo_reanimation_choice_matters(single, 1)) \
		.override_failure_message("with a single candidate every allocation is the same allocation") \
		.is_false()


# ===== (2) the ROT case: the click overrides the automatic priority =====

func test_a_clicked_casualty_comes_back_before_the_living_are_topped_up(timeout := 120000) -> void:
	# v1's plan would spend BOTH successes on the living Tough(3)'s gap and leave the casualty down.
	# The owner wants the model back: one click, then right-click for the rest.
	var u := _legion()
	var tough := u.models[0] as ModelInstance
	var fallen := u.models[1] as ModelInstance
	_pick_at(0.25, {"unit": u, "index": 1})   # LMB on the casualty's candidate ring
	_pick_at(0.60, {})                        # RMB — allocate the rest automatically
	await _main._solo_resolve_reanimation(u, 3, 5, 2)
	assert_bool(fallen.is_alive) \
		.override_failure_message("the clicked casualty must come back — the automatic plan would have left it down") \
		.is_true()
	assert_int(fallen.wounds_current) \
		.override_failure_message("wound currency: a returned model stands up with the ONE wound its success bought") \
		.is_equal(1)
	assert_int(tough.wounds_current) \
		.override_failure_message("the ONE success handed back must top the living model up by exactly one") \
		.is_equal(2)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: every click needs its line (log: %s)" % text.strip_edges()) \
		.contains("Reanimation: you restore a fallen model on Legion — 1 success left")
	assert_str(text) \
		.override_failure_message("the hand-over to the automatic allocation must be visible too (log: %s)" % text.strip_edges()) \
		.contains("Reanimation: the remaining 1 success is allocated automatically")
	assert_str(text).contains("1 model(s), 1 wound(s) restored")
	await E2EBoot.settle(get_tree())


# ===== (3) the counter runs down, and a fully clicked roll never reaches the automatic path =====

func test_every_success_can_be_clicked_and_the_counter_runs_out(timeout := 120000) -> void:
	var u := _legion()
	var tough := u.models[0] as ModelInstance
	var fallen := u.models[1] as ModelInstance
	_pick_at(0.25, {"unit": u, "index": 1})   # the casualty
	_pick_at(0.60, {"unit": u, "index": 0})   # one wound onto the living Tough(3)
	await _main._solo_resolve_reanimation(u, 3, 5, 2)
	assert_bool(fallen.is_alive).is_true()
	assert_int(tough.wounds_current).is_equal(2)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the heal click needs its own line and the counter must reach zero (log: %s)" % text.strip_edges()) \
		.contains("Reanimation: you heal one wound on Legion — 0 successes left")
	assert_str(text) \
		.override_failure_message("nothing was left over — the automatic allocation must not announce itself") \
		.not_contains("allocated automatically")
	await E2EBoot.settle(get_tree())


# ===== (4) a click that buys nothing SAYS so — a silent no-op reads like a broken click (#224) =====

func test_a_click_on_a_healthy_model_is_refused_out_loud(timeout := 120000) -> void:
	var u := _legion()
	_pick_at(0.25, {"unit": u, "index": 2})   # the untouched trooper
	_pick_at(0.60, {})
	await _main._solo_resolve_reanimation(u, 3, 5, 2)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the refusal must name its reason and keep the counter (log: %s)" % text.strip_edges()) \
		.contains("Reanimation: that model takes no restore — it is at full health (2 left)")
	assert_str(text) \
		.override_failure_message("a refused click must not silently spend a success (log: %s)" % text.strip_edges()) \
		.contains("Reanimation: the remaining 2 successes are allocated automatically")
	await E2EBoot.settle(get_tree())


# ===== (5) the ring IS the click target — a fallen model has no body to hit =====

func test_a_candidate_ring_resolves_the_fallen_model_under_the_cursor(timeout := 120000) -> void:
	var u := _legion()
	var fallen := u.models[1] as ModelInstance
	var spots: Array = _main._solo_reanimation_pick_spots(u, _main._solo_reanimation_anchors(u))
	assert_int(spots.size()) \
		.override_failure_message("the only casualty that can return must offer exactly one ring") \
		.is_equal(1)
	var spot := spots[0] as Dictionary
	assert_object(spot["unit"]).is_equal(u)
	assert_int(int(spot["index"])).is_equal(fallen.model_index)
	var camera := _main.get_viewport().get_camera_3d()
	assert_object(camera) \
		.override_failure_message("fixture check: the ring pick needs the scene's own camera") \
		.is_not_null()
	_main._solo_model_pick = {"unit": u, "chain": [u], "recommended": {}, "outcome": [], "spots": spots}
	var on_ring: Dictionary = _main._solo_ring_pick_at(camera.unproject_position(spot["p"] as Vector3))
	assert_object(on_ring.get("unit")) \
		.override_failure_message("a click on the ring must resolve to the model it stands for") \
		.is_equal(u)
	assert_int(int(on_ring.get("index", -1))).is_equal(fallen.model_index)
	# Bare table a metre away: no ring, no pick — the click must not grab the nearest casualty.
	var far: Dictionary = _main._solo_ring_pick_at(
		camera.unproject_position((spot["p"] as Vector3) + Vector3(1.0, 0, 1.0)))
	assert_bool(far.is_empty()) \
		.override_failure_message("a click on empty table picked a model anyway") \
		.is_true()
	_main._solo_model_pick = {}


# ===== (6) batch/headless stays automatic — the self-play harness depends on it =====

func test_batch_mode_allocates_without_ever_asking(timeout := 120000) -> void:
	_main._solo_batch = true
	var u := _legion()
	var tough := u.models[0] as ModelInstance
	await _main._solo_resolve_reanimation(u, 3, 5, 2)
	assert_int(tough.wounds_current) \
		.override_failure_message("v1's automatic priority (living wounded first) must survive untouched") \
		.is_equal(3)
	assert_bool((u.models[1] as ModelInstance).is_alive) \
		.override_failure_message("both successes went into the living gap — the casualty stays down") \
		.is_false()
	assert_str(_log_text()) \
		.override_failure_message("a headless run must never open the click prompt:\n%s" % _log_text()) \
		.not_contains("CLICK a wounded model")

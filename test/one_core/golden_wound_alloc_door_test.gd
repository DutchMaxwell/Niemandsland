extends GdUnitTestSuite
## P4.D-26: the #172 prompt scenarios of the golden witness (P4.D-11, the committed `golden_mixed_kit.json`, recorded on the
## TABLE path), replayed through the CORE door (`CoreActivation.run_ai`, the AI body's call) with the wound_alloc switch ON.
## Both variants must end exactly as the table's recording: `mixed_auto` (the owner right-clicks at once: the core's own order)
## and `mixed_click` (the owner clicks the middle models first: the prompt previews them, the slot list is the answer, the
## core lands them). The comparison reads what the player sees - every model's alive / wounds, Shaken, and the tray rng after.
## With the switch OFF the clicks never reach the core, so `mixed_click` differs from the recording: the comparison can fail.
## Real: the main scene, NmlCore, the table's save card and prompt. Constructed: the golden harness's units and dice pump.
## The tough shape is not replayed: the shoot slice refuses Tough, so the table resolves it either way.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _ties: Array = []   # the cases that differ from the recording only by an exact geometric tie (see _mirror_tie)


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
	CoreActivation._env = 1   # the core door ON, whatever the environment says


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._choice_on = {}
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## What differs between the core run and the table's recording, per scenario: ["<scenario> seed <n>: <what>", ...].
func _differences(only: String = "") -> Array:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MIXED_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("the golden fixture is missing").is_false()
	var out: Array = []
	for sc in Harness.mixed_scenarios():
		if str(sc["shape"]) != "mixed" or (not only.is_empty() and str(sc["name"]) != only):
			continue
		for seed in sc["seeds"]:
			var rec: Dictionary = await Harness._run_case(_main, (sc as Dictionary).merged({"door": "core"}, true), int(seed))
			var gold := {}
			for c in want["cases"]:
				if str(c["scenario"]) == str(sc["name"]) and int(c["seed"]) == int(seed):
					gold = c
			var tag := "%s seed %d" % [sc["name"], int(seed)]
			if rec.has("error"):
				out.append("%s: %s" % [tag, rec["error"]])
			elif str(rec.get("core", "")) != "1":
				out.append("%s: the core did not take the volley" % tag)
			elif JSON.parse_string(JSON.stringify(rec["final"])) != gold["final"]:   # the fixture's numbers came through JSON
				if _mirror_tie(JSON.parse_string(JSON.stringify(rec["final"])), gold["final"]):
					_ties.append(tag)
				else:
					out.append("%s: final %s, golden %s" % [tag, rec["final"], gold["final"]])
			elif str(rec["rng"]) != str(gold["rng"]):
				out.append("%s: tray rng %s, golden %s" % [tag, rec["rng"], gold["rng"]])
	return out


## The one accepted difference between the two casualty orders: after the owner's clicks took the two MIDDLE models of a
## straight line, its two end models are exactly equidistant from the centroid and carry the same value, so which of them the
## automatic rest takes is a coin the table's unstable sort and the core's stable sort (and float noise) toss differently (the
## known non-literal golden difference). True only when the defender's dead sets differ by that one mirror pair
## (slot i here, slot n-1-i there) and nothing else - an ignored answer or any other landing is not a tie.
func _mirror_tie(ours: Array, gold: Array) -> bool:
	if ours[0] != gold[0]:
		return false
	var a: Dictionary = ours[1]
	var b: Dictionary = gold[1]
	for k in ["unit", "alive", "wounds", "shaken"]:
		if a[k] != b[k]:
			return false
	var dead := func(row: Dictionary) -> Array:
		return (row["slots"] as Array).filter(func(s: Array) -> bool: return not s[1]).map(func(s: Array) -> int: return int(s[0]))
	var da: Array = dead.call(a)
	var db: Array = dead.call(b)
	var only_a: Array = da.filter(func(i: int) -> bool: return not db.has(i))
	var only_b: Array = db.filter(func(i: int) -> bool: return not da.has(i))
	return only_a.size() == 1 and only_b.size() == 1 and int(only_a[0]) + int(only_b[0]) == (a["slots"] as Array).size() - 1


## Switch ON: both variants through the core door equal the table's golden recording, seed for seed.
@warning_ignore('unused_parameter')
func test_both_prompt_variants_through_the_core_door_equal_the_golden(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	CoreActivation._choice_on = {"wound_alloc": true}
	var diffs := await _differences()
	assert_array(diffs).override_failure_message("core door vs golden:\n" + "\n".join(diffs.slice(0, 8))).is_empty()
	# Pinned: exactly these two seeds hit the exact tie. If the two orders ever agree on them, delete the exception.
	assert_array(_ties).override_failure_message("the tie cases changed: %s" % str(_ties)).is_equal(["mixed_click seed 49", "mixed_click seed 512"])


## Switch OFF (the default): the core lands its automatic order and nobody is asked, so the harness's prompt never opens in
## ANY variant - the owner's clicks cannot reach the core. This is what the switch buys, and proves the comparison can fail.
@warning_ignore('unused_parameter')
func test_with_the_switch_off_the_owner_is_never_asked(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	CoreActivation._choice_on = {}
	var diffs := await _differences("mixed_click")
	assert_int(diffs.size()).override_failure_message("the clicks reached the core with the switch off: %s" % str(diffs)).is_equal(8)
	for d in diffs:
		assert_str(d).override_failure_message(d).contains("prompt never opened")

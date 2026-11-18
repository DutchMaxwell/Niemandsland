extends GdUnitTestSuite
## P4.0-10 — the golden witness must notice when the OLD table path changes.
##
## CI half of test/one_core/golden_witness.gd: boots the real main.tscn with the one-core kill switch OFF and compares
## the shooting-volley, melee and morale grids against their committed fixtures. Each family also plants one changed
## line in a copy of its fixture and asserts the comparator reports it — the fixture set can fail, it is not a
## snapshot that would accept anything.
##
## Regenerate the fixture ONLY after an intended, owned table change: --capture (see the CLI header), then review
## the diff line by line. A red here means the table's volley result moved without its replacement being recorded.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _saved_flag: String


func before_test() -> void:
	BattleSim._core_env = 0   # P4.D-66: pinned to the GDScript AI; with the core up the shipped brain and the Rust search decide
	# The kill switch is process-wide (and CoreActivation caches it once): remember the value so every later suite
	# runs under the setting it expects.
	_saved_flag = OS.get_environment("NML_ONE_CORE_ACTIVATION")
	OS.set_environment("NML_ONE_CORE_ACTIVATION", "0")
	CoreActivation._env = -1
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	assert_bool(Harness.configure(_main)).override_failure_message(
		"the kill switch is on: this suite must run the old table path").is_true()


func after_test() -> void:
	BattleSim._core_env = -1
	OS.set_environment("NML_ONE_CORE_ACTIVATION", _saved_flag)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_the_committed_fixture_matches_the_old_table_path() -> void:
	assert_bool(CoreActivation.enabled()).override_failure_message(
		"the kill switch is on: this suite must run the old table path").is_false()
	var want := Harness.load_fixture()
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with test/one_core/golden_witness.gd" % Harness.FIXTURE_PATH).is_false()
	var got: Dictionary = await Harness.capture(_main)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_fixture_change_is_reported() -> void:
	var want := Harness.load_fixture()
	assert_bool(want.is_empty()).override_failure_message("fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str(str(problems[0])).contains("planted")


func test_v2_keys_are_compared_and_a_v1_fixture_ignores_them() -> void:
	var got: Dictionary = await Harness.capture(_main)
	var want: Dictionary = got.duplicate(true)
	want["schema"] = Harness.SCHEMA
	assert_array(Harness.compare(want, got)).override_failure_message(
		"a fresh capture must match its own copy").is_empty()
	# One slot of one model flips alive: exactly one difference, and it names the slots.
	var slot: Array = want["cases"][0]["final"][1]["slots"][0]
	slot[1] = not bool(slot[1])
	var slot_problems := Harness.compare(want, got)
	assert_int(slot_problems.size()).override_failure_message(
		"a changed slot went unnoticed or was reported more than once: %s" % str(slot_problems)).is_equal(1)
	assert_str("\n".join(slot_problems)).contains("model slots")
	slot[1] = not bool(slot[1])
	# The tray rng state after the exchange is part of the record.
	want["cases"][0]["rng"] = "1"
	var rng_problems := Harness.compare(want, got)
	assert_int(rng_problems.size()).override_failure_message(
		"a changed rng state went unnoticed: %s" % str(rng_problems)).is_equal(1)
	assert_str("\n".join(rng_problems)).contains("rng")
	# A v1 fixture has neither key: the same capture still matches it, and a changed count is still reported.
	var old: Dictionary = got.duplicate(true)
	old["schema"] = Harness.SCHEMA_V1
	for c in old["cases"]:
		(c as Dictionary).erase("rng")
		for row in c["final"]:
			(row as Dictionary).erase("slots")
	assert_array(Harness.compare(old, got)).override_failure_message(
		"a v1 fixture must compare on the v1 keys only").is_empty()
	old["cases"][0]["final"][1]["alive"] = int(old["cases"][0]["final"][1]["alive"]) + 1
	assert_int(Harness.compare(old, got).size()).is_equal(1)


func test_an_unknown_runner_is_an_error_case_not_a_crash() -> void:
	var rec: Dictionary = await Harness._run_case(_main, {"name": "x", "runner": "nope"}, 0)
	assert_str(str(rec.get("error", ""))).contains("unknown runner")


func test_the_melee_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.MELEE_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family melee" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MELEE_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its melee golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_melee_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MELEE_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("melee fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MELEE_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed melee fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str(str(problems[0])).contains("planted")

func test_the_morale_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.MORALE_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family morale" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MORALE_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its morale golden witness (%s):
%s" % [
			Harness.describe_provenance(want, got), "
".join(problems)]).is_empty()


func test_a_planted_morale_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MORALE_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("morale fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MORALE_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed morale fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str(str(problems[0])).contains("planted")


func test_the_human_door_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.HUMAN_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family human_shoot" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.HUMAN_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its human-door golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_human_door_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.HUMAN_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("human-door fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.HUMAN_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed human-door fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")


func test_the_partial_range_guard_errors_when_every_model_fires() -> void:
	var far: Dictionary = (Harness.human_scenarios()[1] as Dictionary).duplicate(true)
	far["defender"]["x_in"] = 8.0   # planted fault: at 8" every model of the column is in range
	var rec: Dictionary = await Harness._run_case(_main, far, 0)
	assert_str(str(rec.get("error", ""))).contains("not partial")


func test_the_split_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.SPLIT_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family split" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.SPLIT_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its split-fire golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_split_fixture_line_and_extra_are_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.SPLIT_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("split fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.SPLIT_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed split fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")
	# the human split's shot_round stamp is part of the record
	var human_case: Dictionary = want["cases"][8]
	assert_str(str(human_case["scenario"])).is_equal("human_split")
	want["cases"][0]["lines"][0] = got["cases"][0]["lines"][0]
	human_case["extra"]["shot_round"] = "9"
	var extra_problems := Harness.compare(want, got)
	assert_int(extra_problems.size()).override_failure_message(
		"a changed shot_round stamp went unnoticed: %s" % str(extra_problems)).is_equal(1)
	assert_str("\n".join(extra_problems)).contains("extra")


func test_a_split_case_errors_when_only_one_target_is_fired_at() -> void:
	for sc in Harness.split_scenarios():
		var one: Dictionary = (sc as Dictionary).duplicate(true)
		one["def_b"]["x_in"] = 30.0   # planted fault: B is beyond both weapons' reach
		var rec: Dictionary = await Harness._run_case(_main, one, 0)
		assert_str(str(rec.get("error", ""))).override_failure_message(
			"%s: one target only must fail the case, got %s" % [str(one["name"]), str(rec.keys())]).contains("no split")


func test_the_dangerous_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.DANGEROUS_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family dangerous" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.DANGEROUS_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its Dangerous golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_dangerous_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.DANGEROUS_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("Dangerous fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.DANGEROUS_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed Dangerous fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")


func test_a_dangerous_case_errors_when_the_roll_never_happened() -> void:
	var sc: Dictionary = (Harness.dangerous_scenarios()[0] as Dictionary).duplicate(true)
	sc["dice"] = 0   # planted fault: no dice, so the table logs no Dangerous line at all
	var rec: Dictionary = await Harness._run_case(_main, sc, 0)
	assert_str(str(rec.get("error", ""))).contains("no Dangerous line")


func test_the_mixed_kit_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.MIXED_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s — capture it with --family mixed_kit" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MIXED_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its wound-prompt golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_mixed_kit_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MIXED_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("mixed-kit fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MIXED_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed mixed-kit fixture line went unnoticed — the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")


## The prompt really decided something: for every seed and shape the clicked run ends on other model slots than
## the auto run (the table's own pick takes the edge models, the clicks went to the middle). A bypassed prompt would
## make the two runs equal.
func test_a_clicked_run_ends_on_other_slots_than_the_auto_run() -> void:
	var got: Dictionary = await Harness.capture(_main, Harness.MIXED_FAMILY)
	var by := {}
	for c in got["cases"]:
		by["%s:%d" % [str(c["scenario"]), int(c["seed"])]] = c
		if (c as Dictionary).has("error"):
			fail("a prompt case errored: %s" % str(c))
			return
	for shape in ["mixed", "tough"]:
		for seed in Harness.PROMPT_SEEDS:
			var auto: Dictionary = by["%s_auto:%d" % [shape, seed]]
			var click: Dictionary = by["%s_click:%d" % [shape, seed]]
			assert_bool(JSON.stringify(auto["final"][1]["slots"]) != JSON.stringify(click["final"][1]["slots"])) \
				.override_failure_message("%s seed %d: the clicked run equals the auto run - the prompt did not decide" % [
					shape, seed]).is_true()


func test_a_mixed_kit_case_errors_when_no_prompt_opens() -> void:
	var sc: Dictionary = (Harness.mixed_scenarios()[1] as Dictionary).duplicate(true)
	sc["shape"] = "tough"   # planted fault: one shared loadout and Tough 1 - nothing to choose, no prompt
	var rec: Dictionary = await Harness._run_case(_main, sc, 0)
	assert_str(str(rec.get("error", ""))).contains("never opened")


func test_the_move_through_fixture_matches_the_old_table_path() -> void:
	var path := Harness.fixture_path(Harness.MOVE_THROUGH_FAMILY)
	var want := Harness.load_fixture(path)
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s - capture it with --family move_through" % path).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MOVE_THROUGH_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the old table path no longer matches its move-through golden witness (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_move_through_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MOVE_THROUGH_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("move-through fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MOVE_THROUGH_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed move-through fixture line went unnoticed - the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")


func test_the_melee_shapes_fixture_matches_the_old_table_path() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MELEE_SHAPES_FAMILY))
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s - capture it with --family melee_shapes" % Harness.MELEE_SHAPES_FIXTURE_PATH).is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MELEE_SHAPES_FAMILY)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message("melee-shapes witness differs (%s):\n%s" % [
		Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


func test_a_planted_melee_shapes_fixture_line_is_reported() -> void:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MELEE_SHAPES_FAMILY))
	assert_bool(want.is_empty()).override_failure_message("melee-shapes fixture missing").is_false()
	var got: Dictionary = await Harness.capture(_main, Harness.MELEE_SHAPES_FAMILY)
	want["cases"][0]["lines"][0] = "%s (planted)" % str(want["cases"][0]["lines"][0])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message(
		"a changed melee-shapes line went unnoticed - the witness cannot fail").is_equal(1)
	assert_str("\n".join(problems)).contains("planted")

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

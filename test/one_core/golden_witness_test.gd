extends GdUnitTestSuite
## P4.0-10 — the golden witness must notice when the OLD table path changes.
##
## CI half of test/one_core/golden_witness.gd: boots the real main.tscn with the one-core kill switch OFF and compares the
## shooting-volley grid against test/fixtures/one_core/golden_shoot_volley.json. The second test plants one changed
## line in a copy of the fixture and asserts the comparator reports it — the fixture set can fail, it is not a
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

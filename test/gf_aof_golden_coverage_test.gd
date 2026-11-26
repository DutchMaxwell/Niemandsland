extends GdUnitTestSuite
## Plan step 20(a): GF/AoF must not move when Firefight work lands. Every in-repo GF/AoF golden is replayed by a gdUnit
## suite on every PR - the one-core goldens through test/one_core (the golden_witness harness and its suites), the frozen
## shoot-parity tables through test/parity/shoot_parity_test.gd. This guard keeps that true: a golden nobody replays fails
## here, so a new fixture cannot sit in the repo looking like protection it does not give.

const ONE_CORE_GOLDENS := "res://test/fixtures/one_core/"
const ONE_CORE_SUITES := "res://test/one_core/"
const PARITY_TABLES := "res://test/parity/golden/shoot/"
const PARITY_SUITE := "res://test/parity/shoot_parity_test.gd"


static func _texts(dir: String) -> String:
	var all := ""
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			all += FileAccess.get_file_as_string(dir.path_join(f))
	return all


func test_every_one_core_golden_is_replayed() -> void:
	var suites := _texts(ONE_CORE_SUITES)
	var seen := 0
	for f in DirAccess.get_files_at(ONE_CORE_GOLDENS):
		if f.begins_with("golden_") and f.ends_with(".json"):
			seen += 1
			assert_bool(suites.contains(f)).override_failure_message("%s: no test/one_core suite replays it" % f).is_true()
	assert_int(seen).override_failure_message("the one-core goldens are gone").is_greater(0)


func test_every_shoot_parity_table_is_replayed() -> void:
	var suite := FileAccess.get_file_as_string(PARITY_SUITE)
	var seen := 0
	for f in DirAccess.get_files_at(PARITY_TABLES):
		if f.ends_with("_table.jsonl"):
			seen += 1
			var scenario := f.trim_suffix("_table.jsonl")
			assert_bool(suite.contains("_gate(\"%s\"" % scenario)) \
				.override_failure_message("%s: shoot_parity_test.gd has no _gate(\"%s\")" % [f, scenario]).is_true()
	assert_int(seen).override_failure_message("the shoot-parity tables are gone").is_greater(0)

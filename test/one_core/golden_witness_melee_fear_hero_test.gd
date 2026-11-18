extends GdUnitTestSuite
## P4.D-47b - the golden witness of Fear and a joined hero in melee, on the OLD table path.
##
## Companion of golden_witness_test.gd (same boot, same kill switch): it replays family `melee_fear_hero`
## (AI charge through `_run_ai_melee`, the player's charge through `_run_human_melee`, consolidation after both) and
## compares state + battle-log lines + model positions with test/fixtures/one_core/golden_melee_fear_hero.json.
## Each fault the witness must notice is planted in a copy of the fixture (a log line, a recorded wound, a model
## position, a missing hero row), so the grid is shown to fail, not assumed to.
##
## Regenerate the fixture ONLY after an intended, owned table change:
##   godot --headless -s res://test/one_core/golden_witness.gd -- --capture --family melee_fear_hero
## and review the diff line by line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")

## One capture serves the whole suite: the grid takes ~45 s and every test only reads it (static: it outlives the
## per-test suite instance, so the second test does not run the grid again).
static var _captured: Dictionary = {}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _saved_flag: String


func before_test() -> void:
	BattleSim._core_env = 0   # pinned to the GDScript AI: the witness records the table's rules, not the net's picks
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


func after() -> void:
	_captured = {}   # a later run in the same process records again


func _fixture() -> Dictionary:
	var want := Harness.load_fixture(Harness.fixture_path(Harness.MELEE_FEAR_HERO_FAMILY))
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s - capture it with --family melee_fear_hero" % Harness.MELEE_FEAR_HERO_FIXTURE_PATH).is_false()
	return want


func _capture() -> Dictionary:
	if _captured.is_empty():
		_captured = await Harness.capture(_main, Harness.MELEE_FEAR_HERO_FAMILY)
	return _captured


func _case(fixture: Dictionary, scenario: String, seed: int) -> Dictionary:
	for c in fixture.get("cases", []):
		if str(c["scenario"]) == scenario and int(c["seed"]) == seed:
			return c
	return {}


func test_the_melee_fear_hero_fixture_matches_the_old_table_path() -> void:
	var want := _fixture()
	var got: Dictionary = await _capture()
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message("melee Fear/hero witness differs (%s):\n%s" % [
		Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


## One capture, four planted faults: each changes exactly one recorded fact in a copy of the fixture, and the compare
## must name exactly that fact.
func test_planted_faults_in_the_fixture_are_each_reported() -> void:
	var want := _fixture()
	var got: Dictionary = await _capture()
	assert_array(Harness.compare(want, got)).override_failure_message(
		"a fresh capture must match the fixture before a fault is planted").is_empty()
	# 1. a battle-log line
	var a := want.duplicate(true)
	a["cases"][0]["lines"][0] = "%s (planted)" % str(a["cases"][0]["lines"][0])
	var pa := Harness.compare(a, got)
	assert_int(pa.size()).override_failure_message("a changed log line went unnoticed: %s" % str(pa)).is_equal(1)
	assert_str("\n".join(pa)).contains("planted")
	# 2. one recorded wound of the first hero case's hero (the unit total moves, the slot row moves with it)
	var b := want.duplicate(true)
	var hero_case := _case(b, "hero_charger", 17)
	hero_case["final"][2]["wounds"] = int(hero_case["final"][2]["wounds"]) - 1
	var pb := Harness.compare(b, got)
	assert_int(pb.size()).override_failure_message("a changed hero wound went unnoticed: %s" % str(pb)).is_equal(1)
	assert_str("\n".join(pb)).contains("hero_charger:17")
	# 3. a model position after consolidation (state the older fixtures never recorded)
	var c := want.duplicate(true)
	var moved := _case(c, "consolidation_win", 0)
	moved["extra"]["pos"][0][1][0][0] = "0.00"
	var pc := Harness.compare(c, got)
	assert_int(pc.size()).override_failure_message("a changed model position went unnoticed: %s" % str(pc)).is_equal(1)
	assert_str("\n".join(pc)).contains("consolidation_win:0")
	# 4. a hero row that is not in the recording
	var d := want.duplicate(true)
	var no_hero := _case(d, "hero_human", 0)
	(no_hero["final"] as Array).pop_back()
	var pd := Harness.compare(d, got)
	assert_int(pd.size()).override_failure_message("a missing hero row went unnoticed: %s" % str(pd)).is_greater_equal(1)
	assert_str("\n".join(pd)).contains("hero_human:0")


## The fixture must show what its scenario names. A witness whose Fear never changes a result, or whose hero never
## strikes, would stay green while the rule it claims to pin changed - these checks read the committed recording.
## A Fear case "flips" when the tally with the Fear bonus taken back out ends the melee another way than the line says.
func test_the_recording_exercises_what_the_scenarios_name() -> void:
	var want := _fixture()
	var tally := RegEx.create_from_string("Att took (\\d+)(?: \\(Fear: (\\d+)\\))?, Def took (\\d+)(?: \\(Fear: (\\d+)\\))?")
	var flips := {"fear_charger": 0, "fear_defender": 0, "fear_human": 0, "hero_fear_chain": 0}
	var hero_strikes := {"hero_charger": 0, "hero_human": 0, "hero_fear_chain": 0}
	var hero_hurt := 0
	var moved_after_win := false
	for c in want["cases"]:
		var name := str(c["scenario"])
		var key := "%s:%d" % [name, int(c["seed"])]
		var joined := "\n".join(c["lines"])
		if flips.has(name):
			var line := ""
			for l in c["lines"]:
				if str(l).contains("Melee result:"):
					line = str(l)
			var m := tally.search(line)
			assert_object(m).override_failure_message("%s: no Fear-adjusted result line in %s" % [key, line]).is_not_null()
			var raw_att := int(m.get_string(1)) - (int(m.get_string(2)) if m.get_string(2) != "" else 0)
			var raw_def := int(m.get_string(3)) - (int(m.get_string(4)) if m.get_string(4) != "" else 0)
			var raw_end := "draw" if raw_att == raw_def else ("Att" if raw_att > raw_def else "Def")
			var shown_end := "draw" if line.contains("a draw") else ("Att" if line.contains("Att loses") else "Def")
			if raw_end != shown_end:
				flips[name] += 1
		if hero_strikes.has(name) and joined.contains("AttHero strikes with Hero Blade"):
			hero_strikes[name] += 1
		if name == "hero_defender":
			assert_int((c["final"] as Array).size()).override_failure_message("%s must record three units" % key).is_equal(3)
			if int(c["final"][2]["wounds"]) < 3:
				hero_hurt += 1
		if name == "consolidation_win":
			moved_after_win = moved_after_win or str(c["extra"]["pos"][0][1][0][0]) != "6.74"
	for k in flips:
		assert_int(int(flips[k])).override_failure_message("%s: Fear never changes how a melee ends in any seed" % k).is_greater(0)
	for k in hero_strikes:
		assert_int(int(hero_strikes[k])).override_failure_message("%s: the joined hero never struck in any seed" % k).is_greater(0)
	assert_int(hero_hurt).override_failure_message("the defending hero never took a wound in any seed").is_greater(0)
	assert_bool(moved_after_win).override_failure_message(
		"consolidation_win recorded no movement: the far enemy is not the survivor's goal").is_true()

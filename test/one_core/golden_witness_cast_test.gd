extends GdUnitTestSuite
## CC-2 - the golden witness of the table's casts (the AI activation's cast leg), on the OLD table path.
##
## Companion of golden_witness_test.gd (same boot, same kill switch): it replays families `cast_damage` (a damage spell:
## the cast die, the spell's saves, a kill, the morale test) and `cast_effects` (a buff on the caster, a debuff on the
## enemy, a failed cast, a fizzle, boost + interference, a spent once-mod) through `_solo_resolve_ai_casts` and
## compares state + battle-log lines + the tray roll stream with its legs (`extra.rolls`) + the spell records and
## tokens left behind (`extra.mods`) with test/fixtures/one_core/golden_cast_{damage,effects}.json. It is the reference
## the core's cast door (plan PLAN_C_CAST_LEGS, CC-3..CC-13) must reproduce, byte for byte.
## Each fault the witness must notice is planted in a copy of the fixture, so the grid is shown to fail, not assumed to.
##
## Regenerate a fixture ONLY after an intended, owned table change:
##   godot --headless -s res://test/one_core/golden_witness.gd -- --capture --family cast_damage   (or cast_effects)
## and review the diff line by line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")

## One capture per family serves the whole suite (static: it outlives the per-test suite instance).
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


func _fixture(family: String) -> Dictionary:
	var want := Harness.load_fixture(Harness.fixture_path(family))
	assert_bool(want.is_empty()).override_failure_message(
		"fixture missing: %s - capture it with --family %s" % [Harness.fixture_path(family), family]).is_false()
	return want


func _capture(family: String) -> Dictionary:
	if not _captured.has(family):
		_captured[family] = await Harness.capture(_main, family)
	return _captured[family]


func _case(fixture: Dictionary, scenario: String, seed: int) -> Dictionary:
	for c in fixture.get("cases", []):
		if str(c["scenario"]) == scenario and int(c["seed"]) == seed:
			return c
	return {}


func _cases(fixture: Dictionary, scenario: String) -> Array:
	return (fixture.get("cases", []) as Array).filter(func(c: Variant) -> bool: return str((c as Dictionary)["scenario"]) == scenario)


func _text(c: Dictionary) -> String:
	return "\n".join(c["lines"])


func test_the_cast_fixtures_match_the_old_table_path() -> void:
	for family in [Harness.CAST_DAMAGE_FAMILY, Harness.CAST_EFFECTS_FAMILY]:
		var want := _fixture(family)
		var got: Dictionary = await _capture(family)
		var problems := Harness.compare(want, got)
		assert_array(problems).override_failure_message("%s witness differs (%s):\n%s" % [
			family, Harness.describe_provenance(want, got), "\n".join(problems)]).is_empty()


## One capture per family, planted faults: each changes exactly one recorded fact in a copy of the fixture, and the
## compare must name exactly that fact (a battle-log line, a tray roll with its leg, a spell record, a wound).
func test_planted_faults_in_the_fixtures_are_each_reported() -> void:
	var dmg := _fixture(Harness.CAST_DAMAGE_FAMILY)
	var eff := _fixture(Harness.CAST_EFFECTS_FAMILY)
	var got_d: Dictionary = await _capture(Harness.CAST_DAMAGE_FAMILY)
	var got_e: Dictionary = await _capture(Harness.CAST_EFFECTS_FAMILY)
	assert_array(Harness.compare(dmg, got_d) + Harness.compare(eff, got_e)).override_failure_message(
		"a fresh capture must match the fixtures before a fault is planted").is_empty()
	# 1. a battle-log line of the damage grid
	var a := dmg.duplicate(true)
	a["cases"][0]["lines"][0] = "%s (planted)" % str(a["cases"][0]["lines"][0])
	var pa := Harness.compare(a, got_d)
	assert_int(pa.size()).override_failure_message("a changed log line went unnoticed: %s" % str(pa)).is_equal(1)
	assert_str("\n".join(pa)).contains("planted")
	# 2. the leg of the cast die (the roll stream the core door must reproduce)
	var b := dmg.duplicate(true)
	var rolls: Array = b["cases"][0]["extra"]["rolls"]
	rolls[0] = str(rolls[0]).replace("cast|", "spell|")
	var pb := Harness.compare(b, got_d)
	assert_int(pb.size()).override_failure_message("a changed roll leg went unnoticed: %s" % str(pb)).is_equal(1)
	assert_str("\n".join(pb)).contains(str(b["cases"][0]["scenario"]))
	# 3. a spell record the buff left behind
	var c := eff.duplicate(true)
	var buff := _case(c, "buff_self", 0)
	buff["extra"]["mods"][0][1] = []
	var pc := Harness.compare(c, got_e)
	assert_int(pc.size()).override_failure_message("a missing spell record went unnoticed: %s" % str(pc)).is_equal(1)
	assert_str("\n".join(pc)).contains("buff_self:0")
	# 4. a wound of the damage grid (the unit total moves, the slot row moves with it)
	var d := dmg.duplicate(true)
	var hurt := _case(d, "bolt_saves", 0)
	hurt["final"][1]["wounds"] = int(hurt["final"][1]["wounds"]) + 1
	var pd := Harness.compare(d, got_d)
	assert_int(pd.size()).override_failure_message("a changed wound count went unnoticed: %s" % str(pd)).is_equal(1)
	assert_str("\n".join(pd)).contains("bolt_saves:0")


## The fixtures must show what their scenarios name. A witness whose cast never fails, whose morale test never runs or whose
## buff leaves no record would stay green while the rule it claims to pin changed - these checks read the committed recordings.
func test_the_recordings_exercise_what_the_scenarios_name() -> void:
	var dmg := _fixture(Harness.CAST_DAMAGE_FAMILY)
	var eff := _fixture(Harness.CAST_EFFECTS_FAMILY)
	# The roll stream: the cast die is the first roll and the `cast` leg; everything the effect rolls is the `spell` leg.
	for c in (dmg["cases"] as Array) + (eff["cases"] as Array):
		var rolls: Array = c["extra"]["rolls"]
		var key := "%s:%d" % [str(c["scenario"]), int(c["seed"])]
		if str(c["scenario"]) == "fizzle":
			assert_array(rolls).override_failure_message("%s: a fizzle rolls no die" % key).is_empty()
			continue
		assert_str(str(rolls[0])).override_failure_message("%s: the first roll is the cast die" % key).starts_with("cast|attack|1x")
		for r in rolls.slice(1):
			assert_str(str(r)).override_failure_message("%s: every roll after the die is the spell leg" % key).starts_with("spell|")
	# Damage: saves, a kill, morale held and failed, and a cast that fails before any save.
	var shaken := 0
	var held := 0
	var failed := 0
	var wiped := 0
	for c in dmg["cases"]:
		var text := _text(c)
		if text.contains("FAILED"):
			failed += 1
			assert_str(text).override_failure_message("%s:%d: a failed cast rolls no save" % [c["scenario"], c["seed"]]).not_contains("defends")
		if text.contains("passes morale"):
			held += 1
		if text.contains("fails morale"):
			shaken += 1
		if str(c["scenario"]) == "bolt_kill" and text.contains("destroyed"):
			wiped += 1
			assert_str(text).override_failure_message("a destroyed unit tests no morale").not_contains("morale")
	assert_int(failed).override_failure_message("no failed cast in the damage grid").is_greater(0)
	assert_int(held).override_failure_message("no morale test held after a spell").is_greater(0)
	assert_int(shaken).override_failure_message("no morale test failed after a spell").is_greater(0)
	assert_int(wiped).override_failure_message("bolt_kill never destroyed the foe").is_greater(0)
	# Effects: the buff and debuff leave their records and tokens, a failed cast leaves none, a fizzle is one line, the
	# boosted cast states its spend and needs 3+, the once-mod is stated and spent.
	var low_fail := 0   # a failed 4+ cast whose die was a 2 or a 3 (not only the natural 1)
	for c in eff["cases"]:
		var name := str(c["scenario"])
		var key := "%s:%d" % [name, int(c["seed"])]
		var text := _text(c)
		var ok := text.contains("SUCCESS")
		var mods: Array = c["extra"]["mods"]
		match name:
			"buff_self", "boost_interference", "casting_once":
				assert_int((mods[0][1] as Array).size()).override_failure_message("%s: the buff record" % key).is_equal(1 if ok else 0)
				assert_int((mods[0][2] as Array).size()).override_failure_message("%s: the buff token" % key).is_equal(1 if ok else 0)
			"debuff_foe":
				assert_int((mods[1][1] as Array).size()).override_failure_message("%s: the debuff record" % key).is_equal(1 if ok else 0)
		if name == "boost_interference":
			assert_str(text).override_failure_message(key).contains("needs 3+ (2 tokens, +2 boost, -1 interference)")
		if name == "casting_once":
			assert_str(text).override_failure_message(key).contains("+1 to casting rolls (Focus +1)")
			if ok:
				assert_str(text).override_failure_message(key).contains("\"Focus\" on Mystic is consumed")
		if name == "fizzle":
			assert_int((c["lines"] as Array).size()).override_failure_message(key).is_equal(1)
			assert_str(text).contains("fizzles")
		if name == "buff_self" and not ok:
			var die := int(str(c["extra"]["rolls"][0]).split("|")[-1])
			low_fail += 1 if die in [2, 3] else 0
	assert_int(low_fail).override_failure_message("no failed cast with a die of 2 or 3").is_greater(0)

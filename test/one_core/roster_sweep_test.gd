extends GdUnitTestSuite
## One core C-7: the roster sweep harness (test/one_core/roster_sweep.gd) on the bundled real lists. The instrument is checked here
## (it covers every unit on both paths, the parity files and the compare work, the coverage and gate mechanics can fail); the
## sweep over a fleet's per-faction lists is the CLI (roster_sweep_cli.gd). The control pairing below is equal on both paths today:
## a rule or capture change that makes the table and the core diverge on a real roster turns it red with the first difference.
## Real: the main scene, NmlCore, the importer and `EquipmentDistributor` on real list JSON, the table's AI body, the live capture
## and the step driver, tools/parity/parity_compare.py. Constructed: only the unit placement (two blocks, 14" apart).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const LISTS := ["res://assets/arena_lists/p1_2000.json", "res://assets/arena_lists/p2_2000.json"]
const DICE := "user://roster_sweep_dice"
const OUT := "user://roster_sweep_out"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _lists() -> Array:
	return LISTS.map(func(p: String) -> Dictionary: return RosterSweep.load_list(p))


func test_the_sweep_fires_every_unit_and_targets_every_unit_on_both_paths() -> void:
	var lists := _lists()
	var pairs := RosterSweep.ring(lists)
	assert_int(pairs.size()).is_equal(1)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var seeds := 2
	var rows: Array = await RosterSweep.sweep_pair(_main, lists[0], lists[1], seeds, ProjectSettings.globalize_path(DICE))
	var units: Array = (lists[0]["units"] as Array) + (lists[1]["units"] as Array)
	var n := maxi((lists[0]["units"] as Array).size(), (lists[1]["units"] as Array).size())
	assert_int(rows.size()).override_failure_message("2 directions x the longer list x seeds").is_equal(2 * n * seeds)
	var shot := {}
	var hit := {}
	for r in rows:
		shot[r["att"]] = true
		hit[r["tgt"]] = true
	for e in units:
		var nm := str((e["unit"] as OPRApiClient.OPRUnit).name)
		assert_bool(shot.has(nm)).override_failure_message("%s never shot" % nm).is_true()
		assert_bool(hit.has(nm)).override_failure_message("%s was never a target" % nm).is_true()
	var cmp := RosterSweep.compare(rows, OUT)
	assert_array(cmp["problems"]).override_failure_message("the compare's own problems: %s" % [cmp["problems"]]).is_empty()
	var fired := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return bool(v["fired"])).size()
	var verdict := RosterSweep.gate(cmp["verdicts"], {})
	print("ROSTER_SWEEP volleys=%d fired=%d roll_mismatches=%d state_mismatches=%d" % [rows.size(), fired, cmp["roll_mismatches"], verdict["mismatches"] - int(cmp["roll_mismatches"])])
	assert_int(fired).override_failure_message("only %d of %d volleys threw a die: the sweep compares nothing" % [fired, rows.size()]).is_greater(rows.size() / 4)
	assert_array(verdict["unexplained"]).override_failure_message("table and core differ on a real roster: %s" % [(verdict["unexplained"] as Array).slice(0, 3)]).is_empty()
	for half in ["table", "core"]:
		var lines := FileAccess.get_file_as_string(OUT.path_join("sweep_%s.jsonl" % half)).split("\n", false)
		assert_int(lines.size()).override_failure_message("one parity row per volley (%s)" % half).is_equal(rows.size())
	var cov := RosterSweep.coverage(cmp["verdicts"])
	assert_bool(cov.has("AP") and int(cov["AP"]["att"]) > 0 and int(cov["AP"]["tgt"]) > 0).override_failure_message("coverage: %s" % [cov.keys()]).is_true()


func test_an_uncovered_rule_name_is_listed() -> void:
	var cov := {"AP": {"att": 5, "tgt": 5}, "Fear": {"att": 5, "tgt": 0}, "Slow": {"att": 2, "tgt": 9}}
	assert_array(RosterSweep.uncovered(cov, ["AP", "Fear", "Slow", "Zap"], 3)).is_equal(["Fear", "Slow", "Zap"])
	assert_array(RosterSweep.uncovered(cov, ["AP"], 5)).is_empty()
	assert_array(RosterSweep.rule_names("gf")).contains(["AP", "Fear", "Tough"])


func test_a_mismatch_is_explained_only_by_a_label_of_the_deny_list() -> void:
	var v := [{"first_diff": "", "labels": {"att": ["AP"], "tgt": []}},
		{"first_diff": "rolls", "labels": {"att": ["AP"], "tgt": ["Guardian"]}},
		{"first_diff": "tgt.alive", "labels": {"att": [], "tgt": ["Fear"]}}]
	var g := RosterSweep.gate(v, {"Guardian": "alias not ported"})
	assert_int(int(g["mismatches"])).is_equal(2)
	assert_int(int(g["explained"])).is_equal(1)
	assert_int((g["unexplained"] as Array).size()).is_equal(1)
	assert_int((RosterSweep.gate(v, {})["unexplained"] as Array).size()).is_equal(2)


func test_the_ring_puts_every_list_in_two_pairings() -> void:
	var ls := [{"system": "gf", "name": "a"}, {"system": "gf", "name": "b"}, {"system": "gf", "name": "c"}]
	var pairs := RosterSweep.ring(ls)
	assert_int(pairs.size()).is_equal(3)
	for l in ls:
		assert_int(pairs.filter(func(p: Array) -> bool: return p[0] == l or p[1] == l).size()).is_equal(2)
	assert_array(RosterSweep.ring([ls[0]])).is_empty()

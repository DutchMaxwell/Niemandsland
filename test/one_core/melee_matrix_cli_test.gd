extends GdUnitTestSuite
## Plan E (speed plan lever 3): the melee matrix CLI (`melee_matrix_cli.gd`). The instrument proves itself before it reports:
## a rule-free control pair must be equal on every seed and a planted fault (the core half's defender 1" further out) must be
## unequal, else the run is refused. Real: the main scene, NmlCore, the table's `_run_ai_melee`, the door's `run_ai_charge`.
## The verdict CLASSES are pinned on the classifier itself (state > roll > line) and on two cells that cannot drift: AP on the charger's
## weapon (lifted, EQUAL) and a plain Hero (the rule never fires, INERT). A cell with a known log-line gap is NOT pinned here on purpose:
## the line lanes fix those and an unrelated PR would go red; read such cells from the committed cell list run instead.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Cli := preload("res://test/one_core/melee_matrix_cli.gd")
const CELLS := "res://test/one_core/melee_matrix_cells.json"
const SEEDS := 4

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	Cli.arm(_main)


func after_test() -> void:
	Cli.fault_nudge_in = 1.0
	Cli.core_half_nudge_in = 0.0
	Cli.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _cells(wanted: Array) -> Array:
	var all: Array = Cli.load_cells(CELLS)
	assert_int(all.size()).override_failure_message("committed cell list is empty").is_greater(0)
	var out: Array = []
	for w in wanted:
		var hit: Array = all.filter(func(c: Dictionary) -> bool: return c["primitive"] == w[0] and c["seat"] == w[1])
		assert_int(hit.size()).override_failure_message("cell %s missing from the committed list" % [w]).is_equal(1)
		out.append(hit[0])
	return out


func _row(report: Dictionary, prim: String, seat: String) -> Dictionary:
	for r in report["cells"]:
		if r["primitive"] == prim and r["seat"] == seat:
			return r
	return {}


## A half as `_half` returns it, hand-built, so the classifier is pinned without a board.
func _half(core: int) -> Dictionary:
	return {"att": [Vector2(1, 2)], "foe": [Vector2(3, 4)], "wounds": [0, 1], "alive": [1, 1], "shaken": [false, false],
		"fatigued": [false, false], "ledger": ["{}", "{}"], "heroes": [], "rng": 7, "rolls": ["attack|2|4|[1,2]"],
		"lines": ["MELEE|a"], "core": core}


func test_the_classifier_ranks_state_over_roll_over_line() -> void:
	var t := _half(0)
	assert_bool(bool(Cli._compare_halves(t, _half(1))["equal"])).is_true()
	var lines := _half(1)
	lines["lines"] = ["MELEE|b"]
	var c1: Dictionary = Cli._compare_halves(t, lines)
	assert_str(str(c1["cls"])).is_equal("line")
	assert_str(str(c1["diff"])).contains("#0")
	var rolls := lines.duplicate(true)
	rolls["rolls"] = ["attack|2|4|[1,3]"]
	assert_str(str(Cli._compare_halves(t, rolls)["cls"])).is_equal("roll")
	var state := rolls.duplicate(true)
	state["wounds"] = [0, 2]
	assert_str(str(Cli._compare_halves(t, state)["cls"])).is_equal("state")
	var moved := _half(1)
	moved["foe"] = [Vector2(3, 4.5)]
	assert_str(str(Cli._compare_halves(t, moved)["cls"])).is_equal("state")
	var refused: Dictionary = Cli._compare_halves(t, _half(0))
	assert_str(str(refused["cls"])).is_equal("state")
	assert_str(str(refused["diff"])).contains("door_refused")


func test_known_cells_get_their_verdict_and_the_instrument_passes() -> void:
	var report: Dictionary = await Cli.run_matrix(_main, _cells([["AP", "CW"], ["Hero (plain)", "CU"]]), SEEDS)
	assert_bool(bool(report.get("ok", false))).override_failure_message("run refused: %s" % report.get("error", "")).is_true()
	if not bool(report.get("ok", false)):
		return
	assert_int(int(report["control"]["equal_seeds"])).is_equal(SEEDS)
	assert_int(int(report["planted_fault"]["equal_seeds"])).is_equal(0)
	assert_str(str(report["planted_fault"]["first_diff_class"])).is_equal("state")
	var ap := _row(report, "AP", "CW")
	assert_str(str(ap["verdict"])).is_equal("EQUAL")
	assert_int(int(ap["equal_seeds"])).is_equal(SEEDS)
	assert_int(int(ap["fired_seeds"])).is_greater(0)
	var hero := _row(report, "Hero (plain)", "CU")
	assert_str(str(hero["verdict"])).is_equal("INERT")
	assert_int(int(hero["fired_seeds"])).is_equal(0)
	assert_int(int((report["totals"] as Dictionary)["EQUAL"])).is_equal(1)
	assert_int(int((report["totals"] as Dictionary)["INERT"])).is_equal(1)


## RED proof of the refusal: break the instrument and the run must not report.
func test_a_control_that_is_not_equal_refuses_the_run() -> void:
	Cli.core_half_nudge_in = 0.5
	var report: Dictionary = await Cli.run_matrix(_main, _cells([["AP", "CW"]]), 2)
	assert_bool(bool(report.get("ok", true))).is_false()
	assert_str(str(report.get("error", ""))).contains("control")
	assert_bool(report.has("cells")).is_false()


func test_a_planted_fault_that_is_equal_refuses_the_run() -> void:
	Cli.fault_nudge_in = 0.0
	var report: Dictionary = await Cli.run_matrix(_main, _cells([["AP", "CW"]]), 2)
	assert_bool(bool(report.get("ok", true))).is_false()
	assert_str(str(report.get("error", ""))).contains("planted fault")
	assert_bool(report.has("cells")).is_false()

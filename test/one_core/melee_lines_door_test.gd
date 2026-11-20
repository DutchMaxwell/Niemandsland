extends GdUnitTestSuite
## Plan E, melee lines train (lane lift92): the battle-log lines the table writes in a melee and the core door did not, per rule, through the committed
## melee matrix cells (`melee_matrix_cells.json`, door vs table, every compared key incl. the lines in order). Each cell below was a LINE-class cell
## (the dice and the end state equal, a line missing or different) before the train and must now be EQUAL on every seed. The instrument proves itself
## first (rule-free control equal, planted fault unequal) or the run is refused (`melee_matrix_cli_test.gd` pins that half).
## Real: the main scene, NmlCore, the table's `_run_ai_melee`, the door's `run_ai_charge`. Constructed: the matrix's fixture units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Cli := preload("res://test/one_core/melee_matrix_cli.gd")
const CELLS := "res://test/one_core/melee_matrix_cells.json"
const SEEDS := 8
## [primitive, seat]: what each part of the train says (Blast multiplier, the Shielded defence part, the Deadly landing line, the Surge line, the
## Piercing Assault AP line).
## Rending CW is not listed: its line is said now, but its save target (Defense + AP(+4) above 6: the table prints 8, the roll record clamps to 6) stays the
## accepted roll-label class (PLAN_E 19.11. 13:00), like Hazardous.
const TRAIN_CELLS := [["Blast", "CW"], ["Shielded", "TU"], ["Deadly", "CW"], ["Deadly", "TW"], ["Surge", "CW"], ["Piercing Assault", "CU"],
	["Piercing Assault", "CW"], ["Limited", "CW"]]

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
	Cli.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_the_melee_line_cells_of_the_train_are_equal() -> void:
	var all: Array = Cli.load_cells(CELLS)
	var cells: Array = []
	for w in TRAIN_CELLS:
		var hit: Array = all.filter(func(c: Dictionary) -> bool: return c["primitive"] == w[0] and c["seat"] == w[1])
		assert_int(hit.size()).override_failure_message("cell %s missing from the committed list" % [w]).is_equal(1)
		cells.append(hit[0])
	var report: Dictionary = await Cli.run_matrix(_main, cells, SEEDS)
	assert_bool(bool(report.get("ok", false))).override_failure_message("run refused: %s" % report.get("error", "")).is_true()
	if not bool(report.get("ok", false)):
		return
	for row in report["cells"]:
		print("MELEE_LINES %s %s -> %s %d/%d fired=%d %s" % [row["primitive"], row["seat"], row["verdict"], row["equal_seeds"], SEEDS, row["fired_seeds"], row["first_diff"]])
		assert_str(str(row["verdict"])).override_failure_message("%s %s: %s (%s)" % [row["primitive"], row["seat"], row["verdict"], row["first_diff"]]).is_equal("EQUAL")

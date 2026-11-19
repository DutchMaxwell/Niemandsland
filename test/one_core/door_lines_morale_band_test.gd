extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 4): the Banner lines of the shooting morale test a volley causes. A target with Valiant, shot
## from inside the 9" gate, loses its +1 and the table says so ("Banner: <U> gets no +1 from a shot at 9" or under (Valiant counts only
## beyond the gate)"); the core wrote that line only in its ledger. Beyond the gate the Valiant +1 stays and both paths name it
## ("Valiant: <U> gets +1 to morale test rolls (passes on N+)"). Same harness as the other door_lines suites: `SEEDS` seeded volleys on
## the table and on the door, the lines that name the rule compared. The Hero, spell-token and Mind Control lines are pinned in Rust
## (tests/sim/door_morale_lines.rs): the sweep's units join no Hero and carry no spell.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://door_lines_morale_band_dice"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _same(label: String, opts: Dictionary, min_fired: int, rules: Array, prefix: String) -> void:
	var gunners := DoorLines.entry("Gunners", 12, [], [], "battle_brothers", 12)
	var target := DoorLines.entry("Targets", 10, rules, [], "battle_brothers", 0)
	var r := await DoorLines.compare(_main, gunners, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts)
	print("DOOR_LINES %s fired=%d/%d mismatches=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size()])
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func test_a_valiant_target_shot_inside_the_gate_names_the_share_it_loses() -> void:
	await _same("valiant inside", {"distance_in": 8.0}, 3, ["Valiant"], "Banner:")


## Control: the same unit shot from beyond the gate keeps the +1 and both paths name it.
func test_a_valiant_target_shot_beyond_the_gate_names_its_bonus() -> void:
	await _same("valiant beyond", {}, 3, ["Valiant"], "Valiant:")

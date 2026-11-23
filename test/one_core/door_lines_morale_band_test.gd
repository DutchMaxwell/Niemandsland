extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 4): the Banner lines of the shooting morale test a volley causes. A target with Valiant, shot
## from inside the 9" gate, loses its +1 and the table says so ("Banner: <U> gets no +1 from a shot at 9" or under (Valiant counts only
## beyond the gate)"); the core wrote that line only in its ledger. Beyond the gate the Valiant +1 stays and both paths name it
## ("Valiant: <U> gets +1 to morale test rolls (passes on N+)"). Same harness as the other door_lines suites: `SEEDS` seeded volleys on
## the table and on the door, the lines that name the rule compared. The Hero, spell-token and Mind Control lines are pinned in Rust
## (tests/sim/door_morale_lines.rs): the sweep's units join no Hero and carry no spell.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://door_lines_morale_band_dice"

## The door's rule lines per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_VALIANT_INSIDE := [
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	[],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"],
	["COMBAT|Banner: Targets gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_VALIANT_BEYOND := [
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	[],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"],
	["COMBAT|Valiant: Targets gets +1 to morale test rolls (passes on 3+)"]]

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


func _same(label: String, opts: Dictionary, min_fired: int, rules: Array, prefix: String, want: Array) -> void:
	var gunners := DoorLines.entry("Gunners", 12, [], [], "battle_brothers", 12)
	var target := DoorLines.entry("Targets", 10, rules, [], "battle_brothers", 0)
	var dice := ProjectSettings.globalize_path(DICE)
	var got: Array = []
	var fired := 0
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, gunners, target, s, true, dice, opts)
		var lines := DoorLines.named(door["lines"], prefix)
		got.append(lines)
		fired += 1 if not lines.is_empty() else 0
	print("DOOR_LINES %s fired=%d/%d" % [label, fired, SEEDS])
	assert_int(fired).override_failure_message("%s: the rule never fired through the door, nothing is pinned" % label).is_greater_equal(min_fired)
	assert_array(got).override_failure_message("%s: the door's rule lines moved from the pinned values" % label).is_equal(want)


func test_a_valiant_target_shot_inside_the_gate_names_the_share_it_loses() -> void:
	await _same("valiant inside", {"distance_in": 8.0}, 3, ["Valiant"], "Banner:", WANT_VALIANT_INSIDE)


## Control: the same unit shot from beyond the gate keeps the +1 and both paths name it.
func test_a_valiant_target_shot_beyond_the_gate_names_its_bonus() -> void:
	await _same("valiant beyond", {}, 3, ["Valiant"], "Valiant:", WANT_VALIANT_BEYOND)

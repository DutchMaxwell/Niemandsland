extends GdUnitTestSuite
## The deny name `Protection Feat` leaves the deny file. The once-per-game ignore roll's "already used" line is the core's own
## tray line; the spend line stays the door's own sentence after the volley (`CoreActivation._land_feats`, the core only traces
## it) - each line is said once. Probe: `SEEDS` real AI volleys at a Protection Feat unit through the door, once with the feat
## fresh and once with it already spent (the table's latch planted on both halves): the deny file takes the pair and the core
## says the spend (or the already-used) line exactly once per seed.
## Real: the main scene, NmlCore, the importer's unit builder, the live deny file. Constructed: the OPR units.
## RED (main): the deny file refuses the target (taken 0).
## The table arm left with the AI table resolver; door values are snapshot pins read on main ab595da20 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://core_protection_feat_lift_dice"
const SPENT := "spends its once-per-game ignore roll"
const USED := "already used it this game"
## Per seed: the door's count of the spend line, said exactly once (read on main from the table arm).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_FRESH := [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
## Per seed: the door's count of the already-used line, said exactly once (read on main from the table arm).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SPENT := [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

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


static func _count(lines: Array, needle: String) -> int:
	return lines.filter(func(l: String) -> bool: return l.contains("Protection Feat") and l.contains(needle)).size()


## `SEEDS` door volleys of `gunners` at `warriors`; returns {"taken": seeds the deny file takes, "counts": the door's
## per-seed count of the spend (or already-used) line}.
func _probe(spent: bool) -> Dictionary:
	var gunners := DoorLines.entry("Gunners", 10, [], ["AP(1)"], "battle_brothers", 10)
	var warriors := DoorLines.entry("Warriors", 5, ["Protection Feat"], [], "robot_legions", 0)
	var opts := {"ledger": {"tgt": {CoreActivation._ignore_flag("Protection Feat"): true}}} if spent else {}
	var out := {"taken": 0, "counts": []}
	var needle := USED if spent else SPENT
	for s in SEEDS:
		var core := await RosterSweep.volley(_main, gunners, warriors, s, true, ProjectSettings.globalize_path(DICE), opts)
		out["taken"] += 1 if (core["deny"] as Array).is_empty() else 0
		(out["counts"] as Array).append(_count(core["lines"], needle))
	return out


func _gate(label: String, r: Dictionary, want: Array) -> void:
	print("PF_LIFT %s taken=%d/%d counts=%s" % [label, r["taken"], SEEDS, str(r["counts"])])
	assert_int(int(r["taken"])).override_failure_message("%s: the deny file still refuses the target" % label).is_equal(SEEDS)
	assert_array(r["counts"]).override_failure_message("%s: the rule's line count per seed" % label).is_equal(want)


func test_a_fresh_protection_feat_is_spent_once_and_said_once_through_the_door() -> void:
	_gate("fresh", await _probe(false), WANT_FRESH)


func test_a_spent_protection_feat_says_already_used_through_the_door() -> void:
	_gate("spent", await _probe(true), WANT_SPENT)

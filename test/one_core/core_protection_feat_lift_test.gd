extends GdUnitTestSuite
## PLAN_FIRST_DELETION (D-PAR3, after step 29a): the deny name `Protection Feat` leaves the deny file. The once-per-game ignore roll's
## "already used" line is the core's own tray line since 29a; the spend line stays the door's own sentence after the volley
## (`CoreActivation._land_feats`, the core only traces it) - each line is said once. Probe: `SEEDS` real AI volleys at a Protection Feat unit through the
## door against the same volley on the table (`RosterSweep.volley`), once with the feat fresh and once with it already spent (the
## table's latch planted on both halves): the deny file takes the pair, dice (kind, count, faces) and rule state equal, the core says
## each line the table says, and the spend line appears exactly once.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body, the live deny file. Constructed: the OPR units.
## RED (main): the deny file refuses the target (taken 0).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://core_protection_feat_lift_dice"
const SPENT := "spends its once-per-game ignore roll"
const USED := "already used it this game"

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


static func _dice(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> Array: return [str(r["kind"]), int(r["count"]), r["faces"]])


static func _count(lines: Array, needle: String) -> int:
	return lines.filter(func(l: String) -> bool: return l.contains("Protection Feat") and l.contains(needle)).size()


func _probe(spent: bool) -> Dictionary:
	var gunners := DoorLines.entry("Gunners", 10, [], ["AP(1)"], "battle_brothers", 10)
	var warriors := DoorLines.entry("Warriors", 5, ["Protection Feat"], [], "robot_legions", 0)
	var opts := {"ledger": {"tgt": {CoreActivation._ignore_flag("Protection Feat"): true}}} if spent else {}
	var out := {"taken": 0, "named": 0, "bad": []}
	for s in SEEDS:
		var table := await RosterSweep.volley(_main, gunners, warriors, s, false, ProjectSettings.globalize_path(DICE), opts)
		var core := await RosterSweep.volley(_main, gunners, warriors, s, true, ProjectSettings.globalize_path(DICE), opts)
		out["taken"] += 1 if (table["deny"] as Array).is_empty() else 0
		var needle := USED if spent else SPENT
		var t_n := _count(table["lines"], needle)
		var c_n := _count(core["lines"], needle)
		out["named"] += 1 if t_n > 0 else 0
		if _dice(table["rolls"]) != _dice(core["rolls"]):
			(out["bad"] as Array).append("seed %d dice: table %s | core %s" % [s, _dice(table["rolls"]), _dice(core["rolls"])])
		elif RosterSweep.first_state_diff(table["state"], core["state"]) != "":
			(out["bad"] as Array).append("seed %d state: %s" % [s, RosterSweep.first_state_diff(table["state"], core["state"])])
		elif t_n != c_n or c_n > 1:
			(out["bad"] as Array).append("seed %d '%s' lines: table %d, core %d\n%s" % [s, needle, t_n, c_n, core["lines"]])
	return out


func _gate(label: String, r: Dictionary) -> void:
	print("PF_LIFT %s taken=%d/%d named=%d bad=%d" % [label, r["taken"], SEEDS, r["named"], (r["bad"] as Array).size()])
	assert_int(int(r["taken"])).override_failure_message("%s: the deny file still refuses the target" % label).is_equal(SEEDS)
	assert_int(int(r["named"])).override_failure_message("%s: the table never said the line - nothing was probed" % label).is_greater(0)
	assert_array(r["bad"]).override_failure_message("%s:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 3))]).is_empty()


func test_a_fresh_protection_feat_is_spent_once_and_said_once_through_the_door() -> void:
	_gate("fresh", await _probe(false))


func test_a_spent_protection_feat_says_already_used_through_the_door() -> void:
	_gate("spent", await _probe(true))

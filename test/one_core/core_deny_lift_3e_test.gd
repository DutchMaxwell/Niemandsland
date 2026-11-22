extends GdUnitTestSuite
## PLAN_FIRST_DELETION step 3e: deny entries that the parity ruling (docs/one_core/PARITY_RULING.md: a label or wording gap is no
## refusal reason) and #3410 (an illegal step is not landed) no longer need. One probe per lifted entry: `SEEDS` real AI volleys
## through the door against the same volley on the table (`RosterSweep.volley`) - the deny file takes the pair, dice (kind, count,
## faces per roll) and rule state equal, no core landing refused, and the core names the rule wherever the table does.
## The Harassing kite (`hit_and_run_landing`) is probed in core_hit_and_run_door_test.gd (the door takes it, #3410 refuses the
## illegal landing) and on the gate-12 game-3 board (PR text). STAY: `door_own_shred_beside_alias` (a state difference) and
## `door_takedown_names_an_equipment_carrier` (this probe's Banner carrier was taken with the group present too: the probe could not fail).
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body, the live deny file. Constructed: the OPR units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://core_deny_lift_3e_dice"

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


## The rolls by what the ruling compares: kind, count and every face (labels and owners are not compared).
static func _dice(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> Array: return [str(r["kind"]), int(r["count"]), r["faces"]])


## `seeds` volleys on both paths; returns the counts the probe gates on.
func _probe(shooter: Dictionary, target: Dictionary, rule: String, seeds: int, opts := {}) -> Dictionary:
	var out := {"taken": 0, "named_table": 0, "unnamed_core": [], "dice_bad": [], "state_bad": [], "refused_landings": 0}
	for s in seeds:
		var refused := CoreActivation.land_illegal
		var table := await RosterSweep.volley(_main, shooter, target, s, false, ProjectSettings.globalize_path(DICE), opts)
		var core := await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		out["refused_landings"] += CoreActivation.land_illegal - refused
		out["taken"] += 1 if (table["deny"] as Array).is_empty() else 0
		if _dice(table["rolls"]) != _dice(core["rolls"]):
			(out["dice_bad"] as Array).append("seed %d: table %s | core %s" % [s, _dice(table["rolls"]), _dice(core["rolls"])])
		var diff := RosterSweep.first_state_diff(table["state"], core["state"])
		if diff != "":
			(out["state_bad"] as Array).append("seed %d: %s" % [s, diff])
		var says := func(lines: Array) -> bool: return lines.any(func(l: String) -> bool: return l.contains(rule))
		if says.call(table["lines"]):
			out["named_table"] += 1
			if not says.call(core["lines"]):
				(out["unnamed_core"] as Array).append("seed %d: %s" % [s, core["lines"]])
	return out


func _gate(label: String, r: Dictionary) -> void:
	print("DENY_LIFT_3E %s taken=%d/%d named_table=%d unnamed_core=%d dice_bad=%d state_bad=%d refused_landings=%d" % [label, r["taken"], SEEDS,
		r["named_table"], (r["unnamed_core"] as Array).size(), (r["dice_bad"] as Array).size(), (r["state_bad"] as Array).size(), r["refused_landings"]])
	assert_int(int(r["taken"])).override_failure_message("%s: the deny file still refuses the pair" % label).is_equal(SEEDS)
	assert_int(int(r["named_table"])).override_failure_message("%s: the rule never fired on the table - nothing was probed" % label).is_greater(0)
	assert_array(r["dice_bad"]).override_failure_message("%s: dice differ:\n%s" % [label, "\n".join((r["dice_bad"] as Array).slice(0, 3))]).is_empty()
	assert_array(r["state_bad"]).override_failure_message("%s: rule state differs: %s" % [label, r["state_bad"]]).is_empty()
	assert_array(r["unnamed_core"]).override_failure_message("%s: the core does not name the rule:\n%s" % [label, "\n".join((r["unnamed_core"] as Array).slice(0, 2))]).is_empty()
	assert_int(int(r["refused_landings"])).override_failure_message("%s: a core landing was refused as illegal" % label).is_equal(0)


## Deny name `Enhanced Knightborn` (a label gap: which of Knightborn / Enhanced Knightborn names the roll group at the shot's distance).
## Shot from 14" (the gated ignore rolls) and from 6".
func test_the_enhanced_knightborn_target_reads_equal_through_the_door() -> void:
	var gunners := DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10)
	var knights := DoorLines.entry("Knights", 5, ["Enhanced Knightborn"], [], "knight_brothers", 0)
	var far := await _probe(gunners, knights, "Knightborn", SEEDS / 2, {"distance_in": 14.0})
	var near := await _probe(gunners, knights, "Knightborn", SEEDS / 2, {"distance_in": 6.0})
	for k in ["taken", "named_table", "refused_landings"]:
		far[k] = int(far[k]) + int(near[k])
	for k in ["unnamed_core", "dice_bad", "state_bad"]:
		far[k] = (far[k] as Array) + (near[k] as Array)
	_gate("Enhanced Knightborn", far)


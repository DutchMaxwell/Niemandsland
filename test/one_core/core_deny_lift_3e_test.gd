extends GdUnitTestSuite
## Deny entries that the parity ruling (docs/one_core/PARITY_RULING.md: a label or wording gap is no refusal reason) and #3410
## (an illegal step is not landed) no longer need. One probe per lifted entry: `SEEDS` real AI volleys through the door - the deny
## file takes the pair, no core landing is refused, and the core names the rule wherever the rule acts.
## The Harassing kite (`hit_and_run_landing`) is probed in core_hit_and_run_door_test.gd (the door takes it, #3410 refuses the
## illegal landing) and on the gate-12 game-3 board (PR text). STAY: `door_own_shred_beside_alias` (a state difference) and
## `door_takedown_names_an_equipment_carrier` (this probe's Banner carrier was taken with the group present too: the probe could not fail).
## Real: the main scene, NmlCore, the importer's unit builder, the live deny file. Constructed: the OPR units.
## The table arm left with the AI table resolver; door values are snapshot pins read on main ab595da20 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 16
const DICE := "user://core_deny_lift_3e_dice"
## Over the 16 seeds (8 at 14 in and 8 at 6 in): the door's count of seeds whose lines name the rule (read on main from the table arm).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_NAMED := 16

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


## `seeds` door volleys; returns the counts the probe gates on.
func _probe(shooter: Dictionary, target: Dictionary, rule: String, seeds: int, opts := {}) -> Dictionary:
	var out := {"taken": 0, "named": 0, "refused_landings": 0}
	for s in seeds:
		var refused := CoreActivation.land_illegal
		var core := await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		out["refused_landings"] += CoreActivation.land_illegal - refused
		out["taken"] += 1 if (core["deny"] as Array).is_empty() else 0
		if (core["lines"] as Array).any(func(l: String) -> bool: return l.contains(rule)):
			out["named"] += 1
	return out


func _gate(label: String, r: Dictionary) -> void:
	print("DENY_LIFT_3E %s taken=%d/%d named=%d refused_landings=%d" % [label, r["taken"], SEEDS,
		r["named"], r["refused_landings"]])
	assert_int(int(r["taken"])).override_failure_message("%s: the deny file still refuses the pair" % label).is_equal(SEEDS)
	assert_int(int(r["named"])).override_failure_message("%s: the rule never fired through the door - nothing was probed" % label).is_equal(WANT_NAMED)
	assert_int(int(r["refused_landings"])).override_failure_message("%s: a core landing was refused as illegal" % label).is_equal(0)


## Deny name `Enhanced Knightborn` (a label gap: which of Knightborn / Enhanced Knightborn names the roll group at the shot's distance).
## Shot from 14" (the gated ignore rolls) and from 6".
func test_the_enhanced_knightborn_target_reads_equal_through_the_door() -> void:
	var gunners := DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10)
	var knights := DoorLines.entry("Knights", 5, ["Enhanced Knightborn"], [], "knight_brothers", 0)
	var far := await _probe(gunners, knights, "Knightborn", SEEDS / 2, {"distance_in": 14.0})
	var near := await _probe(gunners, knights, "Knightborn", SEEDS / 2, {"distance_in": 6.0})
	for k in ["taken", "named", "refused_landings"]:
		far[k] = int(far[k]) + int(near[k])
	_gate("Enhanced Knightborn", far)


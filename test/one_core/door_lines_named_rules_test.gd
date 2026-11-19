extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 1): Blast, Deadly, the Bloodborn family's extra attacks and "Ambushing Piercing Shot"
## each write their line on the core door, in the table's words. Since C-19 the AI door takes most volleys; the core wrote none of
## these four lines while the table does (a rule applied with no log line). Each case runs `SEEDS` seeded volleys on the table and
## on the door and compares the lines that name the rule (`door_lines.gd`). RED on the old library (the door writes nothing);
## the control cases (a rule that does not apply says nothing on either path) are green on both.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_named_dice"

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


## One case: the lines of `prefix` agree on both halves, and the rule really fired on the table in at least `min_fired` seeds.
func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1, opts := {}, needle := "") -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts, needle)
	print("DOOR_LINES %s fired=%d/%d with_text=%d mismatches=%d" % [label, r["fired"], SEEDS, r["with_text"], (r["bad"] as Array).size()])
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	if needle != "":
		assert_int(int(r["with_text"])).override_failure_message("%s: no seed wrote a line with %s" % [label, needle]).is_greater_equal(1)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _target(size := 10, rules := []) -> Dictionary:
	return DoorLines.entry("Targets", size, rules, [], "battle_brothers", 0)


func test_blast_names_its_multiplier_and_the_cap() -> void:
	await _same("blast", DoorLines.entry("Gunners", 10, [], ["Blast(3)"]), _target(), "Blast(", SEEDS / 2)
	await _same("blast capped", DoorLines.entry("Gunners", 10, [], ["Blast(3)"]), _target(2), "Blast(", SEEDS / 2)


func test_deadly_names_what_it_dealt() -> void:
	await _same("deadly", DoorLines.entry("Gunners", 10, [], ["Deadly(3)"]), _target(5, ["Tough(3)"]), "Deadly(", SEEDS / 2)


## Deadly(2) against Tough(3): the first wound leaves a model at 1, the next must finish it, and the second line says so.
func test_deadly_names_the_wounded_tough_model_it_must_finish() -> void:
	await _same("deadly forced", DoorLines.entry("Gunners", 10, [], ["Deadly(2)"]), _target(5, ["Tough(3)"]), "Deadly(", SEEDS / 2, {}, "finish the already-wounded")


func test_bloodborn_names_its_extra_attacks() -> void:
	await _same("bloodborn", DoorLines.entry("Gunners", 10, ["Bloodborn"], [], "blood_brothers"), _target(), "Bloodborn:", 3)


## "Ambushing Piercing Shot" in its arrival round (the sweep's round is 1) names the rule; one round later it says nothing on either path.
func test_the_ambush_arrival_ap_is_named_in_the_arrival_round_only() -> void:
	var gunners := DoorLines.entry("Gunners", 10, ["Ambushing Piercing Shot"], [])
	await _same("ambush arrival", gunners, _target(), "Ambushing Piercing Shot:", SEEDS, {"ledger": {"att": {"ambush_arrived_round": 1}}})
	var late: Dictionary = await DoorLines.compare(_main, gunners, _target(), "Ambushing Piercing Shot:", SEEDS, ProjectSettings.globalize_path(DICE),
		{"ledger": {"att": {"ambush_arrived_round": 0}}})
	assert_int(int(late["fired"])).override_failure_message("an earlier arrival names the rule").is_equal(0)
	assert_array(late["bad"]).is_empty()

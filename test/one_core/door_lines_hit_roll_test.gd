extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 2): the lines a weapon's hit roll and AP add - Reliable, Precise, Relentless, the Surge family,
## the AP-on-6 rules (Rending, Crack), the named conditional AP (Havocbound, Slayer) - are written by the core door in the table's
## words. Same harness as door_lines_named_rules_test.gd (`door_lines.gd`): `SEEDS` seeded volleys on the table and on the door, the
## lines that name the rule compared. RED on the old library (the door says none of them), GREEN with this change.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_hit_roll_dice"

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
func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE))
	print("DOOR_LINES %s fired=%d/%d mismatches=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size()])
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _target(size := 10, rules := []) -> Dictionary:
	return DoorLines.entry("Targets", size, rules, [], "battle_brothers", 0)


func test_reliable_names_its_quality_once() -> void:
	await _same("reliable", DoorLines.entry("Gunners", 10, [], ["Reliable"]), _target(), "Reliable:", 6)


func test_precise_names_its_bonus() -> void:
	await _same("precise", DoorLines.entry("Gunners", 10, [], ["Precise"]), _target(), "Precise:", 6)


func test_relentless_names_the_hits_the_sixes_paid() -> void:
	await _same("relentless", DoorLines.entry("Gunners", 10, ["Relentless"], []), _target(), "Relentless:", 3)


## A Surge alias names its gate, then the plain total: both lines are compared.
func test_surge_names_its_alias_and_its_bonus() -> void:
	var gunners := DoorLines.entry("Gunners", 10, ["Surge when Shooting"], [])
	await _same("surge alias", gunners, _target(), "Surge when Shooting:", 3)
	await _same("surge total", gunners, _target(), "Surge:", 3)


func test_the_ap_on_6_rules_name_their_hits() -> void:
	await _same("rending", DoorLines.entry("Gunners", 10, [], ["Rending"]), _target(), "Rending:", 3)
	await _same("crack", DoorLines.entry("Gunners", 10, [], ["Crack"], "war_disciples"), _target(), "Crack:", 3)


func test_named_conditional_ap_names_the_rule_and_the_target() -> void:
	await _same("havocbound", DoorLines.entry("Gunners", 10, ["Havocbound"], [], "havoc_brothers"), _target(), "Havocbound:", 6)
	await _same("slayer", DoorLines.entry("Gunners", 10, ["Slayer"], [], "dao_union"), _target(5, ["Tough(3)"]), "Slayer:", 3)

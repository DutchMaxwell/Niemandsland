extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 3): the Versatile Attack pick ("<rule>: <U> picks +1 to hit / AP(+1) for this activation"),
## the over-9" Defense line of the Guarded family ("<U> (Sturdy): shot from over 9" - +1 Defense (saves on N+)"), a Bane alias's re-roll
## line ("Smash: <U> re-rolls N unmodified Defense 6s (why)") and the morale trigger line a Tough single model gets once wounds leave it
## at half ("<U> is at half its tough value (a/b) - morale test (<book>)") are written by the core door in the table's words. Same harness as the other door_lines suites: `SEEDS` seeded volleys on
## the table and on the door, the lines that name the rule compared. RED on the old library, GREEN with this change.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_save_step_dice"

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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE))
	print("DOOR_LINES %s fired=%d/%d mismatches=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size()])
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func test_the_versatile_pick_is_named_once_per_volley() -> void:
	await _same("versatile", DoorLines.entry("Gunners", 10, ["Versatile Attack"], []), DoorLines.entry("Targets", 10, [], [], "battle_brothers", 0),
		"Versatile Attack:", SEEDS)


## One Tough(6) model shot by ten Gunners: wounds leave it at half or less on most seeds, and the morale test follows.
func test_a_tough_single_model_at_half_says_so_before_the_morale_test() -> void:
	await _same("morale half", DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10), DoorLines.entry("Giant", 1, ["Tough(6)"], [], "battle_brothers", 0),
		"Giant is at half its tough value", 3)


## A target that projects +1 Defense from over 9" (Sturdy, the Guarded family) names the rule once per volley.
func test_a_sturdy_target_names_its_over_nine_defense() -> void:
	await _same("sturdy", DoorLines.entry("Gunners", 10, [], []), DoorLines.entry("Targets", 10, ["Sturdy"], [], "dwarf_guilds", 0),
		"Targets (Sturdy)", SEEDS)


## A weapon alias of Bane (Smash: "over half the weapon's range") names its re-rolls, with the condition that opened them.
func test_a_bane_alias_names_its_rerolls() -> void:
	await _same("bane alias", DoorLines.entry("Gunners", 10, [], ["Smash"], "battle_brothers", 10), DoorLines.entry("Targets", 10, [], [], "battle_brothers", 0),
		"Smash:", SEEDS / 2)

extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 3): the Versatile Attack pick ("<rule>: <U> picks +1 to hit / AP(+1) for this activation"),
## the over-9" Defense line of the Guarded family ("<U> (Sturdy): shot from over 9" - +1 Defense (saves on N+)"), a Bane alias's re-roll
## line ("Smash: <U> re-rolls N unmodified Defense 6s (why)") and the morale trigger line a Tough single model gets once wounds leave it
## at half ("<U> is at half its tough value (a/b) - morale test (<book>)") are written by the core door in the table's words. Same harness as the other door_lines suites: `SEEDS` seeded volleys on
## the door, the lines that name the rule pinned. RED on the old library, GREEN with that change.
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_save_step_dice"
## Per label: the door's count of rule lines that name the prefix, per seed (SEEDS entries).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"versatile": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"morale half": [0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1],
	"sturdy": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"bane alias": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
}

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


## One case: the door alone runs SEEDS volleys and writes the pinned count of `<prefix>` rule lines per seed.
func _door_says(label: String, shooter: Dictionary, target: Dictionary, prefix: String) -> void:
	var want: Array = WANT_LINES.get(label, [])
	var got: Array = []
	for s in SEEDS:
		var v: Dictionary = await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE))
		got.append(DoorLines.named(v["lines"], prefix).size())
	print("DOOR_LINES %s %s" % [label, JSON.stringify(got)])
	assert_array(got).override_failure_message("%s: the door's %s lines per seed %s, want %s" % [label, prefix, JSON.stringify(got), JSON.stringify(want)]).is_equal(want)


func test_the_versatile_pick_is_named_once_per_volley() -> void:
	await _door_says("versatile", DoorLines.entry("Gunners", 10, ["Versatile Attack"], []), DoorLines.entry("Targets", 10, [], [], "battle_brothers", 0),
		"Versatile Attack:")


## One Tough(6) model shot by ten Gunners: wounds leave it at half or less on most seeds, and the morale test follows.
func test_a_tough_single_model_at_half_says_so_before_the_morale_test() -> void:
	await _door_says("morale half", DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10), DoorLines.entry("Giant", 1, ["Tough(6)"], [], "battle_brothers", 0),
		"Giant is at half its tough value")


## A target that projects +1 Defense from over 9" (Sturdy, the Guarded family) names the rule once per volley.
func test_a_sturdy_target_names_its_over_nine_defense() -> void:
	await _door_says("sturdy", DoorLines.entry("Gunners", 10, [], []), DoorLines.entry("Targets", 10, ["Sturdy"], [], "dwarf_guilds", 0),
		"Targets (Sturdy)")


## A weapon alias of Bane (Smash: "over half the weapon's range") names its re-rolls, with the condition that opened them.
func test_a_bane_alias_names_its_rerolls() -> void:
	await _door_says("bane alias", DoorLines.entry("Gunners", 10, [], ["Smash"], "battle_brothers", 10), DoorLines.entry("Targets", 10, [], [], "battle_brothers", 0),
		"Smash:")

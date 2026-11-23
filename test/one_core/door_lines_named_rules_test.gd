extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 1): Blast, Deadly, the Bloodborn family's extra attacks and "Ambushing Piercing Shot"
## each write their line on the core door, in the table's words. Since C-19 the AI door takes most volleys; the core wrote none of
## these four lines while the table does (a rule applied with no log line). Each case runs `SEEDS` seeded volleys on the door and
## pins the lines that name the rule (`door_lines.gd`). RED on the old library (the door wrote nothing);
## the control cases (a rule that does not apply says nothing) pin zero lines.
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_named_dice"
## Per label: the door's count of `<prefix>` lines that contain the case's needle (all `<prefix>` lines when it has none), per seed.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"blast": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
	"blast capped": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
	"deadly": [1, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0],
	"deadly forced": [1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0],
	"bloodborn": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"ambush arrival": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"ambush late": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
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


## One case: the door alone runs SEEDS volleys and writes the pinned count of `<prefix>` lines that contain `needle`
## (every `<prefix>` line when the case has none) per seed.
func _door_says(label: String, shooter: Dictionary, target: Dictionary, prefix: String, opts := {}, needle := "") -> void:
	var want: Array = WANT_LINES.get(label, [])
	var got: Array = []
	for s in SEEDS:
		var v: Dictionary = await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		var hits: Array = DoorLines.named(v["lines"], prefix)
		if needle != "":
			hits = hits.filter(func(l: String) -> bool: return l.contains(needle))
		got.append(hits.size())
	print("DOOR_LINES %s %s" % [label, JSON.stringify(got)])
	assert_array(got).override_failure_message("%s: the door's %s lines per seed %s, want %s" % [label, prefix, JSON.stringify(got), JSON.stringify(want)]).is_equal(want)


func _target(size := 10, rules := []) -> Dictionary:
	return DoorLines.entry("Targets", size, rules, [], "battle_brothers", 0)


func test_blast_names_its_multiplier_and_the_cap() -> void:
	await _door_says("blast", DoorLines.entry("Gunners", 10, [], ["Blast(3)"]), _target(), "Blast(")
	await _door_says("blast capped", DoorLines.entry("Gunners", 10, [], ["Blast(3)"]), _target(2), "Blast(")


func test_deadly_names_what_it_dealt() -> void:
	await _door_says("deadly", DoorLines.entry("Gunners", 10, [], ["Deadly(3)"]), _target(5, ["Tough(3)"]), "Deadly(")


## Deadly(2) against Tough(3): the first wound leaves a model at 1, the next must finish it, and the second line says so.
func test_deadly_names_the_wounded_tough_model_it_must_finish() -> void:
	await _door_says("deadly forced", DoorLines.entry("Gunners", 10, [], ["Deadly(2)"]), _target(5, ["Tough(3)"]), "Deadly(", {}, "finish the already-wounded")


func test_bloodborn_names_its_extra_attacks() -> void:
	await _door_says("bloodborn", DoorLines.entry("Gunners", 10, ["Bloodborn"], [], "blood_brothers"), _target(), "Bloodborn:")


## "Ambushing Piercing Shot" in its arrival round (the sweep's round is 1) names the rule; one round later it says nothing.
func test_the_ambush_arrival_ap_is_named_in_the_arrival_round_only() -> void:
	var gunners := DoorLines.entry("Gunners", 10, ["Ambushing Piercing Shot"], [])
	await _door_says("ambush arrival", gunners, _target(), "Ambushing Piercing Shot:", {"ledger": {"att": {"ambush_arrived_round": 1}}})
	await _door_says("ambush late", gunners, _target(), "Ambushing Piercing Shot:", {"ledger": {"att": {"ambush_arrived_round": 0}}})

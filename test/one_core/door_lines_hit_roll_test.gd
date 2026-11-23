extends GdUnitTestSuite
## One core, door lines (lane dlines, PR 2): the lines a weapon's hit roll and AP add - Reliable, Precise, Relentless, the Surge family,
## the AP-on-6 rules (Rending, Crack), the named conditional AP (Havocbound, Slayer) - are written by the core door in the table's
## words. Same harness as door_lines_named_rules_test.gd (`door_lines.gd`): `SEEDS` seeded volleys on the door, the
## lines that name the rule pinned. RED on the old library (the door said none of them), GREEN with that change.
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_hit_roll_dice"
## Per label: the door's count of rule lines that name the prefix, per seed (SEEDS entries).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"reliable": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"precise": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"relentless": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"surge alias": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"surge total": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"rending": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"crack": [1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0],
	"havocbound": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
	"slayer": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
	"unpredictable shooter": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"unpredictable": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"disintegrate": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
	"tear": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
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


func _target(size := 10, rules := []) -> Dictionary:
	return DoorLines.entry("Targets", size, rules, [], "battle_brothers", 0)


func test_reliable_names_its_quality_once() -> void:
	await _door_says("reliable", DoorLines.entry("Gunners", 10, [], ["Reliable"]), _target(), "Reliable:")


func test_precise_names_its_bonus() -> void:
	await _door_says("precise", DoorLines.entry("Gunners", 10, [], ["Precise"]), _target(), "Precise:")


func test_relentless_names_the_hits_the_sixes_paid() -> void:
	await _door_says("relentless", DoorLines.entry("Gunners", 10, ["Relentless"], []), _target(), "Relentless:")


## A Surge alias names its gate, then the plain total: both lines are pinned.
func test_surge_names_its_alias_and_its_bonus() -> void:
	var gunners := DoorLines.entry("Gunners", 10, ["Surge when Shooting"], [])
	await _door_says("surge alias", gunners, _target(), "Surge when Shooting:")
	await _door_says("surge total", gunners, _target(), "Surge:")


func test_the_ap_on_6_rules_name_their_hits() -> void:
	await _door_says("rending", DoorLines.entry("Gunners", 10, [], ["Rending"]), _target(), "Rending:")
	await _door_says("crack", DoorLines.entry("Gunners", 10, [], ["Crack"], "war_disciples"), _target(), "Crack:")


func test_named_conditional_ap_names_the_rule_and_the_target() -> void:
	await _door_says("havocbound", DoorLines.entry("Gunners", 10, ["Havocbound"], [], "havoc_brothers"), _target(), "Havocbound:")
	await _door_says("slayer", DoorLines.entry("Gunners", 10, ["Slayer"], [], "dao_union"), _target(5, ["Tough(3)"]), "Slayer:")


func _aof(entry: Dictionary) -> Dictionary:
	(entry["unit"] as OPRApiClient.OPRUnit).game_system = "aof"
	entry["system"] = "aof"
	return entry


## H-15a (Plan H): the volley die of Unpredictable (Shooter) says the table's line, `<rule>: <U>'s volley rolls N -> AP(+1) | +1 to hit`; both
## spellings (gf jackals, aof duchies_of_vinci). Before, the core threw the die and said nothing on volleys the door already took.
## RED: drop the `say_rule` of the die in the core's volley fold -> the table says the line and the door does not.
func test_the_unpredictable_die_names_the_rule_and_the_roll() -> void:
	await _door_says("unpredictable shooter", DoorLines.entry("Gunners", 10, ["Unpredictable Shooter"], [], "jackals"), _target(), "Unpredictable Shooter:")
	var generic := _aof(DoorLines.entry("Gunners", 10, ["Unpredictable"], [], "duchies_of_vinci"))
	await _door_says("unpredictable", generic, _aof(DoorLines.entry("Targets", 10, [], [], "human_empire", 0)), "Unpredictable:")


## H-17a (Plan H): the generic conditional-AP rules say the table's line too (`Disintegrate: AP(+2) against <U>`, `Tear: AP(+4) against <U>`),
## so the `door_omits_conditional_ap_line` group left the deny file. Disintegrate bites a target at Defense 3+ or better, Tear a Tough(9)+ one.
## RED: restore the group, or drop `say_name` from the core's dice fold -> the table says the line and the door does not.
func test_the_generic_conditional_ap_rules_name_themselves() -> void:
	var armoured := _target()
	(armoured["unit"] as OPRApiClient.OPRUnit).defense = 3
	await _door_says("disintegrate", DoorLines.entry("Gunners", 10, [], ["Disintegrate"], "dao_union"), armoured, "Disintegrate:")
	await _door_says("tear", DoorLines.entry("Gunners", 10, [], ["Tear"], "orc_marauders"), _target(1, ["Tough(9)"]), "Tear:")

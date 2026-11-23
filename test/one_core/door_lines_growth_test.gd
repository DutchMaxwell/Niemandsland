extends GdUnitTestSuite
## One core, door lines (lane lift92): the Growth Markers family's lines in the table's words on the door, pinned per rule and per
## marker count (the lines that name the rule): Piercing Growth / Frenzy ("adds AP(+N) from its growth markers"),
## Defensive Growth / Frenzy ("<U> is <rule>: +N Defense (saves on M+)"), Fortified Growth ("takes the hits at AP(b) instead of AP(a)") and the Frenzy
## kill marker ("gains a marker for the kill (n/m)"). The same commit lifts the `Growth Markers` deny entry: the door takes these volleys now.
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_growth_dice"
## Per label: the door's count of rule lines that name the prefix, per seed (SEEDS entries).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"piercing growth 2": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"piercing growth 4": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"piercing frenzy": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"defensive growth 2": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"defensive growth 4": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"defensive frenzy": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"fortified growth 2": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"fortified growth 4": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"Piercing Frenzy kill at 0": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"Piercing Frenzy kill at 1": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"Piercing Frenzy capped": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"Precision Frenzy kill at 0": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"Precision Frenzy kill at 1": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"Precision Frenzy capped": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
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
func _door_says(label: String, shooter: Dictionary, target: Dictionary, prefix: String, opts := {}) -> void:
	var want: Array = WANT_LINES.get(label, [])
	var got: Array = []
	for s in SEEDS:
		var v: Dictionary = await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		got.append(DoorLines.named(v["lines"], prefix).size())
	print("DOOR_LINES %s %s" % [label, JSON.stringify(got)])
	assert_array(got).override_failure_message("%s: the door's %s lines per seed %s, want %s" % [label, prefix, JSON.stringify(got), JSON.stringify(want)]).is_equal(want)


func _unit(uname: String, size: int, rules: Array, weapon_rules: Array, faction: String, system: String, guns: int) -> Dictionary:
	var e := DoorLines.entry(uname, size, rules, weapon_rules, faction, guns)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


func _marked(who: String, rule: String, markers: int) -> Dictionary:
	return {"ledger": {who: {"growth_%s" % rule.to_snake_case(): markers}}}


## The AP the markers add is named once per weapon profile that has hits to save: Piercing Growth per two markers, Piercing Frenzy per marker.
func test_a_piercing_carrier_names_the_ap_its_markers_add() -> void:
	for markers in [2, 4]:
		await _door_says("piercing growth %d" % markers, _unit("Strikers", 10, ["Piercing Growth"], ["AP(1)"], "alien_hives", "gf", 10),
			_unit("Ranks", 10, [], [], "battle_brothers", "gf", 0), "Piercing Growth:", _marked("att", "Piercing Growth", markers))
	await _door_says("piercing frenzy", _unit("Strikers", 10, ["Piercing Frenzy"], ["AP(1)"], "dark_elves", "aof", 10),
		_unit("Ranks", 10, [], [], "battle_brothers", "gf", 0), "Piercing Frenzy:", _marked("att", "Piercing Frenzy", 2))


## Defensive Growth / Frenzy name their Defense bonus once before the announce, the target's own name leading the line.
func test_a_defensive_target_names_its_defense_bonus() -> void:
	for markers in [2, 4]:
		await _door_says("defensive growth %d" % markers, _unit("Strikers", 10, [], ["AP(1)"], "battle_brothers", "gf", 10),
			_unit("Ranks", 10, ["Defensive Growth"], [], "human_inquisition", "gf", 0), "Ranks is", _marked("tgt", "Defensive Growth", markers))
	await _door_says("defensive frenzy", _unit("Strikers", 10, [], ["AP(1)"], "battle_brothers", "gf", 10),
		_unit("Ranks", 10, ["Defensive Frenzy"], [], "daemons_of_war", "aof", 0), "Ranks is", _marked("tgt", "Defensive Frenzy", 2))


## Fortified Growth names the AP cut once per save batch, against a weapon that has AP to cut.
func test_a_fortified_growth_target_names_its_ap_cut() -> void:
	for markers in [2, 4]:
		await _door_says("fortified growth %d" % markers, _unit("Strikers", 10, [], ["AP(2)"], "daemons_of_plague", "aof", 10),
			_unit("Ranks", 10, ["Fortified Growth"], [], "daemons_of_plague", "aof", 0), "Fortified Growth:", _marked("tgt", "Fortified Growth", markers))


## A Frenzy carrier that wipes its target says the marker the kill earns ("gains a marker for the kill (n/2)"), and none once capped.
func test_a_frenzy_kill_names_its_marker() -> void:
	for rule in ["Piercing Frenzy", "Precision Frenzy"]:
		var faction := "dark_elves" if rule == "Piercing Frenzy" else "dwarves"
		for markers in [0, 1]:
			await _door_says("%s kill at %d" % [rule, markers], _unit("Strikers", 10, [rule], ["AP(1)"], faction, "aof", 10),
				_unit("Ranks", 2, [], [], "battle_brothers", "gf", 0), "%s:" % rule, _marked("att", rule, markers))
		# at the cap (2) the kill places nothing and a Precision rule adds no AP: the pin holds what the door writes there
		await _door_says("%s capped" % rule, _unit("Strikers", 10, [rule], ["AP(1)"], faction, "aof", 10),
			_unit("Ranks", 2, [], [], "battle_brothers", "gf", 0), "%s:" % rule, _marked("att", rule, 2))

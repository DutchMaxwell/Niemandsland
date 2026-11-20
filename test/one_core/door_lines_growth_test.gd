extends GdUnitTestSuite
## One core, door lines (lane lift92): the Growth Markers family's lines in the table's words, on the door and on the table, compared per rule and per
## marker count (the lines that name the rule, in order, plus the end state): Piercing Growth / Frenzy ("adds AP(+N) from its growth markers"),
## Defensive Growth / Frenzy ("<U> is <rule>: +N Defense (saves on M+)"), Fortified Growth ("takes the hits at AP(b) instead of AP(a)") and the Frenzy
## kill marker ("gains a marker for the kill (n/m)"). The same commit lifts the `Growth Markers` deny entry: the door takes these volleys now.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_growth_dice"

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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1, opts := {}) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts)
	print("DOOR_LINES %s fired=%d/%d mismatches=%d state_bad=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size(), r["state_bad"]])
	assert_int(int(r["state_bad"])).override_failure_message("%s: the end states differ, the lines are compared over a pair the door must not take" % label).is_equal(0)
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


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
		await _same("piercing growth %d" % markers, _unit("Strikers", 10, ["Piercing Growth"], ["AP(1)"], "alien_hives", "gf", 10),
			_unit("Ranks", 10, [], [], "battle_brothers", "gf", 0), "Piercing Growth:", 6, _marked("att", "Piercing Growth", markers))
	await _same("piercing frenzy", _unit("Strikers", 10, ["Piercing Frenzy"], ["AP(1)"], "dark_elves", "aof", 10),
		_unit("Ranks", 10, [], [], "battle_brothers", "gf", 0), "Piercing Frenzy:", 6, _marked("att", "Piercing Frenzy", 2))


## Defensive Growth / Frenzy name their Defense bonus once before the announce, the target's own name leading the line.
func test_a_defensive_target_names_its_defense_bonus() -> void:
	for markers in [2, 4]:
		await _same("defensive growth %d" % markers, _unit("Strikers", 10, [], ["AP(1)"], "battle_brothers", "gf", 10),
			_unit("Ranks", 10, ["Defensive Growth"], [], "human_inquisition", "gf", 0), "Ranks is", 6, _marked("tgt", "Defensive Growth", markers))
	await _same("defensive frenzy", _unit("Strikers", 10, [], ["AP(1)"], "battle_brothers", "gf", 10),
		_unit("Ranks", 10, ["Defensive Frenzy"], [], "daemons_of_war", "aof", 0), "Ranks is", 6, _marked("tgt", "Defensive Frenzy", 2))


## Fortified Growth names the AP cut once per save batch, against a weapon that has AP to cut.
func test_a_fortified_growth_target_names_its_ap_cut() -> void:
	for markers in [2, 4]:
		await _same("fortified growth %d" % markers, _unit("Strikers", 10, [], ["AP(2)"], "daemons_of_plague", "aof", 10),
			_unit("Ranks", 10, ["Fortified Growth"], [], "daemons_of_plague", "aof", 0), "Fortified Growth:", 6, _marked("tgt", "Fortified Growth", markers))


## A Frenzy carrier that wipes its target says the marker the kill earns ("gains a marker for the kill (n/2)"), and none once capped.
func test_a_frenzy_kill_names_its_marker() -> void:
	for rule in ["Piercing Frenzy", "Precision Frenzy"]:
		var faction := "dark_elves" if rule == "Piercing Frenzy" else "dwarves"
		for markers in [0, 1]:
			await _same("%s kill at %d" % [rule, markers], _unit("Strikers", 10, [rule], ["AP(1)"], faction, "aof", 10),
				_unit("Ranks", 2, [], [], "battle_brothers", "gf", 0), "%s:" % rule, 6, _marked("att", rule, markers))
		# at the cap (2) the kill places nothing and a Precision rule adds no AP: neither side may say a line (compared, none required to fire)
		await _same("%s capped" % rule, _unit("Strikers", 10, [rule], ["AP(1)"], faction, "aof", 10),
			_unit("Ranks", 2, [], [], "battle_brothers", "gf", 0), "%s:" % rule, 0, _marked("att", rule, 2))

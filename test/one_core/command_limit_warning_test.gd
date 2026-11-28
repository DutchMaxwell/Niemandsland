extends GdUnitTestSuite
## #3862 (O-FT-1): CommandPicks.limit_warning asks the core's `rules::command_limit` (AoF: Skirmish p.13: one model per
## army with each command upgrade) through `NmlCore.command_limit`, and only warns.
## Real: CommandPicks.limit_warning, the NmlCore binding, the core rule. Constructed: the OPRArmy and its units.


func _army(system: String, units: Array) -> OPRApiClient.OPRArmy:
	var army := OPRApiClient.OPRArmy.new()
	army.game_system_abbrev = system
	for spec in units:
		var u := OPRApiClient.OPRUnit.new()
		u.name = str(spec[0])
		u.special_rules.assign(spec[1])
		u.upgrades.assign(spec[2])
		army.units.append(u)
	return army


func before_test() -> void:
	if not ClassDB.class_exists("NmlCore"):
		fail("the core extension is not loaded")


func test_a_second_banner_is_named() -> void:
	var line := CommandPicks.limit_warning(_army("aofs", [["First", ["Banner"], []], ["Second", [], ["Banner"]]]))
	assert_str(line).is_equal(
		"Warning: Second: only one Banner per army in this game system (AoF: Skirmish p.13: one model per army with each command upgrade) - the list plays on")


func test_one_of_each_and_a_label_seen_twice_on_one_unit_pass() -> void:
	assert_str(CommandPicks.limit_warning(_army("aofs", [["Band", ["Banner"], ["Banner"]], ["Pipes", ["Musician"], []]]))).is_empty()


func test_other_systems_have_no_army_limit() -> void:
	for sys in ["gf", "gff", "aof"]:
		assert_str(CommandPicks.limit_warning(_army(sys, [["A", ["Banner"], []], ["B", ["Banner"], []]]))).is_empty()

extends GdUnitTestSuite
## Ruling D16, CMD-ROUNDTRIP step CR2: the table's profile carries an AoF: Skirmish command group's picks (the unit ids its
## Banner and Musician reach) the way the Rust core reads them (core/nml-core-godot/src/plain.rs `command_picks`): written
## from `unit_properties["command_picks"]` when there are any, absent otherwise, so every other profile keeps its shape.


func _unit(props: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "A"
	u.unit_properties = {"player_id": 1, "name": "A", "quality": 4, "defense": 4, "special_rules": ["Banner"], "game_system": "aofs"}
	u.unit_properties.merge(props, true)
	return u


func test_the_picks_are_written_as_unit_ids() -> void:
	var p := BattleSim._unit_profile(_unit({"command_picks": ["B", "C"]}))
	assert_array(p.get("command_picks", [])).is_equal(["B", "C"])


func test_no_picks_write_no_key() -> void:
	assert_bool(BattleSim._unit_profile(_unit({})).has("command_picks")).override_failure_message("no picks set").is_false()
	assert_bool(BattleSim._unit_profile(_unit({"command_picks": []})).has("command_picks")) \
		.override_failure_message("an empty pick list is none").is_false()


func test_the_profile_copies_the_picks() -> void:
	var u := _unit({"command_picks": ["B"]})
	var p := BattleSim._unit_profile(u)
	(u.unit_properties["command_picks"] as Array).append("C")
	assert_array(p.get("command_picks", [])).override_failure_message("a later change on the table does not rewrite the record").is_equal(["B"])

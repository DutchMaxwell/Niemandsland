extends GdUnitTestSuite
## Ruling D16, CMD-ROUNDTRIP step CR3: at game start an AoF: Skirmish command group without picks gets the core's default
## two (`NmlCore.default_command_picks`: the nearest living friendly units, ties by key) in `unit_properties`, with one
## battle-log line; chosen picks, other systems and other units stay untouched.

const IN2M := 0.0254


func _unit(army: OPRArmyManager, uid: String, player: int, x_in: float, rules: Array, system := "aofs") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": player, "name": uid, "quality": 4, "defense": 4, "special_rules": rules, "game_system": system}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	m.properties = {"weapons": [], "equipment": []}
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	army.game_units[uid] = u
	return u


func _core() -> Object:
	return ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null


func _board(system := "aofs") -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	_unit(army, "Cmd", 1, 0.0, ["Banner"], system)
	_unit(army, "Near", 1, 3.0, [])
	_unit(army, "Mid", 1, 6.0, [])
	_unit(army, "Far", 1, 20.0, [])
	_unit(army, "Foe", 2, 1.0, [])
	return army


func test_the_two_nearest_friends_are_picked_and_said() -> void:
	if _core() == null:
		return   # the rule lives in the core; CI builds the extension
	var army := _board()
	var lines := BattleSim.default_command_picks(army, _core())
	assert_array(army.game_units["Cmd"].unit_properties.get("command_picks", [])).is_equal(["Near", "Mid"])
	assert_array(lines).is_equal(["Command group: Cmd's Banner reaches Near and Mid"])


func test_chosen_picks_and_other_systems_stay() -> void:
	var army := _board()
	army.game_units["Cmd"].unit_properties["command_picks"] = ["Far"]
	assert_array(BattleSim.default_command_picks(army, _core())).is_empty()
	assert_array(army.game_units["Cmd"].unit_properties["command_picks"]).is_equal(["Far"])
	var aof := _board("aof")
	assert_array(BattleSim.default_command_picks(aof, _core())).is_empty()
	assert_bool(aof.game_units["Cmd"].unit_properties.has("command_picks")).is_false()

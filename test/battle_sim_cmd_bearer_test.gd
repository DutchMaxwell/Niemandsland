extends GdUnitTestSuite
## Ruling D16, CMD-ROUNDTRIP step CR1: the table's capture writes an AoF: Skirmish command group's bearer the way the Rust
## core counts it (core/nml-core/src/io.rs `cmd_bearer`): the LAST model of the unit carries it, so the key is its slot
## among the living models while it lives and -1 once it is killed. Every other unit writes no key, so its records keep
## their shape.

const IN2M := 0.0254


func _model(u: GameUnit, x_in: float, alive: bool, equipment: Array = []) -> ModelInstance:
	var m := ModelInstance.new()
	m.is_alive = alive
	m.wounds_max = 1
	m.wounds_current = 1
	m.unit = u
	m.properties = {"weapons": [], "equipment": equipment}
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	return m


## Unit "A" of `system` with `rules` and three models whose life is `alive`; the plain unit the core is handed. `kit[i]`,
## when given, is model i's equipment.
func _plain(system: String, rules: Array, alive: Array, kit: Array = []) -> Dictionary:
	var a := GameUnit.new()
	a.unit_id = "A"
	a.unit_properties = {"player_id": 1, "name": "A", "quality": 4, "defense": 4, "special_rules": rules, "game_system": system}
	for i in alive.size():
		a.models.append(_model(a, float(i), alive[i], kit[i] if i < kit.size() else []))
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a}
	var st := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 3)
	return BattleSim.state_to_plain(st, false)["units"]["A"]


func test_the_bearer_is_the_last_living_slot_while_it_lives() -> void:
	assert_int(int(_plain("aofs", ["Banner"], [true, true, true]).get("cmd_bearer", -9))).is_equal(2)
	assert_int(int(_plain("aofs", ["Musician"], [true, false, true]).get("cmd_bearer", -9))) \
		.override_failure_message("another model's death moves the bearer's slot up, it stays the last").is_equal(1)


func test_a_killed_bearer_is_minus_one() -> void:
	assert_int(int(_plain("aofs", ["Banner"], [true, true, false]).get("cmd_bearer", -9))).is_equal(-1)


func test_no_key_outside_an_aofs_command_group() -> void:
	assert_bool(_plain("aof", ["Banner"], [true, true]).has("cmd_bearer")).override_failure_message("aof has no command groups").is_false()
	assert_bool(_plain("aofs", ["Sergeant"], [true, true]).has("cmd_bearer")).override_failure_message("no Banner or Musician").is_false()


## KIT-BEARER-NAME: the model the import gave the Banner carries it, wherever it stands in the unit.
func test_the_marked_model_is_the_bearer() -> void:
	assert_int(int(_plain("aofs", ["Banner"], [true, true, true], [[], ["Banner"], []]).get("cmd_bearer", -9))).is_equal(1)
	assert_int(int(_plain("aofs", ["Musician"], [false, true, true], [[], ["Musician"], []]).get("cmd_bearer", -9))) \
		.override_failure_message("a dead model before it moves its slot up").is_equal(0)
	assert_int(int(_plain("aofs", ["Banner"], [true, false, true], [[], ["Banner"], []]).get("cmd_bearer", -9))) \
		.override_failure_message("the marked model is killed: the last living one does not inherit it").is_equal(-1)


## Lead ruling 26.11.: Banner and Musician on two models are two bearers; on one model, or named by none, one key.
func test_two_models_two_bearers() -> void:
	var two := _plain("aofs", ["Banner", "Musician"], [true, true, true], [[], ["Banner"], ["Musician"]])
	assert_array([two.get("cmd_bearer", -9), two.get("cmd_musician", -9)]).is_equal([1, 2])
	var gone := _plain("aofs", ["Banner", "Musician"], [true, false, true], [[], ["Banner"], ["Musician"]])
	assert_array([gone.get("cmd_bearer", -9), gone.get("cmd_musician", -9)]) \
		.override_failure_message("the Banner's model fell: the Musician's slot moves up, it lives").is_equal([-1, 1])
	var one := _plain("aofs", ["Banner", "Musician"], [true, true, true], [[], ["Banner", "Musician"], []])
	assert_bool(one.has("cmd_musician")).override_failure_message("one model carries both: one key").is_false()
	assert_bool(_plain("aofs", ["Banner", "Musician"], [true, true, true]).has("cmd_musician")) \
		.override_failure_message("a list naming none: both on the last model").is_false()


## KIT-BEARER-NAME, from a real list: the import puts each command upgrade on its own model's equipment. The export
## fixture carries the option `gains`; card_list_aof_beastmen_1000.json is trimmed (no `gains`) and carries no command upgrade.
func test_a_real_list_marks_one_model_per_upgrade() -> void:
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/ratmen_warriors_export.json"))
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline({"name": "t", "gameSystem": "aofs", "units": [fx["drill"]]})
	client.free()
	var ou: OPRApiClient.OPRUnit = army.units[0]
	var nodes: Array[Node3D] = []
	for _m in ou.size:
		nodes.append(auto_free(Node3D.new()))
	var gu := EquipmentDistributor.create_from_opr_unit(ou, nodes, 1)
	var holders := func(rule: String) -> Array:
		return range(gu.models.size()).filter(func(k: int) -> bool: return (gu.models[k].properties.get("equipment", []) as Array).has(rule))
	var banner: Array = holders.call("Banner")
	var musician: Array = holders.call("Musician")
	assert_int(banner.size()).override_failure_message("one model carries the Banner: %s" % [banner]).is_equal(1)
	assert_int(musician.size()).override_failure_message("one model carries the Musician: %s" % [musician]).is_equal(1)
	assert_bool(banner != musician).override_failure_message("two models, two bearers").is_true()
	assert_array([BattleSim._command_bearer(gu, "Banner"), BattleSim._command_bearer(gu, "Musician")]).is_equal([banner[0], musician[0]])

extends GdUnitTestSuite
## Ruling D16, CMD-ROUNDTRIP step CR1: the table's capture writes an AoF: Skirmish command group's bearer the way the Rust
## core counts it (core/nml-core/src/io.rs `cmd_bearer`): the LAST model of the unit carries it, so the key is its slot
## among the living models while it lives and -1 once it is killed. Every other unit writes no key, so its records keep
## their shape.

const IN2M := 0.0254


func _model(u: GameUnit, x_in: float, alive: bool) -> ModelInstance:
	var m := ModelInstance.new()
	m.is_alive = alive
	m.wounds_max = 1
	m.wounds_current = 1
	m.unit = u
	m.properties = {"weapons": [], "equipment": []}
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	return m


## Unit "A" of `system` with `rules` and three models whose life is `alive`; the plain unit the core is handed.
func _plain(system: String, rules: Array, alive: Array) -> Dictionary:
	var a := GameUnit.new()
	a.unit_id = "A"
	a.unit_properties = {"player_id": 1, "name": "A", "quality": 4, "defense": 4, "special_rules": rules, "game_system": system}
	for i in alive.size():
		a.models.append(_model(a, float(i), alive[i]))
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

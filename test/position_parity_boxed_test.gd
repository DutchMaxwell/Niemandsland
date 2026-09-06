extends GdUnitTestSuite
## Replay the same fixed move inputs and expected outputs as the Rust pins.
const Parity := preload("res://tools/position_parity.gd")
const Replay := preload("res://tools/node_recheck.gd")

func test_boxed_escape_pins_match_the_table() -> void:
	var pins: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/position_parity/boxed_escape.json"))
	var corpus: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/position_parity/cases.json"))
	for pin in pins["cases"]:
		var fixture: Dictionary = {}
		for candidate in corpus["cases"]:
			if candidate["id"] == pin["id"]: fixture = candidate
		assert_bool(fixture.is_empty()).is_false()
		var got := _table_move(fixture)
		assert_int(got["end"].size()).is_equal(pin["expected_world"].size())
		for i in got["end"].size():
			var p: Array = pin["expected_world"][i]
			assert_float((got["end"][i] as Vector3).distance_to(Vector3(p[0],p[1],p[2])) / 0.0254
				).is_less_equal(float(pins["tolerance_in"]))
		assert_float(absf(float(got["budget_in"])-float(pin["budget_in"]))
			).is_less_equal(float(pins["tolerance_in"]))

func _table_move(fixture: Dictionary) -> Dictionary:
	var previous := [MovementPlanner.fast_planner, MovementPlanner.fast_planner_guard,
		SoloController._move_seam_env, SoloController._move_check_env]
	var board: Node3D = auto_free(Node3D.new())
	add_child(board)
	var army := Parity.FixtureArmy.new()
	board.add_child(army)
	var solo := Parity.TableProbe.new()
	board.add_child(solo)
	solo.setup(army,null,null)
	solo.board_in = Vector2(fixture["board_in"][0],fixture["board_in"][1])
	solo.prewarm_enabled = false
	army.current_round = int(fixture["round"])
	MovementPlanner.fast_planner = bool(fixture["fast_planner"])
	MovementPlanner.fast_planner_guard = int(fixture["fast_planner_guard"])
	SoloController._move_seam_env = 0
	SoloController._move_check_env = 0
	var units: Dictionary = {}
	for spec in fixture["units"]:
		var unit := GameUnit.new()
		unit.unit_id = str(spec["id"])
		unit.unit_properties = {"name":unit.unit_id,"player_id":int(spec["player"]),
			"special_rules":spec["rules"],"game_system":str(spec["game_system"]),
			"quality":4,"defense":4,"base_is_oval":spec["base_shape"] == "oval",
			"base_width_mm":int(spec["base_w_mm"]),"base_depth_mm":int(spec["base_d_mm"]),
			"base_size_round":int(spec["base_w_mm"]),"ambush_reserve":bool(spec["dormant"])}
		for i in spec["positions"].size():
			var model := ModelInstance.new()
			model.unit = unit
			model.is_alive = true
			model.wounds_current = maxi(1,int(spec["wounds"][i]))
			model.wounds_max = maxi(model.wounds_current,int(spec["tough"]))
			model.properties = {"tough":int(spec["tough"])}
			model.node = Node3D.new()
			board.add_child(model.node)
			model.node.global_position = Replay._vec3(spec["positions"][i])
			unit.models.append(model)
		units[unit.unit_id] = unit
		army.game_units[unit.unit_id] = unit
	for spec in fixture["units"]:
		var unit: GameUnit = units[spec["id"]]
		var heroes: Array = []
		for key in spec["attached"]: heroes.append(units[key])
		unit.unit_properties["attached_heroes"] = heroes
		if not str(spec["attached_to"]).is_empty():
			unit.unit_properties["attached_to"] = units[spec["attached_to"]]
	solo.terrain_type_at = Replay.terrain_at_from_plain(fixture["terrain"])
	var walls: Array = []
	for wall in fixture["terrain"]["walls"]:
		walls.append([Vector2(wall[0][0],wall[0][1]),Vector2(wall[1][0],wall[1][1])])
	solo.walls_provider = func() -> Array: return walls
	var action: Dictionary = fixture["action"]
	var actor: GameUnit = units[action["unit"]]
	solo._move_toward(actor,Replay._vec3(action["dest"]),float(action["band_in"]),false)
	var result := {"end":solo._positions_of(solo._moving_models(actor)),"budget_in":solo.last_move_budget_in}

	for unit in units.values():
		unit.unit_properties["attached_heroes"] = []
		unit.unit_properties["attached_to"] = null
		for model in unit.models:
			model.unit = null
			model.node = null
		unit.models.clear()
	army.game_units.clear()
	MovementPlanner.fast_planner = bool(previous[0])
	MovementPlanner.fast_planner_guard = int(previous[1])
	SoloController._move_seam_env = int(previous[2])
	SoloController._move_check_env = int(previous[3])
	return result

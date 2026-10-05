extends GdUnitTestSuite
## Applying the Borderland theme (5.2a-2) replaces the free pieces (D10), sets grassland and evening light, and ONE
## undo puts the old table back exactly; redo applies it again. Refused once the game has started. Local here: the
## multiplayer sync and the map editor entry follow (5.2c, 5.2b).

var _biome := "desert_dunes"
var _mood := "Day"
var _started := false
var _relayouts := 0


func _hooks() -> Dictionary:
	return {"started": func() -> bool: return _started,
		"biome_get": func() -> String: return _biome, "biome_set": func(b: String) -> void: _biome = b,
		"mood_get": func() -> String: return _mood, "mood_set": func(m: String) -> void: _mood = m,
		"relayout": func() -> void: _relayouts += 1}


func _om() -> ObjectManager:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	om.solid_models_library().apply_manifest_text("{}")   # no model downloads in tests
	return om


func _live(om: ObjectManager) -> Array:
	return ObjectManager.sandbox_pieces(om.get_tree()).filter(func(n: Node) -> bool:
		return not bool(n.get_meta("deleted", false)))


func test_apply_replaces_the_table_and_one_undo_restores_it() -> void:
	var om := _om()
	var old: Node3D = om.spawn_sandbox_terrain("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector3(0.1, 0, 0.1),
		false, 7501)
	var theme := TableTheme.load_theme("ruined_borderland")
	var action := theme.apply(om, _hooks())
	assert_object(action).is_not_null()
	if action == null:
		return
	assert_int(_live(om).size()).is_equal(14)
	assert_bool(_live(om).has(old)).is_false()
	assert_str(_biome).is_equal("temperate_grassland")
	assert_str(_mood).is_equal("Sunset")
	assert_int(_relayouts).is_equal(1)   # the biome dressing is re-laid for the new pieces
	var first: Node3D = action.spawned[0]
	assert_vector(first.global_position).is_equal_approx(theme.pieces[0]["position"], Vector3.ONE * 0.0001)
	assert_float(first.rotation_degrees.y).is_equal_approx(float(theme.pieces[0]["yaw_deg"]), 0.01)
	action.undo()
	assert_array(_live(om)).contains_exactly([old])
	assert_str(_biome).is_equal("desert_dunes")
	assert_str(_mood).is_equal("Day")
	assert_int(_relayouts).is_equal(2)
	action.redo()
	assert_int(_live(om).size()).is_equal(14)


func test_apply_is_refused_once_the_game_started() -> void:
	var om := _om()
	_started = true
	assert_object(TableTheme.load_theme("ruined_borderland").apply(om, _hooks())).is_null()
	assert_int(_live(om).size()).is_equal(0)

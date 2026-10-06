extends GdUnitTestSuite
## Applying the Borderland theme (5.2a-2) replaces the free pieces (D10), keeps the table's biome (S8.1), sets the
## evening light, and ONE
## undo puts the old table back exactly; redo applies it again. Refused once the game has started. Local here: the
## multiplayer sync and the map editor entry follow (5.2c, 5.2b).

var _biome := "desert_dunes"
var _mood := "Day"
var _started := false
var _relayouts := 0
var _paths: Array = [[[1.0, 1.0], [2.0, 2.0]]]   # the table's paths before


func _hooks() -> Dictionary:
	return {"started": func() -> bool: return _started,
		"biome_get": func() -> String: return _biome, "biome_set": func(b: String) -> void: _biome = b,
		"mood_get": func() -> String: return _mood, "mood_set": func(m: String) -> void: _mood = m,
		"relayout": func() -> void: _relayouts += 1,
		"paths_get": func() -> Array: return _paths, "paths_set": func(p: Array) -> void: _paths = p}


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
	assert_str(_biome).is_equal("desert_dunes")   # S8.1: the theme keeps the table's biome
	assert_str(_mood).is_equal("Sunset")
	assert_int(_relayouts).is_equal(1)   # the biome dressing is re-laid for the new pieces
	assert_int(_paths.size()).is_equal(3)   # the theme's worn paths
	var first: Node3D = action.spawned[0]
	assert_vector(first.global_position).is_equal_approx(theme.pieces[0]["position"], Vector3.ONE * 0.0001)
	assert_float(first.rotation_degrees.y).is_equal_approx(float(theme.pieces[0]["yaw_deg"]), 0.01)
	action.undo()
	assert_array(_live(om)).contains_exactly([old])
	assert_str(_biome).is_equal("desert_dunes")
	assert_str(_mood).is_equal("Day")
	assert_int(_relayouts).is_equal(2)
	assert_array(_paths).is_equal([[[1.0, 1.0], [2.0, 2.0]]])   # the old paths back
	action.redo()
	assert_int(_live(om).size()).is_equal(14)


func test_apply_is_refused_once_the_game_started() -> void:
	var om := _om()
	_started = true
	assert_object(TableTheme.load_theme("ruined_borderland").apply(om, _hooks())).is_null()
	assert_int(_live(om).size()).is_equal(0)


## S8.1 (maintainer 06.10.: the terrain should match the biome): the theme follows the table's biome — on a desert
## table it lays the desert woods and ruins (the biome's R2 trees and wall panels), keeps the solids and the biome.
func test_on_a_desert_table_the_theme_lays_desert_woods_and_ruins() -> void:
	_biome = "arid_desert"
	_started = false   # the suite keeps its fields between cases
	var om := _om()
	var action := TableTheme.load_theme("ruined_borderland").apply(om, _hooks())
	assert_str(_biome).is_equal("arid_desert")
	var ids: Array = action.spawned.map(func(n: Node) -> String: return str(n.get_meta("prop_id", "")))
	assert_int(ids.filter(func(i: String) -> bool: return i.begins_with("desert_")).size()).override_failure_message(
		"ids: %s" % [ids]).is_equal(10)   # 6 ruins + 4 woods
	assert_int(ids.filter(func(i: String) -> bool: return i in ["longhouse_6x3", "outcrop_6x3"]).size()).is_equal(4)

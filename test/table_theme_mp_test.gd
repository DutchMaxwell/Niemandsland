extends GdUnitTestSuite
## A theme applied in a multiplayer game reaches the other table (5.2c): every theme piece is spawned there with its
## id and turned to its angle, the replaced pieces are hidden there, and the biome follows; undo and redo send the
## reverse. The mood stays local (lead D13).


class StubNet extends Node:
	var calls: Array = []

	func is_multiplayer_active() -> bool:
		return true

	func broadcast_sandbox_terrain_spawn(prop_id: String, _kind: int, _pos: Vector3, object_id: int) -> void:
		calls.append(["spawn", prop_id, object_id])

	func broadcast_rotation(object_id: int, rot_y: float) -> void:
		calls.append(["rot", object_id, rot_y])

	func broadcast_object_visibility(object_id: int, is_visible: bool) -> void:
		calls.append(["vis", object_id, is_visible])

	func broadcast_table_settings(settings: Dictionary) -> void:
		calls.append(["settings", settings])


var _biome := "desert_dunes"
var _mood := "Day"


func _of(net: StubNet, kind: String) -> Array:
	return net.calls.filter(func(c: Array) -> bool: return c[0] == kind)


func test_a_theme_and_its_undo_reach_the_other_table() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	om.solid_models_library().apply_manifest_text("{}")   # no model downloads in tests
	var net: StubNet = auto_free(StubNet.new())
	om._network_manager = net
	var old: Node3D = om.spawn_sandbox_terrain("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector3(0.1, 0, 0.1),
		false, 7601)
	var hooks := {"started": func() -> bool: return false, "net": net,
		"biome_get": func() -> String: return _biome, "biome_set": func(b: String) -> void: _biome = b,
		"mood_get": func() -> String: return _mood, "mood_set": func(m: String) -> void: _mood = m,
		"paths_get": func() -> Array: return [], "paths_set": func(_p: Array) -> void: pass}
	var action := TableTheme.load_theme("ruined_borderland").apply(om, hooks)
	assert_object(action).is_not_null()
	if action == null:
		return
	assert_int(_of(net, "spawn").size()).is_equal(14)
	var rots := _of(net, "rot")
	assert_int(rots.size()).is_equal(14)
	if rots.size() == 14:
		var first: Node3D = action.spawned[0]
		assert_int(int(rots[0][1])).is_equal(int(first.get_meta("network_id")))
		assert_float(float(rots[0][2])).is_equal_approx(first.rotation.y, 0.0001)
	assert_array(_of(net, "vis")).contains([["vis", 7601, false]])
	var sent: Array = _of(net, "settings")
	assert_bool(sent.any(func(c: Array) -> bool: return c[1].get("biome") == "temperate_grassland" \
		and (c[1].get("paths", []) as Array).size() == 3)).is_true()   # biome and paths reach the other table
	net.calls.clear()
	action.undo()
	assert_array(_of(net, "vis")).contains([["vis", 7601, true]])
	assert_int(_of(net, "vis").filter(func(c: Array) -> bool: return not bool(c[2])).size()).is_equal(14)
	assert_bool(_of(net, "settings").any(func(c: Array) -> bool: return c[1].get("biome") == "desert_dunes" \
		and (c[1].get("paths", [0]) as Array).is_empty())).is_true()
